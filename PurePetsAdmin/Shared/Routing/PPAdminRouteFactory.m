#import "PPAdminRouteFactory.h"

#import "Payments/PPPaymentManagementViewController.h"
#import "Payments/PPPaymentDetailsViewController.h"
#import "Payments/PPPaymentManagementService.h"
#import "Payments/PPPaymentBasicsSettingsViewController.h"
#import "Delivery/PPDeliveryManagementViewController.h"
#import "Providers/PPProviderApplicationsViewController.h"
#import "Providers/PPProviderPlansViewController.h"
#import "Providers/PPProviderFeatureAccessViewController.h"
#import "Providers/PPProviderAccountingViewController.h"
#import "POS/PPPOSFastSellViewController.h"
#import "POS/PPPOSHistoryViewController.h"
#import "Accounting/PPAccountingViewController.h"
#import "CategoriesSection/PPAuditLogViewController.h"
#import "CategoriesSection/PPCategoriesViewController.h"
#import "CategoriesSection/PPContentModerationViewController.h"
#import "CategoriesSection/PPListingsAdminViewController.h"
#import "AccessorySection/AccessoriesListViewController.h"
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
// Legacy PPVetsListViewController replaced by SwiftUI PPVetsListView
#import "Banners/PPBannersListVC.h"
#import "PurePetsAdmin-Swift.h"

@interface PPAdminPaymentOrderRouteViewController : UIViewController
- (instancetype)initWithOrderID:(NSString *)orderID;
@end

@interface PPAdminPaymentOrderRouteViewController ()
@property (nonatomic, copy) NSString *orderID;
@property (nonatomic, strong) UIActivityIndicatorView *indicator;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *retryButton;
@end

@implementation PPAdminPaymentOrderRouteViewController

- (instancetype)initWithOrderID:(NSString *)orderID {
    self = [super initWithNibName:nil bundle:nil];
    if (self) _orderID = [orderID copy] ?: @"";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;
    self.title = kLang(@"PaymentMgmt_Title_List");

    self.indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.indicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.indicator.color = AppPrimaryClr;
    [self.view addSubview:self.indicator];

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [Styling fontMedium:16.0];
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.textColor = PrimaryTextClr;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    [self.view addSubview:self.statusLabel];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.retryButton.titleLabel.font = [Styling fontBold:16.0];
    [self.retryButton setTitle:kLang(@"Retry") forState:UIControlStateNormal];
    [self.retryButton addTarget:self action:@selector(pp_loadOrder) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.view addSubview:self.retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.indicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.indicator.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor constant:-30.0],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.indicator.bottomAnchor constant:16.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [self.retryButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12.0],
        [self.retryButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.retryButton.heightAnchor constraintGreaterThanOrEqualToConstant:44.0]
    ]];
    [self pp_loadOrder];
}

- (void)pp_loadOrder {
    if (self.orderID.length == 0) {
        self.statusLabel.text = kLang(@"PaymentMgmt_Error_OrderNotFound");
        self.retryButton.hidden = YES;
        return;
    }
    self.retryButton.hidden = YES;
    self.statusLabel.text = kLang(@"PaymentMgmt_Loading_PaymentDetails");
    [self.indicator startAnimating];

    __weak typeof(self) weakSelf = self;
    [[PPPaymentManagementService shared] loadFullRecordForOrderID:self.orderID completion:^(PPPaymentAdminRecord * _Nullable record,
                                                                                             NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self.indicator stopAnimating];
            if (!record || error) {
                self.statusLabel.text = error.localizedDescription ?: kLang(@"PaymentMgmt_Error_OrderNotFound");
                self.retryButton.hidden = NO;
                return;
            }

            PPPaymentManagementViewController *payments = [PPPaymentManagementViewController new];
            PPPaymentDetailsViewController *details = [[PPPaymentDetailsViewController alloc] initWithRecord:record];
            [self.navigationController setViewControllers:@[payments, details] animated:NO];
        });
    }];
}

@end

@implementation PPAdminRouteFactory

+ (UIViewController *)makeSwiftUIHostingControllerForVets {
    return [PPVetsListHostingController new];
}

+ (UIViewController *)viewControllerForRouteIdentifier:(NSString *)identifier payload:(NSString *)payload {
    if ([identifier isEqualToString:@"paymentOrder"]) return [[PPAdminPaymentOrderRouteViewController alloc] initWithOrderID:payload ?: @""];
    if ([identifier isEqualToString:@"payments"]) return [PPPaymentManagementViewController new];
    if ([identifier isEqualToString:@"paymentSettings"]) return [PPPaymentBasicsSettingsViewController new];
    if ([identifier isEqualToString:@"fulfillment"]) return [PPFulfillmentOrdersViewController new];
    if ([identifier isEqualToString:@"delivery"]) return [PPDeliveryManagementViewController new];
    if ([identifier isEqualToString:@"providerApplications"]) return [PPProviderApplicationsViewController new];
    if ([identifier isEqualToString:@"providerPlans"]) return [PPProviderPlansViewController new];
    if ([identifier isEqualToString:@"providerFeatures"]) return [PPProviderFeatureAccessViewController new];
    if ([identifier isEqualToString:@"providerAccounting"]) return [PPProviderAccountingViewController new];
    if ([identifier isEqualToString:@"pos"]) return [PPPOSFastSellViewController new];
    if ([identifier isEqualToString:@"posHistory"]) return [PPPOSHistoryViewController new];
    if ([identifier isEqualToString:@"users"]) return [[UsersListVC alloc] initWithViewFor:ViewForEditAccount];
    if ([identifier isEqualToString:@"staff"]) return [PPStaffManagementViewController new];
    if ([identifier isEqualToString:@"account"]) {
        UserModel *currentUser = [UserManager shared].currentUser;
        return currentUser ? [UserManagementController accountEditorForUser:currentUser] : nil;
    }
    if ([identifier isEqualToString:@"chats"]) return [PPChatsViewController new];
    if ([identifier isEqualToString:@"notifications"]) return [NotificationsListViewController new];
    if ([identifier isEqualToString:@"notificationComposer"]) return [NotificationComposerViewController new];
    if ([identifier isEqualToString:@"notificationSettings"]) return [NotificationSettingsViewController new];
    if ([identifier isEqualToString:@"settings"]) return [PPSettingsViewController new];
    if ([identifier isEqualToString:@"accessories"]) return [[AccessoriesListViewController alloc] initWithKind:AccessTypeAccessory];
    if ([identifier isEqualToString:@"food"]) return [[AccessoriesListViewController alloc] initWithKind:AccessTypeFood];
    if ([identifier isEqualToString:@"livePets"]) return [[AccessoriesListViewController alloc] initWithKind:AccessTypeLivePets];
    if ([identifier isEqualToString:@"branches"]) return [PPBranchesViewController new];
    if ([identifier isEqualToString:@"agents"]) return [PPAgentsViewController new];
    if ([identifier isEqualToString:@"accounting"]) return [PPAccountingViewController new];
    if ([identifier isEqualToString:@"audit"]) return [PPAuditLogViewController new];
    if ([identifier isEqualToString:@"moderation"]) return [PPContentModerationViewController new];
    if ([identifier isEqualToString:@"homeControl"]) return [PPHomeControlPanelViewController new];
    if ([identifier isEqualToString:@"services"]) return [PPServicesListViewController new];
    if ([identifier isEqualToString:@"vets"]) return [PPAdminRouteFactory makeSwiftUIHostingControllerForVets];
    if ([identifier isEqualToString:@"categories"]) return [PPCategoriesViewController new];
    if ([identifier isEqualToString:@"banners"]) return [PPBannersListVC new];
    if ([identifier isEqualToString:@"listings"]) return [PPListingsAdminViewController new];
    return nil;
}

@end
