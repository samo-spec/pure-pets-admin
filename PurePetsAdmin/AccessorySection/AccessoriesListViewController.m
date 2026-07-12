#import <UIKit/UIKit.h>
#import "AccessoriesListViewController.h"

@interface AccessoriesListViewController ()<UITableViewDataSource, UITableViewDelegate, PPSDelegate, PPCellWithButtonsDelegate>
@property (nonatomic, strong) id<FIRListenerRegistration> listener;
@property (nonatomic, strong) PPS *searchView;
@property (nonatomic, strong) NSMutableArray<PetAccessory *> *accessories;
@property (nonatomic, strong) NSMutableArray<PetAccessory *> *filteredAccessories;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *pendingQuantityDeltas;
@property (nonatomic, strong) NSMutableDictionary<NSString *, dispatch_block_t> *pendingQuantityDebounceBlocks;
@end

@implementation AccessoriesListViewController

- (instancetype)init {
    return [self initWithKind:AccessTypeAccessory];
}

- (instancetype)initWithKind:(AccessKindType)kind {
    self = [super init];
    if (self) {
        _listKind = kind;
        _currentAccessQuery = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Create and configure UITableView
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    self.view.backgroundColor = AppForgroundColr;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.separatorColor = UIColor.clearColor;
    self.tableView.rowHeight = 80.0;
    self.tableView.estimatedRowHeight = 80.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;

    [self.view addSubview:self.tableView];

    self.accessories = [NSMutableArray array];
    self.filteredAccessories = [NSMutableArray array];
    self.pendingQuantityDeltas = [NSMutableDictionary dictionary];
    self.pendingQuantityDebounceBlocks = [NSMutableDictionary dictionary];

    [self.tableView registerClass:[PPCellWithButtons class] forCellReuseIdentifier:[PPCellWithButtons reuseIdentifier]];
    [self setupSearchHeader];
    [self addTopGradientOverlay];
    [self startListeningForAccessories];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIButton *plus = [self pp_ButtonWithSystemName:@"plus" action:@selector(addAccessory)];
    NSString *title = kLang(@"Manage Accessories");
    if (self.listKind == AccessTypeFood) title = kLang(@"manageFood");
    else if (self.listKind == AccessTypeLivePets) title = kLang(@"Manage Live Pets");
    [self pp_navBarWithOtherButton:plus title:title];
}

- (void)dealloc {
    [self.listener remove];
    for (dispatch_block_t block in self.pendingQuantityDebounceBlocks.allValues) {
        dispatch_block_cancel(block);
    }
}

#pragma mark - Data

- (void)startListeningForAccessories {
    __weak typeof(self) weakSelf = self;
    self.listener = [[AccessoryManager shared] observeAccessoriesOfKind:self.listKind callback:^(NSArray<PetAccessory *> * _Nullable items, NSError * _Nullable error) {
        if (error) {
            DLog(@"[AccessoriesList] listen error: %@", error.localizedDescription);
            return;
        }

        __strong typeof(weakSelf) self = weakSelf;
        self.accessories = [items mutableCopy] ?: [NSMutableArray array];
        // Debug: log number of accessories received
        NSLog(@"[AccessoriesList] listener received %lu items", (unsigned long)self.accessories.count);
        [self _applyFilterAndReload];
    }];
}

- (void)_applyFilterAndReload {
    NSString *q = [PPSafeString(self.currentAccessQuery) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (q.length == 0) {
        self.filteredAccessories = self.accessories.mutableCopy;
    } else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(PetAccessory *obj, NSDictionary *bindings) {
            NSString *name = PPSafeString(obj.name).lowercaseString;
            NSString *desc = PPSafeString(obj.desc).lowercaseString;
            NSString *searchTitle = PPSafeString(obj.searchTitle).lowercaseString;
            return [name containsString:q] || [desc containsString:q] || [searchTitle containsString:q];
        }];
        self.filteredAccessories = [[self.accessories filteredArrayUsingPredicate:p] mutableCopy];
    }
    [self.tableView reloadData];
}

- (PetAccessory *)accessoryAtIndexPath:(NSIndexPath *)indexPath {
    if (!indexPath) return nil;
    if (indexPath.row < 0 || indexPath.row >= self.filteredAccessories.count) return nil;
    return self.filteredAccessories[indexPath.row];
}

#pragma mark - UI

- (void)setupSearchHeader {
    CGFloat barH = 50.0;
    CGFloat pad = 16.0;
    CGFloat containerH = barH + pad * 2;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, containerH)];
    container.backgroundColor = UIColor.clearColor;

    PPS *sv = [[PPS alloc] initWithFrame:CGRectZero];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.delegate = self;
    sv.cornerRadius = barH / 2.0;
    sv.blurEnabled = NO;
    sv.shadowEnabled = YES;
    sv.strokeColor = [UIColor colorWithWhite:1 alpha:0.12];
    sv.textField.placeholder = kLang(@"SetPermissions_Search_Placeholder");
    sv.backgroundColor = AppForgroundColr;
    sv.showsPrimaryButton = NO;

    [container addSubview:sv];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor constant:pad],
        [sv.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:pad],
        [sv.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-pad],
        [sv.heightAnchor constraintEqualToConstant:barH]
    ]];

    self.tableView.tableHeaderView = container;
    self.searchView = sv;
}

- (void)addTopGradientOverlay {

}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
}

#pragma mark - Search

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.currentAccessQuery = text ?: @"";
    [self _applyFilterAndReload];
}

#pragma mark - Actions

- (void)addAccessory {
    AddAccessoryViewController *vc = [[AddAccessoryViewController alloc] initWithAccessory:nil];
    vc.showTypeRow = NO;
    vc.defaultKind = self.listKind;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)editAccessoryAtIndexPath:(NSIndexPath *)indexPath {
    PetAccessory *accessory = [self accessoryAtIndexPath:indexPath];
    if (!accessory) return;
    AddAccessoryViewController *vc = [[AddAccessoryViewController alloc] initWithAccessory:accessory];
    vc.showTypeRow = NO;
    vc.defaultKind = self.listKind;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)adjustQuantityBy:(NSInteger)delta forIndexPath:(NSIndexPath *)indexPath {
    PetAccessory *accessory = [self accessoryAtIndexPath:indexPath];
    if (!accessory || accessory.accessoryID.length == 0) return;

    NSString *docID = accessory.accessoryID;
    NSInteger pending = [self.pendingQuantityDeltas[docID] integerValue] + delta;
    self.pendingQuantityDeltas[docID] = @(pending);

    // Optimistic local update so admin sees the running qty while tapping.
    accessory.quantity = MAX(0, accessory.quantity + delta);
    accessory.noStock = (accessory.quantity <= 0);
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];

    dispatch_block_t oldBlock = self.pendingQuantityDebounceBlocks[docID];
    if (oldBlock) {
        dispatch_block_cancel(oldBlock);
    }

    __weak typeof(self) weakSelf = self;
    dispatch_block_t flushBlock = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSInteger batchedDelta = [self.pendingQuantityDeltas[docID] integerValue];
        [self.pendingQuantityDeltas removeObjectForKey:docID];
        [self.pendingQuantityDebounceBlocks removeObjectForKey:docID];
        if (batchedDelta == 0) return;

        [[AccessoryManager shared] adjustQuantityBy:batchedDelta forAccessoryID:docID completion:^(NSError * _Nullable error) {
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Something went wrong.")];
                return;
            }
            [PPHUD showSuccess:kLang(@"Updated") subtitle:kLang(@"StockUpdated")];
        }];
    });
    self.pendingQuantityDebounceBlocks[docID] = flushBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), flushBlock);
}

- (void)deleteAccessoryAtIndexPath:(NSIndexPath *)indexPath {
    PetAccessory *accessory = [self accessoryAtIndexPath:indexPath];
    if (!accessory) return;

    __weak typeof(self) weakSelf = self;
    [AlertHelper showConfirmationIn:self
                              title:kLang(@"Confirm Delete")
                           subtitle:kLang(@"Are you sure you want to delete this accessory?")
                        placeholder:nil
                      confirmButton:kLang(@"Delete")
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Deleting") subtitle:nil];
        [[AccessoryManager shared] deleteAccessoryWithID:accessory.accessoryID completion:^(NSError * _Nullable err) {
            [PPHUD dismiss];
            if (err) {
                [PPHUD showError:kLang(@"Error") subtitle:err.localizedDescription ?: kLang(@"Something went wrong.")];
            } else {
                [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Accessory removed")];
            }
        }];
    } cancelBlock:nil];
}

#pragma mark - PPCellWithButtonsDelegate

- (void)cellWithButtons:(PPCellWithButtons *)cell didTapFirstButtonAtIndexPath:(NSIndexPath *)indexPath {
    [self editAccessoryAtIndexPath:indexPath];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredAccessories.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPCellWithButtons *cell = [tableView dequeueReusableCellWithIdentifier:[PPCellWithButtons reuseIdentifier] forIndexPath:indexPath];
    PetAccessory *model = [self accessoryAtIndexPath:indexPath];
    // Debug: log model name for this row
    NSLog(@"[AccessoriesList] cellForRow at %@ -> accessory.name: '%@' (id=%@)", indexPath, model.name ?: @"(nil)", model.accessoryID ?: @"(no-id)");
    [cell configureWithItem:model];
    // Force title assignment from VC level to ensure label gets the accessory name
    cell.titleLabel.text = model.name.length ? model.name : @"-";
    cell.indexPath = indexPath;
    cell.delegate = self;
    
    // Remove background color completely
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    
    // Ensure text is visible with proper color and opacity
    cell.titleLabel.textColor = PrimaryTextClr;
    cell.titleLabel.alpha = 1.0;
    cell.titleLabel.hidden = NO;
    
    cell.subtitleLabel.textColor = SeconderyTextClr;
    cell.subtitleLabel.alpha = 1.0;
    cell.subtitleLabel.hidden = NO;
    
    cell.detailLabel.textColor = UIColor.systemGrayColor;
    cell.detailLabel.alpha = 1.0;
    cell.detailLabel.hidden = NO;
    
    [cell.firstButton pp_setSymbolNamed:Language.isRTL ? @"chevron.backward" : @"chevron.forward"
                              pointSize:18
                                 weight:UIImageSymbolWeightMedium
                                  scale:UIImageSymbolScaleMedium
                                   tint:UIColor.darkGrayColor
                                palette:@[UIColor.darkGrayColor]];
    cell.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    return cell;
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;

    UIContextualAction *editAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:kLang(@"Update") handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf editAccessoryAtIndexPath:indexPath];
        completionHandler(YES);
    }];
    editAction.backgroundColor = [UIColor systemBlueColor];
    editAction.image = [UIImage systemImageNamed:@"pencil"];

    UIContextualAction *increaseQty = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:kLang(@"IncreaseQty") handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf adjustQuantityBy:1 forIndexPath:indexPath];
        completionHandler(YES);
    }];
    increaseQty.backgroundColor = [UIColor systemGreenColor];
    increaseQty.image = [UIImage systemImageNamed:@"plus.circle"];

    UIContextualAction *decreaseQty = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:kLang(@"DecreaseQty") handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf adjustQuantityBy:-1 forIndexPath:indexPath];
        completionHandler(YES);
    }];
    decreaseQty.backgroundColor = [UIColor systemOrangeColor];
    decreaseQty.image = [UIImage systemImageNamed:@"minus.circle"];

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:kLang(@"Delete") handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf deleteAccessoryAtIndexPath:indexPath];
        completionHandler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, decreaseQty, increaseQty, editAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    PPCellWithButtons *cell = (PPCellWithButtons *)[tableView cellForRowAtIndexPath:indexPath];
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.separatorInset = UIEdgeInsetsMake(0, 500, 0, 0);
    cell.subtitleLabel.backgroundColor = UIColor.clearColor;
    cell.titleLabel.textColor = SeconderyTextClr;
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    PPCellWithButtons *cell = (PPCellWithButtons *)[tableView cellForRowAtIndexPath:indexPath];
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.separatorInset = UIEdgeInsetsMake(0, 72, 0, 0);
    cell.subtitleLabel.backgroundColor = UIColor.clearColor;
    cell.titleLabel.textColor = PrimaryTextClr;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:PPCellWithButtons.class]) return;
    PPCellWithButtons *buttonsCell = (PPCellWithButtons *)cell;
    buttonsCell.indexPath = indexPath;
    if (@available(iOS 17.0, *)) {
        NSSymbolWiggleEffect *wiggle = [NSSymbolWiggleEffect effect];
        if (@available(iOS 18.0, *)) {
            [buttonsCell.firstButton.imageView addSymbolEffect:wiggle
                                                       options:[NSSymbolEffectOptions optionsWithRepeatBehavior:[NSSymbolEffectOptionsRepeatBehavior behaviorPeriodicWithDelay:1.5]]];
        }
    }
}

@end
