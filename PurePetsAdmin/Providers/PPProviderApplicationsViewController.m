#import "PPProviderApplicationsViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

static NSString * const PPProviderApplicationCellID = @"PPProviderApplicationCell";

static NSString *PPProviderApplicationSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *PPProviderApplicationDisplayName(PPProviderApplication *application) {
    NSDictionary *form = [application.form isKindOfClass:NSDictionary.class] ? application.form : @{};
    for (NSString *key in @[@"fullName", @"businessName", @"companyName", @"legalName"]) {
        NSString *name = PPProviderApplicationSafeString(form[key]);
        if (name.length) return name;
    }
    if (application.userId.length) return application.userId;
    return kLang(@"Providers_Applications_UnknownApplicant");
}

@interface PPProviderApplicationsViewController ()
@property (nonatomic, strong) NSArray<PPProviderApplication *> *applications;
@property (nonatomic, copy) NSString *statusFilter;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) PPProviderContextHeaderView *contextHeader;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPProviderStateView *stateView;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedApplicationIDs;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL isReviewing;
@property (nonatomic, assign) BOOL canManage;
@end

@implementation PPProviderApplicationsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.applications = @[];
    self.statusFilter = @"all";
    self.animatedApplicationIDs = [NSMutableSet set];
    [self pp_evaluatePermissions];
    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_buildHeader];
    [self loadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_fitTableHeader];
}

#pragma mark - Setup

- (void)pp_evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    BOOL canView = [staff hasPermission:kStaffPermProvidersView];
    self.canManage = [staff hasPermission:kStaffPermProvidersManage];
    if (!canView && !self.canManage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
    }
}

- (void)pp_configureNavigation {
    self.title = kLang(@"Providers_Applications_Title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(loadData)];
    refresh.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = refresh;
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPProviderCanvasColor();
    self.tableView.backgroundColor = PPProviderCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 132.0;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, PPSpaceXXL, 0.0);
    [self.tableView registerClass:PPProviderRecordCell.class forCellReuseIdentifier:PPProviderApplicationCellID];
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 0.0;

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
    container.backgroundColor = UIColor.clearColor;
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.contextHeader = [[PPProviderContextHeaderView alloc] initWithTitle:kLang(@"Providers_Applications_HeroTitle")
                                                                   subtitle:kLang(@"Providers_Applications_HeroSubtitle")
                                                                     symbol:@"person.crop.circle.badge.checkmark"];
    self.contextHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.contextHeader];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[
        kLang(@"Providers_All"), kLang(@"Providers_Pending"),
        kLang(@"Providers_Approved"), kLang(@"Providers_Rejected")
    ]];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterControl.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.selectedSegmentTintColor = PPProviderBrandColor();
    [self.filterControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}
                                       forState:UIControlStateSelected];
    [self.filterControl addTarget:self action:@selector(pp_filterChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.filterControl];

    [NSLayoutConstraint activateConstraints:@[
        [self.contextHeader.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.contextHeader.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.contextHeader.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.filterControl.topAnchor constraintEqualToAnchor:self.contextHeader.bottomAnchor constant:PPSpaceSM],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],
        [self.filterControl.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
        [self.filterControl.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceSM],
    ]];
    self.headerContainer = container;
    self.tableView.tableHeaderView = container;
    [self pp_refreshHeaderMetric];
}

- (void)pp_fitTableHeader {
    UIView *header = self.headerContainer;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (!header || width <= 0.0) return;
    header.frame = CGRectMake(0.0, 0.0, width, MAX(header.frame.size.height, 1.0));
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat height = ceil(size.height);
    if (fabs(CGRectGetHeight(header.frame) - height) > 0.5) {
        header.frame = CGRectMake(0.0, 0.0, width, height);
        self.tableView.tableHeaderView = header;
    }
}

#pragma mark - Data and State

- (void)loadData {
    if (self.isLoading || self.isReviewing) return;
    self.isLoading = YES;
    self.currentError = nil;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self pp_updateState];

    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchApplicationsWithCompletion:^(NSArray<PPProviderApplication *> *apps, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            [self.refreshControl endRefreshing];
            self.currentError = error;
            if (!error) self.applications = apps ?: @[];
            [self pp_refreshHeaderMetric];
            [self pp_updateState];
            [self.tableView reloadData];
            if (error && self.applications.count > 0) {
                [AlertHelper showAlertIn:self title:kLang(@"Providers_Applications_LoadFailed") subtitle:kLang(@"Providers_Applications_ErrorSubtitle")];
            }
        });
    }];
}

- (NSArray<PPProviderApplication *> *)pp_filteredApplications {
    NSArray<PPProviderApplication *> *source = self.applications ?: @[];
    if ([self.statusFilter isEqualToString:@"all"]) return source;
    return [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PPProviderApplication *application, NSDictionary *bindings) {
        (void)bindings;
        NSString *status = PPProviderApplicationSafeString(application.status).lowercaseString;
        if ([self.statusFilter isEqualToString:@"pending"]) {
            return status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"];
        }
        return [status isEqualToString:self.statusFilter];
    }]];
}

- (void)pp_refreshHeaderMetric {
    NSUInteger reviewQueue = 0;
    for (PPProviderApplication *application in self.applications) {
        NSString *status = PPProviderApplicationSafeString(application.status).lowercaseString;
        if (status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"]) reviewQueue++;
    }
    NSString *format = kLang(@"Providers_Applications_Summary_Format");
    [self.contextHeader setMetricText:[NSString stringWithFormat:format,
                                      (unsigned long)self.pp_filteredApplications.count,
                                      (unsigned long)reviewQueue]];
}

- (void)pp_updateState {
    BOOL hasRows = self.pp_filteredApplications.count > 0;
    self.stateView.hidden = hasRows;
    if (hasRows) return;
    if (self.isLoading) {
        [self.stateView showLoadingWithTitle:kLang(@"Providers_Applications_Loading") subtitle:kLang(@"Providers_Applications_Subtitle")];
    } else if (self.currentError) {
        [self.stateView showErrorWithTitle:kLang(@"Providers_Applications_LoadFailed") subtitle:kLang(@"Providers_Applications_ErrorSubtitle")];
    } else {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Applications_Empty")
                                  subtitle:kLang(@"Providers_Applications_EmptySubtitle")
                                    symbol:@"person.crop.circle.badge.plus"];
    }
}

- (void)pp_filterChanged:(UISegmentedControl *)sender {
    NSArray<NSString *> *filters = @[@"all", @"pending", @"approved", @"rejected"];
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)filters.count) return;
    self.statusFilter = filters[(NSUInteger)sender.selectedSegmentIndex];
    [self pp_refreshHeaderMetric];
    [self pp_updateState];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self.tableView reloadData];
    } else {
        [UIView transitionWithView:self.tableView duration:PPAnimDurationNormal
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ [self.tableView reloadData]; } completion:nil];
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.pp_filteredApplications.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPProviderRecordCell *cell = [tableView dequeueReusableCellWithIdentifier:PPProviderApplicationCellID forIndexPath:indexPath];
    PPProviderApplication *application = self.pp_filteredApplications[(NSUInteger)indexPath.row];
    NSString *status = PPProviderApplicationSafeString(application.status).lowercaseString;
    BOOL transitionable = self.canManage && (status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"]);
    NSString *reference = application.applicationID.length ? application.applicationID : application.userId;
    [cell configureWithTitle:PPProviderApplicationDisplayName(application)
                    subtitle:PPProviderLocalizedType(application.providerType)
                      detail:[NSString stringWithFormat:@"%@ · %@", PPProviderDateText(application.createdAt), reference ?: @""]
                      status:status
                      symbol:@"person.crop.circle.badge.checkmark"
                  actionable:transitionable];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    PPProviderApplication *application = self.pp_filteredApplications[(NSUInteger)indexPath.row];
    NSString *identifier = application.applicationID.length ? application.applicationID : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedApplicationIDs containsObject:identifier]) return;
    [self.animatedApplicationIDs addObject:identifier];
    cell.contentView.alpha = 0.0;
    cell.contentView.transform = CGAffineTransformMakeTranslation(0.0, PPSpaceMD);
    [UIView animateWithDuration:PPAnimDurationNormal delay:MIN(indexPath.row, 6) * 0.025
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.contentView.alpha = 1.0;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<PPProviderApplication *> *applications = self.pp_filteredApplications;
    if (indexPath.row >= (NSInteger)applications.count || !self.canManage || self.isReviewing) return;
    PPProviderApplication *application = applications[(NSUInteger)indexPath.row];
    NSString *status = PPProviderApplicationSafeString(application.status).lowercaseString;
    BOOL transitionable = status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"];
    if (!transitionable) return;

    UIAlertController *actions = [UIAlertController alertControllerWithTitle:PPProviderApplicationDisplayName(application)
                                                                      message:[NSString stringWithFormat:@"%@\n%@", PPProviderLocalizedType(application.providerType), PPProviderLocalizedStatus(status)]
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
    if (status.length == 0 || [status isEqualToString:@"pending"]) {
        [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_MarkUnderReview") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self pp_requestReviewForApplication:application decision:@"under_review"];
        }]];
    }
    [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Approve") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self pp_requestReviewForApplication:application decision:@"approved"];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Reject") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self pp_requestReviewForApplication:application decision:@"rejected"];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = actions.popoverPresentationController;
    if (popover) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        popover.sourceView = cell ?: self.view;
        popover.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:actions animated:YES completion:nil];
}

#pragma mark - Review

- (void)pp_requestReviewForApplication:(PPProviderApplication *)application decision:(NSString *)decision {
    UIAlertController *notes = [UIAlertController alertControllerWithTitle:kLang(@"Providers_ReviewNotes")
                                                                   message:kLang(@"Providers_ReviewNotes_Context")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [notes addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = kLang(@"Providers_ReviewNotesPlaceholder");
        textField.textAlignment = Language.alignmentForCurrentLanguage;
        textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        textField.accessibilityLabel = kLang(@"Providers_ReviewNotes");
    }];
    [notes addAction:[UIAlertAction actionWithTitle:kLang(@"Confirm") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self pp_submitReviewForApplication:application decision:decision notes:notes.textFields.firstObject.text];
    }]];
    [notes addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:notes animated:YES completion:nil];
}

- (void)pp_submitReviewForApplication:(PPProviderApplication *)application decision:(NSString *)decision notes:(NSString *)notes {
    if (self.isReviewing) return;
    self.isReviewing = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] reviewApplication:application.applicationID status:decision notes:notes completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isReviewing = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            if (error) {
                [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            [PPFunc pp_playSuccessEffect];
            [self loadData];
        });
    }];
}

@end