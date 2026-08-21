#import "PPPaymentManagementViewController.h"
#import "PPPaymentManagementRecordCell.h"
#import "PPPaymentManagementService.h"
#import "PPPaymentDetailsViewController.h"
#import "PPS.h"
#import "Styling.h"
#import "Language.h"
#import "PPToast.h"

static NSString *PPPaymentAdminListTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static UIColor *PPPaymentAdminWorkflowColor(NSString *statusKey)
{
    NSString *normalized = [PPPaymentAdminRecord normalizedStatusString:statusKey];
    if ([normalized isEqualToString:@"paid"]) return [UIColor ppSuccess];
    if ([normalized isEqualToString:@"processing"]) return [UIColor ppInfo];
    if ([normalized isEqualToString:@"shipped"]) return [UIColor ppQuickActionCommunity];
    if ([normalized isEqualToString:@"delivered"]) return [UIColor ppSuccess];
    if ([normalized isEqualToString:@"pending"] || [normalized isEqualToString:@"pending_collection"] || [normalized isEqualToString:@"verification_pending"]) {
        return [UIColor ppInfo];
    }
    if ([normalized isEqualToString:@"failed"]) return [UIColor ppError];
    if ([normalized isEqualToString:@"cancelled"]) return [UIColor ppTextSecondary];
    if ([normalized isEqualToString:@"refunded"] || [normalized isEqualToString:@"partially_refunded"]) {
        return [UIColor ppWarning];
    }
    if ([normalized isEqualToString:@"preparing"] || [normalized isEqualToString:@"packed"]) return [UIColor ppQuickActionAnimals];
    if ([normalized isEqualToString:@"completed"]) return [UIColor ppSuccess];
    if ([normalized isEqualToString:@"shipping"] || [normalized isEqualToString:@"in_transit"] || [normalized isEqualToString:@"out_for_delivery"]) {
        return [UIColor ppInfo];
    }
    return [UIColor ppPrimary];
}

static NSString *PPPaymentAdminWorkflowSymbolForManagement(NSString *statusKey)
{
    NSString *normalized = [PPPaymentAdminRecord normalizedStatusString:statusKey];
    if ([normalized isEqualToString:@"paid"]) return @"checkmark.seal.fill";
    if ([normalized isEqualToString:@"processing"]) return @"gearshape.fill";
    if ([normalized isEqualToString:@"shipped"]) return @"shippingbox.fill";
    if ([normalized isEqualToString:@"delivered"]) return @"house.fill";
    if ([normalized isEqualToString:@"failed"]) return @"exclamationmark.octagon.fill";
    if ([normalized isEqualToString:@"cancelled"]) return @"xmark.octagon.fill";
    if ([normalized isEqualToString:@"refunded"] || [normalized isEqualToString:@"partially_refunded"]) return @"arrow.uturn.left.circle.fill";
    if ([normalized isEqualToString:@"verification_pending"]) return @"shield.lefthalf.filled";
    if ([normalized isEqualToString:@"preparing"] || [normalized isEqualToString:@"packed"]) return @"tray.2.fill";
    if ([normalized isEqualToString:@"shipping"] || [normalized isEqualToString:@"in_transit"] || [normalized isEqualToString:@"out_for_delivery"]) return @"car.fill";
    return @"shippingbox.circle.fill";
}

static NSString *PPPaymentAdminListDateTitle(PPPaymentAdminDateRange dateRange)
{
    switch (dateRange) {
        case PPPaymentAdminDateRangeToday: return kLang(@"PaymentMgmt_Date_Today");
        case PPPaymentAdminDateRangeLast7Days: return kLang(@"PaymentMgmt_Date_Last7Days");
        case PPPaymentAdminDateRangeLast30Days: return kLang(@"PaymentMgmt_Date_Last30Days");
        case PPPaymentAdminDateRangeLast90Days: return kLang(@"PaymentMgmt_Date_Last90Days");
        case PPPaymentAdminDateRangeAll: break;
    }
    return kLang(@"PaymentMgmt_Date_AllDates");
}

static NSString *PPPaymentAdminListCurrencyTitle(PPPaymentAdminRecord *record)
{
    NSString *currency = PPPaymentAdminListTrimmedString(record.currency);
    if (currency.length == 0) currency = @"QAR";
    return [NSString stringWithFormat:@"%@ %.2f", currency.uppercaseString, record.totalAmount];
}

static void PPPaymentAdminApplyLanguageToTableCell(UITableViewCell *cell)
{
    if (![cell isKindOfClass:UITableViewCell.class]) return;
    UISemanticContentAttribute semantic = [Language semanticAttributeForCurrentLanguage];
    NSTextAlignment alignment = [Language alignmentForCurrentLanguage];
    cell.semanticContentAttribute = semantic;
    cell.contentView.semanticContentAttribute = semantic;
    cell.textLabel.textAlignment = alignment;
    cell.detailTextLabel.textAlignment = alignment;
}

typedef NS_ENUM(NSInteger, PPPaymentManagementListActionType) {
    PPPaymentManagementListActionTypeApprove = 0,
    PPPaymentManagementListActionTypeProcessing,
    PPPaymentManagementListActionTypeShipped,
    PPPaymentManagementListActionTypeDelivered,
    PPPaymentManagementListActionTypeCollectPayment,
    PPPaymentManagementListActionTypeCancel,
};

static NSString *PPPaymentAdminListDetailsActionTitle(void)
{
    NSString *title = PPPaymentAdminListTrimmedString(kLang(@"PaymentMgmt_Title_Details"));
    if (title.length == 0 || [title hasPrefix:@"PaymentMgmt_"]) return @"Details";
    return title;
}

@interface PPPaymentManagementViewController () <PPSDelegate>

@property (nonatomic, strong) PPPaymentManagementService *service;
@property (nonatomic, strong) NSMutableArray<PPPaymentAdminRecord *> *records;
@property (nonatomic, strong) PPPaymentManagementFilters *filters;
@property (nonatomic, strong, nullable) FIRDocumentSnapshot *nextCursor;
@property (nonatomic, strong) PPS *searchView;
@property (nonatomic, strong) UIView *searchContainer;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL isLoadingMore;
@property (nonatomic, assign) BOOL hasLoadedOnce;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightOrderActions;



@end

@implementation PPPaymentManagementViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _service = [PPPaymentManagementService shared];
        _filters = [PPPaymentManagementFilters defaultFilters];
        _records = [NSMutableArray array];
        _inFlightOrderActions = [NSMutableSet set];
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale currentLocale];
        [_dateFormatter setLocalizedDateFormatFromTemplate:@"d MMM h:mm a"];
        //self.title = kLang(@"PaymentMgmt_Title_List");
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = AppBackgroundClr;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 124.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.refreshControl = [UIRefreshControl new];
    self.refreshControl.tintColor = [UIColor ppPrimary];
    [self.refreshControl addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventValueChanged];

    [self setupSearchHeader];
    [self pp_reloadPaymentsReset:YES showHUD:YES];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self pp_navBarWithOtherButton:nil title:kLang(@"PaymentMgmt_Title_List")];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (!self.searchContainer) return;
    CGFloat width = self.tableView.bounds.size.width;
    CGRect frame = self.searchContainer.frame;
    if (fabs(frame.size.width - width) > 0.5) {
        frame.size.width = width;
        self.searchContainer.frame = frame;
        self.tableView.tableHeaderView = self.searchContainer;
    }
}

#pragma mark - UI

- (void)setupSearchHeader
{
    CGFloat horizontal = PPScreenMargin;
    CGFloat vertical = PPSpaceSM;
    CGFloat searchHeight = PPButtonHeightLG;
    CGFloat containerHeight = vertical + searchHeight + vertical;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;

    self.searchContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, containerHeight)];
    self.searchContainer.backgroundColor = UIColor.clearColor;

    PPS *search = [[PPS alloc] initWithFrame:CGRectZero];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.cornerRadius = searchHeight / 2.0;
    search.blurEnabled = NO;
    search.shadowEnabled = NO;
    search.debounceInterval = 0.18;
    search.fuzzyEnabled = NO;
    search.caseInsensitive = YES;
    search.diacriticsInsensitive = YES;
    search.delegate = self;
    search.backgroundColor = [UIColor ppSurface];
    search.textField.placeholder = kLang(@"PaymentMgmt_Search_Placeholder");
    search.textField.textAlignment = Language.alignmentForCurrentLanguage;
    search.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    search.textField.text = self.filters.searchText ?: @"";
    self.searchView = search;

    UIImage *filterImage = [UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"];
    UIImage *resetImage = [UIImage systemImageNamed:@"xmark.circle"];
    [search configurePrimaryButtonWithImage:filterImage target:self action:@selector(onFilterTapped)];
    [search configureSecondaryButtonWithImage:resetImage target:self action:@selector(onResetFiltersTapped)];
    search.showsPrimaryButton = YES;

    [self.searchContainer addSubview:search];
    [NSLayoutConstraint activateConstraints:@[
        [search.topAnchor constraintEqualToAnchor:self.searchContainer.topAnchor constant:vertical],
        [search.leadingAnchor constraintEqualToAnchor:self.searchContainer.leadingAnchor constant:horizontal],
        [search.trailingAnchor constraintEqualToAnchor:self.searchContainer.trailingAnchor constant:-horizontal],
        [search.bottomAnchor constraintEqualToAnchor:self.searchContainer.bottomAnchor constant:-vertical],
        [search.heightAnchor constraintEqualToConstant:searchHeight]
    ]];

    self.tableView.tableHeaderView = self.searchContainer;
    [self pp_refreshSearchButtons];
}

- (void)pp_refreshSearchButtons
{
    BOOL hasActiveSearch = PPPaymentAdminListTrimmedString(self.filters.searchText).length > 0;
    self.searchView.showsSecondaryButton = hasActiveSearch || ![self.filters isDefaultState];
}

- (void)pp_setLoadMoreFooterVisible:(BOOL)visible
{
    if (!visible) {
        self.tableView.tableFooterView = [UIView new];
        return;
    }

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 56.0)];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [footer addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    self.tableView.tableFooterView = footer;
}

#pragma mark - Data

- (void)onRefresh
{
    [self pp_reloadPaymentsReset:YES showHUD:NO];
}

- (void)pp_reloadPaymentsReset:(BOOL)reset showHUD:(BOOL)showHUD
{
    if (self.isLoading || self.isLoadingMore) return;
    if (![self.service currentAdminCanViewPayments]) {
        [self.refreshControl endRefreshing];
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_NoViewPaymentsPermission")];
        self.hasLoadedOnce = YES;
        [self.tableView reloadData];
        return;
    }

    self.isLoading = reset;
    self.isLoadingMore = !reset;
    if (reset) {
        self.nextCursor = nil;
        if (showHUD && !self.refreshControl.isRefreshing) {
            [PPHUD showIndeterminateIn:self.view title:kLang(@"Loading") subtitle:kLang(@"PaymentMgmt_Loading_Payments")];
        }
    } else {
        [self pp_setLoadMoreFooterVisible:YES];
    }

    __weak typeof(self) weakSelf = self;
    [self.service fetchOrdersWithFilters:self.filters
                                pageSize:30
                              startAfter:(reset ? nil : self.nextCursor)
                              completion:^(NSArray<PPPaymentAdminRecord *> *records, FIRDocumentSnapshot * _Nullable nextCursor, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        [PPHUD dismiss];
        [self.refreshControl endRefreshing];
        [self pp_setLoadMoreFooterVisible:NO];
        self.isLoading = NO;
        self.isLoadingMore = NO;
        self.hasLoadedOnce = YES;

        BOOL isPartialRead = [PPPaymentManagementService isPartialReadError:error];
        if (error && !isPartialRead) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_LoadPayments")];
            [self.tableView reloadData];
            return;
        }

        self.nextCursor = isPartialRead ? nil : nextCursor;
        if (reset) {
            [self.records removeAllObjects];
        }

        NSMutableSet<NSString *> *knownIDs = [NSMutableSet set];
        for (PPPaymentAdminRecord *record in self.records) {
            if (record.orderId.length > 0) [knownIDs addObject:record.orderId];
        }
        for (PPPaymentAdminRecord *record in records ?: @[]) {
            if (record.orderId.length == 0 || [knownIDs containsObject:record.orderId]) continue;
            [knownIDs addObject:record.orderId];
            [self.records addObject:record];
        }

        [self pp_refreshSearchButtons];
        [self.tableView reloadData];
        if (isPartialRead) {
            [PPToast toast:kLang(@"PPOrder_Error_PartialRead")
                      style:PPToastStyleWarning
                     haptic:NO
                   duration:3.0
                   position:PPToastPositionBottom
                     inView:self.view];
        }
    }];
}

- (void)pp_loadNextPageIfNeededForIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section != 1 || self.records.count == 0) return;
    if (!self.nextCursor || self.isLoading || self.isLoadingMore) return;
    if (indexPath.row < self.records.count - 4) return;
    [self pp_reloadPaymentsReset:NO showHUD:NO];
}

#pragma mark - Filters

- (void)onFilterTapped
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"PaymentMgmt_Filter_Title")
                                                                   message:kLang(@"PaymentMgmt_Filter_Message")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"PaymentMgmt_Filter_Status")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self pp_presentStatusFilter];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"PaymentMgmt_Filter_Method")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self pp_presentPaymentTypeFilter];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"PaymentMgmt_Filter_Date")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction * _Nonnull action) {
        [self pp_presentDateFilter];
    }]];
    if (![self.filters isDefaultState] || PPPaymentAdminListTrimmedString(self.filters.searchText).length > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"PaymentMgmt_Filter_Reset")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            [self onResetFiltersTapped];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self pp_presentActionSheet:sheet sourceView:self.searchView.primaryButton];
}

- (void)onResetFiltersTapped
{
    self.filters = [PPPaymentManagementFilters defaultFilters];
    self.searchView.textField.text = @"";
    [self.searchView unfocus];
    [self pp_refreshSearchButtons];
    [self pp_reloadPaymentsReset:YES showHUD:NO];
}

- (void)pp_presentStatusFilter
{
    NSArray<NSString *> *keys = [PPPaymentAdminRecord quickStatusFilterKeys];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"PaymentMgmt_Filter_Status")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *statusKey in keys) {
        NSString *title = [statusKey isEqualToString:@"all"] ? kLang(@"PaymentMgmt_Filter_AllStatuses") : PPPaymentAdminDisplayTitleForWorkflowStatus(statusKey);
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            self.filters.statusKey = statusKey;
            [self pp_refreshSearchButtons];
            [self pp_reloadPaymentsReset:YES showHUD:NO];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self pp_presentActionSheet:sheet sourceView:self.searchView.primaryButton];
}

- (void)pp_presentPaymentTypeFilter
{
    NSArray<NSDictionary *> *options = @[
        @{@"key": @"all", @"title": kLang(@"PaymentMgmt_Filter_AllMethods")},
        @{@"key": @"qib", @"title": PPPaymentAdminDisplayTitleForPaymentMethod(@"qib")},
        @{@"key": @"card", @"title": PPPaymentAdminDisplayTitleForPaymentMethod(@"card")},
        @{@"key": @"cash", @"title": PPPaymentAdminDisplayTitleForPaymentMethod(@"cash")},
        @{@"key": @"manual", @"title": PPPaymentAdminDisplayTitleForPaymentMethod(@"manual")},
    ];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"PaymentMgmt_Filter_Method")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *option in options) {
        [sheet addAction:[UIAlertAction actionWithTitle:option[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            self.filters.paymentTypeKey = option[@"key"] ?: @"all";
            [self pp_refreshSearchButtons];
            [self pp_reloadPaymentsReset:YES showHUD:NO];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self pp_presentActionSheet:sheet sourceView:self.searchView.primaryButton];
}

- (void)pp_presentDateFilter
{
    NSArray<NSDictionary *> *options = @[
        @{@"title": kLang(@"PaymentMgmt_Date_AllDates"), @"value": @(PPPaymentAdminDateRangeAll)},
        @{@"title": kLang(@"PaymentMgmt_Date_Today"), @"value": @(PPPaymentAdminDateRangeToday)},
        @{@"title": kLang(@"PaymentMgmt_Date_Last7Days"), @"value": @(PPPaymentAdminDateRangeLast7Days)},
        @{@"title": kLang(@"PaymentMgmt_Date_Last30Days"), @"value": @(PPPaymentAdminDateRangeLast30Days)},
        @{@"title": kLang(@"PaymentMgmt_Date_Last90Days"), @"value": @(PPPaymentAdminDateRangeLast90Days)},
    ];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"PaymentMgmt_Filter_Date")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *option in options) {
        [sheet addAction:[UIAlertAction actionWithTitle:option[@"title"]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction * _Nonnull action) {
            self.filters.dateRange = [option[@"value"] integerValue];
            [self pp_refreshSearchButtons];
            [self pp_reloadPaymentsReset:YES showHUD:NO];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self pp_presentActionSheet:sheet sourceView:self.searchView.primaryButton];
}

- (void)pp_presentActionSheet:(UIAlertController *)sheet sourceView:(UIView *)sourceView
{
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: self.view;
        popover.sourceRect = sourceView ? sourceView.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSArray<NSDictionary *> *)pp_orderActionsForRecord:(PPPaymentAdminRecord *)record
{
    if (record.fulfillmentVersion == 1) return @[];
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    if ([PPPaymentAdminRecord canApproveOrderStatus:record.rawStatus] &&
        ![[PPPaymentAdminRecord normalizedStatusString:record.paymentMethodId] isEqualToString:@"cash"]) {
        [rows addObject:@{
            @"type": @(PPPaymentManagementListActionTypeApprove),
            @"title": kLang(@"PaymentMgmt_Action_ApprovePayment_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_ApprovePayment_Subtitle"),
            @"tint": [UIColor ppSuccess],
        }];
    }
    if ([PPPaymentAdminRecord canMarkOrderProcessingForOrder:record]) {
        [rows addObject:@{
            @"type": @(PPPaymentManagementListActionTypeProcessing),
            @"title": kLang(@"PaymentMgmt_Action_MarkProcessing_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_MarkProcessing_Subtitle"),
            @"tint": [UIColor ppInfo],
        }];
    }
    if ([PPPaymentAdminRecord canMarkOrderShippedStatus:record.rawStatus]) {
        [rows addObject:@{
            @"type": @(PPPaymentManagementListActionTypeShipped),
            @"title": kLang(@"PaymentMgmt_Action_MarkShipped_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_MarkShipped_Subtitle"),
            @"tint": [UIColor ppQuickActionCommunity],
        }];
    }
    if ([PPPaymentAdminRecord canMarkOrderDeliveredStatus:record.rawStatus]) {
        [rows addObject:@{
            @"type": @(PPPaymentManagementListActionTypeDelivered),
            @"title": kLang(@"PaymentMgmt_Action_MarkDelivered_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_MarkDelivered_Subtitle"),
            @"tint": [UIColor ppQuickActionServices],
        }];
    }
    if ([PPPaymentAdminRecord canCollectCashPaymentForOrder:record]) {
        [rows addObject:@{
            @"type": @(PPPaymentManagementListActionTypeCollectPayment),
            @"title": kLang(@"PaymentMgmt_Action_CollectPayment_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_CollectPayment_Subtitle"),
            @"tint": [UIColor ppSuccess],
        }];
    }
    if ([PPPaymentAdminRecord canCancelOrderStatus:record.rawStatus]) {
        [rows addObject:@{
            @"type": @(PPPaymentManagementListActionTypeCancel),
            @"title": kLang(@"PaymentMgmt_Action_CancelOrder_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_CancelOrder_Subtitle"),
            @"tint": [UIColor ppError],
        }];
    }
    return rows.copy;
}

- (NSDictionary *)pp_defaultNextOrderActionForRecord:(PPPaymentAdminRecord *)record
{
    for (NSDictionary *row in [self pp_orderActionsForRecord:record]) {
        PPPaymentManagementListActionType type = [row[@"type"] integerValue];
        if (type != PPPaymentManagementListActionTypeCancel) {
            return row;
        }
    }
    return nil;
}

- (void)pp_openDetailsForRecordAtRow:(NSInteger)row
{
    if (row < 0 || row >= self.records.count) return;
    PPPaymentAdminRecord *record = self.records[row];
    PPPaymentDetailsViewController *details = [[PPPaymentDetailsViewController alloc] initWithRecord:record];
    [self.navigationController pushViewController:details animated:YES];
}

- (void)pp_openOrderFromCellButton:(UIButton *)sender
{
    [self pp_openDetailsForRecordAtRow:sender.tag];
}

- (NSString *)pp_titleForListOrderAction:(PPPaymentManagementListActionType)actionType
{
    switch (actionType) {
        case PPPaymentManagementListActionTypeApprove:
            return kLang(@"PaymentMgmt_Action_ApprovePayment_Title");
        case PPPaymentManagementListActionTypeProcessing:
            return kLang(@"PaymentMgmt_Action_MarkProcessing_Title");
        case PPPaymentManagementListActionTypeShipped:
            return kLang(@"PaymentMgmt_Action_MarkShipped_Title");
        case PPPaymentManagementListActionTypeDelivered:
            return kLang(@"PaymentMgmt_Action_MarkDelivered_Title");
        case PPPaymentManagementListActionTypeCollectPayment:
            return kLang(@"PaymentMgmt_Action_CollectPayment_Title");
        case PPPaymentManagementListActionTypeCancel:
            return kLang(@"PaymentMgmt_Action_CancelOrder_Title");
    }
    return kLang(@"PaymentMgmt_Action_UpdateRequest_Title");
}

- (NSString *)pp_confirmationSubtitleForListOrderAction:(PPPaymentManagementListActionType)actionType
{
    switch (actionType) {
        case PPPaymentManagementListActionTypeApprove:
            return kLang(@"PaymentMgmt_Confirm_OrderApprove");
        case PPPaymentManagementListActionTypeProcessing:
            return kLang(@"PaymentMgmt_Confirm_OrderProcessing");
        case PPPaymentManagementListActionTypeShipped:
            return kLang(@"PaymentMgmt_Confirm_OrderShipped");
        case PPPaymentManagementListActionTypeDelivered:
            return kLang(@"PaymentMgmt_Confirm_OrderDelivered");
        case PPPaymentManagementListActionTypeCollectPayment:
            return kLang(@"PaymentMgmt_Confirm_OrderCollectPayment");
        case PPPaymentManagementListActionTypeCancel:
            return kLang(@"PaymentMgmt_Confirm_OrderCancel");
    }
    return kLang(@"PaymentMgmt_Confirm_RequestUpdate");
}

- (NSString *)pp_successMessageForListOrderAction:(PPPaymentManagementListActionType)actionType
{
    switch (actionType) {
        case PPPaymentManagementListActionTypeApprove:
            return kLang(@"PaymentMgmt_Success_OrderApprove");
        case PPPaymentManagementListActionTypeProcessing:
            return kLang(@"PaymentMgmt_Success_OrderProcessing");
        case PPPaymentManagementListActionTypeShipped:
            return kLang(@"PaymentMgmt_Success_OrderShipped");
        case PPPaymentManagementListActionTypeDelivered:
            return kLang(@"PaymentMgmt_Success_OrderDelivered");
        case PPPaymentManagementListActionTypeCollectPayment:
            return kLang(@"PaymentMgmt_Success_OrderCollectPayment");
        case PPPaymentManagementListActionTypeCancel:
            return kLang(@"PaymentMgmt_Success_OrderCancel");
    }
    return kLang(@"Updated");
}

- (NSString *)pp_nextWorkflowStatusForListOrderAction:(PPPaymentManagementListActionType)actionType
                                         record:(PPPaymentAdminRecord *)record
{
    switch (actionType) {
        case PPPaymentManagementListActionTypeApprove:
            return @"paid";
        case PPPaymentManagementListActionTypeProcessing:
            return @"processing";
        case PPPaymentManagementListActionTypeShipped:
            return @"shipped";
        case PPPaymentManagementListActionTypeDelivered:
            return @"delivered";
        case PPPaymentManagementListActionTypeCollectPayment:
            return [record workflowStatusKey];
        case PPPaymentManagementListActionTypeCancel:
            return @"cancelled";
    }
    return [record workflowStatusKey];
}

- (NSString *)pp_callableActionForListOrderAction:(PPPaymentManagementListActionType)actionType
{
    switch (actionType) {
        case PPPaymentManagementListActionTypeApprove: return @"order_approve";
        case PPPaymentManagementListActionTypeProcessing: return @"order_mark_processing";
        case PPPaymentManagementListActionTypeShipped: return @"order_mark_shipped";
        case PPPaymentManagementListActionTypeDelivered: return @"order_mark_delivered";
        case PPPaymentManagementListActionTypeCollectPayment: return @"order_collect_payment";
        case PPPaymentManagementListActionTypeCancel: return @"order_cancel";
    }
    return @"";
}

- (NSString *)pp_defaultAdminNoteForListOrderAction:(PPPaymentManagementListActionType)actionType
                                           record:(PPPaymentAdminRecord *)record
{
    return [self.service defaultAdminNoteForOrderID:record.orderId
                                              action:[self pp_callableActionForListOrderAction:actionType]];
}

- (void)pp_confirmNextOrderActionFromCellButton:(UIButton *)sender
{
    NSInteger row = sender.tag;
    if (row < 0 || row >= self.records.count) return;
    PPPaymentAdminRecord *record = self.records[row];
    NSDictionary *nextAction = [self pp_defaultNextOrderActionForRecord:record];
    if (!nextAction) return;
    NSString *orderID = PPPaymentAdminListTrimmedString(record.orderId);
    if (orderID.length == 0) return;
    if ([self.inFlightOrderActions containsObject:orderID]) return;

    PPPaymentManagementListActionType actionType = [nextAction[@"type"] integerValue];
    NSString *title = [self pp_titleForListOrderAction:actionType];
    NSString *subtitle = [self pp_confirmationSubtitleForListOrderAction:actionType];
    NSString *resolvedNote = [self pp_defaultAdminNoteForListOrderAction:actionType record:record];
    if (resolvedNote.length == 0) return;

    [AlertHelper showConfirmationIn:self
                              title:title
                           subtitle:subtitle
                        placeholder:nil
                      confirmButton:kLang(@"Confirm")
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [self pp_executeListOrderAction:actionType record:record note:resolvedNote];
    } cancelBlock:nil];
}

- (void)pp_executeListOrderAction:(PPPaymentManagementListActionType)actionType
                           record:(PPPaymentAdminRecord *)record
                             note:(NSString *)note
{
    NSString *orderID = PPPaymentAdminListTrimmedString(record.orderId);
    if (orderID.length == 0) return;
    if ([self.inFlightOrderActions containsObject:orderID]) return;

    [self.inFlightOrderActions addObject:orderID];
    [PPHUD showIndeterminateIn:self.view title:kLang(@"PaymentMgmt_Loading_Updating") subtitle:kLang(@"PaymentMgmt_Loading_OrderUpdate")];

    void (^completion)(PPPaymentAdminRecord *, NSError *) = ^(PPPaymentAdminRecord *updatedRecord, NSError *error) {
        [self.inFlightOrderActions removeObject:orderID];
        [PPHUD dismiss];
        if (error) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"PaymentMgmt_Error_UpdateOrder")];
            return;
        }
        if (updatedRecord.orderId.length > 0) {
            for (NSInteger index = 0; index < self.records.count; index++) {
                PPPaymentAdminRecord *candidate = self.records[index];
                if ([candidate.orderId isEqualToString:updatedRecord.orderId]) {
                    self.records[index] = updatedRecord;
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:1];
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                    break;
                }
            }
        } else {
            [self pp_reloadPaymentsReset:YES showHUD:NO];
        }

        [PPHUD showSuccess:kLang(@"Updated") subtitle:[self pp_successMessageForListOrderAction:actionType]];
    };

    switch (actionType) {
        case PPPaymentManagementListActionTypeApprove:
            [self.service approveOrder:record note:note completion:completion];
            break;
        case PPPaymentManagementListActionTypeProcessing:
            [self.service markOrderProcessing:record note:note completion:completion];
            break;
        case PPPaymentManagementListActionTypeShipped:
            [self.service markOrderShipped:record note:note completion:completion];
            break;
        case PPPaymentManagementListActionTypeDelivered:
            [self.service markOrderDelivered:record note:note completion:completion];
            break;
        case PPPaymentManagementListActionTypeCollectPayment:
            [self.service collectOrderPayment:record note:note completion:completion];
            break;
        case PPPaymentManagementListActionTypeCancel:
            [self.service cancelOrder:record note:note completion:completion];
            break;
    }
}

#pragma mark - UITableView

#pragma mark - PPSDelegate

- (void)searchView:(PPS *)view didChangeText:(NSString *)text
{
    self.filters.searchText = PPPaymentAdminListTrimmedString(text);
    [self pp_refreshSearchButtons];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(pp_performDebouncedSearchReload) object:nil];
    [self performSelector:@selector(pp_performDebouncedSearchReload) withObject:nil afterDelay:0.30];
    (void)view;
}

- (void)searchViewDidSubmit:(PPS *)view
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(pp_performDebouncedSearchReload) object:nil];
    [view unfocus];
    [self pp_reloadPaymentsReset:YES showHUD:NO];
}

- (void)pp_performDebouncedSearchReload
{
    [self pp_reloadPaymentsReset:YES showHUD:NO];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    if (section == 0) return 1;
    return MAX(1, self.records.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    if (section == 0) return kLang(@"PaymentMgmt_Section_Overview");
    return kLang(@"PaymentMgmt_Section_Payments");
}

- (UITableViewCell *)pp_summaryCellForTableView:(UITableView *)tableView
{
    static NSString *cellID = @"PaymentSummaryCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:15]];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontRegular:13]];
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.numberOfLines = 0;
    }
    PPPaymentAdminApplyLanguageToTableCell(cell);

    if (!self.hasLoadedOnce && self.isLoading) {
        cell.textLabel.text = kLang(@"PaymentMgmt_Placeholder_LoadingTitle");
        cell.detailTextLabel.text = kLang(@"PaymentMgmt_Placeholder_LoadingSubtitle");
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.clockwise.circle"];
        cell.imageView.tintColor = [UIColor ppPrimary];
        return cell;
    }

    NSInteger openCount = 0;
    NSInteger refundedCount = 0;
    for (PPPaymentAdminRecord *record in self.records) {
        if ([record hasOpenRequests]) openCount += 1;
        NSString *workflow = [record workflowStatusKey];
        if ([workflow isEqualToString:@"refunded"] || [workflow isEqualToString:@"partially_refunded"]) {
            refundedCount += 1;
        }
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *statusTitle = [PPPaymentAdminRecord normalizedStatusString:self.filters.statusKey];
    if (statusTitle.length > 0 && ![statusTitle isEqualToString:@"all"]) {
        [parts addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Summary_Status_Format"), PPPaymentAdminDisplayTitleForWorkflowStatus(statusTitle)]];
    }
    NSString *typeKey = [PPPaymentAdminRecord normalizedStatusString:self.filters.paymentTypeKey];
    if (typeKey.length > 0 && ![typeKey isEqualToString:@"all"]) {
        [parts addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Summary_Method_Format"), PPPaymentAdminDisplayTitleForPaymentMethod(typeKey)]];
    }
    if (self.filters.dateRange != PPPaymentAdminDateRangeAll) {
        [parts addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Summary_Date_Format"), PPPaymentAdminListDateTitle(self.filters.dateRange)]];
    }
    if (PPPaymentAdminListTrimmedString(self.filters.searchText).length > 0) {
        [parts addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Summary_Search_Format"), self.filters.searchText]];
    }
    if (parts.count == 0) {
        [parts addObject:kLang(@"PaymentMgmt_Summary_AllPayments")];
    }
    [parts addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Summary_OpenReviews_Format"), (long)openCount]];
    [parts addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Summary_Refunded_Format"), (long)refundedCount]];
    if (self.nextCursor) {
        [parts addObject:kLang(@"PaymentMgmt_Summary_MoreResults")];
    }

    cell.textLabel.text = self.records.count == 1
        ? kLang(@"PaymentMgmt_Summary_Loaded_Singular")
        : [NSString stringWithFormat:kLang(@"PaymentMgmt_Summary_Loaded_Plural"), (long)self.records.count];
    cell.detailTextLabel.text = [parts componentsJoinedByString:@"\n"];
    cell.imageView.image = [UIImage systemImageNamed:@"creditcard.and.123"];
        cell.imageView.tintColor = [UIColor ppPrimary];
    return cell;
}

- (UITableViewCell *)pp_emptyCellForTableView:(UITableView *)tableView
{
    static NSString *cellID = @"PaymentEmptyCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:16]];
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontRegular:13]];
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.numberOfLines = 0;
    }
    PPPaymentAdminApplyLanguageToTableCell(cell);
    cell.textLabel.text = self.hasLoadedOnce ? kLang(@"PaymentMgmt_Placeholder_NoPaymentsTitle") : kLang(@"PaymentMgmt_Placeholder_NoPaymentsIdleTitle");
    cell.detailTextLabel.text = kLang(@"PaymentMgmt_Placeholder_NoPaymentsSubtitle");
    cell.imageView.image = [UIImage systemImageNamed:@"tray"];
    cell.imageView.tintColor = [UIColor ppTextSecondary];
    return cell;
}

- (UITableViewCell *)pp_recordCellForTableView:(UITableView *)tableView atIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellID = @"PaymentRecordCell";
    PPPaymentManagementRecordCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[PPPaymentManagementRecordCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
    }

    PPPaymentAdminRecord *record = self.records[indexPath.row];
    NSString *userText = PPPaymentAdminListTrimmedString(record.userDisplayName);
    if (userText.length == 0) userText = PPPaymentAdminListTrimmedString(record.userEmail);
    if (userText.length == 0) userText = PPPaymentAdminListTrimmedString(record.userId);

    NSString *paymentMethod = PPPaymentAdminListTrimmedString(record.paymentProvider);
    if (paymentMethod.length == 0) paymentMethod = PPPaymentAdminListTrimmedString(record.paymentTypeKey);
    NSString *paymentMethodTitle = paymentMethod.length > 0 ? PPPaymentAdminDisplayTitleForPaymentMethod(paymentMethod) : kLang(@"PaymentMgmt_Value_Unknown");

    NSString *updatedText = record.updatedAt ? [self.dateFormatter stringFromDate:record.updatedAt] : @"--";
    NSString *customerLine = [NSString stringWithFormat:@"%@ • %@",
                              userText.length > 0 ? userText : kLang(@"PaymentMgmt_Record_UnknownUser"),
                              paymentMethodTitle];
    NSMutableArray<NSString *> *stateBits = [NSMutableArray array];
    [stateBits addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Record_Updated_Format"), updatedText]];
    if ([record hasOpenRequests]) {
        [stateBits addObject:kLang(@"PaymentMgmt_Record_NeedsReview")];
    } else if (record.requests.count > 0) {
        [stateBits addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Record_RequestStatus_Format"), PPPaymentAdminDisplayTitleForRequestStatus(record.latestRequestStatus)]];
    }

    NSString *orderReference = [record displayOrderReference];
    if (orderReference.length == 0) orderReference = record.orderId ?: @"--";
    NSString *orderTitle = [NSString stringWithFormat:kLang(@"PaymentMgmt_Record_OrderId_Format"), orderReference];
    NSString *subtitleText = [stateBits componentsJoinedByString:@" • "];
    NSString *workflowStatus = [record workflowStatusKey];
    UIColor *workflowColor = PPPaymentAdminWorkflowColor(workflowStatus);
    NSString *statusTitle = PPPaymentAdminDisplayTitleForWorkflowStatus(workflowStatus);
    NSString *statusSymbol = PPPaymentAdminWorkflowSymbolForManagement(workflowStatus);
    NSDictionary *nextAction = [self pp_defaultNextOrderActionForRecord:record];
    BOOL hasNextAction = nextAction != nil;
    PPPaymentManagementListActionType actionType = nextAction[@"type"] ? [nextAction[@"type"] integerValue] : PPPaymentManagementListActionTypeDelivered;
    NSString *buttonTitle = hasNextAction
        ? ([nextAction[@"title"] isKindOfClass:NSString.class] ? nextAction[@"title"] : [self pp_titleForListOrderAction:actionType])
        : PPPaymentAdminListDetailsActionTitle();
    UIColor *actionTint = hasNextAction
        ? (nextAction[@"tint"] ?: [UIColor ppPrimary])
        : [UIColor ppTextPrimary];

    [cell configureWithOrderTitle:orderTitle
                       amountText:PPPaymentAdminListCurrencyTitle(record)
                     customerText:customerLine
                     subtitleText:subtitleText
                      statusTitle:statusTitle
                      statusColor:workflowColor
                     statusSymbol:statusSymbol
                      actionTitle:buttonTitle
                       actionTint:actionTint
                  prominentAction:hasNextAction];

    [cell.actionButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    cell.actionButton.tag = indexPath.row;
    if (hasNextAction) {
        [cell.actionButton addTarget:self action:@selector(pp_confirmNextOrderActionFromCellButton:) forControlEvents:UIControlEventTouchUpInside];
    } else {
        [cell.actionButton addTarget:self action:@selector(pp_openOrderFromCellButton:) forControlEvents:UIControlEventTouchUpInside];
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        return [self pp_summaryCellForTableView:tableView];
    }
    if (self.records.count == 0) {
        return [self pp_emptyCellForTableView:tableView];
    }
    return [self pp_recordCellForTableView:tableView atIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    if (indexPath.section == 1 && ![cell isKindOfClass:PPPaymentManagementRecordCell.class]) {
        [Styling applyGroupCellStyle:cell atIndexPath:indexPath inTableView:tableView];
    }
    [self pp_loadNextPageIfNeededForIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;

    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = [Styling fontMedium:14];
    header.textLabel.textColor = [UIColor ppTextSecondary];
    header.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
    header.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || self.records.count == 0) return;
    [self pp_openDetailsForRecordAtRow:indexPath.row];
}

@end
