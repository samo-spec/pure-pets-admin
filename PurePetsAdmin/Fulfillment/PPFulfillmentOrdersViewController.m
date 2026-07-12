#import "PPFulfillmentOrdersViewController.h"
#import "PPFulfillmentService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
@import FirebaseFirestore;

@interface PPFulfillmentOrdersViewController ()
@property (nonatomic, strong) NSArray<PPFulfillmentRecord *> *records;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSString *filterStatus;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPFulfillmentOrdersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Fulfillment_Title");
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorInset = UIEdgeInsetsZero;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = kLang(@"Fulfillment_SearchPlaceholder");
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
    
    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refreshBtn;
    
    [self loadData];
}

- (void)loadData {
    self.isLoading = YES;
    __weak typeof(self) weakSelf = self;
    [[PPFulfillmentService shared] fetchFulfillmentsWithCompletion:^(NSArray<PPFulfillmentRecord *> *records, NSError *error) {
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

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.records.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.records.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Fulfillment_Empty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    
    PPFulfillmentRecord *record = self.records[indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.textLabel.text = [NSString stringWithFormat:@"#%@ — %@", record.parentOrderNumber ?: record.fulfillmentID, record.status];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@ items", record.fulfillmentMode, @(record.items.count)];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.records.count) return;
    
    PPFulfillmentRecord *record = self.records[indexPath.row];
    UIViewController *detail = [self detailViewControllerForFulfillment:record];
    [self.navigationController pushViewController:detail animated:YES];
}

- (UIViewController *)detailViewControllerForFulfillment:(PPFulfillmentRecord *)record {
    UITableViewController *vc = [[UITableViewController alloc] initWithStyle:UITableViewStyleGrouped];
    vc.title = record.parentOrderNumber ?: record.fulfillmentID;
    
    __weak typeof(self) weakSelf = self;
    [[PPFulfillmentService shared] fetchFulfillmentDetail:record.fulfillmentID completion:^(PPFulfillmentRecord *detail, NSArray *events, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
        });
    }];
    
    return vc;
}

@end