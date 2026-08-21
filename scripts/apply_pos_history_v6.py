#!/usr/bin/env python3
from pathlib import Path

path = Path("PurePetsAdmin/POS/PPPOSHistoryViewController.m")
text = path.read_text()


def replace(old: str, new: str, count: int = 1) -> None:
    global text
    if text.count(old) < count:
        raise RuntimeError(f"Missing POS History block: {old[:120]!r}")
    text = text.replace(old, new, count)

helpers = r'''
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
'''
replace('static NSString *const kPPPOSHistoryCellID = @"PPPOSHistoryCell";\n', 'static NSString *const kPPPOSHistoryCellID = @"PPPOSHistoryCell";\n' + helpers + '\n')

replace(
    "@property (nonatomic, assign) BOOL isLoading;\n@property (nonatomic, copy) NSString *errorMessage;",
    "@property (nonatomic, assign) BOOL isLoading;\n@property (nonatomic, copy) NSString *errorMessage;\n@property (nonatomic, strong) UIBarButtonItem *refreshButton;",
)
replace(
    "@implementation PPPOSHistoryViewController\n\n- (void)viewDidLoad {",
    "@implementation PPPOSHistoryViewController\n\n- (instancetype)init {\n    return [super initWithStyle:UITableViewStyleInsetGrouped];\n}\n\n- (void)viewDidLoad {",
)
replace("    self.tableView.estimatedRowHeight = 86.0;", "    self.tableView.estimatedRowHeight = 76.0;")
replace("    self.tableView.contentInset = UIEdgeInsetsMake(12.0, 0.0, 24.0, 0.0);", "    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceSM, 0.0, PPSpaceXL, 0.0);\n    self.tableView.separatorColor = [UIColor ppSurfaceBorder];\n    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = PPSpaceSM;")
replace(
    "    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];\n    refreshBtn.accessibilityLabel = kLang(@\"DC_Refresh\");\n    self.navigationItem.rightBarButtonItem = refreshBtn;",
    "    self.refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];\n    self.refreshButton.accessibilityLabel = kLang(@\"DC_Refresh\");\n    self.navigationItem.rightBarButtonItem = self.refreshButton;",
)
replace(
    "- (void)loadData {\n    self.isLoading = YES;",
    "- (void)loadData {\n    if (self.isLoading) return;\n    self.isLoading = YES;\n    self.refreshButton.enabled = NO;\n    PPCommandCenterNavigationItemsDidChange(self);",
)
replace(
    "            weakSelf.isLoading = NO;\n            if (error) {\n                weakSelf.errorMessage = error.localizedDescription;\n                [weakSelf.tableView reloadData];\n                [AlertHelper showAlertIn:weakSelf title:kLang(@\"Error_Title\") subtitle:error.localizedDescription];\n                return;\n            }",
    "            weakSelf.isLoading = NO;\n            weakSelf.refreshButton.enabled = YES;\n            PPCommandCenterNavigationItemsDidChange(weakSelf);\n            if (error) {\n                weakSelf.errorMessage = kLang(@\"POS_HistoryLoadFailed\");\n                [weakSelf.tableView reloadData];\n                return;\n            }",
)

# Calm grouped rows; no card-per-row wall.
replace("        cell.contentView.backgroundColor = AppForgroundColr;", "        cell.contentView.backgroundColor = [UIColor ppSurface];")
replace("        cell.contentView.layer.cornerRadius = 22.0;", "        cell.contentView.layer.cornerRadius = PPCorner16;")
replace("    cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:18.0]];", "    cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontHeadline]];")
replace("    cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:13.5]];", "    cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontSubheadline]];")

# Staff-facing content is localized and receipt detail is a real drill-in surface.
replace(
    "                                 receipt.paymentMethod.length ? receipt.paymentMethod : @\"-\",\n                                 receipt.createdAt ? [NSDateFormatter localizedStringFromDate:receipt.createdAt dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : @\"-\",",
    "                                 PPPOSHistoryPaymentMethodTitle(receipt.paymentMethod),\n                                 PPPOSHistoryDateTitle(receipt.createdAt),",
)
replace("    return self.receipts.count == 0 ? 104.0 : 88.0;", "    return UITableViewAutomaticDimension;")
replace(
    "    PPPOSReceipt *receipt = self.receipts[indexPath.row];\n    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@\"#%@\", receipt.receiptID] message:[NSString stringWithFormat:@\"%@: %.2f\\n%@: %@\\n%@: %ld\", kLang(@\"POS_Total\"), receipt.total, kLang(@\"POS_PaymentMethod\"), receipt.paymentMethod, kLang(@\"POS_Items\"), (long)receipt.items.count] preferredStyle:UIAlertControllerStyleAlert];\n    [alert addAction:[UIAlertAction actionWithTitle:kLang(@\"OK_Title\") style:UIAlertActionStyleDefault handler:nil]];\n    [self presentViewController:alert animated:YES completion:nil];",
    "    PPPOSReceipt *receipt = self.receipts[indexPath.row];\n    PPPOSReceiptDetailViewController *detail = [[PPPOSReceiptDetailViewController alloc] initWithReceipt:receipt];\n    [self.navigationController pushViewController:detail animated:YES];",
)

path.write_text(text)

strings = {
    Path("PurePetsAdmin/en.lproj/Localizable.strings"): {
        "POS_HistoryLoadFailed": "Couldn’t load sales history. Try again.",
        "POS_ReceiptSummary": "Receipt summary",
        "POS_ReceiptDate": "Date",
    },
    Path("PurePetsAdmin/ar.lproj/Localizable.strings"): {
        "POS_HistoryLoadFailed": "تعذر تحميل سجل المبيعات. حاول مرة أخرى.",
        "POS_ReceiptSummary": "ملخص الإيصال",
        "POS_ReceiptDate": "التاريخ",
    },
}
for strings_path, additions in strings.items():
    source = strings_path.read_text()
    for key, value in additions.items():
        if f'"{key}"' not in source:
            source += f'\n"{key}" = "{value}";\n'
    strings_path.write_text(source)

print("Applied POS History V6 pass.")
