#import "PPStaffPreviewViewController.h"
#import "PPStaffAuth.h"
#import "UserModel.h"
#import "Styling.h"
#import "Language.h"
#import "FUManager.h"
#import "PPHero.h"
@import Firebase;
@import FirebaseFirestore;

static NSString * const PPPreviewStaffCellID = @"PPPreviewStaffCell";

static UIColor *PPStaffPreviewSurfaceColor(void) {
    return [UIColor ppElevatedSurface];
}

static UIColor *PPStaffPreviewBackgroundColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPStaffPreviewPrimaryColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPStaffPreviewPrimaryTextColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPStaffPreviewSecondaryTextColor(void) {
    return [UIColor ppTextSecondary];
}

static UIColor *PPStaffPreviewBorderColor(void) {
    return [PPStaffPreviewPrimaryColor() colorWithAlphaComponent:0.08];
}

@interface PPPreviewStaffCell : UITableViewCell
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *iconShellView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)configureWithStaff:(PPStaffDoc *)staff;
@end

@implementation PPPreviewStaffCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _surfaceView = [[UIView alloc] init];
        _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
        _surfaceView.backgroundColor = PPStaffPreviewSurfaceColor();
        _surfaceView.layer.cornerRadius = 24.0;
        _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _surfaceView.layer.borderColor = PPStaffPreviewBorderColor().CGColor;
        _surfaceView.layer.shadowColor = UIColor.blackColor.CGColor;
        _surfaceView.layer.shadowOpacity = 0.055;
        _surfaceView.layer.shadowRadius = 14.0;
        _surfaceView.layer.shadowOffset = CGSizeMake(0, 8);
        [self.contentView addSubview:_surfaceView];

        _iconShellView = [[UIView alloc] init];
        _iconShellView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconShellView.backgroundColor = [PPStaffPreviewPrimaryColor() colorWithAlphaComponent:0.11];
        _iconShellView.layer.cornerRadius = 19.0;
        [_surfaceView addSubview:_iconShellView];

        UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.badge.key.fill" withConfiguration:iconConfig]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = PPStaffPreviewPrimaryColor();
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconShellView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:16.0];
        _titleLabel.textColor = PPStaffPreviewPrimaryTextColor();
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_surfaceView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:12.5];
        _subtitleLabel.textColor = [PPStaffPreviewSecondaryTextColor() colorWithAlphaComponent:0.92];
        _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _subtitleLabel.numberOfLines = 1;
        [_surfaceView addSubview:_subtitleLabel];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = [Styling fontMedium:11.5];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.layer.cornerRadius = 12.0;
        _statusLabel.layer.masksToBounds = YES;
        [_surfaceView addSubview:_statusLabel];

        UIImageSymbolConfiguration *chevronConfig = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:chevronConfig]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.tintColor = [PPStaffPreviewSecondaryTextColor() colorWithAlphaComponent:0.72];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        [_surfaceView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],
            [_surfaceView.heightAnchor constraintGreaterThanOrEqualToConstant:78.0],

            [_iconShellView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:16.0],
            [_iconShellView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_iconShellView.widthAnchor constraintEqualToConstant:38.0],
            [_iconShellView.heightAnchor constraintEqualToConstant:38.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconShellView.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconShellView.centerYAnchor],

            [_chevronView.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-16.0],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:14.0],
            [_chevronView.heightAnchor constraintEqualToConstant:14.0],

            [_statusLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-10.0],
            [_statusLabel.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],
            [_statusLabel.heightAnchor constraintEqualToConstant:24.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconShellView.trailingAnchor constant:12.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-10.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:17.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-10.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
            [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_surfaceView.bottomAnchor constant:-16.0],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.surfaceView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.surfaceView.bounds cornerRadius:self.surfaceView.layer.cornerRadius].CGPath;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
    self.surfaceView.transform = CGAffineTransformIdentity;
    self.surfaceView.alpha = 1.0;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CGFloat scale = highlighted ? 0.985 : 1.0;
    [UIView animateWithDuration:0.16 animations:^{
        self.surfaceView.transform = CGAffineTransformMakeScale(scale, scale);
        self.surfaceView.alpha = highlighted ? 0.96 : 1.0;
    }];
}

- (void)configureWithStaff:(PPStaffDoc *)staff {
    self.titleLabel.text = staff.uid.length ? staff.uid : @"-";
    self.subtitleLabel.text = [PPStaffAuth localizedRoleName:staff.role] ?: staff.role;
    BOOL active = staff.isActive;
    UIColor *statusColor = active ? [UIColor ppSuccess] : [UIColor ppError];
    self.statusLabel.text = active ? kLang(@"Active") : kLang(@"Disabled");
    self.statusLabel.textColor = statusColor;
    self.statusLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.12];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@",
                               self.titleLabel.text ?: @"",
                               self.subtitleLabel.text ?: @"",
                               self.statusLabel.text ?: @""];
}

@end

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
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UILabel *emptyTitleLabel;
@property (nonatomic, strong) UILabel *emptySubtitleLabel;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedStaffIDs;
@property (nonatomic, strong) PPHero *detailHeroBackground;

@property (nonatomic, assign) BOOL showingDetail;

@end

@implementation PPStaffPreviewViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PPStaffPreviewBackgroundColor();
    self.animatedStaffIDs = [NSMutableSet set];
    [self pp_buildModules];
    [self pp_buildUI];
    [self pp_fetchStaff];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.detailHeroBackground startAnimations];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.detailHeroBackground stopAnimations];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.detailHeroBackground reapplyPalette];
    }
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
    search.placeholder = kLang(@"SetPermissions_Search_Placeholder");
    search.delegate = self;
    search.searchBarStyle = UISearchBarStyleMinimal;
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.backgroundColor = PPStaffPreviewSurfaceColor();
    search.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.layer.cornerRadius = 23.0;
    search.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    search.layer.borderColor = PPStaffPreviewBorderColor().CGColor;
    search.layer.shadowColor = UIColor.blackColor.CGColor;
    search.layer.shadowOpacity = 0.05;
    search.layer.shadowRadius = 14.0;
    search.layer.shadowOffset = CGSizeMake(0, 8);
    search.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        search.searchTextField.backgroundColor = UIColor.clearColor;
        search.searchTextField.textColor = PPStaffPreviewPrimaryTextColor();
        search.searchTextField.font = [Styling fontMedium:16.0];
        search.searchTextField.textAlignment = Language.alignmentForCurrentLanguage;
        search.searchTextField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    }
    [self.view addSubview:search];
    self.searchBar = search;

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.dataSource = self;
    table.delegate = self;
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 78.0;
    table.contentInset = UIEdgeInsetsMake(8.0, 0.0, 34.0, 0.0);
    table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    table.showsVerticalScrollIndicator = NO;
    table.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [table registerClass:PPPreviewStaffCell.class forCellReuseIdentifier:PPPreviewStaffCellID];
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
    self.emptyStateView = [self pp_buildEmptyStateView];
    self.staffTable.backgroundView = self.emptyStateView;
    [self pp_updateEmptyStateTitle:kLang(@"Staff_Preview_Select")
                          subtitle:kLang(@"Staff_Preview_Subtitle")
                            hidden:NO];

    [NSLayoutConstraint activateConstraints:@[
        [search.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14],
        [search.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [search.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        [search.heightAnchor constraintEqualToConstant:52],

        [table.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:10],
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [scroll.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:10],
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

- (UIView *)pp_buildEmptyStateView {
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.backgroundColor = UIColor.clearColor;

    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];

    UIView *iconShell = [[UIView alloc] init];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPStaffPreviewPrimaryColor() colorWithAlphaComponent:0.09];
    iconShell.layer.cornerRadius = 28.0;
    [content addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.badge.key.fill"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = PPStaffPreviewPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

    self.emptyTitleLabel = [[UILabel alloc] init];
    self.emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyTitleLabel.font = [Styling fontBold:19.0];
    self.emptyTitleLabel.textColor = PPStaffPreviewPrimaryTextColor();
    self.emptyTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyTitleLabel.numberOfLines = 2;
    [content addSubview:self.emptyTitleLabel];

    self.emptySubtitleLabel = [[UILabel alloc] init];
    self.emptySubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptySubtitleLabel.font = [Styling fontRegular:14.0];
    self.emptySubtitleLabel.textColor = [PPStaffPreviewSecondaryTextColor() colorWithAlphaComponent:0.9];
    self.emptySubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.emptySubtitleLabel.numberOfLines = 3;
    [content addSubview:self.emptySubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:-20.0],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:28.0],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-28.0],

        [iconShell.topAnchor constraintEqualToAnchor:content.topAnchor],
        [iconShell.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [iconShell.widthAnchor constraintEqualToConstant:56.0],
        [iconShell.heightAnchor constraintEqualToConstant:56.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [self.emptyTitleLabel.topAnchor constraintEqualToAnchor:iconShell.bottomAnchor constant:18.0],
        [self.emptyTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.emptyTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [self.emptySubtitleLabel.topAnchor constraintEqualToAnchor:self.emptyTitleLabel.bottomAnchor constant:8.0],
        [self.emptySubtitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.emptySubtitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.emptySubtitleLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    return container;
}

- (void)pp_updateEmptyStateTitle:(NSString *)title subtitle:(NSString *)subtitle hidden:(BOOL)hidden {
    self.emptyTitleLabel.text = title ?: @"";
    self.emptySubtitleLabel.text = subtitle ?: @"";
    self.emptyStateView.hidden = hidden;
}

- (void)pp_showDetailForStaff:(PPStaffDoc *)staff {
    self.selectedStaff = staff;
    self.showingDetail = YES;

    for (UIView *sub in self.detailContent.subviews) {
        [sub removeFromSuperview];
    }

    CGFloat y = 10.0;
    CGFloat pad = 18.0;
    CGFloat w = self.view.bounds.size.width - pad * 2;

    BOOL isActive = staff.isActive;
    UIColor *statusColor = isActive ? [UIColor ppSuccess] : [UIColor ppError];
    NSString *statusText = isActive ? kLang(@"Active") : kLang(@"Disabled");
    NSString *scopeText = kLang(@"Staff_Scope_Global");
    if (staff.scope && [staff.scope isKindOfClass:NSDictionary.class] && staff.scope.count > 0) {
        scopeText = kLang(@"Staff_Scope_Limited");
    }

    UIView *heroCard = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w, 164.0)];
    heroCard.backgroundColor = UIColor.clearColor;
    [self.detailContent addSubview:heroCard];

    PPHero *hero = [PPHero new];
    hero.frame = heroCard.bounds;
    hero.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    hero.accentColorOverride = PPStaffPreviewPrimaryColor();
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.62;
    [heroCard addSubview:hero];
    self.detailHeroBackground = hero;
    [self.detailHeroBackground startAnimations];

    UIButton *returnButton = [UIButton buttonWithType:UIButtonTypeSystem];
    BOOL isRTL = [Language isRTL];
    CGFloat returnX = isRTL ? 18.0 : (CGRectGetWidth(heroCard.bounds) - 54.0);
    returnButton.frame = CGRectMake(returnX, 18.0, 36.0, 36.0);
    returnButton.autoresizingMask = isRTL ? UIViewAutoresizingFlexibleRightMargin : UIViewAutoresizingFlexibleLeftMargin;
    returnButton.backgroundColor = [PPStaffPreviewSurfaceColor() colorWithAlphaComponent:0.78];
    returnButton.layer.cornerRadius = 18.0;
    returnButton.tintColor = PPStaffPreviewPrimaryTextColor();
    NSString *returnSymbol = isRTL ? @"arrow.right" : @"arrow.left";
    [returnButton setImage:[UIImage systemImageNamed:returnSymbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold]]
                  forState:UIControlStateNormal];
    [returnButton addTarget:self action:@selector(pp_returnToPreviewList) forControlEvents:UIControlEventTouchUpInside];
    returnButton.accessibilityLabel = kLang(@"Back");
    [heroCard addSubview:returnButton];

    CGFloat iconX = isRTL ? (CGRectGetWidth(heroCard.bounds) - 70.0) : 18.0;
    UIView *iconShell = [[UIView alloc] initWithFrame:CGRectMake(iconX, 22.0, 52.0, 52.0)];
    iconShell.autoresizingMask = isRTL ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
    iconShell.backgroundColor = [PPStaffPreviewPrimaryColor() colorWithAlphaComponent:0.13];
    iconShell.layer.cornerRadius = 18.0;
    [heroCard addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.badge.shield.checkmark"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]];
    iconView.frame = CGRectMake(14.0, 14.0, 24.0, 24.0);
    iconView.tintColor = PPStaffPreviewPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

    CGFloat textX = isRTL ? (CGRectGetMaxX(returnButton.frame) + 12.0) : (CGRectGetMaxX(iconShell.frame) + 14.0);
    CGFloat textMaxX = isRTL ? (CGRectGetMinX(iconShell.frame) - 14.0) : (CGRectGetMinX(returnButton.frame) - 12.0);
    CGFloat textWidth = MAX(textMaxX - textX, 120.0);
    UILabel *roleLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 24.0, textWidth, 30.0)];
    roleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    roleLabel.text = [PPStaffAuth localizedRoleName:staff.role] ?: staff.role;
    roleLabel.font = [Styling fontBold:24.0];
    roleLabel.textColor = PPStaffPreviewPrimaryTextColor();
    roleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    roleLabel.adjustsFontSizeToFitWidth = YES;
    roleLabel.minimumScaleFactor = 0.82;
    [heroCard addSubview:roleLabel];

    UILabel *uidLabel = [[UILabel alloc] initWithFrame:CGRectMake(roleLabel.frame.origin.x,
                                                                  CGRectGetMaxY(roleLabel.frame) + 6.0,
                                                                  CGRectGetWidth(roleLabel.frame),
                                                                  38.0)];
    uidLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    uidLabel.text = staff.uid.length ? staff.uid : @"-";
    uidLabel.font = [Styling fontRegular:13.5];
    uidLabel.textColor = [PPStaffPreviewSecondaryTextColor() colorWithAlphaComponent:0.94];
    uidLabel.textAlignment = Language.alignmentForCurrentLanguage;
    uidLabel.numberOfLines = 2;
    uidLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [heroCard addSubview:uidLabel];

    CGFloat statusX = isRTL ? (CGRectGetWidth(heroCard.bounds) - 18.0 - 104.0) : 18.0;
    UIView *statusPill = [self pp_buildPillWithText:statusText tintColor:statusColor frame:CGRectMake(statusX, CGRectGetHeight(heroCard.bounds) - 44.0, 104.0, 28.0)];
    [heroCard addSubview:statusPill];

    CGFloat scopeX = isRTL ? (CGRectGetMinX(statusPill.frame) - 8.0 - 142.0) : (CGRectGetMaxX(statusPill.frame) + 8.0);
    UIView *scopePill = [self pp_buildPillWithText:scopeText tintColor:PPStaffPreviewPrimaryColor() frame:CGRectMake(scopeX, CGRectGetMinY(statusPill.frame), 142.0, 28.0)];
    scopePill.autoresizingMask = isRTL ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
    [heroCard addSubview:scopePill];
    y += CGRectGetHeight(heroCard.bounds) + 14.0;

    UIView *roleCard = [self pp_buildDetailInfoRowWithTitle:kLang(@"Staff_Role_Effective")
                                                      value:[PPStaffAuth localizedRoleName:staff.role] ?: staff.role
                                                 valueColor:PPStaffPreviewPrimaryColor()
                                                      frame:CGRectMake(pad, y, w, 54.0)];
    [self.detailContent addSubview:roleCard];
    y += 62.0;

    UIView *statusCard = [self pp_buildDetailInfoRowWithTitle:kLang(@"Staff_Status_Label")
                                                        value:statusText
                                                   valueColor:statusColor
                                                        frame:CGRectMake(pad, y, w, 54.0)];
    [self.detailContent addSubview:statusCard];
    y += 62.0;

    UIView *scopeCard = [self pp_buildDetailInfoRowWithTitle:kLang(@"Staff_Scope_Label")
                                                       value:scopeText
                                                  valueColor:PPStaffPreviewPrimaryTextColor()
                                                       frame:CGRectMake(pad, y, w, 54.0)];
    [self.detailContent addSubview:scopeCard];
    y += 70.0;

    UILabel *permHeader = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w, 30)];
    permHeader.text = kLang(@"Staff_Permissions_Breakdown");
    permHeader.font = [Styling fontBold:20.0];
    permHeader.textColor = PPStaffPreviewPrimaryTextColor();
    permHeader.textAlignment = Language.alignmentForCurrentLanguage;
    [self.detailContent addSubview:permHeader];
    y += 40.0;

    for (PPStaffPreviewPermissionModule *mod in self.modules) {
        CGFloat cardH = [self pp_heightForModuleCard:mod];
        UIView *card = [self pp_buildModuleCard:mod frame:CGRectMake(pad, y, w, cardH)];
        [self.detailContent addSubview:card];
        y += cardH + 10.0;
    }

    y += 24.0;

    self.detailContent.frame = CGRectMake(0, 0, self.view.bounds.size.width, y);
    self.detailScroll.contentSize = CGSizeMake(self.view.bounds.size.width, y);

    self.staffTable.hidden = YES;
    self.detailScroll.hidden = NO;
    [self.detailScroll scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];

    if (!UIAccessibilityIsReduceMotionEnabled()) {
        self.detailContent.alpha = 0.0;
        self.detailContent.transform = CGAffineTransformMakeTranslation(0.0, 14.0);
        [UIView animateWithDuration:0.34
                              delay:0.02
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            self.detailContent.alpha = 1.0;
            self.detailContent.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)pp_returnToPreviewList {
    self.showingDetail = NO;
    [self.detailHeroBackground stopAnimations];
    self.detailHeroBackground = nil;
    self.detailScroll.hidden = YES;
    self.staffTable.hidden = NO;
    [self.searchBar resignFirstResponder];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        return;
    }
    self.staffTable.alpha = 0.0;
    self.staffTable.transform = CGAffineTransformMakeTranslation(0.0, -8.0);
    [UIView animateWithDuration:0.24
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.staffTable.alpha = 1.0;
        self.staffTable.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (UIView *)pp_buildPillWithText:(NSString *)text tintColor:(UIColor *)tintColor frame:(CGRect)frame {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text ?: @"";
    label.font = [Styling fontMedium:12.0];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = tintColor ?: PPStaffPreviewPrimaryColor();
    label.backgroundColor = [(tintColor ?: PPStaffPreviewPrimaryColor()) colorWithAlphaComponent:0.12];
    label.layer.cornerRadius = CGRectGetHeight(frame) / 2.0;
    label.layer.masksToBounds = YES;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.82;
    label.accessibilityLabel = label.text;
    return label;
}

- (UIView *)pp_buildDetailInfoRowWithTitle:(NSString *)title value:(NSString *)value valueColor:(UIColor *)valueColor frame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = PPStaffPreviewSurfaceColor();
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = PPStaffPreviewBorderColor().CGColor;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 0.0, 116.0, CGRectGetHeight(frame))];
    titleLabel.text = title ?: @"";
    titleLabel.font = [Styling fontMedium:13.0];
    titleLabel.textColor = [PPStaffPreviewSecondaryTextColor() colorWithAlphaComponent:0.9];
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.82;
    [card addSubview:titleLabel];

    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(140.0, 0.0, CGRectGetWidth(frame) - 156.0, CGRectGetHeight(frame))];
    valueLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    valueLabel.text = value ?: @"";
    valueLabel.font = [Styling fontMedium:16.0];
    valueLabel.textColor = valueColor ?: PPStaffPreviewPrimaryTextColor();
    valueLabel.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    valueLabel.adjustsFontSizeToFitWidth = YES;
    valueLabel.minimumScaleFactor = 0.78;
    [card addSubview:valueLabel];

    card.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", titleLabel.text ?: @"", valueLabel.text ?: @""];
    return card;
}

- (CGFloat)pp_heightForModuleCard:(PPStaffPreviewPermissionModule *)mod {
    NSUInteger perms = MAX(mod.requiredPerms.count, 1);
    CGFloat rows = ceil((CGFloat)perms / 3.0);
    return 52.0 + (rows * 30.0) + 12.0;
}

- (UIView *)pp_buildModuleCard:(PPStaffPreviewPermissionModule *)mod frame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = PPStaffPreviewSurfaceColor();
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = PPStaffPreviewBorderColor().CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 12.0, frame.size.width - 32.0, 24.0)];
    title.text = kLang(mod.localizedKey);
    title.font = [Styling fontBold:16.0];
    title.textColor = PPStaffPreviewPrimaryTextColor();
    title.textAlignment = Language.alignmentForCurrentLanguage;
    [card addSubview:title];

    CGFloat px = 16.0;
    CGFloat py = 44.0;
    CGFloat tagH = 24.0;

    for (NSString *perm in mod.requiredPerms) {
        BOOL granted = [self.selectedStaff hasPermission:perm];
        NSString *label = [self pp_localizedPermissionName:perm];
        UIColor *bg = granted ? [[UIColor ppSuccess] colorWithAlphaComponent:0.15] : [[UIColor ppError] colorWithAlphaComponent:0.1];
        UIColor *fg = granted ? [UIColor ppSuccess] : [UIColor ppError];

        UILabel *tag = [[UILabel alloc] initWithFrame:CGRectMake(px, py, 0, tagH)];
        tag.text = label;
        tag.font = [Styling fontMedium:11.0];
        tag.textColor = fg;
        tag.backgroundColor = bg;
        tag.layer.cornerRadius = 8.0;
        tag.clipsToBounds = YES;
        tag.textAlignment = NSTextAlignmentCenter;
        [tag sizeToFit];
        CGRect tf = tag.frame;
        tf.size.width += 18.0;
        tf.size.height = tagH;
        if (tf.size.width < 68.0) tf.size.width = 68.0;
        if (tf.size.width > frame.size.width - 32.0) tf.size.width = frame.size.width - 32.0;
        if (px + tf.size.width + 8.0 > frame.size.width - 16.0) {
            px = 16.0;
            py += 30.0;
        }
        tf.origin.x = px;
        tf.origin.y = py;
        tag.frame = tf;
        tag.accessibilityLabel = [NSString stringWithFormat:@"%@, %@",
                                  label,
                                  granted ? kLang(@"Staff_Permission_Granted") : kLang(@"Staff_Permission_NotGranted")];
        px += tf.size.width + 8.0;
        [card addSubview:tag];
    }

    return card;
}

- (NSString *)pp_localizedPermissionName:(NSString *)perm {
    NSString *token = [[perm ?: @"" stringByReplacingOccurrencesOfString:@"." withString:@"_"] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSString *suffix = token.length ? token : @"";
    NSString *key = [@"StaffPerm_" stringByAppendingString:suffix];
    NSString *localized = kLang(key);
    if ([localized isKindOfClass:NSString.class] && localized.length > 0 && ![localized isEqualToString:key]) {
        return localized;
    }
    return perm ?: @"";
}

#pragma mark - Fetch Staff

- (void)pp_fetchStaff {
    [[PPStaffAuth shared] fetchAllStaff:^(NSArray<PPStaffDoc *> * _Nullable docs, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                self.allStaff = @[];
                self.filteredStaff = @[];
                [self pp_updateEmptyStateTitle:kLang(@"Staff_Preview_Load_Error")
                                      subtitle:kLang(@"Staff_Preview_Load_Error_Subtitle")
                                        hidden:NO];
                [self.staffTable reloadData];
                return;
            }
            self.allStaff = docs ?: @[];
            self.filteredStaff = self.allStaff;
            [self pp_updateEmptyStateTitle:kLang(@"Staff_Preview_Empty")
                                  subtitle:kLang(@"Staff_Preview_Subtitle")
                                    hidden:self.filteredStaff.count > 0];
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
    [self pp_updateEmptyStateTitle:kLang(@"Staff_Preview_Empty")
                          subtitle:kLang(@"Staff_Preview_Subtitle")
                            hidden:self.filteredStaff.count > 0];
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
    PPPreviewStaffCell *cell = [tableView dequeueReusableCellWithIdentifier:PPPreviewStaffCellID forIndexPath:indexPath];
    PPStaffDoc *staff = self.filteredStaff[indexPath.row];
    [cell configureWithStaff:staff];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.filteredStaff.count || UIAccessibilityIsReduceMotionEnabled()) return;

    PPStaffDoc *staff = self.filteredStaff[indexPath.row];
    NSString *identifier = staff.uid.length ? staff.uid : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedStaffIDs containsObject:identifier]) return;
    [self.animatedStaffIDs addObject:identifier];

    cell.contentView.alpha = 0.0;
    cell.contentView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    NSTimeInterval delay = MIN(indexPath.row, 8) * 0.025;
    [UIView animateWithDuration:0.32
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.contentView.alpha = 1.0;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PPStaffDoc *staff = self.filteredStaff[indexPath.row];
    [self.searchBar resignFirstResponder];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self pp_showDetailForStaff:staff];
}

@end
