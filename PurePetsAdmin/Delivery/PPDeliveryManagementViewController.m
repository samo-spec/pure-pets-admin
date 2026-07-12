#import "PPDeliveryManagementViewController.h"
#import "PPDeliveryService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

@interface PPDeliveryManagementViewController ()
@property (nonatomic, strong) NSArray<PPDeliveryRequestRecord *> *records;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, copy) NSString *statusFilter;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPDeliveryManagementViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Delivery_Title");
    self.statusFilter = @"all";
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorInset = UIEdgeInsetsZero;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];

    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[kLang(@"Delivery_All"), kLang(@"Delivery_Active"), kLang(@"Delivery_Completed"), kLang(@"Delivery_Cancelled")]];
    [self.filterSegment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.filterSegment;

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self loadData];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    NSArray *statuses = @[@"all", @"in_transit", @"delivered", @"cancelled"];
    self.statusFilter = statuses[sender.selectedSegmentIndex];
    [self.tableView reloadData];
}

- (void)loadData {
    self.isLoading = YES;
    __weak typeof(self) weakSelf = self;
    [[PPDeliveryService shared] fetchDeliveryRequestsWithCompletion:^(NSArray<PPDeliveryRequestRecord *> *records, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.records = records;
            [weakSelf.tableView reloadData];
        });
    }];
}

- (NSArray<PPDeliveryRequestRecord *> *)filteredRecords {
    if ([self.statusFilter isEqualToString:@"all"]) return self.records;
    return [self.records filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == %@", self.statusFilter]];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *filtered = [self filteredRecords];
    return MAX(filtered.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *filtered = [self filteredRecords];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (filtered.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Delivery_Empty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    PPDeliveryRequestRecord *record = filtered[indexPath.row];
    NSString *orderRef = record.orderNumber.length > 0 ? record.orderNumber : record.orderID;
    cell.textLabel.text = [NSString stringWithFormat:@"#%@ — %@", orderRef, record.status];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@", record.customerName ?: kLang(@"Delivery_UnknownCustomer"), record.deliveryFee ? [NSString stringWithFormat:@"%.2f", record.deliveryFee.doubleValue] : @"—"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Delivery_Actions") message:[NSString stringWithFormat:@"#%@ — %@", record.orderNumber ?: record.orderID, record.status] preferredStyle:UIAlertControllerStyleActionSheet];

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
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptAssignDriver:(PPDeliveryRequestRecord *)record {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Delivery_AssignDriver") message:kLang(@"Delivery_EnterDriverUID") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Driver UID";
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

@end
