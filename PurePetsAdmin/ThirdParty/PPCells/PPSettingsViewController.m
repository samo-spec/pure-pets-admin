//
//  PPSettingsViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 2026-07-13.
//

#import "PPSettingsViewController.h"
#import "PPHero.h"
#import "NotificationSettingsViewController.h"
#import "PPFirebaseCompat.h"
#import "Styling.h"
#import "Language.h"
@import Firebase;
@import FirebaseAuth;

@interface PPSettingsViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPHero *heroGlassBG;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) NSArray<NSDictionary *> *settingsItems;

@end

@implementation PPSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    self.title = kLang(@"Settings") ?: @"Settings";
    
    [self setupSettingsItems];
    [self setupTableView];
    [self setupHeaderUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:kLang(@"Settings") ?: @"Settings" showBack:NO];
    [self updateProfileInfo];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroGlassBG startAnimations];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.heroGlassBG stopAnimations];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.heroGlassBG reapplyPalette];
    }
}

#pragma mark - Items Setup

- (void)setupSettingsItems {
    self.settingsItems = @[
        @{
            @"title": kLang(@"NotificationSettings") ?: @"Notification Settings",
            @"icon": @"bell.badge.fill",
            @"action": @"openNotifications"
        },
        @{
            @"title": kLang(@"AppLanguage") ?: @"Language Preference",
            @"icon": @"globe",
            @"action": @"openLanguage"
        },
        @{
            @"title": kLang(@"HelpCenter") ?: @"Help Center",
            @"icon": @"questionmark.circle.fill",
            @"action": @"openHelp"
        },
        @{
            @"title": kLang(@"Logout") ?: @"Logout",
            @"icon": @"power.circle.fill",
            @"action": @"logout",
            @"destructive": @YES
        }
    ];
}

#pragma mark - UI Setup

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = 70.0;
    
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupHeaderUI {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;
    
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 220.0)];
    header.backgroundColor = UIColor.clearColor;
    
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16.0, 8.0, width - 32.0, 204.0)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = UIColor.clearColor;
    [header addSubview:card];
    
    PPHero *glassBG = [PPHero new];
    glassBG.frame = card.bounds;
    glassBG.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:glassBG];
    self.heroGlassBG = glassBG;
    
    UIView *content = [UIView new];
    content.frame = card.bounds;
    content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:content];
    
    UIView *avatarShell = [[UIView alloc] initWithFrame:CGRectMake(24.0, 32.0, 72.0, 72.0)];
    avatarShell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    avatarShell.layer.cornerRadius = 36.0;
    avatarShell.layer.cornerCurve = kCACornerCurveContinuous;
    avatarShell.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    avatarShell.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor;
    [content addSubview:avatarShell];
    
    self.avatarIMV = [[UIImageView alloc] initWithFrame:CGRectMake(5.0, 5.0, 62.0, 62.0)];
    self.avatarIMV.layer.cornerRadius = 31.0;
    self.avatarIMV.clipsToBounds = YES;
    self.avatarIMV.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarIMV.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatarIMV.tintColor = AppPrimaryClr ?: UIColor.systemBlueColor;
    [avatarShell addSubview:self.avatarIMV];
    
    CGFloat textX = CGRectGetMaxX(avatarShell.frame) + 16.0;
    CGFloat textW = CGRectGetWidth(card.bounds) - textX - 24.0;
    
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 36.0, textW, 32.0)];
    self.nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.nameLabel.font = [Styling fontBold:24];
    self.nameLabel.textColor = PrimaryTextClr ?: UIColor.labelColor;
    self.nameLabel.text = @"—";
    [content addSubview:self.nameLabel];
    
    self.roleLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, CGRectGetMaxY(self.nameLabel.frame) + 4.0, textW, 20.0)];
    self.roleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.roleLabel.font = [Styling fontMedium:14];
    self.roleLabel.textColor = SeconderyTextClr ?: UIColor.secondaryLabelColor;
    self.roleLabel.text = @"—";
    [content addSubview:self.roleLabel];
    
    self.tableView.tableHeaderView = header;
}

#pragma mark - Profile Info Loader

- (void)updateProfileInfo {
    UserModel *curUser = UsrMgr.currentUser;
    if (!curUser) return;
    
    self.nameLabel.text = curUser.UserName.length ? curUser.UserName : (curUser.UserEmail.length ? curUser.UserEmail : @"—");
    
    if (curUser.isAdmin || curUser.isSuperAdmin) {
        self.roleLabel.text = kLang(@"Role_Admin") ?: @"System Admin";
    } else {
        self.roleLabel.text = curUser.role ? [PPRolePermission localizedRoleName:curUser.role] : (kLang(@"pp_role_admin") ?: @"Admin");
    }
    
    if (curUser.UserImageUrl.absoluteString.length > 0) {
        [self.avatarIMV setImageFromUrl:curUser.UserImageUrl.absoluteString Blr:NO Shimmering:YES];
    } else {
        self.avatarIMV.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    }
}

#pragma mark - UITableView Delegate & DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settingsItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SettingCell"];
        cell.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UIView *surface = [UIView new];
        surface.tag = 99;
        surface.translatesAutoresizingMaskIntoConstraints = NO;
        surface.backgroundColor = AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
        surface.layer.cornerRadius = 18.0;
        surface.layer.borderWidth = 1.0;
        surface.layer.borderColor = [(AppPrimaryClr ?: UIColor.systemBlueColor) colorWithAlphaComponent:0.04].CGColor;
        [cell.contentView addSubview:surface];
        
        UIImageView *icon = [UIImageView new];
        icon.tag = 100;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:icon];
        
        UILabel *title = [UILabel new];
        title.tag = 101;
        title.font = [Styling fontMedium:15];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:title];
        
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
        chevron.tag = 102;
        chevron.tintColor = [SeconderyTextClr ?: UIColor.secondaryLabelColor colorWithAlphaComponent:0.5];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:chevron];
        
        [NSLayoutConstraint activateConstraints:@[
            [surface.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:5.0],
            [surface.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
            [surface.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
            [surface.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-5.0],
            
            [icon.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:16.0],
            [icon.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:22.0],
            [icon.heightAnchor constraintEqualToConstant:22.0],
            
            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14.0],
            [title.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [title.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-12.0],
            
            [chevron.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-16.0],
            [chevron.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:12.0],
            [chevron.heightAnchor constraintEqualToConstant:12.0]
        ]];
    }
    
    NSDictionary *item = self.settingsItems[indexPath.row];
    
    UIImageView *icon = [cell.contentView viewWithTag:100];
    UILabel *title = [cell.contentView viewWithTag:101];
    UIImageView *chevron = [cell.contentView viewWithTag:102];
    
    title.text = item[@"title"];
    icon.image = [UIImage systemImageNamed:item[@"icon"]];
    
    if ([item[@"destructive"] boolValue]) {
        title.textColor = UIColor.systemRedColor;
        icon.tintColor = UIColor.systemRedColor;
        chevron.hidden = YES;
    } else {
        title.textColor = PrimaryTextClr ?: UIColor.labelColor;
        icon.tintColor = AppPrimaryClr ?: UIColor.systemBlueColor;
        chevron.hidden = NO;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.settingsItems[indexPath.row];
    NSString *action = item[@"action"];
    
    if ([action isEqualToString:@"openNotifications"]) {
        NotificationSettingsViewController *vc = [NotificationSettingsViewController new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openLanguage"]) {
        // Post language notification to trigger AppMgr language picker
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PPOpenLanguageSelectionNotification" object:nil];
    } else if ([action isEqualToString:@"openHelp"]) {
        // Open web support or placeholder alert
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"HelpCenter") ?: @"Help Center"
                                                                       message:@"For assistance, please visit support@purepets.co"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") ?: @"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if ([action isEqualToString:@"logout"]) {
        NSError *signOutError = nil;
        [[FIRAuth auth] signOut:&signOutError];
        if (signOutError) {
            NSLog(@"[FirebaseAuth] Sign out error: %@", signOutError);
        }
    }
}

@end
