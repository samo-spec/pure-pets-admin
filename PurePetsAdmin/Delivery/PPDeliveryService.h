#import <Foundation/Foundation.h>
@import Firebase;

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
- (void)fetchDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> *records, NSError *error))completion;
- (void)acceptRequest:(NSString *)requestID completion:(void(^)(NSError *error))completion;
- (void)assignDriver:(NSString *)requestID driverUID:(NSString *)driverUID completion:(void(^)(NSError *error))completion;
- (void)completeRequest:(NSString *)requestID completion:(void(^)(NSError *error))completion;
- (void)cancelRequest:(NSString *)requestID completion:(void(^)(NSError *error))completion;
@end

NS_ASSUME_NONNULL_END