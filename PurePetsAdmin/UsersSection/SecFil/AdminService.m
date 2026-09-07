//
//  AdminService.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 06/09/2025.
//

#import "AdminService.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPStaffAuth.h"

@implementation AdminService

+ (FIRFunctions *)pp_functions {
    return [FIRFunctions functionsForRegion:@"us-central1"];
}

+ (void)pp_completeOnMain:(AdminServiceCompletion)completion
                   result:(NSDictionary * _Nullable)result
                    error:(NSError * _Nullable)error {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(result, error);
    });
}

+ (NSDictionary *)pp_normalizedResultDictionary:(id)resultData {
    if ([resultData isKindOfClass:[NSDictionary class]]) {
        return (NSDictionary *)resultData;
    }
    if (!resultData) {
        return @{};
    }
    return @{@"data": resultData};
}

+ (void)pp_callCallable:(NSString *)name
                payload:(NSDictionary *)payload
             completion:(AdminServiceCompletion)completion {
    FIRHTTPSCallable *callable = [[self pp_functions] HTTPSCallableWithName:name];
    [callable callWithObject:(payload ?: @{})
                  completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ [AdminService] %@ failed: %@", name, error.localizedDescription);
            [self pp_completeOnMain:completion result:nil error:error];
            return;
        }

        NSDictionary *normalized = [self pp_normalizedResultDictionary:result.data];
        NSLog(@"✅ [AdminService] %@ result: %@", name, normalized);
        [self pp_completeOnMain:completion result:normalized error:nil];
    }];
}

+ (void)pp_loadStaffRevision:(NSString *)uid
                  completion:(void (^)(NSInteger revision, NSError * _Nullable error))completion {
    [[[[FIRFirestore firestore] collectionWithPath:@"staff_users"] documentWithPath:(uid ?: @"")]
        getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(0, error);
            return;
        }
        NSNumber *stored = [snapshot.data[@"revision"] isKindOfClass:NSNumber.class]
            ? snapshot.data[@"revision"]
            : @0;
        if (completion) completion(MAX(0, stored.integerValue), nil);
    }];
}

+ (void)pp_callIAMCommand:(NSString *)name
                   payload:(NSDictionary *)payload
                    reason:(NSString *)reason
         expectedRevision:(NSInteger)expectedRevision
                completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *command = [(payload ?: @{}) mutableCopy];
    command[@"idempotencyKey"] = NSUUID.UUID.UUIDString;
    command[@"expectedRevision"] = @(MAX(0, expectedRevision));
    command[@"reason"] = reason ?: @"admin_app_iam_command";
    [self pp_callCallable:name payload:command completion:completion];
}

#pragma mark - Staff Management (new Cloud Functions)

+ (void)createStaffMemberWithEmail:(NSString *)email
                              name:(NSString *)name
                          password:(NSString *)password
                              role:(PPStaffRole)role
                       permissions:(NSArray<NSString *> *)permissions
                             scope:(NSDictionary *)scope
                        completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{
        @"email": email ?: @"",
        @"name": name ?: @"",
        @"password": password ?: @"",
        @"role": role ?: PPStaffRoleViewer
    } mutableCopy];
    if (permissions) payload[@"permissions"] = permissions;
    if (scope)       payload[@"scope"] = scope;
    [self pp_callIAMCommand:@"createStaffMember"
                    payload:payload
                     reason:@"admin_app_create_staff_member"
          expectedRevision:0
                 completion:completion];
}

+ (void)assignExistingUserAsStaff:(NSString *)uid
                             role:(PPStaffRole)role
                      permissions:(NSArray<NSString *> *)permissions
                            scope:(NSDictionary *)scope
                       completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{
        @"uid": uid ?: @"",
        @"role": role ?: PPStaffRoleViewer
    } mutableCopy];
    if (permissions) payload[@"permissions"] = permissions;
    if (scope)       payload[@"scope"] = scope;
    [self pp_callIAMCommand:@"assignExistingUserAsStaff"
                    payload:payload
                     reason:@"admin_app_promote_existing_user"
          expectedRevision:0
                 completion:completion];
}

+ (void)updateStaffMember:(NSString *)uid
                  updates:(NSDictionary *)updates
               completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{
        @"uid": uid ?: @""
    } mutableCopy];
    if ([updates isKindOfClass:NSDictionary.class]) {
        [payload addEntriesFromDictionary:updates];
    }
    NSNumber *explicitRevision = [payload[@"expectedRevision"] isKindOfClass:NSNumber.class]
        ? payload[@"expectedRevision"]
        : nil;
    if (explicitRevision) {
        [payload removeObjectForKey:@"expectedRevision"];
        [self pp_callIAMCommand:@"updateStaffMember"
                        payload:payload
                         reason:@"admin_app_update_staff_member"
              expectedRevision:explicitRevision.integerValue
                     completion:completion];
        return;
    }
    [self pp_loadStaffRevision:uid completion:^(NSInteger revision, NSError * _Nullable error) {
        if (error) {
            [self pp_completeOnMain:completion result:nil error:error];
            return;
        }
        [self pp_callIAMCommand:@"updateStaffMember"
                        payload:payload
                         reason:@"admin_app_update_staff_member"
              expectedRevision:revision
                     completion:completion];
    }];
}

+ (void)disableStaffMember:(NSString *)uid
                completion:(AdminServiceCompletion)completion {
    [self pp_loadStaffRevision:uid completion:^(NSInteger revision, NSError * _Nullable error) {
        if (error) {
            [self pp_completeOnMain:completion result:nil error:error];
            return;
        }
        [self disableStaffMember:uid expectedRevision:revision completion:completion];
    }];
}

+ (void)disableStaffMember:(NSString *)uid
          expectedRevision:(NSInteger)expectedRevision
                completion:(AdminServiceCompletion)completion {
    [self pp_callIAMCommand:@"disableStaffMember"
                    payload:@{@"uid": uid ?: @""}
                     reason:@"admin_app_disable_staff_member"
          expectedRevision:expectedRevision
                 completion:completion];
}

#pragma mark - User Access Management (new)

+ (void)updateUserFeatures:(NSString *)uid
                  features:(NSDictionary *)features
                completion:(AdminServiceCompletion)completion {
    [self pp_callCallable:@"updateUserFeatures"
                  payload:@{@"uid": uid ?: @"", @"features": features ?: @{}}
               completion:completion];
}

+ (void)updateUserRestrictions:(NSString *)uid
                  restrictions:(NSDictionary *)restrictions
                    completion:(AdminServiceCompletion)completion {
    [self pp_callCallable:@"updateUserRestrictions"
                  payload:@{@"uid": uid ?: @"", @"restrictions": restrictions ?: @{}}
               completion:completion];
}

+ (void)updateUserStatus:(NSString *)uid
                  status:(NSString *)status
              completion:(AdminServiceCompletion)completion {
    [self updateUserStatus:uid status:status reason:nil duration:nil completion:completion];
}

+ (void)updateUserStatus:(NSString *)uid
                  status:(NSString *)status
                  reason:(NSString *)reason
                duration:(NSString *)duration
              completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{
        @"uid": uid ?: @"",
        @"accountStatus": status ?: @"active"
    } mutableCopy];
    if (reason.length) payload[@"reason"] = reason;
    if (duration.length) payload[@"duration"] = duration;
    [self pp_callCallable:@"updateUserStatus"
                  payload:payload.copy
               completion:completion];
}

+ (void)createCustomerAccountWithName:(NSString *)name
                                email:(NSString *)email
                                phone:(nullable NSString *)phone
                             password:(NSString *)password
                        initialStatus:(nullable NSString *)initialStatus
                           isVerified:(BOOL)isVerified
                           completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{
        @"name": name ?: @"",
        @"email": email ?: @"",
        @"password": password ?: @"",
        @"initialStatus": initialStatus ?: @"active",
        @"isVerified": @(isVerified)
    } mutableCopy];
    if (phone.length > 0) {
        payload[@"phone"] = phone;
    }
    [self pp_callCallable:@"createCustomerAccount"
                  payload:payload.copy
               completion:completion];
}

+ (void)updateUserSubscription:(NSString *)uid
                  subscription:(NSDictionary *)subscription
                    completion:(AdminServiceCompletion)completion {
    [self pp_callCallable:@"updateUserSubscription"
                  payload:@{@"uid": uid ?: @"", @"subscription": subscription ?: @{}}
               completion:completion];
}

+ (void)updateUserVerified:(NSString *)uid
                  verified:(BOOL)verified
                completion:(AdminServiceCompletion)completion {
    [self pp_callCallable:@"updateUserVerified"
                  payload:@{@"uid": uid ?: @"", @"verified": @(verified)}
               completion:completion];
}

#pragma mark - Legacy (kept for migration bridge — will be removed)

+ (void)setAdminFor:(NSString *)emailOrUID
               isUID:(BOOL)isUID
               admin:(BOOL)admin
          superAdmin:(BOOL)superAdmin
          completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    if (isUID) {
        NSMutableDictionary *payload = [@{
            @"uid": emailOrUID ?: @"",
            @"makeAdmin": @(admin),
            @"makeSuperAdmin": @(superAdmin)
        } mutableCopy];
        [self pp_callCallable:@"setAdminClaim" payload:payload completion:completion];
        return;
    }

    NSMutableDictionary *payload = [@{
        @"email": emailOrUID ?: @"",
        @"admin": @(admin),
        @"superAdmin": @(superAdmin)
    } mutableCopy];
    [self pp_callCallable:@"setUserPermissions" payload:payload completion:completion];
}

+ (void)setUserPermissionsForUser:(NSString *)emailOrUID
                            isUID:(BOOL)isUID
                             role:(UserRole)role
                            admin:(BOOL)admin
                       superAdmin:(BOOL)superAdmin
                           blocked:(BOOL)blocked
                        completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    NSMutableDictionary *payload = [@{
        @"role": @(role),
        @"admin": @(admin),
        @"superAdmin": @(superAdmin),
        @"blocked": @(blocked)
    } mutableCopy];
    if (isUID) {
        payload[@"uid"] = emailOrUID ?: @"";
    } else {
        payload[@"email"] = emailOrUID ?: @"";
    }
    [self pp_callCallable:@"setUserPermissions" payload:payload completion:completion];
}

+ (void)setUserRoleFor:(NSString *)emailOrUID
                 isUID:(BOOL)isUID
                  role:(UserRole)role
            completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{ @"role": @(role) } mutableCopy];
    if (isUID) payload[@"uid"] = emailOrUID;
    else payload[@"email"] = emailOrUID;
    [self pp_callCallable:@"setUserPermissions" payload:payload completion:completion];
}

+ (void)setAdmin:(NSString *)emailOrUID
           isUID:(BOOL)isUID
        setAdmin:(BOOL)admin
      completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{ @"admin": @(admin) } mutableCopy];
    if (isUID) payload[@"uid"] = emailOrUID;
    else payload[@"email"] = emailOrUID;
    [self pp_callCallable:@"setUserPermissions" payload:payload completion:completion];
}

+ (void)setUserBlockedFor:(NSString *)emailOrUID
                   isUID:(BOOL)isUID
                  Blocked:(BOOL)blocked
              completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [@{ @"blocked": @(blocked) } mutableCopy];
    if (isUID) payload[@"uid"] = emailOrUID;
    else payload[@"email"] = emailOrUID;
    [self pp_callCallable:@"setUserPermissions" payload:payload completion:completion];
}

+ (void)setUserPermissionsFor:(NSString *)emailOrUID
                        isUID:(BOOL)isUID
                 customClaims:(NSDictionary * _Nullable)claims
                   completion:(AdminServiceCompletion)completion {
    NSMutableDictionary *payload = [claims mutableCopy] ?: [NSMutableDictionary dictionary];
    if (isUID) payload[@"uid"] = emailOrUID;
    else payload[@"email"] = emailOrUID;
    [self pp_callCallable:@"setUserPermissions" payload:payload completion:completion];
}

+ (void)updateUserClaimsFor:(NSString *)emailOrUID
                      isUID:(BOOL)isUID
                     claims:(NSDictionary *)claims
                 completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion {
    NSMutableDictionary *payload = [claims mutableCopy] ?: [NSMutableDictionary dictionary];
    if (isUID) payload[@"uid"] = emailOrUID;
    else payload[@"email"] = emailOrUID;
    [self pp_callCallable:@"updateUserClaims" payload:payload completion:completion];
}

@end
