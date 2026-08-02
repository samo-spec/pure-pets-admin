#import "PPDeliveryManagementViewController.h"
#import "PPDeliveryService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "PPHero.h"

static UIColor *PPDeliveryAccentColor(void) {
    return AppPrimaryClr ?: UIColor.systemPinkColor;
}

static UIColor *PPDeliveryCanvasColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGroupedBackgroundColor;
    return [UIColor colorWithWhite:0.96 alpha:1.0];
}

static UIColor *PPDeliverySurfaceColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondarySystemGroupedBackgroundColor;
    return UIColor.whiteColor;
}

static UIColor *PPDeliveryInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.labelColor;
    return UIColor.blackColor;
}

static UIColor *PPDeliverySubInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondaryLabelColor;
    return [UIColor colorWithWhite:0.40 alpha:1.0];
}

static void PPDeliveryApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    view.layer.shadowRadius = 22.0;
    view.layer.shadowOpacity = 0.052;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.62].CGColor;
}

static NSString *PPDeliveryDateString(NSDate *date) {
    if (!date) return @"-";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

static NSString *PPDeliveryStatusKey(NSString *status) {
    if ([status isEqualToString:@"in_transit"]) return @"Delivery_Status_InTransit";
    if ([status isEqualToString:@"delivered"]) return @"Delivery_Status_Delivered";
    if ([status isEqualToString:@"cancelled"]) return @"Delivery_Status_Cancelled";
    if ([status isEqualToString:@"pending"]) return @"Delivery_Status_Pending";
    if ([status isEqualToString:@"assigned"]) return @"Delivery_Status_Assigned";
    if ([status isEqualToString:@"accepted"]) return @"Delivery_Status_Accepted";
    return @"Delivery_Status_Unknown";
}

static NSString *PPDeliveryStatusText(NSString *status) {
    if (status.length == 0) return kLang(@"Delivery_Status_Unknown");
    NSString *key = PPDeliveryStatusKey(status);
    NSString *localized = kLang(key);
    return ([localized isKindOfClass:NSString.class] && localized.length > 0 && ![localized isEqualToString:key]) ? localized : status;
}

static UIColor *PPDeliveryStatusColor(NSString *status) {
    if ([status isEqualToString:@"delivered"] || [status isEqualToString:@"accepted"]) return UIColor.systemGreenColor;
    if ([status isEqualToString:@"cancelled"]) return UIColor.systemRedColor;
    if ([status isEqualToString:@"in_transit"] || [status isEqualToString:@"assigned"]) return UIColor.systemBlueColor;
    return PPDeliveryAccentColor();
}

@interface PPDeliveryRequestCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *orderLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *statusLabel;
- (void)configureWithRecord:(PPDeliveryRequestRecord *)record;
@end

@implementation PPDeliveryRequestCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPDeliverySurfaceColor();
        PPDeliveryApplyCardChrome(_cardView, 22.0);
        [self.contentView addSubview:_cardView];

        _symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"truck.box.fill"]];
        _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolView.contentMode = UIViewContentModeCenter;
        _symbolView.tintColor = PPDeliveryAccentColor();
        _symbolView.backgroundColor = [PPDeliveryAccentColor() colorWithAlphaComponent:0.11];
        _symbolView.layer.cornerRadius = 18.0;
        if (@available(iOS 13.0, *)) _symbolView.layer.cornerCurve = kCACornerCurveContinuous;
        [_cardView addSubview:_symbolView];

        _orderLabel = [UILabel new];
        _orderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _orderLabel.font = [Styling fontBold:17];
        _orderLabel.textColor = PPDeliveryInkColor();
        _orderLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _orderLabel.adjustsFontSizeToFitWidth = YES;
        _orderLabel.minimumScaleFactor = 0.76;
        [_cardView addSubview:_orderLabel];

        _detailLabel = [UILabel new];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [Styling fontRegular:12];
        _detailLabel.textColor = PPDeliverySubInkColor();
        _detailLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _detailLabel.numberOfLines = 2;
        [_cardView addSubview:_detailLabel];

        _statusLabel = [UILabel new];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = [Styling fontBold:11];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.layer.cornerRadius = 13.0;
        _statusLabel.layer.masksToBounds = YES;
        _statusLabel.adjustsFontSizeToFitWidth = YES;
        _statusLabel.minimumScaleFactor = 0.72;
        [_cardView addSubview:_statusLabel];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle.fill"]];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        chevron.tintColor = [PPDeliverySubInkColor() colorWithAlphaComponent:0.58];
        [_cardView addSubview:chevron];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-7.0],

            [_symbolView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_symbolView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_symbolView.widthAnchor constraintEqualToConstant:46.0],
            [_symbolView.heightAnchor constraintEqualToConstant:46.0],

            [chevron.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],
            [chevron.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:22.0],
            [chevron.heightAnchor constraintEqualToConstant:22.0],

            [_statusLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-10.0],
            [_statusLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:18.0],
            [_statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:92.0],
            [_statusLabel.heightAnchor constraintEqualToConstant:26.0],

            [_orderLabel.leadingAnchor constraintEqualToAnchor:_symbolView.trailingAnchor constant:14.0],
            [_orderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-12.0],
            [_orderLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:17.0],

            [_detailLabel.leadingAnchor constraintEqualToAnchor:_orderLabel.leadingAnchor],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-22.0],
            [_detailLabel.topAnchor constraintEqualToAnchor:_orderLabel.bottomAnchor constant:7.0],
            [_detailLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-17.0],
        ]];
    }
    return self;
}

- (void)configureWithRecord:(PPDeliveryRequestRecord *)record {
    NSString *orderRef = record.orderNumber.length > 0 ? record.orderNumber : record.orderID;
    self.orderLabel.text = [NSString stringWithFormat:@"#%@", orderRef.length ? orderRef : record.requestID ?: @"-"];
    NSString *fee = record.deliveryFee ? [NSString stringWithFormat:@"%.2f %@", record.deliveryFee.doubleValue, kLang(@"Accounting_QAR")] : @"-";
    NSString *driver = record.assignedDriverName.length ? record.assignedDriverName : kLang(@"Delivery_DriverUnassigned");
    self.detailLabel.text = [NSString stringWithFormat:@"%@ - %@ - %@\n%@", record.customerName.length ? record.customerName : kLang(@"Delivery_UnknownCustomer"), fee, driver, PPDeliveryDateString(record.createdAt)];
    UIColor *statusColor = PPDeliveryStatusColor(record.status);
    self.statusLabel.text = PPDeliveryStatusText(record.status);
    self.statusLabel.textColor = statusColor;
    self.statusLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.11];
    self.symbolView.tintColor = statusColor;
    self.symbolView.backgroundColor = [statusColor colorWithAlphaComponent:0.11];
}

@end

@interface PPDeliveryManagementViewController ()
@property (nonatomic, strong) NSArray<PPDeliveryRequestRecord *> *records;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, copy) NSString *statusFilter;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) BOOL isSizingHeader;
@end

@implementation PPDeliveryManagementViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Delivery_Title");
    self.statusFilter = @"all";
    self.records = @[];
    [self pp_configureTableView];
    [self pp_buildHeader];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self loadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroBackground startAnimations];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.heroBackground stopAnimations];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_updateInsets];
    [self pp_sizeHeaderToFit];
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPDeliveryCanvasColor();
    self.tableView.backgroundColor = PPDeliveryCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 98.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    [self.tableView registerClass:PPDeliveryRequestCell.class forCellReuseIdentifier:@"DeliveryCell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"StateCell"];

    UIRefreshControl *refresh = [UIRefreshControl new];
    [refresh addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    [header addSubview:stack];

    UIView *heroCard = [UIView new];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:heroCard];
    [heroCard.heightAnchor constraintGreaterThanOrEqualToConstant:154.0].active = YES;

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.72;
    hero.accentColorOverride = PPDeliveryAccentColor();
    [heroCard addSubview:hero];
    self.heroBackground = hero;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = kLang(@"Delivery_Title");
    title.font = [Styling fontBold:28];
    title.textColor = PPDeliveryInkColor();
    title.textAlignment = [Language alignmentForCurrentLanguage];
    title.numberOfLines = 2;
    [heroCard addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = kLang(@"Delivery_Subtitle");
    subtitle.font = [Styling fontRegular:14];
    subtitle.textColor = PPDeliverySubInkColor();
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.numberOfLines = 2;
    [heroCard addSubview:subtitle];

    UILabel *count = [UILabel new];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    count.font = [Styling fontBold:13];
    count.textColor = PPDeliveryAccentColor();
    count.backgroundColor = [PPDeliveryAccentColor() colorWithAlphaComponent:0.11];
    count.textAlignment = NSTextAlignmentCenter;
    count.layer.cornerRadius = 17.0;
    count.layer.masksToBounds = YES;
    [heroCard addSubview:count];
    self.heroCountLabel = count;

    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[kLang(@"Delivery_All"), kLang(@"Delivery_Active"), kLang(@"Delivery_Completed"), kLang(@"Delivery_Cancelled")]];
    self.filterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterSegment.selectedSegmentIndex = 0;
    self.filterSegment.selectedSegmentTintColor = PPDeliveryAccentColor();
    self.filterSegment.backgroundColor = [PPDeliverySurfaceColor() colorWithAlphaComponent:0.88];
    [self.filterSegment setTitleTextAttributes:@{NSFontAttributeName: [Styling fontMedium:13], NSForegroundColorAttributeName: PPDeliveryInkColor()} forState:UIControlStateNormal];
    [self.filterSegment setTitleTextAttributes:@{NSFontAttributeName: [Styling fontBold:13], NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [self.filterSegment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.filterSegment];
    [self.filterSegment.heightAnchor constraintEqualToConstant:48.0].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:18.0],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14.0],

        [hero.topAnchor constraintEqualToAnchor:heroCard.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:heroCard.bottomAnchor],

        [count.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:24.0],
        [count.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-24.0],
        [count.widthAnchor constraintGreaterThanOrEqualToConstant:88.0],
        [count.heightAnchor constraintEqualToConstant:34.0],

        [title.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:24.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:count.leadingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:28.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-24.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10.0],
        [subtitle.bottomAnchor constraintLessThanOrEqualToAnchor:heroCard.bottomAnchor constant:-24.0],
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_updateHeroCount];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer || self.isSizingHeader) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;

    self.isSizingHeader = YES;
    CGRect frame = self.headerContainer.frame;
    BOOL widthChanged = ABS(CGRectGetWidth(frame) - width) > 0.5;
    if (widthChanged) {
        frame.size.width = width;
        self.headerContainer.frame = frame;
    }
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                         withHorizontalFittingPriority:UILayoutPriorityRequired
                                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat targetHeight = ceil(MAX(1.0, height));
    BOOL heightChanged = ABS(CGRectGetHeight(self.headerContainer.frame) - targetHeight) > 0.5;
    if (widthChanged || heightChanged) {
        frame = self.headerContainer.frame;
        frame.size.width = width;
        frame.size.height = targetHeight;
        self.headerContainer.frame = frame;
        self.tableView.tableHeaderView = self.headerContainer;
    }
    self.isSizingHeader = NO;
}

- (void)pp_updateInsets {
    CGFloat tabHeight = self.tabBarController ? CGRectGetHeight(self.tabBarController.tabBar.bounds) : 0.0;
    UIEdgeInsets inset = self.tableView.contentInset;
    CGFloat targetBottom = MAX(28.0, tabHeight + 34.0);
    if (ABS(inset.bottom - targetBottom) > 0.5) {
        inset.bottom = targetBottom;
        self.tableView.contentInset = inset;
        self.tableView.scrollIndicatorInsets = inset;
    }
}

- (void)filterChanged:(UISegmentedControl *)sender {
    NSArray *statuses = @[@"all", @"in_transit", @"delivered", @"cancelled"];
    NSInteger index = sender.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)statuses.count) index = 0;
    self.statusFilter = statuses[(NSUInteger)index];
    [self pp_updateHeroCount];
    [self.tableView reloadData];
}

- (void)loadData {
    self.isLoading = YES;
    self.errorMessage = nil;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[PPDeliveryService shared] fetchDeliveryRequestsWithCompletion:^(NSArray<PPDeliveryRequestRecord *> *records, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            [weakSelf.refreshControl endRefreshing];
            if (error) {
                weakSelf.errorMessage = error.localizedDescription;
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                weakSelf.records = records ?: @[];
            }
            [weakSelf pp_updateHeroCount];
            [weakSelf.tableView reloadData];
        });
    }];
}

- (NSArray<PPDeliveryRequestRecord *> *)filteredRecords {
    if ([self.statusFilter isEqualToString:@"all"]) return self.records ?: @[];
    return [self.records filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PPDeliveryRequestRecord *record, NSDictionary<NSString *,id> *bindings) {
        (void)bindings;
        if ([self.statusFilter isEqualToString:@"in_transit"]) {
            return [record.status isEqualToString:@"in_transit"] || [record.status isEqualToString:@"assigned"] || [record.status isEqualToString:@"accepted"] || [record.status isEqualToString:@"pending"];
        }
        return [record.status isEqualToString:self.statusFilter];
    }]];
}

- (void)pp_updateHeroCount {
    NSString *format = kLang(@"Delivery_Count_Format");
    self.heroCountLabel.text = [NSString stringWithFormat:format, @([self filteredRecords].count)];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX([self filteredRecords].count, 1);
}

- (UITableViewCell *)pp_stateCellWithText:(NSString *)text {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"StateCell"];
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = text;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = PPDeliverySubInkColor();
    cell.textLabel.font = [Styling fontMedium:15];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *filtered = [self filteredRecords];

    if (filtered.count == 0) {
        NSString *text = self.isLoading ? kLang(@"Loading") : (self.errorMessage.length ? self.errorMessage : kLang(@"Delivery_Empty"));
        return [self pp_stateCellWithText:text];
    }

    PPDeliveryRequestRecord *record = filtered[indexPath.row];
    PPDeliveryRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeliveryCell" forIndexPath:indexPath];
    [cell configureWithRecord:record];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *filtered = [self filteredRecords];
    if (indexPath.row >= filtered.count) return;

    PPDeliveryRequestRecord *record = filtered[indexPath.row];
    [self showActionsForRecord:record];
}

- (void)showActionsForRecord:(PPDeliveryRequestRecord *)record {
    NSString *orderRef = record.orderNumber.length ? record.orderNumber : record.orderID;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Delivery_Actions") message:[NSString stringWithFormat:@"#%@ - %@", orderRef.length ? orderRef : record.requestID, PPDeliveryStatusText(record.status)] preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Delivery_AssignDriver") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self promptAssignDriver:record];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Delivery_MarkCompleted") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self completeRecord:record];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Delivery_CancelRequest") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self cancelRecord:record];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptAssignDriver:(PPDeliveryRequestRecord *)record {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Delivery_AssignDriver") message:kLang(@"Delivery_EnterDriverUID") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Delivery_DriverUIDPlaceholder");
        tf.textAlignment = [Language alignmentForCurrentLanguage];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Confirm") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *driverUID = alert.textFields.firstObject.text;
        if (driverUID.length == 0) return;
        [[PPDeliveryService shared] assignDriver:record.requestID driverUID:driverUID completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                } else {
                    [PPFunc pp_playSuccessEffect];
                    [self loadData];
                }
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)completeRecord:(PPDeliveryRequestRecord *)record {
    [[PPDeliveryService shared] completeRequest:record.requestID completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                [PPFunc pp_playSuccessEffect];
                [self loadData];
            }
        });
    }];
}

- (void)cancelRecord:(PPDeliveryRequestRecord *)record {
    [[PPDeliveryService shared] cancelRequest:record.requestID completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                [PPFunc pp_playSuccessEffect];
                [self loadData];
            }
        });
    }];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0.0, 18.0);
    [UIView animateWithDuration:0.42 delay:MIN(indexPath.row * 0.026, 0.20) usingSpringWithDamping:0.86 initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
