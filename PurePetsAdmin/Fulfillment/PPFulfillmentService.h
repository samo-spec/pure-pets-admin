#import <Foundation/Foundation.h>
@import Firebase;
@import FirebaseFirestore;

NS_ASSUME_NONNULL_BEGIN

@interface PPFulfillmentRecord : NSObject
@property (nonatomic, copy) NSString *fulfillmentID;
@property (nonatomic, copy) NSString *parentOrderID;
@property (nonatomic, copy) NSString *parentOrderNumber;
@property (nonatomic, copy) NSString *ownerID;
@property (nonatomic, copy) NSString *ownerType;
@property (nonatomic, copy) NSString *fulfillmentMode;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, copy) NSDictionary *money;
@property (nonatomic, copy) NSString *customerName;
@property (nonatomic, copy, nullable) NSDate *createdAt;
@property (nonatomic, copy, nullable) NSDate *updatedAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPFulfillmentService : NSObject
+ (instancetype)shared;
- (void)fetchFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *records, NSError *error))completion;
- (void)fetchFulfillmentDetail:(NSString *)fulfillmentID completion:(void(^)(PPFulfillmentRecord *record, NSArray *events, NSError *error))completion;
- (void)adminOverrideFulfillment:(NSString *)fulfillmentID targetStatus:(NSString *)status reason:(NSString *)reason note:(nullable NSString *)note notify:(BOOL)notify completion:(void(^)(NSError *error))completion;
@end

NS_ASSUME_NONNULL_END