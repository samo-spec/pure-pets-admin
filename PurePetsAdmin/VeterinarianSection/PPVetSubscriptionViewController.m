//
//  PPVetSubscriptionViewController.m
//  PurePetsAdmin
//

#import "PPVetSubscriptionViewController.h"
#import "PPVetModel.h"
#import "PPVetManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "XLFormSegmentedCell.h"
#import "XLFormSwitchCell.h"

static NSString * const kTagTier      = @"subTier";
static NSString * const kTagActive    = @"subActive";
static NSString * const kTagStartDate = @"subStart";
static NSString * const kTagEndDate   = @"subEnd";
static NSString * const kTagSave      = @"saveSub";

static CGFloat const kPPVetSubHeaderHeight = 294.0;
static CGFloat const kPPVetSubHorizontalInset = 18.0;
static CGFloat const kPPVetSubGroupedCornerRadius = 22.0;

@interface _PPVetSubscriptionMetricView : UIView
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *valueLabel;
- (instancetype)initWithCaption:(NSString *)caption;
- (void)updateValue:(NSString *)value accentColor:(nullable UIColor *)accentColor;
@end

@implementation _PPVetSubscriptionMetricView

- (instancetype)initWithCaption:(NSString *)caption {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UIColor *accentColor = [UIColor ppPrimary];
        UIColor *surfaceColor = [UIColor ppBackground];
        self.backgroundColor = [surfaceColor colorWithAlphaComponent:0.84];
        self.layer.cornerRadius = 20.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = [accentColor colorWithAlphaComponent:0.10].CGColor;

        _captionLabel = [[UILabel alloc] init];
        _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _captionLabel.font = [Styling fontMedium:10];
        _captionLabel.textColor = [UIColor ppTextSecondary];
        _captionLabel.text = caption;
        _captionLabel.numberOfLines = 1;
        [self addSubview:_captionLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:17];
        _valueLabel.textColor = [UIColor ppTextPrimary];
        _valueLabel.numberOfLines = 2;
        _valueLabel.minimumScaleFactor = 0.82;
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        [self addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_captionLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [_captionLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_captionLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],

            [_valueLabel.topAnchor constraintEqualToAnchor:_captionLabel.bottomAnchor constant:6],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_valueLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
        ]];
    }
    return self;
}

- (void)updateValue:(NSString *)value accentColor:(nullable UIColor *)accentColor {
    self.valueLabel.text = value.length > 0 ? value : @"—";
    self.valueLabel.textColor = accentColor ?: [UIColor ppTextPrimary];
    self.backgroundColor = accentColor
        ? [accentColor colorWithAlphaComponent:0.12]
        : [[UIColor ppBackground] colorWithAlphaComponent:0.84];
    self.layer.borderColor = (accentColor ?: [[UIColor blackColor] colorWithAlphaComponent:0.04]).CGColor;
}

@end

@interface PPVetSubscriptionViewController ()
@property (nonatomic, strong) PPVetModel *vet;
@property (nonatomic, strong) UIView *headerRoot;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UIView *heroAccentOrbLarge;
@property (nonatomic, strong) UIView *heroAccentOrbSmall;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusPillLabel;
@property (nonatomic, strong) UILabel *planTitleLabel;
@property (nonatomic, strong) UILabel *periodLabel;
@property (nonatomic, strong) _PPVetSubscriptionMetricView *tierMetricView;
@property (nonatomic, strong) _PPVetSubscriptionMetricView *startMetricView;
@property (nonatomic, strong) _PPVetSubscriptionMetricView *endMetricView;
@property (nonatomic, strong) NSDateFormatter *headerDateFormatter;
@property (nonatomic, assign) BOOL didPlayEntrance;
@end

@implementation PPVetSubscriptionViewController

- (instancetype)initWithVet:(PPVetModel *)vet {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    self = [super initWithForm:form style:UITableViewStyleInsetGrouped];
    if (self) {
        _vet = vet;
    }
    return self;
}
/*
 Read the new section I added in BuildBits Admin iOS and apply the same section to the Console web app with full parity. Admin and Console are the same dashboard/control system, so this new section must exist and behave the same in both.

 Tasks:
 - Inspect the new Admin iOS section end-to-end
 - Identify all screens, components, fields, actions, flows, permissions, statuses, validations, and backend mappings used by this section
 - Implement the same section in Console web app
 - Keep full parity in data model, business logic, controls, and admin capabilities
 - Match create/edit/view/list/search/filter/status change/enable-disable/block-unblock/subscription/verification or any other actions already supported in Admin
 - Reuse the same backend and Firestore structure safely
 - Do not leave placeholders, partial UI, or missing actions
 - Make Console UI clean, modern, and production-ready
 - Fix any mismatch found between Admin and Console for this section

 Deliver:
 1. Full Console implementation of this Admin section
 2. Summary of everything copied/matched from Admin
 3. Any missing logic or fields added
 4. Files changed
 5. Test checklist proving Admin and Console now behave the same for this section
 
 
 
 
 
 

 
 
 
 */
#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 4.0;
    }

    self.headerDateFormatter = [[NSDateFormatter alloc] init];
    self.headerDateFormatter.dateStyle = NSDateFormatterMediumStyle;
    self.headerDateFormatter.timeStyle = NSDateFormatterNoStyle;

    [self buildForm];
    [self populateForm];
    [self setupHeader];
    [self updateDynamicSummaryAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:kLang(@"Vet_Sub_Management") showBack:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self playEntranceAnimationIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateHeaderFrameIfNeeded];
}

#pragma mark - Header

- (void)setupHeader {
    self.headerRoot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, kPPVetSubHeaderHeight)];
    self.headerRoot.backgroundColor = UIColor.clearColor;
    self.headerRoot.clipsToBounds = NO;

    UIColor *accentColor = [UIColor ppPrimary];
    UIColor *surfaceColor = [UIColor ppElevatedSurface];

    self.heroCard = [[UIView alloc] init];
    self.heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroCard.backgroundColor = surfaceColor;
    self.heroCard.layer.cornerRadius = 32.0;
    self.heroCard.layer.cornerCurve = kCACornerCurveContinuous;
    self.heroCard.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.heroCard.layer.borderColor = [accentColor colorWithAlphaComponent:0.12].CGColor;
    self.heroCard.clipsToBounds = YES;
    [self.headerRoot addSubview:self.heroCard];

    UIView *heroWash = [[UIView alloc] init];
    heroWash.translatesAutoresizingMaskIntoConstraints = NO;
    heroWash.backgroundColor = [accentColor colorWithAlphaComponent:0.07];
    heroWash.layer.cornerRadius = 28.0;
    heroWash.layer.cornerCurve = kCACornerCurveContinuous;
    [self.heroCard addSubview:heroWash];

    self.heroAccentOrbLarge = [[UIView alloc] init];
    self.heroAccentOrbLarge.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroAccentOrbLarge.backgroundColor = [accentColor colorWithAlphaComponent:0.13];
    self.heroAccentOrbLarge.layer.cornerRadius = 74.0;
    self.heroAccentOrbLarge.layer.cornerCurve = kCACornerCurveContinuous;
    [self.heroCard addSubview:self.heroAccentOrbLarge];

    self.heroAccentOrbSmall = [[UIView alloc] init];
    self.heroAccentOrbSmall.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroAccentOrbSmall.backgroundColor = [accentColor colorWithAlphaComponent:0.08];
    self.heroAccentOrbSmall.layer.cornerRadius = 46.0;
    self.heroAccentOrbSmall.layer.cornerCurve = kCACornerCurveContinuous;
    [self.heroCard addSubview:self.heroAccentOrbSmall];

    UIView *avatarSurface = [[UIView alloc] init];
    avatarSurface.translatesAutoresizingMaskIntoConstraints = NO;
    avatarSurface.backgroundColor = [accentColor colorWithAlphaComponent:0.14];
    avatarSurface.layer.cornerRadius = 36.0;
    avatarSurface.layer.cornerCurve = kCACornerCurveContinuous;
    avatarSurface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    avatarSurface.layer.borderColor = [accentColor colorWithAlphaComponent:0.18].CGColor;
    [self.heroCard addSubview:avatarSurface];

    self.avatarView = [[UIImageView alloc] init];
    self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarView.layer.cornerRadius = 29.0;
    self.avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.backgroundColor = [accentColor colorWithAlphaComponent:0.16];
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    [avatarSurface addSubview:self.avatarView];

    if (self.vet.logoURL.length > 0) {
        [self.avatarView setImageFromUrl:self.vet.logoURL
                        placeholderImage:@"veterinary"
                                     Blr:NO
                              Shimmering:YES
                              completion:nil];
    } else {
        self.avatarView.image = [UIImage systemImageNamed:@"stethoscope.circle.fill"];
        self.avatarView.tintColor = accentColor;
        self.avatarView.contentMode = UIViewContentModeCenter;
    }

    self.eyebrowLabel = [[UILabel alloc] init];
    self.eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.eyebrowLabel.font = [Styling fontMedium:12];
    self.eyebrowLabel.textColor = [UIColor ppTextSecondary];
    self.eyebrowLabel.text = kLang(@"Vet_Sub_Management");
    [self.heroCard addSubview:self.eyebrowLabel];

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [Styling fontBold:28];
    self.nameLabel.textColor = [UIColor ppTextPrimary];
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.text = self.vet.title.length > 0 ? self.vet.title : @"—";
    [self.heroCard addSubview:self.nameLabel];

    self.statusPillLabel = [[UILabel alloc] init];
    self.statusPillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPillLabel.font = [Styling fontBold:12];
    self.statusPillLabel.textAlignment = NSTextAlignmentCenter;
    self.statusPillLabel.numberOfLines = 1;
    self.statusPillLabel.adjustsFontSizeToFitWidth = YES;
    self.statusPillLabel.minimumScaleFactor = 0.78;
    self.statusPillLabel.layer.cornerRadius = 14.0;
    self.statusPillLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusPillLabel.clipsToBounds = YES;
    self.statusPillLabel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    [self.heroCard addSubview:self.statusPillLabel];

    self.planTitleLabel = [[UILabel alloc] init];
    self.planTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.planTitleLabel.font = [Styling fontBold:19];
    self.planTitleLabel.textColor = accentColor;
    self.planTitleLabel.numberOfLines = 2;
    [self.heroCard addSubview:self.planTitleLabel];

    self.periodLabel = [[UILabel alloc] init];
    self.periodLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.periodLabel.font = [Styling fontMedium:13];
    self.periodLabel.textColor = [UIColor ppTextSecondary];
    self.periodLabel.numberOfLines = 2;
    [self.heroCard addSubview:self.periodLabel];

    self.tierMetricView = [[_PPVetSubscriptionMetricView alloc] initWithCaption:kLang(@"Vet_Sub_Tier")];
    self.startMetricView = [[_PPVetSubscriptionMetricView alloc] initWithCaption:kLang(@"Vet_Sub_StartDate")];
    self.endMetricView = [[_PPVetSubscriptionMetricView alloc] initWithCaption:kLang(@"Vet_Sub_EndDate")];

    UIView *metricsShell = [[UIView alloc] init];
    metricsShell.translatesAutoresizingMaskIntoConstraints = NO;
    metricsShell.backgroundColor = [accentColor colorWithAlphaComponent:0.05];
    metricsShell.layer.cornerRadius = 26.0;
    metricsShell.layer.cornerCurve = kCACornerCurveContinuous;
    metricsShell.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    metricsShell.layer.borderColor = [accentColor colorWithAlphaComponent:0.08].CGColor;
    [self.heroCard addSubview:metricsShell];

    UIStackView *metricsStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.tierMetricView,
        self.startMetricView,
        self.endMetricView
    ]];
    metricsStack.translatesAutoresizingMaskIntoConstraints = NO;
    metricsStack.axis = UILayoutConstraintAxisHorizontal;
    metricsStack.distribution = UIStackViewDistributionFillEqually;
    metricsStack.spacing = 10.0;
    [metricsShell addSubview:metricsStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroCard.topAnchor constraintEqualToAnchor:self.headerRoot.topAnchor constant:10],
        [self.heroCard.leadingAnchor constraintEqualToAnchor:self.headerRoot.leadingAnchor constant:kPPVetSubHorizontalInset],
        [self.heroCard.trailingAnchor constraintEqualToAnchor:self.headerRoot.trailingAnchor constant:-kPPVetSubHorizontalInset],
        [self.heroCard.bottomAnchor constraintEqualToAnchor:self.headerRoot.bottomAnchor constant:-14],

        [heroWash.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:1],
        [heroWash.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:1],
        [heroWash.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-1],
        [heroWash.heightAnchor constraintEqualToConstant:150],

        [self.heroAccentOrbLarge.widthAnchor constraintEqualToConstant:148],
        [self.heroAccentOrbLarge.heightAnchor constraintEqualToConstant:148],
        [self.heroAccentOrbLarge.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:-30],
        [self.heroAccentOrbLarge.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:26],

        [self.heroAccentOrbSmall.widthAnchor constraintEqualToConstant:92],
        [self.heroAccentOrbSmall.heightAnchor constraintEqualToConstant:92],
        [self.heroAccentOrbSmall.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:76],
        [self.heroAccentOrbSmall.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-56],

        [avatarSurface.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:22],
        [avatarSurface.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-24],
        [avatarSurface.widthAnchor constraintEqualToConstant:72],
        [avatarSurface.heightAnchor constraintEqualToConstant:72],

        [self.avatarView.topAnchor constraintEqualToAnchor:avatarSurface.topAnchor constant:7],
        [self.avatarView.leadingAnchor constraintEqualToAnchor:avatarSurface.leadingAnchor constant:7],
        [self.avatarView.trailingAnchor constraintEqualToAnchor:avatarSurface.trailingAnchor constant:-7],
        [self.avatarView.bottomAnchor constraintEqualToAnchor:avatarSurface.bottomAnchor constant:-7],

        [self.statusPillLabel.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:24],
        [self.statusPillLabel.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:24],
        [self.statusPillLabel.heightAnchor constraintEqualToConstant:28],
        [self.statusPillLabel.widthAnchor constraintGreaterThanOrEqualToConstant:102],
        [self.statusPillLabel.trailingAnchor constraintLessThanOrEqualToAnchor:avatarSurface.leadingAnchor constant:-18],

        [self.eyebrowLabel.topAnchor constraintEqualToAnchor:self.statusPillLabel.bottomAnchor constant:18],
        [self.eyebrowLabel.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:24],
        [self.eyebrowLabel.trailingAnchor constraintLessThanOrEqualToAnchor:avatarSurface.leadingAnchor constant:-18],

        [self.nameLabel.topAnchor constraintEqualToAnchor:self.eyebrowLabel.bottomAnchor constant:6],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:24],
        [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:avatarSurface.leadingAnchor constant:-20],

        [self.planTitleLabel.topAnchor constraintEqualToAnchor:avatarSurface.bottomAnchor constant:18],
        [self.planTitleLabel.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:24],
        [self.planTitleLabel.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-24],
        [self.nameLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.planTitleLabel.topAnchor constant:-12],

        [self.periodLabel.topAnchor constraintEqualToAnchor:self.planTitleLabel.bottomAnchor constant:6],
        [self.periodLabel.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:24],
        [self.periodLabel.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-24],

        [metricsShell.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:20],
        [metricsShell.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-20],
        [metricsShell.bottomAnchor constraintEqualToAnchor:self.heroCard.bottomAnchor constant:-18],
        [metricsShell.heightAnchor constraintEqualToConstant:92],
        [self.periodLabel.bottomAnchor constraintLessThanOrEqualToAnchor:metricsShell.topAnchor constant:-14],

        [metricsStack.topAnchor constraintEqualToAnchor:metricsShell.topAnchor constant:10],
        [metricsStack.leadingAnchor constraintEqualToAnchor:metricsShell.leadingAnchor constant:10],
        [metricsStack.trailingAnchor constraintEqualToAnchor:metricsShell.trailingAnchor constant:-10],
        [metricsStack.bottomAnchor constraintEqualToAnchor:metricsShell.bottomAnchor constant:-10],
    ]];

    self.tableView.tableHeaderView = self.headerRoot;
}

- (void)updateHeaderFrameIfNeeded {
    if (!self.headerRoot) return;

    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) {
        width = CGRectGetWidth(self.view.bounds);
    }

    CGRect frame = self.headerRoot.frame;
    if (fabs(frame.size.width - width) > 0.5 || fabs(frame.size.height - kPPVetSubHeaderHeight) > 0.5) {
        frame.size.width = width;
        frame.size.height = kPPVetSubHeaderHeight;
        self.headerRoot.frame = frame;
        self.tableView.tableHeaderView = self.headerRoot;
    }
}

#pragma mark - Form

- (void)buildForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    // ── Tier ──
    XLFormSectionDescriptor *tierSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Vet_Sub_Tier_Section")];
    [form addFormSection:tierSection];

    XLFormRowDescriptor *tierRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagTier
                                                                         rowType:XLFormRowDescriptorTypeSelectorSegmentedControl
                                                                           title:nil];
    tierRow.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPVetSubscriptionFree) displayText:kLang(@"Vet_Sub_Free")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPVetSubscriptionBasic) displayText:kLang(@"Vet_Sub_Basic")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPVetSubscriptionPremium) displayText:kLang(@"Vet_Sub_Premium")],
    ];
    tierRow.height = 78.0;
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:tierRow];
    }
    [tierSection addFormRow:tierRow];

    // ── Active toggle ──
    XLFormSectionDescriptor *toggleSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Vet_Sub_Status_Section")];
    [form addFormSection:toggleSection];

    XLFormRowDescriptor *activeRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagActive
                                                                           rowType:XLFormRowDescriptorTypeBooleanSwitch
                                                                             title:kLang(@"Vet_Sub_Active_Toggle")];
    activeRow.height = 66.0;
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:activeRow];
    }
    [toggleSection addFormRow:activeRow];

    // ── Dates ──
    XLFormSectionDescriptor *dateSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Vet_Sub_Dates_Section")];
    [form addFormSection:dateSection];

    XLFormRowDescriptor *startRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagStartDate
                                                                          rowType:XLFormRowDescriptorTypeDateInline
                                                                            title:kLang(@"Vet_Sub_StartDate")];
    startRow.value = [NSDate date];
    startRow.height = 60.0;
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:startRow];
    }
    [dateSection addFormRow:startRow];

    XLFormRowDescriptor *endRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagEndDate
                                                                        rowType:XLFormRowDescriptorTypeDateInline
                                                                          title:kLang(@"Vet_Sub_EndDate")];
    endRow.value = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitMonth value:1 toDate:[NSDate date] options:0];
    endRow.height = 60.0;
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:endRow];
    }
    [dateSection addFormRow:endRow];

    // ── Quick durations ──
    XLFormSectionDescriptor *quickSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Vet_Sub_Quick_Section")];
    [form addFormSection:quickSection];

    NSArray *durations = @[
        @{@"tag": @"1m",  @"title": kLang(@"Vet_Sub_1Month"),  @"months": @(1)},
        @{@"tag": @"3m",  @"title": kLang(@"Vet_Sub_3Months"), @"months": @(3)},
        @{@"tag": @"6m",  @"title": kLang(@"Vet_Sub_6Months"), @"months": @(6)},
        @{@"tag": @"12m", @"title": kLang(@"Vet_Sub_1Year"),   @"months": @(12)},
    ];

    for (NSDictionary *d in durations) {
        XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:d[@"tag"]
                                                                         rowType:XLFormRowDescriptorTypeButton
                                                                           title:d[@"title"]];
        NSInteger durationMonths = [d[@"months"] integerValue];
        row.height = 56.0;
        if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
            [Styling applyGlobalStyleToRow:row];
        }
        __weak typeof(self) weakSelf = self;
        row.action.formBlock = ^(XLFormRowDescriptor *rowDescriptor) {
            [PPFunc pp_playTapEffect];
            NSDate *start = [NSDate date];
            NSDate *end = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitMonth value:durationMonths toDate:start options:0];
            [weakSelf.form formRowWithTag:kTagStartDate].value = start;
            [weakSelf.form formRowWithTag:kTagEndDate].value = end;
            [weakSelf.form formRowWithTag:kTagActive].value = @(YES);
            [weakSelf updateDynamicSummaryAnimated:YES];
            [weakSelf.tableView reloadData];
        };
        [quickSection addFormRow:row];
    }

    // ── Save ──
    XLFormSectionDescriptor *btnSection = [XLFormSectionDescriptor formSection];
    [form addFormSection:btnSection];

    XLFormRowDescriptor *saveRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagSave
                                                                         rowType:XLFormRowDescriptorTypeButton
                                                                           title:kLang(@"Vet_Sub_Save")];
    saveRow.height = 64.0;
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:saveRow];
    }
    saveRow.action.formSelector = @selector(saveTapped);
    [btnSection addFormRow:saveRow];

    self.form = form;
}

- (void)populateForm {
    PPVetModel *v = self.vet;

    NSString *tierDisplay;
    switch (v.subscriptionTier) {
        case PPVetSubscriptionBasic:   tierDisplay = kLang(@"Vet_Sub_Basic"); break;
        case PPVetSubscriptionPremium: tierDisplay = kLang(@"Vet_Sub_Premium"); break;
        default:                       tierDisplay = kLang(@"Vet_Sub_Free"); break;
    }
    [self.form formRowWithTag:kTagTier].value = [XLFormOptionsObject formOptionsObjectWithValue:@(v.subscriptionTier) displayText:tierDisplay];
    [self.form formRowWithTag:kTagActive].value = @(v.subscriptionActive);

    if (v.subscriptionStartDate) {
        [self.form formRowWithTag:kTagStartDate].value = v.subscriptionStartDate;
    }
    if (v.subscriptionEndDate) {
        [self.form formRowWithTag:kTagEndDate].value = v.subscriptionEndDate;
    }
}

#pragma mark - Dynamic Summary

- (void)formRowDescriptorValueHasChanged:(XLFormRowDescriptor *)formRow oldValue:(id)oldValue newValue:(id)newValue {
    [super formRowDescriptorValueHasChanged:formRow oldValue:oldValue newValue:newValue];
    [self updateDynamicSummaryAnimated:YES];
}

- (void)updateDynamicSummaryAnimated:(BOOL)animated {
    PPVetSubscriptionTier tier = [self currentTier];
    BOOL active = [self currentIsActive];
    NSDate *startDate = [self currentStartDate];
    NSDate *endDate = [self currentEndDate];
    BOOL expired = [self isExpiredWithEndDate:endDate active:active];

    NSString *tierName = [self titleForTier:tier];
    NSString *periodText = [self headerPeriodTextForStartDate:startDate endDate:endDate];
    NSDictionary *statusStyle = [self statusPresentationForActive:active expired:expired];
    UIColor *planAccent = statusStyle[@"foreground"];
    UIColor *endAccent = expired ? planAccent : nil;

    void (^updates)(void) = ^{
        self.eyebrowLabel.text = self.vet.localizedTypeName.length > 0 ? self.vet.localizedTypeName : kLang(@"Vet_Sub_Management");
        self.planTitleLabel.text = tierName;
        self.planTitleLabel.textColor = planAccent;
        self.periodLabel.text = periodText;

        self.statusPillLabel.text = statusStyle[@"text"];
        self.statusPillLabel.textColor = statusStyle[@"foreground"];
        self.statusPillLabel.backgroundColor = statusStyle[@"background"];
        self.statusPillLabel.layer.borderColor = [((UIColor *)statusStyle[@"foreground"]) colorWithAlphaComponent:0.16].CGColor;

        [self.tierMetricView updateValue:tierName accentColor:planAccent];
        [self.startMetricView updateValue:[self formattedDate:startDate] accentColor:nil];
        [self.endMetricView updateValue:[self formattedDate:endDate] accentColor:endAccent];
    };

    if (animated) {
        [UIView transitionWithView:self.heroCard
                          duration:0.24
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:updates
                        completion:nil];
    } else {
        updates();
    }
}

- (PPVetSubscriptionTier)currentTier {
    id tierValue = [self.form formRowWithTag:kTagTier].value;
    if ([tierValue respondsToSelector:@selector(formValue)]) {
        return (PPVetSubscriptionTier)[[tierValue formValue] integerValue];
    }
    if ([tierValue respondsToSelector:@selector(integerValue)]) {
        return (PPVetSubscriptionTier)[tierValue integerValue];
    }
    return self.vet.subscriptionTier;
}

- (BOOL)currentIsActive {
    id activeValue = [self.form formRowWithTag:kTagActive].value;
    if ([activeValue respondsToSelector:@selector(boolValue)]) {
        return [activeValue boolValue];
    }
    return self.vet.subscriptionActive;
}

- (NSDate *)currentStartDate {
    id value = [self.form formRowWithTag:kTagStartDate].value;
    return [value isKindOfClass:[NSDate class]] ? value : self.vet.subscriptionStartDate;
}

- (NSDate *)currentEndDate {
    id value = [self.form formRowWithTag:kTagEndDate].value;
    return [value isKindOfClass:[NSDate class]] ? value : self.vet.subscriptionEndDate;
}

- (BOOL)isExpiredWithEndDate:(NSDate *)endDate active:(BOOL)active {
    if (!active || !endDate) return NO;
    return [endDate compare:[NSDate date]] == NSOrderedAscending;
}

- (NSDictionary<NSString *, id> *)statusPresentationForActive:(BOOL)active expired:(BOOL)expired {
    UIColor *accentColor = [UIColor ppPrimary];
    if (expired) {
        return @{
            @"text": kLang(@"Vet_Sub_Expired"),
            @"foreground": [UIColor ppWarning],
            @"background": [[UIColor ppWarning] colorWithAlphaComponent:0.16]
        };
    }
    if (active) {
        return @{
            @"text": kLang(@"Vet_Sub_Active_Label"),
            @"foreground": accentColor,
            @"background": [accentColor colorWithAlphaComponent:0.14]
        };
    }
    return @{
        @"text": kLang(@"Vet_Sub_Inactive"),
        @"foreground": [UIColor ppTextSecondary],
        @"background": [[UIColor ppSecondarySurface] colorWithAlphaComponent:0.60]
    };
}

- (NSString *)titleForTier:(PPVetSubscriptionTier)tier {
    switch (tier) {
        case PPVetSubscriptionBasic:   return kLang(@"Vet_Sub_Basic");
        case PPVetSubscriptionPremium: return kLang(@"Vet_Sub_Premium");
        default:                       return kLang(@"Vet_Sub_Free");
    }
}

- (NSString *)formattedDate:(NSDate *)date {
    if (!date) return @"—";
    return [self.headerDateFormatter stringFromDate:date] ?: @"—";
}

- (NSString *)headerPeriodTextForStartDate:(NSDate *)startDate endDate:(NSDate *)endDate {
    NSString *typeLabel = self.vet.localizedTypeName.length > 0 ? self.vet.localizedTypeName : @"";
    NSString *rangeLabel = nil;

    if (startDate && endDate) {
        rangeLabel = [NSString stringWithFormat:@"%@ - %@", [self formattedDate:startDate], [self formattedDate:endDate]];
    } else if (startDate) {
        rangeLabel = [NSString stringWithFormat:@"%@ %@", kLang(@"Vet_Sub_StartDate"), [self formattedDate:startDate]];
    } else if (endDate) {
        rangeLabel = [NSString stringWithFormat:@"%@ %@", kLang(@"Vet_Sub_EndDate"), [self formattedDate:endDate]];
    }

    if (typeLabel.length > 0 && rangeLabel.length > 0) {
        return [NSString stringWithFormat:@"%@  •  %@", typeLabel, rangeLabel];
    }
    if (rangeLabel.length > 0) {
        return rangeLabel;
    }
    if (typeLabel.length > 0) {
        return typeLabel;
    }
    return kLang(@"Vet_Sub_Management");
}

#pragma mark - Table Styling

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    XLFormSectionDescriptor *formSection = [self.form formSectionAtIndex:section];
    if (formSection.title.length == 0) {
        return [UIView new];
    }

    UIView *container = [[UIView alloc] init];
    container.backgroundColor = UIColor.clearColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontMedium:13];
    titleLabel.textColor = [UIColor ppTextSecondary];
    titleLabel.text = formSection.title;
    [container addSubview:titleLabel];

    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    line.layer.cornerRadius = 0.5;
    [container addSubview:line];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:6],
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:kPPVetSubHorizontalInset],
        [titleLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],

        [line.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:12],
        [line.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-kPPVetSubHorizontalInset],
        [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [line.widthAnchor constraintGreaterThanOrEqualToConstant:24],
    ]];

    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    XLFormSectionDescriptor *formSection = [self.form formSectionAtIndex:section];
    return formSection.title.length > 0 ? 34.0 : 10.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == tableView.numberOfSections - 1 ? 12.0 : 16.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    UIView *footer = [[UIView alloc] init];
    footer.backgroundColor = UIColor.clearColor;
    return footer;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self.form formRowAtIndex:indexPath];
    BOOL isQuickRow = [self isQuickDurationRow:row];
    BOOL isSaveRow = [row.tag isEqualToString:kTagSave];
    UIColor *accentColor = [UIColor ppPrimary];
    UIColor *defaultSurfaceColor = [UIColor ppElevatedSurface];

    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.clipsToBounds = NO;
    cell.layer.shadowOpacity = 0.0;
    cell.separatorInset = UIEdgeInsetsZero;

    UIEdgeInsets insets = isQuickRow || isSaveRow
        ? UIEdgeInsetsMake(4.0, kPPVetSubHorizontalInset, 4.0, kPPVetSubHorizontalInset)
        : UIEdgeInsetsMake(0.0, kPPVetSubHorizontalInset, 0.0, kPPVetSubHorizontalInset);

    CGRect backgroundFrame = UIEdgeInsetsInsetRect(cell.bounds, insets);
    UIView *backgroundView = cell.backgroundView ?: [[UIView alloc] initWithFrame:backgroundFrame];
    backgroundView.frame = backgroundFrame;
    backgroundView.layer.cornerRadius = isSaveRow ? 26.0 : kPPVetSubGroupedCornerRadius;
    backgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    backgroundView.layer.maskedCorners = [self maskedCornersForIndexPath:indexPath standalone:(isQuickRow || isSaveRow)];
    backgroundView.layer.masksToBounds = YES;
    backgroundView.layer.borderWidth = isSaveRow ? 0.0 : (1.0 / UIScreen.mainScreen.scale);
    backgroundView.layer.borderColor = (isQuickRow
        ? [accentColor colorWithAlphaComponent:0.18]
        : [accentColor colorWithAlphaComponent:0.07]).CGColor;
    backgroundView.backgroundColor = isSaveRow
        ? accentColor
        : (isQuickRow ? [accentColor colorWithAlphaComponent:0.08] : defaultSurfaceColor);
    cell.backgroundView = backgroundView;

    UIView *selectedBackgroundView = cell.selectedBackgroundView ?: [[UIView alloc] initWithFrame:backgroundFrame];
    selectedBackgroundView.frame = backgroundFrame;
    selectedBackgroundView.layer.cornerRadius = backgroundView.layer.cornerRadius;
    selectedBackgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    selectedBackgroundView.layer.maskedCorners = backgroundView.layer.maskedCorners;
    selectedBackgroundView.layer.masksToBounds = YES;
    selectedBackgroundView.layer.borderWidth = backgroundView.layer.borderWidth;
    selectedBackgroundView.layer.borderColor = backgroundView.layer.borderColor;
    selectedBackgroundView.backgroundColor = isSaveRow
        ? [[UIColor whiteColor] colorWithAlphaComponent:0.14]
        : [accentColor colorWithAlphaComponent:(isQuickRow ? 0.15 : 0.07)];
    cell.selectedBackgroundView = selectedBackgroundView;

    cell.textLabel.font = [Styling fontMedium:15];
    cell.textLabel.textColor = [UIColor ppTextPrimary];
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.textAlignment = Language.alignmentForCurrentLanguage;
    cell.detailTextLabel.font = [Styling fontBold:15];
    cell.detailTextLabel.textColor = [UIColor ppTextPrimary];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textAlignment = Language.isRTL ? NSTextAlignmentLeft : NSTextAlignmentRight;

    if ([row.rowType isEqualToString:XLFormRowDescriptorTypeBooleanSwitch]) {
        cell.textLabel.font = [Styling fontBold:15];
        UISwitch *switchControl = [cell.accessoryView isKindOfClass:[UISwitch class]] ? (UISwitch *)cell.accessoryView : nil;
        switchControl.onTintColor = accentColor;
    } else if ([row.rowType isEqualToString:XLFormRowDescriptorTypeDateInline]) {
        cell.textLabel.font = [Styling fontMedium:14];
        cell.textLabel.textColor = [UIColor ppTextSecondary];
        cell.detailTextLabel.font = [Styling fontBold:15];
    } else if ([row.rowType isEqualToString:XLFormRowDescriptorTypeSelectorSegmentedControl] && [cell isKindOfClass:[XLFormSegmentedCell class]]) {
        XLFormSegmentedCell *segmentedCell = (XLFormSegmentedCell *)cell;
        segmentedCell.textLabel.textColor = UIColor.clearColor;
        segmentedCell.textLabel.font = [Styling fontMedium:1];
        segmentedCell.segmentedControl.selectedSegmentTintColor = accentColor;
        segmentedCell.segmentedControl.backgroundColor = [accentColor colorWithAlphaComponent:0.08];
        segmentedCell.segmentedControl.layer.cornerRadius = 20.0;
        segmentedCell.segmentedControl.layer.cornerCurve = kCACornerCurveContinuous;
        segmentedCell.segmentedControl.layer.masksToBounds = YES;
        segmentedCell.segmentedControl.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        segmentedCell.segmentedControl.layer.borderColor = [accentColor colorWithAlphaComponent:0.12].CGColor;
        NSDictionary *normalAttributes = @{
            NSFontAttributeName: [Styling fontMedium:13],
            NSForegroundColorAttributeName: [UIColor ppTextPrimary]
        };
        NSDictionary *selectedAttributes = @{
            NSFontAttributeName: [Styling fontBold:13],
            NSForegroundColorAttributeName: UIColor.whiteColor
        };
        [segmentedCell.segmentedControl setTitleTextAttributes:normalAttributes forState:UIControlStateNormal];
        [segmentedCell.segmentedControl setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
    } else if (isQuickRow) {
        cell.textLabel.font = [Styling fontBold:15];
        cell.textLabel.textColor = accentColor;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (isSaveRow) {
        cell.textLabel.font = [Styling fontBold:16];
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
}

- (CACornerMask)maskedCornersForIndexPath:(NSIndexPath *)indexPath standalone:(BOOL)standalone {
    if (standalone) {
        return kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }

    NSInteger rows = [self.tableView numberOfRowsInSection:indexPath.section];
    if (rows <= 1) {
        return kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    if (indexPath.row == 0) {
        return kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    if (indexPath.row == rows - 1) {
        return kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    return 0;
}

- (BOOL)isQuickDurationRow:(XLFormRowDescriptor *)row {
    if (row.tag.length == 0) return NO;
    static NSSet<NSString *> *quickTags;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        quickTags = [NSSet setWithArray:@[@"1m", @"3m", @"6m", @"12m"]];
    });
    return [quickTags containsObject:row.tag];
}

#pragma mark - Motion

- (void)playEntranceAnimationIfNeeded {
    if (self.didPlayEntrance) return;
    self.didPlayEntrance = YES;

    self.heroCard.alpha = 0.0;
    self.heroCard.transform = CGAffineTransformMakeTranslation(0, 18);
    [UIView animateWithDuration:0.55
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.heroCard.alpha = 1.0;
        self.heroCard.transform = CGAffineTransformIdentity;
    } completion:nil];

    NSArray<UITableViewCell *> *visibleCells = self.tableView.visibleCells;
    [visibleCells enumerateObjectsUsingBlock:^(UITableViewCell * _Nonnull cell, NSUInteger idx, BOOL * _Nonnull stop) {
        cell.alpha = 0.0;
        cell.transform = CGAffineTransformMakeTranslation(0, 14);
        [UIView animateWithDuration:0.44
                              delay:0.06 + (idx * 0.035)
             usingSpringWithDamping:0.9
              initialSpringVelocity:0.3
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offsetY = scrollView.contentOffset.y;
    CGAffineTransform heroTransform = CGAffineTransformIdentity;
    if (offsetY < 0.0) {
        CGFloat translateY = -offsetY * 0.08;
        CGFloat scale = MIN(1.03, 1.0 + (-offsetY / 900.0));
        heroTransform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, translateY), CGAffineTransformMakeScale(scale, scale));
    } else if (self.didPlayEntrance) {
        CGFloat translateY = MAX(-4.0, -offsetY * 0.03);
        heroTransform = CGAffineTransformMakeTranslation(0, translateY);
    }
    self.heroCard.transform = heroTransform;

    CGFloat orbOffset = MAX(-10.0, MIN(12.0, -offsetY * 0.04));
    self.heroAccentOrbLarge.transform = CGAffineTransformMakeTranslation(orbOffset, 0.0);
    self.heroAccentOrbSmall.transform = CGAffineTransformMakeTranslation(orbOffset * 0.6, offsetY < 0.0 ? 0.0 : MIN(6.0, offsetY * 0.01));
}

#pragma mark - Save

- (void)saveTapped {
    [PPFunc pp_playTapEffect];

    NSDictionary *values = [self formValues];

    NSInteger tier = PPVetSubscriptionFree;
    id tierVal = values[kTagTier];
    if ([tierVal respondsToSelector:@selector(formValue)]) {
        tier = [[tierVal formValue] integerValue];
    }

    BOOL active    = [values[kTagActive] boolValue];
    NSDate *start  = values[kTagStartDate];
    NSDate *end    = values[kTagEndDate];

    // Validate: end must be after start
    if (start && end && [end compare:start] != NSOrderedDescending) {
        [PPHUD showError:kLang(@"Error") subtitle:kLang(@"Vet_Sub_Error_DateOrder")];
        return;
    }

    [PPHUD showIndeterminateIn:self.view title:kLang(@"Vet_Saving") subtitle:nil];

    __weak typeof(self) weakSelf = self;
    [[PPVetManager sharedManager] updateSubscriptionForVetID:self.vet.vetID
                                                        tier:tier
                                                      active:active
                                                   startDate:start
                                                     endDate:end
                                                  completion:^(NSError *error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            weakSelf.vet.subscriptionTier = tier;
            weakSelf.vet.subscriptionActive = active;
            weakSelf.vet.subscriptionStartDate = start;
            weakSelf.vet.subscriptionEndDate = end;
            [weakSelf updateDynamicSummaryAnimated:YES];
            [PPHUD showSuccess:kLang(@"Success_Title") subtitle:kLang(@"Vet_Sub_Updated_Success")];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf.navigationController popViewControllerAnimated:YES];
            });
        }
    }];
}

@end
