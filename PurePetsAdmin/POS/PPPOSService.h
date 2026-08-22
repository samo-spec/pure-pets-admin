#import <Foundation/Foundation.h>

@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@interface PPPOSCartItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double price;
@property (nonatomic, assign) NSInteger quantity;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPPOSReceipt : NSObject
@property (nonatomic, copy) NSString *receiptID;
@property (nonatomic, strong) NSArray<PPPOSCartItem *> *items;
@property (nonatomic, assign) double total;
@property (nonatomic, copy) NSString *paymentMethod;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPPOSService : NSObject
+ (instancetype)shared;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items total:(double)total paymentMethod:(NSString *)paymentMethod completion:(void(^)(NSString * _Nullable orderID, NSError * _Nullable error))completion;
- (void)fetchPOSHistoryWithCompletion:(void(^)(NSArray<PPPOSReceipt *> * _Nullable receipts, NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
