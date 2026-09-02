#import <Foundation/Foundation.h>

@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@interface PPFulfillmentRecord : NSObject
@property (nonatomic, copy) NSString *fulfillmentID;
@property (nonatomic, copy) NSString *branchId;
@property (nonatomic, copy) NSString *regionId;
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
@property (nonatomic, copy, nullable) NSString *adminOverrideCommandID;

- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPFulfillmentService : NSObject
+ (instancetype)shared NS_SWIFT_NAME(shared());
+ (BOOL)isPartialReadError:(nullable NSError *)error;

- (void)fetchFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *records, NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchFulfillments(completion:));

- (id<FIRListenerRegistration>)observeFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *records, BOOL isFromCache, NSError * _Nullable error))completion
    NS_SWIFT_NAME(observeFulfillments(completion:));

- (id<FIRListenerRegistration>)observeFulfillment:(NSString *)fulfillmentID
                                       completion:(void(^)(PPFulfillmentRecord * _Nullable record, BOOL isFromCache, BOOL hasPendingWrites, NSError * _Nullable error))completion
    NS_SWIFT_NAME(observeFulfillment(_:completion:));

- (id<FIRListenerRegistration>)observeAdminOverrideCommand:(NSString *)fulfillmentID
                                      commandDocumentID:(NSString *)commandDocumentID
                                             completion:(void(^)(NSDictionary * _Nullable command, BOOL isFromCache, BOOL hasPendingWrites, NSError * _Nullable error))completion
    NS_SWIFT_NAME(observeAdminOverrideCommand(_:commandDocumentID:completion:));

- (void)fetchFulfillmentDetail:(NSString *)fulfillmentID completion:(void(^)(PPFulfillmentRecord * _Nullable record, NSArray *events, NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchFulfillmentDetail(_:completion:));

/// Resolves the single official, platform-owned child using only the exact IDs
/// already bound to the parent order. Partner children are never returned.
- (void)fetchOfficialFulfillmentForParentOrderID:(NSString *)parentOrderID
                                  fulfillmentIDs:(NSArray<NSString *> *)fulfillmentIDs
                                      completion:(void(^)(PPFulfillmentRecord * _Nullable record, NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchOfficialFulfillment(parentOrderID:fulfillmentIDs:completion:));

- (id<FIRListenerRegistration>)observeFulfillmentEvents:(NSString *)fulfillmentID completion:(void(^)(NSArray<NSDictionary *> *events, NSError * _Nullable error))completion
    NS_SWIFT_NAME(observeFulfillmentEvents(_:completion:));

- (void)resolveUserProfilesForIDs:(NSArray<NSString *> *)userIDs completion:(void(^)(NSDictionary<NSString *, NSString *> *names))completion
    NS_SWIFT_NAME(resolveUserProfiles(forIDs:completion:));

- (void)adminOverrideFulfillment:(NSString *)fulfillmentID
                   expectedStatus:(NSString *)expectedStatus
                    targetStatus:(NSString *)status
                          reason:(NSString *)reason
                             note:(nullable NSString *)note
                           notify:(BOOL)notify
                        commandID:(NSString *)commandID
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion
    NS_SWIFT_NAME(adminOverride(_:expectedStatus:targetStatus:reason:note:notify:commandID:completion:));

/// Advances only the official platform child through the normal provider-side
/// lifecycle graph. The callable remains the authoritative permission and
/// transition gate and synchronizes the parent projection atomically.
- (void)transitionOfficialFulfillment:(PPFulfillmentRecord *)record
                       expectedStatus:(NSString *)expectedStatus
                                action:(NSString *)action
                                  note:(NSString *)note
                             commandID:(NSString *)commandID
                            completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion
    NS_SWIFT_NAME(transitionOfficialFulfillment(_:expectedStatus:action:note:commandID:completion:));

/// Repairs only the recoverable fulfillment-v1 gap where the deterministic
/// official child is absent, then applies a legal `new_request` transition.
/// The callable performs the authority, scope, parent-state, idempotency, and
/// audit checks atomically; this client never writes fulfillment data directly.
- (void)initializeAndTransitionOfficialFulfillmentForOrderID:(NSString *)orderID
                                          expectedParentStatus:(NSString *)expectedParentStatus
                                                        action:(NSString *)action
                                                          note:(NSString *)note
                                                     commandID:(NSString *)commandID
                                                    completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion
    NS_SWIFT_NAME(initializeAndTransitionOfficialFulfillment(orderID:expectedParentStatus:action:note:commandID:completion:));

/// Mirrors the callable's canonical `payments.manage` authorization gate.
- (BOOL)canAdminOverride NS_SWIFT_NAME(canAdminOverride());

+ (NSArray<NSString *> *)allowedOverrideTargetsForStatus:(NSString *)currentStatus
    NS_SWIFT_NAME(allowedOverrideTargets(forStatus:));

+ (BOOL)isOfficialPlatformFulfillment:(nullable PPFulfillmentRecord *)record
    NS_SWIFT_NAME(isOfficialPlatformFulfillment(_:));

+ (NSArray<NSString *> *)availableOfficialActionsForStatus:(NSString *)currentStatus
    NS_SWIFT_NAME(availableOfficialActions(forStatus:));
@end

NS_ASSUME_NONNULL_END
