//
//  PPStaffAuth.m
//  PurePetsAdmin
//
//  Staff authorization sourced from `UsersCol/{uid}`.
//

#import "PPStaffAuth.h"
@import Firebase;
@import FirebaseAuth;

#pragma mark - Staff Role Constants

PPStaffRole const PPStaffRoleSuperAdmin        = @"super_admin";
PPStaffRole const PPStaffRoleOwner             = @"owner";
PPStaffRole const PPStaffRoleOperationsManager = @"operations_manager";
PPStaffRole const PPStaffRoleInventoryManager  = @"inventory_manager";
PPStaffRole const PPStaffRolePaymentsManager   = @"payments_manager";
PPStaffRole const PPStaffRoleSupportAgent      = @"support_agent";
PPStaffRole const PPStaffRoleViewer            = @"viewer";

PPStaffStatus const PPStaffStatusActive   = @"active";
PPStaffStatus const PPStaffStatusDisabled = @"disabled";

static NSString * const kPPStaffAuthUsersCollection = @"UsersCol";
static NSString * const kPPStaffAuthAccountTypeStaff = @"staff";

#pragma mark - Permission Key Constants

NSString * const kStaffPermDashboardView = @"dashboard.view";

NSString * const kStaffPermStaffView   = @"staff.view";
NSString * const kStaffPermStaffManage = @"staff.manage";

NSString * const kStaffPermUsersView                 = @"users.view";
NSString * const kStaffPermUsersManage               = @"users.manage";
NSString * const kStaffPermUsersBlock                = @"users.block";
NSString * const kStaffPermUsersFeaturesView         = @"users.features.view";
NSString * const kStaffPermUsersFeaturesManage       = @"users.features.manage";
NSString * const kStaffPermUsersSubscriptionsView    = @"users.subscriptions.view";
NSString * const kStaffPermUsersSubscriptionsManage  = @"users.subscriptions.manage";
NSString * const kStaffPermUsersRestrictionsView     = @"users.restrictions.view";
NSString * const kStaffPermUsersRestrictionsManage   = @"users.restrictions.manage";

NSString * const kStaffPermStockView   = @"stock.view";
NSString * const kStaffPermStockManage = @"stock.manage";
NSString * const kStaffPermStockCreate = @"stock.create";
NSString * const kStaffPermStockDelete = @"stock.delete";

NSString * const kStaffPermListingsView     = @"listings.view";
NSString * const kStaffPermListingsManage   = @"listings.manage";
NSString * const kStaffPermListingsModerate = @"listings.moderate";

NSString * const kStaffPermPaymentsView   = @"payments.view";
NSString * const kStaffPermPaymentsManage = @"payments.manage";
NSString * const kStaffPermPaymentsRefund = @"payments.refund";

NSString * const kStaffPermPosView    = @"pos.view";
NSString * const kStaffPermPosSell    = @"pos.sell";
NSString * const kStaffPermPosHistory = @"pos.history";

NSString * const kStaffPermBranchesView   = @"branches.view";
NSString * const kStaffPermBranchesManage = @"branches.manage";

NSString * const kStaffPermAgentsView   = @"agents.view";
NSString * const kStaffPermAgentsManage = @"agents.manage";

NSString * const kStaffPermSupportView   = @"support.view";
NSString * const kStaffPermSupportManage = @"support.manage";

NSString * const kStaffPermServicesView   = @"services.view";
NSString * const kStaffPermServicesManage = @"services.manage";

NSString * const kStaffPermProvidersView   = @"providers.view";
NSString * const kStaffPermProvidersManage = @"providers.manage";

NSString * const kStaffPermSettingsView   = @"settings.view";
NSString * const kStaffPermSettingsManage = @"settings.manage";

NSString * const kStaffPermNotificationsView = @"notifications.view";
NSString * const kStaffPermNotificationsSend = @"notifications.send";

NSString * const kStaffPermAccountingView   = @"accounting.view";
NSString * const kStaffPermAccountingManage = @"accounting.manage";

NSString * const kStaffPermReportsView   = @"reports.view";
NSString * const kStaffPermReportsExport = @"reports.export";

NSString * const kStaffPermAuditView = @"audit.view";

NSString * const kStaffPermModerationView   = @"moderation.view";
NSString * const kStaffPermModerationManage = @"moderation.manage";

NSString * const kStaffPermBannersView   = @"banners.view";
NSString * const kStaffPermBannersManage = @"banners.manage";

NSString * const kStaffPermCategoriesView   = @"categories.view";
NSString * const kStaffPermCategoriesManage = @"categories.manage";

NSString * const kStaffPermVeterinariansView   = @"veterinarians.view";
NSString * const kStaffPermVeterinariansManage = @"veterinarians.manage";

static NSString *PPStaffSafeString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:NSNumber.class]) {
        return [[(NSNumber *)value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return @"";
}

static NSString *PPStaffLowercaseString(id value) {
    return [PPStaffSafeString(value).lowercaseString copy];
}

static NSDictionary *PPStaffSafeDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : @{};
}

static NSArray<NSString *> *PPStaffUniqueStrings(id value) {
    NSMutableOrderedSet<NSString *> *ordered = [NSMutableOrderedSet orderedSet];

    if ([value isKindOfClass:NSArray.class]) {
        for (id entry in (NSArray *)value) {
            NSString *normalized = PPStaffSafeString(entry);
            if (normalized.length > 0) {
                [ordered addObject:normalized];
            }
        }
        return ordered.array ?: @[];
    }

    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary *dictionary = (NSDictionary *)value;
        for (id rawKey in dictionary) {
            NSString *permission = PPStaffSafeString(rawKey);
            if (permission.length == 0) {
                continue;
            }

            id rawAllowed = dictionary[rawKey];
            BOOL allowed = NO;
            if ([rawAllowed isKindOfClass:NSDictionary.class]) {
                allowed = [rawAllowed[@"allowed"] respondsToSelector:@selector(boolValue)] ? [rawAllowed[@"allowed"] boolValue] : NO;
            } else if ([rawAllowed respondsToSelector:@selector(boolValue)]) {
                allowed = [rawAllowed boolValue];
            }

            if (allowed) {
                [ordered addObject:permission];
            }
        }
    }

    return ordered.array ?: @[];
}

static NSArray<NSString *> *PPStaffConsolePermissionKeys(id value) {
    NSMutableArray<NSString *> *consolePermissions = [NSMutableArray array];
    for (NSString *permission in PPStaffUniqueStrings(value)) {
        if ([permission containsString:@"."]) {
            [consolePermissions addObject:permission];
        }
    }
    return consolePermissions.copy;
}

static PPStaffRole PPStaffNormalizedRole(id value) {
    NSString *role = PPStaffLowercaseString(value);
    if (role.length == 0) {
        return PPStaffRoleViewer;
    }

    if ([role isEqualToString:PPStaffRoleSuperAdmin] ||
        [role isEqualToString:@"superadmin"] ||
        [role isEqualToString:@"super admin"] ||
        [role isEqualToString:@"admin"]) {
        return PPStaffRoleSuperAdmin;
    }

    if ([role isEqualToString:PPStaffRoleOwner]) {
        return PPStaffRoleOwner;
    }

    if ([role isEqualToString:PPStaffRoleOperationsManager] ||
        [role isEqualToString:@"operationsmanager"] ||
        [role isEqualToString:@"operations manager"] ||
        [role isEqualToString:@"moderator"]) {
        return PPStaffRoleOperationsManager;
    }

    if ([role isEqualToString:PPStaffRoleInventoryManager] ||
        [role isEqualToString:@"inventorymanager"] ||
        [role isEqualToString:@"inventory manager"] ||
        [role isEqualToString:@"storemanager"] ||
        [role isEqualToString:@"store manager"]) {
        return PPStaffRoleInventoryManager;
    }

    if ([role isEqualToString:PPStaffRolePaymentsManager] ||
        [role isEqualToString:@"paymentsmanager"] ||
        [role isEqualToString:@"payments manager"] ||
        [role isEqualToString:@"accountant"]) {
        return PPStaffRolePaymentsManager;
    }

    if ([role isEqualToString:PPStaffRoleSupportAgent] ||
        [role isEqualToString:@"supportagent"] ||
        [role isEqualToString:@"support agent"] ||
        [role isEqualToString:@"staff"] ||
        [role isEqualToString:@"vet"]) {
        return PPStaffRoleSupportAgent;
    }

    if ([role isEqualToString:PPStaffRoleViewer] ||
        [role isEqualToString:@"user"]) {
        return PPStaffRoleViewer;
    }

    return PPStaffRoleViewer;
}

static NSArray<NSString *> *PPStaffAllPermissionKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            kStaffPermDashboardView,
            kStaffPermStaffView, kStaffPermStaffManage,
            kStaffPermUsersView, kStaffPermUsersManage, kStaffPermUsersBlock,
            kStaffPermUsersFeaturesView, kStaffPermUsersFeaturesManage,
            kStaffPermUsersSubscriptionsView, kStaffPermUsersSubscriptionsManage,
            kStaffPermUsersRestrictionsView, kStaffPermUsersRestrictionsManage,
            kStaffPermStockView, kStaffPermStockManage, kStaffPermStockCreate, kStaffPermStockDelete,
            kStaffPermListingsView, kStaffPermListingsManage, kStaffPermListingsModerate,
            kStaffPermPaymentsView, kStaffPermPaymentsManage, kStaffPermPaymentsRefund,
            kStaffPermPosView, kStaffPermPosSell, kStaffPermPosHistory,
            kStaffPermBranchesView, kStaffPermBranchesManage,
            kStaffPermAgentsView, kStaffPermAgentsManage,
            kStaffPermSupportView, kStaffPermSupportManage,
            kStaffPermServicesView, kStaffPermServicesManage,
            kStaffPermProvidersView, kStaffPermProvidersManage,
            kStaffPermSettingsView, kStaffPermSettingsManage,
            kStaffPermNotificationsView, kStaffPermNotificationsSend,
            kStaffPermAccountingView, kStaffPermAccountingManage,
            kStaffPermReportsView, kStaffPermReportsExport,
            kStaffPermAuditView,
            kStaffPermModerationView, kStaffPermModerationManage,
            kStaffPermBannersView, kStaffPermBannersManage,
            kStaffPermCategoriesView, kStaffPermCategoriesManage,
            kStaffPermVeterinariansView, kStaffPermVeterinariansManage,
        ];
    });
    return keys;
}

static NSArray<NSString *> *PPStaffViewOnlyPermissionKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSString *> *result = [NSMutableArray array];
        for (NSString *permission in PPStaffAllPermissionKeys()) {
            if ([permission hasSuffix:@".view"]) {
                [result addObject:permission];
            }
        }
        keys = result.copy;
    });
    return keys;
}

static NSArray<NSString *> *PPStaffResolvedPermissions(NSDictionary *root,
                                                       NSDictionary *staffProfile,
                                                       PPStaffRole role) {
    NSArray<NSString *> *explicitPermissions = PPStaffConsolePermissionKeys(staffProfile[@"permissions"]);
    if (explicitPermissions.count == 0) {
        explicitPermissions = PPStaffConsolePermissionKeys(root[@"permissions"]);
    }

    NSArray<NSString *> *permissions = explicitPermissions.count > 0
        ? explicitPermissions
        : [PPStaffAuth defaultPermissionsForStaffRole:role];

    NSMutableOrderedSet<NSString *> *normalized = [NSMutableOrderedSet orderedSetWithArray:permissions];
    if (![normalized containsObject:kStaffPermDashboardView]) {
        [normalized addObject:kStaffPermDashboardView];
    }
    return normalized.array ?: @[];
}

#pragma mark - PPStaffDoc

@implementation PPStaffDoc

- (instancetype)initWithDictionary:(NSDictionary *)dict uid:(NSString *)uid {
    if ((self = [super init])) {
        NSDictionary *root = PPStaffSafeDictionary(dict);
        NSDictionary *staffProfile = PPStaffSafeDictionary(root[@"staffProfile"]);

        NSString *resolvedRoleValue = PPStaffSafeString(staffProfile[@"role"]);
        if (resolvedRoleValue.length == 0) resolvedRoleValue = PPStaffSafeString(root[@"staffRole"]);
        if (resolvedRoleValue.length == 0) resolvedRoleValue = PPStaffSafeString(root[@"roleName"]);
        if (resolvedRoleValue.length == 0) resolvedRoleValue = PPStaffSafeString(root[@"role"]);

        NSString *statusValue = PPStaffLowercaseString(staffProfile[@"status"]);
        if (statusValue.length == 0) statusValue = PPStaffLowercaseString(root[@"status"]);

        _uid = PPStaffSafeString(uid);
        _accountType = PPStaffLowercaseString(root[@"accountType"]);
        _role = PPStaffNormalizedRole(resolvedRoleValue);
        _status = [statusValue isEqualToString:PPStaffStatusDisabled] ? PPStaffStatusDisabled : PPStaffStatusActive;
        _permissions = PPStaffResolvedPermissions(root, staffProfile, _role);
        _scope = PPStaffSafeDictionary(staffProfile[@"scope"]).count > 0 ? PPStaffSafeDictionary(staffProfile[@"scope"]) : PPStaffSafeDictionary(root[@"scope"]);

        NSNumber *claimsVersion = [staffProfile[@"claimsVersion"] isKindOfClass:NSNumber.class]
            ? staffProfile[@"claimsVersion"]
            : ([root[@"claimsVersion"] isKindOfClass:NSNumber.class] ? root[@"claimsVersion"] : nil);
        _claimsVersion = claimsVersion.integerValue;

        NSString *updatedBy = PPStaffSafeString(staffProfile[@"updatedBy"]);
        if (updatedBy.length == 0) updatedBy = PPStaffSafeString(root[@"updatedBy"]);
        _updatedBy = updatedBy.length > 0 ? updatedBy : nil;
    }
    return self;
}

- (BOOL)isActive {
    return [self.accountType isEqualToString:kPPStaffAuthAccountTypeStaff] &&
           ![self.status isEqualToString:PPStaffStatusDisabled];
}

- (BOOL)isAdmin {
    return [PPStaffAuth isAdminRole:self.role] && self.isActive;
}

- (BOOL)canAccessStaffWorkspace {
    return self.isActive && [self hasPermission:kStaffPermDashboardView];
}

- (BOOL)hasPermission:(NSString *)perm {
    if (!perm.length || !self.isActive) return NO;
    if (self.isAdmin) return YES;
    return [self.permissions containsObject:perm];
}

- (BOOL)hasAnyPermission:(NSArray<NSString *> *)perms {
    if (!self.isActive) return NO;
    if (self.isAdmin) return YES;
    for (NSString *permission in perms) {
        if ([self.permissions containsObject:permission]) {
            return YES;
        }
    }
    return NO;
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

    PPStaffDoc *doc = [[PPStaffDoc alloc] initWithDictionary:snapshot.data ?: @{} uid:snapshot.documentID ?: @""];
    return doc.isActive || [doc.accountType isEqualToString:kPPStaffAuthAccountTypeStaff] ? doc : nil;
}

- (void)fetchStaffDoc:(NSString *)uid completion:(PPStaffDocCompletion)completion {
    if (!uid.length) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"PPStaffAuth"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing uid"}]);
        }
        return;
    }

    [[self staffDoc:uid] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }
            if (completion) completion([self pp_staffDocFromSnapshot:snapshot], nil);
        });
    }];
}

- (id<FIRListenerRegistration>)listenStaffDoc:(NSString *)uid onChange:(PPStaffDocCompletion)block {
    if (!uid.length) {
        if (block) {
            block(nil, [NSError errorWithDomain:@"PPStaffAuth"
                                           code:2
                                       userInfo:@{NSLocalizedDescriptionKey: @"Missing uid"}]);
        }
        return nil;
    }

    return [[self staffDoc:uid] addSnapshotListener:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (block) block(nil, error);
            return;
        }
        if (block) block([self pp_staffDocFromSnapshot:snapshot], nil);
    }];
}

- (void)fetchAllStaff:(PPStaffListCompletion)completion {
    FIRQuery *query = [[self.db collectionWithPath:kPPStaffAuthUsersCollection]
        queryWhereField:@"accountType" isEqualTo:kPPStaffAuthAccountTypeStaff];

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
    FIRQuery *query = [[self.db collectionWithPath:kPPStaffAuthUsersCollection]
        queryWhereField:@"accountType" isEqualTo:kPPStaffAuthAccountTypeStaff];

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
    PPStaffRole normalizedRole = PPStaffNormalizedRole(role);
    return [normalizedRole isEqualToString:PPStaffRoleSuperAdmin] ||
           [normalizedRole isEqualToString:PPStaffRoleOwner];
}

+ (NSArray<NSString *> *)defaultPermissionsForStaffRole:(PPStaffRole)role {
    PPStaffRole normalizedRole = PPStaffNormalizedRole(role);

    if ([normalizedRole isEqualToString:PPStaffRoleSuperAdmin] ||
        [normalizedRole isEqualToString:PPStaffRoleOwner]) {
        return PPStaffAllPermissionKeys();
    }

    if ([normalizedRole isEqualToString:PPStaffRoleOperationsManager]) {
        NSMutableArray<NSString *> *permissions = [NSMutableArray array];
        for (NSString *permission in PPStaffAllPermissionKeys()) {
            if ([permission hasPrefix:@"staff."]) continue;
            if ([permission isEqualToString:kStaffPermAuditView]) continue;
            [permissions addObject:permission];
        }
        return permissions.copy;
    }

    if ([normalizedRole isEqualToString:PPStaffRoleInventoryManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStockView, kStaffPermStockManage, kStaffPermStockCreate, kStaffPermStockDelete,
            kStaffPermCategoriesView, kStaffPermCategoriesManage,
            kStaffPermReportsView,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalizedRole isEqualToString:PPStaffRolePaymentsManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermPaymentsView, kStaffPermPaymentsManage, kStaffPermPaymentsRefund,
            kStaffPermAccountingView, kStaffPermAccountingManage,
            kStaffPermReportsView, kStaffPermReportsExport,
            kStaffPermPosView, kStaffPermPosSell, kStaffPermPosHistory,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalizedRole isEqualToString:PPStaffRoleSupportAgent]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermSupportView, kStaffPermSupportManage,
            kStaffPermUsersView,
            kStaffPermUsersFeaturesView,
            kStaffPermUsersRestrictionsView,
            kStaffPermNotificationsView,
        ];
    }

    return PPStaffViewOnlyPermissionKeys();
}

+ (NSString *)localizedRoleName:(PPStaffRole)role {
    PPStaffRole normalizedRole = PPStaffNormalizedRole(role);
    if ([normalizedRole isEqualToString:PPStaffRoleSuperAdmin])        return kLang(@"StaffRole_SuperAdmin");
    if ([normalizedRole isEqualToString:PPStaffRoleOwner])             return kLang(@"StaffRole_Owner");
    if ([normalizedRole isEqualToString:PPStaffRoleOperationsManager]) return kLang(@"StaffRole_OperationsManager");
    if ([normalizedRole isEqualToString:PPStaffRoleInventoryManager])  return kLang(@"StaffRole_InventoryManager");
    if ([normalizedRole isEqualToString:PPStaffRolePaymentsManager])   return kLang(@"StaffRole_PaymentsManager");
    if ([normalizedRole isEqualToString:PPStaffRoleSupportAgent])      return kLang(@"StaffRole_SupportAgent");
    if ([normalizedRole isEqualToString:PPStaffRoleViewer])            return kLang(@"StaffRole_Viewer");
    return normalizedRole ?: @"";
}

@end
