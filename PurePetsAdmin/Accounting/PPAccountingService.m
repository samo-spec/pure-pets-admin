#import "PPAccountingService.h"
#import "PPStaffAuth.h"
@import FirebaseFirestore;
@import FirebaseAuth;

static NSString * const PPAccountingOrderScopeErrorDomain = @"PPAccountingOrderScope";
static NSString * const PPAccountingPartialReadMarkerKey = @"PPAccountingPartialRead";
static NSUInteger const PPAccountingScopeChunkLimit = 30;

@interface PPAccountingScopedOrderRegistration : NSObject <FIRListenerRegistration>
@property (atomic, assign, getter=isActive) BOOL active;
@property (nonatomic, strong) NSMutableArray<id<FIRListenerRegistration>> *registrations;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<FIRDocumentSnapshot *> *> *documentsByQuery;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *settledQueries;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSError *> *errorsByQuery;
@property (nonatomic, assign) NSUInteger queryCount;
- (void)addRegistration:(id<FIRListenerRegistration>)registration;
@end

@implementation PPAccountingScopedOrderRegistration
- (instancetype)init {
    if ((self = [super init])) {
        _active = YES;
        _registrations = [NSMutableArray array];
        _documentsByQuery = [NSMutableDictionary dictionary];
        _settledQueries = [NSMutableSet set];
        _errorsByQuery = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)addRegistration:(id<FIRListenerRegistration>)registration {
    if (!registration) return;
    BOOL shouldRemove = NO;
    @synchronized (self) {
        if (self.isActive) [self.registrations addObject:registration];
        else shouldRemove = YES;
    }
    if (shouldRemove) [registration remove];
}
- (void)remove {
    NSArray<id<FIRListenerRegistration>> *registrations = nil;
    @synchronized (self) {
        if (!self.isActive) return;
        self.active = NO;
        registrations = self.registrations.copy;
        [self.registrations removeAllObjects];
        [self.documentsByQuery removeAllObjects];
        [self.settledQueries removeAllObjects];
        [self.errorsByQuery removeAllObjects];
    }
    for (id<FIRListenerRegistration> registration in registrations) [registration remove];
}
@end

static NSError *PPAccountingOrderScopeError(NSInteger code, NSString *localizationKey) {
    return [NSError errorWithDomain:PPAccountingOrderScopeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: kLang(localizationKey)}];
}

static NSError *PPAccountingPartialReadError(NSError *underlyingError,
                                             NSUInteger successfulQueryCount,
                                             NSUInteger queryCount) {
    NSMutableDictionary *userInfo = [@{
        NSLocalizedDescriptionKey: kLang(@"PPOrder_Error_PartialRead"),
        PPAccountingPartialReadMarkerKey: @YES,
        @"successfulQueryCount": @(successfulQueryCount),
        @"queryCount": @(queryCount),
    } mutableCopy];
    if (underlyingError) userInfo[NSUnderlyingErrorKey] = underlyingError;
    return [NSError errorWithDomain:PPAccountingOrderScopeErrorDomain code:413 userInfo:userInfo];
}

static NSArray<NSString *> *PPAccountingCanonicalScopeIDs(PPStaffDoc *staff, NSString *key) {
    id value = [staff.scope isKindOfClass:NSDictionary.class] ? staff.scope[key] : nil;
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableOrderedSet<NSString *> *ids = [NSMutableOrderedSet orderedSet];
    for (id entry in (NSArray *)value) {
        if (![entry isKindOfClass:NSString.class]) continue;
        NSString *trimmed = [(NSString *)entry stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length) [ids addObject:trimmed];
    }
    return [ids.array sortedArrayUsingSelector:@selector(compare:)];
}

static BOOL PPAccountingStaffSessionIsCurrent(PPStaffDoc *staff) {
    PPStaffDoc *current = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *authUID = [FIRAuth auth].currentUser.uid;
    return (staff != nil && current == staff && authUID.length > 0 &&
            [staff.uid isEqualToString:authUID] && staff.isActive);
}

static BOOL PPAccountingStaffHasReadableOrderScope(PPStaffDoc *staff) {
    return (staff.isActive && (staff.isAdmin || staff.hasGlobalScope ||
            PPAccountingCanonicalScopeIDs(staff, @"branchIds").count > 0 ||
            PPAccountingCanonicalScopeIDs(staff, @"regionIds").count > 0));
}

static BOOL PPAccountingStaffCanReachOrder(PPStaffDoc *staff, NSDictionary *data) {
    if (!PPAccountingStaffSessionIsCurrent(staff) || ![data isKindOfClass:NSDictionary.class]) return NO;
    if (staff.isAdmin || staff.hasGlobalScope) return YES;
    NSString *branchID = [data[@"branchId"] isKindOfClass:NSString.class]
        ? [(NSString *)data[@"branchId"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    NSString *regionID = [data[@"regionId"] isKindOfClass:NSString.class]
        ? [(NSString *)data[@"regionId"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    return ((branchID.length > 0 && [PPAccountingCanonicalScopeIDs(staff, @"branchIds") containsObject:branchID]) ||
            (regionID.length > 0 && [PPAccountingCanonicalScopeIDs(staff, @"regionIds") containsObject:regionID]));
}

static NSArray<FIRQuery *> *PPAccountingScopedOrderQueries(FIRFirestore *db, PPStaffDoc *staff) {
    FIRCollectionReference *orders = [db collectionWithPath:@"Orders"];
    NSMutableArray<FIRQuery *> *queries = [NSMutableArray array];
    if (staff.isAdmin || staff.hasGlobalScope) {
        [queries addObject:orders];
    } else {
        NSDictionary<NSString *, NSArray<NSString *> *> *scope = @{
            @"branchId": PPAccountingCanonicalScopeIDs(staff, @"branchIds"),
            @"regionId": PPAccountingCanonicalScopeIDs(staff, @"regionIds"),
        };
        for (NSString *field in @[@"branchId", @"regionId"]) {
            NSArray<NSString *> *ids = scope[field];
            for (NSUInteger offset = 0; offset < ids.count; offset += PPAccountingScopeChunkLimit) {
                NSRange range = NSMakeRange(offset, MIN(PPAccountingScopeChunkLimit, ids.count - offset));
                [queries addObject:[orders queryWhereField:field in:[ids subarrayWithRange:range]]];
            }
        }
    }
    NSMutableArray<FIRQuery *> *ordered = [NSMutableArray arrayWithCapacity:queries.count];
    for (FIRQuery *baseQuery in queries) {
        FIRQuery *query = [baseQuery queryOrderedByField:@"updatedAt" descending:YES];
        query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
        [ordered addObject:query];
    }
    return ordered.copy;
}

static NSArray<FIRDocumentSnapshot *> *PPAccountingMergeOrderDocuments(NSArray<NSArray<FIRDocumentSnapshot *> *> *groups) {
    NSMutableDictionary<NSString *, FIRDocumentSnapshot *> *byID = [NSMutableDictionary dictionary];
    for (NSArray<FIRDocumentSnapshot *> *group in groups) {
        for (FIRDocumentSnapshot *document in group) {
            if (document.documentID.length) byID[document.documentID] = document;
        }
    }
    return [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(FIRDocumentSnapshot *left, FIRDocumentSnapshot *right) {
        NSDate *leftDate = [left.data[@"updatedAt"] isKindOfClass:FIRTimestamp.class] ? [left.data[@"updatedAt"] dateValue] : NSDate.distantPast;
        NSDate *rightDate = [right.data[@"updatedAt"] isKindOfClass:FIRTimestamp.class] ? [right.data[@"updatedAt"] dateValue] : NSDate.distantPast;
        NSComparisonResult dateResult = [rightDate compare:leftDate];
        return dateResult != NSOrderedSame ? dateResult : [right.documentID compare:left.documentID];
    }];
}

@implementation PPAccountingTransaction
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _txnID = docID ?: @"";
        _amount = PPSafeDouble(dict[@"total"]);
        if (_amount == 0) _amount = PPSafeDouble(dict[@"amount"]);
        _type = PPSafeString(dict[@"type"]);
        if (_type.length == 0) _type = PPSafeString(dict[@"status"]);
        _desc = PPSafeString(dict[@"description"]);
        if (_desc.length == 0) _desc = PPSafeString(dict[@"customerName"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
    }
    return self;
}
@end

@implementation PPAccountingExpense
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _expenseID = docID ?: @"";
        _amount = PPSafeDouble(dict[@"amount"]);
        _category = PPSafeString(dict[@"category"]);
        _desc = PPSafeString(dict[@"description"]);
        _createdBy = PPSafeString(dict[@"createdBy"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
    }
    return self;
}
@end

@interface PPAccountingService ()
@property (nonatomic, strong) NSMutableArray<PPAccountingTransaction *> *internalTransactions;
@property (nonatomic, strong) NSMutableArray<PPAccountingExpense *> *internalExpenses;
@property (nonatomic, assign) double internalOrderRevenue;
@property (nonatomic, assign) NSInteger internalOrderCount;
@property (nonatomic, assign) BOOL internalOrderRevenueEvidenceAvailable;
@property (nonatomic, strong, nullable) NSError *internalOrderRevenueError;
@end

@implementation PPAccountingService

+ (instancetype)shared {
    static PPAccountingService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _internalTransactions = [NSMutableArray array];
        _internalExpenses = [NSMutableArray array];
    }
    return self;
}

- (NSArray<PPAccountingTransaction *> *)transactions { return self.internalTransactions; }
- (NSArray<PPAccountingExpense *> *)expenses { return self.internalExpenses; }
- (double)orderRevenue { return self.internalOrderRevenue; }
- (NSInteger)orderCount { return self.internalOrderCount; }
- (BOOL)orderRevenueEvidenceAvailable { return self.internalOrderRevenueEvidenceAvailable; }
- (NSError *)orderRevenueError { return self.internalOrderRevenueError; }

- (BOOL)currentStaffCanReadOrderRevenue {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]] &&
           PPAccountingStaffHasReadableOrderScope(staff) &&
           PPAccountingStaffSessionIsCurrent(staff);
}

- (FIRTimestamp *)monthStartTimestamp {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comp = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:[NSDate date]];
    comp.day = 1; comp.hour = 0; comp.minute = 0; comp.second = 0;
    return [FIRTimestamp timestampWithDate:[cal dateFromComponents:comp]];
}

- (id<FIRListenerRegistration>)subscribeTransactionsWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"transactions"] queryOrderedByField:@"createdAt" descending:YES];
    if ([filter isEqualToString:@"month"]) {
        query = [[[db collectionWithPath:@"transactions"] queryWhereField:@"createdAt" isGreaterThanOrEqualTo:[self monthStartTimestamp]] queryOrderedByField:@"createdAt" descending:YES];
    }
    return [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) return;
        [self.internalTransactions removeAllObjects];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [self.internalTransactions addObject:[[PPAccountingTransaction alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (callback) callback();
    }];
}

- (id<FIRListenerRegistration>)subscribeExpensesWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"expenses"] queryOrderedByField:@"createdAt" descending:YES];
    if ([filter isEqualToString:@"month"]) {
        query = [[[db collectionWithPath:@"expenses"] queryWhereField:@"createdAt" isGreaterThanOrEqualTo:[self monthStartTimestamp]] queryOrderedByField:@"createdAt" descending:YES];
    }
    return [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) return;
        [self.internalExpenses removeAllObjects];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [self.internalExpenses addObject:[[PPAccountingExpense alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (callback) callback();
    }];
}

- (id<FIRListenerRegistration>)subscribeOrderRevenueWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    FIRFirestore *db = [FIRFirestore firestore];
    PPAccountingScopedOrderRegistration *composite = [PPAccountingScopedOrderRegistration new];
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    BOOL hasPermission = [staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]];
    if (!hasPermission || !PPAccountingStaffHasReadableOrderScope(staff)) {
        NSError *accessError = PPAccountingOrderScopeError(hasPermission ? 411 : 410,
                                                           hasPermission ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission");
        dispatch_async(dispatch_get_main_queue(), ^{
            self.internalOrderRevenue = 0.0;
            self.internalOrderCount = 0;
            self.internalOrderRevenueEvidenceAvailable = NO;
            self.internalOrderRevenueError = accessError;
            if (callback) callback();
        });
        return composite;
    }

    NSArray<FIRQuery *> *queries = PPAccountingScopedOrderQueries(db, staff);
    composite.queryCount = queries.count;
    BOOL monthOnly = [filter isEqualToString:@"month"];
    NSDate *monthStart = self.monthStartTimestamp.dateValue;
    __weak typeof(self) weakSelf = self;
    [queries enumerateObjectsUsingBlock:^(FIRQuery *query, NSUInteger index, BOOL *stop) {
        id<FIRListenerRegistration> registration = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !composite.isActive) return;
            if (!PPAccountingStaffSessionIsCurrent(staff)) {
                [composite remove];
                NSError *sessionError = PPAccountingOrderScopeError(412, @"PPOrder_Error_SessionChanged");
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.internalOrderRevenue = 0.0;
                    self.internalOrderCount = 0;
                    self.internalOrderRevenueEvidenceAvailable = NO;
                    self.internalOrderRevenueError = sessionError;
                    if (callback) callback();
                });
                return;
            }

            NSArray<NSArray<FIRDocumentSnapshot *> *> *groups = nil;
            NSError *firstError = nil;
            NSUInteger successfulQueryCount = 0;
            BOOL allReady = NO;
            @synchronized (composite) {
                [composite.settledQueries addObject:@(index)];
                if (error) composite.errorsByQuery[@(index)] = error;
                else {
                    composite.documentsByQuery[@(index)] = snapshot.documents ?: @[];
                    [composite.errorsByQuery removeObjectForKey:@(index)];
                }
                allReady = composite.settledQueries.count == composite.queryCount;
                groups = composite.documentsByQuery.allValues.copy;
                firstError = composite.errorsByQuery.allValues.firstObject;
                successfulQueryCount = composite.documentsByQuery.count;
            }
            if (!allReady || !composite.isActive) return;
            NSError *evidenceError = nil;
            if (firstError) {
                evidenceError = successfulQueryCount > 0
                    ? PPAccountingPartialReadError(firstError, successfulQueryCount, composite.queryCount)
                    : firstError;
            }

            double revenue = 0.0;
            NSInteger orderCount = 0;
            for (FIRDocumentSnapshot *document in PPAccountingMergeOrderDocuments(groups)) {
                NSDictionary *data = document.data ?: @{};
                if (!PPAccountingStaffCanReachOrder(staff, data)) continue;
                NSString *paymentStatus = [PPSafeString(data[@"paymentStatus"]) lowercaseString];
                if (![paymentStatus isEqualToString:@"paid"]) continue;
                NSDate *createdAt = [data[@"createdAt"] isKindOfClass:FIRTimestamp.class]
                    ? [(FIRTimestamp *)data[@"createdAt"] dateValue]
                    : nil;
                if (monthOnly && (!createdAt || [createdAt compare:monthStart] == NSOrderedAscending)) continue;
                revenue += PPSafeDouble(data[@"totalAmount"]);
                orderCount += 1;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!composite.isActive || !PPAccountingStaffSessionIsCurrent(staff)) return;
                self.internalOrderRevenue = revenue;
                self.internalOrderCount = orderCount;
                self.internalOrderRevenueEvidenceAvailable = evidenceError == nil;
                self.internalOrderRevenueError = evidenceError;
                if (callback) callback();
            });
        }];
        [composite addRegistration:registration];
    }];
    return composite;
}

- (void)addExpense:(double)amount category:(NSString *)category description:(NSString *)desc completion:(void(^)(NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"unknown";
    [[db collectionWithPath:@"expenses"] addDocumentWithData:@{
        @"amount": @(amount),
        @"category": category ?: @"other",
        @"description": desc ?: @"",
        @"createdBy": uid,
        @"date": [FIRTimestamp timestampWithDate:[NSDate date]],
        @"status": @"active",
        @"createdAt": [FIRTimestamp timestampWithDate:[NSDate date]]
    } completion:^(NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)deleteExpense:(NSString *)expenseID completion:(void(^)(NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[[db collectionWithPath:@"expenses"] documentWithPath:expenseID] deleteDocumentWithCompletion:^(NSError *error) {
        if (completion) completion(error);
    }];
}

@end
