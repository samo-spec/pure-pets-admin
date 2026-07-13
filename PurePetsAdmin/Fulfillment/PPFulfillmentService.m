#import "PPFulfillmentService.h"

@implementation PPFulfillmentRecord
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _fulfillmentID = docID ?: @"";
        _parentOrderID = PPSafeString(dict[@"parentOrderId"]);
        _parentOrderNumber = PPSafeString(dict[@"parentOrderNumber"]);
        _ownerID = PPSafeString(dict[@"ownerID"]);
        _ownerType = PPSafeString(dict[@"ownerType"]);
        _fulfillmentMode = PPSafeString(dict[@"fulfillmentMode"]);
        _status = PPSafeString(dict[@"status"]);
        _items = PPSafeArray(dict[@"items"]);
        _money = PPSafeDict(dict[@"money"]);
        _customerName = PPSafeString(dict[@"customerName"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
        id ua = dict[@"updatedAt"];
        if ([ua isKindOfClass:FIRTimestamp.class]) _updatedAt = [(FIRTimestamp *)ua dateValue];
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

- (void)fetchFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[[db collectionWithPath:@"FulfillmentOrders"] queryOrderedByField:@"createdAt" descending:YES]
     getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSMutableArray *records = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPFulfillmentRecord *r = [[PPFulfillmentRecord alloc] initWithDictionary:doc.data documentID:doc.documentID];
            [records addObject:r];
        }
        if (completion) completion(records, nil);
    }];
}

- (void)fetchFulfillmentDetail:(NSString *)fulfillmentID completion:(void(^)(PPFulfillmentRecord *, NSArray *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *ref = [[db collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID];
    [ref getDocumentWithCompletion:^(FIRDocumentSnapshot *snap, NSError *error) {
        if (error) { if (completion) completion(nil, @[], error); return; }
        PPFulfillmentRecord *r = [[PPFulfillmentRecord alloc] initWithDictionary:snap.data documentID:snap.documentID];
        [[[ref collectionWithPath:@"events"] queryOrderedByField:@"createdAt" descending:YES]
         getDocumentsWithCompletion:^(FIRQuerySnapshot *eventSnap, NSError *eventError) {
            NSMutableArray *events = [NSMutableArray array];
            for (FIRDocumentSnapshot *edoc in eventSnap.documents) {
                [events addObject:edoc.data ?: @{}];
            }
            if (completion) completion(r, events, eventError);
        }];
    }];
}

- (void)adminOverrideFulfillment:(NSString *)fulfillmentID targetStatus:(NSString *)status reason:(NSString *)reason note:(nullable NSString *)note notify:(BOOL)notify completion:(void(^)(NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"adminOverrideFulfillment"];
    [callable callWithObject:@{
        @"fulfillmentID": fulfillmentID,
        @"targetStatus": status,
        @"reason": reason,
        @"note": note ?: @"",
        @"notifyCustomer": @(notify)
    } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(error);
    }];
}

@end