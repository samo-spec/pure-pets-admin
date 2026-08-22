#import "PPProviderPlansViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "PPAlertHelper.h"

static NSString * const PPProviderPlanCellID = @"PPProviderPlanCell";

@interface PPProviderPlansViewController ()
@property (nonatomic, strong) NSArray<PPProviderPlan *> *plans;
@property (nonatomic, strong) PPProviderContextHeaderView *contextHeader;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPProviderStateView *stateView;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL isMutating;
@property (nonatomic, assign) BOOL canManage;
@end

@implementation PPProviderPlansViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.plans = @[];
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
        dispatch_async(dispatch_get_main_queue(), ^{ [self.navigationController popViewControllerAnimated:YES]; });
    }
}

- (void)pp_configureNavigation {
    self.title = kLang(@"Providers_Plans_Title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    if (self.canManage) {
        UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                            target:self
                                                                            action:@selector(pp_chooseProviderTypeForNewPlan)];
        add.accessibilityLabel = kLang(@"Providers_Plans_New");
        self.navigationItem.rightBarButtonItem = add;
        PPCommandCenterNavigationItemsDidChange(self);
    }
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPProviderCanvasColor();
    self.tableView.backgroundColor = PPProviderCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 132.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, PPSpaceXXL, 0.0);
    [self.tableView registerClass:PPProviderRecordCell.class forCellReuseIdentifier:PPProviderPlanCellID];

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
    self.contextHeader = [[PPProviderContextHeaderView alloc] initWithTitle:kLang(@"Providers_Plans_HeroTitle")
                                                                   subtitle:kLang(@"Providers_Plans_HeroSubtitle")
                                                                     symbol:@"list.clipboard.fill"];
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
    if (self.isLoading || self.isMutating) return;
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
            if (!error) self.plans = plans ?: @[];
            [self pp_refreshHeaderMetric];
            [self pp_updateState];
            [self.tableView reloadData];
            if (error && self.plans.count > 0) {
                [AlertHelper showAlertIn:self title:kLang(@"Providers_Plans_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
            }
        });
    }];
}

- (void)pp_refreshHeaderMetric {
    NSUInteger active = 0;
    NSUInteger features = 0;
    for (PPProviderPlan *plan in self.plans) {
        if ([plan.status.lowercaseString isEqualToString:@"active"]) active++;
        features += MAX(plan.featureCount, 0);
    }
    [self.contextHeader setMetricText:[NSString stringWithFormat:kLang(@"Providers_Plans_Summary_Format"),
                                      (unsigned long)self.plans.count,
                                      (unsigned long)active,
                                      (unsigned long)features]];
}

- (void)pp_updateState {
    self.stateView.hidden = self.plans.count > 0;
    if (self.plans.count > 0) return;
    if (self.isLoading) {
        [self.stateView showLoadingWithTitle:kLang(@"Providers_Plans_Loading") subtitle:kLang(@"Providers_Plans_Subtitle")];
    } else if (self.currentError) {
        [self.stateView showErrorWithTitle:kLang(@"Providers_Plans_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
    } else {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Plans_Empty") subtitle:kLang(@"Providers_Plans_Empty_Subtitle") symbol:@"rectangle.stack.badge.plus"];
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.plans.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPProviderRecordCell *cell = [tableView dequeueReusableCellWithIdentifier:PPProviderPlanCellID forIndexPath:indexPath];
    PPProviderPlan *plan = self.plans[(NSUInteger)indexPath.row];
    NSString *name = PPProviderLocalizedText(plan.name, plan.planID);
    NSString *cost = [plan.costType isEqualToString:@"percentage"]
        ? [NSString stringWithFormat:kLang(@"Providers_Percentage_Format"), plan.costValue]
        : PPProviderMoneyText(plan.costValue, plan.currency);
    NSString *subtitle = [NSString stringWithFormat:@"%@ · %@ · %@",
                          PPProviderLocalizedType(plan.providerType), cost,
                          PPProviderLocalizedBillingInterval(plan.billingInterval)];
    NSString *detail = [NSString stringWithFormat:kLang(@"Providers_Plans_Detail_Format"),
                        plan.commissionRate, (long)plan.featureCount];
    if (plan.isRecommended) detail = [NSString stringWithFormat:@"%@ · %@", kLang(@"Providers_Plans_Recommended"), detail];
    [cell configureWithTitle:name subtitle:subtitle detail:detail status:plan.status
                      symbol:@"rectangle.stack.badge.person.crop" actionable:self.canManage];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.canManage || self.isMutating || indexPath.row >= (NSInteger)self.plans.count) return;
    PPProviderPlan *plan = self.plans[(NSUInteger)indexPath.row];
    UIAlertController *actions = [UIAlertController alertControllerWithTitle:PPProviderLocalizedText(plan.name, plan.planID)
                                                                      message:kLang(@"Providers_Plans_Delete_Explanation")
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
    [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Delete") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self pp_confirmDeletePlan:plan];
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

#pragma mark - Create Plan

- (NSArray<NSDictionary *> *)pp_providerTypeOptions {
    return @[
        @{@"value": @"delivery_company", @"title": PPProviderLocalizedType(@"delivery_company")},
        @{@"value": @"service", @"title": PPProviderLocalizedType(@"service")},
        @{@"value": @"marketplace", @"title": PPProviderLocalizedType(@"marketplace")},
        @{@"value": @"pharmacy", @"title": PPProviderLocalizedType(@"pharmacy")},
        @{@"value": @"vet", @"title": PPProviderLocalizedType(@"vet")},
    ];
}

- (void)pp_chooseProviderTypeForNewPlan {
    if (!self.canManage || self.isMutating) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Providers_Plans_SelectType")
                                                                    message:kLang(@"Providers_Plans_SelectType_Subtitle")
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *option in self.pp_providerTypeOptions) {
        [sheet addAction:[UIAlertAction actionWithTitle:option[@"title"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self pp_presentNewPlanFormForProviderType:option[@"value"]];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pp_presentNewPlanFormForProviderType:(NSString *)providerType {
    UIAlertController *form = [UIAlertController alertControllerWithTitle:kLang(@"Providers_Plans_New")
                                                                   message:PPProviderLocalizedType(providerType)
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSArray<NSString *> *placeholders = @[
        kLang(@"Providers_Plans_NameEn"), kLang(@"Providers_Plans_NameAr"),
        kLang(@"Providers_Plans_Price"), kLang(@"Providers_Plans_CommissionRate")
    ];
    [placeholders enumerateObjectsUsingBlock:^(NSString *placeholder, NSUInteger index, BOOL *stop) {
        (void)stop;
        [form addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.placeholder = placeholder;
            field.accessibilityLabel = placeholder;
            field.semanticContentAttribute = index == 1 ? UISemanticContentAttributeForceRightToLeft : [Language semanticAttributeForCurrentLanguage];
            field.textAlignment = index == 1 ? NSTextAlignmentRight : Language.alignmentForCurrentLanguage;
            if (index >= 2) field.keyboardType = UIKeyboardTypeDecimalPad;
        }];
    }];
    UIAlertAction *save = [UIAlertAction actionWithTitle:kLang(@"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *nameEn = [form.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *nameAr = [form.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        double amount = form.textFields[2].text.doubleValue;
        double commission = form.textFields[3].text.doubleValue;
        if (nameEn.length == 0 || nameAr.length == 0 || amount < 0.0 || commission < 0.0 || commission > 100.0) {
            [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"Providers_Plans_Invalid_Form")];
            return;
        }
        NSDictionary *payload = @{
            @"providerType": providerType,
            @"status": @"active",
            @"name": @{@"en": nameEn, @"ar": nameAr},
            @"description": @{@"en": @"", @"ar": @""},
            @"costType": @"price",
            @"costValue": @(amount),
            @"priceAmount": @(amount),
            @"currency": @"QAR",
            @"billingInterval": @"monthly",
            @"percentageBasis": @"item",
            @"percentageCustomLabel": @"",
            @"platformCommissionRate": @(commission),
            @"trialDays": @0,
            @"rank": @(self.plans.count),
            @"recommended": @NO,
            @"features": @[]
        };
        [self pp_savePlanPayload:payload];
    }];
    [form addAction:save];
    [form addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:form animated:YES completion:nil];
}

- (void)pp_savePlanPayload:(NSDictionary *)payload {
    self.isMutating = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] savePlan:payload completion:^(NSString *planID, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isMutating = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            if (error) {
                [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            (void)planID;
            [PPFunc pp_playSuccessEffect];
            [self loadData];
        });
    }];
}

#pragma mark - Delete Plan

- (void)pp_confirmDeletePlan:(PPProviderPlan *)plan {
    [PPAlertHelper showConfirmationIn:self title:kLang(@"Providers_Plans_Delete_Title") subtitle:kLang(@"Providers_Plans_Delete_Explanation") confirmButton:kLang(@"Delete") cancelButton:kLang(@"Cancel") icon:nil confirmBlock:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        [self pp_deletePlan:plan];
    } cancelBlock:nil];
}

- (void)pp_deletePlan:(PPProviderPlan *)plan {
    self.isMutating = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] deletePlan:plan.planID completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isMutating = NO;
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