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
// Legacy PPVetsListViewController replaced by SwiftUI PPVetsListHostingController
#import "PPServicesListViewController.h"
#import "PPAdminWebAppViewController.h"
#import "UsersListVC.h"
#import "UserManagementController.h"
#import "ThirdParty/PPCells/PPSettingsViewController.h"
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
#import "PurePetsAdmin-Swift.h"
#import "Accounting/PPAccountingViewController.h"
#import "Providers/PPProviderApplicationsViewController.h"
#import "Providers/PPProviderPlansViewController.h"
#import "Providers/PPProviderFeatureAccessViewController.h"
#import "Providers/PPProviderAccountingViewController.h"
#import "CategoriesSection/PPContentModerationViewController.h"
#import "CategoriesSection/PPAuditLogViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "PPBranchesViewController.h"
// PP_ADMIN_COMMAND_SPINE_INTEGRATION_INSTALLED
// PP_ADMIN_COMMAND_SPINE_IMPORTS_BEGIN
#import "Fulfillment/PPFulfillmentService.h"
#import "Delivery/PPDeliveryService.h"
#import "Payments/PPPaymentManagementService.h"
#import "Payments/PPPaymentManagementModels.h"
#import "Payments/PPPaymentManagementViewController.h"
#import "Payments/PPPaymentBasicsSettingsViewController.h"
#import "AccessorySection/AccessoryManager.h"
#import "BasicClasses/PetAccessory.h"
// PP_ADMIN_COMMAND_SPINE_IMPORTS_END

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

static NSArray<NSString *> *PPAdminDashboardCanonicalPermissionsForLegacyPermission(NSString *permission) {
    if (permission.length == 0 || [permission containsString:@"."] ||
        [permission isEqualToString:kPermAdminAll]) {
        return permission.length > 0 && [permission containsString:@"."] ? @[permission] : @[];
    }
    if ([permission isEqualToString:kPermPostAds]) {
        return @[kStaffPermBannersManage, kStaffPermListingsManage, kStaffPermListingsModerate];
    }
    if ([permission isEqualToString:kPermManageStore]) {
        return @[
            kStaffPermStockManage,
            kStaffPermStockCreate,
            kStaffPermStockDelete,
            kStaffPermPaymentsManage,
            kStaffPermPaymentsRefund,
            kStaffPermAccountingManage,
            kStaffPermCategoriesManage
        ];
    }
    if ([permission isEqualToString:kPermModeration]) {
        return @[kStaffPermModerationManage, kStaffPermUsersBlock, kStaffPermNotificationsSend];
    }
    if ([permission isEqualToString:kPermManageFood]) {
        return @[kStaffPermStockManage, kStaffPermCategoriesManage];
    }
    if ([permission isEqualToString:kPermManageServices]) {
        return @[kStaffPermServicesManage, kStaffPermProvidersManage, kStaffPermVeterinariansManage];
    }
    return @[];
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
    return AppPrimaryClr;
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
    return AppPrimaryClrDarker;
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
        return AppSecondaryClr;
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
        return AppPrimaryClrDarker;
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
        return AppPrimaryClrShiner;
    }
    if ([tag isEqualToString:@"fulfillment"]) {
        return AppPrimaryClr;
    }
    if ([tag isEqualToString:@"delivery"]) {
        return AppSecondaryClr;
    }
    if ([tag isEqualToString:@"accounting"]) {
        return AppSecondaryClr;
    }
    if ([tag isEqualToString:@"providers"]) {
        return AppPrimaryClrDarker;
    }
    if ([tag isEqualToString:@"pos"] || [tag isEqualToString:@"posHistory"]) {
        return AppPrimaryClrDarker;
    }
    if ([tag isEqualToString:@"moderation"]) {
        return AppPrimaryClrShiner;
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

UIViewController *PPAdminCreateCommandSpineDashboardController(void) {
    AdminDashboardViewController *controller = [AdminDashboardViewController new];
    controller.pp_isCommandSpine = YES;
    return controller;
}

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
    UIColor *signature = AppPrimaryClr;
    UIColor *warm = AppPrimaryClrShiner;

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

// PP_ADMIN_COMMAND_SPINE_TYPES_BEGIN

static NSString *PPAdminCommandNormalizedString(id value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    return [[(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
}

static BOOL PPAdminCommandStatusIsTerminal(NSString *status) {
    NSString *normalized = PPAdminCommandNormalizedString(status);
    if (normalized.length == 0) return NO;
    static NSSet<NSString *> *terminal;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        terminal = [NSSet setWithArray:@[
            @"completed", @"complete", @"delivered",
            @"cancelled", @"canceled", @"rejected",
            @"failed", @"returned", @"closed"
        ]];
    });
    return [terminal containsObject:normalized];
}

static BOOL PPAdminCommandStatusLooksNew(NSString *status) {
    NSString *normalized = PPAdminCommandNormalizedString(status);
    if (normalized.length == 0) return NO;
    return [normalized containsString:@"new"] ||
           [normalized containsString:@"pending"] ||
           [normalized containsString:@"request"] ||
           [normalized containsString:@"waiting"];
}

static NSString *PPAdminCommandLocalizedCount(NSString *singularKey,
                                               NSString *pluralKey,
                                               NSInteger count) {
    if (count == 1) return kLang(singularKey);
    return [NSString stringWithFormat:kLang(pluralKey), (long)count];
}

// Presentation-only feed readiness states, keyed by stable area tags.
static NSString * const kPPAdminCommandFeedPending = @"pending";
static NSString * const kPPAdminCommandFeedLoaded = @"loaded";
static NSString * const kPPAdminCommandFeedFailed = @"failed";
static NSArray<NSString *> *PPAdminCommandTrackedFeedAreas(void) {
    static NSArray<NSString *> *areas;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        areas = @[@"fulfillment", @"delivery", @"payments", @"accessories"];
    });
    return areas;
}

@interface PPAdminCommandSignal : NSObject
@property (nonatomic, copy) NSString *tag;
@property (nonatomic, copy) NSString *moduleTitle;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *ctaTitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, assign) NSInteger urgency;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign, getter=isLive) BOOL live;
+ (instancetype)signalWithTag:(NSString *)tag
                  moduleTitle:(NSString *)moduleTitle
                        title:(NSString *)title
                       detail:(NSString *)detail
                     ctaTitle:(NSString *)ctaTitle
                     iconName:(NSString *)iconName
                      urgency:(NSInteger)urgency
                        count:(NSInteger)count
                         live:(BOOL)live;
@end

@implementation PPAdminCommandSignal
+ (instancetype)signalWithTag:(NSString *)tag
                  moduleTitle:(NSString *)moduleTitle
                        title:(NSString *)title
                       detail:(NSString *)detail
                     ctaTitle:(NSString *)ctaTitle
                     iconName:(NSString *)iconName
                      urgency:(NSInteger)urgency
                        count:(NSInteger)count
                         live:(BOOL)live {
    PPAdminCommandSignal *signal = [PPAdminCommandSignal new];
    signal.tag = tag ?: @"";
    signal.moduleTitle = moduleTitle ?: @"";
    signal.title = title ?: @"";
    signal.detail = detail ?: @"";
    signal.ctaTitle = ctaTitle ?: @"";
    signal.iconName = iconName ?: @"square.grid.2x2";
    signal.urgency = MAX(0, MIN(100, urgency));
    signal.count = MAX(0, count);
    signal.live = live;
    return signal;
}
@end

@interface PPAdminCommandGlassSurface : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *tintView;
@property (nonatomic, assign) CGFloat radius;
- (instancetype)initWithRadius:(CGFloat)radius;
- (void)refreshPalette;
@end

@implementation PPAdminCommandGlassSurface
- (instancetype)initWithRadius:(CGFloat)radius {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _radius = radius;
    self.backgroundColor = AppClearClr;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.shadowColor = AppShadowColor.CGColor;
    self.layer.shadowOpacity = 0.07;
    self.layer.shadowRadius = 20.0;
    self.layer.shadowOffset = CGSizeMake(0, 10);

    _blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    _blurView.userInteractionEnabled = NO;
    _blurView.clipsToBounds = YES;
    _blurView.layer.cornerRadius = radius;
    _blurView.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_blurView];

    _tintView = [UIView new];
    _tintView.userInteractionEnabled = NO;
    [_blurView.contentView addSubview:_tintView];

    [self refreshPalette];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.blurView.frame = self.bounds;
    self.tintView.frame = self.blurView.bounds;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.radius].CGPath;
}

- (void)refreshPalette {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    BOOL reduceTransparency = UIAccessibilityIsReduceTransparencyEnabled();
    self.blurView.hidden = reduceTransparency;
    self.backgroundColor = reduceTransparency ? AppForgroundColr : AppClearClr;
    self.tintView.backgroundColor = [AppForgroundColr colorWithAlphaComponent:dark ? 0.48 : 0.66];
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.layer.borderColor = PPAdminDashboardResolvedColor(PPHairlineColor(), self.traitCollection).CGColor;
    self.layer.shadowColor = AppShadowColor.CGColor;
    self.layer.shadowOpacity = dark ? 0.18 : 0.07;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self refreshPalette];
    }
}
@end

@interface PPAdminCommandCardControl : UIControl
@property (nonatomic, strong) PPAdminCommandGlassSurface *glass;
@property (nonatomic, strong) UIView *iconTile;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *moduleLabel;
@property (nonatomic, strong) UILabel *rankLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, copy) NSString *routeTag;
@property (nonatomic, copy) void (^onRoute)(NSString *tag);
- (void)configureWithSignal:(PPAdminCommandSignal *)signal rank:(NSInteger)rank hot:(BOOL)hot;
@end

@implementation PPAdminCommandCardControl
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.isAccessibilityElement = YES;

    _glass = [[PPAdminCommandGlassSurface alloc] initWithRadius:22.0];
    _glass.userInteractionEnabled = NO;
    [self addSubview:_glass];

    _iconTile = [UIView new];
    _iconTile.userInteractionEnabled = NO;
    _iconTile.layer.cornerRadius = 9.0;
    _iconTile.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_iconTile];

    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_iconTile addSubview:_iconView];

    _moduleLabel = [UILabel new];
    _moduleLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:9], UIFontTextStyleCaption2);
    _moduleLabel.adjustsFontForContentSizeCategory = YES;
    _moduleLabel.textColor = SeconderyTextClr;
    _moduleLabel.numberOfLines = 1;
    _moduleLabel.textAlignment = NSTextAlignmentNatural;
    [self addSubview:_moduleLabel];

    _rankLabel = [UILabel new];
    _rankLabel.font = PPAdminDashboardScaledFont([Styling fontBold:9], UIFontTextStyleCaption2);
    _rankLabel.adjustsFontForContentSizeCategory = YES;
    _rankLabel.textColor = AppPrimaryClr;
    _rankLabel.textAlignment = NSTextAlignmentNatural;
    [self addSubview:_rankLabel];

    _titleLabel = [UILabel new];
    _titleLabel.font = PPAdminDashboardScaledFont([Styling fontBold:14], UIFontTextStyleSubheadline);
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.textColor = PrimaryTextClr;
    _titleLabel.numberOfLines = 2;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.textAlignment = NSTextAlignmentNatural;
    [self addSubview:_titleLabel];

    _detailLabel = [UILabel new];
    _detailLabel.font = PPAdminDashboardScaledFont([Styling fontRegular:9], UIFontTextStyleCaption2);
    _detailLabel.adjustsFontForContentSizeCategory = YES;
    _detailLabel.textColor = SeconderyTextClr;
    _detailLabel.numberOfLines = 1;
    _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _detailLabel.textAlignment = NSTextAlignmentNatural;
    [self addSubview:_detailLabel];

    [self addTarget:self action:@selector(pp_touchDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(pp_touchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit | UIControlEventTouchUpOutside];
    [self addTarget:self action:@selector(pp_activate) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.glass.frame = self.bounds;

    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat inset = 12.0;
    CGFloat icon = 24.0;
    CGFloat rankW = 25.0;
    CGFloat topY = 10.0;

    self.iconTile.frame = CGRectMake(rtl ? CGRectGetWidth(self.bounds) - inset - icon : inset,
                                     topY, icon, icon);
    self.iconView.frame = CGRectInset(self.iconTile.bounds, 5.0, 5.0);

    CGFloat moduleX = rtl ? inset + rankW + 4.0 : inset + icon + 7.0;
    CGFloat moduleRight = rtl ? CGRectGetMinX(self.iconTile.frame) - 7.0 : CGRectGetWidth(self.bounds) - inset - rankW - 4.0;
    CGFloat moduleW = MAX(24.0, moduleRight - moduleX);
    self.moduleLabel.frame = CGRectMake(moduleX, topY + 1.0, moduleW, 17.0);

    self.rankLabel.frame = CGRectMake(rtl ? inset : CGRectGetWidth(self.bounds) - inset - rankW,
                                      topY + 2.0, rankW, 16.0);

    self.titleLabel.frame = CGRectMake(inset, 40.0, CGRectGetWidth(self.bounds) - inset * 2.0, 36.0);
    self.detailLabel.frame = CGRectMake(inset, CGRectGetHeight(self.bounds) - 23.0,
                                        CGRectGetWidth(self.bounds) - inset * 2.0, 15.0);
}

- (void)configureWithSignal:(PPAdminCommandSignal *)signal rank:(NSInteger)rank hot:(BOOL)hot {
    self.routeTag = signal.tag;
    self.moduleLabel.text = signal.moduleTitle;
    self.rankLabel.text = [NSString stringWithFormat:@"%02ld", (long)rank];
    self.titleLabel.text = signal.title;
    self.detailLabel.text = signal.detail;

    UIColor *tint = PPAdminDashboardTintForTag(signal.tag);
    self.iconTile.backgroundColor = [tint colorWithAlphaComponent:hot ? 0.16 : 0.10];
    self.iconView.tintColor = tint;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold];
    self.iconView.image = [UIImage systemImageNamed:signal.iconName withConfiguration:config] ?: [UIImage systemImageNamed:@"circle.fill"];

    self.glass.layer.borderColor = PPAdminDashboardResolvedColor(
        hot ? [AppPrimaryClr colorWithAlphaComponent:0.42] : PPHairlineColor(),
        self.traitCollection
    ).CGColor;
    self.glass.layer.shadowOpacity = hot ? 0.12 : 0.055;
    self.glass.layer.shadowRadius = hot ? 24.0 : 18.0;

    self.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", signal.moduleTitle, signal.title];
    self.accessibilityHint = kLang(@"AdminCommand_Accessibility_OpenHint");
}

- (void)pp_touchDown {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:0.08 animations:^{
        self.transform = CGAffineTransformMakeScale(0.975, 0.975);
    }];
}
- (void)pp_touchUp {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.transform = CGAffineTransformIdentity;
        return;
    }
    [UIView animateWithDuration:0.18
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.28
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}
- (void)pp_activate {
    if (self.routeTag.length > 0 && self.onRoute) self.onRoute(self.routeTag);
}
@end

@interface PPAdminCommandGateControl : UIControl
@property (nonatomic, strong) PPAdminCommandGlassSurface *glass;
@property (nonatomic, strong) UILabel *indexLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIImageView *arrowView;
@property (nonatomic, copy) NSString *routeTag;
@property (nonatomic, copy) void (^onRoute)(NSString *tag);
- (void)configureWithSignal:(PPAdminCommandSignal *)signal;
@end

@implementation PPAdminCommandGateControl
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    _glass = [[PPAdminCommandGlassSurface alloc] initWithRadius:19.0];
    _glass.userInteractionEnabled = NO;
    [self addSubview:_glass];

    _indexLabel = [UILabel new];
    _indexLabel.backgroundColor = AppPrimaryClr;
    _indexLabel.textColor = PPOnPrimaryColor();
    _indexLabel.font = PPAdminDashboardScaledFont([Styling fontBold:10], UIFontTextStyleCaption1);
    _indexLabel.textAlignment = NSTextAlignmentCenter;
    _indexLabel.layer.cornerRadius = 11.0;
    _indexLabel.layer.cornerCurve = kCACornerCurveContinuous;
    _indexLabel.clipsToBounds = YES;
    _indexLabel.text = @"01";
    [self addSubview:_indexLabel];

    _titleLabel = [UILabel new];
    _titleLabel.font = PPAdminDashboardScaledFont([Styling fontBold:10], UIFontTextStyleCaption1);
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.textColor = PrimaryTextClr;
    _titleLabel.textAlignment = NSTextAlignmentNatural;
    [self addSubview:_titleLabel];

    _detailLabel = [UILabel new];
    _detailLabel.font = PPAdminDashboardScaledFont([Styling fontRegular:8], UIFontTextStyleCaption2);
    _detailLabel.adjustsFontForContentSizeCategory = YES;
    _detailLabel.textColor = SeconderyTextClr;
    _detailLabel.textAlignment = NSTextAlignmentNatural;
    _detailLabel.numberOfLines = 1;
    [self addSubview:_detailLabel];

    _arrowView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"]];
    _arrowView.tintColor = AppPrimaryClr;
    _arrowView.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_arrowView];

    [self addTarget:self action:@selector(pp_activate) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.glass.frame = self.bounds;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat h = CGRectGetHeight(self.bounds);
    CGFloat index = 34.0;
    self.indexLabel.frame = CGRectMake(rtl ? CGRectGetWidth(self.bounds) - 10.0 - index : 10.0,
                                       (h-index)/2.0, index, index);
    CGFloat arrowW = 24.0;
    self.arrowView.frame = CGRectMake(rtl ? 10.0 : CGRectGetWidth(self.bounds) - 10.0 - arrowW,
                                      (h-arrowW)/2.0, arrowW, arrowW);
    CGFloat left = rtl ? CGRectGetMaxX(self.arrowView.frame) + 7.0 : CGRectGetMaxX(self.indexLabel.frame) + 8.0;
    CGFloat right = rtl ? CGRectGetMinX(self.indexLabel.frame) - 8.0 : CGRectGetMinX(self.arrowView.frame) - 7.0;
    CGFloat width = MAX(30.0, right-left);
    self.titleLabel.frame = CGRectMake(left, 10.0, width, 18.0);
    self.detailLabel.frame = CGRectMake(left, 30.0, width, 16.0);
    self.arrowView.transform = rtl ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
}
- (void)configureWithSignal:(PPAdminCommandSignal *)signal {
    self.routeTag = signal.tag;
    self.titleLabel.text = kLang(@"AdminCommand_PriorityNow");
    self.detailLabel.text = signal.title;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", kLang(@"AdminCommand_PriorityNow"), signal.title];
    self.accessibilityHint = kLang(@"AdminCommand_Accessibility_OpenHint");
}
- (void)pp_activate {
    if (self.routeTag.length > 0 && self.onRoute) self.onRoute(self.routeTag);
}
@end

@interface PPAdminCommandStageView : UIView
@property (nonatomic, strong) UIView *spine;
@property (nonatomic, copy) NSArray<UIView *> *ticks;
@property (nonatomic, copy) NSArray<PPAdminCommandCardControl *> *cards;
@property (nonatomic, strong) PPAdminCommandGateControl *gate;
@property (nonatomic, strong) UILabel *bridgeLabel;
@property (nonatomic, copy) void (^onRoute)(NSString *tag);
- (void)applySignals:(NSArray<PPAdminCommandSignal *> *)signals;
@end

@implementation PPAdminCommandStageView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = AppClearClr;

    _spine = [UIView new];
    _spine.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.46];
    _spine.layer.cornerRadius = 1.5;
    [self addSubview:_spine];

    NSMutableArray *ticks = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        UIView *tick = [UIView new];
        tick.backgroundColor = AppForgroundColr;
        tick.layer.cornerRadius = 6.0;
        tick.layer.borderWidth = 2.0;
        tick.layer.borderColor = [AppPrimaryClr colorWithAlphaComponent:0.28].CGColor;
        [self addSubview:tick];
        [ticks addObject:tick];
    }
    _ticks = ticks.copy;

    NSMutableArray *cards = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        PPAdminCommandCardControl *card = [PPAdminCommandCardControl new];
        __weak typeof(self) weakSelf = self;
        card.onRoute = ^(NSString *tag) {
            if (weakSelf.onRoute) weakSelf.onRoute(tag);
        };
        [self addSubview:card];
        [cards addObject:card];
    }
    _cards = cards.copy;

    _gate = [PPAdminCommandGateControl new];
    __weak typeof(self) weakSelf = self;
    _gate.onRoute = ^(NSString *tag) {
        if (weakSelf.onRoute) weakSelf.onRoute(tag);
    };
    [self addSubview:_gate];

    _bridgeLabel = [UILabel new];
    _bridgeLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:8], UIFontTextStyleCaption2);
    _bridgeLabel.textColor = SeconderyTextClr;
    _bridgeLabel.textAlignment = NSTextAlignmentCenter;
    _bridgeLabel.backgroundColor = [AppPrimaryClrShiner colorWithAlphaComponent:0.48];
    _bridgeLabel.layer.cornerRadius = 10.0;
    _bridgeLabel.layer.cornerCurve = kCACornerCurveContinuous;
    _bridgeLabel.clipsToBounds = YES;
    _bridgeLabel.text = kLang(@"AdminCommand_DirectRoute");
    [self addSubview:_bridgeLabel];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    CGFloat centerX = floor(w/2.0);
    self.spine.frame = CGRectMake(centerX - 1.5, 10.0, 3.0, h - 20.0);

    NSArray<NSNumber *> *tickY = @[@64.0, @151.0, @342.0, @423.0];
    [self.ticks enumerateObjectsUsingBlock:^(UIView *tick, NSUInteger idx, BOOL *stop) {
        CGFloat y = idx < tickY.count ? tickY[idx].doubleValue : 0.0;
        tick.frame = CGRectMake(centerX - 6.0, y, 12.0, 12.0);
    }];

    CGFloat cardW = MIN(148.0, floor((w - 34.0) / 2.0));
    CGFloat cardH = 88.0;
    CGFloat leftX = 0.0;
    CGFloat rightX = w - cardW;
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;

    NSArray<NSNumber *> *ys = @[@20.0, @105.0, @320.0, @378.0];
    for (NSInteger i = 0; i < self.cards.count; i++) {
        BOOL nominalLeft = (i == 0 || i == 2);
        BOOL actualLeft = rtl ? !nominalLeft : nominalLeft;
        CGFloat x = actualLeft ? leftX : rightX;
        self.cards[i].frame = CGRectMake(x, ys[i].doubleValue, cardW, cardH);
    }

    CGFloat gateW = MIN(176.0, MAX(154.0, w * 0.45));
    self.gate.frame = CGRectMake(centerX - gateW/2.0, 218.0, gateW, 60.0);
    CGFloat bridgeW = MIN(190.0, w - 50.0);
    self.bridgeLabel.frame = CGRectMake(centerX - bridgeW/2.0, 286.0, bridgeW, 20.0);
}

- (void)applySignals:(NSArray<PPAdminCommandSignal *> *)signals {
    for (NSInteger i = 0; i < self.cards.count; i++) {
        PPAdminCommandCardControl *card = self.cards[i];
        if (i < signals.count) {
            PPAdminCommandSignal *signal = signals[i];
            card.hidden = NO;
            [card configureWithSignal:signal rank:i+1 hot:(i < 2 && signal.isLive)];
        } else {
            card.hidden = YES;
        }
    }
    if (signals.firstObject) {
        self.gate.hidden = NO;
        [self.gate configureWithSignal:signals.firstObject];
    } else {
        self.gate.hidden = YES;
    }
    self.bridgeLabel.text = kLang(@"AdminCommand_DirectRoute");
    [self setNeedsLayout];
}
@end

@interface PPAdminCommandCenterView : UIView
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) PPAdminCommandGlassSurface *pulseSurface;
@property (nonatomic, strong) UILabel *pulseCaptionLabel;
@property (nonatomic, strong) UILabel *pulseValueLabel;
@property (nonatomic, strong) PPAdminCommandGlassSurface *roleSurface;
@property (nonatomic, strong) UIView *roleIcon;
@property (nonatomic, strong) UILabel *roleIconLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *roleStatusLabel;
@property (nonatomic, strong) UILabel *roleCountLabel;
@property (nonatomic, strong) PPAdminCommandGlassSurface *lensSurface;
@property (nonatomic, copy) NSArray<UIView *> *lensOrbs;
@property (nonatomic, strong) UILabel *lensTitleLabel;
@property (nonatomic, strong) UILabel *lensSubtitleLabel;
@property (nonatomic, strong) PPAdminCommandStageView *stage;
@property (nonatomic, strong) UILabel *liveMetricValue;
@property (nonatomic, strong) UILabel *liveMetricTitle;
@property (nonatomic, strong) UILabel *urgentMetricValue;
@property (nonatomic, strong) UILabel *urgentMetricTitle;
@property (nonatomic, strong) UILabel *moduleMetricValue;
@property (nonatomic, strong) UILabel *moduleMetricTitle;
@property (nonatomic, strong) PPAdminCommandGlassSurface *prioritySurface;
@property (nonatomic, strong) UIView *priorityIconTile;
@property (nonatomic, strong) UIImageView *priorityIconView;
@property (nonatomic, strong) UILabel *priorityTitleLabel;
@property (nonatomic, strong) UILabel *prioritySubtitleLabel;
@property (nonatomic, strong) UIButton *priorityButton;
@property (nonatomic, copy) NSString *priorityRouteTag;
@property (nonatomic, copy) void (^onRoute)(NSString *tag);
- (void)applyRoleName:(NSString *)roleName
      capabilityCount:(NSInteger)capabilityCount
              signals:(NSArray<PPAdminCommandSignal *> *)signals;
- (void)refreshLocalization;
@end

@implementation PPAdminCommandCenterView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = AppClearClr;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    _scrollView = [UIScrollView new];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.backgroundColor = AppClearClr;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self addSubview:_scrollView];

    _contentView = [UIView new];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentView.backgroundColor = AppClearClr;
    [_scrollView addSubview:_contentView];

    _pulseSurface = [[PPAdminCommandGlassSurface alloc] initWithRadius:18.0];
    _pulseSurface.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:_pulseSurface];

    _pulseCaptionLabel = [UILabel new];
    _pulseCaptionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pulseCaptionLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:8], UIFontTextStyleCaption2);
    _pulseCaptionLabel.textColor = SeconderyTextClr;
    _pulseCaptionLabel.textAlignment = NSTextAlignmentNatural;
    [_pulseSurface addSubview:_pulseCaptionLabel];

    _pulseValueLabel = [UILabel new];
    _pulseValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pulseValueLabel.font = PPAdminDashboardScaledFont([Styling fontBold:27], UIFontTextStyleTitle1);
    _pulseValueLabel.adjustsFontForContentSizeCategory = YES;
    _pulseValueLabel.textColor = PrimaryTextClr;
    _pulseValueLabel.textAlignment = NSTextAlignmentNatural;
    [_pulseSurface addSubview:_pulseValueLabel];

    _roleSurface = [[PPAdminCommandGlassSurface alloc] initWithRadius:18.0];
    _roleSurface.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:_roleSurface];

    _roleIcon = [UIView new];
    _roleIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _roleIcon.backgroundColor = AppPrimaryClr;
    _roleIcon.layer.cornerRadius = 11.0;
    _roleIcon.layer.cornerCurve = kCACornerCurveContinuous;
    [_roleSurface addSubview:_roleIcon];

    _roleIconLabel = [UILabel new];
    _roleIconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleIconLabel.text = @"PP";
    _roleIconLabel.textColor = PPOnPrimaryColor();
    _roleIconLabel.font = PPAdminDashboardScaledFont([Styling fontBold:9], UIFontTextStyleCaption2);
    _roleIconLabel.textAlignment = NSTextAlignmentCenter;
    [_roleIcon addSubview:_roleIconLabel];

    _roleLabel = [UILabel new];
    _roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleLabel.font = PPAdminDashboardScaledFont([Styling fontBold:11], UIFontTextStyleCaption1);
    _roleLabel.adjustsFontForContentSizeCategory = YES;
    _roleLabel.textColor = PrimaryTextClr;
    _roleLabel.textAlignment = NSTextAlignmentNatural;
    [_roleSurface addSubview:_roleLabel];

    _roleStatusLabel = [UILabel new];
    _roleStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleStatusLabel.font = PPAdminDashboardScaledFont([Styling fontRegular:8], UIFontTextStyleCaption2);
    _roleStatusLabel.textColor = SeconderyTextClr;
    _roleStatusLabel.textAlignment = NSTextAlignmentNatural;
    [_roleSurface addSubview:_roleStatusLabel];

    _roleCountLabel = [UILabel new];
    _roleCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleCountLabel.font = PPAdminDashboardScaledFont([Styling fontMedium:9], UIFontTextStyleCaption2);
    _roleCountLabel.textColor = SeconderyTextClr;
    _roleCountLabel.textAlignment = NSTextAlignmentNatural;
    [_roleSurface addSubview:_roleCountLabel];

    _lensSurface = [[PPAdminCommandGlassSurface alloc] initWithRadius:18.0];
    _lensSurface.translatesAutoresizingMaskIntoConstraints = NO;
    _lensSurface.isAccessibilityElement = YES;
    [_contentView addSubview:_lensSurface];

    NSMutableArray *orbs = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIView *orb = [UIView new];
        orb.translatesAutoresizingMaskIntoConstraints = NO;
        orb.backgroundColor = (i == 0) ? [AppPrimaryClr colorWithAlphaComponent:0.12] : [AppForgroundColr colorWithAlphaComponent:0.70];
        orb.layer.cornerRadius = 9.0;
        orb.layer.cornerCurve = kCACornerCurveContinuous;
        orb.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        orb.layer.borderColor = PPHairlineColor().CGColor;
        [_lensSurface addSubview:orb];
        [orbs addObject:orb];
    }
    _lensOrbs = orbs.copy;

    _lensTitleLabel = [UILabel new];
    _lensTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _lensTitleLabel.font = PPAdminDashboardScaledFont([Styling fontBold:10], UIFontTextStyleCaption1);
    _lensTitleLabel.textColor = PrimaryTextClr;
    _lensTitleLabel.textAlignment = NSTextAlignmentNatural;
    [_lensSurface addSubview:_lensTitleLabel];

    _lensSubtitleLabel = [UILabel new];
    _lensSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _lensSubtitleLabel.font = PPAdminDashboardScaledFont([Styling fontRegular:8], UIFontTextStyleCaption2);
    _lensSubtitleLabel.textColor = SeconderyTextClr;
    _lensSubtitleLabel.textAlignment = NSTextAlignmentNatural;
    [_lensSurface addSubview:_lensSubtitleLabel];

    _stage = [PPAdminCommandStageView new];
    _stage.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _stage.onRoute = ^(NSString *tag) {
        if (weakSelf.onRoute) weakSelf.onRoute(tag);
    };
    [_contentView addSubview:_stage];

    UIStackView *metrics = [UIStackView new];
    metrics.translatesAutoresizingMaskIntoConstraints = NO;
    metrics.axis = UILayoutConstraintAxisHorizontal;
    metrics.distribution = UIStackViewDistributionFillEqually;
    metrics.alignment = UIStackViewAlignmentFill;
    [_contentView addSubview:metrics];

    _liveMetricValue = [UILabel new];
    _liveMetricTitle = [UILabel new];
    _urgentMetricValue = [UILabel new];
    _urgentMetricTitle = [UILabel new];
    _moduleMetricValue = [UILabel new];
    _moduleMetricTitle = [UILabel new];

    [metrics addArrangedSubview:[self pp_metricItemWithValue:_liveMetricValue title:_liveMetricTitle]];
    [metrics addArrangedSubview:[self pp_metricItemWithValue:_urgentMetricValue title:_urgentMetricTitle]];
    [metrics addArrangedSubview:[self pp_metricItemWithValue:_moduleMetricValue title:_moduleMetricTitle]];

    _prioritySurface = [[PPAdminCommandGlassSurface alloc] initWithRadius:20.0];
    _prioritySurface.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:_prioritySurface];

    _priorityIconTile = [UIView new];
    _priorityIconTile.translatesAutoresizingMaskIntoConstraints = NO;
    _priorityIconTile.backgroundColor = AppPrimaryClr;
    _priorityIconTile.layer.cornerRadius = 11.0;
    _priorityIconTile.layer.cornerCurve = kCACornerCurveContinuous;
    [_prioritySurface addSubview:_priorityIconTile];

    _priorityIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]];
    _priorityIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _priorityIconView.tintColor = PPOnPrimaryColor();
    _priorityIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_priorityIconTile addSubview:_priorityIconView];

    _priorityTitleLabel = [UILabel new];
    _priorityTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _priorityTitleLabel.font = PPAdminDashboardScaledFont([Styling fontBold:11], UIFontTextStyleCaption1);
    _priorityTitleLabel.adjustsFontForContentSizeCategory = YES;
    _priorityTitleLabel.textColor = PrimaryTextClr;
    _priorityTitleLabel.textAlignment = NSTextAlignmentNatural;
    _priorityTitleLabel.numberOfLines = 1;
    [_prioritySurface addSubview:_priorityTitleLabel];

    _prioritySubtitleLabel = [UILabel new];
    _prioritySubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _prioritySubtitleLabel.font = PPAdminDashboardScaledFont([Styling fontRegular:8], UIFontTextStyleCaption2);
    _prioritySubtitleLabel.adjustsFontForContentSizeCategory = YES;
    _prioritySubtitleLabel.textColor = SeconderyTextClr;
    _prioritySubtitleLabel.textAlignment = NSTextAlignmentNatural;
    _prioritySubtitleLabel.numberOfLines = 1;
    [_prioritySurface addSubview:_prioritySubtitleLabel];

    _priorityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _priorityButton.translatesAutoresizingMaskIntoConstraints = NO;
    _priorityButton.backgroundColor = AppPrimaryClr;
    _priorityButton.tintColor = PPOnPrimaryColor();
    _priorityButton.titleLabel.font = PPAdminDashboardScaledFont([Styling fontBold:10], UIFontTextStyleCaption1);
    _priorityButton.layer.cornerRadius = 13.0;
    _priorityButton.layer.cornerCurve = kCACornerCurveContinuous;
    [_priorityButton addTarget:self action:@selector(pp_openPriority) forControlEvents:UIControlEventTouchUpInside];
    [_prioritySurface addSubview:_priorityButton];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_contentView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [_contentView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor],
        [_contentView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [_contentView.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor],

        [_pulseSurface.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-18.0],
        [_pulseSurface.topAnchor constraintEqualToAnchor:_contentView.topAnchor constant:12.0],
        [_pulseSurface.widthAnchor constraintEqualToConstant:92.0],
        [_pulseSurface.heightAnchor constraintEqualToConstant:66.0],

        [_pulseCaptionLabel.topAnchor constraintEqualToAnchor:_pulseSurface.topAnchor constant:10.0],
        [_pulseCaptionLabel.leadingAnchor constraintEqualToAnchor:_pulseSurface.leadingAnchor constant:11.0],
        [_pulseCaptionLabel.trailingAnchor constraintEqualToAnchor:_pulseSurface.trailingAnchor constant:-11.0],
        [_pulseValueLabel.topAnchor constraintEqualToAnchor:_pulseCaptionLabel.bottomAnchor constant:1.0],
        [_pulseValueLabel.leadingAnchor constraintEqualToAnchor:_pulseSurface.leadingAnchor constant:11.0],
        [_pulseValueLabel.trailingAnchor constraintEqualToAnchor:_pulseSurface.trailingAnchor constant:-11.0],
        [_pulseValueLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_pulseSurface.bottomAnchor constant:-6.0],

        [_roleSurface.topAnchor constraintEqualToAnchor:_contentView.topAnchor constant:12.0],
        [_roleSurface.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:18.0],
        [_roleSurface.trailingAnchor constraintEqualToAnchor:_pulseSurface.leadingAnchor constant:-12.0],
        [_roleSurface.heightAnchor constraintEqualToConstant:58.0],

        [_roleIcon.leadingAnchor constraintEqualToAnchor:_roleSurface.leadingAnchor constant:10.0],
        [_roleIcon.centerYAnchor constraintEqualToAnchor:_roleSurface.centerYAnchor],
        [_roleIcon.widthAnchor constraintEqualToConstant:34.0],
        [_roleIcon.heightAnchor constraintEqualToConstant:34.0],
        [_roleIconLabel.centerXAnchor constraintEqualToAnchor:_roleIcon.centerXAnchor],
        [_roleIconLabel.centerYAnchor constraintEqualToAnchor:_roleIcon.centerYAnchor],
        [_roleLabel.leadingAnchor constraintEqualToAnchor:_roleIcon.trailingAnchor constant:9.0],
        [_roleLabel.topAnchor constraintEqualToAnchor:_roleSurface.topAnchor constant:11.0],
        [_roleStatusLabel.leadingAnchor constraintEqualToAnchor:_roleLabel.leadingAnchor],
        [_roleStatusLabel.topAnchor constraintEqualToAnchor:_roleLabel.bottomAnchor constant:2.0],
        [_roleCountLabel.trailingAnchor constraintEqualToAnchor:_roleSurface.trailingAnchor constant:-11.0],
        [_roleCountLabel.centerYAnchor constraintEqualToAnchor:_roleSurface.centerYAnchor],
        [_roleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_roleCountLabel.leadingAnchor constant:-8.0],

        [_lensSurface.topAnchor constraintEqualToAnchor:_roleSurface.bottomAnchor constant:9.0],
        [_lensSurface.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:18.0],
        [_lensSurface.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-18.0],
        [_lensSurface.heightAnchor constraintEqualToConstant:52.0],

        [_lensOrbs[0].leadingAnchor constraintEqualToAnchor:_lensSurface.leadingAnchor constant:10.0],
        [_lensOrbs[0].centerYAnchor constraintEqualToAnchor:_lensSurface.centerYAnchor],
        [_lensOrbs[0].widthAnchor constraintEqualToConstant:28.0],
        [_lensOrbs[0].heightAnchor constraintEqualToConstant:28.0],
        [_lensOrbs[1].leadingAnchor constraintEqualToAnchor:_lensOrbs[0].leadingAnchor constant:21.0],
        [_lensOrbs[1].centerYAnchor constraintEqualToAnchor:_lensOrbs[0].centerYAnchor],
        [_lensOrbs[1].widthAnchor constraintEqualToConstant:28.0],
        [_lensOrbs[1].heightAnchor constraintEqualToConstant:28.0],
        [_lensOrbs[2].leadingAnchor constraintEqualToAnchor:_lensOrbs[1].leadingAnchor constant:21.0],
        [_lensOrbs[2].centerYAnchor constraintEqualToAnchor:_lensOrbs[0].centerYAnchor],
        [_lensOrbs[2].widthAnchor constraintEqualToConstant:28.0],
        [_lensOrbs[2].heightAnchor constraintEqualToConstant:28.0],
        [_lensTitleLabel.leadingAnchor constraintEqualToAnchor:_lensOrbs[2].trailingAnchor constant:10.0],
        [_lensTitleLabel.topAnchor constraintEqualToAnchor:_lensSurface.topAnchor constant:10.0],
        [_lensTitleLabel.trailingAnchor constraintEqualToAnchor:_lensSurface.trailingAnchor constant:-11.0],
        [_lensSubtitleLabel.leadingAnchor constraintEqualToAnchor:_lensTitleLabel.leadingAnchor],
        [_lensSubtitleLabel.topAnchor constraintEqualToAnchor:_lensTitleLabel.bottomAnchor constant:1.0],
        [_lensSubtitleLabel.trailingAnchor constraintEqualToAnchor:_lensTitleLabel.trailingAnchor],

        [_stage.topAnchor constraintEqualToAnchor:_lensSurface.bottomAnchor constant:8.0],
        [_stage.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:18.0],
        [_stage.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-18.0],
        [_stage.heightAnchor constraintEqualToConstant:474.0],

        [metrics.topAnchor constraintEqualToAnchor:_stage.bottomAnchor constant:4.0],
        [metrics.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:18.0],
        [metrics.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-18.0],
        [metrics.heightAnchor constraintEqualToConstant:54.0],

        [_prioritySurface.topAnchor constraintEqualToAnchor:metrics.bottomAnchor constant:9.0],
        [_prioritySurface.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:18.0],
        [_prioritySurface.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-18.0],
        [_prioritySurface.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor constant:-18.0],
        [_prioritySurface.heightAnchor constraintEqualToConstant:112.0],

        [_priorityIconTile.leadingAnchor constraintEqualToAnchor:_prioritySurface.leadingAnchor constant:11.0],
        [_priorityIconTile.topAnchor constraintEqualToAnchor:_prioritySurface.topAnchor constant:11.0],
        [_priorityIconTile.widthAnchor constraintEqualToConstant:34.0],
        [_priorityIconTile.heightAnchor constraintEqualToConstant:34.0],
        [_priorityIconView.centerXAnchor constraintEqualToAnchor:_priorityIconTile.centerXAnchor],
        [_priorityIconView.centerYAnchor constraintEqualToAnchor:_priorityIconTile.centerYAnchor],
        [_priorityIconView.widthAnchor constraintEqualToConstant:14.0],
        [_priorityIconView.heightAnchor constraintEqualToConstant:14.0],
        [_priorityTitleLabel.leadingAnchor constraintEqualToAnchor:_priorityIconTile.trailingAnchor constant:9.0],
        [_priorityTitleLabel.topAnchor constraintEqualToAnchor:_prioritySurface.topAnchor constant:11.0],
        [_priorityTitleLabel.trailingAnchor constraintEqualToAnchor:_prioritySurface.trailingAnchor constant:-11.0],
        [_prioritySubtitleLabel.leadingAnchor constraintEqualToAnchor:_priorityTitleLabel.leadingAnchor],
        [_prioritySubtitleLabel.topAnchor constraintEqualToAnchor:_priorityTitleLabel.bottomAnchor constant:2.0],
        [_prioritySubtitleLabel.trailingAnchor constraintEqualToAnchor:_priorityTitleLabel.trailingAnchor],
        [_priorityButton.leadingAnchor constraintEqualToAnchor:_prioritySurface.leadingAnchor constant:11.0],
        [_priorityButton.trailingAnchor constraintEqualToAnchor:_prioritySurface.trailingAnchor constant:-11.0],
        [_priorityButton.bottomAnchor constraintEqualToAnchor:_prioritySurface.bottomAnchor constant:-10.0],
        [_priorityButton.heightAnchor constraintEqualToConstant:36.0]
    ]];

    [self refreshLocalization];
    return self;
}

- (UIView *)pp_metricItemWithValue:(UILabel *)value title:(UILabel *)title {
    UIView *container = [UIView new];
    value.translatesAutoresizingMaskIntoConstraints = NO;
    value.font = PPAdminDashboardScaledFont([Styling fontBold:18], UIFontTextStyleTitle3);
    value.textColor = PrimaryTextClr;
    value.textAlignment = NSTextAlignmentCenter;
    value.adjustsFontForContentSizeCategory = YES;
    [container addSubview:value];

    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = PPAdminDashboardScaledFont([Styling fontMedium:8], UIFontTextStyleCaption2);
    title.textColor = SeconderyTextClr;
    title.textAlignment = NSTextAlignmentCenter;
    title.adjustsFontForContentSizeCategory = YES;
    [container addSubview:title];

    [NSLayoutConstraint activateConstraints:@[
        [value.topAnchor constraintEqualToAnchor:container.topAnchor constant:4.0],
        [value.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [value.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [title.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:1.0],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [title.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-2.0]
    ]];
    return container;
}

- (void)refreshLocalization {
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.contentView.semanticContentAttribute = self.semanticContentAttribute;
    self.pulseCaptionLabel.text = kLang(@"AdminCommand_Pulse");
    self.roleStatusLabel.text = kLang(@"AdminCommand_StaffActive");
    self.lensTitleLabel.text = kLang(@"AdminCommand_AllCapabilities");
    self.liveMetricTitle.text = kLang(@"AdminCommand_LiveSignals");
    self.urgentMetricTitle.text = kLang(@"AdminCommand_Urgent");
    self.moduleMetricTitle.text = kLang(@"AdminCommand_Modules");
    self.stage.bridgeLabel.text = kLang(@"AdminCommand_DirectRoute");

    self.roleLabel.textAlignment = NSTextAlignmentNatural;
    self.roleStatusLabel.textAlignment = NSTextAlignmentNatural;
    self.roleCountLabel.textAlignment = NSTextAlignmentNatural;
    self.lensTitleLabel.textAlignment = NSTextAlignmentNatural;
    self.lensSubtitleLabel.textAlignment = NSTextAlignmentNatural;
}

- (void)applyRoleName:(NSString *)roleName
      capabilityCount:(NSInteger)capabilityCount
              signals:(NSArray<PPAdminCommandSignal *> *)signals {
    [self refreshLocalization];

    self.roleLabel.text = roleName.length > 0 ? roleName : kLang(@"pp_role_admin");
    self.roleCountLabel.text = [NSString stringWithFormat:kLang(@"AdminCommand_ModuleCount_Format"), (long)capabilityCount];
    self.lensSubtitleLabel.text = [NSString stringWithFormat:kLang(@"AdminCommand_ModuleCount_Format"), (long)capabilityCount];
    self.lensSurface.accessibilityLabel = [NSString stringWithFormat:@"%@. %@",
                                           kLang(@"AdminCommand_AllCapabilities"),
                                           self.lensSubtitleLabel.text];

    NSInteger liveCount = 0;
    NSInteger urgentCount = 0;
    for (PPAdminCommandSignal *signal in signals) {
        if (signal.isLive) liveCount += 1;
        if (signal.isLive && signal.urgency >= 90) urgentCount += 1;
    }

    NSInteger pressure = MIN(36, urgentCount * 8 + liveCount * 3);
    NSInteger pulse = MAX(64, 100 - pressure);
    self.pulseValueLabel.text = [NSString stringWithFormat:@"%ld", (long)pulse];
    self.liveMetricValue.text = [NSString stringWithFormat:@"%ld", (long)liveCount];
    self.urgentMetricValue.text = [NSString stringWithFormat:@"%ld", (long)urgentCount];
    self.moduleMetricValue.text = [NSString stringWithFormat:@"%ld", (long)capabilityCount];

    [self.stage applySignals:signals];

    PPAdminCommandSignal *top = signals.firstObject;
    if (top) {
        self.prioritySurface.hidden = NO;
        self.priorityRouteTag = top.tag;
        self.priorityTitleLabel.text = top.title;
        self.prioritySubtitleLabel.text = [NSString stringWithFormat:@"%@ · %02d",
                                           top.moduleTitle,
                                           1];
        [self.priorityButton setTitle:top.ctaTitle forState:UIControlStateNormal];
        UIColor *tint = PPAdminDashboardTintForTag(top.tag);
        self.priorityIconTile.backgroundColor = tint;
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        self.priorityIconView.image = [UIImage systemImageNamed:top.iconName withConfiguration:config] ?: [UIImage systemImageNamed:@"arrow.forward"];
        self.priorityButton.backgroundColor = AppPrimaryClr;
        self.priorityButton.accessibilityLabel = top.ctaTitle;
        self.priorityButton.accessibilityHint = kLang(@"AdminCommand_Accessibility_OpenHint");
    } else {
        self.prioritySurface.hidden = YES;
        self.priorityRouteTag = @"";
    }
}

- (void)pp_openPriority {
    if (self.priorityRouteTag.length > 0 && self.onRoute) self.onRoute(self.priorityRouteTag);
}
@end

// PP_ADMIN_COMMAND_SPINE_TYPES_END


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
// PP_ADMIN_COMMAND_SPINE_PROPERTIES_BEGIN
@property (nonatomic, strong) AdminCommandOrbitHostingController *pp_commandOrbitController;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> pp_fulfillmentPriorityReg;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> pp_inventoryPriorityReg;
@property (nonatomic, copy) NSArray<PPFulfillmentRecord *> *pp_fulfillmentPriorityRecords;
@property (nonatomic, copy) NSArray<PPDeliveryRequestRecord *> *pp_deliveryPriorityRecords;
@property (nonatomic, copy) NSArray<PPPaymentAdminRecord *> *pp_paymentPriorityRecords;
@property (nonatomic, copy) NSArray<PetAccessory *> *pp_inventoryPriorityItems;
@property (nonatomic, assign) BOOL pp_priorityFeedsStarted;
@property (nonatomic, assign) BOOL pp_commandSurfaceVisible;
@property (nonatomic, assign) NSUInteger pp_priorityLiveGeneration;
@property (nonatomic, assign) NSUInteger pp_priorityOneShotGeneration;
// Presentation-only feed readiness metadata (pending/loaded/failed per stable
// area tag). Derived from feeds this controller already owns; no new listeners.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *pp_feedStatusByArea;
@property (nonatomic, strong, nullable) NSDate *pp_lastFeedConfirmationAt;
// PP_ADMIN_COMMAND_SPINE_PROPERTIES_END


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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pp_commandLanguageDidChange:)
                                                 name:LanguageDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pp_commandAuthorizationDidChange:)
                                                 name:@"PPAdminCommandAuthorizationDidChangeNotification"
                                               object:self];
    [self pp_buildDashboardLoadingStateIfNeeded];

    NSString *currentUID = [FIRAuth auth].currentUser.uid;
    UserModel *curUser = UsrMgr.currentUser;
    if (!curUser && currentUID.length > 0) {
        curUser = [UsrMgr p_readUserFromDisk:currentUID];
    }

    if (curUser) {
        UsrMgr.currentUser = curUser;
        if (!self.pp_isCommandSpine) {
            [self setupHeaderUIWithUser:curUser];
        }
        [self pp_rebuildDashboardFormPreservingOffset:NO];
        [self pp_installCommandOrbitIfNeeded];
        [self pp_refreshCommandOrbitSnapshot];
        [self pp_startCommandPriorityFeedsIfNeeded];
        [self pp_syncCachedAdminNotificationTokenIfNeeded];
        if (!self.pp_isCommandSpine) {
            [self pp_setDashboardLoadingVisible:NO];
        }
    } else {
        if (!self.pp_isCommandSpine) {
            [self pp_setDashboardLoadingVisible:YES];
        }
        __weak typeof(self) weakSelf = self;
        [FUM reloadCurrentUserWithCompletion:^(UserModel * _Nullable user, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error || !user) {
                    if (!weakSelf.pp_isCommandSpine) {
                        [weakSelf pp_setDashboardLoadingVisible:NO];
                    }
                    [weakSelf showLogin];
                    return;
                }

                UsrMgr.currentUser = user;
                if (!weakSelf.pp_isCommandSpine) {
                    [weakSelf setupHeaderUIWithUser:user];
                }
                [weakSelf pp_rebuildDashboardFormPreservingOffset:NO];
                [weakSelf pp_installCommandOrbitIfNeeded];
                [weakSelf pp_refreshCommandOrbitSnapshot];
                [weakSelf pp_startCommandPriorityFeedsIfNeeded];
                [weakSelf pp_syncCachedAdminNotificationTokenIfNeeded];
                if (!weakSelf.pp_isCommandSpine) {
                    [weakSelf pp_setDashboardLoadingVisible:NO];
                }
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
        if (!weakSelf.pp_isCommandSpine) {
            [weakSelf setupHeaderUIWithUser:UsrMgr.currentUser];
        }
        [weakSelf pp_installCommandOrbitIfNeeded];
        [weakSelf pp_refreshCommandOrbitSnapshot];
        [weakSelf pp_startCommandPriorityFeedsIfNeeded];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.pp_isCommandSpine) {
        return;
    }
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
    if (self.pp_isCommandSpine) {
        return;
    }
    [self.heroGlassBG startAnimations];
    [self pp_animateHeaderIntroIfNeeded];
    [self pp_animateVisibleCellsModern];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.pp_commandSurfaceVisible = YES;
    
    // Aggressively hide navigation bar and tab bar to allow SwiftUI full-screen control
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    if (self.tabBarController) {
        self.tabBarController.tabBar.hidden = YES;
    }
    
    [self updateHeaderWithUser:UsrMgr.currentUser];
    
    // Forcefully hide all legacy native header views that might be lingering
    self.tableView.hidden = YES;
    self.heroShadowView.hidden = YES;
    self.headerRoot.hidden = YES;
    
    [self pp_rebuildDashboardFormPreservingOffset:YES];
    [self pp_installCommandOrbitIfNeeded];
    [self pp_refreshCommandOrbitSnapshot];
    [self pp_startCommandPriorityFeedsIfNeeded];
    [self pp_prepareHeaderIntroIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.pp_commandSurfaceVisible = NO;
    
    // Restore navigation bar and tab bar for other controllers
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    if (self.tabBarController) {
        self.tabBarController.tabBar.hidden = NO;
    }
    
    [self pp_stopCommandPriorityFeeds];
    [self.dashboardBackdropView stopMotion];
    [self.heroGlassBG stopAnimations];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIAccessibilityReduceMotionStatusDidChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:LanguageDidChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"PPAdminCommandAuthorizationDidChangeNotification"
                                                  object:self];
    [self.reg remove];
    [self pp_stopCommandPriorityFeeds];
    [AppMgr stopCountsListening];
}

#pragma mark - Header

- (void)setupHeaderUIWithUser:(UserModel *)curUser {
    if (self.pp_isCommandSpine) {
        return;
    }
    
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

        [contentOverlay.topAnchor constraintEqualToAnchor:heroSurfaceView.topAnchor constant:12.0],
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

- (void)pp_commandLanguageDidChange:(NSNotification *)notification {
    (void)notification;
    if (!self.isViewLoaded || !UsrMgr.currentUser) return;

    [self pp_rebuildDashboardFormPreservingOffset:YES];
    if (!self.pp_isCommandSpine) {
        [self setupHeaderUIWithUser:UsrMgr.currentUser];
    }
}

- (void)pp_commandAuthorizationDidChange:(NSNotification *)notification {
    (void)notification;
    if (!self.isViewLoaded || !UsrMgr.currentUser) return;

    // Authorization refreshes can turn an early fail-closed listener into a
    // readable source. Tear down the old registrations first so an inert
    // listener returned before PPStaffAuth finished cannot pin readiness in a
    // failed state for the rest of the dashboard lifetime.
    [self pp_stopCommandPriorityFeeds];
    [self pp_rebuildDashboardFormPreservingOffset:YES];
    if (!self.pp_isCommandSpine) {
        [self setupHeaderUIWithUser:UsrMgr.currentUser];
    }
    [self pp_startCommandPriorityFeedsIfNeeded];
}

// PP_ADMIN_COMMAND_SPINE_METHODS_BEGIN

#pragma mark - Command Orbit — Direct Priority

- (void)pp_installCommandOrbitIfNeeded {
    if (self.pp_commandOrbitController) {
        [self.view bringSubviewToFront:self.pp_commandOrbitController.view];
        return;
    }

    AdminCommandOrbitHostingController *commandOrbitController = [AdminCommandOrbitHostingController new];
    __weak typeof(self) weakSelf = self;
    commandOrbitController.onRoute = ^(NSString *tag) {
        [weakSelf pp_handleDashboardActionForTag:tag];
    };
    commandOrbitController.onRefresh = ^(void) {
        [weakSelf refreshCommandFeedsFromUser];
    };
    commandOrbitController.onRequestLogout = ^(void) {
        [weakSelf didTapAuthButton];
    };
    commandOrbitController.onToggleLanguage = ^(void) {
        [weakSelf didTapLanguage];
    };
    commandOrbitController.onSelectTab = ^(NSInteger index) {
        if (weakSelf.tabBarController) {
            weakSelf.tabBarController.selectedIndex = index;
        }
    };

    // Every tracked area starts pending so the surface renders an honest
    // loading state instead of a false "all clear" before feeds confirm.
    NSMutableDictionary<NSString *, NSString *> *feedStatus = [NSMutableDictionary dictionary];
    for (NSString *area in PPAdminCommandTrackedFeedAreas()) {
        feedStatus[area] = kPPAdminCommandFeedPending;
    }
    self.pp_feedStatusByArea = feedStatus;

    [self addChildViewController:commandOrbitController];
    commandOrbitController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:commandOrbitController.view];
    [commandOrbitController didMoveToParentViewController:self];
    self.pp_commandOrbitController = commandOrbitController;

    [NSLayoutConstraint activateConstraints:@[
        [commandOrbitController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [commandOrbitController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [commandOrbitController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [commandOrbitController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    // Keep the legacy XLForm alive as the permission/routing authority, but remove it
    // from the visual/accessibility hierarchy.
    self.tableView.hidden = YES;
    self.tableView.userInteractionEnabled = NO;
    self.tableView.accessibilityElementsHidden = YES;
    self.heroShadowView.hidden = YES;
    self.headerRoot.accessibilityElementsHidden = YES;
    // The command-spine surface is the only visible UI; never let the legacy
    // loading overlay cover the new command center.
    self.dashboardLoadingView.hidden = YES;

    [self.view bringSubviewToFront:commandOrbitController.view];
}

- (NSArray<NSDictionary<NSString *, id> *> *)pp_commandAllowedItems {
    NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *section in self.dashboardSections ?: @[]) {
        NSArray *sectionItems = [section[kPPDashboardSectionItemsKey] isKindOfClass:NSArray.class]
            ? section[kPPDashboardSectionItemsKey]
            : @[];
        for (NSDictionary *item in sectionItems) {
            if ([item isKindOfClass:NSDictionary.class]) [items addObject:item];
        }
    }
    return items.copy;
}

- (NSDictionary<NSString *, id> * _Nullable)pp_commandItemForTag:(NSString *)tag {
    if (tag.length == 0) return nil;
    for (NSDictionary<NSString *, id> *item in [self pp_commandAllowedItems]) {
        if ([item[kPPDashboardItemTagKey] isEqualToString:tag]) return item;
    }
    return nil;
}

- (BOOL)pp_commandAllowsTag:(NSString *)tag {
    return [self pp_commandItemForTag:tag] != nil;
}

- (NSString *)pp_commandModuleTitleForTag:(NSString *)tag {
    NSDictionary *item = [self pp_commandItemForTag:tag];
    NSString *title = [item[kPPDashboardItemTitleKey] isKindOfClass:NSString.class]
        ? item[kPPDashboardItemTitleKey]
        : @"";
    return title.length > 0 ? title : kLang(@"AdminDashboard");
}

- (NSString *)pp_commandIconForTag:(NSString *)tag {
    NSDictionary *item = [self pp_commandItemForTag:tag];
    NSString *icon = [item[kPPDashboardItemIconKey] isKindOfClass:NSString.class]
        ? item[kPPDashboardItemIconKey]
        : @"";
    return icon.length > 0 ? icon : @"square.grid.2x2";
}

- (NSString *)pp_commandCTAForTag:(NSString *)tag {
    NSString *module = [self pp_commandModuleTitleForTag:tag];
    return [NSString stringWithFormat:kLang(@"AdminCommand_Open_Format"), module];
}

- (PPAdminCommandSignal *)pp_commandSignalForTag:(NSString *)tag
                                           title:(NSString *)title
                                          detail:(NSString *)detail
                                         urgency:(NSInteger)urgency
                                           count:(NSInteger)count
                                            live:(BOOL)live {
    return [PPAdminCommandSignal signalWithTag:tag
                                   moduleTitle:[self pp_commandModuleTitleForTag:tag]
                                         title:title
                                        detail:detail
                                      ctaTitle:[self pp_commandCTAForTag:tag]
                                      iconName:[self pp_commandIconForTag:tag]
                                       urgency:urgency
                                         count:count
                                          live:live];
}

- (NSArray<PPAdminCommandSignal *> *)pp_commandLiveSignals {
    NSMutableArray<PPAdminCommandSignal *> *signals = [NSMutableArray array];

    if ([self pp_commandAllowsTag:@"fulfillment"]) {
        NSInteger newCount = 0;
        NSInteger activeCount = 0;
        for (PPFulfillmentRecord *record in self.pp_fulfillmentPriorityRecords ?: @[]) {
            NSString *status = PPAdminCommandNormalizedString(record.status);
            if (!PPAdminCommandStatusIsTerminal(status)) activeCount += 1;
            if ([status isEqualToString:@"new_request"] || PPAdminCommandStatusLooksNew(status)) newCount += 1;
        }
        if (newCount > 0) {
            [signals addObject:[self pp_commandSignalForTag:@"fulfillment"
                                                     title:PPAdminCommandLocalizedCount(@"AdminCommand_Fulfillment_One",
                                                                                      @"AdminCommand_Fulfillment_Many",
                                                                                      newCount)
                                                    detail:kLang(@"AdminCommand_NeedsReview")
                                                   urgency:100
                                                     count:newCount
                                                      live:YES]];
        } else if (activeCount > 0) {
            [signals addObject:[self pp_commandSignalForTag:@"fulfillment"
                                                     title:PPAdminCommandLocalizedCount(@"AdminCommand_Fulfillment_Active_One",
                                                                                      @"AdminCommand_Fulfillment_Active_Many",
                                                                                      activeCount)
                                                    detail:kLang(@"AdminCommand_InProgress")
                                                   urgency:84
                                                     count:activeCount
                                                      live:YES]];
        }
    }

    if ([self pp_commandAllowsTag:@"delivery"]) {
        NSInteger newCount = 0;
        NSInteger activeCount = 0;
        for (PPDeliveryRequestRecord *record in self.pp_deliveryPriorityRecords ?: @[]) {
            NSString *status = PPAdminCommandNormalizedString(record.status);
            if (!PPAdminCommandStatusIsTerminal(status)) activeCount += 1;
            if (PPAdminCommandStatusLooksNew(status)) newCount += 1;
        }
        if (newCount > 0) {
            [signals addObject:[self pp_commandSignalForTag:@"delivery"
                                                     title:PPAdminCommandLocalizedCount(@"AdminCommand_Delivery_One",
                                                                                      @"AdminCommand_Delivery_Many",
                                                                                      newCount)
                                                    detail:kLang(@"AdminCommand_NeedsReview")
                                                   urgency:97
                                                     count:newCount
                                                      live:YES]];
        } else if (activeCount > 0) {
            [signals addObject:[self pp_commandSignalForTag:@"delivery"
                                                     title:PPAdminCommandLocalizedCount(@"AdminCommand_Delivery_Active_One",
                                                                                      @"AdminCommand_Delivery_Active_Many",
                                                                                      activeCount)
                                                    detail:kLang(@"AdminCommand_InProgress")
                                                   urgency:82
                                                     count:activeCount
                                                      live:YES]];
        }
    }

    if ([self pp_commandAllowsTag:@"payments"]) {
        NSInteger openRequestCount = 0;
        NSInteger actionableCount = 0;
        for (PPPaymentAdminRecord *record in self.pp_paymentPriorityRecords ?: @[]) {
            if ([record hasOpenRequests]) openRequestCount += 1;
            NSString *status = [record workflowStatusKey] ?: @"";
            BOOL actionable =
                [PPPaymentAdminRecord canApproveOrderStatus:status] ||
                [PPPaymentAdminRecord canMarkOrderProcessingForOrder:record] ||
                [PPPaymentAdminRecord canMarkOrderShippedStatus:status] ||
                [PPPaymentAdminRecord canMarkOrderDeliveredStatus:status] ||
                [PPPaymentAdminRecord canCancelOrderStatus:status] ||
                [PPPaymentAdminRecord canCollectCashPaymentForOrder:record];
            if (actionable) actionableCount += 1;
        }
        NSInteger count = MAX(openRequestCount, actionableCount);
        if (count > 0) {
            [signals addObject:[self pp_commandSignalForTag:@"payments"
                                                     title:PPAdminCommandLocalizedCount(@"AdminCommand_Payment_One",
                                                                                      @"AdminCommand_Payment_Many",
                                                                                      count)
                                                    detail:kLang(@"AdminCommand_NeedsAdminReview")
                                                   urgency:openRequestCount > 0 ? 96 : 90
                                                     count:count
                                                      live:YES]];
        }
    }

    if ([self pp_commandAllowsTag:@"accessories"]) {
        NSInteger lowStockCount = 0;
        for (PetAccessory *item in self.pp_inventoryPriorityItems ?: @[]) {
            if (item.accessKindType != AccessTypeAccessory) continue;
            if (item.isDeleted || item.isBlocked || item.isDisabled || !item.active) continue;
            if (item.noStock || item.quantity <= 3) lowStockCount += 1;
        }
        if (lowStockCount > 0) {
            [signals addObject:[self pp_commandSignalForTag:@"accessories"
                                                     title:PPAdminCommandLocalizedCount(@"AdminCommand_Stock_One",
                                                                                      @"AdminCommand_Stock_Many",
                                                                                      lowStockCount)
                                                    detail:kLang(@"AdminCommand_CheckQuantity")
                                                   urgency:lowStockCount >= 5 ? 92 : 86
                                                     count:lowStockCount
                                                      live:YES]];
        }
    }

    [signals sortUsingComparator:^NSComparisonResult(PPAdminCommandSignal *left, PPAdminCommandSignal *right) {
        if (left.urgency > right.urgency) return NSOrderedAscending;
        if (left.urgency < right.urgency) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return signals.copy;
}

- (NSArray<PPAdminCommandSignal *> *)pp_commandResolvedSignals {
    NSMutableArray<PPAdminCommandSignal *> *resolved = [[self pp_commandLiveSignals] mutableCopy] ?: [NSMutableArray array];
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (PPAdminCommandSignal *signal in resolved) {
        if (signal.tag.length > 0) [used addObject:signal.tag];
    }

    for (NSDictionary<NSString *, id> *item in [self pp_commandAllowedItems]) {
        if (resolved.count >= 6) break;
        NSString *tag = item[kPPDashboardItemTagKey];
        if (tag.length == 0 || [used containsObject:tag]) continue;

        NSString *title = [item[kPPDashboardItemTitleKey] isKindOfClass:NSString.class]
            ? item[kPPDashboardItemTitleKey]
            : kLang(@"AdminCommand_Ready");
        PPAdminCommandSignal *fallback =
            [self pp_commandSignalForTag:tag
                                  title:title
                                 detail:kLang(@"AdminCommand_Ready")
                                urgency:20
                                  count:0
                                   live:NO];
        [resolved addObject:fallback];
        [used addObject:tag];
    }

    if (resolved.count > 6) {
        return [resolved subarrayWithRange:NSMakeRange(0, 6)];
    }
    return resolved.copy;
}

- (void)pp_refreshCommandOrbitSnapshot {
    if (!self.pp_commandOrbitController || !UsrMgr.currentUser) return;

    NSMutableArray<AdminCommandOrbitSignalDescriptor *> *descriptors = [NSMutableArray array];
    for (PPAdminCommandSignal *signal in [self pp_commandResolvedSignals]) {
        AdminCommandOrbitSignalDescriptor *descriptor = [AdminCommandOrbitSignalDescriptor new];
        descriptor.identifier = signal.tag ?: @"";
        descriptor.moduleTitle = signal.moduleTitle ?: @"";
        descriptor.title = signal.title ?: @"";
        descriptor.detail = signal.detail ?: @"";
        descriptor.symbolName = signal.iconName ?: @"square.grid.2x2";
        descriptor.urgency = signal.urgency;
        descriptor.count = signal.count;
        descriptor.isLive = signal.isLive;
        [descriptors addObject:descriptor];
    }

    [self.pp_commandOrbitController applyRoleName:[self pp_currentRoleDisplayNameForUser:UsrMgr.currentUser]
                                  capabilityCount:self.dashboardActionCount
                                          signals:descriptors
                                         animated:(self.view.window != nil && !UIAccessibilityIsReduceMotionEnabled())];
    [self pp_pushCommandReadiness];
}

/// Derives presentation-only readiness from feed statuses this controller
/// already owns and hands it to the hosting controller. Fixed area order keeps
/// the localized source list deterministic in both directions.
- (void)pp_pushCommandReadiness {
    if (!self.pp_commandOrbitController) return;

    NSMutableArray<NSString *> *loadingAreas = [NSMutableArray array];
    NSMutableArray<NSString *> *failedAreas = [NSMutableArray array];
    for (NSString *area in PPAdminCommandTrackedFeedAreas()) {
        NSString *status = self.pp_feedStatusByArea[area];
        if ([status isEqualToString:kPPAdminCommandFeedPending]) {
            [loadingAreas addObject:area];
        } else if ([status isEqualToString:kPPAdminCommandFeedFailed]) {
            [failedAreas addObject:area];
        }
    }

    [self.pp_commandOrbitController applyReadinessWithLoadingAreas:loadingAreas
                                                       failedAreas:failedAreas
                                                        updatedAt:self.pp_lastFeedConfirmationAt];
}

- (void)pp_setCommandFeedStatus:(NSString *)status forArea:(NSString *)area {
    if (area.length == 0 || self.pp_feedStatusByArea[area] == nil) return;
    self.pp_feedStatusByArea[area] = status;
    if (![status isEqualToString:kPPAdminCommandFeedPending]) {
        self.pp_lastFeedConfirmationAt = [NSDate date];
    }
}

/// Drops areas the current permissions do not allow so readiness never waits
/// on a source this operator can never see.
- (void)pp_pruneUntrackedCommandFeedAreas {
    for (NSString *area in PPAdminCommandTrackedFeedAreas()) {
        BOOL allowed = [self pp_commandAllowsTag:area];
        if (allowed && [area isEqualToString:@"payments"] &&
            ![[PPPaymentManagementService shared] currentAdminCanViewPayments]) {
            allowed = NO;
        }
        if (!allowed) {
            [self.pp_feedStatusByArea removeObjectForKey:area];
        }
    }
}

- (void)pp_startCommandPriorityFeedsIfNeeded {
    if (!self.pp_commandOrbitController || !self.pp_commandSurfaceVisible) return;
    if (!self.pp_priorityFeedsStarted) self.pp_priorityLiveGeneration += 1;
    NSUInteger liveGeneration = self.pp_priorityLiveGeneration;
    [self pp_pruneUntrackedCommandFeedAreas];

    if ([self pp_commandAllowsTag:@"fulfillment"] && !self.pp_fulfillmentPriorityReg) {
        __weak typeof(self) weakSelf = self;
        self.pp_fulfillmentPriorityReg =
            [[PPFulfillmentService shared] observeFulfillmentsWithCompletion:^(NSArray<PPFulfillmentRecord *> *records,
                                                                                BOOL isFromCache,
                                                                                NSError * _Nullable error) {
            (void)isFromCache;
            BOOL isPartialRead = [PPFulfillmentService isPartialReadError:error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf || !weakSelf.pp_commandSurfaceVisible ||
                    liveGeneration != weakSelf.pp_priorityLiveGeneration) return;
                [weakSelf pp_setCommandFeedStatus:(error && !isPartialRead) ? kPPAdminCommandFeedFailed : kPPAdminCommandFeedLoaded
                                          forArea:@"fulfillment"];
                if (error && !isPartialRead) {
                    [weakSelf pp_refreshCommandOrbitSnapshot];
                    return;
                }
                weakSelf.pp_fulfillmentPriorityRecords = records ?: @[];
                [weakSelf pp_refreshCommandOrbitSnapshot];
            });
        }];
    }

    if ([self pp_commandAllowsTag:@"accessories"] && !self.pp_inventoryPriorityReg) {
        __weak typeof(self) weakSelf = self;
        self.pp_inventoryPriorityReg =
            [[AccessoryManager shared] observeAllAccessories:^(NSArray<PetAccessory *> * _Nullable items, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf || !weakSelf.pp_commandSurfaceVisible ||
                    liveGeneration != weakSelf.pp_priorityLiveGeneration) return;
                [weakSelf pp_setCommandFeedStatus:error ? kPPAdminCommandFeedFailed : kPPAdminCommandFeedLoaded
                                          forArea:@"accessories"];
                if (error) {
                    [weakSelf pp_refreshCommandOrbitSnapshot];
                    return;
                }
                weakSelf.pp_inventoryPriorityItems = items ?: @[];
                [weakSelf pp_refreshCommandOrbitSnapshot];
            });
        }];
    }

    self.pp_priorityFeedsStarted = YES;
    [self pp_refreshCommandOneShotFeeds];
}

- (void)pp_refreshCommandOneShotFeeds {
    if (!self.pp_commandOrbitController) return;
    NSUInteger generation = ++self.pp_priorityOneShotGeneration;

    if ([self pp_commandAllowsTag:@"delivery"]) {
        __weak typeof(self) weakSelf = self;
        [[PPDeliveryService shared] fetchCommandCenterWithCompletion:^(PPDeliveryCommandCenterSnapshot *projection, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf || !weakSelf.pp_commandSurfaceVisible ||
                    generation != weakSelf.pp_priorityOneShotGeneration) return;
                [weakSelf pp_setCommandFeedStatus:error ? kPPAdminCommandFeedFailed : kPPAdminCommandFeedLoaded
                                          forArea:@"delivery"];
                if (error) {
                    [weakSelf pp_refreshCommandOrbitSnapshot];
                    return;
                }
                weakSelf.pp_deliveryPriorityRecords = projection.records ?: @[];
                [weakSelf pp_refreshCommandOrbitSnapshot];
            });
        }];
    }

    if ([self pp_commandAllowsTag:@"payments"] &&
        [[PPPaymentManagementService shared] currentAdminCanViewPayments]) {
        __weak typeof(self) weakSelf = self;
        [[PPPaymentManagementService shared] fetchOrdersWithFilters:nil
                                                           pageSize:40
                                                         startAfter:nil
                                                         completion:^(NSArray<PPPaymentAdminRecord *> *records,
                                                                      FIRDocumentSnapshot * _Nullable nextCursor,
                                                                      NSError * _Nullable error) {
            (void)nextCursor;
            BOOL isPartialRead = [PPPaymentManagementService isPartialReadError:error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf || !weakSelf.pp_commandSurfaceVisible ||
                    generation != weakSelf.pp_priorityOneShotGeneration) return;
                [weakSelf pp_setCommandFeedStatus:(error && !isPartialRead) ? kPPAdminCommandFeedFailed : kPPAdminCommandFeedLoaded
                                          forArea:@"payments"];
                if (error && !isPartialRead) {
                    [weakSelf pp_refreshCommandOrbitSnapshot];
                    return;
                }
                weakSelf.pp_paymentPriorityRecords = records ?: @[];
                [weakSelf pp_refreshCommandOrbitSnapshot];
            });
        }];
    }
}

- (void)pp_stopCommandPriorityFeeds {
    [self.pp_fulfillmentPriorityReg remove];
    self.pp_fulfillmentPriorityReg = nil;
    [self.pp_inventoryPriorityReg remove];
    self.pp_inventoryPriorityReg = nil;
    self.pp_priorityLiveGeneration += 1;
    self.pp_priorityOneShotGeneration += 1;
    self.pp_priorityFeedsStarted = NO;
    // Nothing is being confirmed while the surface is offscreen; mark tracked
    // areas pending so returning to the tab shows an honest updating state.
    for (NSString *area in self.pp_feedStatusByArea.allKeys.copy) {
        self.pp_feedStatusByArea[area] = kPPAdminCommandFeedPending;
    }
}

/// User-requested re-confirmation. Healthy live listeners remain attached,
/// while failed live listeners are recreated because Firestore terminates a
/// listener after authorization/query errors. Keeping that inert registration
/// would leave the source failed forever. Stale callbacks remain rejected by
/// the generation checks in pp_stopCommandPriorityFeeds.
- (void)refreshCommandFeedsFromUser {
    if (!self.pp_commandOrbitController) return;

    BOOL fulfillmentFailed = [self.pp_feedStatusByArea[@"fulfillment"] isEqualToString:kPPAdminCommandFeedFailed];
    BOOL inventoryFailed = [self.pp_feedStatusByArea[@"accessories"] isEqualToString:kPPAdminCommandFeedFailed];
    if (fulfillmentFailed || inventoryFailed) {
        [self pp_stopCommandPriorityFeeds];
    }

    if (self.pp_feedStatusByArea[@"delivery"]) {
        self.pp_feedStatusByArea[@"delivery"] = kPPAdminCommandFeedPending;
    }
    if (self.pp_feedStatusByArea[@"payments"]) {
        self.pp_feedStatusByArea[@"payments"] = kPPAdminCommandFeedPending;
    }
    [self pp_refreshCommandOrbitSnapshot];
    [self pp_startCommandPriorityFeedsIfNeeded];
}

// PP_ADMIN_COMMAND_SPINE_METHODS_END


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
    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermPaymentsView, kStaffPermPaymentsManage, kStaffPermProvidersView]]) {
        NSArray *items = @[[self pp_itemWithTag:@"fulfillment"
                                       titleKey:@"Fulfillment_Title"
                                    subtitleKey:@"Fulfillment_Subtitle"
                                       iconName:@"shippingbox"]];
        [sections addObject:[self pp_sectionWithTitleKey:@"Fulfillment_Title"
                                          descriptionKey:@"Fulfillment_Subtitle"
                                                   items:items]];
        actionCount += items.count;
    }
    if ([self pp_canAccessAnyPermissions:@[kPermAdminAll, kStaffPermDeliveryView, kStaffPermPaymentsManage]]) {
        NSArray *items = @[[self pp_itemWithTag:@"delivery"
                                       titleKey:@"Delivery_Title"
                                    subtitleKey:@"Delivery_Subtitle"
                                       iconName:@"truck.box"]];
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
    }
    PPStaffDoc *providerLedgerStaff = [PPStaffAuth shared].cachedCurrentStaff;
    if ((providerLedgerStaff.isAdmin || providerLedgerStaff.hasGlobalScope) &&
        [providerLedgerStaff hasAnyPermission:@[kStaffPermPaymentsView, kStaffPermPaymentsManage]]) {
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

    PPStaffDoc *auditStaff = [PPStaffAuth shared].cachedCurrentStaff;
    if ((auditStaff.isAdmin || auditStaff.hasGlobalScope) &&
        [auditStaff hasPermission:kStaffPermAuditView]) {
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
        return [PPInventoryListHostingController makeForAccessories];
    }
    if ([tag isEqualToString:@"food"]) {
        return [PPInventoryListHostingController makeForFood];
    }
    if ([tag isEqualToString:@"livePets"]) {
        return [PPInventoryListHostingController makeForLivePets];
    }
    if ([tag isEqualToString:@"services"]) {
        return [PPServicesListViewController new];
    }
    if ([tag isEqualToString:@"vets"]) {
        return [PPVetsListHostingController new];
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
        return [AdminPaymentListHostingController new];
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
        return [PPProviderApplicationsHostingController new];
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
        UIViewController *vc = [AdminPOSFastSellHostingController new];
        vc.hidesBottomBarWhenPushed = YES;
        return vc;
    }
    if ([tag isEqualToString:@"posHistory"]) {
        UIViewController *vc = [AdminPOSHistoryHostingController new];
        vc.hidesBottomBarWhenPushed = YES;
        return vc;
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

    PPAdminProfileViewController *editor = [[PPAdminProfileViewController alloc] initWithUser:UsrMgr.currentUser];
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
        [loadingView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
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
    [PPAlertHelper showConfirmationIn:self
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
    [PPAlertHelper showConfirmationIn:self
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
    if (self.pp_isCommandSpine) {
        // Command-spine surface: keep the dashboard data model (permissions,
        // priority derivation) but never build or render the legacy XLForm UI.
        self.dashboardSections = [self pp_resolvedDashboardSections];
        if (!self.form) {
            self.form = [XLFormDescriptor formDescriptor];
        }
        [self pp_refreshCommandOrbitSnapshot];
        return;
    }
    CGPoint previousOffset = self.tableView.contentOffset;
    self.form = [self buildLoginForm];
    [self.tableView reloadData];
    [self pp_refreshHeroCopy];
    [self pp_refreshCommandOrbitSnapshot];

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
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *currentUID = [FIRAuth auth].currentUser.uid;
    if (!staff || currentUID.length == 0 || ![staff.uid isEqualToString:currentUID]) {
        return NO;
    }
    if ([staff hasPermission:permKey]) {
        return YES;
    }
    NSArray<NSString *> *canonicalPermissions =
        PPAdminDashboardCanonicalPermissionsForLegacyPermission(permKey);
    return canonicalPermissions.count > 0 && [staff hasAnyPermission:canonicalPermissions];
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
