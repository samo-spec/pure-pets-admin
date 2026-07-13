#import "PPDeliveryService.h"

static NSString * const kPPCompanyID = @"purepets_deliveries";

@implementation PPDeliveryRequestRecord
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _requestID = docID ?: @"";
        _orderID = PPSafeString(dict[@"orderId"]);
        _orderNumber = PPSafeString(dict[@"orderNumber"]);
        _status = PPSafeString(dict[@"status"]);
        _customerName = PPSafeString(dict[@"customerName"]);
        _assignedDriverName = PPSafeString(dict[@"assignedDriverName"]);
        _deliveryFee = PPSafeNumber(dict[@"deliveryFee"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
    }
    return self;
}
@end

@implementation PPDeliveryService

+ (instancetype)shared {
    static PPDeliveryService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (void)callFunction:(NSString *)name params:(NSDictionary *)params completion:(void(^)(id result, NSError *error))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:name];
    [callable callWithObject:params completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(result.data, error);
    }];
}

- (void)fetchDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> *, NSError *))completion {
    [self callFunction:@"listCompanyDeliveryRequests" params:@{@"companyId": kPPCompanyID, @"pageSize": @100} completion:^(id result, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSArray *raw = [result isKindOfClass:NSDictionary.class] ? result[@"requests"] : nil;
        if (![raw isKindOfClass:NSArray.class]) { if (completion) completion(@[], nil); return; }
        NSMutableArray *records = [NSMutableArray array];
        for (NSDictionary *d in raw) {
            if ([d isKindOfClass:NSDictionary.class]) {
                [records addObject:[[PPDeliveryRequestRecord alloc] initWithDictionary:d documentID:d[@"id"] ?: @""]];
            }
        }
        if (completion) completion(records, nil);
    }];
}

- (void)acceptRequest:(NSString *)requestID completion:(void(^)(NSError *))completion {
    [self callFunction:@"acceptCompanyDeliveryRequest" params:@{@"requestId": requestID} completion:^(id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)assignDriver:(NSString *)requestID driverUID:(NSString *)driverUID completion:(void(^)(NSError *))completion {
    [self callFunction:@"assignCompanyDeliveryDriver" params:@{@"requestId": requestID, @"driverUid": driverUID} completion:^(id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)completeRequest:(NSString *)requestID completion:(void(^)(NSError *))completion {
    [self callFunction:@"completeCompanyDeliveryRequest" params:@{@"requestId": requestID} completion:^(id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)cancelRequest:(NSString *)requestID completion:(void(^)(NSError *))completion {
    [self callFunction:@"cancelCompanyDeliveryRequest" params:@{@"requestId": requestID, @"reason": @"Cancelled by admin"} completion:^(id result, NSError *error) {
        if (completion) completion(error);
    }];
}

@end