//
//  PPStaffAuthCatalog.generated.m
//  PurePetsAdmin
//
//  AUTO-GENERATED from Pure Pets Infra/iam/policy-catalog.json — DO NOT EDIT DIRECTLY.
//

#import "PPStaffAuthCatalog.generated.h"

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

#pragma mark - Catalog Accessor Implementations

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
        ];
    });
    return keys;
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

PPStaffRole PPStaffNormalizedRole(id value) {
    if (![value isKindOfClass:NSString.class]) {
        return PPStaffRoleViewer;
    }
    NSString *raw = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) return PPStaffRoleViewer;

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

    return PPStaffRoleViewer;
}

NSArray<NSString *> * PPStaffDefaultPermissionsForRole(PPStaffRole role) {
    PPStaffRole normalized = PPStaffNormalizedRole(role);

    if (PPStaffIsAdminRole(normalized)) {
        return PPStaffAllPermissionKeys();
    }

    if ([normalized isEqualToString:PPStaffRoleOperationsManager]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermNovaView,
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
            kStaffPermHotelTransportManage,
            kStaffPermHotelNotificationsManage,
            kStaffPermHotelReportsView,
            kStaffPermHotelSettingsManage,
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
            kStaffPermPaymentsView,
            kStaffPermPaymentsManage,
            kStaffPermPaymentsRefund,
            kStaffPermPosHistory,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
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
            kStaffPermPaymentsRefund,
            kStaffPermDeliveryCODView,
            kStaffPermDeliveryCODReconcile,
            kStaffPermAccountingView,
            kStaffPermAccountingPaymentRecord,
            kStaffPermReportsView,
            kStaffPermReportsExport,
            kStaffPermPosView,
            kStaffPermPosSell,
            kStaffPermPosHistory,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
            kStaffPermHotelView,
            kStaffPermHotelBillingView,
            kStaffPermHotelBillingManage,
            kStaffPermHotelBillingAdjust,
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
            kStaffPermNovaView,
            kStaffPermStaffView,
            kStaffPermUsersView,
            kStaffPermUsersFeaturesView,
            kStaffPermUsersSubscriptionsView,
            kStaffPermUsersRestrictionsView,
            kStaffPermStockView,
            kStaffPermStockCostView,
            kStaffPermListingsView,
            kStaffPermPaymentsView,
            kStaffPermDeliveryView,
            kStaffPermDeliveryDriverView,
            kStaffPermDeliveryCarrierView,
            kStaffPermDeliveryRouteView,
            kStaffPermPosView,
            kStaffPermBranchesView,
            kStaffPermAgentsView,
            kStaffPermSupportView,
            kStaffPermServicesView,
            kStaffPermProvidersView,
            kStaffPermSettingsView,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
            kStaffPermAccountingView,
            kStaffPermAccountingPeriodView,
            kStaffPermReportsView,
            kStaffPermModerationView,
            kStaffPermCampaignsView,
            kStaffPermCategoriesView,
            kStaffPermVeterinariansView,
            kStaffPermHomeControlView,
            kStaffPermHotelView,
            kStaffPermHotelCareView,
            kStaffPermBannersView,
        ];
    }

    if ([normalized isEqualToString:PPStaffRoleSecurityAdmin]) {
        return @[
            kStaffPermDashboardView,
            kStaffPermStaffView,
            kStaffPermStaffManage,
            kStaffPermAuditView,
            kStaffPermUsersView,
            kStaffPermUsersRestrictionsView,
            kStaffPermUsersRestrictionsManage,
            kStaffPermSettingsView,
            kStaffPermSettingsManage,
            kStaffPermNotificationsView,
            kStaffPermNotificationsInboxView,
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
