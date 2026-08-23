#import "PPProviderFeatureAccessViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "PPAlertHelper.h"

static NSString * const PPProviderFeatureCellID = @"PPProviderFeatureCell";

@interface PPProviderFeatureAccessViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *features;
@property (nonatomic, strong) PPProviderContextHeaderView *contextHeader;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPProviderStateView *stateView;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPProviderFeatureAccessViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.features = @[];
    [self pp_evaluatePermissions];
    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_buildHeader];
    [self loadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = PPProviderCanvasColor();
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: PPProviderPrimaryTextColor()};
        appearance.largeTitleTextAttributes = @{NSForegroundColorAttributeName: PPProviderPrimaryTextColor()};
        appearance.shadowColor = PPProviderSeparatorColor();
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
    }
    self.navigationController.navigationBar.tintColor = PPProviderBrandColor();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_fitTableHeader];
}

#pragma mark - Setup

- (void)pp_evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasAnyPermission:@[kStaffPermProvidersView, kStaffPermProvidersManage]]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.navigationController popViewControllerAnimated:YES]; });
    }
}

- (void)pp_configureNavigation {
    self.title = kLang(@"Providers_Features_Title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(loadData)];
    refresh.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = refresh;
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPProviderCanvasColor();
    self.tableView.backgroundColor = PPProviderCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 136.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, PPSpaceXXL, 0.0);
    [self.tableView registerClass:PPProviderRecordCell.class forCellReuseIdentifier:PPProviderFeatureCellID];

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = PPProviderBrandColor();
    [refresh addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.stateView = [PPProviderStateView new];
    __weak typeof(self) weakSelf = self;
    self.stateView.retryHandler = ^{ [weakSelf loadData]; };
    self.tableView.backgroundView = self.stateView;
}

- (void)pp_buildHeader {
    UIView *container = [UIView new];
    self.contextHeader = [[PPProviderContextHeaderView alloc] initWithTitle:kLang(@"Providers_Features_HeroTitle")
                                                                   subtitle:kLang(@"Providers_Features_HeroSubtitle")
                                                                     symbol:@"checkmark.shield.fill"];
    self.contextHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.contextHeader];
    [NSLayoutConstraint activateConstraints:@[
        [self.contextHeader.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.contextHeader.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.contextHeader.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.contextHeader.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    self.headerContainer = container;
    self.tableView.tableHeaderView = container;
    [self pp_refreshHeaderMetric];
}

- (void)pp_fitTableHeader {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (!self.headerContainer || width <= 0.0) return;
    self.headerContainer.frame = CGRectMake(0.0, 0.0, width, MAX(self.headerContainer.frame.size.height, 1.0));
    CGSize size = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.headerContainer.frame.size.height - ceil(size.height)) > 0.5) {
        self.headerContainer.frame = CGRectMake(0.0, 0.0, width, ceil(size.height));
        self.tableView.tableHeaderView = self.headerContainer;
    }
}

#pragma mark - Data and State

- (void)loadData {
    if (self.isLoading) return;
    self.isLoading = YES;
    self.currentError = nil;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self pp_updateState];

    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchPlansWithCompletion:^(NSArray<PPProviderPlan *> *plans, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            [self.refreshControl endRefreshing];
            self.currentError = error;
            if (!error) self.features = [self pp_flattenFeaturesFromPlans:plans];
            [self pp_refreshHeaderMetric];
            [self pp_updateState];
            [self.tableView reloadData];
            if (error && self.features.count > 0) {
                [PPAlertHelper showAlertIn:self title:kLang(@"Providers_Features_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
            }
        });
    }];
}

- (NSArray<NSDictionary *> *)pp_flattenFeaturesFromPlans:(NSArray<PPProviderPlan *> *)plans {
    NSMutableArray<NSDictionary *> *features = [NSMutableArray array];
    for (PPProviderPlan *plan in plans) {
        for (NSDictionary *document in plan.featureDocuments) {
            NSMutableDictionary *feature = [document mutableCopy];
            feature[@"planID"] = plan.planID ?: @"";
            feature[@"planName"] = plan.name ?: @{};
            feature[@"providerType"] = plan.providerType ?: @"";
            feature[@"planStatus"] = plan.status ?: @"inactive";
            [features addObject:feature.copy];
        }
    }
    return features.copy;
}

- (void)pp_refreshHeaderMetric {
    NSUInteger enabled = 0;
    NSMutableSet<NSString *> *types = [NSMutableSet set];
    for (NSDictionary *feature in self.features) {
        if (![feature[@"enabled"] isKindOfClass:NSNumber.class] || [feature[@"enabled"] boolValue]) enabled++;
        NSString *type = PPSafeString(feature[@"providerType"]);
        if (type.length) [types addObject:type];
    }
    [self.contextHeader setMetricText:[NSString stringWithFormat:kLang(@"Providers_Features_Summary_Format"),
                                      (unsigned long)self.features.count,
                                      (unsigned long)enabled,
                                      (unsigned long)types.count]];
}

- (void)pp_updateState {
    self.stateView.hidden = self.features.count > 0;
    if (self.features.count > 0) return;
    if (self.isLoading) {
        [self.stateView showLoadingWithTitle:kLang(@"Providers_Features_Loading") subtitle:kLang(@"Providers_Features_Subtitle")];
    } else if (self.currentError) {
        [self.stateView showErrorWithTitle:kLang(@"Providers_Features_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
    } else {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Features_Empty") subtitle:kLang(@"Providers_Features_Empty_Subtitle") symbol:@"checkmark.shield"];
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.features.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPProviderRecordCell *cell = [tableView dequeueReusableCellWithIdentifier:PPProviderFeatureCellID forIndexPath:indexPath];
    NSDictionary *feature = self.features[(NSUInteger)indexPath.row];
    NSString *fallback = PPSafeString(feature[@"featureKey"]);
    NSString *title = PPProviderLocalizedText(PPSafeDict(feature[@"title"]), fallback);
    NSString *planName = PPProviderLocalizedText(PPSafeDict(feature[@"planName"]), PPSafeString(feature[@"planID"]));
    NSString *provider = PPProviderLocalizedType(PPSafeString(feature[@"providerType"]));
    NSString *limit = PPSafeString(feature[@"limitValue"]);
    NSString *detail = limit.length
        ? [NSString stringWithFormat:kLang(@"Providers_Features_Detail_WithLimit_Format"), planName, limit]
        : [NSString stringWithFormat:kLang(@"Providers_Features_Detail_Format"), planName];
    BOOL enabled = ![feature[@"enabled"] isKindOfClass:NSNumber.class] || [feature[@"enabled"] boolValue];
    [cell configureWithTitle:title subtitle:provider detail:detail
                      status:(enabled ? @"active" : @"inactive")
                      symbol:@"checkmark.shield.fill" actionable:NO];
    return cell;
}

@end
