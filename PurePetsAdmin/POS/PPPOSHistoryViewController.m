#import "PPPOSHistoryViewController.h"
#import "PPPOSService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"

@interface PPPOSHistoryViewController ()
@property (nonatomic, strong) NSArray<PPPOSReceipt *> *receipts;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPPOSHistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"POS_History_Title");
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorInset = UIEdgeInsetsZero;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self loadData];
}

- (void)loadData {
    self.isLoading = YES;
    __weak typeof(self) weakSelf = self;
    [[PPPOSService shared] fetchPOSHistoryWithCompletion:^(NSArray<PPPOSReceipt *> *receipts, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.receipts = receipts;
            [weakSelf.tableView reloadData];
        });
    }];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.receipts.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (self.receipts.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"POS_History_Empty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    PPPOSReceipt *receipt = self.receipts[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"#%@ — %.2f", receipt.receiptID, receipt.total];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@", receipt.paymentMethod, receipt.createdAt ? [NSDateFormatter localizedStringFromDate:receipt.createdAt dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @"—"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
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
