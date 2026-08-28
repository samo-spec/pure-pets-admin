#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PPDeliveryServiceErrorDomain;

@interface PPDeliveryAllowedAction : NSObject
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *permission;
@property (nonatomic, assign) NSInteger expectedRevision;
@property (nonatomic, copy) NSString *expectedState;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryRequestRecord : NSObject
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy) NSString *orderID;
@property (nonatomic, copy) NSString *orderNumber;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *authority;
@property (nonatomic, copy) NSString *deliveryJobStatus;
@property (nonatomic, copy) NSString *carrierAssignmentStatus;
@property (nonatomic, copy) NSString *driverAssignmentStatus;
@property (nonatomic, copy) NSString *routeStatus;
@property (nonatomic, copy) NSString *podStatus;
@property (nonatomic, copy) NSString *codStatus;
@property (nonatomic, copy) NSString *returnStatus;
@property (nonatomic, assign) NSInteger revision;
@property (nonatomic, copy) NSString *carrierID;
@property (nonatomic, copy) NSString *carrierName;
@property (nonatomic, copy) NSString *carrierType;
@property (nonatomic, copy) NSString *customerName;
@property (nonatomic, copy) NSString *assignedDriverUID;
@property (nonatomic, copy) NSString *assignedDriverName;
@property (nonatomic, strong, nullable) NSNumber *deliveryFee;
@property (nonatomic, copy) NSDictionary *pickupAddress;
@property (nonatomic, copy) NSDictionary *dropoffAddress;
@property (nonatomic, copy) NSDictionary *proofOfDelivery;
@property (nonatomic, copy) NSDictionary *cod;
@property (nonatomic, copy) NSArray<PPDeliveryAllowedAction *> *allowedActions;
@property (nonatomic, copy, nullable) NSDate *createdAt;
@property (nonatomic, copy, nullable) NSDate *updatedAt;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary documentID:(NSString *)documentID;
- (nullable PPDeliveryAllowedAction *)allowedActionNamed:(NSString *)action
    NS_SWIFT_NAME(allowedAction(named:));
@end

@interface PPDeliveryDriverRecord : NSObject
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *phone;
@property (nonatomic, copy) NSString *accountStatus;
@property (nonatomic, copy) NSString *presence;
@property (nonatomic, copy) NSString *shiftStatus;
@property (nonatomic, copy) NSString *workState;
@property (nonatomic, assign) BOOL canReceiveAssignments;
@property (nonatomic, assign) NSInteger activeDeliveryCount;
@property (nonatomic, strong, nullable) NSNumber *maxConcurrentDeliveries;
@property (nonatomic, assign) NSInteger revision;
@property (nonatomic, assign) BOOL eligible;
@property (nonatomic, copy) NSArray<NSString *> *eligibilityReasonCodes;
@property (nonatomic, copy) NSDictionary *eligibilityEvidence;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryVehicleRecord : NSObject
@property (nonatomic, copy) NSString *vehicleID;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *plate;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSDictionary *capacity;
@property (nonatomic, copy) NSString *driverUID;
@property (nonatomic, copy) NSString *hubID;
@property (nonatomic, copy) NSDictionary *compliance;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryHubRecord : NSObject
@property (nonatomic, copy) NSString *hubID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSDictionary *location;
@property (nonatomic, copy) NSArray<NSString *> *zoneIDs;
@property (nonatomic, copy) NSDictionary *capabilities;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryServiceZoneRecord : NSObject
@property (nonatomic, copy) NSString *zoneID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSDictionary *boundary;
@property (nonatomic, copy) NSArray<NSString *> *hubIDs;
@property (nonatomic, copy) NSDictionary *capabilities;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryDriverShiftRecord : NSObject
@property (nonatomic, copy) NSString *shiftID;
@property (nonatomic, copy) NSString *driverUID;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy, nullable) NSDate *plannedStartAt;
@property (nonatomic, copy, nullable) NSDate *plannedEndAt;
@property (nonatomic, copy, nullable) NSDate *actualStartAt;
@property (nonatomic, copy, nullable) NSDate *actualEndAt;
@property (nonatomic, assign) NSInteger revision;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryRouteStopRecord : NSObject
@property (nonatomic, copy) NSString *stopID;
@property (nonatomic, copy) NSString *routeID;
@property (nonatomic, copy) NSString *deliveryJobID;
@property (nonatomic, assign) NSInteger sequence;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSDictionary *location;
@property (nonatomic, copy) NSDictionary *timeWindow;
@property (nonatomic, strong, nullable) NSNumber *serviceDuration;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy, nullable) NSDate *plannedArrival;
@property (nonatomic, copy, nullable) NSDate *estimatedArrival;
@property (nonatomic, copy, nullable) NSDate *actualArrival;
@property (nonatomic, copy, nullable) NSDate *actualDeparture;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryRouteRecord : NSObject
@property (nonatomic, copy) NSString *routeID;
@property (nonatomic, copy) NSString *carrierID;
@property (nonatomic, copy) NSString *driverUID;
@property (nonatomic, copy) NSString *vehicleID;
@property (nonatomic, copy) NSString *hubID;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy, nullable) NSDate *plannedStartAt;
@property (nonatomic, copy, nullable) NSDate *plannedEndAt;
@property (nonatomic, copy, nullable) NSDate *actualStartAt;
@property (nonatomic, copy, nullable) NSDate *actualEndAt;
@property (nonatomic, assign) NSInteger stopCount;
@property (nonatomic, assign) NSInteger completedStopCount;
@property (nonatomic, strong, nullable) NSNumber *distanceMeters;
@property (nonatomic, strong, nullable) NSNumber *durationSeconds;
@property (nonatomic, copy) NSDictionary *capacity;
@property (nonatomic, assign) NSInteger revision;
@property (nonatomic, copy) NSArray<PPDeliveryRouteStopRecord *> *stops;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryFleetFoundation : NSObject
@property (nonatomic, copy) NSString *configurationState;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSArray<PPDeliveryVehicleRecord *> *vehicles;
@property (nonatomic, copy) NSArray<PPDeliveryHubRecord *> *hubs;
@property (nonatomic, copy) NSArray<PPDeliveryServiceZoneRecord *> *serviceZones;
@property (nonatomic, copy) NSArray<PPDeliveryDriverShiftRecord *> *driverShifts;
@property (nonatomic, copy) NSArray<PPDeliveryRouteRecord *> *routes;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryExceptionRecord : NSObject
@property (nonatomic, copy) NSString *exceptionID;
@property (nonatomic, copy) NSString *deliveryJobID;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *severity;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *reasonCode;
@property (nonatomic, copy) NSDictionary *evidence;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryCommandCenterSnapshot : NSObject
@property (nonatomic, copy) NSDictionary *carrier;
@property (nonatomic, copy) NSArray<PPDeliveryRequestRecord *> *records;
@property (nonatomic, copy) NSArray<PPDeliveryDriverRecord *> *drivers;
@property (nonatomic, copy) NSArray<PPDeliveryExceptionRecord *> *exceptions;
@property (nonatomic, copy) NSDictionary *projection;
@property (nonatomic, strong) PPDeliveryFleetFoundation *fleet;
@property (nonatomic, copy) NSDictionary *capabilities;
@property (nonatomic, copy) NSArray<NSString *> *permissions;
@property (nonatomic, copy) NSString *permissionSource;
@property (nonatomic, copy) NSDictionary *eligibilityContext;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryDossierSnapshot : NSObject
@property (nonatomic, strong) PPDeliveryRequestRecord *record;
@property (nonatomic, copy) NSDictionary *carrier;
@property (nonatomic, copy) NSArray<NSDictionary *> *events;
@property (nonatomic, copy) NSArray<PPDeliveryDriverRecord *> *drivers;
@property (nonatomic, copy) NSDictionary *availabilityFunnel;
@property (nonatomic, copy) NSDictionary *freshness;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryCommandResult : NSObject
@property (nonatomic, copy) NSString *commandID;
@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, assign) NSInteger revision;
@property (nonatomic, copy) NSString *outcome;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface PPDeliveryService : NSObject
+ (instancetype)shared;

/// Canonical bounded projection used by both native Admin and web Control.
- (void)fetchCommandCenterWithCompletion:(void(^)(PPDeliveryCommandCenterSnapshot * _Nullable snapshot,
                                                    NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchCommandCenter(completion:));
- (void)fetchDossierForRequestID:(NSString *)requestID
                       completion:(void(^)(PPDeliveryDossierSnapshot * _Nullable dossier,
                                            NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchDossier(requestID:completion:));

/// Executes an Infra-owned command. The action's revision and state are copied
/// from the latest server response; callers cannot choose arbitrary states.
- (void)executeAllowedAction:(PPDeliveryAllowedAction *)allowedAction
                   requestID:(NSString *)requestID
                   commandID:(NSString *)commandID
                   driverUID:(nullable NSString *)driverUID
           handoverConfirmed:(BOOL)handoverConfirmed
                      reason:(nullable NSString *)reason
                  completion:(void(^)(PPDeliveryCommandResult * _Nullable result,
                                       NSError * _Nullable error))completion
    NS_SWIFT_NAME(execute(action:requestID:commandID:driverUID:handoverConfirmed:reason:completion:));

- (void)executeDriverAction:(NSString *)action
                  driverUID:(NSString *)driverUID
           expectedRevision:(NSInteger)expectedRevision
                  commandID:(NSString *)commandID
                 completion:(void(^)(NSError * _Nullable error))completion
    NS_SWIFT_NAME(executeDriver(action:driverUID:expectedRevision:commandID:completion:));

/// Structured Firebase Functions errors are the only source for entity-specific
/// business classification. A generic Firebase `not-found` remains a service
/// incident and is never interpreted as missing carrier configuration.
+ (NSDictionary<NSString *, id> *)domainDetailsForError:(nullable NSError *)error
    NS_SWIFT_NAME(domainDetails(for:));
+ (NSString *)domainCodeForError:(nullable NSError *)error
    NS_SWIFT_NAME(domainCode(for:));
+ (BOOL)isPermissionError:(nullable NSError *)error
    NS_SWIFT_NAME(isPermissionError(_:));

#pragma mark - Legacy callable compatibility

- (void)fetchDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> * _Nullable records, NSError * _Nullable error))completion;
- (void)fetchAllDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> * _Nullable records, NSError * _Nullable error))completion;
- (void)acceptRequest:(NSString *)requestID completion:(void(^)(NSError * _Nullable error))completion;
- (void)assignDriver:(NSString *)requestID driverUID:(NSString *)driverUID completion:(void(^)(NSError * _Nullable error))completion;
- (void)completeRequest:(NSString *)requestID completion:(void(^)(NSError * _Nullable error))completion;
- (void)cancelRequest:(NSString *)requestID completion:(void(^)(NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
