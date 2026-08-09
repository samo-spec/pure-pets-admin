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
#import "PPHero.h"
#import "PurePetsColorPattle.h"
#import <objc/runtime.h>
@import Firebase;
@import FirebaseAuth;
#define RPM [RPManager shared]

static CGFloat const PPUsersListHorizontalInset = 16.0;
static CGFloat const PPUsersListHeaderCardHeight = 272.0;
static CGFloat const PPUsersListRowHeight = 112.0;

static UIColor *PPUsersListBackgroundColor(void) {
    return AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
}

static UIColor *PPUsersListSurfaceColor(void) {
    return AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
}

static UIColor *PPUsersListPrimaryColor(void) {
    return AppPrimaryClr ?: UIColor.systemBlueColor;
}

static UIColor *PPUsersListPrimaryTextColor(void) {
    return PrimaryTextClr ?: UIColor.labelColor;
}

static UIColor *PPUsersListSecondaryTextColor(void) {
    return SeconderyTextClr ?: UIColor.secondaryLabelColor;
}

#pragma mark - PPUsersSummaryHeaderView

@interface PPUsersSummaryHeaderView : UIView
@property (nonatomic, strong) UILabel *totalVal;
@property (nonatomic, strong) UILabel *activeVal;
@property (nonatomic, strong) UILabel *verifiedVal;
@property (nonatomic, strong) UILabel *prodVal;

- (void)updateWithTotal:(NSInteger)total active:(NSInteger)active verified:(NSInteger)verified prod:(NSInteger)prod;
@end

@implementation PPUsersSummaryHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 8.0;
    row.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:self.topAnchor],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];

    [row addArrangedSubview:[self makeChipWithIcon:@"person.3.fill" titleKey:@"Total_Users" valLabel:&_totalVal color:PPPrimaryColor()]];
    [row addArrangedSubview:[self makeChipWithIcon:@"checkmark.circle.fill" titleKey:@"Active_Users" valLabel:&_activeVal color:PPSageAccentColor()]];
    [row addArrangedSubview:[self makeChipWithIcon:@"patch.check.fill" titleKey:@"Verified_Users" valLabel:&_verifiedVal color:PPGoldAccentColor()]];
    [row addArrangedSubview:[self makeChipWithIcon:@"shield.fill" titleKey:@"Production_Users" valLabel:&_prodVal color:PPSecondaryAccentColor()]];
}

- (UIView *)makeChipWithIcon:(NSString *)iconName titleKey:(NSString *)titleKey valLabel:(UILabel * __strong *)valLabel color:(UIColor *)color {
    UIView *chip = [UIView new];
    chip.backgroundColor = [PPUsersListSurfaceColor() colorWithAlphaComponent:0.72];
    chip.layer.cornerRadius = 18.0;
    chip.layer.masksToBounds = YES;
    chip.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    chip.layer.borderColor = [color colorWithAlphaComponent:0.11].CGColor;
    chip.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *accentRail = [UIView new];
    accentRail.translatesAutoresizingMaskIntoConstraints = NO;
    accentRail.backgroundColor = [color colorWithAlphaComponent:0.82];
    [chip addSubview:accentRail];
    
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                            weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName withConfiguration:iconConfig]];
    icon.tintColor = color;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *title = [UILabel new];
    title.text = kLang(titleKey);
    title.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:10.0]];
    title.textColor = [PPUsersListSecondaryTextColor() colorWithAlphaComponent:0.88];
    title.textAlignment = [Language alignmentForCurrentLanguage];
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.72;
    title.adjustsFontForContentSizeCategory = YES;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *val = [UILabel new];
    val.text = @"0";
    val.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:18.0]];
    val.textColor = PPUsersListPrimaryTextColor();
    val.textAlignment = [Language alignmentForCurrentLanguage];
    val.adjustsFontSizeToFitWidth = YES;
    val.minimumScaleFactor = 0.72;
    val.adjustsFontForContentSizeCategory = YES;
    val.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (valLabel) *valLabel = val;
    
    [chip addSubview:icon];
    [chip addSubview:title];
    [chip addSubview:val];
    
    [NSLayoutConstraint activateConstraints:@[
        [accentRail.topAnchor constraintEqualToAnchor:chip.topAnchor],
        [accentRail.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor],
        [accentRail.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor],
        [accentRail.heightAnchor constraintEqualToConstant:3.0],

        [icon.topAnchor constraintEqualToAnchor:chip.topAnchor constant:8.0],
        [icon.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:8.0],
        [icon.widthAnchor constraintEqualToConstant:16.0],
        [icon.heightAnchor constraintEqualToConstant:16.0],

        [val.topAnchor constraintEqualToAnchor:chip.topAnchor constant:8.0],
        [val.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:4.0],
        [val.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-8.0],

        [title.topAnchor constraintEqualToAnchor:val.bottomAnchor constant:3.0],
        [title.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:8.0],
        [title.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-8.0],
        [title.bottomAnchor constraintLessThanOrEqualToAnchor:chip.bottomAnchor constant:-7.0]
    ]];

    chip.isAccessibilityElement = YES;
    chip.accessibilityTraits = UIAccessibilityTraitStaticText;

    return chip;
}

- (void)updateWithTotal:(NSInteger)total active:(NSInteger)active verified:(NSInteger)verified prod:(NSInteger)prod {
    self.totalVal.text = [NSString stringWithFormat:@"%ld", (long)total];
    self.activeVal.text = [NSString stringWithFormat:@"%ld", (long)active];
    self.verifiedVal.text = [NSString stringWithFormat:@"%ld", (long)verified];
    self.prodVal.text = [NSString stringWithFormat:@"%ld", (long)prod];

    NSArray<UILabel *> *values = @[self.totalVal, self.activeVal, self.verifiedVal, self.prodVal];
    for (UILabel *value in values) {
        UIView *chip = value.superview;
        UILabel *title = chip.subviews.count > 1 ? chip.subviews[2] : nil;
        chip.accessibilityLabel = title.text ?: @"";
        chip.accessibilityValue = value.text ?: @"";
    }
}

@end

#pragma mark - UsersListVC

@interface UsersListVC () <UITableViewDelegate, UITableViewDataSource, PPSDelegate, UserCellDelegate>
@property (nonatomic, strong) id<FIRListenerRegistration> usersReg;
@property (nonatomic, strong) PPUsersSummaryHeaderView *summaryHeader;
@property (nonatomic, strong) UIView *stickyHeaderView;
@property (nonatomic, strong) UIView *heroCardView;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *heroTitleLabel;
@property (nonatomic, strong) UILabel *heroSubtitleLabel;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *addUserButton;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UILabel *stateTitleLabel;
@property (nonatomic, strong) UILabel *stateSubtitleLabel;
@property (nonatomic, strong) UIActivityIndicatorView *stateSpinner;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedUserIDs;
@property (nonatomic, assign) BOOL isLoadingUsers;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL didRunEntrance;
@property (nonatomic, assign) BOOL didCaptureNavigationBarHiddenState;
@property (nonatomic, assign) BOOL previousNavigationBarHiddenState;
@property (nonatomic, strong) NSLayoutConstraint *stickyHeaderHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heroCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *summaryHeaderHeightConstraint;
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
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = nil;
    self.view.backgroundColor = PPUsersListBackgroundColor();
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.isLoadingUsers = YES;
    self.animatedUserIDs = [NSMutableSet set];

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

    __weak typeof(self) weakSelf = self;
    self.usersReg =
    [[FUManager shared] listenAllUsersWithDiffsOrderedBy:@"UserName"
                                               ascending:YES
                                    includeMetadataChanges:YES
                                                   queue:dispatch_get_main_queue()
                                                completion:^(NSArray<UserModel *> *users,
                                                             NSArray<FIRDocumentChange *> *changes,
                                                             FIRSnapshotMetadata *meta,
                                                             NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        self.isLoadingUsers = NO;
        self.currentError = error;
        if (error) {
            [self pp_updateStateView];
            return;
        }

        self.allUsers = (users ?: @[]).mutableCopy;
        [self _updateSummaryStats];
        [self _applyFilterAndReload];
    }];
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
        [self.heroBackground reapplyPalette];
    }
}

- (void)dealloc {
    [self.usersReg remove];
    [self.heroBackground stopAnimations];
}

- (void)setupHeaderUI {
    self.stickyHeaderView = [UIView new];
    self.stickyHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stickyHeaderView.backgroundColor = PPUsersListBackgroundColor();
    self.stickyHeaderView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:self.stickyHeaderView];

    self.heroCardView = [UIView new];
    self.heroCardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroCardView.backgroundColor = UIColor.clearColor;
    self.heroCardView.layer.cornerRadius = 30.0;
    self.heroCardView.layer.masksToBounds = YES;
    self.heroCardView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    if (@available(iOS 13.0, *)) {
        self.heroCardView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self.stickyHeaderView addSubview:self.heroCardView];

    self.heroBackground = [PPHero new];
    self.heroBackground.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroBackground.accentColorOverride = PPUsersListPrimaryColor();
    self.heroBackground.accentStyle = PPHeroGlassAccentStyleBar;
    self.heroBackground.animationsEnabled = NO;
    [self.heroCardView addSubview:self.heroBackground];

    UIView *iconShell = [UIView new];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPUsersListPrimaryColor() colorWithAlphaComponent:0.12];
    iconShell.layer.cornerRadius = 18.0;
    iconShell.layer.masksToBounds = YES;
    [self.heroCardView addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.3.sequence.fill"
                                                                       withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21.0 weight:UIImageSymbolWeightSemibold]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = PPUsersListPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.closeButton.tintColor = PPUsersListPrimaryTextColor();
    self.closeButton.backgroundColor = [PPUsersListSurfaceColor() colorWithAlphaComponent:0.72];
    self.closeButton.layer.cornerRadius = 18.0;
    self.closeButton.layer.masksToBounds = YES;
    UIImage *closeImage = [UIImage systemImageNamed:[Language isRTL] ? @"chevron.right" : @"chevron.left"
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightBold]];
    [self.closeButton setImage:closeImage forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(pp_closePicker) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.accessibilityLabel = kLang(@"Cancel");
    [self.heroCardView addSubview:self.closeButton];

    self.addUserButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addUserButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.addUserButton.tintColor = UIColor.whiteColor;
    self.addUserButton.backgroundColor = PPUsersListPrimaryColor();
    self.addUserButton.layer.cornerRadius = 18.0;
    self.addUserButton.layer.masksToBounds = YES;
    [self.addUserButton setImage:[UIImage systemImageNamed:@"plus"
                                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightBold]]
                         forState:UIControlStateNormal];
    [self.addUserButton addTarget:self action:@selector(didTapAddUser) forControlEvents:UIControlEventTouchUpInside];
    self.addUserButton.accessibilityLabel = kLang(@"AddUser");
    [PPButtonHelper attachTapAnimationToButton:self.addUserButton style:PPButtonAnimationStyleGlow];
    [self.heroCardView addSubview:self.addUserButton];

    self.heroTitleLabel = [UILabel new];
    self.heroTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroTitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:25.0]];
    self.heroTitleLabel.textColor = PPUsersListPrimaryTextColor();
    self.heroTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.heroTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.heroTitleLabel.adjustsFontSizeToFitWidth = YES;
    self.heroTitleLabel.minimumScaleFactor = 0.76;
    self.heroTitleLabel.text = [self pp_screenTitleText];
    [self.heroCardView addSubview:self.heroTitleLabel];

    self.heroSubtitleLabel = [UILabel new];
    self.heroSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroSubtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:13.5]];
    self.heroSubtitleLabel.textColor = [PPUsersListSecondaryTextColor() colorWithAlphaComponent:0.92];
    self.heroSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.heroSubtitleLabel.numberOfLines = 2;
    self.heroSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.heroSubtitleLabel.text = [self pp_screenSubtitleText];
    [self.heroCardView addSubview:self.heroSubtitleLabel];

    self.heroCountLabel = [UILabel new];
    self.heroCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroCountLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:13.0]];
    self.heroCountLabel.textColor = PPUsersListPrimaryColor();
    self.heroCountLabel.textAlignment = NSTextAlignmentCenter;
    self.heroCountLabel.backgroundColor = [PPUsersListPrimaryColor() colorWithAlphaComponent:0.09];
    self.heroCountLabel.layer.cornerRadius = 14.0;
    self.heroCountLabel.layer.masksToBounds = YES;
    self.heroCountLabel.adjustsFontSizeToFitWidth = YES;
    self.heroCountLabel.minimumScaleFactor = 0.75;
    self.heroCountLabel.adjustsFontForContentSizeCategory = YES;
    [self.heroCardView addSubview:self.heroCountLabel];

    self.summaryHeader = [PPUsersSummaryHeaderView new];
    self.summaryHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroCardView addSubview:self.summaryHeader];

    PPS *search = [[PPS alloc] initWithFrame:CGRectZero];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.delegate = self;
    search.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.textField.textAlignment = [Language alignmentForCurrentLanguage];
    search.textField.placeholder = self.searchPlaceholderText.length ? self.searchPlaceholderText : kLang(@"SetPermissions_Search_Placeholder");
    search.textField.accessibilityLabel = search.textField.placeholder;
    search.cornerRadius = 22.0;
    search.layer.cornerRadius = 22.0;
    search.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    search.layer.borderColor = [PPUsersListPrimaryColor() colorWithAlphaComponent:0.12].CGColor;
    search.layer.shadowColor = UIColor.blackColor.CGColor;
    search.layer.shadowOpacity = 0.055;
    search.layer.shadowRadius = 14.0;
    search.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    [self pp_configureSearchAdornmentForView:search];
    [self.heroCardView addSubview:search];
    self.searchView = search;

    CGFloat heroCardHeight = [self pp_headerCardHeight];
    CGFloat summaryHeaderHeight = [self pp_summaryHeaderHeight];
    self.stickyHeaderHeightConstraint = [self.stickyHeaderView.heightAnchor constraintEqualToConstant:heroCardHeight + 28.0];
    self.heroCardHeightConstraint = [self.heroCardView.heightAnchor constraintEqualToConstant:heroCardHeight];
    self.summaryHeaderHeightConstraint = [self.summaryHeader.heightAnchor constraintEqualToConstant:summaryHeaderHeight];
    [NSLayoutConstraint activateConstraints:@[
        [self.stickyHeaderView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.stickyHeaderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stickyHeaderView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.stickyHeaderHeightConstraint,

        [self.heroCardView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [self.heroCardView.leadingAnchor constraintEqualToAnchor:self.stickyHeaderView.leadingAnchor constant:PPUsersListHorizontalInset],
        [self.heroCardView.trailingAnchor constraintEqualToAnchor:self.stickyHeaderView.trailingAnchor constant:-PPUsersListHorizontalInset],
        self.heroCardHeightConstraint,

        [self.heroBackground.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor],
        [self.heroBackground.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor],
        [self.heroBackground.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor],
        [self.heroBackground.bottomAnchor constraintEqualToAnchor:self.heroCardView.bottomAnchor],

        [iconShell.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:20.0],
        [iconShell.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:18.0],
        [iconShell.widthAnchor constraintEqualToConstant:52.0],
        [iconShell.heightAnchor constraintEqualToConstant:52.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [self.closeButton.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:22.0],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-18.0],
        [self.closeButton.widthAnchor constraintEqualToConstant:42.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:42.0],

        [self.addUserButton.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:22.0],
        [self.addUserButton.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-18.0],
        [self.addUserButton.widthAnchor constraintEqualToConstant:42.0],
        [self.addUserButton.heightAnchor constraintEqualToConstant:42.0],

        [self.heroTitleLabel.topAnchor constraintEqualToAnchor:self.heroCardView.topAnchor constant:22.0],
        [self.heroTitleLabel.leadingAnchor constraintEqualToAnchor:iconShell.trailingAnchor constant:14.0],
        [self.heroTitleLabel.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-14.0],
        [self.heroTitleLabel.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],

        [self.heroSubtitleLabel.topAnchor constraintEqualToAnchor:self.heroTitleLabel.bottomAnchor constant:6.0],
        [self.heroSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.heroTitleLabel.leadingAnchor],
        [self.heroSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.heroTitleLabel.trailingAnchor],

        [self.heroCountLabel.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:18.0],
        [self.heroCountLabel.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-18.0],
        [self.heroCountLabel.topAnchor constraintEqualToAnchor:self.heroSubtitleLabel.bottomAnchor constant:10.0],
        [self.heroCountLabel.heightAnchor constraintEqualToConstant:28.0],

        [self.summaryHeader.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:18.0],
        [self.summaryHeader.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-18.0],
        [self.summaryHeader.topAnchor constraintEqualToAnchor:self.heroCountLabel.bottomAnchor constant:10.0],
        self.summaryHeaderHeightConstraint,

        [self.searchView.leadingAnchor constraintEqualToAnchor:self.heroCardView.leadingAnchor constant:18.0],
        [self.searchView.trailingAnchor constraintEqualToAnchor:self.heroCardView.trailingAnchor constant:-18.0],
        [self.searchView.topAnchor constraintEqualToAnchor:self.summaryHeader.bottomAnchor constant:10.0],
        [self.searchView.heightAnchor constraintEqualToConstant:48.0],
    ]];

    [self pp_updateHeaderButtons];
    [self pp_refreshHeroCount];
    [self.view bringSubviewToFront:self.stickyHeaderView];
}

- (void)setupStateView {
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.clearColor;

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];

    UIView *iconShell = [UIView new];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPUsersListPrimaryColor() colorWithAlphaComponent:0.09];
    iconShell.layer.cornerRadius = 28.0;
    iconShell.layer.masksToBounds = YES;
    [content addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.3.fill"
                                                                       withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightSemibold]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = PPUsersListPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

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
    [content addSubview:self.stateTitleLabel];

    self.stateSubtitleLabel = [UILabel new];
    self.stateSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateSubtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:14.0]];
    self.stateSubtitleLabel.textColor = [PPUsersListSecondaryTextColor() colorWithAlphaComponent:0.88];
    self.stateSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateSubtitleLabel.numberOfLines = 3;
    self.stateSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    [content addSubview:self.stateSubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:42.0],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:28.0],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-28.0],

        [iconShell.topAnchor constraintEqualToAnchor:content.topAnchor],
        [iconShell.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [iconShell.widthAnchor constraintEqualToConstant:56.0],
        [iconShell.heightAnchor constraintEqualToConstant:56.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [self.stateSpinner.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [self.stateSpinner.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [self.stateTitleLabel.topAnchor constraintEqualToAnchor:iconShell.bottomAnchor constant:18.0],
        [self.stateTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.stateTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [self.stateSubtitleLabel.topAnchor constraintEqualToAnchor:self.stateTitleLabel.bottomAnchor constant:8.0],
        [self.stateSubtitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.stateSubtitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.stateSubtitleLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];

    self.stateView = container;
    self.tableView.backgroundView = container;
}

- (NSString *)pp_screenTitleText {
    if (self.viewForMode == ViewForPicker) return kLang(@"Staff_Select_Existing_User");
    if (self.viewForMode == ViewForEditAccount) return kLang(@"EditUsersAccount_List_Title");
    if (self.viewForMode == ViewForEditRoleAndPermissions) return kLang(@"EditUsersRolePerms_List_Title");
    if (self.viewForMode == ViewForAdminToggle) return kLang(@"AdminToggleList_Title");
    return kLang(@"UsersSection");
}

- (NSString *)pp_screenSubtitleText {
    if (self.viewForMode == ViewForEditAccount) return kLang(@"EditUsersAccount_List_Subtitle");
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
    [self.navigationController setNavigationBarHidden:self.previousNavigationBarHiddenState animated:animated];
    self.navigationController.navigationBar.hidden = self.previousNavigationBarHiddenState;
    self.didCaptureNavigationBarHiddenState = NO;
}

- (void)pp_updateHeaderButtons {
    BOOL canClose = self.viewForMode == ViewForPicker ||
                    self.presentingViewController ||
                    self.navigationController.presentingViewController;
    self.closeButton.hidden = !canClose;
    BOOL canAdd = self.viewForMode == ViewForDefault || self.viewForMode == ViewForAdminToggle;
    self.addUserButton.hidden = canClose || !canAdd;
}

- (CGFloat)pp_stickyHeaderHeight {
    CGFloat safeTop = self.view.safeAreaInsets.top;
    return safeTop + [self pp_headerCardHeight] + 18.0;
}

- (CGFloat)pp_headerCardHeight {
    if (@available(iOS 11.0, *)) {
        if (UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory)) {
            return 352.0;
        }
    }
    return PPUsersListHeaderCardHeight;
}

- (CGFloat)pp_summaryHeaderHeight {
    if (@available(iOS 11.0, *)) {
        if (UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory)) {
            return 88.0;
        }
    }
    return 68.0;
}

- (void)pp_updateStickyHeaderMetrics {
    self.heroCardHeightConstraint.constant = [self pp_headerCardHeight];
    self.summaryHeaderHeightConstraint.constant = [self pp_summaryHeaderHeight];
    CGFloat headerHeight = [self pp_stickyHeaderHeight];
    self.stickyHeaderHeightConstraint.constant = headerHeight;

    UIEdgeInsets inset = self.tableView.contentInset;
    inset.top = headerHeight + 10.0;
    inset.bottom = MAX(inset.bottom, self.view.safeAreaInsets.bottom + 28.0);
    self.tableView.contentInset = inset;

    UIEdgeInsets indicatorInset = self.tableView.scrollIndicatorInsets;
    indicatorInset.top = inset.top;
    indicatorInset.bottom = inset.bottom;
    self.tableView.scrollIndicatorInsets = indicatorInset;

    [self.view bringSubviewToFront:self.stickyHeaderView];
}

- (void)pp_refreshHeroCount {
    NSInteger visible = self.filteredUsers.count;
    NSInteger total = self.allUsers.count;
    self.heroCountLabel.text = [NSString stringWithFormat:@"%ld / %ld  %@",
                                (long)visible,
                                (long)total,
                                kLang(@"Total_Users")];
    self.heroCountLabel.accessibilityLabel = self.heroCountLabel.text;
}

- (void)pp_updateStateView {
    BOOL hasRows = self.filteredUsers.count > 0;
    self.stateView.hidden = hasRows;
    if (hasRows) {
        [self.stateSpinner stopAnimating];
        return;
    }

    if (self.isLoadingUsers) {
        self.stateTitleLabel.text = kLang(@"Loading");
        self.stateSubtitleLabel.text = kLang(@"SetPermissions_Search_Placeholder");
        [self.stateSpinner startAnimating];
        return;
    }

    [self.stateSpinner stopAnimating];
    if (self.currentError) {
        self.stateTitleLabel.text = kLang(@"Error_Title");
        self.stateSubtitleLabel.text = self.currentError.localizedDescription;
    } else {
        self.stateTitleLabel.text = kLang(@"NoUsersFound");
        self.stateSubtitleLabel.text = kLang(@"SetPermissions_Search_Placeholder");
    }
}

- (void)pp_prepareEntranceIfNeeded {
    if (self.didRunEntrance || self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;
    self.stickyHeaderView.alpha = 0.0;
    self.stickyHeaderView.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
    self.tableView.alpha = 0.0;
    self.tableView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
}

- (void)pp_runEntranceIfNeeded {
    if (self.didRunEntrance) return;
    self.didRunEntrance = YES;
    [self.view layoutIfNeeded];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.stickyHeaderView.alpha = 1.0;
        self.stickyHeaderView.transform = CGAffineTransformIdentity;
        self.tableView.alpha = 1.0;
        self.tableView.transform = CGAffineTransformIdentity;
        return;
    }

    [UIView animateWithDuration:0.38
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.stickyHeaderView.alpha = 1.0;
        self.stickyHeaderView.transform = CGAffineTransformIdentity;
    } completion:nil];

    [UIView animateWithDuration:0.44
                          delay:0.08
         usingSpringWithDamping:0.88
          initialSpringVelocity:0.35
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.tableView.alpha = 1.0;
        self.tableView.transform = CGAffineTransformIdentity;
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
    NSInteger prod = 0;
    
    for (UserModel *u in self.allUsers) {
        if (!u.isBlocked && (!u.accountStatus || [u.accountStatus isEqualToString:@"active"])) active++;
        if (u.isVerified) verified++;
        if ([u.prodectionStatus isEqualToString:@"active"]) prod++;
    }
    
    [self.summaryHeader updateWithTotal:total active:active verified:verified prod:prod];
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
    [self pp_refreshHeroCount];
    [self pp_updateStateView];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self.tableView reloadData];
        return;
    }

    [UIView transitionWithView:self.tableView
                      duration:0.20
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{
        [self.tableView reloadData];
    } completion:nil];
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

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.filteredUsers.count || UIAccessibilityIsReduceMotionEnabled()) return;

    UserModel *user = self.filteredUsers[indexPath.row];
    NSString *identifier = user.uid.length ? user.uid : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedUserIDs containsObject:identifier]) return;
    [self.animatedUserIDs addObject:identifier];

    cell.contentView.alpha = 0.0;
    cell.contentView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    NSTimeInterval delay = MIN(indexPath.row, 8) * 0.025;
    [UIView animateWithDuration:0.32
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.contentView.alpha = 1.0;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
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
    UserModel *u = self.filteredUsers[indexPath.row];
    
    BOOL isBlocked = u.isBlocked;
    NSString *title = isBlocked ? kLang(@"Unblock") : kLang(@"BlockUser_Action");
    UIContextualAction *blockAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:title handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self pp_confirmBlockUser:u shouldBlock:!isBlocked completion:completionHandler];
    }];
    blockAction.backgroundColor = isBlocked ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
    blockAction.image = [UIImage systemImageNamed:isBlocked ? @"hand.thumbsup.fill" : @"hand.raised.slash.fill"];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[blockAction]];
}

- (void)pp_confirmBlockUser:(UserModel *)user shouldBlock:(BOOL)shouldBlock completion:(void(^)(BOOL handled))completion {
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
