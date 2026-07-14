#import "PPAuditLogViewController.h"
#import "PPAuditLogEntryModel.h"
#import "PPStaffAuth.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;

static NSString *const kAuditCellID = @"AuditCell";

static UIColor *PPAuditColorForAction(NSString *action) {
    if ([action hasPrefix:@"set_blocked"] || [action hasPrefix:@"set_unblocked"]) {
        return [action containsString:@"unblocked"] ? UIColor.systemGreenColor : UIColor.systemRedColor;
    }
    if ([action hasPrefix:@"set_permission"]) return UIColor.systemPurpleColor;
    if ([action hasPrefix:@"set_role"]) return UIColor.systemIndigoColor;
    if ([action hasPrefix:@"create_"]) return UIColor.systemBlueColor;
    if ([action hasPrefix:@"delete_"]) return UIColor.systemRedColor;
    if ([action hasPrefix:@"update_"]) return UIColor.systemOrangeColor;
    if ([action hasPrefix:@"set_admin"]) return UIColor.systemTealColor;
    return UIColor.systemGrayColor;
}

static NSString *PPAuditLocalizedAction(NSString *action) {
    if ([action isEqualToString:@"set_blocked"]) return kLang(@"Audit_ActionSetBlocked");
    if ([action isEqualToString:@"set_unblocked"]) return kLang(@"Audit_ActionSetUnblocked");
    if ([action isEqualToString:@"set_permission"]) return kLang(@"Audit_ActionSetPermission");
    if ([action isEqualToString:@"set_role"]) return kLang(@"Audit_ActionSetRole");
    if ([action isEqualToString:@"create_user"]) return kLang(@"Audit_ActionCreateUser");
    if ([action isEqualToString:@"delete_user"]) return kLang(@"Audit_ActionDeleteUser");
    if ([action isEqualToString:@"update_user"]) return kLang(@"Audit_ActionUpdateUser");
    return action;
}

static NSString *PPAuditFilterPrefixForSegment(NSInteger segment) {
    switch (segment) {
        case 1: return @"set_blocked";
        case 2: return @"set_unblocked";
        case 3: return @"set_permission";
        case 4: return @"set_role";
        case 5: return @"create_";
        case 6: return @"delete_";
        case 7: return @"update_";
        default: return @"";
    }
}

#pragma mark - JSON Detail Modal

@interface PPAuditJSONDetailViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
- (instancetype)initWithTitle:(NSString *)title json:(NSString *)json;
@end

@implementation PPAuditJSONDetailViewController
{
    NSString *_jsonText;
}

- (instancetype)initWithTitle:(NSString *)title json:(NSString *)json {
    self = [super init];
    if (self) {
        _jsonText = json ?: @"";
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissVC)];
    self.navigationItem.rightBarButtonItem = close;
    _textView = [[UITextView alloc] init];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.editable = NO;
    _textView.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont systemFontOfSize:12];
    _textView.textColor = [UIColor labelColor];
    _textView.backgroundColor = [UIColor systemBackgroundColor];
    _textView.text = _jsonText;
    _textView.contentInset = UIEdgeInsetsMake(PPSpaceBase, PPSpaceBase, PPSpaceBase, PPSpaceBase);
    [self.view addSubview:_textView];
    [NSLayoutConstraint activateConstraints:@[
        [_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)dismissVC {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - PPAuditLogViewController
@interface PPAuditLogViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *allEntries;
@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *filteredEntries;
@property (nonatomic, strong) id<FIRListenerRegistration> listenerReg;
@property (nonatomic, assign) BOOL hasAppeared;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, strong) UIView *heroHeaderView;
@property (nonatomic, strong) UILabel *heroTitleLabel;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, assign) NSInteger selectedFilterIndex;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation PPAuditLogViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.locale = [NSLocale currentLocale];
        [_dateFormatter setLocalizedDateFormatFromTemplate:@"d MMM yyyy h:mm a"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigation];
    [self setupTableView];
    [self evaluatePermissions];
    [self loadData];
}

- (void)setupNavigation {
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.title = kLang(@"Audit_Title");
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = kLang(@"SearchHere");
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
}

- (void)setupTableView {
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kAuditCellID];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)evaluatePermissions {
    BOOL hasView = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermAuditView];
    BOOL isAdmin = UsrMgr.currentUser.isSuperAdmin || UsrMgr.currentUser.isAdmin;
    if (!hasView && !isAdmin) {
        [PPHUD showError:kLang(@"Error_Title")];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)loadData {
    FIRQuery *query = [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"]
                        queryOrderedByField:@"timestamp" descending:YES]
                       queryLimitedTo:500];
    __weak typeof(self) weakSelf = self;
    self.listenerReg = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) {
            [PPHUD showError:kLang(@"Error_Title")];
            return;
        }
        NSMutableArray *entries = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPAuditLogEntryModel *entry = [PPAuditLogEntryModel entryFromSnapshot:doc];
            [entries addObject:entry];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allEntries = entries.copy;
            [self applyFilter];
        });
    }];
}

- (void)refreshData {
    if (self.listenerReg) {
        [self.listenerReg remove];
        self.listenerReg = nil;
    }
    [self loadData];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.refreshControl endRefreshing];
    });
}

- (void)applyFilter {
    NSString *searchText = _searchController.searchBar.text.lowercaseString;
    NSString *filterPrefix = PPAuditFilterPrefixForSegment(self.selectedFilterIndex);
    NSMutableArray *result = [NSMutableArray array];
    for (PPAuditLogEntryModel *entry in self.allEntries) {
        BOOL matchesFilter = filterPrefix.length == 0 || [entry.action hasPrefix:filterPrefix];
        if (!matchesFilter) continue;
        if (searchText.length > 0) {
            NSString *lcAction = entry.action.lowercaseString;
            NSString *lcAdmin = entry.adminUid.lowercaseString;
            NSString *lcTarget = entry.targetUid.lowercaseString;
            NSString *lcReason = entry.reason.lowercaseString;
            BOOL matchesSearch = [lcAction containsString:searchText] ||
                                 [lcAdmin containsString:searchText] ||
                                 [lcTarget containsString:searchText] ||
                                 (lcReason && [lcReason containsString:searchText]);
            if (!matchesSearch) continue;
        }
        [result addObject:entry];
    }
    self.filteredEntries = result.copy;
    [self.tableView reloadData];
    [self updateHero];
}

- (void)updateHero {
    NSInteger total = self.allEntries.count;
    NSInteger filtered = self.filteredEntries.count;
    BOOL isFiltered = filtered < total;
    if (isFiltered) {
        self.heroCountLabel.text = [NSString stringWithFormat:@"%ld / %ld", (long)filtered, (long)total];
    } else {
        self.heroCountLabel.text = [NSString stringWithFormat:@"%ld", (long)total];
    }
}

#pragma mark - Hero Header

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != 0) return nil;
    if (!self.heroHeaderView) {
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 200)];
        container.clipsToBounds = NO;
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor systemBackgroundColor];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        PPApplyContinuousCorners(card, PPCornerMedium);
        PPApplyCardShadow(card);
        [container addSubview:card];
        self.heroTitleLabel = [[UILabel alloc] init];
        self.heroTitleLabel.font = PPFontMedium(PPFontTitle2);
        self.heroTitleLabel.textColor = [UIColor labelColor];
        self.heroTitleLabel.text = kLang(@"Audit_Title");
        self.heroTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:self.heroTitleLabel];
        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.font = PPFontRegular(PPFontSubheadline);
        subtitle.textColor = [UIColor secondaryLabelColor];
        subtitle.text = kLang(@"Audit_Total");
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:subtitle];
        self.heroCountLabel = [[UILabel alloc] init];
        self.heroCountLabel.font = PPFontMedium(PPFontCallout);
        self.heroCountLabel.textColor = AppPrimaryClr;
        self.heroCountLabel.textAlignment = NSTextAlignmentNatural;
        self.heroCountLabel.text = @"0";
        self.heroCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:self.heroCountLabel];
        self.selectedFilterIndex = 0;
        _filterButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _filterButton.translatesAutoresizingMaskIntoConstraints = NO;
        _filterButton.backgroundColor = [UIColor systemGray5Color];
        _filterButton.tintColor = AppPrimaryClr;
        _filterButton.titleLabel.font = PPFontMedium(PPFontSubheadline);
        _filterButton.layer.cornerRadius = PPCornerMedium;
        _filterButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceLG, PPSpaceSM, PPSpaceLG);
        [_filterButton setTitle:kLang(@"Audit_AllActions") forState:UIControlStateNormal];
        _filterButton.showsMenuAsPrimaryAction = YES;
        NSMutableArray *menuActions = [NSMutableArray array];
        NSArray *filterLabels = @[
            kLang(@"Audit_AllActions"),
            kLang(@"Audit_ActionSetBlocked"),
            kLang(@"Audit_ActionSetUnblocked"),
            kLang(@"Audit_ActionSetPermission"),
            kLang(@"Audit_ActionSetRole"),
            kLang(@"Audit_ActionCreateUser"),
            kLang(@"Audit_ActionDeleteUser"),
            kLang(@"Audit_ActionUpdateUser"),
        ];
        [filterLabels enumerateObjectsUsingBlock:^(NSString *label, NSUInteger idx, BOOL *stop) {
            [menuActions addObject:[UIAction actionWithTitle:label image:nil identifier:nil handler:^(__kindof UIAction *action) {
                self.selectedFilterIndex = idx;
                [self.filterButton setTitle:label forState:UIControlStateNormal];
                [self applyFilter];
            }]];
        }];
        _filterButton.menu = [UIMenu menuWithTitle:kLang(@"Audit_AllActions") children:menuActions];
        [card addSubview:_filterButton];
        [NSLayoutConstraint activateConstraints:@[
            [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceBase],
            [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceBase],
            [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:PPSpaceMD],
            [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceSM],
            [self.heroTitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceLG],
            [self.heroTitleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceLG],
            [self.heroTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceLG],
            [subtitle.leadingAnchor constraintEqualToAnchor:self.heroTitleLabel.leadingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:self.heroTitleLabel.bottomAnchor constant:PPSpaceXS],
            [subtitle.trailingAnchor constraintEqualToAnchor:self.heroTitleLabel.trailingAnchor],
            [self.heroCountLabel.leadingAnchor constraintEqualToAnchor:self.heroTitleLabel.leadingAnchor],
            [self.heroCountLabel.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:PPSpaceSM],
            [self.heroCountLabel.trailingAnchor constraintEqualToAnchor:self.heroTitleLabel.trailingAnchor],
            [_filterButton.topAnchor constraintEqualToAnchor:self.heroCountLabel.bottomAnchor constant:PPSpaceMD],
            [_filterButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
            [_filterButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceMD],
        ]];
        self.heroHeaderView = container;
    }
    return self.heroHeaderView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 210 : UITableViewAutomaticDimension;
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, self.filteredEntries.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.filteredEntries.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAuditCellID forIndexPath:indexPath];
        cell.textLabel.text = kLang(@"Audit_NoEntries");
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    PPAuditLogEntryModel *entry = self.filteredEntries[indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAuditCellID forIndexPath:indexPath];
    UIView *badgeView = [cell.contentView viewWithTag:100];
    UILabel *badgeLabel = [cell.contentView viewWithTag:101];
    UILabel *adminLabel = [cell.contentView viewWithTag:102];
    UILabel *targetLabel = [cell.contentView viewWithTag:103];
    UILabel *timeLabel = [cell.contentView viewWithTag:104];
    UILabel *reasonLabel = [cell.contentView viewWithTag:105];
    if (!badgeView) {
        badgeView = [[UIView alloc] init];
        badgeView.tag = 100;
        badgeView.translatesAutoresizingMaskIntoConstraints = NO;
        badgeView.layer.cornerRadius = PPSpaceXS;
        badgeView.clipsToBounds = YES;
        [cell.contentView addSubview:badgeView];
        badgeLabel = [[UILabel alloc] init];
        badgeLabel.tag = 101;
        badgeLabel.font = PPFontBold(PPFontCaption1);
        badgeLabel.textColor = [UIColor whiteColor];
        badgeLabel.textAlignment = NSTextAlignmentCenter;
        badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [badgeView addSubview:badgeLabel];
        adminLabel = [[UILabel alloc] init];
        adminLabel.tag = 102;
        adminLabel.font = PPFontMedium(PPFontHeadline);
        adminLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:adminLabel];
        targetLabel = [[UILabel alloc] init];
        targetLabel.tag = 103;
        targetLabel.font = PPFontRegular(PPFontSubheadline);
        targetLabel.textColor = [UIColor secondaryLabelColor];
        targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:targetLabel];
        timeLabel = [[UILabel alloc] init];
        timeLabel.tag = 104;
        timeLabel.font = PPFontRegular(PPFontCaption1);
        timeLabel.textColor = [UIColor tertiaryLabelColor];
        timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:timeLabel];
        reasonLabel = [[UILabel alloc] init];
        reasonLabel.tag = 105;
        reasonLabel.font = PPFontRegular(PPFontCaption1);
        reasonLabel.textColor = [UIColor tertiaryLabelColor];
        reasonLabel.numberOfLines = 2;
        reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:reasonLabel];
        [NSLayoutConstraint activateConstraints:@[
            [badgeView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:PPSpaceMD],
            [badgeView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD],
            [badgeView.widthAnchor constraintGreaterThanOrEqualToConstant:80],
            [badgeView.heightAnchor constraintEqualToConstant:PPSpaceXXXL],
            [badgeLabel.centerXAnchor constraintEqualToAnchor:badgeView.centerXAnchor],
            [badgeLabel.centerYAnchor constraintEqualToAnchor:badgeView.centerYAnchor],
            [badgeLabel.leadingAnchor constraintEqualToAnchor:badgeView.leadingAnchor constant:PPSpaceSM],
            [badgeLabel.trailingAnchor constraintEqualToAnchor:badgeView.trailingAnchor constant:-PPSpaceSM],
            [adminLabel.leadingAnchor constraintEqualToAnchor:badgeView.trailingAnchor constant:PPSpaceMD],
            [adminLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD],
            [adminLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPSpaceBase],
            [targetLabel.leadingAnchor constraintEqualToAnchor:adminLabel.leadingAnchor],
            [targetLabel.topAnchor constraintEqualToAnchor:adminLabel.bottomAnchor constant:PPSpaceXXS],
            [targetLabel.trailingAnchor constraintEqualToAnchor:adminLabel.trailingAnchor],
            [timeLabel.leadingAnchor constraintEqualToAnchor:adminLabel.leadingAnchor],
            [timeLabel.topAnchor constraintEqualToAnchor:targetLabel.bottomAnchor constant:PPSpaceXXS],
            [timeLabel.trailingAnchor constraintEqualToAnchor:adminLabel.trailingAnchor],
            [reasonLabel.leadingAnchor constraintEqualToAnchor:adminLabel.leadingAnchor],
            [reasonLabel.topAnchor constraintEqualToAnchor:timeLabel.bottomAnchor constant:PPSpaceXXS],
            [reasonLabel.trailingAnchor constraintEqualToAnchor:adminLabel.trailingAnchor],
            [reasonLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-PPSpaceMD],
        ]];
    }
    UIColor *actionColor = PPAuditColorForAction(entry.action);
    badgeView.backgroundColor = actionColor;
    badgeLabel.text = PPAuditLocalizedAction(entry.action);
    adminLabel.text = [NSString stringWithFormat:@"%@: %@", kLang(@"Audit_Admin"), entry.adminUid];
    targetLabel.text = [NSString stringWithFormat:@"%@: %@", kLang(@"Audit_Target"), entry.targetUid];
    timeLabel.text = [entry formattedTimestamp];
    reasonLabel.text = entry.reason.length > 0 ? [NSString stringWithFormat:@"%@: %@", kLang(@"Audit_Reason"), entry.reason] : nil;
    UIView *selBg = [UIView new];
    selBg.backgroundColor = [[actionColor colorWithAlphaComponent:0.08] colorWithAlphaComponent:1.0];
    cell.selectedBackgroundView = selBg;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.filteredEntries.count == 0) return;
    PPAuditLogEntryModel *entry = self.filteredEntries[indexPath.row];
    [self showJSONDiffForEntry:entry];
}

#pragma mark - Actions

- (void)filterChanged {
    [self applyFilter];
}

- (void)showJSONDiffForEntry:(PPAuditLogEntryModel *)entry {
    NSMutableArray *actions = [NSMutableArray array];
    if (entry.before) {
        [actions addObject:[UIAlertAction actionWithTitle:kLang(@"Audit_Before") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self presentJSONModalWithTitle:kLang(@"Audit_Before") json:entry.before];
        }]];
    }
    if (entry.after) {
        [actions addObject:[UIAlertAction actionWithTitle:kLang(@"Audit_After") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self presentJSONModalWithTitle:kLang(@"Audit_After") json:entry.after];
        }]];
    }
    if (entry.before && entry.after) {
        [actions addObject:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ / %@", kLang(@"Audit_Before"), kLang(@"Audit_After")] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self presentCombinedJSONModalForEntry:entry];
        }]];
    }
    if (actions.count == 0) {
        [PPHUD showInfo:kLang(@"Audit_NoEntries")];
        return;
    }
    [actions addObject:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Audit_Title") message:entry.action preferredStyle:UIAlertControllerStyleActionSheet];
    for (UIAlertAction *act in actions) {
        [sheet addAction:act];
    }
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.tableView;
        NSIndexPath *selected = [self.tableView indexPathForSelectedRow];
        if (selected) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:selected];
            sheet.popoverPresentationController.sourceRect = cell.bounds;
        }
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentJSONModalWithTitle:(NSString *)title json:(NSDictionary *)json {
    NSString *jsonStr = @"{}";
    if (json) {
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&err];
        if (data && !err) {
            jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }
    PPAuditJSONDetailViewController *vc = [[PPAuditJSONDetailViewController alloc] initWithTitle:title json:jsonStr];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)presentCombinedJSONModalForEntry:(PPAuditLogEntryModel *)entry {
    NSMutableDictionary *combined = [NSMutableDictionary dictionary];
    if (entry.before) combined[@"before"] = entry.before;
    if (entry.after) combined[@"after"] = entry.after;
    [self presentJSONModalWithTitle:[NSString stringWithFormat:@"%@ / %@", kLang(@"Audit_Before"), kLang(@"Audit_After")] json:combined];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter];
}

#pragma mark - Entrance Animation

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self runEntranceIfNeeded];
}

- (void)runEntranceIfNeeded {
    if (self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;
    self.heroHeaderView.alpha = 0;
    self.heroHeaderView.transform = CGAffineTransformMakeTranslation(0, 14);
    [UIView animateWithDuration:0.42 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.heroHeaderView.alpha = 1;
        self.heroHeaderView.transform = CGAffineTransformIdentity;
    } completion:nil];
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
    [self.listenerReg remove];
}

@end
