//
//  PPStaffAuth.m
//  PurePetsAdmin
//
//  Staff authorization sourced from canonical `staff_users/{uid}`.
//

#import "PPStaffAuth.h"
#import "PPStaffAuthCatalog.generated.m"
#import <CoreFoundation/CoreFoundation.h>
@import Firebase;
@import FirebaseAuth;

#pragma mark - Staff Status Constants

PPStaffStatus const PPStaffStatusActive   = @"active";
PPStaffStatus const PPStaffStatusDisabled = @"disabled";

static NSString * const kPPStaffAuthUsersCollection = @"staff_users";
static NSString * const kPPStaffAuthAccountTypeStaff = @"staff";


static NSString *PPStaffSafeString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:NSNumber.class]) {
        return [[(NSNumber *)value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return @"";
}

static NSDictionary *PPStaffSafeDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : @{};
}

static BOOL PPStaffStrictBooleanTrue(id value) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    CFTypeRef type = (__bridge CFTypeRef)value;
    return CFGetTypeID(type) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)type);
}

static NSArray<NSString *> *PPStaffCanonicalPermissionKeys(id value) {
    NSMutableOrderedSet<NSString *> *ordered = [NSMutableOrderedSet orderedSet];

    if (![value isKindOfClass:NSArray.class]) {
        return @[];
    }

    for (id entry in (NSArray *)value) {
        NSString *normalized = PPStaffSafeString(entry);
        if (normalized.length > 0 && [normalized containsString:@"."]) {
            [ordered addObject:normalized];
        }
    }

    return ordered.array ?: @[];
}

#pragma mark - PPStaffDoc

@implementation PPStaffDoc

- (instancetype)initWithDictionary:(NSDictionary *)dict uid:(NSString *)uid {
    if ((self = [super init])) {
        NSDictionary *root = PPStaffSafeDictionary(dict);

        NSString *resolvedRoleValue = PPStaffSafeString(root[@"role"]);
        if (resolvedRoleValue.length == 0) resolvedRoleValue = PPStaffSafeString(root[@"staffRole"]);
        if (resolvedRoleValue.length == 0) resolvedRoleValue = PPStaffSafeString(root[@"roleName"]);

        // Firestore Rules only admit the exact literal `active`; do not make
        // status case-insensitive here or grant client-only access.
        NSString *statusValue = PPStaffSafeString(root[@"status"]);

        _uid = PPStaffSafeString(uid);
        // Collection membership is the staff authority. Keep the normalized
        // value for legacy consumers that still render UserModel.accountType.
        _accountType = kPPStaffAuthAccountTypeStaff;
        _roleIdentifier = resolvedRoleValue.length > 0 ? resolvedRoleValue : PPStaffRoleViewer;
        NSString *storedRoleName = PPStaffSafeString(root[@"roleName"]);
        _roleName = storedRoleName.length > 0 ? storedRoleName : nil;
        _role = PPStaffNormalizedRole(resolvedRoleValue);
        _status = [statusValue isEqualToString:PPStaffStatusActive] ? PPStaffStatusActive : PPStaffStatusDisabled;
        // Infra resolves role defaults when the stored permissions array is
        // absent or empty. Mirror that rule here so the client does not deny
        // an otherwise valid canonical staff record before the backend does.
        NSArray<NSString *> *explicitPermissions = PPStaffCanonicalPermissionKeys(root[@"permissions"]);
        _permissions = explicitPermissions.count > 0
            ? explicitPermissions
            : [PPStaffAuth defaultPermissionsForStaffRole:_role];
        _scope = PPStaffSafeDictionary(root[@"scope"]);
        NSString *displayName = PPStaffSafeString(root[@"displayName"]);
        if (displayName.length == 0) displayName = PPStaffSafeString(root[@"name"]);
        if (displayName.length == 0) displayName = PPStaffSafeString(root[@"UserName"]);
        _displayName = displayName.length > 0 ? displayName : nil;
        NSString *email = PPStaffSafeString(root[@"email"]);
        if (email.length == 0) email = PPStaffSafeString(root[@"UserEmail"]);
        _email = email.length > 0 ? email : nil;
        NSString *phone = PPStaffSafeString(root[@"phone"]);
        if (phone.length == 0) phone = PPStaffSafeString(root[@"phoneNumber"]);
        if (phone.length == 0) phone = PPStaffSafeString(root[@"MobileNo"]);
        _phone = phone.length > 0 ? phone : nil;
        NSString *photoURL = PPStaffSafeString(root[@"photoURL"]);
        if (photoURL.length == 0) photoURL = PPStaffSafeString(root[@"photoUrl"]);
        if (photoURL.length == 0) photoURL = PPStaffSafeString(root[@"UserImageUrl"]);
        _photoURL = photoURL.length > 0 ? photoURL : nil;
        _verified = PPStaffStrictBooleanTrue(root[@"emailVerified"] ?: root[@"verified"]);

        NSNumber *claimsVersion = [root[@"claimsVersion"] isKindOfClass:NSNumber.class] ? root[@"claimsVersion"] : nil;
        _claimsVersion = claimsVersion.integerValue;

        NSString *updatedBy = PPStaffSafeString(root[@"updatedBy"]);
        _updatedBy = updatedBy.length > 0 ? updatedBy : nil;
    }
    return self;
}

- (BOOL)isActive {
    return [self.status isEqualToString:PPStaffStatusActive];
}

- (BOOL)isAdmin {
    return [PPStaffAuth isAdminRole:self.role] && self.isActive;
}

- (BOOL)canAccessStaffWorkspace {
    return self.isActive && [self hasPermission:kStaffPermDashboardView];
}

- (BOOL)hasGlobalScope {
    return PPStaffStrictBooleanTrue(self.scope[@"global"]);
}

BOOL PPStaffMatchesPermission(NSArray<NSString *> *granted, NSString *perm) {
    if (!perm.length || !granted.count) return NO;
    if ([granted containsObject:perm]) return YES;

    // Canonical hierarchical resolution matching the 18 modules (45 permissions)
    if ([perm isEqualToString:@"stock.cost.view"]) {
        return [granted containsObject:kStaffPermStockManage] || [granted containsObject:kStaffPermStockView];
    }
    if ([perm isEqualToString:@"stock.quarantine.release"]) {
        return [granted containsObject:kStaffPermStockManage];
    }
    if ([perm isEqualToString:@"hotel.checkout"]) {
        return [granted containsObject:kStaffPermHotelCheckIn];
    }
    if ([perm hasPrefix:@"hotel."] && [granted containsObject:@"hotel.manage"]) {
        return YES;
    }
    if ([perm hasPrefix:@"delivery."] && [granted containsObject:@"delivery.override"]) {
        return YES;
    }
    if (([perm isEqualToString:@"delivery.driver.view"] ||
         [perm isEqualToString:@"delivery.driver.manage"] ||
         [perm isEqualToString:@"delivery.assign"] ||
         [perm isEqualToString:@"delivery.route.view"] ||
         [perm isEqualToString:@"delivery.route.manage"] ||
         [perm isEqualToString:@"delivery.pod.review"]) &&
        [granted containsObject:@"delivery.dispatch"]) {
        return YES;
    }
    if ([perm isEqualToString:@"delivery.cod.view"] && [granted containsObject:@"delivery.cod.reconcile"]) {
        return YES;
    }
    if ([perm hasPrefix:@"users.features."] && [granted containsObject:@"users.features.manage"]) {
        return YES;
    }
    if ([perm hasPrefix:@"users.restrictions."] && [granted containsObject:@"users.restrictions.manage"]) {
        return YES;
    }
    if ([perm hasPrefix:@"users.subscriptions."] &&
        ([granted containsObject:@"users.manage"] || [granted containsObject:@"users.features.manage"])) {
        return YES;
    }
    return NO;
}

- (BOOL)hasPermission:(NSString *)perm {
    if (!perm.length || !self.isActive) return NO;
    if (self.isAdmin) return YES;
    return PPStaffMatchesPermission(self.permissions, perm);
}

- (BOOL)hasAnyPermission:(NSArray<NSString *> *)perms {
    if (!self.isActive) return NO;
    if (self.isAdmin) return YES;
    for (NSString *permission in perms) {
        if ([self hasPermission:permission]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSString *> *)assignedBranchIDs {
    NSArray *branches = self.scope[@"branchIds"];
    if ([branches isKindOfClass:NSArray.class]) {
        return branches;
    }
    return @[];
}

- (NSString *)defaultBranchID {
    NSString *def = PPStaffSafeString(self.scope[@"defaultBranchId"]);
    if (def.length > 0) return def;
    return self.assignedBranchIDs.firstObject;
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)branchPermissions {
    NSDictionary *perms = self.scope[@"branchPermissions"];
    if ([perms isKindOfClass:NSDictionary.class]) {
        return perms;
    }
    return nil;
}

- (BOOL)hasAccessToBranch:(NSString *)branchID {
    if (!branchID.length || !self.isActive) return NO;
    if (self.hasGlobalScope || self.isAdmin) return YES;
    return [self.assignedBranchIDs containsObject:branchID];
}

- (BOOL)hasPermission:(NSString *)perm inBranch:(NSString * _Nullable)branchID {
    if (!perm.length || !self.isActive) return NO;
    if (self.isAdmin) return YES;
    if (branchID.length && ![self hasAccessToBranch:branchID]) return NO;
    if (branchID.length && self.branchPermissions[branchID]) {
        NSArray<NSString *> *branchPerms = self.branchPermissions[branchID];
        if ([branchPerms isKindOfClass:NSArray.class]) {
            if (PPStaffMatchesPermission(branchPerms, perm)) return YES;
        }
    }
    return [self hasPermission:perm];
}

- (NSString *)localizedRoleName {
    return [PPStaffAuth localizedRoleName:self.role];
}

@end

#pragma mark - PPStaffAuth

@interface PPStaffAuth ()
@property (nonatomic, strong) FIRFirestore *db;
@property (nonatomic, strong, nullable) PPStaffDoc *cachedCurrentStaff;
@end

@implementation PPStaffAuth

+ (instancetype)shared {
    static PPStaffAuth *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [PPStaffAuth new];
    });
    return sharedInstance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _db = [FIRFirestore firestore];
    }
    return self;
}

- (FIRDocumentReference *)staffDoc:(NSString *)uid {
    return [[self.db collectionWithPath:kPPStaffAuthUsersCollection] documentWithPath:uid];
}

- (PPStaffDoc * _Nullable)pp_staffDocFromSnapshot:(FIRDocumentSnapshot * _Nullable)snapshot {
    if (!snapshot.exists) {
        return nil;
    }

    return [[PPStaffDoc alloc] initWithDictionary:snapshot.data ?: @{} uid:snapshot.documentID ?: @""];
}

- (void)fetchStaffDoc:(NSString *)uid completion:(PPStaffDocCompletion)completion {
    if (!uid.length) {
        NSLog(@"🛡️  [PPADMIN BACKEND] fetchStaffDoc aborted: missing UID");
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"PPStaffAuth"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing uid"}]);
        }
        return;
    }

    NSLog(@"🛡️  [PPADMIN BACKEND] Querying Firestore staff document: staff_users/%@", uid);
    [[self staffDoc:uid] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"❌ [PPADMIN BACKEND] Failed fetching staff_users/%@: %@", uid, error.localizedDescription);
                if (completion) completion(nil, error);
                return;
            }
            if (!snapshot.exists) {
                NSLog(@"⚠️  [PPADMIN BACKEND] Document not found in staff_users/%@", uid);
                if (completion) completion(nil, nil);
                return;
            }
            PPStaffDoc *doc = [self pp_staffDocFromSnapshot:snapshot];
            if (doc && [[FIRAuth auth].currentUser.uid isEqualToString:uid]) {
                self.cachedCurrentStaff = doc.canAccessStaffWorkspace ? doc : nil;
            }
            NSLog(@"✅ [PPADMIN BACKEND] Successfully resolved staff_users/%@ | role=%@ | status=%@ | perms=%lu | active=%d",
                  uid, doc.role, doc.status, (unsigned long)doc.permissions.count, doc.isActive);
            if (completion) completion(doc, nil);
        });
    }];
}

- (id<FIRListenerRegistration>)listenStaffDoc:(NSString *)uid onChange:(PPStaffDocCompletion)block {
    if (!uid.length) {
        NSLog(@"🛡️  [PPADMIN BACKEND] listenStaffDoc aborted: missing UID");
        if (block) {
            block(nil, [NSError errorWithDomain:@"PPStaffAuth"
                                           code:2
                                       userInfo:@{NSLocalizedDescriptionKey: @"Missing uid"}]);
        }
        return nil;
    }

    NSLog(@"🛡️  [PPADMIN BACKEND] Subscribing to snapshot listener for staff_users/%@", uid);
    return [[self staffDoc:uid] addSnapshotListener:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ [PPADMIN BACKEND] Snapshot listener error on staff_users/%@: %@", uid, error.localizedDescription);
            if (block) block(nil, error);
            return;
        }
        PPStaffDoc *doc = [self pp_staffDocFromSnapshot:snapshot];
        if (doc) {
            NSLog(@"🔄 [PPADMIN BACKEND] Snapshot update for staff_users/%@ | role=%@ | status=%@ | perms=%lu",
                  uid, doc.role, doc.status, (unsigned long)doc.permissions.count);
        } else {
            NSLog(@"⚠️  [PPADMIN BACKEND] Snapshot update: staff_users/%@ does not exist", uid);
        }
        if ([[FIRAuth auth].currentUser.uid isEqualToString:uid]) {
            self.cachedCurrentStaff = doc.canAccessStaffWorkspace ? doc : nil;
        }
        if (block) block(doc, nil);
    }];
}

- (void)fetchAllStaff:(PPStaffListCompletion)completion {
    FIRQuery *query = [[self.db collectionWithPath:kPPStaffAuthUsersCollection]
        queryWhereField:@"status" isEqualTo:PPStaffStatusActive];

    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }

            NSMutableArray<PPStaffDoc *> *docs = [NSMutableArray array];
            for (FIRDocumentSnapshot *document in snapshot.documents) {
                PPStaffDoc *doc = [self pp_staffDocFromSnapshot:document];
                if (doc && doc.isActive) {
                    [docs addObject:doc];
                }
            }
            if (completion) completion(docs.copy, nil);
        });
    }];
}

- (id<FIRListenerRegistration>)listenAllStaff:(PPStaffListCompletion)block {
    FIRQuery *query = [self.db collectionWithPath:kPPStaffAuthUsersCollection];

    return [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (block) block(nil, error);
            return;
        }

        NSMutableArray<PPStaffDoc *> *docs = [NSMutableArray array];
        for (FIRDocumentSnapshot *document in snapshot.documents) {
            PPStaffDoc *doc = [self pp_staffDocFromSnapshot:document];
            if (doc) {
                [docs addObject:doc];
            }
        }
        if (block) block(docs.copy, nil);
    }];
}

- (void)checkCurrentUserIsStaff:(void(^)(BOOL isStaff, PPStaffDoc * _Nullable doc))completion {
    NSString *uid = [FIRAuth auth].currentUser.uid;
    if (!uid.length) {
        self.cachedCurrentStaff = nil;
        if (completion) completion(NO, nil);
        return;
    }

    [self fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable doc, NSError * _Nullable error) {
        (void)error;
        BOOL isStaff = doc.canAccessStaffWorkspace;
        self.cachedCurrentStaff = isStaff ? doc : nil;
        if (completion) completion(isStaff, doc);
    }];
}

- (void)refreshCurrentStaff:(PPStaffDocCompletion)completion {
    NSString *uid = [FIRAuth auth].currentUser.uid;
    if (!uid.length) {
        self.cachedCurrentStaff = nil;
        if (completion) completion(nil, nil);
        return;
    }

    [self fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable doc, NSError * _Nullable error) {
        self.cachedCurrentStaff = doc.canAccessStaffWorkspace ? doc : nil;
        if (completion) completion(doc, error);
    }];
}

#pragma mark - Legacy Role Mapping

+ (PPStaffRole)staffRoleFromLegacyRole:(NSInteger)legacyRole {
    switch (legacyRole) {
        case 8: return PPStaffRoleSuperAdmin;
        case 5: return PPStaffRoleSuperAdmin;
        case 2: return PPStaffRoleOwner;
        case 6:
        case 7: return PPStaffRoleInventoryManager;
        case 4: return PPStaffRoleOperationsManager;
        case 3: return PPStaffRoleSupportAgent;
        default: return PPStaffRoleViewer;
    }
}

+ (NSInteger)legacyRoleFromStaffRole:(PPStaffRole)staffRole {
    PPStaffRole normalizedRole = PPStaffNormalizedRole(staffRole);
    if ([normalizedRole isEqualToString:PPStaffRoleSuperAdmin])        return 8;
    if ([normalizedRole isEqualToString:PPStaffRoleOwner])             return 2;
    if ([normalizedRole isEqualToString:PPStaffRoleOperationsManager]) return 4;
    if ([normalizedRole isEqualToString:PPStaffRoleInventoryManager])  return 6;
    if ([normalizedRole isEqualToString:PPStaffRolePaymentsManager])   return 5;
    if ([normalizedRole isEqualToString:PPStaffRoleSupportAgent])      return 3;
    return 1;
}

+ (BOOL)isAdminRole:(PPStaffRole)role {
    return PPStaffIsAdminRole(role);
}

+ (NSArray<NSString *> *)defaultPermissionsForStaffRole:(PPStaffRole)role {
    return PPStaffDefaultPermissionsForRole(role);
}

+ (NSString *)localizedRoleName:(PPStaffRole)role {
    return PPStaffLocalizedRoleName(role);
}


@end
