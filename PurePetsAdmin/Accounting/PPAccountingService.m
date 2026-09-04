#import "PPAccountingService.h"
#import "PPStaffAuth.h"
#import "PPBranchContextManager.h"
@import FirebaseFirestore;
@import FirebaseAuth;
@import FirebaseFunctions;

static NSString *PPAccountingNormalizePeriod(NSString *filter) {
    NSString *f = [filter lowercaseString];
    if ([f isEqualToString:@"today"]) return @"today";
    if ([f isEqualToString:@"week"] || [f isEqualToString:@"this_week"]) return @"this_week";
    if ([f isEqualToString:@"month"] || [f isEqualToString:@"this_month"]) return @"this_month";
    if ([f isEqualToString:@"quarter"] || [f isEqualToString:@"this_quarter"]) return @"this_quarter";
    if ([f isEqualToString:@"year"] || [f isEqualToString:@"this_year"]) return @"this_year";
    if ([f isEqualToString:@"last_month"]) return @"last_month";
    if ([f isEqualToString:@"last_year"]) return @"last_year";
    if ([f isEqualToString:@"all"] || [f isEqualToString:@"all_time"]) return @"all_time";
    return @"this_month";
}

static NSString * const PPAccountingOrderScopeErrorDomain = @"PPAccountingOrderScope";
static NSString * const PPAccountingPartialReadMarkerKey = @"PPAccountingPartialRead";

static NSString *PPAccountingSelectedBranchID(void) {
    NSString *branchID = [PPBranchContextManager sharedManager].currentBranchID ?: @"";
    return [branchID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *PPAccountingWorkspaceCacheKey(NSString *period, NSString *branchID) {
    return [NSString stringWithFormat:@"%@|%@", period ?: @"this_month", branchID ?: @""];
}

static NSError *PPAccountingBranchRequiredError(void) {
    return [NSError errorWithDomain:PPAccountingOrderScopeErrorDomain
                               code:414
                           userInfo:@{NSLocalizedDescriptionKey: kLang(@"BranchContext_SelectBranch_Prompt")}];
}

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

static BOOL PPAccountingStaffSessionIsCurrent(PPStaffDoc *staff) {
    PPStaffDoc *current = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *authUID = [FIRAuth auth].currentUser.uid;
    return (staff != nil && current == staff && authUID.length > 0 &&
            [staff.uid isEqualToString:authUID] && staff.isActive);
}

static BOOL PPAccountingStaffHasReadableOrderScope(PPStaffDoc *staff) {
    NSString *branchID = PPAccountingSelectedBranchID();
    return staff.isActive && branchID.length > 0 && [staff hasAccessToBranch:branchID];
}

static BOOL PPAccountingStaffCanReachOrder(PPStaffDoc *staff, NSDictionary *data) {
    if (!PPAccountingStaffSessionIsCurrent(staff) || ![data isKindOfClass:NSDictionary.class]) return NO;
    NSString *selectedBranchID = PPAccountingSelectedBranchID();
    NSString *branchID = [data[@"branchId"] isKindOfClass:NSString.class]
        ? [(NSString *)data[@"branchId"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    return selectedBranchID.length > 0 && [branchID isEqualToString:selectedBranchID] &&
           [staff hasAccessToBranch:selectedBranchID];
}

static NSArray<FIRQuery *> *PPAccountingScopedOrderQueries(FIRFirestore *db, PPStaffDoc *staff) {
    NSString *branchID = PPAccountingSelectedBranchID();
    if (branchID.length == 0 || ![staff hasAccessToBranch:branchID]) return @[];
    FIRQuery *query = [[[db collectionWithPath:@"Orders"] queryWhereField:@"branchId" isEqualTo:branchID]
                       queryOrderedByField:@"updatedAt" descending:YES];
    query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
    return @[query];
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

@implementation PPAccountingWorkspaceDashboard
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self && [dict isKindOfClass:NSDictionary.class]) {
        _currency = PPSafeString(dict[@"currency"]) ?: @"QAR";
        _income = PPSafeDouble(dict[@"income"]);
        _incomeMinor = [dict[@"incomeMinor"] respondsToSelector:@selector(longLongValue)] ? [dict[@"incomeMinor"] longLongValue] : 0;
        _expenses = PPSafeDouble(dict[@"expenses"]);
        _expensesMinor = [dict[@"expensesMinor"] respondsToSelector:@selector(longLongValue)] ? [dict[@"expensesMinor"] longLongValue] : 0;
        _netProfit = PPSafeDouble(dict[@"netProfit"]);
        _netProfitMinor = [dict[@"netProfitMinor"] respondsToSelector:@selector(longLongValue)] ? [dict[@"netProfitMinor"] longLongValue] : 0;
        _cashIn = PPSafeDouble(dict[@"cashIn"]);
        _cashInMinor = [dict[@"cashInMinor"] respondsToSelector:@selector(longLongValue)] ? [dict[@"cashInMinor"] longLongValue] : 0;
        _cashOut = PPSafeDouble(dict[@"cashOut"]);
        _cashOutMinor = [dict[@"cashOutMinor"] respondsToSelector:@selector(longLongValue)] ? [dict[@"cashOutMinor"] longLongValue] : 0;
        _currentCashBalance = PPSafeDouble(dict[@"currentCashBalance"]);
        _currentCashBalanceMinor = [dict[@"currentCashBalanceMinor"] respondsToSelector:@selector(longLongValue)] ? [dict[@"currentCashBalanceMinor"] longLongValue] : 0;
        _categoryIncomeMinor = [dict[@"categoryIncomeMinor"] isKindOfClass:NSDictionary.class] ? dict[@"categoryIncomeMinor"] : @{};
        _categoryExpenseMinor = [dict[@"categoryExpenseMinor"] isKindOfClass:NSDictionary.class] ? dict[@"categoryExpenseMinor"] : @{};
    }
    return self;
}
@end

@implementation PPAccountingDocument
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self && [dict isKindOfClass:NSDictionary.class]) {
        _documentID = PPSafeString(dict[@"id"]);
        _documentNumber = PPSafeString(dict[@"documentNumber"]) ?: _documentID;
        _kind = PPSafeString(dict[@"kind"]) ?: @"income";
        _status = PPSafeString(dict[@"status"]) ?: @"paid";
        _accountingDateKey = PPSafeString(dict[@"accountingDateKey"]);
        _currency = PPSafeString(dict[@"currency"]) ?: @"QAR";
        _total = PPSafeDouble(dict[@"total"]);
        _totalMinor = [dict[@"totalMinor"] respondsToSelector:@selector(longLongValue)] ? [dict[@"totalMinor"] longLongValue] : 0;
        _categoryId = [dict[@"categoryId"] isKindOfClass:NSString.class] ? dict[@"categoryId"] : nil;
        _categoryName = [dict[@"categoryName"] isKindOfClass:NSString.class] ? dict[@"categoryName"] : nil;
        _descriptionText = [dict[@"description"] isKindOfClass:NSString.class] ? dict[@"description"] : nil;
        _sourceType = [dict[@"sourceType"] isKindOfClass:NSString.class] ? dict[@"sourceType"] : nil;
        _sourceDocumentId = [dict[@"sourceDocumentId"] isKindOfClass:NSString.class] ? dict[@"sourceDocumentId"] : nil;
        _isLegacy = [dict[@"legacy"] boolValue];
        _canonicalLinked = [dict[@"canonicalLinked"] boolValue];
    }
    return self;
}
@end

@implementation PPAccountingWorkspaceSnapshot
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self && [dict isKindOfClass:NSDictionary.class]) {
        NSDictionary *range = [dict[@"range"] isKindOfClass:NSDictionary.class] ? dict[@"range"] : @{};
        _period = PPSafeString(range[@"period"]);
        _fromDateKey = PPSafeString(range[@"fromDateKey"]);
        _toDateKey = PPSafeString(range[@"toDateKey"]);

        NSString *baseCurrency = [dict[@"settings"] isKindOfClass:NSDictionary.class]
            ? PPSafeString(dict[@"settings"][@"baseCurrency"])
            : @"QAR";

        NSArray *dashboards = [dict[@"dashboard"] isKindOfClass:NSArray.class] ? dict[@"dashboard"] : @[];
        NSDictionary *primaryDict = nil;
        for (NSDictionary *entry in dashboards) {
            if ([entry isKindOfClass:NSDictionary.class] && [baseCurrency isEqualToString:PPSafeString(entry[@"currency"])]) {
                primaryDict = entry;
                break;
            }
        }
        if (!primaryDict && dashboards.firstObject && [dashboards.firstObject isKindOfClass:NSDictionary.class]) {
            primaryDict = dashboards.firstObject;
        }
        if (primaryDict) {
            _primaryDashboard = [[PPAccountingWorkspaceDashboard alloc] initWithDictionary:primaryDict];
        }

        NSMutableArray<PPAccountingDocument *> *docs = [NSMutableArray array];
        NSInteger inCount = 0;
        NSInteger exCount = 0;
        NSArray *rawDocs = [dict[@"documents"] isKindOfClass:NSArray.class] ? dict[@"documents"] : @[];
        for (NSDictionary *rawDoc in rawDocs) {
            if (![rawDoc isKindOfClass:NSDictionary.class]) continue;
            PPAccountingDocument *doc = [[PPAccountingDocument alloc] initWithDictionary:rawDoc];
            [docs addObject:doc];
            if ([doc.kind isEqualToString:@"income"]) {
                inCount++;
            } else if ([doc.kind isEqualToString:@"expense"]) {
                exCount++;
            }
        }
        _documents = docs.copy;
        _incomeCount = inCount;
        _expenseCount = exCount;
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
@property (nonatomic, strong) NSMutableDictionary<NSString *, PPAccountingWorkspaceSnapshot *> *workspacesByFilter;
@property (nonatomic, copy, nullable) NSString *currentFilterKey;
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
        _workspacesByFilter = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray<PPAccountingTransaction *> *)transactions { return self.internalTransactions; }
- (NSArray<PPAccountingExpense *> *)expenses { return self.internalExpenses; }
- (double)orderRevenue { return self.internalOrderRevenue; }
- (NSInteger)orderCount { return self.internalOrderCount; }
- (BOOL)orderRevenueEvidenceAvailable { return self.internalOrderRevenueEvidenceAvailable; }
- (NSError *)orderRevenueError { return self.internalOrderRevenueError; }
- (double)liveTotalExpenses {
    double total = 0.0;
    @synchronized (self.internalExpenses) {
        for (PPAccountingExpense *exp in self.internalExpenses) {
            total += exp.amount;
        }
    }
    return total;
}

- (NSInteger)liveExpenseCount {
    @synchronized (self.internalExpenses) {
        return self.internalExpenses.count;
    }
}

- (double)liveTransactionRevenue {
    double total = 0.0;
    @synchronized (self.internalTransactions) {
        for (PPAccountingTransaction *txn in self.internalTransactions) {
            NSString *type = [txn.type lowercaseString];
            if ([type isEqualToString:@"refund"] || [type isEqualToString:@"refunded"] ||
                [type isEqualToString:@"cancel"] || [type isEqualToString:@"cancelled"]) {
                total -= txn.amount;
            } else if ([type isEqualToString:@"expense"]) {
                // skip
            } else {
                total += txn.amount;
            }
        }
    }
    return total;
}

- (NSInteger)liveTransactionCount {
    NSInteger count = 0;
    @synchronized (self.internalTransactions) {
        for (PPAccountingTransaction *txn in self.internalTransactions) {
            NSString *type = [txn.type lowercaseString];
            if (![type isEqualToString:@"expense"] && ![type isEqualToString:@"cancel"] && ![type isEqualToString:@"cancelled"]) {
                count++;
            }
        }
    }
    return count;
}

- (PPAccountingWorkspaceSnapshot *)currentWorkspace {
    NSString *period = self.currentFilterKey ?: @"this_month";
    NSString *key = PPAccountingWorkspaceCacheKey(period, PPAccountingSelectedBranchID());
    return self.workspacesByFilter[key];
}

- (PPAccountingWorkspaceSnapshot *)workspaceForFilter:(NSString *)filter {
    NSString *period = PPAccountingNormalizePeriod(filter);
    return self.workspacesByFilter[PPAccountingWorkspaceCacheKey(period, PPAccountingSelectedBranchID())];
}

- (BOOL)currentStaffCanReadOrderRevenue {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]] &&
           PPAccountingStaffHasReadableOrderScope(staff) &&
           PPAccountingStaffSessionIsCurrent(staff);
}

- (FIRTimestamp *)timestampForFilter:(NSString *)filter {
    if (!filter.length || [filter isEqualToString:@"all"]) return nil;
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    if ([filter isEqualToString:@"today"]) {
        NSDateComponents *comp = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:now];
        comp.hour = 0; comp.minute = 0; comp.second = 0;
        return [FIRTimestamp timestampWithDate:[cal dateFromComponents:comp]];
    } else if ([filter isEqualToString:@"week"]) {
        NSDateComponents *comp = [cal components:NSCalendarUnitYearForWeekOfYear|NSCalendarUnitWeekOfYear fromDate:now];
        return [FIRTimestamp timestampWithDate:[cal dateFromComponents:comp]];
    } else if ([filter isEqualToString:@"quarter"]) {
        NSDateComponents *comp = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:now];
        NSInteger quarterMonth = ((comp.month - 1) / 3) * 3 + 1;
        comp.month = quarterMonth; comp.day = 1; comp.hour = 0; comp.minute = 0; comp.second = 0;
        return [FIRTimestamp timestampWithDate:[cal dateFromComponents:comp]];
    }
    // Default to month
    NSDateComponents *comp = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:now];
    comp.day = 1; comp.hour = 0; comp.minute = 0; comp.second = 0;
    return [FIRTimestamp timestampWithDate:[cal dateFromComponents:comp]];
}

- (FIRTimestamp *)monthStartTimestamp {
    return [self timestampForFilter:@"month"];
}

- (id<FIRListenerRegistration>)subscribeTransactionsWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    NSString *branchID = PPAccountingSelectedBranchID();
    if (branchID.length == 0) {
        [self.internalTransactions removeAllObjects];
        if (callback) callback();
        return [PPAccountingScopedOrderRegistration new];
    }
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"transactions"] queryWhereField:@"branchId" isEqualTo:branchID];
    FIRTimestamp *ts = [self timestampForFilter:filter];
    if (ts) query = [query queryWhereField:@"createdAt" isGreaterThanOrEqualTo:ts];
    query = [query queryOrderedByField:@"createdAt" descending:YES];
    return [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error || ![PPAccountingSelectedBranchID() isEqualToString:branchID]) return;
        [self.internalTransactions removeAllObjects];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [self.internalTransactions addObject:[[PPAccountingTransaction alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (callback) callback();
    }];
}

- (id<FIRListenerRegistration>)subscribeExpensesWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    NSString *branchID = PPAccountingSelectedBranchID();
    if (branchID.length == 0) {
        [self.internalExpenses removeAllObjects];
        if (callback) callback();
        return [PPAccountingScopedOrderRegistration new];
    }
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"expenses"] queryWhereField:@"branchId" isEqualTo:branchID];
    FIRTimestamp *ts = [self timestampForFilter:filter];
    if (ts) query = [query queryWhereField:@"createdAt" isGreaterThanOrEqualTo:ts];
    query = [query queryOrderedByField:@"createdAt" descending:YES];
    return [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error || ![PPAccountingSelectedBranchID() isEqualToString:branchID]) return;
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
    FIRTimestamp *filterTs = [self timestampForFilter:filter];
    NSDate *startDate = filterTs ? filterTs.dateValue : nil;
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
                if (startDate && (!createdAt || [createdAt compare:startDate] == NSOrderedAscending)) continue;
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

- (void)fetchAccountingWorkspaceWithFilter:(NSString *)filter
                                completion:(void(^ _Nullable)(PPAccountingWorkspaceSnapshot * _Nullable snapshot, NSError * _Nullable error))completion {
    NSString *period = PPAccountingNormalizePeriod(filter);
    NSString *branchID = PPAccountingSelectedBranchID();
    self.currentFilterKey = period;
    if (branchID.length == 0) {
        if (completion) completion(nil, PPAccountingBranchRequiredError());
        return;
    }
    NSString *cacheKey = PPAccountingWorkspaceCacheKey(period, branchID);
    FIRFunctions *functions = [FIRFunctions functionsForRegion:@"us-central1"];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"getAccountingWorkspace"];
    NSDictionary *payload = @{
        @"period": period,
        @"pageSize": @100,
        @"branchId": branchID,
    };
    __weak typeof(self) weakSelf = self;
    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![PPAccountingSelectedBranchID() isEqualToString:branchID]) return;
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : @{};
        PPAccountingWorkspaceSnapshot *snapshot = [[PPAccountingWorkspaceSnapshot alloc] initWithDictionary:data];
        @synchronized (self.workspacesByFilter) {
            self.workspacesByFilter[cacheKey] = snapshot;
        }
        if (snapshot.primaryDashboard) {
            self.internalOrderRevenue = snapshot.primaryDashboard.income;
            self.internalOrderCount = snapshot.incomeCount;
            self.internalOrderRevenueEvidenceAvailable = YES;
            self.internalOrderRevenueError = nil;
        }
        if (completion) completion(snapshot, nil);
    }];
}

- (id<FIRListenerRegistration>)subscribeAccountingWorkspaceWithFilter:(NSString *)filter
                                                              callback:(void(^)(PPAccountingWorkspaceSnapshot * _Nullable snapshot))callback {
    NSString *requestedFilter = [filter copy] ?: @"this_month";
    NSString *period = PPAccountingNormalizePeriod(requestedFilter);
    NSString *branchID = PPAccountingSelectedBranchID();
    self.currentFilterKey = period;
    if (branchID.length == 0) {
        if (callback) callback(nil);
        return [PPAccountingScopedOrderRegistration new];
    }

    // 1. Initial fetch
    [self fetchAccountingWorkspaceWithFilter:requestedFilter completion:^(PPAccountingWorkspaceSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([PPAccountingSelectedBranchID() isEqualToString:branchID] && callback) callback(snapshot);
        });
    }];

    // 2. Branch-bound refresh signal. The callable remains the authoritative projection.
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *summaryQuery = [[db collectionWithPath:@"AccountingDailySummaries"] queryWhereField:@"branchId" isEqualTo:branchID];
    summaryQuery = [summaryQuery queryLimitedTo:31];
    __weak typeof(self) weakSelf = self;
    __block BOOL isInitial = YES;
    __block BOOL debouncePending = NO;
    return [summaryQuery addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || error || ![PPAccountingSelectedBranchID() isEqualToString:branchID]) return;
        if (isInitial) {
            isInitial = NO;
            return;
        }
        if (debouncePending) return;
        debouncePending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            debouncePending = NO;
            if (![PPAccountingSelectedBranchID() isEqualToString:branchID]) return;
            [self fetchAccountingWorkspaceWithFilter:requestedFilter completion:^(PPAccountingWorkspaceSnapshot * _Nullable freshSnapshot, NSError * _Nullable err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (callback) callback(freshSnapshot);
                });
            }];
        });
    }];
}

- (void)addExpense:(double)amount category:(NSString *)category description:(NSString *)desc completion:(void(^ _Nullable)(NSError * _Nullable error))completion {
    NSString *branchID = PPAccountingSelectedBranchID();
    if (branchID.length == 0) {
        if (completion) completion(PPAccountingBranchRequiredError());
        return;
    }
    NSDictionary<NSString *, NSString *> *categoryMap = @{
        @"salary": @"salaries", @"rent": @"rent", @"supplies": @"office_expenses",
        @"utilities": @"utilities", @"marketing": @"marketing", @"logistics": @"transportation",
        @"medical": @"other", @"maintenance": @"maintenance", @"inventory": @"equipment", @"other": @"other"
    };
    NSString *normalizedCategory = [category.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *categoryID = categoryMap[normalizedCategory] ?: @"other";
    NSDictionary *payload = @{
        @"kind": @"expense",
        @"amount": @(amount),
        @"currency": @"QAR",
        @"status": @"paid",
        @"categoryId": categoryID,
        @"description": desc ?: @"",
        @"branchId": branchID,
        @"idempotencyKey": NSUUID.UUID.UUIDString,
    };
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"createAccountingDocument"];
    __weak typeof(self) weakSelf = self;
    [callable callWithObject:payload completion:^(__unused FIRHTTPSCallableResult *result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!error && self && [PPAccountingSelectedBranchID() isEqualToString:branchID]) {
            @synchronized (self.workspacesByFilter) {
                [self.workspacesByFilter removeAllObjects];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"PPAccountingDataDidChangeNotification" object:nil];
            });
            [self fetchAccountingWorkspaceWithFilter:self.currentFilterKey ?: @"this_month" completion:nil];
        }
        if (completion) completion(error);
    }];
}

- (void)deleteExpense:(NSString *)expenseID completion:(void(^ _Nullable)(NSError * _Nullable error))completion {
    NSString *branchID = PPAccountingSelectedBranchID();
    if (branchID.length == 0) {
        if (completion) completion(PPAccountingBranchRequiredError());
        return;
    }
    NSString *documentID = [expenseID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![documentID hasPrefix:@"expense_"]) {
        NSError *error = [NSError errorWithDomain:PPAccountingOrderScopeErrorDomain
                                             code:415
                                         userInfo:@{NSLocalizedDescriptionKey: kLang(@"Accounting_LegacyExpenseReadOnly")}];
        if (completion) completion(error);
        return;
    }
    NSDictionary *payload = @{
        @"documentId": documentID,
        @"reason": @"Voided by authorized Admin operator",
        @"branchId": branchID,
        @"idempotencyKey": NSUUID.UUID.UUIDString,
    };
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"voidAccountingDocument"];
    __weak typeof(self) weakSelf = self;
    [callable callWithObject:payload completion:^(__unused FIRHTTPSCallableResult *result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!error && self && [PPAccountingSelectedBranchID() isEqualToString:branchID]) {
            @synchronized (self.workspacesByFilter) {
                [self.workspacesByFilter removeAllObjects];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"PPAccountingDataDidChangeNotification" object:nil];
            });
            [self fetchAccountingWorkspaceWithFilter:self.currentFilterKey ?: @"this_month" completion:nil];
        }
        if (completion) completion(error);
    }];
}

@end
