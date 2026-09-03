//
//  PPBannersListVC.m
//  PurePetsAdmin
//
//  Flagship Beyond-FAANG Apple-grade Banners Command Center
//

#import "PPBannersListVC.h"
#import "PPBannersManager.h"
#import "MainBannerModel.h"
#import "PPBannerViewModel.h"
#import "PPFlagshipBannerCardCell.h"
#import "PPBannerLivePreviewVC.h"
#import "PPAddBannerViewController.h"
#import "PPDesignTokens.h"
#import "Language.h"
#import "Styling.h"
#import "PPAlertHelper.h"
#import "UIViewController+PPNavBar.h"
#import "PPHUD.h"
#import "PurePetsAdmin-Swift.h"

typedef NS_ENUM(NSInteger, PPBannerStatusFilter) {
    PPBannerStatusFilterAll = 0,
    PPBannerStatusFilterActive,
    PPBannerStatusFilterHidden
};

@interface PPBannersListVC () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, PPFlagshipBannerCardDelegate>

// Top Floating Glass Navigation Bar
@property (nonatomic, strong) UIVisualEffectView *navBarVisualEffectView;
@property (nonatomic, strong) UIView *navBarContentContainer;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UILabel *navSubtitleLabel;
@property (nonatomic, strong) UIButton *primaryAddButton;
@property (nonatomic, strong) UIView *navHairline;

// Table View
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

// Header Controls & Decks
@property (nonatomic, strong) UIView *tableHeaderContainer;
@property (nonatomic, strong) UIView *kpiDeckContainer;
@property (nonatomic, strong) UIButton *kpiTotalCard;
@property (nonatomic, strong) UIButton *kpiActiveCard;
@property (nonatomic, strong) UIButton *kpiHiddenCard;
@property (nonatomic, strong) UIButton *kpiGroupsCard;
@property (nonatomic, strong) UILabel *kpiTotalCountLabel;
@property (nonatomic, strong) UILabel *kpiActiveCountLabel;
@property (nonatomic, strong) UILabel *kpiHiddenCountLabel;
@property (nonatomic, strong) UILabel *kpiGroupsCountLabel;

// Placement Screen Filter Scroller
@property (nonatomic, strong) UIScrollView *placementChipsScrollView;
@property (nonatomic, strong) UIStackView *placementChipsStack;
@property (nonatomic, strong) NSMutableArray<UIButton *> *placementChipButtons;
@property (nonatomic, assign) NSInteger selectedHolderFilter; // -1 = All, or PPBannerHolder value

// Search Bar
@property (nonatomic, strong) UIView *searchContainer;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, strong) UIButton *searchClearButton;
@property (nonatomic, strong) UILabel *searchResultsCountLabel;

// Empty State View
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyImageView;
@property (nonatomic, strong) UILabel *emptyTitleLabel;
@property (nonatomic, strong) UILabel *emptySubtitleLabel;
@property (nonatomic, strong) UIButton *emptyActionButton;

// Data & State
@property (nonatomic, strong) id<FIRListenerRegistration> bannersListener;
@property (nonatomic, strong) NSMutableArray<MainBannerModel *> *allGroups;
@property (nonatomic, strong) NSMutableArray<MainBannerModel *> *filteredGroups;
@property (nonatomic, copy)   NSString *searchQuery;
@property (nonatomic, assign) PPBannerStatusFilter statusFilter;
@property (nonatomic, assign) BOOL isSizingHeader;

@end

@implementation PPBannersListVC

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.allGroups = [NSMutableArray array];
    self.filteredGroups = [NSMutableArray array];
    self.placementChipButtons = [NSMutableArray array];
    self.selectedHolderFilter = -1; // All
    self.statusFilter = PPBannerStatusFilterAll;
    self.searchQuery = @"";

    [self setupTableView];
    [self setupTableHeader];
    [self setupFloatingNavigationBar];
    [self setupEmptyStateView];
    [self startObservingBanners];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
    [self updateLayoutOffsets];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateLayoutOffsets];
    [self sizeHeaderIfNeeded];
}

- (void)dealloc {
    if (self.bannersListener) {
        [self.bannersListener remove];
        self.bannersListener = nil;
    }
}

#pragma mark - Floating Glass Navigation Bar

- (void)setupFloatingNavigationBar {
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    _navBarVisualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    _navBarVisualEffectView.translatesAutoresizingMaskIntoConstraints = NO;
    _navBarVisualEffectView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:_navBarVisualEffectView];

    _navBarContentContainer = [[UIView alloc] init];
    _navBarContentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _navBarContentContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [_navBarVisualEffectView.contentView addSubview:_navBarContentContainer];

    // Back Button (Luxury Glass Squircle)
    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    _backButton.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.4];
    _backButton.layer.cornerRadius = 20.0;
    if (@available(iOS 13.0, *)) {
        _backButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    NSString *backIconName = Language.isRTL ? @"arrow.right" : @"arrow.left";
    UIImage *backImg = [UIImage systemImageNamed:backIconName
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]];
    [_backButton setImage:backImg forState:UIControlStateNormal];
    _backButton.tintColor = [UIColor ppTextPrimary];
    [_backButton addTarget:self action:@selector(onBackTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBarContentContainer addSubview:_backButton];

    // Title Stack (Title + Live Status Capsule)
    UIStackView *titleStack = [[UIStackView alloc] init];
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.alignment = UIStackViewAlignmentLeading;
    titleStack.spacing = 1.0;
    [_navBarContentContainer addSubview:titleStack];

    _navTitleLabel = [[UILabel alloc] init];
    _navTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navTitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle3] scaledFontForFont:[Styling fontBold:18]];
    _navTitleLabel.textColor = [UIColor ppTextPrimary];
    _navTitleLabel.text = kLang(@"Banners_Nav_Title");
    _navTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [titleStack addArrangedSubview:_navTitleLabel];

    _navSubtitleLabel = [[UILabel alloc] init];
    _navSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navSubtitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[Styling fontMedium:12]];
    _navSubtitleLabel.textColor = [UIColor ppSuccess];
    _navSubtitleLabel.text = @"● 0 معروض";
    _navSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [titleStack addArrangedSubview:_navSubtitleLabel];

    // Primary Add Button ("+ بنر جديد")
    _primaryAddButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _primaryAddButton.translatesAutoresizingMaskIntoConstraints = NO;
    _primaryAddButton.backgroundColor = [UIColor ppPrimary];
    _primaryAddButton.tintColor = UIColor.whiteColor;
    _primaryAddButton.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontBold:14]];
    _primaryAddButton.layer.cornerRadius = 20.0;
    if (@available(iOS 13.0, *)) {
        _primaryAddButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _primaryAddButton.layer.shadowColor = [UIColor ppPrimary].CGColor;
    _primaryAddButton.layer.shadowOffset = CGSizeMake(0, 4);
    _primaryAddButton.layer.shadowRadius = 10;
    _primaryAddButton.layer.shadowOpacity = 0.25;
    UIImage *plusImg = [UIImage systemImageNamed:@"plus"
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold]];
    [_primaryAddButton setImage:plusImg forState:UIControlStateNormal];
    [_primaryAddButton setTitle:[NSString stringWithFormat:@"  %@", kLang(@"Banners_Nav_NewBanner")] forState:UIControlStateNormal];
    _primaryAddButton.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 16);
    [_primaryAddButton addTarget:self action:@selector(onPrimaryAddTapped) forControlEvents:UIControlEventTouchUpInside];
    [_navBarContentContainer addSubview:_primaryAddButton];

    // Bottom Hairline
    _navHairline = [[UIView alloc] init];
    _navHairline.translatesAutoresizingMaskIntoConstraints = NO;
    _navHairline.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.7];
    [_navBarVisualEffectView.contentView addSubview:_navHairline];

    [NSLayoutConstraint activateConstraints:@[
        [_navBarVisualEffectView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_navBarVisualEffectView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_navBarVisualEffectView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_navBarVisualEffectView.bottomAnchor constraintEqualToAnchor:_navBarContentContainer.bottomAnchor constant:10.0],

        [_navBarContentContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4.0],
        [_navBarContentContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_navBarContentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [_navBarContentContainer.heightAnchor constraintEqualToConstant:46.0],

        [_backButton.leadingAnchor constraintEqualToAnchor:_navBarContentContainer.leadingAnchor],
        [_backButton.centerYAnchor constraintEqualToAnchor:_navBarContentContainer.centerYAnchor],
        [_backButton.widthAnchor constraintEqualToConstant:40.0],
        [_backButton.heightAnchor constraintEqualToConstant:40.0],

        [titleStack.leadingAnchor constraintEqualToAnchor:_backButton.trailingAnchor constant:12.0],
        [titleStack.centerYAnchor constraintEqualToAnchor:_navBarContentContainer.centerYAnchor],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:_primaryAddButton.leadingAnchor constant:-12.0],

        [_primaryAddButton.trailingAnchor constraintEqualToAnchor:_navBarContentContainer.trailingAnchor],
        [_primaryAddButton.centerYAnchor constraintEqualToAnchor:_navBarContentContainer.centerYAnchor],
        [_primaryAddButton.heightAnchor constraintEqualToConstant:40.0],

        [_navHairline.leadingAnchor constraintEqualToAnchor:_navBarVisualEffectView.leadingAnchor],
        [_navHairline.trailingAnchor constraintEqualToAnchor:_navBarVisualEffectView.trailingAnchor],
        [_navHairline.bottomAnchor constraintEqualToAnchor:_navBarVisualEffectView.bottomAnchor],
        [_navHairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];
}

#pragma mark - Table View Setup

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 260.0;
    _tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    _tableView.estimatedSectionHeaderHeight = 64.0;
    _tableView.sectionFooterHeight = 6.0;
    _tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [_tableView registerClass:[PPFlagshipBannerCardCell class] forCellReuseIdentifier:[PPFlagshipBannerCardCell reuseIdentifier]];

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(onPullToRefresh) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

#pragma mark - Table Header (KPIs + Screen Chips + Search)

- (void)setupTableHeader {
    _tableHeaderContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 1.0)];
    _tableHeaderContainer.backgroundColor = UIColor.clearColor;
    _tableHeaderContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *headerStack = [[UIStackView alloc] init];
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    headerStack.axis = UILayoutConstraintAxisVertical;
    headerStack.spacing = 14.0;
    [_tableHeaderContainer addSubview:headerStack];

    // 1. KPI Telemetry Deck (4 Interactive Cards)
    _kpiDeckContainer = [[UIView alloc] init];
    _kpiDeckContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [headerStack addArrangedSubview:_kpiDeckContainer];

    UIStackView *kpiRow = [[UIStackView alloc] init];
    kpiRow.translatesAutoresizingMaskIntoConstraints = NO;
    kpiRow.axis = UILayoutConstraintAxisHorizontal;
    kpiRow.distribution = UIStackViewDistributionFillEqually;
    kpiRow.spacing = 8.0;
    [_kpiDeckContainer addSubview:kpiRow];

    _kpiTotalCard = [self createKPICardWithTitle:kLang(@"Banners_KPI_Total")
                                         iconName:@"square.stack.3d.up.fill"
                                       accentColor:[UIColor ppPrimary]
                                        valueLabel:&_kpiTotalCountLabel
                                            action:@selector(onKPITotalTapped)];
    [kpiRow addArrangedSubview:_kpiTotalCard];

    _kpiActiveCard = [self createKPICardWithTitle:kLang(@"Banners_KPI_Active")
                                          iconName:@"checkmark.seal.fill"
                                        accentColor:[UIColor ppSuccess]
                                         valueLabel:&_kpiActiveCountLabel
                                             action:@selector(onKPIActiveTapped)];
    [kpiRow addArrangedSubview:_kpiActiveCard];

    _kpiHiddenCard = [self createKPICardWithTitle:kLang(@"Banners_KPI_Hidden")
                                          iconName:@"eye.slash.fill"
                                        accentColor:[UIColor ppWarning]
                                         valueLabel:&_kpiHiddenCountLabel
                                             action:@selector(onKPIHiddenTapped)];
    [kpiRow addArrangedSubview:_kpiHiddenCard];

    _kpiGroupsCard = [self createKPICardWithTitle:kLang(@"Banners_KPI_Groups")
                                          iconName:@"rectangle.3.group.fill"
                                        accentColor:[UIColor ppInfo]
                                         valueLabel:&_kpiGroupsCountLabel
                                             action:@selector(onKPIGroupsTapped)];
    [kpiRow addArrangedSubview:_kpiGroupsCard];

    // 2. Placement Screen Filter Chips (Horizontal Scroller)
    _placementChipsScrollView = [[UIScrollView alloc] init];
    _placementChipsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _placementChipsScrollView.showsHorizontalScrollIndicator = NO;
    _placementChipsScrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [headerStack addArrangedSubview:_placementChipsScrollView];
    [_placementChipsScrollView.heightAnchor constraintEqualToConstant:40.0].active = YES;

    _placementChipsStack = [[UIStackView alloc] init];
    _placementChipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _placementChipsStack.axis = UILayoutConstraintAxisHorizontal;
    _placementChipsStack.spacing = 8.0;
    _placementChipsStack.alignment = UIStackViewAlignmentCenter;
    [_placementChipsScrollView addSubview:_placementChipsStack];

    NSArray *chipDefs = @[
        @{@"t": kLang(@"Banners_Screen_All"), @"id": @(-1)},
        @{@"t": kLang(@"Banners_Screen_Main"), @"id": @(PPBannerHolderMainView)},
        @{@"t": kLang(@"Banners_Screen_Accessories"), @"id": @(PPBannerHolderAccessoriesView)},
        @{@"t": kLang(@"Banners_Screen_Food"), @"id": @(PPBannerHolderFoodView)},
        @{@"t": kLang(@"Banners_Screen_Ads"), @"id": @(PPBannerHolderAdsView)},
        @{@"t": kLang(@"Banners_Screen_Vets"), @"id": @(PPBannerHolderVetsView)}
    ];

    for (NSDictionary *d in chipDefs) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        chip.layer.cornerRadius = 18.0;
        if (@available(iOS 13.0, *)) {
            chip.layer.cornerCurve = kCACornerCurveContinuous;
        }
        chip.tag = [d[@"id"] integerValue];
        chip.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontMedium:13]];
        chip.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
        [chip setTitle:d[@"t"] forState:UIControlStateNormal];
        [chip addTarget:self action:@selector(onPlacementChipTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_placementChipsStack addArrangedSubview:chip];
        [_placementChipButtons addObject:chip];
    }
    [self updatePlacementChipsState];

    // 3. Omni-Search Bar
    _searchContainer = [[UIView alloc] init];
    _searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _searchContainer.backgroundColor = [UIColor ppElevatedSurface];
    _searchContainer.layer.cornerRadius = 22.0;
    if (@available(iOS 13.0, *)) {
        _searchContainer.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _searchContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _searchContainer.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.85].CGColor;
    [headerStack addArrangedSubview:_searchContainer];
    [_searchContainer.heightAnchor constraintEqualToConstant:46.0].active = YES;

    UIImageView *searchLens = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    searchLens.translatesAutoresizingMaskIntoConstraints = NO;
    searchLens.tintColor = [UIColor ppTextSecondary];
    searchLens.contentMode = UIViewContentModeScaleAspectFit;
    [_searchContainer addSubview:searchLens];

    _searchTextField = [[UITextField alloc] init];
    _searchTextField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchTextField.placeholder = kLang(@"Banners_Search_Placeholder");
    _searchTextField.textColor = [UIColor ppTextPrimary];
    _searchTextField.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontRegular:14]];
    _searchTextField.delegate = self;
    _searchTextField.textAlignment = [Language alignmentForCurrentLanguage];
    _searchTextField.returnKeyType = UIReturnKeySearch;
    [_searchTextField addTarget:self action:@selector(onSearchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    [_searchContainer addSubview:_searchTextField];

    _searchClearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _searchClearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_searchClearButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    _searchClearButton.tintColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.7];
    _searchClearButton.hidden = YES;
    [_searchClearButton addTarget:self action:@selector(onSearchClearTapped) forControlEvents:UIControlEventTouchUpInside];
    [_searchContainer addSubview:_searchClearButton];

    _searchResultsCountLabel = [[UILabel alloc] init];
    _searchResultsCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _searchResultsCountLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[Styling fontBold:11]];
    _searchResultsCountLabel.textColor = [UIColor ppPrimary];
    _searchResultsCountLabel.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    _searchResultsCountLabel.layer.cornerRadius = 9.0;
    if (@available(iOS 13.0, *)) {
        _searchResultsCountLabel.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _searchResultsCountLabel.clipsToBounds = YES;
    _searchResultsCountLabel.textAlignment = NSTextAlignmentCenter;
    _searchResultsCountLabel.hidden = YES;
    [_searchContainer addSubview:_searchResultsCountLabel];

    // Header Layout Constraints
    [NSLayoutConstraint activateConstraints:@[
        [headerStack.topAnchor constraintEqualToAnchor:_tableHeaderContainer.topAnchor constant:12.0],
        [headerStack.leadingAnchor constraintEqualToAnchor:_tableHeaderContainer.leadingAnchor constant:16.0],
        [headerStack.trailingAnchor constraintEqualToAnchor:_tableHeaderContainer.trailingAnchor constant:-16.0],
        [headerStack.bottomAnchor constraintEqualToAnchor:_tableHeaderContainer.bottomAnchor constant:-8.0],

        [kpiRow.topAnchor constraintEqualToAnchor:_kpiDeckContainer.topAnchor],
        [kpiRow.leadingAnchor constraintEqualToAnchor:_kpiDeckContainer.leadingAnchor],
        [kpiRow.trailingAnchor constraintEqualToAnchor:_kpiDeckContainer.trailingAnchor],
        [kpiRow.bottomAnchor constraintEqualToAnchor:_kpiDeckContainer.bottomAnchor],

        [_placementChipsStack.topAnchor constraintEqualToAnchor:_placementChipsScrollView.topAnchor],
        [_placementChipsStack.leadingAnchor constraintEqualToAnchor:_placementChipsScrollView.leadingAnchor],
        [_placementChipsStack.trailingAnchor constraintEqualToAnchor:_placementChipsScrollView.trailingAnchor],
        [_placementChipsStack.bottomAnchor constraintEqualToAnchor:_placementChipsScrollView.bottomAnchor],
        [_placementChipsStack.heightAnchor constraintEqualToAnchor:_placementChipsScrollView.heightAnchor],

        [searchLens.leadingAnchor constraintEqualToAnchor:_searchContainer.leadingAnchor constant:14.0],
        [searchLens.centerYAnchor constraintEqualToAnchor:_searchContainer.centerYAnchor],
        [searchLens.widthAnchor constraintEqualToConstant:18.0],
        [searchLens.heightAnchor constraintEqualToConstant:18.0],

        [_searchTextField.leadingAnchor constraintEqualToAnchor:searchLens.trailingAnchor constant:10.0],
        [_searchTextField.centerYAnchor constraintEqualToAnchor:_searchContainer.centerYAnchor],
        [_searchTextField.trailingAnchor constraintEqualToAnchor:_searchResultsCountLabel.leadingAnchor constant:-8.0],

        [_searchResultsCountLabel.trailingAnchor constraintEqualToAnchor:_searchClearButton.leadingAnchor constant:-6.0],
        [_searchResultsCountLabel.centerYAnchor constraintEqualToAnchor:_searchContainer.centerYAnchor],
        [_searchResultsCountLabel.heightAnchor constraintEqualToConstant:20.0],

        [_searchClearButton.trailingAnchor constraintEqualToAnchor:_searchContainer.trailingAnchor constant:-10.0],
        [_searchClearButton.centerYAnchor constraintEqualToAnchor:_searchContainer.centerYAnchor],
        [_searchClearButton.widthAnchor constraintEqualToConstant:24.0],
        [_searchClearButton.heightAnchor constraintEqualToConstant:24.0]
    ]];

    _tableView.tableHeaderView = _tableHeaderContainer;
}

- (UIButton *)createKPICardWithTitle:(NSString *)title
                            iconName:(NSString *)iconName
                         accentColor:(UIColor *)accentColor
                          valueLabel:(UILabel * __strong *)valueLabel
                              action:(SEL)action {
    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppElevatedSurface];
    card.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) {
        card.layer.cornerCurve = kCACornerCurveContinuous;
    }
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
    card.layer.shadowColor = [UIColor ppShadow].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 4);
    card.layer.shadowRadius = 8;
    card.layer.shadowOpacity = 0.04;
    [card addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [accentColor colorWithAlphaComponent:0.12];
    iconCircle.layer.cornerRadius = 13.0;
    iconCircle.userInteractionEnabled = NO;
    [card addSubview:iconCircle];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = accentColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.userInteractionEnabled = NO;
    [iconCircle addSubview:iconView];

    UILabel *val = [[UILabel alloc] init];
    val.translatesAutoresizingMaskIntoConstraints = NO;
    val.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle3] scaledFontForFont:[Styling fontBold:18]];
    val.textColor = [UIColor ppTextPrimary];
    val.textAlignment = NSTextAlignmentCenter;
    val.text = @"0";
    val.userInteractionEnabled = NO;
    [card addSubview:val];

    UILabel *cap = [[UILabel alloc] init];
    cap.translatesAutoresizingMaskIntoConstraints = NO;
    cap.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[Styling fontMedium:11]];
    cap.textColor = [UIColor ppTextSecondary];
    cap.textAlignment = NSTextAlignmentCenter;
    cap.text = title;
    cap.userInteractionEnabled = NO;
    [card addSubview:cap];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:90.0],

        [iconCircle.topAnchor constraintEqualToAnchor:card.topAnchor constant:10.0],
        [iconCircle.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iconCircle.widthAnchor constraintEqualToConstant:26.0],
        [iconCircle.heightAnchor constraintEqualToConstant:26.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:14.0],
        [iconView.heightAnchor constraintEqualToConstant:14.0],

        [val.topAnchor constraintEqualToAnchor:iconCircle.bottomAnchor constant:3.0],
        [val.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:2.0],
        [val.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-2.0],

        [cap.topAnchor constraintEqualToAnchor:val.bottomAnchor constant:1.0],
        [cap.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:2.0],
        [cap.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-2.0],
        [cap.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-6.0]
    ]];

    if (valueLabel) *valueLabel = val;
    return card;
}

#pragma mark - Empty State Setup

- (void)setupEmptyStateView {
    _emptyStateView = [[UIView alloc] init];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    _emptyStateView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:_emptyStateView];

    _emptyImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.stack.3d.up.slash"]];
    _emptyImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyImageView.tintColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.4];
    _emptyImageView.contentMode = UIViewContentModeScaleAspectFit;
    [_emptyStateView addSubview:_emptyImageView];

    _emptyTitleLabel = [[UILabel alloc] init];
    _emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyTitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:17]];
    _emptyTitleLabel.textColor = [UIColor ppTextPrimary];
    _emptyTitleLabel.textAlignment = NSTextAlignmentCenter;
    _emptyTitleLabel.text = kLang(@"Banners_Empty_Title");
    [_emptyStateView addSubview:_emptyTitleLabel];

    _emptySubtitleLabel = [[UILabel alloc] init];
    _emptySubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptySubtitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontRegular:13]];
    _emptySubtitleLabel.textColor = [UIColor ppTextSecondary];
    _emptySubtitleLabel.textAlignment = NSTextAlignmentCenter;
    _emptySubtitleLabel.numberOfLines = 0;
    _emptySubtitleLabel.text = kLang(@"Banners_Empty_Subtitle");
    [_emptyStateView addSubview:_emptySubtitleLabel];

    _emptyActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _emptyActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyActionButton.backgroundColor = [UIColor ppPrimary];
    _emptyActionButton.tintColor = UIColor.whiteColor;
    _emptyActionButton.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontBold:14]];
    _emptyActionButton.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) {
        _emptyActionButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [_emptyActionButton setTitle:kLang(@"Banners_Nav_NewBanner") forState:UIControlStateNormal];
    _emptyActionButton.contentEdgeInsets = UIEdgeInsetsMake(10, 20, 10, 20);
    [_emptyActionButton addTarget:self action:@selector(onPrimaryAddTapped) forControlEvents:UIControlEventTouchUpInside];
    [_emptyStateView addSubview:_emptyActionButton];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:50.0],
        [_emptyStateView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32.0],
        [_emptyStateView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32.0],

        [_emptyImageView.topAnchor constraintEqualToAnchor:_emptyStateView.topAnchor],
        [_emptyImageView.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [_emptyImageView.widthAnchor constraintEqualToConstant:64.0],
        [_emptyImageView.heightAnchor constraintEqualToConstant:64.0],

        [_emptyTitleLabel.topAnchor constraintEqualToAnchor:_emptyImageView.bottomAnchor constant:14.0],
        [_emptyTitleLabel.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [_emptyTitleLabel.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

        [_emptySubtitleLabel.topAnchor constraintEqualToAnchor:_emptyTitleLabel.bottomAnchor constant:6.0],
        [_emptySubtitleLabel.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [_emptySubtitleLabel.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

        [_emptyActionButton.topAnchor constraintEqualToAnchor:_emptySubtitleLabel.bottomAnchor constant:16.0],
        [_emptyActionButton.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [_emptyActionButton.bottomAnchor constraintEqualToAnchor:_emptyStateView.bottomAnchor]
    ]];
}

#pragma mark - Layout Offsets & Sizing

- (void)updateLayoutOffsets {
    CGFloat navH = CGRectGetMaxY(self.navBarVisualEffectView.frame);
    if (navH <= 0.0) {
        navH = self.view.safeAreaInsets.top + 60.0;
    }
    UIEdgeInsets insets = UIEdgeInsetsMake(navH, 0, self.view.safeAreaInsets.bottom + 20.0, 0);
    self.tableView.contentInset = insets;
    self.tableView.scrollIndicatorInsets = insets;
}

- (void)sizeHeaderIfNeeded {
    if (!self.tableHeaderContainer || self.isSizingHeader) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;

    self.isSizingHeader = YES;
    CGRect frame = self.tableHeaderContainer.frame;
    frame.size.width = width;
    self.tableHeaderContainer.frame = frame;
    [self.tableHeaderContainer setNeedsLayout];
    [self.tableHeaderContainer layoutIfNeeded];

    CGFloat height = [self.tableHeaderContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                             withHorizontalFittingPriority:UILayoutPriorityRequired
                                                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat targetH = ceil(MAX(1.0, height));
    if (fabs(frame.size.height - targetH) > 0.5) {
        frame.size.height = targetH;
        self.tableHeaderContainer.frame = frame;
        self.tableView.tableHeaderView = self.tableHeaderContainer;
    }
    self.isSizingHeader = NO;
}

#pragma mark - Firestore Observation

- (void)startObservingBanners {
    __weak typeof(self) weakSelf = self;
    self.bannersListener = [[PPBannersManager sharedManager] observeAllBanner:^(NSArray<MainBannerModel *> * _Nullable items, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf.refreshControl endRefreshing];
        if (error) {
            NSLog(@"[PPBannersListVC] observeAllBanner error: %@", error);
            return;
        }

        strongSelf.allGroups = [items mutableCopy] ?: [NSMutableArray array];
        [strongSelf applyFilterAndReload];
    }];
}

- (void)onPullToRefresh {
    [self.allGroups removeAllObjects];
    [self reloadBannersData];
}

- (void)reloadBannersData {
    if (self.bannersListener) {
        [self.bannersListener remove];
    }
    [self startObservingBanners];
}

#pragma mark - Filtering & KPI Updates

- (void)applyFilterAndReload {
    NSString *q = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    NSMutableArray<MainBannerModel *> *result = [NSMutableArray array];

    NSInteger totalBannersCount = 0;
    NSInteger visibleBannersCount = 0;
    NSInteger hiddenBannersCount = 0;

    for (MainBannerModel *group in self.allGroups) {
        NSInteger childCount = group.childBanners.count;
        totalBannersCount += childCount;
        if (group.bannerViewVisible) {
            visibleBannersCount += childCount;
        } else {
            hiddenBannersCount += childCount;
        }

        // Holder Screen filter check
        if (self.selectedHolderFilter != -1 && group.bannerViewHolder != self.selectedHolderFilter) {
            continue;
        }

        // Status filter check
        if (self.statusFilter == PPBannerStatusFilterActive && !group.bannerViewVisible) {
            continue;
        }
        if (self.statusFilter == PPBannerStatusFilterHidden && group.bannerViewVisible) {
            continue;
        }

        // Search query check
        if (q.length == 0) {
            [result addObject:group];
        } else {
            BOOL groupMatch = [group.bannerViewID.lowercaseString containsString:q] || [group.docID.lowercaseString containsString:q];
            NSMutableArray<PPBannerViewModel *> *matchedChildren = [NSMutableArray array];
            for (PPBannerViewModel *child in group.childBanners) {
                NSString *t = [child localizedTitleText].lowercaseString;
                NSString *d = [child localizedDescText].lowercaseString;
                NSString *bID = child.bannerID.lowercaseString;
                NSString *val = child.onTapValue.lowercaseString;
                if ([t containsString:q] || [d containsString:q] || [bID containsString:q] || [val containsString:q] || groupMatch) {
                    [matchedChildren addObject:child];
                }
            }
            if (groupMatch || matchedChildren.count > 0) {
                MainBannerModel *filteredGroup = [[MainBannerModel alloc] initWithID:group.bannerViewID
                                                                             visible:group.bannerViewVisible
                                                                              holder:group.bannerViewHolder
                                                                            position:group.bannerViewPosition
                                                                         transaction:group.bannerViewTransaction
                                                                             banners:matchedChildren.count > 0 ? matchedChildren : group.childBanners];
                filteredGroup.docID = group.docID;
                [result addObject:filteredGroup];
            }
        }
    }

    self.filteredGroups = result;

    // Update KPI Labels
    self.kpiTotalCountLabel.text = [NSString stringWithFormat:@"%ld", (long)totalBannersCount];
    self.kpiActiveCountLabel.text = [NSString stringWithFormat:@"%ld", (long)visibleBannersCount];
    self.kpiHiddenCountLabel.text = [NSString stringWithFormat:@"%ld", (long)hiddenBannersCount];
    self.kpiGroupsCountLabel.text = [NSString stringWithFormat:@"%ld", (long)self.allGroups.count];

    // Update Nav Subtitle
    self.navSubtitleLabel.text = [NSString stringWithFormat:kLang(@"Banners_Nav_Subtitle_Format"), (long)visibleBannersCount, (long)self.allGroups.count];

    // Update Search Results Counter
    if (q.length > 0) {
        NSInteger filteredTotal = 0;
        for (MainBannerModel *g in self.filteredGroups) filteredTotal += g.childBanners.count;
        self.searchResultsCountLabel.hidden = NO;
        self.searchResultsCountLabel.text = [NSString stringWithFormat:@"  %@  ", [NSString stringWithFormat:kLang(@"Banners_Search_Count_Format"), (long)filteredTotal]];
    } else {
        self.searchResultsCountLabel.hidden = YES;
    }

    [self updateKPICardsHighlight];
    [self.tableView reloadData];

    // Handle Empty State
    BOOL isEmpty = (self.filteredGroups.count == 0);
    self.emptyStateView.hidden = !isEmpty;
    if (isEmpty) {
        if (q.length > 0 || self.statusFilter != PPBannerStatusFilterAll || self.selectedHolderFilter != -1) {
            self.emptyTitleLabel.text = kLang(@"Banners_Empty_Filtered_Title");
            self.emptySubtitleLabel.text = kLang(@"Banners_Empty_Filtered_Subtitle");
            [self.emptyActionButton setTitle:kLang(@"Banners_Search_Reset") forState:UIControlStateNormal];
        } else {
            self.emptyTitleLabel.text = kLang(@"Banners_Empty_Title");
            self.emptySubtitleLabel.text = kLang(@"Banners_Empty_Subtitle");
            [self.emptyActionButton setTitle:kLang(@"Banners_Nav_NewBanner") forState:UIControlStateNormal];
        }
    }
}

- (void)updateKPICardsHighlight {
    self.kpiTotalCard.layer.borderColor = (self.statusFilter == PPBannerStatusFilterAll)
        ? [UIColor ppPrimary].CGColor
        : [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
    self.kpiActiveCard.layer.borderColor = (self.statusFilter == PPBannerStatusFilterActive)
        ? [UIColor ppSuccess].CGColor
        : [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
    self.kpiHiddenCard.layer.borderColor = (self.statusFilter == PPBannerStatusFilterHidden)
        ? [UIColor ppWarning].CGColor
        : [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
}

- (void)updatePlacementChipsState {
    for (UIButton *btn in self.placementChipButtons) {
        BOOL isSelected = (btn.tag == self.selectedHolderFilter);
        if (isSelected) {
            btn.backgroundColor = [UIColor ppPrimary];
            btn.tintColor = UIColor.whiteColor;
            btn.layer.borderWidth = 0.0;
        } else {
            btn.backgroundColor = [UIColor ppElevatedSurface];
            btn.tintColor = [UIColor ppTextSecondary];
            btn.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
            btn.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
        }
    }
}

#pragma mark - Search Text Delegate & Actions

- (void)onSearchTextChanged:(UITextField *)textField {
    self.searchQuery = textField.text ?: @"";
    self.searchClearButton.hidden = (self.searchQuery.length == 0);
    [self applyFilterAndReload];
}

- (void)onSearchClearTapped {
    self.searchTextField.text = @"";
    self.searchQuery = @"";
    self.searchClearButton.hidden = YES;
    [self.searchTextField resignFirstResponder];
    [self applyFilterAndReload];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Filter Button Handlers

- (void)onKPITotalTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    self.statusFilter = PPBannerStatusFilterAll;
    self.selectedHolderFilter = -1;
    [self updatePlacementChipsState];
    [self applyFilterAndReload];
}

- (void)onKPIActiveTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    self.statusFilter = (self.statusFilter == PPBannerStatusFilterActive) ? PPBannerStatusFilterAll : PPBannerStatusFilterActive;
    [self applyFilterAndReload];
}

- (void)onKPIHiddenTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    self.statusFilter = (self.statusFilter == PPBannerStatusFilterHidden) ? PPBannerStatusFilterAll : PPBannerStatusFilterHidden;
    [self applyFilterAndReload];
}

- (void)onKPIGroupsTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    [self onPrimaryAddTapped];
}

- (void)onPlacementChipTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    self.selectedHolderFilter = sender.tag;
    [self updatePlacementChipsState];
    [self applyFilterAndReload];
}

#pragma mark - Navigation Actions

- (void)onBackTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];

    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (![self pp_dismissWorkflowRouteIfPossible]) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)onPrimaryAddTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Banners_Nav_NewBanner")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    if (self.allGroups.count > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Banners_Nav_AddBannerToGroup")
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction * _Nonnull action) {
            [weakSelf showGroupPickerForAddingBanner];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Banners_Nav_CreateGroup")
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * _Nonnull action) {
        PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeNewGroup group:nil banner:nil];
        [weakSelf.navigationController pushViewController:vc animated:YES];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Common_Cancel")
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.primaryAddButton;
        sheet.popoverPresentationController.sourceRect = self.primaryAddButton.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showGroupPickerForAddingBanner {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:kLang(@"Banners_Nav_AddBannerToGroup")
                                                                    message:kLang(@"Choose Banner Group")
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (MainBannerModel *group in self.allGroups) {
        NSString *h = [weakSelf holderNameString:group.bannerViewHolder];
        NSString *pos = [weakSelf positionNameString:group.bannerViewPosition];
        NSString *title = [NSString stringWithFormat:@"%@ • %@ (%@)", h, pos, group.bannerViewID ?: group.docID];
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
            PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeAddBannerToGroup group:group banner:nil];
            [weakSelf.navigationController pushViewController:vc animated:YES];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:kLang(@"Common_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    if (picker.popoverPresentationController) {
        picker.popoverPresentationController.sourceView = self.primaryAddButton;
        picker.popoverPresentationController.sourceRect = self.primaryAddButton.bounds;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.filteredGroups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    MainBannerModel *group = self.filteredGroups[section];
    return group.childBanners.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPFlagshipBannerCardCell *cell = [tableView dequeueReusableCellWithIdentifier:[PPFlagshipBannerCardCell reuseIdentifier] forIndexPath:indexPath];
    MainBannerModel *group = self.filteredGroups[indexPath.section];
    PPBannerViewModel *banner = group.childBanners[indexPath.row];
    cell.delegate = self;
    [cell configureWithBanner:banner group:group indexPath:indexPath];
    return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    MainBannerModel *group = self.filteredGroups[section];

    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppElevatedSurface];
    card.layer.cornerRadius = 16.0;
    if (@available(iOS 13.0, *)) {
        card.layer.cornerCurve = kCACornerCurveContinuous;
    }
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.75].CGColor;
    [header addSubview:card];

    // Icon Circle for Holder
    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    iconCircle.layer.cornerRadius = 14.0;
    [card addSubview:iconCircle];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self holderIconName:group.bannerViewHolder]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [UIColor ppPrimary];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconCircle addSubview:iconView];

    // Title & Tags Stack
    UIStackView *titleStack = [[UIStackView alloc] init];
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.alignment = UIStackViewAlignmentLeading;
    titleStack.spacing = 2.0;
    [card addSubview:titleStack];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:15]];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = [NSString stringWithFormat:@"%@: %@ • %@", kLang(@"screen"), [self holderNameString:group.bannerViewHolder], [self positionNameString:group.bannerViewPosition]];
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [titleStack addArrangedSubview:titleLabel];

    UILabel *badgeSubtitle = [[UILabel alloc] init];
    badgeSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    badgeSubtitle.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[Styling fontRegular:11]];
    badgeSubtitle.textColor = [UIColor ppTextSecondary];
    badgeSubtitle.text = [NSString stringWithFormat:@"ID: %@ • %@", group.bannerViewID ?: group.docID, [self transitionNameString:group.bannerViewTransaction]];
    badgeSubtitle.textAlignment = [Language alignmentForCurrentLanguage];
    [titleStack addArrangedSubview:badgeSubtitle];

    // Section Action Buttons (Add Banner to Group + Group Menu)
    UIStackView *actionStack = [[UIStackView alloc] init];
    actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    actionStack.axis = UILayoutConstraintAxisHorizontal;
    actionStack.spacing = 6.0;
    actionStack.alignment = UIStackViewAlignmentCenter;
    [card addSubview:actionStack];

    UIButton *addBannerBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    addBannerBtn.translatesAutoresizingMaskIntoConstraints = NO;
    addBannerBtn.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    addBannerBtn.tintColor = [UIColor ppPrimary];
    [addBannerBtn setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    addBannerBtn.layer.cornerRadius = 16.0;
    addBannerBtn.tag = section;
    [addBannerBtn addTarget:self action:@selector(onAddBannerToGroupTapped:) forControlEvents:UIControlEventTouchUpInside];
    [actionStack addArrangedSubview:addBannerBtn];

    UIButton *groupMenuBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    groupMenuBtn.translatesAutoresizingMaskIntoConstraints = NO;
    groupMenuBtn.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.35];
    groupMenuBtn.tintColor = [UIColor ppTextPrimary];
    [groupMenuBtn setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    groupMenuBtn.layer.cornerRadius = 16.0;
    groupMenuBtn.tag = section;
    [groupMenuBtn addTarget:self action:@selector(onGroupMenuTapped:) forControlEvents:UIControlEventTouchUpInside];
    [actionStack addArrangedSubview:groupMenuBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:6.0],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-6.0],

        [iconCircle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [iconCircle.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconCircle.widthAnchor constraintEqualToConstant:28.0],
        [iconCircle.heightAnchor constraintEqualToConstant:28.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:16.0],
        [iconView.heightAnchor constraintEqualToConstant:16.0],

        [titleStack.leadingAnchor constraintEqualToAnchor:iconCircle.trailingAnchor constant:10.0],
        [titleStack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:actionStack.leadingAnchor constant:-8.0],

        [actionStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [actionStack.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],

        [addBannerBtn.widthAnchor constraintEqualToConstant:32.0],
        [addBannerBtn.heightAnchor constraintEqualToConstant:32.0],

        [groupMenuBtn.widthAnchor constraintEqualToConstant:32.0],
        [groupMenuBtn.heightAnchor constraintEqualToConstant:32.0]
    ]];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 64.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MainBannerModel *group = self.filteredGroups[indexPath.section];
    PPBannerViewModel *child = group.childBanners[indexPath.row];
    [self openBannerEditorForBanner:child inGroup:group];
}

#pragma mark - PPFlagshipBannerCardDelegate

- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didTapPreviewForBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group {
    PPBannerLivePreviewVC *previewVC = [[PPBannerLivePreviewVC alloc] initWithBanner:banner group:group];
    __weak typeof(self) weakSelf = self;
    previewVC.onEditRequested = ^(PPBannerViewModel *b, MainBannerModel *g) {
        [weakSelf openBannerEditorForBanner:b inGroup:g];
    };
    [self presentViewController:previewVC animated:YES completion:nil];
}

- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didTapEditForBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group {
    [self openBannerEditorForBanner:banner inGroup:group];
}

- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didToggleActive:(BOOL)active forBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group {
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Updating") subtitle:nil];
    group.bannerViewVisible = active;

    __weak typeof(self) weakSelf = self;
    [[PPBannersManager sharedManager] updateBannerGroup:group completion:^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            [PPHUD showSuccess:kLang(@"Updated") subtitle:group.bannerViewVisible ? kLang(@"Banners_Status_Active") : kLang(@"Banners_Status_Hidden")];
            [weakSelf applyFilterAndReload];
        }
    }];
}

- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didTapMoreOptionsForBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Group Settings")
                                                                   message:banner.localizedTitleText
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Banners_Action_Preview")
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf bannerCardCell:cell didTapPreviewForBanner:banner inGroup:group];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Banners_Action_Edit")
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf openBannerEditorForBanner:banner inGroup:group];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Banners_Action_Duplicate")
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf duplicateBanner:banner inGroup:group];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Banners_Delete")
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf confirmDeleteBanner:banner inGroup:group];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Common_Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = sourceView;
        sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Group Actions

- (void)onAddBannerToGroupTapped:(UIButton *)sender {
    MainBannerModel *group = self.filteredGroups[sender.tag];
    PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeAddBannerToGroup group:group banner:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)onGroupMenuTapped:(UIButton *)sender {
    MainBannerModel *group = self.filteredGroups[sender.tag];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Group Settings")
                                                                   message:[NSString stringWithFormat:@"%@ • %@", [self holderNameString:group.bannerViewHolder], [self positionNameString:group.bannerViewPosition]]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    // Add Banner
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Add banner to group")
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * _Nonnull action) {
        PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeAddBannerToGroup group:group banner:nil];
        [weakSelf.navigationController pushViewController:vc animated:YES];
    }]];

    // Edit Group Settings
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Edit Banner Group")
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * _Nonnull action) {
        PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeGroupOnly group:group banner:nil];
        [weakSelf.navigationController pushViewController:vc animated:YES];
    }]];

    // Toggle Group Visibility
    NSString *toggleTitle = group.bannerViewVisible ? kLang(@"Banners_Hide") : kLang(@"Banners_Show");
    [sheet addAction:[UIAlertAction actionWithTitle:toggleTitle
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf toggleGroupVisibility:group];
    }]];

    // Delete Group
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Common_Delete")
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf confirmDeleteGroup:group];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Common_Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = sender;
        sheet.popoverPresentationController.sourceRect = sender.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toggleGroupVisibility:(MainBannerModel *)group {
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Updating") subtitle:nil];
    group.bannerViewVisible = !group.bannerViewVisible;
    __weak typeof(self) weakSelf = self;
    [[PPBannersManager sharedManager] updateBannerGroup:group completion:^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            [PPHUD showSuccess:kLang(@"Updated") subtitle:kLang(@"Banners_Visibility_Changed")];
            [weakSelf applyFilterAndReload];
        }
    }];
}

- (void)confirmDeleteGroup:(MainBannerModel *)group {
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                                title:kLang(@"Banners_Confirm_Delete_Title")
                             subtitle:kLang(@"Delete this banner view and its children?")
                          placeholder:nil
                        confirmButton:kLang(@"Common_Delete")
                         cancelButton:kLang(@"Common_Cancel")
                         confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Deleting") subtitle:nil];
        [[PPBannersManager sharedManager] deleteBannerGroup:group completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Banners_Deleted") subtitle:kLang(@"Banner removed")];
                [weakSelf applyFilterAndReload];
            }
        }];
    } cancelBlock:^{}];
}

- (void)confirmDeleteBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group {
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                                title:kLang(@"Banners_Confirm_Delete_Title")
                             subtitle:kLang(@"Banners_Confirm_Delete_Message")
                          placeholder:nil
                        confirmButton:kLang(@"Common_Delete")
                         cancelButton:kLang(@"Common_Cancel")
                         confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Deleting") subtitle:nil];
        [[PPBannersManager sharedManager] deleteChildBanner:banner inGroup:group completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Banners_Deleted") subtitle:kLang(@"Banners_Deleted_Subtitle")];
                [weakSelf applyFilterAndReload];
            }
        }];
    } cancelBlock:^{}];
}

- (void)duplicateBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group {
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Saving") subtitle:nil];
    PPBannerViewModel *copy = [[PPBannerViewModel alloc] initWithTitleEn:[NSString stringWithFormat:@"%@ (Copy)", banner.titleTextEn ?: @""]
                                                                titleAr:[NSString stringWithFormat:@"%@ (نسخة)", banner.titleTextAr ?: @""]
                                                             descTextEn:banner.descTextEn ?: @""
                                                             descTextAr:banner.descTextAr ?: @""
                                                               postDate:[NSDate date]
                                                     backgroundImageURL:banner.backgroundImageURL
                                                         sampleImageURL:banner.sampleImageURL
                                                          badgeImageURL:banner.badgeImageURL
                                                            onTapAction:banner.onTapAction
                                                              textStyle:banner.pannerTextStyle
                                                             onTapValue:banner.onTapValue
                                                               bannerID:[[NSUUID UUID] UUIDString]];
    __weak typeof(self) weakSelf = self;
    [[PPBannersManager sharedManager] addChildBanner:copy toGroup:group.docID completion:^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            [PPHUD showSuccess:kLang(@"Banners_Updated") subtitle:kLang(@"Banners_Action_Duplicate")];
            [weakSelf applyFilterAndReload];
        }
    }];
}

- (void)openBannerEditorForBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group {
    PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeBannerOnly
                                                                                  group:group
                                                                                 banner:banner];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Helper Names & Icons

- (NSString *)holderNameString:(PPBannerHolder)holder {
    switch (holder) {
        case PPBannerHolderMainView:        return kLang(@"Main");
        case PPBannerHolderAccessoriesView: return kLang(@"Accessories");
        case PPBannerHolderAdsView:         return kLang(@"Ads");
        case PPBannerHolderFoodView:        return kLang(@"Food");
        case PPBannerHolderVetsView:        return kLang(@"Vets");
    }
    return kLang(@"Main");
}

- (NSString *)holderIconName:(PPBannerHolder)holder {
    switch (holder) {
        case PPBannerHolderMainView:        return @"house.fill";
        case PPBannerHolderAccessoriesView: return @"bag.fill";
        case PPBannerHolderAdsView:         return @"megaphone.fill";
        case PPBannerHolderFoodView:        return @"takeoutbag.and.cup.and.straw.fill";
        case PPBannerHolderVetsView:        return @"cross.case.fill";
    }
    return @"house.fill";
}

- (NSString *)positionNameString:(PPBannerPosition)pos {
    switch (pos) {
        case PPBannerPositionTop:    return kLang(@"Top");
        case PPBannerPositionCenter: return kLang(@"Center");
        case PPBannerPositionBottom: return kLang(@"Bottom");
    }
    return kLang(@"Top");
}

- (NSString *)transitionNameString:(PPBannerTransaction)tr {
    switch (tr) {
        case PPBannerTransactionScroll:  return kLang(@"Banners_Transition_Scroll");
        case PPBannerTransactionFade:    return kLang(@"Banners_Transition_Fade");
        case PPBannerTransactionReplace: return kLang(@"Banners_Transition_Replace");
    }
    return kLang(@"Banners_Transition_Scroll");
}

@end
