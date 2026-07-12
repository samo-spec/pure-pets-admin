#import "PPPaymentManagementService.h"
#import "UserManager.h"
#import "UserModel.h"
#import "PPRolePermission.h"
#import "Language.h"

static NSString * const PPPaymentAdminServiceErrorDomain = @"PPPaymentAdminService";

@interface PPPaymentManagementService ()

@property (nonatomic, strong) FIRFirestore *db;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *userSummaryCache;

- (FIRFunctions *)pp_functionsClient;
- (BOOL)pp_shouldRetryOrderMutationViaCallable:(NSError *)error;
- (void)pp_retryOrderMutationViaCallableAction:(NSString *)action
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
    UserModel *currentUser = [UserManager shared].currentUser;
    if (!currentUser) return NO;
    return ([currentUser hasPermissionNamed:kPermManageStore] ||
            [currentUser hasPermissionNamed:kPermAdminAll]);
}

- (void)fetchOrdersWithFilters:(PPPaymentManagementFilters *)filters
                      pageSize:(NSInteger)pageSize
                    startAfter:(FIRDocumentSnapshot *)startAfter
                    completion:(PPPaymentAdminRecordsCompletion)completion
{
    if (![self currentAdminCanManagePayments]) {
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
    if (![self currentAdminCanManagePayments]) {
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
    if (![self currentAdminCanManagePayments]) {
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
              completion:completion
              transaction:^NSDictionary * _Nullable(FIRTransaction *transaction,
                                                   FIRDocumentReference *orderRef,
                                                   FIRDocumentSnapshot *orderSnapshot,
                                                   NSError **errorPointer) {
        PPPaymentAdminRecord *freshRecord = [PPPaymentAdminRecord recordFromSnapshot:orderSnapshot];
        if ([freshRecord.paymentMethodId isEqualToString:@"cash"]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_OrderApproveTransition")];
            return nil;
        }
        if (![PPPaymentAdminRecord canApproveOrderStatus:freshRecord.rawStatus]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_OrderApproveTransition")];
            return nil;
        }

        NSMutableDictionary *updatePayload = [@{
            @"status": @"paid",
            @"paymentMethodId": @"qib",
            @"paymentStatus": @"paid",
            @"verificationStatus": @"verified",
            @"paymentProvider": freshRecord.paymentProvider.length > 0 ? freshRecord.paymentProvider : @"QIB",
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"statusUpdatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"manualApprovalAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"manualApprovalBy": [self pp_currentAdminSummary],
        } mutableCopy];
        if (!freshRecord.paidAt) {
            updatePayload[@"paidAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        }
        NSMutableDictionary *inventoryUpdate = [self pp_applyInventoryDeductionIfNeededForRecord:freshRecord
                                                                                      transaction:transaction
                                                                                       errorOut:errorPointer];
        if (*errorPointer) return nil;
        if (inventoryUpdate.count > 0) {
            [updatePayload addEntriesFromDictionary:inventoryUpdate];
        }
        [transaction updateData:updatePayload forDocument:orderRef];

        [self pp_appendOrderEventInTransaction:transaction
                                      orderRef:orderRef
                                          type:@"payment_verified"
                                        status:@"paid"
                                     actorType:@"admin"
                                       summary:@"Payment approved by admin"
                                      metadata:@{
            @"manualApproval": @YES,
            @"note": [self pp_trimmedString:note],
            @"admin": [self pp_currentAdminSummary],
        }];

        [self pp_logAuditInTransaction:transaction
                                action:@"order_approve"
                                 order:freshRecord
                                request:nil
                                  note:note
                                 before:[self pp_auditStateForOrderRecord:freshRecord]
                                  after:@{
            @"status": @"paid",
            @"workflowStatus": @"paid",
            @"paymentMethodId": @"qib",
            @"paymentStatus": @"paid",
            @"inventoryDeducted": @YES,
        }];

        return @{@"orderId": freshRecord.orderId ?: @""};
    }];
}

- (void)markOrderProcessing:(PPPaymentAdminRecord *)record
                       note:(NSString *)note
                 completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_mark_processing"
                    note:note
              completion:completion
              transaction:^NSDictionary * _Nullable(FIRTransaction *transaction,
                                                   FIRDocumentReference *orderRef,
                                                   FIRDocumentSnapshot *orderSnapshot,
                                                   NSError **errorPointer) {
        PPPaymentAdminRecord *freshRecord = [PPPaymentAdminRecord recordFromSnapshot:orderSnapshot];
        if (![PPPaymentAdminRecord canMarkOrderProcessingForOrder:freshRecord]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_OrderProcessingTransition")];
            return nil;
        }

        NSMutableDictionary *updatePayload = [@{
            @"status": @"processing",
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"statusUpdatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        } mutableCopy];
        if ([freshRecord.paymentMethodId isEqualToString:@"cash"]) {
            updatePayload[@"paymentMethodId"] = @"cash";
            updatePayload[@"paymentProvider"] = @"CASH";
            updatePayload[@"paymentStatus"] = @"pending_collection";
            updatePayload[@"verificationStatus"] = @"not_applicable";
        }
        if (!freshRecord.processedAt) {
            updatePayload[@"processedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        }

        NSMutableDictionary *inventoryUpdate = [self pp_applyInventoryDeductionIfNeededForRecord:freshRecord
                                                                                      transaction:transaction
                                                                                       errorOut:errorPointer];
        if (*errorPointer) return nil;
        if (inventoryUpdate.count > 0) {
            [updatePayload addEntriesFromDictionary:inventoryUpdate];
        }
        [transaction updateData:updatePayload forDocument:orderRef];

        [self pp_appendOrderEventInTransaction:transaction
                                      orderRef:orderRef
                                          type:@"fulfillment_processing"
                                        status:@"processing"
                                     actorType:@"admin"
                                       summary:@"Order moved to processing"
                                      metadata:@{
            @"note": [self pp_trimmedString:note],
            @"admin": [self pp_currentAdminSummary],
        }];

        [self pp_logAuditInTransaction:transaction
                                action:@"order_mark_processing"
                                 order:freshRecord
                                request:nil
                                  note:note
                                 before:[self pp_auditStateForOrderRecord:freshRecord]
                                  after:@{
            @"status": @"processing",
            @"workflowStatus": @"processing",
            @"paymentMethodId": freshRecord.paymentMethodId ?: @"",
            @"paymentStatus": [freshRecord.paymentMethodId isEqualToString:@"cash"] ? @"pending_collection" : (freshRecord.paymentStatus ?: @""),
            @"inventoryDeducted": @YES,
        }];

        return @{@"orderId": freshRecord.orderId ?: @""};
    }];
}

- (void)markOrderShipped:(PPPaymentAdminRecord *)record
                    note:(NSString *)note
              completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_mark_shipped"
                    note:note
              completion:completion
              transaction:^NSDictionary * _Nullable(FIRTransaction *transaction,
                                                   FIRDocumentReference *orderRef,
                                                   FIRDocumentSnapshot *orderSnapshot,
                                                   NSError **errorPointer) {
        PPPaymentAdminRecord *freshRecord = [PPPaymentAdminRecord recordFromSnapshot:orderSnapshot];
        if (![PPPaymentAdminRecord canMarkOrderShippedStatus:freshRecord.rawStatus]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_OrderShippedTransition")];
            return nil;
        }

        NSMutableDictionary *updatePayload = [@{
            @"status": @"shipped",
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"statusUpdatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        } mutableCopy];
        if (!freshRecord.shippedAt) {
            updatePayload[@"shippedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        }

        [transaction updateData:updatePayload forDocument:orderRef];

        [self pp_appendOrderEventInTransaction:transaction
                                      orderRef:orderRef
                                          type:@"fulfillment_shipped"
                                        status:@"shipped"
                                     actorType:@"admin"
                                       summary:@"Order marked as shipped"
                                      metadata:@{
            @"note": [self pp_trimmedString:note],
            @"admin": [self pp_currentAdminSummary],
        }];

        [self pp_logAuditInTransaction:transaction
                                action:@"order_mark_shipped"
                                 order:freshRecord
                                request:nil
                                  note:note
                                 before:[self pp_auditStateForOrderRecord:freshRecord]
                                  after:@{
            @"status": @"shipped",
            @"workflowStatus": @"shipped",
            @"paymentMethodId": freshRecord.paymentMethodId ?: @"",
            @"paymentStatus": freshRecord.paymentStatus ?: @"",
        }];

        return @{@"orderId": freshRecord.orderId ?: @""};
    }];
}

- (void)markOrderDelivered:(PPPaymentAdminRecord *)record
                      note:(NSString *)note
                completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_mark_delivered"
                    note:note
              completion:completion
              transaction:^NSDictionary * _Nullable(FIRTransaction *transaction,
                                                   FIRDocumentReference *orderRef,
                                                   FIRDocumentSnapshot *orderSnapshot,
                                                   NSError **errorPointer) {
        PPPaymentAdminRecord *freshRecord = [PPPaymentAdminRecord recordFromSnapshot:orderSnapshot];
        if (![PPPaymentAdminRecord canMarkOrderDeliveredStatus:freshRecord.rawStatus]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_OrderDeliveredTransition")];
            return nil;
        }

        NSMutableDictionary *updatePayload = [@{
            @"status": @"delivered",
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"statusUpdatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        } mutableCopy];
        if (!freshRecord.deliveredAt) {
            updatePayload[@"deliveredAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        }

        [transaction updateData:updatePayload forDocument:orderRef];

        [self pp_appendOrderEventInTransaction:transaction
                                      orderRef:orderRef
                                          type:@"fulfillment_delivered"
                                        status:@"delivered"
                                     actorType:@"admin"
                                       summary:@"Order marked as delivered"
                                      metadata:@{
            @"note": [self pp_trimmedString:note],
            @"admin": [self pp_currentAdminSummary],
        }];

        [self pp_logAuditInTransaction:transaction
                                action:@"order_mark_delivered"
                                 order:freshRecord
                                request:nil
                                  note:note
                                 before:[self pp_auditStateForOrderRecord:freshRecord]
                                  after:@{
            @"status": @"delivered",
            @"workflowStatus": @"delivered",
            @"paymentMethodId": freshRecord.paymentMethodId ?: @"",
            @"paymentStatus": freshRecord.paymentStatus ?: @"",
        }];

        return @{@"orderId": freshRecord.orderId ?: @""};
    }];
}

- (void)cancelOrder:(PPPaymentAdminRecord *)record
               note:(NSString *)note
         completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_cancel"
                    note:note
              completion:completion
              transaction:^NSDictionary * _Nullable(FIRTransaction *transaction,
                                                   FIRDocumentReference *orderRef,
                                                   FIRDocumentSnapshot *orderSnapshot,
                                                   NSError **errorPointer) {
        PPPaymentAdminRecord *freshRecord = [PPPaymentAdminRecord recordFromSnapshot:orderSnapshot];
        if (![PPPaymentAdminRecord canCancelOrderStatus:freshRecord.rawStatus]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_OrderCancelTransition")];
            return nil;
        }

        NSMutableDictionary *updatePayload = [@{
            @"status": @"cancelled",
            @"failureReason": @"cancelled_by_admin",
            @"cancelledAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"statusUpdatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"manualCancellationBy": [self pp_currentAdminSummary],
        } mutableCopy];
        NSString *normalizedPaymentStatus = [[self pp_trimmedString:freshRecord.paymentStatus] lowercaseString];
        if ([freshRecord.paymentMethodId isEqualToString:@"cash"] &&
            ![normalizedPaymentStatus isEqualToString:@"paid"]) {
            updatePayload[@"paymentStatus"] = @"cancelled";
        }

        NSMutableDictionary *restockPayload = [self pp_applyInventoryRestockIfNeededForRecord:freshRecord
                                                                                   transaction:transaction
                                                                                      errorOut:errorPointer];
        if (*errorPointer) return nil;
        if (restockPayload.count > 0) {
            [updatePayload addEntriesFromDictionary:restockPayload];
        }
        [transaction updateData:updatePayload forDocument:orderRef];

        [self pp_appendOrderEventInTransaction:transaction
                                      orderRef:orderRef
                                          type:@"order_cancelled"
                                        status:@"cancelled"
                                     actorType:@"admin"
                                       summary:@"Order cancelled by admin"
                                      metadata:@{
            @"note": [self pp_trimmedString:note],
            @"admin": [self pp_currentAdminSummary],
        }];

        [self pp_logAuditInTransaction:transaction
                                action:@"order_cancel"
                                 order:freshRecord
                                request:nil
                                  note:note
                                 before:[self pp_auditStateForOrderRecord:freshRecord]
                                  after:@{
            @"status": @"cancelled",
            @"workflowStatus": @"cancelled",
            @"paymentMethodId": freshRecord.paymentMethodId ?: @"",
            @"paymentStatus": ([freshRecord.paymentMethodId isEqualToString:@"cash"] &&
                               ![normalizedPaymentStatus isEqualToString:@"paid"]) ? @"cancelled" : (freshRecord.paymentStatus ?: @""),
            @"inventoryRestocked": @(freshRecord.inventoryDeducted),
        }];

        return @{@"orderId": freshRecord.orderId ?: @""};
    }];
}

- (void)collectOrderPayment:(PPPaymentAdminRecord *)record
                       note:(NSString *)note
                 completion:(PPPaymentAdminRecordCompletion)completion
{
    [self pp_mutateOrder:record
                  action:@"order_collect_payment"
                    note:note
              completion:completion
              transaction:^NSDictionary * _Nullable(FIRTransaction *transaction,
                                                   FIRDocumentReference *orderRef,
                                                   FIRDocumentSnapshot *orderSnapshot,
                                                   NSError **errorPointer) {
        PPPaymentAdminRecord *freshRecord = [PPPaymentAdminRecord recordFromSnapshot:orderSnapshot];
        if (![PPPaymentAdminRecord canCollectCashPaymentForOrder:freshRecord]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_OrderCollectPaymentTransition")];
            return nil;
        }

        NSMutableDictionary *updatePayload = [@{
            @"paymentMethodId": @"cash",
            @"paymentProvider": @"CASH",
            @"paymentStatus": @"paid",
            @"verificationStatus": @"not_applicable",
            @"paymentCollectedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"paymentCollectedBy": [self pp_currentAdminSummary],
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        } mutableCopy];
        if (!freshRecord.paidAt) {
            updatePayload[@"paidAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        }
        [transaction updateData:updatePayload forDocument:orderRef];

        [self pp_appendOrderEventInTransaction:transaction
                                      orderRef:orderRef
                                          type:@"payment_collected"
                                        status:freshRecord.rawStatus.length > 0 ? freshRecord.rawStatus : @"delivered"
                                     actorType:@"admin"
                                       summary:@"Cash payment collected"
                                      metadata:@{
            @"note": [self pp_trimmedString:note],
            @"admin": [self pp_currentAdminSummary],
        }];

        [self pp_logAuditInTransaction:transaction
                                action:@"order_collect_payment"
                                 order:freshRecord
                                request:nil
                                  note:note
                                 before:[self pp_auditStateForOrderRecord:freshRecord]
                                  after:@{
            @"status": freshRecord.rawStatus ?: @"",
            @"workflowStatus": [freshRecord workflowStatusKey] ?: @"",
            @"paymentMethodId": @"cash",
            @"paymentStatus": @"paid",
        }];

        return @{@"orderId": freshRecord.orderId ?: @""};
    }];
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

    FIRDocumentReference *orderRef = [[self.db collectionWithPath:@"Orders"] documentWithPath:resolvedOrderID];
    FIRDocumentReference *requestRef = [[orderRef collectionWithPath:@"requests"] documentWithPath:resolvedRequestID];

    [self.db runTransactionWithBlock:^id _Nullable(FIRTransaction * _Nonnull transaction, NSError ** _Nonnull errorPointer) {
        FIRDocumentSnapshot *orderSnapshot = [transaction getDocument:orderRef error:errorPointer];
        if (*errorPointer) return nil;
        if (!orderSnapshot.exists) {
            *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                code:106
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_OrderNotFound")}];
            return nil;
        }

        FIRDocumentSnapshot *requestSnapshot = [transaction getDocument:requestRef error:errorPointer];
        if (*errorPointer) return nil;
        if (!requestSnapshot.exists) {
            *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                code:107
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_RequestNotFound")}];
            return nil;
        }

        PPPaymentAdminRecord *freshOrder = [PPPaymentAdminRecord recordFromSnapshot:orderSnapshot];
        PPPaymentAdminSupportRequest *freshRequest = [PPPaymentAdminSupportRequest requestFromSnapshot:requestSnapshot];
        if (![PPPaymentAdminRecord canResolveRequest:freshRequest withAction:action order:freshOrder]) {
            *errorPointer = [self pp_invalidTransitionError:kLang(@"PaymentMgmt_Error_InvalidRequestTransition")];
            return nil;
        }

        NSDictionary *resolutionPlan = [self pp_resolutionPlanForRequest:freshRequest
                                                                   order:freshOrder
                                                                  action:action
                                                                   amount:amount
                                                                errorOut:errorPointer];
        if (*errorPointer || resolutionPlan.count == 0) return nil;

        NSString *targetStatus = resolutionPlan[@"requestStatus"] ?: @"pending_review";
        NSString *finalResolution = resolutionPlan[@"finalResolution"] ?: targetStatus;
        NSMutableDictionary *requestUpdate = [@{
            @"status": targetStatus,
            @"finalResolution": finalResolution,
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"adminReview": @{
                @"adminUid": [self pp_currentAdminUID],
                @"adminName": [self pp_currentAdminName],
                @"reviewedAt": [FIRFieldValue fieldValueForServerTimestamp],
                @"note": [self pp_trimmedString:note],
                @"action": [self pp_resolutionActionKey:action],
            },
            @"resolution": [self pp_resolutionMetadataWithAction:action
                                                            note:note
                                                          amount:amount],
        } mutableCopy];
        if ([PPPaymentAdminRecord isFinalRequestStatus:targetStatus]) {
            requestUpdate[@"resolvedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        }
        NSDictionary *orderPatch = resolutionPlan[@"orderPatch"];
        NSMutableDictionary *mutablePatch = [NSMutableDictionary dictionary];
        if ([orderPatch isKindOfClass:NSDictionary.class] && orderPatch.count > 0) {
            [mutablePatch addEntriesFromDictionary:orderPatch];
        }
        if (action == PPPaymentAdminRequestResolutionComplete && [freshRequest isReturnLike]) {
            NSDictionary<NSString *, NSDictionary *> *requestItems = [self pp_aggregatedItemsForRequest:freshRequest
                                                                                            orderRecord:freshOrder];
            NSMutableDictionary *restockPatch = [self pp_applyInventoryRestockForAggregatedItems:requestItems
                                                                                      orderRecord:freshOrder
                                                                                      transaction:transaction
                                                                                         errorOut:errorPointer];
            if (*errorPointer) return nil;
            if (restockPatch.count > 0) {
                [mutablePatch addEntriesFromDictionary:restockPatch];
            }
        }
        [transaction updateData:requestUpdate forDocument:requestRef];
        mutablePatch[@"latestRequestType"] = freshRequest.type ?: @"";
        mutablePatch[@"latestRequestStatus"] = targetStatus;
        mutablePatch[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        [transaction updateData:mutablePatch forDocument:orderRef];

        [self pp_appendRequestEventInTransaction:transaction
                                      requestRef:requestRef
                                            type:@"request_status_updated"
                                          status:targetStatus
                                       actorType:@"admin"
                                         summary:[NSString stringWithFormat:@"Request moved to %@", PPPaymentAdminDisplayTitleForRequestStatus(targetStatus)]
                                        metadata:@{
            @"requestType": freshRequest.type ?: @"",
            @"targetStatus": targetStatus,
            @"note": [self pp_trimmedString:note],
            @"finalResolution": finalResolution,
            @"admin": [self pp_currentAdminSummary],
            @"amount": amount ?: @0,
        }];

        [self pp_appendOrderEventInTransaction:transaction
                                      orderRef:orderRef
                                          type:@"request_status_updated"
                                        status:targetStatus
                                     actorType:@"admin"
                                       summary:[NSString stringWithFormat:@"%@ request updated", PPPaymentAdminDisplayTitleForRequestType(freshRequest.type)]
                                      metadata:@{
            @"requestId": freshRequest.requestId ?: @"",
            @"requestType": freshRequest.type ?: @"",
            @"targetStatus": targetStatus,
            @"finalResolution": finalResolution,
            @"note": [self pp_trimmedString:note],
        }];

        [self pp_logAuditInTransaction:transaction
                                action:[self pp_auditActionNameForResolutionAction:action request:freshRequest]
                                 order:freshOrder
                                request:freshRequest
                                  note:note
                                 before:[self pp_auditStateForRequest:freshRequest]
                                  after:@{
            @"status": targetStatus,
            @"finalResolution": finalResolution,
            @"amount": amount ?: @0,
            @"inventoryRestocked": @((action == PPPaymentAdminRequestResolutionComplete && [freshRequest isReturnLike])),
        }];

        return @{@"orderId": freshOrder.orderId ?: @""};
    } completion:^(id  _Nullable result, NSError * _Nullable error) {
        if (error) {
            [self pp_completeRecord:nil error:error completion:completion];
            return;
        }
        NSString *orderID = [self pp_trimmedString:result[@"orderId"]];
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
            transaction:(NSDictionary * _Nullable (^)(FIRTransaction *transaction,
                                                    FIRDocumentReference *orderRef,
                                                    FIRDocumentSnapshot *orderSnapshot,
                                                    NSError **errorPointer))transactionBlock
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

    FIRDocumentReference *orderRef = [[self.db collectionWithPath:@"Orders"] documentWithPath:orderID];
    [self.db runTransactionWithBlock:^id _Nullable(FIRTransaction * _Nonnull transaction, NSError ** _Nonnull errorPointer) {
        FIRDocumentSnapshot *orderSnapshot = [transaction getDocument:orderRef error:errorPointer];
        if (*errorPointer) return nil;
        if (!orderSnapshot.exists) {
            *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                code:405
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_OrderNotFound")}];
            return nil;
        }
        return transactionBlock ? transactionBlock(transaction, orderRef, orderSnapshot, errorPointer) : @{};
    } completion:^(id  _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ [PPPaymentManagementService] %@ failed: %@", action, error.localizedDescription);
            if ([self pp_shouldRetryOrderMutationViaCallable:error]) {
                NSLog(@"↪️ [PPPaymentManagementService] Retrying %@ via callable backend", action);
                [self pp_retryOrderMutationViaCallableAction:action
                                                     orderID:orderID
                                                        note:resolvedNote
                                                  completion:completion];
                return;
            }
            [self pp_completeRecord:nil error:error completion:completion];
            return;
        }

        NSString *resolvedOrderID = [self pp_trimmedString:result[@"orderId"]];
        [self loadFullRecordForOrderID:resolvedOrderID completion:completion];
    }];
}

- (NSMutableDictionary *)pp_applyInventoryDeductionIfNeededForRecord:(PPPaymentAdminRecord *)record
                                                          transaction:(FIRTransaction *)transaction
                                                             errorOut:(NSError **)errorPointer
{
    if (record.inventoryDeducted) {
        return [NSMutableDictionary dictionaryWithDictionary:@{@"inventoryDeducted": @YES}];
    }

    NSDictionary<NSString *, NSDictionary *> *items = [self pp_aggregatedOrderItems:record.items];
    if (items.count == 0) {
        *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                            code:501
                                        userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_InvalidInventoryDeductionItems")}];
        return nil;
    }

    NSMutableArray<NSDictionary *> *pendingInventoryUpdates = [NSMutableArray array];
    for (NSString *itemID in items.allKeys) {
        NSDictionary *entry = items[itemID];
        NSInteger requestedQty = [entry[@"qty"] integerValue];
        FIRDocumentReference *itemRef = [[self.db collectionWithPath:@"petAccessories"] documentWithPath:itemID];
        FIRDocumentSnapshot *itemSnapshot = [transaction getDocument:itemRef error:errorPointer];
        if (*errorPointer) return nil;
        if (!itemSnapshot.exists) {
            *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                code:502
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_StoreItemMissing")}];
            return nil;
        }

        NSInteger currentQty = [itemSnapshot.data[@"quantity"] respondsToSelector:@selector(integerValue)] ? [itemSnapshot.data[@"quantity"] integerValue] : 0;
        if (currentQty < requestedQty) {
            *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                code:503
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_InventoryInsufficient")}];
            return nil;
        }
        [pendingInventoryUpdates addObject:@{
            @"ref": itemRef,
            @"quantity": @(MAX(0, currentQty - requestedQty)),
        }];
    }

    for (NSDictionary *pendingUpdate in pendingInventoryUpdates) {
        FIRDocumentReference *itemRef = pendingUpdate[@"ref"];
        [transaction updateData:@{
            @"quantity": pendingUpdate[@"quantity"] ?: @0,
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        } forDocument:itemRef];
    }

    return [NSMutableDictionary dictionaryWithDictionary:@{
        @"inventoryDeducted": @YES,
        @"inventoryDeductedAt": [FIRFieldValue fieldValueForServerTimestamp],
        @"inventoryRestocked": @NO,
    }];
}

- (NSMutableDictionary *)pp_applyInventoryRestockIfNeededForRecord:(PPPaymentAdminRecord *)record
                                                        transaction:(FIRTransaction *)transaction
                                                           errorOut:(NSError **)errorPointer
{
    if (!record.inventoryDeducted || record.inventoryRestocked) {
        return [NSMutableDictionary dictionary];
    }

    NSDictionary<NSString *, NSDictionary *> *items = [self pp_aggregatedOrderItems:record.items];
    return [self pp_applyInventoryRestockForAggregatedItems:items
                                                orderRecord:record
                                                transaction:transaction
                                                   errorOut:errorPointer];
}

- (NSMutableDictionary *)pp_applyInventoryRestockForAggregatedItems:(NSDictionary<NSString *, NSDictionary *> *)items
                                                         orderRecord:(PPPaymentAdminRecord *)record
                                                         transaction:(FIRTransaction *)transaction
                                                            errorOut:(NSError **)errorPointer
{
    if (!record.inventoryDeducted || record.inventoryRestocked) {
        return [NSMutableDictionary dictionary];
    }

    if (items.count == 0) {
        *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                            code:504
                                        userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_InvalidInventoryRestockItems")}];
        return nil;
    }

    NSMutableArray<NSDictionary *> *pendingInventoryUpdates = [NSMutableArray array];
    for (NSString *itemID in items.allKeys) {
        NSDictionary *entry = items[itemID];
        NSInteger restockQty = [entry[@"qty"] integerValue];
        FIRDocumentReference *itemRef = [[self.db collectionWithPath:@"petAccessories"] documentWithPath:itemID];
        FIRDocumentSnapshot *itemSnapshot = [transaction getDocument:itemRef error:errorPointer];
        if (*errorPointer) return nil;
        if (!itemSnapshot.exists) {
            *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                code:505
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_StoreItemMissing")}];
            return nil;
        }

        NSInteger currentQty = [itemSnapshot.data[@"quantity"] respondsToSelector:@selector(integerValue)] ? [itemSnapshot.data[@"quantity"] integerValue] : 0;
        [pendingInventoryUpdates addObject:@{
            @"ref": itemRef,
            @"quantity": @(MAX(0, currentQty + restockQty)),
        }];
    }

    for (NSDictionary *pendingUpdate in pendingInventoryUpdates) {
        FIRDocumentReference *itemRef = pendingUpdate[@"ref"];
        [transaction updateData:@{
            @"quantity": pendingUpdate[@"quantity"] ?: @0,
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        } forDocument:itemRef];
    }

    return [NSMutableDictionary dictionaryWithDictionary:@{
        @"inventoryRestocked": @YES,
        @"inventoryRestockedAt": [FIRFieldValue fieldValueForServerTimestamp],
        @"inventoryRestockedBy": [self pp_currentAdminSummary],
    }];
}

- (NSDictionary<NSString *, NSDictionary *> *)pp_aggregatedItemsForRequest:(PPPaymentAdminSupportRequest *)request
                                                                orderRecord:(PPPaymentAdminRecord *)order
{
    NSMutableDictionary<NSString *, NSMutableDictionary *> *aggregated = [NSMutableDictionary dictionary];
    for (id rawItem in request.itemSnapshots ?: @[]) {
        if (![rawItem isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = (NSDictionary *)rawItem;
        NSString *itemID = [self pp_firstNonEmptyStringFromDictionary:item keys:@[@"itemId", @"itemID", @"id"]];
        NSInteger qty = [item[@"qty"] ?: item[@"quantity"] integerValue];
        if (itemID.length == 0 || qty <= 0) continue;

        NSMutableDictionary *entry = aggregated[itemID];
        if (!entry) {
            entry = [@{
                @"qty": @(0),
                @"name": [self pp_firstNonEmptyStringFromDictionary:item keys:@[@"name", @"title"]] ?: itemID,
            } mutableCopy];
            aggregated[itemID] = entry;
        }
        entry[@"qty"] = @([entry[@"qty"] integerValue] + qty);
    }

    NSDictionary<NSString *, NSDictionary *> *fullOrderItems = [self pp_aggregatedOrderItems:order.items];
    if (aggregated.count == 0 && request.itemIDs.count > 0) {
        for (NSString *itemID in request.itemIDs) {
            NSString *resolvedItemID = [self pp_trimmedString:itemID];
            if (resolvedItemID.length == 0) continue;
            NSDictionary *orderEntry = fullOrderItems[resolvedItemID];
            NSInteger qty = [orderEntry[@"qty"] integerValue];
            if (qty <= 0) continue;
            aggregated[resolvedItemID] = [@{
                @"qty": @(qty),
                @"name": orderEntry[@"name"] ?: resolvedItemID,
            } mutableCopy];
        }
    }

    if (aggregated.count == 0) {
        return fullOrderItems;
    }

    NSMutableDictionary<NSString *, NSDictionary *> *clamped = [NSMutableDictionary dictionary];
    for (NSString *itemID in aggregated.allKeys) {
        NSDictionary *requestedEntry = aggregated[itemID];
        NSDictionary *orderEntry = fullOrderItems[itemID];
        NSInteger requestedQty = [requestedEntry[@"qty"] integerValue];
        NSInteger orderedQty = [orderEntry[@"qty"] integerValue];
        NSInteger safeQty = orderedQty > 0 ? MIN(requestedQty, orderedQty) : requestedQty;
        if (safeQty <= 0) continue;
        clamped[itemID] = @{
            @"qty": @(safeQty),
            @"name": requestedEntry[@"name"] ?: orderEntry[@"name"] ?: itemID,
        };
    }
    return clamped.copy;
}

- (NSDictionary *)pp_resolutionPlanForRequest:(PPPaymentAdminSupportRequest *)request
                                        order:(PPPaymentAdminRecord *)order
                                       action:(PPPaymentAdminRequestResolution)action
                                        amount:(NSNumber *)amount
                                     errorOut:(NSError **)errorPointer
{
    NSString *requestType = [self pp_trimmedString:request.type];
    switch (action) {
        case PPPaymentAdminRequestResolutionApprove:
            return @{
                @"requestStatus": @"approved",
                @"finalResolution": @"approved",
                @"orderPatch": @{}
            };

        case PPPaymentAdminRequestResolutionReject:
            return @{
                @"requestStatus": @"rejected",
                @"finalResolution": @"rejected",
                @"orderPatch": @{}
            };

        case PPPaymentAdminRequestResolutionComplete: {
            NSMutableDictionary *orderPatch = [NSMutableDictionary dictionary];
            NSString *normalizedRequestType = [PPPaymentAdminRecord normalizedStatusString:requestType];
            if ([normalizedRequestType isEqualToString:@"return"] ||
                [normalizedRequestType isEqualToString:@"replacement"]) {
                orderPatch[@"returnStatus"] = @"completed";
            }
            return @{
                @"requestStatus": @"completed",
                @"finalResolution": @"completed",
                @"orderPatch": orderPatch
            };
        }

        case PPPaymentAdminRequestResolutionRefund:
        case PPPaymentAdminRequestResolutionPartialRefund: {
            BOOL isPartial = (action == PPPaymentAdminRequestResolutionPartialRefund);
            double orderTotal = MAX(0.0, order.totalAmount);
            double resolvedAmount = amount ? MAX(0.0, amount.doubleValue) : orderTotal;
            if (orderTotal <= 0.0) {
                *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                    code:506
                                                userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_InvalidOrderTotalForRefund")}];
                return nil;
            }
            if (isPartial) {
                if (!(resolvedAmount > 0.0 && resolvedAmount < orderTotal)) {
                    *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                                        code:507
                                                    userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_PartialRefundTooHigh")}];
                    return nil;
                }
            } else {
                resolvedAmount = orderTotal;
            }

            NSString *refundStatus = isPartial ? @"partially_refunded" : @"refunded";
            NSMutableDictionary *orderPatch = [@{
                @"refundStatus": refundStatus,
                @"refundAmount": @(resolvedAmount),
                @"refundedAt": [FIRFieldValue fieldValueForServerTimestamp],
            } mutableCopy];
            return @{
                @"requestStatus": refundStatus,
                @"finalResolution": refundStatus,
                @"orderPatch": orderPatch
            };
        }

        case PPPaymentAdminRequestResolutionClose:
            return @{
                @"requestStatus": @"closed",
                @"finalResolution": [PPPaymentAdminRecord normalizedStatusString:request.finalResolution].length > 0 ? [PPPaymentAdminRecord normalizedStatusString:request.finalResolution] : @"closed",
                @"orderPatch": @{}
            };
    }

    *errorPointer = [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                                        code:508
                                    userInfo:@{NSLocalizedDescriptionKey: kLang(@"PaymentMgmt_Error_UnsupportedResolution")}];
    return nil;
}

- (NSDictionary *)pp_resolutionMetadataWithAction:(PPPaymentAdminRequestResolution)action
                                             note:(NSString *)note
                                           amount:(NSNumber *)amount
{
    NSMutableDictionary *metadata = [@{
        @"action": [self pp_resolutionActionKey:action],
        @"note": [self pp_trimmedString:note],
        @"adminUid": [self pp_currentAdminUID],
        @"adminName": [self pp_currentAdminName],
        @"resolvedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } mutableCopy];
    if (amount && amount.doubleValue > 0.0) {
        metadata[@"amount"] = @(amount.doubleValue);
    }
    return metadata;
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

- (NSString *)pp_auditActionNameForResolutionAction:(PPPaymentAdminRequestResolution)action
                                            request:(PPPaymentAdminSupportRequest *)request
{
    switch (action) {
        case PPPaymentAdminRequestResolutionApprove:
            return [NSString stringWithFormat:@"request_%@_approve", request.type ?: @"support"];
        case PPPaymentAdminRequestResolutionReject:
            return [NSString stringWithFormat:@"request_%@_reject", request.type ?: @"support"];
        case PPPaymentAdminRequestResolutionComplete:
            return [NSString stringWithFormat:@"request_%@_complete", request.type ?: @"support"];
        case PPPaymentAdminRequestResolutionRefund:
            return @"request_refund_refunded";
        case PPPaymentAdminRequestResolutionPartialRefund:
            return @"request_refund_partial";
        case PPPaymentAdminRequestResolutionClose:
            return [NSString stringWithFormat:@"request_%@_close", request.type ?: @"support"];
    }
    return @"request_update";
}

#pragma mark - Admin Notes

- (NSString *)defaultAdminNoteForOrderID:(NSString *)orderID
                               nextStatus:(NSString *)nextStatus
{
    NSString *resolvedOrderID = [self pp_trimmedString:orderID];
    NSString *resolvedStatus = [self pp_trimmedString:nextStatus];
    if (resolvedOrderID.length == 0 || resolvedStatus.length == 0) {
        return @"";
    }

    NSString *adminUID = [self pp_trimmedString:[self pp_currentAdminUID]];
    if (adminUID.length == 0) {
        adminUID = @"admin";
    }

    return [NSString stringWithFormat:@"AD: %@ - %@ - %@", adminUID, resolvedStatus, resolvedOrderID];
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

- (NSDictionary<NSString *, NSDictionary *> *)pp_aggregatedOrderItems:(NSArray<NSDictionary *> *)items
{
    NSMutableDictionary<NSString *, NSMutableDictionary *> *aggregated = [NSMutableDictionary dictionary];
    for (id rawItem in items ?: @[]) {
        if (![rawItem isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *item = (NSDictionary *)rawItem;
        NSString *itemID = [self pp_firstNonEmptyStringFromDictionary:item keys:@[@"id", @"itemID"]];
        NSInteger qty = [item[@"qty"] ?: item[@"quantity"] integerValue];
        if (itemID.length == 0 || qty <= 0) continue;
        NSMutableDictionary *entry = aggregated[itemID];
        if (!entry) {
            entry = [@{
                @"qty": @(0),
                @"name": [self pp_firstNonEmptyStringFromDictionary:item keys:@[@"name", @"title"]] ?: itemID
            } mutableCopy];
            aggregated[itemID] = entry;
        }
        NSInteger currentQty = [entry[@"qty"] integerValue];
        entry[@"qty"] = @(currentQty + qty);
    }
    return aggregated.copy;
}

- (NSDictionary *)pp_auditStateForOrderRecord:(PPPaymentAdminRecord *)record
{
    return @{
        @"status": record.rawStatus ?: @"",
        @"workflowStatus": [record workflowStatusKey] ?: @"",
        @"paymentMethodId": record.paymentMethodId ?: @"",
        @"paymentStatus": record.paymentStatus ?: @"",
        @"paymentProvider": record.paymentProvider ?: @"",
        @"verificationStatus": record.verificationStatus ?: @"",
        @"transactionId": record.transactionId ?: @"",
        @"refundStatus": record.refundStatus ?: @"",
        @"returnStatus": record.returnStatus ?: @"",
        @"inventoryDeducted": @(record.inventoryDeducted),
        @"inventoryRestocked": @(record.inventoryRestocked),
        @"paidAt": record.paidAt ? @((long long)(record.paidAt.timeIntervalSince1970 * 1000)) : @0,
        @"processedAt": record.processedAt ? @((long long)(record.processedAt.timeIntervalSince1970 * 1000)) : @0,
        @"shippedAt": record.shippedAt ? @((long long)(record.shippedAt.timeIntervalSince1970 * 1000)) : @0,
        @"deliveredAt": record.deliveredAt ? @((long long)(record.deliveredAt.timeIntervalSince1970 * 1000)) : @0,
        @"paymentCollectedAt": record.paymentCollectedAt ? @((long long)(record.paymentCollectedAt.timeIntervalSince1970 * 1000)) : @0,
        @"updatedAt": @((long long)(record.updatedAt.timeIntervalSince1970 * 1000)),
    };
}

- (NSDictionary *)pp_auditStateForRequest:(PPPaymentAdminSupportRequest *)request
{
    return @{
        @"requestId": request.requestId ?: @"",
        @"type": request.type ?: @"",
        @"status": request.status ?: @"",
        @"finalResolution": request.finalResolution ?: @"",
        @"updatedAt": @((long long)(request.updatedAt.timeIntervalSince1970 * 1000)),
    };
}

- (void)pp_logAuditInTransaction:(FIRTransaction *)transaction
                           action:(NSString *)action
                            order:(PPPaymentAdminRecord *)order
                           request:(PPPaymentAdminSupportRequest *)request
                             note:(NSString *)note
                            before:(NSDictionary *)before
                             after:(NSDictionary *)after
{
    FIRDocumentReference *auditRef = [[self.db collectionWithPath:@"AdminAuditLogs"] documentWithAutoID];
    [transaction setData:@{
        @"auditId": auditRef.documentID ?: @"",
        @"area": @"payments",
        @"action": action ?: @"payment_update",
        @"entityType": request ? @"request" : @"order",
        @"entityId": request ? (request.requestId ?: @"") : (order.orderId ?: @""),
        @"orderId": order.orderId ?: @"",
        @"requestId": request.requestId ?: @"",
        @"adminUid": [self pp_currentAdminUID],
        @"adminName": [self pp_currentAdminName],
        @"note": [self pp_trimmedString:note],
        @"before": before ?: @{},
        @"after": after ?: @{},
        @"createdAt": [FIRFieldValue fieldValueForServerTimestamp],
    } forDocument:auditRef];
}

- (void)pp_appendOrderEventInTransaction:(FIRTransaction *)transaction
                                orderRef:(FIRDocumentReference *)orderRef
                                    type:(NSString *)type
                                  status:(NSString *)status
                               actorType:(NSString *)actorType
                                 summary:(NSString *)summary
                                metadata:(NSDictionary *)metadata
{
    FIRDocumentReference *eventRef = [[orderRef collectionWithPath:@"events"] documentWithAutoID];
    [transaction setData:@{
        @"eventId": eventRef.documentID ?: @"",
        @"type": type ?: @"request_status_updated",
        @"status": status ?: @"pending",
        @"actorType": actorType ?: @"admin",
        @"summary": summary ?: @"Payment update",
        @"metadata": metadata ?: @{},
        @"createdAt": [FIRFieldValue fieldValueForServerTimestamp],
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } forDocument:eventRef];
}

- (void)pp_appendRequestEventInTransaction:(FIRTransaction *)transaction
                                requestRef:(FIRDocumentReference *)requestRef
                                      type:(NSString *)type
                                    status:(NSString *)status
                                 actorType:(NSString *)actorType
                                   summary:(NSString *)summary
                                  metadata:(NSDictionary *)metadata
{
    FIRDocumentReference *eventRef = [[requestRef collectionWithPath:@"events"] documentWithAutoID];
    [transaction setData:@{
        @"eventId": eventRef.documentID ?: @"",
        @"type": type ?: @"request_status_updated",
        @"status": status ?: @"pending_review",
        @"actorType": actorType ?: @"admin",
        @"summary": summary ?: @"Request update",
        @"metadata": metadata ?: @{},
        @"createdAt": [FIRFieldValue fieldValueForServerTimestamp],
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } forDocument:eventRef];
}

- (NSDictionary *)pp_currentAdminSummary
{
    return @{
        @"uid": [self pp_currentAdminUID],
        @"name": [self pp_currentAdminName],
    };
}

- (BOOL)pp_shouldRetryOrderMutationViaCallable:(NSError *)error
{
    if (!error) return NO;
    if (error.code == FIRFirestoreErrorCodePermissionDenied) {
        return YES;
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        underlying.code == FIRFirestoreErrorCodePermissionDenied) {
        return YES;
    }

    NSString *message = [[self pp_trimmedString:error.localizedDescription] lowercaseString];
    return ([message containsString:@"missing or insufficient permissions"] ||
            [message containsString:@"insufficient permissions"] ||
            [message containsString:@"permission denied"]);
}

- (void)pp_retryOrderMutationViaCallableAction:(NSString *)action
                                       orderID:(NSString *)orderID
                                          note:(NSString *)note
                                    completion:(PPPaymentAdminRecordCompletion)completion
{
    FIRHTTPSCallable *callable = [[self pp_functionsClient] HTTPSCallableWithName:@"adminTransitionOrderStatus"];
    NSDictionary *payload = @{
        @"orderId": [self pp_trimmedString:orderID] ?: @"",
        @"action": [self pp_trimmedString:action] ?: @"",
        @"note": [self pp_trimmedString:note] ?: @"",
    };

    [callable callWithObject:payload
                  completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ [PPPaymentManagementService] callable %@ failed: %@", action, error.localizedDescription);
            [self pp_completeRecord:nil error:error completion:completion];
            return;
        }

        NSDictionary *data = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : @{};
        NSString *resolvedOrderID = [self pp_trimmedString:data[@"orderId"]];
        if (resolvedOrderID.length == 0) {
            resolvedOrderID = [self pp_trimmedString:orderID];
        }
        [self loadFullRecordForOrderID:resolvedOrderID completion:completion];
    }];
}

- (NSString *)pp_currentAdminUID
{
    return [self pp_trimmedString:[FIRAuth auth].currentUser.uid];
}

- (NSString *)pp_currentAdminName
{
    UserModel *currentUser = [UserManager shared].currentUser;
    NSString *displayName = [self pp_trimmedString:[currentUser respondsToSelector:@selector(PPBestDisplayName)] ? [currentUser PPBestDisplayName] : currentUser.displayName];
    if (displayName.length > 0) return displayName;
    return @"Admin";
}

- (NSError *)pp_invalidTransitionError:(NSString *)message
{
    return [NSError errorWithDomain:PPPaymentAdminServiceErrorDomain
                               code:409
                           userInfo:@{NSLocalizedDescriptionKey: message ?: kLang(@"PaymentMgmt_Error_InvalidTransition")}];
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
