#import "PPProviderAccountingViewController.h"
@import FirebaseFirestore;
@import FirebaseAuth;
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"

@interface PPProviderCommissionRecord : NSObject
@property (nonatomic, copy) NSString *recordID;
@property (nonatomic, copy) NSString *providerID;
@property (nonatomic, assign) double amount;
@property (nonatomic, assign) double commission;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@implementation PPProviderCommissionRecord
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _recordID = docID ?: @"";
        _providerID = PPSafeString(dict[@"providerId"]);
        _amount = PPSafeDouble(dict[@"amount"]);
        _commission = PPSafeDouble(dict[@"commission"]);
        _status = PPSafeString(dict[@"status"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
    }
    return self;
}
@end

@interface PPProviderAccountingViewController ()
@property (nonatomic, strong) NSArray<PPProviderCommissionRecord *> *records;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPProviderAccountingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_Accounting_Title");
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
    [[[db collectionWithPath:@"providerCommissions"] queryOrderedByField:@"createdAt" descending:YES]
     getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            NSMutableArray *records = [NSMutableArray array];
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                [records addObject:[[PPProviderCommissionRecord alloc] initWithDictionary:doc.data documentID:doc.documentID]];
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (self.records.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : kLang(@"Providers_Accounting_Empty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    PPProviderCommissionRecord *r = self.records[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ — %.2f", r.providerID, r.amount];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %.2f | %@", kLang(@"Providers_Accounting_Commission"), r.commission, r.status];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

@end
