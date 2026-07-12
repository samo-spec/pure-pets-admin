#import "PPProviderApplicationsViewController.h"
#import "PPProviderService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

@interface PPProviderApplicationsViewController ()
@property (nonatomic, strong) NSArray<PPProviderApplication *> *applications;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, copy) NSString *statusFilter;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPProviderApplicationsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_Applications_Title");
    self.statusFilter = @"all";
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];
    
    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[kLang(@"Providers_All"), kLang(@"Providers_Pending"), kLang(@"Providers_Approved"), kLang(@"Providers_Rejected")]];
    [self.filterSegment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.filterSegment;
    
    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refreshBtn;
    
    [self loadData];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    NSArray *statuses = @[@"all", @"pending", @"approved", @"rejected"];
    self.statusFilter = statuses[sender.selectedSegmentIndex];
    [self.tableView reloadData];
}

- (void)loadData {
    self.isLoading = YES;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchApplicationsWithCompletion:^(NSArray<PPProviderApplication *> *apps, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.applications = apps;
            [weakSelf.tableView reloadData];
        });
    }];
}

- (NSArray<PPProviderApplication *> *)filteredApps {
    if ([self.statusFilter isEqualToString:@"all"]) return self.applications;
    return [self.applications filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == %@", self.statusFilter]];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *filtered = [self filteredApps];
    return MAX(filtered.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *filtered = [self filteredApps];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    if (filtered.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Providers_Applications_Empty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    PPProviderApplication *app = filtered[indexPath.row];
    NSDictionary *form = app.form;
    NSString *name = form[@"fullName"] ?: form[@"businessName"] ?: form[@"companyName"] ?: app.userId;
    cell.textLabel.text = [NSString stringWithFormat:@"%@ — %@", name, app.providerType];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", app.status, app.applicationID];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *filtered = [self filteredApps];
    if (indexPath.row >= filtered.count) return;
    
    PPProviderApplication *app = filtered[indexPath.row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Providers_Review") message:[NSString stringWithFormat:@"%@: %@\nStatus: %@", app.providerType, app.form[@"fullName"] ?: app.userId, app.status] preferredStyle:UIAlertControllerStyleActionSheet];
    
    if ([app.status isEqualToString:@"pending"]) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_MarkUnderReview") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self reviewApp:app status:@"under_review"];
        }]];
    }
    if ([app.status isEqualToString:@"pending"] || [app.status isEqualToString:@"under_review"]) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Approve") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self reviewApp:app status:@"approved"];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Reject") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self reviewApp:app status:@"rejected"];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reviewApp:(PPProviderApplication *)app status:(NSString *)status {
    UIAlertController *notesAlert = [UIAlertController alertControllerWithTitle:kLang(@"Providers_ReviewNotes") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [notesAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Providers_ReviewNotesPlaceholder");
    }];
    [notesAlert addAction:[UIAlertAction actionWithTitle:kLang(@"Confirm") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *notes = notesAlert.textFields.firstObject.text;
        [[PPProviderService shared] reviewApplication:app.applicationID status:status notes:notes completion:^(NSError *error) {
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
    [notesAlert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:notesAlert animated:YES completion:nil];
}

@end