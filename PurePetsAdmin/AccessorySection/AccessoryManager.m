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
    AccessKindType normalizedKind = AccessTypeAccessory;
    if (kind == AccessTypeFood) normalizedKind = AccessTypeFood;
    else if (kind == AccessTypeLivePets) normalizedKind = AccessTypeLivePets;
    
    return [[self col] queryWhereField:kFieldAccessKindType isEqualTo:@(normalizedKind)];
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
        [arr addObject:[self _mapDoc:doc]];
    }
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

#pragma mark - WRITE

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

    NSString *docID = model.accessoryID.length ? model.accessoryID : [[self col] documentWithAutoID].documentID;
    model.accessoryID = docID;

    NSDictionary *dict = [model toFirestoreDictionary];
    [[[self col] documentWithPath:docID] setData:dict merge:YES completion:completion];
}

- (void)updateQuantity:(NSInteger)qty forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }
    [[[self col] documentWithPath:docID]
     updateData:[self _inventoryPayloadForQuantity:qty]
     completion:completion];
}

- (void)adjustQuantityBy:(NSInteger)delta forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    FIRDocumentReference *ref = [[self col] documentWithPath:docID];
    [self.db runTransactionWithBlock:^id _Nullable(FIRTransaction * _Nonnull transaction, NSError * _Nonnull * _Nullable errorPointer) {
        FIRDocumentSnapshot *snap = [transaction getDocument:ref error:errorPointer];
        if (*errorPointer) return nil;
        if (!snap.exists) {
            if (errorPointer) *errorPointer = PPAccessoryError(404, @"Accessory not found.");
            return nil;
        }

        NSInteger currentQty = MAX(0, [snap.data[kFieldQuantity] integerValue]);
        NSInteger nextQty = MAX(0, currentQty + delta);
        [transaction updateData:[self _inventoryPayloadForQuantity:nextQty] forDocument:ref];
        return @(nextQty);
    } completion:^(id  _Nullable result, NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}

- (void)setNoStock:(BOOL)noStock forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }

    NSMutableDictionary *data = [@{
        kFieldNoStock: @(noStock),
        kFieldUpdatedAt: [FIRTimestamp timestamp]
    } mutableCopy];
    if (noStock) {
        data[kFieldQuantity] = @0;
    }
    [[[self col] documentWithPath:docID] updateData:data completion:completion];
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
    [[[self col] documentWithPath:docID]
     updateData:@{ @"price": price, kFieldUpdatedAt: [FIRTimestamp timestamp] }
     completion:completion];
}

- (void)setActive:(BOOL)active forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }
    [[[self col] documentWithPath:docID]
     updateData:@{ kFieldActive: @(active), kFieldUpdatedAt: [FIRTimestamp timestamp] }
     completion:completion];
}

- (void)deleteAccessoryWithID:(NSString *)docID completion:(AccessoryVoidBlock)completion {
    if (docID.length == 0) {
        if (completion) completion(PPAccessoryError(400, @"Accessory id is missing."));
        return;
    }
    [[[self col] documentWithPath:docID] deleteDocumentWithCompletion:completion];
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
        [self _dispatchCount:block value:(error ? 0 : (NSInteger)snap.documents.count)];
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
        [self _dispatchCount:block value:(error ? 0 : (NSInteger)snap.documents.count)];
    }];
}

- (id<FIRListenerRegistration>)listenFoodCountActiveOnly:(BOOL)activeOnly
                                                   block:(AccessoryCountBlock)block {
    return [self listenCountForKind:AccessTypeFood activeOnly:activeOnly block:block];
}

@end
