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
    return [[self _queryForKind:kind] addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
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
    return [[self _queryForStoreID:storeID kind:kind]
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

    if (model.ownerID.length == 0) {
        model.ownerID = [FIRAuth auth].currentUser.uid ?: @"";
    }
    if (model.storeID.length == 0) {
        model.storeID = model.ownerID ?: @"";
    }
    if (model.accessKindType == AccessTypeFood) {
        model.condition = AccessConditionsNew;
    }
    [model normalizeInventoryState];

    BOOL isUpdate = model.accessoryID.length > 0;
    NSString *action = isUpdate ? @"update" : @"create";
    NSMutableDictionary *payload = [[model toFirestoreDictionary] mutableCopy];
    // Public catalog document never holds client-supplied cost
    [payload removeObjectForKey:@"costPrice"];
    [payload removeObjectForKey:@"buyPrice"];

    NSMutableDictionary *requestData = [@{
        @"contractVersion": @2,
        @"action": action,
        @"payload": payload
    } mutableCopy];
    if (isUpdate) {
        requestData[@"productId"] = model.accessoryID;
    }

    FIRFunctions *functions = [FIRFunctions functions];
    [[functions HTTPSCallableWithName:@"validateInventoryChange"] callWithObject:requestData completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AccessoryManager] validateInventoryChange %@ failed: %@", action, error.localizedDescription);
            if (completion) completion(error);
            return;
        }
        if (!isUpdate && [result.data isKindOfClass:[NSDictionary class]]) {
            NSString *newId = result.data[@"productId"];
            if (newId.length) {
                model.accessoryID = newId;
            }
        }
        if (completion) completion(nil);
    }];
}

- (void)updateQuantity:(NSInteger)qty forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    FIRFunctions *functions = [FIRFunctions functions];
    NSDictionary *payload = @{
        @"contractVersion": @2,
        @"action": @"update",
        @"productId": docID,
        @"payload": @{
            @"quantity": @(qty),
            @"noStock": @(qty <= 0)
        }
    };
    [[functions HTTPSCallableWithName:@"validateInventoryChange"] callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AccessoryManager] updateQuantity via validateInventoryChange failed: %@", error.localizedDescription);
        }
        if (completion) completion(error);
    }];
}

- (void)adjustQuantityBy:(NSInteger)delta forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    FIRFunctions *functions = [FIRFunctions functions];
    NSDictionary *payload = @{
        @"action": @"adjust",
        @"productId": docID,
        @"payload": @{
            @"type": delta >= 0 ? @"stock_in" : @"stock_out",
            @"quantity": @(ABS(delta)),
            @"reason": @"manual_adjustment"
        }
    };
    [[functions HTTPSCallableWithName:@"validateInventoryChange"] callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AccessoryManager] adjustQuantityBy via validateInventoryChange failed: %@", error.localizedDescription);
        }
        if (completion) completion(error);
    }];
}

- (void)setNoStock:(BOOL)noStock forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    FIRFunctions *functions = [FIRFunctions functions];
    NSMutableDictionary *updatePayload = [@{ @"noStock": @(noStock) } mutableCopy];
    if (noStock) {
        updatePayload[@"quantity"] = @0;
    }
    NSDictionary *payload = @{
        @"contractVersion": @2,
        @"action": @"update",
        @"productId": docID,
        @"payload": updatePayload
    };
    [[functions HTTPSCallableWithName:@"validateInventoryChange"] callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AccessoryManager] setNoStock via validateInventoryChange failed: %@", error.localizedDescription);
        }
        if (completion) completion(error);
    }];
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

    FIRFunctions *functions = [FIRFunctions functions];
    NSDictionary *payload = @{
        @"contractVersion": @2,
        @"action": @"update",
        @"productId": docID,
        @"payload": @{ @"price": price }
    };
    [[functions HTTPSCallableWithName:@"validateInventoryChange"] callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AccessoryManager] updatePrice via validateInventoryChange failed: %@", error.localizedDescription);
        }
        if (completion) completion(error);
    }];
}

- (void)setActive:(BOOL)active forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    FIRFunctions *functions = [FIRFunctions functions];
    NSDictionary *payload = @{
        @"contractVersion": @2,
        @"action": @"update",
        @"productId": docID,
        @"payload": @{ @"active": @(active) }
    };
    [[functions HTTPSCallableWithName:@"validateInventoryChange"] callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AccessoryManager] setActive via validateInventoryChange failed: %@", error.localizedDescription);
        }
        if (completion) completion(error);
    }];
}

- (void)deleteAccessoryWithID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }
    // Zero physical deletions: route through authoritative validateInventoryChange Cloud Function for soft deletion.
    FIRFunctions *functions = [FIRFunctions functions];
    NSDictionary *payload = @{
        @"action": @"delete",
        @"productId": docID
    };
    [[functions HTTPSCallableWithName:@"validateInventoryChange"] callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AccessoryManager] validateInventoryChange delete failed: %@", error.localizedDescription);
            if (completion) completion(error);
            return;
        }
        if (completion) completion(nil);
    }];
}

- (void)batchUpdateQuantities:(NSDictionary<NSString *,NSNumber *> *)idToQty completion:(AccessoryVoidBlock)completion {
    FIRWriteBatch *batch = [self.db batch];
    [idToQty enumerateKeysAndObjectsUsingBlock:^(NSString *docID, NSNumber *qtyNum, BOOL *stop) {
        if (docID.length == 0) return;
        FIRDocumentReference *ref = [[self col] documentWithPath:docID];
        [batch updateData:[self _inventoryPayloadForQuantity:qtyNum.integerValue] forDocument:ref];
    }];
    [batch commitWithCompletion:completion];
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
