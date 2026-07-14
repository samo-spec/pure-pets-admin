#import "PPProviderPlansViewController.h"
#import "PPProviderService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

static NSString *const kPPProviderPlanCellID = @"PPProviderPlanCell";

@interface PPProviderPlansViewController ()
@property (nonatomic, strong) NSArray<PPProviderPlan *> *plans;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@end

@implementation PPProviderPlansViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_Plans_Title");
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 86.0;
    self.tableView.contentInset = UIEdgeInsetsMake(12.0, 0.0, 24.0, 0.0);

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(didTapAdd)];
    addBtn.accessibilityLabel = kLang(@"Providers_Plans_New");
    self.navigationItem.rightBarButtonItem = addBtn;

    [self loadData];
}

- (void)loadData {
    self.isLoading = YES;
    self.errorMessage = nil;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchPlansWithCompletion:^(NSArray<PPProviderPlan *> *plans, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                weakSelf.errorMessage = error.localizedDescription;
                [weakSelf.tableView reloadData];
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.plans = plans ?: @[];
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPPProviderPlanCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kPPProviderPlanCellID];
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

    if (self.plans.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : (self.errorMessage.length ? kLang(@"Error_Title") : kLang(@"Providers_Plans_Empty"));
        cell.detailTextLabel.text = self.errorMessage.length ? self.errorMessage : kLang(@"Providers_Plans_Subtitle");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = self.errorMessage.length ? UIColor.systemRedColor : SeconderyTextClr;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = nil;
        return cell;
    }

    PPProviderPlan *plan = self.plans[indexPath.row];
    NSString *langCode = [Language currentLanguageCode];
    NSString *planName = [langCode isEqualToString:@"ar"] ? plan.name[@"ar"] : plan.name[@"en"];
    cell.textLabel.text = planName.length ? planName : plan.planID;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@  ·  %@  ·  %.0f%%",
                                 plan.price.doubleValue,
                                 kLang(@"Accounting_QAR"),
                                 plan.billingInterval.length ? plan.billingInterval : @"-",
                                 plan.commissionRate * 100.0];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    cell.imageView.image = [[UIImage systemImageNamed:@"rectangle.stack.badge.person.crop" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = AppPrimaryClr;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.plans.count == 0 ? 104.0 : 88.0;
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
