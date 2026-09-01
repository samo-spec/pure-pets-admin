#import "PPProviderPlansViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "PPAlertHelper.h"
#import "PPFunc+Haptics.h"

// MARK: - Helper Functions & Sector Utilities

static NSString * const PPPlanCellIdentifier = @"PPProviderPlanCardCell";

static UIColor *PPSectorThemeColor(NSString * _Nullable providerType) {
    NSString *type = [providerType lowercaseString];
    if ([type isEqualToString:@"delivery_company"]) {
        return [UIColor colorWithRed:0.12 green:0.53 blue:0.90 alpha:1.0]; // Blue
    } else if ([type isEqualToString:@"marketplace"]) {
        return [UIColor colorWithRed:0.40 green:0.31 blue:0.89 alpha:1.0]; // Indigo
    } else if ([type isEqualToString:@"pharmacy"]) {
        return [UIColor colorWithRed:0.65 green:0.25 blue:0.82 alpha:1.0]; // Purple
    } else if ([type isEqualToString:@"vet"]) {
        return [UIColor colorWithRed:0.15 green:0.68 blue:0.38 alpha:1.0]; // Green
    } else if ([type isEqualToString:@"service"]) {
        return [UIColor colorWithRed:0.92 green:0.46 blue:0.14 alpha:1.0]; // Orange
    }
    return [UIColor colorWithRed:0.75 green:0.15 blue:0.30 alpha:1.0]; // Berry Primary
}

static NSString *PPSectorSymbolName(NSString * _Nullable providerType) {
    NSString *type = [providerType lowercaseString];
    if ([type isEqualToString:@"delivery_company"]) {
        return @"box.truck.fill";
    } else if ([type isEqualToString:@"marketplace"]) {
        return @"storefront.fill";
    } else if ([type isEqualToString:@"pharmacy"]) {
        return @"pills.fill";
    } else if ([type isEqualToString:@"vet"]) {
        return @"stethoscope";
    } else if ([type isEqualToString:@"service"]) {
        return @"cross.case.fill";
    }
    return @"sparkles.rectangle.stack.fill";
}

// MARK: - Forward Declarations

@class PPProviderPlanDetailViewController;
@class PPProviderPlanEditViewController;

// MARK: - NextGen V6 Plan Card Cell

@interface PPProviderPlanCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardContainer;
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *sectorBadgeLabel;
@property (nonatomic, strong) UIView *sectorBadgeView;
@property (nonatomic, strong) UILabel *statusBadgeLabel;
@property (nonatomic, strong) UIView *statusBadgeView;
@property (nonatomic, strong) UIView *statusBeaconDot;
@property (nonatomic, strong) UILabel *recommendedBadgeLabel;
@property (nonatomic, strong) UIView *recommendedBadgeView;

// Financial Horizon Strip
@property (nonatomic, strong) UIView *financialBox;
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UILabel *commissionBadgeLabel;
@property (nonatomic, strong) UIView *commissionBadgeView;
@property (nonatomic, strong) UILabel *featuresBadgeLabel;
@property (nonatomic, strong) UIView *featuresBadgeView;

// Action Indicator
@property (nonatomic, strong) UIImageView *chevronImageView;

- (void)configureWithPlan:(PPProviderPlan *)plan actionable:(BOOL)actionable;
@end

@implementation PPProviderPlanCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    self.cardContainer = [UIView new];
    self.cardContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardContainer.backgroundColor = [UIColor ppSurface];
    self.cardContainer.layer.cornerRadius = 20.0;
    self.cardContainer.layer.borderWidth = 1.0;
    self.cardContainer.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.7].CGColor;
    self.cardContainer.layer.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.04].CGColor;
    self.cardContainer.layer.shadowOffset = CGSizeMake(0, 4);
    self.cardContainer.layer.shadowRadius = 10.0;
    self.cardContainer.layer.shadowOpacity = 1.0;
    [self.contentView addSubview:self.cardContainer];

    // Sector Icon Emblem
    self.iconContainer = [UIView new];
    self.iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconContainer.layer.cornerRadius = 16.0;
    [self.cardContainer addSubview:self.iconContainer];

    self.iconImageView = [UIImageView new];
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.iconContainer addSubview:self.iconImageView];

    // Title
    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:17.0] ?: [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    self.titleLabel.textColor = [UIColor ppTextPrimary];
    self.titleLabel.textAlignment = [Language isRTL] ? NSTextAlignmentRight : NSTextAlignmentLeft;
    [self.cardContainer addSubview:self.titleLabel];

    // Sector Badge
    self.sectorBadgeView = [UIView new];
    self.sectorBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectorBadgeView.layer.cornerRadius = 8.0;
    [self.cardContainer addSubview:self.sectorBadgeView];

    self.sectorBadgeLabel = [UILabel new];
    self.sectorBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectorBadgeLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:11.5] ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    [self.sectorBadgeView addSubview:self.sectorBadgeLabel];

    // Status Badge & Beacon
    self.statusBadgeView = [UIView new];
    self.statusBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBadgeView.layer.cornerRadius = 8.0;
    [self.cardContainer addSubview:self.statusBadgeView];

    self.statusBeaconDot = [UIView new];
    self.statusBeaconDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBeaconDot.layer.cornerRadius = 3.5;
    [self.statusBadgeView addSubview:self.statusBeaconDot];

    self.statusBadgeLabel = [UILabel new];
    self.statusBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBadgeLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:11.0] ?: [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    [self.statusBadgeView addSubview:self.statusBadgeLabel];

    // Recommended Star Badge
    self.recommendedBadgeView = [UIView new];
    self.recommendedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.recommendedBadgeView.backgroundColor = [[UIColor systemYellowColor] colorWithAlphaComponent:0.15];
    self.recommendedBadgeView.layer.cornerRadius = 8.0;
    self.recommendedBadgeView.layer.borderColor = [[UIColor systemYellowColor] colorWithAlphaComponent:0.4].CGColor;
    self.recommendedBadgeView.layer.borderWidth = 0.75;
    [self.cardContainer addSubview:self.recommendedBadgeView];

    self.recommendedBadgeLabel = [UILabel new];
    self.recommendedBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.recommendedBadgeLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:10.5] ?: [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    self.recommendedBadgeLabel.textColor = [UIColor systemOrangeColor];
    self.recommendedBadgeLabel.text = kLang(@"Providers_Plans_Recommended_Badge");
    [self.recommendedBadgeView addSubview:self.recommendedBadgeLabel];

    // Financial Horizon Strip
    self.financialBox = [UIView new];
    self.financialBox.translatesAutoresizingMaskIntoConstraints = NO;
    self.financialBox.backgroundColor = [[UIColor ppBackground] colorWithAlphaComponent:0.8];
    self.financialBox.layer.cornerRadius = 14.0;
    self.financialBox.layer.borderWidth = 0.5;
    self.financialBox.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.5].CGColor;
    [self.cardContainer addSubview:self.financialBox];

    self.priceLabel = [UILabel new];
    self.priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.priceLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:15.5] ?: [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
    self.priceLabel.textColor = [UIColor ppTextPrimary];
    [self.financialBox addSubview:self.priceLabel];

    // Commission Badge
    self.commissionBadgeView = [UIView new];
    self.commissionBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.commissionBadgeView.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    self.commissionBadgeView.layer.cornerRadius = 8.0;
    [self.financialBox addSubview:self.commissionBadgeView];

    self.commissionBadgeLabel = [UILabel new];
    self.commissionBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.commissionBadgeLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:11.5] ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightBold];
    self.commissionBadgeLabel.textColor = [UIColor ppPrimary];
    [self.commissionBadgeView addSubview:self.commissionBadgeLabel];

    // Features Badge
    self.featuresBadgeView = [UIView new];
    self.featuresBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.featuresBadgeView.backgroundColor = [[UIColor systemTealColor] colorWithAlphaComponent:0.12];
    self.featuresBadgeView.layer.cornerRadius = 8.0;
    [self.financialBox addSubview:self.featuresBadgeView];

    self.featuresBadgeLabel = [UILabel new];
    self.featuresBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.featuresBadgeLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:11.5] ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    self.featuresBadgeLabel.textColor = [UIColor systemTealColor];
    [self.featuresBadgeView addSubview:self.featuresBadgeLabel];

    // Chevron
    self.chevronImageView = [UIImageView new];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.image = [UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"];
    self.chevronImageView.tintColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.4];
    self.chevronImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.cardContainer addSubview:self.chevronImageView];

    // Auto Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.cardContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
        [self.cardContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [self.cardContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [self.cardContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

        // Icon
        [self.iconContainer.topAnchor constraintEqualToAnchor:self.cardContainer.topAnchor constant:14.0],
        [self.iconContainer.leadingAnchor constraintEqualToAnchor:self.cardContainer.leadingAnchor constant:14.0],
        [self.iconContainer.widthAnchor constraintEqualToConstant:46.0],
        [self.iconContainer.heightAnchor constraintEqualToConstant:46.0],

        [self.iconImageView.centerXAnchor constraintEqualToAnchor:self.iconContainer.centerXAnchor],
        [self.iconImageView.centerYAnchor constraintEqualToAnchor:self.iconContainer.centerYAnchor],
        [self.iconImageView.widthAnchor constraintEqualToConstant:24.0],
        [self.iconImageView.heightAnchor constraintEqualToConstant:24.0],

        // Chevron
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.iconContainer.centerYAnchor],
        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.cardContainer.trailingAnchor constant:-14.0],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:14.0],
        [self.chevronImageView.heightAnchor constraintEqualToConstant:14.0],

        // Title & Badges
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.cardContainer.topAnchor constant:12.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor constant:12.0],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronImageView.leadingAnchor constant:-8.0],

        [self.sectorBadgeView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:3.0],
        [self.sectorBadgeView.leadingAnchor constraintEqualToAnchor:self.iconContainer.trailingAnchor constant:12.0],
        [self.sectorBadgeView.heightAnchor constraintEqualToConstant:20.0],

        [self.sectorBadgeLabel.leadingAnchor constraintEqualToAnchor:self.sectorBadgeView.leadingAnchor constant:6.0],
        [self.sectorBadgeLabel.trailingAnchor constraintEqualToAnchor:self.sectorBadgeView.trailingAnchor constant:-6.0],
        [self.sectorBadgeLabel.centerYAnchor constraintEqualToAnchor:self.sectorBadgeView.centerYAnchor],

        [self.statusBadgeView.centerYAnchor constraintEqualToAnchor:self.sectorBadgeView.centerYAnchor],
        [self.statusBadgeView.leadingAnchor constraintEqualToAnchor:self.sectorBadgeView.trailingAnchor constant:6.0],
        [self.statusBadgeView.heightAnchor constraintEqualToConstant:20.0],

        [self.statusBeaconDot.leadingAnchor constraintEqualToAnchor:self.statusBadgeView.leadingAnchor constant:6.0],
        [self.statusBeaconDot.centerYAnchor constraintEqualToAnchor:self.statusBadgeView.centerYAnchor],
        [self.statusBeaconDot.widthAnchor constraintEqualToConstant:7.0],
        [self.statusBeaconDot.heightAnchor constraintEqualToConstant:7.0],

        [self.statusBadgeLabel.leadingAnchor constraintEqualToAnchor:self.statusBeaconDot.trailingAnchor constant:4.0],
        [self.statusBadgeLabel.trailingAnchor constraintEqualToAnchor:self.statusBadgeView.trailingAnchor constant:-6.0],
        [self.statusBadgeLabel.centerYAnchor constraintEqualToAnchor:self.statusBadgeView.centerYAnchor],

        [self.recommendedBadgeView.centerYAnchor constraintEqualToAnchor:self.sectorBadgeView.centerYAnchor],
        [self.recommendedBadgeView.leadingAnchor constraintEqualToAnchor:self.statusBadgeView.trailingAnchor constant:6.0],
        [self.recommendedBadgeView.heightAnchor constraintEqualToConstant:20.0],

        [self.recommendedBadgeLabel.leadingAnchor constraintEqualToAnchor:self.recommendedBadgeView.leadingAnchor constant:6.0],
        [self.recommendedBadgeLabel.trailingAnchor constraintEqualToAnchor:self.recommendedBadgeView.trailingAnchor constant:-6.0],
        [self.recommendedBadgeLabel.centerYAnchor constraintEqualToAnchor:self.recommendedBadgeView.centerYAnchor],

        // Financial Box
        [self.financialBox.topAnchor constraintEqualToAnchor:self.sectorBadgeView.bottomAnchor constant:10.0],
        [self.financialBox.leadingAnchor constraintEqualToAnchor:self.cardContainer.leadingAnchor constant:12.0],
        [self.financialBox.trailingAnchor constraintEqualToAnchor:self.cardContainer.trailingAnchor constant:-12.0],
        [self.financialBox.bottomAnchor constraintEqualToAnchor:self.cardContainer.bottomAnchor constant:-12.0],

        [self.priceLabel.topAnchor constraintEqualToAnchor:self.financialBox.topAnchor constant:8.0],
        [self.priceLabel.leadingAnchor constraintEqualToAnchor:self.financialBox.leadingAnchor constant:10.0],
        [self.priceLabel.bottomAnchor constraintEqualToAnchor:self.financialBox.bottomAnchor constant:-8.0],

        [self.commissionBadgeView.centerYAnchor constraintEqualToAnchor:self.financialBox.centerYAnchor],
        [self.commissionBadgeView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.priceLabel.trailingAnchor constant:8.0],
        [self.commissionBadgeView.trailingAnchor constraintEqualToAnchor:self.featuresBadgeView.leadingAnchor constant:-6.0],
        [self.commissionBadgeView.heightAnchor constraintEqualToConstant:24.0],

        [self.commissionBadgeLabel.leadingAnchor constraintEqualToAnchor:self.commissionBadgeView.leadingAnchor constant:8.0],
        [self.commissionBadgeLabel.trailingAnchor constraintEqualToAnchor:self.commissionBadgeView.trailingAnchor constant:-8.0],
        [self.commissionBadgeLabel.centerYAnchor constraintEqualToAnchor:self.commissionBadgeView.centerYAnchor],

        [self.featuresBadgeView.centerYAnchor constraintEqualToAnchor:self.financialBox.centerYAnchor],
        [self.featuresBadgeView.trailingAnchor constraintEqualToAnchor:self.financialBox.trailingAnchor constant:-10.0],
        [self.featuresBadgeView.heightAnchor constraintEqualToConstant:24.0],

        [self.featuresBadgeLabel.leadingAnchor constraintEqualToAnchor:self.featuresBadgeView.leadingAnchor constant:8.0],
        [self.featuresBadgeLabel.trailingAnchor constraintEqualToAnchor:self.featuresBadgeView.trailingAnchor constant:-8.0],
        [self.featuresBadgeLabel.centerYAnchor constraintEqualToAnchor:self.featuresBadgeView.centerYAnchor],
    ]];
}

- (void)configureWithPlan:(PPProviderPlan *)plan actionable:(BOOL)actionable {
    (void)actionable;
    NSString *name = PPProviderLocalizedText(plan.name, plan.planID);
    self.titleLabel.text = name;

    // Sector Styling
    UIColor *sectorColor = PPSectorThemeColor(plan.providerType);
    self.iconContainer.backgroundColor = [sectorColor colorWithAlphaComponent:0.12];
    self.iconImageView.tintColor = sectorColor;
    self.iconImageView.image = [UIImage systemImageNamed:PPSectorSymbolName(plan.providerType)];

    self.sectorBadgeView.backgroundColor = [sectorColor colorWithAlphaComponent:0.10];
    self.sectorBadgeLabel.textColor = sectorColor;
    self.sectorBadgeLabel.text = PPProviderLocalizedType(plan.providerType);

    // Status
    BOOL isActive = [plan.status.lowercaseString isEqualToString:@"active"];
    UIColor *statusColor = isActive ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
    self.statusBadgeView.backgroundColor = [statusColor colorWithAlphaComponent:0.12];
    self.statusBeaconDot.backgroundColor = statusColor;
    self.statusBadgeLabel.textColor = statusColor;
    self.statusBadgeLabel.text = PPProviderLocalizedStatus(plan.status);

    // Recommended
    self.recommendedBadgeView.hidden = !plan.isRecommended;

    // Price & Billing
    NSString *costText = [plan.costType isEqualToString:@"percentage"]
        ? [NSString stringWithFormat:kLang(@"Providers_Percentage_Format"), plan.costValue]
        : PPProviderMoneyText(plan.costValue, plan.currency);
    NSString *intervalText = PPProviderLocalizedBillingInterval(plan.billingInterval);
    self.priceLabel.text = [NSString stringWithFormat:@"%@ / %@", costText, intervalText];

    // Commission
    self.commissionBadgeLabel.text = [NSString stringWithFormat:kLang(@"Providers_Percentage_Format"), plan.commissionRate];

    // Features
    if (plan.featureCount > 0) {
        self.featuresBadgeView.hidden = NO;
        self.featuresBadgeLabel.text = [NSString stringWithFormat:kLang(@"Providers_Plans_Features_Included"), (long)plan.featureCount];
    } else {
        self.featuresBadgeView.hidden = NO;
        self.featuresBadgeLabel.text = kLang(@"Providers_Plans_No_Features");
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [UIView animateWithDuration:0.15 animations:^{
        self.cardContainer.transform = highlighted ? CGAffineTransformMakeScale(0.98, 0.98) : CGAffineTransformIdentity;
        self.cardContainer.backgroundColor = highlighted ? [UIColor ppElevatedSurface] : [UIColor ppSurface];
    }];
}

@end

// MARK: - PPProviderPlansViewController Implementation

@interface PPProviderPlansViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

// Navigation Bar
@property (nonatomic, strong) UIView *customNavBar;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UILabel *navSubtitleLabel;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *addPlanButton;

// Main Content
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) PPProviderStateView *stateView;

// Header Components
@property (nonatomic, strong) UIView *tableHeaderView;
@property (nonatomic, strong) UIView *bentoHorizonView;
@property (nonatomic, strong) UILabel *totalPlansMetricLabel;
@property (nonatomic, strong) UILabel *activePlansMetricLabel;
@property (nonatomic, strong) UILabel *featuresMetricLabel;
@property (nonatomic, strong) UILabel *commissionMetricLabel;

// Filter Segment Carousel
@property (nonatomic, strong) UIScrollView *filterScrollView;
@property (nonatomic, strong) UIStackView *filterStackView;
@property (nonatomic, copy) NSString *selectedSectorFilter; // nil = all

// Search Bar
@property (nonatomic, strong) UIView *searchContainerView;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, strong) UIButton *searchClearButton;
@property (nonatomic, strong) UILabel *searchCountLabel;

// State Data
@property (nonatomic, strong) NSArray<PPProviderPlan *> *allPlans;
@property (nonatomic, strong) NSArray<PPProviderPlan *> *filteredPlans;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL isMutating;
@property (nonatomic, assign) BOOL canManage;

@end

@implementation PPProviderPlansViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.allPlans = @[];
    self.filteredPlans = @[];
    self.selectedSectorFilter = nil;

    [self pp_evaluatePermissions];
    [self pp_setupCustomNavBar];
    [self pp_setupTableView];
    [self pp_buildTableHeader];
    [self loadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_updateHeaderFrame];
}

#pragma mark - Permissions

- (void)pp_evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    BOOL canView = [staff hasPermission:kStaffPermProvidersView];
    self.canManage = [staff hasPermission:kStaffPermProvidersManage];
    if (!canView && !self.canManage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.navigationController) {
                [self.navigationController popViewControllerAnimated:YES];
            } else {
                [self dismissViewControllerAnimated:YES completion:nil];
            }
        });
    }
    self.addPlanButton.hidden = !self.canManage;
}

#pragma mark - Navigation Bar

- (void)pp_setupCustomNavBar {
    self.customNavBar = [UIView new];
    self.customNavBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.customNavBar.backgroundColor = [UIColor ppSurface];
    self.customNavBar.layer.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.04].CGColor;
    self.customNavBar.layer.shadowOffset = CGSizeMake(0, 3);
    self.customNavBar.layer.shadowRadius = 8.0;
    self.customNavBar.layer.shadowOpacity = 1.0;
    [self.view addSubview:self.customNavBar];

    // Border
    UIView *navBorder = [UIView new];
    navBorder.translatesAutoresizingMaskIntoConstraints = NO;
    navBorder.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.6];
    [self.customNavBar addSubview:navBorder];

    // Back Button
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.backButton.tintColor = [UIColor ppPrimary];
    UIImage *backIcon = [UIImage systemImageNamed:[Language isRTL] ? @"chevron.right" : @"chevron.left"
                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightBold]];
    [self.backButton setImage:backIcon forState:UIControlStateNormal];
    [self.backButton setTitle:[NSString stringWithFormat:@" %@", kLang(@"Back")] forState:UIControlStateNormal];
    self.backButton.titleLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:15.0] ?: [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    [self.backButton addTarget:self action:@selector(pp_handleBackAction) forControlEvents:UIControlEventTouchUpInside];
    [self.customNavBar addSubview:self.backButton];

    // Titles Container
    UIStackView *titleStack = [UIStackView new];
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.alignment = [Language isRTL] ? UIStackViewAlignmentTrailing : UIStackViewAlignmentLeading;
    titleStack.spacing = 1.0;
    [self.customNavBar addSubview:titleStack];

    self.navTitleLabel = [UILabel new];
    self.navTitleLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:17.5] ?: [UIFont systemFontOfSize:17.5 weight:UIFontWeightBold];
    self.navTitleLabel.textColor = [UIColor ppTextPrimary];
    self.navTitleLabel.text = kLang(@"Providers_Plans_Nav_Title");
    [titleStack addArrangedSubview:self.navTitleLabel];

    self.navSubtitleLabel = [UILabel new];
    self.navSubtitleLabel.font = [UIFont fontWithName:@"Beiruti-Regular" size:11.5] ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    self.navSubtitleLabel.textColor = [UIColor ppTextSecondary];
    self.navSubtitleLabel.text = kLang(@"Providers_Plans_Nav_Subtitle");
    [titleStack addArrangedSubview:self.navSubtitleLabel];

    // Add Plan Action Pill Button
    self.addPlanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addPlanButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.addPlanButton.backgroundColor = [UIColor ppPrimary];
    self.addPlanButton.tintColor = [UIColor whiteColor];
    self.addPlanButton.layer.cornerRadius = 16.0;
    self.addPlanButton.layer.shadowColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.3].CGColor;
    self.addPlanButton.layer.shadowOffset = CGSizeMake(0, 3);
    self.addPlanButton.layer.shadowRadius = 6.0;
    self.addPlanButton.layer.shadowOpacity = 1.0;
    [self.addPlanButton setTitle:[NSString stringWithFormat:@"+ %@", kLang(@"Providers_Plans_New")] forState:UIControlStateNormal];
    self.addPlanButton.titleLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:13.5] ?: [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    self.addPlanButton.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    [self.addPlanButton addTarget:self action:@selector(pp_presentNewPlanForm) forControlEvents:UIControlEventTouchUpInside];
    [self.customNavBar addSubview:self.addPlanButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.customNavBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.customNavBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.customNavBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.customNavBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:54.0],

        [navBorder.leadingAnchor constraintEqualToAnchor:self.customNavBar.leadingAnchor],
        [navBorder.trailingAnchor constraintEqualToAnchor:self.customNavBar.trailingAnchor],
        [navBorder.bottomAnchor constraintEqualToAnchor:self.customNavBar.bottomAnchor],
        [navBorder.heightAnchor constraintEqualToConstant:1.0],

        [self.backButton.leadingAnchor constraintEqualToAnchor:self.customNavBar.leadingAnchor constant:12.0],
        [self.backButton.bottomAnchor constraintEqualToAnchor:self.customNavBar.bottomAnchor constant:-10.0],
        [self.backButton.heightAnchor constraintEqualToConstant:34.0],

        [titleStack.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:10.0],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.addPlanButton.leadingAnchor constant:-10.0],
        [titleStack.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],

        [self.addPlanButton.trailingAnchor constraintEqualToAnchor:self.customNavBar.trailingAnchor constant:-14.0],
        [self.addPlanButton.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.addPlanButton.heightAnchor constraintEqualToConstant:32.0],
    ]];
}

- (void)pp_handleBackAction {
    [PPFunc pp_playSelectionEffect];
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Table View Setup

- (void)pp_setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor ppBackground];
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 145.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(6.0, 0.0, 110.0, 0.0);
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[PPProviderPlanCardCell class] forCellReuseIdentifier:PPPlanCellIdentifier];
    [self.view addSubview:self.tableView];

    // Refresh Control
    self.refreshControl = [UIRefreshControl new];
    self.refreshControl.tintColor = [UIColor ppPrimary];
    [self.refreshControl addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refreshControl;

    // State View
    self.stateView = [PPProviderStateView new];
    __weak typeof(self) weakSelf = self;
    self.stateView.retryHandler = ^{ [weakSelf loadData]; };
    self.tableView.backgroundView = self.stateView;

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.customNavBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - Header & Bento Horizon

- (void)pp_buildTableHeader {
    self.tableHeaderView = [UIView new];
    self.tableHeaderView.backgroundColor = [UIColor clearColor];

    // 1. Bento Grid Container
    self.bentoHorizonView = [UIView new];
    self.bentoHorizonView.translatesAutoresizingMaskIntoConstraints = NO;
    self.bentoHorizonView.backgroundColor = [UIColor ppSurface];
    self.bentoHorizonView.layer.cornerRadius = 22.0;
    self.bentoHorizonView.layer.borderWidth = 1.0;
    self.bentoHorizonView.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.7].CGColor;
    self.bentoHorizonView.layer.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.03].CGColor;
    self.bentoHorizonView.layer.shadowOffset = CGSizeMake(0, 4);
    self.bentoHorizonView.layer.shadowRadius = 8.0;
    self.bentoHorizonView.layer.shadowOpacity = 1.0;
    [self.tableHeaderView addSubview:self.bentoHorizonView];

    // 4 Bento Tiles (2x2 Grid)
    self.totalPlansMetricLabel = [UILabel new];
    self.activePlansMetricLabel = [UILabel new];
    self.featuresMetricLabel = [UILabel new];
    self.commissionMetricLabel = [UILabel new];

    UIView *tile1 = [self pp_createBentoTileWithIcon:@"rectangle.3.group.fill"
                                               color:[UIColor colorWithRed:0.40 green:0.31 blue:0.89 alpha:1.0]
                                               title:kLang(@"Providers_Plans_Bento_Total")
                                               label:self.totalPlansMetricLabel];

    UIView *tile2 = [self pp_createBentoTileWithIcon:@"checkmark.seal.fill"
                                               color:[UIColor systemGreenColor]
                                               title:kLang(@"Providers_Plans_Bento_Active")
                                               label:self.activePlansMetricLabel];

    UIView *tile3 = [self pp_createBentoTileWithIcon:@"sparkles.rectangle.stack.fill"
                                               color:[UIColor systemOrangeColor]
                                               title:kLang(@"Providers_Plans_Bento_Features")
                                               label:self.featuresMetricLabel];

    UIView *tile4 = [self pp_createBentoTileWithIcon:@"percent"
                                               color:[UIColor ppPrimary]
                                               title:kLang(@"Providers_Plans_Bento_AvgCommission")
                                               label:self.commissionMetricLabel];

    UIStackView *topRowStack = [[UIStackView alloc] initWithArrangedSubviews:@[tile1, tile2]];
    topRowStack.translatesAutoresizingMaskIntoConstraints = NO;
    topRowStack.axis = UILayoutConstraintAxisHorizontal;
    topRowStack.distribution = UIStackViewDistributionFillEqually;
    topRowStack.spacing = 10.0;

    UIStackView *bottomRowStack = [[UIStackView alloc] initWithArrangedSubviews:@[tile3, tile4]];
    bottomRowStack.translatesAutoresizingMaskIntoConstraints = NO;
    bottomRowStack.axis = UILayoutConstraintAxisHorizontal;
    bottomRowStack.distribution = UIStackViewDistributionFillEqually;
    bottomRowStack.spacing = 10.0;

    UIStackView *bentoStack = [[UIStackView alloc] initWithArrangedSubviews:@[topRowStack, bottomRowStack]];
    bentoStack.translatesAutoresizingMaskIntoConstraints = NO;
    bentoStack.axis = UILayoutConstraintAxisVertical;
    bentoStack.distribution = UIStackViewDistributionFillEqually;
    bentoStack.spacing = 10.0;
    [self.bentoHorizonView addSubview:bentoStack];

    // 2. Sector Filter Horizontal Carousel
    self.filterScrollView = [UIScrollView new];
    self.filterScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterScrollView.showsHorizontalScrollIndicator = NO;
    self.filterScrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.tableHeaderView addSubview:self.filterScrollView];

    self.filterStackView = [UIStackView new];
    self.filterStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterStackView.axis = UILayoutConstraintAxisHorizontal;
    self.filterStackView.spacing = 8.0;
    self.filterStackView.alignment = UIStackViewAlignmentCenter;
    [self.filterScrollView addSubview:self.filterStackView];

    [self pp_populateFilterChips];

    // 3. Search & Filter Bar
    self.searchContainerView = [UIView new];
    self.searchContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchContainerView.backgroundColor = [UIColor ppSurface];
    self.searchContainerView.layer.cornerRadius = 16.0;
    self.searchContainerView.layer.borderWidth = 1.0;
    self.searchContainerView.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.7].CGColor;
    [self.tableHeaderView addSubview:self.searchContainerView];

    UIImageView *searchIcon = [UIImageView new];
    searchIcon.translatesAutoresizingMaskIntoConstraints = NO;
    searchIcon.image = [UIImage systemImageNamed:@"magnifyingglass"];
    searchIcon.tintColor = [UIColor ppTextSecondary];
    searchIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.searchContainerView addSubview:searchIcon];

    self.searchTextField = [UITextField new];
    self.searchTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchTextField.font = [UIFont fontWithName:@"Beiruti-Medium" size:14.5] ?: [UIFont systemFontOfSize:14.5];
    self.searchTextField.textColor = [UIColor ppTextPrimary];
    self.searchTextField.placeholder = kLang(@"Providers_Plans_SearchPlaceholder");
    self.searchTextField.textAlignment = [Language isRTL] ? NSTextAlignmentRight : NSTextAlignmentLeft;
    self.searchTextField.delegate = self;
    [self.searchTextField addTarget:self action:@selector(pp_searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.searchContainerView addSubview:self.searchTextField];

    self.searchClearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.searchClearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchClearButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.searchClearButton.tintColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.6];
    self.searchClearButton.hidden = YES;
    [self.searchClearButton addTarget:self action:@selector(pp_clearSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.searchContainerView addSubview:self.searchClearButton];

    // Count Pill
    self.searchCountLabel = [UILabel new];
    self.searchCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchCountLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:12.0] ?: [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.searchCountLabel.textColor = [UIColor ppTextSecondary];
    self.searchCountLabel.textAlignment = [Language isRTL] ? NSTextAlignmentRight : NSTextAlignmentLeft;
    [self.tableHeaderView addSubview:self.searchCountLabel];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        // Bento Horizon
        [self.bentoHorizonView.topAnchor constraintEqualToAnchor:self.tableHeaderView.topAnchor constant:12.0],
        [self.bentoHorizonView.leadingAnchor constraintEqualToAnchor:self.tableHeaderView.leadingAnchor constant:16.0],
        [self.bentoHorizonView.trailingAnchor constraintEqualToAnchor:self.tableHeaderView.trailingAnchor constant:-16.0],

        [bentoStack.topAnchor constraintEqualToAnchor:self.bentoHorizonView.topAnchor constant:12.0],
        [bentoStack.leadingAnchor constraintEqualToAnchor:self.bentoHorizonView.leadingAnchor constant:12.0],
        [bentoStack.trailingAnchor constraintEqualToAnchor:self.bentoHorizonView.trailingAnchor constant:-12.0],
        [bentoStack.bottomAnchor constraintEqualToAnchor:self.bentoHorizonView.bottomAnchor constant:-12.0],

        // Filter ScrollView
        [self.filterScrollView.topAnchor constraintEqualToAnchor:self.bentoHorizonView.bottomAnchor constant:12.0],
        [self.filterScrollView.leadingAnchor constraintEqualToAnchor:self.tableHeaderView.leadingAnchor],
        [self.filterScrollView.trailingAnchor constraintEqualToAnchor:self.tableHeaderView.trailingAnchor],
        [self.filterScrollView.heightAnchor constraintEqualToConstant:40.0],

        [self.filterStackView.topAnchor constraintEqualToAnchor:self.filterScrollView.topAnchor],
        [self.filterStackView.leadingAnchor constraintEqualToAnchor:self.filterScrollView.leadingAnchor constant:16.0],
        [self.filterStackView.trailingAnchor constraintEqualToAnchor:self.filterScrollView.trailingAnchor constant:-16.0],
        [self.filterStackView.bottomAnchor constraintEqualToAnchor:self.filterScrollView.bottomAnchor],
        [self.filterStackView.heightAnchor constraintEqualToAnchor:self.filterScrollView.heightAnchor],

        // Search Bar
        [self.searchContainerView.topAnchor constraintEqualToAnchor:self.filterScrollView.bottomAnchor constant:12.0],
        [self.searchContainerView.leadingAnchor constraintEqualToAnchor:self.tableHeaderView.leadingAnchor constant:16.0],
        [self.searchContainerView.trailingAnchor constraintEqualToAnchor:self.tableHeaderView.trailingAnchor constant:-16.0],
        [self.searchContainerView.heightAnchor constraintEqualToConstant:44.0],

        [searchIcon.leadingAnchor constraintEqualToAnchor:self.searchContainerView.leadingAnchor constant:12.0],
        [searchIcon.centerYAnchor constraintEqualToAnchor:self.searchContainerView.centerYAnchor],
        [searchIcon.widthAnchor constraintEqualToConstant:18.0],
        [searchIcon.heightAnchor constraintEqualToConstant:18.0],

        [self.searchTextField.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:10.0],
        [self.searchTextField.trailingAnchor constraintEqualToAnchor:self.searchClearButton.leadingAnchor constant:-8.0],
        [self.searchTextField.centerYAnchor constraintEqualToAnchor:self.searchContainerView.centerYAnchor],

        [self.searchClearButton.trailingAnchor constraintEqualToAnchor:self.searchContainerView.trailingAnchor constant:-12.0],
        [self.searchClearButton.centerYAnchor constraintEqualToAnchor:self.searchContainerView.centerYAnchor],
        [self.searchClearButton.widthAnchor constraintEqualToConstant:20.0],
        [self.searchClearButton.heightAnchor constraintEqualToConstant:20.0],

        // Count Label
        [self.searchCountLabel.topAnchor constraintEqualToAnchor:self.searchContainerView.bottomAnchor constant:8.0],
        [self.searchCountLabel.leadingAnchor constraintEqualToAnchor:self.tableHeaderView.leadingAnchor constant:20.0],
        [self.searchCountLabel.trailingAnchor constraintEqualToAnchor:self.tableHeaderView.trailingAnchor constant:-20.0],
        [self.searchCountLabel.bottomAnchor constraintEqualToAnchor:self.tableHeaderView.bottomAnchor constant:-6.0],
    ]];

    self.tableView.tableHeaderView = self.tableHeaderView;
}

- (UIView *)pp_createBentoTileWithIcon:(NSString *)symbol color:(UIColor *)color title:(NSString *)title label:(UILabel *)metricLabel {
    UIView *tile = [UIView new];
    tile.backgroundColor = [UIColor ppBackground];
    tile.layer.cornerRadius = 14.0;
    tile.layer.borderWidth = 0.5;
    tile.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.4].CGColor;

    UIView *iconBg = [UIView new];
    iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    iconBg.backgroundColor = [color colorWithAlphaComponent:0.12];
    iconBg.layer.cornerRadius = 10.0;
    [tile addSubview:iconBg];

    UIImageView *iconView = [UIImageView new];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = [UIImage systemImageNamed:symbol];
    iconView.tintColor = color;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconBg addSubview:iconView];

    metricLabel.translatesAutoresizingMaskIntoConstraints = NO;
    metricLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:18.0] ?: [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    metricLabel.textColor = [UIColor ppTextPrimary];
    metricLabel.text = @"0";
    [tile addSubview:metricLabel];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:11.5] ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor ppTextSecondary];
    titleLabel.text = title;
    [tile addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconBg.topAnchor constraintEqualToAnchor:tile.topAnchor constant:10.0],
        [iconBg.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:10.0],
        [iconBg.widthAnchor constraintEqualToConstant:32.0],
        [iconBg.heightAnchor constraintEqualToConstant:32.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconBg.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconBg.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:18.0],
        [iconView.heightAnchor constraintEqualToConstant:18.0],

        [metricLabel.centerYAnchor constraintEqualToAnchor:iconBg.centerYAnchor],
        [metricLabel.leadingAnchor constraintEqualToAnchor:iconBg.trailingAnchor constant:8.0],
        [metricLabel.trailingAnchor constraintLessThanOrEqualToAnchor:tile.trailingAnchor constant:-8.0],

        [titleLabel.topAnchor constraintEqualToAnchor:iconBg.bottomAnchor constant:4.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:10.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-10.0],
        [titleLabel.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-8.0],
    ]];

    return tile;
}

- (void)pp_populateFilterChips {
    for (UIView *v in self.filterStackView.arrangedSubviews) {
        [self.filterStackView removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray<NSDictionary *> *filters = @[
        @{@"key": @"", @"title": kLang(@"Providers_Plans_Filter_All")},
        @{@"key": @"delivery_company", @"title": kLang(@"Providers_Plans_Filter_Delivery")},
        @{@"key": @"marketplace", @"title": kLang(@"Providers_Plans_Filter_Marketplace")},
        @{@"key": @"pharmacy", @"title": kLang(@"Providers_Plans_Filter_Pharmacy")},
        @{@"key": @"vet", @"title": kLang(@"Providers_Plans_Filter_Vet")},
        @{@"key": @"service", @"title": kLang(@"Providers_Plans_Filter_Service")},
    ];

    for (NSDictionary *filter in filters) {
        NSString *key = filter[@"key"];
        NSString *title = filter[@"title"];
        BOOL isSelected = (self.selectedSectorFilter == nil && key.length == 0) || [self.selectedSectorFilter isEqualToString:key];

        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        chip.layer.cornerRadius = 16.0;
        chip.layer.borderWidth = 1.0;
        chip.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);

        if (isSelected) {
            chip.backgroundColor = [UIColor ppPrimary];
            chip.tintColor = [UIColor whiteColor];
            chip.layer.borderColor = [UIColor ppPrimary].CGColor;
            chip.titleLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:13.0] ?: [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
        } else {
            chip.backgroundColor = [UIColor ppSurface];
            chip.tintColor = [UIColor ppTextSecondary];
            chip.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
            chip.titleLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:13.0] ?: [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        }

        [chip setTitle:title forState:UIControlStateNormal];
        chip.tag = [filters indexOfObject:filter];
        [chip addTarget:self action:@selector(pp_filterChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.filterStackView addArrangedSubview:chip];
    }
}

- (void)pp_filterChipTapped:(UIButton *)sender {
    [PPFunc pp_playSelectionEffect];
    NSArray<NSDictionary *> *filters = @[
        @{@"key": @""},
        @{@"key": @"delivery_company"},
        @{@"key": @"marketplace"},
        @{@"key": @"pharmacy"},
        @{@"key": @"vet"},
        @{@"key": @"service"},
    ];
    if (sender.tag < (NSInteger)filters.count) {
        NSString *key = filters[sender.tag][@"key"];
        self.selectedSectorFilter = key.length > 0 ? key : nil;
        [self pp_populateFilterChips];
        [self pp_applyFiltersAndReload];
    }
}

- (void)pp_updateHeaderFrame {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (!self.tableHeaderView || width <= 0.0) return;
    self.tableHeaderView.frame = CGRectMake(0, 0, width, MAX(self.tableHeaderView.frame.size.height, 1.0));
    CGSize size = [self.tableHeaderView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                      withHorizontalFittingPriority:UILayoutPriorityRequired
                                            verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.tableHeaderView.frame.size.height - ceil(size.height)) > 0.5) {
        self.tableHeaderView.frame = CGRectMake(0, 0, width, ceil(size.height));
        self.tableView.tableHeaderView = self.tableHeaderView;
    }
}

#pragma mark - Search & Filtering

- (void)pp_searchTextChanged:(UITextField *)sender {
    self.searchClearButton.hidden = sender.text.length == 0;
    [self pp_applyFiltersAndReload];
}

- (void)pp_clearSearch {
    self.searchTextField.text = @"";
    self.searchClearButton.hidden = YES;
    [self pp_applyFiltersAndReload];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)pp_applyFiltersAndReload {
    NSString *query = [self.searchTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    NSString *sector = self.selectedSectorFilter.lowercaseString;

    NSMutableArray<PPProviderPlan *> *results = [NSMutableArray array];
    for (PPProviderPlan *plan in self.allPlans) {
        // Sector Filter
        if (sector.length > 0 && ![plan.providerType.lowercaseString isEqualToString:sector]) {
            continue;
        }

        // Query Search
        if (query.length > 0) {
            NSString *nameAr = PPSafeString(plan.name[@"ar"]).lowercaseString;
            NSString *nameEn = PPSafeString(plan.name[@"en"]).lowercaseString;
            NSString *pType = PPProviderLocalizedType(plan.providerType).lowercaseString;
            NSString *interval = PPProviderLocalizedBillingInterval(plan.billingInterval).lowercaseString;

            BOOL matches = [nameAr containsString:query] ||
                           [nameEn containsString:query] ||
                           [pType containsString:query] ||
                           [interval containsString:query];
            if (!matches) continue;
        }

        [results addObject:plan];
    }

    self.filteredPlans = results.copy;
    self.searchCountLabel.text = [NSString stringWithFormat:@"عرض %lu من إجمالي %lu باقات",
                                  (unsigned long)self.filteredPlans.count,
                                  (unsigned long)self.allPlans.count];
    [self pp_updateState];
    [self.tableView reloadData];
}

#pragma mark - Data Loading

- (void)loadData {
    if (self.isLoading || self.isMutating) return;
    self.isLoading = YES;
    self.currentError = nil;
    [self pp_updateState];

    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchPlansWithCompletion:^(NSArray<PPProviderPlan *> *plans, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            [self.refreshControl endRefreshing];
            self.currentError = error;
            if (!error) {
                self.allPlans = plans ?: @[];
                [self pp_updateBentoMetrics];
                [self pp_applyFiltersAndReload];
            } else {
                [self pp_updateState];
                if (self.allPlans.count > 0) {
                    [PPAlertHelper showAlertIn:self title:kLang(@"Providers_Plans_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
                }
            }
        });
    }];
}

- (void)pp_updateBentoMetrics {
    NSUInteger total = self.allPlans.count;
    NSUInteger active = 0;
    NSUInteger totalFeatures = 0;
    double commissionSum = 0.0;

    for (PPProviderPlan *plan in self.allPlans) {
        if ([plan.status.lowercaseString isEqualToString:@"active"]) active++;
        totalFeatures += MAX(plan.featureCount, 0);
        commissionSum += plan.commissionRate;
    }

    double avgCommission = total > 0 ? (commissionSum / (double)total) : 0.0;

    self.totalPlansMetricLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)total];
    self.activePlansMetricLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)active];
    self.featuresMetricLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)totalFeatures];
    self.commissionMetricLabel.text = [NSString stringWithFormat:@"%.1f%%", avgCommission];
}

- (void)pp_updateState {
    self.stateView.hidden = self.filteredPlans.count > 0;
    if (self.filteredPlans.count > 0) return;
    if (self.isLoading) {
        [self.stateView showLoadingWithTitle:kLang(@"Providers_Plans_Loading") subtitle:kLang(@"Providers_Plans_Subtitle")];
    } else if (self.currentError) {
        [self.stateView showErrorWithTitle:kLang(@"Providers_Plans_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
    } else {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Plans_Empty") subtitle:kLang(@"Providers_Plans_Empty_Subtitle") symbol:@"sparkles.rectangle.stack"];
    }
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.filteredPlans.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPProviderPlanCardCell *cell = [tableView dequeueReusableCellWithIdentifier:PPPlanCellIdentifier forIndexPath:indexPath];
    PPProviderPlan *plan = self.filteredPlans[(NSUInteger)indexPath.row];
    [cell configureWithPlan:plan actionable:self.canManage];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.filteredPlans.count) return;
    PPProviderPlan *plan = self.filteredPlans[(NSUInteger)indexPath.row];
    [self pp_presentPlanDetailViewController:plan];
}

#pragma mark - Plan Actions & Presenters

- (void)pp_presentPlanDetailViewController:(PPProviderPlan *)plan {
    [PPFunc pp_playSelectionEffect];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:PPProviderLocalizedText(plan.name, plan.planID)
                                                                   message:kLang(@"Providers_Plans_Actions")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if (self.canManage) {
        // Toggle Status Action
        BOOL isActive = [plan.status.lowercaseString isEqualToString:@"active"];
        NSString *toggleTitle = isActive ? kLang(@"Providers_Plans_Toggle_Suspend") : kLang(@"Providers_Plans_Toggle_Active");
        [sheet addAction:[UIAlertAction actionWithTitle:toggleTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self pp_togglePlanStatus:plan];
        }]];

        // Edit Plan Action
        [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Plans_Edit_Action") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self pp_presentEditPlanForm:plan];
        }]];

        // Delete Plan Action
        [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Delete") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [self pp_confirmDeletePlan:plan];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 0, 0);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pp_togglePlanStatus:(PPProviderPlan *)plan {
    BOOL isActive = [plan.status.lowercaseString isEqualToString:@"active"];
    NSString *newStatus = isActive ? @"inactive" : @"active";

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"planId"] = plan.planID;
    payload[@"providerType"] = plan.providerType ?: @"";
    payload[@"status"] = newStatus;
    payload[@"name"] = plan.name ?: @{};
    payload[@"description"] = plan.planDescription ?: @{};
    payload[@"costType"] = plan.costType ?: @"price";
    payload[@"costValue"] = @(plan.costValue);
    payload[@"priceAmount"] = @(plan.costValue);
    payload[@"currency"] = plan.currency ?: @"QAR";
    payload[@"billingInterval"] = plan.billingInterval ?: @"monthly";
    payload[@"percentageBasis"] = @"item";
    payload[@"platformCommissionRate"] = @(plan.commissionRate);
    payload[@"recommended"] = @(plan.isRecommended);

    [self pp_savePlanPayload:payload];
}

- (void)pp_presentNewPlanForm {
    [PPFunc pp_playSelectionEffect];
    if (!self.canManage || self.isMutating) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Providers_Plans_SelectType")
                                                                    message:kLang(@"Providers_Plans_SelectType_Subtitle")
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary *> *typeOptions = @[
        @{@"value": @"delivery_company", @"title": PPProviderLocalizedType(@"delivery_company")},
        @{@"value": @"service", @"title": PPProviderLocalizedType(@"service")},
        @{@"value": @"marketplace", @"title": PPProviderLocalizedType(@"marketplace")},
        @{@"value": @"pharmacy", @"title": PPProviderLocalizedType(@"pharmacy")},
        @{@"value": @"vet", @"title": PPProviderLocalizedType(@"vet")},
    ];

    for (NSDictionary *opt in typeOptions) {
        [sheet addAction:[UIAlertAction actionWithTitle:opt[@"title"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self pp_showPlanInputFormForType:opt[@"value"] existingPlan:nil];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.addPlanButton;
        popover.sourceRect = self.addPlanButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pp_presentEditPlanForm:(PPProviderPlan *)plan {
    [self pp_showPlanInputFormForType:plan.providerType existingPlan:plan];
}

- (void)pp_showPlanInputFormForType:(NSString *)providerType existingPlan:(PPProviderPlan * _Nullable)existingPlan {
    NSString *title = existingPlan ? kLang(@"Providers_Plans_Edit_Title") : kLang(@"Providers_Plans_Create_Title");
    UIAlertController *form = [UIAlertController alertControllerWithTitle:title
                                                                   message:PPProviderLocalizedType(providerType)
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = kLang(@"Providers_Plans_NameEn");
        field.text = PPSafeString(existingPlan.name[@"en"]);
    }];
    [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = kLang(@"Providers_Plans_NameAr");
        field.text = PPSafeString(existingPlan.name[@"ar"]);
        field.textAlignment = NSTextAlignmentRight;
    }];
    [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = [NSString stringWithFormat:@"%@ (QAR)", kLang(@"Providers_Plans_Price")];
        field.keyboardType = UIKeyboardTypeDecimalPad;
        if (existingPlan) field.text = [NSString stringWithFormat:@"%.2f", existingPlan.costValue];
    }];
    [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = [NSString stringWithFormat:@"%@ (%%)", kLang(@"Providers_Plans_CommissionRate")];
        field.keyboardType = UIKeyboardTypeDecimalPad;
        if (existingPlan) field.text = [NSString stringWithFormat:@"%.2f", existingPlan.commissionRate];
    }];

    UIAlertAction *save = [UIAlertAction actionWithTitle:kLang(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *nameEn = [form.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *nameAr = [form.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        double amount = form.textFields[2].text.doubleValue;
        double commission = form.textFields[3].text.doubleValue;

        if (nameEn.length == 0 || nameAr.length == 0 || amount < 0.0 || commission < 0.0 || commission > 100.0) {
            [PPAlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"Providers_Plans_Invalid_Form")];
            return;
        }

        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        if (existingPlan.planID.length > 0) payload[@"planId"] = existingPlan.planID;
        payload[@"providerType"] = providerType;
        payload[@"status"] = existingPlan ? (existingPlan.status ?: @"active") : @"active";
        payload[@"name"] = @{@"en": nameEn, @"ar": nameAr};
        payload[@"description"] = @{@"en": @"", @"ar": @""};
        payload[@"costType"] = @"price";
        payload[@"costValue"] = @(amount);
        payload[@"priceAmount"] = @(amount);
        payload[@"currency"] = @"QAR";
        payload[@"billingInterval"] = existingPlan.billingInterval ?: @"monthly";
        payload[@"percentageBasis"] = @"item";
        payload[@"percentageCustomLabel"] = @"";
        payload[@"platformCommissionRate"] = @(commission);
        payload[@"trialDays"] = @0;
        payload[@"rank"] = existingPlan ? @(existingPlan.rank) : @(self.allPlans.count);
        payload[@"recommended"] = @(existingPlan ? existingPlan.isRecommended : NO);
        payload[@"features"] = existingPlan.features ?: @[];

        [self pp_savePlanPayload:payload];
    }];

    [form addAction:save];
    [form addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:form animated:YES completion:nil];
}

- (void)pp_savePlanPayload:(NSDictionary *)payload {
    self.isMutating = YES;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] savePlan:payload completion:^(NSString *planID, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isMutating = NO;
            if (error) {
                [PPAlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            (void)planID;
            [PPFunc pp_playSuccessEffect];
            [self loadData];
        });
    }];
}

- (void)pp_confirmDeletePlan:(PPProviderPlan *)plan {
    [PPAlertHelper showConfirmationIn:self
                                title:kLang(@"Providers_Plans_Delete_Title")
                             subtitle:kLang(@"Providers_Plans_Delete_Explanation")
                        confirmButton:kLang(@"Delete")
                         cancelButton:kLang(@"Cancel")
                                 icon:nil
                         confirmBlock:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        [self pp_deletePlan:plan];
    } cancelBlock:nil];
}

- (void)pp_deletePlan:(PPProviderPlan *)plan {
    self.isMutating = YES;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] deletePlan:plan.planID completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isMutating = NO;
            if (error) {
                [PPAlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            [PPFunc pp_playSuccessEffect];
            [self loadData];
        });
    }];
}

@end
