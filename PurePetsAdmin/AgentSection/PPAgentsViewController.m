#import "PPAgentsViewController.h"
#import "PPAgentEditorViewController.h"
#import "PPAgentModel.h"
#import "PPStaffAuth.h"
#import "PPHUD.h"
#import "Language.h"
#import "Styling.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;

static NSString *const kAgentCellID = @"AgentCell";

@interface PPAgentsViewController ()
@property (nonatomic, strong) NSArray<PPAgentModel *> *agents;
@property (nonatomic, strong) NSArray<PPAgentModel *> *filteredAgents;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, strong) UIView *heroHeaderView;
@property (nonatomic, strong) UILabel *heroTitleLabel;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) id listenerRegistration;
@end

@implementation PPAgentsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigation];
    [self setupTableView];
    [self evaluatePermissions];
    [self startListening];
}

- (void)setupNavigation {
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.title = kLang(@"Agents_Title");
    
    if (self.canManage) {
        UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(didTapAdd)];
        self.navigationItem.rightBarButtonItem = addButton;
    }
}

- (void)setupTableView {
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kAgentCellID];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = kLang(@"Agents_Search");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)evaluatePermissions {
    BOOL hasView = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermAgentsView];
    BOOL hasManage = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermAgentsManage];
    self.canManage = hasManage;
    if (!hasView && !hasManage) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)startListening {
    PPweakify(self);
    FIRQuery *query = [[[FIRFirestore firestore] collectionWithPath:kPPAgentsCol]
                       queryOrderedByField:@"createdAt" descending:YES];
    self.listenerRegistration = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        PPstrongify(self);
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPAgentModel *agent = [PPAgentModel fromDictionary:doc.data withID:doc.documentID];
            if (agent) [items addObject:agent];
        }
        self.agents = items.copy;
        [self applyFilter];
    }];
}

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text;
    if (query.length == 0) {
        self.filteredAgents = self.agents;
    } else {
        NSString *q = query.lowercaseString;
        NSMutableArray *filtered = [NSMutableArray array];
        for (PPAgentModel *a in self.agents) {
            if ([a.nameEn.lowercaseString containsString:q] ||
                [a.nameAr containsString:q] ||
                [a.uid.lowercaseString containsString:q] ||
                [a.email.lowercaseString containsString:q] ||
                [a.phone containsString:q]) {
                [filtered addObject:a];
            }
        }
        self.filteredAgents = filtered.copy;
    }
    [self.tableView reloadData];
    [self updateHero];
}

- (void)updateHero {
    NSInteger total = self.filteredAgents.count;
    NSInteger active = 0;
    for (PPAgentModel *a in self.filteredAgents) {
        if (a.isActive) active++;
    }
    self.heroCountLabel.text = [NSString stringWithFormat:kLang(@"Agents_Count_Format"), (long)total, (long)active];
}

#pragma mark - Hero Header

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != 0) return nil;
    if (!self.heroHeaderView) {
        self.heroHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 120)];
        self.heroHeaderView.clipsToBounds = NO;
        
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor ppBackground];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        PPApplyContinuousCorners(card, PPCornerMedium);
        PPApplyCardShadow(card);
        [self.heroHeaderView addSubview:card];
        
        self.heroTitleLabel = [[UILabel alloc] init];
        self.heroTitleLabel.font = PPFontMedium(PPFontTitle2);
        self.heroTitleLabel.textColor = [UIColor ppTextPrimary];
        self.heroTitleLabel.text = kLang(@"Agents_Title");
        self.heroTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:self.heroTitleLabel];
        
        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.font = PPFontRegular(PPFontSubheadline);
        subtitle.textColor = [UIColor ppTextSecondary];
        subtitle.text = kLang(@"Agents_Subtitle");
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:subtitle];
        
        self.heroCountLabel = [[UILabel alloc] init];
        self.heroCountLabel.font = PPFontMedium(PPFontCallout);
        self.heroCountLabel.textColor = AppPrimaryClr;
        self.heroCountLabel.textAlignment = NSTextAlignmentNatural;
        self.heroCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:self.heroCountLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [card.leadingAnchor constraintEqualToAnchor:self.heroHeaderView.leadingAnchor constant:PPSpaceBase],
            [card.trailingAnchor constraintEqualToAnchor:self.heroHeaderView.trailingAnchor constant:-PPSpaceBase],
            [card.topAnchor constraintEqualToAnchor:self.heroHeaderView.topAnchor constant:PPSpaceMD],
            [card.bottomAnchor constraintEqualToAnchor:self.heroHeaderView.bottomAnchor constant:-PPSpaceSM],
            
            [self.heroTitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceLG],
            [self.heroTitleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceLG],
            [self.heroTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceLG],
            
            [subtitle.leadingAnchor constraintEqualToAnchor:self.heroTitleLabel.leadingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:self.heroTitleLabel.bottomAnchor constant:PPSpaceXS],
            [subtitle.trailingAnchor constraintEqualToAnchor:self.heroTitleLabel.trailingAnchor],
            
            [self.heroCountLabel.leadingAnchor constraintEqualToAnchor:self.heroTitleLabel.leadingAnchor],
            [self.heroCountLabel.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:PPSpaceSM],
            [self.heroCountLabel.trailingAnchor constraintEqualToAnchor:self.heroTitleLabel.trailingAnchor],
        ]];
    }
    return self.heroHeaderView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 130 : UITableViewAutomaticDimension;
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredAgents.count;
}

- (UIColor *)colorForRole:(PPAgentRole)role {
    switch (role) {
        case PPAgentRoleManager: return [UIColor ppPrimary];
        case PPAgentRoleCashier: return [UIColor ppWarning];
        case PPAgentRoleViewer:  return [UIColor ppTextTertiary];
        case PPAgentRoleSales:
        default:                 return AppPrimaryClr;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAgentCellID forIndexPath:indexPath];
    PPAgentModel *agent = self.filteredAgents[indexPath.row];
    UIColor *roleColor = [self colorForRole:agent.role];
    
    UIImageView *iconView = [cell.contentView viewWithTag:100];
    if (!iconView) {
        iconView = [[UIImageView alloc] init];
        iconView.tag = 100;
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        iconView.layer.cornerRadius = PPSpaceXL;
        iconView.clipsToBounds = YES;
        iconView.contentMode = UIViewContentModeCenter;
        iconView.tintColor = [UIColor whiteColor];
        [cell.contentView addSubview:iconView];
        
        [NSLayoutConstraint activateConstraints:@[
            [iconView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:PPSpaceMD],
            [iconView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [iconView.widthAnchor constraintEqualToConstant:PPSpace4XL],
            [iconView.heightAnchor constraintEqualToConstant:PPSpace4XL],
        ]];
    }
    iconView.backgroundColor = roleColor;
    iconView.image = [[UIImage systemImageNamed:@"person.text.rectangle"]
                      imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:PPSpaceLG weight:UIImageSymbolWeightMedium]];
    
    UILabel *nameLabel = [cell.contentView viewWithTag:101];
    if (!nameLabel) {
        nameLabel = [[UILabel alloc] init];
        nameLabel.tag = 101;
        nameLabel.font = PPFontMedium(PPFontHeadline);
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:nameLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [nameLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:PPSpaceMD],
            [nameLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD + 2],
            [nameLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPSpaceBase],
        ]];
    }
    nameLabel.text = [agent localizedName];
    nameLabel.textColor = agent.isActive ? [UIColor ppTextPrimary] : [UIColor ppTextTertiary];
    
    UILabel *detailLabel = [cell.contentView viewWithTag:102];
    if (!detailLabel) {
        detailLabel = [[UILabel alloc] init];
        detailLabel.tag = 102;
        detailLabel.font = PPFontRegular(PPFontSubheadline);
        detailLabel.textColor = [UIColor ppTextSecondary];
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:detailLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [detailLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
            [detailLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:PPSpaceXXS],
            [detailLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        ]];
    }
    detailLabel.text = [NSString stringWithFormat:@"%@ · %@", agent.uid, [agent localizedBranchName]];
    
    UILabel *metaLabel = [cell.contentView viewWithTag:103];
    if (!metaLabel) {
        metaLabel = [[UILabel alloc] init];
        metaLabel.tag = 103;
        metaLabel.font = PPFontRegular(PPFontCaption1);
        metaLabel.textColor = [UIColor ppTextTertiary];
        metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:metaLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [metaLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
            [metaLabel.topAnchor constraintEqualToAnchor:detailLabel.bottomAnchor constant:PPSpaceXXS],
            [metaLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
            [metaLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-PPSpaceMD - 2],
        ]];
    }
    metaLabel.text = [NSString stringWithFormat:@"%@: %@ · %@: %@%.0f%%",
                      kLang(@"Agents_Role"), [agent localizedRoleName],
                      kLang(@"Agents_Commission"),
                      agent.commissionRate > 0 ? @"" : @"0",
                      agent.commissionRate];
    
    UILabel *roleBadge = [cell.contentView viewWithTag:104];
    if (!roleBadge) {
        roleBadge = [[UILabel alloc] init];
        roleBadge.tag = 104;
        roleBadge.font = PPFontMedium(PPFontCaption2);
        roleBadge.textColor = [UIColor whiteColor];
        roleBadge.backgroundColor = roleColor;
        roleBadge.textAlignment = NSTextAlignmentCenter;
        roleBadge.layer.cornerRadius = PPSpaceXS;
        roleBadge.clipsToBounds = YES;
        roleBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:roleBadge];
        
        [NSLayoutConstraint activateConstraints:@[
            [roleBadge.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPSpaceMD],
            [roleBadge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [roleBadge.widthAnchor constraintGreaterThanOrEqualToConstant:PPSpace4XL + PPSpaceXS],
            [roleBadge.heightAnchor constraintEqualToConstant:PPSpaceLG + 4],
        ]];
    }
    roleBadge.text = [agent localizedRoleName];
    roleBadge.backgroundColor = roleColor;
    
    cell.accessoryType = self.canManage ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    
    UIView *selBg = [UIView new];
    selBg.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.08];
    cell.selectedBackgroundView = selBg;
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.canManage;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPAgentModel *agent = self.filteredAgents[indexPath.row];
    if (!self.canManage) return nil;
    
    UIContextualAction *toggleAction = [UIContextualAction contextualActionWithStyle:agent.isActive ? UIContextualActionStyleDestructive : UIContextualActionStyleNormal
                                                                              title:agent.isActive ? kLang(@"Agents_Deactivate") : kLang(@"Agents_Activate")
                                                                            handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self toggleActive:agent];
        completionHandler(YES);
    }];
    toggleAction.backgroundColor = agent.isActive ? [UIColor ppError] : [UIColor ppSuccess];
    return [UISwipeActionsConfiguration configurationWithActions:@[toggleAction]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.canManage) return;
    PPAgentModel *agent = self.filteredAgents[indexPath.row];
    PPAgentEditorViewController *editor = [[PPAgentEditorViewController alloc] initWithAgent:agent];
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - Actions

- (void)didTapAdd {
    PPAgentEditorViewController *editor = [[PPAgentEditorViewController alloc] initWithAgent:nil];
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)toggleActive:(PPAgentModel *)agent {
    BOOL newActive = !agent.isActive;
    [[[[FIRFirestore firestore] collectionWithPath:kPPAgentsCol] documentWithPath:agent.agentID]
     updateData:@{
        @"isActive": @(newActive),
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:newActive ? kLang(@"Agents_Activated") : kLang(@"Agents_Deactivated")];
            [self writeToggleAuditLog:agent newActive:newActive];
        }
    }];
}

- (void)writeToggleAuditLog:(PPAgentModel *)agent newActive:(BOOL)newActive {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
     setData:@{
        @"action": @"toggle_agent_active",
        @"targetCollection": kPPAgentsCol,
        @"targetId": agent.agentID ?: @"",
        @"adminUid": uid,
        @"before": @{@"isActive": @(!newActive)},
        @"after": @{@"isActive": @(newActive)},
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - UISearchResultsUpdating

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
    [self.listenerRegistration remove];
}

@end
