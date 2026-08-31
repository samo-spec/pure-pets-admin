#import "PPDeliveryService.h"
#import "PPFirebaseCompat.h"

NSString * const PPDeliveryServiceErrorDomain = @"PPDeliveryService";

static NSString * const kPPLegacyCompanyID = @"purepets_deliveries";

static NSDictionary *PPDeliveryDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray *PPDeliveryArray(id value) {
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSArray<NSString *> *PPDeliveryStringArray(id value) {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (id entry in PPDeliveryArray(value)) {
        if ([entry isKindOfClass:NSString.class] && [(NSString *)entry length] > 0) {
            [strings addObject:entry];
        }
    }
    return strings.copy;
}

static NSString *PPDeliveryString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}

static NSDate * _Nullable PPDeliveryDate(id value) {
    if ([value isKindOfClass:NSDate.class]) return value;
    if ([value isKindOfClass:FIRTimestamp.class]) return [(FIRTimestamp *)value dateValue];
    if (![value isKindOfClass:NSString.class] || [(NSString *)value length] == 0) return nil;
    if (@available(iOS 10.0, *)) {
        NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
        return [formatter dateFromString:value];
    }
    return nil;
}

static NSError *PPDeliveryInvalidResponseError(void) {
    NSString *description = kLang(@"Delivery_Invalid_Response");
    if (description.length == 0 || [description isEqualToString:@"Delivery_Invalid_Response"]) {
        description = @"Delivery service returned an invalid response.";
    }
    return [NSError errorWithDomain:PPDeliveryServiceErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@implementation PPDeliveryAllowedAction

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _action = [PPDeliveryString(source[@"action"]) uppercaseString];
        _permission = PPDeliveryString(source[@"permission"]);
        _expectedRevision = [source[@"expectedRevision"] respondsToSelector:@selector(integerValue)]
            ? [source[@"expectedRevision"] integerValue]
            : -1;
        _expectedState = [PPDeliveryString(source[@"expectedState"]) lowercaseString];
    }
    return self;
}

@end


@implementation PPDeliveryRequestRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary documentID:(NSString *)documentID {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _requestID = documentID.length > 0 ? documentID : PPDeliveryString(source[@"id"]);
        _orderID = PPDeliveryString(source[@"orderId"]);
        _orderNumber = PPDeliveryString(source[@"reference"]);
        if (_orderNumber.length == 0) _orderNumber = PPDeliveryString(source[@"orderNumber"]);
        _status = [PPDeliveryString(source[@"legacyStatus"]) lowercaseString];
        if (_status.length == 0) _status = [PPDeliveryString(source[@"status"]) lowercaseString];
        _authority = PPDeliveryString(source[@"authority"]);
        if (_authority.length == 0) {
            _authority = [source[@"fulfillmentVersion"] integerValue] == 1
                ? @"FULFILLMENT_V1"
                : @"COMPANY_DELIVERY_REQUEST";
        }
        _deliveryJobStatus = PPDeliveryString(source[@"deliveryJobStatus"]);
        _carrierAssignmentStatus = PPDeliveryString(source[@"carrierAssignmentStatus"]);
        _driverAssignmentStatus = PPDeliveryString(source[@"driverAssignmentStatus"]);
        _routeStatus = PPDeliveryString(source[@"routeStatus"]);
        _podStatus = PPDeliveryString(source[@"podStatus"]);
        _codStatus = PPDeliveryString(source[@"codStatus"]);
        _returnStatus = PPDeliveryString(source[@"returnStatus"]);
        _revision = MAX(0, [source[@"revision"] respondsToSelector:@selector(integerValue)]
                            ? [source[@"revision"] integerValue]
                            : 0);
        _carrierID = PPDeliveryString(source[@"carrierId"]);
        if (_carrierID.length == 0) _carrierID = PPDeliveryString(source[@"targetCompanyId"]);
        _carrierName = PPDeliveryString(source[@"carrierName"]);
        if (_carrierName.length == 0) _carrierName = PPDeliveryString(source[@"targetCompanyName"]);
        _carrierType = PPDeliveryString(source[@"carrierType"]);
        _customerName = PPDeliveryString(source[@"customerName"]);
        _assignedDriverUID = PPDeliveryString(source[@"assignedDriverUid"]);
        _assignedDriverName = PPDeliveryString(source[@"assignedDriverName"]);
        _deliveryFee = [source[@"deliveryFee"] isKindOfClass:NSNumber.class] ? source[@"deliveryFee"] : nil;
        _pickupAddress = [PPDeliveryDictionary(source[@"pickupAddress"]) copy];
        _dropoffAddress = [PPDeliveryDictionary(source[@"dropoffAddress"]) copy];
        _proofOfDelivery = [PPDeliveryDictionary(source[@"pod"] ?: source[@"proofOfDelivery"]) copy];
        _cod = [PPDeliveryDictionary(source[@"cod"]) copy];

        NSMutableArray<PPDeliveryAllowedAction *> *actions = [NSMutableArray array];
        for (id rawAction in PPDeliveryArray(source[@"allowedActions"])) {
            if (![rawAction isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryAllowedAction *action = [[PPDeliveryAllowedAction alloc] initWithDictionary:rawAction];
            if (action.action.length > 0 && action.expectedRevision >= 0 && action.expectedState.length > 0) {
                [actions addObject:action];
            }
        }
        _allowedActions = actions.copy;
        _createdAt = PPDeliveryDate(source[@"createdAt"]);
        _updatedAt = PPDeliveryDate(source[@"updatedAt"]);
    }
    return self;
}

- (PPDeliveryAllowedAction * _Nullable)allowedActionNamed:(NSString *)action {
    NSString *target = [action.uppercaseString copy];
    for (PPDeliveryAllowedAction *candidate in self.allowedActions) {
        if ([candidate.action isEqualToString:target]) return candidate;
    }
    return nil;
}

@end


@implementation PPDeliveryDriverRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        NSDictionary *eligibility = PPDeliveryDictionary(source[@"eligibility"]);
        _uid = PPDeliveryString(source[@"uid"]);
        _displayName = PPDeliveryString(source[@"displayName"]);
        if (_displayName.length == 0) _displayName = _uid;
        _phone = PPDeliveryString(source[@"phone"]);
        _accountStatus = PPDeliveryString(source[@"accountStatus"]);
        _presence = PPDeliveryString(source[@"presence"]);
        _shiftStatus = PPDeliveryString(source[@"shiftStatus"]);
        _workState = PPDeliveryString(source[@"workState"]);
        _canReceiveAssignments = [source[@"canReceiveAssignments"] boolValue];
        _activeDeliveryCount = MAX(0, [source[@"activeDeliveryCount"] integerValue]);
        _maxConcurrentDeliveries = [source[@"maxConcurrentDeliveries"] isKindOfClass:NSNumber.class]
            ? source[@"maxConcurrentDeliveries"]
            : nil;
        _revision = MAX(0, [source[@"revision"] integerValue]);
        _eligible = [eligibility[@"eligible"] boolValue];
        _eligibilityReasonCodes = PPDeliveryStringArray(eligibility[@"reasonCodes"]);
        _eligibilityEvidence = [PPDeliveryDictionary(eligibility[@"evidence"]) copy];
    }
    return self;
}

@end


@implementation PPDeliveryCompanyMemberRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _uid = PPDeliveryString(source[@"uid"]);
        _displayName = PPDeliveryString(source[@"displayName"]);
        if (_displayName.length == 0) _displayName = _uid;
        _phone = PPDeliveryString(source[@"phone"]);
        _email = PPDeliveryString(source[@"email"]);
        _photoURL = PPDeliveryString(source[@"photoURL"]);
        if (_photoURL.length == 0) _photoURL = PPDeliveryString(source[@"UserImageUrl"]);
        _role = [PPDeliveryString(source[@"role"]) lowercaseString];
        _status = [PPDeliveryString(source[@"status"]) lowercaseString];
        _online = [source[@"isOnline"] boolValue];
        _available = source[@"isAvailable"] == nil ? YES : [source[@"isAvailable"] boolValue];
        _canReceiveAssignments = [source[@"canReceiveAssignments"] boolValue];
        _activeDeliveryCount = MAX(0, [source[@"activeDeliveryCount"] integerValue]);
        _lastSeenAt = PPDeliveryDate(source[@"lastSeenAt"]);
    }
    return self;
}

@end


@implementation PPDeliveryVehicleRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _vehicleID = PPDeliveryString(source[@"id"]);
        _label = PPDeliveryString(source[@"label"]);
        _plate = PPDeliveryString(source[@"plate"]);
        _type = PPDeliveryString(source[@"type"]);
        _status = PPDeliveryString(source[@"status"]);
        _capacity = [PPDeliveryDictionary(source[@"capacity"]) copy];
        _driverUID = PPDeliveryString(source[@"driverUid"]);
        _hubID = PPDeliveryString(source[@"hubId"]);
        _compliance = [PPDeliveryDictionary(source[@"compliance"]) copy];
    }
    return self;
}

@end


@implementation PPDeliveryHubRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _hubID = PPDeliveryString(source[@"id"]);
        _name = PPDeliveryString(source[@"name"]);
        _status = PPDeliveryString(source[@"status"]);
        _location = [PPDeliveryDictionary(source[@"location"]) copy];
        _zoneIDs = PPDeliveryStringArray(source[@"zoneIds"]);
        _capabilities = [PPDeliveryDictionary(source[@"capabilities"]) copy];
    }
    return self;
}

@end


@implementation PPDeliveryServiceZoneRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _zoneID = PPDeliveryString(source[@"id"]);
        _name = PPDeliveryString(source[@"name"]);
        _status = PPDeliveryString(source[@"status"]);
        _boundary = [PPDeliveryDictionary(source[@"boundary"]) copy];
        _hubIDs = PPDeliveryStringArray(source[@"hubIds"]);
        _capabilities = [PPDeliveryDictionary(source[@"capabilities"]) copy];
    }
    return self;
}

@end


@implementation PPDeliveryDriverShiftRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _shiftID = PPDeliveryString(source[@"id"]);
        _driverUID = PPDeliveryString(source[@"driverUid"]);
        _status = PPDeliveryString(source[@"status"]);
        _plannedStartAt = PPDeliveryDate(source[@"plannedStartAt"]);
        _plannedEndAt = PPDeliveryDate(source[@"plannedEndAt"]);
        _actualStartAt = PPDeliveryDate(source[@"actualStartAt"]);
        _actualEndAt = PPDeliveryDate(source[@"actualEndAt"]);
        _revision = MAX(0, [source[@"revision"] integerValue]);
    }
    return self;
}

@end


@implementation PPDeliveryRouteStopRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _stopID = PPDeliveryString(source[@"id"]);
        _routeID = PPDeliveryString(source[@"routeId"]);
        _deliveryJobID = PPDeliveryString(source[@"deliveryJobId"]);
        _sequence = MAX(0, [source[@"sequence"] integerValue]);
        _type = PPDeliveryString(source[@"type"]);
        _location = [PPDeliveryDictionary(source[@"location"]) copy];
        _timeWindow = [PPDeliveryDictionary(source[@"timeWindow"]) copy];
        _serviceDuration = [source[@"serviceDuration"] isKindOfClass:NSNumber.class]
            ? source[@"serviceDuration"]
            : nil;
        _status = PPDeliveryString(source[@"status"]);
        _plannedArrival = PPDeliveryDate(source[@"plannedArrival"]);
        _estimatedArrival = PPDeliveryDate(source[@"estimatedArrival"]);
        _actualArrival = PPDeliveryDate(source[@"actualArrival"]);
        _actualDeparture = PPDeliveryDate(source[@"actualDeparture"]);
    }
    return self;
}

@end


@implementation PPDeliveryRouteRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _routeID = PPDeliveryString(source[@"id"]);
        _carrierID = PPDeliveryString(source[@"carrierId"]);
        _driverUID = PPDeliveryString(source[@"driverUid"]);
        _vehicleID = PPDeliveryString(source[@"vehicleId"]);
        _hubID = PPDeliveryString(source[@"hubId"]);
        _status = PPDeliveryString(source[@"status"]);
        _plannedStartAt = PPDeliveryDate(source[@"plannedStartAt"]);
        _plannedEndAt = PPDeliveryDate(source[@"plannedEndAt"]);
        _actualStartAt = PPDeliveryDate(source[@"actualStartAt"]);
        _actualEndAt = PPDeliveryDate(source[@"actualEndAt"]);
        _stopCount = MAX(0, [source[@"stopCount"] integerValue]);
        _completedStopCount = MAX(0, [source[@"completedStopCount"] integerValue]);
        _distanceMeters = [source[@"distanceMeters"] isKindOfClass:NSNumber.class] ? source[@"distanceMeters"] : nil;
        _durationSeconds = [source[@"durationSeconds"] isKindOfClass:NSNumber.class] ? source[@"durationSeconds"] : nil;
        _capacity = [PPDeliveryDictionary(source[@"capacity"]) copy];
        _revision = MAX(0, [source[@"revision"] integerValue]);

        NSMutableArray<PPDeliveryRouteStopRecord *> *stops = [NSMutableArray array];
        for (id rawStop in PPDeliveryArray(source[@"stops"])) {
            if (![rawStop isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryRouteStopRecord *stop = [[PPDeliveryRouteStopRecord alloc] initWithDictionary:rawStop];
            if (stop.stopID.length > 0) [stops addObject:stop];
        }
        _stops = stops.copy;
    }
    return self;
}

@end


@implementation PPDeliveryFleetFoundation

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _configurationState = PPDeliveryString(source[@"configurationState"]);
        if (_configurationState.length == 0) _configurationState = @"NOT_CONFIGURED";
        _source = PPDeliveryString(source[@"source"]);

        NSMutableArray<PPDeliveryVehicleRecord *> *vehicles = [NSMutableArray array];
        for (id rawVehicle in PPDeliveryArray(source[@"vehicles"])) {
            if (![rawVehicle isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryVehicleRecord *vehicle = [[PPDeliveryVehicleRecord alloc] initWithDictionary:rawVehicle];
            if (vehicle.vehicleID.length > 0) [vehicles addObject:vehicle];
        }
        _vehicles = vehicles.copy;

        NSMutableArray<PPDeliveryHubRecord *> *hubs = [NSMutableArray array];
        for (id rawHub in PPDeliveryArray(source[@"hubs"])) {
            if (![rawHub isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryHubRecord *hub = [[PPDeliveryHubRecord alloc] initWithDictionary:rawHub];
            if (hub.hubID.length > 0) [hubs addObject:hub];
        }
        _hubs = hubs.copy;

        NSMutableArray<PPDeliveryServiceZoneRecord *> *zones = [NSMutableArray array];
        for (id rawZone in PPDeliveryArray(source[@"serviceZones"])) {
            if (![rawZone isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryServiceZoneRecord *zone = [[PPDeliveryServiceZoneRecord alloc] initWithDictionary:rawZone];
            if (zone.zoneID.length > 0) [zones addObject:zone];
        }
        _serviceZones = zones.copy;

        NSMutableArray<PPDeliveryDriverShiftRecord *> *shifts = [NSMutableArray array];
        for (id rawShift in PPDeliveryArray(source[@"driverShifts"])) {
            if (![rawShift isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryDriverShiftRecord *shift = [[PPDeliveryDriverShiftRecord alloc] initWithDictionary:rawShift];
            if (shift.shiftID.length > 0) [shifts addObject:shift];
        }
        _driverShifts = shifts.copy;

        NSMutableArray<PPDeliveryRouteRecord *> *routes = [NSMutableArray array];
        for (id rawRoute in PPDeliveryArray(source[@"routes"])) {
            if (![rawRoute isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryRouteRecord *route = [[PPDeliveryRouteRecord alloc] initWithDictionary:rawRoute];
            if (route.routeID.length > 0) [routes addObject:route];
        }
        _routes = routes.copy;
    }
    return self;
}

@end


@implementation PPDeliveryExceptionRecord

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _exceptionID = PPDeliveryString(source[@"id"]);
        _deliveryJobID = PPDeliveryString(source[@"deliveryJobId"]);
        _type = PPDeliveryString(source[@"type"]);
        _severity = PPDeliveryString(source[@"severity"]);
        _status = PPDeliveryString(source[@"status"]);
        _reasonCode = PPDeliveryString(source[@"reasonCode"]);
        _evidence = [PPDeliveryDictionary(source[@"evidence"]) copy];
        _createdAt = PPDeliveryDate(source[@"createdAt"]);
    }
    return self;
}

@end


@implementation PPDeliveryCommandCenterSnapshot

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _carrier = [PPDeliveryDictionary(source[@"carrier"]) copy];

        NSMutableArray<PPDeliveryRequestRecord *> *records = [NSMutableArray array];
        for (id rawJob in PPDeliveryArray(source[@"jobs"])) {
            if (![rawJob isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryRequestRecord *record = [[PPDeliveryRequestRecord alloc] initWithDictionary:rawJob
                                                                                       documentID:PPDeliveryString(rawJob[@"id"])];
            if (record.requestID.length > 0) [records addObject:record];
        }
        _records = records.copy;

        NSMutableArray<PPDeliveryDriverRecord *> *drivers = [NSMutableArray array];
        for (id rawDriver in PPDeliveryArray(source[@"drivers"])) {
            if (![rawDriver isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryDriverRecord *driver = [[PPDeliveryDriverRecord alloc] initWithDictionary:rawDriver];
            if (driver.uid.length > 0) [drivers addObject:driver];
        }
        _drivers = drivers.copy;

        NSMutableArray<PPDeliveryExceptionRecord *> *exceptions = [NSMutableArray array];
        for (id rawException in PPDeliveryArray(source[@"exceptions"])) {
            if (![rawException isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryExceptionRecord *exception = [[PPDeliveryExceptionRecord alloc] initWithDictionary:rawException];
            if (exception.exceptionID.length > 0) [exceptions addObject:exception];
        }
        _exceptions = exceptions.copy;
        _projection = [PPDeliveryDictionary(source[@"projection"]) copy];
        _fleet = [[PPDeliveryFleetFoundation alloc] initWithDictionary:PPDeliveryDictionary(source[@"fleet"])];
        _capabilities = [PPDeliveryDictionary(source[@"capabilities"]) copy];
        _permissions = PPDeliveryStringArray(source[@"permissions"]);
        _permissionSource = PPDeliveryString(source[@"permissionSource"]);
        _eligibilityContext = [PPDeliveryDictionary(source[@"eligibilityContext"]) copy];
    }
    return self;
}

@end


@implementation PPDeliveryDossierSnapshot

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        NSDictionary *job = PPDeliveryDictionary(source[@"job"]);
        _record = [[PPDeliveryRequestRecord alloc] initWithDictionary:job
                                                           documentID:PPDeliveryString(job[@"id"])];
        _carrier = [PPDeliveryDictionary(source[@"carrier"]) copy];

        NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
        for (id event in PPDeliveryArray(source[@"events"])) {
            if ([event isKindOfClass:NSDictionary.class]) [events addObject:[event copy]];
        }
        _events = events.copy;

        NSMutableArray<PPDeliveryDriverRecord *> *drivers = [NSMutableArray array];
        for (id rawDriver in PPDeliveryArray(source[@"drivers"])) {
            if (![rawDriver isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryDriverRecord *driver = [[PPDeliveryDriverRecord alloc] initWithDictionary:rawDriver];
            if (driver.uid.length > 0) [drivers addObject:driver];
        }
        _drivers = drivers.copy;
        _availabilityFunnel = [PPDeliveryDictionary(source[@"availabilityFunnel"]) copy];
        _freshness = [PPDeliveryDictionary(source[@"freshness"]) copy];
    }
    return self;
}

@end


@implementation PPDeliveryCommandResult

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super init])) {
        NSDictionary *source = PPDeliveryDictionary(dictionary);
        _commandID = PPDeliveryString(source[@"commandId"]);
        _requestID = PPDeliveryString(source[@"requestId"]);
        _action = PPDeliveryString(source[@"action"]);
        _status = PPDeliveryString(source[@"status"]);
        _revision = MAX(0, [source[@"revision"] integerValue]);
        _outcome = PPDeliveryString(source[@"outcome"]);
    }
    return self;
}

@end


@interface PPDeliveryService ()
- (void)callFunction:(NSString *)name
              params:(NSDictionary *)params
          completion:(void(^)(id _Nullable result, NSError * _Nullable error))completion;
@end

@implementation PPDeliveryService

+ (instancetype)shared {
    static PPDeliveryService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (void)callFunction:(NSString *)name
              params:(NSDictionary *)params
          completion:(void(^)(id _Nullable result, NSError * _Nullable error))completion {
    FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:name];
    [callable callWithObject:params ?: @{} completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (completion) completion(result.data, error);
    }];
}

+ (NSDictionary<NSString *,id> *)domainDetailsForError:(NSError *)error {
    if (!error || ![error.userInfo isKindOfClass:NSDictionary.class]) return @{};
    id details = error.userInfo[FIRFunctionsErrorDetailsKey] ?: error.userInfo[@"details"];
    return [details isKindOfClass:NSDictionary.class] ? (NSDictionary<NSString *, id> *)details : @{};
}

+ (NSString *)domainCodeForError:(NSError *)error {
    NSString *domainCode = PPDeliveryString([self domainDetailsForError:error][@"domainCode"]);
    if (domainCode.length > 0) return domainCode;
    if ([self isPermissionError:error]) return @"DELIVERY_PERMISSION_DENIED";
    return @"DELIVERY_SERVICE_UNAVAILABLE";
}

+ (BOOL)isPermissionError:(NSError *)error {
    if (!error) return NO;
    NSString *domainCode = PPDeliveryString([self domainDetailsForError:error][@"domainCode"]);
    if ([domainCode isEqualToString:@"DELIVERY_PERMISSION_DENIED"]) return YES;
    if (![error.domain isEqualToString:FIRFunctionsErrorDomain] &&
        ![error.domain isEqualToString:@"com.firebase.functions"]) return NO;
    return error.code == FIRFunctionsErrorCodePermissionDenied ||
           error.code == FIRFunctionsErrorCodeUnauthenticated;
}

- (void)fetchCommandCenterWithCompletion:(void(^)(PPDeliveryCommandCenterSnapshot *, NSError *))completion {
    [self callFunction:@"getDeliveryCommandCenter"
                params:@{@"pageSize": @100}
            completion:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        if (![result isKindOfClass:NSDictionary.class]) {
            if (completion) completion(nil, PPDeliveryInvalidResponseError());
            return;
        }
        if (completion) completion([[PPDeliveryCommandCenterSnapshot alloc] initWithDictionary:result], nil);
    }];
}

- (void)fetchDossierForRequestID:(NSString *)requestID
                       completion:(void(^)(PPDeliveryDossierSnapshot *, NSError *))completion {
    NSString *safeRequestID = [requestID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (safeRequestID.length == 0) {
        if (completion) completion(nil, PPDeliveryInvalidResponseError());
        return;
    }
    [self callFunction:@"getDeliveryDossier"
                params:@{@"requestId": safeRequestID}
            completion:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        if (![result isKindOfClass:NSDictionary.class]) {
            if (completion) completion(nil, PPDeliveryInvalidResponseError());
            return;
        }
        if (completion) completion([[PPDeliveryDossierSnapshot alloc] initWithDictionary:result], nil);
    }];
}

- (void)executeAllowedAction:(PPDeliveryAllowedAction *)allowedAction
                   requestID:(NSString *)requestID
                   commandID:(NSString *)commandID
                   driverUID:(NSString *)driverUID
           handoverConfirmed:(BOOL)handoverConfirmed
                      reason:(NSString *)reason
                  completion:(void(^)(PPDeliveryCommandResult *, NSError *))completion {
    NSString *safeRequestID = [requestID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeCommandID = [commandID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (safeRequestID.length == 0 || safeCommandID.length == 0 ||
        allowedAction.action.length == 0 || allowedAction.expectedRevision < 0 ||
        allowedAction.expectedState.length == 0) {
        if (completion) completion(nil, PPDeliveryInvalidResponseError());
        return;
    }

    NSMutableDictionary *payload = [@{
        @"requestId": safeRequestID,
        @"commandId": safeCommandID,
        @"action": allowedAction.action,
        @"expectedRevision": @(allowedAction.expectedRevision),
        @"expectedState": allowedAction.expectedState,
    } mutableCopy];
    NSString *safeDriverUID = [driverUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeReason = [reason stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (safeDriverUID.length > 0) payload[@"driverUid"] = safeDriverUID;
    if (safeReason.length > 0) payload[@"reason"] = safeReason;
    if ([allowedAction.action isEqualToString:@"RECONCILE_COD"]) {
        payload[@"handoverConfirmed"] = @(handoverConfirmed);
    }

    [self callFunction:@"executeDeliveryCommand" params:payload completion:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        if (![result isKindOfClass:NSDictionary.class]) {
            if (completion) completion(nil, PPDeliveryInvalidResponseError());
            return;
        }
        if (completion) completion([[PPDeliveryCommandResult alloc] initWithDictionary:result], nil);
    }];
}

- (void)executeDriverAction:(NSString *)action
                  driverUID:(NSString *)driverUID
           expectedRevision:(NSInteger)expectedRevision
                  commandID:(NSString *)commandID
                 completion:(void(^)(NSError *))completion {
    NSString *safeAction = [[action stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    NSString *safeDriverUID = [driverUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeCommandID = [commandID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSSet<NSString *> *supported = [NSSet setWithArray:@[@"PAUSE", @"RESUME", @"SUSPEND", @"REACTIVATE"]];
    if (![supported containsObject:safeAction] || safeDriverUID.length == 0 ||
        safeCommandID.length == 0 || expectedRevision < 0) {
        if (completion) completion(PPDeliveryInvalidResponseError());
        return;
    }
    [self callFunction:@"updateDeliveryDriverOperationalState"
                params:@{
                    @"action": safeAction,
                    @"driverUid": safeDriverUID,
                    @"expectedRevision": @(expectedRevision),
                    @"commandId": safeCommandID,
                }
            completion:^(__unused id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)fetchCompanyMembersForCompanyID:(NSString *)companyID
                              completion:(void(^)(NSArray<PPDeliveryCompanyMemberRecord *> *, NSError *))completion {
    NSString *safeCompanyID = [companyID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (safeCompanyID.length == 0) {
        if (completion) completion(nil, PPDeliveryInvalidResponseError());
        return;
    }
    [self callFunction:@"listCompanyMembers"
                params:@{@"companyId": safeCompanyID}
            completion:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *source = PPDeliveryDictionary(result);
        NSMutableArray<PPDeliveryCompanyMemberRecord *> *members = [NSMutableArray array];
        for (id rawMember in PPDeliveryArray(source[@"members"])) {
            if (![rawMember isKindOfClass:NSDictionary.class]) continue;
            PPDeliveryCompanyMemberRecord *member = [[PPDeliveryCompanyMemberRecord alloc] initWithDictionary:rawMember];
            if (member.uid.length > 0) [members addObject:member];
        }
        [members sortUsingComparator:^NSComparisonResult(PPDeliveryCompanyMemberRecord *left,
                                                         PPDeliveryCompanyMemberRecord *right) {
            BOOL leftActiveDriver = [left.role isEqualToString:@"driver"] &&
                [left.status isEqualToString:@"active"] && left.canReceiveAssignments && left.available;
            BOOL rightActiveDriver = [right.role isEqualToString:@"driver"] &&
                [right.status isEqualToString:@"active"] && right.canReceiveAssignments && right.available;
            if (leftActiveDriver != rightActiveDriver) return leftActiveDriver ? NSOrderedAscending : NSOrderedDescending;
            return [left.displayName localizedCaseInsensitiveCompare:right.displayName];
        }];
        if (completion) completion(members.copy, nil);
    }];
}

- (void)inviteDriverIdentifier:(NSString *)identifier
                     companyID:(NSString *)companyID
                    completion:(void(^)(NSError *))completion {
    NSString *safeIdentifier = [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeCompanyID = [companyID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (safeIdentifier.length == 0 || safeCompanyID.length == 0) {
        if (completion) completion(PPDeliveryInvalidResponseError());
        return;
    }
    [self callFunction:@"inviteDeliveryCompanyMember"
                params:@{
                    @"companyId": safeCompanyID,
                    @"targetIdentifier": safeIdentifier,
                    @"targetUid": safeIdentifier,
                    @"role": @"driver",
                }
            completion:^(__unused id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)disableDriverUID:(NSString *)driverUID
               companyID:(NSString *)companyID
              completion:(void(^)(NSError *))completion {
    NSString *safeDriverUID = [driverUID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safeCompanyID = [companyID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (safeDriverUID.length == 0 || safeCompanyID.length == 0) {
        if (completion) completion(PPDeliveryInvalidResponseError());
        return;
    }
    [self callFunction:@"disableDeliveryCompanyMember"
                params:@{@"companyId": safeCompanyID, @"targetUid": safeDriverUID}
            completion:^(__unused id result, NSError *error) {
        if (completion) completion(error);
    }];
}

#pragma mark - Legacy callable compatibility

- (NSArray<PPDeliveryRequestRecord *> *)pp_recordsFromResult:(id)result {
    NSDictionary *source = PPDeliveryDictionary(result);
    NSArray *raw = PPDeliveryArray(source[@"requests"] ?: source[@"jobs"]);
    NSMutableArray<PPDeliveryRequestRecord *> *records = [NSMutableArray array];
    for (id rawRecord in raw) {
        if (![rawRecord isKindOfClass:NSDictionary.class]) continue;
        PPDeliveryRequestRecord *record = [[PPDeliveryRequestRecord alloc] initWithDictionary:rawRecord
                                                                                   documentID:PPDeliveryString(rawRecord[@"id"])];
        if (record.requestID.length > 0) [records addObject:record];
    }
    return records.copy;
}

- (void)fetchDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> *, NSError *))completion {
    [self callFunction:@"listCompanyDeliveryRequests"
                params:@{@"companyId": kPPLegacyCompanyID, @"pageSize": @50}
            completion:^(id result, NSError *error) {
        if (completion) completion(error ? @[] : [self pp_recordsFromResult:result], error);
    }];
}

- (void)fetchAllDeliveryRequestsWithCompletion:(void(^)(NSArray<PPDeliveryRequestRecord *> *, NSError *))completion {
    [self pp_fetchDeliveryRequestsAfterToken:nil
                                     records:[NSMutableArray array]
                                  seenTokens:[NSMutableSet set]
                                  completion:completion];
}

- (void)pp_fetchDeliveryRequestsAfterToken:(NSString * _Nullable)token
                                   records:(NSMutableArray<PPDeliveryRequestRecord *> *)records
                                seenTokens:(NSMutableSet<NSString *> *)seenTokens
                                completion:(void(^)(NSArray<PPDeliveryRequestRecord *> *, NSError *))completion {
    NSMutableDictionary *params = [@{@"companyId": kPPLegacyCompanyID, @"pageSize": @50} mutableCopy];
    if (token.length > 0) params[@"nextPageToken"] = token;

    [self callFunction:@"listCompanyDeliveryRequests" params:params completion:^(id result, NSError *error) {
        if (error) {
            if (completion) completion(records.copy, error);
            return;
        }
        NSMutableSet<NSString *> *knownIDs = [NSMutableSet set];
        for (PPDeliveryRequestRecord *record in records) {
            if (record.requestID.length > 0) [knownIDs addObject:record.requestID];
        }
        for (PPDeliveryRequestRecord *record in [self pp_recordsFromResult:result]) {
            if (record.requestID.length > 0 && ![knownIDs containsObject:record.requestID]) {
                [records addObject:record];
                [knownIDs addObject:record.requestID];
            }
        }

        NSString *nextToken = PPDeliveryString(PPDeliveryDictionary(result)[@"nextPageToken"]);
        if (nextToken.length == 0) {
            if (completion) completion(records.copy, nil);
            return;
        }
        if ([seenTokens containsObject:nextToken]) {
            NSError *paginationError = [NSError errorWithDomain:PPDeliveryServiceErrorDomain
                                                            code:2
                                                        userInfo:@{NSLocalizedDescriptionKey: kLang(@"Delivery_Pagination_Error")}];
            if (completion) completion(records.copy, paginationError);
            return;
        }
        [seenTokens addObject:nextToken];
        [self pp_fetchDeliveryRequestsAfterToken:nextToken records:records seenTokens:seenTokens completion:completion];
    }];
}

- (void)acceptRequest:(NSString *)requestID completion:(void(^)(NSError *))completion {
    [self callFunction:@"acceptCompanyDeliveryRequest" params:@{@"requestId": requestID} completion:^(__unused id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)assignDriver:(NSString *)requestID driverUID:(NSString *)driverUID completion:(void(^)(NSError *))completion {
    [self callFunction:@"assignCompanyDeliveryDriver" params:@{@"requestId": requestID, @"driverUid": driverUID} completion:^(__unused id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)completeRequest:(NSString *)requestID completion:(void(^)(NSError *))completion {
    [self callFunction:@"completeCompanyDeliveryRequest" params:@{@"requestId": requestID} completion:^(__unused id result, NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)cancelRequest:(NSString *)requestID completion:(void(^)(NSError *))completion {
    [self callFunction:@"cancelCompanyDeliveryRequest"
                params:@{@"requestId": requestID, @"reason": @"Cancelled by admin"}
            completion:^(__unused id result, NSError *error) {
        if (completion) completion(error);
    }];
}

@end
