#import <Foundation/Foundation.h>
@import FirebaseFirestore;

NS_ASSUME_NONNULL_BEGIN

@interface PPProviderApplication : NSObject
@property (nonatomic, copy) NSString *applicationID;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *providerType;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSDictionary *form;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPProviderPlan : NSObject
@property (nonatomic, copy) NSString *planID;
@property (nonatomic, copy) NSDictionary *name;
@property (nonatomic, copy) NSDictionary *planDescription;
@property (nonatomic, copy) NSString *providerType;
@property (nonatomic, copy) NSNumber *price;
@property (nonatomic, copy) NSString *costType;
@property (nonatomic, assign) double costValue;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, copy) NSString *billingInterval;
@property (nonatomic, assign) double commissionRate;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, strong) NSArray *features;
@property (nonatomic, strong) NSArray<NSDictionary *> *featureDocuments;
@property (nonatomic, assign) NSInteger featureCount;
@property (nonatomic, assign) NSInteger rank;
@property (nonatomic, assign, getter=isRecommended) BOOL recommended;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPProviderCommissionRecord : NSObject
@property (nonatomic, copy) NSString *recordID;
@property (nonatomic, copy) NSString *providerID;
@property (nonatomic, copy) NSString *orderID;
@property (nonatomic, copy) NSString *fulfillmentID;
@property (nonatomic, copy) NSString *planID;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, assign) double grossSaleAmount;
@property (nonatomic, assign) double platformCommissionAmount;
@property (nonatomic, assign) double providerNetAmount;
@property (nonatomic, assign) double commissionRate;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPProviderService : NSObject
+ (instancetype)shared;
- (void)fetchApplicationsWithCompletion:(void(^)(NSArray<PPProviderApplication *> *apps, NSError *error))completion;
- (void)fetchPlansWithCompletion:(void(^)(NSArray<PPProviderPlan *> *plans, NSError *error))completion;
- (void)reviewApplication:(NSString *)appID status:(NSString *)status notes:(nullable NSString *)notes completion:(void(^)(NSError *error))completion;
- (void)savePlan:(NSDictionary *)planData completion:(void(^)(NSString *planID, NSError *error))completion;
- (void)deletePlan:(NSString *)planID completion:(void(^)(NSError *error))completion;
- (void)fetchCommissionReportForProviderID:(NSString *)providerID
                                completion:(void(^)(NSArray<PPProviderCommissionRecord *> *records,
                                                     NSArray<NSDictionary *> *totals,
                                                     NSError *error))completion;
@end

NS_ASSUME_NONNULL_END