#import "AccessoryManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import <FirebaseFirestore/FIRFieldPath.h>
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
static NSString * const kColAccessories = @"petAccessories";
static NSString * const kFieldAccessKindType = @"accessKindType";
static NSString * const kFieldOwnerID = @"ownerID";
static NSString * const kFieldStoreID = @"storeID";
static NSString * const kFieldQuantity = @"quantity";
static NSString * const kFieldNoStock = @"noStock";
static NSString * const kFieldActive = @"active";
static NSString * const kFieldUpdatedAt = @"updatedAt";
static NSInteger const kInventoryLivePageLimit = 100;

static NSError *PPAccessoryError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"pp.accessory.manager"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Accessory operation failed"}];
}

@interface AccessoryManager ()
@property (nonatomic, strong) FIRFirestore *db;
@end

@implementation AccessoryManager

+ (instancetype)shared {
    static AccessoryManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [AccessoryManager new];
    });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _db = [FIRFirestore firestore];
    }
    return self;
}

- (FIRCollectionReference *)col {
    return [self.db collectionWithPath:kColAccessories];
}

#pragma mark - Private Helpers

- (FIRQuery *)_queryForKind:(AccessKindType)kind {
    switch (kind) {
        case AccessTypeAccessory:
        case AccessTypeFood:
        case AccessTypeLivePets:
        case AccessTypePetMedicine:
            return [[self col] queryWhereField:kFieldAccessKindType isEqualTo:@(kind)];
    }

    // Fail closed: an invalid kind must never expose the accessory catalog.
    return [[self col] queryWhereField:kFieldAccessKindType isEqualTo:@(NSIntegerMin)];
}

- (FIRQuery *)_queryForStoreID:(NSString *)storeID kind:(AccessKindType)kind {
    FIRQuery *q = [self _queryForKind:kind];
    if (storeID.length > 0) {
        q = [q queryWhereField:kFieldStoreID isEqualTo:storeID];
    }
    return q;
}

- (PetAccessory *)_mapDoc:(FIRDocumentSnapshot *)doc {
    NSDictionary *data = doc.data ?: @{};
    return [[PetAccessory alloc] initWithDictionary:data documentID:doc.documentID];
}

- (NSArray<PetAccessory *> *)_mapDocs:(NSArray<FIRDocumentSnapshot *> *)docs {
    NSMutableArray<PetAccessory *> *arr = [NSMutableArray arrayWithCapacity:docs.count];
    for (FIRDocumentSnapshot *doc in docs) {
        PetAccessory *item = [self _mapDoc:doc];
        if (item.isDeleted) {
            continue;
        }
        [arr addObject:item];
    }
    [arr sortUsingComparator:^NSComparisonResult(PetAccessory *a, PetAccessory *b) {
        if (a.createdAt && b.createdAt) {
            NSComparisonResult res = [b.createdAt compare:a.createdAt];
            if (res != NSOrderedSame) return res;
        } else if (b.createdAt) {
            return NSOrderedDescending;
        } else if (a.createdAt) {
            return NSOrderedAscending;
        }
        return [b.accessoryID compare:a.accessoryID];
    }];
    return arr;
}

- (NSDictionary *)_inventoryPayloadForQuantity:(NSInteger)quantity {
    NSInteger safeQty = MAX(0, quantity);
    return @{
        kFieldQuantity: @(safeQty),
        kFieldNoStock: @(safeQty <= 0),
        kFieldUpdatedAt: [FIRTimestamp timestamp]
    };
}

- (void)_dispatchCount:(AccessoryCountBlock)block value:(NSInteger)value {
    if (!block) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(value);
    });
}

- (NSString *)_commandIDForAction:(NSString *)action productID:(NSString *)productID {
    NSString *safeAction = action.length > 0 ? action : @"inventory";
    NSString *safeProductID = productID.length > 0 ? productID : @"new";
    return [NSString stringWithFormat:@"admin-ios-%@-%@-%@", safeAction, safeProductID, [NSUUID UUID].UUIDString.lowercaseString];
}

- (void)_callInventoryAction:(NSString *)action
                   productID:(NSString * _Nullable)productID
                      payload:(NSDictionary *)payload
                   completion:(AccessoryVoidBlock)completion {
    NSString *commandID = [self _commandIDForAction:action productID:productID ?: @"new"];
    NSMutableDictionary *request = [@{
        @"contractVersion": @2,
        @"action": action,
        @"commandId": commandID,
        @"payload": payload ?: @{}
    } mutableCopy];
    if (productID.length > 0) {
        request[@"productId"] = productID;
    }
    [[[FIRFunctions functions] HTTPSCallableWithName:@"validateInventoryChange"]
     callWithObject:request
     completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
        BOOL valid = [response[@"ok"] boolValue] && [response[@"commandId"] isEqualToString:commandID];
        if (completion) {
            completion(valid ? nil : PPAccessoryError(502, @"Inventory service returned an invalid command response."));
        }
    }];
}

- (void)_loadCanonicalBranchForProductID:(NSString *)productID
                              completion:(void (^)(NSString * _Nullable branchID, NSError * _Nullable error))completion {
    [[[self col] documentWithPath:productID] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if (!snapshot.exists) {
            completion(nil, PPAccessoryError(404, @"Inventory item was not found."));
            return;
        }
        NSDictionary *data = snapshot.data ?: @{};
        NSString *branchID = [data[@"storeID"] isKindOfClass:NSString.class] ? data[@"storeID"] : nil;
        if (branchID.length == 0 && [data[@"branchID"] isKindOfClass:NSString.class]) {
            branchID = data[@"branchID"];
        }
        branchID = [branchID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (branchID.length == 0 || [branchID isEqualToString:@"main_store"]) {
            completion(nil, PPAccessoryError(412, @"A specific authoritative branch is required for stock adjustment."));
            return;
        }
        completion(branchID, nil);
    }];
}

- (void)_adjustProductID:(NSString *)productID
              newQuantity:(NSNumber * _Nullable)newQuantity
                     delta:(NSNumber * _Nullable)delta
                    reason:(NSString *)reason
                completion:(AccessoryVoidBlock)completion {
    [self _loadCanonicalBranchForProductID:productID completion:^(NSString * _Nullable branchID, NSError * _Nullable error) {
        if (error || branchID.length == 0) {
            if (completion) completion(error ?: PPAccessoryError(412, @"A specific authoritative branch is required."));
            return;
        }
        NSString *commandID = [self _commandIDForAction:@"adjust" productID:productID];
        NSMutableDictionary *payload = [@{
            @"productId": productID,
            @"branchId": branchID,
            @"commandId": commandID,
            @"type": @"adjustment",
            @"reason": reason.length > 0 ? reason : @"manual_adjustment",
            @"referenceId": @"legacy_accessory_manager"
        } mutableCopy];
        if (newQuantity) payload[@"newQuantity"] = newQuantity;
        if (delta) payload[@"delta"] = delta;
        NSDictionary *request = @{ @"contractVersion": @2, @"payload": payload };
        [[[FIRFunctions functions] HTTPSCallableWithName:@"adjustBranchStock"]
         callWithObject:request
         completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable callError) {
            if (callError) {
                if (completion) completion(callError);
                return;
            }
            NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
            BOOL valid = [response[@"ok"] boolValue] && [response[@"commandId"] isEqualToString:commandID];
            if (completion) {
                completion(valid ? nil : PPAccessoryError(502, @"Stock service returned an invalid command response."));
            }
        }];
    }];
}

#pragma mark - READ

- (void)fetchAllAccessories:(AccessoryArrayBlock)completion {
    [[self col] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        completion(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (id<FIRListenerRegistration>)observeAllAccessories:(AccessoryArrayBlock)onChange {
    return [[self col] addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!onChange) return;
        onChange(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (void)fetchAccessoriesOfKind:(AccessKindType)kind completion:(AccessoryArrayBlock)completion {
    [[self _queryForKind:kind] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        completion(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (void)fetchAccessoriesOfKind:(AccessKindType)kind
                         limit:(NSUInteger)limit
            startAfterDocument:(FIRDocumentSnapshot * _Nullable)lastDoc
                    completion:(void (^)(NSArray<PetAccessory *> * _Nullable items, FIRDocumentSnapshot * _Nullable lastSnapshot, NSError * _Nullable error))completion {
    FIRQuery *q = [[[self _queryForKind:kind] queryOrderedByField:kFieldUpdatedAt descending:YES] queryLimitedTo:limit > 0 ? limit : 50];
    if (lastDoc) {
        q = [q queryStartingAfterDocument:lastDoc];
    }
    [q getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        if (error) {
            completion(nil, nil, error);
            return;
        }
        NSArray<PetAccessory *> *items = [self _mapDocs:snap.documents];
        FIRDocumentSnapshot *newLast = snap.documents.lastObject;
        completion(items, newLast, nil);
    }];
}

- (id<FIRListenerRegistration>)observeAccessoriesOfKind:(AccessKindType)kind callback:(AccessoryArrayBlock)onChange {
    FIRQuery *boundedQuery = [[self _queryForKind:kind] queryLimitedTo:kInventoryLivePageLimit];
    return [boundedQuery addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!onChange) return;
        onChange(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (void)fetchAccessoriesForOwnerID:(NSString *)ownerID completion:(AccessoryArrayBlock)completion {
    [[[self col] queryWhereField:kFieldOwnerID isEqualTo:ownerID ?: @""]
     getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        completion(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (void)fetchAccessoriesForOwnerID:(NSString *)ownerID kind:(AccessKindType)kind completion:(AccessoryArrayBlock)completion {
    [[[self _queryForKind:kind] queryWhereField:kFieldOwnerID isEqualTo:ownerID ?: @""]
     getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        completion(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (void)fetchAccessoriesWithIDs:(NSArray<NSString *> *)ids completion:(AccessoryArrayBlock)completion {
    if (ids.count == 0) {
        if (completion) completion(@[], nil);
        return;
    }

    NSMutableArray<PetAccessory *> *all = [NSMutableArray array];
    __block NSError *lastErr = nil;
    dispatch_queue_t syncQueue = dispatch_queue_create("pp.accessories.fetch.ids.sync", DISPATCH_QUEUE_SERIAL);
    dispatch_group_t group = dispatch_group_create();

    for (NSUInteger i = 0; i < ids.count; i += 10) {
        NSArray *chunk = [ids subarrayWithRange:NSMakeRange(i, MIN(10, ids.count - i))];
        dispatch_group_enter(group);
        [[[self col] queryWhereFieldPath:[FIRFieldPath documentID] in:chunk]
         getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
            if (error) {
                dispatch_sync(syncQueue, ^{
                    if (!lastErr) {
                        lastErr = error;
                    }
                });
            } else {
                NSArray<PetAccessory *> *mapped = [self _mapDocs:snap.documents];
                dispatch_sync(syncQueue, ^{
                    [all addObjectsFromArray:mapped];
                });
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (!completion) return;
        __block NSArray<PetAccessory *> *result = nil;
        __block NSError *finalError = nil;
        dispatch_sync(syncQueue, ^{
            result = [all copy];
            finalError = lastErr;
        });
        completion(finalError ? nil : result, finalError);
    });
}

- (void)fetchAccessoriesForStoreID:(NSString *)storeID
                               kind:(AccessKindType)kind
                         completion:(AccessoryArrayBlock)completion {
    [[self _queryForStoreID:storeID kind:kind] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        completion(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (id<FIRListenerRegistration>)observeAccessoriesForStoreID:(NSString *)storeID
                                                        kind:(AccessKindType)kind
                                                    callback:(AccessoryArrayBlock)onChange {
    return [[[self _queryForStoreID:storeID kind:kind] queryLimitedTo:kInventoryLivePageLimit]
            addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!onChange) return;
        onChange(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (void)fetchFood:(AccessoryArrayBlock)completion {
    [self fetchAccessoriesOfKind:AccessTypeFood completion:completion];
}

- (id<FIRListenerRegistration>)observeFood:(AccessoryArrayBlock)onChange {
    return [self observeAccessoriesOfKind:AccessTypeFood callback:onChange];
}

#pragma mark - WRITE (AUTHORITATIVE CALLABLE ROUTING)

- (void)createOrUpdateAccessory:(PetAccessory *)model completion:(AccessoryVoidBlock)completion {
    if (!model) {
        if (completion) completion(PPAccessoryError(400, @"Accessory model is required."));
        return;
    }

    if (model.accessKindType == AccessTypeFood) {
        model.condition = AccessConditionsNew;
    }
    [model normalizeInventoryState];

    BOOL isUpdate = model.accessoryID.length > 0;
    NSString *action = isUpdate ? @"update" : @"create";
    NSMutableDictionary *payload = [@{
        @"name": model.name ?: @"",
        @"nameEn": model.nameEn ?: @"",
        @"desc": model.desc ?: @"",
        @"descEn": model.descEn ?: @"",
        @"price": model.price ?: @0,
        @"discountPercent": model.discountPercent ?: @0,
        @"discountAmount": model.discountAmount ?: @0,
        @"petMainCategoryID": @(model.petMainCategoryID),
        @"petSubCategoryID": @(model.petSubCategoryID),
        @"condition": @(model.condition),
        @"imageURLsArray": model.imageURLsArray ?: @[],
        @"isNew": @(model.isNew),
        @"hasOffer": @(model.hasOffer),
        @"showInAppMarket": @(model.showInAppMarket),
        @"active": @(model.active)
    } mutableCopy];
    if (model.sku.length > 0) payload[@"sku"] = model.sku;
    if (model.barcode.length > 0) payload[@"barcode"] = model.barcode;
    if (model.category.length > 0) payload[@"category"] = model.category;
    if (model.wholesalePrice) payload[@"wholesalePrice"] = model.wholesalePrice;
    if (model.weight) payload[@"weight"] = model.weight;
    if (model.weightUnit.length > 0) payload[@"weightUnit"] = model.weightUnit;
    if (model.size.length > 0) payload[@"size"] = model.size;
    if (model.expiryDate) payload[@"expiryDate"] = [NSISO8601DateFormatter stringFromDate:model.expiryDate timeZone:NSTimeZone.localTimeZone formatOptions:NSISO8601DateFormatWithInternetDateTime];

    if (!isUpdate) {
        payload[@"quantity"] = @(MAX(0, model.quantity));
        payload[@"product_type"] = model.accessKindType == AccessTypeLivePets ? @"live" : @"normal";
        payload[@"accessKindType"] = @(model.accessKindType);
        NSString *branchID = model.resolvedBranchID;
        if (branchID.length > 0 && ![branchID isEqualToString:@"main_store"]) {
            payload[@"storeID"] = branchID;
            payload[@"branchId"] = branchID;
        }
        if (model.costPrice) payload[@"costPrice"] = model.costPrice;
    }

    NSString *commandID = [self _commandIDForAction:action productID:isUpdate ? model.accessoryID : @"new"];
    NSMutableDictionary *request = [@{
        @"contractVersion": @2,
        @"action": action,
        @"commandId": commandID,
        @"payload": payload
    } mutableCopy];
    if (isUpdate) {
        request[@"productId"] = model.accessoryID;
        if (model.revision > 0) request[@"expectedRevision"] = @(model.revision);
    }
    [[[FIRFunctions functions] HTTPSCallableWithName:@"validateInventoryChange"]
     callWithObject:request
     completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
        if (![response[@"ok"] boolValue] || ![response[@"commandId"] isEqualToString:commandID]) {
            if (completion) completion(PPAccessoryError(502, @"Inventory service returned an invalid command response."));
            return;
        }
        if (!isUpdate && [response[@"productId"] isKindOfClass:NSString.class]) {
            model.accessoryID = response[@"productId"];
        }
        if ([response[@"revision"] respondsToSelector:@selector(integerValue)]) {
            model.revision = [response[@"revision"] integerValue];
        }
        if (completion) completion(nil);
    }];
}

- (void)updateQuantity:(NSInteger)qty forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    if (qty < 0) {
        if (completion) completion(PPAccessoryError(400, @"Inventory quantity cannot be negative."));
        return;
    }
    [self _adjustProductID:docID newQuantity:@(qty) delta:nil reason:@"legacy_absolute_count" completion:completion];
}

- (void)adjustQuantityBy:(NSInteger)delta forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    [self _adjustProductID:docID newQuantity:nil delta:@(delta) reason:@"legacy_relative_adjustment" completion:completion];
}

- (void)setNoStock:(BOOL)noStock forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    // Availability is derived by Infra from the committed branch quantity.
    // A zero-delta command safely reconciles a legacy false toggle without
    // allowing the client to author `noStock` independently.
    [self _adjustProductID:docID
               newQuantity:noStock ? @0 : nil
                      delta:noStock ? nil : @0
                     reason:noStock ? @"legacy_marked_no_stock" : @"legacy_reconcile_in_stock"
                 completion:completion];
}

- (void)updatePrice:(NSNumber *)price forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }
    if (!price) {
        if (completion) completion(nil);
        return;
    }

    [self _callInventoryAction:@"update" productID:docID payload:@{ @"price": price } completion:completion];
}

- (void)setActive:(BOOL)active forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    [self _callInventoryAction:@"update" productID:docID payload:@{ @"active": @(active) } completion:completion];
}

- (void)deleteAccessoryWithID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }
    [self _callInventoryAction:@"delete"
                     productID:docID
                        payload:@{ @"reason": @"legacy_admin_soft_delete" }
                     completion:completion];
}

- (void)batchUpdateQuantities:(NSDictionary<NSString *,NSNumber *> *)idToQty completion:(AccessoryVoidBlock)completion {
    if (idToQty.count == 0) {
        if (completion) completion(nil);
        return;
    }
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t stateQueue = dispatch_queue_create("pp.accessory.manager.batch.state", DISPATCH_QUEUE_SERIAL);
    __block NSError *firstError = nil;
    [idToQty enumerateKeysAndObjectsUsingBlock:^(NSString *docID, NSNumber *qtyNum, BOOL *stop) {
        if (docID.length == 0) return;
        dispatch_group_enter(group);
        [self updateQuantity:qtyNum.integerValue forAccessoryID:docID completion:^(NSError * _Nullable error) {
            if (error) {
                dispatch_sync(stateQueue, ^{
                    if (!firstError) firstError = error;
                });
            }
            dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __block NSError *resultError = nil;
        dispatch_sync(stateQueue, ^{ resultError = firstError; });
        if (completion) completion(resultError);
    });
}

#pragma mark - LIVE COUNT

- (id<FIRListenerRegistration>)listenAccessoriesCount:(AccessoryCountBlock)block {
    return [self listenAccessoriesCountActiveOnly:NO block:block];
}

- (id<FIRListenerRegistration>)listenAccessoriesCountActiveOnly:(BOOL)activeOnly
                                                          block:(AccessoryCountBlock)block {
    FIRQuery *q = [self col];
    if (activeOnly) {
        q = [q queryWhereField:kFieldActive isEqualTo:@YES];
    }
    return [q addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (error) {
            [self _dispatchCount:block value:0];
            return;
        }
        NSInteger count = 0;
        for (FIRDocumentSnapshot *doc in snap.documents) {
            if (![doc.data[@"isDeleted"] boolValue]) {
                count++;
            }
        }
        [self _dispatchCount:block value:count];
    }];
}

- (id<FIRListenerRegistration>)listenCountForKind:(AccessKindType)kind
                                       activeOnly:(BOOL)activeOnly
                                            block:(AccessoryCountBlock)block {
    FIRQuery *q = [self _queryForKind:kind];
    if (activeOnly) {
        q = [q queryWhereField:kFieldActive isEqualTo:@YES];
    }
    return [q addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (error) {
            [self _dispatchCount:block value:0];
            return;
        }
        NSInteger count = 0;
        for (FIRDocumentSnapshot *doc in snap.documents) {
            if (![doc.data[@"isDeleted"] boolValue]) {
                count++;
            }
        }
        [self _dispatchCount:block value:count];
    }];
}

- (id<FIRListenerRegistration>)listenFoodCountActiveOnly:(BOOL)activeOnly
                                                   block:(AccessoryCountBlock)block {
    return [self listenCountForKind:AccessTypeFood activeOnly:activeOnly block:block];
}

@end
