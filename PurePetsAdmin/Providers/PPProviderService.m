#import "PPProviderService.h"
@import FirebaseAuth;
@import FirebaseFunctions;

@implementation PPProviderApplication
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _applicationID = docID ?: @"";
        _userId = PPSafeString(dict[@"userId"]);
        _providerType = PPSafeString(dict[@"providerType"]);
        _status = PPSafeString(dict[@"status"]);
        _form = PPSafeDict(dict[@"form"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
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
        _providerType = PPSafeString(dict[@"providerType"]);
        _price = PPSafeNumber(dict[@"price"]);
        _billingInterval = PPSafeString(dict[@"billingInterval"]);
        _commissionRate = PPSafeDouble(dict[@"platformCommissionRate"]);
        _status = PPSafeString(dict[@"status"]);
        _features = PPSafeArray(dict[@"features"]);
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
    [[[db collectionWithPath:@"providerApplications"] queryOrderedByField:@"createdAt" descending:YES]
     getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSMutableArray *apps = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [apps addObject:[[PPProviderApplication alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (completion) completion(apps, nil);
    }];
}

- (void)fetchPlansWithCompletion:(void(^)(NSArray<PPProviderPlan *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[[db collectionWithPath:@"providerPlans"] queryOrderedByField:@"price" ascending:YES]
     getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSMutableArray *plans = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [plans addObject:[[PPProviderPlan alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (completion) completion(plans, nil);
    }];
}

- (void)reviewApplication:(NSString *)appID status:(NSString *)status notes:(nullable NSString *)notes completion:(void(^)(NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    [functions callFunction:@"reviewProviderApplication" parameters:@{
        @"applicationId": appID,
        @"status": status,
        @"reviewNotes": notes ?: @""
    } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)savePlan:(NSDictionary *)planData completion:(void(^)(NSString *, NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    [functions callFunction:@"saveProviderPlan" parameters:planData completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(result.data[@"planId"] ?: @"", error);
    }];
}

- (void)deletePlan:(NSString *)planID completion:(void(^)(NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    [functions callFunction:@"deleteProviderPlan" parameters:@{@"planId": planID} completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(error);
    }];
}

@end