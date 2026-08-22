#import "PPPaymentDetailsViewController.h"
#import "PPPaymentManagementService.h"
#import "Fulfillment/PPFulfillmentService.h"
#import "Styling.h"
#import "Language.h"

typedef NS_ENUM(NSInteger, PPPaymentOrderAdminActionType) {
    PPPaymentOrderAdminActionTypeApprove = 0,
    PPPaymentOrderAdminActionTypeProcessing,
    PPPaymentOrderAdminActionTypeShipped,
    PPPaymentOrderAdminActionTypeDelivered,
    PPPaymentOrderAdminActionTypeCollectPayment,
    PPPaymentOrderAdminActionTypeCancel,
    PPPaymentOrderAdminActionTypeOfficialAccept,
    PPPaymentOrderAdminActionTypeOfficialReject,
    PPPaymentOrderAdminActionTypeOfficialStartPreparing,
    PPPaymentOrderAdminActionTypeOfficialMarkReady,
    PPPaymentOrderAdminActionTypeOfficialRequestDelivery,
    PPPaymentOrderAdminActionTypeOfficialConfirmHandover,
    PPPaymentOrderAdminActionTypeOfficialCancel,
};

typedef NS_ENUM(NSInteger, PPPaymentRequestAdminActionType) {
    PPPaymentRequestAdminActionTypeApprove = 0,
    PPPaymentRequestAdminActionTypeReject,
    PPPaymentRequestAdminActionTypeComplete,
    PPPaymentRequestAdminActionTypeRefund,
    PPPaymentRequestAdminActionTypePartialRefund,
    PPPaymentRequestAdminActionTypeClose,
};

typedef NS_ENUM(NSInteger, PPPaymentDetailsSection) {
    PPPaymentDetailsSectionNextStep = 0,
    PPPaymentDetailsSectionOverview,
    PPPaymentDetailsSectionActions,
    PPPaymentDetailsSectionItems,
    PPPaymentDetailsSectionRequests,
    PPPaymentDetailsSectionTimeline,
    PPPaymentDetailsSectionAudit,
};

static NSString *PPPaymentAdminDetailsTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static UIColor *PPPaymentAdminDetailsStatusColor(NSString *statusKey)
{
    NSString *normalized = [PPPaymentAdminRecord normalizedStatusString:statusKey];
    if ([normalized isEqualToString:@"paid"]) return [UIColor ppSuccess];
    if ([normalized isEqualToString:@"processing"]) return [UIColor ppInfo];
    if ([normalized isEqualToString:@"shipped"]) return [UIColor ppQuickActionCommunity];
    if ([normalized isEqualToString:@"delivered"]) return [UIColor ppSuccess];
    if ([normalized isEqualToString:@"failed"]) return [UIColor ppError];
    if ([normalized isEqualToString:@"cancelled"]) return [UIColor ppTextSecondary];
    if ([normalized isEqualToString:@"refunded"] || [normalized isEqualToString:@"partially_refunded"]) return [UIColor ppWarning];
    return [UIColor ppPrimary];
}

static NSString *PPPaymentAdminDetailsCurrencyTitle(PPPaymentAdminRecord *record)
{
    NSString *currency = PPPaymentAdminDetailsTrimmedString(record.currency);
    if (currency.length == 0) currency = @"QAR";
    return [NSString stringWithFormat:@"%@ %.2f", currency.uppercaseString, record.totalAmount];
}

static NSString *PPPaymentAdminDetailsFirstNonEmpty(NSDictionary *dictionary, NSArray<NSString *> *keys)
{
    NSDictionary *source = [dictionary isKindOfClass:NSDictionary.class] ? dictionary : @{};
    for (NSString *key in keys ?: @[]) {
        NSString *value = PPPaymentAdminDetailsTrimmedString(source[key]);
        if (value.length > 0) return value;
    }
    return @"";
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

@interface PPPaymentNextStepCell : UITableViewCell

@property (nonatomic, strong, readonly) UIButton *actionButton;

- (void)configureWithStatusTitle:(NSString *)statusTitle
                     statusColor:(UIColor *)statusColor
                     actionTitle:(NSString *)actionTitle
                      actionTint:(UIColor *)actionTint
                        subtitle:(NSString *)subtitle;

@end

@implementation PPPaymentNextStepCell {
    UIView *_surfaceView;
    UIView *_statusContainer;
    UIImageView *_workflowIconView;
    UILabel *_captionLabel;
    UILabel *_statusLabel;
    UILabel *_subtitleLabel;
    UIButton *_actionButton;
    UIStackView *_actionRow;
}

static UIFont *PPPaymentDetailsScaledFont(UIFont *baseFont, UIFontTextStyle textStyle)
{
    if (!baseFont) return [UIFont preferredFontForTextStyle:textStyle];
    return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _surfaceView = [UIView new];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.backgroundColor = [UIColor ppElevatedSurface];
    PPApplyContinuousCorners(_surfaceView, PPCornerCard);
    _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _surfaceView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [self.contentView addSubview:_surfaceView];

    _captionLabel = [UILabel new];
    _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _captionLabel.font = PPPaymentDetailsScaledFont([Styling fontMedium:12], UIFontTextStyleCaption1);
    _captionLabel.adjustsFontForContentSizeCategory = YES;
    _captionLabel.textColor = [UIColor ppTextSecondary];
    _captionLabel.text = kLang(@"PaymentMgmt_Field_Workflow");
    _captionLabel.numberOfLines = 0;

    _statusContainer = [UIView new];
    _statusContainer.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_statusContainer, PPCornerSmall);

    _workflowIconView = [UIImageView new];
    _workflowIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _workflowIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_statusContainer addSubview:_workflowIconView];

    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = PPPaymentDetailsScaledFont([Styling fontBold:13], UIFontTextStyleCallout);
    _statusLabel.adjustsFontForContentSizeCategory = YES;
    _statusLabel.numberOfLines = 0;
    [_statusContainer addSubview:_statusLabel];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_actionButton, PPCorner16);
    _actionButton.titleLabel.font = PPPaymentDetailsScaledFont([Styling fontBold:14], UIFontTextStyleCallout);
    _actionButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    _actionButton.titleLabel.numberOfLines = 0;
    _actionButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceBase, PPSpaceMD, PPSpaceBase);
    [_actionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_actionButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = PPPaymentDetailsScaledFont([Styling fontRegular:13], UIFontTextStyleFootnote);
    _subtitleLabel.adjustsFontForContentSizeCategory = YES;
    _subtitleLabel.textColor = [UIColor ppTextSecondary];
    _subtitleLabel.numberOfLines = 0;

    _actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[_statusContainer, _actionButton]];
    _actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    _actionRow.axis = UILayoutConstraintAxisHorizontal;
    _actionRow.alignment = UIStackViewAlignmentCenter;
    _actionRow.spacing = PPSpaceMD;

    UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[_captionLabel, _actionRow, _subtitleLabel]];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = PPSpaceMD;
    [_surfaceView addSubview:contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],

        [contentStack.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceBase],
        [contentStack.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:PPSpaceBase],
        [contentStack.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-PPSpaceBase],
        [contentStack.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceBase],

        [_workflowIconView.leadingAnchor constraintEqualToAnchor:_statusContainer.leadingAnchor constant:PPSpaceSM],
        [_workflowIconView.centerYAnchor constraintEqualToAnchor:_statusContainer.centerYAnchor],
        [_workflowIconView.widthAnchor constraintEqualToConstant:17.0],
        [_workflowIconView.heightAnchor constraintEqualToConstant:17.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_workflowIconView.trailingAnchor constant:PPSpaceSM],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_statusContainer.trailingAnchor constant:-PPSpaceSM],
        [_statusLabel.topAnchor constraintEqualToAnchor:_statusContainer.topAnchor constant:PPSpaceSM],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:_statusContainer.bottomAnchor constant:-PPSpaceSM],
    ]];

    [self pp_refreshAdaptiveLayout];
    return self;
}

- (UIButton *)actionButton
{
    return _actionButton;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self pp_refreshAdaptiveLayout];
}

- (void)pp_refreshAdaptiveLayout
{
    BOOL accessibilitySize = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    _actionRow.axis = accessibilitySize ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    _actionRow.alignment = accessibilitySize ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_actionButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
}

- (void)configureWithStatusTitle:(NSString *)statusTitle
                     statusColor:(UIColor *)statusColor
                     actionTitle:(NSString *)actionTitle
                      actionTint:(UIColor *)actionTint
                        subtitle:(NSString *)subtitle
{
    UISemanticContentAttribute semantic = [Language semanticAttributeForCurrentLanguage];
    NSTextAlignment alignment = [Language alignmentForCurrentLanguage];
    self.semanticContentAttribute = semantic;
    self.contentView.semanticContentAttribute = semantic;
    _surfaceView.semanticContentAttribute = semantic;
    _captionLabel.textAlignment = alignment;
    _statusLabel.textAlignment = alignment;
    _subtitleLabel.textAlignment = alignment;

    UIColor *resolvedStatusColor = statusColor ?: [UIColor ppPrimary];
    UIColor *resolvedActionTint = actionTint ?: [UIColor ppPrimary];
    _statusContainer.backgroundColor = [resolvedStatusColor colorWithAlphaComponent:0.10];
    _statusContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _statusContainer.layer.borderColor = [resolvedStatusColor colorWithAlphaComponent:0.20].CGColor;
    _workflowIconView.tintColor = resolvedStatusColor;
    _workflowIconView.image = [[UIImage systemImageNamed:@"arrowshape.turn.up.right.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _statusLabel.text = statusTitle ?: @"--";
    _statusLabel.textColor = resolvedStatusColor;

    [_actionButton setTitle:actionTitle ?: @"--" forState:UIControlStateNormal];
    _actionButton.backgroundColor = resolvedActionTint;
    _actionButton.accessibilityLabel = actionTitle ?: @"";
    _subtitleLabel.text = subtitle;
    _subtitleLabel.hidden = PPPaymentAdminDetailsTrimmedString(subtitle).length == 0;

    _statusContainer.isAccessibilityElement = YES;
    _statusContainer.accessibilityLabel = statusTitle ?: @"";
    _workflowIconView.accessibilityElementsHidden = YES;
    _statusLabel.isAccessibilityElement = NO;
    [self pp_refreshAdaptiveLayout];
}

@end

@class PPPaymentRequestDetailsViewController;

typedef void (^PPPaymentDetailsUpdateBlock)(PPPaymentAdminRecord *record);

@interface PPPaymentRequestDetailsViewController : UITableViewController

- (instancetype)initWithOrderRecord:(PPPaymentAdminRecord *)orderRecord
                            request:(PPPaymentAdminSupportRequest *)request
                      updateHandler:(PPPaymentDetailsUpdateBlock)updateHandler;

@end

@interface PPPaymentDetailsViewController ()

@property (nonatomic, strong) PPPaymentManagementService *service;
@property (nonatomic, strong) PPFulfillmentService *fulfillmentService;
@property (nonatomic, strong) PPPaymentAdminRecord *record;
@property (nonatomic, strong, nullable) PPFulfillmentRecord *officialFulfillment;
@property (nonatomic, strong, nullable) NSError *officialFulfillmentError;
@property (nonatomic, strong) NSArray<NSNumber *> *visibleSections;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, assign) BOOL isRefreshingRecord;
@property (nonatomic, assign) BOOL officialFulfillmentLoading;
@property (nonatomic, assign) BOOL actionInFlight;

@end

@implementation PPPaymentDetailsViewController

- (instancetype)initWithRecord:(PPPaymentAdminRecord *)record
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _service = [PPPaymentManagementService shared];
        _fulfillmentService = [PPFulfillmentService shared];
        _record = record;
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale currentLocale];
        [_dateFormatter setLocalizedDateFormatFromTemplate:@"d MMM yyyy h:mm a"];
        //self.title = kLang(@"PaymentMgmt_Title_Details");
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
    self.tableView.estimatedRowHeight = 74.0;

    self.refreshControl = [UIRefreshControl new];
    self.refreshControl.tintColor = [UIColor ppPrimary];
    [self.refreshControl addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventValueChanged];

    [self pp_setupDossierHeader];
    [self pp_rebuildSections];
    [self pp_reloadRecordShowHUD:YES];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (!self.tableView.tableHeaderView) return;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;
    CGSize fitting = [self.tableView.tableHeaderView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame = self.tableView.tableHeaderView.frame;
    CGFloat targetHeight = MAX(fitting.height, 104.0);
    if (fabs(frame.size.width - width) > 0.5 || fabs(frame.size.height - targetHeight) > 0.5) {
        frame.size.width = width;
        frame.size.height = targetHeight;
        self.tableView.tableHeaderView.frame = frame;
        self.tableView.tableHeaderView = self.tableView.tableHeaderView;
    }
}

- (void)pp_onBackTapped
{
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)pp_setupDossierHeader
{
    CGFloat horizontal = PPScreenMargin;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;

    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 110.0)];
    headerContainer.backgroundColor = UIColor.clearColor;

    // 1. Navigation Top Bar (Back Button + Refresh Button)
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *backConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    UIImage *chevronImg = [UIImage systemImageNamed:[Language isRTL] ? @"chevron.right" : @"chevron.left" withConfiguration:backConfig];
    [backBtn setImage:chevronImg forState:UIControlStateNormal];
    [backBtn setTitle:[NSString stringWithFormat:@" %@", kLang(@"Back")] forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor ppPrimary] forState:UIControlStateNormal];
    backBtn.tintColor = [UIColor ppPrimary];
    backBtn.titleLabel.font = [Styling fontBold:15];
    [backBtn addTarget:self action:@selector(pp_onBackTapped) forControlEvents:UIControlEventTouchUpInside];
    [headerContainer addSubview:backBtn];

    UIButton *refreshBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    refreshBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *refreshConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [refreshBtn setImage:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:refreshConfig] forState:UIControlStateNormal];
    refreshBtn.tintColor = [UIColor ppPrimary];
    refreshBtn.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    refreshBtn.layer.cornerRadius = 18.0;
    refreshBtn.layer.masksToBounds = YES;
    [refreshBtn addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventTouchUpInside];
    [headerContainer addSubview:refreshBtn];

    // 2. Eyebrow Category Breadcrumb
    UILabel *eyebrowLabel = [UILabel new];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [Styling fontRegular:12];
    eyebrowLabel.textColor = [UIColor ppTextSecondary];
    eyebrowLabel.text = [NSString stringWithFormat:@"%@ / %@", kLang(@"CommandCenter_Work_Workspace"), kLang(@"PaymentMgmt_Title_Details")];
    eyebrowLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [headerContainer addSubview:eyebrowLabel];

    // 3. Dossier Large Title (Order ID)
    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:22];
    titleLabel.textColor = [UIColor ppTextPrimary];
    NSString *orderId = self.record.orderId ?: @"";
    titleLabel.text = [orderId hasPrefix:@"#"] ? orderId : [NSString stringWithFormat:@"#%@", orderId];
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [headerContainer addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        // Back Button & Refresh Button
        [backBtn.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:4],
        [backBtn.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [backBtn.heightAnchor constraintGreaterThanOrEqualToConstant:44],

        [refreshBtn.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
        [refreshBtn.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],
        [refreshBtn.widthAnchor constraintEqualToConstant:36],
        [refreshBtn.heightAnchor constraintEqualToConstant:36],

        // Eyebrow
        [eyebrowLabel.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:2],
        [eyebrowLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [eyebrowLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],

        // Title
        [titleLabel.topAnchor constraintEqualToAnchor:eyebrowLabel.bottomAnchor constant:2],
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerContainer.bottomAnchor constant:-8]
    ]];

    self.tableView.tableHeaderView = headerContainer;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    UIButton *refresh = [self pp_ButtonWithSystemName:@"arrow.clockwise" action:@selector(onRefresh)];
    [self pp_navBarWithOtherButton:refresh title:kLang(@"PaymentMgmt_Title_Details")];
}

- (void)onRefresh
{
    [self pp_reloadRecordShowHUD:NO];
}

- (void)pp_reloadRecordShowHUD:(BOOL)showHUD
{
    if (self.isRefreshingRecord) return;
    self.isRefreshingRecord = YES;
    if (showHUD && !self.refreshControl.isRefreshing) {
        [PPHUD showIndeterminateIn:self.view title:kLang(@"Loading") subtitle:kLang(@"PaymentMgmt_Loading_PaymentDetails")];
    }

    __weak typeof(self) weakSelf = self;
    [self.service loadFullRecordForOrderID:self.record.orderId completion:^(PPPaymentAdminRecord * _Nullable record, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        self.isRefreshingRecord = NO;
        [PPHUD dismiss];
        [self.refreshControl endRefreshing];

        if (error) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_LoadPaymentDetails")];
            return;
        }

        if (record) {
            self.record = record;
            [self pp_reloadOfficialFulfillment];
        }
    }];
}

- (void)pp_reloadOfficialFulfillment
{
    self.officialFulfillment = nil;
    self.officialFulfillmentError = nil;
    self.officialFulfillmentLoading = (self.record.fulfillmentVersion == 1);
    [self pp_rebuildSections];
    [self.tableView reloadData];
    if (self.record.fulfillmentVersion != 1) return;

    NSString *parentOrderID = self.record.orderId ?: @"";
    NSArray<NSString *> *fulfillmentIDs = self.record.fulfillmentOrderIDs ?: @[];
    __weak typeof(self) weakSelf = self;
    [self.fulfillmentService fetchOfficialFulfillmentForParentOrderID:parentOrderID
                                                       fulfillmentIDs:fulfillmentIDs
                                                           completion:^(PPFulfillmentRecord * _Nullable record, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self.record.orderId isEqualToString:parentOrderID]) return;
        self.officialFulfillmentLoading = NO;
        self.officialFulfillment = record;
        self.officialFulfillmentError = error;
        [self pp_rebuildSections];
        [self.tableView reloadData];
    }];
}

- (void)pp_rebuildSections
{
    NSMutableArray<NSNumber *> *sections = [NSMutableArray array];
    if ([self pp_defaultNextOrderAction] != nil) {
        [sections addObject:@(PPPaymentDetailsSectionNextStep)];
    }
    [sections addObject:@(PPPaymentDetailsSectionOverview)];
    if ([self pp_orderActions].count > 0) {
        [sections addObject:@(PPPaymentDetailsSectionActions)];
    }
    [sections addObject:@(PPPaymentDetailsSectionItems)];
    if (self.record.requests.count > 0) {
        [sections addObject:@(PPPaymentDetailsSectionRequests)];
    }
    [sections addObject:@(PPPaymentDetailsSectionTimeline)];
    [sections addObject:@(PPPaymentDetailsSectionAudit)];
    self.visibleSections = sections.copy;
}

- (PPPaymentDetailsSection)pp_sectionTypeForIndex:(NSInteger)section
{
    return (PPPaymentDetailsSection)[self.visibleSections[section] integerValue];
}

- (NSArray<NSDictionary *> *)pp_overviewRows
{
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    NSString *workflowStatus = [self.record workflowStatusKey];
    NSString *customerName = PPPaymentAdminDetailsTrimmedString(self.record.userDisplayName);
    NSString *customerEmail = PPPaymentAdminDetailsTrimmedString(self.record.userEmail);
    NSString *paymentMethod = PPPaymentAdminDetailsTrimmedString(self.record.paymentProvider);
    if (paymentMethod.length == 0) paymentMethod = PPPaymentAdminDetailsTrimmedString(self.record.paymentTypeKey);
    NSString *paymentStatus = PPPaymentAdminDetailsTrimmedString(self.record.paymentStatus);
    NSString *transactionID = PPPaymentAdminDetailsTrimmedString(self.record.transactionId);
    NSString *verification = PPPaymentAdminDetailsTrimmedString(self.record.verificationStatus);
    NSString *shippingAddress = [self pp_shippingAddressText];
    NSString *orderReference = PPPaymentAdminDetailsTrimmedString([self.record displayOrderReference]);

    if (orderReference.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_OrderReference"), @"detail": orderReference}];
    }
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Workflow"), @"detail": PPPaymentAdminDisplayTitleForWorkflowStatus(workflowStatus), @"tint": PPPaymentAdminDetailsStatusColor(workflowStatus)}];
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_OrderStatus"), @"detail": PPPaymentAdminDisplayTitleForOrderStatus(self.record.rawStatus.length > 0 ? self.record.rawStatus : @"pending")}];
    if (self.record.fulfillmentVersion == 1) {
        NSString *fulfillmentDetail = nil;
        UIColor *fulfillmentTint = [UIColor ppTextSecondary];
        if (self.officialFulfillmentLoading) {
            fulfillmentDetail = kLang(@"PaymentMgmt_OfficialFulfillment_Loading");
        } else if (self.officialFulfillmentError) {
            fulfillmentDetail = self.officialFulfillmentError.localizedDescription ?: kLang(@"PaymentMgmt_OfficialFulfillment_Error");
            fulfillmentTint = [UIColor ppError];
        } else if (!self.officialFulfillment) {
            fulfillmentDetail = kLang(@"PaymentMgmt_OfficialFulfillment_None");
        } else {
            fulfillmentDetail = [NSString stringWithFormat:@"%@ • %@",
                                 PPPaymentAdminDisplayTitleForOrderStatus(self.officialFulfillment.status),
                                 self.officialFulfillment.fulfillmentID];
            fulfillmentTint = PPPaymentAdminDetailsStatusColor(self.officialFulfillment.status);
        }
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_OfficialFulfillment_Title"),
                          @"detail": fulfillmentDetail ?: @"--",
                          @"tint": fulfillmentTint,
                          @"multiline": @YES}];
    }
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Customer"), @"detail": customerName.length > 0 ? customerName : (self.record.userId.length > 0 ? self.record.userId : kLang(@"PaymentMgmt_Value_Unknown"))}];
    if (customerEmail.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Email"), @"detail": customerEmail}];
    }
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Total"), @"detail": PPPaymentAdminDetailsCurrencyTitle(self.record)}];
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_PaymentMethod"), @"detail": paymentMethod.length > 0 ? PPPaymentAdminDisplayTitleForPaymentMethod(paymentMethod) : kLang(@"PaymentMgmt_Value_Unknown")}];
    if (paymentStatus.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_PaymentStatus"), @"detail": PPPaymentAdminDisplayTitleForOrderStatus(paymentStatus)}];
    }
    if (verification.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Verification"), @"detail": PPPaymentAdminDisplayTitleForVerificationStatus(verification)}];
    }
    if (transactionID.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Transaction"), @"detail": transactionID}];
    }
    if (self.record.failureReason.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_FailureReason"), @"detail": PPPaymentAdminDisplayTitleForFailureReason(self.record.failureReason)}];
    }
    if (self.record.refundStatus.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_RefundStatus"), @"detail": PPPaymentAdminDisplayTitleForRequestStatus(self.record.refundStatus)}];
    }
    if (self.record.returnStatus.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_ReturnStatus"), @"detail": PPPaymentAdminDisplayTitleForOrderStatus(self.record.returnStatus)}];
    }
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Created"), @"detail": [self pp_dateString:self.record.createdAt]}];
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Updated"), @"detail": [self pp_dateString:self.record.updatedAt]}];
    if (self.record.paidAt) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_PaidAt"), @"detail": [self pp_dateString:self.record.paidAt]}];
    }
    if (self.record.processedAt) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_ProcessedAt"), @"detail": [self pp_dateString:self.record.processedAt]}];
    }
    if (self.record.shippedAt) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_ShippedAt"), @"detail": [self pp_dateString:self.record.shippedAt]}];
    }
    if (self.record.deliveredAt) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_DeliveredAt"), @"detail": [self pp_dateString:self.record.deliveredAt]}];
    }
    if (self.record.paymentCollectedAt) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_PaymentCollectedAt"), @"detail": [self pp_dateString:self.record.paymentCollectedAt]}];
    }
    if (shippingAddress.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Shipping"), @"detail": shippingAddress, @"multiline": @YES}];
    }
    return rows.copy;
}

- (NSArray<NSDictionary *> *)pp_orderActions
{
    if (![self.service currentAdminCanManagePayments]) return @[];
    if (self.record.fulfillmentVersion == 1) {
        if (self.officialFulfillmentLoading || self.officialFulfillmentError || !self.officialFulfillment) return @[];
        NSDictionary<NSString *, NSDictionary *> *presentation = @{
            @"accept": @{@"type": @(PPPaymentOrderAdminActionTypeOfficialAccept), @"title": kLang(@"PaymentMgmt_OfficialFulfillment_Action_Accept"), @"tint": [UIColor ppSuccess]},
            @"reject": @{@"type": @(PPPaymentOrderAdminActionTypeOfficialReject), @"title": kLang(@"PaymentMgmt_OfficialFulfillment_Action_Reject"), @"tint": [UIColor ppError]},
            @"start_preparing": @{@"type": @(PPPaymentOrderAdminActionTypeOfficialStartPreparing), @"title": kLang(@"PaymentMgmt_OfficialFulfillment_Action_StartPreparing"), @"tint": [UIColor ppInfo]},
            @"mark_ready": @{@"type": @(PPPaymentOrderAdminActionTypeOfficialMarkReady), @"title": kLang(@"PaymentMgmt_OfficialFulfillment_Action_MarkReady"), @"tint": [UIColor ppSuccess]},
            @"request_delivery": @{@"type": @(PPPaymentOrderAdminActionTypeOfficialRequestDelivery), @"title": kLang(@"PaymentMgmt_OfficialFulfillment_Action_RequestDelivery"), @"tint": [UIColor ppQuickActionCommunity]},
            @"confirm_handover": @{@"type": @(PPPaymentOrderAdminActionTypeOfficialConfirmHandover), @"title": kLang(@"PaymentMgmt_OfficialFulfillment_Action_ConfirmHandover"), @"tint": [UIColor ppInfo]},
            @"cancel_request": @{@"type": @(PPPaymentOrderAdminActionTypeOfficialCancel), @"title": kLang(@"PaymentMgmt_OfficialFulfillment_Action_Cancel"), @"tint": [UIColor ppError]},
        };
        NSMutableArray<NSDictionary *> *officialRows = [NSMutableArray array];
        for (NSString *action in [PPFulfillmentService availableOfficialActionsForStatus:self.officialFulfillment.status]) {
            NSDictionary *base = presentation[action];
            if (!base) continue;
            NSMutableDictionary *row = base.mutableCopy;
            row[@"fulfillmentAction"] = action;
            row[@"subtitle"] = kLang(@"PaymentMgmt_OfficialFulfillment_Action_Subtitle");
            [officialRows addObject:row.copy];
        }
        return officialRows.copy;
    }
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    if ([PPPaymentAdminRecord canApproveOrderStatus:self.record.rawStatus] &&
        ![[PPPaymentAdminRecord normalizedStatusString:self.record.paymentMethodId] isEqualToString:@"cash"]) {
        [rows addObject:@{
            @"type": @(PPPaymentOrderAdminActionTypeApprove),
            @"title": kLang(@"PaymentMgmt_Action_ApprovePayment_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_ApprovePayment_Subtitle"),
            @"tint": [UIColor ppSuccess],
        }];
    }
    if ([PPPaymentAdminRecord canMarkOrderProcessingForOrder:self.record]) {
        [rows addObject:@{
            @"type": @(PPPaymentOrderAdminActionTypeProcessing),
            @"title": kLang(@"PaymentMgmt_Action_MarkProcessing_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_MarkProcessing_Subtitle"),
            @"tint": [UIColor ppInfo],
        }];
    }
    if ([PPPaymentAdminRecord canMarkOrderShippedStatus:self.record.rawStatus]) {
        [rows addObject:@{
            @"type": @(PPPaymentOrderAdminActionTypeShipped),
            @"title": kLang(@"PaymentMgmt_Action_MarkShipped_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_MarkShipped_Subtitle"),
            @"tint": [UIColor ppQuickActionCommunity],
        }];
    }
    if ([PPPaymentAdminRecord canMarkOrderDeliveredStatus:self.record.rawStatus]) {
        [rows addObject:@{
            @"type": @(PPPaymentOrderAdminActionTypeDelivered),
            @"title": kLang(@"PaymentMgmt_Action_MarkDelivered_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_MarkDelivered_Subtitle"),
            @"tint": [UIColor ppQuickActionServices],
        }];
    }
    if ([PPPaymentAdminRecord canCollectCashPaymentForOrder:self.record]) {
        [rows addObject:@{
            @"type": @(PPPaymentOrderAdminActionTypeCollectPayment),
            @"title": kLang(@"PaymentMgmt_Action_CollectPayment_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_CollectPayment_Subtitle"),
            @"tint": [UIColor ppSuccess],
        }];
    }
    if ([PPPaymentAdminRecord canCancelOrderStatus:self.record.rawStatus]) {
        [rows addObject:@{
            @"type": @(PPPaymentOrderAdminActionTypeCancel),
            @"title": kLang(@"PaymentMgmt_Action_CancelOrder_Title"),
            @"subtitle": kLang(@"PaymentMgmt_Action_CancelOrder_Subtitle"),
            @"tint": [UIColor ppError],
        }];
    }
    return rows.copy;
}

- (NSDictionary *)pp_defaultNextOrderAction
{
    for (NSDictionary *row in [self pp_orderActions]) {
        PPPaymentOrderAdminActionType type = [row[@"type"] integerValue];
        if (type != PPPaymentOrderAdminActionTypeCancel) {
            return row;
        }
    }
    return nil;
}

- (NSString *)pp_shippingAddressText
{
    NSDictionary *snapshot = self.record.shippingAddressSnapshot ?: @{};
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSString *name = PPPaymentAdminDetailsFirstNonEmpty(snapshot, @[@"fullName", @"displayName", @"locatioName", @"name"]);
    if (name.length > 0) [lines addObject:name];

    NSString *line1 = PPPaymentAdminDetailsFirstNonEmpty(snapshot, @[@"addressLine1", @"line1"]);
    NSString *line2 = PPPaymentAdminDetailsFirstNonEmpty(snapshot, @[@"addressLine2", @"line2"]);
    NSString *city = PPPaymentAdminDetailsFirstNonEmpty(snapshot, @[@"cityName", @"city"]);
    NSString *country = PPPaymentAdminDetailsFirstNonEmpty(snapshot, @[@"countryName", @"country"]);
    NSString *phone = PPPaymentAdminDetailsFirstNonEmpty(snapshot, @[@"phoneNumber", @"phone"]);

    NSMutableArray<NSString *> *locationParts = [NSMutableArray array];
    if (line1.length > 0) [locationParts addObject:line1];
    if (line2.length > 0) [locationParts addObject:line2];
    if (city.length > 0) [locationParts addObject:city];
    if (country.length > 0) [locationParts addObject:country];
    if (locationParts.count > 0) [lines addObject:[locationParts componentsJoinedByString:@", "]];
    if (phone.length > 0) [lines addObject:phone];

    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)pp_dateString:(NSDate *)date
{
    if (![date isKindOfClass:NSDate.class]) return @"--";
    return [self.dateFormatter stringFromDate:date];
}

- (UITableViewCell *)pp_valueCellForTableView:(UITableView *)tableView
{
    static NSString *cellID = @"PPPaymentValueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
        cell.textLabel.font = [Styling fontMedium:14];
        cell.detailTextLabel.font = [Styling fontRegular:14];
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    PPPaymentAdminApplyLanguageToTableCell(cell);
    return cell;
}

- (UITableViewCell *)pp_subtitleCellForTableView:(UITableView *)tableView reuseIdentifier:(NSString *)reuseIdentifier
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
        cell.textLabel.font = PPPaymentDetailsScaledFont([Styling fontBold:15], UIFontTextStyleHeadline);
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.font = PPPaymentDetailsScaledFont([Styling fontRegular:13], UIFontTextStyleSubheadline);
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.numberOfLines = 0;
    }
    PPPaymentAdminApplyLanguageToTableCell(cell);
    return cell;
}

- (UITableViewCell *)pp_placeholderCellForTableView:(UITableView *)tableView
                                              title:(NSString *)title
                                           subtitle:(NSString *)subtitle
{
    UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentPlaceholderCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = title;
    cell.detailTextLabel.text = subtitle;
    cell.imageView.image = [UIImage systemImageNamed:@"tray"];
    cell.imageView.tintColor = [UIColor ppTextSecondary];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    switch ([self pp_sectionTypeForIndex:section]) {
        case PPPaymentDetailsSectionOverview:
            return [self pp_overviewRows].count;
        case PPPaymentDetailsSectionNextStep:
            return 1;
        case PPPaymentDetailsSectionActions:
            return [self pp_orderActions].count;
        case PPPaymentDetailsSectionItems:
            return MAX(1, self.record.items.count);
        case PPPaymentDetailsSectionRequests:
            return MAX(1, self.record.requests.count);
        case PPPaymentDetailsSectionTimeline:
            return MAX(1, self.record.timelineEvents.count);
        case PPPaymentDetailsSectionAudit:
            return MAX(1, self.record.auditEntries.count);
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    switch ([self pp_sectionTypeForIndex:section]) {
        case PPPaymentDetailsSectionOverview: return kLang(@"PaymentMgmt_Section_Overview");
        case PPPaymentDetailsSectionNextStep: return nil;
        case PPPaymentDetailsSectionActions: return kLang(@"PaymentMgmt_Section_AdminActions");
        case PPPaymentDetailsSectionItems: return kLang(@"PaymentMgmt_Section_Items");
        case PPPaymentDetailsSectionRequests: return kLang(@"PaymentMgmt_Section_Requests");
        case PPPaymentDetailsSectionTimeline: return kLang(@"PaymentMgmt_Section_Timeline");
        case PPPaymentDetailsSectionAudit: return kLang(@"PaymentMgmt_Section_Audit");
    }
    return @"";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    if ([self pp_sectionTypeForIndex:section] == PPPaymentDetailsSectionNextStep) {
        return CGFLOAT_MIN;
    }
    return UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    (void)tableView;
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    if ([self pp_sectionTypeForIndex:section] == PPPaymentDetailsSectionNextStep) return;

    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = PPPaymentDetailsScaledFont([Styling fontMedium:14], UIFontTextStyleHeadline);
    header.textLabel.adjustsFontForContentSizeCategory = YES;
    header.textLabel.textColor = [UIColor ppTextSecondary];
    header.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
    header.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
}

- (UITableViewCell *)pp_nextStepCellForTableView:(UITableView *)tableView
{
    static NSString *cellID = @"PPPaymentNextStepCell";
    PPPaymentNextStepCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (![cell isKindOfClass:PPPaymentNextStepCell.class]) {
        cell = [[PPPaymentNextStepCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
    }

    NSDictionary *row = [self pp_defaultNextOrderAction];
    NSString *workflowStatus = [self.record workflowStatusKey];
    [cell configureWithStatusTitle:PPPaymentAdminDisplayTitleForWorkflowStatus(workflowStatus)
                       statusColor:PPPaymentAdminDetailsStatusColor(workflowStatus)
                       actionTitle:row[@"title"]
                        actionTint:row[@"tint"]
                          subtitle:row[@"subtitle"]];
    [cell.actionButton addTarget:self action:@selector(pp_nextStepButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PPPaymentDetailsSection sectionType = [self pp_sectionTypeForIndex:indexPath.section];
    switch (sectionType) {
        case PPPaymentDetailsSectionOverview: {
            UITableViewCell *cell = [self pp_valueCellForTableView:tableView];
            NSDictionary *row = [self pp_overviewRows][indexPath.row];
            cell.textLabel.text = row[@"title"];
            cell.detailTextLabel.text = row[@"detail"];
            cell.detailTextLabel.textColor = row[@"tint"] ?: [UIColor ppTextSecondary];
            cell.detailTextLabel.font = [row[@"multiline"] boolValue] ? [Styling fontRegular:13] : [Styling fontMedium:14];
            return cell;
        }

        case PPPaymentDetailsSectionNextStep:
            return [self pp_nextStepCellForTableView:tableView];

        case PPPaymentDetailsSectionActions: {
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentActionCell"];
            NSDictionary *row = [self pp_orderActions][indexPath.row];
            cell.textLabel.text = row[@"title"];
            cell.textLabel.textColor = row[@"tint"] ?: [UIColor ppTextPrimary];
            cell.detailTextLabel.text = row[@"subtitle"];
            cell.detailTextLabel.textColor = [UIColor ppTextSecondary];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.imageView.image = [UIImage systemImageNamed:@"shield.lefthalf.filled"];
            cell.imageView.tintColor = row[@"tint"] ?: AppPrimaryClr;
            return cell;
        }

        case PPPaymentDetailsSectionItems: {
            if (self.record.items.count == 0) {
                return [self pp_placeholderCellForTableView:tableView
                                                      title:kLang(@"PaymentMgmt_Placeholder_NoItemsTitle")
                                                   subtitle:kLang(@"PaymentMgmt_Placeholder_NoItemsSubtitle")];
            }
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentItemCell"];
            NSDictionary *item = [self.record.items[indexPath.row] isKindOfClass:NSDictionary.class] ? self.record.items[indexPath.row] : @{};
            NSString *title = PPPaymentAdminDetailsFirstNonEmpty(item, @[@"name", @"title"]);
            if (title.length == 0) title = PPPaymentAdminDetailsFirstNonEmpty(item, @[@"id", @"itemID"]);
            NSInteger qty = [item[@"qty"] ?: item[@"quantity"] integerValue];
            double price = [item[@"price"] respondsToSelector:@selector(doubleValue)] ? [item[@"price"] doubleValue] : 0.0;
            cell.textLabel.text = title.length > 0 ? title : kLang(@"PaymentMgmt_Value_StoreItem");
            NSMutableArray<NSString *> *details = [NSMutableArray array];
            [details addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Item_Qty_Format"), (long)MAX(1, qty)]];
            if (price > 0.0) {
                [details addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Item_UnitPrice_Format"), price]];
            }
            NSString *itemID = PPPaymentAdminDetailsFirstNonEmpty(item, @[@"id", @"itemID"]);
            if (itemID.length > 0) {
                [details addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Item_Id_Format"), itemID]];
            }
            cell.detailTextLabel.text = [details componentsJoinedByString:@" • "];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.imageView.image = [UIImage systemImageNamed:@"cube.box"];
            cell.imageView.tintColor = [UIColor ppPrimary];
            return cell;
        }

        case PPPaymentDetailsSectionRequests: {
            if (self.record.requests.count == 0) {
                return [self pp_placeholderCellForTableView:tableView
                                                      title:kLang(@"PaymentMgmt_Placeholder_NoRequestsTitle")
                                                   subtitle:kLang(@"PaymentMgmt_Placeholder_NoRequestsSubtitle")];
            }
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentRequestCell"];
            PPPaymentAdminSupportRequest *request = self.record.requests[indexPath.row];
            NSString *statusTitle = PPPaymentAdminDisplayTitleForRequestStatus(request.status);
            NSString *reason = request.reasonTitle.length > 0 ? request.reasonTitle : request.subject;
            NSMutableArray<NSString *> *details = [NSMutableArray array];
            [details addObject:statusTitle];
            if (reason.length > 0) [details addObject:reason];
            if (request.updatedAt) [details addObject:[self pp_dateString:request.updatedAt]];
            cell.textLabel.text = PPPaymentAdminDisplayTitleForRequestType(request.type);
            cell.textLabel.textColor = PPPaymentAdminDetailsStatusColor([request effectiveResolutionKey]);
            cell.detailTextLabel.text = [details componentsJoinedByString:@"\n"];
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.uturn.backward.circle"];
            cell.imageView.tintColor = PPPaymentAdminDetailsStatusColor([request effectiveResolutionKey]);
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        case PPPaymentDetailsSectionTimeline: {
            if (self.record.timelineEvents.count == 0) {
                return [self pp_placeholderCellForTableView:tableView
                                                      title:kLang(@"PaymentMgmt_Placeholder_NoTimelineTitle")
                                                   subtitle:kLang(@"PaymentMgmt_Placeholder_NoTimelineSubtitle")];
            }
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentTimelineCell"];
            PPPaymentAdminTimelineEvent *event = self.record.timelineEvents[indexPath.row];
            NSString *summary = PPPaymentAdminDisplayTitleForTimelineSummary(event);
            NSString *status = PPPaymentAdminDisplayTitleForWorkflowStatus(event.status);
            if ([event.status containsString:@"review"] || [event.status containsString:@"approved"] || [event.status containsString:@"rejected"]) {
                status = PPPaymentAdminDisplayTitleForRequestStatus(event.status);
            }
            cell.textLabel.text = summary;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@ • %@", status, PPPaymentAdminDisplayTitleForActorType(event.actorType.length > 0 ? event.actorType : @"system"), [self pp_dateString:event.createdAt]];
            cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
            cell.imageView.tintColor = PPPaymentAdminDetailsStatusColor(event.status);
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        case PPPaymentDetailsSectionAudit: {
            if (self.record.auditEntries.count == 0) {
                return [self pp_placeholderCellForTableView:tableView
                                                      title:kLang(self.record.auditEvidenceRestricted ? @"PaymentMgmt_Audit_ScopeRestricted_Title" : @"PaymentMgmt_Placeholder_NoAuditTitle")
                                                   subtitle:kLang(self.record.auditEvidenceRestricted ? @"PaymentMgmt_Audit_ScopeRestricted_Subtitle" : @"PaymentMgmt_Placeholder_NoAuditSubtitle")];
            }
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentAuditCell"];
            PPPaymentAdminAuditEntry *entry = self.record.auditEntries[indexPath.row];
            NSString *adminName = entry.adminName.length > 0 ? entry.adminName : kLang(@"Admin");
            NSMutableArray<NSString *> *details = [NSMutableArray array];
            [details addObject:[NSString stringWithFormat:@"%@ • %@", adminName, [self pp_dateString:entry.createdAt]]];
            if (entry.note.length > 0) [details addObject:entry.note];
            NSString *beforeStatus = PPPaymentAdminDetailsTrimmedString(entry.beforeState[@"status"]);
            NSString *afterStatus = PPPaymentAdminDetailsTrimmedString(entry.afterState[@"status"]);
            if (beforeStatus.length > 0 || afterStatus.length > 0) {
                NSString *beforeTitle = [entry.entityType isEqualToString:@"request"] ? PPPaymentAdminDisplayTitleForRequestStatus(beforeStatus) : PPPaymentAdminDisplayTitleForOrderStatus(beforeStatus);
                NSString *afterTitle = [entry.entityType isEqualToString:@"request"] ? PPPaymentAdminDisplayTitleForRequestStatus(afterStatus) : PPPaymentAdminDisplayTitleForOrderStatus(afterStatus);
                [details addObject:[NSString stringWithFormat:kLang(@"PaymentMgmt_Audit_StatusTransition_Format"),
                                    beforeStatus.length > 0 ? beforeTitle : @"--",
                                    afterStatus.length > 0 ? afterTitle : @"--"]];
            }
            cell.textLabel.text = PPPaymentAdminDisplayTitleForAuditAction(entry.action.length > 0 ? entry.action : @"payment_update");
            cell.detailTextLabel.text = [details componentsJoinedByString:@"\n"];
            cell.imageView.image = [UIImage systemImageNamed:@"person.text.rectangle"];
            cell.imageView.tintColor = [UIColor ppQuickActionCommunity];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
    }

    return [UITableViewCell new];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PPPaymentDetailsSection sectionType = [self pp_sectionTypeForIndex:indexPath.section];
    if (sectionType == PPPaymentDetailsSectionNextStep) {
        [self pp_nextStepButtonTapped];
        return;
    }
    if (sectionType == PPPaymentDetailsSectionActions) {
        NSDictionary *row = [self pp_orderActions][indexPath.row];
        [self pp_handleOrderAction:[row[@"type"] integerValue]];
        return;
    }

    if (sectionType == PPPaymentDetailsSectionRequests && self.record.requests.count > 0) {
        PPPaymentAdminSupportRequest *request = self.record.requests[indexPath.row];
        __weak typeof(self) weakSelf = self;
        PPPaymentRequestDetailsViewController *details = [[PPPaymentRequestDetailsViewController alloc] initWithOrderRecord:self.record
                                                                                                                     request:request
                                                                                                               updateHandler:^(PPPaymentAdminRecord *updatedRecord) {
            __strong typeof(weakSelf) self = weakSelf;
            self.record = updatedRecord;
            [self pp_rebuildSections];
            [self.tableView reloadData];
        }];
        [self.navigationController pushViewController:details animated:YES];
    }
}

- (void)pp_nextStepButtonTapped
{
    NSDictionary *row = [self pp_defaultNextOrderAction];
    if (row == nil) return;
    [self pp_handleOrderAction:[row[@"type"] integerValue]];
}

- (NSString *)pp_titleForOrderAction:(PPPaymentOrderAdminActionType)actionType
{
    switch (actionType) {
        case PPPaymentOrderAdminActionTypeApprove: return kLang(@"PaymentMgmt_Action_ApprovePayment_Title");
        case PPPaymentOrderAdminActionTypeProcessing: return kLang(@"PaymentMgmt_Action_MarkProcessing_Title");
        case PPPaymentOrderAdminActionTypeShipped: return kLang(@"PaymentMgmt_Action_MarkShipped_Title");
        case PPPaymentOrderAdminActionTypeDelivered: return kLang(@"PaymentMgmt_Action_MarkDelivered_Title");
        case PPPaymentOrderAdminActionTypeCollectPayment: return kLang(@"PaymentMgmt_Action_CollectPayment_Title");
        case PPPaymentOrderAdminActionTypeCancel: return kLang(@"PaymentMgmt_Action_CancelOrder_Title");
        case PPPaymentOrderAdminActionTypeOfficialAccept: return kLang(@"PaymentMgmt_OfficialFulfillment_Action_Accept");
        case PPPaymentOrderAdminActionTypeOfficialReject: return kLang(@"PaymentMgmt_OfficialFulfillment_Action_Reject");
        case PPPaymentOrderAdminActionTypeOfficialStartPreparing: return kLang(@"PaymentMgmt_OfficialFulfillment_Action_StartPreparing");
        case PPPaymentOrderAdminActionTypeOfficialMarkReady: return kLang(@"PaymentMgmt_OfficialFulfillment_Action_MarkReady");
        case PPPaymentOrderAdminActionTypeOfficialRequestDelivery: return kLang(@"PaymentMgmt_OfficialFulfillment_Action_RequestDelivery");
        case PPPaymentOrderAdminActionTypeOfficialConfirmHandover: return kLang(@"PaymentMgmt_OfficialFulfillment_Action_ConfirmHandover");
        case PPPaymentOrderAdminActionTypeOfficialCancel: return kLang(@"PaymentMgmt_OfficialFulfillment_Action_Cancel");
    }
    return kLang(@"PaymentMgmt_Action_UpdateRequest_Title");
}

- (NSString *)pp_nextWorkflowStatusForOrderAction:(PPPaymentOrderAdminActionType)actionType
{
    switch (actionType) {
        case PPPaymentOrderAdminActionTypeApprove:
            return @"paid";
        case PPPaymentOrderAdminActionTypeProcessing:
            return @"processing";
        case PPPaymentOrderAdminActionTypeShipped:
            return @"shipped";
        case PPPaymentOrderAdminActionTypeDelivered:
            return @"delivered";
        case PPPaymentOrderAdminActionTypeCollectPayment:
            return [self.record workflowStatusKey];
        case PPPaymentOrderAdminActionTypeCancel:
            return @"cancelled";
        case PPPaymentOrderAdminActionTypeOfficialAccept:
        case PPPaymentOrderAdminActionTypeOfficialReject:
        case PPPaymentOrderAdminActionTypeOfficialStartPreparing:
        case PPPaymentOrderAdminActionTypeOfficialMarkReady:
        case PPPaymentOrderAdminActionTypeOfficialRequestDelivery:
        case PPPaymentOrderAdminActionTypeOfficialConfirmHandover:
        case PPPaymentOrderAdminActionTypeOfficialCancel:
            return [self.record workflowStatusKey];
    }
    return [self.record workflowStatusKey];
}

- (NSString *)pp_callableActionForOrderAction:(PPPaymentOrderAdminActionType)actionType
{
    switch (actionType) {
        case PPPaymentOrderAdminActionTypeApprove: return @"order_approve";
        case PPPaymentOrderAdminActionTypeProcessing: return @"order_mark_processing";
        case PPPaymentOrderAdminActionTypeShipped: return @"order_mark_shipped";
        case PPPaymentOrderAdminActionTypeDelivered: return @"order_mark_delivered";
        case PPPaymentOrderAdminActionTypeCollectPayment: return @"order_collect_payment";
        case PPPaymentOrderAdminActionTypeCancel: return @"order_cancel";
        case PPPaymentOrderAdminActionTypeOfficialAccept: return @"accept";
        case PPPaymentOrderAdminActionTypeOfficialReject: return @"reject";
        case PPPaymentOrderAdminActionTypeOfficialStartPreparing: return @"start_preparing";
        case PPPaymentOrderAdminActionTypeOfficialMarkReady: return @"mark_ready";
        case PPPaymentOrderAdminActionTypeOfficialRequestDelivery: return @"request_delivery";
        case PPPaymentOrderAdminActionTypeOfficialConfirmHandover: return @"confirm_handover";
        case PPPaymentOrderAdminActionTypeOfficialCancel: return @"cancel_request";
    }
    return @"";
}

- (NSString *)pp_resolvedAdminNoteForOrderAction:(PPPaymentOrderAdminActionType)actionType
                                    userNote:(NSString *)userNote
{
    NSString *trimmedUserNote = PPPaymentAdminDetailsTrimmedString(userNote);
    if (trimmedUserNote.length > 0) {
        return trimmedUserNote;
    }

    if (self.record.fulfillmentVersion == 1) {
        return [NSString stringWithFormat:kLang(@"PaymentMgmt_OfficialFulfillment_DefaultNote"),
                [self pp_titleForOrderAction:actionType]];
    }

    return [self.service defaultAdminNoteForOrderID:self.record.orderId
                                              action:[self pp_callableActionForOrderAction:actionType]];
}

- (NSString *)pp_promptSubtitleForOrderAction:(PPPaymentOrderAdminActionType)actionType
{
    switch (actionType) {
        case PPPaymentOrderAdminActionTypeApprove: return kLang(@"PaymentMgmt_Prompt_OrderApproveNote");
        case PPPaymentOrderAdminActionTypeProcessing: return kLang(@"PaymentMgmt_Prompt_OrderProcessingNote");
        case PPPaymentOrderAdminActionTypeShipped: return kLang(@"PaymentMgmt_Prompt_OrderShippedNote");
        case PPPaymentOrderAdminActionTypeDelivered: return kLang(@"PaymentMgmt_Prompt_OrderDeliveredNote");
        case PPPaymentOrderAdminActionTypeCollectPayment: return kLang(@"PaymentMgmt_Prompt_OrderCollectPaymentNote");
        case PPPaymentOrderAdminActionTypeCancel: return kLang(@"PaymentMgmt_Prompt_OrderCancelNote");
        case PPPaymentOrderAdminActionTypeOfficialAccept:
        case PPPaymentOrderAdminActionTypeOfficialReject:
        case PPPaymentOrderAdminActionTypeOfficialStartPreparing:
        case PPPaymentOrderAdminActionTypeOfficialMarkReady:
        case PPPaymentOrderAdminActionTypeOfficialRequestDelivery:
        case PPPaymentOrderAdminActionTypeOfficialConfirmHandover:
        case PPPaymentOrderAdminActionTypeOfficialCancel:
            return kLang(@"PaymentMgmt_OfficialFulfillment_Prompt");
    }
    return kLang(@"PaymentMgmt_Prompt_RequestNote_Subtitle");
}

- (NSString *)pp_confirmationSubtitleForOrderAction:(PPPaymentOrderAdminActionType)actionType
{
    switch (actionType) {
        case PPPaymentOrderAdminActionTypeApprove: return kLang(@"PaymentMgmt_Confirm_OrderApprove");
        case PPPaymentOrderAdminActionTypeProcessing: return kLang(@"PaymentMgmt_Confirm_OrderProcessing");
        case PPPaymentOrderAdminActionTypeShipped: return kLang(@"PaymentMgmt_Confirm_OrderShipped");
        case PPPaymentOrderAdminActionTypeDelivered: return kLang(@"PaymentMgmt_Confirm_OrderDelivered");
        case PPPaymentOrderAdminActionTypeCollectPayment: return kLang(@"PaymentMgmt_Confirm_OrderCollectPayment");
        case PPPaymentOrderAdminActionTypeCancel: return kLang(@"PaymentMgmt_Confirm_OrderCancel");
        case PPPaymentOrderAdminActionTypeOfficialAccept:
        case PPPaymentOrderAdminActionTypeOfficialReject:
        case PPPaymentOrderAdminActionTypeOfficialStartPreparing:
        case PPPaymentOrderAdminActionTypeOfficialMarkReady:
        case PPPaymentOrderAdminActionTypeOfficialRequestDelivery:
        case PPPaymentOrderAdminActionTypeOfficialConfirmHandover:
        case PPPaymentOrderAdminActionTypeOfficialCancel:
            return kLang(@"PaymentMgmt_OfficialFulfillment_Confirm");
    }
    return kLang(@"PaymentMgmt_Confirm_RequestUpdate");
}

- (NSString *)pp_successMessageForOrderAction:(PPPaymentOrderAdminActionType)actionType
{
    switch (actionType) {
        case PPPaymentOrderAdminActionTypeApprove: return kLang(@"PaymentMgmt_Success_OrderApprove");
        case PPPaymentOrderAdminActionTypeProcessing: return kLang(@"PaymentMgmt_Success_OrderProcessing");
        case PPPaymentOrderAdminActionTypeShipped: return kLang(@"PaymentMgmt_Success_OrderShipped");
        case PPPaymentOrderAdminActionTypeDelivered: return kLang(@"PaymentMgmt_Success_OrderDelivered");
        case PPPaymentOrderAdminActionTypeCollectPayment: return kLang(@"PaymentMgmt_Success_OrderCollectPayment");
        case PPPaymentOrderAdminActionTypeCancel: return kLang(@"PaymentMgmt_Success_OrderCancel");
        case PPPaymentOrderAdminActionTypeOfficialAccept:
        case PPPaymentOrderAdminActionTypeOfficialReject:
        case PPPaymentOrderAdminActionTypeOfficialStartPreparing:
        case PPPaymentOrderAdminActionTypeOfficialMarkReady:
        case PPPaymentOrderAdminActionTypeOfficialRequestDelivery:
        case PPPaymentOrderAdminActionTypeOfficialConfirmHandover:
        case PPPaymentOrderAdminActionTypeOfficialCancel:
            return kLang(@"PaymentMgmt_OfficialFulfillment_Success");
    }
    return kLang(@"PaymentMgmt_Success_RequestUpdate");
}

- (void)pp_handleOrderAction:(PPPaymentOrderAdminActionType)actionType
{
    if (self.actionInFlight) return;
    NSString *title = [self pp_titleForOrderAction:actionType];
    NSString *subtitle = [self pp_promptSubtitleForOrderAction:actionType];
    [self pp_promptForAdminNoteWithTitle:title subtitle:subtitle completion:^(NSString *note) {
        NSString *resolvedNote = [self pp_resolvedAdminNoteForOrderAction:actionType userNote:note];
        if (resolvedNote.length == 0) return;

        [AlertHelper showConfirmationIn:self
                                  title:title
                               subtitle:[self pp_confirmationSubtitleForOrderAction:actionType]
                            placeholder:nil
                          confirmButton:kLang(@"Confirm")
                           cancelButton:kLang(@"Cancel")
                           confirmBlock:^{
            [self pp_executeOrderAction:actionType note:resolvedNote];
        } cancelBlock:nil];
    }];
}

- (void)pp_executeOrderAction:(PPPaymentOrderAdminActionType)actionType note:(NSString *)note
{
    self.actionInFlight = YES;
    [PPHUD showIndeterminateIn:self.view title:kLang(@"PaymentMgmt_Loading_Updating") subtitle:kLang(@"PaymentMgmt_Loading_OrderUpdate")];

    if (self.record.fulfillmentVersion == 1) {
        PPFulfillmentRecord *fulfillment = self.officialFulfillment;
        NSString *action = [self pp_callableActionForOrderAction:actionType];
        NSString *commandID = NSUUID.UUID.UUIDString;
        if (!fulfillment || action.length == 0) {
            self.actionInFlight = NO;
            [PPHUD dismiss];
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_OfficialFulfillment_NotManageable")];
            return;
        }
        __weak typeof(self) weakSelf = self;
        [self.fulfillmentService transitionOfficialFulfillment:fulfillment
                                                expectedStatus:fulfillment.status
                                                         action:action
                                                           note:note
                                                      commandID:commandID
                                                     completion:^(__unused NSDictionary * _Nullable result, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            self.actionInFlight = NO;
            [PPHUD dismiss];
            if (error) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"PaymentMgmt_Error_UpdateOrder")];
                [self pp_reloadRecordShowHUD:NO];
                return;
            }
            [PPHUD showSuccess:kLang(@"Updated") subtitle:[self pp_successMessageForOrderAction:actionType]];
            [self pp_reloadRecordShowHUD:NO];
        }];
        return;
    }

    void (^completion)(PPPaymentAdminRecord *, NSError *) = ^(PPPaymentAdminRecord *updatedRecord, NSError *error) {
        self.actionInFlight = NO;
        [PPHUD dismiss];
        if (error) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_UpdateOrder")];
            return;
        }

        if (updatedRecord) {
            self.record = updatedRecord;
            [self pp_rebuildSections];
            [self.tableView reloadData];
        }

        [PPHUD showSuccess:kLang(@"Updated") subtitle:[self pp_successMessageForOrderAction:actionType]];
    };

    switch (actionType) {
        case PPPaymentOrderAdminActionTypeApprove:
            [self.service approveOrder:self.record note:note completion:completion];
            break;
        case PPPaymentOrderAdminActionTypeProcessing:
            [self.service markOrderProcessing:self.record note:note completion:completion];
            break;
        case PPPaymentOrderAdminActionTypeShipped:
            [self.service markOrderShipped:self.record note:note completion:completion];
            break;
        case PPPaymentOrderAdminActionTypeDelivered:
            [self.service markOrderDelivered:self.record note:note completion:completion];
            break;
        case PPPaymentOrderAdminActionTypeCollectPayment:
            [self.service collectOrderPayment:self.record note:note completion:completion];
            break;
        case PPPaymentOrderAdminActionTypeCancel:
            [self.service cancelOrder:self.record note:note completion:completion];
            break;
        case PPPaymentOrderAdminActionTypeOfficialAccept:
        case PPPaymentOrderAdminActionTypeOfficialReject:
        case PPPaymentOrderAdminActionTypeOfficialStartPreparing:
        case PPPaymentOrderAdminActionTypeOfficialMarkReady:
        case PPPaymentOrderAdminActionTypeOfficialRequestDelivery:
        case PPPaymentOrderAdminActionTypeOfficialConfirmHandover:
        case PPPaymentOrderAdminActionTypeOfficialCancel:
            break;
    }
}

- (void)pp_promptForAdminNoteWithTitle:(NSString *)title
                              subtitle:(NSString *)subtitle
                            completion:(void (^)(NSString *note))completion
{
    [AlertHelper showTextPromptIn:self
                            title:title
                         subtitle:subtitle
                      placeholder:kLang(@"PaymentMgmt_Value_AdminNote")
                      initialText:nil
                      confirmText:kLang(@"Confirm")
                       cancelText:kLang(@"Cancel")
                      secureEntry:NO
                     keyboardType:UIKeyboardTypeDefault
                       completion:^(NSString * _Nullable text) {
        if (!text) {
            return;
        }
        NSString *note = PPPaymentAdminDetailsTrimmedString(text);
        if (text && note.length > 0 && note.length < 3) {
            [AlertHelper showWarningIn:self title:kLang(@"PaymentMgmt_Prompt_NoteRequired_Title") subtitle:kLang(@"PaymentMgmt_Prompt_NoteRequired_Subtitle")];
            return;
        }
        if (completion) completion(note);
    }];
}

@end

@interface PPPaymentRequestDetailsViewController ()

@property (nonatomic, strong) PPPaymentManagementService *service;
@property (nonatomic, strong) PPPaymentAdminRecord *orderRecord;
@property (nonatomic, strong) PPPaymentAdminSupportRequest *request;
@property (nonatomic, strong) NSArray<PPPaymentAdminTimelineEvent *> *events;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, copy) PPPaymentDetailsUpdateBlock updateHandler;
@property (nonatomic, assign) BOOL isRefreshingRequest;
@property (nonatomic, assign) BOOL actionInFlight;

@end

@implementation PPPaymentRequestDetailsViewController

- (instancetype)initWithOrderRecord:(PPPaymentAdminRecord *)orderRecord
                            request:(PPPaymentAdminSupportRequest *)request
                      updateHandler:(PPPaymentDetailsUpdateBlock)updateHandler
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _service = [PPPaymentManagementService shared];
        _orderRecord = orderRecord;
        _request = request;
        _updateHandler = [updateHandler copy];
        _events = request.events ?: @[];
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale currentLocale];
        [_dateFormatter setLocalizedDateFormatFromTemplate:@"d MMM yyyy h:mm a"];
        self.title = PPPaymentAdminDisplayTitleForRequestType(request.type);
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
    self.tableView.estimatedRowHeight = 72.0;

    self.refreshControl = [UIRefreshControl new];
    self.refreshControl.tintColor = [UIColor ppPrimary];
    [self.refreshControl addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventValueChanged];

    [self pp_setupDossierHeader];
    [self pp_reloadRequestShowHUD:YES];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (!self.tableView.tableHeaderView) return;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;
    CGSize fitting = [self.tableView.tableHeaderView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame = self.tableView.tableHeaderView.frame;
    CGFloat targetHeight = MAX(fitting.height, 104.0);
    if (fabs(frame.size.width - width) > 0.5 || fabs(frame.size.height - targetHeight) > 0.5) {
        frame.size.width = width;
        frame.size.height = targetHeight;
        self.tableView.tableHeaderView.frame = frame;
        self.tableView.tableHeaderView = self.tableView.tableHeaderView;
    }
}

- (void)pp_onBackTapped
{
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)pp_setupDossierHeader
{
    CGFloat horizontal = PPScreenMargin;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;

    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 110.0)];
    headerContainer.backgroundColor = UIColor.clearColor;

    // 1. Navigation Top Bar (Back Button + Refresh Button)
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *backConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    UIImage *chevronImg = [UIImage systemImageNamed:[Language isRTL] ? @"chevron.right" : @"chevron.left" withConfiguration:backConfig];
    [backBtn setImage:chevronImg forState:UIControlStateNormal];
    [backBtn setTitle:[NSString stringWithFormat:@" %@", kLang(@"Back")] forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor ppPrimary] forState:UIControlStateNormal];
    backBtn.tintColor = [UIColor ppPrimary];
    backBtn.titleLabel.font = [Styling fontBold:15];
    [backBtn addTarget:self action:@selector(pp_onBackTapped) forControlEvents:UIControlEventTouchUpInside];
    [headerContainer addSubview:backBtn];

    UIButton *refreshBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    refreshBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *refreshConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [refreshBtn setImage:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:refreshConfig] forState:UIControlStateNormal];
    refreshBtn.tintColor = [UIColor ppPrimary];
    refreshBtn.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    refreshBtn.layer.cornerRadius = 18.0;
    refreshBtn.layer.masksToBounds = YES;
    [refreshBtn addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventTouchUpInside];
    [headerContainer addSubview:refreshBtn];

    // 2. Eyebrow Category Breadcrumb
    UILabel *eyebrowLabel = [UILabel new];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [Styling fontRegular:12];
    eyebrowLabel.textColor = [UIColor ppTextSecondary];
    eyebrowLabel.text = [NSString stringWithFormat:@"%@ / %@", kLang(@"CommandCenter_Work_Workspace"), kLang(@"PaymentMgmt_Section_Requests")];
    eyebrowLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [headerContainer addSubview:eyebrowLabel];

    // 3. Dossier Large Title (Request Title)
    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:22];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = PPPaymentAdminDisplayTitleForRequestType(self.request.type);
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [headerContainer addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        // Back Button & Refresh Button
        [backBtn.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:4],
        [backBtn.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [backBtn.heightAnchor constraintGreaterThanOrEqualToConstant:44],

        [refreshBtn.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
        [refreshBtn.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],
        [refreshBtn.widthAnchor constraintEqualToConstant:36],
        [refreshBtn.heightAnchor constraintEqualToConstant:36],

        // Eyebrow
        [eyebrowLabel.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:2],
        [eyebrowLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [eyebrowLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],

        // Title
        [titleLabel.topAnchor constraintEqualToAnchor:eyebrowLabel.bottomAnchor constant:2],
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerContainer.bottomAnchor constant:-8]
    ]];

    self.tableView.tableHeaderView = headerContainer;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    UIButton *refresh = [self pp_ButtonWithSystemName:@"arrow.clockwise" action:@selector(onRefresh)];
    [self pp_navBarWithOtherButton:refresh title:@""];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;

    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = PPPaymentDetailsScaledFont([Styling fontMedium:14], UIFontTextStyleHeadline);
    header.textLabel.adjustsFontForContentSizeCategory = YES;
    header.textLabel.textColor = [UIColor ppTextSecondary];
    header.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
    header.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
}

- (void)onRefresh
{
    [self pp_reloadRequestShowHUD:NO];
}

- (void)pp_reloadRequestShowHUD:(BOOL)showHUD
{
    if (self.isRefreshingRequest) return;
    self.isRefreshingRequest = YES;
    if (showHUD && !self.refreshControl.isRefreshing) {
        [PPHUD showIndeterminateIn:self.view title:kLang(@"Loading") subtitle:kLang(@"PaymentMgmt_Loading_Request")];
    }

    __weak typeof(self) weakSelf = self;
    [self.service loadFullRecordForOrderID:self.orderRecord.orderId completion:^(PPPaymentAdminRecord * _Nullable record, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error || !record) {
            self.isRefreshingRequest = NO;
            [PPHUD dismiss];
            [self.refreshControl endRefreshing];
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_LoadRequest")];
            return;
        }

        self.orderRecord = record;
        PPPaymentAdminSupportRequest *freshRequest = nil;
        for (PPPaymentAdminSupportRequest *candidate in record.requests ?: @[]) {
            if ([candidate.requestId isEqualToString:self.request.requestId]) {
                freshRequest = candidate;
                break;
            }
        }
        if (freshRequest) {
            self.request = freshRequest;
           // self.title = PPPaymentAdminDisplayTitleForRequestType(self.request.type);
        }

        [self.service loadEventsForRequest:self.request completion:^(NSArray<PPPaymentAdminTimelineEvent *> *events, NSError * _Nullable eventsError) {
            self.isRefreshingRequest = NO;
            [PPHUD dismiss];
            [self.refreshControl endRefreshing];

            if (eventsError) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_LoadRequestHistory")];
                return;
            }

            self.events = events ?: @[];
            if (self.updateHandler) self.updateHandler(record);
            [self.tableView reloadData];
        }];
    }];
}

- (NSString *)pp_dateString:(NSDate *)date
{
    if (![date isKindOfClass:NSDate.class]) return @"--";
    return [self.dateFormatter stringFromDate:date];
}

- (NSArray<NSDictionary *> *)pp_summaryRows
{
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    NSString *effectiveResolution = [self.request effectiveResolutionKey];
    [rows addObject:@{
        @"title": kLang(@"PaymentMgmt_Field_Status"),
        @"detail": PPPaymentAdminDisplayTitleForRequestStatus(self.request.status),
        @"tint": PPPaymentAdminDetailsStatusColor(effectiveResolution),
    }];
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Type"), @"detail": PPPaymentAdminDisplayTitleForRequestType(self.request.type)}];
    if (self.request.reasonTitle.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Reason"), @"detail": self.request.reasonTitle}];
    }
    if (self.request.subject.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Subject"), @"detail": self.request.subject}];
    }
    if (self.request.issueCategory.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Category"), @"detail": PPPaymentAdminDisplayTitleForIssueCategory(self.request.issueCategory)}];
    }
    [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Submitted"), @"detail": [self pp_dateString:(self.request.submittedAt ?: self.request.createdAt)]}];
    if (self.request.resolvedAt) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Resolved"), @"detail": [self pp_dateString:self.request.resolvedAt]}];
    }
    if (self.request.finalResolution.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_FinalResolution"), @"detail": PPPaymentAdminDisplayTitleForRequestStatus(self.request.finalResolution)}];
    }
    NSNumber *amount = self.request.resolution[@"amount"];
    if ([amount respondsToSelector:@selector(doubleValue)] && amount.doubleValue > 0.0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_ResolvedAmount"), @"detail": [NSString stringWithFormat:@"%@ %.2f", PPPaymentAdminDetailsTrimmedString(self.orderRecord.currency).uppercaseString ?: @"QAR", amount.doubleValue]}];
    }
    if (self.request.notes.length > 0) {
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_Notes"), @"detail": self.request.notes, @"multiline": @YES}];
    }
    NSString *reviewer = PPPaymentAdminDetailsTrimmedString(self.request.adminReview[@"adminName"]);
    NSString *reviewNote = PPPaymentAdminDetailsTrimmedString(self.request.adminReview[@"note"]);
    if (reviewer.length > 0) {
        NSString *reviewValue = reviewNote.length > 0 ? [NSString stringWithFormat:@"%@\n%@", reviewer, reviewNote] : reviewer;
        [rows addObject:@{@"title": kLang(@"PaymentMgmt_Field_LastReview"), @"detail": reviewValue, @"multiline": @YES}];
    }
    return rows.copy;
}

- (NSArray<NSDictionary *> *)pp_requestActions
{
    if (![self.service currentAdminCanManagePayments]) return @[];
    BOOL canRefund = [self.service currentAdminCanRefundPayments];
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    if ([PPPaymentAdminRecord canResolveRequest:self.request withAction:PPPaymentAdminRequestResolutionApprove order:self.orderRecord]) {
        [rows addObject:@{@"type": @(PPPaymentRequestAdminActionTypeApprove), @"title": [self pp_titleForRequestAction:PPPaymentRequestAdminActionTypeApprove], @"subtitle": kLang(@"PaymentMgmt_Action_ApproveRequest_Subtitle"), @"tint": [UIColor ppSuccess]}];
    }
    if ([PPPaymentAdminRecord canResolveRequest:self.request withAction:PPPaymentAdminRequestResolutionReject order:self.orderRecord]) {
        [rows addObject:@{@"type": @(PPPaymentRequestAdminActionTypeReject), @"title": [self pp_titleForRequestAction:PPPaymentRequestAdminActionTypeReject], @"subtitle": kLang(@"PaymentMgmt_Action_RejectRequest_Subtitle"), @"tint": [UIColor ppError]}];
    }
    if ([PPPaymentAdminRecord canResolveRequest:self.request withAction:PPPaymentAdminRequestResolutionComplete order:self.orderRecord]) {
        NSString *subtitle = [self.request isReturnLike]
            ? kLang(@"PaymentMgmt_Action_CompleteReturnRequest_Subtitle")
            : kLang(@"PaymentMgmt_Action_CompleteRequest_Subtitle");
        [rows addObject:@{@"type": @(PPPaymentRequestAdminActionTypeComplete), @"title": [self pp_titleForRequestAction:PPPaymentRequestAdminActionTypeComplete], @"subtitle": subtitle, @"tint": [UIColor ppInfo]}];
    }
    if (canRefund && [PPPaymentAdminRecord canResolveRequest:self.request withAction:PPPaymentAdminRequestResolutionRefund order:self.orderRecord]) {
        [rows addObject:@{@"type": @(PPPaymentRequestAdminActionTypeRefund), @"title": [self pp_titleForRequestAction:PPPaymentRequestAdminActionTypeRefund], @"subtitle": kLang(@"PaymentMgmt_Action_RefundFull_Subtitle"), @"tint": [UIColor ppWarning]}];
    }
    if (canRefund && [PPPaymentAdminRecord canResolveRequest:self.request withAction:PPPaymentAdminRequestResolutionPartialRefund order:self.orderRecord]) {
        [rows addObject:@{@"type": @(PPPaymentRequestAdminActionTypePartialRefund), @"title": [self pp_titleForRequestAction:PPPaymentRequestAdminActionTypePartialRefund], @"subtitle": kLang(@"PaymentMgmt_Action_RefundPartial_Subtitle"), @"tint": [UIColor ppWarning]}];
    }
    if ([PPPaymentAdminRecord canResolveRequest:self.request withAction:PPPaymentAdminRequestResolutionClose order:self.orderRecord]) {
        [rows addObject:@{@"type": @(PPPaymentRequestAdminActionTypeClose), @"title": [self pp_titleForRequestAction:PPPaymentRequestAdminActionTypeClose], @"subtitle": kLang(@"PaymentMgmt_Action_CloseRequest_Subtitle"), @"tint": [UIColor ppTextSecondary]}];
    }
    return rows.copy;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    NSInteger sections = 3; // summary, timeline, actions
    if (self.request.itemSnapshots.count > 0 || self.request.itemIDs.count > 0) sections += 1;
    if (self.request.attachments.count > 0) sections += 1;
    return sections;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    NSInteger index = 0;
    if (section == index++) return kLang(@"PaymentMgmt_Section_Summary");
    if (self.request.itemSnapshots.count > 0 || self.request.itemIDs.count > 0) {
        if (section == index++) return kLang(@"PaymentMgmt_Section_RequestedItems");
    }
    if (self.request.attachments.count > 0) {
        if (section == index++) return kLang(@"PaymentMgmt_Section_Attachments");
    }
    if (section == index++) return kLang(@"PaymentMgmt_Section_Timeline");
    return kLang(@"PaymentMgmt_Section_Actions");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    NSInteger index = 0;
    if (section == index++) return [self pp_summaryRows].count;
    if (self.request.itemSnapshots.count > 0 || self.request.itemIDs.count > 0) {
        if (section == index++) {
            return MAX(1, self.request.itemSnapshots.count > 0 ? self.request.itemSnapshots.count : self.request.itemIDs.count);
        }
    }
    if (self.request.attachments.count > 0) {
        if (section == index++) return self.request.attachments.count;
    }
    if (section == index++) return MAX(1, self.events.count);
    return MAX(1, [self pp_requestActions].count);
}

- (UITableViewCell *)pp_valueCellForTableView:(UITableView *)tableView
{
    static NSString *cellID = @"PPPaymentRequestValueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
        cell.textLabel.font = [Styling fontMedium:14];
        cell.detailTextLabel.font = [Styling fontRegular:14];
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    PPPaymentAdminApplyLanguageToTableCell(cell);
    return cell;
}

- (UITableViewCell *)pp_subtitleCellForTableView:(UITableView *)tableView reuseIdentifier:(NSString *)reuseIdentifier
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
        cell.textLabel.font = PPPaymentDetailsScaledFont([Styling fontBold:15], UIFontTextStyleHeadline);
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.font = PPPaymentDetailsScaledFont([Styling fontRegular:13], UIFontTextStyleSubheadline);
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.numberOfLines = 0;
    }
    PPPaymentAdminApplyLanguageToTableCell(cell);
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger index = 0;
    if (indexPath.section == index++) {
        UITableViewCell *cell = [self pp_valueCellForTableView:tableView];
        NSDictionary *row = [self pp_summaryRows][indexPath.row];
        cell.textLabel.text = row[@"title"];
        cell.detailTextLabel.text = row[@"detail"];
        cell.detailTextLabel.textColor = row[@"tint"] ?: [UIColor ppTextSecondary];
        return cell;
    }

    if (self.request.itemSnapshots.count > 0 || self.request.itemIDs.count > 0) {
        if (indexPath.section == index++) {
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentRequestItemCell"];
            if (self.request.itemSnapshots.count > 0) {
                NSDictionary *item = [self.request.itemSnapshots[indexPath.row] isKindOfClass:NSDictionary.class] ? self.request.itemSnapshots[indexPath.row] : @{};
                NSString *title = PPPaymentAdminDetailsFirstNonEmpty(item, @[@"name", @"title"]);
                if (title.length == 0) title = PPPaymentAdminDetailsFirstNonEmpty(item, @[@"itemId", @"itemID", @"id"]);
                NSInteger qty = [item[@"qty"] ?: item[@"quantity"] integerValue];
                cell.textLabel.text = title.length > 0 ? title : kLang(@"PaymentMgmt_Value_RequestedItem");
                cell.detailTextLabel.text = [NSString stringWithFormat:kLang(@"PaymentMgmt_Item_Qty_Format"), (long)MAX(1, qty)];
            } else {
                NSString *itemID = self.request.itemIDs[indexPath.row];
                cell.textLabel.text = itemID;
                cell.detailTextLabel.text = kLang(@"PaymentMgmt_Value_RequestedItem");
            }
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.imageView.image = [UIImage systemImageNamed:@"cube.box"];
            cell.imageView.tintColor = [UIColor ppPrimary];
            return cell;
        }
    }

    if (self.request.attachments.count > 0) {
        if (indexPath.section == index++) {
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentAttachmentCell"];
            NSDictionary *attachment = [self.request.attachments[indexPath.row] isKindOfClass:NSDictionary.class] ? self.request.attachments[indexPath.row] : @{};
            NSString *fileName = PPPaymentAdminDetailsFirstNonEmpty(attachment, @[@"fileName"]);
            NSString *mimeType = PPPaymentAdminDetailsFirstNonEmpty(attachment, @[@"mimeType"]);
            NSString *url = PPPaymentAdminDetailsFirstNonEmpty(attachment, @[@"attachmentURL", @"url"]);
            cell.textLabel.text = fileName.length > 0 ? fileName : kLang(@"PaymentMgmt_Value_Attachment");
            cell.detailTextLabel.text = mimeType.length > 0 ? mimeType : url;
            cell.imageView.image = [UIImage systemImageNamed:@"paperclip.circle"];
            cell.imageView.tintColor = [UIColor ppQuickActionServices];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
    }

    if (indexPath.section == index++) {
        if (self.events.count == 0) {
            UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentRequestEventPlaceholderCell"];
            cell.textLabel.text = kLang(@"PaymentMgmt_Placeholder_NoRequestHistoryTitle");
            cell.detailTextLabel.text = kLang(@"PaymentMgmt_Placeholder_NoRequestHistorySubtitle");
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.imageView.image = [UIImage systemImageNamed:@"clock.badge.xmark"];
            cell.imageView.tintColor = [UIColor ppTextSecondary];
            return cell;
        }
        UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentRequestEventCell"];
        PPPaymentAdminTimelineEvent *event = self.events[indexPath.row];
        NSString *summary = PPPaymentAdminDisplayTitleForTimelineSummary(event);
        cell.textLabel.text = summary;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@ • %@", PPPaymentAdminDisplayTitleForRequestStatus(event.status), PPPaymentAdminDisplayTitleForActorType(event.actorType.length > 0 ? event.actorType : @"system"), [self pp_dateString:event.createdAt]];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        cell.imageView.tintColor = PPPaymentAdminDetailsStatusColor(event.status);
        return cell;
    }

    NSArray<NSDictionary *> *actions = [self pp_requestActions];
    if (actions.count == 0) {
        UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentRequestActionPlaceholderCell"];
        cell.textLabel.text = kLang(@"PaymentMgmt_Placeholder_NoRequestActionsTitle");
        cell.detailTextLabel.text = kLang(@"PaymentMgmt_Placeholder_NoRequestActionsSubtitle");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = [UIImage systemImageNamed:@"checkmark.seal"];
        cell.imageView.tintColor = [UIColor ppTextSecondary];
        return cell;
    }
    UITableViewCell *cell = [self pp_subtitleCellForTableView:tableView reuseIdentifier:@"PPPaymentRequestActionCell"];
    NSDictionary *row = actions[indexPath.row];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.textColor = row[@"tint"] ?: [UIColor ppTextPrimary];
    cell.detailTextLabel.text = row[@"subtitle"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = [UIImage systemImageNamed:@"bolt.shield"];
    cell.imageView.tintColor = row[@"tint"] ?: AppPrimaryClr;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSInteger index = 0;
    if (indexPath.section == index++) return;
    if (self.request.itemSnapshots.count > 0 || self.request.itemIDs.count > 0) {
        if (indexPath.section == index++) return;
    }
    if (self.request.attachments.count > 0) {
        if (indexPath.section == index++) {
            NSDictionary *attachment = [self.request.attachments[indexPath.row] isKindOfClass:NSDictionary.class] ? self.request.attachments[indexPath.row] : @{};
            NSString *urlString = PPPaymentAdminDetailsFirstNonEmpty(attachment, @[@"attachmentURL", @"url"]);
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
            return;
        }
    }
    if (indexPath.section == index++) return;

    NSArray<NSDictionary *> *actions = [self pp_requestActions];
    if (actions.count == 0) return;
    NSDictionary *row = actions[indexPath.row];
    [self pp_handleRequestAction:[row[@"type"] integerValue]];
}

- (void)pp_handleRequestAction:(PPPaymentRequestAdminActionType)actionType
{
    if (self.actionInFlight) return;

    if (actionType == PPPaymentRequestAdminActionTypePartialRefund) {
        [AlertHelper showTextPromptIn:self
                                title:kLang(@"PaymentMgmt_Prompt_PartialRefund_Title")
                             subtitle:kLang(@"PaymentMgmt_Prompt_PartialRefund_Subtitle")
                          placeholder:kLang(@"PaymentMgmt_Value_Amount")
                          initialText:nil
                          confirmText:kLang(@"PaymentMgmt_Prompt_Continue")
                           cancelText:kLang(@"Cancel")
                          secureEntry:NO
                         keyboardType:UIKeyboardTypeDecimalPad
                           completion:^(NSString * _Nullable text) {
            NSString *trimmed = PPPaymentAdminDetailsTrimmedString(text);
            double amount = trimmed.doubleValue;
            if (trimmed.length == 0 || amount <= 0.0 || amount >= self.orderRecord.totalAmount) {
                [AlertHelper showWarningIn:self title:kLang(@"PaymentMgmt_Prompt_InvalidAmount_Title") subtitle:kLang(@"PaymentMgmt_Prompt_InvalidAmount_Subtitle")];
                return;
            }
            [self pp_promptForNoteAndExecuteAction:actionType amount:@(amount)];
        }];
        return;
    }

    [self pp_promptForNoteAndExecuteAction:actionType amount:nil];
}

- (void)pp_promptForNoteAndExecuteAction:(PPPaymentRequestAdminActionType)actionType amount:(NSNumber *)amount
{
    NSString *title = [self pp_titleForRequestAction:actionType];
    [AlertHelper showTextPromptIn:self
                            title:title
                         subtitle:kLang(@"PaymentMgmt_Prompt_RequestNote_Subtitle")
                      placeholder:kLang(@"PaymentMgmt_Value_AdminNote")
                      initialText:nil
                      confirmText:kLang(@"Confirm")
                       cancelText:kLang(@"Cancel")
                      secureEntry:NO
                     keyboardType:UIKeyboardTypeDefault
                       completion:^(NSString * _Nullable text) {
        NSString *note = PPPaymentAdminDetailsTrimmedString(text);
        if (text && note.length < 3) {
            [AlertHelper showWarningIn:self title:kLang(@"PaymentMgmt_Prompt_NoteRequired_Title") subtitle:kLang(@"PaymentMgmt_Prompt_NoteRequired_Subtitle")];
            return;
        }
        NSString *subtitle = [self pp_confirmationSubtitleForRequestAction:actionType amount:amount];
        [AlertHelper showConfirmationIn:self
                                  title:title
                               subtitle:subtitle
                            placeholder:nil
                          confirmButton:kLang(@"Confirm")
                           cancelButton:kLang(@"Cancel")
                           confirmBlock:^{
            [self pp_executeRequestAction:actionType note:note amount:amount];
        } cancelBlock:nil];
    }];
}

- (NSString *)pp_titleForRequestAction:(PPPaymentRequestAdminActionType)actionType
{
    switch (actionType) {
        case PPPaymentRequestAdminActionTypeApprove: return kLang(@"PaymentMgmt_Action_ApproveRequest_Title");
        case PPPaymentRequestAdminActionTypeReject: return kLang(@"PaymentMgmt_Action_RejectRequest_Title");
        case PPPaymentRequestAdminActionTypeComplete: return kLang(@"PaymentMgmt_Action_CompleteRequest_Title");
        case PPPaymentRequestAdminActionTypeRefund: return kLang(@"PaymentMgmt_Action_RefundFull_Title");
        case PPPaymentRequestAdminActionTypePartialRefund: return kLang(@"PaymentMgmt_Action_RefundPartial_Title");
        case PPPaymentRequestAdminActionTypeClose: return kLang(@"PaymentMgmt_Action_CloseRequest_Title");
    }
    return kLang(@"PaymentMgmt_Action_UpdateRequest_Title");
}

- (NSString *)pp_confirmationSubtitleForRequestAction:(PPPaymentRequestAdminActionType)actionType amount:(NSNumber *)amount
{
    switch (actionType) {
        case PPPaymentRequestAdminActionTypeApprove:
            return kLang(@"PaymentMgmt_Confirm_RequestApprove");
        case PPPaymentRequestAdminActionTypeReject:
            return kLang(@"PaymentMgmt_Confirm_RequestReject");
        case PPPaymentRequestAdminActionTypeComplete:
            return [self.request isReturnLike] ? kLang(@"PaymentMgmt_Confirm_RequestCompleteReturn") : kLang(@"PaymentMgmt_Confirm_RequestComplete");
        case PPPaymentRequestAdminActionTypeRefund:
            return kLang(@"PaymentMgmt_Confirm_RequestRefund");
        case PPPaymentRequestAdminActionTypePartialRefund:
            return [NSString stringWithFormat:kLang(@"PaymentMgmt_Confirm_RequestPartialRefund_Format"), PPPaymentAdminDetailsTrimmedString(self.orderRecord.currency).uppercaseString ?: @"QAR", amount.doubleValue];
        case PPPaymentRequestAdminActionTypeClose:
            return kLang(@"PaymentMgmt_Confirm_RequestClose");
    }
    return kLang(@"PaymentMgmt_Confirm_RequestUpdate");
}

- (void)pp_executeRequestAction:(PPPaymentRequestAdminActionType)actionType note:(NSString *)note amount:(NSNumber *)amount
{
    self.actionInFlight = YES;
    [PPHUD showIndeterminateIn:self.view title:kLang(@"PaymentMgmt_Loading_Updating") subtitle:kLang(@"PaymentMgmt_Loading_RequestUpdate")];

    PPPaymentAdminRequestResolution resolution = PPPaymentAdminRequestResolutionApprove;
    switch (actionType) {
        case PPPaymentRequestAdminActionTypeApprove: resolution = PPPaymentAdminRequestResolutionApprove; break;
        case PPPaymentRequestAdminActionTypeReject: resolution = PPPaymentAdminRequestResolutionReject; break;
        case PPPaymentRequestAdminActionTypeComplete: resolution = PPPaymentAdminRequestResolutionComplete; break;
        case PPPaymentRequestAdminActionTypeRefund: resolution = PPPaymentAdminRequestResolutionRefund; break;
        case PPPaymentRequestAdminActionTypePartialRefund: resolution = PPPaymentAdminRequestResolutionPartialRefund; break;
        case PPPaymentRequestAdminActionTypeClose: resolution = PPPaymentAdminRequestResolutionClose; break;
    }

    __weak typeof(self) weakSelf = self;
    [self.service resolveRequest:self.request
                        forOrder:self.orderRecord
                          action:resolution
                            note:note
                          amount:amount
                      completion:^(PPPaymentAdminRecord * _Nullable record, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        self.actionInFlight = NO;
        [PPHUD dismiss];
        if (error) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"PaymentMgmt_Error_UpdateRequest")];
            return;
        }

        if (record) {
            self.orderRecord = record;
            for (PPPaymentAdminSupportRequest *candidate in record.requests ?: @[]) {
                if ([candidate.requestId isEqualToString:self.request.requestId]) {
                    self.request = candidate;
                    break;
                }
            }
            if (self.updateHandler) self.updateHandler(record);
        }

        [PPHUD showSuccess:kLang(@"Updated") subtitle:kLang(@"PaymentMgmt_Success_RequestUpdate")];
        [self pp_reloadRequestShowHUD:NO];
    }];
}

@end
