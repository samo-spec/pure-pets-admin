#import "PPPOSHistoryViewController.h"
#import "PPPOSService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"

static NSString *const kPPPOSHistoryCellID = @"PPPOSHistoryCell";

@interface PPPOSHistoryViewController ()
@property (nonatomic, strong) NSArray<PPPOSReceipt *> *receipts;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@end

@implementation PPPOSHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"POS_History_Title");
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 86.0;
    self.tableView.contentInset = UIEdgeInsetsMake(12.0, 0.0, 24.0, 0.0);

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    refreshBtn.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self loadData];
}

- (void)loadData {
    self.isLoading = YES;
    self.errorMessage = nil;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[PPPOSService shared] fetchPOSHistoryWithCompletion:^(NSArray<PPPOSReceipt *> *receipts, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                weakSelf.errorMessage = error.localizedDescription;
                [weakSelf.tableView reloadData];
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
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
        cell.contentView.backgroundColor = AppForgroundColr;
        cell.contentView.layer.cornerRadius = 22.0;
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
    cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:18.0]];
    cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:13.5]];
    cell.textLabel.textColor = PrimaryTextClr;
    cell.detailTextLabel.textColor = SeconderyTextClr;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (self.receipts.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : (self.errorMessage.length ? kLang(@"Error_Title") : kLang(@"POS_History_Empty"));
        cell.detailTextLabel.text = self.errorMessage.length ? self.errorMessage : kLang(@"POS_History_Subtitle");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = self.errorMessage.length ? UIColor.systemRedColor : SeconderyTextClr;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = nil;
        return cell;
    }

    PPPOSReceipt *receipt = self.receipts[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"#%@  ·  %.2f %@", receipt.receiptID, receipt.total, kLang(@"Accounting_QAR")];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@  ·  %@ %ld",
                                 receipt.paymentMethod.length ? receipt.paymentMethod : @"-",
                                 receipt.createdAt ? [NSDateFormatter localizedStringFromDate:receipt.createdAt dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"-",
                                 kLang(@"POS_Items"),
                                 (long)receipt.items.count];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    cell.imageView.image = [[UIImage systemImageNamed:@"receipt.fill" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = AppPrimaryClr;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.receipts.count == 0 ? 104.0 : 88.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.receipts.count) return;

    PPPOSReceipt *receipt = self.receipts[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"#%@", receipt.receiptID] message:[NSString stringWithFormat:@"%@: %.2f\n%@: %@\n%@: %ld", kLang(@"POS_Total"), receipt.total, kLang(@"POS_PaymentMethod"), receipt.paymentMethod, kLang(@"POS_Items"), (long)receipt.items.count] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK_Title") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
