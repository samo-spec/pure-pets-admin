#import "PPStaffPreviewViewController.h"
#import "PPStaffAuth.h"
#import "UserModel.h"
#import "Styling.h"
#import "Language.h"
#import "FUManager.h"
@import Firebase;
@import FirebaseFirestore;

static NSString * const PPPreviewStaffCellID = @"PPPreviewStaffCell";
static NSString * const PPPreviewPermCellID  = @"PPPreviewPermCell";

@interface PPStaffPreviewPermissionModule : NSObject
@property (nonatomic, copy) NSString *localizedKey;
@property (nonatomic, copy) NSArray<NSString *> *requiredPerms;
- (instancetype)initWithKey:(NSString *)key perms:(NSArray<NSString *> *)perms;
@end

@implementation PPStaffPreviewPermissionModule
- (instancetype)initWithKey:(NSString *)key perms:(NSArray<NSString *> *)perms {
    self = [super init];
    if (self) { _localizedKey = key; _requiredPerms = perms; }
    return self;
}
@end

#pragma mark -

@interface PPStaffPreviewViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *staffTable;
@property (nonatomic, strong) UIScrollView *detailScroll;
@property (nonatomic, strong) UIView *detailContent;

@property (nonatomic, strong) NSArray<PPStaffDoc *> *allStaff;
@property (nonatomic, strong) NSArray<PPStaffDoc *> *filteredStaff;
@property (nonatomic, strong) PPStaffDoc *selectedStaff;
@property (nonatomic, strong) NSArray<PPStaffPreviewPermissionModule *> *modules;

@property (nonatomic, assign) BOOL showingDetail;

@end

@implementation PPStaffPreviewViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    [self pp_buildModules];
    [self pp_buildUI];
    [self pp_fetchStaff];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

#pragma mark - Modules Definition

- (void)pp_buildModules {
    self.modules = @[
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Dashboard"
                                                      perms:@[kStaffPermDashboardView]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Staff"
                                                      perms:@[kStaffPermStaffView, kStaffPermStaffManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Users"
                                                      perms:@[kStaffPermUsersView, kStaffPermUsersManage,
                                                              kStaffPermUsersBlock, kStaffPermUsersFeaturesView,
                                                              kStaffPermUsersFeaturesManage, kStaffPermUsersSubscriptionsView,
                                                              kStaffPermUsersSubscriptionsManage, kStaffPermUsersRestrictionsView,
                                                              kStaffPermUsersRestrictionsManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Stock"
                                                      perms:@[kStaffPermStockView, kStaffPermStockManage,
                                                              kStaffPermStockCreate, kStaffPermStockDelete]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Listings"
                                                      perms:@[kStaffPermListingsView, kStaffPermListingsManage,
                                                              kStaffPermListingsModerate]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Payments"
                                                      perms:@[kStaffPermPaymentsView, kStaffPermPaymentsManage,
                                                              kStaffPermPaymentsRefund]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_POS"
                                                      perms:@[kStaffPermPosView, kStaffPermPosSell, kStaffPermPosHistory]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Branches"
                                                      perms:@[kStaffPermBranchesView, kStaffPermBranchesManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Agents"
                                                      perms:@[kStaffPermAgentsView, kStaffPermAgentsManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Support"
                                                      perms:@[kStaffPermSupportView, kStaffPermSupportManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Services"
                                                      perms:@[kStaffPermServicesView, kStaffPermServicesManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Providers"
                                                      perms:@[kStaffPermProvidersView, kStaffPermProvidersManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Settings"
                                                      perms:@[kStaffPermSettingsView, kStaffPermSettingsManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Notifications"
                                                      perms:@[kStaffPermNotificationsView, kStaffPermNotificationsSend]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Accounting"
                                                      perms:@[kStaffPermAccountingView, kStaffPermAccountingManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Reports"
                                                      perms:@[kStaffPermReportsView, kStaffPermReportsExport]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Audit"
                                                      perms:@[kStaffPermAuditView]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Moderation"
                                                      perms:@[kStaffPermModerationView, kStaffPermModerationManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Banners"
                                                      perms:@[kStaffPermBannersView, kStaffPermBannersManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Categories"
                                                      perms:@[kStaffPermCategoriesView, kStaffPermCategoriesManage]],
        [[PPStaffPreviewPermissionModule alloc] initWithKey:@"Staff_Module_Veterinarians"
                                                      perms:@[kStaffPermVeterinariansView, kStaffPermVeterinariansManage]],
    ];
}

#pragma mark - Build UI

- (void)pp_buildUI {
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectZero];
    search.placeholder = kLang(@"Search");
    search.delegate = self;
    search.searchBarStyle = UISearchBarStyleMinimal;
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.backgroundColor = AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
    search.layer.cornerRadius = 10;
    search.clipsToBounds = YES;
    [self.view addSubview:search];
    self.searchBar = search;

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.dataSource = self;
    table.delegate = self;
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.translatesAutoresizingMaskIntoConstraints = NO;
    [table registerClass:UITableViewCell.class forCellReuseIdentifier:PPPreviewStaffCellID];
    [self.view addSubview:table];
    self.staffTable = table;

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.backgroundColor = UIColor.clearColor;
    scroll.hidden = YES;
    [self.view addSubview:scroll];
    self.detailScroll = scroll;

    UIView *detailContent = [[UIView alloc] initWithFrame:CGRectZero];
    detailContent.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:detailContent];
    self.detailContent = detailContent;

    [NSLayoutConstraint activateConstraints:@[
        [search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [search.heightAnchor constraintEqualToConstant:44],

        [table.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:4],
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [scroll.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [detailContent.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [detailContent.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [detailContent.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [detailContent.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [detailContent.widthAnchor constraintEqualToAnchor:scroll.widthAnchor],
    ]];
}

- (void)pp_showDetailForStaff:(PPStaffDoc *)staff {
    self.selectedStaff = staff;
    self.showingDetail = YES;

    for (UIView *sub in self.detailContent.subviews) {
        [sub removeFromSuperview];
    }

    UIColor *primary = AppPrimaryClr ?: UIColor.systemBlueColor;
    UIColor *textCol = PrimaryTextClr ?: UIColor.labelColor;
    UIColor *secondaryCol = SeconderyTextClr ?: UIColor.secondaryLabelColor;
    UIColor *surface = AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;

    CGFloat y = 0;
    CGFloat pad = 16;
    CGFloat w = self.view.bounds.size.width - pad * 2;

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w, 28)];
    nameLabel.text = staff.uid;
    nameLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:22];
    nameLabel.textColor = textCol;
    [self.detailContent addSubview:nameLabel];
    y += 32;

    UIView *roleCard = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w, 44)];
    roleCard.backgroundColor = surface;
    roleCard.layer.cornerRadius = 10;
    [self.detailContent addSubview:roleCard];

    UILabel *roleTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 80, 44)];
    roleTitle.text = kLang(@"Staff_Role_Effective");
    roleTitle.font = [UIFont fontWithName:@"Beiruti-Medium" size:14];
    roleTitle.textColor = secondaryCol;
    [roleCard addSubview:roleTitle];

    UILabel *roleValue = [[UILabel alloc] initWithFrame:CGRectMake(100, 0, w - 112, 44)];
    roleValue.text = [PPStaffAuth localizedRoleName:staff.role] ?: staff.role;
    roleValue.font = [UIFont fontWithName:@"Beiruti-Medium" size:16];
    roleValue.textColor = primary;
    roleValue.textAlignment = NSTextAlignmentRight;
    [roleCard addSubview:roleValue];
    y += 52;

    UIView *statusCard = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w, 44)];
    statusCard.backgroundColor = surface;
    statusCard.layer.cornerRadius = 10;
    [self.detailContent addSubview:statusCard];

    UILabel *statusTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 80, 44)];
    statusTitle.text = kLang(@"Staff_Status_Label");
    statusTitle.font = [UIFont fontWithName:@"Beiruti-Medium" size:14];
    statusTitle.textColor = secondaryCol;
    [statusCard addSubview:statusTitle];

    BOOL isActive = staff.isActive;
    UIColor *statusColor = isActive ? UIColor.systemGreenColor : UIColor.systemRedColor;
    NSString *statusText = isActive ? kLang(@"Active") : kLang(@"Disabled");

    UILabel *statusValue = [[UILabel alloc] initWithFrame:CGRectMake(100, 0, w - 112, 44)];
    statusValue.text = statusText;
    statusValue.font = [UIFont fontWithName:@"Beiruti-Medium" size:16];
    statusValue.textColor = statusColor;
    statusValue.textAlignment = NSTextAlignmentRight;
    [statusCard addSubview:statusValue];
    y += 52;

    UIView *scopeCard = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w, 44)];
    scopeCard.backgroundColor = surface;
    scopeCard.layer.cornerRadius = 10;
    [self.detailContent addSubview:scopeCard];

    UILabel *scopeTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 80, 44)];
    scopeTitle.text = @"Scope";
    scopeTitle.font = [UIFont fontWithName:@"Beiruti-Medium" size:14];
    scopeTitle.textColor = secondaryCol;
    [scopeCard addSubview:scopeTitle];

    NSString *scopeText = kLang(@"Staff_Scope_Global");
    if (staff.scope && [staff.scope isKindOfClass:NSDictionary.class] && staff.scope.count > 0) {
        scopeText = kLang(@"Staff_Scope_Limited");
    }

    UILabel *scopeValue = [[UILabel alloc] initWithFrame:CGRectMake(100, 0, w - 112, 44)];
    scopeValue.text = scopeText;
    scopeValue.font = [UIFont fontWithName:@"Beiruti-Medium" size:16];
    scopeValue.textColor = textCol;
    scopeValue.textAlignment = NSTextAlignmentRight;
    [scopeCard addSubview:scopeValue];
    y += 52;

    UILabel *permHeader = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w, 30)];
    permHeader.text = kLang(@"Staff_Permissions_Breakdown");
    permHeader.font = [UIFont fontWithName:@"Beiruti-Bold" size:18];
    permHeader.textColor = textCol;
    [self.detailContent addSubview:permHeader];
    y += 38;

    for (PPStaffPreviewPermissionModule *mod in self.modules) {
        CGFloat cardH = [self pp_heightForModuleCard:mod];
        UIView *card = [self pp_buildModuleCard:mod frame:CGRectMake(pad, y, w, cardH)];
        [self.detailContent addSubview:card];
        y += cardH + 8;
    }

    y += 20;

    self.detailContent.frame = CGRectMake(0, 0, self.view.bounds.size.width, y);
    self.detailScroll.contentSize = CGSizeMake(self.view.bounds.size.width, y);

    self.staffTable.hidden = YES;
    self.detailScroll.hidden = NO;
    [self.detailScroll scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
}

- (CGFloat)pp_heightForModuleCard:(PPStaffPreviewPermissionModule *)mod {
    CGFloat base = 36;
    NSUInteger perms = mod.requiredPerms.count;
    if (perms <= 4) return base;
    return base + (ceil((CGFloat)(perms - 4) / 4.0) * 28);
}

- (UIView *)pp_buildModuleCard:(PPStaffPreviewPermissionModule *)mod frame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 10;

    UIColor *textCol = PrimaryTextClr ?: UIColor.labelColor;
    UIColor *secondaryCol = SeconderyTextClr ?: UIColor.secondaryLabelColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, frame.size.width - 24, 22)];
    title.text = kLang(mod.localizedKey);
    title.font = [UIFont fontWithName:@"Beiruti-Medium" size:15];
    title.textColor = textCol;
    [card addSubview:title];

    CGFloat px = 12;
    CGFloat py = 34;
    CGFloat tagH = 24;

    for (NSString *perm in mod.requiredPerms) {
        BOOL granted = [self.selectedStaff hasPermission:perm];
        NSString *label = [self pp_shortPermName:perm];
        UIColor *bg = granted ? [UIColor.systemGreenColor colorWithAlphaComponent:0.15] : [UIColor.systemRedColor colorWithAlphaComponent:0.1];
        UIColor *fg = granted ? UIColor.systemGreenColor : UIColor.systemRedColor;

        UILabel *tag = [[UILabel alloc] initWithFrame:CGRectMake(px, py, 0, tagH)];
        tag.text = label;
        tag.font = [UIFont fontWithName:@"Beiruti-Regular" size:11];
        tag.textColor = fg;
        tag.backgroundColor = bg;
        tag.layer.cornerRadius = 6;
        tag.clipsToBounds = YES;
        tag.textAlignment = NSTextAlignmentCenter;
        [tag sizeToFit];
        CGRect tf = tag.frame;
        tf.size.width += 12;
        tf.size.height = tagH;
        if (tf.size.width < 50) tf.size.width = 50;
        if (px + tf.size.width + 6 > frame.size.width - 12) {
            px = 12;
            py += 28;
        }
        tf.origin.x = px;
        tf.origin.y = py;
        tag.frame = tf;
        px += tf.size.width + 6;
        [card addSubview:tag];
    }

    return card;
}

- (NSString *)pp_shortPermName:(NSString *)perm {
    if ([perm hasPrefix:@"kStaffPerm"]) {
        return [perm substringFromIndex:10];
    }
    return perm;
}

#pragma mark - Fetch Staff

- (void)pp_fetchStaff {
    [[PPStaffAuth shared] fetchAllStaff:^(NSArray<PPStaffDoc *> * _Nullable docs, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                return;
            }
            self.allStaff = docs ?: @[];
            self.filteredStaff = self.allStaff;
            [self.staffTable reloadData];
        });
    }];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredStaff = self.allStaff;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"uid CONTAINS[cd] %@", searchText];
        self.filteredStaff = [self.allStaff filteredArrayUsingPredicate:pred];
    }
    [self.staffTable reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredStaff.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:PPPreviewStaffCellID forIndexPath:indexPath];
    PPStaffDoc *staff = self.filteredStaff[indexPath.row];

    cell.textLabel.text = staff.uid;
    cell.textLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:16];
    cell.textLabel.textColor = PrimaryTextClr ?: UIColor.labelColor;

    NSString *roleName = [PPStaffAuth localizedRoleName:staff.role] ?: staff.role;
    cell.detailTextLabel.text = roleName;
    cell.detailTextLabel.font = [UIFont fontWithName:@"Beiruti-Regular" size:13];
    cell.detailTextLabel.textColor = SeconderyTextClr ?: UIColor.secondaryLabelColor;

    cell.backgroundColor = UIColor.clearColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UIView *sel = [[UIView alloc] init];
    sel.backgroundColor = [AppPrimaryClr ?: UIColor.systemBlueColor colorWithAlphaComponent:0.1];
    cell.selectedBackgroundView = sel;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PPStaffDoc *staff = self.filteredStaff[indexPath.row];
    [self.searchBar resignFirstResponder];
    [self pp_showDetailForStaff:staff];
}

@end
