#import <Foundation/Foundation.h>

@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@interface PPProviderApplication : NSObject
@property (nonatomic, copy) NSString *applicationID;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *providerType;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *planId;
@property (nonatomic, copy) NSString *profileId;
@property (nonatomic, copy) NSString *deliveryCompanyId;
@property (nonatomic, copy) NSDictionary *form;
@property (nonatomic, copy) NSDictionary *planSnapshot;
@property (nonatomic, copy) NSDictionary *userSummary;
@property (nonatomic, copy, nullable) NSDate *submittedAt;
@property (nonatomic, copy, nullable) NSDate *createdAt;
@property (nonatomic, copy, nullable) NSDate *updatedAt;
@property (nonatomic, copy, nullable) NSDate *reviewedAt;
@property (nonatomic, copy) NSString *reviewedBy;
@property (nonatomic, copy) NSString *reviewNotes;
@property (nonatomic, copy) NSString *rejectionReason;
@property (nonatomic, copy) NSString *rejectionCode;
@property (nonatomic, copy) NSArray<NSDictionary *> *reviewFindings;
@property (nonatomic, copy) NSDictionary *activationChecklist;
@property (nonatomic, assign) NSInteger resubmissionCount;
@property (nonatomic, assign) NSInteger version;
@property (nonatomic, copy) NSArray<NSString *> *tags;
@property (nonatomic, copy) NSDictionary *documents;
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
- (void)fetchApplicationsWithCompletion:(void(^)(NSArray<PPProviderApplication *> *apps, NSError * _Nullable error))completion;
- (id<FIRListenerRegistration>)listenApplicationsWithUpdate:(void(^)(NSArray<PPProviderApplication *> *apps, NSError * _Nullable error))updateBlock;
- (void)fetchPlansWithCompletion:(void(^)(NSArray<PPProviderPlan *> *plans, NSError * _Nullable error))completion;
- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
                 completion:(void(^)(NSDictionary *result, NSError * _Nullable error))completion;
- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
             rejectionCode:(nullable NSString *)rejectionCode
            reviewFindings:(nullable NSArray<NSDictionary *> *)reviewFindings
                completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;
- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
             rejectionCode:(nullable NSString *)rejectionCode
            reviewFindings:(nullable NSArray<NSDictionary *> *)reviewFindings
           expectedVersion:(nullable NSNumber *)expectedVersion
                completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;
- (void)reviewApplication:(NSString *)appID
                    status:(NSString *)status
                     notes:(nullable NSString *)notes
             rejectionCode:(nullable NSString *)rejectionCode
            reviewFindings:(nullable NSArray<NSDictionary *> *)reviewFindings
           expectedVersion:(nullable NSNumber *)expectedVersion
            idempotencyKey:(nullable NSString *)idempotencyKey
                completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;
- (void)savePlan:(NSDictionary *)planData completion:(void(^)(NSString *planID, NSError * _Nullable error))completion;
- (void)deletePlan:(NSString *)planID completion:(void(^)(NSError * _Nullable error))completion;
- (void)fetchCommissionReportForProviderID:(NSString *)providerID
                                completion:(void(^)(NSArray<PPProviderCommissionRecord *> *records,
                                                     NSArray<NSDictionary *> *totals,
                                                      NSError * _Nullable error))completion;
- (void)batchAssignReviewer:(NSArray<NSString *> *)applicationIDs
                 reviewerUid:(NSString *)reviewerUid
                  completion:(void(^)(NSInteger updatedCount, NSError * _Nullable error))completion;
- (void)batchAddTag:(NSArray<NSString *> *)applicationIDs
                 tag:(NSString *)tag
          completion:(void(^)(NSInteger updatedCount, NSError * _Nullable error))completion;
- (void)reviewApplicationDocument:(NSString *)applicationID
                     documentType:(NSString *)documentType
                         decision:(NSString *)decision
                          finding:(nullable NSString *)finding
                       expiryDate:(nullable NSString *)expiryDate
                       completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchPartnerSyncSnapshot:(NSString *)partnerId
                   clientVersion:(nullable NSNumber *)clientVersion
                      completion:(void(^)(BOOL inSync, BOOL catchUpRequired, NSDictionary * _Nullable snapshot, NSError * _Nullable error))completion;

- (void)reconcilePartnerReadModels:(NSString *)partnerId
                        completion:(void(^)(BOOL reconciled, NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)restrictPartnerAccount:(NSString *)partnerId
                         scope:(NSString *)scope
                   scopeTarget:(nullable NSString *)scopeTarget
                    reasonCode:(NSString *)reasonCode
                internalReason:(nullable NSString *)internalReason
           partnerFacingReason:(nullable NSString *)partnerFacingReason
         partnerFacingReasonAr:(nullable NSString *)partnerFacingReasonAr
                requiredAction:(nullable NSString *)requiredAction
              requiredActionAr:(nullable NSString *)requiredActionAr
               expectedVersion:(nullable NSNumber *)expectedVersion
                idempotencyKey:(nullable NSString *)idempotencyKey
                    completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)suspendPartnerAccount:(NSString *)partnerId
                        scope:(NSString *)scope
                  scopeTarget:(nullable NSString *)scopeTarget
                   reasonCode:(NSString *)reasonCode
               internalReason:(nullable NSString *)internalReason
          partnerFacingReason:(nullable NSString *)partnerFacingReason
        partnerFacingReasonAr:(nullable NSString *)partnerFacingReasonAr
               requiredAction:(nullable NSString *)requiredAction
             requiredActionAr:(nullable NSString *)requiredActionAr
              expectedVersion:(nullable NSNumber *)expectedVersion
               idempotencyKey:(nullable NSString *)idempotencyKey
                   completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)liftPartnerRestriction:(NSString *)partnerId
                 restrictionId:(NSString *)restrictionId
                    liftReason:(NSString *)liftReason
                  liftReasonAr:(nullable NSString *)liftReasonAr
               expectedVersion:(nullable NSNumber *)expectedVersion
                idempotencyKey:(nullable NSString *)idempotencyKey
                    completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchPartnerRestrictions:(NSString *)partnerId
                      completion:(void(^)(NSDictionary * _Nullable summary, NSError * _Nullable error))completion;

- (void)reviewPartnerReactivation:(NSString *)partnerId
                        requestId:(NSString *)requestId
                         decision:(NSString *)decision
                       conditions:(nullable NSArray<NSString *> *)conditions
                  rejectionReason:(nullable NSString *)rejectionReason
                rejectionReasonAr:(nullable NSString *)rejectionReasonAr
                       adminNotes:(nullable NSString *)adminNotes
                  expectedVersion:(nullable NSNumber *)expectedVersion
                   idempotencyKey:(nullable NSString *)idempotencyKey
                       completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)reinstatePartner:(NSString *)partnerId
                  reason:(NSString *)reason
                reasonAr:(nullable NSString *)reasonAr
              conditions:(nullable NSArray<NSString *> *)conditions
         expectedVersion:(nullable NSNumber *)expectedVersion
          idempotencyKey:(nullable NSString *)idempotencyKey
              completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchPartnerReactivationDossier:(NSString *)partnerId
                             completion:(void(^)(NSDictionary * _Nullable dossier, NSError * _Nullable error))completion;

- (void)initiatePartnerOffboarding:(NSString *)partnerId
                   offboardingType:(NSString *)offboardingType
                        reasonCode:(NSString *)reasonCode
                            reason:(NSString *)reason
                          reasonAr:(nullable NSString *)reasonAr
                   expectedVersion:(nullable NSNumber *)expectedVersion
                    idempotencyKey:(nullable NSString *)idempotencyKey
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)resolvePartnerOffboardingOperations:(NSString *)partnerId
                       remainingOrdersCount:(nullable NSNumber *)remainingOrdersCount
                                      notes:(nullable NSString *)notes
                            expectedVersion:(nullable NSNumber *)expectedVersion
                                 completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)settlePartnerOffboarding:(NSString *)partnerId
             settlementReference:(nullable NSString *)settlementReference
                           notes:(nullable NSString *)notes
                 expectedVersion:(nullable NSNumber *)expectedVersion
                      completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)finalizePartnerOffboarding:(NSString *)partnerId
                     forceOverride:(BOOL)forceOverride
                    overrideReason:(nullable NSString *)overrideReason
                   expectedVersion:(nullable NSNumber *)expectedVersion
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchPartnerOffboardingDossier:(NSString *)partnerId
                            completion:(void(^)(NSDictionary * _Nullable dossier, NSError * _Nullable error))completion;

- (void)fetchPartnerAuditTrail:(NSString *)partnerId
                         limit:(nullable NSNumber *)limit
                filterCategory:(nullable NSString *)filterCategory
                    completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)verifyPartnerAuditProvenance:(NSString *)partnerId
            includeComplianceDossier:(BOOL)includeComplianceDossier
                          completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)redactPartnerPersonalData:(NSString *)partnerId
                      legalReason:(nullable NSString *)legalReason
                        requestId:(nullable NSString *)requestId
                  expectedVersion:(nullable NSNumber *)expectedVersion
                       completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)exportPartnerPrivacyData:(NSString *)partnerId
                      completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchPartnerCockpitSummary:(NSString *)partnerId
                        clientEtag:(nullable NSString *)clientEtag
                      forceRefresh:(BOOL)forceRefresh
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchPartnerObservabilityDashboardWithCompletion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)reconstructPartnerState:(NSString *)partnerId
                           mode:(NSString *)mode
                  upToTimestamp:(nullable NSString *)upToTimestamp
                   repairReason:(nullable NSString *)repairReason
                     completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchPartnerDisasterRecoveryDashboardWithCompletion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

- (void)createPartnerCheckpointSnapshot:(NSString *)partnerId
                             completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
