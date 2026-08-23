#import "PPPOSService.h"
@import FirebaseFirestore;
@import FirebaseAuth;
@import FirebaseFunctions;

@implementation PPPOSCartItem
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _itemID = PPSafeString(dict[@"productId"] ?: dict[@"itemId"] ?: dict[@"itemID"]);
        _name = PPSafeString(dict[@"name"]);
        _price = PPSafeDouble(dict[@"unitPrice"] ?: dict[@"price"]);
        _quantity = MAX(1, [PPSafeNumber(dict[@"quantity"]) integerValue]);
    }
    return self;
}
@end

@implementation PPPOSReceipt
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _receiptID = docID ?: @"";
        _total = PPSafeDouble(dict[@"total"]);
        _paymentMethod = PPSafeString(dict[@"paymentMethod"]);
        NSArray *rawItems = PPSafeArray(dict[@"items"]);
        NSMutableArray *parsedItems = [NSMutableArray array];
        for (NSDictionary *raw in rawItems) {
            if ([raw isKindOfClass:NSDictionary.class]) {
                [parsedItems addObject:[[PPPOSCartItem alloc] initWithDictionary:raw]];
            }
        }
        _items = parsedItems.copy;
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
    }
    return self;
}
@end

@implementation PPPOSService

+ (instancetype)shared {
    static PPPOSService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items total:(double)total paymentMethod:(NSString *)paymentMethod completion:(void(^)(NSString *, NSError *))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    
    NSMutableArray *mappedItems = [NSMutableArray array];
    for (NSDictionary *item in items) {
        [mappedItems addObject:@{
            @"productId": item[@"itemID"] ?: item[@"itemId"] ?: @"",
            @"quantity": item[@"quantity"] ?: @(1),
            @"unitPrice": item[@"price"] ?: @(0)
        }];
    }
    
    NSString *commandId = [[NSUUID UUID] UUIDString];
    
    NSDictionary *data = @{
        @"action": @"create",
        @"commandId": commandId,
        @"payload": @{
            @"items": mappedItems,
            @"paymentMethod": paymentMethod ?: @"cash",
            @"status": @"completed",
            @"subtotal": @(total),
            @"total": @(total),
            @"cashReceived": [paymentMethod isEqualToString:@"cash"] ? @(total) : @(0)
        }
    };
    
    [[functions HTTPSCallableWithName:@"processTransaction"] callWithObject:data completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
        } else {
            NSString *docId = [result.data isKindOfClass:[NSDictionary class]] ? result.data[@"transactionId"] : nil;
            if (completion) completion(docId ?: commandId, nil);
        }
    }];
}

- (void)fetchPOSHistoryWithCompletion:(void(^)(NSArray<PPPOSReceipt *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[[[db collectionWithPath:@"transactions"] queryWhereField:@"posSchemaVersion" isEqualTo:@(2)] queryOrderedByField:@"createdAt" descending:YES]
     getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) { if (completion) completion(@[], error); return; }
        NSMutableArray *receipts = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [receipts addObject:[[PPPOSReceipt alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (completion) completion(receipts, nil);
    }];
}

@end
