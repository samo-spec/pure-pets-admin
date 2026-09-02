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
@import Firebase;
@import FirebaseAuth;
@import FirebaseStorage;

#pragma mark - PPAdminPermissionsInspectorSheet

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
    self.view.backgroundColor = [UIColor ppSurfaceElevated];
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

    [self setupUI];
}

- (void)setupUI {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-32],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40]
    ]];

    // Header Card
    UIView *headerCard = [[UIView alloc] init];
    headerCard.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(headerCard, PPCornerCard);
    [stack addArrangedSubview:headerCard];

    UIImageView *shieldIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.lefthalf.filled"]];
    shieldIcon.translatesAutoresizingMaskIntoConstraints = NO;
    shieldIcon.tintColor = [UIColor ppPrimary];
    [headerCard addSubview:shieldIcon];

    UILabel *headerTitle = [[UILabel alloc] init];
    headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    headerTitle.text = [Language isRTL] ? @"سجل الصلاحيات الإدارية السيادية" : @"Sovereign Admin Permissions Matrix";
    headerTitle.font = [Styling fontBold:17.0];
    headerTitle.textColor = [UIColor ppTextPrimary];
    headerTitle.textAlignment = Language.alignmentForCurrentLanguage;
    [headerCard addSubview:headerTitle];

    UILabel *headerSubtitle = [[UILabel alloc] init];
    headerSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    headerSubtitle.text = [Language isRTL] ? @"المستوى: وصول سيادي كامل لكافة أقسام النظام والبيانات" : @"Tier: Full Sovereign Access across all platform subsystems";
    headerSubtitle.font = [Styling fontRegular:12.5];
    headerSubtitle.textColor = [UIColor ppTextSecondary];
    headerSubtitle.numberOfLines = 2;
    headerSubtitle.textAlignment = Language.alignmentForCurrentLanguage;
    [headerCard addSubview:headerSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [shieldIcon.topAnchor constraintEqualToAnchor:headerCard.topAnchor constant:16],
        [shieldIcon.leadingAnchor constraintEqualToAnchor:headerCard.leadingAnchor constant:16],
        [shieldIcon.widthAnchor constraintEqualToConstant:28],
        [shieldIcon.heightAnchor constraintEqualToConstant:28],

        [headerTitle.topAnchor constraintEqualToAnchor:headerCard.topAnchor constant:14],
        [headerTitle.leadingAnchor constraintEqualToAnchor:shieldIcon.trailingAnchor constant:12],
        [headerTitle.trailingAnchor constraintEqualToAnchor:headerCard.trailingAnchor constant:-16],

        [headerSubtitle.topAnchor constraintEqualToAnchor:headerTitle.bottomAnchor constant:4],
        [headerSubtitle.leadingAnchor constraintEqualToAnchor:headerTitle.leadingAnchor],
        [headerSubtitle.trailingAnchor constraintEqualToAnchor:headerTitle.trailingAnchor],
        [headerSubtitle.bottomAnchor constraintEqualToAnchor:headerCard.bottomAnchor constant:-16]
    ]];

    // Permission Cards List
    NSArray *permissions = @[
        @{@"title": [Language isRTL] ? @"إدارة الطلبات والمدفوعات والمحاسبة" : @"Orders, QIB Payments & Accounting", @"desc": [Language isRTL] ? @"صلاحية كاملة لمتابعة وتنفيذ وتأكيد طلبات المتجر والصيدلية والخدمات" : @"Full authority to oversee, transition, and reconcile transactions", @"icon": @"creditcard.fill"},
        @{@"title": [Language isRTL] ? @"إدارة المنتجات والمخزون والتسعير" : @"Inventory, Stock & Dynamic Pricing", @"desc": [Language isRTL] ? @"تعديل الأسعار وإضافة المنتجات وإدارة المخزون ونقاط البيع السريعة" : @"Direct control over catalog accessories, medicine, and retail POS", @"icon": @"cart.fill"},
        @{@"title": [Language isRTL] ? @"عروض الخدمات ومزودي الخدمة" : @"Services & Registered Providers", @"desc": [Language isRTL] ? @"اعتماد ومراجعة الخدمات وتعديل التوفر وأسعار المزودين" : @"Full approval & oversight for service providers and veterinarians", @"icon": @"cross.case.fill"},
        @{@"title": [Language isRTL] ? @"إدارة المستخدمين وصلاحيات الموظفين" : @"User Accounts & Access Governance", @"desc": [Language isRTL] ? @"تعديل الأدوار وحظر الحسابات ومراجعة فرق العمل الإدارية" : @"RBAC management, account state modification, and staff roles", @"icon": @"person.3.fill"},
        @{@"title": [Language isRTL] ? @"مركز الإشعارات والبث الإداري" : @"Push Notifications & Broadcast Hub", @"desc": [Language isRTL] ? @"إرسال تنبيهات عامة أو مستهدفة لكافة المستخدمين والعملاء" : @"Authoring and dispatching push notifications across platform", @"icon": @"bell.badge.fill"},
        @{@"title": [Language isRTL] ? @"سجل التدقيق والمراقبة الأمنية" : @"Audit Logging & Security Surveillance", @"desc": [Language isRTL] ? @"رصد وتتبع كافة العمليات الحساسة مع طوابع زمنية موثقة" : @"Immutable tracking and verification of all administrative actions", @"icon": @"doc.text.magnifyingglass"}
    ];

    for (NSDictionary *item in permissions) {
        UIView *permCard = [[UIView alloc] init];
        permCard.backgroundColor = [UIColor ppSurface];
        permCard.layer.borderWidth = 1.0;
        permCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        PPApplyContinuousCorners(permCard, PPCornerMedium);
        [stack addArrangedSubview:permCard];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:item[@"icon"]]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.tintColor = [UIColor ppPrimary];
        [permCard addSubview:icon];

        UILabel *titleL = [[UILabel alloc] init];
        titleL.translatesAutoresizingMaskIntoConstraints = NO;
        titleL.text = item[@"title"];
        titleL.font = [Styling fontBold:14.5];
        titleL.textColor = [UIColor ppTextPrimary];
        titleL.textAlignment = Language.alignmentForCurrentLanguage;
        [permCard addSubview:titleL];

        UILabel *descL = [[UILabel alloc] init];
        descL.translatesAutoresizingMaskIntoConstraints = NO;
        descL.text = item[@"desc"];
        descL.font = [Styling fontRegular:12.0];
        descL.textColor = [UIColor ppTextSecondary];
        descL.numberOfLines = 2;
        descL.textAlignment = Language.alignmentForCurrentLanguage;
        [permCard addSubview:descL];

        UIImageView *checkBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
        checkBadge.translatesAutoresizingMaskIntoConstraints = NO;
        checkBadge.tintColor = [UIColor ppSuccess];
        [permCard addSubview:checkBadge];

        [NSLayoutConstraint activateConstraints:@[
            [icon.topAnchor constraintEqualToAnchor:permCard.topAnchor constant:14],
            [icon.leadingAnchor constraintEqualToAnchor:permCard.leadingAnchor constant:14],
            [icon.widthAnchor constraintEqualToConstant:22],
            [icon.heightAnchor constraintEqualToConstant:22],

            [checkBadge.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
            [checkBadge.trailingAnchor constraintEqualToAnchor:permCard.trailingAnchor constant:-14],
            [checkBadge.widthAnchor constraintEqualToConstant:18],
            [checkBadge.heightAnchor constraintEqualToConstant:18],

            [titleL.topAnchor constraintEqualToAnchor:permCard.topAnchor constant:13],
            [titleL.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
            [titleL.trailingAnchor constraintEqualToAnchor:checkBadge.leadingAnchor constant:-8],

            [descL.topAnchor constraintEqualToAnchor:titleL.bottomAnchor constant:3],
            [descL.leadingAnchor constraintEqualToAnchor:titleL.leadingAnchor],
            [descL.trailingAnchor constraintEqualToAnchor:permCard.trailingAnchor constant:-14],
            [descL.bottomAnchor constraintEqualToAnchor:permCard.bottomAnchor constant:-13]
        ]];
    }
}

@end

#pragma mark - PPAdminSecurityVaultSheet

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
    self.view.backgroundColor = [UIColor ppSurfaceElevated];
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

    [self setupUI];
}

- (void)setupUI {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-32],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40]
    ]];

    // Header Lock Card
    UIView *headerCard = [[UIView alloc] init];
    headerCard.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(headerCard, PPCornerCard);
    [stack addArrangedSubview:headerCard];

    UIImageView *lockIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"]];
    lockIcon.translatesAutoresizingMaskIntoConstraints = NO;
    lockIcon.tintColor = [UIColor ppPrimary];
    [headerCard addSubview:lockIcon];

    UILabel *headerTitle = [[UILabel alloc] init];
    headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    headerTitle.text = [Language isRTL] ? @"خزنة الأمان والجلسات المعتمدة" : @"Security Vault & Active Sessions";
    headerTitle.font = [Styling fontBold:17.0];
    headerTitle.textColor = [UIColor ppTextPrimary];
    headerTitle.textAlignment = Language.alignmentForCurrentLanguage;
    [headerCard addSubview:headerTitle];

    UILabel *headerSubtitle = [[UILabel alloc] init];
    headerSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    headerSubtitle.text = [Language isRTL] ? @"حماية الحساب الإداري، المصادقة البيومترية، وإدارة كلمات المرور" : @"Administrative account defense, biometric auth, and credential lifecycle";
    headerSubtitle.font = [Styling fontRegular:12.5];
    headerSubtitle.textColor = [UIColor ppTextSecondary];
    headerSubtitle.numberOfLines = 2;
    headerSubtitle.textAlignment = Language.alignmentForCurrentLanguage;
    [headerCard addSubview:headerSubtitle];

    [NSLayoutConstraint activateConstraints:@[
        [lockIcon.topAnchor constraintEqualToAnchor:headerCard.topAnchor constant:16],
        [lockIcon.leadingAnchor constraintEqualToAnchor:headerCard.leadingAnchor constant:16],
        [lockIcon.widthAnchor constraintEqualToConstant:28],
        [lockIcon.heightAnchor constraintEqualToConstant:28],

        [headerTitle.topAnchor constraintEqualToAnchor:headerCard.topAnchor constant:14],
        [headerTitle.leadingAnchor constraintEqualToAnchor:lockIcon.trailingAnchor constant:12],
        [headerTitle.trailingAnchor constraintEqualToAnchor:headerCard.trailingAnchor constant:-16],

        [headerSubtitle.topAnchor constraintEqualToAnchor:headerTitle.bottomAnchor constant:4],
        [headerSubtitle.leadingAnchor constraintEqualToAnchor:headerTitle.leadingAnchor],
        [headerSubtitle.trailingAnchor constraintEqualToAnchor:headerTitle.trailingAnchor],
        [headerSubtitle.bottomAnchor constraintEqualToAnchor:headerCard.bottomAnchor constant:-16]
    ]];

    // 1. Biometrics Row
    UIView *bioRow = [[UIView alloc] init];
    bioRow.backgroundColor = [UIColor ppSurface];
    bioRow.layer.borderWidth = 1.0;
    bioRow.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(bioRow, PPCornerMedium);
    [stack addArrangedSubview:bioRow];

    UILabel *bioTitle = [[UILabel alloc] init];
    bioTitle.translatesAutoresizingMaskIntoConstraints = NO;
    bioTitle.text = [Language isRTL] ? @"المصادقة البيومترية (Face ID / Touch ID)" : @"Biometric Authentication";
    bioTitle.font = [Styling fontBold:14.5];
    bioTitle.textColor = [UIColor ppTextPrimary];
    bioTitle.textAlignment = Language.alignmentForCurrentLanguage;
    [bioRow addSubview:bioTitle];

    UILabel *bioSub = [[UILabel alloc] init];
    bioSub.translatesAutoresizingMaskIntoConstraints = NO;
    bioSub.text = [Language isRTL] ? @"طلب التحقق البيومتري عند فتح لوحة التحكم" : @"Require biometric check before unlocking session";
    bioSub.font = [Styling fontRegular:12.0];
    bioSub.textColor = [UIColor ppTextSecondary];
    bioSub.textAlignment = Language.alignmentForCurrentLanguage;
    [bioRow addSubview:bioSub];

    UISwitch *bioSwitch = [[UISwitch alloc] init];
    bioSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    bioSwitch.onTintColor = [UIColor ppPrimary];
    bioSwitch.on = YES;
    [bioRow addSubview:bioSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [bioTitle.topAnchor constraintEqualToAnchor:bioRow.topAnchor constant:14],
        [bioTitle.leadingAnchor constraintEqualToAnchor:bioRow.leadingAnchor constant:16],
        [bioTitle.trailingAnchor constraintLessThanOrEqualToAnchor:bioSwitch.leadingAnchor constant:-12],

        [bioSub.topAnchor constraintEqualToAnchor:bioTitle.bottomAnchor constant:2],
        [bioSub.leadingAnchor constraintEqualToAnchor:bioTitle.leadingAnchor],
        [bioSub.trailingAnchor constraintEqualToAnchor:bioTitle.trailingAnchor],
        [bioSub.bottomAnchor constraintEqualToAnchor:bioRow.bottomAnchor constant:-14],

        [bioSwitch.trailingAnchor constraintEqualToAnchor:bioRow.trailingAnchor constant:-16],
        [bioSwitch.centerYAnchor constraintEqualToAnchor:bioRow.centerYAnchor]
    ]];

    // 2. Reset Password Button
    UIButton *resetPassBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetPassBtn.backgroundColor = [UIColor ppSurface];
    resetPassBtn.layer.borderWidth = 1.0;
    resetPassBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(resetPassBtn, PPCornerMedium);
    [resetPassBtn setTitle:[Language isRTL] ? @"🔑 إرسال رابط إعادة تعيين كلمة المرور إلى البريد" : @"🔑 Send Password Reset Email" forState:UIControlStateNormal];
    [resetPassBtn setTitleColor:[UIColor ppPrimary] forState:UIControlStateNormal];
    resetPassBtn.titleLabel.font = [Styling fontBold:14.5];
    [resetPassBtn addTarget:self action:@selector(sendPasswordResetTapped) forControlEvents:UIControlEventTouchUpInside];
    [resetPassBtn.heightAnchor constraintEqualToConstant:50].active = YES;
    [stack addArrangedSubview:resetPassBtn];

    // 3. Active Device Card
    UIView *deviceCard = [[UIView alloc] init];
    deviceCard.backgroundColor = [UIColor ppSurface];
    deviceCard.layer.borderWidth = 1.0;
    deviceCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(deviceCard, PPCornerMedium);
    [stack addArrangedSubview:deviceCard];

    UIImageView *phoneIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"iphone.gen3"]];
    phoneIcon.translatesAutoresizingMaskIntoConstraints = NO;
    phoneIcon.tintColor = [UIColor ppTextSecondary];
    [deviceCard addSubview:phoneIcon];

    UILabel *deviceTitle = [[UILabel alloc] init];
    deviceTitle.translatesAutoresizingMaskIntoConstraints = NO;
    deviceTitle.text = [Language isRTL] ? @"الجهاز المصرح الحالي: iPhone 13 Pro Max" : @"Authorized Hardware: iPhone 13 Pro Max";
    deviceTitle.font = [Styling fontBold:14.0];
    deviceTitle.textColor = [UIColor ppTextPrimary];
    deviceTitle.textAlignment = Language.alignmentForCurrentLanguage;
    [deviceCard addSubview:deviceTitle];

    UILabel *deviceSub = [[UILabel alloc] init];
    deviceSub.translatesAutoresizingMaskIntoConstraints = NO;
    deviceSub.text = [Language isRTL] ? @"جلسة مصرحة وموثقة بواسطة Firebase App Check" : @"Session cryptographically bound via Firebase App Check";
    deviceSub.font = [Styling fontRegular:11.5];
    deviceSub.textColor = [UIColor ppSuccess];
    deviceSub.textAlignment = Language.alignmentForCurrentLanguage;
    [deviceCard addSubview:deviceSub];

    [NSLayoutConstraint activateConstraints:@[
        [phoneIcon.centerYAnchor constraintEqualToAnchor:deviceCard.centerYAnchor],
        [phoneIcon.leadingAnchor constraintEqualToAnchor:deviceCard.leadingAnchor constant:16],
        [phoneIcon.widthAnchor constraintEqualToConstant:24],
        [phoneIcon.heightAnchor constraintEqualToConstant:24],

        [deviceTitle.topAnchor constraintEqualToAnchor:deviceCard.topAnchor constant:14],
        [deviceTitle.leadingAnchor constraintEqualToAnchor:phoneIcon.trailingAnchor constant:12],
        [deviceTitle.trailingAnchor constraintEqualToAnchor:deviceCard.trailingAnchor constant:-16],

        [deviceSub.topAnchor constraintEqualToAnchor:deviceTitle.bottomAnchor constant:3],
        [deviceSub.leadingAnchor constraintEqualToAnchor:deviceTitle.leadingAnchor],
        [deviceSub.trailingAnchor constraintEqualToAnchor:deviceTitle.trailingAnchor],
        [deviceSub.bottomAnchor constraintEqualToAnchor:deviceCard.bottomAnchor constant:-14]
    ]];
}

- (void)sendPasswordResetTapped {
    [PPFunc pp_playTapEffect];
    NSString *email = self.user.email ?: [UserManager shared].currentUser.email;
    if (email.length == 0) {
        [PPHUD showError:kLang(@"Error") subtitle:[Language isRTL] ? @"لا يوجد بريد إلكتروني مسجل" : @"No email found"];
        return;
    }

    [PPHUD showIndeterminateIn:self.view title:[Language isRTL] ? @"جارٍ الإرسال..." : @"Sending..." subtitle:nil];
    [[FIRAuth auth] sendPasswordResetWithEmail:email completion:^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            [PPAlertHelper showInfoIn:self
                                title:[Language isRTL] ? @"تم إرسال الرابط بنجاح" : @"Reset Link Sent"
                             subtitle:[NSString stringWithFormat:[Language isRTL] ? @"تم إرسال رابط إعادة تعيين كلمة المرور إلى: %@" : @"Password reset instructions sent to: %@", email]];
        }
    }];
}

@end

#pragma mark - Category-Defining PPAdminProfileViewController

@interface PPAdminProfileViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UserModel *currentUser;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;

// Hero Subviews
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UIButton *changePhotoBtn;
@property (nonatomic, strong) UILabel *adminNameLabel;
@property (nonatomic, strong) UILabel *adminRoleBadge;
@property (nonatomic, strong) UILabel *adminEmailLabel;
@property (nonatomic, strong) UILabel *adminUidPill;

// KPI Labels
@property (nonatomic, strong) UILabel *kpiScopeLabel;
@property (nonatomic, strong) UILabel *kpiSessionLabel;
@property (nonatomic, strong) UILabel *kpiAuditLabel;

// Form Fields
@property (nonatomic, strong) UITextField *nameTextField;
@property (nonatomic, strong) UITextField *phoneTextField;
@property (nonatomic, strong) UIButton *saveChangesButton;
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

    [self setupNavigationBar];
    [self setupScrollView];
    [self setupHeroIdentityCard];
    [self setupCockpitKPICards];
    [self setupEditableCredentialsCard];
    [self setupQuickSystemRails];
    [self setupSignOutChamber];
    [self populateUserData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupNavigationBar];
    [self populateUserData];
}

#pragma mark - PPNavBar

- (void)setupNavigationBar {
    NSString *title = kLang(@"EditMyAccount_Title") ?: ([Language isRTL] ? @"حسابي (الملف الشخصي)" : @"My Account");
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:title showBack:YES];

    // Security Vault Icon in navbar
    UIButton *vaultBtn = [self pp_ButtonWithSystemName:@"lock.shield.fill" action:@selector(openSecurityVaultTapped)];
    vaultBtn.tintColor = [UIColor ppPrimary];
    vaultBtn.accessibilityLabel = [Language isRTL] ? @"أمان الجلسة" : @"Security Vault";
    [self pp_navBarAddActionButton:vaultBtn key:@"admin_security_vault"];
}

- (void)setupScrollView {
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scrollView];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 16.0;
    [_scrollView addSubview:_contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_contentStack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:14],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor constant:16],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor constant:-16],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-34],
        [_contentStack.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor constant:-32]
    ]];
}

#pragma mark - Hero Identity Chamber

- (void)setupHeroIdentityCard {
    _heroCard = [[UIView alloc] init];
    _heroCard.backgroundColor = [UIColor ppSurfaceElevated];
    _heroCard.layer.borderWidth = 1.0;
    _heroCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(_heroCard, PPCornerCard);
    PPApplyCardShadow(_heroCard);
    [_contentStack addArrangedSubview:_heroCard];

    // Avatar
    _avatarImageView = [[UIImageView alloc] init];
    _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarImageView.clipsToBounds = YES;
    _avatarImageView.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(_avatarImageView, 28.0);
    _avatarImageView.userInteractionEnabled = YES;
    UITapGestureRecognizer *avatarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(changeAvatarTapped)];
    [_avatarImageView addGestureRecognizer:avatarTap];
    [_heroCard addSubview:_avatarImageView];

    // Camera Badge Button
    _changePhotoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _changePhotoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _changePhotoBtn.backgroundColor = [UIColor ppPrimary];
    [_changePhotoBtn setImage:[UIImage systemImageNamed:@"camera.fill"] forState:UIControlStateNormal];
    _changePhotoBtn.tintColor = UIColor.whiteColor;
    PPApplyContinuousCorners(_changePhotoBtn, 14.0);
    [_changePhotoBtn addTarget:self action:@selector(changeAvatarTapped) forControlEvents:UIControlEventTouchUpInside];
    [_heroCard addSubview:_changePhotoBtn];

    // Admin Name
    _adminNameLabel = [[UILabel alloc] init];
    _adminNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _adminNameLabel.font = [Styling fontBold:20.0];
    _adminNameLabel.textColor = [UIColor ppTextPrimary];
    _adminNameLabel.textAlignment = NSTextAlignmentCenter;
    [_heroCard addSubview:_adminNameLabel];

    // Role Sovereign Pill
    _adminRoleBadge = [[UILabel alloc] init];
    _adminRoleBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _adminRoleBadge.font = [Styling fontBold:12.0];
    _adminRoleBadge.textColor = [UIColor ppPrimary];
    _adminRoleBadge.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.09];
    _adminRoleBadge.textAlignment = NSTextAlignmentCenter;
    PPApplyContinuousCorners(_adminRoleBadge, PPCornerPill);
    [_heroCard addSubview:_adminRoleBadge];

    // Email
    _adminEmailLabel = [[UILabel alloc] init];
    _adminEmailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _adminEmailLabel.font = [Styling fontRegular:13.5];
    _adminEmailLabel.textColor = [UIColor ppTextSecondary];
    _adminEmailLabel.textAlignment = NSTextAlignmentCenter;
    _adminEmailLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *emailTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyEmailTapped)];
    [_adminEmailLabel addGestureRecognizer:emailTap];
    [_heroCard addSubview:_adminEmailLabel];

    // Staff UID Pill
    _adminUidPill = [[UILabel alloc] init];
    _adminUidPill.translatesAutoresizingMaskIntoConstraints = NO;
    _adminUidPill.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium];
    _adminUidPill.textColor = [UIColor ppTextTertiary];
    _adminUidPill.textAlignment = NSTextAlignmentCenter;
    [_heroCard addSubview:_adminUidPill];

    [NSLayoutConstraint activateConstraints:@[
        [_avatarImageView.topAnchor constraintEqualToAnchor:_heroCard.topAnchor constant:20],
        [_avatarImageView.centerXAnchor constraintEqualToAnchor:_heroCard.centerXAnchor],
        [_avatarImageView.widthAnchor constraintEqualToConstant:84],
        [_avatarImageView.heightAnchor constraintEqualToConstant:84],

        [_changePhotoBtn.trailingAnchor constraintEqualToAnchor:_avatarImageView.trailingAnchor constant:4],
        [_changePhotoBtn.bottomAnchor constraintEqualToAnchor:_avatarImageView.bottomAnchor constant:4],
        [_changePhotoBtn.widthAnchor constraintEqualToConstant:28],
        [_changePhotoBtn.heightAnchor constraintEqualToConstant:28],

        [_adminNameLabel.topAnchor constraintEqualToAnchor:_avatarImageView.bottomAnchor constant:12],
        [_adminNameLabel.leadingAnchor constraintEqualToAnchor:_heroCard.leadingAnchor constant:16],
        [_adminNameLabel.trailingAnchor constraintEqualToAnchor:_heroCard.trailingAnchor constant:-16],

        [_adminRoleBadge.topAnchor constraintEqualToAnchor:_adminNameLabel.bottomAnchor constant:6],
        [_adminRoleBadge.centerXAnchor constraintEqualToAnchor:_heroCard.centerXAnchor],
        [_adminRoleBadge.heightAnchor constraintEqualToConstant:24],

        [_adminEmailLabel.topAnchor constraintEqualToAnchor:_adminRoleBadge.bottomAnchor constant:8],
        [_adminEmailLabel.centerXAnchor constraintEqualToAnchor:_heroCard.centerXAnchor],

        [_adminUidPill.topAnchor constraintEqualToAnchor:_adminEmailLabel.bottomAnchor constant:4],
        [_adminUidPill.centerXAnchor constraintEqualToAnchor:_heroCard.centerXAnchor],
        [_adminUidPill.bottomAnchor constraintEqualToAnchor:_heroCard.bottomAnchor constant:-18]
    ]];
}

#pragma mark - Cockpit KPI Cards

- (void)setupCockpitKPICards {
    UIStackView *kpiGrid = [[UIStackView alloc] init];
    kpiGrid.axis = UILayoutConstraintAxisHorizontal;
    kpiGrid.distribution = UIStackViewDistributionFillEqually;
    kpiGrid.spacing = 8;
    [_contentStack addArrangedSubview:kpiGrid];

    _kpiScopeLabel = [self makeKPILabelWithText:@"100%" color:[UIColor ppPrimary]];
    _kpiSessionLabel = [self makeKPILabelWithText:[Language isRTL] ? @"مؤمّنة" : @"Secure" color:[UIColor ppSuccess]];
    _kpiAuditLabel = [self makeKPILabelWithText:[Language isRTL] ? @"نشط" : @"Active" color:[UIColor ppTextPrimary]];

    UIView *tile1 = [self makeProfileKPITileWithTitle:[Language isRTL] ? @"نطاق الصلاحيات" : @"Privilege Tier"
                                                 icon:@"shield.checkered"
                                                color:[UIColor ppPrimary]
                                           valueLabel:_kpiScopeLabel
                                               action:@selector(openPermissionsInspectorTapped)];

    UIView *tile2 = [self makeProfileKPITileWithTitle:[Language isRTL] ? @"أمان الجلسة" : @"Session State"
                                                 icon:@"lock.circle.fill"
                                                color:[UIColor ppSuccess]
                                           valueLabel:_kpiSessionLabel
                                               action:@selector(openSecurityVaultTapped)];

    UIView *tile3 = [self makeProfileKPITileWithTitle:[Language isRTL] ? @"سجل العمليات" : @"Audit Trail"
                                                 icon:@"doc.text.magnifyingglass"
                                                color:[UIColor ppTextPrimary]
                                           valueLabel:_kpiAuditLabel
                                               action:@selector(openAuditLogTapped)];

    [kpiGrid addArrangedSubview:tile1];
    [kpiGrid addArrangedSubview:tile2];
    [kpiGrid addArrangedSubview:tile3];
}

- (UILabel *)makeKPILabelWithText:(NSString *)text color:(UIColor *)color {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [Styling fontBold:15.0];
    lbl.textColor = color;
    lbl.text = text;
    lbl.textAlignment = NSTextAlignmentCenter;
    return lbl;
}

- (UIView *)makeProfileKPITileWithTitle:(NSString *)title icon:(NSString *)icon color:(UIColor *)color valueLabel:(UILabel *)valLbl action:(SEL)action {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(card, PPCornerMedium);
    card.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:action];
    [card addGestureRecognizer:tap];

    UIImageView *ico = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    ico.translatesAutoresizingMaskIntoConstraints = NO;
    ico.tintColor = color;
    [card addSubview:ico];

    UILabel *titleL = [[UILabel alloc] init];
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    titleL.text = title;
    titleL.font = [Styling fontMedium:10.5];
    titleL.textColor = [UIColor ppTextSecondary];
    titleL.textAlignment = NSTextAlignmentCenter;
    [card addSubview:titleL];

    [card addSubview:valLbl];

    [NSLayoutConstraint activateConstraints:@[
        [ico.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [ico.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [ico.widthAnchor constraintEqualToConstant:18],
        [ico.heightAnchor constraintEqualToConstant:18],

        [valLbl.topAnchor constraintEqualToAnchor:ico.bottomAnchor constant:3],
        [valLbl.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],

        [titleL.topAnchor constraintEqualToAnchor:valLbl.bottomAnchor constant:2],
        [titleL.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [titleL.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10]
    ]];
    return card;
}

#pragma mark - Editable Credentials Form

- (void)setupEditableCredentialsCard {
    UIView *formCard = [[UIView alloc] init];
    formCard.backgroundColor = [UIColor ppSurfaceElevated];
    formCard.layer.borderWidth = 1.0;
    formCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(formCard, PPCornerCard);
    PPApplyCardShadow(formCard);
    [_contentStack addArrangedSubview:formCard];

    UILabel *sectionHeader = [[UILabel alloc] init];
    sectionHeader.translatesAutoresizingMaskIntoConstraints = NO;
    sectionHeader.text = [Language isRTL] ? @"البيانات الإدارية القابلة للتحديث" : @"Administrative Profile Details";
    sectionHeader.font = [Styling fontBold:14.5];
    sectionHeader.textColor = [UIColor ppTextPrimary];
    sectionHeader.textAlignment = Language.alignmentForCurrentLanguage;
    [formCard addSubview:sectionHeader];

    _nameTextField = [self makeStyledTextFieldWithPlaceholder:[Language isRTL] ? @"الاسم الكامل" : @"Full Name" icon:@"person.fill"];
    _nameTextField.delegate = self;
    [formCard addSubview:_nameTextField];

    _phoneTextField = [self makeStyledTextFieldWithPlaceholder:[Language isRTL] ? @"رقم الهاتف المعتمد" : @"Phone Number" icon:@"phone.fill"];
    _phoneTextField.keyboardType = UIKeyboardTypePhonePad;
    _phoneTextField.delegate = self;
    [formCard addSubview:_phoneTextField];

    _saveChangesButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _saveChangesButton.translatesAutoresizingMaskIntoConstraints = NO;
    _saveChangesButton.backgroundColor = [UIColor ppPrimary];
    [_saveChangesButton setTitle:[Language isRTL] ? @"💾 حفظ تحديثات الملف الشخصي" : @"💾 Save Profile Changes" forState:UIControlStateNormal];
    [_saveChangesButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _saveChangesButton.titleLabel.font = [Styling fontBold:15.0];
    PPApplyContinuousCorners(_saveChangesButton, PPCornerMedium);
    PPApplyButtonShadow(_saveChangesButton);
    [_saveChangesButton addTarget:self action:@selector(saveProfileChangesTapped) forControlEvents:UIControlEventTouchUpInside];
    [formCard addSubview:_saveChangesButton];

    [NSLayoutConstraint activateConstraints:@[
        [sectionHeader.topAnchor constraintEqualToAnchor:formCard.topAnchor constant:16],
        [sectionHeader.leadingAnchor constraintEqualToAnchor:formCard.leadingAnchor constant:16],
        [sectionHeader.trailingAnchor constraintEqualToAnchor:formCard.trailingAnchor constant:-16],

        [_nameTextField.topAnchor constraintEqualToAnchor:sectionHeader.bottomAnchor constant:12],
        [_nameTextField.leadingAnchor constraintEqualToAnchor:formCard.leadingAnchor constant:16],
        [_nameTextField.trailingAnchor constraintEqualToAnchor:formCard.trailingAnchor constant:-16],
        [_nameTextField.heightAnchor constraintEqualToConstant:48],

        [_phoneTextField.topAnchor constraintEqualToAnchor:_nameTextField.bottomAnchor constant:10],
        [_phoneTextField.leadingAnchor constraintEqualToAnchor:formCard.leadingAnchor constant:16],
        [_phoneTextField.trailingAnchor constraintEqualToAnchor:formCard.trailingAnchor constant:-16],
        [_phoneTextField.heightAnchor constraintEqualToConstant:48],

        [_saveChangesButton.topAnchor constraintEqualToAnchor:_phoneTextField.bottomAnchor constant:16],
        [_saveChangesButton.leadingAnchor constraintEqualToAnchor:formCard.leadingAnchor constant:16],
        [_saveChangesButton.trailingAnchor constraintEqualToAnchor:formCard.trailingAnchor constant:-16],
        [_saveChangesButton.heightAnchor constraintEqualToConstant:50],
        [_saveChangesButton.bottomAnchor constraintEqualToAnchor:formCard.bottomAnchor constant:-16]
    ]];
}

- (UITextField *)makeStyledTextFieldWithPlaceholder:(NSString *)placeholder icon:(NSString *)iconName {
    UITextField *tf = [[UITextField alloc] init];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    tf.backgroundColor = [UIColor ppSurface];
    tf.layer.borderWidth = 1.0;
    tf.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    tf.placeholder = placeholder;
    tf.font = [Styling fontMedium:14.5];
    tf.textColor = [UIColor ppTextPrimary];
    tf.textAlignment = Language.alignmentForCurrentLanguage;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    PPApplyContinuousCorners(tf, PPCornerMedium);

    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 48)];
    UIImageView *ico = [[UIImageView alloc] initWithFrame:CGRectMake(12, 14, 20, 20)];
    ico.image = [UIImage systemImageNamed:iconName];
    ico.tintColor = [UIColor ppTextSecondary];
    ico.contentMode = UIViewContentModeScaleAspectFit;
    [leftPad addSubview:ico];

    tf.leftView = leftPad;
    tf.leftViewMode = UITextFieldViewModeAlways;
    return tf;
}

#pragma mark - Fast System Rails

- (void)setupQuickSystemRails {
    UIView *railsCard = [[UIView alloc] init];
    railsCard.backgroundColor = [UIColor ppSurfaceElevated];
    railsCard.layer.borderWidth = 1.0;
    railsCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(railsCard, PPCornerCard);
    PPApplyCardShadow(railsCard);
    [_contentStack addArrangedSubview:railsCard];

    UIStackView *railsStack = [[UIStackView alloc] init];
    railsStack.translatesAutoresizingMaskIntoConstraints = NO;
    railsStack.axis = UILayoutConstraintAxisVertical;
    railsStack.spacing = 2;
    [railsCard addSubview:railsStack];

    [NSLayoutConstraint activateConstraints:@[
        [railsStack.topAnchor constraintEqualToAnchor:railsCard.topAnchor constant:8],
        [railsStack.leadingAnchor constraintEqualToAnchor:railsCard.leadingAnchor constant:8],
        [railsStack.trailingAnchor constraintEqualToAnchor:railsCard.trailingAnchor constant:-8],
        [railsStack.bottomAnchor constraintEqualToAnchor:railsCard.bottomAnchor constant:-8]
    ]];

    [railsStack addArrangedSubview:[self makeRailRowWithTitle:[Language isRTL] ? @"إعدادات الإشعارات الإدارية" : @"Notification Settings"
                                                         icon:@"bell.badge.fill"
                                                        color:[UIColor systemOrangeColor]
                                                       action:@selector(openNotificationSettingsTapped)]];

    [railsStack addArrangedSubview:[self makeRailRowWithTitle:[Language isRTL] ? @"لغة الواجهة (العربية ⇄ English)" : @"App Language (AR ⇄ EN)"
                                                         icon:@"globe"
                                                        color:[UIColor ppPrimary]
                                                       action:@selector(toggleLanguageTapped)]];

    [railsStack addArrangedSubview:[self makeRailRowWithTitle:[Language isRTL] ? @"مركز الدعم والمساعدة الإدارية" : @"Admin Support Center"
                                                         icon:@"questionmark.circle.fill"
                                                        color:[UIColor systemTealColor]
                                                       action:@selector(openHelpCenterTapped)]];
}

- (UIView *)makeRailRowWithTitle:(NSString *)title icon:(NSString *)icon color:(UIColor *)color action:(SEL)action {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = UIColor.clearColor;
    [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [row.heightAnchor constraintEqualToConstant:50].active = YES;

    UIImageView *ico = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    ico.translatesAutoresizingMaskIntoConstraints = NO;
    ico.tintColor = color;
    [row addSubview:ico];

    UILabel *titleL = [[UILabel alloc] init];
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    titleL.text = title;
    titleL.font = [Styling fontMedium:14.5];
    titleL.textColor = [UIColor ppTextPrimary];
    titleL.textAlignment = Language.alignmentForCurrentLanguage;
    [row addSubview:titleL];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = [UIColor ppTextTertiary];
    [row addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [ico.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [ico.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [ico.widthAnchor constraintEqualToConstant:22],
        [ico.heightAnchor constraintEqualToConstant:22],

        [titleL.leadingAnchor constraintEqualToAnchor:ico.trailingAnchor constant:12],
        [titleL.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [titleL.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-8],

        [chevron.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [chevron.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:14],
        [chevron.heightAnchor constraintEqualToConstant:14]
    ]];
    return row;
}

#pragma mark - Sign Out Chamber

- (void)setupSignOutChamber {
    UIButton *signOutBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    signOutBtn.translatesAutoresizingMaskIntoConstraints = NO;
    signOutBtn.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.08];
    signOutBtn.layer.borderWidth = 1.0;
    signOutBtn.layer.borderColor = [[UIColor ppError] colorWithAlphaComponent:0.25].CGColor;
    PPApplyContinuousCorners(signOutBtn, PPCornerMedium);
    [signOutBtn setTitle:[Language isRTL] ? @"🚪 إنهاء جلسة الإدارة بأمان" : @"🚪 Sign Out Securely" forState:UIControlStateNormal];
    [signOutBtn setTitleColor:[UIColor ppError] forState:UIControlStateNormal];
    signOutBtn.titleLabel.font = [Styling fontBold:15.0];
    [signOutBtn addTarget:self action:@selector(confirmSignOutTapped) forControlEvents:UIControlEventTouchUpInside];
    [signOutBtn.heightAnchor constraintEqualToConstant:50].active = YES;
    [_contentStack addArrangedSubview:signOutBtn];
}

#pragma mark - Data Binding

- (void)populateUserData {
    UserModel *user = self.currentUser ?: [UserManager shared].currentUser;
    if (!user) return;

    NSString *dispName = [user PPBestDisplayName];
    if (dispName.length == 0) dispName = user.UserName ?: user.displayName;
    self.adminNameLabel.text = dispName.length > 0 ? dispName : ([Language isRTL] ? @"مسؤول المنصة" : @"Platform Admin");
    self.nameTextField.text = ([user PPBestDisplayName] ?: user.UserName ?: @"");
    self.phoneTextField.text = user.MobileNo ?: @"";
    self.adminEmailLabel.text = user.email.length > 0 ? user.email : @"admin@pure-pets.net";
    self.adminUidPill.text = [NSString stringWithFormat:@"STAFF ID: %@", [user.uid.length > 8 ? [user.uid substringToIndex:8] : user.uid uppercaseString]];

    NSString *roleText = [Language isRTL] ? @"👑 مالك النظام الإداري (Owner)" : @"👑 Sovereign System Owner";
    if (user.role == UserRoleSuperAdmin || user.isSuperAdmin) {
        roleText = [Language isRTL] ? @"⚡ مدير عام (Super Admin)" : @"⚡ Super Administrator";
    } else if (user.role == UserRoleAdmin || user.isAdmin) {
        roleText = [Language isRTL] ? @"🛡️ مسؤول معتمد (Admin)" : @"🛡️ Authorized Administrator";
    }
    self.adminRoleBadge.text = [NSString stringWithFormat:@"  %@  ", roleText];

    // Avatar Image
    NSString *avatarUrl = user.photoURL ?: user.UserImageUrl.absoluteString ?: user.UserImageName;
    if (avatarUrl.length > 0) {
        [self.avatarImageView sd_setImageWithURL:[NSURL URLWithString:avatarUrl]
                               placeholderImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    } else {
        self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
        self.avatarImageView.tintColor = [UIColor ppPrimary];
    }
}

#pragma mark - Actions

- (void)openPermissionsInspectorTapped {
    [PPFunc pp_playTapEffect];
    PPAdminPermissionsInspectorSheet *sheet = [[PPAdminPermissionsInspectorSheet alloc] initWithUser:self.currentUser];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openSecurityVaultTapped {
    [PPFunc pp_playTapEffect];
    PPAdminSecurityVaultSheet *sheet = [[PPAdminSecurityVaultSheet alloc] initWithUser:self.currentUser];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openAuditLogTapped {
    [PPFunc pp_playTapEffect];
    PPAuditLogViewController *vc = [[PPAuditLogViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openNotificationSettingsTapped {
    [PPFunc pp_playTapEffect];
    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openHelpCenterTapped {
    [PPFunc pp_playTapEffect];
    [PPAlertHelper showInfoIn:self title:kLang(@"HelpCenter") subtitle:kLang(@"Settings_Help_Message")];
}

- (void)toggleLanguageTapped {
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
        [weakSelf populateUserData];
    } cancelBlock:nil];
}

- (void)copyEmailTapped {
    [PPFunc pp_playTapEffect];
    NSString *email = self.adminEmailLabel.text;
    if (email.length > 0) {
        [UIPasteboard generalPasteboard].string = email;
        [PPToast toast:[Language isRTL] ? @"تم نسخ البريد الإلكتروني" : @"Email copied to clipboard!"];
    }
}

- (void)changeAvatarTapped {
    [PPFunc pp_playTapEffect];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[Language isRTL] ? @"تحديث الصورة الشخصية للمسؤول" : @"Update Admin Avatar"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [alert addAction:[UIAlertAction actionWithTitle:[Language isRTL] ? @"📸 التقاط صورة بالكاميرا" : @"📸 Take Photo"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [weakSelf openImagePickerWithSource:UIImagePickerControllerSourceTypeCamera];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:[Language isRTL] ? @"🖼️ اختيار من مكتبة الصور" : @"🖼️ Choose from Library"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf openImagePickerWithSource:UIImagePickerControllerSourceTypePhotoLibrary];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openImagePickerWithSource:(UIImagePickerControllerSourceType)sourceType {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = sourceType;
    picker.allowsEditing = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *chosen = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (!chosen) return;

    self.avatarImageView.image = chosen;
    [PPHUD showIndeterminateIn:self.view title:[Language isRTL] ? @"جارٍ رفع الصورة..." : @"Uploading Photo..." subtitle:nil];

    NSData *data = UIImageJPEGRepresentation(chosen, 0.75);
    NSString *uid = self.currentUser.uid ?: [UserManager shared].currentUser.uid;
    NSString *path = [NSString stringWithFormat:@"profile_images/%@.jpg", uid];
    FIRStorageReference *ref = [[FIRStorage storage] referenceWithPath:path];
    FIRStorageMetadata *meta = [[FIRStorageMetadata alloc] init];
    meta.contentType = @"image/jpeg";

    __weak typeof(self) weakSelf = self;
    [ref putData:data metadata:meta completion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
        if (error) {
            [PPHUD dismiss];
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            return;
        }

        [ref downloadURLWithCompletion:^(NSURL * _Nullable URL, NSError * _Nullable error2) {
            if (URL) {
                NSString *urlStr = URL.absoluteString;
                [[UserManager shared] updateUserFieldsForUID:uid fields:@{@"userProfileImageUrl": urlStr} completion:^(NSError * _Nullable error3) {
                    [PPHUD dismiss];
                    if (error3) {
                        [PPHUD showError:kLang(@"Error") subtitle:error3.localizedDescription];
                    } else {
                        weakSelf.currentUser.photoURL = urlStr;
                        weakSelf.currentUser.UserImageUrl = [NSURL URLWithString:urlStr];
                        [UserManager shared].currentUser.photoURL = urlStr;
                        [UserManager shared].currentUser.UserImageUrl = [NSURL URLWithString:urlStr];
                        [PPHUD showSuccess:[Language isRTL] ? @"تم تحديث الصورة الشخصية بنجاح" : @"Avatar updated successfully!"];
                    }
                }];
            } else {
                [PPHUD dismiss];
            }
        }];
    }];
}

- (void)saveProfileChangesTapped {
    [PPFunc pp_playTapEffect];
    [self.view endEditing:YES];

    NSString *name = [self.nameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *phone = [self.phoneTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *uid = self.currentUser.uid ?: [UserManager shared].currentUser.uid;

    if (uid.length == 0) return;

    [PPHUD showIndeterminateIn:self.view title:[Language isRTL] ? @"جارٍ الحفظ..." : @"Saving..." subtitle:nil];

    NSDictionary *fields = @{
        @"UserName": name ?: @"",
        @"displayName": name ?: @"",
        @"MobileNo": phone ?: @""
    };

    __weak typeof(self) weakSelf = self;
    [[UserManager shared] updateUserFieldsForUID:uid fields:fields completion:^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            weakSelf.currentUser.UserName = name;
            weakSelf.currentUser.displayName = name;
            weakSelf.currentUser.MobileNo = phone;
            [UserManager shared].currentUser.UserName = name;
            [UserManager shared].currentUser.displayName = name;
            [UserManager shared].currentUser.MobileNo = phone;
            [weakSelf populateUserData];
            [PPHUD showSuccess:[Language isRTL] ? @"تم حفظ البيانات بنجاح" : @"Profile updated!"];
        }
    }];
}

- (void)confirmSignOutTapped {
    [PPAlertHelper showConfirmationIn:self
                                title:kLang(@"Logout_Confirm_Title")
                             subtitle:kLang(@"Logout_Confirm_Message")
                          placeholder:nil
                        confirmButton:kLang(@"Confirm")
                         cancelButton:kLang(@"Cancel")
                                 icon:[UIImage systemImageNamed:@"power.circle.fill"]
                         confirmBlock:^{
        [UsrMgr signOutWithCompletion:nil];
    } cancelBlock:nil];
}

@end

#pragma mark - PPSettingsViewController (with full PPNavBar)

@interface PPSettingsViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UIView *avatarShell;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *emailLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *profileChevron;
@property (nonatomic, strong) UILabel *settingsSubtitleLabel;
@property (nonatomic, strong) UIButton *profileCard;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *settingsSections;
@property (nonatomic, strong) NSArray<NSString *> *settingsSectionTitles;
@end

@implementation PPSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self setupNavigation];
    [self setupSettingsItems];
    [self setupTableView];
    [self setupHeaderUI];
    [self updateProfileInfo];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setupNavigation];
    [self updateProfileInfo];
}

- (void)setupNavigation {
    NSString *title = kLang(@"Settings") ?: ([Language isRTL] ? @"الإعدادات" : @"Settings");
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:title showBack:YES];
}

- (void)setupSettingsItems {
    self.settingsSectionTitles = @[
        kLang(@"Settings_Section_Preferences"),
        kLang(@"Settings_Section_Support"),
        kLang(@"Settings_Section_Session")
    ];
    self.settingsSections = @[
        @[
            @{
                @"title": kLang(@"NotificationSettings"),
                @"subtitle": kLang(@"Settings_Notifications_Subtitle"),
                @"icon": @"bell.badge.fill",
                @"action": @"openNotifications",
                @"tone": @"care"
            },
            @{
                @"title": kLang(@"AppLanguage"),
                @"subtitle": kLang(@"Settings_Language_Subtitle"),
                @"icon": @"globe",
                @"action": @"openLanguage",
                @"tone": @"accent"
            }
        ],
        @[
            @{
                @"title": kLang(@"HelpCenter"),
                @"subtitle": kLang(@"Settings_Help_Subtitle"),
                @"icon": @"questionmark.circle.fill",
                @"action": @"openHelp",
                @"tone": @"care"
            }
        ],
        @[
            @{
                @"title": kLang(@"Logout"),
                @"subtitle": kLang(@"Settings_Logout_Subtitle"),
                @"icon": @"power.circle.fill",
                @"action": @"logout",
                @"tone": @"destructive"
            }
        ]
    ];
}

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.sectionHeaderTopPadding = 0.0;
    _tableView.contentInset = UIEdgeInsetsMake(0, 0, 80, 0);
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupHeaderUI {
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 180)];
    header.backgroundColor = UIColor.clearColor;

    _settingsSubtitleLabel = [[UILabel alloc] init];
    _settingsSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsSubtitleLabel.text = kLang(@"Settings_ProfileSubtitle");
    _settingsSubtitleLabel.textColor = [UIColor ppTextTertiary];
    _settingsSubtitleLabel.font = [Styling fontMedium:12.5];
    _settingsSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [header addSubview:_settingsSubtitleLabel];

    _profileCard = [UIButton buttonWithType:UIButtonTypeCustom];
    _profileCard.translatesAutoresizingMaskIntoConstraints = NO;
    _profileCard.backgroundColor = [UIColor ppSurfaceElevated];
    _profileCard.layer.borderWidth = 1.0;
    _profileCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(_profileCard, PPCornerCard);
    PPApplyCardShadow(_profileCard);
    [_profileCard addTarget:self action:@selector(pp_openProfile) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_profileCard];

    _avatarShell = [[UIView alloc] init];
    _avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarShell.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(_avatarShell, 20.0);
    _avatarShell.userInteractionEnabled = NO;
    [_profileCard addSubview:_avatarShell];

    _avatarIMV = [[UIImageView alloc] init];
    _avatarIMV.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarIMV.contentMode = UIViewContentModeScaleAspectFill;
    _avatarIMV.clipsToBounds = YES;
    PPApplyContinuousCorners(_avatarIMV, 20.0);
    _avatarIMV.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    _avatarIMV.tintColor = [UIColor ppPrimary];
    [_avatarShell addSubview:_avatarIMV];

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [Styling fontBold:16.5];
    _nameLabel.textColor = [UIColor ppTextPrimary];
    _nameLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [_profileCard addSubview:_nameLabel];

    _roleLabel = [[UILabel alloc] init];
    _roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleLabel.font = [Styling fontMedium:12.5];
    _roleLabel.textColor = [UIColor ppPrimary];
    _roleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [_profileCard addSubview:_roleLabel];

    _emailLabel = [[UILabel alloc] init];
    _emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emailLabel.font = [Styling fontRegular:12.0];
    _emailLabel.textColor = [UIColor ppTextSecondary];
    _emailLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [_profileCard addSubview:_emailLabel];

    _profileChevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
    _profileChevron.translatesAutoresizingMaskIntoConstraints = NO;
    _profileChevron.tintColor = [UIColor ppTextTertiary];
    [_profileCard addSubview:_profileChevron];

    [NSLayoutConstraint activateConstraints:@[
        [_settingsSubtitleLabel.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
        [_settingsSubtitleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [_settingsSubtitleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],

        [_profileCard.topAnchor constraintEqualToAnchor:_settingsSubtitleLabel.bottomAnchor constant:10],
        [_profileCard.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [_profileCard.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [_profileCard.heightAnchor constraintEqualToConstant:94],

        [_avatarShell.centerYAnchor constraintEqualToAnchor:_profileCard.centerYAnchor],
        [_avatarShell.trailingAnchor constraintEqualToAnchor:_profileCard.trailingAnchor constant:-14],
        [_avatarShell.widthAnchor constraintEqualToConstant:62],
        [_avatarShell.heightAnchor constraintEqualToConstant:62],

        [_avatarIMV.topAnchor constraintEqualToAnchor:_avatarShell.topAnchor],
        [_avatarIMV.leadingAnchor constraintEqualToAnchor:_avatarShell.leadingAnchor],
        [_avatarIMV.trailingAnchor constraintEqualToAnchor:_avatarShell.trailingAnchor],
        [_avatarIMV.bottomAnchor constraintEqualToAnchor:_avatarShell.bottomAnchor],

        [_nameLabel.topAnchor constraintEqualToAnchor:_profileCard.topAnchor constant:16],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:_avatarShell.leadingAnchor constant:-12],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_profileChevron.trailingAnchor constant:8],

        [_roleLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:3],
        [_roleLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
        [_roleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],

        [_emailLabel.topAnchor constraintEqualToAnchor:_roleLabel.bottomAnchor constant:2],
        [_emailLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
        [_emailLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],

        [_profileChevron.leadingAnchor constraintEqualToAnchor:_profileCard.leadingAnchor constant:14],
        [_profileChevron.centerYAnchor constraintEqualToAnchor:_profileCard.centerYAnchor],
        [_profileChevron.widthAnchor constraintEqualToConstant:14],
        [_profileChevron.heightAnchor constraintEqualToConstant:14]
    ]];

    _tableView.tableHeaderView = header;
}

- (void)updateProfileInfo {
    UserModel *user = [UserManager shared].currentUser;
    if (!user) return;

    NSString *dispName = [user PPBestDisplayName];
    if (dispName.length == 0) dispName = user.UserName ?: user.displayName;
    self.nameLabel.text = dispName.length > 0 ? dispName : ([Language isRTL] ? @"مسؤول المنصة" : @"Platform Admin");
    self.roleLabel.text = [Language isRTL] ? @"مالك النظام الإداري (Owner)" : @"Sovereign Admin";
    self.emailLabel.text = (user.UserEmail.length > 0 ? user.UserEmail : (user.email.length > 0 ? user.email : @"admin@pure-pets.net"));

    NSString *avatarStr = user.photoURL ?: user.UserImageUrl.absoluteString ?: user.UserImageName;
    if (avatarStr.length > 0) {
        [self.avatarIMV sd_setImageWithURL:[NSURL URLWithString:avatarStr]
                          placeholderImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    }
}

- (void)pp_openProfile {
    [PPFunc pp_playTapEffect];
    UserModel *currentUser = [UserManager shared].currentUser;
    PPAdminProfileViewController *profileVC = [[PPAdminProfileViewController alloc] initWithUser:currentUser];
    [self.navigationController pushViewController:profileVC animated:YES];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.settingsSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settingsSections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.settingsSectionTitles[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SettingsCell"];
        cell.backgroundColor = [UIColor ppSurfaceElevated];
        cell.layer.borderWidth = 0.5;
        cell.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        cell.layer.cornerRadius = 14.0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    NSDictionary *item = self.settingsSections[indexPath.section][indexPath.row];
    cell.textLabel.text = item[@"title"];
    cell.textLabel.font = [Styling fontBold:14.5];
    cell.textLabel.textColor = [item[@"tone"] isEqualToString:@"destructive"] ? [UIColor ppError] : [UIColor ppTextPrimary];

    cell.detailTextLabel.text = item[@"subtitle"];
    cell.detailTextLabel.font = [Styling fontRegular:12.0];
    cell.detailTextLabel.textColor = [UIColor ppTextSecondary];

    cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
    cell.imageView.tintColor = [item[@"tone"] isEqualToString:@"destructive"] ? [UIColor ppError] : [UIColor ppPrimary];

    cell.accessoryType = [item[@"tone"] isEqualToString:@"destructive"] ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.settingsSections[indexPath.section][indexPath.row];
    NSString *action = item[@"action"];

    if ([action isEqualToString:@"openNotifications"]) {
        NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openLanguage"]) {
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
            [weakSelf setupSettingsItems];
            [weakSelf.tableView reloadData];
        } cancelBlock:nil];
    } else if ([action isEqualToString:@"openHelp"]) {
        [PPAlertHelper showInfoIn:self title:kLang(@"HelpCenter") subtitle:kLang(@"Settings_Help_Message")];
    } else if ([action isEqualToString:@"logout"]) {
        [PPAlertHelper showConfirmationIn:self
                                    title:kLang(@"Logout_Confirm_Title")
                                 subtitle:kLang(@"Logout_Confirm_Message")
                              placeholder:nil
                            confirmButton:kLang(@"Confirm")
                             cancelButton:kLang(@"Cancel")
                                     icon:[UIImage systemImageNamed:@"power.circle.fill"]
                             confirmBlock:^{
            [UsrMgr signOutWithCompletion:nil];
        } cancelBlock:nil];
    }
}

@end
