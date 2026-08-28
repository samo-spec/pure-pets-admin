#import "PPContentModerationViewController.h"
#import "PPStaffAuth.h"
#import "PPAlertHelper.h"
#import "Styling.h"
#import "Language.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseFirestore;

static NSString *const kModerationCellID = @"ModerationCell";
static NSString *const kChatReportCellID = @"ChatReportCell";

#pragma mark - Moderation Item Model

@interface PPContentModerationItem : NSObject
@property (nonatomic, copy) NSString *documentID;
@property (nonatomic, copy) NSString *collectionName;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, copy, nullable) NSString *reportReason;
- (NSString *)sourceLabel;
- (UIColor *)sourceColor;
@end

@implementation PPContentModerationItem
- (NSString *)sourceLabel {
    if ([self.collectionName isEqualToString:@"pet_ads"]) return kLang(@"Moderation_Source_PetAd");
    if ([self.collectionName isEqualToString:@"adopt_pets"]) return kLang(@"Moderation_Source_Adoption");
    if ([self.collectionName isEqualToString:@"serviceOffers"]) return kLang(@"Moderation_Source_Service");
    return self.collectionName;
}
- (UIColor *)sourceColor {
    if ([self.collectionName isEqualToString:@"pet_ads"]) return [UIColor ppPrimary];
    if ([self.collectionName isEqualToString:@"adopt_pets"]) return [UIColor ppSuccess];
    if ([self.collectionName isEqualToString:@"serviceOffers"]) return [UIColor ppWarning];
    return [UIColor ppTextTertiary];
}
@end

#pragma mark - Chat Report Model

@interface PPChatReportItem : NSObject
@property (nonatomic, copy) NSString *documentID;
@property (nonatomic, copy) NSString *reporterUID;
@property (nonatomic, copy) NSString *reportedUserUID;
@property (nonatomic, copy) NSString *reason;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, copy, nullable) NSString *chatID;
@end

@implementation PPChatReportItem
@end

#pragma mark - View Controller

@interface PPContentModerationViewController ()
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) NSArray<PPContentModerationItem *> *contentItems;
@property (nonatomic, strong) NSArray<PPChatReportItem *> *chatReports;
@property (nonatomic, assign) BOOL hasAppeared;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, strong) id<FIRListenerRegistration> petAdsListener;
@property (nonatomic, strong) id<FIRListenerRegistration> adoptPetsListener;
@property (nonatomic, strong) id<FIRListenerRegistration> serviceOffersListener;
@property (nonatomic, strong) id<FIRListenerRegistration> chatReportsListener;
@property (nonatomic, assign) BOOL canManage;
@end

@implementation PPContentModerationViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupSegmentedControl];
    [self setupTableView];
    [self evaluatePermissions];
    [self loadContentQueue];
}

#pragma mark - Setup

- (void)setupSegmentedControl {
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[
        kLang(@"Moderation_ContentQueue"),
        kLang(@"Moderation_ChatReports")
    ]];
    self.segmentedControl.selectedSegmentIndex = 0;
    [self.segmentedControl addTarget:self action:@selector(segmentDidChange:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = kLang(@"Moderation_Title");
}

- (void)setupTableView {
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kModerationCellID];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kChatReportCellID];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    [self setupV6Header];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)setupV6Header {
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *chevronName = [Language isRTL] ? @"chevron.right" : @"chevron.left";
    UIImage *chevron = [UIImage systemImageNamed:chevronName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]];
    NSString *backText = [Language isRTL] ? @" رجوع" : @" Back";
    [backBtn setImage:chevron forState:UIControlStateNormal];
    [backBtn setTitle:backText forState:UIControlStateNormal];
    backBtn.tintColor = [UIColor ppPrimary];
    backBtn.titleLabel.font = [Styling fontBold:16];
    [backBtn setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [backBtn addTarget:self action:@selector(didTapBack) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:backBtn];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.font = [Styling fontBold:12];
    eyebrow.textColor = [UIColor ppTextSecondary];
    eyebrow.text = kLang(@"Moderation_Eyebrow");
    eyebrow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:eyebrow];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:22];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = kLang(@"Moderation_Title");
    titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    titleLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:titleLabel];
    
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.segmentedControl];

    [NSLayoutConstraint activateConstraints:@[
        [backBtn.topAnchor constraintEqualToAnchor:header.topAnchor constant:10],
        [backBtn.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [backBtn.heightAnchor constraintGreaterThanOrEqualToConstant:44],

        [eyebrow.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:10],
        [eyebrow.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [eyebrow.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],

        [titleLabel.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:4],
        [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        
        [self.segmentedControl.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:16],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [self.segmentedControl.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-16],
        [self.segmentedControl.heightAnchor constraintEqualToConstant:32]
    ]];

    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                withHorizontalFittingPriority:UILayoutPriorityRequired
                                      verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    header.frame = CGRectMake(0, 0, width, size.height);
    self.tableView.tableHeaderView = header;
}

- (void)didTapBack {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
}

- (void)evaluatePermissions {
    BOOL hasView = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermModerationView];
    BOOL hasManage = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermModerationManage];
    self.canManage = hasManage;
    if (!hasView && !hasManage) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - Data Loading

- (void)loadContentQueue {
    [self.petAdsListener remove]; self.petAdsListener = nil;
    [self.adoptPetsListener remove]; self.adoptPetsListener = nil;
    [self.serviceOffersListener remove]; self.serviceOffersListener = nil;
    [self.chatReportsListener remove]; self.chatReportsListener = nil;

    if (self.segmentedControl.selectedSegmentIndex == 0) {
        [self loadContentModerationItems];
    } else {
        [self loadChatReports];
    }
}

- (void)loadContentModerationItems {
    FIRFirestore *db = [FIRFirestore firestore];
    NSArray<NSString *> *statuses = @[@"flagged", @"pending_review", @"reported"];
    __block NSMutableArray<PPContentModerationItem *> *petAdsItems = [NSMutableArray array];
    __block NSMutableArray<PPContentModerationItem *> *adoptItems = [NSMutableArray array];
    __block NSMutableArray<PPContentModerationItem *> *serviceItems = [NSMutableArray array];
    PPweakify(self);

    self.petAdsListener = [[[[db collectionWithPath:@"pet_ads"]
        queryWhereField:@"status" in:statuses]
        queryOrderedByField:@"createdAt" descending:YES]
        addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        PPstrongify(self);
        if (error) return;
        petAdsItems = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            if (!doc.exists) continue;
            PPContentModerationItem *item = [self moderationItemFromDoc:doc collection:@"pet_ads"];
            if (item) [petAdsItems addObject:item];
        }
        [self mergeContentFromPetAds:petAdsItems adopt:adoptItems services:serviceItems];
    }];

    self.adoptPetsListener = [[[[db collectionWithPath:@"adopt_pets"]
        queryWhereField:@"status" in:statuses]
        queryOrderedByField:@"createdAt" descending:YES]
        addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        PPstrongify(self);
        if (error) return;
        adoptItems = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            if (!doc.exists) continue;
            PPContentModerationItem *item = [self moderationItemFromDoc:doc collection:@"adopt_pets"];
            if (item) [adoptItems addObject:item];
        }
        [self mergeContentFromPetAds:petAdsItems adopt:adoptItems services:serviceItems];
    }];

    self.serviceOffersListener = [[[[db collectionWithPath:@"serviceOffers"]
        queryWhereField:@"status" in:statuses]
        queryOrderedByField:@"createdAt" descending:YES]
        addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        PPstrongify(self);
        if (error) return;
        serviceItems = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            if (!doc.exists) continue;
            PPContentModerationItem *item = [self moderationItemFromDoc:doc collection:@"serviceOffers"];
            if (item) [serviceItems addObject:item];
        }
        [self mergeContentFromPetAds:petAdsItems adopt:adoptItems services:serviceItems];
    }];
}

- (PPContentModerationItem *)moderationItemFromDoc:(FIRDocumentSnapshot *)doc collection:(NSString *)collection {
    NSDictionary *data = doc.data;
    if (!data) return nil;
    PPContentModerationItem *item = [PPContentModerationItem new];
    item.documentID = doc.documentID;
    item.collectionName = collection;
    item.title = doc[@"title"] ?: doc[@"name"] ?: doc[@"serviceName"] ?: kLang(@"Unknown");
    item.status = doc[@"status"] ?: @"";
    item.reportReason = doc[@"reportReason"] ?: doc[@"rejectionReason"];
    item.createdAt = [doc[@"createdAt"] isKindOfClass:[FIRTimestamp class]]
        ? ((FIRTimestamp *)doc[@"createdAt"]).dateValue : [NSDate date];
    return item;
}

- (void)mergeContentFromPetAds:(NSArray<PPContentModerationItem *> *)petAds adopt:(NSArray<PPContentModerationItem *> *)adopt services:(NSArray<PPContentModerationItem *> *)services {
    [self.refreshControl endRefreshing];
    NSMutableArray *merged = [NSMutableArray array];
    [merged addObjectsFromArray:petAds];
    [merged addObjectsFromArray:adopt];
    [merged addObjectsFromArray:services];
    [merged sortUsingComparator:^NSComparisonResult(PPContentModerationItem *a, PPContentModerationItem *b) {
        return [b.createdAt compare:a.createdAt];
    }];
    self.contentItems = merged.copy;
    [self.tableView reloadData];
    [self runEntranceIfNeeded];
}

- (void)loadChatReports {
    FIRFirestore *db = [FIRFirestore firestore];
    self.contentItems = @[];
    [self.tableView reloadData];

    self.chatReportsListener = [[[db collectionWithPath:@"ChatReports"]
      queryOrderedByField:@"createdAt" descending:YES]
     addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        [self.refreshControl endRefreshing];
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
            return;
        }
        NSMutableArray<PPChatReportItem *> *reports = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            if (!doc.exists) continue;
            PPChatReportItem *report = [PPChatReportItem new];
            report.documentID = doc.documentID;
            report.reporterUID = doc[@"reporterUID"] ?: @"";
            report.reportedUserUID = doc[@"reportedUserUID"] ?: @"";
            report.reason = doc[@"reason"] ?: @"";
            report.status = doc[@"status"] ?: @"pending";
            report.chatID = doc[@"chatID"];
            report.createdAt = [doc[@"createdAt"] isKindOfClass:[FIRTimestamp class]]
                ? ((FIRTimestamp *)doc[@"createdAt"]).dateValue : [NSDate date];
            [reports addObject:report];
        }
        self.chatReports = [reports copy];
        [self.tableView reloadData];
        [self runEntranceIfNeeded];
    }];
}

- (void)refreshData {
    [self loadContentQueue];
}

- (void)segmentDidChange:(UISegmentedControl *)sender {
    [self loadContentQueue];
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        return MAX((NSInteger)self.contentItems.count, 1);
    }
    return MAX((NSInteger)self.chatReports.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.segmentedControl.selectedSegmentIndex == 0) {
        return [self contentCellForIndexPath:indexPath];
    }
    return [self chatReportCellForIndexPath:indexPath];
}

- (UITableViewCell *)contentCellForIndexPath:(NSIndexPath *)indexPath {
    if (self.contentItems.count == 0) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kModerationCellID forIndexPath:indexPath];
        cell.textLabel.text = kLang(@"Moderation_NoContent");
        cell.textLabel.textColor = [UIColor ppTextSecondary];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kModerationCellID forIndexPath:indexPath];
    PPContentModerationItem *item = self.contentItems[indexPath.row];

    UILabel *sourceBadge = [cell.contentView viewWithTag:100];
    if (!sourceBadge) {
        sourceBadge = [[UILabel alloc] init];
        sourceBadge.tag = 100;
        sourceBadge.font = PPFontBold(PPFontCaption2);
        sourceBadge.textColor = [UIColor whiteColor];
        sourceBadge.textAlignment = NSTextAlignmentCenter;
        sourceBadge.layer.cornerRadius = PPSpaceXS;
        sourceBadge.clipsToBounds = YES;
        sourceBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:sourceBadge];

        [NSLayoutConstraint activateConstraints:@[
            [sourceBadge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:PPSpaceMD],
            [sourceBadge.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD],
            [sourceBadge.widthAnchor constraintGreaterThanOrEqualToConstant:PPSpace4XL],
            [sourceBadge.heightAnchor constraintEqualToConstant:PPSpaceLG],
        ]];
    }
    sourceBadge.backgroundColor = [item sourceColor];
    sourceBadge.text = [item sourceLabel];

    UILabel *titleLabel = [cell.contentView viewWithTag:101];
    if (!titleLabel) {
        titleLabel = [[UILabel alloc] init];
        titleLabel.tag = 101;
        titleLabel.font = PPFontMedium(PPFontHeadline);
        titleLabel.numberOfLines = 2;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.leadingAnchor constraintEqualToAnchor:sourceBadge.trailingAnchor constant:PPSpaceSM],
            [titleLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD + 2],
            [titleLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPSpaceBase],
        ]];
    }
    titleLabel.text = item.title;

    UILabel *statusLabel = [cell.contentView viewWithTag:102];
    if (!statusLabel) {
        statusLabel = [[UILabel alloc] init];
        statusLabel.tag = 102;
        statusLabel.font = PPFontRegular(PPFontSubheadline);
        statusLabel.textColor = [UIColor ppTextSecondary];
        statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:statusLabel];

        [NSLayoutConstraint activateConstraints:@[
            [statusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [statusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:PPSpaceXXS],
            [statusLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [statusLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-PPSpaceMD - 2],
        ]];
    }
    NSString *statusKey = [item.status isEqualToString:@"flagged"] ? @"Moderation_Status_Flagged"
                         : [item.status isEqualToString:@"pending_review"] ? @"Moderation_Status_Pending"
                         : item.status;
    statusLabel.text = kLang(statusKey);

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    return cell;
}

- (UITableViewCell *)chatReportCellForIndexPath:(NSIndexPath *)indexPath {
    if (self.chatReports.count == 0) {
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kChatReportCellID forIndexPath:indexPath];
        cell.textLabel.text = kLang(@"Moderation_NoContent");
        cell.textLabel.textColor = [UIColor ppTextSecondary];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kChatReportCellID forIndexPath:indexPath];
    PPChatReportItem *report = self.chatReports[indexPath.row];

    UILabel *reasonLabel = [cell.contentView viewWithTag:200];
    if (!reasonLabel) {
        reasonLabel = [[UILabel alloc] init];
        reasonLabel.tag = 200;
        reasonLabel.font = PPFontMedium(PPFontHeadline);
        reasonLabel.numberOfLines = 2;
        reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:reasonLabel];

        [NSLayoutConstraint activateConstraints:@[
            [reasonLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:PPSpaceMD],
            [reasonLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD + 2],
            [reasonLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPSpaceBase],
        ]];
    }
    reasonLabel.text = report.reason.length > 0 ? report.reason : kLang(@"Unknown");

    UILabel *metaLabel = [cell.contentView viewWithTag:201];
    if (!metaLabel) {
        metaLabel = [[UILabel alloc] init];
        metaLabel.tag = 201;
        metaLabel.font = PPFontRegular(PPFontSubheadline);
        metaLabel.textColor = [UIColor ppTextSecondary];
        metaLabel.numberOfLines = 2;
        metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:metaLabel];

        [NSLayoutConstraint activateConstraints:@[
            [metaLabel.leadingAnchor constraintEqualToAnchor:reasonLabel.leadingAnchor],
            [metaLabel.topAnchor constraintEqualToAnchor:reasonLabel.bottomAnchor constant:PPSpaceXXS],
            [metaLabel.trailingAnchor constraintEqualToAnchor:reasonLabel.trailingAnchor],
            [metaLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-PPSpaceMD - 2],
        ]];
    }
    metaLabel.text = [NSString stringWithFormat:kLang(@"ChatReports_Meta_Format"), report.reporterUID, report.reportedUserUID];

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    return cell;
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.segmentedControl.selectedSegmentIndex == 0) {
        if (indexPath.row >= self.contentItems.count) return;
        PPContentModerationItem *item = self.contentItems[indexPath.row];
        [self showContentDetail:item];
    } else {
        if (indexPath.row >= self.chatReports.count) return;
        PPChatReportItem *report = self.chatReports[indexPath.row];
        [self showChatReportDetail:report];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.canManage) return nil;

    if (self.segmentedControl.selectedSegmentIndex == 0) {
        if (indexPath.row >= self.contentItems.count) return nil;
        PPContentModerationItem *item = self.contentItems[indexPath.row];

        UIContextualAction *approve = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
            title:kLang(@"Moderation_Approve") handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
            [self approveContent:item atIndex:indexPath];
            completion(YES);
        }];
        approve.backgroundColor = [UIColor ppSuccess];

        UIContextualAction *reject = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
            title:kLang(@"Moderation_Reject") handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
            [self rejectContent:item atIndex:indexPath];
            completion(YES);
        }];
        reject.backgroundColor = [UIColor ppError];

        return [UISwipeActionsConfiguration configurationWithActions:@[reject, approve]];
    }

    if (indexPath.row >= self.chatReports.count) return nil;
    PPChatReportItem *report = self.chatReports[indexPath.row];

    UIContextualAction *resolve = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:kLang(@"Moderation_Resolve") handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [self resolveChatReport:report atIndex:indexPath];
        completion(YES);
    }];
    resolve.backgroundColor = [UIColor ppPrimary];

    UIContextualAction *dismiss = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:kLang(@"Moderation_Dismiss") handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)) {
        [self dismissChatReport:report atIndex:indexPath];
        completion(YES);
    }];
    dismiss.backgroundColor = [UIColor ppTextTertiary];

    return [UISwipeActionsConfiguration configurationWithActions:@[dismiss, resolve]];
}

#pragma mark - Actions

- (void)approveContent:(PPContentModerationItem *)item atIndex:(NSIndexPath *)indexPath {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSDictionary *update = @{
        @"status": @"approved",
        @"moderatedBy": uid,
        @"moderatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    };

    [[[[FIRFirestore firestore] collectionWithPath:item.collectionName] documentWithPath:item.documentID]
     updateData:update completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"Moderation_Approve")];
            [self writeAuditLog:@"moderation.approve" item:item];
        }
    }];
}

- (void)rejectContent:(PPContentModerationItem *)item atIndex:(NSIndexPath *)indexPath {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSDictionary *update = @{
        @"status": @"rejected",
        @"moderatedBy": uid,
        @"moderatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    };

    [[[[FIRFirestore firestore] collectionWithPath:item.collectionName] documentWithPath:item.documentID]
     updateData:update completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"Moderation_Reject")];
            [self writeAuditLog:@"moderation.reject" item:item];
        }
    }];
}

- (void)resolveChatReport:(PPChatReportItem *)report atIndex:(NSIndexPath *)indexPath {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSDictionary *update = @{
        @"status": @"resolved",
        @"resolvedBy": uid,
        @"resolvedAt": [FIRFieldValue fieldValueForServerTimestamp],
    };

    [[[[FIRFirestore firestore] collectionWithPath:@"ChatReports"] documentWithPath:report.documentID]
     updateData:update completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"Moderation_Resolve")];
            [self writeAuditLog:@"chatReport.resolve" chatReport:report];
        }
    }];
}

- (void)dismissChatReport:(PPChatReportItem *)report atIndex:(NSIndexPath *)indexPath {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSDictionary *update = @{
        @"status": @"dismissed",
        @"dismissedBy": uid,
        @"dismissedAt": [FIRFieldValue fieldValueForServerTimestamp],
    };

    [[[[FIRFirestore firestore] collectionWithPath:@"ChatReports"] documentWithPath:report.documentID]
     updateData:update completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"Moderation_Dismiss")];
            [self writeAuditLog:@"chatReport.dismiss" chatReport:report];
        }
    }];
}

- (void)showContentDetail:(PPContentModerationItem *)item {
    [PPAlertHelper showInfoIn:self title:item.title subtitle:[NSString stringWithFormat:kLang(@"Moderation_Detail_Format"),
                 [item sourceLabel], item.documentID, item.status, item.reportReason ?: kLang(@"None")]];
}

- (void)showChatReportDetail:(PPChatReportItem *)report {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"ChatReports_Detail_Title")
        message:[NSString stringWithFormat:kLang(@"ChatReports_Detail_Format"),
                 report.reporterUID, report.reportedUserUID, report.reason, report.status]
        preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *resolve = [UIAlertAction actionWithTitle:kLang(@"Moderation_Resolve") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSInteger idx = [self.chatReports indexOfObjectIdenticalTo:report];
        if (idx == NSNotFound) return;
        NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:0];
        [self resolveChatReport:report atIndex:ip];
    }];
    UIAlertAction *dismiss = [UIAlertAction actionWithTitle:kLang(@"Moderation_Dismiss") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSInteger idx = [self.chatReports indexOfObjectIdenticalTo:report];
        if (idx == NSNotFound) return;
        NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:0];
        [self dismissChatReport:report atIndex:ip];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil];

    if (self.canManage) {
        [alert addAction:resolve];
        [alert addAction:dismiss];
    }
    [alert addAction:cancel];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.tableView;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Audit Log

- (void)writeAuditLog:(NSString *)action item:(PPContentModerationItem *)item {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
      setData:@{
        @"action": action ?: @"",
        @"targetCollection": item.collectionName ?: @"",
        @"targetId": item.documentID ?: @"",
        @"adminUid": uid,
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

- (void)writeAuditLog:(NSString *)action chatReport:(PPChatReportItem *)report {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
      setData:@{
        @"action": action ?: @"",
        @"targetCollection": @"ChatReports",
        @"targetId": report.documentID ?: @"",
        @"adminUid": uid,
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - Entrance Animation

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self runEntranceIfNeeded];
}

- (void)runEntranceIfNeeded {
    if (self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;

    [self.tableView.visibleCells enumerateObjectsUsingBlock:^(UITableViewCell *cell, NSUInteger idx, BOOL *stop) {
        cell.alpha = 0;
        cell.transform = CGAffineTransformMakeTranslation(0, 10);
        [UIView animateWithDuration:0.32 delay:0.08 + idx * 0.04 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (void)dealloc {
    [self.petAdsListener remove];
    [self.adoptPetsListener remove];
    [self.serviceOffersListener remove];
    [self.chatReportsListener remove];
}

@end
