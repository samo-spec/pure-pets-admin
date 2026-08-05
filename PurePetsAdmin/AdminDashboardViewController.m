//
//  AdminDashboardViewController.m
//  PurePetsAdmin
//

#import "AdminDashboardViewController.h"
#import "PPHero.h"
#import "PPFirebaseCompat.h"
#import "NotificationComposerViewController.h"
#import "NotificationSettingsViewController.h"
#import "NotificationsListViewController.h"
#import "PPBannersListVC.h"
#import "PPPaymentManagementViewController.h"
#import "PPPaymentBasicsSettingsViewController.h"
#import "PPVetsListViewController.h"
#import "PPServicesListViewController.h"
#import "PPAdminWebAppViewController.h"
#import "AccessoriesListViewController.h"
#import "UsersListVC.h"
#import "UserManagementController.h"
#import "AdminLoginViewController.h"
#import "AddUserViewController.h"
#import "BlockUserViewController.h"
#import "StaffMembersViewController.h"
#import "StaffRolesViewController.h"
#import "PPStaffAuth.h"
#import "UsersSection/UserController/PPStaffManagementViewController.h"
#import "HomeControl/PPHomeControlPanelViewController.h"
#import "CategoriesSection/PPCategoriesViewController.h"
#import "CategoriesSection/PPListingsAdminViewController.h"
#import "BranchSection/PPBranchesViewController.h"
#import "AgentSection/PPAgentsViewController.h"
#import "Fulfillment/PPFulfillmentOrdersViewController.h"
#import "Delivery/PPDeliveryManagementViewController.h"
#import "Accounting/PPAccountingViewController.h"
#import "Providers/PPProviderApplicationsViewController.h"
#import "Providers/PPProviderPlansViewController.h"
#import "Providers/PPProviderFeatureAccessViewController.h"
#import "Providers/PPProviderAccountingViewController.h"
#import "POS/PPPOSFastSellViewController.h"
#import "POS/PPPOSHistoryViewController.h"
#import "CategoriesSection/PPContentModerationViewController.h"
#import "CategoriesSection/PPAuditLogViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "PPBranchesViewController.h"
@import Firebase;
@import FirebaseAuth;

static CGFloat const kPPAdminDashboardHeaderHeight = 322.0;
static CGFloat const kPPAdminDashboardRowHeight = 84.0;
static CGFloat const kPPAdminDashboardSectionInset = 20.0;

static NSString * const kPPDashboardSectionTitleKey = @"title";
static NSString * const kPPDashboardSectionDetailKey = @"detail";
static NSString * const kPPDashboardSectionItemsKey = @"items";
static NSString * const kPPDashboardItemTagKey = @"tag";
static NSString * const kPPDashboardItemTitleKey = @"title";
static NSString * const kPPDashboardItemSubtitleKey = @"subtitle";
static NSString * const kPPDashboardItemIconKey = @"icon";
static NSString * const kPPDashboardItemTintKey = @"tint";

static NSInteger PPAdminDashboardSectionPriority(NSDictionary<NSString *, id> *sectionInfo) {
    NSArray<NSDictionary<NSString *, id> *> *items = sectionInfo[kPPDashboardSectionItemsKey];
    NSString *firstTag = items.firstObject[kPPDashboardItemTagKey];
    if (firstTag.length == 0) return NSIntegerMax;

    static NSDictionary<NSString *, NSNumber *> *priorityByTag;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        priorityByTag = @{
            @"fulfillment": @0,
            @"delivery": @1,
            @"payments": @2,
            @"paymentBasics": @2,
            @"usersList": @3,
            @"moderation": @4,
            @"listings": @5,
            @"banners": @5,
            @"notificationsInbox": @6,
            @"notificationsCompose": @6,
            @"notificationSettings": @6,
            @"accessories": @7,
            @"food": @7,
            @"livePets": @7,
            @"pos": @8,
            @"posHistory": @8,
            @"providerApplications": @9,
            @"providerPlans": @9,
            @"providerFeatures": @9,
            @"providerAccounting": @9,
            @"accounting": @10,
            @"services": @11,
            @"vets": @12,
            @"branches": @13,
            @"agents": @14,
            @"categories": @15,
            @"homeControl": @16,
            @"staffManagement": @17,
            @"audit": @18,
            @"editMyAccount": @19
        };
    });

    NSNumber *priority = priorityByTag[firstTag];
    return priority ? priority.integerValue : NSIntegerMax;
}

static UIColor *PPAdminDashboardCanvasColor(UITraitCollection *traits) {
    (void)traits;
    return AppBackgroundClr;
}

static BOOL PPAdminDashboardIsDark(UITraitCollection *traits) {
    if (@available(iOS 13.0, *)) {
        return (traits ?: UITraitCollection.currentTraitCollection).userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

static UIColor *PPAdminDashboardResolvedColor(UIColor *color, UITraitCollection *traits) {
    if (!color) return AppClearClr;
    if (@available(iOS 13.0, *)) {
        return [color resolvedColorWithTraitCollection:(traits ?: UITraitCollection.currentTraitCollection)];
    }
    return color;
}

static UIColor *PPAdminDashboardHeroSignatureColor(UITraitCollection *traits) {
    (void)traits;
    return AppPrimaryClr ?: AppSecondaryClr;
}

static UIColor *PPAdminDashboardHeroInkColor(void) {
    return PrimaryTextClr;
}

static UIColor *PPAdminDashboardHeroSecondaryInkColor(void) {
    return SeconderyTextClr;
}

static UIColor *PPAdminDashboardHeroTertiaryInkColor(void) {
    return PPTextTertiaryColor();
}

static UIColor *PPAdminDashboardHeroLiquidBorderColor(void) {
    return PPLiquidBorderColor();
}

static UIColor *PPAdminDashboardHeroHairlineColor(void) {
    return PPHairlineColor();
}

static UIColor *PPAdminDashboardHeroPanelColor(UITraitCollection *traits) {
    BOOL dark = PPAdminDashboardIsDark(traits);
    if (UIAccessibilityIsReduceTransparencyEnabled()) {
        return AppBackgroundClrShiner;
    }
    return [AppBackgroundClrShiner colorWithAlphaComponent:dark ? 0.72 : 0.64];
}

static UIColor *PPAdminDashboardHeroControlColor(UITraitCollection *traits) {
    BOOL dark = PPAdminDashboardIsDark(traits);
    if (UIAccessibilityIsReduceTransparencyEnabled()) {
        return AppForgroundColr;
    }
    return [AppForgroundColr colorWithAlphaComponent:dark ? 0.76 : 0.70];
}

static UIColor *PPAdminDashboardHeroCriticalTintColor(UITraitCollection *traits) {
    (void)traits;
    return AppPrimaryClrDarker ?: AppPrimaryClr ?: AppSecondaryClr;
}

static UIFont *PPAdminDashboardScaledFont(UIFont *font, UIFontTextStyle textStyle) {
    if (!font) return [UIFont preferredFontForTextStyle:textStyle];
    return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:font];
}

static UIColor *PPAdminDashboardTintForTag(NSString *tag) {
    if ([tag isEqualToString:@"staffList"] || [tag isEqualToString:@"staffManagement"] || [tag isEqualToString:@"addUser"] || [tag isEqualToString:@"staffRoles"] ||
        [tag isEqualToString:@"usersList"] || [tag isEqualToString:@"usersRolePermissions"] || [tag isEqualToString:@"blockUser"]) {
        return AppPrimaryClr;
    }
    if ([tag isEqualToString:@"accessories"] || [tag isEqualToString:@"food"] || [tag isEqualToString:@"livePets"]) {
        return AppSecondaryClr ?: AppPrimaryClr;
    }
    if ([tag isEqualToString:@"services"]) {
        return AppSecondaryClr;
    }
    if ([tag isEqualToString:@"vets"]) {
        return AppPrimaryClrDarker;
    }
    if ([tag isEqualToString:@"listings"]) {
        return AppSecondaryClr;
    }
    if ([tag isEqualToString:@"banners"]) {
        return AppPrimaryClrDarker ?: AppPrimaryClr;
    }
    if ([tag isEqualToString:@"payments"] || [tag isEqualToString:@"paymentBasics"]) {
        return AppSecondaryClr;
    }
    if ([tag hasPrefix:@"notification"]) {
        return AppPrimaryClrDarker;
    }
    if ([tag isEqualToString:@"adminWebApp"]) {
        return AppSecondaryClr;
    }
    if ([tag isEqualToString:@"homeControl"]) {
        return AppPrimaryClrShiner ?: AppSecondaryClr ?: AppPrimaryClr;
    }
    if ([tag isEqualToString:@"fulfillment"]) {
        return AppPrimaryClr;
    }
    if ([tag isEqualToString:@"delivery"]) {
        return AppSecondaryClr;
    }
    if ([tag isEqualToString:@"accounting"]) {
        return AppSecondaryClr ?: AppPrimaryClr;
    }
    if ([tag isEqualToString:@"providers"]) {
        return AppPrimaryClrDarker ?: AppPrimaryClr;
    }
    if ([tag isEqualToString:@"pos"] || [tag isEqualToString:@"posHistory"]) {
        return AppPrimaryClrDarker ?: AppSecondaryClr ?: AppPrimaryClr;
    }
    if ([tag isEqualToString:@"moderation"]) {
        return AppPrimaryClrShiner ?: AppSecondaryClr ?: AppPrimaryClr;
    }
    if ([tag isEqualToString:@"audit"]) {
        return AppPrimaryClrDarker;
    }
    return AppPrimaryClr;
}

@interface PPAdminDashboardBackdropView : UIView
@property (nonatomic, strong) CAGradientLayer *baseLayer;
@property (nonatomic, strong) CAGradientLayer *topLightLayer;
@property (nonatomic, strong) CAGradientLayer *lowerLightLayer;
- (void)startMotionIfNeeded;
- (void)stopMotion;
- (void)refreshPalette;
@end

@implementation PPAdminDashboardBackdropView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.userInteractionEnabled = NO;
    self.opaque = YES;

    _baseLayer = [CAGradientLayer layer];
    _baseLayer.startPoint = CGPointMake(0.08, 0.0);
    _baseLayer.endPoint = CGPointMake(0.92, 1.0);
    [self.layer addSublayer:_baseLayer];

    _topLightLayer = [CAGradientLayer layer];
    _topLightLayer.type = kCAGradientLayerRadial;
    _topLightLayer.startPoint = CGPointMake(0.42, 0.38);
    _topLightLayer.endPoint = CGPointMake(0.94, 0.94);
    _topLightLayer.locations = @[@0.0, @0.54, @1.0];
    [self.layer addSublayer:_topLightLayer];

    _lowerLightLayer = [CAGradientLayer layer];
    _lowerLightLayer.type = kCAGradientLayerRadial;
    _lowerLightLayer.startPoint = CGPointMake(0.56, 0.42);
    _lowerLightLayer.endPoint = CGPointMake(0.96, 0.96);
    _lowerLightLayer.locations = @[@0.0, @0.58, @1.0];
    [self.layer addSublayer:_lowerLightLayer];

    [self refreshPalette];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.baseLayer.frame = self.bounds;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    self.topLightLayer.frame = CGRectMake(-width * 0.34, -width * 0.24, width * 1.10, width * 1.10);
    self.lowerLightLayer.frame = CGRectMake(width * 0.30, MAX(260.0, height * 0.46), width * 0.92, width * 0.92);
    [CATransaction commit];
}

- (void)refreshPalette {
    BOOL isDark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIColor *canvas = PPAdminDashboardCanvasColor(self.traitCollection);
    UIColor *secondary = AppBackgroundClrDarker;
    UIColor *signature = AppPrimaryClr ?: AppSecondaryClr;
    UIColor *warm = AppPrimaryClrShiner ?: AppSecondaryClr ?: AppPrimaryClr;

    self.backgroundColor = canvas;
    self.baseLayer.colors = @[(id)canvas.CGColor, (id)secondary.CGColor, (id)canvas.CGColor];
    self.baseLayer.locations = @[@0.0, @0.55, @1.0];
    self.topLightLayer.colors = @[
        (id)[signature colorWithAlphaComponent:isDark ? 0.11 : 0.075].CGColor,
        (id)[signature colorWithAlphaComponent:isDark ? 0.035 : 0.020].CGColor,
        (id)AppClearClr.CGColor
    ];
    self.lowerLightLayer.colors = @[
        (id)[warm colorWithAlphaComponent:isDark ? 0.065 : 0.050].CGColor,
        (id)[warm colorWithAlphaComponent:0.018].CGColor,
        (id)AppClearClr.CGColor
    ];
}

- (void)startMotionIfNeeded {
    if (!self.window || UIAccessibilityIsReduceMotionEnabled()) {
        [self stopMotion];
        return;
    }
    BOOL hasTopMotion = [self.topLightLayer animationForKey:@"pp.admin.backdrop.top"] != nil;
    BOOL hasLowerMotion = [self.lowerLightLayer animationForKey:@"pp.admin.backdrop.lower"] != nil;
    if (hasTopMotion && hasLowerMotion) return;

    if (!hasTopMotion) {
        CABasicAnimation *topOpacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
        topOpacity.fromValue = @0.66;
        topOpacity.toValue = @1.0;
        CABasicAnimation *topScale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        topScale.fromValue = @0.97;
        topScale.toValue = @1.035;
        CAAnimationGroup *topGroup = [CAAnimationGroup animation];
        topGroup.animations = @[topOpacity, topScale];
        topGroup.duration = 8.6;
        topGroup.autoreverses = YES;
        topGroup.repeatCount = HUGE_VALF;
        topGroup.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.topLightLayer addAnimation:topGroup forKey:@"pp.admin.backdrop.top"];
    }

    if (!hasLowerMotion) {
        CABasicAnimation *lowerOpacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
        lowerOpacity.fromValue = @0.58;
        lowerOpacity.toValue = @0.90;
        CABasicAnimation *lowerScale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        lowerScale.fromValue = @1.02;
        lowerScale.toValue = @0.965;
        CAAnimationGroup *lowerGroup = [CAAnimationGroup animation];
        lowerGroup.animations = @[lowerOpacity, lowerScale];
        lowerGroup.duration = 10.2;
        lowerGroup.beginTime = CACurrentMediaTime() + 0.7;
        lowerGroup.autoreverses = YES;
        lowerGroup.repeatCount = HUGE_VALF;
        lowerGroup.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.lowerLightLayer addAnimation:lowerGroup forKey:@"pp.admin.backdrop.lower"];
    }
}

- (void)stopMotion {
    [self.topLightLayer removeAnimationForKey:@"pp.admin.backdrop.top"];
    [self.lowerLightLayer removeAnimationForKey:@"pp.admin.backdrop.lower"];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self refreshPalette];
    }
}

@end

@interface AdminDashboardViewController ()
@property (nonatomic, strong) PPAdminDashboardBackdropView *dashboardBackdropView;
@property (nonatomic, strong) UIView *dashboardLoadingView;
@property (nonatomic, strong) UIActivityIndicatorView *dashboardLoadingIndicator;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UILabel *heroBadgeLabel;
@property (nonatomic, strong) UILabel *adminNameLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *heroSummaryLabel;
@property (nonatomic, strong) UILabel *heroAccessLabel;
@property (nonatomic, strong) UIView *heroBadgeContainer;
@property (nonatomic, strong) UIView *heroStatusDotView;
@property (nonatomic, strong) UIView *heroAccessPill;
@property (nonatomic, strong) UIImageView *heroAccessIconView;
@property (nonatomic, strong) UIView *heroIdentityContainer;
@property (nonatomic, strong) UIView *heroStatsContainer;
@property (nonatomic, strong) UIView *heroStatsAccentView;
@property (nonatomic, strong) UIView *heroSurfaceView;
@property (nonatomic, strong) UIView *heroShadowView;
@property (nonatomic, strong) UIView *heroAvatarShellView;
@property (nonatomic, strong) UIButton *heroAvatarEditButton;
@property (nonatomic, strong) UIView *avatarBadgeView;
@property (nonatomic, strong) PPHero *heroGlassBG;
@property (nonatomic, strong) UIButton *heroLanguageButton;
@property (nonatomic, strong) UIButton *heroLogoutButton;
@property (nonatomic, strong) UILabel *statAdsValueLbl;
@property (nonatomic, strong) UILabel *statAccValueLbl;
@property (nonatomic, strong) UILabel *statUsersValueLbl;
@property (nonatomic, strong) id<FIRListenerRegistration> reg;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *dashboardSections;
@property (nonatomic, assign) NSInteger dashboardActionCount;
@property (nonatomic, assign) BOOL hasAnimatedHeaderIntro;
@property (nonatomic, assign) BOOL hasPreparedHeaderIntro;
@property (nonatomic, assign) BOOL hasStartedCountListener;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedDashboardTags;
@end

@implementation AdminDashboardViewController

- (instancetype)init {
    self = [super initWithForm:[XLFormDescriptor formDescriptor] style:UITableViewStyleGrouped];
    if (self) {
        _animatedDashboardTags = [NSMutableSet set];
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = PPAdminDashboardCanvasColor(self.traitCollection);
    self.dashboardBackdropView = [[PPAdminDashboardBackdropView alloc] initWithFrame:CGRectZero];
    self.dashboardBackdropView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view insertSubview:self.dashboardBackdropView belowSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.dashboardBackdropView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.dashboardBackdropView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.dashboardBackdropView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.dashboardBackdropView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.tableView.backgroundColor = AppClearClr;
    self.tableView.backgroundView = nil;
    self.tableView.opaque = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.estimatedRowHeight = kPPAdminDashboardRowHeight;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.insetsContentViewsToSafeArea = NO;
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.layoutMargins = UIEdgeInsetsZero;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pp_reduceMotionStatusDidChange:)
                                                 name:UIAccessibilityReduceMotionStatusDidChangeNotification
                                               object:nil];
    [self pp_buildDashboardLoadingStateIfNeeded];

    NSString *currentUID = [FIRAuth auth].currentUser.uid;
    UserModel *curUser = UsrMgr.currentUser;
    if (!curUser && currentUID.length > 0) {
        curUser = [UsrMgr p_readUserFromDisk:currentUID];
    }

    if (curUser) {
        UsrMgr.currentUser = curUser;
        [self setupHeaderUIWithUser:curUser];
        [self pp_rebuildDashboardFormPreservingOffset:NO];
        [self pp_syncCachedAdminNotificationTokenIfNeeded];
        [self pp_setDashboardLoadingVisible:NO];
    } else {
        [self pp_setDashboardLoadingVisible:YES];
        __weak typeof(self) weakSelf = self;
        [FUM reloadCurrentUserWithCompletion:^(UserModel * _Nullable user, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || !user) {
                    [weakSelf pp_setDashboardLoadingVisible:NO];
                    [weakSelf showLogin];
                    return;
                }

                UsrMgr.currentUser = user;
                [weakSelf setupHeaderUIWithUser:user];
                [weakSelf pp_rebuildDashboardFormPreservingOffset:NO];
                [weakSelf pp_syncCachedAdminNotificationTokenIfNeeded];
                [weakSelf pp_setDashboardLoadingVisible:NO];
            });
        }];
    }

    if (currentUID.length == 0) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.reg = [RPM listenPermissionsForUID:currentUID onChange:^(NSDictionary *perms, NSError *error) {
        if (error) {
            return;
        }

        if (!UsrMgr.currentUser) {
            return;
        }

        if (![UsrMgr.currentUser.permissions isKindOfClass:NSMutableDictionary.class]) {
            UsrMgr.currentUser.permissions = [NSMutableDictionary dictionary];
        }
        [UsrMgr.currentUser.permissions setDictionary:perms ?: @{}];

        PPStaffDoc *cachedStaff = [PPStaffAuth shared].cachedCurrentStaff;
        if (cachedStaff.uid.length == 0 || ![cachedStaff.uid isEqualToString:UsrMgr.currentUser.uid]) {
            cachedStaff = nil;
        }

        if (cachedStaff) {
            UserRole mappedRole = [PPStaffAuth legacyRoleFromStaffRole:cachedStaff.role];
            if (mappedRole != UserRoleUnknown) {
                UsrMgr.currentUser.role = mappedRole;
            }
            UsrMgr.currentUser.isSuperAdmin = [cachedStaff.role isEqualToString:PPStaffRoleSuperAdmin];
            UsrMgr.currentUser.isAdmin = UsrMgr.currentUser.isSuperAdmin || [cachedStaff.role isEqualToString:PPStaffRoleOwner];
            UsrMgr.currentUser.isBlocked = !cachedStaff.isActive;
        }

        [weakSelf pp_rebuildDashboardFormPreservingOffset:YES];
        [weakSelf setupHeaderUIWithUser:UsrMgr.currentUser];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_sizeTableHeaderToFit];
    [self pp_updateHeroGradientFrame];
    [self pp_applyHeaderMotionForOffset:self.tableView.contentOffset.y];
    if (self.avatarBadgeView.superview) {
        [self.avatarBadgeView.superview bringSubviewToFront:self.avatarBadgeView];
    }
    if (!CGRectIsEmpty(self.heroShadowView.bounds)) {
        self.heroShadowView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.heroShadowView.bounds
                                                                          cornerRadius:32.0].CGPath;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.dashboardBackdropView startMotionIfNeeded];
    [self.heroGlassBG startAnimations];
    [self pp_animateHeaderIntroIfNeeded];
    [self pp_animateVisibleCellsModern];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];

    [self updateHeaderWithUser:UsrMgr.currentUser];
    [self pp_rebuildDashboardFormPreservingOffset:YES];
    [self pp_prepareHeaderIntroIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self.dashboardBackdropView stopMotion];
    [self.heroGlassBG stopAnimations];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIAccessibilityReduceMotionStatusDidChangeNotification
                                                  object:nil];
    [self.reg remove];
    [AppMgr stopCountsListening];
}

#pragma mark - Header

- (void)setupHeaderUIWithUser:(UserModel *)curUser {
    if (self.headerRoot) {
        [self updateHeaderWithUser:curUser];
        [self pp_refreshHeroCopy];
        return;
    }

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), kPPAdminDashboardHeaderHeight)];
    header.backgroundColor = AppClearClr;
    header.clipsToBounds = NO;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.headerRoot = header;

    UIView *heroShadowView = [UIView new];
    heroShadowView.translatesAutoresizingMaskIntoConstraints = NO;
    heroShadowView.backgroundColor = AppClearClr;
    heroShadowView.layer.cornerRadius = 32.0;
    heroShadowView.layer.cornerCurve = kCACornerCurveContinuous;
    heroShadowView.layer.shadowColor = AppShadowColor.CGColor;
    heroShadowView.layer.shadowOpacity = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.28 : 0.10;
    heroShadowView.layer.shadowRadius = 30.0;
    heroShadowView.layer.shadowOffset = CGSizeMake(0.0, 18.0);
    // We insert heroShadowView directly into self.view so it remains fixed
    [self.view addSubview:heroShadowView];
    self.heroShadowView = heroShadowView;

    UIView *heroSurfaceView = [UIView new];
    heroSurfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    heroSurfaceView.backgroundColor = AppClearClr;
    heroSurfaceView.clipsToBounds = NO;
    [heroShadowView addSubview:heroSurfaceView];
    self.heroSurfaceView = heroSurfaceView;

    PPHero *glassBG = [PPHero new];
    glassBG.translatesAutoresizingMaskIntoConstraints = NO;
    glassBG.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    glassBG.cornerGlowOpacityMultiplier = 0.34;
    glassBG.accentColorOverride = PPAdminDashboardHeroSignatureColor(self.traitCollection);
    [heroSurfaceView addSubview:glassBG];
    self.heroGlassBG = glassBG;

    UIColor *accentColor = PPAdminDashboardHeroSignatureColor(self.traitCollection);

    UIView *contentOverlay = [UIView new];
    contentOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    contentOverlay.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [heroSurfaceView addSubview:contentOverlay];

    UIView *badgeView = [UIView new];
    badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    badgeView.backgroundColor = AppClearClr;
    [contentOverlay addSubview:badgeView];
    self.heroBadgeContainer = badgeView;

    UILabel *badgeLabel = [UILabel new];
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    badgeLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:11], UIFontTextStyleCaption1);
    badgeLabel.adjustsFontForContentSizeCategory = YES;
    badgeLabel.textColor = PPAdminDashboardHeroSecondaryInkColor();
    badgeLabel.textAlignment = [Language alignmentForCurrentLanguage];
    badgeLabel.numberOfLines = 1;
    badgeLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.heroBadgeLabel = badgeLabel;

    UIView *badgeDot = [UIView new];
    badgeDot.translatesAutoresizingMaskIntoConstraints = NO;
    badgeDot.backgroundColor = [accentColor colorWithAlphaComponent:0.96];
    badgeDot.layer.cornerRadius = 3.0;
    badgeDot.layer.cornerCurve = kCACornerCurveContinuous;
    self.heroStatusDotView = badgeDot;

    UIStackView *badgeStack = [[UIStackView alloc] initWithArrangedSubviews:@[badgeDot, badgeLabel]];
    badgeStack.translatesAutoresizingMaskIntoConstraints = NO;
    badgeStack.axis = UILayoutConstraintAxisHorizontal;
    badgeStack.alignment = UIStackViewAlignmentCenter;
    badgeStack.spacing = 8.0;
    badgeStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [badgeView addSubview:badgeStack];

    UIView *accessPill = [UIView new];
    accessPill.translatesAutoresizingMaskIntoConstraints = NO;
    accessPill.backgroundColor = PPAdminDashboardHeroControlColor(self.traitCollection);
    accessPill.layer.cornerRadius = 17.0;
    accessPill.layer.cornerCurve = kCACornerCurveContinuous;
    accessPill.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    accessPill.layer.borderColor = PPAdminDashboardHeroHairlineColor().CGColor;
    accessPill.isAccessibilityElement = YES;
    accessPill.accessibilityTraits = UIAccessibilityTraitStaticText;
    self.heroAccessPill = accessPill;

    UIImageView *accessIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"key.fill"]];
    accessIcon.translatesAutoresizingMaskIntoConstraints = NO;
    accessIcon.tintColor = [accentColor colorWithAlphaComponent:0.92];
    accessIcon.contentMode = UIViewContentModeScaleAspectFit;
    [accessPill addSubview:accessIcon];
    self.heroAccessIconView = accessIcon;

    UILabel *accessLabel = [UILabel new];
    accessLabel.translatesAutoresizingMaskIntoConstraints = NO;
    accessLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:11], UIFontTextStyleCaption1);
    accessLabel.adjustsFontForContentSizeCategory = YES;
    accessLabel.textColor = PPAdminDashboardHeroSecondaryInkColor();
    accessLabel.textAlignment = NSTextAlignmentNatural;
    accessLabel.numberOfLines = 1;
    accessLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    accessLabel.accessibilityElementsHidden = YES;
    [accessPill addSubview:accessLabel];
    self.heroAccessLabel = accessLabel;

    UIButton *languageButton = [self pp_makeHeroIconButtonWithSystemName:@"globe"
                                                       accessibilityLabel:kLang(@"Confirm_LanguageChange_Title")
                                                                   action:@selector(didTapLanguage)
                                                                 critical:NO];
    self.heroLanguageButton = languageButton;

    UIButton *logoutButton = [self pp_makeHeroIconButtonWithSystemName:@"power"
                                                     accessibilityLabel:kLang(@"Logout")
                                                                 action:@selector(didTapAuthButton)
                                                               critical:YES];
    self.heroLogoutButton = logoutButton;

    UIStackView *topActionStack = [[UIStackView alloc] initWithArrangedSubviews:@[accessPill, languageButton, logoutButton]];
    topActionStack.translatesAutoresizingMaskIntoConstraints = NO;
    topActionStack.axis = UILayoutConstraintAxisHorizontal;
    topActionStack.alignment = UIStackViewAlignmentCenter;
    topActionStack.distribution = UIStackViewDistributionFill;
    topActionStack.spacing = 8.0;
    topActionStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [contentOverlay addSubview:topActionStack];

    UIView *identityContainer = [UIView new];
    identityContainer.translatesAutoresizingMaskIntoConstraints = NO;
    identityContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [contentOverlay addSubview:identityContainer];
    self.heroIdentityContainer = identityContainer;

    UIView *avatarShell = [UIView new];
    avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    avatarShell.backgroundColor = PPAdminDashboardHeroControlColor(self.traitCollection);
    avatarShell.layer.cornerRadius = 38.0;
    avatarShell.layer.cornerCurve = kCACornerCurveContinuous;
    avatarShell.layer.shadowColor = AppShadowColor.CGColor;
    avatarShell.layer.shadowOpacity = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.24 : 0.085;
    avatarShell.layer.shadowRadius = 18.0;
    avatarShell.layer.shadowOffset = CGSizeMake(0.0, 12.0);
    avatarShell.clipsToBounds = NO;
    self.heroAvatarShellView = avatarShell;

    UIImageView *avatar = [UIImageView new];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.layer.cornerRadius = 33.0;
    avatar.clipsToBounds = YES;
    avatar.userInteractionEnabled = YES;
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.isAccessibilityElement = YES;
    avatar.accessibilityTraits = UIAccessibilityTraitButton;
    [avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapAddProfilePhoto)]];
    [avatarShell addSubview:avatar];
    self.avatarIMV = avatar;

    UIButton *editAvatarButton = [UIButton buttonWithType:UIButtonTypeSystem];
    editAvatarButton.translatesAutoresizingMaskIntoConstraints = NO;
    editAvatarButton.backgroundColor = PPAdminDashboardHeroControlColor(self.traitCollection);
    editAvatarButton.tintColor = PPAdminDashboardHeroInkColor();
    editAvatarButton.layer.cornerRadius = 14.0;
    editAvatarButton.layer.cornerCurve = kCACornerCurveContinuous;
    editAvatarButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    editAvatarButton.layer.borderColor = PPAdminDashboardHeroHairlineColor().CGColor;
    editAvatarButton.clipsToBounds = YES;
    UIImageSymbolConfiguration *smallSymbol = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold];
    [editAvatarButton setImage:[UIImage systemImageNamed:@"pencil" withConfiguration:smallSymbol] forState:UIControlStateNormal];
    [editAvatarButton addTarget:self action:@selector(didTapAddProfilePhoto) forControlEvents:UIControlEventTouchUpInside];
    editAvatarButton.hidden = YES;
    editAvatarButton.userInteractionEnabled = NO;
    editAvatarButton.isAccessibilityElement = NO;
    [avatarShell addSubview:editAvatarButton];
    self.heroAvatarEditButton = editAvatarButton;

    UIView *avatarBadgeView = [UIView new];
    avatarBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarBadgeView.backgroundColor = [accentColor colorWithAlphaComponent:0.98];
    avatarBadgeView.layer.cornerRadius = 12.0;
    avatarBadgeView.layer.cornerCurve = kCACornerCurveContinuous;
    avatarBadgeView.layer.borderWidth = 1.5;
    avatarBadgeView.layer.borderColor = PPAdminDashboardHeroLiquidBorderColor().CGColor;
    avatarBadgeView.layer.shadowColor = AppShadowColor.CGColor;
    avatarBadgeView.layer.shadowOpacity = 0.12;
    avatarBadgeView.layer.shadowRadius = 12.0;
    avatarBadgeView.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    avatarBadgeView.userInteractionEnabled = NO;
    avatarBadgeView.layer.zPosition = 40.0;
    [avatarShell addSubview:avatarBadgeView];
    self.avatarBadgeView = avatarBadgeView;

    UIImageView *avatarBadgeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
    avatarBadgeIcon.translatesAutoresizingMaskIntoConstraints = NO;
    avatarBadgeIcon.tintColor = PPOnPrimaryColor();
    avatarBadgeIcon.contentMode = UIViewContentModeScaleAspectFit;
    [avatarBadgeView addSubview:avatarBadgeIcon];

    UILabel *nameLabel = [UILabel new];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.font = PPAdminDashboardScaledFont([Styling fontBold:33], UIFontTextStyleLargeTitle);
    nameLabel.adjustsFontForContentSizeCategory = YES;
    nameLabel.textColor = PPAdminDashboardHeroInkColor();
    nameLabel.textAlignment = [Language alignmentForCurrentLanguage];
    nameLabel.numberOfLines = 2;
    nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    nameLabel.allowsDefaultTighteningForTruncation = YES;
    self.adminNameLabel = nameLabel;

    UILabel *roleLabel = [UILabel new];
    roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    roleLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:14], UIFontTextStyleSubheadline);
    roleLabel.adjustsFontForContentSizeCategory = YES;
    roleLabel.textColor = PPAdminDashboardHeroSecondaryInkColor();
    roleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    roleLabel.numberOfLines = 2;
    self.roleLabel = roleLabel;

    UILabel *summaryLabel = [UILabel new];
    summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    summaryLabel.font = PPAdminDashboardScaledFont([Styling fontRegular:12], UIFontTextStyleFootnote);
    summaryLabel.adjustsFontForContentSizeCategory = YES;
    summaryLabel.textColor = PPAdminDashboardHeroTertiaryInkColor();
    summaryLabel.textAlignment = [Language alignmentForCurrentLanguage];
    summaryLabel.numberOfLines = 2;
    summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.heroSummaryLabel = summaryLabel;

    UIStackView *copyStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameLabel, roleLabel, summaryLabel]];
    copyStack.translatesAutoresizingMaskIntoConstraints = NO;
    copyStack.axis = UILayoutConstraintAxisVertical;
    copyStack.alignment = UIStackViewAlignmentFill;
    copyStack.spacing = 6.0;
    copyStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *identityStack = [[UIStackView alloc] initWithArrangedSubviews:@[copyStack, avatarShell]];
    identityStack.translatesAutoresizingMaskIntoConstraints = NO;
    identityStack.axis = UILayoutConstraintAxisHorizontal;
    identityStack.alignment = UIStackViewAlignmentCenter;
    identityStack.distribution = UIStackViewDistributionFill;
    identityStack.spacing = 16.0;
    identityStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [identityContainer addSubview:identityStack];

    UIView *statsPanel = [UIView new];
    statsPanel.translatesAutoresizingMaskIntoConstraints = NO;
    statsPanel.backgroundColor = PPAdminDashboardHeroPanelColor(self.traitCollection);
    statsPanel.layer.cornerRadius = 22.0;
    statsPanel.layer.cornerCurve = kCACornerCurveContinuous;
    statsPanel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    statsPanel.layer.borderColor = PPAdminDashboardHeroHairlineColor().CGColor;
    statsPanel.clipsToBounds = YES;
    [contentOverlay addSubview:statsPanel];
    self.heroStatsContainer = statsPanel;

    UIView *statsTopLine = [UIView new];
    statsTopLine.translatesAutoresizingMaskIntoConstraints = NO;
    statsTopLine.backgroundColor = [accentColor colorWithAlphaComponent:0.52];
    statsTopLine.userInteractionEnabled = NO;
    [statsPanel addSubview:statsTopLine];
    self.heroStatsAccentView = statsTopLine;

    UIStackView *statsStack = [UIStackView new];
    statsStack.axis = UILayoutConstraintAxisHorizontal;
    statsStack.distribution = UIStackViewDistributionFillEqually;
    statsStack.spacing = 0.0;
    statsStack.translatesAutoresizingMaskIntoConstraints = NO;
    statsStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [statsPanel addSubview:statsStack];

    self.statAdsValueLbl = [UILabel new];
    self.statAccValueLbl = [UILabel new];
    self.statUsersValueLbl = [UILabel new];

    [statsStack addArrangedSubview:[self pp_makeHeroStatItemWithTitle:kLang(@"pp_stats_ads") valueLabel:self.statAdsValueLbl]];
    [statsStack addArrangedSubview:[self pp_makeHeroStatItemWithTitle:kLang(@"pp_stats_accessories") valueLabel:self.statAccValueLbl]];
    [statsStack addArrangedSubview:[self pp_makeHeroStatItemWithTitle:kLang(@"pp_stats_users") valueLabel:self.statUsersValueLbl]];

    for (NSInteger index = 1; index < statsStack.arrangedSubviews.count; index++) {
        UIView *separator = [UIView new];
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        separator.backgroundColor = PPAdminDashboardHeroHairlineColor();
        [statsPanel addSubview:separator];
        UIView *item = statsStack.arrangedSubviews[index];
        [NSLayoutConstraint activateConstraints:@[
            [separator.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
            [separator.topAnchor constraintEqualToAnchor:statsPanel.topAnchor constant:18.0],
            [separator.bottomAnchor constraintEqualToAnchor:statsPanel.bottomAnchor constant:-18.0],
            [separator.centerXAnchor constraintEqualToAnchor:item.leadingAnchor]
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [heroShadowView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:0.0],
        [heroShadowView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [heroShadowView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [heroShadowView.heightAnchor constraintEqualToConstant:kPPAdminDashboardHeaderHeight - 16.0],

        [heroSurfaceView.topAnchor constraintEqualToAnchor:heroShadowView.topAnchor],
        [heroSurfaceView.leadingAnchor constraintEqualToAnchor:heroShadowView.leadingAnchor],
        [heroSurfaceView.trailingAnchor constraintEqualToAnchor:heroShadowView.trailingAnchor],
        [heroSurfaceView.bottomAnchor constraintEqualToAnchor:heroShadowView.bottomAnchor],

        [self.heroGlassBG.topAnchor constraintEqualToAnchor:heroSurfaceView.topAnchor],
        [self.heroGlassBG.leadingAnchor constraintEqualToAnchor:heroSurfaceView.leadingAnchor],
        [self.heroGlassBG.trailingAnchor constraintEqualToAnchor:heroSurfaceView.trailingAnchor],
        [self.heroGlassBG.bottomAnchor constraintEqualToAnchor:heroSurfaceView.bottomAnchor],

        [contentOverlay.topAnchor constraintEqualToAnchor:heroSurfaceView.safeAreaLayoutGuide.topAnchor constant:12.0],
        [contentOverlay.leadingAnchor constraintEqualToAnchor:heroSurfaceView.leadingAnchor constant:22.0],
        [contentOverlay.trailingAnchor constraintEqualToAnchor:heroSurfaceView.trailingAnchor constant:-22.0],
        [contentOverlay.bottomAnchor constraintEqualToAnchor:heroSurfaceView.bottomAnchor constant:-20.0],

        [badgeView.topAnchor constraintEqualToAnchor:contentOverlay.topAnchor],
        [badgeView.leadingAnchor constraintEqualToAnchor:contentOverlay.leadingAnchor],
        [badgeView.trailingAnchor constraintLessThanOrEqualToAnchor:topActionStack.leadingAnchor constant:-12.0],

        [badgeStack.topAnchor constraintEqualToAnchor:badgeView.topAnchor constant:7.0],
        [badgeStack.leadingAnchor constraintEqualToAnchor:badgeView.leadingAnchor],
        [badgeStack.trailingAnchor constraintEqualToAnchor:badgeView.trailingAnchor],
        [badgeStack.bottomAnchor constraintEqualToAnchor:badgeView.bottomAnchor constant:-7.0],

        [badgeDot.widthAnchor constraintEqualToConstant:6.0],
        [badgeDot.heightAnchor constraintEqualToConstant:6.0],

        [topActionStack.topAnchor constraintEqualToAnchor:contentOverlay.topAnchor],
        [topActionStack.trailingAnchor constraintEqualToAnchor:contentOverlay.trailingAnchor],
        [topActionStack.heightAnchor constraintGreaterThanOrEqualToConstant:36.0],

        [accessPill.heightAnchor constraintGreaterThanOrEqualToConstant:32.0],

        [accessIcon.leadingAnchor constraintEqualToAnchor:accessPill.leadingAnchor constant:11.0],
        [accessIcon.centerYAnchor constraintEqualToAnchor:accessPill.centerYAnchor],
        [accessIcon.widthAnchor constraintEqualToConstant:12.0],
        [accessIcon.heightAnchor constraintEqualToConstant:12.0],
        [accessLabel.leadingAnchor constraintEqualToAnchor:accessIcon.trailingAnchor constant:7.0],
        [accessLabel.trailingAnchor constraintEqualToAnchor:accessPill.trailingAnchor constant:-12.0],
        [accessLabel.topAnchor constraintEqualToAnchor:accessPill.topAnchor constant:7.0],
        [accessLabel.bottomAnchor constraintEqualToAnchor:accessPill.bottomAnchor constant:-7.0],

        [languageButton.widthAnchor constraintEqualToConstant:40.0],
        [languageButton.heightAnchor constraintEqualToConstant:40.0],
        [logoutButton.widthAnchor constraintEqualToConstant:40.0],
        [logoutButton.heightAnchor constraintEqualToConstant:40.0],

        [identityContainer.topAnchor constraintEqualToAnchor:topActionStack.bottomAnchor constant:16.0],

        [identityContainer.leadingAnchor constraintEqualToAnchor:contentOverlay.leadingAnchor],
        [identityContainer.trailingAnchor constraintEqualToAnchor:contentOverlay.trailingAnchor],
        [identityContainer.bottomAnchor constraintLessThanOrEqualToAnchor:statsPanel.topAnchor constant:-12.0],

        [identityStack.topAnchor constraintEqualToAnchor:identityContainer.topAnchor],
        [identityStack.leadingAnchor constraintEqualToAnchor:identityContainer.leadingAnchor],
        [identityStack.trailingAnchor constraintEqualToAnchor:identityContainer.trailingAnchor],
        [identityStack.bottomAnchor constraintLessThanOrEqualToAnchor:identityContainer.bottomAnchor],

        [avatarShell.widthAnchor constraintEqualToConstant:76.0],
        [avatarShell.heightAnchor constraintEqualToConstant:76.0],

        [avatar.topAnchor constraintEqualToAnchor:avatarShell.topAnchor constant:5.0],
        [avatar.leadingAnchor constraintEqualToAnchor:avatarShell.leadingAnchor constant:5.0],
        [avatar.trailingAnchor constraintEqualToAnchor:avatarShell.trailingAnchor constant:-5.0],
        [avatar.bottomAnchor constraintEqualToAnchor:avatarShell.bottomAnchor constant:-5.0],

        [editAvatarButton.widthAnchor constraintEqualToConstant:28.0],
        [editAvatarButton.heightAnchor constraintEqualToConstant:28.0],
        [editAvatarButton.topAnchor constraintEqualToAnchor:avatarShell.topAnchor constant:3.0],
        [editAvatarButton.leadingAnchor constraintEqualToAnchor:avatarShell.leadingAnchor constant:3.0],

        [avatarBadgeView.widthAnchor constraintEqualToConstant:24.0],
        [avatarBadgeView.heightAnchor constraintEqualToConstant:24.0],
        [avatarBadgeView.trailingAnchor constraintEqualToAnchor:avatarShell.trailingAnchor constant:2.0],
        [avatarBadgeView.bottomAnchor constraintEqualToAnchor:avatarShell.bottomAnchor constant:2.0],

        [avatarBadgeIcon.centerXAnchor constraintEqualToAnchor:avatarBadgeView.centerXAnchor],
        [avatarBadgeIcon.centerYAnchor constraintEqualToAnchor:avatarBadgeView.centerYAnchor],
        [avatarBadgeIcon.widthAnchor constraintEqualToConstant:11.0],
        [avatarBadgeIcon.heightAnchor constraintEqualToConstant:11.0],

        [statsPanel.leadingAnchor constraintEqualToAnchor:contentOverlay.leadingAnchor],
        [statsPanel.trailingAnchor constraintEqualToAnchor:contentOverlay.trailingAnchor],
        [statsPanel.bottomAnchor constraintEqualToAnchor:contentOverlay.bottomAnchor],
        [statsPanel.heightAnchor constraintEqualToConstant:76.0],

        [statsTopLine.topAnchor constraintEqualToAnchor:statsPanel.topAnchor],
        [statsTopLine.leadingAnchor constraintEqualToAnchor:statsPanel.leadingAnchor constant:24.0],
        [statsTopLine.widthAnchor constraintEqualToConstant:44.0],
        [statsTopLine.heightAnchor constraintEqualToConstant:2.0],

        [statsStack.topAnchor constraintEqualToAnchor:statsPanel.topAnchor constant:10.0],
        [statsStack.leadingAnchor constraintEqualToAnchor:statsPanel.leadingAnchor constant:10.0],
        [statsStack.trailingAnchor constraintEqualToAnchor:statsPanel.trailingAnchor constant:-10.0],
        [statsStack.bottomAnchor constraintEqualToAnchor:statsPanel.bottomAnchor constant:-10.0]
    ]];

    [heroSurfaceView bringSubviewToFront:contentOverlay];
    [avatarShell bringSubviewToFront:avatarBadgeView];

    [avatarShell setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [avatarShell setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [languageButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [logoutButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [accessPill setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [accessPill setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [badgeLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [accessLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.tableView.tableHeaderView = header;
    [self pp_refreshHeroPalette];
    [self pp_sizeTableHeaderToFit];
    [self pp_updateHeroGradientFrame];
    [self updateHeaderWithUser:curUser];
    [self pp_prepareHeaderIntroIfNeeded];
    if (self.view.window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_animateHeaderIntroIfNeeded];
        });
    }
}

- (UIButton *)pp_makeHeroIconButtonWithSystemName:(NSString *)systemName
                              accessibilityLabel:(NSString *)accessibilityLabel
                                          action:(SEL)action
                                        critical:(BOOL)critical {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = critical ? 1 : 0;
    button.backgroundColor = PPAdminDashboardHeroControlColor(self.traitCollection);
    button.tintColor = critical ? PPAdminDashboardHeroCriticalTintColor(self.traitCollection) : PPAdminDashboardHeroSecondaryInkColor();
    button.layer.cornerRadius = 20.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = PPAdminDashboardHeroHairlineColor().CGColor;
    button.clipsToBounds = YES;
    button.adjustsImageWhenHighlighted = NO;
    button.accessibilityLabel = accessibilityLabel;
    button.accessibilityTraits = UIAccessibilityTraitButton;

    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:14.0
                                                                                         weight:UIImageSymbolWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:systemName withConfiguration:symbol] ?: [UIImage systemImageNamed:systemName];
    [button setImage:image forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(pp_heroControlTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:self action:@selector(pp_heroControlTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit | UIControlEventTouchUpOutside];
    return button;
}

- (void)pp_heroControlTouchDown:(UIButton *)sender {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:0.08
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        sender.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:nil];
}

- (void)pp_heroControlTouchUp:(UIButton *)sender {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        sender.transform = CGAffineTransformIdentity;
        return;
    }
    [UIView animateWithDuration:0.18
                          delay:0.0
         usingSpringWithDamping:0.84
          initialSpringVelocity:0.36
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        sender.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)pp_refreshHeroPalette {
    UIColor *accent = PPAdminDashboardHeroSignatureColor(self.traitCollection);
    UIColor *hairline = PPAdminDashboardHeroHairlineColor();
    UIColor *liquidBorder = PPAdminDashboardHeroLiquidBorderColor();
    UIColor *panel = PPAdminDashboardHeroPanelColor(self.traitCollection);
    UIColor *control = PPAdminDashboardHeroControlColor(self.traitCollection);
    BOOL dark = PPAdminDashboardIsDark(self.traitCollection);

    self.heroGlassBG.accentColorOverride = accent;
    self.heroGlassBG.cornerGlowOpacityMultiplier = dark ? 0.42 : 0.30;
    [self.heroGlassBG reapplyPalette];

    self.heroShadowView.layer.shadowOpacity = dark ? 0.28 : 0.10;
    self.heroShadowView.layer.shadowColor = AppShadowColor.CGColor;
    self.heroStatusDotView.backgroundColor = [accent colorWithAlphaComponent:0.94];
    self.heroAccessPill.backgroundColor = control;
    self.heroAccessPill.layer.borderColor = PPAdminDashboardResolvedColor(hairline, self.traitCollection).CGColor;
    self.heroAccessIconView.tintColor = [accent colorWithAlphaComponent:dark ? 0.88 : 0.92];
    self.heroAvatarShellView.backgroundColor = control;
    self.heroAvatarShellView.layer.shadowOpacity = dark ? 0.24 : 0.085;
    self.heroAvatarEditButton.backgroundColor = control;
    self.heroAvatarEditButton.tintColor = PPAdminDashboardHeroInkColor();
    self.heroAvatarEditButton.layer.borderColor = PPAdminDashboardResolvedColor(hairline, self.traitCollection).CGColor;
    self.avatarBadgeView.backgroundColor = [accent colorWithAlphaComponent:0.96];
    self.avatarBadgeView.layer.borderColor = PPAdminDashboardResolvedColor(liquidBorder, self.traitCollection).CGColor;
    self.heroStatsContainer.backgroundColor = panel;
    self.heroStatsContainer.layer.borderColor = PPAdminDashboardResolvedColor(hairline, self.traitCollection).CGColor;
    self.heroStatsAccentView.backgroundColor = [accent colorWithAlphaComponent:dark ? 0.42 : 0.50];

    self.heroBadgeLabel.textColor = PPAdminDashboardHeroSecondaryInkColor();
    self.heroAccessLabel.textColor = PPAdminDashboardHeroSecondaryInkColor();
    self.adminNameLabel.textColor = PPAdminDashboardHeroInkColor();
    self.roleLabel.textColor = PPAdminDashboardHeroSecondaryInkColor();
    self.heroSummaryLabel.textColor = PPAdminDashboardHeroTertiaryInkColor();
    self.statAdsValueLbl.textColor = PPAdminDashboardHeroInkColor();
    self.statAccValueLbl.textColor = PPAdminDashboardHeroInkColor();
    self.statUsersValueLbl.textColor = PPAdminDashboardHeroInkColor();

    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:2];
    if (self.heroLanguageButton) [buttons addObject:self.heroLanguageButton];
    if (self.heroLogoutButton) [buttons addObject:self.heroLogoutButton];
    for (UIButton *button in buttons) {
        button.backgroundColor = control;
        button.tintColor = (button.tag == 1) ? PPAdminDashboardHeroCriticalTintColor(self.traitCollection) : PPAdminDashboardHeroSecondaryInkColor();
        button.layer.borderColor = PPAdminDashboardResolvedColor(hairline, self.traitCollection).CGColor;
    }
}

- (UIView *)pp_makeHeroStatItemWithTitle:(NSString *)title valueLabel:(UILabel *)valueLabel {
    UIView *container = [UIView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.isAccessibilityElement = YES;

    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.font = PPAdminDashboardScaledFont([Styling fontBold:26],
                                                 UIFontTextStyleTitle2);
    valueLabel.adjustsFontForContentSizeCategory = YES;
    valueLabel.textColor = PPAdminDashboardHeroInkColor();
    valueLabel.textAlignment = NSTextAlignmentCenter;
    valueLabel.text = @"—";
    valueLabel.accessibilityElementsHidden = YES;
    [container addSubview:valueLabel];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:10], UIFontTextStyleCaption2);
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textColor = PPAdminDashboardHeroTertiaryInkColor();
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;
    titleLabel.text = title;
    titleLabel.accessibilityElementsHidden = YES;
    [container addSubview:titleLabel];

    container.accessibilityLabel = title;
    container.accessibilityValue = kLang(@"Loading");

    [NSLayoutConstraint activateConstraints:@[
        [valueLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:3.0],
        [valueLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4.0],
        [valueLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4.0],

        [titleLabel.topAnchor constraintEqualToAnchor:valueLabel.bottomAnchor constant:2.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4.0],
        [titleLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-3.0]
    ]];

    return container;
}

- (void)updateHeaderWithUser:(UserModel *)user {
    if (!self.headerRoot || !user) return;

    self.heroBadgeLabel.text = kLang(@"AdminDashboard_Badge");
    self.heroSummaryLabel.text = kLang(@"AdminDashboard_Hero_Subtitle");
    self.heroBadgeLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.heroSummaryLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.roleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.adminNameLabel.textAlignment = [Language alignmentForCurrentLanguage];

    NSString *accessText = [NSString stringWithFormat:kLang(@"AdminDashboard_AccessCount_Format"), (long)MAX(self.dashboardActionCount, 1)];
    NSString *roleTitle = [self pp_currentRoleDisplayNameForUser:user];
    self.roleLabel.text = roleTitle.length > 0 ? roleTitle : kLang(@"pp_role_admin");
    self.heroAccessLabel.text = accessText;
    self.heroAccessPill.accessibilityLabel = accessText;

    self.adminNameLabel.text = [user PPBestDisplayName] ?: kLang(@"AdminDashboard");

    self.avatarIMV.accessibilityLabel = kLang(@"EditMyAccount_Title");
    [self pp_refreshHeroPalette];

    NSURL *url = nil;
    if ([user.UserImageUrl isKindOfClass:NSURL.class]) {
        url = (NSURL *)user.UserImageUrl;
    } else if ([user.UserImageUrl isKindOfClass:NSString.class]) {
        url = [NSURL URLWithString:(NSString *)user.UserImageUrl];
    }

    __weak typeof(self) weakSelf = self;
    [self.avatarIMV setImageFromUrl:url.absoluteString placeholderImage:@"person.crop.circle.fill" completion:nil];

    if (self.hasStartedCountListener) return;
    self.hasStartedCountListener = YES;
    [AppMgr startListeningCountsWithCallback:^(NSInteger ads, NSInteger users, NSInteger accessories, NSError *error) {
        if (error) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.statAdsValueLbl.text = @(ads).stringValue;
            weakSelf.statAccValueLbl.text = @(accessories).stringValue;
            weakSelf.statUsersValueLbl.text = @(users).stringValue;
            weakSelf.statAdsValueLbl.superview.accessibilityValue = weakSelf.statAdsValueLbl.text;
            weakSelf.statAccValueLbl.superview.accessibilityValue = weakSelf.statAccValueLbl.text;
            weakSelf.statUsersValueLbl.superview.accessibilityValue = weakSelf.statUsersValueLbl.text;
        });
    }];
}

- (void)pp_refreshHeroCopy {
    [self updateHeaderWithUser:UsrMgr.currentUser];
}

- (NSString *)pp_currentRoleDisplayNameForUser:(UserModel *)user {
    if (!user) {
        return @"";
    }

    PPStaffDoc *cachedStaff = [PPStaffAuth shared].cachedCurrentStaff;
    if (cachedStaff.uid.length > 0 && [cachedStaff.uid isEqualToString:user.uid]) {
        return [PPStaffAuth localizedRoleName:cachedStaff.role];
    }

    return user.role ? [PPRolePermission localizedRoleName:user.role] : kLang(@"pp_role_admin");
}

- (void)pp_sizeTableHeaderToFit {
    if (!self.headerRoot) {
        return;
    }

    CGFloat targetWidth = CGRectGetWidth(self.tableView.bounds);
    if (targetWidth <= 0.0) {
        targetWidth = CGRectGetWidth(self.view.bounds);
    }
    if (targetWidth <= 0.0) {
        return;
    }

    CGRect frame = self.headerRoot.frame;
    frame.size.width = targetWidth;
    if (frame.size.height <= 0.0) {
        frame.size.height = kPPAdminDashboardHeaderHeight;
    }
    self.headerRoot.frame = frame;
    [self.headerRoot setNeedsLayout];
    [self.headerRoot layoutIfNeeded];

    CGSize fitting = [self.headerRoot systemLayoutSizeFittingSize:CGSizeMake(targetWidth, UILayoutFittingCompressedSize.height)
                             withHorizontalFittingPriority:UILayoutPriorityRequired
                                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat targetHeight = MAX(kPPAdminDashboardHeaderHeight, ceil(fitting.height));
    if (fabs(CGRectGetHeight(self.headerRoot.frame) - targetHeight) > 0.5) {
        CGRect updatedFrame = self.headerRoot.frame;
        updatedFrame.size.height = targetHeight;
        self.headerRoot.frame = updatedFrame;
        self.tableView.tableHeaderView = self.headerRoot;
    }
    [self pp_updateHeroGradientFrame];
}

- (void)pp_updateHeroGradientFrame {
    // The dashboard hero now uses a native thin-material view instead of a gradient layer.
}

- (void)pp_prepareHeaderIntroIfNeeded {
    if (self.hasAnimatedHeaderIntro || self.hasPreparedHeaderIntro || !self.headerRoot) {
        return;
    }

    self.hasPreparedHeaderIntro = YES;
    NSArray<UIView *> *heroViews = @[self.heroBadgeContainer, self.heroIdentityContainer, self.heroStatsContainer];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.heroShadowView.alpha = 1.0;
        self.heroShadowView.transform = CGAffineTransformIdentity;
        for (UIView *view in heroViews) {
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        }
        return;
    }

    self.heroShadowView.alpha = 0.0;
    self.heroShadowView.transform = CGAffineTransformMakeScale(0.985, 0.985);
    for (UIView *view in heroViews) {
        view.alpha = 0.0;
        view.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    }
}

- (void)pp_animateHeaderIntroIfNeeded {
    if (self.hasAnimatedHeaderIntro || !self.hasPreparedHeaderIntro || !self.headerRoot.window) {
        return;
    }

    self.hasAnimatedHeaderIntro = YES;
    NSArray<UIView *> *heroViews = @[self.heroBadgeContainer, self.heroIdentityContainer, self.heroStatsContainer];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.heroShadowView.alpha = 1.0;
        self.heroShadowView.transform = CGAffineTransformIdentity;
        for (UIView *view in heroViews) {
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        }
        return;
    }

    [UIView animateWithDuration:0.42
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.heroShadowView.alpha = 1.0;
        self.heroShadowView.transform = CGAffineTransformIdentity;
    } completion:nil];

    [heroViews enumerateObjectsUsingBlock:^(UIView *view, NSUInteger idx, BOOL *stop) {
        [UIView animateWithDuration:0.46
                              delay:0.05 + (0.055 * idx)
             usingSpringWithDamping:0.92
              initialSpringVelocity:0.20
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (void)pp_reduceMotionStatusDidChange:(NSNotification *)notification {
    (void)notification;
    if (!self.headerRoot) {
        if (UIAccessibilityIsReduceMotionEnabled()) {
            [self.dashboardBackdropView stopMotion];
        } else if (self.view.window) {
            [self.dashboardBackdropView startMotionIfNeeded];
        }
        return;
    }
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self.dashboardBackdropView stopMotion];
        [self.headerRoot.layer removeAllAnimations];
        self.heroShadowView.alpha = 1.0;
        self.heroShadowView.transform = CGAffineTransformIdentity;
        for (UIView *view in @[self.heroBadgeContainer, self.heroIdentityContainer, self.heroStatsContainer]) {
            [view.layer removeAllAnimations];
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        }
        [self pp_applyHeaderMotionForOffset:self.tableView.contentOffset.y];
    } else if (self.view.window) {
        [self.dashboardBackdropView startMotionIfNeeded];
    }
}

#pragma mark - Build Form

- (XLFormDescriptor *)buildLoginForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    self.dashboardSections = [self pp_resolvedDashboardSections];

    for (NSDictionary<NSString *, id> *sectionInfo in self.dashboardSections) {
        XLFormSectionDescriptor *section = [XLFormSectionDescriptor formSectionWithTitle:sectionInfo[kPPDashboardSectionTitleKey]];
        section.footerTitle = sectionInfo[kPPDashboardSectionDetailKey];
        [form addFormSection:section];

        NSArray<NSDictionary<NSString *, id> *> *items = sectionInfo[kPPDashboardSectionItemsKey];
        for (NSDictionary<NSString *, id> *itemInfo in items) {
            [section addFormRow:[self adminRowWithItem:itemInfo]];
        }
    }

    return form;
}

- (NSArray<NSDictionary<NSString *, id> *> *)pp_resolvedDashboardSections {
    NSMutableArray<NSDictionary<NSString *, id> *> *sections = [NSMutableArray array];
    NSInteger actionCount = 0;

    NSMutableArray<NSDictionary<NSString *, id> *> *userItems = [NSMutableArray array];
    if ([self pp_canAccessAnyPermissions:@[
        kPermModeration,
        kPermAdminAll,
        kStaffPermUsersView,
        kStaffPermUsersManage,
        kStaffPermUsersBlock,
        kStaffPermUsersFeaturesView,
        kStaffPermUsersFeaturesManage,
        kStaffPermUsersRestrictionsView,
        kStaffPermUsersRestrictionsManage
    ]]) {
        [userItems addObject:[self pp_itemWithTag:@"usersList"
                                         titleKey:@"SetPermissions"
                                      subtitleKey:@"SetPermissionsSubtitle"
                                         iconName:@"person.2.fill"]];
    }
    if (userItems.count > 0) {
        [sections addObject:[self pp_sectionWithTitleKey:@"UsersSection"
                                          descriptionKey:@"AdminDashboard_Section_Users_Description"
                                                   items:userItems]];
        actionCount += userItems.count;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *mgmtItems = [NSMutableArray array];
    if ([self pp_canAccessAnyPermissions:@[kStaffPermStaffView, kStaffPermStaffManage, kStaffPermUsersView, kPermModeration, kPermAdminAll]]) {
        [mgmtItems addObject:[self pp_itemWithTag:@"staffManagement"
                                         titleKey:@"Staff_Management"
                                      subtitleKey:@"AdminDashboard_Section_Management_Description"
                                         iconName:@"person.3.sequence.fill"]];
    }
    if (mgmtItems.count > 0) {
        [sections addObject:[self pp_sectionWithTitleKey:@"Permissions_Title"
                                          descriptionKey:@"AdminDashboard_Section_Management_Description"
                                                   items:mgmtItems]];
        actionCount += mgmtItems.count;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *stockItems = [NSMutableArray array];
    if ([self pp_canAccessAnyPermissions:@[
        kPermManageStore,
        kPermAdminAll
    ]]) {
        [stockItems addObject:[self pp_itemWithTag:@"accessories"
                                          titleKey:@"Manage Accessories"
                                       subtitleKey:@"ManageAccessoriesSubtitle"
                                          iconName:@"shippingbox"]];
    }
    if ([self pp_canAccessAnyPermissions:@[
        kPermManageFood,
        kPermManageStore,
        kPermAdminAll
    ]]) {
        [stockItems addObject:[self pp_itemWithTag:@"food"
                                          titleKey:@"manageFood"
                                       subtitleKey:@"manageFoodSubtitle"
                                          iconName:@"bag"]];
    }
    if ([self pp_canAccessAnyPermissions:@[
        kPermManageStore,
        kPermAdminAll
    ]]) {
        [stockItems addObject:[self pp_itemWithTag:@"livePets"
                                          titleKey:@"Manage Live Pets"
                                       subtitleKey:@"ManageLivePetsSubtitle"
                                          iconName:@"square.grid.2x2"]];
    }
    if (stockItems.count > 0) {
        [sections addObject:[self pp_sectionWithTitleKey:@"StockSection"
                                          descriptionKey:@"AdminDashboard_Section_Stock_Description"
                                                   items:stockItems]];
        actionCount += stockItems.count;
    }

    if ([self pp_canAccessAnyPermissions:@[
        kPermAdminAll,
        kStaffPermBranchesView,
        kStaffPermBranchesManage
    ]]) {
        NSArray *items = @[[self pp_itemWithTag:@"branches"
                                       titleKey:@"Branches_Title"
                                    subtitleKey:@"Branches_Subtitle"
                                       iconName:@"building.2"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Branches_Title"
                                          descriptionKey:@"Branches_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }

    if ([self pp_canAccessAnyPermissions:@[
        kPermAdminAll,
        kStaffPermAgentsView,
        kStaffPermAgentsManage
    ]]) {
        NSArray *items = @[[self pp_itemWithTag:@"agents"
                                       titleKey:@"Agents_Title"
                                    subtitleKey:@"Agents_Subtitle"
                                       iconName:@"person.text.rectangle"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Agents_Title"
                                          descriptionKey:@"Agents_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }

    if ([self pp_canAccessAnyPermissions:@[
        kPermManageServices,
        kPermAdminAll,
        kStaffPermServicesView,
        kStaffPermServicesManage,
        kStaffPermProvidersManage
    ]]) {
        NSArray *items = @[[self pp_itemWithTag:@"services"
                                       titleKey:@"Service_Manage_Title"
                                    subtitleKey:@"Service_Manage_Subtitle"
                                       iconName:@"cross.case"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Service_Section_Title"
                                          descriptionKey:@"AdminDashboard_Section_Services_Description"
                                                   items:items]];
        actionCount += items.count;
    }

    if ([self pp_canAccessAnyPermissions:@[
        kPermManageServices,
        kPermAdminAll,
        kStaffPermVeterinariansView,
        kStaffPermVeterinariansManage,
        kStaffPermProvidersManage
    ]]) {
        NSArray *items = @[[self pp_itemWithTag:@"vets"
                                       titleKey:@"Vet_Section_Title"
                                    subtitleKey:@"Vet_Manage_Subtitle"
                                       iconName:@"stethoscope"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Vet_Section_Title"
                                          descriptionKey:@"AdminDashboard_Section_Vets_Description"
                                                   items:items]];
        actionCount += items.count;
    }

    if ([self pp_canAccessAnyPermissions:@[
        kPermAdminAll,
        kStaffPermCategoriesView,
        kStaffPermCategoriesManage
    ]]) {
        NSArray *items = @[[self pp_itemWithTag:@"categories"
                                       titleKey:@"Categories_Title"
                                    subtitleKey:@"Categories_Subtitle"
                                       iconName:@"square.grid.2x2"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Categories_Title"
                                          descriptionKey:@"Categories_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }

    if ([self pp_canAccessAnyPermissions:@[
        kPermAdminAll,
        kStaffPermModerationView,
        kStaffPermModerationManage,
        kStaffPermListingsModerate
    ]]) {
        NSArray *items = @[[self pp_itemWithTag:@"moderation"
                                        titleKey:@"Moderation_Title"
                                     subtitleKey:@"Moderation_Subtitle"
                                        iconName:@"shield.lefthalf.filled"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Staff_Module_Moderation"
                                          descriptionKey:@"Moderation_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }

    if ([self pp_canAccessAnyPermissions:@[
        kPermPostAds,
        kPermAdminAll,
        kStaffPermBannersManage,
        kStaffPermListingsView,
        kStaffPermListingsManage,
        kStaffPermListingsModerate
    ]]) {
        NSMutableArray *listingItems = [NSMutableArray array];
        if ([self pp_canAccessAnyPermissions:@[
            kStaffPermListingsView,
            kStaffPermListingsManage,
            kStaffPermListingsModerate
        ]]) {
            [listingItems addObject:[self pp_itemWithTag:@"listings"
                                               titleKey:@"Staff_Module_Listings"
                                            subtitleKey:@"ListingsAdmin_Dashboard_Subtitle"
                                               iconName:@"list.bullet.clipboard"]];
        }
        if ([self pp_canAccessAnyPermissions:@[
            kStaffPermBannersManage
        ]]) {
            [listingItems addObject:[self pp_itemWithTag:@"banners"
                                               titleKey:@"Staff_Module_Banners"
                                            subtitleKey:@"Banners_Manage_Subtitle"
                                               iconName:@"square.3.layers.3d.middle.filled"]];
        }
        if (listingItems.count > 0) {
            [sections addObject:[self pp_sectionWithTitleKey:@"Staff_Module_Listings"
                                              descriptionKey:@"AdminDashboard_Section_Banners_Description"
                                                       items:listingItems.copy]];
            actionCount += listingItems.count;
        }
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *paymentItems = [NSMutableArray array];
    if ([self pp_canAccessAnyPermissions:@[
        kPermManageStore,
        kPermAdminAll,
        kStaffPermPaymentsView,
        kStaffPermPaymentsManage,
        kStaffPermPaymentsRefund,
        kStaffPermAccountingManage
    ]]) {
        [paymentItems addObject:[self pp_itemWithTag:@"payments"
                                            titleKey:@"PaymentMgmt_Dashboard_Title"
                                         subtitleKey:@"PaymentMgmt_Dashboard_Subtitle"
                                            iconName:@"creditcard"]];
    }
    if ([self pp_canAccessAnyPermissions:@[
        kPermManageStore,
        kPermAdminAll,
        kStaffPermPaymentsManage,
        kStaffPermAccountingManage,
        kStaffPermSettingsManage
    ]]) {
        [paymentItems addObject:[self pp_itemWithTag:@"paymentBasics"
                                            titleKey:@"PaymentMgmt_Dashboard_Settings_Title"
                                         subtitleKey:@"PaymentMgmt_Dashboard_Settings_Subtitle"
                                            iconName:@"slider.horizontal.3"]];
    }
    if (paymentItems.count > 0) {
        [sections addObject:[self pp_sectionWithTitleKey:@"PaymentMgmt_Title_List"
                                          descriptionKey:@"AdminDashboard_Section_Payments_Description"
                                                   items:paymentItems]];
        actionCount += paymentItems.count;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *notificationItems = [NSMutableArray array];
    if ([self pp_canAccessAnyPermissions:@[
        kPermModeration,
        kPermAdminAll,
        kStaffPermNotificationsView,
        kStaffPermSupportView,
        kStaffPermSupportManage
    ]]) {
        [notificationItems addObject:[self pp_itemWithTag:@"notificationsInbox"
                                                 titleKey:@"NotificationsTitle"
                                              subtitleKey:@"NotificationsDashboard_Subtitle"
                                                 iconName:@"bell.badge"]];
    }
    if ([self pp_canAccessAnyPermissions:@[
        kPermModeration,
        kPermAdminAll,
        kStaffPermNotificationsSend,
        kStaffPermSupportManage
    ]]) {
        [notificationItems addObject:[self pp_itemWithTag:@"notificationsCompose"
                                                 titleKey:@"SendPushNotification"
                                              subtitleKey:@"SendPushNotificationSubtitle"
                                                 iconName:@"paperplane"]];
    }
    if ([self pp_canAccessAnyPermissions:@[
        kPermModeration,
        kPermAdminAll,
        kStaffPermNotificationsView,
        kStaffPermNotificationsSend,
        kStaffPermSupportManage
    ]]) {
        [notificationItems addObject:[self pp_itemWithTag:@"notificationSettings"
                                                 titleKey:@"Notification Settings"
                                              subtitleKey:@"NotificationSettings_Subtitle"
                                                 iconName:@"bell.circle"]];
    }
    if (notificationItems.count > 0) {
        [sections addObject:[self pp_sectionWithTitleKey:@"NotificationsSection"
                                          descriptionKey:@"AdminDashboard_Section_Notifications_Description"
                                                   items:notificationItems]];
        actionCount += notificationItems.count;
    }

    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermSettingsView, kStaffPermSettingsManage]]) {
        NSArray *items = @[[self pp_itemWithTag:@"homeControl"
                                       titleKey:@"HomeControl_Title"
                                    subtitleKey:@"HomeControl_Subtitle"
                                       iconName:@"switch.radio"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"HomeControl_Title"
                                          descriptionKey:@"HomeControl_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }
    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermPaymentsView, kStaffPermPaymentsManage]]) {
        NSArray *items = @[[self pp_itemWithTag:@"fulfillment"
                                       titleKey:@"Fulfillment_Title"
                                    subtitleKey:@"Fulfillment_Subtitle"
                                       iconName:@"shippingbox"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Fulfillment_Title"
                                          descriptionKey:@"Fulfillment_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }
    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermPaymentsView, kStaffPermPaymentsManage]]) {
        NSArray *items = @[[self pp_itemWithTag:@"delivery"
                                       titleKey:@"Delivery_Title"
                                    subtitleKey:@"Delivery_Subtitle"
                                       iconName:@"truck"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Delivery_Title"
                                          descriptionKey:@"Delivery_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }
    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermAccountingView, kStaffPermAccountingManage]]) {
        NSArray *items = @[[self pp_itemWithTag:@"accounting"
                                       titleKey:@"Accounting_Title"
                                    subtitleKey:@"Accounting_Subtitle"
                                       iconName:@"dollarsign.circle"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Accounting_Title"
                                          descriptionKey:@"Accounting_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *providerItems = [NSMutableArray array];
    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermProvidersView, kStaffPermProvidersManage]]) {
        [providerItems addObject:[self pp_itemWithTag:@"providerApplications"
                                            titleKey:@"Providers_Applications_Title"
                                         subtitleKey:@"Providers_Applications_Subtitle"
                                            iconName:@"person.badge.plus"]];
        [providerItems addObject:[self pp_itemWithTag:@"providerPlans"
                                            titleKey:@"Providers_Plans_Title"
                                         subtitleKey:@"Providers_Plans_Subtitle"
                                            iconName:@"list.clipboard"]];
        [providerItems addObject:[self pp_itemWithTag:@"providerFeatures"
                                            titleKey:@"Providers_Features_Title"
                                         subtitleKey:@"Providers_Features_Subtitle"
                                            iconName:@"gearshape.2"]];
        [providerItems addObject:[self pp_itemWithTag:@"providerAccounting"
                                            titleKey:@"Providers_Accounting_Title"
                                         subtitleKey:@"Providers_Accounting_Subtitle"
                                            iconName:@"chart.pie"]];
    }
    if (providerItems.count > 0) {
        [sections addObject:[self pp_sectionWithTitleKey:@"Providers_Section_Title"
                                          descriptionKey:@"AdminDashboard_Section_Providers_Description"
                                                   items:providerItems]];
        actionCount += providerItems.count;
    }
    NSMutableArray<NSDictionary<NSString *, id> *> *posItems = [NSMutableArray array];
    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermPosView, kStaffPermPosSell]]) {
        [posItems addObject:[self pp_itemWithTag:@"pos"
                                        titleKey:@"POS_Title"
                                     subtitleKey:@"POS_Subtitle"
                                        iconName:@"cart"]];
        [posItems addObject:[self pp_itemWithTag:@"posHistory"
                                        titleKey:@"POS_History_Title"
                                     subtitleKey:@"POS_History_Subtitle"
                                        iconName:@"clock.arrow.circlepath"]];
    } else if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermPosHistory]]) {
        [posItems addObject:[self pp_itemWithTag:@"posHistory"
                                        titleKey:@"POS_History_Title"
                                     subtitleKey:@"POS_History_Subtitle"
                                        iconName:@"clock.arrow.circlepath"]];
    }
    if (posItems.count > 0) {
        [sections addObject:[self pp_sectionWithTitleKey:@"POS_Section_Title"
                                          descriptionKey:@"AdminDashboard_Section_POS_Description"
                                                   items:posItems]];
        actionCount += posItems.count;
    }

    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermAuditView]]) {
        NSArray *items = @[[self pp_itemWithTag:@"audit"
                                        titleKey:@"Audit_Title"
                                     subtitleKey:@"Staff_Module_Audit"
                                        iconName:@"doc.text.magnifyingglass"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Staff_Module_Audit"
                                          descriptionKey:@"AdminDashboard_Section_Audit_Description"
                                                   items:items]];
        actionCount += items.count;
    }

    NSArray *settingsItems = @[[self pp_itemWithTag:@"editMyAccount"
                                           titleKey:@"EditMyAccount_Title"
                                        subtitleKey:@"EditMyAccount_Subtitle"
                                           iconName:@"person.circle"]];
    [sections addObject:[self pp_sectionWithTitleKey:@"Settings"
                                      descriptionKey:@"AdminDashboard_Section_Settings_Description"
                                               items:settingsItems]];
    actionCount += settingsItems.count;

    [sections sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *left,
                                                      NSDictionary<NSString *, id> *right) {
        NSInteger leftPriority = PPAdminDashboardSectionPriority(left);
        NSInteger rightPriority = PPAdminDashboardSectionPriority(right);
        if (leftPriority < rightPriority) return NSOrderedAscending;
        if (leftPriority > rightPriority) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    self.dashboardActionCount = actionCount;
    return sections.copy;
}

- (NSDictionary<NSString *, id> *)pp_sectionWithTitleKey:(NSString *)titleKey
                                          descriptionKey:(NSString *)descriptionKey
                                                   items:(NSArray<NSDictionary<NSString *, id> *> *)items {
    return @{
        kPPDashboardSectionTitleKey: kLang(titleKey),
        kPPDashboardSectionDetailKey: kLang(descriptionKey),
        kPPDashboardSectionItemsKey: items ?: @[]
    };
}

- (NSDictionary<NSString *, id> *)pp_itemWithTag:(NSString *)tag
                                        titleKey:(NSString *)titleKey
                                     subtitleKey:(NSString *)subtitleKey
                                        iconName:(NSString *)iconName {
    return @{
        kPPDashboardItemTagKey: tag ?: @"",
        kPPDashboardItemTitleKey: kLang(titleKey),
        kPPDashboardItemSubtitleKey: kLang(subtitleKey),
        kPPDashboardItemIconKey: iconName ?: @"square.grid.2x2",
        kPPDashboardItemTintKey: PPAdminDashboardTintForTag(tag ?: @"")
    };
}

- (XLFormRowDescriptor *)adminRowWithItem:(NSDictionary<NSString *, id> *)itemInfo {
    NSString *tag = itemInfo[kPPDashboardItemTagKey];
    UIImage *icon = [UIImage systemImageNamed:itemInfo[kPPDashboardItemIconKey]];
    XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:@"XLAdminCell"];
    row.value = @{
        @"icon": icon ?: [UIImage new],
        @"title": itemInfo[kPPDashboardItemTitleKey] ?: @"",
        @"subtitle": itemInfo[kPPDashboardItemSubtitleKey] ?: @"",
        @"tint": itemInfo[kPPDashboardItemTintKey] ?: AppPrimaryClr
    };

    __weak typeof(self) weakSelf = self;
    row.action.formBlock = ^(XLFormRowDescriptor *rowDescriptor) {
        [weakSelf pp_handleDashboardActionForTag:tag];
    };
    return row;
}

#pragma mark - Actions

- (void)pp_handleDashboardActionForTag:(NSString *)tag {
    if (tag.length == 0) {
        return;
    }

    [PPFunc pp_playTapEffect];

    if ([tag isEqualToString:@"editMyAccount"]) {
        [self pp_openCurrentAccountEditor];
        return;
    }

    UIViewController *controller = [self pp_viewControllerForDashboardTag:tag];
    if (controller) {
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (UIViewController *)pp_viewControllerForDashboardTag:(NSString *)tag {
    if ([tag isEqualToString:@"usersList"]) {
        return [[UsersListVC alloc] initWithViewFor:ViewForEditAccount];
    }
    if ([tag isEqualToString:@"staffManagement"]) {
        return [PPStaffManagementViewController new];
    }
    if ([tag isEqualToString:@"blockUser"]) {
        return [BlockUserViewController new];
    }
    if ([tag isEqualToString:@"usersRolePermissions"]) {
        return [[UsersListVC alloc] initWithViewFor:ViewForEditRoleAndPermissions];
    }
    if ([tag isEqualToString:@"accessories"]) {
        return [[AccessoriesListViewController alloc] initWithKind:AccessTypeAccessory];
    }
    if ([tag isEqualToString:@"food"]) {
        return [[AccessoriesListViewController alloc] initWithKind:AccessTypeFood];
    }
    if ([tag isEqualToString:@"livePets"]) {
        return [[AccessoriesListViewController alloc] initWithKind:AccessTypeLivePets];
    }
    if ([tag isEqualToString:@"services"]) {
        return [PPServicesListViewController new];
    }
    if ([tag isEqualToString:@"vets"]) {
        return [PPVetsListViewController new];
    }
    if ([tag isEqualToString:@"branches"]) {
        return [PPBranchesViewController new];
    }
    if ([tag isEqualToString:@"agents"]) {
        return [PPAgentsViewController new];
    }
    if ([tag isEqualToString:@"categories"]) {
        return [PPCategoriesViewController new];
    }
    if ([tag isEqualToString:@"moderation"]) {
        return [PPContentModerationViewController new];
    }
    if ([tag isEqualToString:@"listings"]) {
        return [PPListingsAdminViewController new];
    }
    if ([tag isEqualToString:@"banners"]) {
        return [PPBannersListVC new];
    }
    if ([tag isEqualToString:@"payments"]) {
        return [PPPaymentManagementViewController new];
    }
    if ([tag isEqualToString:@"paymentBasics"]) {
        return [PPPaymentBasicsSettingsViewController new];
    }
    if ([tag isEqualToString:@"notificationsInbox"]) {
        return [NotificationsListViewController new];
    }
    if ([tag isEqualToString:@"notificationsCompose"]) {
        return [NotificationComposerViewController new];
    }
    if ([tag isEqualToString:@"notificationSettings"]) {
        return [NotificationSettingsViewController new];
    }
    if ([tag isEqualToString:@"adminWebApp"]) {
        return [PPAdminWebAppViewController new];
    }
    if ([tag isEqualToString:@"homeControl"]) {
        return [PPHomeControlPanelViewController new];
    }
    if ([tag isEqualToString:@"fulfillment"]) {
        return [PPFulfillmentOrdersViewController new];
    }
    if ([tag isEqualToString:@"delivery"]) {
        return [PPDeliveryManagementViewController new];
    }
    if ([tag isEqualToString:@"accounting"]) {
        return [PPAccountingViewController new];
    }
    if ([tag isEqualToString:@"providerApplications"]) {
        return [PPProviderApplicationsViewController new];
    }
    if ([tag isEqualToString:@"providerPlans"]) {
        return [PPProviderPlansViewController new];
    }
    if ([tag isEqualToString:@"providerFeatures"]) {
        return [PPProviderFeatureAccessViewController new];
    }
    if ([tag isEqualToString:@"providerAccounting"]) {
        return [PPProviderAccountingViewController new];
    }
    if ([tag isEqualToString:@"pos"]) {
        return [PPPOSFastSellViewController new];
    }
    if ([tag isEqualToString:@"posHistory"]) {
        return [PPPOSHistoryViewController new];
    }
    if ([tag isEqualToString:@"audit"]) {
        return [PPAuditLogViewController new];
    }
    return nil;
}

- (void)pp_openCurrentAccountEditor {
    if (!UsrMgr.currentUser) {
        return;
    }

    UIViewController *editor = [UserManagementController accountEditorForUser:UsrMgr.currentUser];
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)didTapAddProfilePhoto {
    [self pp_handleDashboardActionForTag:@"editMyAccount"];
}

- (void)showLogin {
    Class loginClass = NSClassFromString(@"PPProLoginHostingController");
    UIViewController *loginController = loginClass ? [[loginClass alloc] init] : [AdminLoginViewController new];
    [self.navigationController pushViewController:loginController animated:YES];
}

- (void)pp_buildDashboardLoadingStateIfNeeded {
    if (self.dashboardLoadingView) return;

    UIView *loadingView = [UIView new];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.backgroundColor = [AppBackgroundClrShiner colorWithAlphaComponent:UIAccessibilityIsReduceTransparencyEnabled() ? 1.0 : 0.92];
    loadingView.layer.cornerRadius = 24.0;
    loadingView.layer.cornerCurve = kCACornerCurveContinuous;
    loadingView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    loadingView.layer.borderColor = [PPHairlineColor() colorWithAlphaComponent:0.24].CGColor;
    loadingView.layer.shadowColor = AppShadowColor.CGColor;
    loadingView.layer.shadowOpacity = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.24 : 0.08;
    loadingView.layer.shadowRadius = 20.0;
    loadingView.layer.shadowOffset = CGSizeMake(0.0, 12.0);
    loadingView.hidden = YES;
    loadingView.isAccessibilityElement = YES;
    loadingView.accessibilityLabel = kLang(@"Loading");
    [self.view addSubview:loadingView];
    self.dashboardLoadingView = loadingView;

    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.color = AppPrimaryClr;
    [loadingView addSubview:indicator];
    self.dashboardLoadingIndicator = indicator;

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = PPAdminDashboardScaledFont([Styling fontMedium:13], UIFontTextStyleSubheadline);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = PrimaryTextClr;
    label.textAlignment = NSTextAlignmentCenter;
    label.text = kLang(@"Loading");
    [loadingView addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [loadingView.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [loadingView.widthAnchor constraintEqualToConstant:172.0],
        [loadingView.heightAnchor constraintEqualToConstant:104.0],

        [indicator.centerXAnchor constraintEqualToAnchor:loadingView.centerXAnchor],
        [indicator.topAnchor constraintEqualToAnchor:loadingView.topAnchor constant:22.0],
        [label.topAnchor constraintEqualToAnchor:indicator.bottomAnchor constant:10.0],
        [label.leadingAnchor constraintEqualToAnchor:loadingView.leadingAnchor constant:18.0],
        [label.trailingAnchor constraintEqualToAnchor:loadingView.trailingAnchor constant:-18.0],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:loadingView.bottomAnchor constant:-16.0]
    ]];
}

- (void)pp_setDashboardLoadingVisible:(BOOL)visible {
    [self pp_buildDashboardLoadingStateIfNeeded];
    if (self.dashboardLoadingView.hidden == !visible) return;

    self.dashboardLoadingView.hidden = !visible;
    if (visible) {
        [self.dashboardLoadingIndicator startAnimating];
        [self.view bringSubviewToFront:self.dashboardLoadingView];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, kLang(@"Loading"));
    } else {
        [self.dashboardLoadingIndicator stopAnimating];
    }
}

- (void)didTapLanguage {
    [PPFunc pp_playTapEffect];
    NSInteger newLangVal = ([Language languageVal] == 0) ? 1 : 0;
    [AlertHelper showConfirmationIn:self
                              title:kLang(@"Confirm_LanguageChange_Title")
                           subtitle:kLang(@"Confirm_LanguageChange_Msg")
                        placeholder:nil
                      confirmButton:kLang(@"Confirm")
                       cancelButton:kLang(@"Cancel")
                               icon:[UIImage systemImageNamed:@"globe"]
                       confirmBlock:^{
        [Language userSelectedLanguage:LanguageCode[newLangVal]];
    } cancelBlock:nil];
}

- (void)didTapAuthButton {
    [PPFunc pp_playTapEffect];
    [AlertHelper showConfirmationIn:self
                              title:kLang(@"Logout_Confirm_Title")
                           subtitle:kLang(@"Logout_Confirm_Message")
                        placeholder:nil
                      confirmButton:kLang(@"Confirm")
                       cancelButton:kLang(@"Cancel")
                               icon:[UIImage systemImageNamed:@"power.circle.fill"]
                       confirmBlock:^{
        [[UserManager shared] signOut];
        [[NSNotificationCenter defaultCenter] postNotificationName:UserManagerAuthStateDidChangeNotification object:nil];
    } cancelBlock:nil];
}

#pragma mark - Helpers

- (void)pp_rebuildDashboardFormPreservingOffset:(BOOL)preserveOffset {
    CGPoint previousOffset = self.tableView.contentOffset;
    self.form = [self buildLoginForm];
    [self.tableView reloadData];
    [self pp_refreshHeroCopy];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (preserveOffset) {
            CGFloat minOffsetY = -self.tableView.adjustedContentInset.top;
            CGFloat maxOffsetY = MAX(minOffsetY, self.tableView.contentSize.height - CGRectGetHeight(self.tableView.bounds) + self.tableView.adjustedContentInset.bottom);
            CGFloat clampedY = MIN(MAX(previousOffset.y, minOffsetY), maxOffsetY);
            [self.tableView setContentOffset:CGPointMake(previousOffset.x, clampedY) animated:NO];
        }

        [self pp_applyHeaderMotionForOffset:self.tableView.contentOffset.y];
        [self pp_animateVisibleCellsModern];
    });
}

- (void)pp_animateVisibleCellsModern {
    NSArray<UITableViewCell *> *cells = self.tableView.visibleCells;
    [cells enumerateObjectsUsingBlock:^(UITableViewCell *cell, NSUInteger idx, BOOL *stop) {
        NSString *tag = nil;
        if ([cell isKindOfClass:XLFormBaseCell.class]) {
            tag = ((XLFormBaseCell *)cell).rowDescriptor.tag;
        }
        [self pp_animateDashboardCellIfNeeded:cell tag:tag delay:(0.03 * idx)];
    }];
}

- (void)pp_animateDashboardCellIfNeeded:(UITableViewCell *)cell tag:(NSString *)tag delay:(NSTimeInterval)delay {
    if (!cell || tag.length == 0 || [self.animatedDashboardTags containsObject:tag]) {
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
        return;
    }
    [self.animatedDashboardTags addObject:tag];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
        return;
    }

    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
    [UIView animateWithDuration:0.38
                          delay:delay
         usingSpringWithDamping:0.94
          initialSpringVelocity:0.18
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (BOOL)pp_canAccessPermission:(NSString *)permKey {
    return [UsrMgr.currentUser hasPermissionNamed:permKey];
}

- (BOOL)pp_canAccessAnyPermissions:(NSArray<NSString *> *)permissionKeys {
    for (NSString *permissionKey in permissionKeys ?: @[]) {
        if ([self pp_canAccessPermission:permissionKey]) {
            return YES;
        }
    }
    return NO;
}

- (void)pp_syncCachedAdminNotificationTokenIfNeeded {
    // Intentionally left lightweight here. The existing login/bootstrap flow owns token freshness.
}

#pragma mark - UITableView

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ? 94.0 : 68.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return (section == self.form.formSections.count - 1) ? 24.0 : 12.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContentSizeCategory category = self.traitCollection.preferredContentSizeCategory;
    if (UIContentSizeCategoryIsAccessibilityCategory(category)) return 120.0;
    if ([category isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge]) return 100.0;
    if ([category isEqualToString:UIContentSizeCategoryExtraExtraLarge]) return 94.0;
    return kPPAdminDashboardRowHeight;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section < 0 || section >= self.form.formSections.count) {
        return nil;
    }

    XLFormSectionDescriptor *sectionDescriptor = self.form.formSections[section];

    UIView *container = [UIView new];
    container.backgroundColor = AppClearClr;
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIColor *sectionTint = AppPrimaryClr;
    XLFormRowDescriptor *firstRow = sectionDescriptor.formRows.firstObject;
    NSDictionary *firstValue = [firstRow.value isKindOfClass:NSDictionary.class] ? (NSDictionary *)firstRow.value : nil;
    if ([firstValue[@"tint"] isKindOfClass:UIColor.class]) {
        sectionTint = firstValue[@"tint"];
    }

    UIView *accentView = [UIView new];
    accentView.translatesAutoresizingMaskIntoConstraints = NO;
    accentView.backgroundColor = [sectionTint colorWithAlphaComponent:0.88];
    accentView.layer.cornerRadius = 1.5;
    accentView.layer.cornerCurve = kCACornerCurveContinuous;
    [container addSubview:accentView];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPAdminDashboardScaledFont([Styling fontBold:20], UIFontTextStyleHeadline);
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textColor = PrimaryTextClr;
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    titleLabel.text = sectionDescriptor.title;
    titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [container addSubview:titleLabel];

    UILabel *detailLabel = [UILabel new];
    detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    detailLabel.font = PPAdminDashboardScaledFont([Styling fontRegular:12], UIFontTextStyleFootnote);
    detailLabel.adjustsFontForContentSizeCategory = YES;
    detailLabel.textColor = [SeconderyTextClr colorWithAlphaComponent:0.76];
    detailLabel.textAlignment = [Language alignmentForCurrentLanguage];
    detailLabel.numberOfLines = 2;
    detailLabel.text = sectionDescriptor.footerTitle;
    [container addSubview:detailLabel];

    [NSLayoutConstraint activateConstraints:@[
        [accentView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:kPPAdminDashboardSectionInset],
        [accentView.topAnchor constraintEqualToAnchor:container.topAnchor constant:14.0],
        [accentView.widthAnchor constraintEqualToConstant:3.0],
        [accentView.heightAnchor constraintEqualToConstant:20.0],

        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:10.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:accentView.trailingAnchor constant:10.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-kPPAdminDashboardSectionInset],

        [detailLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],
        [detailLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [detailLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-7.0]
    ]];

    return container;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    UIView *footer = [UIView new];
    footer.backgroundColor = AppClearClr;
    return footer;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = AppClearClr;
    cell.contentView.backgroundColor = AppClearClr;
    NSString *tag = nil;
    if ([cell isKindOfClass:XLFormBaseCell.class]) {
        tag = ((XLFormBaseCell *)cell).rowDescriptor.tag;
    }
    [self pp_animateDashboardCellIfNeeded:cell tag:tag delay:0.0];
}

#pragma mark - Motion

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self pp_applyHeaderMotionForOffset:scrollView.contentOffset.y];
}

- (void)pp_applyHeaderMotionForOffset:(CGFloat)offsetY {
    return; // Completely stop hero content from scrolling/moving with tableview
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    BOOL colorChanged = [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection];
    BOOL contentSizeChanged = previousTraitCollection &&
    ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory];
    if (!colorChanged && !contentSizeChanged) {
        return;
    }

    if (colorChanged) {
        self.view.backgroundColor = PPAdminDashboardCanvasColor(self.traitCollection);
        [self.dashboardBackdropView refreshPalette];
        [self pp_refreshHeroPalette];
        self.dashboardLoadingView.backgroundColor = [AppBackgroundClrShiner colorWithAlphaComponent:UIAccessibilityIsReduceTransparencyEnabled() ? 1.0 : 0.92];
        self.dashboardLoadingView.layer.borderColor = [PPHairlineColor() colorWithAlphaComponent:0.24].CGColor;
        self.dashboardLoadingView.layer.shadowOpacity = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.24 : 0.08;
    }
    if (contentSizeChanged) {
        [self pp_sizeTableHeaderToFit];
    }
    [self.tableView reloadData];
}

@end
