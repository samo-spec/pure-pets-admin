//
//  PPStaffAuth.m
//  PurePetsAdmin
//
//  Staff authorization sourced from canonical `staff_users/{uid}`.
//

#import "PPStaffAuth.h"
#import <CoreFoundation/CoreFoundation.h>
@import Firebase;
@import FirebaseAuth;

#pragma mark - Staff Role Constants

PPStaffRole const PPStaffRoleSuperAdmin        = @"super_admin";
PPStaffRole const PPStaffRoleOwner             = @"owner";
PPStaffRole const PPStaffRoleOperationsManager = @"operations_manager";
PPStaffRole const PPStaffRoleBranchManager     = @"branch_manager";
PPStaffRole const PPStaffRoleInventoryManager  = @"inventory_manager";
PPStaffRole const PPStaffRoleAccountant        = @"accountant";
PPStaffRole const PPStaffRoleWarehouse         = @"warehouse";
PPStaffRole const PPStaffRoleSales             = @"sales";
PPStaffRole const PPStaffRolePaymentsManager   = @"payments_manager";
PPStaffRole const PPStaffRoleSupportAgent      = @"support_agent";
PPStaffRole const PPStaffRoleViewer            = @"viewer";

PPStaffStatus const PPStaffStatusActive   = @"active";
PPStaffStatus const PPStaffStatusDisabled = @"disabled";

static NSString * const kPPStaffAuthUsersCollection = @"staff_users";
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

NSString * const kStaffPermDeliveryView           = @"delivery.view";
NSString * const kStaffPermDeliveryDispatch       = @"delivery.dispatch";
NSString * const kStaffPermDeliveryAssign         = @"delivery.assign";
NSString * const kStaffPermDeliveryOverride       = @"delivery.override";
NSString * const kStaffPermDeliveryDriverView     = @"delivery.driver.view";
NSString * const kStaffPermDeliveryDriverManage   = @"delivery.driver.manage";
NSString * const kStaffPermDeliveryCarrierView    = @"delivery.carrier.view";
NSString * const kStaffPermDeliveryCarrierManage  = @"delivery.carrier.manage";
NSString * const kStaffPermDeliveryRouteView      = @"delivery.route.view";
NSString * const kStaffPermDeliveryRouteManage    = @"delivery.route.manage";
NSString * const kStaffPermDeliveryPODReview      = @"delivery.pod.review";
NSString * const kStaffPermDeliveryCODView        = @"delivery.cod.view";
NSString * const kStaffPermDeliveryCODReconcile   = @"delivery.cod.reconcile";
NSString * const kStaffPermDeliverySettingsManage = @"delivery.settings.manage";

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

NSString * const kStaffPermHotelView                  = @"hotel.view";
NSString * const kStaffPermHotelReservationsManage    = @"hotel.reservations.manage";
NSString * const kStaffPermHotelCheckIn               = @"hotel.checkin";
NSString * const kStaffPermHotelCheckOut              = @"hotel.checkout";
NSString * const kStaffPermHotelAccommodationsManage  = @"hotel.accommodations.manage";
NSString * const kStaffPermHotelCareView              = @"hotel.care.view";
NSString * const kStaffPermHotelCareManage            = @"hotel.care.manage";
NSString * const kStaffPermHotelTaskRead               = @"hotel.task.read";
NSString * const kStaffPermHotelTaskAssign             = @"hotel.task.assign";
NSString * const kStaffPermHotelTaskExecute            = @"hotel.task.execute";
NSString * const kStaffPermHotelMedicationRead         = @"hotel.medication.read";
NSString * const kStaffPermHotelMedicationManage       = @"hotel.medication.manage";
NSString * const kStaffPermHotelMedicationAdminister   = @"hotel.medication.administer";
NSString * const kStaffPermHotelHealthRead             = @"hotel.health.read";
NSString * const kStaffPermHotelHealthCreate           = @"hotel.health.create";
NSString * const kStaffPermHotelHealthManage           = @"hotel.health.manage";
NSString * const kStaffPermHotelIncidentsView          = @"hotel.incidents.view";
NSString * const kStaffPermHotelIncidentsManage        = @"hotel.incidents.manage";
NSString * const kStaffPermHotelServicesManage         = @"hotel.services.manage";
NSString * const kStaffPermHotelMediaView              = @"hotel.media.view";
NSString * const kStaffPermHotelMediaManage            = @"hotel.media.manage";
NSString * const kStaffPermHotelBillingView            = @"hotel.billing.view";
NSString * const kStaffPermHotelBillingManage          = @"hotel.billing.manage";
NSString * const kStaffPermHotelBillingAdjust          = @"hotel.billing.adjust";
NSString * const kStaffPermHotelTransportManage        = @"hotel.transport.manage";
NSString * const kStaffPermHotelNotificationsManage    = @"hotel.notifications.manage";
NSString * const kStaffPermHotelReportsView            = @"hotel.reports.view";
NSString * const kStaffPermHotelSettingsManage         = @"hotel.settings.manage";
NSString * const kStaffPermHotelOverride               = @"hotel.override";

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

static PPStaffRole PPStaffNormalizedRole(id value) {
    NSString *rawRole = PPStaffSafeString(value);
    if (rawRole.length == 0) {
        return PPStaffRoleViewer;
    }

    // Mirror infra's explicit legacy migration aliases; arbitrary role labels
    // must never become an elevated Admin role on the client.
    if ([rawRole isEqualToString:@"SuperAdmin"]) return PPStaffRoleSuperAdmin;
    if ([rawRole isEqualToString:@"Owner"]) return PPStaffRoleOwner;
    if ([rawRole isEqualToString:@"BranchManager"]) return PPStaffRoleBranchManager;
    if ([rawRole isEqualToString:@"Accountant"]) return PPStaffRoleAccountant;
    if ([rawRole isEqualToString:@"Warehouse"]) return PPStaffRoleWarehouse;
    if ([rawRole isEqualToString:@"Sales"]) return PPStaffRoleSales;
    if ([rawRole isEqualToString:@"InventoryManager"]) return PPStaffRoleInventoryManager;
    if ([rawRole isEqualToString:@"Staff"]) return PPStaffRoleViewer;
    if ([rawRole isEqualToString:@"Viewer"]) return PPStaffRoleViewer;

    NSMutableString *canonicalCandidate = [rawRole.lowercaseString mutableCopy];
    NSCharacterSet *allowedCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz_"];
    for (NSUInteger index = 0; index < canonicalCandidate.length; index++) {
        unichar character = [canonicalCandidate characterAtIndex:index];
        if (![allowedCharacters characterIsMember:character]) {
            [canonicalCandidate replaceCharactersInRange:NSMakeRange(index, 1) withString:@"_"];
        }
    }

    NSArray<NSString *> *knownRoles = @[
        PPStaffRoleSuperAdmin,
        PPStaffRoleOwner,
        PPStaffRoleOperationsManager,
        PPStaffRoleBranchManager,
        PPStaffRoleInventoryManager,
        PPStaffRoleAccountant,
        PPStaffRoleWarehouse,
        PPStaffRoleSales,
        PPStaffRolePaymentsManager,
        PPStaffRoleSupportAgent,
        PPStaffRoleViewer,
    ];
    if ([knownRoles containsObject:canonicalCandidate]) {
        return canonicalCandidate;
    }

    // Infra normalizes unknown/custom labels to viewer. Preserve that exact
    // fallback so role display, default permissions, and client IAM agree.
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
            kStaffPermDeliveryView, kStaffPermDeliveryDispatch, kStaffPermDeliveryAssign,
            kStaffPermDeliveryOverride,
            kStaffPermDeliveryDriverView, kStaffPermDeliveryDriverManage,
            kStaffPermDeliveryCarrierView, kStaffPermDeliveryCarrierManage,
            kStaffPermDeliveryRouteView, kStaffPermDeliveryRouteManage,
            kStaffPermDeliveryPODReview,
            kStaffPermDeliveryCODView, kStaffPermDeliveryCODReconcile,
            kStaffPermDeliverySettingsManage,
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
            kStaffPermHotelView, kStaffPermHotelReservationsManage,
            kStaffPermHotelCheckIn, kStaffPermHotelCheckOut,
            kStaffPermHotelAccommodationsManage,
            kStaffPermHotelCareView, kStaffPermHotelCareManage,
            kStaffPermHotelTaskRead, kStaffPermHotelTaskAssign, kStaffPermHotelTaskExecute,
            kStaffPermHotelMedicationRead, kStaffPermHotelMedicationManage, kStaffPermHotelMedicationAdminister,
            kStaffPermHotelHealthRead, kStaffPermHotelHealthCreate, kStaffPermHotelHealthManage,
            kStaffPermHotelIncidentsView, kStaffPermHotelIncidentsManage,
            kStaffPermHotelServicesManage,
            kStaffPermHotelMediaView, kStaffPermHotelMediaManage,
            kStaffPermHotelBillingView, kStaffPermHotelBillingManage, kStaffPermHotelBillingAdjust,
            kStaffPermHotelTransportManage, kStaffPermHotelNotificationsManage,
            kStaffPermHotelReportsView, kStaffPermHotelSettingsManage,
            kStaffPermHotelOverride,
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
            if ([permission hasSuffix:@".view"] &&
                ![permission isEqualToString:kStaffPermDeliveryCODView] &&
                ![permission isEqualToString:kStaffPermHotelIncidentsView] &&
                ![permission isEqualToString:kStaffPermHotelMediaView] &&
                ![permission isEqualToString:kStaffPermHotelBillingView] &&
                ![permission isEqualToString:kStaffPermHotelReportsView]) {
                [result addObject:permission];
            }
        }
        keys = result.copy;
    });
    return keys;
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
            if ([permission isEqualToString:kStaffPermDeliverySettingsManage]) continue;
            if ([permission isEqualToString:kStaffPermHotelMedicationAdminister]) continue;
            if ([permission isEqualToString:kStaffPermHotelBillingAdjust]) continue;
            if ([permission isEqualToString:kStaffPermHotelOverride]) continue;
            [permissions addObject:permission];
        }
        return permissions.copy;
    }

    if ([normalizedRole isEqualToString:PPStaffRoleBranchManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStockView, kStaffPermStockManage, kStaffPermStockCreate,
            kStaffPermPosView, kStaffPermPosSell, kStaffPermPosHistory,
            kStaffPermAccountingView,
            kStaffPermDeliveryView, kStaffPermDeliveryDispatch, kStaffPermDeliveryAssign,
            kStaffPermReportsView,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalizedRole isEqualToString:PPStaffRoleAccountant]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermAccountingView, kStaffPermAccountingManage,
            kStaffPermPaymentsView, kStaffPermPaymentsManage,
            kStaffPermDeliveryCODView, kStaffPermDeliveryCODReconcile,
            kStaffPermReportsView, kStaffPermReportsExport,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalizedRole isEqualToString:PPStaffRoleWarehouse]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStockView, kStaffPermStockManage, kStaffPermStockCreate,
            kStaffPermDeliveryView, kStaffPermDeliveryDispatch,
            kStaffPermCategoriesView,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalizedRole isEqualToString:PPStaffRoleSales]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermPosView, kStaffPermPosSell, kStaffPermPosHistory,
            kStaffPermStockView,
            kStaffPermNotificationsView,
        ];
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
            kStaffPermDeliveryCODView, kStaffPermDeliveryCODReconcile,
            kStaffPermAccountingView, kStaffPermAccountingManage,
            kStaffPermReportsView, kStaffPermReportsExport,
            kStaffPermPosView, kStaffPermPosSell, kStaffPermPosHistory,
            kStaffPermNotificationsView,
            kStaffPermHotelView,
            kStaffPermHotelBillingView, kStaffPermHotelBillingManage, kStaffPermHotelBillingAdjust,
            kStaffPermHotelReportsView,
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
            kStaffPermHotelView, kStaffPermHotelCareView,
        ];
    }

    return PPStaffViewOnlyPermissionKeys();
}

+ (NSString *)localizedRoleName:(PPStaffRole)role {
    PPStaffRole normalizedRole = PPStaffNormalizedRole(role);
    if ([normalizedRole isEqualToString:PPStaffRoleSuperAdmin])        return kLang(@"StaffRole_SuperAdmin");
    if ([normalizedRole isEqualToString:PPStaffRoleOwner])             return kLang(@"StaffRole_Owner");
    if ([normalizedRole isEqualToString:PPStaffRoleOperationsManager]) return kLang(@"StaffRole_OperationsManager");
    if ([normalizedRole isEqualToString:PPStaffRoleBranchManager])     return kLang(@"StaffRole_BranchManager");
    if ([normalizedRole isEqualToString:PPStaffRoleAccountant])        return kLang(@"StaffRole_Accountant");
    if ([normalizedRole isEqualToString:PPStaffRoleWarehouse])         return kLang(@"StaffRole_Warehouse");
    if ([normalizedRole isEqualToString:PPStaffRoleSales])             return kLang(@"StaffRole_Sales");
    if ([normalizedRole isEqualToString:PPStaffRoleInventoryManager])  return kLang(@"StaffRole_InventoryManager");
    if ([normalizedRole isEqualToString:PPStaffRolePaymentsManager])   return kLang(@"StaffRole_PaymentsManager");
    if ([normalizedRole isEqualToString:PPStaffRoleSupportAgent])      return kLang(@"StaffRole_SupportAgent");
    if ([normalizedRole isEqualToString:PPStaffRoleViewer])            return kLang(@"StaffRole_Viewer");
    return normalizedRole ?: @"";
}

@end
