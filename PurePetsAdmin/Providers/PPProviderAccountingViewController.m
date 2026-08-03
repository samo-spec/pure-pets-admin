#import "PPProviderAccountingViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"

static NSString * const PPProviderAccountingCellID = @"PPProviderAccountingCell";
static NSString * const PPProviderAccountingLastProviderKey = @"PPProviderAccountingLastProviderID";

@interface PPProviderAccountingViewController () <UITextFieldDelegate>
@property (nonatomic, strong) NSArray<PPProviderCommissionRecord *> *records;
@property (nonatomic, strong) NSArray<NSDictionary *> *totals;
@property (nonatomic, strong) PPProviderContextHeaderView *contextHeader;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIView *inputSurface;
@property (nonatomic, strong) UITextField *providerField;
@property (nonatomic, strong) UIButton *loadButton;
@property (nonatomic, strong) PPProviderStateView *stateView;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, copy) NSString *loadedProviderID;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPProviderAccountingViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.records = @[];
    self.totals = @[];
    [self pp_evaluatePermissions];
    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_buildHeader];
    [self pp_updateState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_fitTableHeader];
}

#pragma mark - Setup

- (void)pp_evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasAnyPermission:@[kStaffPermAccountingView, kStaffPermAccountingManage]]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.navigationController popViewControllerAnimated:YES]; });
    }
}

- (void)pp_configureNavigation {
    self.title = kLang(@"Providers_Accounting_Title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(pp_reloadCurrentProvider)];
    refresh.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = refresh;
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPProviderCanvasColor();
    self.tableView.backgroundColor = PPProviderCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 148.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, PPSpaceXXL, 0.0);
    [self.tableView registerClass:PPProviderRecordCell.class forCellReuseIdentifier:PPProviderAccountingCellID];

    self.stateView = [PPProviderStateView new];
    __weak typeof(self) weakSelf = self;
    self.stateView.retryHandler = ^{ [weakSelf pp_reloadCurrentProvider]; };
    self.tableView.backgroundView = self.stateView;
}

- (void)pp_buildHeader {
    UIView *container = [UIView new];
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.contextHeader = [[PPProviderContextHeaderView alloc] initWithTitle:kLang(@"Providers_Accounting_HeroTitle")
                                                                   subtitle:kLang(@"Providers_Accounting_HeroSubtitle")
                                                                     symbol:@"lock.shield.fill"];
    self.contextHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.contextHeader];

    self.inputSurface = [UIView new];
    self.inputSurface.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputSurface.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(self.inputSurface, PPCornerCard);
    self.inputSurface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.inputSurface.layer.borderColor = PPProviderSeparatorColor().CGColor;
    [container addSubview:self.inputSurface];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = kLang(@"Providers_Accounting_ProviderID");
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:15.0]];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = PPProviderPrimaryTextColor();
    label.textAlignment = Language.alignmentForCurrentLanguage;
    [self.inputSurface addSubview:label];

    self.providerField = [UITextField new];
    self.providerField.translatesAutoresizingMaskIntoConstraints = NO;
    self.providerField.placeholder = kLang(@"Providers_Accounting_ProviderPlaceholder");
    self.providerField.text = [NSUserDefaults.standardUserDefaults stringForKey:PPProviderAccountingLastProviderKey];
    self.providerField.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:16.0]];
    self.providerField.adjustsFontForContentSizeCategory = YES;
    self.providerField.textColor = PPProviderPrimaryTextColor();
    self.providerField.backgroundColor = PPProviderRaisedSurfaceColor();
    self.providerField.textAlignment = Language.alignmentForCurrentLanguage;
    self.providerField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.providerField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.providerField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.providerField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.providerField.returnKeyType = UIReturnKeyGo;
    self.providerField.delegate = self;
    self.providerField.accessibilityLabel = kLang(@"Providers_Accounting_ProviderID");
    self.providerField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, PPSpaceMD, 1)];
    self.providerField.leftViewMode = UITextFieldViewModeAlways;
    self.providerField.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, PPSpaceMD, 1)];
    self.providerField.rightViewMode = UITextFieldViewModeAlways;
    PPApplyContinuousCorners(self.providerField, PPCornerSmall);
    [self.inputSurface addSubview:self.providerField];

    self.loadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.loadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loadButton setTitle:kLang(@"Providers_Accounting_LoadReport") forState:UIControlStateNormal];
    [self.loadButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.loadButton.backgroundColor = PPProviderBrandColor();
    self.loadButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:15.0]];
    self.loadButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    PPApplyContinuousCorners(self.loadButton, PPCornerSmall);
    [self.loadButton addTarget:self action:@selector(pp_loadProviderFromField) forControlEvents:UIControlEventTouchUpInside];
    [self.inputSurface addSubview:self.loadButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.contextHeader.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.contextHeader.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.contextHeader.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.inputSurface.topAnchor constraintEqualToAnchor:self.contextHeader.bottomAnchor constant:PPSpaceSM],
        [self.inputSurface.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],
        [self.inputSurface.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],
        [self.inputSurface.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceSM],
        [label.topAnchor constraintEqualToAnchor:self.inputSurface.topAnchor constant:PPSpaceBase],
        [label.leadingAnchor constraintEqualToAnchor:self.inputSurface.leadingAnchor constant:PPSpaceBase],
        [label.trailingAnchor constraintEqualToAnchor:self.inputSurface.trailingAnchor constant:-PPSpaceBase],
        [self.providerField.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:PPSpaceSM],
        [self.providerField.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
        [self.providerField.trailingAnchor constraintEqualToAnchor:label.trailingAnchor],
        [self.providerField.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightMD],
        [self.loadButton.topAnchor constraintEqualToAnchor:self.providerField.bottomAnchor constant:PPSpaceMD],
        [self.loadButton.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
        [self.loadButton.trailingAnchor constraintEqualToAnchor:label.trailingAnchor],
        [self.loadButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightMD],
        [self.loadButton.bottomAnchor constraintEqualToAnchor:self.inputSurface.bottomAnchor constant:-PPSpaceBase],
    ]];
    self.headerContainer = container;
    self.tableView.tableHeaderView = container;
    [self.contextHeader setMetricText:kLang(@"Providers_Accounting_SecureLedger")];
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

- (void)pp_loadProviderFromField {
    NSString *providerID = [self.providerField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (providerID.length == 0) {
        [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"Providers_Accounting_ProviderRequired")];
        return;
    }
    [self.view endEditing:YES];
    [self pp_loadProviderID:providerID];
}

- (void)pp_reloadCurrentProvider {
    NSString *providerID = self.loadedProviderID.length ? self.loadedProviderID : self.providerField.text;
    providerID = [providerID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (providerID.length == 0) {
        [self pp_updateState];
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.providerField);
        return;
    }
    [self pp_loadProviderID:providerID];
}

- (void)pp_loadProviderID:(NSString *)providerID {
    if (self.isLoading) return;
    self.isLoading = YES;
    self.currentError = nil;
    self.loadedProviderID = providerID;
    self.providerField.text = providerID;
    self.loadButton.enabled = NO;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [NSUserDefaults.standardUserDefaults setObject:providerID forKey:PPProviderAccountingLastProviderKey];
    [self pp_updateState];

    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchCommissionReportForProviderID:providerID completion:^(NSArray<PPProviderCommissionRecord *> *records, NSArray<NSDictionary *> *totals, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            self.loadButton.enabled = YES;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            self.currentError = error;
            if (!error) {
                self.records = records ?: @[];
                self.totals = totals ?: @[];
            }
            [self pp_refreshHeaderMetric];
            [self pp_updateState];
            [self.tableView reloadData];
        });
    }];
}

- (void)pp_refreshHeaderMetric {
    double sales = 0.0;
    double net = 0.0;
    NSString *currency = @"QAR";
    for (NSDictionary *total in self.totals) {
        sales += PPSafeDouble(total[@"totalSales"]);
        net += PPSafeDouble(total[@"providerNet"]);
        NSString *candidate = PPSafeString(total[@"currency"]);
        if (candidate.length) currency = candidate;
    }
    if (self.loadedProviderID.length == 0) {
        [self.contextHeader setMetricText:kLang(@"Providers_Accounting_SecureLedger")];
        return;
    }
    [self.contextHeader setMetricText:[NSString stringWithFormat:kLang(@"Providers_Accounting_Summary_Format"),
                                      (unsigned long)self.records.count,
                                      PPProviderMoneyText(sales, currency),
                                      PPProviderMoneyText(net, currency)]];
}

- (void)pp_updateState {
    BOOL hasRows = self.records.count > 0;
    self.stateView.hidden = hasRows;
    if (hasRows) return;
    if (self.isLoading) {
        [self.stateView showLoadingWithTitle:kLang(@"Providers_Accounting_Loading") subtitle:self.loadedProviderID ?: @""];
    } else if (self.currentError) {
        [self.stateView showErrorWithTitle:kLang(@"Providers_Accounting_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
    } else if (self.loadedProviderID.length) {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Accounting_Empty") subtitle:kLang(@"Providers_Accounting_Empty_Subtitle") symbol:@"doc.text.magnifyingglass"];
    } else {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Accounting_SelectProvider") subtitle:kLang(@"Providers_Accounting_SelectProvider_Subtitle") symbol:@"person.text.rectangle"];
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.records.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPProviderRecordCell *cell = [tableView dequeueReusableCellWithIdentifier:PPProviderAccountingCellID forIndexPath:indexPath];
    PPProviderCommissionRecord *record = self.records[(NSUInteger)indexPath.row];
    NSString *order = record.orderID.length ? record.orderID : record.recordID;
    NSString *subtitle = [NSString stringWithFormat:kLang(@"Providers_Accounting_MoneyLine_Format"),
                          PPProviderMoneyText(record.grossSaleAmount, record.currency),
                          PPProviderMoneyText(record.providerNetAmount, record.currency)];
    NSString *detail = [NSString stringWithFormat:kLang(@"Providers_Accounting_Detail_Format"),
                        PPProviderMoneyText(record.platformCommissionAmount, record.currency),
                        record.commissionRate,
                        PPProviderDateText(record.createdAt)];
    [cell configureWithTitle:order subtitle:subtitle detail:detail status:record.status symbol:@"lock.doc.fill" actionable:NO];
    return cell;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.providerField) {
        [self pp_loadProviderFromField];
        return NO;
    }
    return YES;
}

@end