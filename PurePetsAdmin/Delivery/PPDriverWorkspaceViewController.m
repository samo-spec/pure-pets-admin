#import "PPDriverWorkspaceViewController.h"
#import "PPDriverWorkspaceService.h"
#import "PPDesignTokens.h"
#import "Language.h"
#import "Styling.h"
#import "PPFirebaseCompat.h"
#import "UIViewController+PPNavBar.h"
#import "PurePetsAdmin-Swift.h"

#import <UserNotifications/UserNotifications.h>
#import <MapKit/MapKit.h>
#import <QuartzCore/QuartzCore.h>

NSString * const PPAdminRouteToDriverTaskNotification = @"PPAdminRouteToDriverTaskNotification";
NSString * const PPDriverTasksDidChangeNotification = @"PPDriverTasksDidChangeNotification";

static NSDictionary *DDict(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }
static NSString *DText(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSArray *DArray(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static BOOL DFlag(id value) { return [value isKindOfClass:NSNumber.class] && [value boolValue]; }
static NSString *DL(NSString *key) { return kLang(key); }

NSDictionary<NSString *,NSString *> *PPDriverTaskRoute(NSDictionary *payload) {
    NSDictionary *root = DDict(payload), *meta = DDict(root[@"meta"]);
    NSString *route = DText(root[@"route"] ?: meta[@"route"]);
    NSString *target = DText(root[@"targetAppId"] ?: root[@"appId"] ?: root[@"targetApp"] ?: meta[@"targetAppId"]);
    NSString *task = DText(root[@"taskId"] ?: meta[@"taskId"] ?: root[@"requestId"] ?: meta[@"requestId"]);
    NSString *authority = DText(root[@"authority"] ?: meta[@"authority"]);
    if (![route isEqualToString:@"driver_task"] || (target.length && ![target isEqualToString:@"admin_ios"]) ||
        !task.length || task.length > 128 || [task containsString:@"/"] ||
        ![@[@"FULFILLMENT_V1",@"COMPANY_DELIVERY_REQUEST"] containsObject:authority]) return @{};
    return @{ @"taskId":task, @"authority":authority };
}

static UIFont *DFont(CGFloat size, BOOL bold, UIFontTextStyle style) {
    UIFont *font = bold ? [Styling fontBold:size] : [Styling fontRegular:size];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:font ?: [UIFont systemFontOfSize:size]];
}

static UILabel *DLabel(NSString *text, CGFloat size, BOOL bold, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = DFont(size, bold, size >= 25 ? UIFontTextStyleTitle1 : UIFontTextStyleBody);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.textAlignment = [Language alignmentForCurrentLanguage];
    return label;
}

static UIStackView *DStack(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;
    return stack;
}

static NSString *DAddress(NSDictionary *address) {
    NSDictionary *branchName = DDict(address[@"branchName"]);
    if (branchName.count) {
        NSString *name = Language.isRTL ? DText(branchName[@"ar"]) : DText(branchName[@"en"]);
        if (!name.length) name = DText(branchName[@"ar"]).length ? DText(branchName[@"ar"]) : DText(branchName[@"en"]);
        if (name.length) return name;
    }
    for (NSString *key in @[@"formattedAddress",@"fullAddress",@"address",@"addressLine1",@"locationName",@"locatioName",@"label"]) {
        if (DText(address[key]).length) return DText(address[key]);
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"buildingNumber",@"streetName",@"street",@"zoneNumber",@"area",@"city",@"country"]) {
        id value = address[key]; NSString *part = DText(value);
        if ([value isKindOfClass:NSNumber.class]) part = [value stringValue];
        if (part.length && ![parts containsObject:part]) [parts addObject:part];
    }
    return parts.count ? [parts componentsJoinedByString:@" · "] : DL(@"Driver_Address_Pending");
}

static NSString *DStatus(NSString *status) {
    NSDictionary *keys = @{
        @"delivery_requested": @"Driver_Status_New",
        @"accepted_by_company": @"Driver_Status_New",
        @"delivery_assigned": @"Driver_Status_Handover",
        @"awaiting_handover": @"Driver_Status_Pickup",
        @"assigned_to_driver": @"Driver_Status_Pickup",
        @"handed_over": @"Driver_Status_Collected",
        @"picked_up": @"Driver_Status_Collected",
        @"in_transit": @"Driver_Status_Transit",
        @"delivered": @"Driver_Status_Delivered",
        @"payment_pending": @"Driver_Status_Payment",
        @"payment_confirmed": @"Driver_Status_Paid",
        @"completed": @"Driver_Status_Complete",
        @"cancelled": @"Driver_Status_Cancelled",
        @"failed": @"Driver_Status_Attention",
        @"returned": @"Driver_Status_Returned",
        @"rejected": @"Driver_Status_Cancelled"
    };
    return DL(keys[status] ?: @"Driver_Status_Updated");
}

static UIColor *DStatusColor(NSString *status) {
    if ([@[@"delivered", @"completed", @"payment_confirmed"] containsObject:status]) {
        return UIColor.ppSuccess;
    }
    if ([@[@"in_transit", @"handed_over", @"picked_up"] containsObject:status]) {
        return [UIColor colorWithRed:0.18 green:0.48 blue:0.96 alpha:1.0];
    }
    if ([@[@"delivery_assigned", @"awaiting_handover", @"assigned_to_driver", @"delivery_requested"] containsObject:status]) {
        return UIColor.ppWarning;
    }
    if ([@[@"cancelled", @"failed", @"rejected", @"returned"] containsObject:status]) {
        return UIColor.ppError;
    }
    return UIColor.ppPrimary;
}

static NSString *DAction(NSString *action) {
    return DL(@{
        @"CLAIM": @"Driver_Action_Claim",
        @"PICK_UP": @"Driver_Action_Pickup",
        @"START_TRANSIT": @"Driver_Action_Transit",
        @"DELIVER": @"Driver_Action_Deliver",
        @"CONFIRM_PAYMENT": @"Driver_Action_Cash",
        @"COMPLETE": @"Driver_Action_Complete"
    }[action] ?: @"Driver_Open");
}

#pragma mark - Telemetry Pulse Beacon

@interface PPDriverPulseBeaconView : UIView
@property(nonatomic, strong) UIView *coreDot;
@property(nonatomic, strong) UIView *pulseRing;
@property(nonatomic, strong) UIColor *beaconColor;
@property(nonatomic, assign) BOOL isPulsing;
- (void)setBeaconColor:(UIColor *)color pulsing:(BOOL)pulsing;
@end

@implementation PPDriverPulseBeaconView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _pulseRing = [UIView new];
        _pulseRing.translatesAutoresizingMaskIntoConstraints = NO;
        _pulseRing.layer.cornerRadius = 9;
        _pulseRing.alpha = 0;
        [self addSubview:_pulseRing];

        _coreDot = [UIView new];
        _coreDot.translatesAutoresizingMaskIntoConstraints = NO;
        _coreDot.layer.cornerRadius = 4;
        _coreDot.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_coreDot];

        [NSLayoutConstraint activateConstraints:@[
            [_coreDot.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_coreDot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_coreDot.widthAnchor constraintEqualToConstant:8],
            [_coreDot.heightAnchor constraintEqualToConstant:8],

            [_pulseRing.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_pulseRing.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pulseRing.widthAnchor constraintEqualToConstant:18],
            [_pulseRing.heightAnchor constraintEqualToConstant:18]
        ]];
    }
    return self;
}

- (void)setBeaconColor:(UIColor *)color pulsing:(BOOL)pulsing {
    _beaconColor = color ?: UIColor.ppPrimary;
    _isPulsing = pulsing;
    _coreDot.backgroundColor = _beaconColor;
    _pulseRing.backgroundColor = [_beaconColor colorWithAlphaComponent:0.35];

    [_pulseRing.layer removeAllAnimations];
    if (pulsing && !UIAccessibilityIsReduceMotionEnabled()) {
        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.duration = 1.6;
        group.repeatCount = HUGE_VALF;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];

        CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scale.fromValue = @(0.7);
        scale.toValue = @(2.1);

        CABasicAnimation *opacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
        opacity.fromValue = @(0.65);
        opacity.toValue = @(0.0);

        group.animations = @[scale, opacity];
        [_pulseRing.layer addAnimation:group forKey:@"beacon_pulse"];
    } else {
        _pulseRing.alpha = 0;
    }
}

@end

#pragma mark - Category-Defining Task Cell

@interface PPDriverTaskCell : UITableViewCell
@property(nonatomic, strong) UIView *cardView;
@property(nonatomic, copy, nullable) void (^onNavigate)(void);
@property(nonatomic, copy, nullable) void (^onCall)(void);
- (void)render:(NSDictionary *)task focused:(BOOL)focused detail:(BOOL)detail;
@end

@implementation PPDriverTaskCell

- (void)render:(NSDictionary *)task focused:(BOOL)focused detail:(BOOL)detail {
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    [PPDriverTaskCellBridge configureWithCell:self
                                         task:DDict(task)
                                      focused:focused
                                       detail:detail];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    UIView *target = self.cardView ?: self.contentView;
    [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.2 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        target.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - Main Driver Workspace Controller

@interface PPDriverWorkspaceViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, copy) NSString *taskID;
@property(nonatomic, copy) NSString *authority;
@property(nonatomic, copy) NSString *uid;
@property(nonatomic, copy) NSString *lane;
@property(nonatomic, strong) PPDriverWorkspaceService *service;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) UIStackView *header;
@property(nonatomic, strong) UIView *lanesContainer;
@property(nonatomic, strong) UIView *laneHighlightView;
@property(nonatomic, strong) NSLayoutConstraint *laneHighlightLeading;
@property(nonatomic, strong) NSMutableArray<UIButton *> *laneButtons;
@property(nonatomic, strong) NSMutableArray<UILabel *> *laneBadgeLabels;
@property(nonatomic, strong) UIStackView *detailActions;
@property(nonatomic, strong) UIStackView *feedback;
@property(nonatomic, strong) UIControl *availabilityCard;
@property(nonatomic, strong) PPDriverPulseBeaconView *availabilityBeacon;
@property(nonatomic, strong) UILabel *availabilityTitleLabel;
@property(nonatomic, strong) UILabel *availabilitySubtitleLabel;
@property(nonatomic, strong) UILabel *availabilityDispatchLabel;
@property(nonatomic, strong) UILabel *availabilityAccountLabel;
@property(nonatomic, strong) UILabel *availabilityShiftLabel;
@property(nonatomic, strong) UILabel *availabilityWorkLabel;
@property(nonatomic, strong) UILabel *availabilityBlockerLabel;
@property(nonatomic, strong) UIImageView *availabilityChevron;
@property(nonatomic, strong) UIView *availabilityActionRow;
@property(nonatomic, strong) UIButton *callDispatchButton;
@property(nonatomic, strong) UIButton *checkStatusButton;
@property(nonatomic, strong) UIView *navBarContainer;
@property(nonatomic, strong) UIVisualEffectView *navBlurView;
@property(nonatomic, strong) UIView *topBar;
@property(nonatomic, strong) UIButton *backButton;
@property(nonatomic, strong) PPDriverPulseBeaconView *topBeaconDot;
@property(nonatomic, strong) UIButton *utilityButton;
@property(nonatomic, strong) NSDictionary *availability;
@property(nonatomic, assign) BOOL pendingAvailability;
@property(nonatomic, strong) UIStackView *dock;
@property(nonatomic, strong) NSArray<NSDictionary *> *tasks;
@property(nonatomic, strong) NSDictionary *cursor;
@property(nonatomic, strong) NSDictionary *pendingCommand;
@property(nonatomic, strong) NSTimer *refreshTimer;
@property(nonatomic, assign) BOOL loading;
@property(nonatomic, assign) BOOL submitting;
@property(nonatomic, assign) BOOL hasMore;
@property(nonatomic, assign) BOOL showingAdditionalPages;
@property(nonatomic, assign) BOOL visible;
@property(nonatomic, assign) NSUInteger generation;
@end

@implementation PPDriverWorkspaceViewController

- (instancetype)initWithTaskID:(NSString *)taskID authority:(NSString *)authority {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _taskID = taskID.copy ?: @"";
        _authority = authority.copy ?: @"";
        _lane = @"active";
        _tasks = @[];
        _service = [PPDriverWorkspaceService new];
        _laneButtons = [NSMutableArray array];
        _laneBadgeLabels = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.uid = FIRAuth.auth.currentUser.uid ?: @"";
    self.view.backgroundColor = UIColor.ppBackground;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;

    // --- Frosted Pinned Sovereign Navigation Bar ---
    UIView *navBarContainer = [UIView new];
    navBarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    navBarContainer.backgroundColor = [UIColor.ppBackground colorWithAlphaComponent:0.92];
    navBarContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.navBarContainer = navBarContainer;
    [self.view addSubview:navBarContainer];

    // Subtle blur backdrop
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    self.navBlurView = blurView;
    [navBarContainer addSubview:blurView];

    UIView *topHairline = [UIView new];
    topHairline.translatesAutoresizingMaskIntoConstraints = NO;
    topHairline.backgroundColor = [UIColor.ppSurfaceBorder colorWithAlphaComponent:0.65];
    [navBarContainer addSubview:topHairline];

    UIView *topBar = [UIView new];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    topBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.topBar = topBar;
    [navBarContainer addSubview:topBar];

    // Leading Back Button with Squircle Highlight
    UIButton *backBtn = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(handleBackAction)];
    backBtn.accessibilityLabel = DL(@"Driver_Back");
    backBtn.layer.cornerRadius = 14;
    backBtn.layer.cornerCurve = kCACornerCurveContinuous;
    self.backButton = backBtn;
    [topBar addSubview:backBtn];

    // Fleet Subtitle Beacon Pill
    UIView *beaconPill = [UIView new];
    beaconPill.translatesAutoresizingMaskIntoConstraints = NO;
    beaconPill.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.08];
    beaconPill.layer.cornerRadius = 14;
    beaconPill.layer.cornerCurve = kCACornerCurveContinuous;
    beaconPill.layer.borderWidth = 1.0;
    beaconPill.layer.borderColor = [UIColor.ppPrimary colorWithAlphaComponent:0.20].CGColor;

    PPDriverPulseBeaconView *topBeacon = [[PPDriverPulseBeaconView alloc] initWithFrame:CGRectZero];
    [topBeacon setBeaconColor:UIColor.ppPrimary pulsing:YES];
    self.topBeaconDot = topBeacon;
    [beaconPill addSubview:topBeacon];

    UILabel *caption = DLabel(DL(self.taskID.length ? @"Driver_Task_Subtitle" : @"Driver_Workspace_Subtitle"), 12, YES, UIColor.ppPrimary);
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [beaconPill addSubview:caption];

    [NSLayoutConstraint activateConstraints:@[
        [topBeacon.leadingAnchor constraintEqualToAnchor:beaconPill.leadingAnchor constant:10],
        [topBeacon.centerYAnchor constraintEqualToAnchor:beaconPill.centerYAnchor],
        [topBeacon.widthAnchor constraintEqualToConstant:14],
        [topBeacon.heightAnchor constraintEqualToConstant:14],
        [caption.leadingAnchor constraintEqualToAnchor:topBeacon.trailingAnchor constant:6],
        [caption.trailingAnchor constraintEqualToAnchor:beaconPill.trailingAnchor constant:-12],
        [caption.topAnchor constraintEqualToAnchor:beaconPill.topAnchor constant:5],
        [caption.bottomAnchor constraintEqualToAnchor:beaconPill.bottomAnchor constant:-5]
    ]];
    [topBar addSubview:beaconPill];

    // Trailing Action Squircle Button (Notifications)
    UIButton *utility = [UIButton buttonWithType:UIButtonTypeSystem];
    utility.translatesAutoresizingMaskIntoConstraints = NO;
    utility.backgroundColor = [UIColor ppSurface];
    utility.layer.cornerRadius = 14;
    utility.layer.cornerCurve = kCACornerCurveContinuous;
    utility.layer.borderWidth = 0.8;
    utility.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
    utility.layer.shadowColor = UIColor.blackColor.CGColor;
    utility.layer.shadowOpacity = 0.04;
    utility.layer.shadowOffset = CGSizeMake(0, 2);
    utility.layer.shadowRadius = 6;
    utility.layer.masksToBounds = NO;
    utility.tintColor = UIColor.ppTextPrimary;
    UIImage *utilIcon = [UIImage systemImageNamed:@"bell.fill"];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold];
    UIImage *configuredIcon = [utilIcon imageByApplyingSymbolConfiguration:config] ?: utilIcon;
    [utility setImage:configuredIcon forState:UIControlStateNormal];
    [utility addTarget:self action:@selector(utilityTapped) forControlEvents:UIControlEventTouchUpInside];
    utility.accessibilityLabel = DL(@"Driver_Notifications");
    self.utilityButton = utility;
    utility.hidden = !self.onNotifications;
    [topBar addSubview:utility];

    [NSLayoutConstraint activateConstraints:@[
        [blurView.leadingAnchor constraintEqualToAnchor:navBarContainer.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:navBarContainer.trailingAnchor],
        [blurView.topAnchor constraintEqualToAnchor:navBarContainer.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:navBarContainer.bottomAnchor],

        [topHairline.leadingAnchor constraintEqualToAnchor:navBarContainer.leadingAnchor],
        [topHairline.trailingAnchor constraintEqualToAnchor:navBarContainer.trailingAnchor],
        [topHairline.bottomAnchor constraintEqualToAnchor:navBarContainer.bottomAnchor],
        [topHairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],

        [backBtn.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor],
        [backBtn.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [backBtn.widthAnchor constraintEqualToConstant:44],
        [backBtn.heightAnchor constraintEqualToConstant:44],

        [beaconPill.leadingAnchor constraintEqualToAnchor:backBtn.trailingAnchor constant:10],
        [beaconPill.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [beaconPill.trailingAnchor constraintLessThanOrEqualToAnchor:utility.leadingAnchor constant:-8],
        [beaconPill.heightAnchor constraintEqualToConstant:28],

        [utility.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor],
        [utility.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [utility.widthAnchor constraintEqualToConstant:44],
        [utility.heightAnchor constraintEqualToConstant:44],

        [topBar.heightAnchor constraintEqualToConstant:44],

        [navBarContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [navBarContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [navBarContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [navBarContainer.bottomAnchor constraintEqualToAnchor:topBar.bottomAnchor constant:10],

        [topBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:navBarContainer.leadingAnchor constant:16],
        [topBar.trailingAnchor constraintEqualToAnchor:navBarContainer.trailingAnchor constant:-16]
    ]];

    // --- Hero Header Architecture ---
    UIStackView *header = DStack(@[], 14);
    self.header = header;
    header.layoutMargins = UIEdgeInsetsMake(12, 18, 14, 18);
    header.layoutMarginsRelativeArrangement = YES;

    // Commanding Hero Title & Shift Badge Stack
    UIStackView *heroStack = DStack(@[], 4);

    UILabel *shiftBadge = DLabel(DL(@"Driver_Shift_Badge"), 12.5, YES, UIColor.ppTextSecondary);
    [heroStack addArrangedSubview:shiftBadge];

    UILabel *heading = DLabel(DL(self.taskID.length ? @"Driver_Task_Title" : @"Driver_Title"), 32, YES, UIColor.ppTextPrimary);
    heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    [heroStack addArrangedSubview:heading];

    [header addArrangedSubview:heroStack];

    // Main Run Sheet Controls (Lanes & Cockpit Availability Card)
    if (!self.taskID.length) {
        // --- Fluid Liquid Segmented Lanes Dock ---
        UIView *lanesContainer = [UIView new];
        lanesContainer.translatesAutoresizingMaskIntoConstraints = NO;
        lanesContainer.backgroundColor = UIColor.ppSecondarySurface;
        lanesContainer.layer.cornerRadius = 18;
        lanesContainer.layer.cornerCurve = kCACornerCurveContinuous;
        lanesContainer.layer.borderWidth = 1.0;
        lanesContainer.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
        lanesContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.lanesContainer = lanesContainer;

        // Sliding Highlight Pill
        UIView *highlight = [UIView new];
        highlight.translatesAutoresizingMaskIntoConstraints = NO;
        highlight.backgroundColor = UIColor.ppSurface;
        highlight.layer.cornerRadius = 14;
        highlight.layer.cornerCurve = kCACornerCurveContinuous;
        highlight.layer.shadowColor = UIColor.ppShadow.CGColor;
        highlight.layer.shadowOpacity = 0.08;
        highlight.layer.shadowOffset = CGSizeMake(0, 2);
        highlight.layer.shadowRadius = 6;
        highlight.layer.borderWidth = 0.5;
        highlight.layer.borderColor = [UIColor.ppSurfaceBorder colorWithAlphaComponent:0.6].CGColor;
        [lanesContainer addSubview:highlight];
        self.laneHighlightView = highlight;

        UIStackView *lanesStack = [[UIStackView alloc] init];
        lanesStack.translatesAutoresizingMaskIntoConstraints = NO;
        lanesStack.axis = UILayoutConstraintAxisHorizontal;
        lanesStack.distribution = UIStackViewDistributionFillEqually;
        lanesStack.spacing = 4;
        lanesStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [lanesContainer addSubview:lanesStack];

        NSLayoutConstraint *hlLeading = [highlight.leadingAnchor constraintEqualToAnchor:lanesContainer.leadingAnchor constant:4];
        self.laneHighlightLeading = hlLeading;

        [NSLayoutConstraint activateConstraints:@[
            hlLeading,
            [highlight.topAnchor constraintEqualToAnchor:lanesContainer.topAnchor constant:4],
            [highlight.bottomAnchor constraintEqualToAnchor:lanesContainer.bottomAnchor constant:-4],
            [highlight.widthAnchor constraintEqualToAnchor:lanesContainer.widthAnchor multiplier:1.0/3.0 constant:-2.66],

            [lanesStack.leadingAnchor constraintEqualToAnchor:lanesContainer.leadingAnchor constant:4],
            [lanesStack.trailingAnchor constraintEqualToAnchor:lanesContainer.trailingAnchor constant:-4],
            [lanesStack.topAnchor constraintEqualToAnchor:lanesContainer.topAnchor constant:4],
            [lanesStack.bottomAnchor constraintEqualToAnchor:lanesContainer.bottomAnchor constant:-4],
            [lanesContainer.heightAnchor constraintEqualToConstant:48]
        ]];

        NSArray *laneTitles = @[@"Driver_Lane_Active", @"Driver_Lane_New", @"Driver_Lane_History"];
        NSArray *laneSymbols = @[@"shippingbox.fill", @"plus.circle.fill", @"checkmark.circle.fill"];
        for (NSInteger i = 0; i < 3; i++) {
            UIButton *laneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            laneBtn.tag = i;
            laneBtn.layer.cornerRadius = 14;
            laneBtn.layer.cornerCurve = kCACornerCurveContinuous;

            UIImage *symbolImg = [[UIImage systemImageNamed:laneSymbols[i]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [laneBtn setImage:symbolImg forState:UIControlStateNormal];
            [laneBtn setTitle:DL(laneTitles[i]) forState:UIControlStateNormal];
            laneBtn.titleLabel.font = DFont(13.5, YES, UIFontTextStyleSubheadline);
            laneBtn.titleLabel.adjustsFontForContentSizeCategory = YES;
            laneBtn.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 6 : -6, 0, [Language isRTL] ? -6 : 6);

            [laneBtn addTarget:self action:@selector(laneTapped:) forControlEvents:UIControlEventTouchUpInside];
            [lanesStack addArrangedSubview:laneBtn];
            [self.laneButtons addObject:laneBtn];
        }
        [self updateLaneButtonAppearancesAnimated:NO];
        [header addArrangedSubview:lanesContainer];

        // --- Sovereign Driver Fleet Availability & Telemetry Cockpit Card ---
        UIControl *availCard = [UIControl new];
        availCard.translatesAutoresizingMaskIntoConstraints = NO;
        availCard.backgroundColor = UIColor.ppElevatedSurface;
        availCard.layer.cornerRadius = 22;
        availCard.layer.cornerCurve = kCACornerCurveContinuous;
        availCard.layer.borderWidth = 1.0;
        availCard.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
        availCard.layer.shadowColor = UIColor.ppShadow.CGColor;
        availCard.layer.shadowOpacity = 0.05;
        availCard.layer.shadowOffset = CGSizeMake(0, 4);
        availCard.layer.shadowRadius = 10;
        [availCard addTarget:self action:@selector(toggleAvailability) forControlEvents:UIControlEventTouchUpInside];
        self.availabilityCard = availCard;

        // Internal Master Stack
        UIStackView *cardInnerStack = DStack(@[], 12);
        cardInnerStack.translatesAutoresizingMaskIntoConstraints = NO;
        [availCard addSubview:cardInnerStack];

        // Top Status Header Row
        UIView *statusRow = [UIView new];
        statusRow.translatesAutoresizingMaskIntoConstraints = NO;

        UIView *dotHousing = [UIView new];
        dotHousing.translatesAutoresizingMaskIntoConstraints = NO;
        dotHousing.backgroundColor = [UIColor.ppTextSecondary colorWithAlphaComponent:0.10];
        dotHousing.layer.cornerRadius = 20;
        dotHousing.layer.cornerCurve = kCACornerCurveContinuous;
        [statusRow addSubview:dotHousing];

        PPDriverPulseBeaconView *availBeacon = [[PPDriverPulseBeaconView alloc] initWithFrame:CGRectZero];
        [availBeacon setBeaconColor:UIColor.ppWarning pulsing:YES];
        self.availabilityBeacon = availBeacon;
        [dotHousing addSubview:availBeacon];

        UIStackView *labelStack = [UIStackView new];
        labelStack.translatesAutoresizingMaskIntoConstraints = NO;
        labelStack.axis = UILayoutConstraintAxisVertical;
        labelStack.spacing = 4;
        labelStack.alignment = UIStackViewAlignmentFill;

        UILabel *titleLbl = DLabel(DL(@"Driver_Availability_Loading"), 17, YES, UIColor.ppTextPrimary);
        titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
        self.availabilityTitleLabel = titleLbl;

        UILabel *subLbl = DLabel(DL(@"Driver_Fleet_Pending_Subtitle"), 13.5, NO, UIColor.ppTextSecondary);
        subLbl.translatesAutoresizingMaskIntoConstraints = NO;
        self.availabilitySubtitleLabel = subLbl;

        [labelStack addArrangedSubview:titleLbl];
        [labelStack addArrangedSubview:subLbl];
        [statusRow addSubview:labelStack];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
        chevron.tintColor = UIColor.ppTextSecondary;
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        [statusRow addSubview:chevron];
        self.availabilityChevron = chevron;

        [NSLayoutConstraint activateConstraints:@[
            [dotHousing.leadingAnchor constraintEqualToAnchor:statusRow.leadingAnchor],
            [dotHousing.topAnchor constraintEqualToAnchor:statusRow.topAnchor],
            [dotHousing.widthAnchor constraintEqualToConstant:44],
            [dotHousing.heightAnchor constraintEqualToConstant:44],

            [availBeacon.centerXAnchor constraintEqualToAnchor:dotHousing.centerXAnchor],
            [availBeacon.centerYAnchor constraintEqualToAnchor:dotHousing.centerYAnchor],
            [availBeacon.widthAnchor constraintEqualToConstant:22],
            [availBeacon.heightAnchor constraintEqualToConstant:22],

            [labelStack.leadingAnchor constraintEqualToAnchor:dotHousing.trailingAnchor constant:12],
            [labelStack.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8],
            [labelStack.topAnchor constraintEqualToAnchor:statusRow.topAnchor constant:2],
            [labelStack.bottomAnchor constraintEqualToAnchor:statusRow.bottomAnchor constant:-2],

            [chevron.trailingAnchor constraintEqualToAnchor:statusRow.trailingAnchor constant:-2],
            [chevron.centerYAnchor constraintEqualToAnchor:dotHousing.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:14],
            [chevron.heightAnchor constraintEqualToConstant:14]
        ]];
        [cardInnerStack addArrangedSubview:statusRow];

        // Operational states are read-only: a driver's presence switch cannot
        // undo a dispatcher pause, reactivate membership, or end a shift.
        UIStackView *operationalStates = DStack(@[], 8);
        operationalStates.layoutMargins = UIEdgeInsetsMake(12, 14, 12, 14);
        operationalStates.layoutMarginsRelativeArrangement = YES;
        operationalStates.backgroundColor = [UIColor.ppSecondarySurface colorWithAlphaComponent:0.85];
        operationalStates.layer.cornerRadius = 16;
        operationalStates.layer.cornerCurve = kCACornerCurveContinuous;
        operationalStates.layer.borderWidth = 0.8;
        operationalStates.layer.borderColor = [UIColor.ppSurfaceBorder colorWithAlphaComponent:0.6].CGColor;
        self.availabilityDispatchLabel = DLabel(@"", 13, YES, UIColor.ppTextPrimary);
        self.availabilityDispatchLabel.accessibilityIdentifier = @"driver.availability.dispatch";
        self.availabilityAccountLabel = DLabel(@"", 12.5, NO, UIColor.ppTextSecondary);
        self.availabilityAccountLabel.accessibilityIdentifier = @"driver.availability.account";
        self.availabilityShiftLabel = DLabel(@"", 12.5, NO, UIColor.ppTextSecondary);
        self.availabilityShiftLabel.accessibilityIdentifier = @"driver.availability.shift";
        self.availabilityWorkLabel = DLabel(@"", 12.5, NO, UIColor.ppTextSecondary);
        self.availabilityWorkLabel.accessibilityIdentifier = @"driver.availability.work";
        for (UILabel *state in @[self.availabilityDispatchLabel, self.availabilityAccountLabel,
                                  self.availabilityShiftLabel, self.availabilityWorkLabel]) {
            [operationalStates addArrangedSubview:state];
        }
        self.availabilityBlockerLabel = DLabel(@"", 12.5, YES, UIColor.ppWarning);
        self.availabilityBlockerLabel.hidden = YES;
        [operationalStates addArrangedSubview:self.availabilityBlockerLabel];
        [cardInnerStack addArrangedSubview:operationalStates];

        // Fleet Pending Action Buttons Row (Direct Call to Dispatch & Check Status)
        UIView *actionRow = [UIView new];
        actionRow.translatesAutoresizingMaskIntoConstraints = NO;
        self.availabilityActionRow = actionRow;

        UIButton *callBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        callBtn.translatesAutoresizingMaskIntoConstraints = NO;
        callBtn.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.10];
        callBtn.tintColor = UIColor.ppPrimary;
        callBtn.layer.cornerRadius = 16;
        callBtn.layer.cornerCurve = kCACornerCurveContinuous;
        [callBtn setTitle:DL(@"Driver_Fleet_Call_Dispatch") forState:UIControlStateNormal];
        [callBtn setImage:[UIImage systemImageNamed:@"phone.fill"] forState:UIControlStateNormal];
        callBtn.titleLabel.font = DFont(13.5, YES, UIFontTextStyleHeadline);
        callBtn.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 6 : -6, 0, [Language isRTL] ? -6 : 6);
        [callBtn addTarget:self action:@selector(callDispatch) forControlEvents:UIControlEventTouchUpInside];
        self.callDispatchButton = callBtn;
        [actionRow addSubview:callBtn];

        UIButton *recheckBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        recheckBtn.translatesAutoresizingMaskIntoConstraints = NO;
        recheckBtn.backgroundColor = [UIColor.ppSecondarySurface colorWithAlphaComponent:0.9];
        recheckBtn.tintColor = UIColor.ppTextPrimary;
        recheckBtn.layer.cornerRadius = 16;
        recheckBtn.layer.cornerCurve = kCACornerCurveContinuous;
        recheckBtn.layer.borderWidth = 0.8;
        recheckBtn.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
        [recheckBtn setTitle:DL(@"Driver_Fleet_Refresh_Status") forState:UIControlStateNormal];
        [recheckBtn setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
        recheckBtn.titleLabel.font = DFont(13.5, YES, UIFontTextStyleHeadline);
        recheckBtn.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 6 : -6, 0, [Language isRTL] ? -6 : 6);
        [recheckBtn addTarget:self action:@selector(recheckStatusTapped) forControlEvents:UIControlEventTouchUpInside];
        self.checkStatusButton = recheckBtn;
        [actionRow addSubview:recheckBtn];

        [NSLayoutConstraint activateConstraints:@[
            [callBtn.leadingAnchor constraintEqualToAnchor:actionRow.leadingAnchor],
            [callBtn.topAnchor constraintEqualToAnchor:actionRow.topAnchor constant:4],
            [callBtn.bottomAnchor constraintEqualToAnchor:actionRow.bottomAnchor],
            [callBtn.heightAnchor constraintGreaterThanOrEqualToConstant:48],

            [recheckBtn.leadingAnchor constraintEqualToAnchor:callBtn.trailingAnchor constant:10],
            [recheckBtn.trailingAnchor constraintEqualToAnchor:actionRow.trailingAnchor],
            [recheckBtn.topAnchor constraintEqualToAnchor:actionRow.topAnchor constant:4],
            [recheckBtn.bottomAnchor constraintEqualToAnchor:actionRow.bottomAnchor],
            [recheckBtn.widthAnchor constraintEqualToAnchor:callBtn.widthAnchor],
            [recheckBtn.heightAnchor constraintGreaterThanOrEqualToConstant:48]
        ]];
        // The two buttons are siblings of the presence UIControl, not children:
        // they remain VoiceOver-accessible even when presence itself is disabled.

        [NSLayoutConstraint activateConstraints:@[
            [cardInnerStack.leadingAnchor constraintEqualToAnchor:availCard.leadingAnchor constant:16],
            [cardInnerStack.trailingAnchor constraintEqualToAnchor:availCard.trailingAnchor constant:-16],
            [cardInnerStack.topAnchor constraintEqualToAnchor:availCard.topAnchor constant:16],
            [cardInnerStack.bottomAnchor constraintEqualToAnchor:availCard.bottomAnchor constant:-16]
        ]];
        [header addArrangedSubview:availCard];
        [header addArrangedSubview:actionRow];
    }

    // Feedback Container (for Empty Radar Hub / Informational Deck)
    self.feedback = DStack(@[], 12);
    [header addArrangedSubview:self.feedback];

    // --- Table & Dock Setup ---
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.estimatedRowHeight = 260;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:PPDriverTaskCell.class forCellReuseIdentifier:@"task"];
    self.table.refreshControl = [UIRefreshControl new];
    [self.table.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.table.contentInset = UIEdgeInsetsMake(6, 0, self.taskID.length ? 14 : 110, 0);
    self.table.accessibilityIdentifier = @"driver.workspace.tasks";

    self.dock = DStack(@[], 8);
    self.dock.translatesAutoresizingMaskIntoConstraints = NO;
    self.dock.layoutMargins = UIEdgeInsetsMake(12, 18, 6, 18);
    self.dock.layoutMarginsRelativeArrangement = YES;
    self.dock.backgroundColor = UIColor.ppBackground;
    self.dock.hidden = !self.taskID.length;

    CGFloat initialWidth = UIScreen.mainScreen.bounds.size.width;
    CGSize targetHeaderSize = [header systemLayoutSizeFittingSize:CGSizeMake(initialWidth, UILayoutFittingCompressedSize.height)
                                    withHorizontalFittingPriority:UILayoutPriorityRequired
                                      verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, initialWidth, targetHeaderSize.height > 0 ? targetHeaderSize.height : 300);
    self.table.tableHeaderView = header;
    [self.view addSubview:self.table];
    [self.view addSubview:self.dock];

    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.navBarContainer.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.taskID.length ? self.dock.topAnchor : self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.dock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.dock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.dock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4]
    ]];

    [self adaptType];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(passiveRefresh) name:PPDriverTasksDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(passiveRefresh) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(adaptType) name:UIContentSizeCategoryDidChangeNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateLaneButtonAppearancesAnimated:NO];
    CGFloat width = self.table.bounds.size.width;
    if (width <= 0) {
        width = self.view.bounds.size.width > 0 ? self.view.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
    }
    for (UIStackView *stack in @[self.header, self.detailActions ?: self.header]) {
        CGSize size = [stack systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                           withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        if (size.height > 0 && (fabs(stack.frame.size.height - size.height) > 0.5 || fabs(stack.frame.size.width - width) > 0.5)) {
            stack.frame = CGRectMake(0, 0, width, size.height);
            if (stack == self.header) {
                self.table.tableHeaderView = stack;
            } else {
                self.table.tableFooterView = stack;
            }
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateLaneButtonAppearancesAnimated:NO];
        [self renderAvailability];
        self.backButton.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
        self.utilityButton.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
        [self.table reloadData];
    }
}

- (void)adaptType {
    [self.table reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.visible = YES;
    [self.refreshTimer invalidate];
    [self refresh];
    __weak typeof(self) weakSelf = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *timer) {
        [weakSelf passiveRefresh];
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([self.navigationController respondsToSelector:@selector(pp_enableSwipeToPop)]) {
        [(id)self.navigationController pp_enableSwipeToPop];
    } else if (self.navigationController.interactivePopGestureRecognizer) {
        self.navigationController.interactivePopGestureRecognizer.enabled = YES;
        self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.visible = NO;
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    self.generation++;
    self.loading = NO;
}

- (void)dealloc {
    [self.refreshTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setOnNotifications:(void (^)(void))onNotifications {
    _onNotifications = [onNotifications copy];
    self.utilityButton.hidden = !onNotifications;
}

- (BOOL)sessionMatches {
    return self.uid.length && [self.uid isEqualToString:FIRAuth.auth.currentUser.uid];
}

- (void)handleBackAction {
    if (self.onClose) {
        self.onClose();
        return;
    }
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)utilityTapped {
    if (self.onNotifications) {
        self.onNotifications();
    }
}

#pragma mark - Lanes Interaction

- (void)updateLaneButtonAppearancesAnimated:(BOOL)animated {
    NSInteger activeIndex = [@[@"active", @"available", @"history"] indexOfObject:self.lane];
    if (activeIndex == NSNotFound) activeIndex = 0;

    void (^updateBlock)(void) = ^{
        for (NSInteger i = 0; i < self.laneButtons.count; i++) {
            UIButton *btn = self.laneButtons[i];
            BOOL isSelected = (i == activeIndex);
            if (isSelected) {
                btn.tintColor = UIColor.ppPrimary;
                [btn setTitleColor:UIColor.ppPrimary forState:UIControlStateNormal];
            } else {
                btn.tintColor = UIColor.ppTextSecondary;
                [btn setTitleColor:UIColor.ppTextSecondary forState:UIControlStateNormal];
            }
            btn.accessibilityTraits = isSelected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
        }

        if (self.lanesContainer.bounds.size.width > 0) {
            CGFloat laneWidth = (self.lanesContainer.bounds.size.width - 8) / 3.0;
            CGFloat targetX = 4 + (laneWidth * activeIndex);
            self.laneHighlightLeading.constant = targetX;
            [self.lanesContainer layoutIfNeeded];
        }
    };

    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState animations:updateBlock completion:nil];
    } else {
        updateBlock();
    }
}

- (void)laneTapped:(UIButton *)button {
    if (self.submitting) return;
    self.generation++;
    self.loading = NO;
    self.lane = @[@"active", @"available", @"history"][button.tag];
    self.tasks = @[];
    self.cursor = nil;
    self.hasMore = NO;
    self.showingAdditionalPages = NO;

    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [[UISelectionFeedbackGenerator new] selectionChanged];
    }
    [self updateLaneButtonAppearancesAnimated:YES];

    [self.table reloadData];
    [self refresh];
}

#pragma mark - Data Loading & Lifecycle

- (void)refresh {
    if (!self.visible || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || self.loading || self.submitting || self.pendingCommand || self.presentedViewController) return;
    [self loadMore:NO];
}

- (void)passiveRefresh {
    if (self.table.dragging || self.table.decelerating || (!self.taskID.length && self.showingAdditionalPages)) return;
    [self refresh];
}

- (void)loadNext {
    if (self.hasMore && !self.loading && !self.submitting && !self.pendingCommand) {
        [self loadMore:YES];
    }
}

- (void)clear:(UIStackView *)stack {
    for (UIView *view in stack.arrangedSubviews.copy) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

#pragma mark - Category-Defining Empty Radar Hub

- (void)switchToAvailableLane {
    if (self.laneButtons.count > 1) {
        [self laneTapped:self.laneButtons[1]];
    }
}

- (void)message:(NSString *)key retry:(BOOL)retry {
    [self clear:self.feedback];

    BOOL accessDenied = [key isEqualToString:@"Driver_Access_Denied"];
    BOOL fleetPending = !self.loading && !self.taskID.length && !self.availability.count && !accessDenied;

    // In run sheet mode (!self.taskID.length), if the driver is pending fleet activation or denied,
    // the availabilityCard in header already represents the authoritative Fleet Standby Gate.
    // Suppress the duplicate card in self.feedback so the screen is clean, unified, and intentional.
    if (!self.taskID.length && (!self.availability.count || accessDenied)) {
        [self.view setNeedsLayout];
        return;
    }

    if ([key isEqualToString:@"Driver_Loading"]) {
        UIView *loadingCard = [UIView new];
        loadingCard.translatesAutoresizingMaskIntoConstraints = NO;
        loadingCard.backgroundColor = UIColor.ppElevatedSurface;
        loadingCard.layer.cornerRadius = 20;
        loadingCard.layer.cornerCurve = kCACornerCurveContinuous;
        loadingCard.layer.borderWidth = 1.0;
        loadingCard.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;

        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        spinner.color = UIColor.ppPrimary;
        [spinner startAnimating];
        [loadingCard addSubview:spinner];

        UILabel *loadLbl = DLabel(DL(@"Driver_Loading"), 14, YES, UIColor.ppTextSecondary);
        loadLbl.translatesAutoresizingMaskIntoConstraints = NO;
        [loadingCard addSubview:loadLbl];

        [NSLayoutConstraint activateConstraints:@[
            [spinner.leadingAnchor constraintEqualToAnchor:loadingCard.leadingAnchor constant:20],
            [spinner.centerYAnchor constraintEqualToAnchor:loadingCard.centerYAnchor],
            [loadLbl.leadingAnchor constraintEqualToAnchor:spinner.trailingAnchor constant:12],
            [loadLbl.trailingAnchor constraintEqualToAnchor:loadingCard.trailingAnchor constant:-20],
            [loadLbl.topAnchor constraintEqualToAnchor:loadingCard.topAnchor constant:16],
            [loadLbl.bottomAnchor constraintEqualToAnchor:loadingCard.bottomAnchor constant:-16]
        ]];
        [self.feedback addArrangedSubview:loadingCard];
        [self.view setNeedsLayout];
        return;
    }

    BOOL isPendingOrDenied = accessDenied || fleetPending;

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.ppElevatedSurface;
    card.layer.cornerRadius = 24;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
    card.layer.shadowColor = UIColor.ppShadow.CGColor;
    card.layer.shadowOpacity = 0.05;
    card.layer.shadowOffset = CGSizeMake(0, 6);
    card.layer.shadowRadius = 14;

    UIStackView *cardStack = DStack(@[], 16);
    cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    cardStack.alignment = UIStackViewAlignmentCenter;
    [card addSubview:cardStack];

    // Ambient Luminous Radar Icon Housing
    UIView *radarCenter = [UIView new];
    radarCenter.translatesAutoresizingMaskIntoConstraints = NO;
    radarCenter.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.08];
    radarCenter.layer.cornerRadius = 32;
    radarCenter.layer.cornerCurve = kCACornerCurveContinuous;

    UIView *outerRing = [UIView new];
    outerRing.translatesAutoresizingMaskIntoConstraints = NO;
    outerRing.layer.cornerRadius = 44;
    outerRing.layer.borderWidth = 1.0;
    outerRing.layer.borderColor = [UIColor.ppPrimary colorWithAlphaComponent:0.18].CGColor;
    [radarCenter addSubview:outerRing];

    NSString *iconName = [self.lane isEqualToString:@"available"] ? @"sparkles.rectangle.stack.fill" : ([self.lane isEqualToString:@"history"] ? @"clock.arrow.circlepath" : @"car.side.fill");
    if (isPendingOrDenied) {
        iconName = @"shield.lefthalf.filled.badge.checkmark";
    }
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    iv.tintColor = isPendingOrDenied ? UIColor.ppWarning : UIColor.ppPrimary;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [radarCenter addSubview:iv];

    [NSLayoutConstraint activateConstraints:@[
        [radarCenter.widthAnchor constraintEqualToConstant:64],
        [radarCenter.heightAnchor constraintEqualToConstant:64],

        [outerRing.centerXAnchor constraintEqualToAnchor:radarCenter.centerXAnchor],
        [outerRing.centerYAnchor constraintEqualToAnchor:radarCenter.centerYAnchor],
        [outerRing.widthAnchor constraintEqualToConstant:88],
        [outerRing.heightAnchor constraintEqualToConstant:88],

        [iv.centerXAnchor constraintEqualToAnchor:radarCenter.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:radarCenter.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:30],
        [iv.heightAnchor constraintEqualToConstant:30]
    ]];
    [cardStack addArrangedSubview:radarCenter];

    // Empowering Typography Hierarchy
    BOOL emptyActive = [key isEqualToString:@"Driver_Empty_Active"] && self.availability.count;
    NSString *headlineKey = accessDenied ? @"Driver_Access_Denied" : (fleetPending ? @"Driver_Fleet_Pending_Title" : (emptyActive ? @"Driver_Radar_Title" : key));
    NSString *bodyKey = accessDenied ? @"Driver_Access_Denied" : (fleetPending ? @"Driver_Fleet_Pending_Subtitle" : (emptyActive ? @"Driver_Radar_Subtitle" : key));

    UILabel *titleLbl = DLabel(DL(headlineKey), 19, YES, UIColor.ppTextPrimary);
    titleLbl.textAlignment = NSTextAlignmentCenter;
    [cardStack addArrangedSubview:titleLbl];

    UILabel *descLbl = DLabel(DL(bodyKey), 13.5, NO, UIColor.ppTextSecondary);
    descLbl.textAlignment = NSTextAlignmentCenter;
    [cardStack addArrangedSubview:descLbl];

    // Tactical Action Buttons Hub
    UIStackView *actionsStack = [[UIStackView alloc] init];
    actionsStack.axis = UILayoutConstraintAxisHorizontal;
    actionsStack.spacing = 10;
    actionsStack.distribution = UIStackViewDistributionFillEqually;
    actionsStack.translatesAutoresizingMaskIntoConstraints = NO;

    if (emptyActive) {
        UIButton *browseAction = [UIButton buttonWithType:UIButtonTypeSystem];
        browseAction.backgroundColor = UIColor.ppPrimary;
        browseAction.tintColor = UIColor.whiteColor;
        browseAction.layer.cornerRadius = 15;
        browseAction.layer.cornerCurve = kCACornerCurveContinuous;
        [browseAction setTitle:DL(@"Driver_Lane_New") forState:UIControlStateNormal];
        [browseAction setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [browseAction setImage:[UIImage systemImageNamed:@"sparkles"] forState:UIControlStateNormal];
        browseAction.titleLabel.font = DFont(13.5, YES, UIFontTextStyleHeadline);
        browseAction.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 6 : -6, 0, [Language isRTL] ? -6 : 6);
        [browseAction addTarget:self action:@selector(switchToAvailableLane) forControlEvents:UIControlEventTouchUpInside];
        [actionsStack addArrangedSubview:browseAction];
    }

    UIButton *primaryAction = [UIButton buttonWithType:UIButtonTypeSystem];
    primaryAction.backgroundColor = emptyActive ? [UIColor.ppSecondarySurface colorWithAlphaComponent:0.9] : [UIColor.ppPrimary colorWithAlphaComponent:0.10];
    primaryAction.tintColor = emptyActive ? UIColor.ppTextPrimary : UIColor.ppPrimary;
    primaryAction.layer.cornerRadius = 15;
    primaryAction.layer.cornerCurve = kCACornerCurveContinuous;
    if (emptyActive) {
        primaryAction.layer.borderWidth = 0.8;
        primaryAction.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
    }
    [primaryAction setTitle:DL(retry ? @"Driver_Retry" : @"Driver_Refresh_Run") forState:UIControlStateNormal];
    [primaryAction setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
    primaryAction.titleLabel.font = DFont(13.5, YES, UIFontTextStyleHeadline);
    primaryAction.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 6 : -6, 0, [Language isRTL] ? -6 : 6);
    [primaryAction addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    [actionsStack addArrangedSubview:primaryAction];

    if (isPendingOrDenied) {
        UIButton *dispatchAction = [UIButton buttonWithType:UIButtonTypeSystem];
        dispatchAction.backgroundColor = [UIColor.ppSecondarySurface colorWithAlphaComponent:0.9];
        dispatchAction.tintColor = UIColor.ppTextPrimary;
        dispatchAction.layer.cornerRadius = 15;
        dispatchAction.layer.cornerCurve = kCACornerCurveContinuous;
        dispatchAction.layer.borderWidth = 0.8;
        dispatchAction.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
        [dispatchAction setTitle:DL(@"Driver_Call_Dispatch_Short") forState:UIControlStateNormal];
        [dispatchAction setImage:[UIImage systemImageNamed:@"phone.fill"] forState:UIControlStateNormal];
        dispatchAction.titleLabel.font = DFont(13.5, YES, UIFontTextStyleHeadline);
        dispatchAction.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 6 : -6, 0, [Language isRTL] ? -6 : 6);
        [dispatchAction addTarget:self action:@selector(callDispatch) forControlEvents:UIControlEventTouchUpInside];
        [actionsStack addArrangedSubview:dispatchAction];
    }

    [cardStack addArrangedSubview:actionsStack];

    [NSLayoutConstraint activateConstraints:@[
        [actionsStack.widthAnchor constraintEqualToAnchor:cardStack.widthAnchor constant:-20],
        [actionsStack.heightAnchor constraintEqualToConstant:44],

        [cardStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [cardStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [cardStack.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [cardStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24]
    ]];

    [self.feedback addArrangedSubview:card];
    [self.view setNeedsLayout];
}

- (void)retryTapped {
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
    }
    if (self.pendingCommand) [self submitPending]; else [self refresh];
}

- (void)recheckStatusTapped {
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
        [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.checkStatusButton.transform = CGAffineTransformMakeRotation(M_PI);
        } completion:^(BOOL finished) {
            self.checkStatusButton.transform = CGAffineTransformIdentity;
        }];
    }
    [self refresh];
}

- (void)callDispatch {
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [[UIImpactFeedbackGenerator new] impactOccurred];
    }
    // Official Pure Pets Qatar Operations & Fleet Hotline
    NSURL *phoneUrl = [NSURL URLWithString:@"tel://+97459997720"];
    if ([UIApplication.sharedApplication canOpenURL:phoneUrl]) {
        [UIApplication.sharedApplication openURL:phoneUrl options:@{} completionHandler:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:DL(@"Driver_Fleet_Call_Dispatch")
                                                                       message:DL(@"Settings_Help_Message")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)loadMore:(BOOL)more {
    if (![self sessionMatches]) {
        self.tasks = @[];
        [self.table reloadData];
        [self renderDock];
        [self message:@"Driver_Access_Denied" retry:NO];
        return;
    }
    self.loading = YES;
    NSUInteger epoch = ++self.generation;
    [self renderDock];
    [self renderAvailability];
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    if (self.taskID.length) {
        parameters[@"taskId"] = self.taskID;
        parameters[@"authority"] = self.authority;
    } else {
        parameters[@"lane"] = self.lane;
        if (more && self.cursor) parameters[@"cursor"] = self.cursor;
    }
    if (!self.tasks.count) [self message:@"Driver_Loading" retry:NO];

    __weak typeof(self) weakSelf = self;
    [self.service load:parameters completion:^(NSDictionary *data, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || epoch != self.generation || ![self sessionMatches]) return;
        self.loading = NO;
        [self.table.refreshControl endRefreshing];
        if (error) {
            BOOL denied = [error.domain isEqualToString:FIRFunctionsErrorDomain] && (error.code == FIRFunctionsErrorCodePermissionDenied || error.code == FIRFunctionsErrorCodeUnauthenticated || error.code == FIRFunctionsErrorCodeNotFound);
            if (denied) {
                self.tasks = @[];
                self.cursor = nil;
                self.hasMore = NO;
                self.availability = @{};
                [self renderDock];
                [self renderAvailability];
                [self.table reloadData];
                if (!self.taskID.length) [self updateFooter];
            }
            [self message:denied ? @"Driver_Access_Denied" : @"Driver_Error_Load" retry:!denied];
            return;
        }
        NSMutableArray *items = more ? self.tasks.mutableCopy : [NSMutableArray array];
        NSArray *rows = self.taskID.length ? (DDict(data[@"task"]).count ? @[data[@"task"]] : @[]) : DArray(data[@"tasks"]);
        for (id raw in rows) {
            NSDictionary *task = DDict(raw);
            if (!DText(task[@"taskId"]).length || ![@[@"FULFILLMENT_V1", @"COMPANY_DELIVERY_REQUEST"] containsObject:DText(task[@"authority"])]) continue;
            NSIndexSet *duplicate = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *other, NSUInteger idx, BOOL *stop) {
                return [other[@"taskId"] isEqual:task[@"taskId"]] && [other[@"authority"] isEqual:task[@"authority"]];
            }];
            [items removeObjectsAtIndexes:duplicate];
            [items addObject:task];
        }
        self.tasks = items;
        self.cursor = DDict(data[@"nextCursor"]);
        self.hasMore = DFlag(data[@"hasMore"]);
        self.showingAdditionalPages = more;
        if (!self.taskID.length) {
            self.availability = DDict(DArray(data[@"availability"]).firstObject);
            [self renderAvailability];
        }
        [self clear:self.feedback];
        [self.table reloadData];
        [self renderDock];
        if (!self.taskID.length) [self updateFooter];
        [self.view setNeedsLayout];
        if (!self.tasks.count) {
            [self message:self.hasMore ? @"Driver_More_Available" : ([self.lane isEqualToString:@"available"] ? @"Driver_Empty_New" : ([self.lane isEqualToString:@"history"] ? @"Driver_Empty_History" : @"Driver_Empty_Active")) retry:NO];
        }
        if (!self.taskID.length) [self notificationStatus];
    }];
}

#pragma mark - Cockpit Availability Rendering

- (void)renderAvailability {
    if (!self.availabilityCard) return;
    BOOL hasFleet = self.availability.count > 0;
    BOOL online = DFlag(self.availability[@"online"]);
    BOOL paused = DFlag(self.availability[@"assignmentsPaused"]);
    NSString *account = DText(self.availability[@"accountStatus"]).uppercaseString;
    NSString *shift = DText(self.availability[@"shiftStatus"]).uppercaseString;
    NSString *work = DText(self.availability[@"workState"]).uppercaseString;
    NSArray *reasons = DArray(self.availability[@"readinessReasons"]);

    // The beacon describes presence only; dispatch readiness is an independent line.
    UIColor *presenceColor = !hasFleet ? UIColor.ppWarning : (online ? UIColor.ppSuccess : UIColor.ppTextSecondary);
    [self.availabilityBeacon setBeaconColor:presenceColor pulsing:hasFleet && online];
    [self.topBeaconDot setBeaconColor:presenceColor pulsing:hasFleet && online];
    NSString *titleKey = !hasFleet ? @"Driver_Fleet_Pending_Title" : (online ? @"Driver_Presence_Online" : @"Driver_Presence_Offline");
    NSString *subtitleKey = !hasFleet ? @"Driver_Fleet_Pending_Subtitle" : (online ? @"Driver_Presence_Go_Offline" : @"Driver_Presence_Go_Online");
    self.availabilityTitleLabel.text = DL(titleKey);
    self.availabilitySubtitleLabel.text = DL(subtitleKey);

    self.availabilityDispatchLabel.text = DL(hasFleet ? (paused ? @"Driver_Dispatch_Paused_Standalone" : @"Driver_Dispatch_Enabled") : @"Driver_Dispatch_Unknown");
    self.availabilityDispatchLabel.textColor = paused ? UIColor.ppWarning : UIColor.ppTextPrimary;
    self.availabilityAccountLabel.text = DL(!hasFleet || !account.length ? @"Driver_Account_Status_Unknown" : ([account isEqualToString:@"ACTIVE"] ? @"Driver_Account_Status_Active" : @"Driver_Account_Status_Restricted"));
    self.availabilityShiftLabel.text = DL(!hasFleet || !shift.length ? @"Driver_Shift_Unknown" : ([shift isEqualToString:@"ON_SHIFT"] ? @"Driver_Shift_On" : ([shift isEqualToString:@"BREAK"] ? @"Driver_Shift_Break" : ([shift isEqualToString:@"OFF_SHIFT"] ? @"Driver_Shift_Off" : @"Driver_Shift_Unknown"))));
    self.availabilityShiftLabel.textColor = [@[@"BREAK", @"OFF_SHIFT"] containsObject:shift] ? UIColor.ppWarning : UIColor.ppTextSecondary;
    NSString *workKey = !hasFleet || !work.length || [work isEqualToString:@"UNKNOWN"] ? @"Driver_Work_Unknown" : ([work isEqualToString:@"BUSY"] ? @"Driver_Work_Busy" : @"Driver_Work_Idle");
    self.availabilityWorkLabel.text = DL(workKey);
    if (hasFleet && [self.availability[@"activeDeliveryCount"] isKindOfClass:NSNumber.class]) {
        self.availabilityWorkLabel.text = [NSString stringWithFormat:DL(@"Driver_Work_Count_Format"), self.availability[@"activeDeliveryCount"]];
    }
    // Explain known blockers without claiming complete dispatch eligibility.
    self.availabilityWorkLabel.textColor = UIColor.ppTextSecondary;
    NSString *blockerKey = nil;
    if (hasFleet) {
        if (account.length && ![account isEqualToString:@"ACTIVE"]) {
            blockerKey = @"Driver_Readiness_Account";
        } else if (paused) {
            blockerKey = @"Driver_Readiness_Dispatch_Fix";
        } else if ([shift isEqualToString:@"BREAK"] || [shift isEqualToString:@"OFF_SHIFT"]) {
            blockerKey = @"Driver_Readiness_Shift";
        } else if ([reasons containsObject:@"CAPACITY_EXCEEDED"]) {
            blockerKey = @"Driver_Readiness_Capacity";
        } else if ([reasons containsObject:@"PRESENCE_STALE"]) {
            blockerKey = @"Driver_Readiness_Stale";
        }
    }
    self.availabilityBlockerLabel.text = blockerKey ? DL(blockerKey) : @"";
    self.availabilityBlockerLabel.hidden = !blockerKey;

    // The presence control is separate from the sibling dispatcher buttons.
    self.availabilityCard.userInteractionEnabled = hasFleet && !self.pendingCommand && !self.submitting && !self.loading;
    self.availabilityCard.alpha = self.availabilityCard.userInteractionEnabled ? 1.0 : 0.80;
    self.availabilityCard.isAccessibilityElement = hasFleet;
    self.availabilityCard.accessibilityTraits = UIAccessibilityTraitButton;
    self.availabilityCard.accessibilityLabel = DL(@"Driver_Presence_Control");
    self.availabilityCard.accessibilityValue = [@[DL(titleKey), self.availabilityDispatchLabel.text ?: @"",
        self.availabilityAccountLabel.text ?: @"", self.availabilityShiftLabel.text ?: @"",
        self.availabilityWorkLabel.text ?: @"", self.availabilityBlockerLabel.text ?: @""] componentsJoinedByString:@", "];
    self.availabilityCard.accessibilityHint = hasFleet ? DL(subtitleKey) : nil;
    self.availabilityChevron.hidden = !hasFleet;
    self.availabilityActionRow.hidden = hasFleet && !paused;
    self.checkStatusButton.enabled = !self.submitting && !self.loading;
    [self.view setNeedsLayout];
}

- (void)requestOnline:(BOOL)online {
    if (!self.availability.count || self.submitting || self.pendingCommand || self.loading || ![self sessionMatches]) return;
    self.pendingAvailability = YES;
    self.pendingCommand = @{
        @"companyId": self.availability[@"companyId"] ?: @"",
        @"online": @(online),
        @"expectedRevision": self.availability[@"revision"] ?: @0,
        @"commandId": NSUUID.UUID.UUIDString
    };
    [self submitPending];
}

- (void)toggleAvailability {
    if (!self.availability.count || self.submitting || self.pendingCommand || self.loading) return;
    BOOL online = !DFlag(self.availability[@"online"]);
    // Going online is reversible; avoid a redundant alert. Only warn about
    // going offline if the server reports outstanding deliveries.
    NSInteger active = MAX(0, [self.availability[@"activeDeliveryCount"] integerValue]);
    if (online || active == 0) {
        [self requestOnline:online];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DL(@"Driver_Go_Offline")
                                                                   message:DL(@"Driver_Offline_With_Orders")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Go_Offline") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf requestOnline:NO];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateFooter {
    if (!self.hasMore) {
        self.detailActions = nil;
        self.table.tableFooterView = [UIView new];
        return;
    }
    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    more.translatesAutoresizingMaskIntoConstraints = NO;
    more.backgroundColor = UIColor.ppElevatedSurface;
    more.tintColor = UIColor.ppPrimary;
    more.layer.cornerRadius = 16;
    more.layer.cornerCurve = kCACornerCurveContinuous;
    more.layer.borderWidth = 1.0;
    more.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
    [more setTitle:DL(@"Driver_Load_More") forState:UIControlStateNormal];
    [more setImage:[UIImage systemImageNamed:@"arrow.down"] forState:UIControlStateNormal];
    more.titleLabel.font = DFont(15, YES, UIFontTextStyleHeadline);
    more.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 8 : -8, 0, [Language isRTL] ? -8 : 8);
    [more.heightAnchor constraintEqualToConstant:48].active = YES;
    [more addTarget:self action:@selector(loadNext) forControlEvents:UIControlEventTouchUpInside];

    self.detailActions = DStack(@[more], 0);
    self.detailActions.layoutMargins = UIEdgeInsetsMake(8, 20, 20, 20);
    self.detailActions.layoutMarginsRelativeArrangement = YES;
    self.table.tableFooterView = self.detailActions;
    [self.view setNeedsLayout];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.tasks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPDriverTaskCell *cell = [tableView dequeueReusableCellWithIdentifier:@"task" forIndexPath:indexPath];
    NSDictionary *task = self.tasks[indexPath.row];
    BOOL finished = [@[@"completed", @"cancelled", @"rejected", @"failed", @"returned"] containsObject:DText(task[@"status"])];
    BOOL focused = indexPath.row == 0 && [self.lane isEqualToString:@"active"] && DFlag(task[@"mine"]) && !finished;
    [cell render:task focused:focused detail:self.taskID.length > 0];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.taskID.length) return;
    NSDictionary *task = self.tasks[indexPath.row];
    if (self.onOpenTask) self.onOpenTask(DText(task[@"taskId"]), DText(task[@"authority"]));
}

- (NSString *)cashText:(NSDictionary *)task {
    NSDictionary *cash = DDict(task[@"cash"]);
    NSNumber *amount = [cash[@"amount"] isKindOfClass:NSNumber.class] ? cash[@"amount"] : nil;
    NSString *currency = DText(cash[@"currency"]);
    if (!amount || !currency.length) return DL(@"Driver_Cash_Unavailable");
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:[Language isRTL] ? @"ar_QA" : @"en_QA"];
    f.numberStyle = NSNumberFormatterCurrencyStyle;
    f.currencyCode = currency;
    return [NSString stringWithFormat:DL(@"Driver_Cash_Format"), [f stringFromNumber:amount] ?: @""];
}

#pragma mark - Detail Dock & Primary Action

- (void)renderDock {
    [self clear:self.dock];
    if (self.taskID.length && !self.tasks.count) {
        self.detailActions = nil;
        self.table.tableFooterView = [UIView new];
    }
    if (!self.taskID.length || !self.tasks.count) return;
    NSDictionary *task = self.tasks.firstObject;

    self.detailActions = DStack(@[], 12);
    self.detailActions.layoutMargins = UIEdgeInsetsMake(8, 18, 20, 18);
    self.detailActions.layoutMarginsRelativeArrangement = YES;
    self.table.tableFooterView = self.detailActions;

    // Quick Secondary Actions Row (Maps & Call)
    if (DFlag(task[@"mine"])) {
        UIStackView *quickRow = [[UIStackView alloc] init];
        quickRow.axis = UILayoutConstraintAxisHorizontal;
        quickRow.distribution = UIStackViewDistributionFillEqually;
        quickRow.spacing = 10;

        UIButton *navigate = [UIButton buttonWithType:UIButtonTypeSystem];
        navigate.backgroundColor = UIColor.ppElevatedSurface;
        navigate.tintColor = UIColor.ppPrimary;
        navigate.layer.cornerRadius = 16;
        navigate.layer.cornerCurve = kCACornerCurveContinuous;
        navigate.layer.borderWidth = 1.0;
        navigate.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
        [navigate setTitle:DL(@"Driver_Navigate") forState:UIControlStateNormal];
        [navigate setImage:[UIImage systemImageNamed:@"arrow.triangle.turn.up.right.diamond.fill"] forState:UIControlStateNormal];
        navigate.titleLabel.font = DFont(14, YES, UIFontTextStyleHeadline);
        navigate.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 8 : -8, 0, [Language isRTL] ? -8 : 8);
        [navigate.heightAnchor constraintEqualToConstant:48].active = YES;
        [navigate addTarget:self action:@selector(navigate) forControlEvents:UIControlEventTouchUpInside];
        [quickRow addArrangedSubview:navigate];

        if (DText(task[@"phone"]).length) {
            UIButton *call = [UIButton buttonWithType:UIButtonTypeSystem];
            call.backgroundColor = UIColor.ppElevatedSurface;
            call.tintColor = UIColor.ppSuccess;
            call.layer.cornerRadius = 16;
            call.layer.cornerCurve = kCACornerCurveContinuous;
            call.layer.borderWidth = 1.0;
            call.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
            [call setTitle:DL(@"Driver_Call") forState:UIControlStateNormal];
            [call setImage:[UIImage systemImageNamed:@"phone.fill"] forState:UIControlStateNormal];
            call.titleLabel.font = DFont(14, YES, UIFontTextStyleHeadline);
            call.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 8 : -8, 0, [Language isRTL] ? -8 : 8);
            [call.heightAnchor constraintEqualToConstant:48].active = YES;
            [call addTarget:self action:@selector(callRecipient) forControlEvents:UIControlEventTouchUpInside];
            [quickRow addArrangedSubview:call];
        }
        [self.detailActions addArrangedSubview:quickRow];
    }

    if (DFlag(DDict(task[@"cash"])[@"required"]) && !DFlag(DDict(task[@"cash"])[@"collected"])) {
        [self.detailActions addArrangedSubview:DLabel([self cashText:task], 16, YES, UIColor.ppTextPrimary)];
    }

    // Prominent Primary Action in Floating Dock
    NSArray *actions = DArray(task[@"actions"]);
    if (actions.count) {
        UIButton *action = [UIButton buttonWithType:UIButtonTypeSystem];
        action.backgroundColor = UIColor.ppPrimary;
        action.tintColor = UIColor.whiteColor;
        action.layer.cornerRadius = 18;
        action.layer.cornerCurve = kCACornerCurveContinuous;
        action.layer.shadowColor = UIColor.ppPrimary.CGColor;
        action.layer.shadowOpacity = 0.30;
        action.layer.shadowOffset = CGSizeMake(0, 6);
        action.layer.shadowRadius = 12;

        [action setTitle:DAction(DText(actions.firstObject)) forState:UIControlStateNormal];
        [action setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [action setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateNormal];
        action.titleLabel.font = DFont(18, YES, UIFontTextStyleHeadline);
        action.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 10 : -10, 0, [Language isRTL] ? -10 : 10);
        [action.heightAnchor constraintEqualToConstant:54].active = YES;

        action.accessibilityIdentifier = @"driver.task.primaryAction";
        [action addTarget:self action:@selector(confirmAction) forControlEvents:UIControlEventTouchUpInside];
        action.enabled = !self.loading && !self.submitting && !self.pendingCommand;
        [self.dock addArrangedSubview:action];
    } else {
        [self.detailActions addArrangedSubview:DLabel(DL([DText(task[@"status"]) isEqualToString:@"delivery_assigned"] ? @"Driver_Wait_Handover" : @"Driver_No_Action"), 15, NO, UIColor.ppTextSecondary)];
    }
}

- (void)confirmAction {
    if (self.loading || self.submitting || self.pendingCommand || !self.tasks.count) return;
    NSDictionary *task = self.tasks.firstObject;
    NSString *action = DText(DArray(task[@"actions"]).firstObject);
    if (!action.length) return;
    NSDictionary *proof = DDict(task[@"proofRequirements"]);
    if ([action isEqualToString:@"DELIVER"] && [self.authority isEqualToString:@"COMPANY_DELIVERY_REQUEST"] &&
        (DFlag(proof[@"photoRequired"]) || DFlag(proof[@"signatureRequired"]) || DFlag(proof[@"otpRequired"]))) {
        // This is a real backend proof boundary, not a missing text field.
        // Offer a direct recovery path instead of a silent/scroll-hidden error.
        UIAlertController *help = [UIAlertController alertControllerWithTitle:DL(@"Driver_Proof_Assistance_Title")
                                                                    message:DL(@"Driver_Proof_Assistance")
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [help addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Cancel") style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [help addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Fleet_Call_Dispatch")
                                                  style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *ignored) {
            [weakSelf callDispatch];
        }]];
        [self presentViewController:help animated:YES completion:nil];
        return;
    }
    BOOL legacyCash = [action isEqualToString:@"DELIVER"] && [self.authority isEqualToString:@"COMPANY_DELIVERY_REQUEST"] && DFlag(DDict(task[@"cash"])[@"required"]);
    BOOL cash = legacyCash || [action isEqualToString:@"CONFIRM_PAYMENT"];
    NSDictionary *cashSnapshot = DDict(task[@"cash"]);
    if (cash && (![cashSnapshot[@"amount"] isKindOfClass:NSNumber.class] || [cashSnapshot[@"amount"] doubleValue] <= 0 || !DText(cashSnapshot[@"currency"]).length)) {
        [self message:@"Driver_Cash_Unavailable" retry:YES];
        return;
    }
    NSString *message = cash ? [self cashText:task] : DL(@"Driver_Confirm_Body");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DAction(action) message:message preferredStyle:UIAlertControllerStyleAlert];
    BOOL receiver = [action isEqualToString:@"DELIVER"] && [self.authority isEqualToString:@"COMPANY_DELIVERY_REQUEST"];
    // Raw OTP input is not proof: the backend requires trusted otpVerified
    // evidence, which this client cannot safely produce.
    if (receiver) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = DL(@"Driver_Receiver");
            field.textAlignment = [Language alignmentForCurrentLanguage];
            field.textContentType = UITextContentTypeName;
        }];
    }
    [alert addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:DAction(action) style:UIAlertActionStyleDefault handler:^(UIAlertAction *ignored) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self sessionMatches]) return;
        NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if (receiver && DFlag(proof[@"receiverNameRequired"]) && !name.length) {
            [self message:@"Driver_Receiver_Required" retry:NO];
            return;
        }
        NSMutableDictionary *command = [@{
            @"taskId": self.taskID,
            @"authority": self.authority,
            @"action": action,
            @"expectedState": task[@"status"] ?: @"",
            @"expectedRevision": task[@"revision"] ?: @0,
            @"commandId": NSUUID.UUID.UUIDString
        } mutableCopy];
        if (receiver) command[@"receiverName"] = name;
        if ([action isEqualToString:@"CONFIRM_PAYMENT"]) {
            command[@"confirmedCashAmount"] = cashSnapshot[@"amount"];
            command[@"confirmedCashCurrency"] = cashSnapshot[@"currency"];
        }
        if (legacyCash) {
            id amount = DDict(task[@"cash"])[@"amount"];
            if (![amount isKindOfClass:NSNumber.class]) {
                [self message:@"Driver_Cash_Unavailable" retry:NO];
                return;
            }
            command[@"cashCollected"] = @YES;
            command[@"cashAmountCollected"] = amount;
        }
        self.pendingAvailability = NO;
        self.pendingCommand = command;
        [self submitPending];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)submitPending {
    if (self.submitting || !self.pendingCommand || ![self sessionMatches]) return;
    self.submitting = YES;
    [self renderDock];
    [self renderAvailability];
    [self message:@"Driver_Saving" retry:NO];
    __weak typeof(self) weakSelf = self;
    void (^completion)(NSDictionary *, NSError *) = ^(NSDictionary *data, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self sessionMatches]) return;
        self.submitting = NO;
        if (error) {
            BOOL definite = [error.domain isEqualToString:FIRFunctionsErrorDomain] && [@[@(FIRFunctionsErrorCodePermissionDenied), @(FIRFunctionsErrorCodeUnauthenticated), @(FIRFunctionsErrorCodeFailedPrecondition), @(FIRFunctionsErrorCodeInvalidArgument), @(FIRFunctionsErrorCodeNotFound), @(FIRFunctionsErrorCodeAborted), @(FIRFunctionsErrorCodeAlreadyExists)] containsObject:@(error.code)];
            if (definite) {
                self.pendingCommand = nil;
                if (error.code == FIRFunctionsErrorCodePermissionDenied || error.code == FIRFunctionsErrorCodeUnauthenticated || error.code == FIRFunctionsErrorCodeNotFound) {
                    self.tasks = @[];
                    [self.table reloadData];
                }
                [self message:@"Driver_Error_Changed" retry:YES];
            } else {
                [self message:@"Driver_Error_Uncertain" retry:YES];
            }
            [self renderDock];
            [self renderAvailability];
            return;
        }
        self.pendingCommand = nil;
        [self renderAvailability];
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, DL(@"Driver_Saved"));
        if (self.visible) [self loadMore:NO];
        [NSNotificationCenter.defaultCenter postNotificationName:PPDriverTasksDidChangeNotification object:self];
    };
    if (self.pendingAvailability) {
        [self.service setAvailability:self.pendingCommand completion:completion];
    } else {
        [self.service execute:self.pendingCommand completion:completion];
    }
}

- (void)callRecipient {
    NSString *phone = DText(self.tasks.firstObject[@"phone"]);
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789"];
    NSString *safe = [[phone componentsSeparatedByCharactersInSet:allowed.invertedSet] componentsJoinedByString:@""];
    if (safe.length) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:[@"tel:" stringByAppendingString:safe]] options:@{} completionHandler:nil];
    }
}

- (void)navigate {
    if (!self.tasks.count) return;
    NSDictionary *task = self.tasks.firstObject;
    NSString *status = DText(task[@"status"]);
    BOOL pickup = [@[@"delivery_assigned", @"awaiting_handover", @"assigned_to_driver"] containsObject:status];
    NSDictionary *address = DDict(task[pickup ? @"pickup" : @"dropoff"]);
    NSString *query = DAddress(address);
    if ([query isEqualToString:DL(@"Driver_Address_Pending")]) {
        [self message:@"Driver_Address_Pending" retry:NO];
        return;
    }
    NSURLComponents *url = [NSURLComponents componentsWithString:@"https://maps.apple.com/"];
    url.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"daddr" value:query],
        [NSURLQueryItem queryItemWithName:@"dirflg" value:@"d"]
    ];
    [UIApplication.sharedApplication openURL:url.URL options:@{} completionHandler:nil];
}

- (void)notificationStatus {
    if (!self.onNotifications) return;
    NSUInteger epoch = self.generation;
    __weak typeof(self) weakSelf = self;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || epoch != self.generation || !self.visible || !self.onNotifications || ![self sessionMatches]) return;
            if (settings.authorizationStatus == UNAuthorizationStatusDenied || settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
                UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
                button.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.08];
                button.tintColor = UIColor.ppPrimary;
                button.layer.cornerRadius = 14;
                button.layer.cornerCurve = kCACornerCurveContinuous;
                [button setTitle:DL(@"Driver_Enable_Notifications") forState:UIControlStateNormal];
                [button setImage:[UIImage systemImageNamed:@"bell.badge.fill"] forState:UIControlStateNormal];
                button.titleLabel.font = DFont(14, YES, UIFontTextStyleHeadline);
                button.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 8 : -8, 0, [Language isRTL] ? -8 : 8);
                [button addTarget:self action:@selector(enableNotifications) forControlEvents:UIControlEventTouchUpInside];
                [button.heightAnchor constraintEqualToConstant:46].active = YES;
                [self.feedback addArrangedSubview:button];
                [self.view setNeedsLayout];
            }
        });
    }];
}

- (void)enableNotifications {
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
            });
        } else {
            [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted) [UIApplication.sharedApplication registerForRemoteNotifications];
                    [self refresh];
                });
            }];
        }
    }];
}

@end
