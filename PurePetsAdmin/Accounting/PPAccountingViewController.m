#import "PPAccountingViewController.h"
#import "PPAccountingService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "AppManager.h"
@import FirebaseFirestore;

@interface PPAccountingViewController ()
@property (nonatomic, strong) PPAccountingService *service;
@property (nonatomic, strong) NSArray<id<FIRListenerRegistration>> *listeners;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *currentFilter;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@end

@implementation PPAccountingViewController

- (void)dealloc {
    for (id<FIRListenerRegistration> reg in self.listeners) {
        [reg remove];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Accounting_Title");
    self.service = [PPAccountingService shared];
    self.listeners = @[];
    self.currentFilter = @"month";
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"MetricCell"];
    
    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[kLang(@"Accounting_ThisMonth"), kLang(@"Accounting_AllTime")]];
    self.filterSegment.selectedSegmentIndex = 0;
    [self.filterSegment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.filterSegment;
    
    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(didTapAddExpense)];
    self.navigationItem.rightBarButtonItem = addBtn;
    
    [self subscribeToData];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    self.currentFilter = sender.selectedSegmentIndex == 0 ? @"month" : @"all";
    [self subscribeToData];
}

- (void)subscribeToData {
    for (id<FIRListenerRegistration> reg in self.listeners) { [reg remove]; }
    self.isLoading = YES;
    
    __weak typeof(self) weakSelf = self;
    id<FIRListenerRegistration> txnReg = [self.service subscribeTransactionsWithFilter:self.currentFilter callback:^{
        [weakSelf dataUpdated];
    }];
    id<FIRListenerRegistration> expReg = [self.service subscribeExpensesWithFilter:self.currentFilter callback:^{
        [weakSelf dataUpdated];
    }];
    id<FIRListenerRegistration> revReg = [self.service subscribeOrderRevenueWithFilter:self.currentFilter callback:^{
        [weakSelf dataUpdated];
    }];
    self.listeners = @[txnReg, expReg, revReg];
}

- (void)dataUpdated {
    self.isLoading = NO;
    [self.tableView reloadData];
}

- (void)didTapAddExpense {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Accounting_AddExpense") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Accounting_Amount");
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Accounting_Description");
    }];
    
    NSArray *categories = @[@"salary", @"rent", @"supplies", @"utilities", @"marketing", @"other"];
    __block NSString *selectedCategory = @"other";
    
    UIAlertController *categoryPicker = [UIAlertController alertControllerWithTitle:kLang(@"Accounting_Category") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *cat in categories) {
        NSString *catKey = [NSString stringWithFormat:@"Accounting_Cat_%@", cat];
        [categoryPicker addAction:[UIAlertAction actionWithTitle:kLang(catKey) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            selectedCategory = cat;
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        double amount = [alert.textFields[0].text doubleValue];
        NSString *desc = alert.textFields[1].text ?: @"";
        if (amount <= 0) {
            [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"Accounting_InvalidAmount")];
            return;
        }
        [self.service addExpense:amount category:selectedCategory description:desc completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                } else {
                    [PPFunc pp_playSuccessEffect];
                }
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return MAX(self.service.transactions.count, 1);
    return MAX(self.service.expenses.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return kLang(@"Accounting_Overview");
    if (section == 1) return kLang(@"Accounting_Transactions");
    return kLang(@"Accounting_Expenses");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MetricCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        
        double revenue = self.service.orderRevenue;
        double expenses = 0;
        for (PPAccountingExpense *e in self.service.expenses) { expenses += e.amount; }
        double profit = revenue - expenses;
        
        if (indexPath.row == 0) {
            cell.textLabel.text = kLang(@"Accounting_Revenue");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", revenue, kLang(@"Accounting_QAR")];
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.circle.fill"];
            cell.imageView.tintColor = UIColor.systemGreenColor;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = kLang(@"Accounting_Expenses");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", expenses, kLang(@"Accounting_QAR")];
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.down.circle.fill"];
            cell.imageView.tintColor = UIColor.systemRedColor;
        } else {
            cell.textLabel.text = kLang(@"Accounting_Profit");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", profit, kLang(@"Accounting_QAR")];
            cell.imageView.image = [UIImage systemImageNamed:@"dollarsign.circle.fill"];
            cell.imageView.tintColor = profit >= 0 ? UIColor.systemGreenColor : UIColor.systemRedColor;
        }
        cell.textLabel.font = [Styling fontMedium:16];
        cell.detailTextLabel.font = [Styling fontBold:18];
        return cell;
    }
    
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
        cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        if (self.service.transactions.count == 0) {
            cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Accounting_NoTransactions");
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        PPAccountingTransaction *txn = self.service.transactions[indexPath.row];
        cell.textLabel.text = txn.desc.length > 0 ? txn.desc : [NSString stringWithFormat:@"%@ #%@", kLang(@"Accounting_Transaction"), txn.txnID];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", txn.amount, kLang(@"Accounting_QAR")];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    if (self.service.expenses.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Accounting_NoExpenses");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    PPAccountingExpense *exp = self.service.expenses[indexPath.row];
    NSString *catKey = [NSString stringWithFormat:@"Accounting_Cat_%@", exp.category];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ — %@", kLang(catKey), exp.desc];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", exp.amount, kLang(@"Accounting_QAR")];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

@end