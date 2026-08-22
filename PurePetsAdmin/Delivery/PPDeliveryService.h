#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

@interface PPDeliveryRequestRecord : NSObject
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy) NSString *orderID;
@property (nonatomic, copy) NSString *orderNumber;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *customerName;
@property (nonatomic, copy) NSString *assignedDriverName;
@property (nonatomic, strong) NSNumber *deliveryFee;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPDeliveryService : NSObject
+ (instancetype)shared;
- (void)fetchDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> * _Nullable records, NSError * _Nullable error))completion;
- (void)fetchAllDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> * _Nullable records, NSError * _Nullable error))completion;
- (void)acceptRequest:(NSString *)requestID completion:(void(^)(NSError * _Nullable error))completion;
- (void)assignDriver:(NSString *)requestID driverUID:(NSString *)driverUID completion:(void(^)(NSError * _Nullable error))completion;
- (void)completeRequest:(NSString *)requestID completion:(void(^)(NSError * _Nullable error))completion;
- (void)cancelRequest:(NSString *)requestID completion:(void(^)(NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
