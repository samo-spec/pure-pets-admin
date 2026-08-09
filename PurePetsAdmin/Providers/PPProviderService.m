#import "PPProviderService.h"
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

@implementation PPProviderApplication
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _applicationID = docID ?: @"";
        _userId = PPSafeString(dict[@"userId"]);
        _providerType = PPSafeString(dict[@"providerType"]);
        _status = PPSafeString(dict[@"status"]);
        _form = PPSafeDict(dict[@"form"]);
        _createdAt = PPProviderServiceDate(dict[@"submittedAt"] ?: dict[@"createdAt"]);
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
    [[db collectionWithPath:@"providerApplications"] getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSMutableArray *apps = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [apps addObject:[[PPProviderApplication alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        [apps sortUsingComparator:^NSComparisonResult(PPProviderApplication *left, PPProviderApplication *right) {
            NSDate *leftDate = left.createdAt ?: NSDate.distantPast;
            NSDate *rightDate = right.createdAt ?: NSDate.distantPast;
            return [rightDate compare:leftDate];
        }];
        if (completion) completion(apps.copy, nil);
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

- (void)reviewApplication:(NSString *)appID status:(NSString *)status notes:(nullable NSString *)notes completion:(void(^)(NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"reviewProviderApplication"];
    [callable callWithObject:@{
        @"applicationId": appID,
        @"decision": status,
        @"reviewNotes": notes ?: @""
    } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(error);
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

@end