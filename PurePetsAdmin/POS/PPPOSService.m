#import "PPPOSService.h"
@import FirebaseFirestore;
@import FirebaseAuth;

@implementation PPPOSCartItem
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _itemID = PPSafeString(dict[@"itemId"]);
        _name = PPSafeString(dict[@"name"]);
        _price = PPSafeDouble(dict[@"price"]);
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
    FIRFirestore *db = [FIRFirestore firestore];
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"unknown";
    __block FIRDocumentReference *ref = [[db collectionWithPath:@"POSOrders"] addDocumentWithData:@{
        @"items": items ?: @[],
        @"total": @(total),
        @"paymentMethod": paymentMethod ?: @"cash",
        @"createdBy": uid,
        @"status": @"completed",
        @"createdAt": [FIRTimestamp timestampWithDate:[NSDate date]]
    } completion:^(NSError *error) {
        if (completion) completion(ref.documentID, error);
    }];
}

- (void)fetchPOSHistoryWithCompletion:(void(^)(NSArray<PPPOSReceipt *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[[db collectionWithPath:@"POSOrders"] queryOrderedByField:@"createdAt" descending:YES]
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
