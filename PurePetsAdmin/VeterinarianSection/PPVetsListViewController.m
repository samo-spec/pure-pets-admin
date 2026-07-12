//
//  PPVetsListViewController.m
//  PurePetsAdmin
//

#import "PPVetsListViewController.h"
#import "PPVetModel.h"
#import "PPVetManager.h"
#import "PPVetCell.h"
#import "PPAddEditVetViewController.h"
#import "PPVetDetailViewController.h"
#import "PPVetSubscriptionViewController.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

typedef NS_ENUM(NSInteger, PPVetListFilter) {
    PPVetListFilterAll = 0,
    PPVetListFilterActive,
    PPVetListFilterDisabled
};

#pragma mark - Stats Pill (private helper)

@interface _PPVetStatPill : UIView
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@end

@implementation _PPVetStatPill

- (instancetype)initWithCaption:(NSString *)caption accentColor:(UIColor *)accent {
    if (self = [super init]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [accent colorWithAlphaComponent:0.08];
        self.layer.cornerRadius = 14;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:20];
        _valueLabel.textColor = accent;
        _valueLabel.textAlignment = NSTextAlignmentCenter;
        _valueLabel.text = @"0";
        [self addSubview:_valueLabel];

        _captionLabel = [UILabel new];
        _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _captionLabel.font = [Styling fontMedium:10];
        _captionLabel.textColor = SeconderyTextClr;
        _captionLabel.textAlignment = NSTextAlignmentCenter;
        _captionLabel.text = caption;
        [self addSubview:_captionLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_valueLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_valueLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_captionLabel.topAnchor constraintEqualToAnchor:_valueLabel.bottomAnchor constant:2],
            [_captionLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_captionLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)updateValue:(NSInteger)value {
    self.valueLabel.text = [NSString stringWithFormat:@"%ld", (long)value];
}

@end

#pragma mark - VC

@interface PPVetsListViewController () <UITableViewDataSource, UITableViewDelegate, PPSDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPS *searchView;
@property (nonatomic, strong) UISegmentedControl *filterControl;

@property (nonatomic, strong) NSMutableArray<PPVetModel *> *allVets;
@property (nonatomic, strong) NSMutableArray<PPVetModel *> *filteredVets;
@property (nonatomic, copy)   NSString *searchQuery;
@property (nonatomic, assign) PPVetListFilter activeFilter;

@property (nonatomic, strong) id<FIRListenerRegistration> listener;

// Stats
@property (nonatomic, strong) UIStackView *statsStack;
@property (nonatomic, strong) _PPVetStatPill *totalPill;
@property (nonatomic, strong) _PPVetStatPill *activePill;
@property (nonatomic, strong) _PPVetStatPill *disabledPill;

// Empty state
@property (nonatomic, strong) UIView *emptyContainer;

// Entrance animation
@property (nonatomic, assign) BOOL didPlayEntrance;
@end

@implementation PPVetsListViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;

    self.allVets = [NSMutableArray array];
    self.filteredVets = [NSMutableArray array];
    self.searchQuery = @"";
    self.activeFilter = PPVetListFilterAll;
    self.didPlayEntrance = NO;

    [self setupStatsHeader];
    [self setupFilterControl];
    [self setupTableView];
    [self setupEmptyState];
    [self startListening];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIButton *plus = [self pp_ButtonWithSystemName:@"plus" action:@selector(addVetTapped)];
    [self pp_navBarWithOtherButton:plus title:kLang(@"Vet_Section_Title")];
}

- (void)dealloc {
    [self.listener remove];
}

#pragma mark - Stats Header

- (void)setupStatsHeader {
    _totalPill    = [[_PPVetStatPill alloc] initWithCaption:kLang(@"Vet_Filter_All") accentColor:AppPrimaryClr];
    _activePill   = [[_PPVetStatPill alloc] initWithCaption:kLang(@"Vet_Filter_Active") accentColor:UIColor.systemGreenColor];
    _disabledPill = [[_PPVetStatPill alloc] initWithCaption:kLang(@"Vet_Filter_Disabled") accentColor:UIColor.systemRedColor];

    _statsStack = [[UIStackView alloc] initWithArrangedSubviews:@[_totalPill, _activePill, _disabledPill]];
    _statsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _statsStack.axis = UILayoutConstraintAxisHorizontal;
    _statsStack.distribution = UIStackViewDistributionFillEqually;
    _statsStack.spacing = 10;
    [self.view addSubview:_statsStack];

    [NSLayoutConstraint activateConstraints:@[
        [_statsStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [_statsStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_statsStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    ]];
}

- (void)refreshStats {
    NSInteger total = self.allVets.count;
    NSInteger active = 0, disabled = 0;
    for (PPVetModel *v in self.allVets) {
        if (v.isDisabled) disabled++; else active++;
    }
    [_totalPill updateValue:total];
    [_activePill updateValue:active];
    [_disabledPill updateValue:disabled];
}

#pragma mark - Filter

- (void)setupFilterControl {
    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[
        kLang(@"Vet_Filter_All"),
        kLang(@"Vet_Filter_Active"),
        kLang(@"Vet_Filter_Disabled")
    ]];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];

    [self.filterControl setTitleTextAttributes:@{
        NSFontAttributeName: [Styling fontMedium:13],
        NSForegroundColorAttributeName: SeconderyTextClr
    } forState:UIControlStateNormal];
    [self.filterControl setTitleTextAttributes:@{
        NSFontAttributeName: [Styling fontBold:13],
        NSForegroundColorAttributeName: UIColor.whiteColor
    } forState:UIControlStateSelected];
    self.filterControl.selectedSegmentTintColor = AppPrimaryClr;

    [self.view addSubview:self.filterControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:self.statsStack.bottomAnchor constant:12],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.filterControl.heightAnchor constraintEqualToConstant:36],
    ]];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    [PPFunc pp_playTapEffect];
    self.activeFilter = (PPVetListFilter)sender.selectedSegmentIndex;
    [self applyFilterAndReload];
}

#pragma mark - Table

- (void)setupTableView {
    CGFloat searchH = 48.0;
    CGFloat pad = 10.0;

    // Search header
    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, searchH + pad * 2)];
    headerContainer.backgroundColor = UIColor.clearColor;

    PPS *sv = [[PPS alloc] initWithFrame:CGRectZero];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.delegate = self;
    sv.cornerRadius = searchH / 2.0;
    sv.blurEnabled = NO;
    sv.shadowEnabled = NO;
    sv.strokeColor = [SeconderyTextClr colorWithAlphaComponent:0.12];
    sv.textField.placeholder = kLang(@"Vet_Search_Placeholder");
    sv.backgroundColor = AppForgroundColr;
    sv.showsPrimaryButton = NO;
    [headerContainer addSubview:sv];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:pad],
        [sv.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:16],
        [sv.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-16],
        [sv.heightAnchor constraintEqualToConstant:searchH]
    ]];
    self.searchView = sv;

    // Table
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = [PPVetCell preferredHeight];
    self.tableView.estimatedRowHeight = [PPVetCell preferredHeight];
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.tableHeaderView = headerContainer;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 20, 0);

    // Pull-to-refresh
    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    refresh.tintColor = AppPrimaryClr;
    [refresh addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refresh;

    [self.tableView registerClass:[PPVetCell class] forCellReuseIdentifier:[PPVetCell reuseID]];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)onRefresh {
    __weak typeof(self) weakSelf = self;
    [[PPVetManager sharedManager] fetchAllVetsWithCompletion:^(NSArray<PPVetModel *> *vets, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView.refreshControl endRefreshing];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
                return;
            }
            weakSelf.allVets = [vets mutableCopy] ?: [NSMutableArray array];
            [weakSelf refreshStats];
            [weakSelf applyFilterAndReload];
        });
    }];
}

#pragma mark - Empty State

- (void)setupEmptyState {
    _emptyContainer = [UIView new];
    _emptyContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyContainer.hidden = YES;
    [self.view addSubview:_emptyContainer];

    UIImageView *icon = [UIImageView new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.image = [UIImage systemImageNamed:@"stethoscope"];
    icon.tintColor = [SeconderyTextClr colorWithAlphaComponent:0.3];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [_emptyContainer addSubview:icon];

    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = kLang(@"Vet_Empty_List");
    lbl.font = [Styling fontMedium:15];
    lbl.textColor = SeconderyTextClr;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.numberOfLines = 0;
    [_emptyContainer addSubview:lbl];

    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    addBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [addBtn setTitle:[NSString stringWithFormat:@"  %@", kLang(@"Vet_Add_Title")] forState:UIControlStateNormal];
    [addBtn setImage:[UIImage systemImageNamed:@"plus.circle.fill"] forState:UIControlStateNormal];
    addBtn.titleLabel.font = [Styling fontBold:15];
    addBtn.tintColor = UIColor.whiteColor;
    addBtn.backgroundColor = AppPrimaryClr;
    addBtn.layer.cornerRadius = 22;
    addBtn.contentEdgeInsets = UIEdgeInsetsMake(12, 24, 12, 24);
    [addBtn addTarget:self action:@selector(addVetTapped) forControlEvents:UIControlEventTouchUpInside];
    [_emptyContainer addSubview:addBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:20],
        [_emptyContainer.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:40],

        [icon.topAnchor constraintEqualToAnchor:_emptyContainer.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:_emptyContainer.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:64],
        [icon.heightAnchor constraintEqualToConstant:64],

        [lbl.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
        [lbl.leadingAnchor constraintEqualToAnchor:_emptyContainer.leadingAnchor],
        [lbl.trailingAnchor constraintEqualToAnchor:_emptyContainer.trailingAnchor],

        [addBtn.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:20],
        [addBtn.centerXAnchor constraintEqualToAnchor:_emptyContainer.centerXAnchor],
        [addBtn.bottomAnchor constraintEqualToAnchor:_emptyContainer.bottomAnchor],
        [addBtn.heightAnchor constraintEqualToConstant:44],
    ]];
}

#pragma mark - Data

- (void)startListening {
    __weak typeof(self) weakSelf = self;
    self.listener = [[PPVetManager sharedManager] observeAllVets:^(NSArray<PPVetModel *> *vets, NSError *error) {
        if (error) {
            DLog(@"[VetsList] listener error: %@", error.localizedDescription);
            return;
        }
        __strong typeof(weakSelf) self = weakSelf;
        self.allVets = [vets mutableCopy] ?: [NSMutableArray array];
        [self refreshStats];
        [self applyFilterAndReload];
    }];
}

- (void)applyFilterAndReload {
    NSMutableArray<PPVetModel *> *result = [NSMutableArray array];

    for (PPVetModel *vet in self.allVets) {
        if (self.activeFilter == PPVetListFilterActive && vet.isDisabled) continue;
        if (self.activeFilter == PPVetListFilterDisabled && !vet.isDisabled) continue;

        NSString *q = PPSafeString(self.searchQuery).lowercaseString;
        if (q.length > 0) {
            NSString *name  = PPSafeString(vet.title).lowercaseString;
            NSString *desc  = PPSafeString(vet.descriptionText).lowercaseString;
            NSString *phone = PPSafeString(vet.phone).lowercaseString;
            if (![name containsString:q] && ![desc containsString:q] && ![phone containsString:q]) continue;
        }
        [result addObject:vet];
    }

    [result sortUsingComparator:^NSComparisonResult(PPVetModel *a, PPVetModel *b) {
        if (a.isDisabled != b.isDisabled) return a.isDisabled ? NSOrderedDescending : NSOrderedAscending;
        return [a.title localizedCaseInsensitiveCompare:b.title ?: @""];
    }];

    self.filteredVets = result;
    [self.tableView reloadData];
    self.emptyContainer.hidden = (self.filteredVets.count > 0);
    self.tableView.hidden = (self.filteredVets.count == 0);

    if (!self.didPlayEntrance && self.filteredVets.count > 0) {
        self.didPlayEntrance = YES;
        [self playCellEntranceAnimation];
    }
}

- (PPVetModel *)vetAtIndexPath:(NSIndexPath *)ip {
    if (!ip || ip.row >= (NSInteger)self.filteredVets.count) return nil;
    return self.filteredVets[ip.row];
}

#pragma mark - Cell Entrance Animation

- (void)playCellEntranceAnimation {
    NSArray<UITableViewCell *> *cells = self.tableView.visibleCells;
    for (NSUInteger idx = 0; idx < cells.count; idx++) {
        UITableViewCell *cell = cells[idx];
        cell.alpha = 0;
        cell.transform = CGAffineTransformMakeTranslation(0, 24);
        [UIView animateWithDuration:0.45
                              delay:0.04 * idx
             usingSpringWithDamping:0.88
              initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

#pragma mark - Actions

- (void)addVetTapped {
    [PPFunc pp_playTapEffect];
    PPAddEditVetViewController *vc = [[PPAddEditVetViewController alloc] initWithVet:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)editVetAtIndexPath:(NSIndexPath *)ip {
    PPVetModel *vet = [self vetAtIndexPath:ip];
    if (!vet) return;
    [PPFunc pp_playTapEffect];
    PPAddEditVetViewController *vc = [[PPAddEditVetViewController alloc] initWithVet:vet];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)viewVetAtIndexPath:(NSIndexPath *)ip {
    PPVetModel *vet = [self vetAtIndexPath:ip];
    if (!vet) return;
    [PPFunc pp_playTapEffect];
    PPVetDetailViewController *vc = [[PPVetDetailViewController alloc] initWithVet:vet];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)toggleDisabledAtIndexPath:(NSIndexPath *)ip {
    PPVetModel *vet = [self vetAtIndexPath:ip];
    if (!vet) return;

    BOOL newState = !vet.isDisabled;
    NSString *confirmTitle = newState ? kLang(@"Vet_Confirm_Disable_Title") : kLang(@"Vet_Confirm_Enable_Title");
    NSString *confirmMsg   = newState ? kLang(@"Vet_Confirm_Disable_Msg")   : kLang(@"Vet_Confirm_Enable_Msg");
    NSString *confirmBtn   = newState ? kLang(@"Vet_Action_Disable")        : kLang(@"Vet_Action_Enable");

    __weak typeof(self) weakSelf = self;
    [AlertHelper showConfirmationIn:self
                              title:confirmTitle
                           subtitle:confirmMsg
                        placeholder:nil
                      confirmButton:confirmBtn
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Vet_Updating") subtitle:nil];
        [[PPVetManager sharedManager] setDisabled:newState forVetID:vet.vetID completion:^(NSError *error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Updated") subtitle:newState ? kLang(@"Vet_Disabled_Success") : kLang(@"Vet_Enabled_Success")];
            }
        }];
    } cancelBlock:nil];
}

- (void)deleteVetAtIndexPath:(NSIndexPath *)ip {
    PPVetModel *vet = [self vetAtIndexPath:ip];
    if (!vet) return;

    __weak typeof(self) weakSelf = self;
    [AlertHelper showConfirmationIn:self
                              title:kLang(@"Vet_Confirm_Delete_Title")
                           subtitle:kLang(@"Vet_Confirm_Delete_Msg")
                        placeholder:nil
                      confirmButton:kLang(@"Delete")
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Deleting") subtitle:nil];
        [[PPVetManager sharedManager] deleteVet:vet completion:^(NSError *error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Vet_Deleted_Success")];
            }
        }];
    } cancelBlock:nil];
}

- (void)manageSubscriptionAtIndexPath:(NSIndexPath *)ip {
    PPVetModel *vet = [self vetAtIndexPath:ip];
    if (!vet) return;
    [PPFunc pp_playTapEffect];
    PPVetSubscriptionViewController *vc = [[PPVetSubscriptionViewController alloc] initWithVet:vet];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - PPSDelegate

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.searchQuery = text ?: @"";
    [self applyFilterAndReload];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredVets.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPVetCell *cell = [tableView dequeueReusableCellWithIdentifier:[PPVetCell reuseID] forIndexPath:indexPath];
    PPVetModel *vet = [self vetAtIndexPath:indexPath];
    if (vet) [cell configureWithVet:vet];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self viewVetAtIndexPath:indexPath];
}

// ── Context Menu (iOS 13+) ──

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                       point:(CGPoint)point API_AVAILABLE(ios(13.0)) {

    PPVetModel *vet = [self vetAtIndexPath:indexPath];
    if (!vet) return nil;

    __weak typeof(self) weakSelf = self;

    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        // View
        UIAction *viewAction = [UIAction actionWithTitle:kLang(@"Vet_Detail_Title")
                                                   image:[UIImage systemImageNamed:@"eye"]
                                              identifier:nil
                                                 handler:^(UIAction *action) {
            [weakSelf viewVetAtIndexPath:indexPath];
        }];

        // Edit
        UIAction *editAction = [UIAction actionWithTitle:kLang(@"Vet_Edit_Title")
                                                   image:[UIImage systemImageNamed:@"pencil"]
                                              identifier:nil
                                                 handler:^(UIAction *action) {
            [weakSelf editVetAtIndexPath:indexPath];
        }];

        // Enable / Disable
        BOOL disabled = vet.isDisabled;
        UIAction *toggleAction = [UIAction actionWithTitle:disabled ? kLang(@"Vet_Action_Enable") : kLang(@"Vet_Action_Disable")
                                                     image:[UIImage systemImageNamed:disabled ? @"checkmark.circle" : @"nosign"]
                                                identifier:nil
                                                   handler:^(UIAction *action) {
            [weakSelf toggleDisabledAtIndexPath:indexPath];
        }];
        if (!disabled) toggleAction.attributes = UIMenuElementAttributesDestructive;

        // Subscription
        UIAction *subAction = [UIAction actionWithTitle:kLang(@"Vet_Subscription")
                                                  image:[UIImage systemImageNamed:@"creditcard.circle"]
                                             identifier:nil
                                                handler:^(UIAction *action) {
            [weakSelf manageSubscriptionAtIndexPath:indexPath];
        }];

        // Call
        UIAction *callAction = [UIAction actionWithTitle:kLang(@"Vet_Field_Phone")
                                                   image:[UIImage systemImageNamed:@"phone"]
                                              identifier:nil
                                                 handler:^(UIAction *action) {
            NSString *phone = [vet.phone stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (phone.length == 0) return;
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[@"tel://" stringByAppendingString:phone]] options:@{} completionHandler:nil];
        }];
        if (vet.phone.length == 0) callAction.attributes = UIMenuElementAttributesDisabled;

        // Delete
        UIAction *deleteAction = [UIAction actionWithTitle:kLang(@"Delete")
                                                     image:[UIImage systemImageNamed:@"trash"]
                                                identifier:nil
                                                   handler:^(UIAction *action) {
            [weakSelf deleteVetAtIndexPath:indexPath];
        }];
        deleteAction.attributes = UIMenuElementAttributesDestructive;

        UIMenu *primaryMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[viewAction, editAction]];
        UIMenu *manageMenu  = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[toggleAction, subAction, callAction]];
        UIMenu *dangerMenu  = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[deleteAction]];

        return [UIMenu menuWithTitle:vet.title ?: @"" children:@[primaryMenu, manageMenu, dangerMenu]];
    }];
}

// ── Swipe Actions (keep for quick access) ──

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {

    __weak typeof(self) weakSelf = self;
    PPVetModel *vet = [self vetAtIndexPath:indexPath];

    UIContextualAction *editAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *action, UIView *sourceView, void (^handler)(BOOL)) {
        [weakSelf editVetAtIndexPath:indexPath];
        handler(YES);
    }];
    editAction.backgroundColor = UIColor.systemBlueColor;
    editAction.image = [UIImage systemImageNamed:@"pencil.circle.fill"];

    BOOL isDisabled = vet.isDisabled;
    UIContextualAction *toggleAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *action, UIView *sourceView, void (^handler)(BOOL)) {
        [weakSelf toggleDisabledAtIndexPath:indexPath];
        handler(YES);
    }];
    toggleAction.backgroundColor = isDisabled ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
    toggleAction.image = [UIImage systemImageNamed:isDisabled ? @"checkmark.circle.fill" : @"nosign"];

    UIContextualAction *subAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:nil handler:^(UIContextualAction *action, UIView *sourceView, void (^handler)(BOOL)) {
        [weakSelf manageSubscriptionAtIndexPath:indexPath];
        handler(YES);
    }];
    subAction.backgroundColor = AppPrimaryClr;
    subAction.image = [UIImage systemImageNamed:@"creditcard.circle.fill"];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[subAction, toggleAction, editAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {

    __weak typeof(self) weakSelf = self;

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(UIContextualAction *action, UIView *sourceView, void (^handler)(BOOL)) {
        [weakSelf deleteVetAtIndexPath:indexPath];
        handler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash.circle.fill"];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

// ── Highlight effect for visible cells ──

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    // Ensure cells that scroll into view after the initial batch also get a subtle fade-in
    if (self.didPlayEntrance) {
        cell.alpha = 0;
        [UIView animateWithDuration:0.25 animations:^{ cell.alpha = 1; }];
    }
}

@end
