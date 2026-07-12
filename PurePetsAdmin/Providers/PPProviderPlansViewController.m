#import "PPProviderPlansViewController.h"
#import "PPProviderService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

@interface PPProviderPlansViewController ()
@property (nonatomic, strong) NSArray<PPProviderPlan *> *plans;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPProviderPlansViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_Plans_Title");
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorInset = UIEdgeInsetsZero;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(didTapAdd)];
    self.navigationItem.rightBarButtonItem = addBtn;

    [self loadData];
}

- (void)loadData {
    self.isLoading = YES;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchPlansWithCompletion:^(NSArray<PPProviderPlan *> *plans, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.plans = plans;
            [weakSelf.tableView reloadData];
        });
    }];
}

- (void)didTapAdd {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Providers_Plans_New") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Providers_Plans_NameEn");
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Providers_Plans_NameAr");
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Providers_Plans_Price");
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Providers_Plans_CommissionRate");
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *nameEn = alert.textFields[0].text ?: @"";
        NSString *nameAr = alert.textFields[1].text ?: @"";
        double price = [alert.textFields[2].text doubleValue];
        double rate = [alert.textFields[3].text doubleValue];

        NSDictionary *planData = @{
            @"name": @{@"en": nameEn, @"ar": nameAr},
            @"price": @(price),
            @"platformCommissionRate": @(rate),
            @"status": @"active"
        };

        [[PPProviderService shared] savePlan:planData completion:^(NSString *planID, NSError *error) {
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

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.plans.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (self.plans.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Providers_Plans_Empty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    PPProviderPlan *plan = self.plans[indexPath.row];
    NSString *langCode = [Language currentLanguageCode];
    NSString *planName = [langCode isEqualToString:@"ar"] ? plan.name[@"ar"] : plan.name[@"en"];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ — %.2f", planName ?: plan.planID, plan.price.doubleValue];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %.0f%%", plan.billingInterval, plan.commissionRate * 100];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.plans.count) return;

    PPProviderPlan *plan = self.plans[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Providers_Plans_Actions") message:plan.planID preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[PPProviderService shared] deletePlan:plan.planID completion:^(NSError *error) {
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

@end
