#import "PPProviderService.h"
#import "PPStaffAuth.h"
@import FirebaseFirestore;
@import FirebaseAuth;
@import FirebaseFunctions;

static NSDate *PPProviderServiceDate(id value) {
    if ([value isKindOfClass:NSDate.class]) return value;
    if ([value isKindOfClass:FIRTimestamp.class]) return [(FIRTimestamp *)value dateValue];
    if ([value isKindOfClass:NSNumber.class]) return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = value;
        NSNumber *seconds = PPSafeNumber(dictionary[@"_seconds"] ?: dictionary[@"seconds"]);
        if (seconds) return [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    }
    if ([value isKindOfClass:NSString.class]) {
        NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
        return [formatter dateFromString:value];
    }
    return nil;
}

static BOOL PPProviderLedgerStaffCanRead(PPStaffDoc *staff) {
    PPStaffDoc *current = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *authUID = [FIRAuth auth].currentUser.uid;
    return (staff != nil && current == staff && authUID.length > 0 &&
            [staff.uid isEqualToString:authUID] && staff.isActive &&
            (staff.isAdmin || staff.hasGlobalScope) &&
            [staff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]]);
}

static NSError *PPProviderLedgerAccessError(void) {
    return [NSError errorWithDomain:@"PPProviderService"
                               code:403
                           userInfo:@{NSLocalizedDescriptionKey: kLang(@"PPOrder_Error_LedgerRestricted")}];
}

@implementation PPProviderApplication
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        NSDictionary *safe = PPSafeDict(dict);
        _applicationID = [PPSafeString(docID) copy];
        _userId = [PPSafeString(safe[@"userId"]) copy];
        _providerType = [PPSafeString(safe[@"providerType"]) copy];
        _status = [PPSafeString(safe[@"status"]) copy];
        _planId = [PPSafeString(safe[@"planId"]) copy];
        _profileId = [PPSafeString(safe[@"profileId"]) copy];
        _deliveryCompanyId = [PPSafeString(safe[@"deliveryCompanyId"]) copy];
        _form = [PPSafeDict(safe[@"form"]) copy];
        _planSnapshot = [PPSafeDict(safe[@"planSnapshot"]) copy];
        _userSummary = [PPSafeDict(safe[@"userSummary"]) copy];
        _submittedAt = PPProviderServiceDate(safe[@"submittedAt"]);
        _createdAt = PPProviderServiceDate(safe[@"createdAt"]);
        _updatedAt = PPProviderServiceDate(safe[@"updatedAt"]);
        _reviewedAt = PPProviderServiceDate(safe[@"reviewedAt"]);
        _reviewedBy = [PPSafeString(safe[@"reviewedBy"]) copy];
        _reviewNotes = [PPSafeString(safe[@"reviewNotes"]) copy];
        _rejectionReason = [PPSafeString(safe[@"rejectionReason"]) copy];
        _rejectionCode = [PPSafeString(safe[@"rejectionCode"]) copy];
        _reviewFindings = [PPSafeArray(safe[@"reviewFindings"]) copy];
        _activationChecklist = [PPSafeDict(safe[@"activationChecklist"]) copy];
        _resubmissionCount = PPSafeIntegerUniversal(safe[@"resubmissionCount"]);
        _version = PPSafeIntegerUniversal(safe[@"version"]);
        if (_version < 1) _version = 1;
        _tags = [PPSafeArray(safe[@"tags"]) copy];
        _documents = [PPSafeDict(safe[@"documents"]) copy];
    }
    return self;
}
@end

@implementation PPProviderPlan
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _planID = docID ?: @"";
        _name = PPSafeDict(dict[@"name"]);
        _planDescription = PPSafeDict(dict[@"description"]);
        _providerType = PPSafeString(dict[@"providerType"]);
        _costType = PPSafeString(dict[@"costType"]);
        _costValue = PPSafeDouble(dict[@"costValue"] ?: dict[@"priceAmount"] ?: dict[@"price"]);
        _price = @(_costValue);
        _currency = PPSafeString(dict[@"currency"]);
        if (_currency.length == 0) _currency = @"QAR";
        _billingInterval = PPSafeString(dict[@"billingInterval"]);
        _commissionRate = PPSafeDouble(dict[@"platformCommissionRate"]);
        _status = PPSafeString(dict[@"status"]);
        _features = PPSafeArray(dict[@"features"]);
        _featureDocuments = @[];
        _featureCount = PPSafeIntegerUniversal(dict[@"featureCount"]);
        if (_featureCount == 0) _featureCount = _features.count;
        _rank = PPSafeIntegerUniversal(dict[@"rank"]);
        _recommended = [dict[@"recommended"] respondsToSelector:@selector(boolValue)] ? [dict[@"recommended"] boolValue] : NO;
    }
    return self;
}
@end

@implementation PPProviderCommissionRecord

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _recordID = PPSafeString(dict[@"id"] ?: dict[@"ledgerId"]);
        _providerID = PPSafeString(dict[@"providerID"] ?: dict[@"providerId"]);
        _orderID = PPSafeString(dict[@"orderID"]);
        _fulfillmentID = PPSafeString(dict[@"fulfillmentID"]);
        _planID = PPSafeString(dict[@"planID"]);
        _currency = PPSafeString(dict[@"currency"]);
        if (_currency.length == 0) _currency = @"QAR";
        _status = PPSafeString(dict[@"status"]);
        _grossSaleAmount = PPSafeDouble(dict[@"grossSaleAmount"]);
        _platformCommissionAmount = PPSafeDouble(dict[@"platformCommissionAmount"]);
        _providerNetAmount = PPSafeDouble(dict[@"providerNetAmount"]);
        _commissionRate = PPSafeDouble(dict[@"commissionRateSnapshot"]);
        _createdAt = PPProviderServiceDate(dict[@"createdAt"]);
    }
    return self;
}

@end

@implementation PPProviderService

+ (instancetype)shared {
    static PPProviderService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (void)fetchApplicationsWithCompletion:(void(^)(NSArray<PPProviderApplication *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"providerApplications"] queryWhereField:@"providerType" in:@[
        @"delivery_company",
        @"service",
        @"marketplace",
        @"pharmacy",
        @"vet"
    ]];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSMutableArray *apps = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [apps addObject:[[PPProviderApplication alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        [apps sortUsingComparator:^NSComparisonResult(PPProviderApplication *left, PPProviderApplication *right) {
            NSDate *leftDate = left.submittedAt ?: left.createdAt ?: left.updatedAt ?: NSDate.distantPast;
            NSDate *rightDate = right.submittedAt ?: right.createdAt ?: right.updatedAt ?: NSDate.distantPast;
            return [rightDate compare:leftDate];
        }];
        if (completion) completion(apps.copy, nil);
    }];
}

- (id<FIRListenerRegistration>)listenApplicationsWithUpdate:(void(^)(NSArray<PPProviderApplication *> *, NSError *))updateBlock {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"providerApplications"] queryWhereField:@"providerType" in:@[
        @"delivery_company",
        @"service",
        @"marketplace",
        @"pharmacy",
        @"vet"
    ]];
    return [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (updateBlock) updateBlock(@[], error);
            return;
        }
        NSMutableArray *apps = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [apps addObject:[[PPProviderApplication alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        [apps sortUsingComparator:^NSComparisonResult(PPProviderApplication *left, PPProviderApplication *right) {
            NSDate *leftDate = left.submittedAt ?: left.createdAt ?: left.updatedAt ?: NSDate.distantPast;
            NSDate *rightDate = right.submittedAt ?: right.createdAt ?: right.updatedAt ?: NSDate.distantPast;
            return [rightDate compare:leftDate];
        }];
        if (updateBlock) updateBlock(apps.copy, nil);
    }];
}

- (void)fetchPlansWithCompletion:(void(^)(NSArray<PPProviderPlan *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[db collectionWithPath:@"providerPlans"] getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSMutableArray *plans = [NSMutableArray array];
        dispatch_group_t group = dispatch_group_create();
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPProviderPlan *plan = [[PPProviderPlan alloc] initWithDictionary:doc.data documentID:doc.documentID];
            [plans addObject:plan];
            dispatch_group_enter(group);
            [[[[db collectionWithPath:@"providerPlans"] documentWithPath:doc.documentID] collectionWithPath:@"features"]
             getDocumentsWithCompletion:^(FIRQuerySnapshot *featureSnapshot, NSError *featureError) {
                if (!featureError) {
                    NSMutableArray<NSDictionary *> *documents = [NSMutableArray array];
                    for (FIRDocumentSnapshot *featureDocument in featureSnapshot.documents) {
                        NSMutableDictionary *value = [PPSafeDict(featureDocument.data) mutableCopy];
                        value[@"featureId"] = featureDocument.documentID ?: @"";
                        [documents addObject:value.copy];
                    }
                    [documents sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
                        NSInteger leftOrder = PPSafeIntegerUniversal(left[@"sortOrder"]);
                        NSInteger rightOrder = PPSafeIntegerUniversal(right[@"sortOrder"]);
                        if (leftOrder != rightOrder) return leftOrder < rightOrder ? NSOrderedAscending : NSOrderedDescending;
                        return [PPSafeString(left[@"featureKey"]) compare:PPSafeString(right[@"featureKey"])];
                    }];
                    plan.featureDocuments = documents.copy;
                    plan.featureCount = documents.count;
                }
                dispatch_group_leave(group);
            }];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [plans sortUsingComparator:^NSComparisonResult(PPProviderPlan *left, PPProviderPlan *right) {
                if (left.rank != right.rank) return left.rank < right.rank ? NSOrderedAscending : NSOrderedDescending;
                if (left.costValue != right.costValue) return left.costValue < right.costValue ? NSOrderedAscending : NSOrderedDescending;
                return [left.planID compare:right.planID];
            }];
            if (completion) completion(plans.copy, nil);
        });
    }];
}

- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
                completion:(void(^)(NSDictionary *, NSError *))completion {
    [self reviewApplication:appID status:status notes:notes rejectionCode:nil reviewFindings:nil completion:completion];
}

- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
             rejectionCode:(nullable NSString *)rejectionCode
            reviewFindings:(nullable NSArray<NSDictionary *> *)reviewFindings
                completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self reviewApplication:appID status:status notes:notes rejectionCode:rejectionCode reviewFindings:reviewFindings expectedVersion:nil completion:completion];
}

- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
             rejectionCode:(nullable NSString *)rejectionCode
            reviewFindings:(nullable NSArray<NSDictionary *> *)reviewFindings
           expectedVersion:(nullable NSNumber *)expectedVersion
                completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self reviewApplication:appID status:status notes:notes rejectionCode:rejectionCode reviewFindings:reviewFindings expectedVersion:expectedVersion idempotencyKey:nil completion:completion];
}

- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
             rejectionCode:(nullable NSString *)rejectionCode
            reviewFindings:(nullable NSArray<NSDictionary *> *)reviewFindings
           expectedVersion:(nullable NSNumber *)expectedVersion
            idempotencyKey:(nullable NSString *)idempotencyKey
                completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"reviewProviderApplication"];
    NSMutableDictionary *payload = [@{
        @"applicationId": appID ?: @"",
        @"decision": status ?: @"",
        @"reviewNotes": notes ?: @""
    } mutableCopy];
    if (rejectionCode.length > 0) {
        payload[@"rejectionCode"] = rejectionCode;
        payload[@"rejectionReason"] = notes ?: @"";
    }
    if (reviewFindings.count > 0) {
        payload[@"reviewFindings"] = reviewFindings;
    }
    if (expectedVersion) {
        payload[@"expectedVersion"] = expectedVersion;
    }
    NSString *effectiveKey = idempotencyKey ?: [NSString stringWithFormat:@"rev_%@_%@_%@", appID ?: @"app", status ?: @"stat", [[NSUUID UUID] UUIDString].lowercaseString];
    payload[@"idempotencyKey"] = effectiveKey;

    [callable callWithObject:payload.copy completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(PPSafeDict(result.data), error);
    }];
}

- (void)savePlan:(NSDictionary *)planData completion:(void(^)(NSString *, NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"saveProviderPlan"];
    [callable callWithObject:planData completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(PPSafeString(data[@"planId"]), error);
    }];
}

- (void)deletePlan:(NSString *)planID completion:(void(^)(NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"deleteProviderPlan"];
    [callable callWithObject:@{@"planId": planID} completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)fetchCommissionReportForProviderID:(NSString *)providerID
                                completion:(void(^)(NSArray<PPProviderCommissionRecord *> *, NSArray<NSDictionary *> *, NSError *))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (!PPProviderLedgerStaffCanRead(staff)) {
        if (completion) completion(@[], @[], PPProviderLedgerAccessError());
        return;
    }
    NSString *cleanProviderID = [PPSafeString(providerID) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (cleanProviderID.length == 0) {
        NSError *error = [NSError errorWithDomain:@"PPProviderService"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: kLang(@"Providers_Accounting_ProviderRequired")}];
        if (completion) completion(@[], @[], error);
        return;
    }
    FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:@"getProviderCommissionReport"];
    [callable callWithObject:@{@"providerID": cleanProviderID} completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (!PPProviderLedgerStaffCanRead(staff)) {
            if (completion) completion(@[], @[], PPProviderLedgerAccessError());
            return;
        }
        if (error) {
            if (completion) completion(@[], @[], error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        NSMutableArray<PPProviderCommissionRecord *> *records = [NSMutableArray array];
        for (id value in PPSafeArray(data[@"rows"])) {
            NSDictionary *row = PPSafeDict(value);
            if (row.count) [records addObject:[[PPProviderCommissionRecord alloc] initWithDictionary:row]];
        }
        [records sortUsingComparator:^NSComparisonResult(PPProviderCommissionRecord *left, PPProviderCommissionRecord *right) {
            return [(right.createdAt ?: NSDate.distantPast) compare:(left.createdAt ?: NSDate.distantPast)];
        }];
        if (completion) completion(records.copy, PPSafeArray(data[@"totals"]), nil);
    }];
}

- (void)batchAssignReviewer:(NSArray<NSString *> *)applicationIDs
                 reviewerUid:(NSString *)reviewerUid
                  completion:(void(^)(NSInteger updatedCount, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"batchAssignProviderReviewer"];
    [callable callWithObject:@{
        @"applicationIds": applicationIDs ?: @[],
        @"reviewerUid": reviewerUid ?: @""
    } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(0, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        NSInteger count = PPSafeIntegerUniversal(data[@"updatedCount"]);
        if (completion) completion(count, nil);
    }];
}

- (void)batchAddTag:(NSArray<NSString *> *)applicationIDs
                 tag:(NSString *)tag
          completion:(void(^)(NSInteger updatedCount, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"batchTagProviderApplications"];
    [callable callWithObject:@{
        @"applicationIds": applicationIDs ?: @[],
        @"tag": tag ?: @""
    } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(0, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        NSInteger count = PPSafeIntegerUniversal(data[@"updatedCount"]);
        if (completion) completion(count, nil);
    }];
}

- (void)reviewApplicationDocument:(NSString *)applicationID
                     documentType:(NSString *)documentType
                         decision:(NSString *)decision
                          finding:(nullable NSString *)finding
                       expiryDate:(nullable NSString *)expiryDate
                       completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"reviewApplicationDocument"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"applicationId"] = applicationID ?: @"";
    payload[@"documentType"] = documentType ?: @"";
    payload[@"decision"] = decision ?: @"";
    if (finding.length > 0) {
        payload[@"finding"] = finding;
    }
    if (expiryDate.length > 0) {
        payload[@"expiryDate"] = expiryDate;
    }
    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)fetchPartnerSyncSnapshot:(NSString *)partnerId
                   clientVersion:(nullable NSNumber *)clientVersion
                      completion:(void(^)(BOOL inSync, BOOL catchUpRequired, NSDictionary * _Nullable snapshot, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"fetchPartnerSyncSnapshot"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    if (clientVersion) {
        payload[@"clientVersion"] = clientVersion;
    }

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(NO, NO, nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        BOOL inSync = [data[@"inSync"] boolValue];
        BOOL catchUp = [data[@"catchUpRequired"] boolValue];
        if (completion) completion(inSync, catchUp, data, nil);
    }];
}

- (void)reconcilePartnerReadModels:(NSString *)partnerId
                        completion:(void(^)(BOOL reconciled, NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"syncPartnerReadModels"];
    NSDictionary *payload = @{
        @"partnerId": partnerId ?: @"",
        @"force": @YES,
    };

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(NO, nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        BOOL reconciled = [data[@"reconciled"] boolValue];
        if (completion) completion(reconciled, data, nil);
    }];
}

- (void)restrictPartnerAccount:(NSString *)partnerId
                         scope:(NSString *)scope
                   scopeTarget:(nullable NSString *)scopeTarget
                    reasonCode:(NSString *)reasonCode
                internalReason:(nullable NSString *)internalReason
           partnerFacingReason:(nullable NSString *)partnerFacingReason
         partnerFacingReasonAr:(nullable NSString *)partnerFacingReasonAr
                requiredAction:(nullable NSString *)requiredAction
              requiredActionAr:(nullable NSString *)requiredActionAr
               expectedVersion:(nullable NSNumber *)expectedVersion
                idempotencyKey:(nullable NSString *)idempotencyKey
                    completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"restrictPartnerAccount"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    payload[@"scope"] = scope ?: @"full_account";
    if (scopeTarget.length > 0) payload[@"scopeTarget"] = scopeTarget;
    payload[@"reasonCode"] = reasonCode.length > 0 ? reasonCode : @"TEMPORARY_RESTRICTION";
    if (internalReason.length > 0) payload[@"internalReason"] = internalReason;
    if (partnerFacingReason.length > 0) payload[@"partnerFacingReason"] = partnerFacingReason;
    if (partnerFacingReasonAr.length > 0) payload[@"partnerFacingReason_ar"] = partnerFacingReasonAr;
    if (requiredAction.length > 0) payload[@"requiredAction"] = requiredAction;
    if (requiredActionAr.length > 0) payload[@"requiredAction_ar"] = requiredActionAr;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;
    if (idempotencyKey.length > 0) payload[@"idempotencyKey"] = idempotencyKey;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)suspendPartnerAccount:(NSString *)partnerId
                        scope:(NSString *)scope
                  scopeTarget:(nullable NSString *)scopeTarget
                   reasonCode:(NSString *)reasonCode
               internalReason:(nullable NSString *)internalReason
          partnerFacingReason:(nullable NSString *)partnerFacingReason
        partnerFacingReasonAr:(nullable NSString *)partnerFacingReasonAr
               requiredAction:(nullable NSString *)requiredAction
             requiredActionAr:(nullable NSString *)requiredActionAr
              expectedVersion:(nullable NSNumber *)expectedVersion
               idempotencyKey:(nullable NSString *)idempotencyKey
                   completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"suspendPartnerAccount"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    payload[@"scope"] = scope ?: @"full_account";
    if (scopeTarget.length > 0) payload[@"scopeTarget"] = scopeTarget;
    payload[@"reasonCode"] = reasonCode.length > 0 ? reasonCode : @"SUSPENSION_ENFORCED";
    if (internalReason.length > 0) payload[@"internalReason"] = internalReason;
    if (partnerFacingReason.length > 0) payload[@"partnerFacingReason"] = partnerFacingReason;
    if (partnerFacingReasonAr.length > 0) payload[@"partnerFacingReason_ar"] = partnerFacingReasonAr;
    if (requiredAction.length > 0) payload[@"requiredAction"] = requiredAction;
    if (requiredActionAr.length > 0) payload[@"requiredAction_ar"] = requiredActionAr;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;
    if (idempotencyKey.length > 0) payload[@"idempotencyKey"] = idempotencyKey;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)liftPartnerRestriction:(NSString *)partnerId
                 restrictionId:(NSString *)restrictionId
                    liftReason:(NSString *)liftReason
                  liftReasonAr:(nullable NSString *)liftReasonAr
               expectedVersion:(nullable NSNumber *)expectedVersion
                idempotencyKey:(nullable NSString *)idempotencyKey
                    completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"liftPartnerAccountRestriction"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    payload[@"restrictionId"] = restrictionId ?: @"";
    payload[@"liftReason"] = liftReason ?: @"";
    if (liftReasonAr.length > 0) payload[@"liftReason_ar"] = liftReasonAr;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;
    if (idempotencyKey.length > 0) payload[@"idempotencyKey"] = idempotencyKey;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)fetchPartnerRestrictions:(NSString *)partnerId
                      completion:(void(^)(NSDictionary * _Nullable summary, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"getPartnerRestrictionsSummary"];
    NSDictionary *payload = @{
        @"partnerId": partnerId ?: @"",
    };

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        NSDictionary *summary = [data[@"summary"] isKindOfClass:NSDictionary.class] ? data[@"summary"] : data;
        if (completion) completion(summary, nil);
    }];
}

- (void)reviewPartnerReactivation:(NSString *)partnerId
                        requestId:(NSString *)requestId
                         decision:(NSString *)decision
                       conditions:(nullable NSArray<NSString *> *)conditions
                  rejectionReason:(nullable NSString *)rejectionReason
                rejectionReasonAr:(nullable NSString *)rejectionReasonAr
                       adminNotes:(nullable NSString *)adminNotes
                  expectedVersion:(nullable NSNumber *)expectedVersion
                   idempotencyKey:(nullable NSString *)idempotencyKey
                       completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"reviewPartnerReactivationRequest"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    payload[@"requestId"] = requestId ?: @"";
    payload[@"decision"] = decision ?: @"";
    if (conditions) payload[@"conditions"] = conditions;
    if (rejectionReason.length > 0) payload[@"rejectionReason"] = rejectionReason;
    if (rejectionReasonAr.length > 0) payload[@"rejectionReason_ar"] = rejectionReasonAr;
    if (adminNotes.length > 0) payload[@"adminNotes"] = adminNotes;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;
    if (idempotencyKey.length > 0) payload[@"idempotencyKey"] = idempotencyKey;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)reinstatePartner:(NSString *)partnerId
                  reason:(NSString *)reason
                reasonAr:(nullable NSString *)reasonAr
              conditions:(nullable NSArray<NSString *> *)conditions
         expectedVersion:(nullable NSNumber *)expectedVersion
          idempotencyKey:(nullable NSString *)idempotencyKey
              completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"reinstatePartnerAccount"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    payload[@"reinstateReason"] = reason ?: @"";
    if (reasonAr.length > 0) payload[@"reinstateReason_ar"] = reasonAr;
    if (conditions) payload[@"conditions"] = conditions;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;
    if (idempotencyKey.length > 0) payload[@"idempotencyKey"] = idempotencyKey;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)fetchPartnerReactivationDossier:(NSString *)partnerId
                             completion:(void(^)(NSDictionary * _Nullable dossier, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"getPartnerReactivationDossierData"];
    NSDictionary *payload = @{
        @"partnerId": partnerId ?: @"",
    };

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        NSDictionary *dossier = [data[@"dossier"] isKindOfClass:NSDictionary.class] ? data[@"dossier"] : data;
        if (completion) completion(dossier, nil);
    }];
}

- (void)initiatePartnerOffboarding:(NSString *)partnerId
                   offboardingType:(NSString *)offboardingType
                        reasonCode:(NSString *)reasonCode
                            reason:(NSString *)reason
                          reasonAr:(nullable NSString *)reasonAr
                   expectedVersion:(nullable NSNumber *)expectedVersion
                    idempotencyKey:(nullable NSString *)idempotencyKey
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"initiatePartnerOffboardingWorkflow"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    payload[@"offboardingType"] = offboardingType ?: @"involuntary";
    payload[@"reasonCode"] = reasonCode ?: @"other";
    payload[@"reason"] = reason ?: @"";
    if (reasonAr.length > 0) payload[@"reason_ar"] = reasonAr;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;
    if (idempotencyKey.length > 0) payload[@"idempotencyKey"] = idempotencyKey;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)resolvePartnerOffboardingOperations:(NSString *)partnerId
                       remainingOrdersCount:(nullable NSNumber *)remainingOrdersCount
                                      notes:(nullable NSString *)notes
                            expectedVersion:(nullable NSNumber *)expectedVersion
                                 completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"resolvePartnerOffboardingOperations"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    if (remainingOrdersCount) payload[@"remainingOrdersCount"] = remainingOrdersCount;
    if (notes.length > 0) payload[@"notes"] = notes;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)settlePartnerOffboarding:(NSString *)partnerId
             settlementReference:(nullable NSString *)settlementReference
                           notes:(nullable NSString *)notes
                 expectedVersion:(nullable NSNumber *)expectedVersion
                      completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"settlePartnerOffboarding"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    if (settlementReference.length > 0) payload[@"settlementReference"] = settlementReference;
    if (notes.length > 0) payload[@"notes"] = notes;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)finalizePartnerOffboarding:(NSString *)partnerId
                     forceOverride:(BOOL)forceOverride
                    overrideReason:(nullable NSString *)overrideReason
                   expectedVersion:(nullable NSNumber *)expectedVersion
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"finalizePartnerOffboardingWorkflow"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    payload[@"forceOverride"] = @(forceOverride);
    if (overrideReason.length > 0) payload[@"overrideReason"] = overrideReason;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)fetchPartnerOffboardingDossier:(NSString *)partnerId
                            completion:(void(^)(NSDictionary * _Nullable dossier, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"getPartnerOffboardingDossierData"];
    NSDictionary *payload = @{
        @"partnerId": partnerId ?: @"",
    };

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        NSDictionary *dossier = [data[@"dossier"] isKindOfClass:NSDictionary.class] ? data[@"dossier"] : data;
        if (completion) completion(dossier, nil);
    }];
}

- (void)fetchPartnerAuditTrail:(NSString *)partnerId
                         limit:(nullable NSNumber *)limit
                filterCategory:(nullable NSString *)filterCategory
                    completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"getPartnerAuditTrail"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    if (limit) payload[@"limit"] = limit;
    if (filterCategory && filterCategory.length > 0) payload[@"filterCategory"] = filterCategory;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)verifyPartnerAuditProvenance:(NSString *)partnerId
            includeComplianceDossier:(BOOL)includeComplianceDossier
                          completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"verifyPartnerAuditProvenance"];
    NSDictionary *payload = @{
        @"partnerId": partnerId ?: @"",
        @"includeComplianceDossier": @(includeComplianceDossier),
    };

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)redactPartnerPersonalData:(NSString *)partnerId
                      legalReason:(nullable NSString *)legalReason
                        requestId:(nullable NSString *)requestId
                  expectedVersion:(nullable NSNumber *)expectedVersion
                       completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"redactPartnerPersonalData"];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"partnerId"] = partnerId ?: @"";
    if (legalReason && legalReason.length > 0) payload[@"legalReason"] = legalReason;
    if (requestId && requestId.length > 0) payload[@"requestId"] = requestId;
    if (expectedVersion) payload[@"expectedVersion"] = expectedVersion;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)exportPartnerPrivacyData:(NSString *)partnerId
                      completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"exportPartnerPrivacyData"];
    NSDictionary *payload = @{
        @"partnerId": partnerId ?: @"",
    };

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = PPSafeDict(result.data);
        if (completion) completion(data, nil);
    }];
}

- (void)fetchPartnerCockpitSummary:(NSString *)partnerId
                        clientEtag:(nullable NSString *)clientEtag
                      forceRefresh:(BOOL)forceRefresh
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    if (partnerId.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"PPProviderService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"partnerId is required"}]);
        }
        return;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:partnerId forKey:@"partnerId"];
    if (clientEtag.length > 0) {
        payload[@"clientEtag"] = clientEtag;
    }
    if (forceRefresh) {
        payload[@"forceRefresh"] = @YES;
    }

    FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:@"getPartnerCockpitSummary"];
    callable.timeoutInterval = 20.0;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            NSDictionary *data = [result.data isKindOfClass:[NSDictionary class]] ? (NSDictionary *)result.data : @{};
            if (completion) completion(data, nil);
        });
    }];
}

- (void)fetchPartnerObservabilityDashboardWithCompletion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"getPartnerObservabilityDashboard"];
    callable.timeoutInterval = 30.0;

    [callable callWithObject:@{} completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            NSDictionary *data = [result.data isKindOfClass:[NSDictionary class]] ? (NSDictionary *)result.data : @{};
            if (completion) completion(data, nil);
        });
    }];
}

- (void)reconstructPartnerState:(NSString *)partnerId
                           mode:(NSString *)mode
                  upToTimestamp:(nullable NSString *)upToTimestamp
                   repairReason:(nullable NSString *)repairReason
                     completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    if (partnerId.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"PPProviderService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"partnerId is required"}]);
        }
        return;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:partnerId forKey:@"partnerId"];
    payload[@"mode"] = mode.length > 0 ? mode : @"DRY_RUN";
    if (upToTimestamp.length > 0) payload[@"upToTimestamp"] = upToTimestamp;
    if (repairReason.length > 0) payload[@"repairReason"] = repairReason;

    FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:@"reconstructPartnerState"];
    callable.timeoutInterval = 60.0;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            NSDictionary *data = [result.data isKindOfClass:[NSDictionary class]] ? (NSDictionary *)result.data : @{};
            if (completion) completion(data, nil);
        });
    }];
}

- (void)fetchPartnerDisasterRecoveryDashboardWithCompletion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"getPartnerDisasterRecoveryDashboard"];
    callable.timeoutInterval = 30.0;

    [callable callWithObject:@{} completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            NSDictionary *data = [result.data isKindOfClass:[NSDictionary class]] ? (NSDictionary *)result.data : @{};
            if (completion) completion(data, nil);
        });
    }];
}

- (void)createPartnerCheckpointSnapshot:(NSString *)partnerId
                             completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    if (partnerId.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"PPProviderService" code:400 userInfo:@{NSLocalizedDescriptionKey: @"partnerId is required"}]);
        }
        return;
    }

    NSDictionary *payload = @{ @"partnerId": partnerId };
    FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:@"createPartnerCheckpointSnapshot"];
    callable.timeoutInterval = 30.0;

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            NSDictionary *data = [result.data isKindOfClass:[NSDictionary class]] ? (NSDictionary *)result.data : @{};
            if (completion) completion(data, nil);
        });
    }];
}

@end
