#import "PPFulfillmentService.h"
#import "PPStaffAuth.h"
@import FirebaseAuth;
@import FirebaseFirestore;
@import FirebaseFunctions;

static NSString * const PPFulfillmentServiceErrorDomain = @"PPFulfillmentService";
static NSString * const PPFulfillmentPartialReadMarkerKey = @"PPFulfillmentPartialRead";
static NSString * const PPFulfillmentOfficialOwnerID = @"PUIDPOFFICILAL20262214";
static NSUInteger const PPFulfillmentScopeChunkLimit = 30;

@interface PPFulfillmentCompositeRegistration : NSObject <FIRListenerRegistration>
@property (atomic, assign, getter=isActive) BOOL active;
@property (nonatomic, strong) NSMutableArray<id<FIRListenerRegistration>> *registrations;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<FIRDocumentSnapshot *> *> *documentsByQuery;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *settledQueries;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSError *> *errorsByQuery;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *cacheStateByQuery;
@property (nonatomic, assign) NSUInteger queryCount;
- (void)addRegistration:(id<FIRListenerRegistration>)registration;
@end

@implementation PPFulfillmentCompositeRegistration
- (instancetype)init {
    if ((self = [super init])) {
        _active = YES;
        _registrations = [NSMutableArray array];
        _documentsByQuery = [NSMutableDictionary dictionary];
        _settledQueries = [NSMutableSet set];
        _errorsByQuery = [NSMutableDictionary dictionary];
        _cacheStateByQuery = [NSMutableDictionary dictionary];
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
        [self.cacheStateByQuery removeAllObjects];
    }
    for (id<FIRListenerRegistration> registration in registrations) [registration remove];
}
@end

static NSError *PPFulfillmentReadError(NSInteger code, NSString *localizationKey) {
    return [NSError errorWithDomain:PPFulfillmentServiceErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: kLang(localizationKey)}];
}

/// A missing document is a recoverable *read* outcome only when the Firestore
/// SDK reports it as such. Function `not-found` failures are intentionally not
/// included here because they can represent an authorization-protected server
/// resource and must remain fail-closed.
static BOOL PPFulfillmentErrorContainsCode(NSError *error, NSString *domain, NSInteger code) {
    NSError *currentError = error;
    for (NSUInteger depth = 0; currentError && depth < 4; depth += 1) {
        if ([currentError.domain isEqualToString:domain] && currentError.code == code) {
            return YES;
        }
        id underlying = currentError.userInfo[NSUnderlyingErrorKey];
        currentError = [underlying isKindOfClass:NSError.class] ? underlying : nil;
    }
    return NO;
}

static BOOL PPFulfillmentErrorContainsFirestoreCode(NSError *error, NSInteger code) {
    return PPFulfillmentErrorContainsCode(error, FIRFirestoreErrorDomain, code);
}

static BOOL PPFulfillmentErrorIndicatesAbsentDocument(NSError *error) {
    return PPFulfillmentErrorContainsFirestoreCode(error, FIRFirestoreErrorCodeNotFound) ||
        PPFulfillmentErrorContainsCode(error, NSCocoaErrorDomain, NSFileNoSuchFileError);
}

static NSError *PPFulfillmentOfficialReadFailure(NSError *underlyingError) {
    if (!underlyingError || PPFulfillmentErrorIndicatesAbsentDocument(underlyingError)) return nil;
    if (PPFulfillmentErrorContainsFirestoreCode(underlyingError, FIRFirestoreErrorCodePermissionDenied)) {
        return PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope");
    }
    return PPFulfillmentReadError(413, @"PaymentMgmt_OfficialFulfillment_LoadFailed_Subtitle");
}

static NSError *PPFulfillmentPartialReadError(NSError *underlyingError,
                                              NSUInteger successfulQueryCount,
                                              NSUInteger queryCount) {
    NSMutableDictionary *userInfo = [@{
        NSLocalizedDescriptionKey: kLang(@"PPOrder_Error_PartialRead"),
        PPFulfillmentPartialReadMarkerKey: @YES,
        @"successfulQueryCount": @(successfulQueryCount),
        @"queryCount": @(queryCount),
    } mutableCopy];
    if (underlyingError) userInfo[NSUnderlyingErrorKey] = underlyingError;
    return [NSError errorWithDomain:PPFulfillmentServiceErrorDomain code:413 userInfo:userInfo];
}

static NSArray<NSString *> *PPFulfillmentCanonicalScopeIDs(PPStaffDoc *staff, NSString *key) {
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

static BOOL PPFulfillmentCanRead(PPStaffDoc *staff) {
    return staff.isActive && [staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage, kStaffPermProvidersView]];
}

static BOOL PPFulfillmentHasReadableScope(PPStaffDoc *staff) {
    return (staff.isActive && (staff.isAdmin || staff.hasGlobalScope ||
            PPFulfillmentCanonicalScopeIDs(staff, @"branchIds").count > 0 ||
            PPFulfillmentCanonicalScopeIDs(staff, @"regionIds").count > 0));
}

static BOOL PPFulfillmentStaffSessionIsCurrent(PPStaffDoc *staff) {
    PPStaffDoc *current = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *authUID = [FIRAuth auth].currentUser.uid;
    return (staff != nil && current == staff && authUID.length > 0 &&
            [staff.uid isEqualToString:authUID] && staff.isActive);
}

static NSString *PPFulfillmentExactResourceScopeID(NSDictionary *data, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = data[key];
        if ([value isKindOfClass:NSString.class]) return value;
    }
    return @"";
}

static BOOL PPFulfillmentStaffCanReachData(PPStaffDoc *staff, NSDictionary *data) {
    if (!PPFulfillmentStaffSessionIsCurrent(staff) || ![data isKindOfClass:NSDictionary.class]) return NO;
    if (staff.isAdmin || staff.hasGlobalScope) return YES;

    // Match Firestore Rules' exact-document compatibility precedence. Collection
    // queries remain canonical branchId/regionId-only in PPFulfillmentScopedQueries.
    NSString *branchID = PPFulfillmentExactResourceScopeID(data, @[@"BranchID", @"branchId", @"branchID", @"branch_id"]);
    NSString *regionID = PPFulfillmentExactResourceScopeID(data, @[@"regionId", @"regionID", @"RegionID"]);
    return ((branchID.length > 0 && [PPFulfillmentCanonicalScopeIDs(staff, @"branchIds") containsObject:branchID]) ||
            (regionID.length > 0 && [PPFulfillmentCanonicalScopeIDs(staff, @"regionIds") containsObject:regionID]));
}

static FIRQuery *PPFulfillmentOrderedQuery(FIRQuery *query, NSInteger limit) {
    query = [query queryOrderedByField:@"updatedAt" descending:YES];
    query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
    return [query queryLimitedTo:MAX(1, limit)];
}

static NSArray<FIRQuery *> *PPFulfillmentScopedQueries(FIRFirestore *db, PPStaffDoc *staff, NSInteger limit) {
    FIRCollectionReference *collection = [db collectionWithPath:@"FulfillmentOrders"];
    if (staff.isAdmin || staff.hasGlobalScope) return @[PPFulfillmentOrderedQuery(collection, limit)];

    NSMutableArray<FIRQuery *> *queries = [NSMutableArray array];
    NSDictionary<NSString *, NSArray<NSString *> *> *scope = @{
        @"branchId": PPFulfillmentCanonicalScopeIDs(staff, @"branchIds"),
        @"regionId": PPFulfillmentCanonicalScopeIDs(staff, @"regionIds"),
    };
    for (NSString *field in @[@"branchId", @"regionId"]) {
        NSArray<NSString *> *ids = scope[field];
        for (NSUInteger offset = 0; offset < ids.count; offset += PPFulfillmentScopeChunkLimit) {
            NSRange range = NSMakeRange(offset, MIN(PPFulfillmentScopeChunkLimit, ids.count - offset));
            FIRQuery *query = [collection queryWhereField:field in:[ids subarrayWithRange:range]];
            [queries addObject:PPFulfillmentOrderedQuery(query, limit)];
        }
    }
    return queries.copy;
}

static NSArray<FIRDocumentSnapshot *> *PPFulfillmentMergeDocuments(NSArray<NSArray<FIRDocumentSnapshot *> *> *groups, NSInteger limit) {
    NSMutableDictionary<NSString *, FIRDocumentSnapshot *> *byID = [NSMutableDictionary dictionary];
    for (NSArray<FIRDocumentSnapshot *> *group in groups) {
        for (FIRDocumentSnapshot *document in group) {
            if (document.documentID.length) byID[document.documentID] = document;
        }
    }
    NSArray<FIRDocumentSnapshot *> *sorted = [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(FIRDocumentSnapshot *left, FIRDocumentSnapshot *right) {
        NSDate *leftDate = [left.data[@"updatedAt"] isKindOfClass:FIRTimestamp.class] ? [left.data[@"updatedAt"] dateValue] : NSDate.distantPast;
        NSDate *rightDate = [right.data[@"updatedAt"] isKindOfClass:FIRTimestamp.class] ? [right.data[@"updatedAt"] dateValue] : NSDate.distantPast;
        NSComparisonResult dateResult = [rightDate compare:leftDate];
        return dateResult != NSOrderedSame ? dateResult : [right.documentID compare:left.documentID];
    }];
    return sorted.count > (NSUInteger)limit ? [sorted subarrayWithRange:NSMakeRange(0, limit)] : sorted;
}

@interface PPFulfillmentService ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *userProfileCache;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@end

@implementation PPFulfillmentRecord
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _fulfillmentID = docID ?: @"";
        _branchId = PPSafeString(dict[@"branchId"]);
        _regionId = PPSafeString(dict[@"regionId"]);
        _parentOrderID = PPSafeString(dict[@"parentOrderId"]);
        _parentOrderNumber = PPSafeString(dict[@"parentOrderNumber"]);
        _parentUserId = PPSafeString(dict[@"parentUserId"]);
        _customerID = PPSafeString(dict[@"customerID"]);
        if (!_customerID.length) _customerID = _parentUserId;
        _customerName = PPSafeString(dict[@"customerName"]);
        _ownerID = PPSafeString(dict[@"ownerID"]);
        if (!_ownerID.length) _ownerID = PPSafeString(dict[@"ownerId"]);
        _ownerType = PPSafeString(dict[@"ownerType"]);
        _fulfillmentMode = PPSafeString(dict[@"fulfillmentMode"]);
        _status = PPSafeString(dict[@"status"]);
        _items = PPSafeArray(dict[@"items"]);
        _money = PPSafeDict(dict[@"money"]);
        
        _adminOverrideBy = PPSafeString(dict[@"adminOverrideBy"]);
        _adminOverrideReason = PPSafeString(dict[@"adminOverrideReason"]);
        _adminOverrideCommandID = PPSafeString(dict[@"adminOverrideCommandId"]);

        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
        id ua = dict[@"updatedAt"];
        if ([ua isKindOfClass:FIRTimestamp.class]) _updatedAt = [(FIRTimestamp *)ua dateValue];
        id oa = dict[@"adminOverrideAt"];
        if ([oa isKindOfClass:FIRTimestamp.class]) _adminOverrideAt = [(FIRTimestamp *)oa dateValue];
    }
    return self;
}
@end

@implementation PPFulfillmentService

+ (instancetype)shared {
    static PPFulfillmentService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

+ (BOOL)isPartialReadError:(NSError *)error {
    return [error.domain isEqualToString:PPFulfillmentServiceErrorDomain] &&
           [error.userInfo[PPFulfillmentPartialReadMarkerKey] boolValue];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _userProfileCache = [NSMutableDictionary dictionary];
        _cacheQueue = dispatch_queue_create("com.purepets.fulfillment.cache", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)fetchFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (!PPFulfillmentCanRead(staff)) {
        if (completion) completion(@[], PPFulfillmentReadError(410, @"PPOrder_Error_NoReadPermission"));
        return;
    }
    if (!PPFulfillmentHasReadableScope(staff)) {
        if (completion) completion(@[], PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope"));
        return;
    }

    NSArray<FIRQuery *> *queries = PPFulfillmentScopedQueries(db, staff, 100);
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSArray<FIRDocumentSnapshot *> *> *documents = [NSMutableArray arrayWithCapacity:queries.count];
    for (NSUInteger index = 0; index < queries.count; index++) [documents addObject:@[]];
    __block NSError *firstError = nil;
    __block NSUInteger successfulQueryCount = 0;
    [queries enumerateObjectsUsingBlock:^(FIRQuery *query, NSUInteger index, BOOL *stop) {
        dispatch_group_enter(group);
        [query getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
            @synchronized (documents) {
                if (error && !firstError) firstError = error;
                if (!error) {
                    successfulQueryCount += 1;
                    documents[index] = snapshot.documents ?: @[];
                }
            }
            dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
            if (completion) completion(@[], PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (firstError && successfulQueryCount == 0) {
            if (completion) completion(@[], firstError);
            return;
        }

        NSMutableArray<PPFulfillmentRecord *> *records = [NSMutableArray array];
        for (FIRDocumentSnapshot *document in PPFulfillmentMergeDocuments(documents, 100)) {
            [records addObject:[[PPFulfillmentRecord alloc] initWithDictionary:document.data documentID:document.documentID]];
        }
        NSError *resultError = firstError
            ? PPFulfillmentPartialReadError(firstError, successfulQueryCount, queries.count)
            : nil;
        if (completion) completion(records.copy, resultError);
    });
}

- (id<FIRListenerRegistration>)observeFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *, BOOL, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    PPFulfillmentCompositeRegistration *composite = [PPFulfillmentCompositeRegistration new];
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (!PPFulfillmentCanRead(staff) || !PPFulfillmentHasReadableScope(staff)) {
        NSError *error = PPFulfillmentReadError(PPFulfillmentCanRead(staff) ? 411 : 410,
                                                PPFulfillmentCanRead(staff) ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission");
        if (completion) completion(@[], NO, error);
        return composite;
    }

    NSArray<FIRQuery *> *queries = PPFulfillmentScopedQueries(db, staff, 100);
    composite.queryCount = queries.count;
    [queries enumerateObjectsUsingBlock:^(FIRQuery *query, NSUInteger index, BOOL *stop) {
        id<FIRListenerRegistration> registration = [query addSnapshotListenerWithIncludeMetadataChanges:YES listener:^(FIRQuerySnapshot *snapshot, NSError *error) {
            if (!composite.isActive) return;
            if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
                [composite remove];
                if (completion) completion(@[], NO, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
                return;
            }
            NSArray<NSArray<FIRDocumentSnapshot *> *> *groups = nil;
            NSError *firstError = nil;
            NSUInteger successfulQueryCount = 0;
            BOOL allReady = NO;
            BOOL isFromCache = NO;
            @synchronized (composite) {
                [composite.settledQueries addObject:@(index)];
                if (error) composite.errorsByQuery[@(index)] = error;
                else {
                    composite.documentsByQuery[@(index)] = snapshot.documents ?: @[];
                    composite.cacheStateByQuery[@(index)] = @(snapshot.metadata.isFromCache);
                    [composite.errorsByQuery removeObjectForKey:@(index)];
                }
                allReady = composite.settledQueries.count == composite.queryCount;
                groups = composite.documentsByQuery.allValues.copy;
                firstError = composite.errorsByQuery.allValues.firstObject;
                successfulQueryCount = composite.documentsByQuery.count;
                isFromCache = firstError == nil && composite.cacheStateByQuery.count == composite.queryCount;
                if (isFromCache) {
                    for (NSNumber *cacheState in composite.cacheStateByQuery.allValues) {
                        if (!cacheState.boolValue) {
                            isFromCache = NO;
                            break;
                        }
                    }
                }
            }
            if (!allReady || !composite.isActive) return;
            if (firstError && successfulQueryCount == 0) {
                if (completion) completion(@[], NO, firstError);
                return;
            }

            NSMutableArray<PPFulfillmentRecord *> *records = [NSMutableArray array];
            for (FIRDocumentSnapshot *document in PPFulfillmentMergeDocuments(groups, 100)) {
                [records addObject:[[PPFulfillmentRecord alloc] initWithDictionary:document.data documentID:document.documentID]];
            }
            NSError *resultError = firstError
                ? PPFulfillmentPartialReadError(firstError, successfulQueryCount, composite.queryCount)
                : nil;
            if (completion) completion(records.copy, isFromCache, resultError);
        }];
        [composite addRegistration:registration];
    }];
    return composite;
}

- (id<FIRListenerRegistration>)observeFulfillment:(NSString *)fulfillmentID completion:(void(^)(PPFulfillmentRecord *, BOOL, BOOL, NSError *))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    PPFulfillmentCompositeRegistration *composite = [PPFulfillmentCompositeRegistration new];
    if (!PPFulfillmentCanRead(staff) || !PPFulfillmentHasReadableScope(staff)) {
        NSError *error = PPFulfillmentReadError(PPFulfillmentCanRead(staff) ? 411 : 410,
                                                PPFulfillmentCanRead(staff) ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission");
        if (completion) completion(nil, NO, NO, error);
        return composite;
    }
    FIRDocumentReference *ref = [[[FIRFirestore firestore] collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID];
    id<FIRListenerRegistration> registration = [ref addSnapshotListenerWithIncludeMetadataChanges:YES listener:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (!composite.isActive) return;
        if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
            [composite remove];
            if (completion) completion(nil, NO, NO, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (error) {
            if (completion) completion(nil, NO, NO, error);
            return;
        }
        if (!snapshot.exists) {
            NSError *notFound = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
            if (completion) completion(nil, snapshot.metadata.isFromCache, snapshot.metadata.hasPendingWrites, notFound);
            return;
        }
        if (!PPFulfillmentStaffCanReachData(staff, snapshot.data)) {
            [composite remove];
            if (completion) completion(nil, snapshot.metadata.isFromCache, snapshot.metadata.hasPendingWrites,
                                       PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope"));
            return;
        }
        PPFulfillmentRecord *record = [[PPFulfillmentRecord alloc] initWithDictionary:snapshot.data documentID:snapshot.documentID];
        if (completion) completion(record, snapshot.metadata.isFromCache, snapshot.metadata.hasPendingWrites, nil);
    }];
    [composite addRegistration:registration];
    return composite;
}

- (id<FIRListenerRegistration>)observeAdminOverrideCommand:(NSString *)fulfillmentID commandDocumentID:(NSString *)commandDocumentID completion:(void(^)(NSDictionary *, BOOL, BOOL, NSError *))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    PPFulfillmentCompositeRegistration *composite = [PPFulfillmentCompositeRegistration new];
    if (![staff hasPermission:kStaffPermPaymentsManage] || !PPFulfillmentHasReadableScope(staff)) {
        NSError *error = PPFulfillmentReadError([staff hasPermission:kStaffPermPaymentsManage] ? 411 : 410,
                                                [staff hasPermission:kStaffPermPaymentsManage] ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission");
        if (completion) completion(nil, NO, NO, error);
        return composite;
    }
    FIRDocumentReference *fulfillmentRef = [[[FIRFirestore firestore] collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID];
    [fulfillmentRef getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
        if (!composite.isActive) return;
        if (error || !snapshot.exists) {
            if (completion) completion(nil, NO, NO, error ?: PPFulfillmentReadError(404, @"PPOrder_Error_NoReadPermission"));
            return;
        }
        if (!PPFulfillmentStaffCanReachData(staff, snapshot.data)) {
            if (completion) completion(nil, snapshot.metadata.isFromCache, snapshot.metadata.hasPendingWrites,
                                       PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope"));
            return;
        }
        FIRDocumentReference *commandRef = [[fulfillmentRef collectionWithPath:@"adminOverrideCommands"] documentWithPath:commandDocumentID];
        id<FIRListenerRegistration> registration = [commandRef addSnapshotListenerWithIncludeMetadataChanges:YES listener:^(FIRDocumentSnapshot *commandSnapshot, NSError *commandError) {
            if (!composite.isActive) return;
            if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
                [composite remove];
                if (completion) completion(nil, NO, NO, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
                return;
            }
            if (commandError) {
                if (completion) completion(nil, NO, NO, commandError);
                return;
            }
            if (!commandSnapshot.exists) {
                NSError *notFound = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
                if (completion) completion(nil, commandSnapshot.metadata.isFromCache, commandSnapshot.metadata.hasPendingWrites, notFound);
                return;
            }
            if (completion) completion(commandSnapshot.data, commandSnapshot.metadata.isFromCache, commandSnapshot.metadata.hasPendingWrites, nil);
        }];
        [composite addRegistration:registration];
    }];
    return composite;
}

- (void)fetchFulfillmentDetail:(NSString *)fulfillmentID completion:(void(^)(PPFulfillmentRecord *, NSArray *, NSError *))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (!PPFulfillmentCanRead(staff) || !PPFulfillmentHasReadableScope(staff)) {
        if (completion) completion(nil, @[], PPFulfillmentReadError(PPFulfillmentCanRead(staff) ? 411 : 410,
                                                                    PPFulfillmentCanRead(staff) ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission"));
        return;
    }
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *ref = [[db collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID];
    [ref getDocumentWithCompletion:^(FIRDocumentSnapshot *snap, NSError *error) {
        if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
            if (completion) completion(nil, @[], PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (error) { if (completion) completion(nil, @[], error); return; }
        if (!snap.exists) {
            NSError *notFound = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:nil];
            if (completion) completion(nil, @[], notFound);
            return;
        }
        if (!PPFulfillmentStaffCanReachData(staff, snap.data)) {
            if (completion) completion(nil, @[], PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope"));
            return;
        }
        PPFulfillmentRecord *r = [[PPFulfillmentRecord alloc] initWithDictionary:snap.data documentID:snap.documentID];
        FIRQuery *eventsQuery = [[ref collectionWithPath:@"events"] queryOrderedByField:@"createdAt" descending:YES];
        eventsQuery = [eventsQuery queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
        eventsQuery = [eventsQuery queryLimitedTo:100];
        [eventsQuery
         getDocumentsWithCompletion:^(FIRQuerySnapshot *eventSnap, NSError *eventError) {
            if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
                if (completion) completion(nil, @[], PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
                return;
            }
            NSMutableArray *events = [NSMutableArray array];
            for (FIRDocumentSnapshot *edoc in eventSnap.documents) {
                NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:edoc.data ?: @{}];
                event[@"id"] = edoc.documentID;
                [events addObject:event];
            }
            if (completion) completion(r, events, eventError);
        }];
    }];
}

- (void)fetchOfficialFulfillmentForParentOrderID:(NSString *)parentOrderID
                                  fulfillmentIDs:(NSArray<NSString *> *)fulfillmentIDs
                                      completion:(void(^)(PPFulfillmentRecord *, NSError *))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasPermission:kStaffPermPaymentsManage] || !PPFulfillmentHasReadableScope(staff)) {
        if (completion) completion(nil, PPFulfillmentReadError([staff hasPermission:kStaffPermPaymentsManage] ? 411 : 410,
                                                               [staff hasPermission:kStaffPermPaymentsManage] ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission"));
        return;
    }
    NSString *safeParentID = [parentOrderID isKindOfClass:NSString.class]
        ? [parentOrderID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    NSMutableOrderedSet<NSString *> *exactIDs = [NSMutableOrderedSet orderedSet];
    for (id value in fulfillmentIDs ?: @[]) {
        if (![value isKindOfClass:NSString.class]) continue;
        NSString *fulfillmentID = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (fulfillmentID.length) [exactIDs addObject:fulfillmentID];
    }
    if (!safeParentID.length || exactIDs.count == 0) {
        if (completion) completion(nil, nil);
        return;
    }

    FIRCollectionReference *collection = [[FIRFirestore firestore] collectionWithPath:@"FulfillmentOrders"];
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<PPFulfillmentRecord *> *matches = [NSMutableArray array];
    __block NSError *firstError = nil;
    for (NSString *fulfillmentID in exactIDs.array) {
        dispatch_group_enter(group);
        [[collection documentWithPath:fulfillmentID] getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
            @synchronized (matches) {
                NSError *readFailure = PPFulfillmentOfficialReadFailure(error);
                if (!firstError && readFailure) firstError = readFailure;
                if (!error && snapshot.exists) {
                    PPFulfillmentRecord *record = [[PPFulfillmentRecord alloc] initWithDictionary:snapshot.data documentID:snapshot.documentID];
                    if ([record.parentOrderID isEqualToString:safeParentID] &&
                        [PPFulfillmentService isOfficialPlatformFulfillment:record]) {
                        if (PPFulfillmentStaffCanReachData(staff, snapshot.data)) {
                            [matches addObject:record];
                        } else if (!firstError) {
                            firstError = PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope");
                        }
                    }
                }
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
            if (completion) completion(nil, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (firstError) {
            if (completion) completion(nil, firstError);
            return;
        }
        if (matches.count > 1) {
            if (completion) completion(nil, PPFulfillmentReadError(414, @"PaymentMgmt_OfficialFulfillment_Ambiguous"));
            return;
        }
        if (completion) completion(matches.firstObject, nil);
    });
}

- (id<FIRListenerRegistration>)observeFulfillmentEvents:(NSString *)fulfillmentID completion:(void(^)(NSArray<NSDictionary *> *, NSError *))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    PPFulfillmentCompositeRegistration *composite = [PPFulfillmentCompositeRegistration new];
    if (!PPFulfillmentCanRead(staff) || !PPFulfillmentHasReadableScope(staff)) {
        if (completion) completion(@[], PPFulfillmentReadError(PPFulfillmentCanRead(staff) ? 411 : 410,
                                                               PPFulfillmentCanRead(staff) ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission"));
        return composite;
    }
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *fulfillmentRef = [[db collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID];
    [fulfillmentRef getDocumentWithCompletion:^(FIRDocumentSnapshot *parentSnapshot, NSError *parentError) {
        if (!composite.isActive) return;
        if (parentError || !parentSnapshot.exists) {
            if (completion) completion(@[], parentError ?: PPFulfillmentReadError(404, @"PPOrder_Error_NoReadPermission"));
            return;
        }
        if (!PPFulfillmentStaffCanReachData(staff, parentSnapshot.data)) {
            if (completion) completion(@[], PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope"));
            return;
        }
        FIRQuery *query = [[fulfillmentRef collectionWithPath:@"events"] queryOrderedByField:@"createdAt" descending:YES];
        query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
        query = [query queryLimitedTo:50];
        id<FIRListenerRegistration> registration = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
            if (!composite.isActive) return;
            if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
                [composite remove];
                if (completion) completion(@[], PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
                return;
            }
            if (error) {
                if (completion) completion(@[], error);
                return;
            }
            NSMutableArray *events = [NSMutableArray array];
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:doc.data ?: @{}];
                dict[@"id"] = doc.documentID;
                [events addObject:dict];
            }
            if (completion) completion(events, nil);
        }];
        [composite addRegistration:registration];
    }];
    return composite;
}

- (void)resolveUserProfilesForIDs:(NSArray<NSString *> *)userIDs completion:(void(^)(NSDictionary<NSString *, NSString *> *names))completion {
    if (!userIDs.count) {
        if (completion) completion(@{});
        return;
    }
    
    NSMutableSet *missing = [NSMutableSet set];
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    
    dispatch_sync(self.cacheQueue, ^{
        for (NSString *uid in userIDs) {
            if (!uid.length) continue;
            NSString *cached = self.userProfileCache[uid];
            if (cached) {
                results[uid] = cached;
            } else {
                [missing addObject:uid];
            }
        }
    });
    
    if (!missing.count) {
        if (completion) completion(results);
        return;
    }
    
    FIRFirestore *db = [FIRFirestore firestore];
    dispatch_group_t group = dispatch_group_create();
    
    NSArray *missingList = missing.allObjects;
    NSUInteger chunkSize = 10;
    
    for (NSUInteger i = 0; i < missingList.count; i += chunkSize) {
        NSRange range = NSMakeRange(i, MIN(chunkSize, missingList.count - i));
        NSArray *chunk = [missingList subarrayWithRange:range];
        
        dispatch_group_enter(group);
        [[[db collectionWithPath:@"PublicUserProfiles"] queryWhereFieldPath:[FIRFieldPath documentID] in:chunk] getDocumentsWithCompletion:^(FIRQuerySnapshot *snap, NSError *err) {
            NSMutableSet *found = [NSMutableSet set];
            if (!err) {
                for (FIRDocumentSnapshot *doc in snap.documents) {
                    NSDictionary *data = doc.data;
                    NSString *name = PPSafeString(data[@"displayName"]);
                    if (!name.length) name = PPSafeString(data[@"name"]);
                    if (!name.length) name = PPSafeString(data[@"fullName"]);
                    if (!name.length) name = PPSafeString(data[@"email"]);
                    if (name.length) {
                        [found addObject:doc.documentID];
                        dispatch_barrier_async(self.cacheQueue, ^{
                            self.userProfileCache[doc.documentID] = name;
                        });
                        results[doc.documentID] = name;
                    }
                }
            }
            
            NSMutableArray *stillMissing = [NSMutableArray array];
            for (NSString *uid in chunk) {
                if (![found containsObject:uid]) [stillMissing addObject:uid];
            }
            
            if (stillMissing.count > 0) {
                [[[db collectionWithPath:@"UsersCol"] queryWhereFieldPath:[FIRFieldPath documentID] in:stillMissing] getDocumentsWithCompletion:^(FIRQuerySnapshot *uSnap, NSError *uErr) {
                    if (!uErr) {
                        for (FIRDocumentSnapshot *doc in uSnap.documents) {
                            NSDictionary *data = doc.data;
                            NSString *name = PPSafeString(data[@"displayName"]);
                            if (!name.length) name = PPSafeString(data[@"name"]);
                            if (!name.length) name = PPSafeString(data[@"fullName"]);
                            if (!name.length) name = PPSafeString(data[@"email"]);
                            if (name.length) {
                                dispatch_barrier_async(self.cacheQueue, ^{
                                    self.userProfileCache[doc.documentID] = name;
                                });
                                results[doc.documentID] = name;
                            }
                        }
                    }
                    dispatch_group_leave(group);
                }];
            } else {
                dispatch_group_leave(group);
            }
        }];
    }
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) completion(results);
    });
}

- (void)adminOverrideFulfillment:(NSString *)fulfillmentID expectedStatus:(NSString *)expectedStatus targetStatus:(NSString *)status reason:(NSString *)reason note:(nullable NSString *)note notify:(BOOL)notify commandID:(NSString *)commandID completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasPermission:kStaffPermPaymentsManage] || !PPFulfillmentHasReadableScope(staff)) {
        if (completion) completion(nil, PPFulfillmentReadError([staff hasPermission:kStaffPermPaymentsManage] ? 411 : 410,
                                                               [staff hasPermission:kStaffPermPaymentsManage] ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission"));
        return;
    }
    FIRDocumentReference *fulfillmentRef = [[[FIRFirestore firestore] collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID];
    [fulfillmentRef getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *readError) {
        if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
            if (completion) completion(nil, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (readError || !snapshot.exists) {
            NSError *resolvedError = readError ?: [NSError errorWithDomain:NSCocoaErrorDomain
                                                                       code:NSFileNoSuchFileError
                                                                   userInfo:nil];
            if (completion) completion(nil, resolvedError);
            return;
        }
        if (!PPFulfillmentStaffCanReachData(staff, snapshot.data)) {
            if (completion) completion(nil, PPFulfillmentReadError(411, @"PPOrder_Error_MissingReadScope"));
            return;
        }

        FIRFunctions *functions = [FIRFunctions functions];
        FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"adminOverrideFulfillment"];
        [callable callWithObject:@{
            @"fulfillmentID": fulfillmentID ?: @"",
            @"expectedStatus": expectedStatus ?: @"",
            @"targetStatus": status ?: @"",
            @"reason": reason ?: @"",
            @"note": note ?: @"",
            @"notifyCustomer": @(notify),
            @"commandId": commandID ?: @""
        } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
            if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
                if (completion) completion(nil, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
                return;
            }
            NSDictionary *dict = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : nil;
            if (completion) completion(dict, error);
        }];
    }];
}

- (void)transitionOfficialFulfillment:(PPFulfillmentRecord *)record
                       expectedStatus:(NSString *)expectedStatus
                                action:(NSString *)action
                                  note:(NSString *)note
                             commandID:(NSString *)commandID
                            completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *safeExpectedStatus = [expectedStatus.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeAction = [action.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeNote = [note stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeCommandID = [commandID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![staff hasPermission:kStaffPermPaymentsManage] || !PPFulfillmentHasReadableScope(staff)) {
        if (completion) completion(nil, PPFulfillmentReadError([staff hasPermission:kStaffPermPaymentsManage] ? 411 : 410,
                                                               [staff hasPermission:kStaffPermPaymentsManage] ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission"));
        return;
    }
    if (![PPFulfillmentService isOfficialPlatformFulfillment:record] ||
        !record.fulfillmentID.length || !record.parentOrderID.length) {
        if (completion) completion(nil, PPFulfillmentReadError(415, @"PaymentMgmt_OfficialFulfillment_NotManageable"));
        return;
    }
    if (!safeExpectedStatus.length || ![safeExpectedStatus isEqualToString:record.status.lowercaseString] ||
        ![[PPFulfillmentService availableOfficialActionsForStatus:safeExpectedStatus] containsObject:safeAction] ||
        safeNote.length < 3 || !safeCommandID.length) {
        if (completion) completion(nil, PPFulfillmentReadError(416, @"PaymentMgmt_OfficialFulfillment_InvalidCommand"));
        return;
    }

    FIRDocumentReference *fulfillmentRef = [[[FIRFirestore firestore] collectionWithPath:@"FulfillmentOrders"] documentWithPath:record.fulfillmentID];
    [fulfillmentRef getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *readError) {
        if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
            if (completion) completion(nil, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (readError || !snapshot.exists) {
            if (completion) completion(nil, readError ?: PPFulfillmentReadError(404, @"PaymentMgmt_OfficialFulfillment_NotManageable"));
            return;
        }
        PPFulfillmentRecord *freshRecord = [[PPFulfillmentRecord alloc] initWithDictionary:snapshot.data documentID:snapshot.documentID];
        if (![freshRecord.parentOrderID isEqualToString:record.parentOrderID] ||
            ![PPFulfillmentService isOfficialPlatformFulfillment:freshRecord] ||
            !PPFulfillmentStaffCanReachData(staff, snapshot.data)) {
            if (completion) completion(nil, PPFulfillmentReadError(415, @"PaymentMgmt_OfficialFulfillment_NotManageable"));
            return;
        }

        FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:@"staffTransitionOfficialFulfillment"];
        [callable callWithObject:@{
            @"fulfillmentID": freshRecord.fulfillmentID,
            @"expectedStatus": safeExpectedStatus,
            @"action": safeAction,
            @"note": safeNote,
            @"commandId": safeCommandID,
        } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
            if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
                if (completion) completion(nil, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
                return;
            }
            NSDictionary *dict = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : nil;
            if (completion) completion(dict, error);
        }];
    }];
}

- (void)initializeAndTransitionOfficialFulfillmentForOrderID:(NSString *)orderID
                                          expectedParentStatus:(NSString *)expectedParentStatus
                                                        action:(NSString *)action
                                                          note:(NSString *)note
                                                     commandID:(NSString *)commandID
                                                    completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *safeOrderID = [orderID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeExpectedParentStatus = [expectedParentStatus.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeAction = [action.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeNote = [note stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeCommandID = [commandID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![staff hasPermission:kStaffPermPaymentsManage] || !PPFulfillmentHasReadableScope(staff)) {
        if (completion) completion(nil, PPFulfillmentReadError([staff hasPermission:kStaffPermPaymentsManage] ? 411 : 410,
                                                               [staff hasPermission:kStaffPermPaymentsManage] ? @"PPOrder_Error_MissingReadScope" : @"PPOrder_Error_NoReadPermission"));
        return;
    }
    if (!safeOrderID.length || !safeExpectedParentStatus.length ||
        ![[PPFulfillmentService availableOfficialActionsForStatus:@"new_request"] containsObject:safeAction] ||
        safeNote.length < 3 || !safeCommandID.length) {
        if (completion) completion(nil, PPFulfillmentReadError(416, @"PaymentMgmt_OfficialFulfillment_InvalidCommand"));
        return;
    }

    FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:@"staffInitializeAndTransitionOfficialFulfillment"];
    [callable callWithObject:@{
        @"orderId": safeOrderID,
        @"expectedParentStatus": safeExpectedParentStatus,
        @"action": safeAction,
        @"note": safeNote,
        @"commandId": safeCommandID,
    } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (!PPFulfillmentStaffSessionIsCurrent(staff)) {
            if (completion) completion(nil, PPFulfillmentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        NSDictionary *dict = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : nil;
        if (completion) completion(dict, error);
    }];
}

- (BOOL)canAdminOverride {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [staff hasPermission:kStaffPermPaymentsManage] && PPFulfillmentHasReadableScope(staff);
}

+ (NSArray<NSString *> *)allowedOverrideTargetsForStatus:(NSString *)currentStatus {
    if (!currentStatus.length) return @[];
    NSDictionary *transitions = @{
        @"new_request": @[@"accepted", @"rejected", @"cancelled"],
        @"accepted": @[@"preparing", @"cancelled"],
        @"preparing": @[@"ready_for_pickup", @"cancelled"],
        @"ready_for_pickup": @[@"delivery_requested", @"cancelled"],
        @"delivery_requested": @[@"cancelled"],
        @"delivery_assigned": @[@"awaiting_handover", @"cancelled"],
        @"awaiting_handover": @[@"handed_over", @"cancelled"],
        @"handed_over": @[@"in_transit"]
    };
    return transitions[currentStatus] ?: @[];
}

+ (BOOL)isOfficialPlatformFulfillment:(PPFulfillmentRecord *)record {
    if (![record isKindOfClass:PPFulfillmentRecord.class]) return NO;
    NSString *ownerType = record.ownerType.lowercaseString ?: @"";
    NSString *mode = record.fulfillmentMode.lowercaseString ?: @"";
    return [ownerType isEqualToString:@"platform"] &&
           [record.ownerID isEqualToString:PPFulfillmentOfficialOwnerID] &&
           (mode.length == 0 || [mode isEqualToString:@"platform_managed"]);
}

+ (NSArray<NSString *> *)availableOfficialActionsForStatus:(NSString *)currentStatus {
    NSString *status = currentStatus.lowercaseString ?: @"";
    NSDictionary<NSString *, NSArray<NSString *> *> *transitions = @{
        @"new_request": @[@"accept", @"reject", @"cancel_request"],
        @"accepted": @[@"start_preparing", @"cancel_request"],
        @"preparing": @[@"mark_ready", @"cancel_request"],
        @"ready_for_pickup": @[@"request_delivery", @"cancel_request"],
        @"delivery_requested": @[@"cancel_request"],
        @"delivery_assigned": @[@"confirm_handover", @"cancel_request"],
        @"awaiting_handover": @[@"cancel_request"],
    };
    return transitions[status] ?: @[];
}

@end
