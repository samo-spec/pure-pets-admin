#import "PPPaymentManagementService.h"
#import "UserManager.h"
#import "UserModel.h"
#import "PPRolePermission.h"
#import "PPStaffAuth.h"
#import "Language.h"

static NSString * const PPPaymentAdminServiceErrorDomain = @"PPPaymentAdminService";
static NSString * const PPPaymentPartialReadMarkerKey = @"PPPaymentPartialRead";
static NSUInteger const PPPaymentAdminScopeChunkLimit = 30;

static NSError *PPPaymentReadError(NSInteger code, NSString *localizationKey)
{
    return [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: kLang(localizationKey)}];
}

static NSError *PPPaymentPartialReadError(NSError *underlyingError,
                                          NSUInteger successfulQueryCount,
                                          NSUInteger queryCount)
{
    NSMutableDictionary *userInfo = [@{
        NSLocalizedDescriptionKey: kLang(@"PPOrder_Error_PartialRead"),
        PPPaymentPartialReadMarkerKey: @YES,
        @"successfulQueryCount": @(successfulQueryCount),
        @"queryCount": @(queryCount),
    } mutableCopy];
    if (underlyingError) userInfo[NSUnderlyingErrorKey] = underlyingError;
    return [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain code:414 userInfo:userInfo];
}

static NSArray<NSString *> *PPPaymentCanonicalScopeIDs(PPStaffDoc *staff, NSString *key)
{
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

static BOOL PPPaymentHasReadableScope(PPStaffDoc *staff)
{
    return (staff.isActive && (staff.isAdmin || staff.hasGlobalScope ||
            PPPaymentCanonicalScopeIDs(staff, @"branchIds").count > 0 ||
            PPPaymentCanonicalScopeIDs(staff, @"regionIds").count > 0));
}

static BOOL PPPaymentStaffSessionIsCurrent(PPStaffDoc *staff)
{
    PPStaffDoc *current = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *authUID = [FIRAuth auth].currentUser.uid;
    return (staff != nil && current == staff && authUID.length > 0 &&
            [staff.uid isEqualToString:authUID] && staff.isActive);
}

static BOOL PPPaymentStaffCanReachData(PPStaffDoc *staff, NSDictionary *data)
{
    if (!PPPaymentStaffSessionIsCurrent(staff) || ![data isKindOfClass:NSDictionary.class]) return NO;
    if (staff.isAdmin || staff.hasGlobalScope) return YES;
    NSString *branchID = [data[@"branchId"] isKindOfClass:NSString.class]
        ? [(NSString *)data[@"branchId"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    NSString *regionID = [data[@"regionId"] isKindOfClass:NSString.class]
        ? [(NSString *)data[@"regionId"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    return ((branchID.length > 0 && [PPPaymentCanonicalScopeIDs(staff, @"branchIds") containsObject:branchID]) ||
            (regionID.length > 0 && [PPPaymentCanonicalScopeIDs(staff, @"regionIds") containsObject:regionID]));
}

static BOOL PPPaymentStaffCanReachRecord(PPStaffDoc *staff, PPPaymentAdminRecord *record)
{
    return PPPaymentStaffCanReachData(staff, @{
        @"branchId": record.branchId ?: @"",
        @"regionId": record.regionId ?: @"",
    });
}

static BOOL PPPaymentCanReadUnscopedAudit(PPStaffDoc *staff)
{
    return PPPaymentStaffSessionIsCurrent(staff) &&
           (staff.isAdmin || staff.hasGlobalScope) &&
           [staff hasPermission:kStaffPermAuditView];
}

static BOOL PPPaymentCursorIsValid(FIRDocumentSnapshot *cursor)
{
    return cursor == nil ||
           (cursor.documentID.length > 0 && [cursor.data[@"updatedAt"] isKindOfClass:FIRTimestamp.class]);
}

static FIRQuery *PPPaymentQueryStartingAfterCursor(FIRQuery *query, FIRDocumentSnapshot *cursor)
{
    if (!cursor) return query;
    return [query queryStartingAfterValues:@[cursor.data[@"updatedAt"], cursor.documentID]];
}

static NSArray<FIRDocumentSnapshot *> *PPPaymentMergeOrderDocuments(NSArray<NSArray<FIRDocumentSnapshot *> *> *groups,
                                                                    NSInteger limit,
                                                                    BOOL *truncated)
{
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
    NSInteger resolvedLimit = MAX(1, limit);
    if (truncated) *truncated = sorted.count > (NSUInteger)resolvedLimit;
    return sorted.count > (NSUInteger)resolvedLimit
        ? [sorted subarrayWithRange:NSMakeRange(0, resolvedLimit)]
        : sorted;
}

@interface PPPaymentManagementService ()

@property (nonatomic, strong) FIRFirestore *db;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *userSummaryCache;

- (FIRFunctions *)pp_functionsClient;
- (void)pp_callAdminTransitionAction:(NSString *)action
                             orderID:(NSString *)orderID
                                note:(NSString *)note
                          completion:(PPPaymentAdminRecordCompletion)completion;
- (void)pp_completeSettings:(PPPaymentAdminSettings *)settings
                      error:(NSError *)error
                 completion:(PPPaymentAdminSettingsCompletion)completion;
- (NSArray<FIRQuery *> *)pp_baseOrdersQueriesForFilters:(PPPaymentManagementFilters *)filters
                                                   staff:(PPStaffDoc *)staff;
- (void)pp_fetchRequestSummariesForOrderID:(NSString *)orderID
                                      staff:(PPStaffDoc *)staff
                                 completion:(void (^)(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error))completion;
- (void)pp_fetchAllRequestsForOrderID:(NSString *)orderID
                                staff:(PPStaffDoc *)staff
                           completion:(void (^)(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error))completion;
- (void)pp_fetchTimelineForOrderID:(NSString *)orderID
                             staff:(PPStaffDoc *)staff
                        completion:(void (^)(NSArray<PPPaymentAdminTimelineEvent *> *events, NSError * _Nullable error))completion;
- (void)pp_fetchAuditEntriesForOrderID:(NSString *)orderID
                                  staff:(PPStaffDoc *)staff
                             completion:(void (^)(NSArray<PPPaymentAdminAuditEntry *> *entries, NSError * _Nullable error))completion;

@end

@implementation PPPaymentManagementService

+ (instancetype)shared
{
    static PPPaymentManagementService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [PPPaymentManagementService new];
    });
    return service;
}

+ (BOOL)isPartialReadError:(NSError *)error
{
    return [error.domain isEqualToString:PPPaymentAdminServiceErrorDomain] &&
           [error.userInfo[PPPaymentPartialReadMarkerKey] boolValue];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _db = [FIRFirestore firestore];
        _userSummaryCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)currentAdminCanManagePayments
{
    return [[[PPStaffAuth shared] cachedCurrentStaff] hasPermission:kStaffPermPaymentsManage];
}

- (BOOL)currentAdminCanViewPayments
{
    PPStaffDoc *staff = [[PPStaffAuth shared] cachedCurrentStaff];
    return ([staff hasPermission:kStaffPermPaymentsView] ||
            [staff hasPermission:kStaffPermPaymentsManage]);
}

- (BOOL)currentAdminCanRefundPayments
{
    return [[[PPStaffAuth shared] cachedCurrentStaff] hasPermission:kStaffPermPaymentsRefund];
}

- (void)fetchOrdersWithFilters:(PPPaymentManagementFilters *)filters
                      pageSize:(NSInteger)pageSize
                    startAfter:(FIRDocumentSnapshot *)startAfter
                    completion:(PPPaymentAdminRecordsCompletion)completion
{
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]]) {
        [self pp_completeRecords:@[]
                      nextCursor:nil
                           error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                    code:400
                                                userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoViewPaymentsPermission")}]
                      completion:completion];
        return;
    }
    if (!PPPaymentHasReadableScope(staff)) {
        [self pp_completeRecords:@[]
                      nextCursor:nil
                           error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                    code:409
                                                userInfo:@{NSLocalizedDescriptionKey: kLang(@"PPOrder_Error_MissingReadScope")}]
                      completion:completion];
        return;
    }
    if (!PPPaymentCursorIsValid(startAfter)) {
        [self pp_completeRecords:@[]
                      nextCursor:nil
                           error:PPPaymentReadError(410, @"PPOrder_Error_InvalidCursor")
                      completion:completion];
        return;
    }

    NSInteger resolvedPageSize = MAX(10, MIN(100, pageSize));
    PPPaymentManagementFilters *resolvedFilters = filters ? [filters copy] : [PPPaymentManagementFilters defaultFilters];
    NSArray<FIRQuery *> *baseQueries = [self pp_baseOrdersQueriesForFilters:resolvedFilters staff:staff];
    NSMutableArray<PPPaymentAdminRecord *> *collected = [NSMutableArray array];
    __block FIRDocumentSnapshot *cursor = startAfter;
    __block BOOL exhausted = NO;
    __block NSInteger fetchCount = 0;
    BOOL hasSearch = ([self pp_trimmedString:resolvedFilters.searchText].length > 0);
    BOOL hasCustomFilters = ![resolvedFilters isDefaultState];
    NSInteger maxFetchPasses = hasSearch ? 12 : (hasCustomFilters ? 8 : 5);
    __weak typeof(self) weakSelf = self;

    __block void (^fetchNextBatch)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(@[], nil, [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                                     code:900
                                                                 userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_ServiceReleased")}]);
            return;
        }

        if (exhausted || collected.count >= resolvedPageSize || fetchCount >= maxFetchPasses) {
            FIRDocumentSnapshot *nextCursor = exhausted ? nil : cursor;
            [strongSelf pp_completeRecords:collected nextCursor:nextCursor error:nil completion:completion];
            return;
        }

        fetchCount += 1;
        NSInteger batchLimit = MAX(resolvedPageSize * 2, 40);
        dispatch_group_t queryGroup = dispatch_group_create();
        NSMutableArray<NSArray<FIRDocumentSnapshot *> *> *queryDocuments = [NSMutableArray arrayWithCapacity:baseQueries.count];
        for (NSUInteger index = 0; index < baseQueries.count; index++) [queryDocuments addObject:@[]];
        __block NSError *queryError = nil;
        __block NSUInteger successfulQueryCount = 0;
        __block BOOL allQueriesExhausted = YES;
        [baseQueries enumerateObjectsUsingBlock:^(FIRQuery *baseQuery, NSUInteger index, BOOL *stop) {
            FIRQuery *query = [baseQuery queryLimitedTo:batchLimit];
            query = PPPaymentQueryStartingAfterCursor(query, cursor);
            dispatch_group_enter(queryGroup);
            [query getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
                @synchronized (queryDocuments) {
                    if (error && !queryError) queryError = error;
                    if (!error) {
                        successfulQueryCount += 1;
                        NSArray<FIRDocumentSnapshot *> *batch = snapshot.documents ?: @[];
                        queryDocuments[index] = batch;
                        if (batch.count >= (NSUInteger)batchLimit) allQueriesExhausted = NO;
                    }
                }
                dispatch_group_leave(queryGroup);
            }];
        }];

        dispatch_group_notify(queryGroup, dispatch_get_main_queue(), ^{
            if (!PPPaymentStaffSessionIsCurrent(staff)) {
                [strongSelf pp_completeRecords:@[] nextCursor:nil error:PPPaymentReadError(412, @"PPOrder_Error_SessionChanged") completion:completion];
                return;
            }
            BOOL isPartialResult = queryError != nil && successfulQueryCount > 0;
            if (queryError && !isPartialResult) {
                [strongSelf pp_completeRecords:@[] nextCursor:nil error:queryError completion:completion];
                return;
            }
            NSError *partialError = isPartialResult
                ? PPPaymentPartialReadError(queryError, successfulQueryCount, baseQueries.count)
                : nil;

            BOOL mergeTruncated = NO;
            NSArray<FIRDocumentSnapshot *> *documents = PPPaymentMergeOrderDocuments(queryDocuments, batchLimit, &mergeTruncated);
            if (documents.count == 0) {
                exhausted = YES;
                [strongSelf pp_completeRecords:collected nextCursor:nil error:partialError completion:completion];
                return;
            }

            NSMutableArray<PPPaymentAdminRecord *> *batchRecords = [NSMutableArray arrayWithCapacity:documents.count];
            for (FIRDocumentSnapshot *doc in documents) {
                PPPaymentAdminRecord *record = [PPPaymentAdminRecord recordFromSnapshot:doc];
                if (record.orderId.length == 0) continue;
                [batchRecords addObject:record];
            }

            [strongSelf pp_resolveUsersForRecords:batchRecords completion:^{
                [strongSelf refreshRequestSummariesForRecords:batchRecords completion:^(__unused NSArray<PPPaymentAdminRecord *> *recordsWithSummaries) {
                    if (!PPPaymentStaffSessionIsCurrent(staff)) {
                        [strongSelf pp_completeRecords:@[] nextCursor:nil error:PPPaymentReadError(412, @"PPOrder_Error_SessionChanged") completion:completion];
                        return;
                    }
                    NSUInteger lastExaminedIndex = NSNotFound;
                    for (NSUInteger index = 0; index < batchRecords.count; index++) {
                        PPPaymentAdminRecord *record = batchRecords[index];
                        lastExaminedIndex = index;
                        if ([record matchesFilters:resolvedFilters]) {
                            [collected addObject:record];
                        }
                        if (collected.count >= resolvedPageSize) {
                            break;
                        }
                    }

                    if (lastExaminedIndex != NSNotFound) cursor = documents[lastExaminedIndex];
                    BOOL hasUnexaminedDocuments = (lastExaminedIndex != NSNotFound &&
                                                   lastExaminedIndex + 1 < documents.count);
                    BOOL sourceHasMore = mergeTruncated || !allQueriesExhausted;
                    exhausted = !hasUnexaminedDocuments && !sourceHasMore;

                    if (isPartialResult) {
                        [strongSelf pp_completeRecords:collected nextCursor:nil error:partialError completion:completion];
                        return;
                    }

                    if (collected.count >= resolvedPageSize || exhausted) {
                        FIRDocumentSnapshot *nextCursor = exhausted ? nil : cursor;
                        [strongSelf pp_completeRecords:collected nextCursor:nextCursor error:nil completion:completion];
                        return;
                    }

                    fetchNextBatch();
                }];
            }];
        });
    };

    fetchNextBatch();
}

- (void)refreshRequestSummariesForRecords:(NSArray<PPPaymentAdminRecord *> *)records
                               completion:(void (^)(NSArray<PPPaymentAdminRecord *> *records))completion
{
    if (records.count == 0) {
        if (completion) completion(@[]);
        return;
    }

    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]] ||
        !PPPaymentHasReadableScope(staff) || !PPPaymentStaffSessionIsCurrent(staff)) {
        if (completion) completion(records);
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    __weak typeof(self) weakSelf = self;
    for (PPPaymentAdminRecord *record in records) {
        if (record.orderId.length == 0 || !PPPaymentStaffCanReachRecord(staff, record)) continue;
        dispatch_group_enter(group);
        [self pp_fetchRequestSummariesForOrderID:record.orderId staff:staff completion:^(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            (void)strongSelf;
            if (!error) {
                [record applyRequestSummaries:requests];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) completion(records);
    });
}

- (void)loadFullRecordForOrderID:(NSString *)orderID
                      completion:(PPPaymentAdminRecordCompletion)completion
{
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:401
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoViewPaymentDetailsPermission")}]
                     completion:completion];
        return;
    }
    if (!PPPaymentHasReadableScope(staff)) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:409
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PPOrder_Error_MissingReadScope")}]
                     completion:completion];
        return;
    }

    NSString *resolvedOrderID = [self pp_trimmedString:orderID];
    if (resolvedOrderID.length == 0) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:101
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_MissingOrderID")}]
                     completion:completion];
        return;
    }

    FIRDocumentReference *orderRef = [[self.db collectionWithPath:@"Orders"] documentWithPath:resolvedOrderID];
    [orderRef getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (!PPPaymentStaffSessionIsCurrent(staff)) {
            [self pp_completeRecord:nil error:PPPaymentReadError(412, @"PPOrder_Error_SessionChanged") completion:completion];
            return;
        }
        if (error) {
            [self pp_completeRecord:nil error:error completion:completion];
            return;
        }
        if (!snapshot.exists) {
            [self pp_completeRecord:nil
                              error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                       code:102
                                                   userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_OrderNotFound")}]
                         completion:completion];
            return;
        }

        PPPaymentAdminRecord *record = [PPPaymentAdminRecord recordFromSnapshot:snapshot];
        if (!PPPaymentStaffCanReachRecord(staff, record)) {
            [self pp_completeRecord:nil error:PPPaymentReadError(409, @"PPOrder_Error_MissingReadScope") completion:completion];
            return;
        }
        dispatch_group_t group = dispatch_group_create();

        dispatch_group_enter(group);
        [self pp_resolveUsersForRecords:@[record] completion:^{
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [self pp_fetchAllRequestsForOrderID:record.orderId staff:staff completion:^(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable requestsError) {
            if (!requestsError) {
                [record applyRequestSummaries:requests];
            }
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [self pp_fetchTimelineForOrderID:record.orderId staff:staff completion:^(NSArray<PPPaymentAdminTimelineEvent *> *events, NSError * _Nullable timelineError) {
            if (!timelineError) {
                record.timelineEvents = events ?: @[];
            }
            dispatch_group_leave(group);
        }];

        if (PPPaymentCanReadUnscopedAudit(staff)) {
            dispatch_group_enter(group);
            [self pp_fetchAuditEntriesForOrderID:record.orderId staff:staff completion:^(NSArray<PPPaymentAdminAuditEntry *> *entries, NSError * _Nullable auditError) {
                if (!auditError) record.auditEntries = entries ?: @[];
                else record.auditEvidenceRestricted = YES;
                dispatch_group_leave(group);
            }];
        } else {
            record.auditEntries = @[];
            record.auditEvidenceRestricted = YES;
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (!PPPaymentStaffSessionIsCurrent(staff)) {
                [self pp_completeRecord:nil error:PPPaymentReadError(412, @"PPOrder_Error_SessionChanged") completion:completion];
                return;
            }
            [self pp_completeRecord:record error:nil completion:completion];
        });
    }];
}

- (void)loadEventsForRequest:(PPPaymentAdminSupportRequest *)request
                   completion:(PPPaymentAdminRequestEventsCompletion)completion
{
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage, kStaffPermPaymentsRefund]]) {
        if (completion) completion(@[], PPPaymentReadError(410, @"PPOrder_Error_NoReadPermission"));
        return;
    }
    if (!PPPaymentHasReadableScope(staff)) {
        if (completion) completion(@[], PPPaymentReadError(411, @"PPOrder_Error_MissingReadScope"));
        return;
    }
    NSString *orderID = [self pp_trimmedString:request.orderId];
    NSString *requestID = [self pp_trimmedString:request.requestId];
    if (orderID.length == 0 || requestID.length == 0) {
        if (completion) completion(@[], [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                            code:103
                                                        userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_MissingRequestReference")}]);
        return;
    }

    FIRDocumentReference *orderRef = [[self.db collectionWithPath:@"Orders"] documentWithPath:orderID];
    [orderRef getDocumentWithCompletion:^(FIRDocumentSnapshot *orderSnapshot, NSError *orderError) {
        if (!PPPaymentStaffSessionIsCurrent(staff)) {
            if (completion) completion(@[], PPPaymentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (orderError || !orderSnapshot.exists) {
            if (completion) completion(@[], orderError ?: PPPaymentReadError(404, @"PaymentMgmt_Error_OrderNotFound"));
            return;
        }
        if (!PPPaymentStaffCanReachData(staff, orderSnapshot.data)) {
            if (completion) completion(@[], PPPaymentReadError(409, @"PPOrder_Error_MissingReadScope"));
            return;
        }
        FIRQuery *query = [[[[orderRef collectionWithPath:@"requests"]
                              documentWithPath:requestID]
                             collectionWithPath:@"events"]
                            queryOrderedByField:@"createdAt" descending:NO];
        query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:NO];
        [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (!PPPaymentStaffSessionIsCurrent(staff)) {
                if (completion) completion(@[], PPPaymentReadError(412, @"PPOrder_Error_SessionChanged"));
                return;
            }
            if (error) {
                if (completion) completion(@[], error);
                return;
            }
            NSMutableArray<PPPaymentAdminTimelineEvent *> *events = [NSMutableArray array];
            for (FIRDocumentSnapshot *doc in snapshot.documents ?: @[]) {
                [events addObject:[PPPaymentAdminTimelineEvent eventFromSnapshot:doc]];
            }
            if (completion) completion(events.copy, nil);
        }];
    }];
}

- (void)loadPaymentSettingsWithCompletion:(PPPaymentAdminSettingsCompletion)completion
{
    if (![self currentAdminCanViewPayments]) {
        [self pp_completeSettings:nil
                            error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                     code:401
                                                 userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoViewPaymentsPermission")}]
                       completion:completion];
        return;
    }

    FIRDocumentReference *settingsRef = [[self.db collectionWithPath:@"CommerceConfig"] documentWithPath:@"payments"];
    [settingsRef getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            [self pp_completeSettings:nil error:error completion:completion];
            return;
        }

        PPPaymentAdminSettings *settings = [PPPaymentAdminSettings settingsFromDictionary:[snapshot.data isKindOfClass:NSDictionary.class] ? snapshot.data : @{}];
        [self pp_completeSettings:settings error:nil completion:completion];
    }];
}

- (void)savePaymentSettings:(PPPaymentAdminSettings *)settings
                 completion:(PPPaymentAdminSettingsCompletion)completion
{
    if (![self currentAdminCanManagePayments]) {
        [self pp_completeSettings:nil
                            error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                     code:401
                                                 userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoViewPaymentsPermission")}]
                       completion:completion];
        return;
    }
    if (!settings) {
        [self pp_completeSettings:nil
                            error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                     code:400
                                                 userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Settings_Error_InvalidDeliveryFee")}]
                       completion:completion];
        return;
    }

    FIRHTTPSCallable *callable = [[self pp_functionsClient] HTTPSCallableWithName:@"updateCommercePaymentSettings"];
    NSDictionary *payload = @{
        @"deliveryFee": @(MAX(0.0, settings.deliveryFee)),
        @"cashOnDeliveryEnabled": @(settings.cashOnDeliveryEnabled),
        @"onlinePaymentEnabled": @(settings.onlinePaymentEnabled),
    };

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            [self pp_completeSettings:nil error:error completion:completion];
            return;
        }

        NSDictionary *data = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : @{};
        NSDictionary *settingsDict = [data[@"settings"] isKindOfClass:NSDictionary.class] ? data[@"settings"] : data;
        PPPaymentAdminSettings *resolved = [PPPaymentAdminSettings settingsFromDictionary:settingsDict];
        [self pp_completeSettings:resolved error:nil completion:completion];
    }];
}

- (void)approveOrder:(PPPaymentAdminRecord *)record
                note:(NSString *)note
          completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_approve"
                    note:note
              completion:completion];
}

- (void)markOrderProcessing:(PPPaymentAdminRecord *)record
                       note:(NSString *)note
                 completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_mark_processing"
                    note:note
              completion:completion];
}

- (void)markOrderShipped:(PPPaymentAdminRecord *)record
                    note:(NSString *)note
              completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_mark_shipped"
                    note:note
              completion:completion];
}

- (void)markOrderDelivered:(PPPaymentAdminRecord *)record
                      note:(NSString *)note
                completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_mark_delivered"
                    note:note
              completion:completion];
}

- (void)cancelOrder:(PPPaymentAdminRecord *)record
               note:(NSString *)note
         completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_cancel"
                    note:note
              completion:completion];
}

- (void)collectOrderPayment:(PPPaymentAdminRecord *)record
                       note:(NSString *)note
                 completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_collect_payment"
                    note:note
              completion:completion];
}

- (void)resolveRequest:(PPPaymentAdminSupportRequest *)request
              forOrder:(PPPaymentAdminRecord *)record
                action:(PPPaymentAdminRequestResolution)action
                  note:(NSString *)note
                amount:(NSNumber *)amount
            completion:(PPPaymentAdminRecordCompletion)completion
{
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasPermission:kStaffPermPaymentsManage]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:401
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoManagePermission")}]
                     completion:completion];
        return;
    }
    if (!PPPaymentHasReadableScope(staff) || !PPPaymentStaffCanReachRecord(staff, record)) {
        [self pp_completeRecord:nil
                          error:PPPaymentReadError(411, @"PPOrder_Error_MissingReadScope")
                     completion:completion];
        return;
    }
    if ((action == PPPaymentAdminRequestResolutionRefund ||
         action == PPPaymentAdminRequestResolutionPartialRefund) &&
        ![staff hasPermission:kStaffPermPaymentsRefund]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:403
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoRefundPermission")}]
                     completion:completion];
        return;
    }

    NSString *resolvedOrderID = [self pp_trimmedString:record.orderId];
    NSString *resolvedRequestID = [self pp_trimmedString:request.requestId];
    NSString *requestOrderID = [self pp_trimmedString:request.orderId];
    if (resolvedOrderID.length == 0 || resolvedRequestID.length == 0) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:104
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_MissingRequestReference")}]
                     completion:completion];
        return;
    }
    if (requestOrderID.length > 0 && ![requestOrderID isEqualToString:resolvedOrderID]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:106
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_MissingRequestReference")}]
                     completion:completion];
        return;
    }

    if (![self pp_noteIsAcceptable:note]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:105
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_AdminNoteRequired")}]
                     completion:completion];
        return;
    }

    NSString *actionKey = [self pp_resolutionActionKey:action];
    NSString *noteCode = [NSString stringWithFormat:@"payment.request.%@", [self pp_trimmedString:actionKey]];
    NSMutableDictionary *payload = [@{
        @"orderId": resolvedOrderID,
        @"requestId": resolvedRequestID,
        @"action": actionKey,
        @"note": [self pp_trimmedString:note],
        @"noteCode": noteCode,
    } mutableCopy];
    if (amount != nil) {
        payload[@"amount"] = amount;
    }
    if ((action == PPPaymentAdminRequestResolutionRefund ||
         action == PPPaymentAdminRequestResolutionPartialRefund) &&
        record.currency.length > 0) {
        payload[@"currency"] = record.currency;
    }

    NSLog(@"PPLAB admin request mutation route=callable orderId=%@ requestId=%@ action=%@", resolvedOrderID, resolvedRequestID, actionKey);
    FIRHTTPSCallable *callable = [[self pp_functionsClient] HTTPSCallableWithName:@"adminResolvePaymentRequest"];
    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"PPLAB admin request mutation failed orderId=%@ requestId=%@ action=%@ code=%ld", resolvedOrderID, resolvedRequestID, actionKey, (long)error.code);
            [self pp_completeRecord:nil error:error completion:completion];
            return;
        }

        NSDictionary *data = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : @{};
        NSString *orderID = [self pp_trimmedString:data[@"orderId"]];
        if (orderID.length == 0) orderID = resolvedOrderID;
        NSLog(@"PPLAB admin request mutation accepted orderId=%@ requestId=%@ action=%@", orderID, resolvedRequestID, actionKey);
        [self loadFullRecordForOrderID:orderID completion:completion];
    }];
}

#pragma mark - Private Queries

- (NSArray<FIRQuery *> *)pp_baseOrdersQueriesForFilters:(PPPaymentManagementFilters *)filters
                                                   staff:(PPStaffDoc *)staff
{
    FIRCollectionReference *collection = [self.db collectionWithPath:@"Orders"];
    NSMutableArray<FIRQuery *> *queries = [NSMutableArray array];
    if (staff.isAdmin || staff.hasGlobalScope) {
        [queries addObject:collection];
    } else {
        NSDictionary<NSString *, NSArray<NSString *> *> *scope = @{
            @"branchId": PPPaymentCanonicalScopeIDs(staff, @"branchIds"),
            @"regionId": PPPaymentCanonicalScopeIDs(staff, @"regionIds"),
        };
        for (NSString *field in @[@"branchId", @"regionId"]) {
            NSArray<NSString *> *ids = scope[field];
            for (NSUInteger offset = 0; offset < ids.count; offset += PPPaymentAdminScopeChunkLimit) {
                NSRange range = NSMakeRange(offset, MIN(PPPaymentAdminScopeChunkLimit, ids.count - offset));
                [queries addObject:[collection queryWhereField:field in:[ids subarrayWithRange:range]]];
            }
        }
    }

    NSDate *floorDate = [self pp_floorDateForRange:filters.dateRange];
    NSMutableArray<FIRQuery *> *orderedQueries = [NSMutableArray arrayWithCapacity:queries.count];
    for (FIRQuery *baseQuery in queries) {
        FIRQuery *query = baseQuery;
        if (floorDate) {
            query = [query queryWhereField:@"updatedAt"
                   isGreaterThanOrEqualTo:[FIRTimestamp timestampWithDate:floorDate]];
        }
        query = [query queryOrderedByField:@"updatedAt" descending:YES];
        query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
        [orderedQueries addObject:query];
    }
    return orderedQueries.copy;
}

- (NSDate *)pp_floorDateForRange:(PPPaymentAdminDateRange)dateRange
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    switch (dateRange) {
        case PPPaymentAdminDateRangeToday: {
            NSDate *startOfToday = nil;
            [calendar rangeOfUnit:NSCalendarUnitDay startDate:&startOfToday interval:NULL forDate:now];
            return startOfToday;
        }
        case PPPaymentAdminDateRangeLast7Days:
            return [calendar dateByAddingUnit:NSCalendarUnitDay value:-7 toDate:now options:0];
        case PPPaymentAdminDateRangeLast30Days:
            return [calendar dateByAddingUnit:NSCalendarUnitDay value:-30 toDate:now options:0];
        case PPPaymentAdminDateRangeLast90Days:
            return [calendar dateByAddingUnit:NSCalendarUnitDay value:-90 toDate:now options:0];
        case PPPaymentAdminDateRangeAll:
            break;
    }
    return nil;
}

- (void)pp_fetchRequestSummariesForOrderID:(NSString *)orderID
                                      staff:(PPStaffDoc *)staff
                                completion:(void (^)(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error))completion
{
    FIRQuery *query = [[[[self.db collectionWithPath:@"Orders"]
                         documentWithPath:orderID]
                        collectionWithPath:@"requests"]
                       queryOrderedByField:@"updatedAt" descending:YES];
    query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
    query = [query queryLimitedTo:6];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (!PPPaymentStaffSessionIsCurrent(staff)) {
            if (completion) completion(@[], PPPaymentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray<PPPaymentAdminSupportRequest *> *requests = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents ?: @[]) {
            PPPaymentAdminSupportRequest *request = [PPPaymentAdminSupportRequest requestFromSnapshot:doc];
            if (request.orderId.length == 0) request.orderId = orderID;
            if ([request.orderId isEqualToString:orderID]) [requests addObject:request];
        }
        if (completion) completion(requests.copy, nil);
    }];
}

- (void)pp_fetchAllRequestsForOrderID:(NSString *)orderID
                                staff:(PPStaffDoc *)staff
                           completion:(void (^)(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error))completion
{
    FIRQuery *query = [[[[self.db collectionWithPath:@"Orders"]
                         documentWithPath:orderID]
                        collectionWithPath:@"requests"]
                       queryOrderedByField:@"updatedAt" descending:YES];
    query = [query queryOrderedByFieldPath:[FIRFieldPath documentID] descending:YES];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (!PPPaymentStaffSessionIsCurrent(staff)) {
            if (completion) completion(@[], PPPaymentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray<PPPaymentAdminSupportRequest *> *requests = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents ?: @[]) {
            PPPaymentAdminSupportRequest *request = [PPPaymentAdminSupportRequest requestFromSnapshot:doc];
            if (request.orderId.length == 0) request.orderId = orderID;
            if ([request.orderId isEqualToString:orderID]) [requests addObject:request];
        }
        if (completion) completion(requests.copy, nil);
    }];
}

- (void)pp_fetchTimelineForOrderID:(NSString *)orderID
                             staff:(PPStaffDoc *)staff
                        completion:(void (^)(NSArray<PPPaymentAdminTimelineEvent *> *events, NSError * _Nullable error))completion
{
    FIRQuery *query = [[[[self.db collectionWithPath:@"Orders"]
                         documentWithPath:orderID]
                        collectionWithPath:@"events"]
                       queryOrderedByField:@"createdAt" descending:NO];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (!PPPaymentStaffSessionIsCurrent(staff)) {
            if (completion) completion(@[], PPPaymentReadError(412, @"PPOrder_Error_SessionChanged"));
            return;
        }
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray<PPPaymentAdminTimelineEvent *> *events = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents ?: @[]) {
            [events addObject:[PPPaymentAdminTimelineEvent eventFromSnapshot:doc]];
        }
        if (completion) completion(events.copy, nil);
    }];
}

- (void)pp_fetchAuditEntriesForOrderID:(NSString *)orderID
                                  staff:(PPStaffDoc *)staff
                            completion:(void (^)(NSArray<PPPaymentAdminAuditEntry *> *entries, NSError * _Nullable error))completion
{
    if (!PPPaymentCanReadUnscopedAudit(staff)) {
        if (completion) completion(@[], PPPaymentReadError(413, @"PPOrder_Error_AuditRestricted"));
        return;
    }
    FIRQuery *query = [[[self.db collectionWithPath:@"AdminAuditLogs"]
                        queryWhereField:@"orderId" isEqualTo:orderID]
                       queryWhereField:@"area" isEqualTo:@"payments"];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (!PPPaymentCanReadUnscopedAudit(staff)) {
            if (completion) completion(@[], PPPaymentReadError(413, @"PPOrder_Error_AuditRestricted"));
            return;
        }
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray<PPPaymentAdminAuditEntry *> *entries = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents ?: @[]) {
            PPPaymentAdminAuditEntry *entry = [PPPaymentAdminAuditEntry auditFromSnapshot:doc];
            if (entry.orderId.length == 0 || [entry.orderId isEqualToString:orderID]) {
                [entries addObject:entry];
            }
        }
        [entries sortUsingComparator:^NSComparisonResult(PPPaymentAdminAuditEntry * _Nonnull left, PPPaymentAdminAuditEntry * _Nonnull right) {
            return [right.createdAt compare:left.createdAt];
        }];
        if (completion) completion(entries.copy, nil);
    }];
}

#pragma mark - Private Mutations

- (void)pp_mutateOrder:(PPPaymentAdminRecord *)record
                action:(NSString *)action
                  note:(NSString *)note
            completion:(PPPaymentAdminRecordCompletion)completion
{
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasPermission:kStaffPermPaymentsManage]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:402
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoManagePermission")}]
                     completion:completion];
        return;
    }
    if (!PPPaymentHasReadableScope(staff) || !PPPaymentStaffCanReachRecord(staff, record)) {
        [self pp_completeRecord:nil
                          error:PPPaymentReadError(411, @"PPOrder_Error_MissingReadScope")
                     completion:completion];
        return;
    }

    NSString *resolvedNote = [self pp_trimmedString:note];
    if (![self pp_noteIsAcceptable:resolvedNote]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:403
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_AdminNoteRequired")}]
                     completion:completion];
        return;
    }

    NSString *orderID = [self pp_trimmedString:record.orderId];
    if (orderID.length == 0) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:404
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_MissingOrderID")}]
                     completion:completion];
        return;
    }

    NSLog(@"PPLAB admin order mutation route=callable orderId=%@ action=%@", orderID, action);
    [self pp_callAdminTransitionAction:action
                               orderID:orderID
                                  note:resolvedNote
                            completion:completion];
}

- (NSString *)pp_resolutionActionKey:(PPPaymentAdminRequestResolution)action
{
    switch (action) {
        case PPPaymentAdminRequestResolutionApprove: return @"approve";
        case PPPaymentAdminRequestResolutionReject: return @"reject";
        case PPPaymentAdminRequestResolutionComplete: return @"complete";
        case PPPaymentAdminRequestResolutionRefund: return @"refund";
        case PPPaymentAdminRequestResolutionPartialRefund: return @"partial_refund";
        case PPPaymentAdminRequestResolutionClose: return @"close";
    }
    return @"approve";
}

#pragma mark - Admin Notes

- (NSString *)defaultAdminNoteForOrderID:(NSString *)orderID
                                  action:(NSString *)action
{
    if ([self pp_trimmedString:orderID].length == 0) {
        return @"";
    }

    NSString *resolvedAction = [[self pp_trimmedString:action] lowercaseString];
    NSArray<NSString *> *supportedActions = @[
        @"order_approve",
        @"order_mark_processing",
        @"order_mark_ready",
        @"order_mark_shipped",
        @"order_mark_in_transit",
        @"order_mark_delivered",
        @"order_collect_payment",
        @"order_mark_completed",
        @"order_cancel",
    ];
    if (![supportedActions containsObject:resolvedAction]) {
        return @"";
    }

    return [NSString stringWithFormat:@"payment.order.%@", resolvedAction];
}

- (NSString *)defaultAdminNoteForOrderID:(NSString *)orderID
                               nextStatus:(NSString *)nextStatus
{
    NSString *resolvedStatus = [[self pp_trimmedString:nextStatus] lowercaseString];
    NSDictionary<NSString *, NSString *> *statusToAction = @{
        @"paid": @"order_approve",
        @"processing": @"order_mark_processing",
        @"ready": @"order_mark_ready",
        @"shipped": @"order_mark_shipped",
        @"in_transit": @"order_mark_in_transit",
        @"delivered": @"order_mark_delivered",
        @"completed": @"order_mark_completed",
        @"cancelled": @"order_cancel",
    };
    NSString *action = statusToAction[resolvedStatus];
    if (action.length > 0) {
        return [self defaultAdminNoteForOrderID:orderID action:action];
    }
    return @"";
}

#pragma mark - Private User Resolution

- (void)pp_resolveUsersForRecords:(NSArray<PPPaymentAdminRecord *> *)records
                       completion:(dispatch_block_t)completion
{
    NSMutableArray<PPPaymentAdminRecord *> *pendingRecords = [NSMutableArray array];
    for (PPPaymentAdminRecord *record in records ?: @[]) {
        NSString *userID = [self pp_trimmedString:record.userId];
        if (userID.length == 0) continue;
        NSDictionary *cachedUser = nil;
        @synchronized (self.userSummaryCache) {
            cachedUser = self.userSummaryCache[userID];
        }
        if (cachedUser) {
            [self pp_applyUserSummary:cachedUser toRecord:record];
            continue;
        }
        [pendingRecords addObject:record];
    }

    if (pendingRecords.count == 0) {
        if (completion) completion();
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    for (PPPaymentAdminRecord *record in pendingRecords) {
        NSString *userID = [self pp_trimmedString:record.userId];
        if (userID.length == 0) continue;
        dispatch_group_enter(group);
        [[[self.db collectionWithPath:@"UsersCol"] documentWithPath:userID]
         getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (!error && snapshot.exists) {
                NSDictionary *summary = [self pp_userSummaryFromSnapshot:snapshot];
                @synchronized (self.userSummaryCache) {
                    self.userSummaryCache[userID] = summary ?: @{};
                }
                [self pp_applyUserSummary:summary toRecord:record];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) completion();
    });
}

- (NSDictionary *)pp_userSummaryFromSnapshot:(FIRDocumentSnapshot *)snapshot
{
    NSDictionary *data = snapshot.data ?: @{};
    NSString *displayName = [self pp_firstNonEmptyStringFromDictionary:data keys:@[@"displayName", @"UserName", @"FirstName", @"name"]];
    NSString *email = [self pp_firstNonEmptyStringFromDictionary:data keys:@[@"email", @"UserEmail"]];
    return @{
        @"displayName": displayName ?: @"",
        @"email": email ?: @"",
    };
}

- (void)pp_applyUserSummary:(NSDictionary *)summary toRecord:(PPPaymentAdminRecord *)record
{
    NSString *displayName = [self pp_firstNonEmptyStringFromDictionary:summary keys:@[@"displayName"]];
    NSString *email = [self pp_firstNonEmptyStringFromDictionary:summary keys:@[@"email"]];
    if (displayName.length > 0) {
        record.userDisplayName = displayName;
    } else if (record.userDisplayName.length == 0) {
        record.userDisplayName = [self pp_deliveryNameForRecord:record];
    }
    if (email.length > 0) {
        record.userEmail = email;
    }
}

#pragma mark - Private Helpers

- (void)pp_callAdminTransitionAction:(NSString *)action
                             orderID:(NSString *)orderID
                                note:(NSString *)note
                          completion:(PPPaymentAdminRecordCompletion)completion
{
    FIRHTTPSCallable *callable = [[self pp_functionsClient] HTTPSCallableWithName:@"adminTransitionOrderStatus"];
    NSString *noteCode = [NSString stringWithFormat:@"payment.order.%@", [self pp_trimmedString:action]];
    NSDictionary *payload = @{
        @"orderId": [self pp_trimmedString:orderID] ?: @"",
        @"action": [self pp_trimmedString:action] ?: @"",
        @"note": [self pp_trimmedString:note] ?: @"",
        @"noteCode": noteCode,
    };

    [callable callWithObject:payload
                  completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"PPLAB admin order mutation failed orderId=%@ action=%@ code=%ld", orderID, action, (long)error.code);
            [self pp_completeRecord:nil error:error completion:completion];
            return;
        }

        NSDictionary *data = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : @{};
        NSString *resolvedOrderID = [self pp_trimmedString:data[@"orderId"]];
        if (resolvedOrderID.length == 0) {
            resolvedOrderID = [self pp_trimmedString:orderID];
        }
        NSLog(@"PPLAB admin order mutation accepted orderId=%@ action=%@", resolvedOrderID, action);
        [self loadFullRecordForOrderID:resolvedOrderID completion:completion];
    }];
}

- (BOOL)pp_noteIsAcceptable:(NSString *)note
{
    return ([self pp_trimmedString:note].length >= 3);
}

- (NSString *)pp_deliveryNameForRecord:(PPPaymentAdminRecord *)record
{
    NSDictionary *snapshot = record.shippingAddressSnapshot ?: @{};
    NSString *name = [self pp_firstNonEmptyStringFromDictionary:snapshot keys:@[@"fullName", @"displayName", @"locatioName", @"name"]];
    if (name.length > 0) return name;
    return record.userId ?: kLang(@"PaymentMgmt_Record_UnknownUser");
}

- (NSString *)pp_firstNonEmptyStringFromDictionary:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys
{
    NSDictionary *source = [dictionary isKindOfClass:NSDictionary.class] ? dictionary : @{};
    for (NSString *key in keys ?: @[]) {
        NSString *value = [self pp_trimmedString:source[key]];
        if (value.length > 0) {
            return value;
        }
    }
    return @"";
}

- (NSString *)pp_trimmedString:(id)value
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (FIRFunctions *)pp_functionsClient
{
    return [FIRFunctions functionsForRegion:@"us-central1"];
}

- (void)pp_completeRecords:(NSArray<PPPaymentAdminRecord *> *)records
                nextCursor:(FIRDocumentSnapshot *)nextCursor
                     error:(NSError *)error
                completion:(PPPaymentAdminRecordsCompletion)completion
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(records ?: @[], nextCursor, error);
    });
}

- (void)pp_completeRecord:(PPPaymentAdminRecord *)record
                    error:(NSError *)error
               completion:(PPPaymentAdminRecordCompletion)completion
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(record, error);
    });
}

- (void)pp_completeSettings:(PPPaymentAdminSettings *)settings
                      error:(NSError *)error
                 completion:(PPPaymentAdminSettingsCompletion)completion
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(settings, error);
    });
}

@end
