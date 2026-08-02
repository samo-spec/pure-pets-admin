#import <Foundation/Foundation.h>
@import Firebase;
@import FirebaseFirestore;

NS_ASSUME_NONNULL_BEGIN

@interface PPFulfillmentRecord : NSObject
@property (nonatomic, copy) NSString *fulfillmentID;
@property (nonatomic, copy) NSString *parentOrderID;
@property (nonatomic, copy) NSString *parentOrderNumber;
@property (nonatomic, copy) NSString *parentUserId;
@property (nonatomic, copy) NSString *customerID;
@property (nonatomic, copy) NSString *customerName;
@property (nonatomic, copy) NSString *ownerID;
@property (nonatomic, copy) NSString *ownerType;
@property (nonatomic, copy) NSString *fulfillmentMode;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, copy) NSDictionary *money;
@property (nonatomic, copy, nullable) NSDate *createdAt;
@property (nonatomic, copy, nullable) NSDate *updatedAt;
@property (nonatomic, copy, nullable) NSDate *adminOverrideAt;
@property (nonatomic, copy, nullable) NSString *adminOverrideBy;
@property (nonatomic, copy, nullable) NSString *adminOverrideReason;

- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPFulfillmentService : NSObject
+ (instancetype)shared;

- (void)fetchFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *records, NSError * _Nullable error))completion;

- (id<FIRListenerRegistration>)observeFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *records, NSError * _Nullable error))completion;

- (void)fetchFulfillmentDetail:(NSString *)fulfillmentID completion:(void(^)(PPFulfillmentRecord * _Nullable record, NSArray *events, NSError * _Nullable error))completion;

- (id<FIRListenerRegistration>)observeFulfillmentEvents:(NSString *)fulfillmentID completion:(void(^)(NSArray<NSDictionary *> *events, NSError * _Nullable error))completion;

- (void)resolveUserProfilesForIDs:(NSArray<NSString *> *)userIDs completion:(void(^)(NSDictionary<NSString *, NSString *> *names))completion;

- (void)adminOverrideFulfillment:(NSString *)fulfillmentID
                    targetStatus:(NSString *)status
                          reason:(NSString *)reason
                            note:(nullable NSString *)note
                          notify:(BOOL)notify
                      completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

+ (NSArray<NSString *> *)allowedOverrideTargetsForStatus:(NSString *)currentStatus;
@end

NS_ASSUME_NONNULL_END