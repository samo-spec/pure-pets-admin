//
//  PPStaffAuthCatalog.generated.h
//  PurePetsAdmin
//
//  AUTO-GENERATED from Pure Pets Infra/iam/policy-catalog.json — DO NOT EDIT DIRECTLY.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Staff Role Types and Constants

typedef NSString * PPStaffRole NS_TYPED_ENUM;

extern PPStaffRole const PPStaffRoleSuperAdmin;
extern PPStaffRole const PPStaffRoleOwner;
extern PPStaffRole const PPStaffRoleOperationsManager;
extern PPStaffRole const PPStaffRoleBranchManager;
extern PPStaffRole const PPStaffRoleInventoryManager;
extern PPStaffRole const PPStaffRoleAccountant;
extern PPStaffRole const PPStaffRoleWarehouse;
extern PPStaffRole const PPStaffRoleSales;
extern PPStaffRole const PPStaffRolePaymentsManager;
extern PPStaffRole const PPStaffRoleSupportAgent;
extern PPStaffRole const PPStaffRoleContentEditor;
extern PPStaffRole const PPStaffRoleContentPublisher;
extern PPStaffRole const PPStaffRoleViewer;
extern PPStaffRole const PPStaffRoleSecurityAdmin;
extern PPStaffRole const PPStaffRoleComplianceAuditor;

#pragma mark - Permission Keys Constants (120 Permissions)

extern NSString * const kStaffPermDashboardView;
extern NSString * const kStaffPermNovaView;
extern NSString * const kStaffPermStaffView;
extern NSString * const kStaffPermStaffManage;
extern NSString * const kStaffPermUsersView;
extern NSString * const kStaffPermUsersManage;
extern NSString * const kStaffPermUsersBlock;
extern NSString * const kStaffPermUsersFeaturesView;
extern NSString * const kStaffPermUsersFeaturesManage;
extern NSString * const kStaffPermUsersSubscriptionsView;
extern NSString * const kStaffPermUsersSubscriptionsManage;
extern NSString * const kStaffPermUsersRestrictionsView;
extern NSString * const kStaffPermUsersRestrictionsManage;
extern NSString * const kStaffPermStockView;
extern NSString * const kStaffPermStockCostView;
extern NSString * const kStaffPermStockManage;
extern NSString * const kStaffPermStockQuarantineRelease;
extern NSString * const kStaffPermStockCreate;
extern NSString * const kStaffPermStockDelete;
extern NSString * const kStaffPermListingsView;
extern NSString * const kStaffPermListingsManage;
extern NSString * const kStaffPermListingsModerate;
extern NSString * const kStaffPermPaymentsView;
extern NSString * const kStaffPermPaymentsManage;
extern NSString * const kStaffPermPaymentsRefund;
extern NSString * const kStaffPermDeliveryView;
extern NSString * const kStaffPermDeliveryDispatch;
extern NSString * const kStaffPermDeliveryAssign;
extern NSString * const kStaffPermDeliveryOverride;
extern NSString * const kStaffPermDeliveryDriverView;
extern NSString * const kStaffPermDeliveryDriverManage;
extern NSString * const kStaffPermDeliveryCarrierView;
extern NSString * const kStaffPermDeliveryCarrierManage;
extern NSString * const kStaffPermDeliveryRouteView;
extern NSString * const kStaffPermDeliveryRouteManage;
extern NSString * const kStaffPermDeliveryPODReview;
extern NSString * const kStaffPermDeliveryCODView;
extern NSString * const kStaffPermDeliveryCODReconcile;
extern NSString * const kStaffPermDeliverySettingsManage;
extern NSString * const kStaffPermPosView;
extern NSString * const kStaffPermPosSell;
extern NSString * const kStaffPermPosHistory;
extern NSString * const kStaffPermBranchesView;
extern NSString * const kStaffPermBranchesManage;
extern NSString * const kStaffPermAgentsView;
extern NSString * const kStaffPermAgentsManage;
extern NSString * const kStaffPermSupportView;
extern NSString * const kStaffPermSupportManage;
extern NSString * const kStaffPermServicesView;
extern NSString * const kStaffPermServicesManage;
extern NSString * const kStaffPermProvidersView;
extern NSString * const kStaffPermProvidersManage;
extern NSString * const kStaffPermSettingsView;
extern NSString * const kStaffPermSettingsManage;
extern NSString * const kStaffPermNotificationsView;
extern NSString * const kStaffPermNotificationsInboxView;
extern NSString * const kStaffPermNotificationsSend;
extern NSString * const kStaffPermAccountingView;
extern NSString * const kStaffPermAccountingManage;
extern NSString * const kStaffPermAccountingDocumentCreate;
extern NSString * const kStaffPermAccountingDocumentEditDraft;
extern NSString * const kStaffPermAccountingApprove;
extern NSString * const kStaffPermAccountingPaymentRecord;
extern NSString * const kStaffPermAccountingTransfer;
extern NSString * const kStaffPermAccountingVoid;
extern NSString * const kStaffPermAccountingAttachmentsManage;
extern NSString * const kStaffPermAccountingAccountsManage;
extern NSString * const kStaffPermAccountingCategoriesManage;
extern NSString * const kStaffPermAccountingSettingsManage;
extern NSString * const kStaffPermAccountingReconcile;
extern NSString * const kStaffPermAccountingExport;
extern NSString * const kStaffPermAccountingPeriodView;
extern NSString * const kStaffPermAccountingPeriodClose;
extern NSString * const kStaffPermAccountingPeriodReopen;
extern NSString * const kStaffPermReportsView;
extern NSString * const kStaffPermReportsExport;
extern NSString * const kStaffPermAuditView;
extern NSString * const kStaffPermModerationView;
extern NSString * const kStaffPermModerationManage;
extern NSString * const kStaffPermCampaignsView;
extern NSString * const kStaffPermCampaignsEdit;
extern NSString * const kStaffPermCampaignsPublish;
extern NSString * const kStaffPermCampaignsSettings;
extern NSString * const kStaffPermCategoriesView;
extern NSString * const kStaffPermCategoriesManage;
extern NSString * const kStaffPermVeterinariansView;
extern NSString * const kStaffPermVeterinariansManage;
extern NSString * const kStaffPermHomeControlView;
extern NSString * const kStaffPermHomeControlManage;
extern NSString * const kStaffPermHotelView;
extern NSString * const kStaffPermHotelReservationsManage;
extern NSString * const kStaffPermHotelCheckIn;
extern NSString * const kStaffPermHotelCheckOut;
extern NSString * const kStaffPermHotelAccommodationsManage;
extern NSString * const kStaffPermHotelCareView;
extern NSString * const kStaffPermHotelCareManage;
extern NSString * const kStaffPermHotelTaskRead;
extern NSString * const kStaffPermHotelTaskAssign;
extern NSString * const kStaffPermHotelTaskExecute;
extern NSString * const kStaffPermHotelMedicationRead;
extern NSString * const kStaffPermHotelMedicationManage;
extern NSString * const kStaffPermHotelMedicationAdminister;
extern NSString * const kStaffPermHotelHealthRead;
extern NSString * const kStaffPermHotelHealthCreate;
extern NSString * const kStaffPermHotelHealthManage;
extern NSString * const kStaffPermHotelIncidentsView;
extern NSString * const kStaffPermHotelIncidentsManage;
extern NSString * const kStaffPermHotelServicesManage;
extern NSString * const kStaffPermHotelMediaView;
extern NSString * const kStaffPermHotelMediaManage;
extern NSString * const kStaffPermHotelBillingView;
extern NSString * const kStaffPermHotelBillingManage;
extern NSString * const kStaffPermHotelBillingAdjust;
extern NSString * const kStaffPermHotelTransportManage;
extern NSString * const kStaffPermHotelNotificationsManage;
extern NSString * const kStaffPermHotelReportsView;
extern NSString * const kStaffPermHotelSettingsManage;
extern NSString * const kStaffPermHotelOverride;
extern NSString * const kStaffPermBannersView;
extern NSString * const kStaffPermBannersManage;

#pragma mark - Catalog Accessors

FOUNDATION_EXPORT NSArray<NSString *> * PPStaffAllPermissionKeys(void);
FOUNDATION_EXPORT NSArray<NSString *> * PPStaffDefaultPermissionsForRole(PPStaffRole role);
FOUNDATION_EXPORT BOOL PPStaffIsAdminRole(PPStaffRole role);
FOUNDATION_EXPORT BOOL PPStaffIsRootRole(PPStaffRole role);
FOUNDATION_EXPORT PPStaffRole PPStaffNormalizedRole(id _Nullable value);
FOUNDATION_EXPORT NSString * PPStaffLocalizedRoleName(PPStaffRole role);

NS_ASSUME_NONNULL_END
