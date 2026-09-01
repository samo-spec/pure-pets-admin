#import <Foundation/Foundation.h>

@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@interface PPPOSCartItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double price;
@property (nonatomic, assign) double lineTotal;
@property (nonatomic, assign) NSInteger quantity;
@property (nonatomic, copy, nullable) NSString *inventoryMode;
@property (nonatomic, copy) NSArray<NSString *> *unitIDs;
@property (nonatomic, copy) NSArray<NSString *> *unitRingTags;
@property (nonatomic, copy) NSArray<NSDictionary *> *unitPrices;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPPOSInventoryUnit : NSObject
@property (nonatomic, copy) NSString *unitID;
@property (nonatomic, copy) NSString *ringTag;
@property (nonatomic, assign) double sellingPrice;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPPOSSubmitResult : NSObject
@property (nonatomic, copy) NSString *transactionID;
@property (nonatomic, assign) double total;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, assign, getter=isIdempotent) BOOL idempotent;
@end

@interface PPPOSReceipt : NSObject
@property (nonatomic, copy) NSString *receiptID;
@property (nonatomic, strong) NSArray<PPPOSCartItem *> *items;
@property (nonatomic, assign) double subtotal;
@property (nonatomic, assign) double discount;
@property (nonatomic, assign) double total;
@property (nonatomic, assign) double cashReceived;
@property (nonatomic, assign) double changeDue;
@property (nonatomic, copy) NSString *paymentMethod;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *customerName;
@property (nonatomic, copy) NSString *customerPhone;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *operatorID;
@property (nonatomic, assign) NSInteger schemaVersion;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPPOSService : NSObject
+ (instancetype)shared;
+ (BOOL)isExactUnitSelectionConflictError:(NSError *)error;
+ (NSDictionary<NSString *, id> *)exactUnitConflictDetailsForError:(NSError *)error;
- (void)listAvailableUnitsForProductID:(NSString *)productID
                               cursor:(nullable NSString *)cursor
                           completion:(void(^)(NSArray<PPPOSInventoryUnit *> * _Nullable units,
                                               NSString * _Nullable nextCursor,
                                               BOOL hasMore,
                                               NSError * _Nullable error))completion;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(nullable NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                     completion:(void(^)(PPPOSSubmitResult * _Nullable result,
                                         NSError * _Nullable error))completion;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(nullable NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(nullable NSString *)customerName
                  customerPhone:(nullable NSString *)customerPhone
                  posCustomerID:(nullable NSString *)posCustomerID
                     completion:(void(^)(PPPOSSubmitResult * _Nullable result,
                                         NSError * _Nullable error))completion;
- (void)fetchPOSHistoryWithCompletion:(void(^)(NSArray<PPPOSReceipt *> * _Nullable receipts,
                                                NSError * _Nullable error))completion;
- (void)fetchPOSReceiptForTransactionID:(NSString *)transactionID
                             completion:(void(^)(PPPOSReceipt * _Nullable receipt,
                                                 NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
