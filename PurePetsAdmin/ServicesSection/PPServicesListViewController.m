//
//  PPServicesListViewController.m
//  PurePetsAdmin
//

#import "PPServicesListViewController.h"
#import "PPServiceModel.h"
#import "PPServiceManager.h"
#import "PPServiceCell.h"
#import "PPAddEditServiceViewController.h"
#import "PPServiceDetailViewController.h"
#import "PPServiceModerationViewController.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

typedef NS_ENUM(NSInteger, PPServicePrimaryFilter) {
    PPServicePrimaryFilterAll = 0,
    PPServicePrimaryFilterLive,
    PPServicePrimaryFilterArchived
};

typedef NS_ENUM(NSInteger, PPServiceSecondaryFilter) {
    PPServiceSecondaryFilterAny = 0,
    PPServiceSecondaryFilterNeedsReview,
    PPServiceSecondaryFilterVerified,
    PPServiceSecondaryFilterPending,
    PPServiceSecondaryFilterBlocked,
    PPServiceSecondaryFilterDisabled
};

typedef NS_ENUM(NSInteger, PPServiceSortOption) {
    PPServiceSortOptionUpdatedDesc = 0,
    PPServiceSortOptionTitleAsc,
    PPServiceSortOptionPriceHighToLow,
    PPServiceSortOptionPriceLowToHigh,
    PPServiceSortOptionAvailableSoonest
};

@interface _PPServiceStatPill : UIView
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *captionLabel;
- (instancetype)initWithCaption:(NSString *)caption accentColor:(UIColor *)accentColor;
- (void)updateValue:(NSInteger)value;
@end

@implementation _PPServiceStatPill

- (instancetype)initWithCaption:(NSString *)caption accentColor:(UIColor *)accentColor {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [accentColor colorWithAlphaComponent:0.10];
        self.layer.cornerRadius = 16.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:21];
        _valueLabel.textColor = accentColor;
        _valueLabel.textAlignment = NSTextAlignmentCenter;
        _valueLabel.text = @"0";
        [self addSubview:_valueLabel];

        _captionLabel = [UILabel new];
        _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _captionLabel.font = [Styling fontMedium:10];
        _captionLabel.textColor = SeconderyTextClr;
        _captionLabel.textAlignment = NSTextAlignmentCenter;
        _captionLabel.text = caption;
        [self addSubview:_captionLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_valueLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [_valueLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_captionLabel.topAnchor constraintEqualToAnchor:_valueLabel.bottomAnchor constant:3],
            [_captionLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
            [_captionLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
            [_captionLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12]
        ]];
    }
    return self;
}

- (void)updateValue:(NSInteger)value {
    self.valueLabel.text = [NSString stringWithFormat:@"%ld", (long)value];
}

@end

@interface PPServicesListViewController () <UITableViewDataSource, UITableViewDelegate, PPSDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPS *searchView;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UIButton *refineButton;
@property (nonatomic, strong) NSMutableArray<PPServiceModel *> *allServices;
@property (nonatomic, strong) NSMutableArray<PPServiceModel *> *filteredServices;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, assign) PPServicePrimaryFilter primaryFilter;
@property (nonatomic, assign) PPServiceSecondaryFilter secondaryFilter;
@property (nonatomic, assign) PPServiceSortOption sortOption;
@property (nonatomic, strong) id<FIRListenerRegistration> listener;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL didPlayEntrance;

@property (nonatomic, strong) UIStackView *statsStack;
@property (nonatomic, strong) _PPServiceStatPill *totalPill;
@property (nonatomic, strong) _PPServiceStatPill *livePill;
@property (nonatomic, strong) _PPServiceStatPill *reviewPill;
@property (nonatomic, strong) _PPServiceStatPill *archivedPill;

@property (nonatomic, strong) UIView *placeholderView;
@property (nonatomic, strong) UIImageView *placeholderIconView;
@property (nonatomic, strong) UILabel *placeholderTitleLabel;
@property (nonatomic, strong) UILabel *placeholderSubtitleLabel;
@property (nonatomic, strong) UIButton *placeholderButton;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *loadingLabel;
@end

@implementation PPServicesListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;
    self.allServices = [NSMutableArray array];
    self.filteredServices = [NSMutableArray array];
    self.searchQuery = @"";
    self.primaryFilter = PPServicePrimaryFilterAll;
    self.secondaryFilter = PPServiceSecondaryFilterAny;
    self.sortOption = PPServiceSortOptionUpdatedDesc;

    [self setupStatsHeader];
    [self setupControls];
    [self setupTableView];
    [self setupPlaceholderView];
    [self setupLoadingView];
    [self updateRefineButtonTitle];
    [self startListening];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIButton *plusButton = [self pp_ButtonWithSystemName:@"plus" action:@selector(addServiceTapped)];
    [self pp_navBarWithOtherButton:plusButton title:kLang(@"Service_Section_Title")];
}

- (void)dealloc {
    [self.listener remove];
}

#pragma mark - Setup

- (void)pp_onBackTapped {
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)setupStatsHeader {
    // 1. Navigation Top Bar (Back Button + Add Button)
    UIButton *backBtn = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(pp_onBackTapped)];
    [self.view addSubview:backBtn];

    UIButton *addBtn = [self pp_ButtonWithSystemName:@"plus" action:@selector(addServiceTapped)];
    [self.view addSubview:addBtn];

    // 2. Eyebrow Category Breadcrumb
    UILabel *eyebrowLabel = [UILabel new];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [Styling fontRegular:12];
    eyebrowLabel.textColor = SeconderyTextClr;
    eyebrowLabel.text = [NSString stringWithFormat:@"%@ / %@", kLang(@"CommandCenter_Work_Workspace"), kLang(@"Service_Section_Title")];
    eyebrowLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [self.view addSubview:eyebrowLabel];

    // 3. Dossier Large Title
    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:22];
    titleLabel.textColor = PrimaryTextClr;
    titleLabel.text = kLang(@"Service_Section_Title");
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [self.view addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [backBtn.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [backBtn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [backBtn.widthAnchor constraintEqualToConstant:44],
        [backBtn.heightAnchor constraintEqualToConstant:44],

        [addBtn.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
        [addBtn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [addBtn.widthAnchor constraintEqualToConstant:44],
        [addBtn.heightAnchor constraintEqualToConstant:44],

        [eyebrowLabel.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:2],
        [eyebrowLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [eyebrowLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [titleLabel.topAnchor constraintEqualToAnchor:eyebrowLabel.bottomAnchor constant:2],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16]
    ]];

    self.totalPill = [[_PPServiceStatPill alloc] initWithCaption:kLang(@"Service_Stat_Total") accentColor:AppPrimaryClr];
    self.livePill = [[_PPServiceStatPill alloc] initWithCaption:kLang(@"Service_Stat_Live") accentColor:[UIColor ppSuccess]];
    self.reviewPill = [[_PPServiceStatPill alloc] initWithCaption:kLang(@"Service_Stat_Review") accentColor:[UIColor ppWarning]];
    self.archivedPill = [[_PPServiceStatPill alloc] initWithCaption:kLang(@"Service_Stat_Archived") accentColor:[UIColor ppTextSecondary]];

    self.statsStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.totalPill,
        self.livePill,
        self.reviewPill,
        self.archivedPill
    ]];
    self.statsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.statsStack.axis = UILayoutConstraintAxisHorizontal;
    self.statsStack.spacing = 10.0;
    self.statsStack.distribution = UIStackViewDistributionFillEqually;
    [self.view addSubview:self.statsStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.statsStack.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12],
        [self.statsStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statsStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16]
    ]];
}

- (void)setupControls {
    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[
        kLang(@"Service_Filter_All"),
        kLang(@"Service_Filter_Live"),
        kLang(@"Service_Filter_Archived")
    ]];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.selectedSegmentTintColor = AppPrimaryClr;
    [self.filterControl setTitleTextAttributes:@{
        NSFontAttributeName: [Styling fontMedium:13],
        NSForegroundColorAttributeName: SeconderyTextClr
    } forState:UIControlStateNormal];
    [self.filterControl setTitleTextAttributes:@{
        NSFontAttributeName: [Styling fontBold:13],
        NSForegroundColorAttributeName: UIColor.whiteColor
    } forState:UIControlStateSelected];
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];

    self.refineButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.refineButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.refineButton.backgroundColor = AppForgroundColr;
    self.refineButton.layer.cornerRadius = 18.0;
    self.refineButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.refineButton.titleLabel.font = [Styling fontBold:12];
    self.refineButton.tintColor = AppPrimaryClr;
    [self.refineButton setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] forState:UIControlStateNormal];
    self.refineButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    [self.refineButton addTarget:self action:@selector(showRefineSheet) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *controlsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.filterControl, self.refineButton]];
    controlsRow.translatesAutoresizingMaskIntoConstraints = NO;
    controlsRow.axis = UILayoutConstraintAxisHorizontal;
    controlsRow.spacing = 10.0;
    controlsRow.alignment = UIStackViewAlignmentFill;
    [self.view addSubview:controlsRow];

    [NSLayoutConstraint activateConstraints:@[
        [controlsRow.topAnchor constraintEqualToAnchor:self.statsStack.bottomAnchor constant:12],
        [controlsRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [controlsRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.refineButton.widthAnchor constraintEqualToConstant:128],
        [self.refineButton.heightAnchor constraintEqualToConstant:36],
        [self.filterControl.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)setupTableView {
    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 68)];
    headerContainer.backgroundColor = UIColor.clearColor;

    self.searchView = [[PPS alloc] initWithFrame:CGRectZero];
    self.searchView.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchView.delegate = self;
    self.searchView.cornerRadius = 24.0;
    self.searchView.blurEnabled = NO;
    self.searchView.shadowEnabled = NO;
    self.searchView.showsPrimaryButton = NO;
    self.searchView.strokeColor = [SeconderyTextClr colorWithAlphaComponent:0.14];
    self.searchView.backgroundColor = AppForgroundColr;
    self.searchView.textField.placeholder = kLang(@"Service_Search_Placeholder");
    [headerContainer addSubview:self.searchView];

    [NSLayoutConstraint activateConstraints:@[
        [self.searchView.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:10],
        [self.searchView.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:16],
        [self.searchView.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-16],
        [self.searchView.heightAnchor constraintEqualToConstant:48]
    ]];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = [PPServiceCell preferredHeight];
    self.tableView.estimatedRowHeight = [PPServiceCell preferredHeight];
    self.tableView.tableHeaderView = headerContainer;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 28, 0);
    [self.tableView registerClass:[PPServiceCell class] forCellReuseIdentifier:[PPServiceCell reuseID]];

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = AppPrimaryClr;
    [refresh addTarget:self action:@selector(refreshTriggered) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refresh;

    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.statsStack.bottomAnchor constant:58],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupPlaceholderView {
    self.placeholderView = [UIView new];
    self.placeholderView.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderView.hidden = YES;
    [self.view addSubview:self.placeholderView];

    self.placeholderIconView = [UIImageView new];
    self.placeholderIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderIconView.tintColor = [SeconderyTextClr colorWithAlphaComponent:0.34];
    self.placeholderIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.placeholderIconView.image = [UIImage systemImageNamed:@"sparkles.rectangle.stack.fill"];
    [self.placeholderView addSubview:self.placeholderIconView];

    self.placeholderTitleLabel = [UILabel new];
    self.placeholderTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderTitleLabel.font = [Styling fontBold:18];
    self.placeholderTitleLabel.textColor = PrimaryTextClr;
    self.placeholderTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.placeholderTitleLabel.numberOfLines = 0;
    [self.placeholderView addSubview:self.placeholderTitleLabel];

    self.placeholderSubtitleLabel = [UILabel new];
    self.placeholderSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderSubtitleLabel.font = [Styling fontMedium:14];
    self.placeholderSubtitleLabel.textColor = SeconderyTextClr;
    self.placeholderSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.placeholderSubtitleLabel.numberOfLines = 0;
    [self.placeholderView addSubview:self.placeholderSubtitleLabel];

    self.placeholderButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.placeholderButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderButton.tintColor = UIColor.whiteColor;
    self.placeholderButton.backgroundColor = AppPrimaryClr;
    self.placeholderButton.layer.cornerRadius = 22.0;
    self.placeholderButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.placeholderButton.titleLabel.font = [Styling fontBold:15];
    self.placeholderButton.contentEdgeInsets = UIEdgeInsetsMake(12, 22, 12, 22);
    [self.placeholderButton addTarget:self action:@selector(placeholderButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.placeholderView addSubview:self.placeholderButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.placeholderView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.placeholderView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:26],
        [self.placeholderView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:34],

        [self.placeholderIconView.topAnchor constraintEqualToAnchor:self.placeholderView.topAnchor],
        [self.placeholderIconView.centerXAnchor constraintEqualToAnchor:self.placeholderView.centerXAnchor],
        [self.placeholderIconView.widthAnchor constraintEqualToConstant:66],
        [self.placeholderIconView.heightAnchor constraintEqualToConstant:66],

        [self.placeholderTitleLabel.topAnchor constraintEqualToAnchor:self.placeholderIconView.bottomAnchor constant:18],
        [self.placeholderTitleLabel.leadingAnchor constraintEqualToAnchor:self.placeholderView.leadingAnchor],
        [self.placeholderTitleLabel.trailingAnchor constraintEqualToAnchor:self.placeholderView.trailingAnchor],

        [self.placeholderSubtitleLabel.topAnchor constraintEqualToAnchor:self.placeholderTitleLabel.bottomAnchor constant:10],
        [self.placeholderSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.placeholderView.leadingAnchor],
        [self.placeholderSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.placeholderView.trailingAnchor],

        [self.placeholderButton.topAnchor constraintEqualToAnchor:self.placeholderSubtitleLabel.bottomAnchor constant:20],
        [self.placeholderButton.centerXAnchor constraintEqualToAnchor:self.placeholderView.centerXAnchor],
        [self.placeholderButton.bottomAnchor constraintEqualToAnchor:self.placeholderView.bottomAnchor]
    ]];
}

- (void)setupLoadingView {
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.color = AppPrimaryClr;
    [self.view addSubview:self.loadingIndicator];

    self.loadingLabel = [UILabel new];
    self.loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingLabel.font = [Styling fontMedium:13];
    self.loadingLabel.textColor = SeconderyTextClr;
    self.loadingLabel.text = kLang(@"Service_Loading");
    [self.view addSubview:self.loadingLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-6],
        [self.loadingLabel.topAnchor constraintEqualToAnchor:self.loadingIndicator.bottomAnchor constant:10],
        [self.loadingLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
}

#pragma mark - Data

- (void)startListening {
    [self.listener remove];
    self.isLoading = YES;
    [self updateLoadingState];

    __weak typeof(self) weakSelf = self;
    self.listener = [[PPServiceManager sharedManager] observeAllServices:^(NSArray<PPServiceModel *> * _Nullable services, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        self.isLoading = NO;
        [self.tableView.refreshControl endRefreshing];
        [self updateLoadingState];

        if (error) {
            DLog(@"[ServicesList] listener error: %@", error.localizedDescription);
            if (self.allServices.count == 0) {
                [self showPlaceholderWithTitle:kLang(@"Service_Error_LoadTitle")
                                      subtitle:error.localizedDescription ?: kLang(@"Service_Error_Generic")
                                   buttonTitle:kLang(@"Retry")
                                          icon:@"exclamationmark.triangle.fill"];
                self.tableView.hidden = YES;
            } else {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            }
            return;
        }

        self.allServices = [services mutableCopy] ?: [NSMutableArray array];
        [self refreshStats];
        [self applyFilterAndReload];
    }];
}

- (void)refreshTriggered {
    __weak typeof(self) weakSelf = self;
    [[PPServiceManager sharedManager] fetchAllServicesWithCompletion:^(NSArray<PPServiceModel *> * _Nullable services, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        [self.tableView.refreshControl endRefreshing];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            return;
        }
        self.allServices = [services mutableCopy] ?: [NSMutableArray array];
        [self refreshStats];
        [self applyFilterAndReload];
    }];
}

- (void)refreshStats {
    NSInteger total = self.allServices.count;
    NSInteger live = 0;
    NSInteger review = 0;
    NSInteger archived = 0;

    for (PPServiceModel *service in self.allServices) {
        if (service.isDeleted) {
            archived += 1;
        }
        if (service.isLive) {
            live += 1;
        }
        if ([self servicePassesSecondaryFilter:service filter:PPServiceSecondaryFilterNeedsReview]) {
            review += 1;
        }
    }

    [self.totalPill updateValue:total];
    [self.livePill updateValue:live];
    [self.reviewPill updateValue:review];
    [self.archivedPill updateValue:archived];
}

- (void)applyFilterAndReload {
    NSMutableArray<PPServiceModel *> *result = [NSMutableArray array];
    NSString *query = [PPSafeString(self.searchQuery).lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    for (PPServiceModel *service in self.allServices) {
        if (self.primaryFilter == PPServicePrimaryFilterLive && !service.isLive) {
            continue;
        }
        if (self.primaryFilter == PPServicePrimaryFilterArchived && !service.isDeleted) {
            continue;
        }
        if (![self servicePassesSecondaryFilter:service filter:self.secondaryFilter]) {
            continue;
        }
        if (query.length > 0 && ![self service:service matchesSearchQuery:query]) {
            continue;
        }
        [result addObject:service];
    }

    [result sortUsingComparator:^NSComparisonResult(PPServiceModel *left, PPServiceModel *right) {
        return [self compareService:left to:right];
    }];

    self.filteredServices = result;
    [self.tableView reloadData];

    if (self.filteredServices.count == 0) {
        NSString *title = self.allServices.count == 0 ? kLang(@"Service_Empty_Title") : kLang(@"Service_Empty_Filtered_Title");
        NSString *subtitle = self.allServices.count == 0 ? kLang(@"Service_Empty_Subtitle") : kLang(@"Service_Empty_Filtered_Subtitle");
        [self showPlaceholderWithTitle:title
                              subtitle:subtitle
                           buttonTitle:(self.allServices.count == 0 ? kLang(@"Service_Add_Title") : kLang(@"Service_ClearFilters"))
                                  icon:@"sparkles.rectangle.stack.fill"];
        self.tableView.hidden = YES;
    } else {
        self.placeholderView.hidden = YES;
        self.tableView.hidden = NO;
        if (!self.didPlayEntrance) {
            self.didPlayEntrance = YES;
            [self playEntranceAnimation];
        }
    }
}

#pragma mark - Actions

- (void)addServiceTapped {
    [PPFunc pp_playTapEffect];
    PPAddEditServiceViewController *controller = [[PPAddEditServiceViewController alloc] initWithService:nil];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)viewServiceAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return;
    }
    [PPFunc pp_playTapEffect];
    PPServiceDetailViewController *controller = [[PPServiceDetailViewController alloc] initWithService:service];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)editServiceAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return;
    }
    [PPFunc pp_playTapEffect];
    PPAddEditServiceViewController *controller = [[PPAddEditServiceViewController alloc] initWithService:service];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)moderateServiceAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return;
    }
    [PPFunc pp_playTapEffect];
    PPServiceModerationViewController *controller = [[PPServiceModerationViewController alloc] initWithService:service];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)toggleDisabledAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return;
    }

    BOOL newState = !service.isDisabled;
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                              title:(newState ? kLang(@"Service_Confirm_Disable_Title") : kLang(@"Service_Confirm_Enable_Title"))
                           subtitle:(newState ? kLang(@"Service_Confirm_Disable_Subtitle") : kLang(@"Service_Confirm_Enable_Subtitle"))
                        placeholder:nil
                      confirmButton:(newState ? kLang(@"Service_Action_Disable") : kLang(@"Service_Action_Enable"))
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Service_Updating") subtitle:nil];
        [[PPServiceManager sharedManager] setDisabled:newState
                                         forServiceID:service.serviceID
                                            auditNote:nil
                                           completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Updated") subtitle:(newState ? kLang(@"Service_Disabled_Success") : kLang(@"Service_Enabled_Success"))];
            }
        }];
    } cancelBlock:nil];
}

- (void)toggleBlockedAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return;
    }

    BOOL newState = !service.isBlocked;
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                              title:(newState ? kLang(@"Service_Confirm_Block_Title") : kLang(@"Service_Confirm_Unblock_Title"))
                           subtitle:(newState ? kLang(@"Service_Confirm_Block_Subtitle") : kLang(@"Service_Confirm_Unblock_Subtitle"))
                        placeholder:nil
                      confirmButton:(newState ? kLang(@"Service_Action_Block") : kLang(@"Service_Action_Unblock"))
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Service_Updating") subtitle:nil];
        [[PPServiceManager sharedManager] setBlocked:newState
                                        forServiceID:service.serviceID
                                           auditNote:nil
                                          completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Updated") subtitle:(newState ? kLang(@"Service_Blocked_Success") : kLang(@"Service_Unblocked_Success"))];
            }
        }];
    } cancelBlock:nil];
}

- (void)toggleArchivedAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return;
    }

    BOOL shouldArchive = !service.isDeleted;
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                              title:(shouldArchive ? kLang(@"Service_Confirm_Archive_Title") : kLang(@"Service_Confirm_Restore_Title"))
                           subtitle:(shouldArchive ? kLang(@"Service_Confirm_Archive_Subtitle") : kLang(@"Service_Confirm_Restore_Subtitle"))
                        placeholder:nil
                      confirmButton:(shouldArchive ? kLang(@"Service_Action_Archive") : kLang(@"Service_Action_Restore"))
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Service_Updating") subtitle:nil];
        PPServiceVoidBlock done = ^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Updated") subtitle:(shouldArchive ? kLang(@"Service_Archived_Success") : kLang(@"Service_Restored_Success"))];
            }
        };
        if (shouldArchive) {
            [[PPServiceManager sharedManager] archiveServiceID:service.serviceID auditNote:nil completion:done];
        } else {
            [[PPServiceManager sharedManager] restoreServiceID:service.serviceID auditNote:nil completion:done];
        }
    } cancelBlock:nil];
}

- (void)deletePermanentlyAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                              title:kLang(@"Service_Confirm_Delete_Title")
                           subtitle:kLang(@"Service_Confirm_Delete_Subtitle")
                        placeholder:nil
                      confirmButton:kLang(@"Delete")
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Deleting") subtitle:nil];
        [[PPServiceManager sharedManager] deleteServicePermanently:service.serviceID
                                                         auditNote:nil
                                                        completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Service_Deleted_Success")];
            }
        }];
    } cancelBlock:nil];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    self.primaryFilter = (PPServicePrimaryFilter)sender.selectedSegmentIndex;
    [self applyFilterAndReload];
}

- (void)showRefineSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Service_Refine_Title")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Service_Refine_Sort")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf showSortSheet];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Service_Refine_Filter")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf showSecondaryFilterSheet];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Service_ClearFilters")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        weakSelf.secondaryFilter = PPServiceSecondaryFilterAny;
        weakSelf.sortOption = PPServiceSortOptionUpdatedDesc;
        weakSelf.searchQuery = @"";
        weakSelf.searchView.textField.text = @"";
        [weakSelf updateRefineButtonTitle];
        [weakSelf applyFilterAndReload];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self pp_presentActionSheet:sheet sourceView:self.refineButton];
}

- (void)showSortSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Service_Refine_Sort")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary *> *options = @[
        @{@"title": kLang(@"Service_Sort_Updated"), @"value": @(PPServiceSortOptionUpdatedDesc)},
        @{@"title": kLang(@"Service_Sort_Title"), @"value": @(PPServiceSortOptionTitleAsc)},
        @{@"title": kLang(@"Service_Sort_PriceHigh"), @"value": @(PPServiceSortOptionPriceHighToLow)},
        @{@"title": kLang(@"Service_Sort_PriceLow"), @"value": @(PPServiceSortOptionPriceLowToHigh)},
        @{@"title": kLang(@"Service_Sort_Available"), @"value": @(PPServiceSortOptionAvailableSoonest)}
    ];

    __weak typeof(self) weakSelf = self;
    for (NSDictionary *option in options) {
        [sheet addAction:[UIAlertAction actionWithTitle:option[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            weakSelf.sortOption = [option[@"value"] integerValue];
            [weakSelf updateRefineButtonTitle];
            [weakSelf applyFilterAndReload];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self pp_presentActionSheet:sheet sourceView:self.refineButton];
}

- (void)showSecondaryFilterSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Service_Refine_Filter")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSDictionary *> *options = @[
        @{@"title": kLang(@"Service_Filter_Any"), @"value": @(PPServiceSecondaryFilterAny)},
        @{@"title": kLang(@"Service_Filter_NeedsReview"), @"value": @(PPServiceSecondaryFilterNeedsReview)},
        @{@"title": kLang(@"Service_Filter_Verified"), @"value": @(PPServiceSecondaryFilterVerified)},
        @{@"title": kLang(@"Service_Filter_Pending"), @"value": @(PPServiceSecondaryFilterPending)},
        @{@"title": kLang(@"Service_Filter_Blocked"), @"value": @(PPServiceSecondaryFilterBlocked)},
        @{@"title": kLang(@"Service_Filter_Disabled"), @"value": @(PPServiceSecondaryFilterDisabled)}
    ];

    __weak typeof(self) weakSelf = self;
    for (NSDictionary *option in options) {
        [sheet addAction:[UIAlertAction actionWithTitle:option[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            weakSelf.secondaryFilter = [option[@"value"] integerValue];
            [weakSelf updateRefineButtonTitle];
            [weakSelf applyFilterAndReload];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self pp_presentActionSheet:sheet sourceView:self.refineButton];
}

- (void)placeholderButtonTapped {
    if (!self.isLoading && self.allServices.count == 0) {
        if (self.placeholderButton.currentTitle.length > 0 &&
            [self.placeholderButton.currentTitle isEqualToString:kLang(@"Retry")]) {
            [self startListening];
            return;
        }
        [self addServiceTapped];
        return;
    }

    self.secondaryFilter = PPServiceSecondaryFilterAny;
    self.primaryFilter = PPServicePrimaryFilterAll;
    self.filterControl.selectedSegmentIndex = 0;
    self.searchQuery = @"";
    self.searchView.textField.text = @"";
    [self updateRefineButtonTitle];
    [self applyFilterAndReload];
}

#pragma mark - Helpers

- (PPServiceModel *)serviceAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.filteredServices.count) {
        return nil;
    }
    return self.filteredServices[indexPath.row];
}

- (BOOL)service:(PPServiceModel *)service matchesSearchQuery:(NSString *)query {
    NSArray<NSString *> *haystack = @[
        PPSafeString(service.title).lowercaseString,
        PPSafeString(service.serviceDescriptionText).lowercaseString,
        PPSafeString(service.category).lowercaseString,
        PPSafeString(service.categoryID).lowercaseString,
        PPSafeString(service.serviceOwnerID).lowercaseString,
        PPSafeString(service.serviceID).lowercaseString,
        PPSafeString(service.verificationStatus).lowercaseString,
        PPSafeString(service.subscriptionPlan).lowercaseString,
        PPSafeString(service.subscriptionStatus).lowercaseString
    ];

    for (NSString *value in haystack) {
        if ([value containsString:query]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)servicePassesSecondaryFilter:(PPServiceModel *)service filter:(PPServiceSecondaryFilter)filter {
    NSString *verification = [[PPSafeString(service.verificationStatus) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    switch (filter) {
        case PPServiceSecondaryFilterAny:
            return YES;
        case PPServiceSecondaryFilterNeedsReview:
            return service.isBlocked ||
                   service.isDisabled ||
                   [verification isEqualToString:@"pending"] ||
                   [verification isEqualToString:@"pending_review"] ||
                   [verification isEqualToString:@"verification_pending"] ||
                   [verification isEqualToString:@"rejected"];
        case PPServiceSecondaryFilterVerified:
            return [verification isEqualToString:@"verified"];
        case PPServiceSecondaryFilterPending:
            return [verification isEqualToString:@"pending"] ||
                   [verification isEqualToString:@"pending_review"] ||
                   [verification isEqualToString:@"verification_pending"];
        case PPServiceSecondaryFilterBlocked:
            return service.isBlocked;
        case PPServiceSecondaryFilterDisabled:
            return service.isDisabled;
    }
    return YES;
}

- (NSComparisonResult)compareService:(PPServiceModel *)left to:(PPServiceModel *)right {
    switch (self.sortOption) {
        case PPServiceSortOptionTitleAsc:
            return [left.title localizedCaseInsensitiveCompare:right.title ?: @""];
        case PPServiceSortOptionPriceHighToLow:
            return left.price > right.price ? NSOrderedAscending : (left.price < right.price ? NSOrderedDescending : NSOrderedSame);
        case PPServiceSortOptionPriceLowToHigh:
            return left.price < right.price ? NSOrderedAscending : (left.price > right.price ? NSOrderedDescending : NSOrderedSame);
        case PPServiceSortOptionAvailableSoonest: {
            NSDate *l = left.availableDate ?: [NSDate distantFuture];
            NSDate *r = right.availableDate ?: [NSDate distantFuture];
            return [l compare:r];
        }
        case PPServiceSortOptionUpdatedDesc:
        default: {
            NSDate *l = left.updatedAt ?: left.timestamp ?: [NSDate distantPast];
            NSDate *r = right.updatedAt ?: right.timestamp ?: [NSDate distantPast];
            return [r compare:l];
        }
    }
}

- (void)updateRefineButtonTitle {
    NSString *title = [NSString stringWithFormat:@" %@", [self sortLabelForCurrentSelection]];
    [self.refineButton setTitle:title forState:UIControlStateNormal];
}

- (NSString *)sortLabelForCurrentSelection {
    switch (self.sortOption) {
        case PPServiceSortOptionTitleAsc:
            return kLang(@"Service_Sort_Title");
        case PPServiceSortOptionPriceHighToLow:
            return kLang(@"Service_Sort_PriceHigh");
        case PPServiceSortOptionPriceLowToHigh:
            return kLang(@"Service_Sort_PriceLow");
        case PPServiceSortOptionAvailableSoonest:
            return kLang(@"Service_Sort_Available");
        case PPServiceSortOptionUpdatedDesc:
        default:
            return kLang(@"Service_Sort_Updated");
    }
}

- (void)showPlaceholderWithTitle:(NSString *)title subtitle:(NSString *)subtitle buttonTitle:(NSString *)buttonTitle icon:(NSString *)iconName {
    self.placeholderView.hidden = NO;
    self.placeholderIconView.image = [UIImage systemImageNamed:iconName];
    self.placeholderTitleLabel.text = title;
    self.placeholderSubtitleLabel.text = subtitle;
    [self.placeholderButton setTitle:buttonTitle forState:UIControlStateNormal];
}

- (void)pp_presentActionSheet:(UIAlertController *)sheet sourceView:(UIView *)sourceView {
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: self.view;
        popover.sourceRect = sourceView ? sourceView.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)updateLoadingState {
    self.loadingIndicator.hidden = !self.isLoading;
    self.loadingLabel.hidden = !self.isLoading;
    if (self.isLoading) {
        [self.loadingIndicator startAnimating];
    } else {
        [self.loadingIndicator stopAnimating];
    }
}

- (void)playEntranceAnimation {
    NSArray<UITableViewCell *> *cells = self.tableView.visibleCells;
    [cells enumerateObjectsUsingBlock:^(UITableViewCell * _Nonnull cell, NSUInteger idx, BOOL * _Nonnull stop) {
        cell.alpha = 0.0;
        cell.transform = CGAffineTransformMakeTranslation(0, 26);
        [UIView animateWithDuration:0.44
                              delay:0.04 * idx
             usingSpringWithDamping:0.88
              initialSpringVelocity:0.42
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

#pragma mark - PPSDelegate

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.searchQuery = text ?: @"";
    [self applyFilterAndReload];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredServices.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPServiceCell *cell = [tableView dequeueReusableCellWithIdentifier:[PPServiceCell reuseID] forIndexPath:indexPath];
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (service) {
        [cell configureWithService:service];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self viewServiceAtIndexPath:indexPath];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                    point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];
    if (!service) {
        return nil;
    }

    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        UIAction *viewAction = [UIAction actionWithTitle:kLang(@"Service_Action_View")
                                                   image:[UIImage systemImageNamed:@"eye"]
                                              identifier:nil
                                                 handler:^(__unused UIAction * _Nonnull action) {
            [weakSelf viewServiceAtIndexPath:indexPath];
        }];

        UIAction *editAction = [UIAction actionWithTitle:kLang(@"Service_Action_Edit")
                                                   image:[UIImage systemImageNamed:@"pencil"]
                                              identifier:nil
                                                 handler:^(__unused UIAction * _Nonnull action) {
            [weakSelf editServiceAtIndexPath:indexPath];
        }];

        UIAction *adminAction = [UIAction actionWithTitle:kLang(@"Service_Action_Moderate")
                                                    image:[UIImage systemImageNamed:@"slider.horizontal.3"]
                                               identifier:nil
                                                  handler:^(__unused UIAction * _Nonnull action) {
            [weakSelf moderateServiceAtIndexPath:indexPath];
        }];

        UIAction *disableAction = [UIAction actionWithTitle:(service.isDisabled ? kLang(@"Service_Action_Enable") : kLang(@"Service_Action_Disable"))
                                                      image:[UIImage systemImageNamed:(service.isDisabled ? @"checkmark.circle" : @"nosign")]
                                                 identifier:nil
                                                    handler:^(__unused UIAction * _Nonnull action) {
            [weakSelf toggleDisabledAtIndexPath:indexPath];
        }];

        UIAction *blockAction = [UIAction actionWithTitle:(service.isBlocked ? kLang(@"Service_Action_Unblock") : kLang(@"Service_Action_Block"))
                                                    image:[UIImage systemImageNamed:(service.isBlocked ? @"lock.open" : @"hand.raised.fill")]
                                               identifier:nil
                                                  handler:^(__unused UIAction * _Nonnull action) {
            [weakSelf toggleBlockedAtIndexPath:indexPath];
        }];

        UIAction *archiveAction = [UIAction actionWithTitle:(service.isDeleted ? kLang(@"Service_Action_Restore") : kLang(@"Service_Action_Archive"))
                                                      image:[UIImage systemImageNamed:(service.isDeleted ? @"arrow.uturn.backward.circle" : @"archivebox")]
                                                 identifier:nil
                                                    handler:^(__unused UIAction * _Nonnull action) {
            [weakSelf toggleArchivedAtIndexPath:indexPath];
        }];

        UIAction *deleteAction = [UIAction actionWithTitle:kLang(@"Delete")
                                                     image:[UIImage systemImageNamed:@"trash"]
                                                identifier:nil
                                                   handler:^(__unused UIAction * _Nonnull action) {
            [weakSelf deletePermanentlyAtIndexPath:indexPath];
        }];
        deleteAction.attributes = UIMenuElementAttributesDestructive;

        return [UIMenu menuWithTitle:service.title ?: @""
                            children:@[
            [UIMenu menuWithTitle:@""
                            image:nil
                       identifier:nil
                          options:UIMenuOptionsDisplayInline
                         children:@[viewAction, editAction, adminAction]],
            [UIMenu menuWithTitle:@""
                            image:nil
                       identifier:nil
                          options:UIMenuOptionsDisplayInline
                         children:@[disableAction, blockAction, archiveAction]],
            [UIMenu menuWithTitle:@""
                            image:nil
                       identifier:nil
                          options:UIMenuOptionsDisplayInline
                         children:@[deleteAction]]
        ]];
    }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];

    UIContextualAction *editAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull handler)(BOOL)) {
        [weakSelf editServiceAtIndexPath:indexPath];
        handler(YES);
    }];
    editAction.backgroundColor = [UIColor ppInfo];
    editAction.image = [UIImage systemImageNamed:@"pencil.circle.fill"];

    UIContextualAction *moderateAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull handler)(BOOL)) {
        [weakSelf moderateServiceAtIndexPath:indexPath];
        handler(YES);
    }];
    moderateAction.backgroundColor = AppPrimaryClr;
    moderateAction.image = [UIImage systemImageNamed:@"slider.horizontal.3"];

    UIContextualAction *blockAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull handler)(BOOL)) {
        [weakSelf toggleBlockedAtIndexPath:indexPath];
        handler(YES);
    }];
    blockAction.backgroundColor = service.isBlocked ? [UIColor ppSuccess] : [UIColor ppWarning];
    blockAction.image = [UIImage systemImageNamed:(service.isBlocked ? @"lock.open.fill" : @"hand.raised.fill")];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[blockAction, moderateAction, editAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;
    PPServiceModel *service = [self serviceAtIndexPath:indexPath];

    UIContextualAction *archiveAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull handler)(BOOL)) {
        [weakSelf toggleArchivedAtIndexPath:indexPath];
        handler(YES);
    }];
    archiveAction.backgroundColor = service.isDeleted ? [UIColor ppSuccess] : [UIColor ppError];
    archiveAction.image = [UIImage systemImageNamed:(service.isDeleted ? @"arrow.uturn.backward.circle.fill" : @"archivebox.circle.fill")];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[archiveAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.didPlayEntrance) {
        cell.alpha = 0.0;
        [UIView animateWithDuration:0.24 animations:^{
            cell.alpha = 1.0;
        }];
    }
}

@end
