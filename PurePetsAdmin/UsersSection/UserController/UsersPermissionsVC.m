//
//  UsersPermissionsVC 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 02/09/2025.
//


//  UsersPermissionsVC.m
#import "UsersPermissionsVC.h"
#import "RPManager.h"
#import "FUManager.h"

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
#define RPM [RPManager shared]

#pragma mark - Internal Models

@interface _PermItem : NSObject
@property (nonatomic, copy) NSString *key;    // e.g. @"PostAds"
@property (nonatomic, copy) NSString *title;  // e.g. @"Manage Users"
@property (nonatomic, assign) BOOL value;     // current ON/OFF
+ (instancetype)item:(NSString *)key title:(NSString *)title;
@end

@implementation _PermItem
+ (instancetype)item:(NSString *)key title:(NSString *)title {
    _PermItem *i = [_PermItem new];
    i.key = key ?: @"";
    i.title = title ?: key ?: @"";
    return i;
}
@end


#pragma mark - VC

@interface UsersPermissionsVC ()
@property (nonatomic, strong) NSMutableArray<_PermItem *> *items;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> permsListener;

// Header UI
@property (nonatomic, strong) UILabel *uidLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *adminLabel;
@end

@implementation UsersPermissionsVC

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithUID:(nullable NSString *)uid {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        [self commonInit];
        self.targetUID = uid;
    }
    return self;
}

- (void)commonInit {
    self.title = @"User Permissions";
    self.items = [@[
        [_PermItem item:kPermPostAds        title:@"Post Ads"],
        [_PermItem item:kPermSellNew        title:@"Sell New"],
        [_PermItem item:kPermSellUsed       title:@"Sell Used"],
        [_PermItem item:kPermAdoption       title:@"Adoption"],
        [_PermItem item:kPermManageStore    title:@"Manage Store"],
        [_PermItem item:kPermModeration     title:@"Moderation"],
        [_PermItem item:kPermManageFood     title:@"Manage Food"],
        [_PermItem item:kPermManageServices title:@"Manage Services"],
        [_PermItem item:kPermProduction     title:@"Production"],
        [_PermItem item:kPermAdminAll       title:@"Admin (All)"],
    ] mutableCopy];
  
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(refreshTapped)];
    
    // Bottom toolbar actions
    UIBarButtonItem *roleBtn =
        [[UIBarButtonItem alloc] initWithTitle:@"Set Role"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(setRoleTapped)];
    UIBarButtonItem *toggleAdminClaimBtn =
        [[UIBarButtonItem alloc] initWithTitle:@"Toggle Admin Claim"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(toggleAdminClaimTapped)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                          target:nil action:nil];
    self.toolbarItems = @[roleBtn, flex, toggleAdminClaimBtn];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationController.toolbarHidden = NO;

    // Default to current user if no uid provided
    if (self.targetUID.length == 0) {
        UserModel *current = [FUManager shared].currentUser;
        self.targetUID = current.uid.length ? current.uid : current.ID;
    }

    [self buildHeader];
    [self attachPermissionsListener];
    
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
}

- (void)dealloc {
    [self.permsListener remove];
    self.permsListener = nil;
}

#pragma mark - Header

- (void)buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 84)];

    UILabel *uid = [self smallLabel];
    UILabel *role = [self smallLabel];
    UILabel *admin = [self smallLabel];

    uid.text = [NSString stringWithFormat:@"UID: %@", self.targetUID ?: @"<none>"];
    role.text = @"Role: —";
    admin.text = @"Admin: —";

    [header addSubview:uid];
    [header addSubview:role];
    [header addSubview:admin];

    uid.translatesAutoresizingMaskIntoConstraints = NO;
    role.translatesAutoresizingMaskIntoConstraints = NO;
    admin.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [uid.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [uid.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [uid.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],

        [role.leadingAnchor constraintEqualToAnchor:uid.leadingAnchor],
        [role.trailingAnchor constraintEqualToAnchor:uid.trailingAnchor],
        [role.topAnchor constraintEqualToAnchor:uid.bottomAnchor constant:6],

        [admin.leadingAnchor constraintEqualToAnchor:uid.leadingAnchor],
        [admin.trailingAnchor constraintEqualToAnchor:uid.trailingAnchor],
        [admin.topAnchor constraintEqualToAnchor:role.bottomAnchor constant:6],
    ]];

    self.tableView.tableHeaderView = header;
    self.uidLabel = uid;
    self.roleLabel = role;
    self.adminLabel = admin;

    [self updateHeaderRoleAndAdminFromCurrentValues];
}

- (UILabel *)smallLabel {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    l.textColor = [UIColor secondaryLabelColor];
    l.numberOfLines = 2;
    return l;
}

- (void)updateHeaderRoleAndAdminFromCurrentValues {
    // If you expose role lookup on RPManager, use it here; otherwise infer admin from AdminAll.
    BOOL isAdmin = [self valueForKey:@"AdminAll"];
    self.adminLabel.text = [NSString stringWithFormat:@"Admin: %@", isAdmin ? @"YES" : @"NO"];

    // Optional: if RPManager can fetch role title (e.g. via RPSubCol/role doc)
    if ([RPM respondsToSelector:@selector(cachedRoleNameForUID:)]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSString *roleName = [RPM performSelector:@selector(cachedRoleNameForUID:) withObject:self.targetUID];
        #pragma clang diagnostic pop
        if (roleName.length) {
            self.roleLabel.text = [NSString stringWithFormat:@"Role: %@", roleName];
        }
    }
}

#pragma mark - Live permissions

- (void)attachPermissionsListener {
    __weak typeof(self) weakSelf = self;

    // Stop existing
    [self.permsListener remove];
    self.permsListener = nil;

    if (self.targetUID.length == 0) { return; }

    self.permsListener =
    [RPM listenPermissionsForUID:self.targetUID
                        onChange:^(NSDictionary<NSString *,NSNumber *> * _Nonnull perms, NSError * _Nullable error)
    {
        if (error) {
            NSLog(@"❌ listenPermissions error: %@", error.localizedDescription);
            return;
        }

        // Map incoming dict → items array
        for (_PermItem *it in weakSelf.items) {
            it.value = [perms[it.key] boolValue];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateHeaderRoleAndAdminFromCurrentValues];
            [weakSelf.tableView reloadData];
        });
    }];
}

#pragma mark - Helpers

- (BOOL)valueForKey:(NSString *)key {
    for (_PermItem *it in self.items) if ([it.key isEqualToString:key]) return it.value;
    return NO;
}

- (NSIndexPath *)indexPathForKey:(NSString *)key {
    NSInteger row = 0;
    for (_PermItem *it in self.items) {
        if ([it.key isEqualToString:key]) {
            return [NSIndexPath indexPathForRow:row inSection:0];
        }
        row++;
    }
    return nil;
}

#pragma mark - Actions

- (void)refreshTapped {
    // Manual fetch once (optional)
    if (self.targetUID.length == 0) return;
    __weak typeof(self) weakSelf = self;
    [RPM fetchPermissionsForUID:self.targetUID completion:^(NSDictionary<NSString *,NSNumber *> * _Nullable perms, NSError * _Nullable error) {
        if (error) { NSLog(@"❌ fetchPermissions: %@", error.localizedDescription); return; }
        for (_PermItem *it in weakSelf.items) { it.value = [perms[it.key] boolValue]; }
        [weakSelf updateHeaderRoleAndAdminFromCurrentValues];
        [weakSelf.tableView reloadData];
    }];
}

- (void)setRoleTapped {
    if (self.targetUID.length == 0) return;

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Set Role"
                                                                message:@"Choose a role to apply"
                                                         preferredStyle:UIAlertControllerStyleActionSheet];

    void (^applyRole)(NSString *, NSInteger) = ^(NSString *name, NSInteger value){
        [RPM setRoleValue:(UserRole)value
                 roleName:name
                   forUID:self.targetUID
               completion:^(NSError * _Nullable error) {
            if (error) NSLog(@"❌ setRoleValue: %@", error.localizedDescription);
            else       NSLog(@"✅ role set to %@", name);
        }];
    };

    [ac addAction:[UIAlertAction actionWithTitle:@"User" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ applyRole(@"user", UserRoleUser); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Owner" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ applyRole(@"owner", UserRoleOwner); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Vet" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ applyRole(@"vet", UserRoleVet); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Moderator" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ applyRole(@"moderator", UserRoleModerator); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Store Manager" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ applyRole(@"storemanager", UserRoleStoreManager); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Food Manager" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ applyRole(@"foodmanager", UserRoleFoodManager); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Admin" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){ applyRole(@"admin", UserRoleAdmin); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Super Admin" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){ applyRole(@"superadmin", UserRoleSuperAdmin); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    [self presentActionSheetFromNavSafe:ac];
}

- (void)toggleAdminClaimTapped {
    if (self.targetUID.length == 0) return;

    [RPM toggleAdminClaimForUID:self.targetUID
                     completion:^(id  _Nullable obj, NSError * _Nullable error) {
        if (error) NSLog(@"❌ toggleAdminClaim: %@", error.localizedDescription);
        else       NSLog(@"✅ toggleAdminClaim ok: %@", obj);
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"Permissions"; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellID = @"permcell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:CellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellID];
        UISwitch *sw = [UISwitch new];
        sw.tag = 2211;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    _PermItem *it = self.items[indexPath.row];
    cell.textLabel.text = it.title;
    cell.detailTextLabel.text = it.key;
    ((UISwitch *)cell.accessoryView).on = it.value;
    ((UISwitch *)cell.accessoryView).accessibilityIdentifier = it.key; // carry key
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    if (self.targetUID.length == 0) return;
    NSString *key = sender.accessibilityIdentifier ?: @"";
    if (key.length == 0) return;

    [RPM setPermission:key forUID:self.targetUID allowed:sender.isOn
            completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ setPermission %@: %@", key, error.localizedDescription);
            // Revert UI on failure
            sender.on = !sender.on;
        } else {
            // Update local cache so header reflects correctly even before listener echo
            for (_PermItem *it in self.items) if ([it.key isEqualToString:key]) it.value = sender.isOn;
            [self updateHeaderRoleAndAdminFromCurrentValues];
        }
    }];
}

#pragma mark - iPad popover helper

- (void)presentActionSheetFromNavSafe:(UIAlertController *)ac {
    ac.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController *pop = ac.popoverPresentationController;
    if (pop) {
        pop.barButtonItem = self.toolbarItems.firstObject; // anchor to left toolbar button
        pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

@end
