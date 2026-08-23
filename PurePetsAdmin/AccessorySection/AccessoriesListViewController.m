#import <UIKit/UIKit.h>
#import "AccessoriesListViewController.h"
#import "AccessoryCell.h"
#import "AddAccessoryViewController.h"

@interface AccessoriesListViewController () <UITableViewDataSource, UITableViewDelegate, PPSDelegate, AccessoryCellDelegate>
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

    // Card-based lists stand out beautifully on the default background color
    self.view.backgroundColor = AppBackgroundClr;

    // Create and configure UITableView
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 112.0;
    self.tableView.estimatedRowHeight = 112.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;

    // Premium content inset
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 20.0, 0);

    [self.view addSubview:self.tableView];

    self.accessories = [NSMutableArray array];
    self.filteredAccessories = [NSMutableArray array];
    self.pendingQuantityDeltas = [NSMutableDictionary dictionary];
    self.pendingQuantityDebounceBlocks = [NSMutableDictionary dictionary];

    [self.tableView registerClass:[AccessoryCell class] forCellReuseIdentifier:@"AccessoryCell"];
    
    [self setupSearchHeader];
    [self startListeningForAccessories];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    UIButton *plus = [self pp_ButtonWithSystemName:@"plus" action:@selector(addAccessory)];
    NSString *title = kLang(@"Manage Accessories");
    if (self.listKind == AccessTypeFood) {
        title = kLang(@"manageFood");
        if (title.length == 0 || [title isEqualToString:@"manageFood"]) title = @"إدارة الأطعمة";
    } else if (self.listKind == AccessTypeLivePets) {
        title = kLang(@"Manage Live Pets");
        if (title.length == 0 || [title isEqualToString:@"Manage Live Pets"]) title = @"إدارة الحيوانات الأليفة";
    } else {
        if (title.length == 0 || [title isEqualToString:@"Manage Accessories"]) title = @"إدارة الإكسسوارات";
    }
    
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
        if (!self) return;
        self.accessories = [items mutableCopy] ?: [NSMutableArray array];
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
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.filteredAccessories.count == 0) {
        UIView *emptyView = [[UIView alloc] initWithFrame:self.tableView.bounds];
        emptyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shippingbox.fill"]];
        iconView.tintColor = [SeconderyTextClr colorWithAlphaComponent:0.35];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyView addSubview:iconView];
        
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:18] ?: [UIFont boldSystemFontOfSize:18];
        titleLabel.textColor = PrimaryTextClr;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        
        NSString *emptyTitle = kLang(@"No Accessories Found");
        if (self.listKind == AccessTypeFood) {
            emptyTitle = @"لا توجد أطعمة مضافة";
        } else if (self.listKind == AccessTypeLivePets) {
            emptyTitle = @"لا توجد حيوانات أليفة مضافة";
        } else {
            if (emptyTitle.length == 0 || [emptyTitle isEqualToString:@"No Accessories Found"]) {
                emptyTitle = @"لا توجد إكسسوارات مضافة";
            }
        }
        titleLabel.text = emptyTitle;
        [emptyView addSubview:titleLabel];
        
        UILabel *subLabel = [[UILabel alloc] init];
        subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subLabel.font = [UIFont fontWithName:@"Beiruti-Regular" size:14] ?: [UIFont systemFontOfSize:14];
        subLabel.textColor = SeconderyTextClr;
        subLabel.textAlignment = NSTextAlignmentCenter;
        
        NSString *emptySub = kLang(@"Tap + to add your first accessory.");
        if (self.listKind == AccessTypeFood) {
            emptySub = @"اضغط على + لإضافة أول منتج طعام لك.";
        } else if (self.listKind == AccessTypeLivePets) {
            emptySub = @"اضغط على + لإضافة أول حيوان أليف.";
        } else {
            if (emptySub.length == 0 || [emptySub isEqualToString:@"Tap + to add your first accessory."]) {
                emptySub = @"اضغط على + لإضافة أول منتج لك.";
            }
        }
        subLabel.text = emptySub;
        [emptyView addSubview:subLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [iconView.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
            [iconView.centerYAnchor constraintEqualToAnchor:emptyView.centerYAnchor constant:-40.0],
            [iconView.widthAnchor constraintEqualToConstant:64.0],
            [iconView.heightAnchor constraintEqualToConstant:64.0],
            
            [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:16.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:emptyView.leadingAnchor constant:24.0],
            [titleLabel.trailingAnchor constraintEqualToAnchor:emptyView.trailingAnchor constant:-24.0],
            
            [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
            [subLabel.leadingAnchor constraintEqualToAnchor:emptyView.leadingAnchor constant:24.0],
            [subLabel.trailingAnchor constraintEqualToAnchor:emptyView.trailingAnchor constant:-24.0]
        ]];
        
        self.tableView.backgroundView = emptyView;
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (PetAccessory *)accessoryAtIndexPath:(NSIndexPath *)indexPath {
    if (!indexPath) return nil;
    if (indexPath.row < 0 || indexPath.row >= self.filteredAccessories.count) return nil;
    return self.filteredAccessories[indexPath.row];
}

#pragma mark - UI

- (void)setupSearchHeader {
    CGFloat barH = 48.0;
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
    sv.strokeColor = [UIColor colorWithWhite:0 alpha:0.04];
    sv.textField.placeholder = kLang(@"SetPermissions_Search_Placeholder");
    if (sv.textField.placeholder.length == 0 || [sv.textField.placeholder isEqualToString:@"SetPermissions_Search_Placeholder"]) {
        sv.textField.placeholder = @"بحث عن المنتجات...";
    }
    sv.backgroundColor = AppForgroundColr;
    sv.showsPrimaryButton = NO;

    [container addSubview:sv];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:container.topAnchor constant:pad],
        [sv.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
        [sv.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
        [sv.heightAnchor constraintEqualToConstant:barH]
    ]];

    self.tableView.tableHeaderView = container;
    self.searchView = sv;
}

- (void)addTopGradientOverlay {
    // Legacy stub
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
    [PPAlertHelper showConfirmationIn:self
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

#pragma mark - AccessoryCellDelegate

- (void)accessoryCell:(AccessoryCell *)cell didTapAdjustQuantityBy:(NSInteger)delta {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (indexPath) {
        [self adjustQuantityBy:delta forIndexPath:indexPath];
    }
}

- (void)accessoryCellDidTapEdit:(AccessoryCell *)cell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (indexPath) {
        [self editAccessoryAtIndexPath:indexPath];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredAccessories.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AccessoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AccessoryCell" forIndexPath:indexPath];
    PetAccessory *model = [self accessoryAtIndexPath:indexPath];
    
    [cell configureWithAccessory:model];
    cell.delegate = self;
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self editAccessoryAtIndexPath:indexPath];
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) weakSelf = self;

    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:kLang(@"Delete") handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf deleteAccessoryAtIndexPath:indexPath];
        completionHandler(YES);
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"];

    UIContextualAction *editAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:kLang(@"Update") handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [weakSelf editAccessoryAtIndexPath:indexPath];
        completionHandler(YES);
    }];
    editAction.backgroundColor = [UIColor ppPrimary];
    editAction.image = [UIImage systemImageNamed:@"pencil.fill"];

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, editAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:AccessoryCell.class]) return;
    AccessoryCell *accCell = (AccessoryCell *)cell;

    // Premium entrance animation
    if (!accCell.hasAnimated) {
        accCell.hasAnimated = YES;
        
        accCell.alpha = 0.0;
        accCell.transform = CGAffineTransformMakeTranslation(0, 24.0);

        [UIView animateWithDuration:0.55
                              delay:0.04 * indexPath.row
             usingSpringWithDamping:0.82
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            accCell.alpha = 1.0;
            accCell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

@end
