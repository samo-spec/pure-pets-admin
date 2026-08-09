#import "PPPaymentManagementService.h"
#import "UserManager.h"
#import "UserModel.h"
#import "PPRolePermission.h"
#import "PPStaffAuth.h"
#import "Language.h"

static NSString * const PPPaymentAdminServiceErrorDomain = @"PPPaymentAdminService";

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
    if (![self currentAdminCanViewPayments]) {
        [self pp_completeRecords:@[]
                      nextCursor:nil
                           error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                    code:400
                                                userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoViewPaymentsPermission")}]
                      completion:completion];
        return;
    }

    NSInteger resolvedPageSize = MAX(10, MIN(100, pageSize));
    PPPaymentManagementFilters *resolvedFilters = filters ? [filters copy] : [PPPaymentManagementFilters defaultFilters];
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
        FIRQuery *query = [strongSelf pp_baseOrdersQueryForFilters:resolvedFilters];
        query = [query queryLimitedTo:MAX(resolvedPageSize * 2, 40)];
        if (cursor) {
            query = [query queryStartingAfterDocument:cursor];
        }

        [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) {
                [strongSelf pp_completeRecords:@[] nextCursor:nil error:error completion:completion];
                return;
            }

            NSArray<FIRDocumentSnapshot *> *documents = snapshot.documents ?: @[];
            if (documents.count == 0) {
                exhausted = YES;
                [strongSelf pp_completeRecords:collected nextCursor:nil error:nil completion:completion];
                return;
            }

            cursor = documents.lastObject;
            if (documents.count < MAX(resolvedPageSize * 2, 40)) {
                exhausted = YES;
            }

            NSMutableArray<PPPaymentAdminRecord *> *batchRecords = [NSMutableArray arrayWithCapacity:documents.count];
            for (FIRDocumentSnapshot *doc in documents) {
                PPPaymentAdminRecord *record = [PPPaymentAdminRecord recordFromSnapshot:doc];
                if (record.orderId.length == 0) continue;
                [batchRecords addObject:record];
            }

            [strongSelf pp_resolveUsersForRecords:batchRecords completion:^{
                [strongSelf refreshRequestSummariesForRecords:batchRecords completion:^(__unused NSArray<PPPaymentAdminRecord *> *recordsWithSummaries) {
                    for (PPPaymentAdminRecord *record in batchRecords) {
                        if ([record matchesFilters:resolvedFilters]) {
                            [collected addObject:record];
                        }
                        if (collected.count >= resolvedPageSize) {
                            break;
                        }
                    }

                    if (collected.count >= resolvedPageSize || exhausted) {
                        FIRDocumentSnapshot *nextCursor = exhausted ? nil : cursor;
                        [strongSelf pp_completeRecords:collected nextCursor:nextCursor error:nil completion:completion];
                        return;
                    }

                    fetchNextBatch();
                }];
            }];
        }];
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

    dispatch_group_t group = dispatch_group_create();
    __weak typeof(self) weakSelf = self;
    for (PPPaymentAdminRecord *record in records) {
        if (record.orderId.length == 0) continue;
        dispatch_group_enter(group);
        [self pp_fetchRequestSummariesForOrderID:record.orderId completion:^(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error) {
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
    if (![self currentAdminCanViewPayments]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:401
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoViewPaymentDetailsPermission")}]
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
        dispatch_group_t group = dispatch_group_create();

        dispatch_group_enter(group);
        [self pp_resolveUsersForRecords:@[record] completion:^{
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [self pp_fetchAllRequestsForOrderID:record.orderId completion:^(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable requestsError) {
            if (!requestsError) {
                [record applyRequestSummaries:requests];
            }
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [self pp_fetchTimelineForOrderID:record.orderId completion:^(NSArray<PPPaymentAdminTimelineEvent *> *events, NSError * _Nullable timelineError) {
            if (!timelineError) {
                record.timelineEvents = events ?: @[];
            }
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [self pp_fetchAuditEntriesForOrderID:record.orderId completion:^(NSArray<PPPaymentAdminAuditEntry *> *entries, NSError * _Nullable auditError) {
            if (!auditError) {
                record.auditEntries = entries ?: @[];
            }
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [self pp_completeRecord:record error:nil completion:completion];
        });
    }];
}

- (void)loadEventsForRequest:(PPPaymentAdminSupportRequest *)request
                   completion:(PPPaymentAdminRequestEventsCompletion)completion
{
    NSString *orderID = [self pp_trimmedString:request.orderId];
    NSString *requestID = [self pp_trimmedString:request.requestId];
    if (orderID.length == 0 || requestID.length == 0) {
        if (completion) completion(@[], [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                            code:103
                                                        userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_MissingRequestReference")}]);
        return;
    }

    FIRQuery *query = [[[[[self.db collectionWithPath:@"Orders"]
                           documentWithPath:orderID]
                          collectionWithPath:@"requests"]
                         documentWithPath:requestID]
                        collectionWithPath:@"events"];
    query = [query queryOrderedByField:@"createdAt" descending:NO];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
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
    if (![self currentAdminCanManagePayments]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:401
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoManagePermission")}]
                     completion:completion];
        return;
    }
    if ((action == PPPaymentAdminRequestResolutionRefund ||
         action == PPPaymentAdminRequestResolutionPartialRefund) &&
        ![self currentAdminCanRefundPayments]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:403
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoRefundPermission")}]
                     completion:completion];
        return;
    }

    NSString *resolvedOrderID = [self pp_trimmedString:record.orderId];
    NSString *resolvedRequestID = [self pp_trimmedString:request.requestId];
    if (resolvedOrderID.length == 0 || resolvedRequestID.length == 0) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:104
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

- (FIRQuery *)pp_baseOrdersQueryForFilters:(PPPaymentManagementFilters *)filters
{
    FIRQuery *query = [[self.db collectionWithPath:@"Orders"] queryOrderedByField:@"updatedAt" descending:YES];
    NSDate *floorDate = [self pp_floorDateForRange:filters.dateRange];
    if (floorDate) {
        query = [query queryWhereField:@"updatedAt"
               isGreaterThanOrEqualTo:[FIRTimestamp timestampWithDate:floorDate]];
    }
    return query;
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
                                completion:(void (^)(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error))completion
{
    FIRQuery *query = [[[[self.db collectionWithPath:@"Orders"]
                         documentWithPath:orderID]
                        collectionWithPath:@"requests"]
                       queryOrderedByField:@"updatedAt" descending:YES];
    query = [query queryLimitedTo:6];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray<PPPaymentAdminSupportRequest *> *requests = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents ?: @[]) {
            [requests addObject:[PPPaymentAdminSupportRequest requestFromSnapshot:doc]];
        }
        if (completion) completion(requests.copy, nil);
    }];
}

- (void)pp_fetchAllRequestsForOrderID:(NSString *)orderID
                           completion:(void (^)(NSArray<PPPaymentAdminSupportRequest *> *requests, NSError * _Nullable error))completion
{
    FIRQuery *query = [[[[self.db collectionWithPath:@"Orders"]
                         documentWithPath:orderID]
                        collectionWithPath:@"requests"]
                       queryOrderedByField:@"createdAt" descending:YES];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray<PPPaymentAdminSupportRequest *> *requests = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents ?: @[]) {
            [requests addObject:[PPPaymentAdminSupportRequest requestFromSnapshot:doc]];
        }
        if (completion) completion(requests.copy, nil);
    }];
}

- (void)pp_fetchTimelineForOrderID:(NSString *)orderID
                        completion:(void (^)(NSArray<PPPaymentAdminTimelineEvent *> *events, NSError * _Nullable error))completion
{
    FIRQuery *query = [[[[self.db collectionWithPath:@"Orders"]
                         documentWithPath:orderID]
                        collectionWithPath:@"events"]
                       queryOrderedByField:@"createdAt" descending:NO];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
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
                            completion:(void (^)(NSArray<PPPaymentAdminAuditEntry *> *entries, NSError * _Nullable error))completion
{
    FIRQuery *query = [[[self.db collectionWithPath:@"AdminAuditLogs"]
                        queryWhereField:@"orderId" isEqualTo:orderID]
                       queryWhereField:@"area" isEqualTo:@"payments"];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
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
    if (![self currentAdminCanManagePayments]) {
        [self pp_completeRecord:nil
                          error:[NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                   code:402
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_NoManagePermission")}]
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
