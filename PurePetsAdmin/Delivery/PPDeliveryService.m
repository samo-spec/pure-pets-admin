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
    [self callFunction:@"listCompanyDeliveryRequests" params:@{@"companyId": kPPCompanyID, @"pageSize": @50} completion:^(id result, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        if (completion) completion([self pp_recordsFromResult:result], nil);
    }];
}

- (void)fetchAllDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> *, NSError *))completion {
    [self pp_fetchDeliveryRequestsAfterToken:nil
                                     records:[NSMutableArray array]
                                  seenTokens:[NSMutableSet set]
                                  completion:completion];
}

- (NSArray<PPDeliveryRequestRecord *> *)pp_recordsFromResult:(id)result {
    NSArray *raw = [result isKindOfClass:NSDictionary.class] ? result[@"requests"] : nil;
    if (![raw isKindOfClass:NSArray.class]) return @[];

    NSMutableArray<PPDeliveryRequestRecord *> *records = [NSMutableArray array];
    for (NSDictionary *dictionary in raw) {
        if (![dictionary isKindOfClass:NSDictionary.class]) continue;
        [records addObject:[[PPDeliveryRequestRecord alloc] initWithDictionary:dictionary
                                                                    documentID:PPSafeString(dictionary[@"id"])]];
    }
    return records.copy;
}

- (void)pp_fetchDeliveryRequestsAfterToken:(NSString * _Nullable)token
                                   records:(NSMutableArray<PPDeliveryRequestRecord *> *)records
                                seenTokens:(NSMutableSet<NSString *> *)seenTokens
                                completion:(void(^)(NSArray<PPDeliveryRequestRecord *> *, NSError *))completion {
    NSMutableDictionary *params = [@{@"companyId": kPPCompanyID, @"pageSize": @50} mutableCopy];
    if (token.length > 0) params[@"nextPageToken"] = token;

    [self callFunction:@"listCompanyDeliveryRequests" params:params completion:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(records.copy, error);
            return;
        }

        NSMutableSet<NSString *> *knownRequestIDs = [NSMutableSet set];
        for (PPDeliveryRequestRecord *record in records) {
            if (record.requestID.length > 0) [knownRequestIDs addObject:record.requestID];
        }
        for (PPDeliveryRequestRecord *record in [self pp_recordsFromResult:result]) {
            if (record.requestID.length == 0 || ![knownRequestIDs containsObject:record.requestID]) {
                [records addObject:record];
                if (record.requestID.length > 0) [knownRequestIDs addObject:record.requestID];
            }
        }

        NSString *nextToken = [result isKindOfClass:NSDictionary.class]
            ? PPSafeString(result[@"nextPageToken"])
            : @"";
        if (nextToken.length == 0) {
            if (completion) completion(records.copy, nil);
            return;
        }
        if ([seenTokens containsObject:nextToken]) {
            NSError *paginationError = [NSError errorWithDomain:@"PPDeliveryService"
                                                            code:2
                                                        userInfo:@{NSLocalizedDescriptionKey: kLang(@"Delivery_Pagination_Error")}];
            if (completion) completion(records.copy, paginationError);
            return;
        }

        [seenTokens addObject:nextToken];
        [self pp_fetchDeliveryRequestsAfterToken:nextToken
                                         records:records
                                      seenTokens:seenTokens
                                      completion:completion];
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
