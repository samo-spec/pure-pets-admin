//
//  RPManager.m
//  PurePetsAdmin
//

#import "RPManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "AdminService.h"
#import "PPStaffAuth.h"
@import Firebase;
@import FirebaseAuth;
#pragma mark - Logging

#ifndef DLog
#   if DEBUG
#       define DLog(fmt, ...) NSLog((@"[RP] " fmt), ##__VA_ARGS__)
#   else
#       define DLog(...)
#   endif
#endif

#pragma mark - Constants
NSString * const kUsersCol                  = @"UsersCol";
NSString * const kPermisstionsCol           = @"permissions";
NSString * const kRPSubCol                  = @"RPSubCol";
NSString * const kRPRoleDoc                 = @"role";
NSString * const kRPPermissionsCol          = @"permissions";
static NSString * const kLegacyPermisstionsCol = @"PermisstionsCol";
static NSString * const kLegacyPermissionsCol = @"PermissionsCol";
static NSString * const kRPSecondaryAuthApp = @"com-purepets-admin-usercreator";
static inline NSError * RPError(NSString *msg, NSInteger code) {
    return [NSError errorWithDomain:@"RPManager" code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg ?: @"Error"}];
}

static NSString *PPCanonicalPermissionName(NSString *rawName) {
    NSString *name = [PPSafeString(rawName) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) return @"";
    if ([name isEqualToString:@"ManageUsers"]) return kPermAdoption;
    if ([name isEqualToString:@"ManageNotificatiuons"] || [name isEqualToString:@"ManageNotifications"]) return kPermModeration;
    if ([name isEqualToString:@"ManageBanners"]) return kPermPostAds;
    if ([name isEqualToString:@"Prodection"]) return kPermProduction;
    return name;
}

static NSString *PPLegacyPermissionName(NSString *canonicalName) {
    NSString *name = [PPSafeString(canonicalName) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) return @"";
    if ([name isEqualToString:kPermAdoption]) return @"ManageUsers";
    if ([name isEqualToString:kPermModeration]) return @"ManageNotificatiuons";
    if ([name isEqualToString:kPermPostAds]) return @"ManageBanners";
    if ([name isEqualToString:kPermProduction]) return @"Prodection";
    return name;
}

static NSArray<NSString *> *PPLegacyPermissionNames(NSString *canonicalName) {
    NSString *primary = PPLegacyPermissionName(canonicalName);
    if (primary.length == 0) {
        return @[];
    }
    if ([canonicalName isEqualToString:kPermModeration]) {
        return @[primary, @"ManageNotifications"];
    }
    return @[primary];
}

@interface PPMultiListenerRegistration : NSObject <FIRListenerRegistration>
@property (nonatomic, strong) NSArray<id<FIRListenerRegistration>> *registrations;
- (instancetype)initWithRegistrations:(NSArray<id<FIRListenerRegistration>> *)registrations;
@end

@implementation PPMultiListenerRegistration

- (instancetype)initWithRegistrations:(NSArray<id<FIRListenerRegistration>> *)registrations {
    self = [super init];
    if (self) {
        _registrations = registrations ?: @[];
    }
    return self;
}

- (void)remove {
    for (id<FIRListenerRegistration> registration in self.registrations) {
        [registration remove];
    }
    self.registrations = @[];
}

@end

@interface RPManager ()
@property (nonatomic, strong) FIRFirestore *db;
@property (nonatomic, strong) id<FIRListenerRegistration> reg;
- (FIRCollectionReference *)legacyPermsCol:(NSString *)uid;
- (FIRCollectionReference *)legacyPermsColAlt:(NSString *)uid;
- (void)logAdminAuditAction:(NSString *)action
                  targetUID:(NSString *)targetUID
                     before:(NSDictionary *)before
                      after:(NSDictionary *)after
                     reason:(nullable NSString *)reason
                 completion:(void (^_Nullable)(NSError * _Nullable error))completion;
- (void)pp_setLegacyPermissionPayload:(NSDictionary *)payload
                               forUID:(NSString *)uid
                        canonicalName:(NSString *)canonicalName
                                batch:(FIRWriteBatch *)batch;

@end

@implementation StaffRoleTemplate
@end

@implementation RPManager


// Generic function to call Firebase role management functions
- (void)setUserRole:(NSString *)functionName
         identifier:(NSString *)identifier
             status:(BOOL)status
         completion:(void (^)(BOOL success, NSString *message))completion {
    
    FIRFunctions *functions = [FIRFunctions functions];
    
    // Prepare data
    NSDictionary *data = @{
        @"identifier": identifier,
        @"status": @(status)
    };
    
    // Call function
    [[functions HTTPSCallableWithName:functionName] callWithObject:data
                                                        completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            // Handle Firebase Functions error
            NSString *errorMessage;
            
            if ([error.domain isEqualToString:@"com.firebase.functions"]) {
                // Firebase Functions error
                FIRFunctionsErrorCode code = error.code;
                
                // Get error details correctly
                id details = error.description;
                
                switch (code) {
                    case FIRFunctionsErrorCodeAborted:
                        errorMessage = @"Operation was aborted";
                        break;
                    case FIRFunctionsErrorCodeAlreadyExists:
                        errorMessage = @"Resource already exists";
                        break;
                    case FIRFunctionsErrorCodeCancelled:
                        errorMessage = @"Operation was cancelled";
                        break;
                    case FIRFunctionsErrorCodeDataLoss:
                        errorMessage = @"Data loss occurred";
                        break;
                    case FIRFunctionsErrorCodeDeadlineExceeded:
                        errorMessage = @"Deadline exceeded";
                        break;
                    case FIRFunctionsErrorCodeFailedPrecondition:
                        errorMessage = @"Precondition failed";
                        break;
                    case FIRFunctionsErrorCodeInternal:
                        errorMessage = @"Internal error";
                        break;
                    case FIRFunctionsErrorCodeInvalidArgument:
                        errorMessage = @"Invalid argument";
                        break;
                    case FIRFunctionsErrorCodeNotFound:
                        errorMessage = @"Resource not found";
                        break;
                    case FIRFunctionsErrorCodeOutOfRange:
                        errorMessage = @"Out of range";
                        break;
                    case FIRFunctionsErrorCodePermissionDenied:
                        errorMessage = @"Permission denied";
                        break;
                    case FIRFunctionsErrorCodeResourceExhausted:
                        errorMessage = @"Resource exhausted";
                        break;
                    case FIRFunctionsErrorCodeUnauthenticated:
                        errorMessage = @"Unauthenticated";
                        break;
                    case FIRFunctionsErrorCodeUnavailable:
                        errorMessage = @"Service unavailable";
                        break;
                    case FIRFunctionsErrorCodeUnimplemented:
                        errorMessage = @"Not implemented";
                        break;
                    case FIRFunctionsErrorCodeUnknown:
                    default:
                        errorMessage = @"Unknown error occurred";
                        break;
                }
                
                // Append details if available
                if (details) {
                    errorMessage = [NSString stringWithFormat:@"%@: %@", errorMessage, details];
                }
                
            } else {
                // Other error (network, etc.)
                errorMessage = error.localizedDescription;
            }
            
            NSLog(@"Firebase Error: %@", errorMessage);
            
            if (completion) {
                completion(NO, errorMessage);
            }
            return;
        }
        
        // Function executed successfully
        NSDictionary *resultData = result.data;
        NSLog(@"Result: %@", resultData);
        
        if (completion) {
            NSString *message = resultData[@"message"] ?: @"Operation completed successfully";
            completion(YES, message);
        }
    }];
}

// Set Moderator role
- (void)setModerator:(NSString *)identifier status:(BOOL)status completion:(void (^)(BOOL, NSString *))completion {
    [self setUserRole:@"setModerator" identifier:identifier status:status completion:completion];
}

//================================================ SUPE ADMIN END =================================================//
#pragma mark - Staff Roles (Custom Roles)

- (void)listenStaffRoles:(void(^)(NSArray<StaffRoleTemplate *> * _Nullable roles, NSError * _Nullable error))completion {
    [[self.db collectionWithPath:@"staff_roles"] addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        NSMutableArray *roles = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            StaffRoleTemplate *t = [StaffRoleTemplate new];
            t.id = doc.documentID;
            t.name = doc.data[@"name"] ?: @{};
            t.roleDescription = doc.data[@"description"] ?: @{};
            t.permissions = doc.data[@"permissions"] ?: @[];
            [roles addObject:t];
        }
        if (completion) completion(roles, nil);
    }];
}

- (void)createStaffRole:(NSDictionary *)data completion:(void(^)(NSString * _Nullable roleID, NSError * _Nullable error))completion {
    __block FIRDocumentReference *ref = [[self.db collectionWithPath:@"staff_roles"] addDocumentWithData:data completion:^(NSError * _Nullable error) {
        if (completion) completion(ref.documentID, error);
    }];
}

- (void)updateStaffRole:(NSString *)roleID data:(NSDictionary *)data completion:(void(^)(NSError * _Nullable error))completion {
    [[[self.db collectionWithPath:@"staff_roles"] documentWithPath:roleID] setData:data merge:YES completion:completion];
}

- (void)deleteStaffRole:(NSString *)roleID completion:(void(^)(NSError * _Nullable error))completion {
    [[[self.db collectionWithPath:@"staff_roles"] documentWithPath:roleID] deleteDocumentWithCompletion:completion];
}

- (NSArray<NSString *> *)defaultPermissionsForRole:(UserRole)role {
    return [PPRolePermission defaultPermissionsForRole:role];
}

- (BOOL)role:(UserRole)role hasPermission:(NSString *)permKey
{
    if (!permKey.length) return NO;
    NSArray<NSString *> *defaults = [self defaultPermissionsForRole:role];
    return [defaults containsObject:permKey];
}


+ (instancetype)shared {
    static RPManager *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [RPManager new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _db = [FIRFirestore firestore];
    }
    return self;
}

- (nullable FIRAuth *)p_userCreatorAuth {
    FIRApp *secondary = [FIRApp appNamed:kRPSecondaryAuthApp];
    if (!secondary) {
        FIRApp *defaultApp = [FIRApp defaultApp];
        if (!defaultApp || !defaultApp.options) {
            return nil;
        }
        [FIRApp configureWithName:kRPSecondaryAuthApp options:defaultApp.options];
        secondary = [FIRApp appNamed:kRPSecondaryAuthApp];
    }
    return secondary ? [FIRAuth authWithApp:secondary] : nil;
}

#pragma mark - Paths

- (FIRDocumentReference *)userDoc:(NSString *)uid {
    return [[self.db collectionWithPath:kUsersCol] documentWithPath:uid];
}

- (FIRCollectionReference *)rpPermisstionsCol:(NSString *)uid {
    // UsersCol/{uid}/RP/permissions
    FIRCollectionReference *rpCol = [[self userDoc:uid] collectionWithPath:kPermisstionsCol];
    return rpCol;
}

#pragma mark - Roles (RP/meta)


- (void)setRole:(UserRole)role
         forUID:(NSString *)uid
     completion:(void(^)(NSError * _Nullable error))completion
{
    if (uid.length == 0) { if (completion) completion([NSError errorWithDomain:@"RP" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]); return; }
    BOOL adminRole = (role == UserRoleAdmin || role == UserRoleSuperAdmin);
    BOOL superAdminRole = (role == UserRoleSuperAdmin);

    NSDictionary *payload = @{
        @"role" : @(role),
        @"roleName"  : [PPRolePermission roleName:role],
        @"isAdmin"   : @(adminRole),
        @"admin"     : @(adminRole),
        @"isSuperAdmin": @(superAdminRole),
        @"superadmin": @(superAdminRole),
        @"updatedAt" : [FIRFieldValue fieldValueForServerTimestamp]
    };

    [[self userDoc:uid] setData:payload merge:YES completion:^(NSError * _Nullable error) {
        if (!error) {
            [self logAdminAuditAction:@"set_role"
                            targetUID:uid
                               before:@{}
                                after:@{@"role": @(role)}
                               reason:nil
                           completion:nil];
        }
        if (completion) completion(error);
    }];
}

- (void)fetchRoleForUID:(NSString *)uid
             completion:(void(^)(UserRole role, NSDictionary * _Nullable meta, NSError * _Nullable error))completion
{
    if (uid.length == 0) { if (completion) completion(UserRoleUnknown, nil, [NSError errorWithDomain:@"RP" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]); return; }

    [[self userDoc:uid] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable error) {
        if (error || !snap.exists) { if (completion) completion(UserRoleUnknown, snap.data, error); return; }
        NSNumber *n = snap.data[@"role"];
        UserRole r = n ? (UserRole)n.integerValue : UserRoleUnknown;
        completion(r, snap.data, nil);
    }];
}

#pragma mark - Permissions (RP/permissions subcollection)

- (void)setPermissionNamed:(NSString *)permName
                    forUID:(NSString *)uid
                   allowed:(BOOL)allowed
                completion:(void(^)(NSError * _Nullable error))completion
{
    [self setPermission:permName forUID:uid allowed:allowed completion:completion];
}

- (void)fetchPermissionsForUID:(NSString *)uid
                    completion:(void(^)(NSDictionary<NSString *, NSNumber *> * _Nullable perms,
                                        NSError * _Nullable error))completion
{
    if (uid.length == 0) { if (completion) completion(@{}, [NSError errorWithDomain:@"RP" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]); return; }

    // Read from UsersCol staff profile.
    [[PPStaffAuth shared] fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable doc, NSError * _Nullable error) {
        if (error) { if (completion) completion(@{}, error); return; }
        if (!doc) { if (completion) completion(@{}, nil); return; }

        // Convert permissions array to legacy {key: @YES} dictionary format
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (NSString *perm in doc.permissions) {
            map[perm] = @(YES);
        }
        if (completion) completion(map.copy, nil);
    }];
}

- (id<FIRListenerRegistration>)listenPermissionsForUID:(NSString *)uid
                                              onChange:(void(^)(NSDictionary<NSString *, NSNumber *> *perms,
                                                                NSError * _Nullable error))block
{
    if (uid.length == 0) {
        if (block) block(@{}, [NSError errorWithDomain:@"RP" code:5 userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]);
        return nil;
    }

    // Single listener on UsersCol staff profile.
    return [[PPStaffAuth shared] listenStaffDoc:uid onChange:^(PPStaffDoc * _Nullable doc, NSError * _Nullable error) {
        if (error) { if (block) block(@{}, error); return; }
        if (!doc)  { if (block) block(@{}, nil); return; }

        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (NSString *perm in doc.permissions) {
            map[perm] = @(YES);
        }
        if (block) block(map.copy, nil);
    }];
}

- (void)setBlocked:(BOOL)blocked
            forUID:(NSString *)uid
            reason:(NSString *)reason
          duration:(NSString *)duration
        completion:(RPVoidError)completion
{
    if (!uid.length) {
        if (completion) completion(RPError(@"Missing uid", 40));
        return;
    }

    // The callable owns the status, compatibility mirrors, context, and audit log.
    NSString *newStatus = blocked ? @"blocked" : @"active";
    [AdminService updateUserStatus:uid
                            status:newStatus
                            reason:reason
                          duration:duration
                        completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
        (void)result;
        if (error) {
            DLog(@"[RP] updateUserStatus failed: %@", error.localizedDescription);
        }
        if (completion) completion(error);
    }];
}

- (void)removeUserByUID:(NSString *)uid
             completion:(RPVoidError)completion
{
    if (!uid.length) {
        if (completion) completion(RPError(@"Missing uid", 41));
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self setBlocked:YES forUID:uid reason:@"Deleted by admin" duration:nil completion:^(NSError * _Nullable blockErr) {
        __strong typeof(weakSelf) self = weakSelf;
        dispatch_group_t group = dispatch_group_create();
        __block FIRQuerySnapshot *canonicalSnap = nil;
        __block FIRQuerySnapshot *legacySnap = nil;
        __block FIRQuerySnapshot *legacyAltSnap = nil;
        __block NSError *readErr = nil;

        dispatch_group_enter(group);
        [[self rpPermisstionsCol:uid] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
            canonicalSnap = snap;
            if (error && !readErr) readErr = error;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [[self legacyPermsCol:uid] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
            legacySnap = snap;
            if (error && !readErr) readErr = error;
            dispatch_group_leave(group);
        }];

        dispatch_group_enter(group);
        [[self legacyPermsColAlt:uid] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
            legacyAltSnap = snap;
            if (error && !readErr) readErr = error;
            dispatch_group_leave(group);
        }];

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (readErr) {
                if (completion) completion(readErr);
                return;
            }

            FIRWriteBatch *batch = [self.db batch];
            for (FIRDocumentSnapshot *doc in canonicalSnap.documents ?: @[]) {
                [batch deleteDocument:doc.reference];
            }
            for (FIRDocumentSnapshot *doc in legacySnap.documents ?: @[]) {
                [batch deleteDocument:doc.reference];
            }
            for (FIRDocumentSnapshot *doc in legacyAltSnap.documents ?: @[]) {
                [batch deleteDocument:doc.reference];
            }
            [batch deleteDocument:[self userDoc:uid]];
            [batch commitWithCompletion:^(NSError * _Nullable deleteErr) {
                if (blockErr) {
                    DLog(@"[RP] removeUserByUID block warning: %@", blockErr.localizedDescription);
                }
                if (!deleteErr) {
                    [self logAdminAuditAction:@"remove_user"
                                    targetUID:uid
                                       before:@{}
                                        after:@{@"removed": @YES}
                                       reason:@"Deleted by admin"
                                   completion:nil];
                }
                if (completion) completion(deleteErr);
            }];
        });
    }];
}


- (void)fetchIDTokenClaims:(void(^)(NSDictionary * _Nullable claims,
                                    NSError * _Nullable error))completion
{
    FIRUser *u = [FIRAuth auth].currentUser;
    if (!u) {
        if (completion) completion(nil, [NSError errorWithDomain:@"RBManager"
                                                            code:142
                                                        userInfo:@{NSLocalizedDescriptionKey: @"No current user"}]);
        return;
    }
    [u getIDTokenResultForcingRefresh:YES completion:^(FIRAuthTokenResult * _Nullable tokenResult, NSError * _Nullable error) {
        if (completion) completion(tokenResult.claims, error);
    }];
}



//=============================================================================================================================================================================================

// UsersCol/<uid>/RP/meta/permissions
- (FIRCollectionReference *)permsCol:(NSString *)uid {
    return [[self userDoc:uid] collectionWithPath:kPermisstionsCol];
}

- (FIRCollectionReference *)legacyPermsCol:(NSString *)uid {
    return [[self userDoc:uid] collectionWithPath:kLegacyPermisstionsCol];
}

- (FIRCollectionReference *)legacyPermsColAlt:(NSString *)uid {
    return [[self userDoc:uid] collectionWithPath:kLegacyPermissionsCol];
}

// UsersCol/<uid>/RP/meta/permissions/<name>
- (FIRDocumentReference *)permDoc:(NSString *)uid name:(NSString *)name {
    return [[self permsCol:uid] documentWithPath:name];
}

- (void)pp_setLegacyPermissionPayload:(NSDictionary *)payload
                               forUID:(NSString *)uid
                        canonicalName:(NSString *)canonicalName
                                batch:(FIRWriteBatch *)batch
{
    if (!uid.length || !canonicalName.length || !payload || !batch) {
        return;
    }

    NSArray<NSString *> *legacyNames = PPLegacyPermissionNames(canonicalName);
    if (legacyNames.count == 0) {
        return;
    }

    NSArray<FIRCollectionReference *> *legacyCollections = @[
        [self legacyPermsCol:uid],
        [self legacyPermsColAlt:uid]
    ];
    for (FIRCollectionReference *collection in legacyCollections) {
        if (![collection isKindOfClass:FIRCollectionReference.class]) {
            continue;
        }
        for (NSString *legacyName in legacyNames) {
            if (legacyName.length == 0) {
                continue;
            }
            [batch setData:payload
               forDocument:[collection documentWithPath:legacyName]
                     merge:YES];
        }
    }
}

- (void)logAdminAuditAction:(NSString *)action
                  targetUID:(NSString *)targetUID
                     before:(NSDictionary *)before
                      after:(NSDictionary *)after
                     reason:(NSString *)reason
                 completion:(void (^_Nullable)(NSError * _Nullable error))completion
{
    NSString *actorUID = [FIRAuth auth].currentUser.uid ?: @"";
    NSDictionary *payload = @{
        @"adminUid": actorUID,
        @"targetUid": targetUID ?: @"",
        @"action": action ?: @"",
        @"before": before ?: @{},
        @"after": after ?: @{},
        @"reason": reason ?: @"",
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp]
    };
    [[[self.db collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
     setData:payload
     completion:completion];
}


#pragma mark - Create user (Auth + Firestore + RP)

- (void)createUserWithEmail:(NSString *)email
                   password:(NSString *)password
                   username:(NSString *)username
                       role:(UserRole)role
                permissions:(NSDictionary<NSString *,NSNumber *> *)perms
                    isAdmin:(BOOL)isAdmin
                completion:(nonnull UserCreationCompletion)completion
{
    NSString *cleanEmail = [email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *cleanUsername = [username stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!cleanEmail.length || !password.length || !cleanUsername.length) {
        if (completion) completion(nil, RPError(@"Missing required user fields", 10));
        return;
    }

    FIRAuth *creatorAuth = [self p_userCreatorAuth];
    if (!creatorAuth) {
        if (completion) completion(nil, RPError(@"Unable to initialize admin user creator auth", 11));
        return;
    }
    DLog(@"createUser ▶︎ %@", cleanEmail);

    [creatorAuth createUserWithEmail:cleanEmail password:password
                             completion:^(FIRAuthDataResult * _Nullable result, NSError * _Nullable err) {
        if (err || !result.user) {
            DLog(@"createUser ❌ %@", err.localizedDescription);
            if (completion) completion(nil,err);
            return;
        }
        NSString *uid = result.user.uid;
        NSError *secondarySignOutError = nil;
        [creatorAuth signOut:&secondarySignOutError];
        if (secondarySignOutError) {
            DLog(@"createUser ⚠️ secondary signOut failed: %@", secondarySignOutError.localizedDescription);
        }

        // Build writes in a single batch
        FIRWriteBatch *batch = [self.db batch];
        BOOL adminRole = (isAdmin || role == UserRoleAdmin || role == UserRoleSuperAdmin);
        BOOL superAdminRole = (role == UserRoleSuperAdmin);

       
        // UsersCol/<uid> base fields
        NSDictionary *base = @{
            @"ID": uid,
            @"uid": uid,
            @"UserEmail": cleanEmail,
            @"UserName": cleanUsername,
            @"isAdmin": @(adminRole),
            @"admin": @(adminRole),
            @"isSuperAdmin": @(superAdminRole),
            @"superadmin": @(superAdminRole),
            @"isBlocked": @NO,
            @"createdAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"verified": @(YES),
            @"displayName": cleanUsername,
            @"email": cleanEmail,
            
        };
        [batch setData:base forDocument:[self userDoc:uid] merge:YES];

        // RPSubCol/role
        NSDictionary *roleMap = @{
            @"roleName": [PPRolePermission roleName:role],
            @"role": @(role),
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]
        };
        [batch setData:roleMap forDocument:[self userDoc:uid] merge:YES];

        // RPSubCol/permissions
        NSMutableDictionary<NSString *, NSNumber *> *finalPerms = [NSMutableDictionary dictionary];
        for (NSString *key in [self defaultPermissionsForRole:role]) finalPerms[key] = @YES;
        // apply overrides if provided
        [perms enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSNumber *v, BOOL *stop) {
            if (!k.length || ![v isKindOfClass:NSNumber.class]) return;
            finalPerms[k] = v;
        }];

        [finalPerms enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSNumber *allowed, BOOL *stop) {
            NSString *canonicalName = PPCanonicalPermissionName(name);
            if (!canonicalName.length) return;
            NSDictionary *permPayload = @{@"allowed": allowed,
                                          @"updatedAt":[FIRFieldValue fieldValueForServerTimestamp],
                                          @"updatedBy": [FIRAuth auth].currentUser.uid ?: @""};
            [batch setData:permPayload forDocument:[self permDoc:uid name:canonicalName] merge:YES];
            [self pp_setLegacyPermissionPayload:permPayload
                                        forUID:uid
                                 canonicalName:canonicalName
                                         batch:batch];
        }];

        // Admin mirror if AdminAll explicitly true
        if ([finalPerms[kPermAdminAll] boolValue]) {
            [batch setData:@{@"isAdmin": @YES,
                             @"updatedAt":[FIRFieldValue fieldValueForServerTimestamp]}
              forDocument:[self userDoc:uid]
                    merge:YES];
        }

        // UsersCol login source for Admin / Console staff access.
        PPStaffRole staffRole = [PPStaffAuth staffRoleFromLegacyRole:role];
        NSArray *staffPerms = [PPStaffAuth defaultPermissionsForStaffRole:staffRole];
        NSDictionary *staffProfile = @{
            @"role": staffRole,
            @"status": PPStaffStatusActive,
            @"permissions": staffPerms,
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"updatedBy": [FIRAuth auth].currentUser.uid ?: @"",
        };
        [batch setData:@{
            @"accountType": @"staff",
            @"staffProfile": staffProfile,
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        } forDocument:[self userDoc:uid] merge:YES];

        [batch commitWithCompletion:^(NSError * _Nullable e) {
            if (e) {
                DLog(@"createUser ❌ batch %@", e.localizedDescription);
                if (completion) completion(nil, e);
                return;
            }

            DLog(@"createUser ✅ uid=%@", uid);

            // Build UserModel snapshot from what we just wrote
            UserModel *newUser = [[UserModel alloc] init];
            newUser.uid = uid;
            newUser.ID = uid;
            newUser.email = cleanEmail;
            newUser.UserEmail = cleanEmail;
            newUser.UserName = cleanUsername;
            newUser.isAdmin = adminRole;
            newUser.isSuperAdmin = superAdminRole;
            newUser.role = role;
            newUser.permissions = finalPerms;
            newUser.verified = YES;
            newUser.isBlocked = NO;
            newUser.loginDate = [NSDate date];

            [self logAdminAuditAction:@"create_user"
                            targetUID:uid
                               before:@{}
                                after:@{
                                    @"role": @(role),
                                    @"isAdmin": @(newUser.isAdmin),
                                    @"permissions": finalPerms ?: @{}
                                }
                               reason:nil
                           completion:nil];

            if (completion) { DLog(@"createUser ✅ uid=%@", uid); completion(newUser, nil); }
        }];

    }];
}


// RPManager.m

- (void)setRole:(UserRole)role
         forUID:(NSString *)uid
        roleName:(NSString *)roleName
applyDefaultPermissions:(BOOL)applyDefaults
      completion:(RPVoidError)completion
{
    if (!uid.length) { if (completion) completion(RPError(@"Missing uid", 20)); return; }

    NSString *name = roleName.length ? roleName : [PPRolePermission roleName:role];

    // Write to UsersCol for backward compat
    FIRWriteBatch *batch = [self.db batch];

    [batch setData:@{@"roleName": name,
                     @"role": @(role),
                     @"updatedAt":[FIRFieldValue fieldValueForServerTimestamp]}
       forDocument:[self userDoc:uid]
             merge:YES];

    BOOL adminRole = (role == UserRoleAdmin || role == UserRoleSuperAdmin);
    BOOL superAdminRole = (role == UserRoleSuperAdmin);
    [batch setData:@{@"isAdmin": @(adminRole),
                     @"admin": @(adminRole),
                     @"isSuperAdmin": @(superAdminRole),
                     @"superadmin": @(superAdminRole),
                     @"updatedAt":[FIRFieldValue fieldValueForServerTimestamp]}
       forDocument:[self userDoc:uid]
             merge:YES];

    PPStaffRole staffRole = [PPStaffAuth staffRoleFromLegacyRole:role];
    NSDictionary *staffProfileUpdates = applyDefaults
        ? @{
            @"accountType": @"staff",
            @"staffProfile.role": staffRole,
            @"staffProfile.permissions": [PPStaffAuth defaultPermissionsForStaffRole:staffRole],
            @"staffProfile.updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"staffProfile.updatedBy": [FIRAuth auth].currentUser.uid ?: @"",
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        }
        : @{
            @"accountType": @"staff",
            @"staffProfile.role": staffRole,
            @"staffProfile.updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"staffProfile.updatedBy": [FIRAuth auth].currentUser.uid ?: @"",
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        };
    [batch updateData:staffProfileUpdates forDocument:[self userDoc:uid]];

    __weak typeof(self) weakSelf = self;
    [batch commitWithCompletion:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) { if (completion) completion(error); return; }

        [self logAdminAuditAction:@"set_role"
                        targetUID:uid
                           before:@{}
                            after:@{@"role": @(role), @"roleName": name ?: @"", @"staffRole": staffRole}
                           reason:nil
                       completion:nil];

        if (completion) completion(nil);
    }];
}




- (void)setPermission:(NSString *)permName
               forUID:(NSString *)uid
              allowed:(BOOL)allowed
           completion:(void(^)(NSError * _Nullable error))completion
{
    NSString *canonicalName = PPCanonicalPermissionName(permName);
    if (!uid.length || !canonicalName.length) { if (completion) completion(RPError(@"Missing uid or permName", 30)); return; }

    // Update UsersCol staff profile.
    [[PPStaffAuth shared] fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable doc, NSError * _Nullable error) {
        if (error || !doc) {
            DLog(@"[RP] setPermission: staff doc not found for %@", uid);
            if (completion) completion(error ?: RPError(@"Staff doc not found", 31));
            return;
        }

        NSMutableSet *perms = [NSMutableSet setWithArray:doc.permissions ?: @[]];
        if (allowed) {
            [perms addObject:canonicalName];
        } else {
            [perms removeObject:canonicalName];
        }

        NSDictionary *permPayload = @{
            @"allowed": @(allowed),
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"updatedBy": [FIRAuth auth].currentUser.uid ?: @""
        };

        FIRWriteBatch *batch = [self.db batch];
        [batch setData:permPayload forDocument:[self permDoc:uid name:canonicalName] merge:YES];
        [self pp_setLegacyPermissionPayload:permPayload
                                    forUID:uid
                             canonicalName:canonicalName
                                     batch:batch];

        if ([canonicalName containsString:@"."]) {
            [batch updateData:@{
                @"accountType": @"staff",
                @"staffProfile.permissions": [perms allObjects],
                @"staffProfile.updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
                @"staffProfile.updatedBy": [FIRAuth auth].currentUser.uid ?: @"",
                @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
            } forDocument:[self userDoc:uid]];
        }

        [batch commitWithCompletion:^(NSError * _Nullable writeError) {
            if (!writeError) {
                [self logAdminAuditAction:@"set_permission"
                                targetUID:uid
                                   before:@{}
                                    after:@{@"permission": canonicalName, @"allowed": @(allowed)}
                                   reason:nil
                               completion:nil];
            } else {
                DLog(@"[RP] setPermission UsersCol error: %@", writeError.localizedDescription);
            }
            if (completion) completion(writeError);
        }];
    }];
}




- (void)allowPermission:(NSString *)permName forUID:(NSString *)uid completion:(RPVoidError)completion {
    [self setPermission:permName forUID:uid allowed:YES completion:completion];
}

- (void)denyPermission:(NSString *)permName forUID:(NSString *)uid completion:(RPVoidError)completion {
    [self setPermission:permName forUID:uid allowed:NO completion:completion];
}


- (void)checkPermission:(NSString *)permName forUID:(NSString *)uid completion:(RPBoolError)completion {
    NSString *canonicalName = PPCanonicalPermissionName(permName);
    if (!uid.length || !canonicalName.length) { if (completion) completion(NO, RPError(@"Missing uid or permName", 33)); return; }

    // Read from UsersCol staff profile.
    [[PPStaffAuth shared] fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable doc, NSError * _Nullable error) {
        if (error)  { if (completion) completion(NO, error); return; }
        if (!doc)   { if (completion) completion(NO, nil); return; }
        BOOL allowed = [doc hasPermission:canonicalName];
        if (completion) completion(allowed, nil);
    }];
}

#pragma mark - Roles



/// Back-compat shim — some older codepaths may still call this signature
- (void)setRoleValue:(UserRole)role
           roleName:(nullable NSString *)roleName
             forUID:(NSString *)uid
         completion:(void(^)(NSError * _Nullable error))completion
{
    // Ignore roleName param and forward to the canonical method.
    [self setRole:role forUID:uid completion:completion];
    
}


- (void)listenForRoleChangesOfUser:(NSString *)uid
                        completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion {

    FIRDocumentReference *doc = [[[FIRFirestore firestore] collectionWithPath:@"UsersCol"] documentWithPath:uid];

    self.reg = [doc addSnapshotListener:^(FIRDocumentSnapshot * _Nullable snapshot,
                                          NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ [RoleListener] Firestore error: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        if (!snapshot.exists) {
            NSLog(@"⚠️ [RoleListener] User doc missing");
            [[PPStaffAuth shared] fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable doc, NSError * _Nullable staffError) {
                if (staffError) {
                    NSLog(@"⚠️ [RoleListener] UsersCol staff profile fallback failed: %@", staffError.localizedDescription);
                }

                if (doc) {
                    UserModel *user = UsrMgr.currentUser;
                    if (!user || ![user.uid isEqualToString:uid]) {
                        user = [UserModel new];
                        user.uid = uid ?: @"";
                    }

                    UserRole mappedRole = (UserRole)[PPStaffAuth legacyRoleFromStaffRole:doc.role];
                    user.role = mappedRole;
                    user.isSuperAdmin = (mappedRole == UserRoleSuperAdmin);
                    user.isAdmin = PPIsAllowedAdminRole(mappedRole);
                    user.isBlocked = !doc.isActive;

                    [UsrMgr p_cacheUser:user];
                    if (completion) completion(user, nil);
                    return;
                }

                UserModel *cachedUser = UsrMgr.currentUser;
                if (cachedUser && [cachedUser.uid isEqualToString:uid]) {
                    NSLog(@"ℹ️ [RoleListener] Using cached user while Firestore doc is unavailable");
                    if (completion) completion(cachedUser, nil);
                }
            }];
            return;
        }
        
        UserModel *user = [[UserModel alloc] initWithSnapshot:snapshot];
        if (!user) {
            NSLog(@"⚠️ [RoleListener] Snapshot could not be parsed into a user model");
            return;
        }
        [[PPStaffAuth shared] fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable staffDoc, NSError * _Nullable staffError) {
            if (staffError) {
                NSLog(@"⚠️ [RoleListener] UsersCol staff profile overlay failed: %@", staffError.localizedDescription);
            }

            if (staffDoc) {
                if (!staffDoc.isActive) {
                    user.isBlocked = YES;
                } else {
                    UserRole mappedRole = [PPStaffAuth legacyRoleFromStaffRole:staffDoc.role];
                    if (mappedRole != UserRoleUnknown) {
                        user.role = mappedRole;
                        user.isSuperAdmin = [staffDoc.role isEqualToString:PPStaffRoleSuperAdmin];
                        user.isAdmin = user.isSuperAdmin ||
                                       mappedRole == UserRoleAdmin ||
                                       mappedRole == UserRoleSuperAdmin ||
                                       mappedRole == UserRoleOwner;
                    }

                    if (staffDoc.permissions.count > 0) {
                        NSMutableDictionary<NSString *, NSNumber *> *permissionMap =
                            [NSMutableDictionary dictionaryWithDictionary:user.permissions ?: @{}];
                        for (NSString *permission in staffDoc.permissions) {
                            permissionMap[permission] = @YES;
                        }
                        user.permissions = permissionMap;
                    }
                }
            }

            NSLog(@"🔄 [RoleListener] Updated role=%@, admin=%@, super=%@, blocked=%@",
                  [PPRolePermission roleName:user.role],
                  user.isAdmin ? @"YES" : @"NO",
                  user.isSuperAdmin ? @"YES" : @"NO",
                  user.isBlocked ? @"YES" : @"NO");

            [UsrMgr p_cacheUser:user];

            if (completion) completion(user, nil);
        }];
    }];
}

- (void)stopListening {
    [self.reg remove];
    self.reg = nil;
}

@end
