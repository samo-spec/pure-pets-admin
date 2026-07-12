// PetAccessoryManager.h

//
//
//
//
//
//
//
//
//
//
NS_ASSUME_NONNULL_BEGIN

typedef void(^AccessoryArrayBlock)(NSArray<PetAccessory *> * _Nullable items, NSError * _Nullable error);
typedef void(^AccessoryVoidBlock)(NSError * _Nullable error);
typedef void (^AccessoryCountBlock)(NSInteger count);

@interface AccessoryManager : NSObject
+ (instancetype)shared;

- (id<FIRListenerRegistration>)listenAccessoriesCount:(AccessoryCountBlock)block;
- (id<FIRListenerRegistration>)listenAccessoriesCountActiveOnly:(BOOL)activeOnly
                                                          block:(AccessoryCountBlock)block;

// READ
- (void)fetchAllAccessories:(AccessoryArrayBlock)completion;
- (id<FIRListenerRegistration>)observeAllAccessories:(AccessoryArrayBlock)onChange;

// FILTERS
- (void)fetchAccessoriesForOwnerID:(NSString *)ownerID completion:(AccessoryArrayBlock)completion;
- (void)fetchAccessoriesWithIDs:(NSArray<NSString *> *)ids completion:(AccessoryArrayBlock)completion;
- (void)fetchAccessoriesForStoreID:(NSString *)storeID
                               kind:(AccessKindType)kind
                         completion:(AccessoryArrayBlock)completion;
- (id<FIRListenerRegistration>)observeAccessoriesForStoreID:(NSString *)storeID
                                                        kind:(AccessKindType)kind
                                                    callback:(AccessoryArrayBlock)onChange;

// WRITE
- (void)updateQuantity:(NSInteger)qty forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion;
- (void)adjustQuantityBy:(NSInteger)delta forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion;
- (void)setNoStock:(BOOL)noStock forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion;
- (void)updatePrice:(NSNumber *)price forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion;
- (void)deleteAccessoryWithID:(NSString *)docID completion:(AccessoryVoidBlock)completion;

// UPSERT
- (void)createOrUpdateAccessory:(PetAccessory *)model completion:(AccessoryVoidBlock)completion;

// BATCH
- (void)batchUpdateQuantities:(NSDictionary<NSString *, NSNumber *> *)idToQty completion:(AccessoryVoidBlock)completion;

// Optional admin toggles
- (void)setActive:(BOOL)active forAccessoryID:(NSString *)docID completion:(AccessoryVoidBlock)completion;

#pragma mark - New: Kind & Food helpers

/// Fetch all accessories of the given kind (Accessory or Food).
- (void)fetchAccessoriesOfKind:(AccessKindType)kind completion:(AccessoryArrayBlock)completion;

/// Live observer for accessories of a given kind.
- (id<FIRListenerRegistration>)observeAccessoriesOfKind:(AccessKindType)kind
                                               callback:(AccessoryArrayBlock)onChange;

/// Fetch items for an owner, filtered by kind.
- (void)fetchAccessoriesForOwnerID:(NSString *)ownerID
                              kind:(AccessKindType)kind
                        completion:(AccessoryArrayBlock)completion;

/// Convenience: fetch all Food items (kind = AccessTypeFood).
- (void)fetchFood:(AccessoryArrayBlock)completion;

/// Convenience: live observer for Food items.
- (id<FIRListenerRegistration>)observeFood:(AccessoryArrayBlock)onChange;

/// Listen for counts filtered by kind and active flag.
- (id<FIRListenerRegistration>)listenCountForKind:(AccessKindType)kind
                                       activeOnly:(BOOL)activeOnly
                                            block:(AccessoryCountBlock)block;

/// Convenience: live count of Food items, optionally active only.
- (id<FIRListenerRegistration>)listenFoodCountActiveOnly:(BOOL)activeOnly
                                                   block:(AccessoryCountBlock)block;

@end

NS_ASSUME_NONNULL_END
