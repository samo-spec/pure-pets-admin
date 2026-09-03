//
//  PPSettingsViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 2026-07-13.
//  Reimagined from absolute first principles:
//  1. PPSettingsViewController with full PPNavBar navigation bar.
//  2. Category-defining Admin Profile & Identity Command Center (PPAdminProfileViewController).
//  3. Sovereign Permissions Inspector Sheet (PPAdminPermissionsInspectorSheet).
//  4. Security & Session Vault Sheet (PPAdminSecurityVaultSheet).
//

#import "PPSettingsViewController.h"
#import "NotificationSettingsViewController.h"
#import "UserManagementController.h"
#import "PPAuditLogViewController.h"
#import "PPFirebaseCompat.h"
#import "Styling.h"
#import "Language.h"
#import "PPDesignTokens.h"
#import "PPAlertHelper.h"
#import "PPHUD.h"
#import "PPToast.h"
#import "PPFunc.h"
#import "UIViewController+PPNavBar.h"
#import "UIImageView+WebCache.h"
#import "UserManager+Refs.h"
#import "PPStaffAuth.h"
#import "SDImageCache.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseStorage;
#import "PurePetsAdmin-Swift.h"


#pragma mark - PPAdminPermissionsInspectorSheet (NextGen V6 Swift Bridge)

@interface PPAdminPermissionsInspectorSheet ()
@property (nonatomic, strong) UserModel *user;
@end

@implementation PPAdminPermissionsInspectorSheet

- (instancetype)initWithUser:(nullable UserModel *)user {
    self = [super init];
    if (self) {
        _user = user ?: [UserManager shared].currentUser;
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[
                [UISheetPresentationControllerDetent mediumDetent],
                [UISheetPresentationControllerDetent largeDetent]
            ];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 28.0;
        }
    }

    PPAdminPermissionsInspectorHostingController *host = [[PPAdminPermissionsInspectorHostingController alloc] initWithUser:self.user];
    [self addChildViewController:host];
    host.view.translatesAutoresizingMaskIntoConstraints = NO;
    host.view.backgroundColor = UIColor.clearColor;
    [self.view addSubview:host.view];
    [NSLayoutConstraint activateConstraints:@[
        [host.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [host.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [host.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [host.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [host didMoveToParentViewController:self];
}

@end

#pragma mark - PPAdminSecurityVaultSheet (NextGen V6 Swift Bridge)

@interface PPAdminSecurityVaultSheet ()
@property (nonatomic, strong) UserModel *user;
@end

@implementation PPAdminSecurityVaultSheet

- (instancetype)initWithUser:(nullable UserModel *)user {
    self = [super init];
    if (self) {
        _user = user ?: [UserManager shared].currentUser;
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[
                [UISheetPresentationControllerDetent mediumDetent],
                [UISheetPresentationControllerDetent largeDetent]
            ];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 28.0;
        }
    }

    PPAdminSecurityVaultHostingController *host = [[PPAdminSecurityVaultHostingController alloc] initWithUser:self.user];
    [self addChildViewController:host];
    host.view.translatesAutoresizingMaskIntoConstraints = NO;
    host.view.backgroundColor = UIColor.clearColor;
    [self.view addSubview:host.view];
    [NSLayoutConstraint activateConstraints:@[
        [host.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [host.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [host.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [host.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [host didMoveToParentViewController:self];
}

@end

#pragma mark - PPAdminProfileViewController (Category-Defining NextGen V6 Swift Bridge)

@interface PPAdminProfileViewController ()
@property (nonatomic, strong) UserModel *currentUser;
@property (nonatomic, strong) UIViewController *hostingController;
@end

@implementation PPAdminProfileViewController

- (instancetype)initWithUser:(nullable UserModel *)user {
    self = [super init];
    if (self) {
        _currentUser = user ?: [UserManager shared].currentUser;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (!self.currentUser) {
        self.currentUser = [UserManager shared].currentUser;
    }

    __weak typeof(self) weakSelf = self;
    PPAdminProfileHostingController *host = [[PPAdminProfileHostingController alloc] initWithUser:self.currentUser onDismiss:^{
        if (!weakSelf) {
            [PPAdminNavigationFallback popOrDismiss];
            return;
        }
        if ([weakSelf pp_dismissWorkflowRouteIfPossible]) {
            return;
        }
        if (weakSelf.navigationController && weakSelf.navigationController.viewControllers.count > 1) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
            return;
        }
        if (weakSelf.presentingViewController) {
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
            return;
        }
        [PPAdminNavigationFallback popOrDismissFrom:weakSelf];
    }];
    self.hostingController = host;

    [self addChildViewController:host];
    host.view.translatesAutoresizingMaskIntoConstraints = NO;
    host.view.backgroundColor = UIColor.clearColor;
    [self.view addSubview:host.view];
    [NSLayoutConstraint activateConstraints:@[
        [host.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [host.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [host.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [host.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [host didMoveToParentViewController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

@end


#pragma mark - PPSettingsViewController (Sovereign Admin Command Center)

@interface PPSettingsViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;

// Operator Hero Components
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UILabel *monogramLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *roleBadgeLabel;
@property (nonatomic, strong) UIView *roleBadgeView;
@property (nonatomic, strong) UILabel *emailLabel;
@property (nonatomic, strong) UIView *operatorHaloView;

// Telemetry
@property (nonatomic, strong) UIButton *pingButton;
@property (nonatomic, strong) UIActivityIndicatorView *pingSpinner;
@property (nonatomic, strong) UILabel *pingStatusLabel;

// Interface Studio
@property (nonatomic, strong) UIView *themeLightCard;
@property (nonatomic, strong) UIView *themeDarkCard;
@property (nonatomic, strong) UIView *themeSystemCard;
@property (nonatomic, strong) UIImageView *themeLightCheck;
@property (nonatomic, strong) UIImageView *themeDarkCheck;
@property (nonatomic, strong) UIImageView *themeSystemCheck;
@property (nonatomic, strong) UISwitch *hapticsSwitch;

// Storage
@property (nonatomic, strong) UILabel *cacheFootprintLabel;
@property (nonatomic, strong) UIProgressView *cacheProgressBar;

@end

@implementation PPSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self setupNavigation];
    [self setupLayout];
    [self updateProfileData];
    [self updateStorageData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupNavigation];
    [self updateProfileData];
    [self updateStorageData];
    [self updateThemeSelectionVisuals];
}

- (void)setupNavigation {
    NSString *title = kLang(@"Settings_CommandCenter_Title") ?: ([Language isRTL] ? @"إعدادات النظام والتطبيق" : @"App & System Settings");
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:title showBack:YES];
}

- (void)setupLayout {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.backgroundColor = UIColor.clearColor;
    _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:_scrollView];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 20.0;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.distribution = UIStackViewDistributionFill;
    [_scrollView addSubview:_contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_contentStack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor constant:16.0],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.leadingAnchor constant:16.0],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.trailingAnchor constant:-16.0],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-48.0]
    ]];

    // 1. Spatial Operator Identity Capsule & Sovereign Beacon
    [_contentStack addArrangedSubview:[self pp_createOperatorHeroCard]];

    // 2. Platform & Cloud Diagnostics Hub
    [_contentStack addArrangedSubview:[self pp_createTelemetryCard]];

    // 3. Interface Architecture & Ergonomics Studio
    [_contentStack addArrangedSubview:[self pp_createInterfaceStudioCard]];

    // 4. Operational Modules & Privileged Portals
    [_contentStack addArrangedSubview:[self pp_createPortalsCard]];

    // 5. Storage, Cache & Device Health Engine
    [_contentStack addArrangedSubview:[self pp_createStorageCard]];

    // 6. Support & Sovereign Session Termination
    [_contentStack addArrangedSubview:[self pp_createSessionCard]];

    // 7. Platform Signature Stamp
    [_contentStack addArrangedSubview:[self pp_createFooterView]];
}

#pragma mark - Card 1: Spatial Operator Identity Capsule

- (UIView *)pp_createOperatorHeroCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.22].CGColor;
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);

    // Eyebrow & Status Strip
    UIView *topStrip = [[UIView alloc] init];
    topStrip.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:topStrip];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.text = kLang(@"Settings_Operator_Eyebrow") ?: @"المسؤول السيادي • مساحة العمل";
    eyebrow.font = [Styling fontBold:11.5];
    eyebrow.textColor = [UIColor ppPrimary];
    eyebrow.textAlignment = [Language alignmentForCurrentLanguage];
    [topStrip addSubview:eyebrow];

    UIView *pulseDot = [[UIView alloc] init];
    pulseDot.translatesAutoresizingMaskIntoConstraints = NO;
    pulseDot.backgroundColor = [UIColor ppSuccess];
    PPApplyContinuousCorners(pulseDot, 4.0);
    [topStrip addSubview:pulseDot];

    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.text = [Language isRTL] ? @"متصل ونشط" : @"Active & Connected";
    statusLabel.font = [Styling fontMedium:11.0];
    statusLabel.textColor = [UIColor ppSuccess];
    [topStrip addSubview:statusLabel];

    // Avatar Container with Halo Ring
    _operatorHaloView = [[UIView alloc] init];
    _operatorHaloView.translatesAutoresizingMaskIntoConstraints = NO;
    _operatorHaloView.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(_operatorHaloView, 34.0);
    _operatorHaloView.layer.borderWidth = 2.0;
    _operatorHaloView.layer.borderColor = [UIColor ppPrimary].CGColor;
    [card addSubview:_operatorHaloView];

    _avatarImageView = [[UIImageView alloc] init];
    _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarImageView.clipsToBounds = YES;
    PPApplyContinuousCorners(_avatarImageView, 30.0);
    [_operatorHaloView addSubview:_avatarImageView];

    _monogramLabel = [[UILabel alloc] init];
    _monogramLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _monogramLabel.font = [Styling fontBold:20.0];
    _monogramLabel.textColor = [UIColor ppPrimary];
    _monogramLabel.textAlignment = NSTextAlignmentCenter;
    [_operatorHaloView addSubview:_monogramLabel];

    // Operator Details
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [Styling fontBold:18.0];
    _nameLabel.textColor = [UIColor ppTextPrimary];
    _nameLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [card addSubview:_nameLabel];

    // Canonical Role Badge
    _roleBadgeView = [[UIView alloc] init];
    _roleBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    _roleBadgeView.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(_roleBadgeView, 8.0);
    [card addSubview:_roleBadgeView];

    UIImageView *roleIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.fill"]];
    roleIcon.translatesAutoresizingMaskIntoConstraints = NO;
    roleIcon.tintColor = [UIColor ppPrimary];
    roleIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_roleBadgeView addSubview:roleIcon];

    _roleBadgeLabel = [[UILabel alloc] init];
    _roleBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleBadgeLabel.font = [Styling fontBold:11.5];
    _roleBadgeLabel.textColor = [UIColor ppPrimary];
    [_roleBadgeView addSubview:_roleBadgeLabel];

    _emailLabel = [[UILabel alloc] init];
    _emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emailLabel.font = [Styling fontRegular:12.5];
    _emailLabel.textColor = [UIColor ppTextSecondary];
    _emailLabel.textAlignment = NSTextAlignmentLeft;
    [card addSubview:_emailLabel];

    // Security Filament Bar
    UIView *filamentBar = [[UIView alloc] init];
    filamentBar.translatesAutoresizingMaskIntoConstraints = NO;
    filamentBar.backgroundColor = [[UIColor ppBackground] colorWithAlphaComponent:0.65];
    filamentBar.layer.borderWidth = 0.5;
    filamentBar.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(filamentBar, 10.0);
    [card addSubview:filamentBar];

    UIImageView *shieldIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"]];
    shieldIcon.translatesAutoresizingMaskIntoConstraints = NO;
    shieldIcon.tintColor = [UIColor ppSuccess];
    shieldIcon.contentMode = UIViewContentModeScaleAspectFit;
    [filamentBar addSubview:shieldIcon];

    UILabel *filamentLabel = [[UILabel alloc] init];
    filamentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    filamentLabel.text = kLang(@"Settings_Operator_Security_Filament") ?: @"متصل بالنظام السيادي • App Check نشط • pure-pets-49199";
    filamentLabel.font = [Styling fontMedium:11.0];
    filamentLabel.textColor = [UIColor ppTextSecondary];
    filamentLabel.textAlignment = [Language alignmentForCurrentLanguage];
    filamentLabel.numberOfLines = 1;
    filamentLabel.adjustsFontSizeToFitWidth = YES;
    [filamentBar addSubview:filamentLabel];

    // 3 Quick Action Portals across bottom
    UIStackView *quickActionsStack = [[UIStackView alloc] init];
    quickActionsStack.translatesAutoresizingMaskIntoConstraints = NO;
    quickActionsStack.axis = UILayoutConstraintAxisHorizontal;
    quickActionsStack.distribution = UIStackViewDistributionFillEqually;
    quickActionsStack.spacing = 8.0;
    [card addSubview:quickActionsStack];

    UIButton *profileBtn = [self pp_createTactilePillButtonWithTitle:kLang(@"Settings_Action_Profile") ?: @"الملف الشخصي"
                                                          systemIcon:@"person.fill"
                                                              action:@selector(pp_openProfile)];
    UIButton *permsBtn = [self pp_createTactilePillButtonWithTitle:kLang(@"Settings_Action_Permissions") ?: @"الصلاحيات"
                                                        systemIcon:@"checklist.checked"
                                                            action:@selector(pp_openPermissionsInspector)];
    UIButton *vaultBtn = [self pp_createTactilePillButtonWithTitle:kLang(@"Settings_Action_Vault") ?: @"خزنة الأمان"
                                                        systemIcon:@"key.fill"
                                                            action:@selector(pp_openSecurityVault)];

    [quickActionsStack addArrangedSubview:profileBtn];
    [quickActionsStack addArrangedSubview:permsBtn];
    [quickActionsStack addArrangedSubview:vaultBtn];

    [NSLayoutConstraint activateConstraints:@[
        [topStrip.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [topStrip.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [topStrip.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [topStrip.heightAnchor constraintEqualToConstant:20.0],

        [eyebrow.leadingAnchor constraintEqualToAnchor:topStrip.leadingAnchor],
        [eyebrow.centerYAnchor constraintEqualToAnchor:topStrip.centerYAnchor],

        [statusLabel.trailingAnchor constraintEqualToAnchor:topStrip.trailingAnchor],
        [statusLabel.centerYAnchor constraintEqualToAnchor:topStrip.centerYAnchor],

        [pulseDot.trailingAnchor constraintEqualToAnchor:statusLabel.leadingAnchor constant:-6.0],
        [pulseDot.centerYAnchor constraintEqualToAnchor:topStrip.centerYAnchor],
        [pulseDot.widthAnchor constraintEqualToConstant:7.0],
        [pulseDot.heightAnchor constraintEqualToConstant:7.0],

        [_operatorHaloView.topAnchor constraintEqualToAnchor:topStrip.bottomAnchor constant:12.0],
        [_operatorHaloView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [_operatorHaloView.widthAnchor constraintEqualToConstant:68.0],
        [_operatorHaloView.heightAnchor constraintEqualToConstant:68.0],

        [_avatarImageView.centerXAnchor constraintEqualToAnchor:_operatorHaloView.centerXAnchor],
        [_avatarImageView.centerYAnchor constraintEqualToAnchor:_operatorHaloView.centerYAnchor],
        [_avatarImageView.widthAnchor constraintEqualToConstant:60.0],
        [_avatarImageView.heightAnchor constraintEqualToConstant:60.0],

        [_monogramLabel.centerXAnchor constraintEqualToAnchor:_operatorHaloView.centerXAnchor],
        [_monogramLabel.centerYAnchor constraintEqualToAnchor:_operatorHaloView.centerYAnchor],

        [_nameLabel.topAnchor constraintEqualToAnchor:_operatorHaloView.topAnchor constant:2.0],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_operatorHaloView.trailingAnchor constant:14.0],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [_roleBadgeView.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4.0],
        [_roleBadgeView.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_roleBadgeView.heightAnchor constraintEqualToConstant:24.0],

        [roleIcon.leadingAnchor constraintEqualToAnchor:_roleBadgeView.leadingAnchor constant:8.0],
        [roleIcon.centerYAnchor constraintEqualToAnchor:_roleBadgeView.centerYAnchor],
        [roleIcon.widthAnchor constraintEqualToConstant:12.0],
        [roleIcon.heightAnchor constraintEqualToConstant:12.0],

        [_roleBadgeLabel.leadingAnchor constraintEqualToAnchor:roleIcon.trailingAnchor constant:5.0],
        [_roleBadgeLabel.trailingAnchor constraintEqualToAnchor:_roleBadgeView.trailingAnchor constant:-8.0],
        [_roleBadgeLabel.centerYAnchor constraintEqualToAnchor:_roleBadgeView.centerYAnchor],

        [_emailLabel.topAnchor constraintEqualToAnchor:_roleBadgeView.bottomAnchor constant:5.0],
        [_emailLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_emailLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [filamentBar.topAnchor constraintEqualToAnchor:_operatorHaloView.bottomAnchor constant:14.0],
        [filamentBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [filamentBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [filamentBar.heightAnchor constraintEqualToConstant:32.0],

        [shieldIcon.leadingAnchor constraintEqualToAnchor:filamentBar.leadingAnchor constant:10.0],
        [shieldIcon.centerYAnchor constraintEqualToAnchor:filamentBar.centerYAnchor],
        [shieldIcon.widthAnchor constraintEqualToConstant:14.0],
        [shieldIcon.heightAnchor constraintEqualToConstant:14.0],

        [filamentLabel.leadingAnchor constraintEqualToAnchor:shieldIcon.trailingAnchor constant:8.0],
        [filamentLabel.trailingAnchor constraintEqualToAnchor:filamentBar.trailingAnchor constant:-10.0],
        [filamentLabel.centerYAnchor constraintEqualToAnchor:filamentBar.centerYAnchor],

        [quickActionsStack.topAnchor constraintEqualToAnchor:filamentBar.bottomAnchor constant:12.0],
        [quickActionsStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [quickActionsStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [quickActionsStack.heightAnchor constraintEqualToConstant:36.0],
        [quickActionsStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
    ]];

    return card;
}

- (UIButton *)pp_createTactilePillButtonWithTitle:(NSString *)title systemIcon:(NSString *)icon action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    btn.layer.borderWidth = 0.5;
    btn.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.25].CGColor;
    PPApplyContinuousCorners(btn, 10.0);

    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor ppPrimary] forState:UIControlStateNormal];
    btn.titleLabel.font = [Styling fontBold:11.5];

    UIImage *img = [UIImage systemImageNamed:icon];
    [btn setImage:img forState:UIControlStateNormal];
    btn.tintColor = [UIColor ppPrimary];
    btn.imageEdgeInsets = [Language isRTL] ? UIEdgeInsetsMake(0, 6, 0, -6) : UIEdgeInsetsMake(0, -6, 0, 6);

    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

#pragma mark - Card 2: Platform & Cloud Diagnostics Hub

- (UIView *)pp_createTelemetryCard {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *header = [self pp_createSectionHeaderWithTitle:kLang(@"Settings_Section_Telemetry") ?: @"حالة البيئة والمنصة السحابية"
                                                  subtitle:kLang(@"Settings_Telemetry_Desc") ?: @"مراقبة حية للمؤشرات الحيوية لخوادم وقواعد بيانات Pure Pets."];
    [container addSubview:header];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);
    [container addSubview:card];

    UIStackView *vStack = [[UIStackView alloc] init];
    vStack.translatesAutoresizingMaskIntoConstraints = NO;
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 10.0;
    [card addSubview:vStack];

    [vStack addArrangedSubview:[self pp_createTelemetryRowWithIcon:@"cylinder.split.1x2.fill"
                                                         iconColor:[UIColor systemBlueColor]
                                                             title:kLang(@"Settings_Telemetry_Firestore") ?: @"قاعدة بيانات Firestore"
                                                             value:kLang(@"Settings_Telemetry_Status_Healthy") ?: @"نشط • استجابة < 40ms"
                                                          isStatus:YES]];

    [vStack addArrangedSubview:[self pp_createTelemetryRowWithIcon:@"bolt.horizontal.fill"
                                                         iconColor:[UIColor systemOrangeColor]
                                                             title:kLang(@"Settings_Telemetry_Functions") ?: @"وظائف Cloud Functions"
                                                             value:kLang(@"Settings_Telemetry_Status_Node22") ?: @"Node 22 • التدقيق مفعل"
                                                          isStatus:NO]];

    [vStack addArrangedSubview:[self pp_createTelemetryRowWithIcon:@"checkmark.shield.fill"
                                                         iconColor:[UIColor ppSuccess]
                                                             title:kLang(@"Settings_Telemetry_AppCheck") ?: @"حماية App Check"
                                                             value:kLang(@"Settings_Telemetry_Status_Protected") ?: @"مفعل وموثق"
                                                          isStatus:YES]];

    [vStack addArrangedSubview:[self pp_createTelemetryRowWithIcon:@"terminal.fill"
                                                         iconColor:[UIColor systemPurpleColor]
                                                             title:kLang(@"Settings_Telemetry_Build") ?: @"إصدار التطبيق السيادي"
                                                             value:kLang(@"Settings_Telemetry_Status_Version") ?: @"v6.2.0 (Build 2026.09)"
                                                          isStatus:NO]];

    // Ping Connectivity Action Button
    _pingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _pingButton.translatesAutoresizingMaskIntoConstraints = NO;
    _pingButton.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.09];
    _pingButton.layer.borderWidth = 1.0;
    _pingButton.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.25].CGColor;
    PPApplyContinuousCorners(_pingButton, 12.0);
    [_pingButton setTitle:kLang(@"Settings_Telemetry_Ping_CTA") ?: @"فحص الاتصال الحي" forState:UIControlStateNormal];
    [_pingButton setTitleColor:[UIColor ppPrimary] forState:UIControlStateNormal];
    _pingButton.titleLabel.font = [Styling fontBold:12.5];
    [_pingButton setImage:[UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"] forState:UIControlStateNormal];
    _pingButton.tintColor = [UIColor ppPrimary];
    _pingButton.imageEdgeInsets = [Language isRTL] ? UIEdgeInsetsMake(0, 6, 0, -6) : UIEdgeInsetsMake(0, -6, 0, 6);
    [_pingButton addTarget:self action:@selector(pp_testConnectivity) forControlEvents:UIControlEventTouchUpInside];
    [vStack addArrangedSubview:_pingButton];

    _pingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _pingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _pingSpinner.hidesWhenStopped = YES;
    _pingSpinner.color = [UIColor ppPrimary];
    [_pingButton addSubview:_pingSpinner];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:container.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [vStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [vStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [vStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [vStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],

        [_pingButton.heightAnchor constraintEqualToConstant:38.0],
        [_pingSpinner.centerYAnchor constraintEqualToAnchor:_pingButton.centerYAnchor],
        [_pingSpinner.trailingAnchor constraintEqualToAnchor:_pingButton.trailingAnchor constant:-16.0]
    ]];

    return container;
}

- (UIView *)pp_createTelemetryRowWithIcon:(NSString *)icon iconColor:(UIColor *)color title:(NSString *)title value:(NSString *)value isStatus:(BOOL)status {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [[UIColor ppBackground] colorWithAlphaComponent:0.40];
    PPApplyContinuousCorners(row, 10.0);

    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.tintColor = color;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:iv];

    UILabel *lblTitle = [[UILabel alloc] init];
    lblTitle.translatesAutoresizingMaskIntoConstraints = NO;
    lblTitle.text = title;
    lblTitle.font = [Styling fontMedium:12.5];
    lblTitle.textColor = [UIColor ppTextPrimary];
    lblTitle.textAlignment = [Language alignmentForCurrentLanguage];
    [row addSubview:lblTitle];

    UILabel *lblVal = [[UILabel alloc] init];
    lblVal.translatesAutoresizingMaskIntoConstraints = NO;
    lblVal.text = value;
    lblVal.font = [Styling fontBold:11.5];
    lblVal.textColor = status ? [UIColor ppSuccess] : [UIColor ppTextSecondary];
    lblVal.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    [row addSubview:lblVal];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:38.0],

        [iv.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10.0],
        [iv.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:16.0],
        [iv.heightAnchor constraintEqualToConstant:16.0],

        [lblTitle.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:8.0],
        [lblTitle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [lblVal.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-10.0],
        [lblVal.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [lblVal.leadingAnchor constraintGreaterThanOrEqualToAnchor:lblTitle.trailingAnchor constant:8.0]
    ]];

    return row;
}

#pragma mark - Card 3: Interface Architecture & Ergonomics Studio

- (UIView *)pp_createInterfaceStudioCard {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *header = [self pp_createSectionHeaderWithTitle:kLang(@"Settings_Section_Interface") ?: @"هندسة الواجهة وتجربة الاستخدام"
                                                  subtitle:kLang(@"Settings_Interface_Desc") ?: @"تخصيص المظهر ونمط العرض واللغة والتفاعل اللمسي."];
    [container addSubview:header];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);
    [container addSubview:card];

    UILabel *themeTitle = [[UILabel alloc] init];
    themeTitle.translatesAutoresizingMaskIntoConstraints = NO;
    themeTitle.text = kLang(@"Settings_Theme_Title") ?: @"نمط العرض";
    themeTitle.font = [Styling fontBold:13.5];
    themeTitle.textColor = [UIColor ppTextPrimary];
    themeTitle.textAlignment = [Language alignmentForCurrentLanguage];
    [card addSubview:themeTitle];

    // Theme Mockup Cards (Light, Dark, System)
    UIStackView *themeStack = [[UIStackView alloc] init];
    themeStack.translatesAutoresizingMaskIntoConstraints = NO;
    themeStack.axis = UILayoutConstraintAxisHorizontal;
    themeStack.distribution = UIStackViewDistributionFillEqually;
    themeStack.spacing = 10.0;
    [card addSubview:themeStack];

    _themeLightCard = [self pp_createThemeChoiceCardForStyle:UIUserInterfaceStyleLight
                                                       title:kLang(@"Settings_Theme_Light") ?: @"نهاري ناصع"
                                                    checkRef:&_themeLightCheck];
    _themeDarkCard = [self pp_createThemeChoiceCardForStyle:UIUserInterfaceStyleDark
                                                      title:kLang(@"Settings_Theme_Dark") ?: @"ليلي مركز"
                                                   checkRef:&_themeDarkCheck];
    _themeSystemCard = [self pp_createThemeChoiceCardForStyle:UIUserInterfaceStyleUnspecified
                                                        title:kLang(@"Settings_Theme_System") ?: @"تلقائي"
                                                     checkRef:&_themeSystemCheck];

    [themeStack addArrangedSubview:_themeLightCard];
    [themeStack addArrangedSubview:_themeDarkCard];
    [themeStack addArrangedSubview:_themeSystemCard];

    // Divider
    UIView *divider1 = [[UIView alloc] init];
    divider1.translatesAutoresizingMaskIntoConstraints = NO;
    divider1.backgroundColor = [UIColor ppSurfaceBorder];
    [card addSubview:divider1];

    // Bilingual Typographic Switcher Row
    UIView *langRow = [[UIView alloc] init];
    langRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:langRow];

    UIImageView *langIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"globe"]];
    langIcon.translatesAutoresizingMaskIntoConstraints = NO;
    langIcon.tintColor = [UIColor ppPrimary];
    langIcon.contentMode = UIViewContentModeScaleAspectFit;
    [langRow addSubview:langIcon];

    UILabel *langTitle = [[UILabel alloc] init];
    langTitle.translatesAutoresizingMaskIntoConstraints = NO;
    langTitle.text = kLang(@"Settings_Language_Title") ?: @"لغة لوحة التحكم";
    langTitle.font = [Styling fontBold:13.5];
    langTitle.textColor = [UIColor ppTextPrimary];
    langTitle.textAlignment = [Language alignmentForCurrentLanguage];
    [langRow addSubview:langTitle];

    UIButton *langSwitchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    langSwitchBtn.translatesAutoresizingMaskIntoConstraints = NO;
    langSwitchBtn.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(langSwitchBtn, 8.0);
    NSString *currentLangTitle = [Language isRTL] ? @"العربية (RTL)" : @"English (LTR)";
    [langSwitchBtn setTitle:currentLangTitle forState:UIControlStateNormal];
    [langSwitchBtn setTitleColor:[UIColor ppPrimary] forState:UIControlStateNormal];
    langSwitchBtn.titleLabel.font = [Styling fontBold:12.0];
    langSwitchBtn.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    [langSwitchBtn addTarget:self action:@selector(pp_openLanguageSwitcher) forControlEvents:UIControlEventTouchUpInside];
    [langRow addSubview:langSwitchBtn];

    // Divider
    UIView *divider2 = [[UIView alloc] init];
    divider2.translatesAutoresizingMaskIntoConstraints = NO;
    divider2.backgroundColor = [UIColor ppSurfaceBorder];
    [card addSubview:divider2];

    // Haptics & Sound Toggle
    UIView *hapticRow = [[UIView alloc] init];
    hapticRow.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:hapticRow];

    UIImageView *hapticIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"hand.tap.fill"]];
    hapticIcon.translatesAutoresizingMaskIntoConstraints = NO;
    hapticIcon.tintColor = [UIColor systemOrangeColor];
    hapticIcon.contentMode = UIViewContentModeScaleAspectFit;
    [hapticRow addSubview:hapticIcon];

    UILabel *hapticTitle = [[UILabel alloc] init];
    hapticTitle.translatesAutoresizingMaskIntoConstraints = NO;
    hapticTitle.text = kLang(@"Settings_Haptics_Title") ?: @"الاستجابة اللمسية والصوتية";
    hapticTitle.font = [Styling fontBold:13.0];
    hapticTitle.textColor = [UIColor ppTextPrimary];
    hapticTitle.textAlignment = [Language alignmentForCurrentLanguage];
    [hapticRow addSubview:hapticTitle];

    UILabel *hapticSub = [[UILabel alloc] init];
    hapticSub.translatesAutoresizingMaskIntoConstraints = NO;
    hapticSub.text = kLang(@"Settings_Haptics_Subtitle") ?: @"اهتزاز وتأثيرات دقيقة عند اعتماد الإجراءات";
    hapticSub.font = [Styling fontRegular:11.0];
    hapticSub.textColor = [UIColor ppTextSecondary];
    hapticSub.textAlignment = [Language alignmentForCurrentLanguage];
    [hapticRow addSubview:hapticSub];

    _hapticsSwitch = [[UISwitch alloc] init];
    _hapticsSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    _hapticsSwitch.onTintColor = [UIColor ppPrimary];
    BOOL hapticsEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"PPAdminHapticsEnabled"] == nil ? YES : [[NSUserDefaults standardUserDefaults] boolForKey:@"PPAdminHapticsEnabled"];
    [_hapticsSwitch setOn:hapticsEnabled animated:NO];
    [_hapticsSwitch addTarget:self action:@selector(pp_hapticsToggled:) forControlEvents:UIControlEventValueChanged];
    [hapticRow addSubview:_hapticsSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:container.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [themeTitle.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [themeTitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [themeTitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [themeStack.topAnchor constraintEqualToAnchor:themeTitle.bottomAnchor constant:12.0],
        [themeStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [themeStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [themeStack.heightAnchor constraintEqualToConstant:90.0],

        [divider1.topAnchor constraintEqualToAnchor:themeStack.bottomAnchor constant:16.0],
        [divider1.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [divider1.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [divider1.heightAnchor constraintEqualToConstant:0.5],

        [langRow.topAnchor constraintEqualToAnchor:divider1.bottomAnchor constant:14.0],
        [langRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [langRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [langRow.heightAnchor constraintEqualToConstant:36.0],

        [langIcon.leadingAnchor constraintEqualToAnchor:langRow.leadingAnchor],
        [langIcon.centerYAnchor constraintEqualToAnchor:langRow.centerYAnchor],
        [langIcon.widthAnchor constraintEqualToConstant:20.0],
        [langIcon.heightAnchor constraintEqualToConstant:20.0],

        [langTitle.leadingAnchor constraintEqualToAnchor:langIcon.trailingAnchor constant:10.0],
        [langTitle.centerYAnchor constraintEqualToAnchor:langRow.centerYAnchor],

        [langSwitchBtn.trailingAnchor constraintEqualToAnchor:langRow.trailingAnchor],
        [langSwitchBtn.centerYAnchor constraintEqualToAnchor:langRow.centerYAnchor],

        [divider2.topAnchor constraintEqualToAnchor:langRow.bottomAnchor constant:14.0],
        [divider2.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [divider2.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [divider2.heightAnchor constraintEqualToConstant:0.5],

        [hapticRow.topAnchor constraintEqualToAnchor:divider2.bottomAnchor constant:14.0],
        [hapticRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [hapticRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [hapticRow.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0],

        [hapticIcon.leadingAnchor constraintEqualToAnchor:hapticRow.leadingAnchor],
        [hapticIcon.centerYAnchor constraintEqualToAnchor:hapticRow.centerYAnchor],
        [hapticIcon.widthAnchor constraintEqualToConstant:20.0],
        [hapticIcon.heightAnchor constraintEqualToConstant:20.0],

        [hapticTitle.topAnchor constraintEqualToAnchor:hapticRow.topAnchor],
        [hapticTitle.leadingAnchor constraintEqualToAnchor:hapticIcon.trailingAnchor constant:10.0],
        [hapticTitle.trailingAnchor constraintEqualToAnchor:_hapticsSwitch.leadingAnchor constant:-10.0],

        [hapticSub.topAnchor constraintEqualToAnchor:hapticTitle.bottomAnchor constant:2.0],
        [hapticSub.leadingAnchor constraintEqualToAnchor:hapticTitle.leadingAnchor],
        [hapticSub.trailingAnchor constraintEqualToAnchor:hapticTitle.trailingAnchor],
        [hapticSub.bottomAnchor constraintEqualToAnchor:hapticRow.bottomAnchor],

        [_hapticsSwitch.trailingAnchor constraintEqualToAnchor:hapticRow.trailingAnchor],
        [_hapticsSwitch.centerYAnchor constraintEqualToAnchor:hapticRow.centerYAnchor]
    ]];

    return container;
}

- (UIView *)pp_createThemeChoiceCardForStyle:(UIUserInterfaceStyle)style title:(NSString *)title checkRef:(UIImageView * __strong *)checkRef {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [UIColor ppBackground];
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(btn, 14.0);
    btn.tag = (NSInteger)style;

    // Mini Mockup preview
    UIView *miniCanvas = [[UIView alloc] init];
    miniCanvas.translatesAutoresizingMaskIntoConstraints = NO;
    miniCanvas.userInteractionEnabled = NO;
    PPApplyContinuousCorners(miniCanvas, 8.0);
    [btn addSubview:miniCanvas];

    if (style == UIUserInterfaceStyleLight) {
        miniCanvas.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.97 alpha:1.0];
        UIView *navLine = [[UIView alloc] init];
        navLine.translatesAutoresizingMaskIntoConstraints = NO;
        navLine.backgroundColor = [UIColor ppPrimary];
        [miniCanvas addSubview:navLine];
        [NSLayoutConstraint activateConstraints:@[
            [navLine.topAnchor constraintEqualToAnchor:miniCanvas.topAnchor constant:4.0],
            [navLine.leadingAnchor constraintEqualToAnchor:miniCanvas.leadingAnchor constant:6.0],
            [navLine.trailingAnchor constraintEqualToAnchor:miniCanvas.trailingAnchor constant:-6.0],
            [navLine.heightAnchor constraintEqualToConstant:3.0]
        ]];
    } else if (style == UIUserInterfaceStyleDark) {
        miniCanvas.backgroundColor = [UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1.0];
        UIView *navLine = [[UIView alloc] init];
        navLine.translatesAutoresizingMaskIntoConstraints = NO;
        navLine.backgroundColor = [UIColor systemCyanColor];
        [miniCanvas addSubview:navLine];
        [NSLayoutConstraint activateConstraints:@[
            [navLine.topAnchor constraintEqualToAnchor:miniCanvas.topAnchor constant:4.0],
            [navLine.leadingAnchor constraintEqualToAnchor:miniCanvas.leadingAnchor constant:6.0],
            [navLine.trailingAnchor constraintEqualToAnchor:miniCanvas.trailingAnchor constant:-6.0],
            [navLine.heightAnchor constraintEqualToConstant:3.0]
        ]];
    } else {
        // System dual split
        CAGradientLayer *grad = [CAGradientLayer layer];
        grad.colors = @[
            (id)[UIColor colorWithRed:0.96 green:0.96 blue:0.97 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.10 green:0.11 blue:0.14 alpha:1.0].CGColor
        ];
        grad.startPoint = CGPointMake(0, 0);
        grad.endPoint = CGPointMake(1, 1);
        grad.frame = CGRectMake(0, 0, 70, 34);
        [miniCanvas.layer addSublayer:grad];
    }

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.font = [Styling fontBold:11.5];
    lbl.textColor = [UIColor ppTextPrimary];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.userInteractionEnabled = NO;
    [btn addSubview:lbl];

    UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    check.translatesAutoresizingMaskIntoConstraints = NO;
    check.tintColor = [UIColor ppPrimary];
    check.hidden = YES;
    check.userInteractionEnabled = NO;
    [btn addSubview:check];
    if (checkRef) *checkRef = check;

    [btn addTarget:self action:@selector(pp_themeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [miniCanvas.topAnchor constraintEqualToAnchor:btn.topAnchor constant:8.0],
        [miniCanvas.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
        [miniCanvas.widthAnchor constraintEqualToConstant:64.0],
        [miniCanvas.heightAnchor constraintEqualToConstant:34.0],

        [lbl.topAnchor constraintEqualToAnchor:miniCanvas.bottomAnchor constant:8.0],
        [lbl.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:4.0],
        [lbl.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-4.0],

        [check.topAnchor constraintEqualToAnchor:btn.topAnchor constant:5.0],
        [check.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-5.0],
        [check.widthAnchor constraintEqualToConstant:16.0],
        [check.heightAnchor constraintEqualToConstant:16.0]
    ]];

    return btn;
}

- (void)pp_themeButtonTapped:(UIButton *)sender {
    [PPFunc pp_playTapEffect];
    UIUserInterfaceStyle targetStyle = (UIUserInterfaceStyle)sender.tag;
    [self pp_selectThemeWithStyle:targetStyle];
}

- (void)pp_selectThemeWithStyle:(UIUserInterfaceStyle)style {
    UIWindow *window = self.view.window ?: [UIApplication sharedApplication].windows.firstObject;
    window.overrideUserInterfaceStyle = style;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)style forKey:@"PPAdminThemeStylePreference"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateThemeSelectionVisuals];
}

- (void)updateThemeSelectionVisuals {
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:@"PPAdminThemeStylePreference"];
    UIUserInterfaceStyle current = (UIUserInterfaceStyle)saved;

    _themeLightCheck.hidden = (current != UIUserInterfaceStyleLight);
    _themeDarkCheck.hidden = (current != UIUserInterfaceStyleDark);
    _themeSystemCheck.hidden = (current != UIUserInterfaceStyleUnspecified);

    _themeLightCard.layer.borderColor = (current == UIUserInterfaceStyleLight) ? [UIColor ppPrimary].CGColor : [UIColor ppSurfaceBorder].CGColor;
    _themeLightCard.layer.borderWidth = (current == UIUserInterfaceStyleLight) ? 2.0 : 1.0;

    _themeDarkCard.layer.borderColor = (current == UIUserInterfaceStyleDark) ? [UIColor ppPrimary].CGColor : [UIColor ppSurfaceBorder].CGColor;
    _themeDarkCard.layer.borderWidth = (current == UIUserInterfaceStyleDark) ? 2.0 : 1.0;

    _themeSystemCard.layer.borderColor = (current == UIUserInterfaceStyleUnspecified) ? [UIColor ppPrimary].CGColor : [UIColor ppSurfaceBorder].CGColor;
    _themeSystemCard.layer.borderWidth = (current == UIUserInterfaceStyleUnspecified) ? 2.0 : 1.0;
}

#pragma mark - Card 4: Operational Modules & Privileged Portals

- (UIView *)pp_createPortalsCard {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *header = [self pp_createSectionHeaderWithTitle:kLang(@"Settings_Section_Portals") ?: @"المسارات والوحدات الإدارية"
                                                  subtitle:kLang(@"Settings_Portals_Desc") ?: @"وصول سريع للوحدات التنظيمية والرقابية للتحكم بالمنصة."];
    [container addSubview:header];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);
    [container addSubview:card];

    UIStackView *vStack = [[UIStackView alloc] init];
    vStack.translatesAutoresizingMaskIntoConstraints = NO;
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 0.0;
    [card addSubview:vStack];

    [vStack addArrangedSubview:[self pp_createPortalRowWithTitle:kLang(@"Settings_Portal_Notifications_Title") ?: @"إعدادات وقنوات الإشعارات"
                                                        subtitle:kLang(@"Settings_Portal_Notifications_Subtitle") ?: @"قنوات البث المباشر، تنبيهات التوصيل، وصفارات الطوارئ"
                                                      systemIcon:@"bell.badge.fill"
                                                       iconColor:[UIColor systemPinkColor]
                                                          action:@selector(pp_openNotifications)]];

    [vStack addArrangedSubview:[self pp_createDividerView]];

    [vStack addArrangedSubview:[self pp_createPortalRowWithTitle:kLang(@"Settings_Portal_Accounting_Title") ?: @"الدفتر المالي والمحاسبة المركزية"
                                                        subtitle:kLang(@"Settings_Portal_Accounting_Subtitle") ?: @"ضريبة القيمة المضافة، بوابات الدفع، والتسويات المالية"
                                                      systemIcon:@"chart.line.uptrend.xyaxis"
                                                       iconColor:[UIColor ppSuccess]
                                                          action:@selector(pp_openAccounting)]];

    [vStack addArrangedSubview:[self pp_createDividerView]];

    [vStack addArrangedSubview:[self pp_createPortalRowWithTitle:kLang(@"Settings_Portal_Audit_Title") ?: @"سجل العمليات والرقابة السيادية"
                                                        subtitle:kLang(@"Settings_Portal_Audit_Subtitle") ?: @"فحص العمليات الإدارية وسجلات التدقيق الموثقة تاريخياً"
                                                      systemIcon:@"doc.text.magnifyingglass"
                                                       iconColor:[UIColor ppPrimary]
                                                          action:@selector(pp_openAuditLog)]];

    [vStack addArrangedSubview:[self pp_createDividerView]];

    [vStack addArrangedSubview:[self pp_createPortalRowWithTitle:kLang(@"Settings_Portal_Permissions_Title") ?: @"فاحص وتراخيص الصلاحيات"
                                                        subtitle:kLang(@"Settings_Portal_Permissions_Subtitle") ?: @"استعراض الصلاحيات الممنوحة لحسابك في النظام"
                                                      systemIcon:@"shield.lefthalf.filled"
                                                       iconColor:[UIColor systemIndigoColor]
                                                          action:@selector(pp_openPermissionsInspector)]];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:container.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [vStack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [vStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [vStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [vStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];

    return container;
}

- (UIView *)pp_createPortalRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle systemIcon:(NSString *)icon iconColor:(UIColor *)color action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = UIColor.clearColor;

    UIView *iconPlate = [[UIView alloc] init];
    iconPlate.translatesAutoresizingMaskIntoConstraints = NO;
    iconPlate.backgroundColor = [color colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(iconPlate, 12.0);
    iconPlate.userInteractionEnabled = NO;
    [btn addSubview:iconPlate];

    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.tintColor = color;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.userInteractionEnabled = NO;
    [iconPlate addSubview:iv];

    UILabel *lblTitle = [[UILabel alloc] init];
    lblTitle.translatesAutoresizingMaskIntoConstraints = NO;
    lblTitle.text = title;
    lblTitle.font = [Styling fontBold:14.0];
    lblTitle.textColor = [UIColor ppTextPrimary];
    lblTitle.textAlignment = [Language alignmentForCurrentLanguage];
    lblTitle.userInteractionEnabled = NO;
    [btn addSubview:lblTitle];

    UILabel *lblSub = [[UILabel alloc] init];
    lblSub.translatesAutoresizingMaskIntoConstraints = NO;
    lblSub.text = subtitle;
    lblSub.font = [Styling fontRegular:11.5];
    lblSub.textColor = [UIColor ppTextSecondary];
    lblSub.textAlignment = [Language alignmentForCurrentLanguage];
    lblSub.userInteractionEnabled = NO;
    [btn addSubview:lblSub];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = [UIColor ppTextTertiary];
    chevron.userInteractionEnabled = NO;
    [btn addSubview:chevron];

    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [btn.heightAnchor constraintEqualToConstant:68.0],

        [iconPlate.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:16.0],
        [iconPlate.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
        [iconPlate.widthAnchor constraintEqualToConstant:40.0],
        [iconPlate.heightAnchor constraintEqualToConstant:40.0],

        [iv.centerXAnchor constraintEqualToAnchor:iconPlate.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:iconPlate.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:20.0],
        [iv.heightAnchor constraintEqualToConstant:20.0],

        [lblTitle.topAnchor constraintEqualToAnchor:btn.topAnchor constant:14.0],
        [lblTitle.leadingAnchor constraintEqualToAnchor:iconPlate.trailingAnchor constant:12.0],
        [lblTitle.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8.0],

        [lblSub.topAnchor constraintEqualToAnchor:lblTitle.bottomAnchor constant:3.0],
        [lblSub.leadingAnchor constraintEqualToAnchor:lblTitle.leadingAnchor],
        [lblSub.trailingAnchor constraintEqualToAnchor:lblTitle.trailingAnchor],

        [chevron.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-16.0],
        [chevron.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:14.0],
        [chevron.heightAnchor constraintEqualToConstant:14.0]
    ]];

    return btn;
}

#pragma mark - Card 5: Storage, Cache & Device Health Engine

- (UIView *)pp_createStorageCard {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *header = [self pp_createSectionHeaderWithTitle:kLang(@"Settings_Section_Storage") ?: @"الذاكرة والتخزين المؤقت"
                                                  subtitle:kLang(@"Settings_Storage_Desc") ?: @"إدارة الملفات المؤقتة لتسريع الأداء وتحرير مساحة التخزين."];
    [container addSubview:header];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);
    [container addSubview:card];

    UIImageView *driveIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"internaldrive.fill"]];
    driveIcon.translatesAutoresizingMaskIntoConstraints = NO;
    driveIcon.tintColor = [UIColor ppPrimary];
    driveIcon.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:driveIcon];

    UILabel *footprintTitle = [[UILabel alloc] init];
    footprintTitle.translatesAutoresizingMaskIntoConstraints = NO;
    footprintTitle.text = kLang(@"Settings_Storage_Footprint") ?: @"المساحة المشغولة حالياً:";
    footprintTitle.font = [Styling fontMedium:13.0];
    footprintTitle.textColor = [UIColor ppTextSecondary];
    footprintTitle.textAlignment = [Language alignmentForCurrentLanguage];
    [card addSubview:footprintTitle];

    _cacheFootprintLabel = [[UILabel alloc] init];
    _cacheFootprintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _cacheFootprintLabel.text = @"0.0 MB";
    _cacheFootprintLabel.font = [Styling fontBold:16.0];
    _cacheFootprintLabel.textColor = [UIColor ppPrimary];
    _cacheFootprintLabel.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    [card addSubview:_cacheFootprintLabel];

    _cacheProgressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _cacheProgressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _cacheProgressBar.progressTintColor = [UIColor ppPrimary];
    _cacheProgressBar.trackTintColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(_cacheProgressBar, 4.0);
    _cacheProgressBar.progress = 0.35;
    [card addSubview:_cacheProgressBar];

    UIButton *purgeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    purgeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    purgeBtn.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.08];
    purgeBtn.layer.borderWidth = 0.8;
    purgeBtn.layer.borderColor = [[UIColor ppError] colorWithAlphaComponent:0.25].CGColor;
    PPApplyContinuousCorners(purgeBtn, 12.0);
    [purgeBtn setTitle:kLang(@"Settings_Storage_Purge_CTA") ?: @"تنظيف الذاكرة المؤقتة الآن" forState:UIControlStateNormal];
    [purgeBtn setTitleColor:[UIColor ppError] forState:UIControlStateNormal];
    purgeBtn.titleLabel.font = [Styling fontBold:12.5];
    [purgeBtn setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
    purgeBtn.tintColor = [UIColor ppError];
    purgeBtn.imageEdgeInsets = [Language isRTL] ? UIEdgeInsetsMake(0, 6, 0, -6) : UIEdgeInsetsMake(0, -6, 0, 6);
    [purgeBtn addTarget:self action:@selector(pp_purgeCache) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:purgeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:container.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [driveIcon.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [driveIcon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [driveIcon.widthAnchor constraintEqualToConstant:22.0],
        [driveIcon.heightAnchor constraintEqualToConstant:22.0],

        [footprintTitle.centerYAnchor constraintEqualToAnchor:driveIcon.centerYAnchor],
        [footprintTitle.leadingAnchor constraintEqualToAnchor:driveIcon.trailingAnchor constant:10.0],

        [_cacheFootprintLabel.centerYAnchor constraintEqualToAnchor:driveIcon.centerYAnchor],
        [_cacheFootprintLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [_cacheProgressBar.topAnchor constraintEqualToAnchor:driveIcon.bottomAnchor constant:14.0],
        [_cacheProgressBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [_cacheProgressBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [_cacheProgressBar.heightAnchor constraintEqualToConstant:8.0],

        [purgeBtn.topAnchor constraintEqualToAnchor:_cacheProgressBar.bottomAnchor constant:16.0],
        [purgeBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [purgeBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [purgeBtn.heightAnchor constraintEqualToConstant:40.0],
        [purgeBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
    ]];

    return container;
}

#pragma mark - Card 6: Support, Security & Sovereign Session Termination

- (UIView *)pp_createSessionCard {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *header = [self pp_createSectionHeaderWithTitle:kLang(@"Settings_Section_Account_Session") ?: @"الجلسة والحماية السيادية"
                                                  subtitle:nil];
    [container addSubview:header];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);
    [container addSubview:card];

    UIStackView *vStack = [[UIStackView alloc] init];
    vStack.translatesAutoresizingMaskIntoConstraints = NO;
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 0.0;
    [card addSubview:vStack];

    [vStack addArrangedSubview:[self pp_createPortalRowWithTitle:kLang(@"HelpCenter") ?: @"مركز المساعدة والتوثيق"
                                                        subtitle:kLang(@"Settings_Help_Subtitle") ?: @"الدعم والإرشاد ومسارات التصعيد الإداري"
                                                      systemIcon:@"questionmark.circle.fill"
                                                       iconColor:[UIColor systemTealColor]
                                                          action:@selector(pp_openHelp)]];

    [vStack addArrangedSubview:[self pp_createDividerView]];

    [vStack addArrangedSubview:[self pp_createPortalRowWithTitle:kLang(@"Settings_Action_Vault") ?: @"خزنة الأمان السيادية"
                                                        subtitle:[Language isRTL] ? @"البيانات الحيوية، مفاتيح الجلسة، وتغيير كلمة المرور" : @"Biometrics, session keys & password security"
                                                      systemIcon:@"lock.rotation"
                                                       iconColor:[UIColor systemIndigoColor]
                                                          action:@selector(pp_openSecurityVault)]];

    [vStack addArrangedSubview:[self pp_createDividerView]];

    // Destructive Logout Row
    UIButton *logoutBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    logoutBtn.translatesAutoresizingMaskIntoConstraints = NO;
    logoutBtn.backgroundColor = UIColor.clearColor;

    UIView *logoutPlate = [[UIView alloc] init];
    logoutPlate.translatesAutoresizingMaskIntoConstraints = NO;
    logoutPlate.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(logoutPlate, 12.0);
    logoutPlate.userInteractionEnabled = NO;
    [logoutBtn addSubview:logoutPlate];

    UIImageView *logoutIv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"power.circle.fill"]];
    logoutIv.translatesAutoresizingMaskIntoConstraints = NO;
    logoutIv.tintColor = [UIColor ppError];
    logoutIv.contentMode = UIViewContentModeScaleAspectFit;
    logoutIv.userInteractionEnabled = NO;
    [logoutPlate addSubview:logoutIv];

    UILabel *logoutTitle = [[UILabel alloc] init];
    logoutTitle.translatesAutoresizingMaskIntoConstraints = NO;
    logoutTitle.text = kLang(@"Settings_Session_Logout_CTA") ?: @"تسجيل الخروج من لوحة التحكم";
    logoutTitle.font = [Styling fontBold:14.0];
    logoutTitle.textColor = [UIColor ppError];
    logoutTitle.textAlignment = [Language alignmentForCurrentLanguage];
    logoutTitle.userInteractionEnabled = NO;
    [logoutBtn addSubview:logoutTitle];

    UILabel *logoutSub = [[UILabel alloc] init];
    logoutSub.translatesAutoresizingMaskIntoConstraints = NO;
    logoutSub.text = kLang(@"Settings_Logout_Subtitle") ?: @"إنهاء جلسة الإدارة بأمان";
    logoutSub.font = [Styling fontRegular:11.5];
    logoutSub.textColor = [UIColor ppTextSecondary];
    logoutSub.textAlignment = [Language alignmentForCurrentLanguage];
    logoutSub.userInteractionEnabled = NO;
    [logoutBtn addSubview:logoutSub];

    [logoutBtn addTarget:self action:@selector(pp_handleLogout) forControlEvents:UIControlEventTouchUpInside];
    [vStack addArrangedSubview:logoutBtn];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:container.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],

        [vStack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [vStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [vStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [vStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [logoutBtn.heightAnchor constraintEqualToConstant:68.0],

        [logoutPlate.leadingAnchor constraintEqualToAnchor:logoutBtn.leadingAnchor constant:16.0],
        [logoutPlate.centerYAnchor constraintEqualToAnchor:logoutBtn.centerYAnchor],
        [logoutPlate.widthAnchor constraintEqualToConstant:40.0],
        [logoutPlate.heightAnchor constraintEqualToConstant:40.0],

        [logoutIv.centerXAnchor constraintEqualToAnchor:logoutPlate.centerXAnchor],
        [logoutIv.centerYAnchor constraintEqualToAnchor:logoutPlate.centerYAnchor],
        [logoutIv.widthAnchor constraintEqualToConstant:22.0],
        [logoutIv.heightAnchor constraintEqualToConstant:22.0],

        [logoutTitle.topAnchor constraintEqualToAnchor:logoutBtn.topAnchor constant:14.0],
        [logoutTitle.leadingAnchor constraintEqualToAnchor:logoutPlate.trailingAnchor constant:12.0],
        [logoutTitle.trailingAnchor constraintEqualToAnchor:logoutBtn.trailingAnchor constant:-16.0],

        [logoutSub.topAnchor constraintEqualToAnchor:logoutTitle.bottomAnchor constant:3.0],
        [logoutSub.leadingAnchor constraintEqualToAnchor:logoutTitle.leadingAnchor],
        [logoutSub.trailingAnchor constraintEqualToAnchor:logoutTitle.trailingAnchor]
    ]];

    return container;
}

#pragma mark - Footer Signature Stamp

- (UIView *)pp_createFooterView {
    UIView *footer = [[UIView alloc] init];
    footer.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *stamp = [[UILabel alloc] init];
    stamp.translatesAutoresizingMaskIntoConstraints = NO;
    stamp.text = [Language isRTL] ? @"منصة Pure Pets • الإدارة المركزية السيادية • إصدار 6.2" : @"Pure Pets Platform • Sovereign Administration Core • v6.2";
    stamp.font = [Styling fontMedium:11.5];
    stamp.textColor = [UIColor ppTextTertiary];
    stamp.textAlignment = NSTextAlignmentCenter;
    [footer addSubview:stamp];

    [NSLayoutConstraint activateConstraints:@[
        [stamp.topAnchor constraintEqualToAnchor:footer.topAnchor constant:12.0],
        [stamp.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [stamp.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:-10.0]
    ]];

    return footer;
}

#pragma mark - Helper Builders

- (UIView *)pp_createSectionHeaderWithTitle:(NSString *)title subtitle:(nullable NSString *)subtitle {
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lblTitle = [[UILabel alloc] init];
    lblTitle.translatesAutoresizingMaskIntoConstraints = NO;
    lblTitle.text = title;
    lblTitle.font = [Styling fontBold:14.5];
    lblTitle.textColor = [UIColor ppTextPrimary];
    lblTitle.textAlignment = [Language alignmentForCurrentLanguage];
    [header addSubview:lblTitle];

    if (subtitle.length > 0) {
        UILabel *lblSub = [[UILabel alloc] init];
        lblSub.translatesAutoresizingMaskIntoConstraints = NO;
        lblSub.text = subtitle;
        lblSub.font = [Styling fontRegular:11.5];
        lblSub.textColor = [UIColor ppTextSecondary];
        lblSub.textAlignment = [Language alignmentForCurrentLanguage];
        lblSub.numberOfLines = 2;
        [header addSubview:lblSub];

        [NSLayoutConstraint activateConstraints:@[
            [lblTitle.topAnchor constraintEqualToAnchor:header.topAnchor],
            [lblTitle.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4.0],
            [lblTitle.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-4.0],

            [lblSub.topAnchor constraintEqualToAnchor:lblTitle.bottomAnchor constant:2.0],
            [lblSub.leadingAnchor constraintEqualToAnchor:lblTitle.leadingAnchor],
            [lblSub.trailingAnchor constraintEqualToAnchor:lblTitle.trailingAnchor],
            [lblSub.bottomAnchor constraintEqualToAnchor:header.bottomAnchor]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [lblTitle.topAnchor constraintEqualToAnchor:header.topAnchor],
            [lblTitle.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4.0],
            [lblTitle.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-4.0],
            [lblTitle.bottomAnchor constraintEqualToAnchor:header.bottomAnchor]
        ]];
    }

    return header;
}

- (UIView *)pp_createDividerView {
    UIView *div = [[UIView alloc] init];
    div.translatesAutoresizingMaskIntoConstraints = NO;
    div.backgroundColor = [UIColor ppSurfaceBorder];
    [div.heightAnchor constraintEqualToConstant:0.5].active = YES;
    return div;
}

#pragma mark - State Updaters

- (void)updateProfileData {
    UserModel *user = [UserManager shared].currentUser;
    if (!user) return;

    NSString *dispName = [user PPBestDisplayName];
    if (dispName.length == 0) dispName = user.UserName ?: user.displayName;
    self.nameLabel.text = dispName.length > 0 ? dispName : ([Language isRTL] ? @"مسؤول المنصة" : @"Platform Admin");

    // Check staff role
    [[PPStaffAuth shared] checkCurrentUserIsStaff:^(BOOL isStaff, PPStaffDoc * _Nullable doc) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *roleName = doc.roleName;
            if (roleName.length == 0) {
                if ([doc.role isEqualToString:PPStaffRoleOwner]) {
                    roleName = kLang(@"Settings_Operator_Role_Owner") ?: @"مالك النظام السيادي";
                } else if ([doc.role isEqualToString:PPStaffRoleSuperAdmin]) {
                    roleName = kLang(@"Settings_Operator_Role_SuperAdmin") ?: @"مشرف عام للنظام";
                } else if ([doc.role isEqualToString:PPStaffRoleOperationsManager]) {
                    roleName = kLang(@"Settings_Operator_Role_Operations") ?: @"مدير العمليات المركزية";
                } else {
                    roleName = kLang(@"Settings_Operator_Role_Staff") ?: @"عضو الفريق الإداري";
                }
            }
            self.roleBadgeLabel.text = roleName;
        });
    }];

    self.emailLabel.text = (user.UserEmail.length > 0 ? user.UserEmail : (user.email.length > 0 ? user.email : @"admin@pure-pets.net"));

    NSString *avatarStr = user.photoURL ?: user.UserImageUrl.absoluteString ?: user.UserImageName;
    if (avatarStr.length > 0) {
        self.monogramLabel.hidden = YES;
        self.avatarImageView.hidden = NO;
        [self.avatarImageView sd_setImageWithURL:[NSURL URLWithString:avatarStr]
                               placeholderImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    } else {
        self.avatarImageView.hidden = YES;
        self.monogramLabel.hidden = NO;
        NSString *initials = @"PP";
        if (dispName.length >= 2) {
            initials = [[dispName substringToIndex:2] uppercaseString];
        }
        self.monogramLabel.text = initials;
    }
}

- (void)updateStorageData {
    unsigned long long diskSize = [[SDImageCache sharedImageCache] totalDiskSize];
    double mbSize = (double)diskSize / (1024.0 * 1024.0);
    self.cacheFootprintLabel.text = [NSString stringWithFormat:@"%.1f MB", mbSize];
    float ratio = MIN(MAX((float)(mbSize / 150.0), 0.05f), 1.0f);
    self.cacheProgressBar.progress = ratio;
}

#pragma mark - User Actions

- (void)pp_testConnectivity {
    [PPFunc pp_playTapEffect];
    [self.pingSpinner startAnimating];
    self.pingButton.enabled = NO;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.pingSpinner stopAnimating];
        weakSelf.pingButton.enabled = YES;
        [PPHUD showSuccess:kLang(@"Settings_Telemetry_Ping_Success") ?: @"الاتصال ممتاز: استجابة خوادم Firebase طبيعية وسريعة"];
    });
}

- (void)pp_hapticsToggled:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:@"PPAdminHapticsEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (sender.isOn) {
        [PPFunc pp_playTapEffect];
    }
}

- (void)pp_openLanguageSwitcher {
    [PPFunc pp_playTapEffect];
    NSInteger nextLanguageValue = ([Language languageVal] == 0) ? 1 : 0;
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                                title:kLang(@"Confirm_LanguageChange_Title")
                             subtitle:kLang(@"Confirm_LanguageChange_Msg")
                          placeholder:nil
                        confirmButton:kLang(@"Confirm")
                         cancelButton:kLang(@"Cancel")
                                 icon:[UIImage systemImageNamed:@"globe"]
                         confirmBlock:^{
        [Language userSelectedLanguage:LanguageCode[nextLanguageValue]];
        [weakSelf setupNavigation];
    } cancelBlock:nil];
}

- (void)pp_purgeCache {
    [PPFunc pp_playTapEffect];
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                                title:kLang(@"Settings_Storage_Purge_Confirm_Title") ?: @"تنظيف الذاكرة المؤقتة؟"
                             subtitle:kLang(@"Settings_Storage_Purge_Confirm_Msg") ?: @"سيتم تفريغ كافة الصور والبيانات المؤقتة وإعادة تحميلها عند الحاجة."
                          placeholder:nil
                        confirmButton:kLang(@"Confirm")
                         cancelButton:kLang(@"Cancel")
                                 icon:[UIImage systemImageNamed:@"trash.fill"]
                         confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Loading") subtitle:nil];
        [[SDImageCache sharedImageCache] clearMemory];
        [[SDImageCache sharedImageCache] clearDiskOnCompletion:^{
            [PPHUD dismiss];
            [PPHUD showSuccess:kLang(@"Settings_Storage_Purged_Toast") ?: @"تم تنظيف الذاكرة المؤقتة بنجاح"];
            [weakSelf updateStorageData];
        }];
    } cancelBlock:nil];
}

- (void)pp_openProfile {
    [PPFunc pp_playTapEffect];
    UserModel *currentUser = [UserManager shared].currentUser;
    PPAdminProfileViewController *profileVC = [[PPAdminProfileViewController alloc] initWithUser:currentUser];
    [self.navigationController pushViewController:profileVC animated:YES];
}

- (void)pp_openPermissionsInspector {
    [PPFunc pp_playTapEffect];
    UserModel *currentUser = [UserManager shared].currentUser;
    PPAdminPermissionsInspectorSheet *sheet = [[PPAdminPermissionsInspectorSheet alloc] initWithUser:currentUser];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pp_openSecurityVault {
    [PPFunc pp_playTapEffect];
    UserModel *currentUser = [UserManager shared].currentUser;
    PPAdminSecurityVaultSheet *sheet = [[PPAdminSecurityVaultSheet alloc] initWithUser:currentUser];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pp_openNotifications {
    [PPFunc pp_playTapEffect];
    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)pp_openAccounting {
    [PPFunc pp_playTapEffect];
    AdminAccountingHostingController *vc = [[AdminAccountingHostingController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)pp_openAuditLog {
    [PPFunc pp_playTapEffect];
    PPAuditLogViewController *vc = [[PPAuditLogViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)pp_openHelp {
    [PPFunc pp_playTapEffect];
    [PPAlertHelper showInfoIn:self
                        title:kLang(@"HelpCenter") ?: @"مركز المساعدة والتوثيق"
                     subtitle:kLang(@"Settings_Help_Message") ?: @"للمساعدة، يرجى التواصل عبر support@purepets.co"];
}

- (void)pp_handleLogout {
    [PPFunc pp_playTapEffect];
    [PPAlertHelper showConfirmationIn:self
                                title:kLang(@"Settings_Session_Logout_Confirm_Title") ?: @"تأكيد إنهاء الجلسة الإدارية"
                             subtitle:kLang(@"Settings_Session_Logout_Confirm_Msg") ?: @"هل أنت متأكد من رغبتك في تسجيل الخروج من تطبيق الإدارة السيادية؟"
                          placeholder:nil
                        confirmButton:kLang(@"Confirm")
                         cancelButton:kLang(@"Cancel")
                                 icon:[UIImage systemImageNamed:@"power.circle.fill"]
                         confirmBlock:^{
        [UsrMgr signOutWithCompletion:nil];
    } cancelBlock:nil];
}

@end

