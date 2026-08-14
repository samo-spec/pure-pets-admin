#import "UsersListVC.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPUserCell.h"
#import "UserManagementController.h"
#import "RPManager.h"
#import "FUManager.h"
#import "Styling.h"
#import "Language.h"
#import "PPFunc.h"
#import "PPToast.h"
#import "PPDesignTokens.h"
#import "PPStaffAuth.h"
#import <objc/runtime.h>
@import Firebase;
@import FirebaseAuth;
#define RPM [RPManager shared]

static CGFloat const PPUsersListHorizontalInset = 16.0;
static CGFloat const PPUsersListHeaderCardHeight = 256.0;
static CGFloat const PPUsersListCustomerHeaderHeight = 184.0;
static CGFloat const PPUsersListRowHeight = 92.0;

static UIColor *PPUsersListBackgroundColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPUsersListPrimaryColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPUsersListPrimaryTextColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPUsersListSecondaryTextColor(void) {
    return [UIColor ppTextSecondary];
}

static NSString *PPUsersResolvedAccountStatus(UserModel *user) {
    NSString *status = [[user.accountStatus ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (status.length > 0) return status;
    return user.isBlocked ? @"blocked" : @"active";
}

static NSString *PPUsersLocalizedCount(NSInteger count) {
    return [NSNumberFormatter localizedStringFromNumber:@(count) numberStyle:NSNumberFormatterDecimalStyle];
}

@interface PPUsersPassthroughHeaderView : UIView
@property (nonatomic, weak) UIView *passthroughView;
@end

@implementation PPUsersPassthroughHeaderView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (!hitView) return nil;

    UIView *candidate = hitView;
    while (candidate && candidate != self) {
        if ([candidate isKindOfClass:UIControl.class]) return hitView;
        candidate = candidate.superview;
    }
    return self.passthroughView ?: self;
}

@end

#pragma mark - PPUsersSummaryHeaderView

@interface PPUsersSummaryHeaderView : UIView
@property (nonatomic, strong) UILabel *totalVal;
@property (nonatomic, strong) UILabel *activeVal;
@property (nonatomic, strong) UILabel *verifiedVal;
@property (nonatomic, strong) UILabel *attentionVal;
@property (nonatomic, strong) UIView *railView;
@property (nonatomic, assign) BOOL usesCustomerCopy;
@property (nonatomic, strong) UIStackView *metricsStack;
@property (nonatomic, copy) NSArray<UIStackView *> *metricContentStacks;
@property (nonatomic, copy) NSArray<UILabel *> *metricTitleLabels;
@property (nonatomic, copy) NSArray<UIView *> *metricSeparators;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *metricEqualWidthConstraints;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *metricEqualHeightConstraints;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *separatorWidthConstraints;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *separatorHeightConstraints;

- (instancetype)initWithCustomerCopy:(BOOL)usesCustomerCopy;
- (void)updateWithTotal:(NSInteger)total active:(NSInteger)active verified:(NSInteger)verified attention:(NSInteger)attention;
- (void)setupCustomerLedgerUI;
- (UIStackView *)makeLedgerMetricWithTitleKey:(NSString *)titleKey valLabel:(UILabel * __strong *)valLabel color:(UIColor *)color;
- (void)updateCustomerLedgerLayout;
@end

@implementation PPUsersSummaryHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithCustomerCopy:(BOOL)usesCustomerCopy {
    if (self = [super initWithFrame:CGRectZero]) {
        _usesCustomerCopy = usesCustomerCopy;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    if (self.usesCustomerCopy) {
        [self setupCustomerLedgerUI];
        return;
    }

    BOOL accessibilityCategory = UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory);
    self.railView = [UIView new];
    self.railView.translatesAutoresizingMaskIntoConstraints = NO;
    self.railView.backgroundColor = [UIColor ppSurface];
    self.railView.layer.cornerRadius = PPCornerSmall;
    self.railView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.railView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    self.railView.layer.masksToBounds = YES;
    [self addSubview:self.railView];

    UIStackView *row = [[UIStackView alloc] init];
    row.axis = accessibilityCategory ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 0.0;
    row.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.railView addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [self.railView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.railView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.railView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.railView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [row.topAnchor constraintEqualToAnchor:self.railView.topAnchor],
        [row.leadingAnchor constraintEqualToAnchor:self.railView.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.railView.trailingAnchor],
        [row.bottomAnchor constraintEqualToAnchor:self.railView.bottomAnchor]
    ]];

    NSString *totalKey = self.usesCustomerCopy ? @"MissionControl_Customers_Metric_Total" : @"Total_Users";
    NSString *activeKey = self.usesCustomerCopy ? @"MissionControl_Customers_Metric_Active" : @"Active_Users";
    NSString *verifiedKey = self.usesCustomerCopy ? @"MissionControl_Customers_Metric_Verified" : @"Verified_Users";
    NSString *attentionKey = self.usesCustomerCopy ? @"MissionControl_Customers_Metric_Attention" : @"Blocked";
    UIView *total = [self makeMetricWithTitleKey:totalKey valLabel:&_totalVal color:PPUsersListPrimaryTextColor()];
    UIView *active = [self makeMetricWithTitleKey:activeKey valLabel:&_activeVal color:[UIColor ppSuccess]];
    UIView *verified = [self makeMetricWithTitleKey:verifiedKey valLabel:&_verifiedVal color:[UIColor ppInfo]];
    UIView *attention = [self makeMetricWithTitleKey:attentionKey valLabel:&_attentionVal color:[UIColor ppWarning]];
    NSArray<UIView *> *metrics = @[total, active, verified, attention];
    for (NSInteger index = 0; index < (NSInteger)metrics.count; index++) {
        UIView *metric = metrics[index];
        [row addArrangedSubview:metric];
        if (!accessibilityCategory && index > 0) {
            [metric.widthAnchor constraintEqualToAnchor:metrics.firstObject.widthAnchor].active = YES;
        }
        [metric.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;
        if (index < (NSInteger)metrics.count - 1) {
            UIView *separator = [UIView new];
            separator.backgroundColor = [UIColor ppSurfaceBorder];
            [row addArrangedSubview:separator];
            if (accessibilityCategory) {
                [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
            } else {
                [separator.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
            }
        }
    }
}

- (void)setupCustomerLedgerUI {
    self.railView = [UIView new];
    self.railView.translatesAutoresizingMaskIntoConstraints = NO;
    self.railView.backgroundColor = UIColor.clearColor;
    self.railView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self addSubview:self.railView];

    self.metricsStack = [UIStackView new];
    self.metricsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.metricsStack.distribution = UIStackViewDistributionFill;
    self.metricsStack.alignment = UIStackViewAlignmentFill;
    self.metricsStack.spacing = 0.0;
    self.metricsStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.railView addSubview:self.metricsStack];

    UIStackView *total = [self makeLedgerMetricWithTitleKey:@"MissionControl_Customers_Metric_Total"
                                                   valLabel:&_totalVal
                                                      color:PPUsersListPrimaryTextColor()];
    UIStackView *active = [self makeLedgerMetricWithTitleKey:@"MissionControl_Customers_Metric_Active"
                                                    valLabel:&_activeVal
                                                       color:[UIColor ppSuccess]];
    UIStackView *verified = [self makeLedgerMetricWithTitleKey:@"MissionControl_Customers_Metric_Verified"
                                                      valLabel:&_verifiedVal
                                                         color:[UIColor ppInfo]];
    UIStackView *attention = [self makeLedgerMetricWithTitleKey:@"MissionControl_Customers_Metric_Attention"
                                                       valLabel:&_attentionVal
                                                          color:[UIColor ppWarning]];
    NSArray<UIStackView *> *metrics = @[total, active, verified, attention];
    NSMutableArray<UIView *> *separators = [NSMutableArray array];
    NSMutableArray<NSLayoutConstraint *> *equalWidths = [NSMutableArray array];
    NSMutableArray<NSLayoutConstraint *> *equalHeights = [NSMutableArray array];
    NSMutableArray<NSLayoutConstraint *> *separatorWidths = [NSMutableArray array];
    NSMutableArray<NSLayoutConstraint *> *separatorHeights = [NSMutableArray array];

    for (NSInteger index = 0; index < (NSInteger)metrics.count; index++) {
        UIView *metric = metrics[index];
        [self.metricsStack addArrangedSubview:metric];
        [metric.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;
        if (index > 0) {
            [equalWidths addObject:[metric.widthAnchor constraintEqualToAnchor:metrics.firstObject.widthAnchor]];
            [equalHeights addObject:[metric.heightAnchor constraintEqualToAnchor:metrics.firstObject.heightAnchor]];
        }
        if (index < (NSInteger)metrics.count - 1) {
            UIView *separator = [UIView new];
            separator.backgroundColor = [UIColor ppSurfaceBorder];
            separator.isAccessibilityElement = NO;
            [self.metricsStack addArrangedSubview:separator];
            [separators addObject:separator];
            [separatorWidths addObject:[separator.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]];
            [separatorHeights addObject:[separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]];
        }
    }

    self.metricContentStacks = metrics;
    self.metricTitleLabels = @[(UILabel *)[total viewWithTag:201],
                               (UILabel *)[active viewWithTag:201],
                               (UILabel *)[verified viewWithTag:201],
                               (UILabel *)[attention viewWithTag:201]];
    self.metricSeparators = separators;
    self.metricEqualWidthConstraints = equalWidths;
    self.metricEqualHeightConstraints = equalHeights;
    self.separatorWidthConstraints = separatorWidths;
    self.separatorHeightConstraints = separatorHeights;

    [NSLayoutConstraint activateConstraints:@[
        [self.railView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.railView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.railView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.railView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.metricsStack.topAnchor constraintEqualToAnchor:self.railView.topAnchor],
        [self.metricsStack.leadingAnchor constraintEqualToAnchor:self.railView.leadingAnchor],
        [self.metricsStack.trailingAnchor constraintEqualToAnchor:self.railView.trailingAnchor],
        [self.metricsStack.bottomAnchor constraintEqualToAnchor:self.railView.bottomAnchor]
    ]];
    [self updateCustomerLedgerLayout];
}

- (UIStackView *)makeLedgerMetricWithTitleKey:(NSString *)titleKey valLabel:(UILabel * __strong *)valLabel color:(UIColor *)color {
    UILabel *title = [UILabel new];
    title.text = kLang(titleKey);
    title.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:11.0]];
    title.textColor = PPUsersListSecondaryTextColor();
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 2;
    title.adjustsFontForContentSizeCategory = YES;
    title.tag = 201;

    UILabel *val = [UILabel new];
    val.text = PPUsersLocalizedCount(0);
    val.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:18.0]];
    val.textColor = color;
    val.textAlignment = NSTextAlignmentCenter;
    val.adjustsFontForContentSizeCategory = YES;
    [val setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [val setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    if (valLabel) *valLabel = val;

    UIStackView *metric = [[UIStackView alloc] initWithArrangedSubviews:@[val, title]];
    metric.axis = UILayoutConstraintAxisVertical;
    metric.alignment = UIStackViewAlignmentFill;
    metric.distribution = UIStackViewDistributionFill;
    metric.spacing = 1.0;
    metric.layoutMargins = UIEdgeInsetsMake(4.0, 4.0, 4.0, 4.0);
    metric.layoutMarginsRelativeArrangement = YES;
    metric.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    metric.isAccessibilityElement = YES;
    metric.accessibilityTraits = UIAccessibilityTraitStaticText;
    metric.accessibilityLabel = title.text ?: @"";
    metric.accessibilityValue = val.text ?: @"";
    return metric;
}

- (void)updateCustomerLedgerLayout {
    BOOL accessibilityCategory = UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory);
    self.metricsStack.axis = accessibilityCategory ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;

    if (accessibilityCategory) {
        [NSLayoutConstraint deactivateConstraints:self.metricEqualWidthConstraints];
        [NSLayoutConstraint deactivateConstraints:self.separatorWidthConstraints];
        [NSLayoutConstraint activateConstraints:self.metricEqualHeightConstraints];
        [NSLayoutConstraint activateConstraints:self.separatorHeightConstraints];
    } else {
        [NSLayoutConstraint deactivateConstraints:self.metricEqualHeightConstraints];
        [NSLayoutConstraint deactivateConstraints:self.separatorHeightConstraints];
        [NSLayoutConstraint activateConstraints:self.separatorWidthConstraints];
        [NSLayoutConstraint activateConstraints:self.metricEqualWidthConstraints];
    }

    NSArray<UILabel *> *values = @[self.totalVal, self.activeVal, self.verifiedVal, self.attentionVal];
    for (NSInteger index = 0; index < (NSInteger)self.metricContentStacks.count; index++) {
        UIStackView *metric = self.metricContentStacks[index];
        UILabel *title = self.metricTitleLabels[index];
        UILabel *value = values[index];
        [metric removeArrangedSubview:title];
        [metric removeArrangedSubview:value];
        [title removeFromSuperview];
        [value removeFromSuperview];
        if (accessibilityCategory) {
            [metric insertArrangedSubview:title atIndex:0];
            [metric insertArrangedSubview:value atIndex:1];
            metric.axis = UILayoutConstraintAxisHorizontal;
            metric.spacing = PPSpaceSM;
            metric.layoutMargins = UIEdgeInsetsMake(PPSpaceXS, PPSpaceSM, PPSpaceXS, PPSpaceSM);
            title.textAlignment = [Language alignmentForCurrentLanguage];
            value.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;
        } else {
            [metric insertArrangedSubview:value atIndex:0];
            [metric insertArrangedSubview:title atIndex:1];
            metric.axis = UILayoutConstraintAxisVertical;
            metric.spacing = 1.0;
            metric.layoutMargins = UIEdgeInsetsMake(PPSpaceXS, PPSpaceXS, PPSpaceXS, PPSpaceXS);
            title.textAlignment = NSTextAlignmentCenter;
            value.textAlignment = NSTextAlignmentCenter;
        }
    }
}

- (UIView *)makeMetricWithTitleKey:(NSString *)titleKey valLabel:(UILabel * __strong *)valLabel color:(UIColor *)color {
    UIView *metric = [UIView new];
    metric.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *title = [UILabel new];
    title.text = kLang(titleKey);
    title.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:11.0]];
    title.textColor = PPUsersListSecondaryTextColor();
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 2;
    title.adjustsFontForContentSizeCategory = YES;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.tag = 201;
    
    UILabel *val = [UILabel new];
    val.text = PPUsersLocalizedCount(0);
    val.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:18.0]];
    val.textColor = color;
    val.textAlignment = NSTextAlignmentCenter;
    val.adjustsFontForContentSizeCategory = YES;
    val.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (valLabel) *valLabel = val;
    
    [metric addSubview:title];
    [metric addSubview:val];
    
    [NSLayoutConstraint activateConstraints:@[
        [val.topAnchor constraintEqualToAnchor:metric.topAnchor constant:6.0],
        [val.leadingAnchor constraintEqualToAnchor:metric.leadingAnchor constant:4.0],
        [val.trailingAnchor constraintEqualToAnchor:metric.trailingAnchor constant:-4.0],
        [title.topAnchor constraintEqualToAnchor:val.bottomAnchor constant:1.0],
        [title.leadingAnchor constraintEqualToAnchor:metric.leadingAnchor constant:4.0],
        [title.trailingAnchor constraintEqualToAnchor:metric.trailingAnchor constant:-4.0],
        [title.bottomAnchor constraintLessThanOrEqualToAnchor:metric.bottomAnchor constant:-5.0]
    ]];

    metric.isAccessibilityElement = YES;
    metric.accessibilityTraits = UIAccessibilityTraitStaticText;

    return metric;
}

- (void)updateWithTotal:(NSInteger)total active:(NSInteger)active verified:(NSInteger)verified attention:(NSInteger)attention {
    self.totalVal.text = PPUsersLocalizedCount(total);
    self.activeVal.text = PPUsersLocalizedCount(active);
    self.verifiedVal.text = PPUsersLocalizedCount(verified);
    self.attentionVal.text = PPUsersLocalizedCount(attention);

    NSArray<UILabel *> *values = @[self.totalVal, self.activeVal, self.verifiedVal, self.attentionVal];
    for (UILabel *value in values) {
        UIView *metric = value.superview;
        UILabel *title = [metric viewWithTag:201];
        metric.accessibilityLabel = title.text ?: @"";
        metric.accessibilityValue = value.text ?: @"";
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.railView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        for (UIView *separator in self.metricSeparators) {
            separator.backgroundColor = [UIColor ppSurfaceBorder];
        }
    }
    if (self.usesCustomerCopy &&
        ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) {
        [self updateCustomerLedgerLayout];
    }
}

@end

#pragma mark - UsersListVC

@interface UsersListVC () <UITableViewDelegate, UITableViewDataSource, PPSDelegate, UserCellDelegate>
@property (nonatomic, strong) id<FIRListenerRegistration> usersReg;
@property (nonatomic, strong) PPUsersSummaryHeaderView *summaryHeader;
@property (nonatomic, strong) UIView *stickyHeaderView;
@property (nonatomic, strong) UIView *heroCardView;
@property (nonatomic, strong) UILabel *heroTitleLabel;
@property (nonatomic, strong) UILabel *heroSubtitleLabel;
@property (nonatomic, strong) UIButton *attentionButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *addUserButton;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UIImageView *stateIconView;
@property (nonatomic, strong) UILabel *stateTitleLabel;
@property (nonatomic, strong) UILabel *stateSubtitleLabel;
@property (nonatomic, strong) UIActivityIndicatorView *stateSpinner;
@property (nonatomic, strong) UIButton *stateRetryButton;
@property (nonatomic, assign) BOOL isLoadingUsers;
@property (nonatomic, assign) BOOL accessDenied;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, assign) NSInteger attentionCount;
@property (nonatomic, assign) NSUInteger listenerGeneration;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL didRunEntrance;
@property (nonatomic, assign) BOOL didCaptureNavigationBarHiddenState;
@property (nonatomic, assign) BOOL previousNavigationBarHiddenState;
@property (nonatomic, strong) NSLayoutConstraint *stickyHeaderHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heroCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *summaryHeaderHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *attentionWidthConstraint;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *customerCompactHeaderConstraints;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *customerAccessibilityHeaderConstraints;
- (void)pp_updateCustomerHeaderConstraintSet;
@end

@implementation UsersListVC
@synthesize rowDescriptor = _rowDescriptor;

- (instancetype)init {
    if (self = [super init]) {
        _viewForMode = ViewForDefault;
    }
    return self;
}

- (instancetype)initWithViewFor:(ViewFor)mode {
    if (self = [super init]) {
        _viewForMode = mode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self pp_screenTitleText];
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = nil;
    self.view.backgroundColor = PPUsersListBackgroundColor();
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.isLoadingUsers = YES;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = PPUsersListBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPUsersListRowHeight;
    self.tableView.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) {
        self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.tableView registerClass:PPUserCell.class forCellReuseIdentifier:PPUserCell.reuseIdentifier];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [self setupStateView];
    [self setupHeaderUI];
    [self pp_prepareEntranceIfNeeded];

    self.allUsers = [NSMutableArray new];
    self.filteredUsers = [NSMutableArray new];
    [self pp_updateStateView];
    self.accessDenied = [self pp_isCustomerAccountMode] && ![self pp_hasUserDirectoryAccess];
    if (self.accessDenied) {
        self.isLoadingUsers = NO;
        [self pp_refreshAttentionSignal];
        [self pp_updateStateView];
    } else {
        [self pp_startUsersListener];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_applyNoNavigationBarAnimated:animated];
    [self pp_prepareEntranceIfNeeded];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self pp_applyNoNavigationBarAnimated:NO];
    [self pp_runEntranceIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pp_restoreNavigationBarIfNeededAnimated:animated];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_applyNoNavigationBarAnimated:NO];
    [self pp_updateStickyHeaderMetrics];
    [self pp_prepareEntranceIfNeeded];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.heroCardView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        self.searchView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    }
    if ([self pp_isCustomerAccountMode] &&
        ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) {
        [self pp_updateCustomerHeaderConstraintSet];
        [self pp_updateStickyHeaderMetrics];
    }
}

- (void)dealloc {
    [self.usersReg remove];
}

#pragma mark - Users Listener

- (BOOL)pp_hasUserDirectoryAccess {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [staff hasAnyPermission:@[
        kStaffPermUsersView,
        kStaffPermUsersManage,
        kStaffPermUsersBlock,
        kStaffPermUsersFeaturesView,
        kStaffPermUsersFeaturesManage,
        kStaffPermUsersSubscriptionsView,
        kStaffPermUsersSubscriptionsManage,
        kStaffPermUsersRestrictionsView,
        kStaffPermUsersRestrictionsManage,
    ]];
}

- (BOOL)pp_isCustomerAccountMode {
    return self.viewForMode == ViewForEditAccount;
}

- (NSArray<UserModel *> *)pp_usersForCurrentMode:(NSArray<UserModel *> *)users {
    if (![self pp_isCustomerAccountMode]) return users ?: @[];

    NSPredicate *customersOnly = [NSPredicate predicateWithBlock:^BOOL(UserModel *user, NSDictionary *bindings) {
        NSString *accountType = [[user.accountType ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        return ![accountType isEqualToString:@"staff"];
    }];
    return [(users ?: @[]) filteredArrayUsingPredicate:customersOnly];
}

- (void)pp_startUsersListener {
    if ([self pp_isCustomerAccountMode] && (self.accessDenied || ![self pp_hasUserDirectoryAccess])) {
        self.accessDenied = YES;
        self.isLoadingUsers = NO;
        [self pp_refreshAttentionSignal];
        [self pp_updateStateView];
        return;
    }
    [self.usersReg remove];
    self.usersReg = nil;
    NSUInteger generation = ++self.listenerGeneration;

    self.isLoadingUsers = YES;
    self.currentError = nil;
    [self pp_refreshAttentionSignal];
    [self pp_updateStateView];

    __weak typeof(self) weakSelf = self;
    self.usersReg = [[FUManager shared] listenAllUsersWithDiffsOrderedBy:@"UserName"
                                                              ascending:YES
                                                   includeMetadataChanges:YES
                                                                  queue:dispatch_get_main_queue()
                                                               completion:^(NSArray<UserModel *> *users,
                                                                            NSArray<FIRDocumentChange *> *changes,
                                                                            FIRSnapshotMetadata *meta,
                                                                            NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.listenerGeneration) return;
        (void)changes;
        (void)meta;

        self.isLoadingUsers = NO;
        self.currentError = error;
        if (error) {
            [self pp_refreshAttentionSignal];
            [self pp_updateStateView];
            return;
        }

        self.allUsers = [[self pp_usersForCurrentMode:users] mutableCopy];
        [self _updateSummaryStats];
        [self _applyFilterAndReload];
    }];
}

- (void)pp_retryUsers {
    self.accessDenied = [self pp_isCustomerAccountMode] && ![self pp_hasUserDirectoryAccess];
    [self pp_startUsersListener];
}

- (void)setupHeaderUI {
    BOOL usesGlobalNavigation = PPCommandCenterNavigationIsManaged(self.navigationController);
    BOOL customerMode = [self pp_isCustomerAccountMode];
    PPUsersPassthroughHeaderView *stickyHeader = [PPUsersPassthroughHeaderView new];
    stickyHeader.passthroughView = self.tableView;
    self.stickyHeaderView = stickyHeader;
    self.stickyHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stickyHeaderView.backgroundColor = PPUsersListBackgroundColor();
    self.stickyHeaderView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:self.stickyHeaderView];

    self.heroCardView = [UIView new];
    self.heroCardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroCardView.backgroundColor = customerMode ? PPUsersListBackgroundColor() : [UIColor ppElevatedSurface];
    self.heroCardView.layer.cornerRadius = customerMode ? 0.0 : PPCorner16;
    self.heroCardView.layer.masksToBounds = !customerMode;
    self.heroCardView.layer.borderWidth = customerMode ? 0.0 : 1.0 / UIScreen.mainScreen.scale;
    self.heroCardView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    self.heroCardView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    if (@available(iOS 13.0, *)) {
        self.heroCardView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self.stickyHeaderView addSubview:self.heroCardView];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.3.sequence.fill"
                                                                       withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIImageSymbolWeightSemibold]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = PPUsersListPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.isAccessibilityElement = NO;
    iconView.hidden = customerMode;
    [self.heroCardView addSubview:iconView];

    if (!usesGlobalNavigation) {
        self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.closeButton.tintColor = PPUsersListPrimaryTextColor();
        self.closeButton.backgroundColor = [UIColor ppSurface];
        self.closeButton.layer.cornerRadius = PPCornerSmall;
        self.closeButton.layer.masksToBounds = YES;
        UIImage *closeImage = [UIImage systemImageNamed:[Language isRTL] ? @"arrow.right" : @"arrow.left"
                                      withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightBold]];
        [self.closeButton setImage:closeImage forState:UIControlStateNormal];
        [self.closeButton addTarget:self action:@selector(pp_closePicker) forControlEvents:UIControlEventTouchUpInside];
        self.closeButton.accessibilityLabel = kLang(@"Cancel");
        [self.heroCardView addSubview:self.closeButton];
    }

    self.addUserButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addUserButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.addUserButton.tintColor = PPOnPrimaryColor();
    self.addUserButton.backgroundColor = PPUsersListPrimaryColor();
    self.addUserButton.layer.cornerRadius = PPCornerSmall;
    self.addUserButton.layer.masksToBounds = YES;
    [self.addUserButton setImage:[UIImage systemImageNamed:@"plus"
                                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightBold]]
                         forState:UIControlStateNormal];
    [self.addUserButton addTarget:self action:@selector(didTapAddUser) forControlEvents:UIControlEventTouchUpInside];
    self.addUserButton.accessibilityLabel = kLang(@"AddUser");
    [self.heroCardView addSubview:self.addUserButton];

    NSMutableArray<UIView *> *briefingViews = [NSMutableArray array];
    if (!usesGlobalNavigation) {
        self.heroTitleLabel = [UILabel new];
        self.heroTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.heroTitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:21.0]];
        self.heroTitleLabel.textColor = PPUsersListPrimaryTextColor();
        self.heroTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        self.heroTitleLabel.adjustsFontForContentSizeCategory = YES;
        self.heroTitleLabel.numberOfLines = 2;
        self.heroTitleLabel.text = [self pp_screenTitleText];
        [briefingViews addObject:self.heroTitleLabel];
    }

    self.heroSubtitleLabel = [UILabel new];
    self.heroSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroSubtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:13.0]];
    self.heroSubtitleLabel.textColor = PPUsersListSecondaryTextColor();
    self.heroSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.heroSubtitleLabel.numberOfLines = 2;
    self.heroSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.heroSubtitleLabel.text = [self pp_screenSubtitleText];

    [briefingViews addObject:self.heroSubtitleLabel];
    UIStackView *briefingStack = [[UIStackView alloc] initWithArrangedSubviews:briefingViews];
    briefingStack.translatesAutoresizingMaskIntoConstraints = NO;
    briefingStack.axis = UILayoutConstraintAxisVertical;
    briefingStack.alignment = UIStackViewAlignmentFill;
    briefingStack.spacing = 1.0;
    briefingStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.heroCardView addSubview:briefingStack];

    self.attentionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.attentionButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.attentionButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:11.0]];
    self.attentionButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.attentionButton.titleLabel.numberOfLines = 2;
    self.attentionButton.contentHorizontalAlignment = customerMode ? UIControlContentHorizontalAlignmentLeading : UIControlContentHorizontalAlignmentCenter;
    self.attentionButton.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.attentionButton.layer.cornerRadius = customerMode ? 0.0 : PPCornerSmall;
    self.attentionButton.layer.masksToBounds = !customerMode;
    self.attentionButton.contentEdgeInsets = customerMode ? UIEdgeInsetsZero : UIEdgeInsetsMake(4.0, 8.0, 4.0, 8.0);
    [self.attentionButton addTarget:self action:@selector(pp_retryUsers) forControlEvents:UIControlEventTouchUpInside];
    [self.heroCardView addSubview:self.attentionButton];

    self.summaryHeader = [[PPUsersSummaryHeaderView alloc] initWithCustomerCopy:[self pp_isCustomerAccountMode]];
    self.summaryHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroCardView addSubview:self.summaryHeader];

    PPS *search = [[PPS alloc] initWithFrame:CGRectZero];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.delegate = self;
    search.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.textField.textAlignment = [Language alignmentForCurrentLanguage];
    search.textField.placeholder = self.searchPlaceholderText.length
        ? self.searchPlaceholderText
        : ([self pp_isCustomerAccountMode] ? kLang(@"MissionControl_Customers_Search_Placeholder") : kLang(@"SetPermissions_Search_Placeholder"));
    search.textField.accessibilityLabel = search.textField.placeholder;
    search.cornerRadius = PPCornerSmall;
    search.layer.cornerRadius = PPCornerSmall;
    search.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    search.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    if (customerMode) {
        search.textField.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:16.0]];
        search.textField.adjustsFontForContentSizeCategory = YES;
        search.backgroundColor = [UIColor ppSurface];
        search.blurEnabled = NO;
        search.shadowEnabled = NO;
        PPApplyContinuousCorners(search, PPCornerSmall);
    }
    [self pp_configureSearchAdornmentForView:search];
    [self.heroCardView addSubview:search];
    self.searchView = search;

    CGFloat heroCardHeight = [self pp_headerCardHeight];
    CGFloat summaryHeaderHeight = [self pp_summaryHeaderHeight];
    self.stickyHeaderHeightConstraint = [self.stickyHeaderView.heightAnchor constraintEqualToConstant:heroCardHeight + 28.0];
    self.heroCardHeightConstraint = [self.heroCardView.heightAnchor constraintEqualToConstant:heroCardHeight];
    self.summaryHeaderHeightConstraint = [self.summaryHeader.heightAnchor constraintEqualToConstant:summaryHeaderHeight];
    self.attentionWidthConstraint = [self.attentionButton.widthAnchor constraintEqualToConstant:132.0];
    NSLayoutConstraint *preferredSummaryTop = [self.summaryHeader.topAnchor constraintEqualToAnchor:self.attentionButton.bottomAnchor constant:8.0];
    preferredSummaryTop.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.stickyHeaderView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.stickyHeaderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stickyHeaderView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.stickyHeaderHeightConstraint,

        [self.heroCardView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:(customerMode ? 2.0 : 6.0)],
        [self.heroCardView.leadingAnchor constraintEqualToAnchor:self.stickyHeaderView.leadingAnchor constant:PPUsersListHorizontalInset],
        [self.heroCardView.trailingAnchor constraintEqualToAnchor:self.stickyHeaderView.trailingAnchor constant:-PPUsersListHorizontalInset],
        self.heroCardHeightConstraint,
        self.summaryHeaderHeightConstraint,

        [iconView.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:14.0],
        [iconView.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:14.0],
        [iconView.widthAnchor constraintEqualToConstant:28.0],
        [iconView.heightAnchor constraintEqualToConstant:28.0],

        [self.addUserButton.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:12.0],
        [self.addUserButton.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-12.0],
        [self.addUserButton.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.addUserButton.heightAnchor constraintEqualToConstant:PPTouchTargetMin],
    ]];

    if (customerMode) {
        self.customerCompactHeaderConstraints = @[
            [briefingStack.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:PPSpaceSM],
            [briefingStack.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:PPSpaceXS],
            [briefingStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.attentionButton.leadingAnchor constant:-PPSpaceSM],

            [self.attentionButton.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:PPSpaceSM],
            [self.attentionButton.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-PPSpaceXS],
            self.attentionWidthConstraint,
            [self.attentionButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],

            [self.summaryHeader.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor],
            [self.summaryHeader.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor],
            [self.summaryHeader.topAnchor constraintGreaterThanOrEqualToAnchor:briefingStack.bottomAnchor constant:PPSpaceSM],
            [self.summaryHeader.topAnchor constraintGreaterThanOrEqualToAnchor:self.attentionButton.bottomAnchor constant:PPSpaceSM],
            preferredSummaryTop,

            [self.searchView.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor],
            [self.searchView.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor],
            [self.searchView.topAnchor constraintEqualToAnchor:self.summaryHeader.bottomAnchor constant:PPSpaceSM],
            [self.searchView.heightAnchor constraintEqualToConstant:PPButtonHeightMD],
            [self.searchView.bottomAnchor constraintLessThanOrEqualToAnchor:self.heroCardView.bottomAnchor constant:-PPSpaceSM],
        ];
        self.customerAccessibilityHeaderConstraints = @[
            [briefingStack.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:PPSpaceMD],
            [briefingStack.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor],
            [briefingStack.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor],

            [self.attentionButton.topAnchor constraintEqualToAnchor:briefingStack.bottomAnchor constant:PPSpaceSM],
            [self.attentionButton.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor],
            [self.attentionButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.heroCardView.trailingAnchor],
            [self.attentionButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],

            [self.summaryHeader.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor],
            [self.summaryHeader.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor],
            [self.summaryHeader.topAnchor constraintEqualToAnchor:self.attentionButton.bottomAnchor constant:PPSpaceSM],

            [self.searchView.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor],
            [self.searchView.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor],
            [self.searchView.topAnchor constraintEqualToAnchor:self.summaryHeader.bottomAnchor constant:PPSpaceSM],
            [self.searchView.heightAnchor constraintEqualToConstant:PPButtonHeightLG + PPSpaceLG],
            [self.searchView.bottomAnchor constraintLessThanOrEqualToAnchor:self.heroCardView.bottomAnchor constant:-PPSpaceMD],
        ];
        [self pp_updateCustomerHeaderConstraintSet];
    } else {
        [NSLayoutConstraint activateConstraints:@[
        [briefingStack.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:12.0],
        [briefingStack.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10.0],
        [briefingStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.attentionButton.leadingAnchor constant:-8.0],

        [self.attentionButton.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:12.0],
        [self.attentionButton.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-12.0],
        self.attentionWidthConstraint,
        [self.attentionButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],

        [self.summaryHeader.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:12.0],
        [self.summaryHeader.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-12.0],
        [self.summaryHeader.topAnchor constraintGreaterThanOrEqualToAnchor:briefingStack.bottomAnchor constant:8.0],
        [self.summaryHeader.topAnchor constraintGreaterThanOrEqualToAnchor:self.attentionButton.bottomAnchor constant:8.0],
        preferredSummaryTop,

        [self.searchView.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:12.0],
        [self.searchView.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-12.0],
        [self.searchView.topAnchor constraintEqualToAnchor:self.summaryHeader.bottomAnchor constant:8.0],
        [self.searchView.heightAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.searchView.bottomAnchor constraintLessThanOrEqualToAnchor:self.heroCardView.bottomAnchor constant:-10.0],
        ]];
    }
    if (self.closeButton) {
        [NSLayoutConstraint activateConstraints:@[
            [self.closeButton.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:12.0],
            [self.closeButton.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-12.0],
            [self.closeButton.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
            [self.closeButton.heightAnchor constraintEqualToConstant:PPTouchTargetMin],
        ]];
    }

    [self pp_updateHeaderButtons];
    [self pp_refreshAttentionSignal];
    [self.view bringSubviewToFront:self.stickyHeaderView];
}

- (void)setupStateView {
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.clearColor;

    UIView *iconRow = [UIView new];
    iconRow.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *iconShell = [UIView new];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [UIColor ppSurface];
    iconShell.layer.cornerRadius = PPCornerSmall;
    iconShell.layer.masksToBounds = YES;
    [iconRow addSubview:iconShell];

    self.stateIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.3.fill"
                                                                              withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightSemibold]]];
    self.stateIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateIconView.tintColor = PPUsersListPrimaryColor();
    self.stateIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.stateIconView.isAccessibilityElement = NO;
    [iconShell addSubview:self.stateIconView];

    self.stateSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.stateSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateSpinner.color = PPUsersListPrimaryColor();
    [iconShell addSubview:self.stateSpinner];

    self.stateTitleLabel = [UILabel new];
    self.stateTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateTitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:19.0]];
    self.stateTitleLabel.textColor = PPUsersListPrimaryTextColor();
    self.stateTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateTitleLabel.numberOfLines = 2;
    self.stateTitleLabel.adjustsFontForContentSizeCategory = YES;

    self.stateSubtitleLabel = [UILabel new];
    self.stateSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateSubtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:14.0]];
    self.stateSubtitleLabel.textColor = [PPUsersListSecondaryTextColor() colorWithAlphaComponent:0.88];
    self.stateSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateSubtitleLabel.numberOfLines = 4;
    self.stateSubtitleLabel.adjustsFontForContentSizeCategory = YES;

    self.stateRetryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stateRetryButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateRetryButton.backgroundColor = PPUsersListPrimaryColor();
    self.stateRetryButton.tintColor = PPOnPrimaryColor();
    NSString *retryTitle = [self pp_isCustomerAccountMode] ? kLang(@"MissionControl_Customers_Retry") : kLang(@"Retry");
    [self.stateRetryButton setTitle:retryTitle forState:UIControlStateNormal];
    [self.stateRetryButton setTitleColor:PPOnPrimaryColor() forState:UIControlStateNormal];
    [self.stateRetryButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
    self.stateRetryButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:15.0]];
    self.stateRetryButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.stateRetryButton.layer.cornerRadius = PPCornerSmall;
    self.stateRetryButton.layer.masksToBounds = YES;
    self.stateRetryButton.accessibilityLabel = retryTitle;
    [self.stateRetryButton addTarget:self action:@selector(pp_retryUsers) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[iconRow, self.stateTitleLabel, self.stateSubtitleLabel, self.stateRetryButton]];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.axis = UILayoutConstraintAxisVertical;
    content.alignment = UIStackViewAlignmentFill;
    content.spacing = 10.0;
    [container addSubview:content];

    NSLayoutConstraint *preferredWidth = [content.widthAnchor constraintEqualToAnchor:container.widthAnchor constant:-56.0];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:36.0],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:28.0],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-28.0],
        [content.widthAnchor constraintLessThanOrEqualToConstant:360.0],
        preferredWidth,

        [iconRow.heightAnchor constraintEqualToConstant:52.0],
        [iconShell.centerXAnchor constraintEqualToAnchor:iconRow.centerXAnchor],
        [iconShell.centerYAnchor constraintEqualToAnchor:iconRow.centerYAnchor],
        [iconShell.widthAnchor constraintEqualToConstant:52.0],
        [iconShell.heightAnchor constraintEqualToConstant:52.0],

        [self.stateIconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [self.stateIconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [self.stateSpinner.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [self.stateSpinner.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],
        [self.stateRetryButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin]
    ]];

    self.stateView = container;
    self.tableView.backgroundView = container;
}

- (NSString *)pp_screenTitleText {
    if (self.viewForMode == ViewForPicker) return kLang(@"Staff_Select_Existing_User");
    if (self.viewForMode == ViewForEditAccount) return kLang(@"MissionControl_Customers_Title");
    if (self.viewForMode == ViewForEditRoleAndPermissions) return kLang(@"EditUsersRolePerms_List_Title");
    if (self.viewForMode == ViewForAdminToggle) return kLang(@"AdminToggleList_Title");
    return kLang(@"UsersSection");
}

- (NSString *)pp_screenSubtitleText {
    if (self.viewForMode == ViewForEditAccount) return kLang(@"MissionControl_Customers_Briefing");
    if (self.viewForMode == ViewForEditRoleAndPermissions) return kLang(@"EditUsersRolePerms_List_Subtitle");
    return kLang(@"AdminDashboard_Section_Users_Description");
}

- (void)pp_configureSearchAdornmentForView:(PPS *)searchView {
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:iconConfig]];
    iconView.tintColor = [PPUsersListSecondaryTextColor() colorWithAlphaComponent:0.85];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(0.0, 0.0, 18.0, 18.0);

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 28.0, 18.0)];
    iconView.center = CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds));
    [container addSubview:iconView];

    searchView.textField.leftView = nil;
    searchView.textField.rightView = nil;
    if ([Language isRTL]) {
        searchView.textField.rightView = container;
        searchView.textField.rightViewMode = UITextFieldViewModeAlways;
    } else {
        searchView.textField.leftView = container;
        searchView.textField.leftViewMode = UITextFieldViewModeAlways;
    }
}

- (void)pp_applyNoNavigationBarAnimated:(BOOL)animated {
    if (!self.navigationController) return;
    if (PPCommandCenterNavigationIsManaged(self.navigationController)) {
        [self pp_updateHeaderButtons];
        return;
    }
    if (!self.didCaptureNavigationBarHiddenState) {
        self.previousNavigationBarHiddenState = self.navigationController.navigationBarHidden;
        self.didCaptureNavigationBarHiddenState = YES;
    }
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = nil;
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    self.navigationController.navigationBar.hidden = YES;
    [self pp_updateHeaderButtons];
}

- (void)pp_restoreNavigationBarIfNeededAnimated:(BOOL)animated {
    if (!self.navigationController || !self.didCaptureNavigationBarHiddenState) return;
    if (PPCommandCenterNavigationIsManaged(self.navigationController)) return;
    [self.navigationController setNavigationBarHidden:self.previousNavigationBarHiddenState animated:animated];
    self.navigationController.navigationBar.hidden = self.previousNavigationBarHiddenState;
    self.didCaptureNavigationBarHiddenState = NO;
}

- (void)pp_updateHeaderButtons {
    BOOL canClose = !PPCommandCenterNavigationIsManaged(self.navigationController) &&
                    (self.viewForMode == ViewForPicker ||
                    self.presentingViewController ||
                    self.navigationController.presentingViewController);
    self.closeButton.hidden = !canClose;
    BOOL canAdd = self.viewForMode == ViewForDefault || self.viewForMode == ViewForAdminToggle;
    self.addUserButton.hidden = canClose || !canAdd;
    BOOL customerMode = [self pp_isCustomerAccountMode];
    self.attentionButton.hidden = !customerMode || canClose;
    self.attentionWidthConstraint.constant = customerMode && !canClose ? 132.0 : PPTouchTargetMin;
}

- (void)pp_updateCustomerHeaderConstraintSet {
    if (![self pp_isCustomerAccountMode] || self.customerCompactHeaderConstraints.count == 0) return;
    BOOL accessibilityCategory = UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory);
    if (accessibilityCategory) {
        [NSLayoutConstraint deactivateConstraints:self.customerCompactHeaderConstraints];
        [NSLayoutConstraint activateConstraints:self.customerAccessibilityHeaderConstraints];
        self.attentionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    } else {
        [NSLayoutConstraint deactivateConstraints:self.customerAccessibilityHeaderConstraints];
        [NSLayoutConstraint activateConstraints:self.customerCompactHeaderConstraints];
        self.attentionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        self.stickyHeaderView.transform = CGAffineTransformIdentity;
    }
}

- (CGFloat)pp_stickyHeaderHeight {
    CGFloat safeTop = self.view.safeAreaInsets.top;
    return safeTop + [self pp_headerCardHeight] + ([self pp_isCustomerAccountMode] ? 8.0 : 14.0);
}

- (CGFloat)pp_headerCardHeight {
    if (@available(iOS 11.0, *)) {
        UIContentSizeCategory category = UIApplication.sharedApplication.preferredContentSizeCategory;
        if (UIContentSizeCategoryIsAccessibilityCategory(category)) {
            if ([self pp_isCustomerAccountMode]) {
                return PPCommandCenterNavigationIsManaged(self.navigationController) ? 660.0 : 820.0;
            }
            return 560.0;
        }
        if ([category isEqualToString:UIContentSizeCategoryExtraExtraLarge] ||
            [category isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge]) {
            if ([self pp_isCustomerAccountMode]) {
                BOOL usesGlobalNavigation = PPCommandCenterNavigationIsManaged(self.navigationController);
                if (usesGlobalNavigation) {
                    return [category isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge] ? 232.0 : 220.0;
                }
                return [category isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge] ? 320.0 : 300.0;
            }
            return 312.0;
        }
    }
    if ([self pp_isCustomerAccountMode]) {
        return PPCommandCenterNavigationIsManaged(self.navigationController) ? PPUsersListCustomerHeaderHeight : 232.0;
    }
    return PPUsersListHeaderCardHeight;
}

- (CGFloat)pp_summaryHeaderHeight {
    if (@available(iOS 11.0, *)) {
        if (UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory)) {
            return [self pp_isCustomerAccountMode] ? 336.0 : 236.0;
        }
        if ([self pp_isCustomerAccountMode]) {
            UIContentSizeCategory category = UIApplication.sharedApplication.preferredContentSizeCategory;
            if ([category isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge]) return 88.0;
            if ([category isEqualToString:UIContentSizeCategoryExtraExtraLarge]) return 76.0;
        }
    }
    return 60.0;
}

- (void)pp_updateStickyHeaderMetrics {
    self.heroCardHeightConstraint.constant = [self pp_headerCardHeight];
    self.summaryHeaderHeightConstraint.constant = [self pp_summaryHeaderHeight];
    CGFloat headerHeight = [self pp_stickyHeaderHeight];
    self.stickyHeaderHeightConstraint.constant = headerHeight;

    UIEdgeInsets inset = self.tableView.contentInset;
    inset.top = headerHeight + 10.0;
    CGFloat minimumBottomInset = self.view.safeAreaInsets.bottom + 28.0;
    BOOL scrollsAccessibilityHeader = [self pp_isCustomerAccountMode] &&
        UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    inset.bottom = scrollsAccessibilityHeader
        ? MAX(minimumBottomInset, CGRectGetHeight(self.view.bounds))
        : minimumBottomInset;
    self.tableView.contentInset = inset;

    UIEdgeInsets indicatorInset = self.tableView.scrollIndicatorInsets;
    indicatorInset.top = inset.top;
    indicatorInset.bottom = inset.bottom;
    self.tableView.scrollIndicatorInsets = indicatorInset;

    [self.view bringSubviewToFront:self.stickyHeaderView];
    [self scrollViewDidScroll:self.tableView];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.tableView || ![self pp_isCustomerAccountMode]) return;
    if (!UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)) {
        self.stickyHeaderView.transform = CGAffineTransformIdentity;
        return;
    }

    CGFloat travel = MAX(0.0, scrollView.contentOffset.y + scrollView.contentInset.top);
    CGFloat maximumTravel = MAX(0.0, CGRectGetHeight(self.stickyHeaderView.bounds) - self.view.safeAreaInsets.top);
    self.stickyHeaderView.transform = CGAffineTransformMakeTranslation(0.0, -MIN(travel, maximumTravel));
}

- (void)pp_refreshAttentionSignal {
    if (!self.attentionButton) return;

    NSString *title = nil;
    NSString *symbol = nil;
    UIColor *color = nil;
    BOOL recoverable = self.currentError != nil;
    if (self.accessDenied) {
        title = kLang(@"CommandCenter_Permission_Denied_Title");
        symbol = @"lock.fill";
        color = [UIColor ppError];
        recoverable = NO;
    } else if (self.currentError) {
        title = kLang(self.allUsers.count > 0
                      ? @"MissionControl_Customers_Signal_RetainedError"
                      : @"MissionControl_Customers_Signal_LoadError");
        symbol = @"arrow.clockwise";
        color = [UIColor ppError];
    } else if (self.isLoadingUsers) {
        title = kLang(@"MissionControl_Customers_Signal_Loading");
        symbol = @"arrow.triangle.2.circlepath";
        color = [UIColor ppInfo];
    } else if (self.attentionCount > 0) {
        title = [NSString stringWithFormat:kLang(@"MissionControl_Customers_Signal_Attention_Format"),
                 PPUsersLocalizedCount(self.attentionCount)];
        symbol = @"exclamationmark.circle.fill";
        color = [UIColor ppWarning];
    } else {
        title = kLang(@"MissionControl_Customers_Signal_Clear");
        symbol = @"checkmark.circle.fill";
        color = [UIColor ppSuccess];
    }

    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold];
    [self.attentionButton setImage:[UIImage systemImageNamed:symbol withConfiguration:configuration] forState:UIControlStateNormal];
    [self.attentionButton setTitle:title forState:UIControlStateNormal];
    [self.attentionButton setTitleColor:color forState:UIControlStateNormal];
    self.attentionButton.tintColor = color;
    self.attentionButton.backgroundColor = [self pp_isCustomerAccountMode] ? UIColor.clearColor : [color colorWithAlphaComponent:0.11];
    self.attentionButton.userInteractionEnabled = recoverable;
    self.attentionButton.accessibilityLabel = title;
    self.attentionButton.accessibilityHint = recoverable ? kLang(@"MissionControl_Customers_Retry_Hint") : nil;
    self.attentionButton.accessibilityTraits = recoverable ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
}

- (void)pp_updateStateView {
    BOOL customerMode = [self pp_isCustomerAccountMode];
    BOOL hasRows = self.filteredUsers.count > 0;
    self.stateView.hidden = hasRows;
    if (hasRows) {
        [self.stateSpinner stopAnimating];
        self.stateRetryButton.hidden = YES;
        return;
    }

    if (self.accessDenied) {
        self.stateTitleLabel.text = kLang(@"CommandCenter_Permission_Denied_Title");
        self.stateSubtitleLabel.text = kLang(@"CommandCenter_Permission_Denied_Message");
        self.stateIconView.hidden = NO;
        self.stateIconView.image = [UIImage systemImageNamed:@"lock.fill"];
        self.stateIconView.tintColor = [UIColor ppError];
        self.stateRetryButton.hidden = YES;
        [self.stateSpinner stopAnimating];
        return;
    }

    if (self.isLoadingUsers) {
        self.stateTitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_Loading_Title") : kLang(@"Loading");
        self.stateSubtitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_Loading_Body") : kLang(@"SetPermissions_Search_Placeholder");
        self.stateIconView.hidden = YES;
        self.stateRetryButton.hidden = YES;
        [self.stateSpinner startAnimating];
        return;
    }

    [self.stateSpinner stopAnimating];
    self.stateIconView.hidden = NO;
    if (self.currentError) {
        self.stateTitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_Error_Title") : kLang(@"Error_Title");
        self.stateSubtitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_Error_Body") : self.currentError.localizedDescription;
        self.stateIconView.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
        self.stateIconView.tintColor = [UIColor ppError];
        self.stateRetryButton.hidden = NO;
    } else if (self.allUsers.count == 0) {
        self.stateTitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_SourceEmpty_Title") : kLang(@"NoUsersFound");
        self.stateSubtitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_SourceEmpty_Body") : kLang(@"SetPermissions_Search_Placeholder");
        self.stateIconView.image = [UIImage systemImageNamed:@"tray"];
        self.stateIconView.tintColor = [UIColor ppTextSecondary];
        self.stateRetryButton.hidden = YES;
    } else {
        self.stateTitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_FilteredEmpty_Title") : kLang(@"NoUsersFound");
        self.stateSubtitleLabel.text = customerMode ? kLang(@"MissionControl_Customers_FilteredEmpty_Body") : kLang(@"SetPermissions_Search_Placeholder");
        self.stateIconView.image = [UIImage systemImageNamed:@"magnifyingglass"];
        self.stateIconView.tintColor = [UIColor ppTextSecondary];
        self.stateRetryButton.hidden = YES;
    }
}

- (void)pp_prepareEntranceIfNeeded {
    if (self.didRunEntrance || self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;
    self.stickyHeaderView.alpha = 0.0;
    self.tableView.alpha = 0.0;
}

- (void)pp_runEntranceIfNeeded {
    if (self.didRunEntrance) return;
    self.didRunEntrance = YES;
    [self.view layoutIfNeeded];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.stickyHeaderView.alpha = 1.0;
        self.tableView.alpha = 1.0;
        return;
    }

    [UIView animateWithDuration:0.28
                           delay:0.0
                         options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                      animations:^{
        self.stickyHeaderView.alpha = 1.0;
        self.tableView.alpha = 1.0;
    } completion:nil];
}

- (void)pp_closePicker {
    if (self.presentingViewController || self.navigationController.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)_updateSummaryStats {
    NSInteger total = self.allUsers.count;
    NSInteger active = 0;
    NSInteger verified = 0;
    NSInteger attention = 0;
    
    for (UserModel *u in self.allUsers) {
        NSString *status = PPUsersResolvedAccountStatus(u);
        if ([status isEqualToString:@"active"]) active++;
        else if ([status isEqualToString:@"blocked"] ||
                 [status isEqualToString:@"disabled"] ||
                 [status isEqualToString:@"pending_review"]) attention++;
        if (u.isVerified) verified++;
    }

    self.attentionCount = attention;
    [self.summaryHeader updateWithTotal:total active:active verified:verified attention:attention];
    [self pp_refreshAttentionSignal];
}

#pragma mark - Search delegate

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.currentQuery = text ?: @"";
    [self _applyFilterAndReload];
}

- (void)_applyFilterAndReload {
    NSString *q = self.currentQuery ?: @"";
    if (q.length == 0) {
        self.filteredUsers = self.allUsers.mutableCopy;
    } else {
        NSString *needle = q.lowercaseString;
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(UserModel *u, NSDictionary *_) {
            return [u.UserName.lowercaseString containsString:needle] ||
                   [u.UserEmail.lowercaseString containsString:needle] ||
                   [u.MobileNo.lowercaseString containsString:needle] ||
                   [u.uid.lowercaseString containsString:needle];
        }];
        self.filteredUsers = [[self.allUsers filteredArrayUsingPredicate:p] mutableCopy];
    }
    [self pp_updateStateView];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
     PPUserCell *cell = [tableView dequeueReusableCellWithIdentifier:PPUserCell.reuseIdentifier forIndexPath:indexPath];
    UserModel *u = self.filteredUsers[indexPath.row];
    [cell configureWithUser:u indexPath:indexPath viewFor:self.viewForMode];
    cell.accessibilityIdentifier = u.uid.length ? u.uid : [NSString stringWithFormat:@"user-%ld", (long)indexPath.row];
    cell.delegate = self;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UserModel *u = self.filteredUsers[indexPath.row];
    
    if (self.viewForMode == ViewForPicker) {
        void (^pickBlock)(UserModel *) = [self.onUserPicked copy];
        BOOL isPresented = (self.presentingViewController || self.navigationController.presentingViewController);
        void (^finishPick)(void) = ^{
            if ([self respondsToSelector:@selector(rowDescriptor)] && self.rowDescriptor) {
                self.rowDescriptor.value = u;
            }
            if (pickBlock) {
                pickBlock(u);
            }
        };

        if (isPresented) {
            [self dismissViewControllerAnimated:YES completion:finishPick];
        } else {
            finishPick();
            [self.navigationController popViewControllerAnimated:YES];
        }
        return;
    }
    
    EditType type = EditTypeDefault;
    if (self.viewForMode == ViewForEditAccount) type = EditTypeUserData;
    else if (self.viewForMode == ViewForEditRoleAndPermissions) type = EditTypeUserPermisstionAndRoles;
    
    UserManagementController *vc = [[UserManagementController alloc] initWithUser:u type:type];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)userCellDidTapAction:(PPUserCell *)cell user:(UserModel *)user {
    [self tableView:self.tableView didSelectRowAtIndexPath:cell.indexPath];
}

- (void)didTapAddUser {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"AddUser") message:kLang(@"Enter_Email_Password") preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Name");
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Email");
        textField.keyboardType = UIKeyboardTypeEmailAddress;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Password");
        textField.secureTextEntry = YES;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *name = alert.textFields[0].text;
        NSString *email = alert.textFields[1].text;
        NSString *password = alert.textFields[2].text;
        
        if (name.length == 0 || email.length == 0 || password.length == 0) {
            [PPToast toast:kLang(@"Error_MissingFields")];
            return;
        }
        
        [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:@""];
        
        [[FUManager shared] createUserWithEmail:email password:password username:name role:0 permissions:nil isAdmin:NO completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPToast toast:error.localizedDescription];
            } else {
                [PPToast toast:kLang(@"Success")];
            }
        }];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasPermission:kStaffPermUsersManage]) return nil;

    UserModel *u = self.filteredUsers[indexPath.row];

    BOOL isBlocked = [PPUsersResolvedAccountStatus(u) isEqualToString:@"blocked"];
    NSString *title = isBlocked ? kLang(@"Unblock") : kLang(@"BlockUser_Action");
    UIContextualAction *blockAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:title handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self pp_confirmBlockUser:u shouldBlock:!isBlocked completion:completionHandler];
    }];
    blockAction.backgroundColor = isBlocked ? [UIColor ppSuccess] : [UIColor ppWarning];
    blockAction.image = [UIImage systemImageNamed:isBlocked ? @"hand.thumbsup.fill" : @"hand.raised.slash.fill"];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[blockAction]];
}

- (void)pp_confirmBlockUser:(UserModel *)user shouldBlock:(BOOL)shouldBlock completion:(void(^)(BOOL handled))completion {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasPermission:kStaffPermUsersManage]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        if (completion) completion(NO);
        return;
    }

    // Current user check
    if ([[FIRAuth auth].currentUser.uid isEqualToString:user.uid]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        if (completion) completion(NO);
        return;
    }
    
    NSString *actionName = shouldBlock ? kLang(@"BlockUser_Action") : kLang(@"Unblock");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Confirm") message:[NSString stringWithFormat:@"%@ %@", actionName, user.UserName] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (completion) completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:actionName style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [RPM setBlocked:shouldBlock forUID:user.uid reason:nil duration:nil completion:^(NSError * _Nullable error) {
            if (error) [PPToast toast:error.localizedDescription];
            else [PPToast toast:kLang(@"Success")];
            if (completion) completion(error == nil);
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
