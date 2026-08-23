#import "PPPOSHistoryViewController.h"
#import "PPPOSService.h"
#import "Language.h"



static NSString *const kPPPOSHistoryCellID = @"PPPOSHistoryCell";

static NSString *PPPOSHistoryPaymentMethodTitle(NSString *rawValue) {
    NSString *normalized = [[rawValue ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([normalized isEqualToString:@"cash"]) return kLang(@"POS_Cash");
    if ([normalized isEqualToString:@"card"]) return kLang(@"POS_Card");
    return rawValue.length ? rawValue : @"—";
}

static NSString *PPPOSHistoryDateTitle(NSDate *date) {
    if (!date) return @"—";
    return [NSDateFormatter localizedStringFromDate:date
                                           dateStyle:NSDateFormatterMediumStyle
                                           timeStyle:NSDateFormatterShortStyle];
}

@interface PPPOSReceiptDetailViewController : UITableViewController
- (instancetype)initWithReceipt:(PPPOSReceipt *)receipt;
@end

@interface PPPOSReceiptDetailViewController ()
@property (nonatomic, strong) PPPOSReceipt *receipt;
@end

@implementation PPPOSReceiptDetailViewController

- (instancetype)initWithReceipt:(PPPOSReceipt *)receipt {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _receipt = receipt;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"#%@", self.receipt.receiptID ?: @""];
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;
    self.tableView.separatorColor = [UIColor ppSurfaceBorder];
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceSM, 0.0, PPSpaceXL, 0.0);
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = PPSpaceSM;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : self.receipt.items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? kLang(@"POS_ReceiptSummary") : kLang(@"POS_Items");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *identifier = indexPath.section == 0 ? @"POSReceiptSummaryRow" : @"POSReceiptItemRow";
    UITableViewCellStyle style = indexPath.section == 0 ? UITableViewCellStyleValue1 : UITableViewCellStyleSubtitle;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    cell.backgroundColor = [UIColor ppSurface];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = [UIColor ppTextPrimary];
    cell.detailTextLabel.textColor = [UIColor ppTextSecondary];
    cell.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
    cell.detailTextLabel.textAlignment = [Language alignmentForCurrentLanguage];

    if (indexPath.section == 0) {
        cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontCallout]];
        cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontCallout]];
        if (indexPath.row == 0) {
            cell.textLabel.text = kLang(@"POS_Total");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", self.receipt.total, kLang(@"Accounting_QAR")];
            cell.detailTextLabel.textColor = [UIColor ppPrimary];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = kLang(@"POS_PaymentMethod");
            cell.detailTextLabel.text = PPPOSHistoryPaymentMethodTitle(self.receipt.paymentMethod);
        } else {
            cell.textLabel.text = kLang(@"POS_ReceiptDate");
            cell.detailTextLabel.text = PPPOSHistoryDateTitle(self.receipt.createdAt);
        }
    } else {
        PPPOSCartItem *item = self.receipt.items[indexPath.row];
        cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontBody]];
        cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontSubheadline]];
        cell.textLabel.text = item.name.length ? item.name : item.itemID;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %ld  •  %.2f %@",
                                     kLang(@"POS_ItemQty"), (long)item.quantity,
                                     item.price * item.quantity, kLang(@"Accounting_QAR")];
        cell.detailTextLabel.numberOfLines = 2;
    }
    return cell;
}

@end


@interface PPPOSHistoryViewController ()
@property (nonatomic, strong) NSArray<PPPOSReceipt *> *receipts;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, strong) UIBarButtonItem *refreshButton;
@end

@implementation PPPOSHistoryViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"POS_History_Title");
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceSM, 0.0, PPSpaceXL, 0.0);
    self.tableView.separatorColor = [UIColor ppSurfaceBorder];
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = PPSpaceSM;

    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.refreshButton.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = self.refreshButton;
    PPCommandCenterNavigationItemsDidChange(self);

    [self loadData];
}

- (void)loadData {
    if (self.isLoading) return;
    self.isLoading = YES;
    self.refreshButton.enabled = NO;
    PPCommandCenterNavigationItemsDidChange(self);
    self.errorMessage = nil;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[PPPOSService shared] fetchPOSHistoryWithCompletion:^(NSArray<PPPOSReceipt *> *receipts, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            weakSelf.refreshButton.enabled = YES;
            PPCommandCenterNavigationItemsDidChange(weakSelf);
            if (error) {
                weakSelf.errorMessage = kLang(@"POS_HistoryLoadFailed");
                [weakSelf.tableView reloadData];
                return;
            }
            weakSelf.receipts = receipts ?: @[];
            [weakSelf.tableView reloadData];
        });
    }];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.receipts.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPPPOSHistoryCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kPPPOSHistoryCellID];
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = [UIColor ppSurface];
        cell.contentView.layer.cornerRadius = PPCorner16;
        cell.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        cell.contentView.layer.masksToBounds = YES;
        cell.textLabel.numberOfLines = 1;
        cell.detailTextLabel.numberOfLines = 2;
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    }
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
    cell.detailTextLabel.textAlignment = [Language alignmentForCurrentLanguage];
    cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontHeadline]];
    cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontSubheadline]];
    cell.textLabel.textColor = PrimaryTextClr;
    cell.detailTextLabel.textColor = SeconderyTextClr;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (self.receipts.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : (self.errorMessage.length ? kLang(@"Error_Title") : kLang(@"POS_History_Empty"));
        cell.detailTextLabel.text = self.errorMessage.length ? self.errorMessage : kLang(@"POS_History_Subtitle");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = self.errorMessage.length ? [UIColor ppError] : [UIColor ppTextSecondary];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = nil;
        return cell;
    }

    PPPOSReceipt *receipt = self.receipts[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"#%@  ·  %.2f %@", receipt.receiptID, receipt.total, kLang(@"Accounting_QAR")];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@  ·  %@ %ld",
                                 PPPOSHistoryPaymentMethodTitle(receipt.paymentMethod),
                                 PPPOSHistoryDateTitle(receipt.createdAt),
                                 kLang(@"POS_Items"),
                                 (long)receipt.items.count];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    cell.imageView.image = [[UIImage systemImageNamed:@"receipt.fill" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = AppPrimaryClr;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.receipts.count) return;

    PPPOSReceipt *receipt = self.receipts[indexPath.row];
    PPPOSReceiptDetailViewController *detail = [[PPPOSReceiptDetailViewController alloc] initWithReceipt:receipt];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
