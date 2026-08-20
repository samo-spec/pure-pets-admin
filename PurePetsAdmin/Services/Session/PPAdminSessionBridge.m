#import "PPAdminSessionBridge.h"

#import <CoreFoundation/CoreFoundation.h>
#import "UsersSection/References/UserManager.h"
#import "UsersSection/References/UserModel.h"
#import "UsersSection/SecFil/FUManager.h"
#import "UsersSection/SecFil/PPStaffAuth.h"

@import FirebaseAuth;

NSString * const PPAdminSessionBridgeErrorDomain = @"PPAdminSessionBridge";

static BOOL PPAdminSessionStrictGlobalScope(NSDictionary<NSString *, id> *scope) {
    id value = scope[@"global"];
    if (![value isKindOfClass:NSNumber.class]) return NO;
    CFTypeRef type = (__bridge CFTypeRef)value;
    return CFGetTypeID(type) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)type);
}

@interface PPAdminSessionSnapshot ()
@property (nonatomic, copy, readwrite) NSString *uid;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic, copy, readwrite) NSString *email;
@property (nonatomic, copy, readwrite) NSString *roleIdentifier;
@property (nonatomic, copy, readwrite) NSString *localizedRoleName;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *permissions;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, id> *scope;
@property (nonatomic, assign, readwrite) BOOL grantsAllPermissions;
@end

@interface PPAdminSessionObservation ()
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> registration;
@end

@implementation PPAdminSessionObservation

- (void)invalidate {
    [self.registration remove];
    self.registration = nil;
}

- (void)dealloc {
    [self.registration remove];
}

@end

@implementation PPAdminSessionSnapshot

- (BOOL)hasPermission:(NSString *)permission {
    if (permission.length == 0) return NO;
    return self.grantsAllPermissions || [self.permissions containsObject:permission];
}

- (BOOL)hasAnyPermission:(NSArray<NSString *> *)permissions {
    if (self.grantsAllPermissions) return YES;
    for (NSString *permission in permissions ?: @[]) {
        if ([self.permissions containsObject:permission]) return YES;
    }
    return NO;
}

- (BOOL)hasGlobalScope {
    return self.grantsAllPermissions || PPAdminSessionStrictGlobalScope(self.scope);
}

@end

@implementation PPAdminSessionBridge

+ (NSError *)pp_errorWithCode:(PPAdminSessionBridgeErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:PPAdminSessionBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @""}];
}

+ (NSError *)pp_staffAccessError:(PPStaffDoc *)staffDoc {
    BOOL disabled = staffDoc != nil && !staffDoc.isActive;
    return [self pp_errorWithCode:(disabled ? PPAdminSessionBridgeErrorDisabled : PPAdminSessionBridgeErrorUnauthorized)
                       description:kLang(disabled ? @"StatusAccountDisabled" : @"StatusNoAccess")];
}

+ (PPAdminSessionSnapshot *)pp_snapshotForAuthUser:(FIRUser *)authUser
                                          userModel:(UserModel *)userModel
                                           staffDoc:(PPStaffDoc *)staffDoc {
    PPAdminSessionSnapshot *snapshot = [PPAdminSessionSnapshot new];
    snapshot.uid = authUser.uid ?: @"";

    NSString *displayName = [userModel PPBestDisplayName];
    if (displayName.length == 0) displayName = authUser.displayName;
    if (displayName.length == 0) displayName = authUser.email;
    snapshot.displayName = displayName ?: @"";
    snapshot.email = userModel.UserEmail.length > 0 ? userModel.UserEmail : (authUser.email ?: @"");
    snapshot.roleIdentifier = staffDoc.role ?: @"";
    snapshot.localizedRoleName = [PPStaffAuth localizedRoleName:staffDoc.role] ?: staffDoc.role ?: @"";
    // The session router must consume the same canonical permission list as
    // Firestore Rules. UserModel is populated below only for legacy screens.
    snapshot.permissions = staffDoc.permissions ?: @[];
    snapshot.scope = staffDoc.scope ?: @{};
    snapshot.grantsAllPermissions = staffDoc.isAdmin;
    return snapshot;
}

+ (UserModel * _Nullable)pp_applyStaffDoc:(PPStaffDoc *)staffDoc
                              toUserModel:(UserModel * _Nullable)userModel
                                 authUser:(FIRUser *)authUser {
    UserModel *effectiveUser = userModel ?: [[FUManager shared] userModelFromAuth:authUser doc:nil];
    if (!effectiveUser) return nil;

    NSMutableDictionary<NSString *, NSNumber *> *permissionMap = [NSMutableDictionary dictionary];
    for (NSString *permission in staffDoc.permissions ?: @[]) {
        if (permission.length > 0) permissionMap[permission] = @YES;
    }
    effectiveUser.accountType = staffDoc.accountType;
    effectiveUser.staffRole = staffDoc.role;
    effectiveUser.role = [PPStaffAuth legacyRoleFromStaffRole:staffDoc.role];
    effectiveUser.isSuperAdmin = [staffDoc.role isEqualToString:PPStaffRoleSuperAdmin];
    effectiveUser.isAdmin = staffDoc.isAdmin;
    effectiveUser.isBlocked = !staffDoc.isActive;
    effectiveUser.permissions = permissionMap;
    [UserManager shared].currentUser = effectiveUser;
    return effectiveUser;
}

+ (void)restoreCurrentSessionWithCompletion:(PPAdminSessionRestoreCompletion)completion {
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, nil);
        });
        return;
    }

    [[PPStaffAuth shared] refreshCurrentStaff:^(PPStaffDoc * _Nullable staffDoc,
                                                NSError * _Nullable staffError) {
        if (staffError) {
            if (completion) completion(nil, staffError);
            return;
        }
        if (!staffDoc.canAccessStaffWorkspace) {
            if (completion) completion(nil, [self pp_staffAccessError:staffDoc]);
            return;
        }

        [[UserManager shared] loadUserByUIDOrID:authUser.uid completion:^(UserModel * _Nullable loadedUser,
                                                                          NSError * _Nullable userError) {
            UserModel *effectiveUser = [self pp_applyStaffDoc:staffDoc
                                                  toUserModel:loadedUser
                                                     authUser:authUser];
            if (!effectiveUser) {
                if (completion) {
                    completion(nil, userError ?: [self pp_errorWithCode:PPAdminSessionBridgeErrorMissingUser
                                                             description:kLang(@"StatusUserDocError")]);
                }
                return;
            }

            [[UserManager shared] p_writeUserToDisk:effectiveUser forUID:authUser.uid];

            PPAdminSessionSnapshot *snapshot = [self pp_snapshotForAuthUser:authUser
                                                                   userModel:effectiveUser
                                                                    staffDoc:staffDoc];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(snapshot, nil);
            });
        }];
    }];
}

+ (PPAdminSessionObservation *)observeCurrentSessionWithChange:(PPAdminSessionRestoreCompletion)change {
    PPAdminSessionObservation *observation = [PPAdminSessionObservation new];
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (change) change(nil, nil); });
        return observation;
    }

    observation.registration = [[PPStaffAuth shared] listenStaffDoc:authUser.uid
                                                            onChange:^(PPStaffDoc * _Nullable staffDoc,
                                                                       NSError * _Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (change) change(nil, error); });
            return;
        }
        if (!staffDoc.canAccessStaffWorkspace) {
            NSError *accessError = [self pp_staffAccessError:staffDoc];
            dispatch_async(dispatch_get_main_queue(), ^{ if (change) change(nil, accessError); });
            return;
        }

        UserModel *effectiveUser = [self pp_applyStaffDoc:staffDoc
                                               toUserModel:[UserManager shared].currentUser
                                                  authUser:authUser];
        PPAdminSessionSnapshot *snapshot = effectiveUser
            ? [self pp_snapshotForAuthUser:authUser userModel:effectiveUser staffDoc:staffDoc]
            : nil;
        NSError *snapshotError = snapshot ? nil : [self pp_errorWithCode:PPAdminSessionBridgeErrorMissingUser
                                                              description:kLang(@"StatusUserDocError")];
        dispatch_async(dispatch_get_main_queue(), ^{ if (change) change(snapshot, snapshotError); });
    }];
    return observation;
}

+ (NSString *)localizedRoleNameForRoleIdentifier:(NSString *)roleIdentifier {
    return [PPStaffAuth localizedRoleName:roleIdentifier] ?: roleIdentifier ?: @"";
}

+ (void)signOutWithCompletion:(void (^)(NSError * _Nullable))completion {
    [[UserManager shared] signOutWithCompletion:completion];
}

@end
