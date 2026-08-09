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
#import "PurePetsColorPattle.h"
@import Firebase;
@import FirebaseAuth;

@interface PPSettingsViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPHero *heroGlassBG;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *emailLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *settingsTitleLabel;
@property (nonatomic, strong) UILabel *settingsSubtitleLabel;
@property (nonatomic, strong) UIView *profileCard;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *settingsSections;
@property (nonatomic, strong) NSArray<NSString *> *settingsSectionTitles;
@property (nonatomic, assign) BOOL didCaptureNavigationBarHiddenState;
@property (nonatomic, assign) BOOL previousNavigationBarHiddenState;
@property (nonatomic, assign) BOOL didRunEntrance;

@end

@implementation PPSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    self.title = kLang(@"Settings");
    
    [self setupSettingsItems];
    [self setupTableView];
    [self setupHeaderUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_applyNoNavigationBarAnimated:animated];
    [self updateProfileInfo];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self pp_runEntranceIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pp_restoreNavigationBarIfNeededAnimated:animated];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.heroGlassBG reapplyPalette];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;

    CGRect frame = header.frame;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    CGFloat height = [self pp_headerHeight];
    if (frame.size.width == width && frame.size.height == height) return;

    frame.size.width = width;
    frame.size.height = height;
    header.frame = frame;
    [header layoutIfNeeded];
    self.tableView.tableHeaderView = header;
}

- (CGFloat)pp_headerHeight {
    if (@available(iOS 11.0, *)) {
        if (UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory)) {
            return 360.0;
        }
    }
    return 292.0;
}

#pragma mark - Items Setup

- (void)setupSettingsItems {
    self.settingsSectionTitles = @[
        kLang(@"Settings_Section_Preferences"),
        kLang(@"Settings_Section_Support"),
        kLang(@"Settings_Section_Session")
    ];
    self.settingsSections = @[
        @[
        @{
            @"title": kLang(@"NotificationSettings"),
            @"subtitle": kLang(@"Settings_Notifications_Subtitle"),
            @"icon": @"bell.badge.fill",
            @"action": @"openNotifications"
        },
        @{
            @"title": kLang(@"AppLanguage"),
            @"subtitle": kLang(@"Settings_Language_Subtitle"),
            @"icon": @"globe",
            @"action": @"openLanguage"
        }
        ],
        @[
        @{
            @"title": kLang(@"HelpCenter"),
            @"subtitle": kLang(@"Settings_Help_Subtitle"),
            @"icon": @"questionmark.circle.fill",
            @"action": @"openHelp"
        }
        ],
        @[
        @{
            @"title": kLang(@"Logout"),
            @"subtitle": kLang(@"Settings_Logout_Subtitle"),
            @"icon": @"power.circle.fill",
            @"action": @"logout",
            @"destructive": @YES
        }
        ]
    ];
}

#pragma mark - UI Setup

- (void)pp_applyNoNavigationBarAnimated:(BOOL)animated {
    if (!self.navigationController) return;
    if (!self.didCaptureNavigationBarHiddenState) {
        self.previousNavigationBarHiddenState = self.navigationController.navigationBarHidden;
        self.didCaptureNavigationBarHiddenState = YES;
    }
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)pp_restoreNavigationBarIfNeededAnimated:(BOOL)animated {
    if (!self.navigationController || !self.didCaptureNavigationBarHiddenState) return;
    [self.navigationController setNavigationBarHidden:self.previousNavigationBarHiddenState animated:animated];
    self.didCaptureNavigationBarHiddenState = NO;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 88.0;
    self.tableView.sectionHeaderHeight = 36.0;
    self.tableView.sectionFooterHeight = PPSpaceLG;
    
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
    
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 292.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    header.layoutMargins = UIEdgeInsetsMake(0.0, PPSpaceBase, 0.0, PPSpaceBase);
    
    self.settingsTitleLabel = [UILabel new];
    self.settingsTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsTitleLabel.text = kLang(@"Settings");
    self.settingsTitleLabel.textColor = PrimaryTextClr;
    self.settingsTitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:28.0]];
    self.settingsTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.settingsTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [header addSubview:self.settingsTitleLabel];

    self.settingsSubtitleLabel = [UILabel new];
    self.settingsSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsSubtitleLabel.text = kLang(@"Settings_ProfileSubtitle");
    self.settingsSubtitleLabel.textColor = PPTextTertiaryColor();
    self.settingsSubtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:13.0]];
    self.settingsSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.settingsSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [header addSubview:self.settingsSubtitleLabel];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    [header addSubview:card];
    self.profileCard = card;
    
    PPHero *glassBG = [PPHero new];
    glassBG.translatesAutoresizingMaskIntoConstraints = NO;
    glassBG.animationsEnabled = NO;
    [card addSubview:glassBG];
    self.heroGlassBG = glassBG;

    UIView *accessRail = [UIView new];
    accessRail.translatesAutoresizingMaskIntoConstraints = NO;
    accessRail.backgroundColor = PPGoldAccentColor();
    accessRail.layer.cornerRadius = 2.0;
    [card addSubview:accessRail];
    
    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    
    UIView *avatarShell = [[UIView alloc] init];
    avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    avatarShell.backgroundColor = [AppBackgroundClrShiner colorWithAlphaComponent:0.78];
    avatarShell.layer.cornerRadius = 36.0;
    avatarShell.layer.cornerCurve = kCACornerCurveContinuous;
    avatarShell.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    avatarShell.layer.borderColor = PPLiquidBorderColor().CGColor;
    [content addSubview:avatarShell];
    
    self.avatarIMV = [[UIImageView alloc] init];
    self.avatarIMV.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarIMV.layer.cornerRadius = 31.0;
    self.avatarIMV.clipsToBounds = YES;
    self.avatarIMV.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarIMV.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatarIMV.tintColor = AppPrimaryClr;
    [avatarShell addSubview:self.avatarIMV];
    
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:24.0]];
    self.nameLabel.textColor = PrimaryTextClr;
    self.nameLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.nameLabel.adjustsFontForContentSizeCategory = YES;
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.text = @"—";
    [content addSubview:self.nameLabel];
    
    self.roleLabel = [[UILabel alloc] init];
    self.roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.roleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:14.0]];
    self.roleLabel.textColor = SeconderyTextClr;
    self.roleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.roleLabel.adjustsFontForContentSizeCategory = YES;
    self.roleLabel.text = @"—";
    [content addSubview:self.roleLabel];

    self.emailLabel = [[UILabel alloc] init];
    self.emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:12.0]];
    self.emailLabel.textColor = PPTextTertiaryColor();
    self.emailLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.emailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.emailLabel.adjustsFontForContentSizeCategory = YES;
    self.emailLabel.text = @"—";
    [content addSubview:self.emailLabel];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:12.0]];
    self.statusLabel.textColor = PPPrimaryColor();
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.backgroundColor = [PPPrimaryColor() colorWithAlphaComponent:0.10];
    self.statusLabel.layer.cornerRadius = 16.0;
    self.statusLabel.layer.masksToBounds = YES;
    [content addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.settingsTitleLabel.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceMD],
        [self.settingsTitleLabel.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [self.settingsTitleLabel.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [self.settingsSubtitleLabel.topAnchor constraintEqualToAnchor:self.settingsTitleLabel.bottomAnchor constant:PPSpaceXXS],
        [self.settingsSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.settingsTitleLabel.leadingAnchor],
        [self.settingsSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.settingsTitleLabel.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:self.settingsSubtitleLabel.bottomAnchor constant:PPSpaceMD],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPSpaceBase],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPSpaceBase],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceMD],

        [glassBG.topAnchor constraintEqualToAnchor:card.topAnchor],
        [glassBG.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [glassBG.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [glassBG.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [accessRail.topAnchor constraintEqualToAnchor:card.topAnchor],
        [accessRail.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceXL],
        [accessRail.widthAnchor constraintEqualToConstant:72.0],
        [accessRail.heightAnchor constraintEqualToConstant:4.0],

        [content.topAnchor constraintEqualToAnchor:card.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [avatarShell.topAnchor constraintEqualToAnchor:content.topAnchor constant:PPSpaceLG],
        [avatarShell.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:PPSpaceXL],
        [avatarShell.widthAnchor constraintEqualToConstant:72.0],
        [avatarShell.heightAnchor constraintEqualToConstant:72.0],

        [self.avatarIMV.centerXAnchor constraintEqualToAnchor:avatarShell.centerXAnchor],
        [self.avatarIMV.centerYAnchor constraintEqualToAnchor:avatarShell.centerYAnchor],
        [self.avatarIMV.widthAnchor constraintEqualToConstant:62.0],
        [self.avatarIMV.heightAnchor constraintEqualToConstant:62.0],

        [self.nameLabel.leadingAnchor constraintEqualToAnchor:avatarShell.trailingAnchor constant:PPSpaceBase],
        [self.nameLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-PPSpaceXL],
        [self.nameLabel.topAnchor constraintEqualToAnchor:avatarShell.topAnchor],

        [self.roleLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.roleLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        [self.roleLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:PPSpaceXS],

        [self.emailLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.emailLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        [self.emailLabel.topAnchor constraintEqualToAnchor:self.roleLabel.bottomAnchor constant:PPSpaceXXS],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:avatarShell.leadingAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:avatarShell.bottomAnchor constant:PPSpaceMD],
        [self.statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:108.0],
        [self.statusLabel.heightAnchor constraintEqualToConstant:32.0],
    ]];

    card.isAccessibilityElement = YES;
    card.accessibilityTraits = UIAccessibilityTraitHeader;
    card.accessibilityLabel = kLang(@"Settings_ProfileSubtitle");
    card.accessibilityIdentifier = @"settings.profile";
    
    self.tableView.tableHeaderView = header;
}

- (void)pp_runEntranceIfNeeded {
    if (self.didRunEntrance || !self.tableView) return;
    self.didRunEntrance = YES;

    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.tableView.alpha = 1.0;
        self.tableView.transform = CGAffineTransformIdentity;
        return;
    }

    self.tableView.alpha = 0.0;
    self.tableView.transform = CGAffineTransformMakeTranslation(0.0, 14.0);
    [UIView animateWithDuration:0.42
                          delay:0.0
         usingSpringWithDamping:0.90
          initialSpringVelocity:0.25
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.tableView.alpha = 1.0;
        self.tableView.transform = CGAffineTransformIdentity;
    } completion:nil];
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

    self.emailLabel.text = curUser.UserEmail.length ? curUser.UserEmail : @"—";
    self.statusLabel.text = curUser.isBlocked ? (kLang(@"Blocked") ?: @"Blocked") : (kLang(@"Active") ?: @"Active");
    self.statusLabel.textColor = curUser.isBlocked ? PPCriticalColor() : PPPrimaryColor();
    self.statusLabel.backgroundColor = [self.statusLabel.textColor colorWithAlphaComponent:0.10];
    self.profileCard.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@, %@",
                                           self.nameLabel.text ?: @"",
                                           self.roleLabel.text ?: @"",
                                           self.emailLabel.text ?: @"",
                                           self.statusLabel.text ?: @""];
    
    if (curUser.UserImageUrl.absoluteString.length > 0) {
        [self.avatarIMV setImageFromUrl:curUser.UserImageUrl.absoluteString Blr:NO Shimmering:YES];
    } else {
        self.avatarIMV.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    }
}

#pragma mark - UITableView Delegate & DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settingsSections[section].count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.settingsSections.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *container = [UIView new];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = self.settingsSectionTitles[section];
    label.textColor = PPTextTertiaryColor();
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:12.0]];
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = [Language alignmentForCurrentLanguage];
    label.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor]
    ]];
    return container;
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
        surface.layer.cornerRadius = PPCornerMedium;
        surface.layer.cornerCurve = kCACornerCurveContinuous;
        surface.layer.borderWidth = 1.0;
        surface.layer.borderColor = PPHairlineColor().CGColor;
        surface.layer.shadowColor = PPDeepCharcoalColor().CGColor;
        surface.layer.shadowOpacity = PPShadowSubtleOpacity;
        surface.layer.shadowRadius = PPShadowSubtleRadius;
        surface.layer.shadowOffset = CGSizeMake(0, PPShadowSubtleOffsetY);
        [cell.contentView addSubview:surface];

        UIView *iconSurface = [UIView new];
        iconSurface.tag = 103;
        iconSurface.translatesAutoresizingMaskIntoConstraints = NO;
        iconSurface.layer.cornerRadius = PPCornerMedium;
        iconSurface.layer.cornerCurve = kCACornerCurveContinuous;
        [surface addSubview:iconSurface];
        
        UIImageView *icon = [UIImageView new];
        icon.tag = 100;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [iconSurface addSubview:icon];
        
        UILabel *title = [UILabel new];
        title.tag = 101;
        title.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:16.0]];
        title.textAlignment = [Language alignmentForCurrentLanguage];
        title.adjustsFontForContentSizeCategory = YES;
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:title];

        UILabel *subtitle = [UILabel new];
        subtitle.tag = 104;
        subtitle.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:12.0]];
        subtitle.textColor = PPTextTertiaryColor();
        subtitle.textAlignment = [Language alignmentForCurrentLanguage];
        subtitle.numberOfLines = 2;
        subtitle.adjustsFontForContentSizeCategory = YES;
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:subtitle];

        UIView *separator = [UIView new];
        separator.tag = 105;
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        separator.backgroundColor = PPHairlineColor();
        [surface addSubview:separator];
        
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
        chevron.tag = 102;
        chevron.tintColor = [SeconderyTextClr ?: UIColor.secondaryLabelColor colorWithAlphaComponent:0.5];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:chevron];
        
        [NSLayoutConstraint activateConstraints:@[
            [surface.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [surface.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
            [surface.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
            [surface.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            
            [iconSurface.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:14.0],
            [iconSurface.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [iconSurface.widthAnchor constraintEqualToConstant:44.0],
            [iconSurface.heightAnchor constraintEqualToConstant:44.0],

            [icon.centerXAnchor constraintEqualToAnchor:iconSurface.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:iconSurface.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:22.0],
            [icon.heightAnchor constraintEqualToConstant:22.0],
            
            [title.leadingAnchor constraintEqualToAnchor:iconSurface.trailingAnchor constant:14.0],
            [title.topAnchor constraintEqualToAnchor:surface.topAnchor constant:15.0],
            [title.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-12.0],

            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2.0],
            [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-12.0],
            [subtitle.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-14.0],
            
            [chevron.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-16.0],
            [chevron.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:12.0],
            [chevron.heightAnchor constraintEqualToConstant:12.0],

            [separator.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [separator.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-PPSpaceBase],
            [separator.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor],
            [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
        ]];
    }
    
    NSDictionary *item = self.settingsSections[indexPath.section][indexPath.row];
    
    UIImageView *icon = [cell.contentView viewWithTag:100];
    UILabel *title = [cell.contentView viewWithTag:101];
    UIImageView *chevron = [cell.contentView viewWithTag:102];
    UIView *iconSurface = [cell.contentView viewWithTag:103];
    UILabel *subtitle = [cell.contentView viewWithTag:104];
    UIView *separator = [cell.contentView viewWithTag:105];
    UIView *surface = [cell.contentView viewWithTag:99];
    
    title.text = item[@"title"];
    subtitle.text = item[@"subtitle"];
    icon.image = [UIImage systemImageNamed:item[@"icon"]];
    BOOL isFirst = indexPath.row == 0;
    BOOL isLast = indexPath.row == self.settingsSections[indexPath.section].count - 1;
    surface.layer.maskedCorners = isFirst && isLast ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner) :
                                  isFirst ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner) :
                                  isLast ? (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner) : 0;
    separator.hidden = isLast;
    
    if ([item[@"destructive"] boolValue]) {
        title.textColor = UIColor.systemRedColor;
        subtitle.textColor = [UIColor.systemRedColor colorWithAlphaComponent:0.72];
        icon.tintColor = UIColor.systemRedColor;
        iconSurface.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.10];
        chevron.hidden = YES;
    } else {
        title.textColor = PrimaryTextClr ?: UIColor.labelColor;
        icon.tintColor = AppPrimaryClr ?: UIColor.systemBlueColor;
        iconSurface.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.10];
        chevron.hidden = NO;
    }
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.isAccessibilityElement = YES;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title.text ?: @"", subtitle.text ?: @""];
    cell.accessibilityIdentifier = item[@"action"];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[UISelectionFeedbackGenerator new] selectionChanged];
    NSDictionary *item = self.settingsSections[indexPath.section][indexPath.row];
    NSString *action = item[@"action"];
    
    if ([action isEqualToString:@"openNotifications"]) {
        NotificationSettingsViewController *vc = [NotificationSettingsViewController new];
        [self.navigationController pushViewController:vc animated:YES];
    } else if ([action isEqualToString:@"openLanguage"]) {
        // Post language notification to trigger AppMgr language picker
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PPOpenLanguageSelectionNotification" object:nil];
    } else if ([action isEqualToString:@"openHelp"]) {
        // Open web support or placeholder alert
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"HelpCenter")
                                                                       message:kLang(@"Settings_Help_Message")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if ([action isEqualToString:@"logout"]) {
        [UsrMgr signOut];
    }
}

@end
