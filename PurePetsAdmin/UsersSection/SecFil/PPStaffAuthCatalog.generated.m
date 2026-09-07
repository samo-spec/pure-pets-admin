//
//  PPStaffAuthCatalog.generated.m
//  PurePetsAdmin
//
//  AUTO-GENERATED from Pure Pets Infra/iam/policy-catalog.json — DO NOT EDIT DIRECTLY.
//

#import "PPStaffAuthCatalog.generated.h"

NSString * const PPStaffIAMPolicyVersion = @"2.0.0-draft.1";
NSString * const PPStaffIAMSchemaVersion = @"2.0.0";
NSString * const PPStaffIAMPolicySHA256 = @"9bc50f132f50ba66aece07207ec74236625ccb9be353e15f8cb770088fa5678a";

#pragma mark - Role Definitions

PPStaffRole const PPStaffRoleSuperAdmin = @"super_admin";
PPStaffRole const PPStaffRoleOwner = @"owner";
PPStaffRole const PPStaffRoleOperationsManager = @"operations_manager";
PPStaffRole const PPStaffRoleBranchManager = @"branch_manager";
PPStaffRole const PPStaffRoleInventoryManager = @"inventory_manager";
PPStaffRole const PPStaffRoleAccountant = @"accountant";
PPStaffRole const PPStaffRoleWarehouse = @"warehouse";
PPStaffRole const PPStaffRoleSales = @"sales";
PPStaffRole const PPStaffRolePaymentsManager = @"payments_manager";
PPStaffRole const PPStaffRoleSupportAgent = @"support_agent";
PPStaffRole const PPStaffRoleContentEditor = @"content_editor";
PPStaffRole const PPStaffRoleContentPublisher = @"content_publisher";
PPStaffRole const PPStaffRoleViewer = @"viewer";
PPStaffRole const PPStaffRoleSecurityAdmin = @"security_admin";
PPStaffRole const PPStaffRoleComplianceAuditor = @"compliance_auditor";

#pragma mark - Permission Key Definitions

NSString * const kStaffPermDashboardView = @"dashboard.view";
NSString * const kStaffPermNovaView = @"nova.view";
NSString * const kStaffPermStaffView = @"staff.view";
NSString * const kStaffPermStaffManage = @"staff.manage";
NSString * const kStaffPermUsersView = @"users.view";
NSString * const kStaffPermUsersManage = @"users.manage";
NSString * const kStaffPermUsersBlock = @"users.block";
NSString * const kStaffPermUsersFeaturesView = @"users.features.view";
NSString * const kStaffPermUsersFeaturesManage = @"users.features.manage";
NSString * const kStaffPermUsersSubscriptionsView = @"users.subscriptions.view";
NSString * const kStaffPermUsersSubscriptionsManage = @"users.subscriptions.manage";
NSString * const kStaffPermUsersRestrictionsView = @"users.restrictions.view";
NSString * const kStaffPermUsersRestrictionsManage = @"users.restrictions.manage";
NSString * const kStaffPermStockView = @"stock.view";
NSString * const kStaffPermStockCostView = @"stock.cost.view";
NSString * const kStaffPermStockManage = @"stock.manage";
NSString * const kStaffPermStockQuarantineRelease = @"stock.quarantine.release";
NSString * const kStaffPermStockCreate = @"stock.create";
NSString * const kStaffPermStockDelete = @"stock.delete";
NSString * const kStaffPermListingsView = @"listings.view";
NSString * const kStaffPermListingsManage = @"listings.manage";
NSString * const kStaffPermListingsModerate = @"listings.moderate";
NSString * const kStaffPermPaymentsView = @"payments.view";
NSString * const kStaffPermPaymentsManage = @"payments.manage";
NSString * const kStaffPermPaymentsRefund = @"payments.refund";
NSString * const kStaffPermDeliveryView = @"delivery.view";
NSString * const kStaffPermDeliveryDispatch = @"delivery.dispatch";
NSString * const kStaffPermDeliveryAssign = @"delivery.assign";
NSString * const kStaffPermDeliveryOverride = @"delivery.override";
NSString * const kStaffPermDeliveryDriverView = @"delivery.driver.view";
NSString * const kStaffPermDeliveryDriverManage = @"delivery.driver.manage";
NSString * const kStaffPermDeliveryCarrierView = @"delivery.carrier.view";
NSString * const kStaffPermDeliveryCarrierManage = @"delivery.carrier.manage";
NSString * const kStaffPermDeliveryRouteView = @"delivery.route.view";
NSString * const kStaffPermDeliveryRouteManage = @"delivery.route.manage";
NSString * const kStaffPermDeliveryPODReview = @"delivery.pod.review";
NSString * const kStaffPermDeliveryCODView = @"delivery.cod.view";
NSString * const kStaffPermDeliveryCODReconcile = @"delivery.cod.reconcile";
NSString * const kStaffPermDeliverySettingsManage = @"delivery.settings.manage";
NSString * const kStaffPermPosView = @"pos.view";
NSString * const kStaffPermPosSell = @"pos.sell";
NSString * const kStaffPermPosHistory = @"pos.history";
NSString * const kStaffPermBranchesView = @"branches.view";
NSString * const kStaffPermBranchesManage = @"branches.manage";
NSString * const kStaffPermAgentsView = @"agents.view";
NSString * const kStaffPermAgentsManage = @"agents.manage";
NSString * const kStaffPermSupportView = @"support.view";
NSString * const kStaffPermSupportManage = @"support.manage";
NSString * const kStaffPermServicesView = @"services.view";
NSString * const kStaffPermServicesManage = @"services.manage";
NSString * const kStaffPermProvidersView = @"providers.view";
NSString * const kStaffPermProvidersManage = @"providers.manage";
NSString * const kStaffPermSettingsView = @"settings.view";
NSString * const kStaffPermSettingsManage = @"settings.manage";
NSString * const kStaffPermNotificationsView = @"notifications.view";
NSString * const kStaffPermNotificationsInboxView = @"notifications.inbox.view";
NSString * const kStaffPermNotificationsSend = @"notifications.send";
NSString * const kStaffPermAccountingView = @"accounting.view";
NSString * const kStaffPermAccountingManage = @"accounting.manage";
NSString * const kStaffPermAccountingDocumentCreate = @"accounting.document.create";
NSString * const kStaffPermAccountingDocumentEditDraft = @"accounting.document.edit_draft";
NSString * const kStaffPermAccountingApprove = @"accounting.approve";
NSString * const kStaffPermAccountingPaymentRecord = @"accounting.payment.record";
NSString * const kStaffPermAccountingTransfer = @"accounting.transfer";
NSString * const kStaffPermAccountingVoid = @"accounting.void";
NSString * const kStaffPermAccountingAttachmentsManage = @"accounting.attachments.manage";
NSString * const kStaffPermAccountingAccountsManage = @"accounting.accounts.manage";
NSString * const kStaffPermAccountingCategoriesManage = @"accounting.categories.manage";
NSString * const kStaffPermAccountingSettingsManage = @"accounting.settings.manage";
NSString * const kStaffPermAccountingReconcile = @"accounting.reconcile";
NSString * const kStaffPermAccountingExport = @"accounting.export";
NSString * const kStaffPermAccountingPeriodView = @"accounting.period.view";
NSString * const kStaffPermAccountingPeriodClose = @"accounting.period.close";
NSString * const kStaffPermAccountingPeriodReopen = @"accounting.period.reopen";
NSString * const kStaffPermReportsView = @"reports.view";
NSString * const kStaffPermReportsExport = @"reports.export";
NSString * const kStaffPermAuditView = @"audit.view";
NSString * const kStaffPermModerationView = @"moderation.view";
NSString * const kStaffPermModerationManage = @"moderation.manage";
NSString * const kStaffPermCampaignsView = @"campaigns.view";
NSString * const kStaffPermCampaignsEdit = @"campaigns.edit";
NSString * const kStaffPermCampaignsPublish = @"campaigns.publish";
NSString * const kStaffPermCampaignsSettings = @"campaigns.settings";
NSString * const kStaffPermCategoriesView = @"categories.view";
NSString * const kStaffPermCategoriesManage = @"categories.manage";
NSString * const kStaffPermVeterinariansView = @"veterinarians.view";
NSString * const kStaffPermVeterinariansManage = @"veterinarians.manage";
NSString * const kStaffPermHomeControlView = @"home_control.view";
NSString * const kStaffPermHomeControlManage = @"home_control.manage";
NSString * const kStaffPermHotelView = @"hotel.view";
NSString * const kStaffPermHotelReservationsManage = @"hotel.reservations.manage";
NSString * const kStaffPermHotelCheckIn = @"hotel.checkin";
NSString * const kStaffPermHotelCheckOut = @"hotel.checkout";
NSString * const kStaffPermHotelAccommodationsManage = @"hotel.accommodations.manage";
NSString * const kStaffPermHotelCareView = @"hotel.care.view";
NSString * const kStaffPermHotelCareManage = @"hotel.care.manage";
NSString * const kStaffPermHotelTaskRead = @"hotel.task.read";
NSString * const kStaffPermHotelTaskAssign = @"hotel.task.assign";
NSString * const kStaffPermHotelTaskExecute = @"hotel.task.execute";
NSString * const kStaffPermHotelMedicationRead = @"hotel.medication.read";
NSString * const kStaffPermHotelMedicationManage = @"hotel.medication.manage";
NSString * const kStaffPermHotelMedicationAdminister = @"hotel.medication.administer";
NSString * const kStaffPermHotelHealthRead = @"hotel.health.read";
NSString * const kStaffPermHotelHealthCreate = @"hotel.health.create";
NSString * const kStaffPermHotelHealthManage = @"hotel.health.manage";
NSString * const kStaffPermHotelIncidentsView = @"hotel.incidents.view";
NSString * const kStaffPermHotelIncidentsManage = @"hotel.incidents.manage";
NSString * const kStaffPermHotelServicesManage = @"hotel.services.manage";
NSString * const kStaffPermHotelMediaView = @"hotel.media.view";
NSString * const kStaffPermHotelMediaManage = @"hotel.media.manage";
NSString * const kStaffPermHotelBillingView = @"hotel.billing.view";
NSString * const kStaffPermHotelBillingManage = @"hotel.billing.manage";
NSString * const kStaffPermHotelBillingAdjust = @"hotel.billing.adjust";
NSString * const kStaffPermHotelTransportManage = @"hotel.transport.manage";
NSString * const kStaffPermHotelNotificationsManage = @"hotel.notifications.manage";
NSString * const kStaffPermHotelReportsView = @"hotel.reports.view";
NSString * const kStaffPermHotelSettingsManage = @"hotel.settings.manage";
NSString * const kStaffPermHotelOverride = @"hotel.override";
NSString * const kStaffPermBannersView = @"banners.view";
NSString * const kStaffPermBannersManage = @"banners.manage";
NSString * const kStaffPermIamStaffRead = @"iam.staff.read";
NSString * const kStaffPermIamStaffCreate = @"iam.staff.create";
NSString * const kStaffPermIamStaffUpdate = @"iam.staff.update";
NSString * const kStaffPermIamStaffDisable = @"iam.staff.disable";
NSString * const kStaffPermIamRoleRead = @"iam.role.read";
NSString * const kStaffPermIamRoleCreate = @"iam.role.create";
NSString * const kStaffPermIamRoleUpdate = @"iam.role.update";
NSString * const kStaffPermIamRoleDelete = @"iam.role.delete";
NSString * const kStaffPermIamBindingRead = @"iam.binding.read";
NSString * const kStaffPermIamBindingGrant = @"iam.binding.grant";
NSString * const kStaffPermIamBindingRevoke = @"iam.binding.revoke";
NSString * const kStaffPermIamElevationRequest = @"iam.elevation.request";
NSString * const kStaffPermIamElevationApprove = @"iam.elevation.approve";
NSString * const kStaffPermIamElevationRevoke = @"iam.elevation.revoke";
NSString * const kStaffPermIamProjectionReconcile = @"iam.projection.reconcile";
NSString * const kStaffPermIamPolicyRead = @"iam.policy.read";
NSString * const kStaffPermIamPolicyUpdate = @"iam.policy.update";
NSString * const kStaffPermIamRootAssign = @"iam.root.assign";

#pragma mark - Catalog Accessor Implementations

NSArray<PPStaffRole> * PPStaffAllRoleKeys(void) {
    static NSArray<PPStaffRole> *roles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        roles = @[
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
            PPStaffRoleContentEditor,
            PPStaffRoleContentPublisher,
            PPStaffRoleViewer,
            PPStaffRoleSecurityAdmin,
            PPStaffRoleComplianceAuditor,
        ];
    });
    return roles;
}

NSArray<NSString *> * PPStaffAllPermissionKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            kStaffPermDashboardView,
            kStaffPermNovaView,
            kStaffPermStaffView,
            kStaffPermStaffManage,
            kStaffPermUsersView,
            kStaffPermUsersManage,
            kStaffPermUsersBlock,
            kStaffPermUsersFeaturesView,
            kStaffPermUsersFeaturesManage,
            kStaffPermUsersSubscriptionsView,
            kStaffPermUsersSubscriptionsManage,
            kStaffPermUsersRestrictionsView,
            kStaffPermUsersRestrictionsManage,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermStockManage,
            kStaffPermStockQuarantineRelease,
            kStaffPermStockCreate,
            kStaffPermStockDelete,
            kStaffPermListingsView,
            kStaffPermListingsManage,
            kStaffPermListingsModerate,
            kStaffPermPaymentsView,
            kStaffPermPaymentsManage,
            kStaffPermPaymentsRefund,
            kStaffPermDeliveryView,
            kStaffPermDeliveryDispatch,
            kStaffPermDeliveryAssign,
            kStaffPermDeliveryOverride,
            kStaffPermDeliveryDriverView,
            kStaffPermDeliveryDriverManage,
            kStaffPermDeliveryCarrierView,
            kStaffPermDeliveryCarrierManage,
            kStaffPermDeliveryRouteView,
            kStaffPermDeliveryRouteManage,
            kStaffPermDeliveryPODReview,
            kStaffPermDeliveryCODView,
            kStaffPermDeliveryCODReconcile,
            kStaffPermDeliverySettingsManage,
            kStaffPermPosView,
            kStaffPermPosSell,
            kStaffPermPosHistory,
            kStaffPermBranchesView,
            kStaffPermBranchesManage,
            kStaffPermAgentsView,
            kStaffPermAgentsManage,
            kStaffPermSupportView,
            kStaffPermSupportManage,
            kStaffPermServicesView,
            kStaffPermServicesManage,
            kStaffPermProvidersView,
            kStaffPermProvidersManage,
            kStaffPermSettingsView,
            kStaffPermSettingsManage,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
            kStaffPermNotificationsSend,
            kStaffPermAccountingView,
            kStaffPermAccountingManage,
            kStaffPermAccountingDocumentCreate,
            kStaffPermAccountingDocumentEditDraft,
            kStaffPermAccountingApprove,
            kStaffPermAccountingPaymentRecord,
            kStaffPermAccountingTransfer,
            kStaffPermAccountingVoid,
            kStaffPermAccountingAttachmentsManage,
            kStaffPermAccountingAccountsManage,
            kStaffPermAccountingCategoriesManage,
            kStaffPermAccountingSettingsManage,
            kStaffPermAccountingReconcile,
            kStaffPermAccountingExport,
            kStaffPermAccountingPeriodView,
            kStaffPermAccountingPeriodClose,
            kStaffPermAccountingPeriodReopen,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermAuditView,
            kStaffPermModerationView,
            kStaffPermModerationManage,
            kStaffPermCampaignsView,
            kStaffPermCampaignsEdit,
            kStaffPermCampaignsPublish,
            kStaffPermCampaignsSettings,
            kStaffPermCategoriesView,
            kStaffPermCategoriesManage,
            kStaffPermVeterinariansView,
            kStaffPermVeterinariansManage,
            kStaffPermHomeControlView,
            kStaffPermHomeControlManage,
            kStaffPermHotelView,
            kStaffPermHotelReservationsManage,
            kStaffPermHotelCheckIn,
            kStaffPermHotelCheckOut,
            kStaffPermHotelAccommodationsManage,
            kStaffPermHotelCareView,
            kStaffPermHotelCareManage,
            kStaffPermHotelTaskRead,
            kStaffPermHotelTaskAssign,
            kStaffPermHotelTaskExecute,
            kStaffPermHotelMedicationRead,
            kStaffPermHotelMedicationManage,
            kStaffPermHotelMedicationAdminister,
            kStaffPermHotelHealthRead,
            kStaffPermHotelHealthCreate,
            kStaffPermHotelHealthManage,
            kStaffPermHotelIncidentsView,
            kStaffPermHotelIncidentsManage,
            kStaffPermHotelServicesManage,
            kStaffPermHotelMediaView,
            kStaffPermHotelMediaManage,
            kStaffPermHotelBillingView,
            kStaffPermHotelBillingManage,
            kStaffPermHotelBillingAdjust,
            kStaffPermHotelTransportManage,
            kStaffPermHotelNotificationsManage,
            kStaffPermHotelReportsView,
            kStaffPermHotelSettingsManage,
            kStaffPermHotelOverride,
            kStaffPermBannersView,
            kStaffPermBannersManage,
            kStaffPermIamStaffRead,
            kStaffPermIamStaffCreate,
            kStaffPermIamStaffUpdate,
            kStaffPermIamStaffDisable,
            kStaffPermIamRoleRead,
            kStaffPermIamRoleCreate,
            kStaffPermIamRoleUpdate,
            kStaffPermIamRoleDelete,
            kStaffPermIamBindingRead,
            kStaffPermIamBindingGrant,
            kStaffPermIamBindingRevoke,
            kStaffPermIamElevationRequest,
            kStaffPermIamElevationApprove,
            kStaffPermIamElevationRevoke,
            kStaffPermIamProjectionReconcile,
            kStaffPermIamPolicyRead,
            kStaffPermIamPolicyUpdate,
            kStaffPermIamRootAssign,
        ];
    });
    return keys;
}

NSArray<NSDictionary<NSString *, id> *> * PPStaffPermissionModules(void) {
    static NSArray<NSDictionary<NSString *, id> *> *modules;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        modules = @[
            @{ @"key": @"dashboard",
               @"labelEn": @"Dashboard",
               @"labelAr": @"لوحة التحكم",
               @"actions": @[
                   @{ @"key": @"dashboard.view", @"labelEn": @"View dashboard", @"labelAr": @"عرض لوحة التحكم", @"riskTier": @"T0", @"protected": @NO },
               ] },
            @{ @"key": @"nova",
               @"labelEn": @"Nova",
               @"labelAr": @"نوفا",
               @"actions": @[
                   @{ @"key": @"nova.view", @"labelEn": @"View Nova", @"labelAr": @"عرض نوفا", @"riskTier": @"T0", @"protected": @NO },
               ] },
            @{ @"key": @"staff",
               @"labelEn": @"Staff",
               @"labelAr": @"الموظفون",
               @"actions": @[
                   @{ @"key": @"staff.view", @"labelEn": @"View staff", @"labelAr": @"عرض الموظفين", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"staff.manage", @"labelEn": @"Manage staff", @"labelAr": @"إدارة الموظفين", @"riskTier": @"T4", @"protected": @YES },
               ] },
            @{ @"key": @"iam",
               @"labelEn": @"Identity and Access",
               @"labelAr": @"الهوية والصلاحيات",
               @"actions": @[
                   @{ @"key": @"iam.staff.read", @"labelEn": @"Read workforce identities", @"labelAr": @"عرض هويات فريق العمل", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"iam.staff.create", @"labelEn": @"Create workforce identities", @"labelAr": @"إنشاء هويات فريق العمل", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.staff.update", @"labelEn": @"Update workforce identities", @"labelAr": @"تحديث هويات فريق العمل", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.staff.disable", @"labelEn": @"Disable workforce identities", @"labelAr": @"تعطيل هويات فريق العمل", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.role.read", @"labelEn": @"Read role definitions", @"labelAr": @"عرض تعريفات الأدوار", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"iam.role.create", @"labelEn": @"Create custom role versions", @"labelAr": @"إنشاء إصدارات أدوار مخصصة", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.role.update", @"labelEn": @"Create a replacement custom role version", @"labelAr": @"إنشاء إصدار بديل لدور مخصص", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.role.delete", @"labelEn": @"Retire custom role versions", @"labelAr": @"إيقاف إصدارات الأدوار المخصصة", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.binding.read", @"labelEn": @"Read scoped role bindings", @"labelAr": @"عرض ارتباطات الأدوار المحددة النطاق", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"iam.binding.grant", @"labelEn": @"Grant scoped role bindings", @"labelAr": @"منح ارتباطات أدوار محددة النطاق", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.binding.revoke", @"labelEn": @"Revoke scoped role bindings", @"labelAr": @"إلغاء ارتباطات أدوار محددة النطاق", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.elevation.request", @"labelEn": @"Request temporary privileged access", @"labelAr": @"طلب وصول مميز مؤقت", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"iam.elevation.approve", @"labelEn": @"Approve temporary privileged access", @"labelAr": @"اعتماد وصول مميز مؤقت", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.elevation.revoke", @"labelEn": @"Revoke temporary privileged access", @"labelAr": @"إلغاء وصول مميز مؤقت", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.projection.reconcile", @"labelEn": @"Reconcile authorization projections", @"labelAr": @"تسوية إسقاطات الصلاحيات", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.policy.read", @"labelEn": @"Read IAM policy releases", @"labelAr": @"عرض إصدارات سياسة الصلاحيات", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"iam.policy.update", @"labelEn": @"Publish IAM policy releases", @"labelAr": @"نشر إصدارات سياسة الصلاحيات", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"iam.root.assign", @"labelEn": @"Assign or recover Platform Root", @"labelAr": @"تعيين أو استعادة المشرف التقني العام", @"riskTier": @"T4", @"protected": @YES },
               ] },
            @{ @"key": @"users",
               @"labelEn": @"Users",
               @"labelAr": @"المستخدمون",
               @"actions": @[
                   @{ @"key": @"users.view", @"labelEn": @"View users", @"labelAr": @"عرض المستخدمين", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"users.manage", @"labelEn": @"Manage users", @"labelAr": @"إدارة المستخدمين", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"users.block", @"labelEn": @"Block / unblock users", @"labelAr": @"حظر / إلغاء حظر المستخدمين", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"users.features.view", @"labelEn": @"View user features", @"labelAr": @"عرض ميزات المستخدمين", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"users.features.manage", @"labelEn": @"Manage user features", @"labelAr": @"إدارة ميزات المستخدمين", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"users.subscriptions.view", @"labelEn": @"View user subscriptions", @"labelAr": @"عرض اشتراكات المستخدمين", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"users.subscriptions.manage", @"labelEn": @"Manage user subscriptions", @"labelAr": @"إدارة اشتراكات المستخدمين", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"users.restrictions.view", @"labelEn": @"View user restrictions", @"labelAr": @"عرض قيود المستخدمين", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"users.restrictions.manage", @"labelEn": @"Manage user restrictions", @"labelAr": @"إدارة قيود المستخدمين", @"riskTier": @"T2", @"protected": @NO },
               ] },
            @{ @"key": @"stock",
               @"labelEn": @"Stock",
               @"labelAr": @"المخزون",
               @"actions": @[
                   @{ @"key": @"stock.view", @"labelEn": @"View stock", @"labelAr": @"عرض المخزون", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"stock.cost.view", @"labelEn": @"View stock costs", @"labelAr": @"عرض تكاليف المخزون", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"stock.manage", @"labelEn": @"Manage stock", @"labelAr": @"إدارة المخزون", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"stock.quarantine.release", @"labelEn": @"Release quarantined animals", @"labelAr": @"إخراج الحيوانات من الحجر", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"stock.create", @"labelEn": @"Create stock items", @"labelAr": @"إنشاء عناصر المخزون", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"stock.delete", @"labelEn": @"Delete stock items", @"labelAr": @"حذف عناصر المخزون", @"riskTier": @"T1", @"protected": @YES },
               ] },
            @{ @"key": @"listings",
               @"labelEn": @"Listings",
               @"labelAr": @"الإعلانات",
               @"actions": @[
                   @{ @"key": @"listings.view", @"labelEn": @"View listings", @"labelAr": @"عرض الإعلانات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"listings.manage", @"labelEn": @"Manage listings", @"labelAr": @"إدارة الإعلانات", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"listings.moderate", @"labelEn": @"Moderate listings", @"labelAr": @"مراجعة الإعلانات", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"payments",
               @"labelEn": @"Payments",
               @"labelAr": @"المدفوعات",
               @"actions": @[
                   @{ @"key": @"payments.view", @"labelEn": @"View payments", @"labelAr": @"عرض المدفوعات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"payments.manage", @"labelEn": @"Manage payments", @"labelAr": @"إدارة المدفوعات", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"payments.refund", @"labelEn": @"Process refunds", @"labelAr": @"معالجة الاسترجاعات", @"riskTier": @"T3", @"protected": @YES },
               ] },
            @{ @"key": @"delivery",
               @"labelEn": @"Delivery operations",
               @"labelAr": @"عمليات التوصيل",
               @"actions": @[
                   @{ @"key": @"delivery.view", @"labelEn": @"View delivery operations", @"labelAr": @"عرض عمليات التوصيل", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"delivery.dispatch", @"labelEn": @"Dispatch deliveries", @"labelAr": @"إدارة إرسال التوصيلات", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"delivery.assign", @"labelEn": @"Assign delivery drivers", @"labelAr": @"تعيين سائقي التوصيل", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"delivery.override", @"labelEn": @"Override delivery safeguards", @"labelAr": @"تجاوز ضوابط التوصيل", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"delivery.driver.view", @"labelEn": @"View delivery drivers", @"labelAr": @"عرض سائقي التوصيل", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"delivery.driver.manage", @"labelEn": @"Manage delivery drivers", @"labelAr": @"إدارة سائقي التوصيل", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"delivery.carrier.view", @"labelEn": @"View delivery carriers", @"labelAr": @"عرض شركات التوصيل", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"delivery.carrier.manage", @"labelEn": @"Manage delivery carriers", @"labelAr": @"إدارة شركات التوصيل", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"delivery.route.view", @"labelEn": @"View delivery routes", @"labelAr": @"عرض مسارات التوصيل", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"delivery.route.manage", @"labelEn": @"Manage delivery routes", @"labelAr": @"إدارة مسارات التوصيل", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"delivery.pod.review", @"labelEn": @"Review proof of delivery", @"labelAr": @"مراجعة إثبات التوصيل", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"delivery.cod.view", @"labelEn": @"View cash-on-delivery custody", @"labelAr": @"عرض عهدة الدفع عند الاستلام", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"delivery.cod.reconcile", @"labelEn": @"Reconcile cash on delivery", @"labelAr": @"تسوية الدفع عند الاستلام", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"delivery.settings.manage", @"labelEn": @"Manage delivery settings", @"labelAr": @"إدارة إعدادات التوصيل", @"riskTier": @"T4", @"protected": @YES },
               ] },
            @{ @"key": @"pos",
               @"labelEn": @"Point of Sale",
               @"labelAr": @"نقطة البيع",
               @"actions": @[
                   @{ @"key": @"pos.view", @"labelEn": @"View POS", @"labelAr": @"عرض نقطة البيع", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"pos.sell", @"labelEn": @"Sell via POS", @"labelAr": @"بيع عبر نقطة البيع", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"pos.history", @"labelEn": @"View POS history", @"labelAr": @"عرض سجل نقطة البيع", @"riskTier": @"T0", @"protected": @NO },
               ] },
            @{ @"key": @"branches",
               @"labelEn": @"Branches",
               @"labelAr": @"الفروع",
               @"actions": @[
                   @{ @"key": @"branches.view", @"labelEn": @"View branches", @"labelAr": @"عرض الفروع", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"branches.manage", @"labelEn": @"Manage branches", @"labelAr": @"إدارة الفروع", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"agents",
               @"labelEn": @"Agents",
               @"labelAr": @"الوكلاء",
               @"actions": @[
                   @{ @"key": @"agents.view", @"labelEn": @"View agents", @"labelAr": @"عرض الوكلاء", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"agents.manage", @"labelEn": @"Manage agents", @"labelAr": @"إدارة الوكلاء", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"support",
               @"labelEn": @"Support",
               @"labelAr": @"الدعم",
               @"actions": @[
                   @{ @"key": @"support.view", @"labelEn": @"View support", @"labelAr": @"عرض الدعم", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"support.manage", @"labelEn": @"Manage support", @"labelAr": @"إدارة الدعم", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"services",
               @"labelEn": @"Services",
               @"labelAr": @"الخدمات",
               @"actions": @[
                   @{ @"key": @"services.view", @"labelEn": @"View services", @"labelAr": @"عرض الخدمات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"services.manage", @"labelEn": @"Manage services", @"labelAr": @"إدارة الخدمات", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"providers",
               @"labelEn": @"Provider applications",
               @"labelAr": @"طلبات مقدمي الخدمة",
               @"actions": @[
                   @{ @"key": @"providers.view", @"labelEn": @"View provider applications", @"labelAr": @"عرض طلبات مقدمي الخدمة", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"providers.manage", @"labelEn": @"Manage provider applications", @"labelAr": @"إدارة طلبات مقدمي الخدمة", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"settings",
               @"labelEn": @"Settings",
               @"labelAr": @"الإعدادات",
               @"actions": @[
                   @{ @"key": @"settings.view", @"labelEn": @"View settings", @"labelAr": @"عرض الإعدادات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"settings.manage", @"labelEn": @"Manage settings", @"labelAr": @"إدارة الإعدادات", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"notifications",
               @"labelEn": @"Notifications",
               @"labelAr": @"الإشعارات",
               @"actions": @[
                   @{ @"key": @"notifications.view", @"labelEn": @"View notifications", @"labelAr": @"عرض الإشعارات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"notifications.inbox.view", @"labelEn": @"Inspect user notification inboxes", @"labelAr": @"فحص صناديق إشعارات المستخدمين", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"notifications.send", @"labelEn": @"Send notifications", @"labelAr": @"إرسال الإشعارات", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"accounting",
               @"labelEn": @"Accounting",
               @"labelAr": @"المحاسبة",
               @"actions": @[
                   @{ @"key": @"accounting.view", @"labelEn": @"View accounting", @"labelAr": @"عرض المحاسبة", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"accounting.manage", @"labelEn": @"Manage accounting", @"labelAr": @"إدارة المحاسبة", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"accounting.document.create", @"labelEn": @"Create accounting documents", @"labelAr": @"إنشاء مستندات محاسبية", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"accounting.document.edit_draft", @"labelEn": @"Edit draft accounting documents", @"labelAr": @"تعديل مسودات محاسبية", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"accounting.approve", @"labelEn": @"Approve accounting documents", @"labelAr": @"اعتماد المستندات المحاسبية", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"accounting.payment.record", @"labelEn": @"Record accounting payments", @"labelAr": @"تسجيل المدفوعات المحاسبية", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"accounting.transfer", @"labelEn": @"Transfer accounting funds", @"labelAr": @"تحويل الأموال المحاسبية", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"accounting.void", @"labelEn": @"Void accounting documents", @"labelAr": @"إلغاء المستندات المحاسبية", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"accounting.attachments.manage", @"labelEn": @"Manage accounting attachments", @"labelAr": @"إدارة مرفقات المحاسبة", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"accounting.accounts.manage", @"labelEn": @"Manage accounting accounts", @"labelAr": @"إدارة حسابات المحاسبة", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"accounting.categories.manage", @"labelEn": @"Manage accounting categories", @"labelAr": @"إدارة فئات المحاسبة", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"accounting.settings.manage", @"labelEn": @"Manage accounting settings", @"labelAr": @"إدارة إعدادات المحاسبة", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"accounting.reconcile", @"labelEn": @"Reconcile accounting", @"labelAr": @"تسوية المحاسبة", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"accounting.export", @"labelEn": @"Export accounting", @"labelAr": @"تصدير المحاسبة", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"accounting.period.view", @"labelEn": @"View accounting periods", @"labelAr": @"عرض الفترات المحاسبية", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"accounting.period.close", @"labelEn": @"Close accounting periods", @"labelAr": @"إغلاق الفترات المحاسبية", @"riskTier": @"T4", @"protected": @YES },
                   @{ @"key": @"accounting.period.reopen", @"labelEn": @"Reopen accounting periods", @"labelAr": @"إعادة فتح الفترات المحاسبية", @"riskTier": @"T4", @"protected": @YES },
               ] },
            @{ @"key": @"reports",
               @"labelEn": @"Reports",
               @"labelAr": @"التقارير",
               @"actions": @[
                   @{ @"key": @"reports.view", @"labelEn": @"View reports", @"labelAr": @"عرض التقارير", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"reports.export", @"labelEn": @"Export reports", @"labelAr": @"تصدير التقارير", @"riskTier": @"T2", @"protected": @NO },
               ] },
            @{ @"key": @"audit",
               @"labelEn": @"Audit",
               @"labelAr": @"التدقيق",
               @"actions": @[
                   @{ @"key": @"audit.view", @"labelEn": @"View audit log", @"labelAr": @"عرض سجل التدقيق", @"riskTier": @"T4", @"protected": @YES },
               ] },
            @{ @"key": @"moderation",
               @"labelEn": @"Moderation",
               @"labelAr": @"المراجعة",
               @"actions": @[
                   @{ @"key": @"moderation.view", @"labelEn": @"View moderation", @"labelAr": @"عرض المراجعة", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"moderation.manage", @"labelEn": @"Manage moderation", @"labelAr": @"إدارة المراجعة", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"campaigns",
               @"labelEn": @"Campaigns",
               @"labelAr": @"الحملات",
               @"actions": @[
                   @{ @"key": @"campaigns.view", @"labelEn": @"View campaigns", @"labelAr": @"عرض الحملات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"campaigns.edit", @"labelEn": @"Edit campaign drafts", @"labelAr": @"تحرير مسودات الحملات", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"campaigns.publish", @"labelEn": @"Publish, pause, and archive campaigns", @"labelAr": @"نشر الحملات وإيقافها وأرشفتها", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"campaigns.settings", @"labelEn": @"Manage campaign action settings", @"labelAr": @"إدارة إعدادات إجراءات الحملات", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"categories",
               @"labelEn": @"Categories",
               @"labelAr": @"الأقسام",
               @"actions": @[
                   @{ @"key": @"categories.view", @"labelEn": @"View categories", @"labelAr": @"عرض الأقسام", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"categories.manage", @"labelEn": @"Manage categories", @"labelAr": @"إدارة الأقسام", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"veterinarians",
               @"labelEn": @"Veterinarians",
               @"labelAr": @"الأطباء البيطريون",
               @"actions": @[
                   @{ @"key": @"veterinarians.view", @"labelEn": @"View veterinarians", @"labelAr": @"عرض الأطباء البيطريين", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"veterinarians.manage", @"labelEn": @"Manage veterinarians", @"labelAr": @"إدارة الأطباء البيطريين", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"home_control",
               @"labelEn": @"Home Control",
               @"labelAr": @"تحكم الصفحة الرئيسية",
               @"actions": @[
                   @{ @"key": @"home_control.view", @"labelEn": @"View home control", @"labelAr": @"عرض تحكم الصفحة الرئيسية", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"home_control.manage", @"labelEn": @"Publish home control", @"labelAr": @"نشر إعدادات الصفحة الرئيسية", @"riskTier": @"T1", @"protected": @NO },
               ] },
            @{ @"key": @"hotel",
               @"labelEn": @"Pets Hotel",
               @"labelAr": @"فندق الحيوانات",
               @"actions": @[
                   @{ @"key": @"hotel.view", @"labelEn": @"View Pets Hotel", @"labelAr": @"عرض فندق الحيوانات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"hotel.reservations.manage", @"labelEn": @"Manage hotel reservations", @"labelAr": @"إدارة حجوزات الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.checkin", @"labelEn": @"Check guests in", @"labelAr": @"تسجيل وصول الضيوف", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.checkout", @"labelEn": @"Check guests out", @"labelAr": @"تسجيل مغادرة الضيوف", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.accommodations.manage", @"labelEn": @"Manage rooms and capacity", @"labelAr": @"إدارة الغرف والسعة", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.care.view", @"labelEn": @"View care operations", @"labelAr": @"عرض عمليات الرعاية", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"hotel.care.manage", @"labelEn": @"Manage care plans and tasks", @"labelAr": @"إدارة خطط الرعاية والمهام", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.task.read", @"labelEn": @"View hotel tasks", @"labelAr": @"عرض مهام الفندق", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"hotel.task.assign", @"labelEn": @"Assign hotel tasks", @"labelAr": @"تعيين مهام الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.task.execute", @"labelEn": @"Execute hotel tasks", @"labelAr": @"تنفيذ مهام الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.medication.read", @"labelEn": @"View medication records", @"labelAr": @"عرض سجلات الأدوية", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"hotel.medication.manage", @"labelEn": @"Manage medication plans", @"labelAr": @"إدارة خطط الأدوية", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.medication.administer", @"labelEn": @"Administer medication", @"labelAr": @"إعطاء الأدوية", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"hotel.health.read", @"labelEn": @"View health observations", @"labelAr": @"عرض الملاحظات الصحية", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"hotel.health.create", @"labelEn": @"Record health observations", @"labelAr": @"تسجيل الملاحظات الصحية", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.health.manage", @"labelEn": @"Manage health records", @"labelAr": @"إدارة السجلات الصحية", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.incidents.view", @"labelEn": @"View incidents", @"labelAr": @"عرض الحوادث", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"hotel.incidents.manage", @"labelEn": @"Manage incidents", @"labelAr": @"إدارة الحوادث", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.services.manage", @"labelEn": @"Manage hotel services", @"labelAr": @"إدارة خدمات الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.media.view", @"labelEn": @"View stay photos and evidence", @"labelAr": @"عرض صور وأدلة الإقامة", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"hotel.media.manage", @"labelEn": @"Manage stay photos and evidence", @"labelAr": @"إدارة صور وأدلة الإقامة", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.billing.view", @"labelEn": @"View hotel billing", @"labelAr": @"عرض فواتير الفندق", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"hotel.billing.manage", @"labelEn": @"Manage hotel charges", @"labelAr": @"إدارة رسوم الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.billing.adjust", @"labelEn": @"Void and adjust hotel charges", @"labelAr": @"إلغاء وتعديل رسوم الفندق", @"riskTier": @"T3", @"protected": @YES },
                   @{ @"key": @"hotel.transport.manage", @"labelEn": @"Manage hotel transport", @"labelAr": @"إدارة نقل الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.notifications.manage", @"labelEn": @"Manage hotel customer updates", @"labelAr": @"إدارة تحديثات عملاء الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.reports.view", @"labelEn": @"View hotel reports", @"labelAr": @"عرض تقارير الفندق", @"riskTier": @"T2", @"protected": @NO },
                   @{ @"key": @"hotel.settings.manage", @"labelEn": @"Manage hotel settings", @"labelAr": @"إدارة إعدادات الفندق", @"riskTier": @"T1", @"protected": @NO },
                   @{ @"key": @"hotel.override", @"labelEn": @"Override hotel safeguards", @"labelAr": @"تجاوز ضوابط الفندق", @"riskTier": @"T4", @"protected": @YES },
               ] },
            @{ @"key": @"banners",
               @"labelEn": @"Banners",
               @"labelAr": @"البنرات",
               @"actions": @[
                   @{ @"key": @"banners.view", @"labelEn": @"View banners", @"labelAr": @"عرض البنرات", @"riskTier": @"T0", @"protected": @NO },
                   @{ @"key": @"banners.manage", @"labelEn": @"Manage banners", @"labelAr": @"إدارة البنرات", @"riskTier": @"T1", @"protected": @NO },
               ] },
        ];
    });
    return modules;
}

BOOL PPStaffIsAdminRole(PPStaffRole role) {
    PPStaffRole normalized = PPStaffNormalizedRole(role);
    return [normalized isEqualToString:PPStaffRoleSuperAdmin] ||
           [normalized isEqualToString:PPStaffRoleOwner];
}

BOOL PPStaffIsRootRole(PPStaffRole role) {
    PPStaffRole normalized = PPStaffNormalizedRole(role);
    return [normalized isEqualToString:PPStaffRoleSuperAdmin];
}

PPStaffRole _Nullable PPStaffNormalizedRole(id value) {
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *raw = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) return nil;

    // Known legacy aliases
    if ([raw isEqualToString:@"SuperAdmin"]) return PPStaffRoleSuperAdmin;
    if ([raw isEqualToString:@"superadmin"]) return PPStaffRoleSuperAdmin;
    if ([raw isEqualToString:@"Admin"]) return PPStaffRoleOwner;
    if ([raw isEqualToString:@"admin"]) return PPStaffRoleOwner;
    if ([raw isEqualToString:@"Owner"]) return PPStaffRoleOwner;
    if ([raw isEqualToString:@"owner"]) return PPStaffRoleOwner;
    if ([raw isEqualToString:@"SecurityAdmin"]) return PPStaffRoleSecurityAdmin;
    if ([raw isEqualToString:@"securityadmin"]) return PPStaffRoleSecurityAdmin;
    if ([raw isEqualToString:@"security_admin"]) return PPStaffRoleSecurityAdmin;
    if ([raw isEqualToString:@"security admin"]) return PPStaffRoleSecurityAdmin;
    if ([raw isEqualToString:@"ComplianceAuditor"]) return PPStaffRoleComplianceAuditor;
    if ([raw isEqualToString:@"complianceauditor"]) return PPStaffRoleComplianceAuditor;
    if ([raw isEqualToString:@"compliance_auditor"]) return PPStaffRoleComplianceAuditor;
    if ([raw isEqualToString:@"compliance auditor"]) return PPStaffRoleComplianceAuditor;
    if ([raw isEqualToString:@"auditor"]) return PPStaffRoleComplianceAuditor;
    if ([raw isEqualToString:@"OperationsManager"]) return PPStaffRoleOperationsManager;
    if ([raw isEqualToString:@"operationsmanager"]) return PPStaffRoleOperationsManager;
    if ([raw isEqualToString:@"operations manager"]) return PPStaffRoleOperationsManager;
    if ([raw isEqualToString:@"moderator"]) return PPStaffRoleOperationsManager;
    if ([raw isEqualToString:@"BranchManager"]) return PPStaffRoleBranchManager;
    if ([raw isEqualToString:@"branch_manager"]) return PPStaffRoleBranchManager;
    if ([raw isEqualToString:@"branchmanager"]) return PPStaffRoleBranchManager;
    if ([raw isEqualToString:@"branch manager"]) return PPStaffRoleBranchManager;
    if ([raw isEqualToString:@"Accountant"]) return PPStaffRoleAccountant;
    if ([raw isEqualToString:@"accountant"]) return PPStaffRoleAccountant;
    if ([raw isEqualToString:@"Warehouse"]) return PPStaffRoleWarehouse;
    if ([raw isEqualToString:@"warehouse"]) return PPStaffRoleWarehouse;
    if ([raw isEqualToString:@"Sales"]) return PPStaffRoleSales;
    if ([raw isEqualToString:@"sales"]) return PPStaffRoleSales;
    if ([raw isEqualToString:@"InventoryManager"]) return PPStaffRoleInventoryManager;
    if ([raw isEqualToString:@"inventorymanager"]) return PPStaffRoleInventoryManager;
    if ([raw isEqualToString:@"inventory manager"]) return PPStaffRoleInventoryManager;
    if ([raw isEqualToString:@"storemanager"]) return PPStaffRoleInventoryManager;
    if ([raw isEqualToString:@"store manager"]) return PPStaffRoleInventoryManager;
    if ([raw isEqualToString:@"PaymentsManager"]) return PPStaffRolePaymentsManager;
    if ([raw isEqualToString:@"paymentsmanager"]) return PPStaffRolePaymentsManager;
    if ([raw isEqualToString:@"payments manager"]) return PPStaffRolePaymentsManager;
    if ([raw isEqualToString:@"SupportAgent"]) return PPStaffRoleSupportAgent;
    if ([raw isEqualToString:@"supportagent"]) return PPStaffRoleSupportAgent;
    if ([raw isEqualToString:@"support agent"]) return PPStaffRoleSupportAgent;
    if ([raw isEqualToString:@"Staff"]) return PPStaffRoleViewer;
    if ([raw isEqualToString:@"staff"]) return PPStaffRoleViewer;
    if ([raw isEqualToString:@"Viewer"]) return PPStaffRoleViewer;
    if ([raw isEqualToString:@"viewer"]) return PPStaffRoleViewer;
    if ([raw isEqualToString:@"user"]) return PPStaffRoleViewer;

    NSString *lower = [raw.lowercaseString stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    lower = [lower stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    if ([lower isEqualToString:@"super_admin"]) return PPStaffRoleSuperAdmin;
    if ([lower isEqualToString:@"owner"]) return PPStaffRoleOwner;
    if ([lower isEqualToString:@"operations_manager"]) return PPStaffRoleOperationsManager;
    if ([lower isEqualToString:@"branch_manager"]) return PPStaffRoleBranchManager;
    if ([lower isEqualToString:@"inventory_manager"]) return PPStaffRoleInventoryManager;
    if ([lower isEqualToString:@"accountant"]) return PPStaffRoleAccountant;
    if ([lower isEqualToString:@"warehouse"]) return PPStaffRoleWarehouse;
    if ([lower isEqualToString:@"sales"]) return PPStaffRoleSales;
    if ([lower isEqualToString:@"payments_manager"]) return PPStaffRolePaymentsManager;
    if ([lower isEqualToString:@"support_agent"]) return PPStaffRoleSupportAgent;
    if ([lower isEqualToString:@"content_editor"]) return PPStaffRoleContentEditor;
    if ([lower isEqualToString:@"content_publisher"]) return PPStaffRoleContentPublisher;
    if ([lower isEqualToString:@"viewer"]) return PPStaffRoleViewer;
    if ([lower isEqualToString:@"security_admin"]) return PPStaffRoleSecurityAdmin;
    if ([lower isEqualToString:@"compliance_auditor"]) return PPStaffRoleComplianceAuditor;

    return nil;
}

NSArray<NSString *> * PPStaffDefaultPermissionsForRole(PPStaffRole role) {
    PPStaffRole normalized = PPStaffNormalizedRole(role);

    if ([normalized isEqualToString:PPStaffRoleSuperAdmin]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStaffView,
            kStaffPermSettingsView,
            kStaffPermAuditView,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
            kStaffPermIamStaffRead,
            kStaffPermIamStaffCreate,
            kStaffPermIamStaffUpdate,
            kStaffPermIamStaffDisable,
            kStaffPermIamRoleRead,
            kStaffPermIamRoleCreate,
            kStaffPermIamRoleUpdate,
            kStaffPermIamRoleDelete,
            kStaffPermIamBindingRead,
            kStaffPermIamBindingGrant,
            kStaffPermIamBindingRevoke,
            kStaffPermIamElevationRequest,
            kStaffPermIamElevationApprove,
            kStaffPermIamElevationRevoke,
            kStaffPermIamProjectionReconcile,
            kStaffPermIamPolicyRead,
            kStaffPermIamPolicyUpdate,
            kStaffPermIamRootAssign,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleOwner]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermNovaView,
            kStaffPermStaffView,
            kStaffPermUsersView,
            kStaffPermUsersManage,
            kStaffPermUsersBlock,
            kStaffPermUsersFeaturesView,
            kStaffPermUsersFeaturesManage,
            kStaffPermUsersSubscriptionsView,
            kStaffPermUsersSubscriptionsManage,
            kStaffPermUsersRestrictionsView,
            kStaffPermUsersRestrictionsManage,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermStockManage,
            kStaffPermStockCreate,
            kStaffPermListingsView,
            kStaffPermListingsManage,
            kStaffPermListingsModerate,
            kStaffPermPaymentsView,
            kStaffPermPaymentsManage,
            kStaffPermDeliveryView,
            kStaffPermDeliveryDispatch,
            kStaffPermDeliveryAssign,
            kStaffPermDeliveryDriverView,
            kStaffPermDeliveryDriverManage,
            kStaffPermDeliveryCarrierView,
            kStaffPermDeliveryCarrierManage,
            kStaffPermDeliveryRouteView,
            kStaffPermDeliveryRouteManage,
            kStaffPermDeliveryPODReview,
            kStaffPermDeliveryCODView,
            kStaffPermPosView,
            kStaffPermPosHistory,
            kStaffPermBranchesView,
            kStaffPermBranchesManage,
            kStaffPermAgentsView,
            kStaffPermAgentsManage,
            kStaffPermSupportView,
            kStaffPermSupportManage,
            kStaffPermServicesView,
            kStaffPermServicesManage,
            kStaffPermProvidersView,
            kStaffPermProvidersManage,
            kStaffPermSettingsView,
            kStaffPermNotificationsView,
            kStaffPermAccountingView,
            kStaffPermAccountingExport,
            kStaffPermAccountingPeriodView,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermAuditView,
            kStaffPermModerationView,
            kStaffPermModerationManage,
            kStaffPermCampaignsView,
            kStaffPermCampaignsEdit,
            kStaffPermCategoriesView,
            kStaffPermCategoriesManage,
            kStaffPermVeterinariansView,
            kStaffPermVeterinariansManage,
            kStaffPermHomeControlView,
            kStaffPermHomeControlManage,
            kStaffPermHotelView,
            kStaffPermHotelReservationsManage,
            kStaffPermHotelAccommodationsManage,
            kStaffPermHotelCareView,
            kStaffPermHotelHealthRead,
            kStaffPermHotelIncidentsView,
            kStaffPermHotelServicesManage,
            kStaffPermHotelMediaView,
            kStaffPermHotelBillingView,
            kStaffPermHotelReportsView,
            kStaffPermBannersView,
            kStaffPermBannersManage,
            kStaffPermIamPolicyRead,
            kStaffPermIamRoleRead,
            kStaffPermIamBindingRead,
            kStaffPermIamElevationRequest,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleOperationsManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermNovaView,
            kStaffPermUsersView,
            kStaffPermUsersManage,
            kStaffPermUsersFeaturesView,
            kStaffPermUsersSubscriptionsView,
            kStaffPermUsersRestrictionsView,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermStockManage,
            kStaffPermStockCreate,
            kStaffPermListingsView,
            kStaffPermListingsManage,
            kStaffPermListingsModerate,
            kStaffPermPaymentsView,
            kStaffPermDeliveryView,
            kStaffPermDeliveryDispatch,
            kStaffPermDeliveryAssign,
            kStaffPermDeliveryDriverView,
            kStaffPermDeliveryDriverManage,
            kStaffPermDeliveryCarrierView,
            kStaffPermDeliveryCarrierManage,
            kStaffPermDeliveryRouteView,
            kStaffPermDeliveryRouteManage,
            kStaffPermDeliveryPODReview,
            kStaffPermDeliveryCODView,
            kStaffPermPosView,
            kStaffPermPosHistory,
            kStaffPermBranchesView,
            kStaffPermBranchesManage,
            kStaffPermAgentsView,
            kStaffPermAgentsManage,
            kStaffPermSupportView,
            kStaffPermSupportManage,
            kStaffPermServicesView,
            kStaffPermServicesManage,
            kStaffPermProvidersView,
            kStaffPermProvidersManage,
            kStaffPermNotificationsView,
            kStaffPermReportsView,
            kStaffPermModerationView,
            kStaffPermModerationManage,
            kStaffPermCampaignsView,
            kStaffPermCampaignsEdit,
            kStaffPermCategoriesView,
            kStaffPermCategoriesManage,
            kStaffPermVeterinariansView,
            kStaffPermVeterinariansManage,
            kStaffPermHomeControlView,
            kStaffPermHomeControlManage,
            kStaffPermHotelView,
            kStaffPermHotelReservationsManage,
            kStaffPermHotelCheckIn,
            kStaffPermHotelCheckOut,
            kStaffPermHotelAccommodationsManage,
            kStaffPermHotelCareView,
            kStaffPermHotelCareManage,
            kStaffPermHotelTaskRead,
            kStaffPermHotelTaskAssign,
            kStaffPermHotelHealthRead,
            kStaffPermHotelHealthCreate,
            kStaffPermHotelIncidentsView,
            kStaffPermHotelIncidentsManage,
            kStaffPermHotelServicesManage,
            kStaffPermHotelMediaView,
            kStaffPermHotelMediaManage,
            kStaffPermHotelTransportManage,
            kStaffPermHotelNotificationsManage,
            kStaffPermHotelReportsView,
            kStaffPermBannersView,
            kStaffPermBannersManage,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleBranchManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStaffView,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermStockManage,
            kStaffPermStockCreate,
            kStaffPermStockDelete,
            kStaffPermStockQuarantineRelease,
            kStaffPermPosView,
            kStaffPermPosSell,
            kStaffPermPosHistory,
            kStaffPermPaymentsView,
            kStaffPermPaymentsManage,
            kStaffPermPaymentsRefund,
            kStaffPermAccountingView,
            kStaffPermAccountingDocumentCreate,
            kStaffPermAccountingDocumentEditDraft,
            kStaffPermAccountingPaymentRecord,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermBranchesView,
            kStaffPermSupportView,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleInventoryManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermStockManage,
            kStaffPermStockQuarantineRelease,
            kStaffPermStockCreate,
            kStaffPermStockDelete,
            kStaffPermCategoriesView,
            kStaffPermCategoriesManage,
            kStaffPermReportsView,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleAccountant]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermAccountingView,
            kStaffPermAccountingManage,
            kStaffPermAccountingDocumentCreate,
            kStaffPermAccountingDocumentEditDraft,
            kStaffPermAccountingPaymentRecord,
            kStaffPermAccountingAttachmentsManage,
            kStaffPermAccountingAccountsManage,
            kStaffPermAccountingCategoriesManage,
            kStaffPermAccountingReconcile,
            kStaffPermAccountingExport,
            kStaffPermAccountingPeriodView,
            kStaffPermPaymentsView,
            kStaffPermPosHistory,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleWarehouse]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermStockManage,
            kStaffPermStockCreate,
            kStaffPermStockDelete,
            kStaffPermStockQuarantineRelease,
            kStaffPermCategoriesView,
            kStaffPermReportsView,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleSales]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermPosView,
            kStaffPermPosSell,
            kStaffPermPosHistory,
            kStaffPermStockView,
            kStaffPermPaymentsView,
            kStaffPermNotificationsView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRolePaymentsManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermPaymentsView,
            kStaffPermPaymentsManage,
            kStaffPermDeliveryCODView,
            kStaffPermAccountingView,
            kStaffPermAccountingPaymentRecord,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermPosView,
            kStaffPermPosHistory,
            kStaffPermNotificationsView,
            kStaffPermHotelView,
            kStaffPermHotelBillingView,
            kStaffPermHotelReportsView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleSupportAgent]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermSupportView,
            kStaffPermSupportManage,
            kStaffPermUsersView,
            kStaffPermUsersFeaturesView,
            kStaffPermUsersRestrictionsView,
            kStaffPermNotificationsView,
            kStaffPermHotelView,
            kStaffPermHotelCareView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleContentEditor]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermCampaignsView,
            kStaffPermCampaignsEdit,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleContentPublisher]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermCampaignsView,
            kStaffPermCampaignsEdit,
            kStaffPermCampaignsPublish,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleViewer]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStockView,
            kStaffPermListingsView,
            kStaffPermPaymentsView,
            kStaffPermDeliveryView,
            kStaffPermDeliveryRouteView,
            kStaffPermPosView,
            kStaffPermBranchesView,
            kStaffPermSupportView,
            kStaffPermServicesView,
            kStaffPermProvidersView,
            kStaffPermNotificationsView,
            kStaffPermReportsView,
            kStaffPermCampaignsView,
            kStaffPermCategoriesView,
            kStaffPermHomeControlView,
            kStaffPermHotelView,
            kStaffPermBannersView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleSecurityAdmin]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStaffView,
            kStaffPermAuditView,
            kStaffPermUsersView,
            kStaffPermUsersRestrictionsView,
            kStaffPermSettingsView,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
            kStaffPermIamStaffRead,
            kStaffPermIamStaffCreate,
            kStaffPermIamStaffUpdate,
            kStaffPermIamStaffDisable,
            kStaffPermIamRoleRead,
            kStaffPermIamRoleCreate,
            kStaffPermIamRoleUpdate,
            kStaffPermIamRoleDelete,
            kStaffPermIamBindingRead,
            kStaffPermIamBindingGrant,
            kStaffPermIamBindingRevoke,
            kStaffPermIamElevationRequest,
            kStaffPermIamElevationApprove,
            kStaffPermIamElevationRevoke,
            kStaffPermIamProjectionReconcile,
            kStaffPermIamPolicyRead,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleComplianceAuditor]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermAuditView,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermAccountingView,
            kStaffPermAccountingPeriodView,
            kStaffPermAccountingExport,
            kStaffPermPaymentsView,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermStaffView,
            kStaffPermUsersView,
            kStaffPermUsersFeaturesView,
            kStaffPermUsersSubscriptionsView,
            kStaffPermUsersRestrictionsView,
            kStaffPermDeliveryView,
            kStaffPermDeliveryDriverView,
            kStaffPermDeliveryCarrierView,
            kStaffPermDeliveryRouteView,
            kStaffPermDeliveryCODView,
            kStaffPermDeliveryPODReview,
            kStaffPermPosView,
            kStaffPermPosHistory,
            kStaffPermBranchesView,
            kStaffPermAgentsView,
            kStaffPermServicesView,
            kStaffPermProvidersView,
            kStaffPermListingsView,
            kStaffPermCampaignsView,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
            kStaffPermCategoriesView,
            kStaffPermVeterinariansView,
            kStaffPermHomeControlView,
            kStaffPermHotelView,
            kStaffPermHotelCareView,
            kStaffPermBannersView,
            kStaffPermModerationView,
        ];
    }

    return @[];
}

NSString * PPStaffLocalizedRoleName(PPStaffRole role) {
    PPStaffRole normalized = PPStaffNormalizedRole(role);
    if ([normalized isEqualToString:PPStaffRoleSuperAdmin]) return NSLocalizedString(@"StaffRole_SUPER_ADMIN", @"مدير عام");
    if ([normalized isEqualToString:PPStaffRoleOwner]) return NSLocalizedString(@"StaffRole_OWNER", @"المالك");
    if ([normalized isEqualToString:PPStaffRoleOperationsManager]) return NSLocalizedString(@"StaffRole_OPERATIONS_MANAGER", @"مدير العمليات");
    if ([normalized isEqualToString:PPStaffRoleBranchManager]) return NSLocalizedString(@"StaffRole_BRANCH_MANAGER", @"مدير فرع");
    if ([normalized isEqualToString:PPStaffRoleInventoryManager]) return NSLocalizedString(@"StaffRole_INVENTORY_MANAGER", @"مدير المخزون");
    if ([normalized isEqualToString:PPStaffRoleAccountant]) return NSLocalizedString(@"StaffRole_ACCOUNTANT", @"محاسب");
    if ([normalized isEqualToString:PPStaffRoleWarehouse]) return NSLocalizedString(@"StaffRole_WAREHOUSE", @"أمين مستودع");
    if ([normalized isEqualToString:PPStaffRoleSales]) return NSLocalizedString(@"StaffRole_SALES", @"مبيعات");
    if ([normalized isEqualToString:PPStaffRolePaymentsManager]) return NSLocalizedString(@"StaffRole_PAYMENTS_MANAGER", @"مدير المدفوعات");
    if ([normalized isEqualToString:PPStaffRoleSupportAgent]) return NSLocalizedString(@"StaffRole_SUPPORT_AGENT", @"وكيل الدعم");
    if ([normalized isEqualToString:PPStaffRoleContentEditor]) return NSLocalizedString(@"StaffRole_CONTENT_EDITOR", @"محرر محتوى");
    if ([normalized isEqualToString:PPStaffRoleContentPublisher]) return NSLocalizedString(@"StaffRole_CONTENT_PUBLISHER", @"ناشر محتوى");
    if ([normalized isEqualToString:PPStaffRoleViewer]) return NSLocalizedString(@"StaffRole_VIEWER", @"عرض فقط");
    if ([normalized isEqualToString:PPStaffRoleSecurityAdmin]) return NSLocalizedString(@"StaffRole_SECURITY_ADMIN", @"مسؤول الأمان");
    if ([normalized isEqualToString:PPStaffRoleComplianceAuditor]) return NSLocalizedString(@"StaffRole_COMPLIANCE_AUDITOR", @"مدقق الامتثال");
    return normalized ?: @"";
}
