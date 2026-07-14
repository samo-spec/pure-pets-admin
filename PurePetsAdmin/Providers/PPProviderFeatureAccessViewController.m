#import "PPProviderFeatureAccessViewController.h"
@import FirebaseFirestore;
@import FirebaseAuth;
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

static NSString *const kPPProviderFeatureCellID = @"PPProviderFeatureCell";

@interface PPProviderFeatureAccessViewController ()
@property (nonatomic, strong) NSArray<FIRDocumentSnapshot *> *features;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@end

@implementation PPProviderFeatureAccessViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_Features_Title");
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 86.0;
    self.tableView.contentInset = UIEdgeInsetsMake(12.0, 0.0, 24.0, 0.0);

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    refreshBtn.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = refreshBtn;

    [self loadData];
}

- (void)loadData {
    self.isLoading = YES;
    self.errorMessage = nil;
    [self.tableView reloadData];
    FIRFirestore *db = [FIRFirestore firestore];
    __weak typeof(self) weakSelf = self;
    [[db collectionWithPath:@"providerFeatures"] getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                weakSelf.errorMessage = error.localizedDescription;
                [weakSelf.tableView reloadData];
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.features = snapshot.documents ?: @[];
            [weakSelf.tableView reloadData];
        });
    }];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.features.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPPProviderFeatureCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kPPProviderFeatureCellID];
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
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (self.features.count == 0) {
        cell.textLabel.text = self.isLoading ? kLang(@"Loading") : (self.errorMessage.length ? kLang(@"Error_Title") : kLang(@"Providers_Features_Empty"));
        cell.detailTextLabel.text = self.errorMessage.length ? self.errorMessage : kLang(@"Providers_Features_Subtitle");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = self.errorMessage.length ? UIColor.systemRedColor : SeconderyTextClr;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.imageView.image = nil;
        return cell;
    }

    FIRDocumentSnapshot *doc = self.features[indexPath.row];
    NSDictionary *data = doc.data;
    NSString *name = PPSafeString(data[@"name"]);
    NSString *providerType = PPSafeString(data[@"providerType"]);
    cell.textLabel.text = name.length > 0 ? name : doc.documentID;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@",
                                 providerType.length ? providerType : @"-",
                                 PPSafeString(data[@"status"]).length ? PPSafeString(data[@"status"]) : @"-"];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    cell.imageView.image = [[UIImage systemImageNamed:@"checkmark.shield.fill" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.tintColor = AppPrimaryClr;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.features.count == 0 ? 104.0 : 88.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
