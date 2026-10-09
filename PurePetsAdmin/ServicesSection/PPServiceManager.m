#import "PPServiceManager.h"
#import "PPServiceModel.h"
#import "PPStaffAuth.h"
#import "PPFirebaseCompat.h"
#import "ArabicNormalizer.h"
#import <math.h>
#import <CommonCrypto/CommonDigest.h>
@import FirebaseFirestore;
@import FirebaseAuth;
@import FirebaseFunctions;
@import FirebaseStorage;

static NSString * const kPPServicesCollection = @"serviceOffers";
NSString * const PPServiceManagerErrorDomain = @"pp.service.manager";
NSInteger const PPServiceCommandAwaitingConfirmationCode = 202;
NSString * const PPServiceCommandIDKey = @"pp.service.commandID";
NSString * const PPServiceCommandRevisionKey = @"pp.service.commandRevision";
NSString * const PPServiceCommandAcceptedKey = @"pp.service.commandAccepted";

@interface PPServiceManager ()
@property (nonatomic, strong) FIRFirestore *db;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *uploadedMedia;
- (void)execute:(NSString *)operation serviceID:(NSString *)serviceID payload:(NSDictionary *)payload
       expected:(PPServiceModel *)expected auditNote:(nullable NSString *)auditNote
    observation:(void (^ _Nullable)(PPServiceModel *model))observation completion:(PPServiceVoidBlock)completion;
@end

@implementation PPServiceManager

+ (instancetype)sharedManager {
    static PPServiceManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [PPServiceManager new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) { _db = FIRFirestore.firestore; _uploadedMedia = [NSMutableDictionary new]; }
    return self;
}

#pragma mark - Canonical staff authorization

- (BOOL)currentAdminCanManageServices {
    PPStaffDoc *staff = PPStaffAuth.shared.cachedCurrentStaff;
    if (!staff.isActive || ![staff.uid isEqualToString:FIRAuth.auth.currentUser.uid]) return NO;
    if ([staff.authorizationMode isEqualToString:@"enforced"]) {
        return [staff.authorizationGlobalPermissions containsObject:kStaffPermServicesManage];
    }
    if ([staff.authorizationMode isEqualToString:@"retired"] ||
        (staff.authorizationMode && ![@[@"legacy", @"shadow", @"prepared"] containsObject:staff.authorizationMode])) return NO;
    return staff.isAdmin || (staff.hasGlobalScope && [staff.explicitPermissions containsObject:kStaffPermServicesManage]);
}

- (BOOL)currentAdminCanReadServices {
    PPStaffDoc *staff = PPStaffAuth.shared.cachedCurrentStaff;
    return staff.isActive && [staff.uid isEqualToString:FIRAuth.auth.currentUser.uid] &&
        (staff.isAdmin || [staff hasPermission:kStaffPermServicesView] || [staff hasPermission:kStaffPermServicesManage]);
}

#pragma mark - Reads and bounded list projection

- (FIRCollectionReference *)collection { return [self.db collectionWithPath:kPPServicesCollection]; }

- (NSArray<PPServiceModel *> *)models:(NSArray<FIRQueryDocumentSnapshot *> *)documents {
    NSMutableArray *items = [NSMutableArray new];
    for (FIRQueryDocumentSnapshot *document in documents) {
        [items addObject:[PPServiceModel fromDictionary:document.data withID:document.documentID]];
    }
    return items.copy;
}

- (id<FIRListenerRegistration>)observeQuery:(FIRQuery *)query reportsCacheState:(BOOL)reportsCacheState onChange:(PPServiceArrayBlock)onChange {
    if (![self currentAdminCanReadServices]) {
        [self completeArray:nil error:[self error:403 key:@"Service_Error_NoPermission"] completion:onChange];
        return nil;
    }
    return [query addSnapshotListenerWithIncludeMetadataChanges:reportsCacheState listener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (![self currentAdminCanReadServices]) {
            [self completeArray:nil error:[self error:403 key:@"Service_Error_NoPermission"] completion:onChange];
            return;
        }
        NSError *stateError = [self localizedReadError:error];
        if (reportsCacheState && !error && (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites)) {
            stateError = [self error:299 key:@"Service_Workspace_CachedData"];
        }
        [self completeArray:(snapshot ? [self models:snapshot.documents] : nil) error:stateError completion:onChange];
    }];
}

- (id<FIRListenerRegistration>)observeAllServices:(PPServiceArrayBlock)onChange {
    return [self observeQuery:self.collection reportsCacheState:NO onChange:onChange];
}

- (id<FIRListenerRegistration>)observeServicePageWithLimit:(NSInteger)limit onChange:(PPServiceArrayBlock)onChange {
    FIRQuery *query = [[self.collection queryOrderedByFieldPath:FIRFieldPath.documentID] queryLimitedTo:MAX(1, MIN(limit, 200))];
    return [self observeQuery:query reportsCacheState:YES onChange:onChange];
}

- (void)fetchServicePageAfterServiceID:(nullable NSString *)serviceID limit:(NSInteger)limit completion:(PPServiceArrayBlock)completion {
    if (![self currentAdminCanReadServices]) {
        [self completeArray:nil error:[self error:403 key:@"Service_Error_NoPermission"] completion:completion]; return;
    }
    FIRQuery *query = [[self.collection queryOrderedByFieldPath:FIRFieldPath.documentID] queryLimitedTo:MAX(1, MIN(limit, 200))];
    if (serviceID.length) query = [query queryStartingAfterValues:@[serviceID]];
    [query getDocumentsWithSource:FIRFirestoreSourceServer completion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        [self completeArray:(error ? nil : [self models:snapshot.documents]) error:[self localizedReadError:error] completion:completion];
    }];
}

- (void)fetchAllServicesWithCompletion:(PPServiceArrayBlock)completion {
    if (![self currentAdminCanReadServices]) {
        [self completeArray:nil error:[self error:403 key:@"Service_Error_NoPermission"] completion:completion]; return;
    }
    [self.collection getDocumentsWithSource:FIRFirestoreSourceServer completion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        [self completeArray:(error ? nil : [self models:snapshot.documents]) error:[self localizedReadError:error] completion:completion];
    }];
}

- (void)fetchServiceByID:(NSString *)serviceID completion:(PPServiceModelBlock)completion {
    if (![self currentAdminCanReadServices]) {
        [self completeModel:nil error:[self error:403 key:@"Service_Error_NoPermission"] completion:completion]; return;
    }
    if (![self validID:serviceID]) {
        [self completeModel:nil error:[self error:400 key:@"Service_Error_MissingID"] completion:completion]; return;
    }
    [[self.collection documentWithPath:serviceID] getDocumentWithSource:FIRFirestoreSourceServer completion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
        if (error || !snapshot.exists) {
            [self completeModel:nil error:[self localizedReadError:error] ?: [self error:404 key:@"Service_Error_NotFound"] completion:completion]; return;
        }
        [self completeModel:[PPServiceModel fromDictionary:snapshot.data withID:serviceID] error:nil completion:completion];
    }];
}

#pragma mark - Content writes

- (void)addService:(PPServiceModel *)service image:(UIImage *)image auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    if (![self requireManage:completion]) return;
    PPServiceModel *candidate = [service copy];
    candidate.serviceID = service.serviceID.length ? service.serviceID : NSUUID.UUID.UUIDString;
    // Keep the ID stable for a repeat of the same editor submission.
    service.serviceID = candidate.serviceID;
    if (!candidate.serviceOwnerID.length) candidate.serviceOwnerID = FIRAuth.auth.currentUser.uid ?: @"";
    if (![self validateContent:candidate completion:completion]) return;
    [self resolveImage:image candidate:candidate completion:^(NSError *error) {
        if (error) { [self completeVoid:error completion:completion]; return; }
        [self execute:@"create" serviceID:candidate.serviceID payload:[self contentPayload:candidate]
              expected:nil auditNote:auditNote completion:completion];
    }];
}

- (void)updateService:(PPServiceModel *)service image:(UIImage *)image auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    if (![self requireManage:completion] || ![self validateContent:service completion:completion]) return;
    PPServiceModel *candidate = [service copy];
    [self fetchServiceByID:service.serviceID completion:^(PPServiceModel *current, NSError *error) {
        if (error) { [self completeVoid:error completion:completion]; return; }
        // The editor carries its original revision/timestamp. A fresh read
        // provides compatibility only for legacy callers that omit a baseline.
        PPServiceModel *expected = service.updatedAt ? service : current;
        [self resolveImage:image candidate:candidate completion:^(NSError *uploadError) {
            if (uploadError) { [self completeVoid:uploadError completion:completion]; return; }
            [self execute:@"edit" serviceID:candidate.serviceID payload:[self contentPayload:candidate]
                  expected:expected auditNote:auditNote completion:completion];
        }];
    }];
}

#pragma mark - Administrative decision writes

- (void)updateAdministrativeStateForService:(PPServiceModel *)service auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    if (![self requireManage:completion]) return;
    [self fetchServiceByID:service.serviceID completion:^(PPServiceModel *expected, NSError *error) {
        if (error) { [self completeVoid:error completion:completion]; return; }
        [self updateAdministrativeStateForService:service expectedService:expected auditNote:auditNote completion:completion];
    }];
}

- (void)updateAdministrativeStateForService:(PPServiceModel *)service expectedService:(PPServiceModel *)expected auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    [self saveAdministrativeStateForService:service expectedService:expected auditNote:auditNote
        completion:^(PPServiceModel *observed, NSError *error) { [self completeVoid:error completion:completion]; }];
}

- (void)saveAdministrativeStateForService:(PPServiceModel *)service expectedService:(PPServiceModel *)expected auditNote:(NSString *)auditNote completion:(PPServiceModelBlock)completion {
    __block PPServiceModel *observed = nil;
    PPServiceVoidBlock finish = ^(NSError *error) { [self completeModel:observed error:error completion:completion]; };
    if (![self requireManage:finish]) return;
    if (![service.serviceID isEqualToString:expected.serviceID]) {
        [self completeVoid:[self error:400 key:@"Service_Error_MissingID"] completion:finish]; return;
    }
    if (service.subscriptionStartDate && service.subscriptionEndDate &&
        [service.subscriptionStartDate compare:service.subscriptionEndDate] == NSOrderedDescending) {
        [self completeVoid:[self error:400 key:@"Service_Error_SubscriptionDateOrder"] completion:finish]; return;
    }
    [self execute:@"moderate" serviceID:service.serviceID payload:[self.class administrativePayload:service]
          expected:expected auditNote:auditNote observation:^(PPServiceModel *model) { observed = model; } completion:finish];
}

- (void)setDisabled:(BOOL)disabled forServiceID:(NSString *)serviceID auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    [self changeState:@{@"isDisabled": @(disabled)} serviceID:serviceID auditNote:auditNote completion:completion];
}
- (void)setBlocked:(BOOL)blocked forServiceID:(NSString *)serviceID auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    [self changeState:@{@"isBlocked": @(blocked)} serviceID:serviceID auditNote:auditNote completion:completion];
}
- (void)archiveServiceID:(NSString *)serviceID auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    [self changeState:@{@"isDeleted": @YES} serviceID:serviceID auditNote:auditNote completion:completion];
}
- (void)restoreServiceID:(NSString *)serviceID auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    [self changeState:@{@"isDeleted": @NO} serviceID:serviceID auditNote:auditNote completion:completion];
}
- (void)changeState:(NSDictionary *)payload serviceID:(NSString *)serviceID auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    if (![self requireManage:completion]) return;
    [self fetchServiceByID:serviceID completion:^(PPServiceModel *expected, NSError *error) {
        if (error) { [self completeVoid:error completion:completion]; return; }
        [self execute:@"state" serviceID:serviceID payload:payload expected:expected auditNote:auditNote completion:completion];
    }];
}
- (void)deleteServicePermanently:(NSString *)serviceID auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    if (![self requireManage:completion]) return;
    [self fetchServiceByID:serviceID completion:^(PPServiceModel *expected, NSError *error) {
        if (error) { [self completeVoid:error completion:completion]; return; }
        [self execute:@"delete" serviceID:serviceID payload:@{} expected:expected auditNote:auditNote completion:completion];
    }];
}

#pragma mark - Callable command and server observation

- (void)execute:(NSString *)operation serviceID:(NSString *)serviceID payload:(NSDictionary *)payload expected:(PPServiceModel *)expected auditNote:(NSString *)auditNote completion:(PPServiceVoidBlock)completion {
    [self execute:operation serviceID:serviceID payload:payload expected:expected auditNote:auditNote
        observation:nil completion:completion];
}

- (void)execute:(NSString *)operation serviceID:(NSString *)serviceID payload:(NSDictionary *)payload expected:(PPServiceModel *)expected auditNote:(NSString *)auditNote observation:(void (^)(PPServiceModel *))observation completion:(PPServiceVoidBlock)completion {
    if (![self requireManage:completion]) return;
    NSString *actorUID = [FIRAuth.auth.currentUser.uid copy];
    if (![self validID:serviceID]) { [self completeVoid:[self error:400 key:@"Service_Error_MissingID"] completion:completion]; return; }
    NSNumber *revision = [expected.extraFields[@"adminRevision"] isKindOfClass:NSNumber.class] ? expected.extraFields[@"adminRevision"] : @0;
    if (!isfinite(revision.doubleValue) || revision.doubleValue < 0 ||
        floor(revision.doubleValue) != revision.doubleValue || revision.doubleValue >= 9007199254740991.0) {
        [self completeVoid:[self error:409 key:@"Service_Review_Conflict"] completion:completion]; return;
    }
    NSNumber *nextRevision = @(revision.longLongValue + 1);
    NSMutableDictionary *envelope = [@{
        @"operation": operation, @"serviceID": serviceID, @"payload": payload,
        @"expectedRevision": revision, @"expectedUpdatedAtMs": [self.class milliseconds:expected.updatedAt],
        @"auditNote": auditNote ?: @""
    } mutableCopy];
    if ([operation isEqualToString:@"moderate"]) {
        envelope[@"expectedAdminState"] = [self.class administrativePayload:expected];
        NSMutableDictionary *reviewed = [[self contentPayload:expected] mutableCopy];
        [reviewed removeObjectForKey:@"extras"];
        [reviewed removeObjectForKey:@"searchTitle"];
        reviewed[@"timestamp"] = [self.class milliseconds:expected.timestamp];
        envelope[@"expectedContentState"] = reviewed;
    }
    // Identical draft, baseline and actor produce the same command on retry.
    // The server binds this identity to the exact payload and persists its receipt.
    NSDictionary *wire = [self.class wireValue:envelope];
    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:wire options:NSJSONWritingSortedKeys error:&jsonError];
    if (!data) { [self completeVoid:[self error:400 key:@"Service_Error_FlagsJSONInvalid"] completion:completion]; return; }
    NSMutableData *identity = [NSMutableData dataWithData:[(actorUID ?: @"") dataUsingEncoding:NSUTF8StringEncoding]];
    [identity appendData:data];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(identity.bytes, (CC_LONG)identity.length, digest);
    NSMutableString *commandID = [NSMutableString new];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [commandID appendFormat:@"%02x", digest[index]];
    NSMutableDictionary *request = [wire mutableCopy];
    request[@"commandID"] = commandID;
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"adminServiceCommand"];
    [callable callWithObject:request completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        if (![actorUID isEqualToString:FIRAuth.auth.currentUser.uid] || ![self currentAdminCanManageServices]) {
            [self completeVoid:[self error:403 key:@"Service_Error_NoPermission"] completion:completion]; return;
        }
        if (error) { [self completeVoid:[self localizedCommandError:error] completion:completion]; return; }
        NSDictionary *receipt = [result.data isKindOfClass:NSDictionary.class] ? result.data : @{};
        BOOL deleted = [operation isEqualToString:@"delete"];
        BOOL accepted = [receipt[@"ok"] isKindOfClass:NSNumber.class] && [receipt[@"ok"] boolValue] &&
            [receipt[@"serviceID"] isEqual:serviceID] && [receipt[@"commandID"] isEqual:commandID] &&
            [receipt[@"revision"] isKindOfClass:NSNumber.class] && [receipt[@"revision"] isEqual:nextRevision] &&
            [receipt[@"deleted"] isKindOfClass:NSNumber.class] && [receipt[@"deleted"] boolValue] == deleted;
        // A successful transport with an incomplete receipt is an unknown
        // outcome. Observe the deterministic command before enabling a new
        // decision; do not claim acceptance or blindly resubmit it.
        [[self.collection documentWithPath:serviceID] getDocumentWithSource:FIRFirestoreSourceServer completion:^(FIRDocumentSnapshot *snapshot, NSError *readError) {
            if (![actorUID isEqualToString:FIRAuth.auth.currentUser.uid] || ![self currentAdminCanManageServices]) {
                [self completeVoid:[self error:403 key:@"Service_Error_NoPermission"] completion:completion]; return;
            }
            BOOL confirmed = snapshot && !readError && (deleted ? (accepted && !snapshot.exists) :
                (snapshot.exists && [snapshot.data[@"adminLastCommandID"] isEqual:commandID] &&
                 [snapshot.data[@"adminRevision"] isEqual:nextRevision]));
            NSError *observationError = nil;
            if (!confirmed) {
                NSMutableDictionary *info = [@{NSLocalizedDescriptionKey: kLang(accepted ? @"Service_Review_AcceptedPending" : @"Service_Workspace_AwaitingConfirmation"),
                    PPServiceCommandIDKey: commandID, PPServiceCommandRevisionKey: nextRevision,
                    PPServiceCommandAcceptedKey: @(accepted)} mutableCopy];
                if (readError) info[NSUnderlyingErrorKey] = readError;
                observationError = [NSError errorWithDomain:PPServiceManagerErrorDomain
                    code:PPServiceCommandAwaitingConfirmationCode userInfo:info];
            } else if (observation && snapshot.exists) {
                observation([PPServiceModel fromDictionary:snapshot.data withID:serviceID]);
            }
            [self completeVoid:observationError completion:completion];
        }];
    }];
}

+ (NSDictionary *)administrativePayload:(PPServiceModel *)service {
    return @{
        @"isDisabled": @(service.isDisabled), @"isBlocked": @(service.isBlocked),
        @"verificationStatus": service.verificationStatus ?: @"", @"subscriptionType": service.subscriptionType ?: @"",
        @"subscriptionPlan": service.subscriptionPlan ?: @"", @"subscriptionStatus": service.subscriptionStatus ?: @"",
        @"subscriptionActive": @(service.subscriptionActive),
        @"subscriptionStartDate": [self milliseconds:service.subscriptionStartDate],
        @"subscriptionEndDate": [self milliseconds:service.subscriptionEndDate], @"serviceFlags": service.serviceFlags ?: @{}
    };
}

+ (BOOL)administrativeState:(PPServiceModel *)observed matchesService:(PPServiceModel *)candidate {
    return [[self wireValue:[self administrativePayload:observed]] isEqual:[self wireValue:[self administrativePayload:candidate]]];
}

- (NSDictionary *)contentPayload:(PPServiceModel *)service {
    NSMutableDictionary *payload = [NSMutableDictionary new];
    NSDictionary *source = service.toDictionary;
    for (NSString *key in @[@"title", @"searchTitle", @"description", @"price", @"category", @"categoryID", @"petMainKindID", @"availableDate", @"timestamp", @"imageURL", @"serviceOwnerID", @"type", @"blurHash", @"petMainCategoryIDs", @"isAllCategories", @"targetCategories", @"categories", @"categoryIDs"]) {
        payload[key] = source[key] ?: NSNull.null;
    }
    payload[@"searchTitle"] = [ArabicNormalizer normalize:service.title ?: @""] ?: @"";
    NSMutableDictionary *extras = [service.extraFields mutableCopy] ?: [NSMutableDictionary new];
    [extras removeObjectsForKeys:@[@"adminRevision", @"adminLastCommandID", @"createdBy", @"updatedBy",
                                  @"rating", @"averageRating", @"ratingValue", @"reviewCount", @"reviews", @"reviewsUpdatedAt",
                                  @"reviewsCount", @"ratingCount", @"ratingsCount", @"reviewList", @"ratings"]];
    payload[@"extras"] = extras;
    return [self.class wireValue:payload];
}

+ (id)milliseconds:(NSDate *)date { return date ? @(llround(date.timeIntervalSince1970 * 1000.0)) : NSNull.null; }

+ (id)wireValue:(id)value {
    if ([value isKindOfClass:NSDate.class]) return [self milliseconds:value];
    if ([value isKindOfClass:FIRTimestamp.class]) return [self milliseconds:[value dateValue]];
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [NSMutableDictionary new];
        for (NSString *key in value) result[key] = [self wireValue:value[key]];
        return result;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [NSMutableArray new];
        for (id item in value) [result addObject:[self wireValue:item]];
        return result;
    }
    return value ?: NSNull.null;
}

#pragma mark - Media and validation

- (void)resolveImage:(UIImage *)image candidate:(PPServiceModel *)candidate completion:(PPServiceVoidBlock)completion {
    if (!image) { completion(nil); return; }
    NSData *data = UIImageJPEGRepresentation(image, 0.85);
    if (!data) { completion([self error:400 key:@"Service_Error_ImageUpload"]); return; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *imageHash = [NSMutableString new];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) [imageHash appendFormat:@"%02x", digest[index]];
    NSString *cacheKey = [NSString stringWithFormat:@"%@/%@/%@", FIRAuth.auth.currentUser.uid ?: @"", candidate.serviceID, imageHash];
    NSString *existingURL = self.uploadedMedia[cacheKey];
    if (existingURL) { candidate.imageURL = existingURL; completion(nil); return; }
    // A stale edit must not replace the image still referenced by the current
    // service. A repeat of identical media reuses this staged upload URL.
    NSString *path = [NSString stringWithFormat:@"services/%@/%@.jpg", candidate.serviceID, NSUUID.UUID.UUIDString];
    FIRStorageReference *reference = [FIRStorage.storage.reference child:path];
    FIRStorageMetadata *metadata = [FIRStorageMetadata new];
    metadata.contentType = @"image/jpeg";
    metadata.customMetadata = @{@"uploaded_by": FIRAuth.auth.currentUser.uid ?: @"", @"entity_type": @"service", @"entity_id": candidate.serviceID};
    [reference putData:data metadata:metadata completion:^(FIRStorageMetadata *result, NSError *error) {
        if (error) { completion([self error:400 key:@"Service_Error_ImageUpload"]); return; }
        [reference downloadURLWithCompletion:^(NSURL *url, NSError *urlError) {
            if (urlError || !url) { completion([self error:400 key:@"Service_Error_ImageUpload"]); return; }
            dispatch_async(dispatch_get_main_queue(), ^{
                candidate.imageURL = url.absoluteString;
                if (self.uploadedMedia.count >= 128) {
                    NSString *oldest = self.uploadedMedia.allKeys.firstObject;
                    if (oldest) [self.uploadedMedia removeObjectForKey:oldest];
                }
                self.uploadedMedia[cacheKey] = url.absoluteString;
                completion(nil);
            });
        }];
    }];
}

- (BOOL)validID:(NSString *)value {
    return value.length > 0 && value.length <= 200 && ![value containsString:@"/"] &&
        ![value isEqualToString:@"."] && ![value isEqualToString:@".."];
}
- (BOOL)requireManage:(PPServiceVoidBlock)completion {
    if ([self currentAdminCanManageServices]) return YES;
    [self completeVoid:[self error:403 key:@"Service_Error_NoPermission"] completion:completion]; return NO;
}
- (BOOL)validateContent:(PPServiceModel *)service completion:(PPServiceVoidBlock)completion {
    NSString *key = nil;
    if (!service.title.length) key = @"Service_Error_TitleRequired";
    else if (!service.serviceDescriptionText.length) key = @"Service_Error_DescriptionRequired";
    else if (!service.serviceOwnerID.length) key = @"Service_Error_OwnerRequired";
    else if (!isfinite(service.price) || service.price < 0) key = @"Service_Error_InvalidPrice";
    else if (!service.category.length && !service.categoryID.length) key = @"Service_Error_CategoryRequired";
    if (!key) return YES;
    [self completeVoid:[self error:400 key:key] completion:completion]; return NO;
}

- (NSError *)localizedReadError:(NSError *)source {
    if (!source) return nil;
    if ([source.domain isEqualToString:FIRFirestoreErrorDomain] &&
        (source.code == FIRFirestoreErrorCodePermissionDenied || source.code == FIRFirestoreErrorCodeUnauthenticated)) {
        return [self error:403 key:@"Service_Error_NoPermission"];
    }
    // Reserve manager codes for manager outcomes. The SDK/network code stays
    // in the underlying error instead of colliding with 404 or pending codes.
    return [NSError errorWithDomain:PPServiceManagerErrorDomain code:503
                          userInfo:@{NSLocalizedDescriptionKey: kLang(@"Service_Workspace_ReadFailure"), NSUnderlyingErrorKey: source}];
}

- (NSError *)localizedCommandError:(NSError *)source {
    if (![source.domain isEqualToString:@"com.firebase.functions"] &&
        ![source.domain isEqualToString:FIRFunctionsErrorDomain]) {
        return source;
    }
    switch (source.code) {
        case FIRFunctionsErrorCodePermissionDenied:
        case FIRFunctionsErrorCodeUnauthenticated: return [self error:403 key:@"Service_Error_NoPermission"];
        case FIRFunctionsErrorCodeAborted:
        case FIRFunctionsErrorCodeAlreadyExists: return [self error:409 key:@"Service_Review_Conflict"];
        case FIRFunctionsErrorCodeNotFound: return [self error:404 key:@"Service_Error_CommandUnavailable"];
        case FIRFunctionsErrorCodeInvalidArgument: return [self error:400 key:@"Service_Error_CommandInvalid"];
        case FIRFunctionsErrorCodeUnavailable:
        case FIRFunctionsErrorCodeDeadlineExceeded: return [self error:503 key:@"Service_Error_CommandRetry"];
        default: return [self error:500 key:@"Service_Error_CommandFailed"];
    }
}
- (NSError *)error:(NSInteger)code key:(NSString *)key {
    return [NSError errorWithDomain:PPServiceManagerErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: kLang(key)}];
}
- (void)completeVoid:(NSError *)error completion:(PPServiceVoidBlock)completion {
    if (!completion) return;
    if (NSThread.isMainThread) completion(error); else dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
}
- (void)completeArray:(NSArray<PPServiceModel *> *)services error:(NSError *)error completion:(PPServiceArrayBlock)completion {
    if (!completion) return;
    if (NSThread.isMainThread) completion(services, error); else dispatch_async(dispatch_get_main_queue(), ^{ completion(services, error); });
}
- (void)completeModel:(PPServiceModel *)service error:(NSError *)error completion:(PPServiceModelBlock)completion {
    if (!completion) return;
    if (NSThread.isMainThread) completion(service, error); else dispatch_async(dispatch_get_main_queue(), ^{ completion(service, error); });
}

@end
