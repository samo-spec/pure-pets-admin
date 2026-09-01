#import "PPPOSService.h"
#import "PPFirebaseCompat.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseFunctions;

static NSString * const PPPOSServiceErrorDomain = @"pp.pos.service";
static NSString * const PPPOSIndividualInventoryMode = @"INDIVIDUAL_TRACKED";

static NSError *PPPOSServiceError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:PPPOSServiceErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Invalid POS response."}];
}

static NSArray<NSString *> *PPPOSStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        NSString *string = PPSafeString(item);
        if (string.length > 0) [result addObject:string];
    }
    return result.copy;
}

@implementation PPPOSCartItem
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _itemID = PPSafeString(dict[@"productId"] ?: dict[@"itemId"] ?: dict[@"itemID"]);
        _name = PPSafeString(dict[@"name"]);
        _price = PPSafeDouble(dict[@"unitPrice"] ?: dict[@"price"]);
        _quantity = MAX(1, [PPSafeNumber(dict[@"quantity"]) integerValue]);
        _lineTotal = dict[@"lineTotal"] == nil
            ? _price * _quantity
            : PPSafeDouble(dict[@"lineTotal"]);
        _inventoryMode = PPSafeString(dict[@"inventoryMode"]);
        _unitIDs = PPPOSStringArray(dict[@"unitIds"]);
        _unitRingTags = PPPOSStringArray(dict[@"unitRingTags"]);
        _unitPrices = [dict[@"unitPrices"] isKindOfClass:NSArray.class] ? dict[@"unitPrices"] : @[];
    }
    return self;
}
@end

@implementation PPPOSInventoryUnit
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _unitID = PPSafeString(dict[@"unitId"] ?: dict[@"id"]);
        _ringTag = PPSafeString(dict[@"ringTag"]);
        _sellingPrice = PPSafeDouble(dict[@"sellingPrice"]);
    }
    return self;
}
@end

@implementation PPPOSSubmitResult
@end

@implementation PPPOSReceipt
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _receiptID = docID ?: @"";
        _subtotal = PPSafeDouble(dict[@"subtotal"]);
        _discount = PPSafeDouble(dict[@"discount"]);
        _total = PPSafeDouble(dict[@"total"]);
        _cashReceived = PPSafeDouble(dict[@"cashReceived"]);
        _changeDue = PPSafeDouble(dict[@"changeDue"]);
        _paymentMethod = PPSafeString(dict[@"paymentMethod"]);
        _currency = PPSafeString(dict[@"currency"]);
        _status = PPSafeString(dict[@"status"]);
        _customerName = PPSafeString(dict[@"customerName"]);
        _customerPhone = PPSafeString(dict[@"customerPhone"]);
        _note = PPSafeString(dict[@"note"]);
        _source = PPSafeString(dict[@"source"]);
        _operatorID = PPSafeString(dict[@"operator"] ?: dict[@"createdBy"]);
        _schemaVersion = [PPSafeNumber(dict[@"posSchemaVersion"]) integerValue];
        NSArray *rawItems = PPSafeArray(dict[@"items"]);
        NSMutableArray *parsedItems = [NSMutableArray array];
        for (NSDictionary *raw in rawItems) {
            if ([raw isKindOfClass:NSDictionary.class]) {
                [parsedItems addObject:[[PPPOSCartItem alloc] initWithDictionary:raw]];
            }
        }
        _items = parsedItems.copy;
        id createdAt = dict[@"createdAt"] ?: dict[@"timestamp"];
        if ([createdAt isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)createdAt dateValue];
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

+ (BOOL)isExactUnitSelectionConflictError:(NSError *)error {
    if (!error) return NO;
    if (![error.domain isEqualToString:FIRFunctionsErrorDomain] &&
        ![error.domain isEqualToString:@"com.firebase.functions"]) return NO;
    NSDictionary *details = [self exactUnitConflictDetailsForError:error];
    NSString *domainCode = [PPSafeString(details[@"domainCode"]) uppercaseString];
    if ([domainCode hasPrefix:@"POS_INVENTORY_UNIT_"] ||
        [domainCode isEqualToString:@"POS_PRODUCT_NOT_FOUND"] ||
        [domainCode isEqualToString:@"POS_INSUFFICIENT_STOCK"]) {
        return YES;
    }
    if (error.code == FIRFunctionsErrorCodeNotFound) return YES;
    if (error.code != FIRFunctionsErrorCodeFailedPrecondition) return NO;

    NSString *message = [error.localizedDescription lowercaseString];
    return [message containsString:@"inventory unit"] ||
        [message containsString:@"animal"] ||
        [message containsString:@"no longer available"] ||
        [message containsString:@"product is unavailable"] ||
        [message containsString:@"insufficient stock"];
}

+ (NSDictionary<NSString *, id> *)exactUnitConflictDetailsForError:(NSError *)error {
    if (!error || ![error.userInfo isKindOfClass:NSDictionary.class]) return @{};
    id details = error.userInfo[FIRFunctionsErrorDetailsKey] ?: error.userInfo[@"details"];
    return [details isKindOfClass:NSDictionary.class] ? (NSDictionary<NSString *, id> *)details : @{};
}

- (void)listAvailableUnitsForProductID:(NSString *)productID
                               cursor:(NSString *)cursor
                           completion:(void(^)(NSArray<PPPOSInventoryUnit *> *, NSString *, BOOL, NSError *))completion {
    NSString *trimmedProductID = [productID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedProductID.length == 0) {
        if (completion) completion(nil, nil, NO, PPPOSServiceError(400, @"productId is required."));
        return;
    }

    NSMutableDictionary *payload = [@{
        @"productId": trimmedProductID,
        @"includeHistory": @NO,
        @"status": @"AVAILABLE",
        @"pageSize": @(50),
    } mutableCopy];
    if (cursor.length > 0) payload[@"cursor"] = cursor;

    [[[FIRFunctions functions] HTTPSCallableWithName:@"listLivePetInventoryUnits"]
     callWithObject:payload
     completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, nil, NO, error);
            return;
        }
        NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
        if (![response[@"ok"] boolValue] ||
            ![PPSafeString(response[@"inventoryMode"]) isEqualToString:PPPOSIndividualInventoryMode]) {
            if (completion) completion(nil, nil, NO, PPPOSServiceError(502, @"Invalid exact-unit response."));
            return;
        }
        NSMutableArray<PPPOSInventoryUnit *> *units = [NSMutableArray array];
        for (NSDictionary *rawUnit in PPSafeArray(response[@"units"])) {
            if (![rawUnit isKindOfClass:NSDictionary.class]) continue;
            PPPOSInventoryUnit *unit = [[PPPOSInventoryUnit alloc] initWithDictionary:rawUnit];
            if (unit.unitID.length > 0) [units addObject:unit];
        }
        if (completion) {
            completion(units.copy,
                       PPSafeString(response[@"nextCursor"]),
                       [response[@"hasMore"] boolValue],
                       nil);
        }
    }];
}

- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                     completion:(void(^)(PPPOSSubmitResult *, NSError *))completion {
    [self submitPOSOrderWithItems:items
                            total:total
                    paymentMethod:paymentMethod
                     cashReceived:cashReceived
                        commandID:commandID
                     customerName:nil
                    customerPhone:nil
                    posCustomerID:nil
                       completion:completion];
}

- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(NSString *)customerName
                  customerPhone:(NSString *)customerPhone
                  posCustomerID:(NSString *)posCustomerID
                     completion:(void(^)(PPPOSSubmitResult *, NSError *))completion {
    NSMutableArray *mappedItems = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSString *productID = PPSafeString(item[@"itemID"] ?: item[@"itemId"] ?: item[@"productId"]);
        NSString *inventoryMode = PPSafeString(item[@"inventoryMode"]);
        NSMutableDictionary *mapped = [@{
            @"productId": productID,
            @"quantity": item[@"quantity"] ?: @(1),
        } mutableCopy];
        if ([inventoryMode isEqualToString:PPPOSIndividualInventoryMode]) {
            mapped[@"inventoryMode"] = PPPOSIndividualInventoryMode;
            mapped[@"unitIds"] = [item[@"unitIds"] isKindOfClass:NSArray.class] ? item[@"unitIds"] : @[];
            mapped[@"unitPrices"] = [item[@"unitPrices"] isKindOfClass:NSArray.class] ? item[@"unitPrices"] : @[];
        } else {
            mapped[@"unitPrice"] = item[@"price"] ?: item[@"unitPrice"] ?: @(0);
        }
        [mappedItems addObject:mapped];
    }

    NSMutableDictionary *salePayload = [@{
        @"items": mappedItems,
        @"paymentMethod": paymentMethod ?: @"cash",
        @"status": @"completed",
        @"subtotal": @(total),
        @"total": @(total),
        @"currency": @"QAR",
        @"source": @"admin_ios",
    } mutableCopy];
    if ([paymentMethod isEqualToString:@"cash"]) {
        salePayload[@"cashReceived"] = @(MAX(total, PPSafeDouble(cashReceived)));
    }
    if (customerName.length > 0) {
        salePayload[@"customerName"] = customerName;
    }
    if (customerPhone.length > 0) {
        salePayload[@"customerPhone"] = customerPhone;
    }
    if (posCustomerID.length > 0) {
        salePayload[@"posCustomerId"] = posCustomerID;
    }

    NSDictionary *data = @{
        @"action": @"create",
        @"commandId": commandID ?: @"",
        @"payload": salePayload,
    };

    [[[FIRFunctions functions] HTTPSCallableWithName:@"processTransaction"]
     callWithObject:data
     completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
        NSString *transactionID = PPSafeString(response[@"transactionId"]);
        NSString *currency = PPSafeString(response[@"currency"]);
        if (![response[@"ok"] boolValue] || transactionID.length == 0 || currency.length == 0) {
            if (completion) completion(nil, PPPOSServiceError(502, @"Invalid transaction response."));
            return;
        }
        PPPOSSubmitResult *submitResult = [PPPOSSubmitResult new];
        submitResult.transactionID = transactionID;
        submitResult.total = PPSafeDouble(response[@"total"]);
        submitResult.currency = currency;
        submitResult.idempotent = [response[@"idempotent"] boolValue];
        if (completion) completion(submitResult, nil);
    }];
}

- (void)fetchPOSHistoryWithCompletion:(void(^)(NSArray<PPPOSReceipt *> *, NSError *))completion {
    FIRCollectionReference *transactions = [[FIRFirestore firestore] collectionWithPath:@"transactions"];
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<PPPOSReceipt *> *receipts = [NSMutableArray array];
    __block NSError *firstError = nil;

    for (NSNumber *schemaVersion in @[@(2), @(3)]) {
        dispatch_group_enter(group);
        [[[transactions queryWhereField:@"posSchemaVersion" isEqualTo:schemaVersion]
           queryOrderedByField:@"createdAt" descending:YES]
          getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
            @synchronized (receipts) {
                if (error && !firstError) firstError = error;
                if (!error) {
                    for (FIRDocumentSnapshot *doc in snapshot.documents) {
                        [receipts addObject:[[PPPOSReceipt alloc] initWithDictionary:doc.data documentID:doc.documentID]];
                    }
                }
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (firstError) {
            if (completion) completion(@[], firstError);
            return;
        }
        [receipts sortUsingComparator:^NSComparisonResult(PPPOSReceipt *left, PPPOSReceipt *right) {
            NSDate *leftDate = left.createdAt ?: NSDate.distantPast;
            NSDate *rightDate = right.createdAt ?: NSDate.distantPast;
            return [rightDate compare:leftDate];
        }];
        if (completion) completion(receipts.copy, nil);
    });
}

- (void)fetchPOSReceiptForTransactionID:(NSString *)transactionID
                             completion:(void(^)(PPPOSReceipt *, NSError *))completion {
    NSString *trimmedID = [transactionID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedID.length == 0) {
        if (completion) completion(nil, PPPOSServiceError(400, @"transactionId is required."));
        return;
    }

    FIRDocumentReference *reference = [[[FIRFirestore firestore] collectionWithPath:@"transactions"]
                                       documentWithPath:trimmedID];
    [reference getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = snapshot.data;
        if (!snapshot.exists || ![data isKindOfClass:NSDictionary.class]) {
            if (completion) completion(nil, PPPOSServiceError(404, @"Transaction receipt was not found."));
            return;
        }

        PPPOSReceipt *receipt = [[PPPOSReceipt alloc] initWithDictionary:data documentID:snapshot.documentID];
        if (receipt.receiptID.length == 0 || receipt.items.count == 0 || receipt.currency.length == 0) {
            if (completion) completion(nil, PPPOSServiceError(502, @"Invalid transaction receipt."));
            return;
        }
        if (completion) completion(receipt, nil);
    }];
}

@end
