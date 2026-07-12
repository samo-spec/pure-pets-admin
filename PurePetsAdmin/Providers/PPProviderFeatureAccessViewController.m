#import "PPProviderFeatureAccessViewController.h"
@import FirebaseFirestore;
@import FirebaseAuth;
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

@interface PPProviderFeatureAccessViewController ()
@property (nonatomic, strong) NSArray<FIRDocumentSnapshot *> *features;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPProviderFeatureAccessViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_Features_Title");
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorInset = UIEdgeInsetsZero;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self loadData];
}

- (void)loadData {
    self.isLoading = YES;
    FIRFirestore *db = [FIRFirestore firestore];
    __weak typeof(self) weakSelf = self;
    [[db collectionWithPath:@"providerFeatures"] getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.features = snapshot.documents;
            [weakSelf.tableView reloadData];
        });
    }];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.features.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (self.features.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Providers_Features_Empty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    FIRDocumentSnapshot *doc = self.features[indexPath.row];
    NSDictionary *data = doc.data;
    NSString *name = PPSafeString(data[@"name"]);
    NSString *providerType = PPSafeString(data[@"providerType"]);
    cell.textLabel.text = name.length > 0 ? name : doc.documentID;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@", providerType, PPSafeString(data[@"status"])];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
