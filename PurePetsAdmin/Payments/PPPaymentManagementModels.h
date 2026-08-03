#import <Foundation/Foundation.h>

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPPaymentAdminDateRange) {
    PPPaymentAdminDateRangeAll = 0,
    PPPaymentAdminDateRangeToday,
    PPPaymentAdminDateRangeLast7Days,
    PPPaymentAdminDateRangeLast30Days,
    PPPaymentAdminDateRangeLast90Days,
};

typedef NS_ENUM(NSInteger, PPPaymentAdminRequestResolution) {
    PPPaymentAdminRequestResolutionApprove = 0,
    PPPaymentAdminRequestResolutionReject,
    PPPaymentAdminRequestResolutionComplete,
    PPPaymentAdminRequestResolutionRefund,
    PPPaymentAdminRequestResolutionPartialRefund,
    PPPaymentAdminRequestResolutionClose,
};

@class PPPaymentAdminSupportRequest;

@interface PPPaymentManagementFilters : NSObject <NSCopying>

@property (nonatomic, copy) NSString *statusKey;
@property (nonatomic, copy) NSString *paymentTypeKey;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, assign) PPPaymentAdminDateRange dateRange;

+ (instancetype)defaultFilters;
- (BOOL)isDefaultState;

@end

@interface PPPaymentAdminSettings : NSObject

@property (nonatomic, assign) double deliveryFee;
@property (nonatomic, assign) BOOL cashOnDeliveryEnabled;
@property (nonatomic, assign) BOOL onlinePaymentEnabled;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
@property (nonatomic, copy, nullable) NSString *updatedBy;

+ (instancetype)settingsFromDictionary:(NSDictionary *)dictionary;

@end

@interface PPPaymentAdminTimelineEvent : NSObject

@property (nonatomic, copy) NSString *eventId;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *actorType;
@property (nonatomic, copy) NSString *summaryCode;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, strong, nullable) NSDictionary *metadata;
@property (nonatomic, strong) NSDate *createdAt;

+ (instancetype)eventFromSnapshot:(FIRDocumentSnapshot *)snapshot;
+ (instancetype)eventFromDictionary:(NSDictionary *)dictionary documentID:(nullable NSString *)documentID;

@end

@interface PPPaymentAdminAuditEntry : NSObject

@property (nonatomic, copy) NSString *auditId;
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *area;
@property (nonatomic, copy) NSString *entityType;
@property (nonatomic, copy) NSString *entityId;
@property (nonatomic, copy) NSString *orderId;
@property (nonatomic, copy) NSString *requestId;
@property (nonatomic, copy) NSString *adminUid;
@property (nonatomic, copy) NSString *adminName;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, strong, nullable) NSDictionary *beforeState;
@property (nonatomic, strong, nullable) NSDictionary *afterState;
@property (nonatomic, strong) NSDate *createdAt;

+ (instancetype)auditFromSnapshot:(FIRDocumentSnapshot *)snapshot;
+ (instancetype)auditFromDictionary:(NSDictionary *)dictionary documentID:(nullable NSString *)documentID;

@end

@interface PPPaymentAdminSupportRequest : NSObject

@property (nonatomic, copy) NSString *requestId;
@property (nonatomic, copy) NSString *orderId;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *reasonCode;
@property (nonatomic, copy) NSString *reasonTitle;
@property (nonatomic, copy) NSString *issueCategory;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *notes;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *finalResolution;
@property (nonatomic, copy) NSArray<NSString *> *itemIDs;
@property (nonatomic, copy) NSArray<NSDictionary *> *itemSnapshots;
@property (nonatomic, copy) NSArray<NSDictionary *> *attachments;
@property (nonatomic, strong, nullable) NSDictionary *resolution;
@property (nonatomic, strong, nullable) NSDictionary *adminReview;
@property (nonatomic, strong, nullable) NSDate *submittedAt;
@property (nonatomic, strong, nullable) NSDate *resolvedAt;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, copy) NSArray<PPPaymentAdminTimelineEvent *> *events;

+ (instancetype)requestFromSnapshot:(FIRDocumentSnapshot *)snapshot;
+ (instancetype)requestFromDictionary:(NSDictionary *)dictionary documentID:(nullable NSString *)documentID;
- (BOOL)isRefundLike;
- (BOOL)isReturnLike;
- (BOOL)isCancellationLike;
- (BOOL)isOpen;
- (NSString *)effectiveResolutionKey;

@end

@interface PPPaymentAdminRecord : NSObject

@property (nonatomic, copy) NSString *orderId;
@property (nonatomic, copy, nullable) NSString *orderNumber;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *userDisplayName;
@property (nonatomic, copy) NSString *userEmail;
@property (nonatomic, copy) NSString *rawStatus;
@property (nonatomic, copy) NSString *paymentMethodId;
@property (nonatomic, copy) NSString *paymentStatus;
@property (nonatomic, copy) NSString *paymentProvider;
@property (nonatomic, copy) NSString *paymentTypeKey;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, copy) NSString *transactionId;
@property (nonatomic, copy) NSString *verificationStatus;
@property (nonatomic, copy) NSString *failureReason;
@property (nonatomic, copy) NSString *refundStatus;
@property (nonatomic, copy) NSString *returnStatus;
@property (nonatomic, copy) NSString *latestRequestType;
@property (nonatomic, copy) NSString *latestRequestStatus;
@property (nonatomic, assign) NSInteger fulfillmentVersion;
@property (nonatomic, copy) NSArray<NSString *> *fulfillmentOrderIDs;
@property (nonatomic, assign) double totalAmount;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, strong, nullable) NSDate *statusUpdatedAt;
@property (nonatomic, strong, nullable) NSDate *paidAt;
@property (nonatomic, strong, nullable) NSDate *processedAt;
@property (nonatomic, strong, nullable) NSDate *shippedAt;
@property (nonatomic, strong, nullable) NSDate *deliveredAt;
@property (nonatomic, strong, nullable) NSDate *cancelledAt;
@property (nonatomic, strong, nullable) NSDate *paymentCollectedAt;
@property (nonatomic, strong, nullable) NSDate *estimatedDeliveryAt;
@property (nonatomic, copy) NSArray<NSDictionary *> *items;
@property (nonatomic, strong) NSDictionary *shippingAddressSnapshot;
@property (nonatomic, assign) BOOL inventoryDeducted;
@property (nonatomic, assign) BOOL inventoryRestocked;
@property (nonatomic, strong, nullable) NSDictionary *paymentResponse;
@property (nonatomic, copy) NSArray<PPPaymentAdminSupportRequest *> *requests;
@property (nonatomic, copy) NSArray<PPPaymentAdminTimelineEvent *> *timelineEvents;
@property (nonatomic, copy) NSArray<PPPaymentAdminAuditEntry *> *auditEntries;
@property (nonatomic, strong, nullable) FIRDocumentSnapshot *sourceSnapshot;

+ (instancetype)recordFromSnapshot:(FIRDocumentSnapshot *)snapshot;
+ (instancetype)recordFromDictionary:(NSDictionary *)dictionary documentID:(nullable NSString *)documentID;

+ (NSString *)normalizedStatusString:(nullable id)value;
+ (BOOL)status:(NSString *)statusKey matchesAnyKeywords:(NSArray<NSString *> *)keywords;
+ (BOOL)isPaidLikeStatus:(NSString *)statusKey;
+ (BOOL)isFailureLikeStatus:(NSString *)statusKey;
+ (BOOL)isCancelledLikeStatus:(NSString *)statusKey;
+ (BOOL)isProcessingLikeStatus:(NSString *)statusKey;
+ (BOOL)isShippedLikeStatus:(NSString *)statusKey;
+ (BOOL)isDeliveredLikeStatus:(NSString *)statusKey;
+ (BOOL)requestStatusIsOpen:(NSString *)statusKey;
+ (BOOL)isFinalRequestStatus:(NSString *)statusKey;
+ (BOOL)canApproveOrderStatus:(NSString *)statusKey;
+ (BOOL)canMarkOrderProcessingStatus:(NSString *)statusKey;
+ (BOOL)canMarkOrderProcessingForOrder:(PPPaymentAdminRecord *)order;
+ (BOOL)canMarkOrderShippedStatus:(NSString *)statusKey;
+ (BOOL)canMarkOrderDeliveredStatus:(NSString *)statusKey;
+ (BOOL)canCancelOrderStatus:(NSString *)statusKey;
+ (BOOL)canCollectCashPaymentForOrder:(PPPaymentAdminRecord *)order;
+ (BOOL)orderHasCapturedPaymentForStatus:(NSString *)statusKey
                           transactionId:(nullable NSString *)transactionId
                                   paidAt:(nullable NSDate *)paidAt;
+ (BOOL)canResolveRequest:(PPPaymentAdminSupportRequest *)request
                 withAction:(PPPaymentAdminRequestResolution)action
                     order:(PPPaymentAdminRecord *)order;
+ (NSArray<NSString *> *)quickStatusFilterKeys;

- (NSString *)workflowStatusKey;
- (BOOL)matchesFilters:(PPPaymentManagementFilters *)filters;
- (BOOL)matchesSearchText:(NSString *)searchText;
- (BOOL)hasOpenRequests;
- (BOOL)hasRefundSignal;
- (BOOL)hasReturnSignal;
- (void)applyRequestSummaries:(NSArray<PPPaymentAdminSupportRequest *> *)requests;
- (NSString *)displayOrderReference;

@end

FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForRequestStatus(NSString *statusKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForRequestType(NSString *typeKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForWorkflowStatus(NSString *statusKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForResolutionAction(PPPaymentAdminRequestResolution action);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForPaymentMethod(NSString *methodKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForOrderStatus(NSString *statusKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForVerificationStatus(NSString *statusKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForFailureReason(NSString *reasonKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForIssueCategory(NSString *categoryKey);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForActorType(NSString *actorType);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForTimelineSummary(PPPaymentAdminTimelineEvent *event);
FOUNDATION_EXTERN NSString * PPPaymentAdminDisplayTitleForAuditAction(NSString *actionKey);
FOUNDATION_EXTERN NSDate * _Nullable PPPaymentAdminDateFromValue(id _Nullable value);

NS_ASSUME_NONNULL_END
