//
//  PPSettingsViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 2026-07-13.
//

#import "PPSettingsViewController.h"
#import "NotificationSettingsViewController.h"
#import "UserManagementController.h"
#import "PPFirebaseCompat.h"
#import "Styling.h"
#import "Language.h"
#import "PPDesignTokens.h"
#import "AlertHelper.h"
@import Firebase;
@import FirebaseAuth;

typedef NS_ENUM(NSInteger, PPSettingsProfileState) {
    PPSettingsProfileStateLoading = 0,
    PPSettingsProfileStateReady,
    PPSettingsProfileStateUnavailable
};

@interface PPSettingsViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UIView *avatarShell;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *roleLabel;
@property (nonatomic, strong) UILabel *emailLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *profileChevron;
@property (nonatomic, strong) UIActivityIndicatorView *profileActivityIndicator;
@property (nonatomic, strong) UILabel *settingsTitleLabel;
@property (nonatomic, strong) UILabel *settingsSubtitleLabel;
@property (nonatomic, strong) UIView *profileCard;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *settingsSections;
@property (nonatomic, strong) NSArray<NSString *> *settingsSectionTitles;
@property (nonatomic, assign) PPSettingsProfileState profileState;
@property (nonatomic, assign) BOOL isSigningOut;
@property (nonatomic, copy, nullable) NSString *signOutErrorMessage;
@property (nonatomic, assign) BOOL didCaptureNavigationBarHiddenState;
@property (nonatomic, assign) BOOL previousNavigationBarHiddenState;
@property (nonatomic, assign) BOOL didRunEntrance;

@end

@implementation PPSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.title = kLang(@"Settings");
    self.profileState = PPSettingsProfileStateLoading;
    
    [self setupSettingsItems];
    [self setupTableView];
    [self setupHeaderUI];
    [self updateProfileInfo];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_applyNoNavigationBarAnimated:animated];
    [self pp_refreshLocalizedInterface];
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
    if (!previousTraitCollection ||
        [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self pp_applyPalette];
        [self.tableView reloadData];
    }
    if (!previousTraitCollection ||
        ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) {
        [self.tableView reloadData];
        [self.tableView beginUpdates];
        [self.tableView endUpdates];
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

- (void)pp_refreshLocalizedInterface {
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.title = kLang(@"Settings");
    self.settingsTitleLabel.text = kLang(@"Settings");
    self.settingsSubtitleLabel.text = kLang(@"Settings_ProfileSubtitle");
    self.settingsTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.settingsSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.profileCard.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.profileCard.accessibilityHint = kLang(@"EditMyAccount_Title");
    [self setupSettingsItems];
    [self.tableView reloadData];
}

- (void)pp_applyPalette {
    self.view.backgroundColor = [UIColor ppBackground];
    self.profileCard.backgroundColor = [UIColor ppSurface];
    self.profileCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    self.avatarShell.backgroundColor = [[UIColor ppPrimaryShiner] colorWithAlphaComponent:0.78];
    self.avatarShell.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    self.profileChevron.tintColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.72];
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
            @"action": @"openNotifications",
            @"tone": @"care"
        },
        @{
            @"title": kLang(@"AppLanguage"),
            @"subtitle": kLang(@"Settings_Language_Subtitle"),
            @"icon": @"globe",
            @"action": @"openLanguage",
            @"tone": @"accent"
        }
        ],
        @[
        @{
            @"title": kLang(@"HelpCenter"),
            @"subtitle": kLang(@"Settings_Help_Subtitle"),
            @"icon": @"questionmark.circle.fill",
            @"action": @"openHelp",
            @"tone": @"info"
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
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.layoutMargins = UIEdgeInsetsMake(0.0, PPScreenMargin, 0.0, PPScreenMargin);
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 36.0;
    self.tableView.sectionFooterHeight = PPSpaceLG;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, PPSpaceLG, 0.0);
    
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
    header.layoutMargins = UIEdgeInsetsMake(0.0, PPScreenMargin, 0.0, PPScreenMargin);
    
    self.settingsTitleLabel = [UILabel new];
    self.settingsTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsTitleLabel.text = kLang(@"Settings");
    self.settingsTitleLabel.textColor = [UIColor ppTextPrimary];
    self.settingsTitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontTitle1]];
    self.settingsTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.settingsTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.settingsTitleLabel.numberOfLines = 2;
    [header addSubview:self.settingsTitleLabel];

    self.settingsSubtitleLabel = [UILabel new];
    self.settingsSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsSubtitleLabel.text = kLang(@"Settings_ProfileSubtitle");
    self.settingsSubtitleLabel.textColor = [UIColor ppTextTertiary];
    self.settingsSubtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontSubheadline]];
    self.settingsSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.settingsSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.settingsSubtitleLabel.numberOfLines = 2;
    [header addSubview:self.settingsSubtitleLabel];

    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurface];
    card.layer.cornerRadius = PPCornerCard;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    card.layer.masksToBounds = YES;
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addTarget:self action:@selector(pp_openProfile) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:card];
    self.profileCard = card;

    UIView *accessRail = [UIView new];
    accessRail.translatesAutoresizingMaskIntoConstraints = NO;
    accessRail.backgroundColor = [UIColor ppPremiumAccent];
    accessRail.layer.cornerRadius = 2.0;
    accessRail.accessibilityElementsHidden = YES;
    accessRail.userInteractionEnabled = NO;
    [card addSubview:accessRail];
    
    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.accessibilityElementsHidden = YES;
    content.userInteractionEnabled = NO;
    [card addSubview:content];
    
    UIView *avatarShell = [[UIView alloc] init];
    avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    avatarShell.backgroundColor = [[UIColor ppPrimaryShiner] colorWithAlphaComponent:0.78];
    avatarShell.layer.cornerRadius = PPCorner16;
    avatarShell.layer.cornerCurve = kCACornerCurveContinuous;
    avatarShell.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    avatarShell.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    avatarShell.userInteractionEnabled = NO;
    [content addSubview:avatarShell];
    self.avatarShell = avatarShell;
    
    self.avatarIMV = [[UIImageView alloc] init];
    self.avatarIMV.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarIMV.layer.cornerRadius = PPCornerSmall;
    self.avatarIMV.layer.cornerCurve = kCACornerCurveContinuous;
    self.avatarIMV.clipsToBounds = YES;
    self.avatarIMV.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarIMV.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatarIMV.tintColor = [UIColor ppPrimary];
    self.avatarIMV.accessibilityElementsHidden = YES;
    [avatarShell addSubview:self.avatarIMV];
    
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontTitle2]];
    self.nameLabel.textColor = [UIColor ppTextPrimary];
    self.nameLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.nameLabel.adjustsFontForContentSizeCategory = YES;
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.text = kLang(@"Loading");
    [content addSubview:self.nameLabel];
    
    self.roleLabel = [[UILabel alloc] init];
    self.roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.roleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontSubheadline]];
    self.roleLabel.textColor = [UIColor ppTextSecondary];
    self.roleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.roleLabel.adjustsFontForContentSizeCategory = YES;
    self.roleLabel.text = kLang(@"Loading");
    [content addSubview:self.roleLabel];

    self.emailLabel = [[UILabel alloc] init];
    self.emailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emailLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:PPFontFootnote]];
    self.emailLabel.textColor = [UIColor ppTextTertiary];
    self.emailLabel.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.emailLabel.textAlignment = NSTextAlignmentLeft;
    self.emailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.emailLabel.numberOfLines = 2;
    self.emailLabel.adjustsFontForContentSizeCategory = YES;
    self.emailLabel.text = kLang(@"Loading");
    [content addSubview:self.emailLabel];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontFootnote]];
    self.statusLabel.textColor = [UIColor ppPrimary];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    self.statusLabel.layer.cornerRadius = PPCornerPill;
    self.statusLabel.layer.masksToBounds = YES;
    self.statusLabel.numberOfLines = 1;
    [content addSubview:self.statusLabel];

    self.profileChevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"
                                                                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                                                                         weight:UIImageSymbolWeightSemibold]]];
    self.profileChevron.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileChevron.tintColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.72];
    self.profileChevron.contentMode = UIViewContentModeScaleAspectFit;
    self.profileChevron.accessibilityElementsHidden = YES;
    [card addSubview:self.profileChevron];

    self.profileActivityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.profileActivityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.profileActivityIndicator.color = [UIColor ppPrimary];
    self.profileActivityIndicator.hidesWhenStopped = YES;
    self.profileActivityIndicator.accessibilityElementsHidden = YES;
    [card addSubview:self.profileActivityIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [self.settingsTitleLabel.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceMD],
        [self.settingsTitleLabel.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [self.settingsTitleLabel.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [self.settingsSubtitleLabel.topAnchor constraintEqualToAnchor:self.settingsTitleLabel.bottomAnchor constant:PPSpaceXXS],
        [self.settingsSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.settingsTitleLabel.leadingAnchor],
        [self.settingsSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.settingsTitleLabel.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:self.settingsSubtitleLabel.bottomAnchor constant:PPSpaceMD],
        [card.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceMD],

        [accessRail.topAnchor constraintEqualToAnchor:card.topAnchor],
        [accessRail.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceXL],
        [accessRail.widthAnchor constraintEqualToConstant:64.0],
        [accessRail.heightAnchor constraintEqualToConstant:4.0],

        [content.topAnchor constraintEqualToAnchor:card.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [avatarShell.topAnchor constraintEqualToAnchor:content.topAnchor constant:PPSpaceLG],
        [avatarShell.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:PPSpaceXL],
        [avatarShell.widthAnchor constraintEqualToConstant:68.0],
        [avatarShell.heightAnchor constraintEqualToConstant:68.0],

        [self.avatarIMV.centerXAnchor constraintEqualToAnchor:avatarShell.centerXAnchor],
        [self.avatarIMV.centerYAnchor constraintEqualToAnchor:avatarShell.centerYAnchor],
        [self.avatarIMV.widthAnchor constraintEqualToConstant:58.0],
        [self.avatarIMV.heightAnchor constraintEqualToConstant:58.0],

        [self.profileChevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceLG],
        [self.profileChevron.centerYAnchor constraintEqualToAnchor:avatarShell.centerYAnchor],
        [self.profileChevron.widthAnchor constraintEqualToConstant:18.0],
        [self.profileChevron.heightAnchor constraintEqualToConstant:22.0],

        [self.profileActivityIndicator.trailingAnchor constraintEqualToAnchor:self.profileChevron.leadingAnchor constant:-PPSpaceSM],
        [self.profileActivityIndicator.centerYAnchor constraintEqualToAnchor:avatarShell.centerYAnchor],
        [self.profileActivityIndicator.widthAnchor constraintEqualToConstant:20.0],
        [self.profileActivityIndicator.heightAnchor constraintEqualToConstant:20.0],

        [self.nameLabel.leadingAnchor constraintEqualToAnchor:avatarShell.trailingAnchor constant:PPSpaceBase],
        [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.profileChevron.leadingAnchor constant:-PPSpaceSM],
        [self.nameLabel.topAnchor constraintEqualToAnchor:avatarShell.topAnchor],

        [self.roleLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.roleLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        [self.roleLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:PPSpaceXS],

        [self.emailLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.emailLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
        [self.emailLabel.topAnchor constraintEqualToAnchor:self.roleLabel.bottomAnchor constant:PPSpaceXXS],
        [self.emailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-PPSpaceLG],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:avatarShell.leadingAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:avatarShell.bottomAnchor constant:PPSpaceMD],
        [self.statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:108.0],
        [self.statusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:32.0],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-PPSpaceLG],
    ]];

    card.isAccessibilityElement = YES;
    card.accessibilityTraits = UIAccessibilityTraitButton;
    card.accessibilityLabel = kLang(@"Settings_ProfileSubtitle");
    card.accessibilityHint = kLang(@"EditMyAccount_Title");
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
    self.profileState = PPSettingsProfileStateLoading;
    self.profileChevron.hidden = YES;
    [self.profileActivityIndicator startAnimating];

    UserModel *curUser = UsrMgr.currentUser;
    if (!curUser) {
        self.profileState = PPSettingsProfileStateUnavailable;
        self.nameLabel.text = kLang(@"NoSignedInUser_Title");
        self.roleLabel.text = kLang(@"StatusNoAccess");
        self.emailLabel.text = kLang(@"NoSignedInUser_Message");
        self.emailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.statusLabel.text = kLang(@"StatusNoAccess");
        self.statusLabel.textColor = [UIColor ppError];
        self.statusLabel.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.10];
        self.profileChevron.hidden = YES;
        self.profileCard.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@, %@",
                                               self.nameLabel.text ?: @"",
                                               self.roleLabel.text ?: @"",
                                               self.emailLabel.text ?: @"",
                                               self.statusLabel.text ?: @""];
        self.profileCard.accessibilityHint = kLang(@"NoSignedInUser_Message");
        [self.profileActivityIndicator stopAnimating];
        return;
    }

    self.profileState = PPSettingsProfileStateReady;
    NSString *displayName = curUser.UserName.length ? curUser.UserName : curUser.UserEmail;
    self.nameLabel.text = displayName.length ? displayName : kLang(@"StatusUserDocError");

    if (curUser.isAdmin || curUser.isSuperAdmin) {
        self.roleLabel.text = kLang(@"Role_Admin");
    } else {
        self.roleLabel.text = curUser.role ? ([PPRolePermission localizedRoleName:curUser.role] ?: kLang(@"pp_role_admin")) : kLang(@"pp_role_admin");
    }

    self.emailLabel.text = curUser.UserEmail.length ? curUser.UserEmail : kLang(@"StatusUserDocError");
    self.emailLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.statusLabel.text = curUser.isBlocked ? kLang(@"Blocked") : kLang(@"Active");
    self.statusLabel.textColor = curUser.isBlocked ? [UIColor ppError] : [UIColor ppPrimary];
    self.statusLabel.backgroundColor = [self.statusLabel.textColor colorWithAlphaComponent:0.10];
    self.profileChevron.hidden = NO;
    self.profileCard.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@, %@",
                                           self.nameLabel.text ?: @"",
                                           self.roleLabel.text ?: @"",
                                           self.emailLabel.text ?: @"",
                                           self.statusLabel.text ?: @""];
    self.profileCard.accessibilityHint = kLang(@"EditMyAccount_Title");
    [self.profileActivityIndicator stopAnimating];
    
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
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *marker = [UIView new];
    marker.translatesAutoresizingMaskIntoConstraints = NO;
    marker.backgroundColor = section == 2 ? [UIColor ppError] : [UIColor ppPremiumAccent];
    marker.layer.cornerRadius = 1.5;

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = self.settingsSectionTitles[section];
    label.textColor = [UIColor ppTextTertiary];
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontFootnote]];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 2;
    label.textAlignment = [Language alignmentForCurrentLanguage];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[marker, label]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = PPSpaceSM;
    stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:PPSpaceSM],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceSM],
        [marker.widthAnchor constraintEqualToConstant:3.0],
        [marker.heightAnchor constraintEqualToConstant:14.0]
    ]];
    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (UIColor *)pp_tintColorForItem:(NSDictionary *)item {
    NSString *tone = item[@"tone"];
    if ([tone isEqualToString:@"care"]) return [UIColor ppCareAccent];
    if ([tone isEqualToString:@"accent"]) return [UIColor ppPremiumAccent];
    if ([tone isEqualToString:@"info"]) return [UIColor ppInfo];
    return [UIColor ppPrimary];
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
        surface.backgroundColor = [UIColor ppSurface];
        surface.layer.cornerRadius = PPCornerSmall;
        surface.layer.cornerCurve = kCACornerCurveContinuous;
        surface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        surface.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        surface.layer.masksToBounds = YES;
        [cell.contentView addSubview:surface];

        UIView *iconSurface = [UIView new];
        iconSurface.tag = 103;
        iconSurface.translatesAutoresizingMaskIntoConstraints = NO;
        iconSurface.layer.cornerRadius = PPCornerSmall;
        iconSurface.layer.cornerCurve = kCACornerCurveContinuous;
        [surface addSubview:iconSurface];
        
        UIImageView *icon = [UIImageView new];
        icon.tag = 100;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.accessibilityElementsHidden = YES;
        [iconSurface addSubview:icon];
        
        UILabel *title = [UILabel new];
        title.tag = 101;
        title.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontBody]];
        title.textAlignment = [Language alignmentForCurrentLanguage];
        title.adjustsFontForContentSizeCategory = YES;
        title.numberOfLines = 0;
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:title];

        UILabel *subtitle = [UILabel new];
        subtitle.tag = 104;
        subtitle.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:PPFontFootnote]];
        subtitle.textColor = [UIColor ppTextTertiary];
        subtitle.textAlignment = [Language alignmentForCurrentLanguage];
        subtitle.numberOfLines = 0;
        subtitle.adjustsFontForContentSizeCategory = YES;
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:subtitle];

        UIView *separator = [UIView new];
        separator.tag = 105;
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        separator.backgroundColor = [UIColor ppSurfaceBorder];
        [surface addSubview:separator];
        
        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"
                                                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12.0
                                                                                                                                      weight:UIImageSymbolWeightSemibold]]];
        chevron.tag = 102;
        chevron.tintColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.72];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        chevron.accessibilityElementsHidden = YES;
        [surface addSubview:chevron];

        UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        activityIndicator.tag = 106;
        activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        activityIndicator.color = [UIColor ppPrimary];
        activityIndicator.hidesWhenStopped = YES;
        activityIndicator.accessibilityElementsHidden = YES;
        [surface addSubview:activityIndicator];
        
        [NSLayoutConstraint activateConstraints:@[
            [surface.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [surface.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:PPScreenMargin],
            [surface.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPScreenMargin],
            [surface.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            
            [iconSurface.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:PPSpaceMD],
            [iconSurface.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [iconSurface.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
            [iconSurface.heightAnchor constraintEqualToConstant:PPTouchTargetMin],

            [icon.centerXAnchor constraintEqualToAnchor:iconSurface.centerXAnchor],
            [icon.centerYAnchor constraintEqualToAnchor:iconSurface.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:22.0],
            [icon.heightAnchor constraintEqualToConstant:22.0],
            
            [title.leadingAnchor constraintEqualToAnchor:iconSurface.trailingAnchor constant:PPSpaceMD],
            [title.topAnchor constraintEqualToAnchor:surface.topAnchor constant:PPSpaceMD],
            [title.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-PPSpaceSM],

            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceXXS],
            [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-PPSpaceSM],
            [subtitle.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-PPSpaceMD],
            
            [chevron.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-PPSpaceMD],
            [chevron.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:14.0],
            [chevron.heightAnchor constraintEqualToConstant:18.0],

            [activityIndicator.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-PPSpaceMD],
            [activityIndicator.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [activityIndicator.widthAnchor constraintEqualToConstant:22.0],
            [activityIndicator.heightAnchor constraintEqualToConstant:22.0],

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
    UIActivityIndicatorView *activityIndicator = [cell.contentView viewWithTag:106];
    
    title.text = item[@"title"];
    NSString *action = item[@"action"];
    BOOL isDestructive = [item[@"destructive"] boolValue];
    BOOL isSigningOutRow = isDestructive && [action isEqualToString:@"logout"];
    NSString *subtitleText = item[@"subtitle"];
    if (isSigningOutRow && self.isSigningOut) {
        subtitleText = kLang(@"CommandCenter_Signing_Out");
    } else if (isSigningOutRow && self.signOutErrorMessage.length > 0) {
        subtitleText = self.signOutErrorMessage;
    }
    subtitle.text = subtitleText;
    icon.image = [UIImage systemImageNamed:item[@"icon"]];
    BOOL isFirst = indexPath.row == 0;
    BOOL isLast = indexPath.row == self.settingsSections[indexPath.section].count - 1;
    surface.layer.maskedCorners = isFirst && isLast ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner) :
                                  isFirst ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner) :
                                  isLast ? (kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner) : 0;
    separator.hidden = isLast;
    surface.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    surface.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    if (isDestructive) {
        title.textColor = [UIColor ppError];
        subtitle.textColor = [[UIColor ppError] colorWithAlphaComponent:0.72];
        icon.tintColor = [UIColor ppError];
        iconSurface.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.10];
        surface.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.055];
        chevron.hidden = YES;
    } else {
        title.textColor = [UIColor ppTextPrimary];
        UIColor *tintColor = [self pp_tintColorForItem:item];
        subtitle.textColor = [UIColor ppTextTertiary];
        icon.tintColor = tintColor;
        iconSurface.backgroundColor = [tintColor colorWithAlphaComponent:0.12];
        surface.backgroundColor = [UIColor ppSurface];
        chevron.hidden = NO;
    }
    BOOL shouldShowSpinner = isSigningOutRow && self.isSigningOut;
    activityIndicator.hidden = !shouldShowSpinner;
    if (shouldShowSpinner) {
        [activityIndicator startAnimating];
    } else {
        [activityIndicator stopAnimating];
    }
    cell.userInteractionEnabled = !shouldShowSpinner;
    cell.alpha = shouldShowSpinner ? 0.72 : 1.0;
    cell.isAccessibilityElement = YES;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (shouldShowSpinner ? UIAccessibilityTraitNotEnabled : 0);
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title.text ?: @"", subtitle.text ?: @""];
    cell.accessibilityIdentifier = action;
    
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
        [self pp_openLanguageSelection];
    } else if ([action isEqualToString:@"openHelp"]) {
        [self pp_presentHelp];
    } else if ([action isEqualToString:@"logout"]) {
        [self pp_confirmLogout];
    }
}

#pragma mark - Local Actions

- (void)pp_openProfile {
    [[UISelectionFeedbackGenerator new] selectionChanged];
    UserModel *currentUser = UsrMgr.currentUser;
    if (!currentUser) {
        [AlertHelper showInfoIn:self
                          title:kLang(@"NoSignedInUser_Title")
                       subtitle:kLang(@"NoSignedInUser_Message")];
        return;
    }

    UserManagementController *editor = [UserManagementController accountEditorForUser:currentUser];
    if (editor && self.navigationController) {
        [self.navigationController pushViewController:editor animated:YES];
    }
}

- (void)pp_openLanguageSelection {
    // Keep the existing event contract for any legacy picker owner.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PPOpenLanguageSelectionNotification" object:nil];

    NSInteger nextLanguageValue = ([Language languageVal] == 0) ? 1 : 0;
    [AlertHelper showConfirmationIn:self
                              title:kLang(@"Confirm_LanguageChange_Title")
                           subtitle:kLang(@"Confirm_LanguageChange_Msg")
                        placeholder:nil
                      confirmButton:kLang(@"Confirm")
                       cancelButton:kLang(@"Cancel")
                               icon:[UIImage systemImageNamed:@"globe"]
                       confirmBlock:^{
        [Language userSelectedLanguage:LanguageCode[nextLanguageValue]];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                                        kLang(@"Language changed successfully"));
    }
                        cancelBlock:nil];
}

- (void)pp_presentHelp {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"HelpCenter")
                                                                       message:kLang(@"Settings_Help_Message")
                                                                preferredStyle:UIAlertControllerStyleAlert];
    alert.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pp_confirmLogout {
    if (self.isSigningOut) return;

    [AlertHelper showConfirmationIn:self
                              title:kLang(@"Logout_Confirm_Title")
                           subtitle:kLang(@"Logout_Confirm_Message")
                        placeholder:nil
                      confirmButton:kLang(@"Confirm")
                       cancelButton:kLang(@"Cancel")
                               icon:[UIImage systemImageNamed:@"power.circle.fill"]
                       confirmBlock:^{
        [self pp_beginSignOut];
    }
                        cancelBlock:nil];
}

- (void)pp_beginSignOut {
    if (self.isSigningOut) return;
    self.isSigningOut = YES;
    self.signOutErrorMessage = nil;
    [self.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                                    kLang(@"CommandCenter_Signing_Out"));

    __weak typeof(self) weakSelf = self;
    [UsrMgr signOutWithCompletion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            strongSelf.isSigningOut = NO;
            if (error) {
                strongSelf.signOutErrorMessage = error.localizedDescription.length ? error.localizedDescription : kLang(@"Error");
                [strongSelf.tableView reloadData];
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                                                strongSelf.signOutErrorMessage);
                return;
            }

            strongSelf.signOutErrorMessage = nil;
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                                            kLang(@"Logout_Success_Message"));
        });
    }];
}

@end
