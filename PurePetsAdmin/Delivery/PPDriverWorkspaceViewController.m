#import "PPDriverWorkspaceViewController.h"
#import "PPDriverWorkspaceService.h"
#import "PPDesignTokens.h"
#import "Language.h"
#import "Styling.h"
#import "PPFirebaseCompat.h"

#import <UserNotifications/UserNotifications.h>
#import <MapKit/MapKit.h>

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
    for (NSString *key in @[@"formattedAddress",@"fullAddress",@"address",@"addressLine1",@"label"]) {
        if (DText(address[key]).length) return DText(address[key]);
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"buildingNumber",@"streetName",@"street",@"zoneNumber",@"area",@"city"]) {
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

#pragma mark - Category-Defining Task Cell

@interface PPDriverTaskCell : UITableViewCell
@property(nonatomic, strong) UIView *cardView;
- (void)render:(NSDictionary *)task focused:(BOOL)focused detail:(BOOL)detail;
@end

@implementation PPDriverTaskCell

- (void)render:(NSDictionary *)task focused:(BOOL)focused detail:(BOOL)detail {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.ppSurface;
    card.layer.cornerRadius = focused ? 26 : 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = focused ? 1.5 : 1.0;
    card.layer.borderColor = (focused ? [UIColor.ppPrimary colorWithAlphaComponent:0.38] : UIColor.ppSurfaceBorder).CGColor;
    
    // Ambient floating card shadow
    card.layer.shadowColor = UIColor.ppShadow.CGColor;
    card.layer.shadowOpacity = focused ? 0.12 : 0.05;
    card.layer.shadowOffset = CGSizeMake(0, focused ? 8 : 4);
    card.layer.shadowRadius = focused ? 16 : 10;
    [self.contentView addSubview:card];
    self.cardView = card;

    NSMutableArray *content = [NSMutableArray array];

    // --- Header Row: Status Badge & Order Number ---
    UIView *headerRow = [UIView new];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;

    // Status Pill
    NSString *statusStr = DText(task[@"status"]);
    UIColor *statusClr = DStatusColor(statusStr);
    UIView *statusPill = [UIView new];
    statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    statusPill.backgroundColor = [statusClr colorWithAlphaComponent:0.12];
    statusPill.layer.cornerRadius = 10;
    statusPill.layer.cornerCurve = kCACornerCurveContinuous;

    UIView *statusDot = [UIView new];
    statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    statusDot.backgroundColor = statusClr;
    statusDot.layer.cornerRadius = 3.5;
    [statusPill addSubview:statusDot];

    UILabel *statusLabel = DLabel(focused ? DL(@"Driver_Next") : DStatus(statusStr), 12, YES, statusClr);
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [statusPill addSubview:statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [statusDot.leadingAnchor constraintEqualToAnchor:statusPill.leadingAnchor constant:8],
        [statusDot.centerYAnchor constraintEqualToAnchor:statusPill.centerYAnchor],
        [statusDot.widthAnchor constraintEqualToConstant:7],
        [statusDot.heightAnchor constraintEqualToConstant:7],
        [statusLabel.leadingAnchor constraintEqualToAnchor:statusDot.trailingAnchor constant:6],
        [statusLabel.trailingAnchor constraintEqualToAnchor:statusPill.trailingAnchor constant:-10],
        [statusLabel.topAnchor constraintEqualToAnchor:statusPill.topAnchor constant:4],
        [statusLabel.bottomAnchor constraintEqualToAnchor:statusPill.bottomAnchor constant:-4],
    ]];
    [headerRow addSubview:statusPill];

    // Order Title
    NSString *number = DText(task[@"orderNumber"]);
    NSString *isolatedNumber = [NSString stringWithFormat:@"\u2068%@\u2069", number];
    UILabel *title = DLabel(number.length ? [NSString stringWithFormat:DL(@"Driver_Order_Format"), isolatedNumber] : DL(@"Driver_Delivery"), focused ? 22 : 19, YES, UIColor.ppTextPrimary);
    title.accessibilityTraits |= UIAccessibilityTraitHeader;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:title];

    [NSLayoutConstraint activateConstraints:@[
        [statusPill.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [statusPill.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [title.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [title.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:statusPill.trailingAnchor constant:12]
    ]];
    [content addObject:headerRow];

    // Subtle divider
    UIView *divider = [UIView new];
    divider.backgroundColor = UIColor.ppSurfaceBorder;
    [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    [content addObject:divider];

    // --- Route Journey Visualizer ---
    UIView *routeContainer = [UIView new];
    routeContainer.translatesAutoresizingMaskIntoConstraints = NO;

    // Pickup Stop
    UIView *pickupIconBg = [UIView new];
    pickupIconBg.translatesAutoresizingMaskIntoConstraints = NO;
    pickupIconBg.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.10];
    pickupIconBg.layer.cornerRadius = 14;
    pickupIconBg.layer.cornerCurve = kCACornerCurveContinuous;

    UIImageView *pickupIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shippingbox.fill"]];
    pickupIcon.tintColor = UIColor.ppPrimary;
    pickupIcon.contentMode = UIViewContentModeScaleAspectFit;
    pickupIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [pickupIconBg addSubview:pickupIcon];

    UIStackView *pickupCopy = DStack(@[
        DLabel(DL(@"Driver_Pickup"), 11, YES, UIColor.ppTextSecondary),
        DLabel(DAddress(DDict(task[@"pickup"])), 15, YES, UIColor.ppTextPrimary)
    ], 2);
    pickupCopy.translatesAutoresizingMaskIntoConstraints = NO;

    [routeContainer addSubview:pickupIconBg];
    [routeContainer addSubview:pickupCopy];

    // Connecting route track
    UIView *routeTrack = [UIView new];
    routeTrack.translatesAutoresizingMaskIntoConstraints = NO;
    routeTrack.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.25];
    routeTrack.layer.cornerRadius = 1;
    [routeContainer addSubview:routeTrack];

    // Dropoff Stop
    UIView *dropoffIconBg = [UIView new];
    dropoffIconBg.translatesAutoresizingMaskIntoConstraints = NO;
    dropoffIconBg.backgroundColor = [UIColor.ppSuccess colorWithAlphaComponent:0.12];
    dropoffIconBg.layer.cornerRadius = 14;
    dropoffIconBg.layer.cornerCurve = kCACornerCurveContinuous;

    UIImageView *dropoffIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"mappin.and.ellipse"]];
    dropoffIcon.tintColor = UIColor.ppSuccess;
    dropoffIcon.contentMode = UIViewContentModeScaleAspectFit;
    dropoffIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [dropoffIconBg addSubview:dropoffIcon];

    UIStackView *dropoffCopy = DStack(@[
        DLabel(DL(@"Driver_Dropoff"), 11, YES, UIColor.ppTextSecondary),
        DLabel(DAddress(DDict(task[@"dropoff"])), 15, YES, UIColor.ppTextPrimary)
    ], 2);
    dropoffCopy.translatesAutoresizingMaskIntoConstraints = NO;

    [routeContainer addSubview:dropoffIconBg];
    [routeContainer addSubview:dropoffCopy];

    [NSLayoutConstraint activateConstraints:@[
        // Pickup Icon & Copy
        [pickupIconBg.leadingAnchor constraintEqualToAnchor:routeContainer.leadingAnchor],
        [pickupIconBg.topAnchor constraintEqualToAnchor:routeContainer.topAnchor],
        [pickupIconBg.widthAnchor constraintEqualToConstant:28],
        [pickupIconBg.heightAnchor constraintEqualToConstant:28],
        [pickupIcon.centerXAnchor constraintEqualToAnchor:pickupIconBg.centerXAnchor],
        [pickupIcon.centerYAnchor constraintEqualToAnchor:pickupIconBg.centerYAnchor],
        [pickupIcon.widthAnchor constraintEqualToConstant:15],
        [pickupIcon.heightAnchor constraintEqualToConstant:15],
        [pickupCopy.leadingAnchor constraintEqualToAnchor:pickupIconBg.trailingAnchor constant:12],
        [pickupCopy.trailingAnchor constraintEqualToAnchor:routeContainer.trailingAnchor],
        [pickupCopy.topAnchor constraintEqualToAnchor:routeContainer.topAnchor],

        // Vertical Track connecting the stops
        [routeTrack.centerXAnchor constraintEqualToAnchor:pickupIconBg.centerXAnchor],
        [routeTrack.topAnchor constraintEqualToAnchor:pickupIconBg.bottomAnchor constant:4],
        [routeTrack.bottomAnchor constraintEqualToAnchor:dropoffIconBg.topAnchor constant:-4],
        [routeTrack.widthAnchor constraintEqualToConstant:2],

        // Dropoff Icon & Copy
        [dropoffIconBg.leadingAnchor constraintEqualToAnchor:routeContainer.leadingAnchor],
        [dropoffIconBg.topAnchor constraintEqualToAnchor:pickupCopy.bottomAnchor constant:14],
        [dropoffIconBg.widthAnchor constraintEqualToConstant:28],
        [dropoffIconBg.heightAnchor constraintEqualToConstant:28],
        [dropoffIcon.centerXAnchor constraintEqualToAnchor:dropoffIconBg.centerXAnchor],
        [dropoffIcon.centerYAnchor constraintEqualToAnchor:dropoffIconBg.centerYAnchor],
        [dropoffIcon.widthAnchor constraintEqualToConstant:15],
        [dropoffIcon.heightAnchor constraintEqualToConstant:15],
        [dropoffCopy.leadingAnchor constraintEqualToAnchor:dropoffIconBg.trailingAnchor constant:12],
        [dropoffCopy.trailingAnchor constraintEqualToAnchor:routeContainer.trailingAnchor],
        [dropoffCopy.topAnchor constraintEqualToAnchor:dropoffIconBg.topAnchor],
        [dropoffCopy.bottomAnchor constraintEqualToAnchor:routeContainer.bottomAnchor]
    ]];
    [content addObject:routeContainer];

    // Cash on Delivery Card (if required)
    NSDictionary *cash = DDict(task[@"cash"]);
    if (DFlag(cash[@"required"]) && !DFlag(cash[@"collected"])) {
        UIView *cashCard = [UIView new];
        cashCard.translatesAutoresizingMaskIntoConstraints = NO;
        cashCard.backgroundColor = [UIColor.ppWarning colorWithAlphaComponent:0.08];
        cashCard.layer.cornerRadius = 12;
        cashCard.layer.cornerCurve = kCACornerCurveContinuous;
        cashCard.layer.borderWidth = 1.0;
        cashCard.layer.borderColor = [UIColor.ppWarning colorWithAlphaComponent:0.25].CGColor;

        UIImageView *cashIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"banknote.fill"]];
        cashIcon.tintColor = UIColor.ppWarning;
        cashIcon.translatesAutoresizingMaskIntoConstraints = NO;
        [cashCard addSubview:cashIcon];

        NSNumber *amount = [cash[@"amount"] isKindOfClass:NSNumber.class] ? cash[@"amount"] : nil;
        NSString *currency = DText(cash[@"currency"]);
        NSString *cashString = amount ? [NSString stringWithFormat:@"%@ %@", amount, currency] : @"";
        UILabel *cashLbl = DLabel([NSString stringWithFormat:DL(@"Driver_Cash_Format"), cashString], 13, YES, UIColor.ppTextPrimary);
        cashLbl.translatesAutoresizingMaskIntoConstraints = NO;
        [cashCard addSubview:cashLbl];

        [NSLayoutConstraint activateConstraints:@[
            [cashIcon.leadingAnchor constraintEqualToAnchor:cashCard.leadingAnchor constant:10],
            [cashIcon.centerYAnchor constraintEqualToAnchor:cashCard.centerYAnchor],
            [cashIcon.widthAnchor constraintEqualToConstant:18],
            [cashIcon.heightAnchor constraintEqualToConstant:18],
            [cashLbl.leadingAnchor constraintEqualToAnchor:cashIcon.trailingAnchor constant:8],
            [cashLbl.trailingAnchor constraintEqualToAnchor:cashCard.trailingAnchor constant:-10],
            [cashLbl.topAnchor constraintEqualToAnchor:cashCard.topAnchor constant:8],
            [cashLbl.bottomAnchor constraintEqualToAnchor:cashCard.bottomAnchor constant:-8]
        ]];
        [content addObject:cashCard];
    }

    // Detail Extra Information
    if (!DFlag(task[@"mine"])) {
        [content addObject:DLabel(DL(@"Driver_Private_Until_Claim"), 13, NO, UIColor.ppTextSecondary)];
    }
    if (detail && DText(task[@"customerName"]).length) {
        UIStackView *custStack = DStack(@[
            DLabel(DL(@"Driver_Receiver"), 11, YES, UIColor.ppTextSecondary),
            DLabel(DText(task[@"customerName"]), 16, YES, UIColor.ppTextPrimary)
        ], 2);
        [content addObject:custStack];
    }

    // Interactive Action Affordance (if not detail mode)
    if (!detail) {
        UIView *actionRow = [UIView new];
        actionRow.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *openLabel = DLabel(DL(@"Driver_Open"), 14, YES, UIColor.ppPrimary);
        openLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [actionRow addSubview:openLabel];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
        chevron.tintColor = UIColor.ppPrimary;
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        [actionRow addSubview:chevron];

        [NSLayoutConstraint activateConstraints:@[
            [openLabel.leadingAnchor constraintEqualToAnchor:actionRow.leadingAnchor],
            [openLabel.centerYAnchor constraintEqualToAnchor:actionRow.centerYAnchor],
            [openLabel.topAnchor constraintEqualToAnchor:actionRow.topAnchor constant:4],
            [openLabel.bottomAnchor constraintEqualToAnchor:actionRow.bottomAnchor constant:-4],
            [chevron.trailingAnchor constraintEqualToAnchor:actionRow.trailingAnchor],
            [chevron.centerYAnchor constraintEqualToAnchor:actionRow.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:14],
            [chevron.heightAnchor constraintEqualToConstant:14]
        ]];
        [content addObject:actionRow];
    }

    UIStackView *stack = DStack(content, 14);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
        [card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18],
        [card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7],
        [card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]
    ]];

    self.isAccessibilityElement = !detail;
    self.accessibilityLabel = [@[title.text ?: @"", statusLabel.text ?: @"", DL(@"Driver_Pickup"), DAddress(DDict(task[@"pickup"])), DL(@"Driver_Dropoff"), DAddress(DDict(task[@"dropoff"]))] componentsJoinedByString:@", "];
    self.accessibilityTraits = detail ? UIAccessibilityTraitNone : UIAccessibilityTraitButton;
    self.accessibilityHint = detail ? nil : DL(@"Driver_Open");
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:0.2 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.2 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.cardView.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
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
@property(nonatomic, strong) NSMutableArray<UIButton *> *laneButtons;
@property(nonatomic, strong) UIStackView *detailActions;
@property(nonatomic, strong) UIStackView *feedback;
@property(nonatomic, strong) UIControl *availabilityCard;
@property(nonatomic, strong) UIView *availabilityDot;
@property(nonatomic, strong) UILabel *availabilityTitleLabel;
@property(nonatomic, strong) UILabel *availabilitySubtitleLabel;
@property(nonatomic, strong) UIImageView *availabilityChevron;
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
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.uid = FIRAuth.auth.currentUser.uid ?: @"";
    self.view.backgroundColor = UIColor.ppBackground;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    // --- Elegant Header Architecture ---
    UIStackView *header = DStack(@[], 14);
    self.header = header;
    header.layoutMargins = UIEdgeInsetsMake(12, 18, 12, 18);
    header.layoutMarginsRelativeArrangement = YES;

    // 1. Top Bar Row (Beacon Badge on Leading, Utility Button on Trailing)
    UIView *topBar = [UIView new];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;

    // Fleet Subtitle Beacon Pill
    UIView *beaconPill = [UIView new];
    beaconPill.translatesAutoresizingMaskIntoConstraints = NO;
    beaconPill.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.08];
    beaconPill.layer.cornerRadius = 13;
    beaconPill.layer.cornerCurve = kCACornerCurveContinuous;
    beaconPill.layer.borderWidth = 1.0;
    beaconPill.layer.borderColor = [UIColor.ppPrimary colorWithAlphaComponent:0.18].CGColor;

    UIView *beaconDot = [UIView new];
    beaconDot.translatesAutoresizingMaskIntoConstraints = NO;
    beaconDot.backgroundColor = UIColor.ppPrimary;
    beaconDot.layer.cornerRadius = 3.5;
    [beaconPill addSubview:beaconDot];

    UILabel *caption = DLabel(DL(self.taskID.length ? @"Driver_Task_Subtitle" : @"Driver_Workspace_Subtitle"), 12, YES, UIColor.ppPrimary);
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [beaconPill addSubview:caption];

    [NSLayoutConstraint activateConstraints:@[
        [beaconDot.leadingAnchor constraintEqualToAnchor:beaconPill.leadingAnchor constant:10],
        [beaconDot.centerYAnchor constraintEqualToAnchor:beaconPill.centerYAnchor],
        [beaconDot.widthAnchor constraintEqualToConstant:7],
        [beaconDot.heightAnchor constraintEqualToConstant:7],
        [caption.leadingAnchor constraintEqualToAnchor:beaconDot.trailingAnchor constant:6],
        [caption.trailingAnchor constraintEqualToAnchor:beaconPill.trailingAnchor constant:-12],
        [caption.topAnchor constraintEqualToAnchor:beaconPill.topAnchor constant:5],
        [caption.bottomAnchor constraintEqualToAnchor:beaconPill.bottomAnchor constant:-5]
    ]];
    [topBar addSubview:beaconPill];

    // Trailing Action Squircle Button (Notifications or Back)
    UIButton *utility = [UIButton buttonWithType:UIButtonTypeSystem];
    utility.translatesAutoresizingMaskIntoConstraints = NO;
    utility.backgroundColor = UIColor.ppElevatedSurface;
    utility.layer.cornerRadius = 14;
    utility.layer.cornerCurve = kCACornerCurveContinuous;
    utility.layer.borderWidth = 1.0;
    utility.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
    utility.tintColor = UIColor.ppTextPrimary;
    UIImage *utilIcon = [UIImage systemImageNamed:self.taskID.length ? ([Language isRTL] ? @"arrow.right" : @"arrow.left") : @"bell.fill"];
    [utility setImage:utilIcon forState:UIControlStateNormal];
    [utility addTarget:self action:@selector(utilityTapped) forControlEvents:UIControlEventTouchUpInside];
    utility.accessibilityLabel = DL(self.taskID.length ? @"Driver_Back" : @"Driver_Notifications");
    self.utilityButton = utility;
    utility.hidden = !self.taskID.length && !self.onNotifications;
    [topBar addSubview:utility];

    [NSLayoutConstraint activateConstraints:@[
        [beaconPill.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor],
        [beaconPill.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [utility.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor],
        [utility.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        [utility.widthAnchor constraintEqualToConstant:40],
        [utility.heightAnchor constraintEqualToConstant:40],
        [topBar.heightAnchor constraintGreaterThanOrEqualToConstant:42]
    ]];
    [header addArrangedSubview:topBar];

    // 2. Commanding Title
    UILabel *heading = DLabel(DL(self.taskID.length ? @"Driver_Task_Title" : @"Driver_Title"), 30, YES, UIColor.ppTextPrimary);
    heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    [header addArrangedSubview:heading];

    // 3. Segmented Command Bar & Fleet Availability (Only in main run sheet mode)
    if (!self.taskID.length) {
        // --- Studio Segmented Lanes Control ---
        UIView *lanesContainer = [UIView new];
        lanesContainer.translatesAutoresizingMaskIntoConstraints = NO;
        lanesContainer.backgroundColor = UIColor.ppSecondarySurface;
        lanesContainer.layer.cornerRadius = 16;
        lanesContainer.layer.cornerCurve = kCACornerCurveContinuous;
        lanesContainer.layer.borderWidth = 1.0;
        lanesContainer.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
        self.lanesContainer = lanesContainer;

        UIStackView *lanesStack = [[UIStackView alloc] init];
        lanesStack.translatesAutoresizingMaskIntoConstraints = NO;
        lanesStack.axis = UILayoutConstraintAxisHorizontal;
        lanesStack.distribution = UIStackViewDistributionFillEqually;
        lanesStack.spacing = 4;
        [lanesContainer addSubview:lanesStack];

        [NSLayoutConstraint activateConstraints:@[
            [lanesStack.leadingAnchor constraintEqualToAnchor:lanesContainer.leadingAnchor constant:4],
            [lanesStack.trailingAnchor constraintEqualToAnchor:lanesContainer.trailingAnchor constant:-4],
            [lanesStack.topAnchor constraintEqualToAnchor:lanesContainer.topAnchor constant:4],
            [lanesStack.bottomAnchor constraintEqualToAnchor:lanesContainer.bottomAnchor constant:-4],
            [lanesContainer.heightAnchor constraintEqualToConstant:46]
        ]];

        NSArray *laneTitles = @[@"Driver_Lane_Active", @"Driver_Lane_New", @"Driver_Lane_History"];
        NSArray *laneSymbols = @[@"shippingbox.fill", @"plus.circle.fill", @"checkmark.circle.fill"];
        for (NSInteger i = 0; i < 3; i++) {
            UIButton *laneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            laneBtn.tag = i;
            laneBtn.layer.cornerRadius = 12;
            laneBtn.layer.cornerCurve = kCACornerCurveContinuous;

            UIImage *symbolImg = [[UIImage systemImageNamed:laneSymbols[i]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [laneBtn setImage:symbolImg forState:UIControlStateNormal];
            [laneBtn setTitle:DL(laneTitles[i]) forState:UIControlStateNormal];
            laneBtn.titleLabel.font = DFont(13, YES, UIFontTextStyleSubheadline);
            laneBtn.titleLabel.adjustsFontForContentSizeCategory = YES;
            laneBtn.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 6 : -6, 0, [Language isRTL] ? -6 : 6);

            [laneBtn addTarget:self action:@selector(laneTapped:) forControlEvents:UIControlEventTouchUpInside];
            [lanesStack addArrangedSubview:laneBtn];
            [self.laneButtons addObject:laneBtn];
        }
        [self updateLaneButtonAppearances];
        [header addArrangedSubview:lanesContainer];

        // --- Driver Operational Availability Card ---
        UIControl *availCard = [UIControl new];
        availCard.translatesAutoresizingMaskIntoConstraints = NO;
        availCard.backgroundColor = UIColor.ppElevatedSurface;
        availCard.layer.cornerRadius = 18;
        availCard.layer.cornerCurve = kCACornerCurveContinuous;
        availCard.layer.borderWidth = 1.0;
        availCard.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
        availCard.layer.shadowColor = UIColor.ppShadow.CGColor;
        availCard.layer.shadowOpacity = 0.04;
        availCard.layer.shadowOffset = CGSizeMake(0, 4);
        availCard.layer.shadowRadius = 8;
        [availCard addTarget:self action:@selector(toggleAvailability) forControlEvents:UIControlEventTouchUpInside];
        self.availabilityCard = availCard;

        UIView *dotContainer = [UIView new];
        dotContainer.translatesAutoresizingMaskIntoConstraints = NO;
        dotContainer.backgroundColor = [UIColor.ppTextSecondary colorWithAlphaComponent:0.12];
        dotContainer.layer.cornerRadius = 18;
        dotContainer.layer.cornerCurve = kCACornerCurveContinuous;
        [availCard addSubview:dotContainer];

        UIView *dot = [UIView new];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.backgroundColor = UIColor.ppTextSecondary;
        dot.layer.cornerRadius = 6;
        [dotContainer addSubview:dot];
        self.availabilityDot = dot;

        UIStackView *labelStack = [UIStackView new];
        labelStack.translatesAutoresizingMaskIntoConstraints = NO;
        labelStack.axis = UILayoutConstraintAxisVertical;
        labelStack.spacing = 2;
        labelStack.alignment = UIStackViewAlignmentLeading;

        UILabel *titleLbl = DLabel(DL(@"Driver_Availability_Loading"), 14, YES, UIColor.ppTextPrimary);
        titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
        self.availabilityTitleLabel = titleLbl;

        UILabel *subLbl = DLabel(DL(@"Driver_Fleet_Pending"), 12, NO, UIColor.ppTextSecondary);
        subLbl.translatesAutoresizingMaskIntoConstraints = NO;
        self.availabilitySubtitleLabel = subLbl;

        [labelStack addArrangedSubview:titleLbl];
        [labelStack addArrangedSubview:subLbl];
        [availCard addSubview:labelStack];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
        chevron.tintColor = UIColor.ppTextSecondary;
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        [availCard addSubview:chevron];
        self.availabilityChevron = chevron;

        [NSLayoutConstraint activateConstraints:@[
            [dotContainer.leadingAnchor constraintEqualToAnchor:availCard.leadingAnchor constant:14],
            [dotContainer.centerYAnchor constraintEqualToAnchor:availCard.centerYAnchor],
            [dotContainer.widthAnchor constraintEqualToConstant:36],
            [dotContainer.heightAnchor constraintEqualToConstant:36],
            [dot.centerXAnchor constraintEqualToAnchor:dotContainer.centerXAnchor],
            [dot.centerYAnchor constraintEqualToAnchor:dotContainer.centerYAnchor],
            [dot.widthAnchor constraintEqualToConstant:12],
            [dot.heightAnchor constraintEqualToConstant:12],
            [labelStack.leadingAnchor constraintEqualToAnchor:dotContainer.trailingAnchor constant:12],
            [labelStack.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8],
            [labelStack.topAnchor constraintEqualToAnchor:availCard.topAnchor constant:14],
            [labelStack.bottomAnchor constraintEqualToAnchor:availCard.bottomAnchor constant:-14],
            [chevron.trailingAnchor constraintEqualToAnchor:availCard.trailingAnchor constant:-14],
            [chevron.centerYAnchor constraintEqualToAnchor:availCard.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:14],
            [chevron.heightAnchor constraintEqualToConstant:14]
        ]];
        [header addArrangedSubview:availCard];
    }

    // Feedback Container (for Empty Deck / Messages)
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

    self.table.tableHeaderView = header;
    [self.view addSubview:self.table];
    [self.view addSubview:self.dock];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *readable = self.view.readableContentGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.dock.topAnchor],
        [self.dock.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
        [self.dock.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
        [self.dock.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-4]
    ]];

    [self adaptType];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(passiveRefresh) name:PPDriverTasksDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(passiveRefresh) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(adaptType) name:UIContentSizeCategoryDidChangeNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    for (UIStackView *stack in @[self.header, self.detailActions ?: self.header]) {
        CGFloat width = self.table.bounds.size.width;
        CGSize size = [stack systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                           withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        if (fabs(stack.frame.size.height - size.height) > 0.5 || fabs(stack.frame.size.width - width) > 0.5) {
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
        [self updateLaneButtonAppearances];
        [self renderAvailability];
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
    self.utilityButton.hidden = !self.taskID.length && !onNotifications;
}

- (BOOL)sessionMatches {
    return self.uid.length && [self.uid isEqualToString:FIRAuth.auth.currentUser.uid];
}

- (void)utilityTapped {
    if (self.taskID.length) {
        if (self.onClose) self.onClose();
    } else if (self.onNotifications) {
        self.onNotifications();
    }
}

#pragma mark - Lanes Interaction

- (void)updateLaneButtonAppearances {
    NSInteger activeIndex = [@[@"active", @"available", @"history"] indexOfObject:self.lane];
    for (NSInteger i = 0; i < self.laneButtons.count; i++) {
        UIButton *btn = self.laneButtons[i];
        BOOL isSelected = (i == activeIndex);
        if (isSelected) {
            btn.backgroundColor = UIColor.ppSurface;
            btn.tintColor = UIColor.ppPrimary;
            [btn setTitleColor:UIColor.ppPrimary forState:UIControlStateNormal];
            btn.layer.shadowColor = UIColor.ppShadow.CGColor;
            btn.layer.shadowOpacity = 0.06;
            btn.layer.shadowOffset = CGSizeMake(0, 2);
            btn.layer.shadowRadius = 4;
        } else {
            btn.backgroundColor = UIColor.clearColor;
            btn.tintColor = UIColor.ppTextSecondary;
            [btn setTitleColor:UIColor.ppTextSecondary forState:UIControlStateNormal];
            btn.layer.shadowOpacity = 0;
        }
        btn.accessibilityTraits = isSelected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
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
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.2 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            [self updateLaneButtonAppearances];
        } completion:nil];
    } else {
        [self updateLaneButtonAppearances];
    }

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

- (void)message:(NSString *)key retry:(BOOL)retry {
    [self clear:self.feedback];

    // Reinvented Fleet Empty State / Status Card
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.ppSurface;
    card.layer.cornerRadius = 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = UIColor.ppSurfaceBorder.CGColor;
    card.layer.shadowColor = UIColor.ppShadow.CGColor;
    card.layer.shadowOpacity = 0.04;
    card.layer.shadowOffset = CGSizeMake(0, 4);
    card.layer.shadowRadius = 8;

    // Soft Icon Container
    UIView *iconContainer = [UIView new];
    iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    iconContainer.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.08];
    iconContainer.layer.cornerRadius = 24;
    iconContainer.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:iconContainer];

    NSString *iconName = [self.lane isEqualToString:@"available"] ? @"sparkles.rectangle.stack.fill" : ([self.lane isEqualToString:@"history"] ? @"clock.arrow.circlepath" : @"car.side.fill");
    if ([key isEqualToString:@"Driver_Access_Denied"]) {
        iconName = @"shield.lefthalf.filled.badge.checkmark";
    }
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    iv.tintColor = UIColor.ppPrimary;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [iconContainer addSubview:iv];

    UILabel *lbl = DLabel(DL(key), 14, NO, UIColor.ppTextSecondary);
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.textAlignment = NSTextAlignmentCenter;
    [card addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [iconContainer.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iconContainer.topAnchor constraintEqualToAnchor:card.topAnchor constant:22],
        [iconContainer.widthAnchor constraintEqualToConstant:48],
        [iconContainer.heightAnchor constraintEqualToConstant:48],
        [iv.centerXAnchor constraintEqualToAnchor:iconContainer.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:iconContainer.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:24],
        [iv.heightAnchor constraintEqualToConstant:24],
        [lbl.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [lbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [lbl.topAnchor constraintEqualToAnchor:iconContainer.bottomAnchor constant:12]
    ]];

    if (retry) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.backgroundColor = [UIColor.ppPrimary colorWithAlphaComponent:0.08];
        button.tintColor = UIColor.ppPrimary;
        button.layer.cornerRadius = 14;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        [button setTitle:DL(@"Driver_Retry") forState:UIControlStateNormal];
        [button setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
        button.titleLabel.font = DFont(14, YES, UIFontTextStyleHeadline);
        button.imageEdgeInsets = UIEdgeInsetsMake(0, [Language isRTL] ? 8 : -8, 0, [Language isRTL] ? -8 : 8);
        [button addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [button.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [button.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:16],
            [button.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],
            [button.heightAnchor constraintEqualToConstant:44],
            [button.widthAnchor constraintGreaterThanOrEqualToConstant:140]
        ]];
    } else {
        [lbl.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22].active = YES;
    }

    [self.feedback addArrangedSubview:card];
    [self.view setNeedsLayout];
}

- (void)retryTapped {
    if (self.pendingCommand) [self submitPending]; else [self refresh];
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
    BOOL paused = DFlag(self.availability[@"assignmentsPaused"]);
    BOOL online = DFlag(self.availability[@"online"]);

    UIColor *accentColor = !hasFleet ? UIColor.ppWarning : (paused ? UIColor.ppWarning : (online ? UIColor.ppSuccess : UIColor.ppTextSecondary));
    self.availabilityDot.backgroundColor = accentColor;

    NSString *titleKey = !hasFleet ? @"Driver_Fleet_Pending" : (paused ? @"Driver_Dispatch_Paused" : (online ? @"Driver_Online" : @"Driver_Offline"));
    self.availabilityTitleLabel.text = DL(titleKey);
    self.availabilitySubtitleLabel.text = DL(hasFleet ? (online ? @"Driver_Go_Offline" : @"Driver_Go_Online") : @"Driver_Fleet_Pending");

    self.availabilityCard.userInteractionEnabled = hasFleet && !self.pendingCommand && !self.submitting && !self.loading;
    self.availabilityCard.alpha = self.availabilityCard.userInteractionEnabled ? 1.0 : 0.75;
    self.availabilityChevron.hidden = !hasFleet;
    [self.view setNeedsLayout];
}

- (void)toggleAvailability {
    if (!self.availability.count || self.submitting || self.pendingCommand) return;
    BOOL online = !DFlag(self.availability[@"online"]);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DL(online ? @"Driver_Go_Online" : @"Driver_Go_Offline")
                                                                   message:DL(@"Driver_Availability_Body")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:DL(online ? @"Driver_Go_Online" : @"Driver_Go_Offline") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self sessionMatches]) return;
        self.pendingAvailability = YES;
        self.pendingCommand = @{
            @"companyId": self.availability[@"companyId"] ?: @"",
            @"online": @(online),
            @"expectedRevision": self.availability[@"revision"] ?: @0,
            @"commandId": NSUUID.UUID.UUIDString
        };
        [self submitPending];
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
        [self message:@"Driver_Proof_Assistance" retry:NO];
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
