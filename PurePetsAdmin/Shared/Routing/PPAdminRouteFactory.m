#import "PPAdminRouteFactory.h"

#import "Providers/PPProviderApplicationsViewController.h"
#import "Providers/PPProviderPlansViewController.h"
#import "Providers/PPProviderFeatureAccessViewController.h"
#import "Providers/PPProviderAccountingViewController.h"
#import "Accounting/PPAccountingViewController.h"
#import "CategoriesSection/PPAuditLogViewController.h"
#import "CategoriesSection/PPCategoriesViewController.h"
#import "CategoriesSection/PPContentModerationViewController.h"
#import "CategoriesSection/PPListingsAdminViewController.h"
#import "BranchSection/PPBranchesViewController.h"
#import "AgentSection/PPAgentsViewController.h"
#import "UsersSection/UserController/UsersListVC.h"
#import "UsersSection/UserController/PPStaffManagementViewController.h"
#import "UsersSection/UserController/UserManagementController.h"
#import "UsersSection/References/UserManager.h"
#import "NotificationsSection/NotificationsListViewController.h"
#import "NotificationsSection/NotificationComposerViewController.h"
#import "NotificationsSection/NotificationSettingsViewController.h"
#import "ThirdParty/PPCells/PPChatsViewController.h"
#import "ThirdParty/PPCells/PPSettingsViewController.h"
#import "HomeControl/PPHomeControlPanelViewController.h"
#import "ServicesSection/PPServicesListViewController.h"
#import "Banners/PPBannersListVC.h"
#import "PurePetsAdmin-Swift.h"

@implementation PPAdminRouteFactory

+ (UIViewController *)makeSwiftUIHostingControllerForVets {
    return [PPVetsListHostingController new];
}

+ (UIViewController *)viewControllerForRouteIdentifier:(NSString *)identifier payload:(NSString *)payload {
    if ([identifier isEqualToString:@"paymentOrder"]) return [[AdminPaymentDetailHostingController alloc] initWithOrderID:payload ?: @""];
    if ([identifier isEqualToString:@"payments"]) return [AdminPaymentListHostingController new];
    if ([identifier isEqualToString:@"paymentSettings"]) return [AdminPaymentSettingsHostingController new];
    if ([identifier isEqualToString:@"fulfillment"]) return [AdminFulfillmentListHostingController new];
    if ([identifier isEqualToString:@"delivery"]) return [AdminDeliveryListHostingController new];
    if ([identifier isEqualToString:@"providerApplications"]) return [PPProviderApplicationsHostingController new];
    if ([identifier isEqualToString:@"providerPlans"]) return [PPProviderPlansViewController new];
    if ([identifier isEqualToString:@"providerFeatures"]) return [PPProviderFeatureAccessViewController new];
    if ([identifier isEqualToString:@"providerAccounting"]) return [PPProviderAccountingViewController new];
    if ([identifier isEqualToString:@"pos"]) return [AdminPOSFastSellHostingController new];
    if ([identifier isEqualToString:@"posHistory"]) return [AdminPOSHistoryHostingController new];
    if ([identifier isEqualToString:@"users"]) return [PPAdminUsersListHostingController new];
    if ([identifier isEqualToString:@"staff"]) return [AdminStaffManagementHostingController new];
    if ([identifier isEqualToString:@"account"]) {
        UserModel *currentUser = [UserManager shared].currentUser;
        return currentUser ? [[PPAdminProfileViewController alloc] initWithUser:currentUser] : nil;
    }
    if ([identifier isEqualToString:@"chats"]) return [PPAdminChatsHostingController new];
    if ([identifier isEqualToString:@"notifications"]) return [NotificationsListViewController new];
    if ([identifier isEqualToString:@"notificationComposer"]) return [NotificationComposerViewController new];
    if ([identifier isEqualToString:@"notificationSettings"]) return [NotificationSettingsViewController new];
    if ([identifier isEqualToString:@"settings"]) return [PPSettingsViewController new];
    if ([identifier isEqualToString:@"accessories"]) return [PPInventoryListHostingController makeForAccessories];
    if ([identifier isEqualToString:@"food"]) return [PPInventoryListHostingController makeForFood];
    if ([identifier isEqualToString:@"livePets"]) return [PPInventoryListHostingController makeForLivePets];
    if ([identifier isEqualToString:@"branches"]) return [AdminBranchesHostingController new];
    if ([identifier isEqualToString:@"agents"]) return [PPAgentsViewController new];
    if ([identifier isEqualToString:@"accounting"]) return [PPAccountingViewController new];
    if ([identifier isEqualToString:@"audit"]) return [PPAuditLogViewController new];
    if ([identifier isEqualToString:@"moderation"]) return [PPContentModerationViewController new];
    if ([identifier isEqualToString:@"homeControl"]) return [AdminHomeControlHostingController new];
    if ([identifier isEqualToString:@"services"]) return [PPServicesListViewController new];
    if ([identifier isEqualToString:@"vets"]) return [PPAdminRouteFactory makeSwiftUIHostingControllerForVets];
    if ([identifier isEqualToString:@"categories"]) return [PPCategoriesViewController new];
    if ([identifier isEqualToString:@"banners"]) return [PPBannersListVC new];
    if ([identifier isEqualToString:@"listings"]) return [PPListingsAdminViewController new];
    return nil;
}

@end
