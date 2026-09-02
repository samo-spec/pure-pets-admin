//
//  NotificationsListViewController.m
//  PurePetsAdmin
//
//  Reimagined category-defining administrative notification command center.
//  First-principles spatial composition: Cockpit KPIs, Triage Lenses,
//  Chronological Day Grouping, Omni-Search, Flagship Cards, and Action Hub.
//

#import "NotificationsListViewController.h"
#import "NotificationCell.h"
#import "NotificationDetailViewController.h"
#import "NotificationComposerViewController.h"
#import "NotificationSettingsViewController.h"
#import "NotificationManager.h"
#import "NotificationModel.h"
#import "Styling.h"
#import "Language.h"
#import "PPDesignTokens.h"
#import "UIViewController+PPNavBar.h"
#import "PPFunc.h"
#import "PPHUD.h"
#import "PPToast.h"
#import "SceneDelegate.h"
@import FirebaseAuth;

typedef NS_ENUM(NSInteger, PPAdminNotificationLens) {
    PPAdminNotificationLensInbox = 0,
    PPAdminNotificationLensUnread,
    PPAdminNotificationLensOrders,
    PPAdminNotificationLensDelivery,
    PPAdminNotificationLensChat,
    PPAdminNotificationLensAlerts
};

@interface PPAdminDaySection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<NotificationModel *> *items;
@end

@implementation PPAdminDaySection
@end

@interface NotificationsListViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *cockpitHeaderView;

// Cockpit Metric Badges
@property (nonatomic, strong) UILabel *kpiTotalLabel;
@property (nonatomic, strong) UILabel *kpiUnreadLabel;
@property (nonatomic, strong) UILabel *kpiOrdersLabel;
@property (nonatomic, strong) UILabel *kpiChatLabel;

// Search & Lens
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIButton *searchClearBtn;
@property (nonatomic, strong) UILabel *searchCountLabel;
@property (nonatomic, strong) UIScrollView *lensScrollView;
@property (nonatomic, strong) UIStackView *lensStackView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *lensButtons;

// Empty State
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *emptyImageView;
@property (nonatomic, strong) UILabel *emptyTitleLabel;
@property (nonatomic, strong) UILabel *emptySubtitleLabel;

// Data & State
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, assign) PPAdminNotificationLens activeLens;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) NSArray<NotificationModel *> *allNotifications;
@property (nonatomic, strong) NSArray<NotificationModel *> *filteredNotifications;
@property (nonatomic, strong) NSArray<PPAdminDaySection *> *daySections;

@property (nonatomic, strong, nullable) id<FIRListenerRegistration> inboxListener;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation NotificationsListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.uid = [FIRAuth auth].currentUser.uid ?: @"";
    self.allNotifications = @[];
    self.filteredNotifications = @[];
    self.daySections = @[];
    self.activeLens = PPAdminNotificationLensInbox;
    self.searchQuery = @"";

    [self setupNavigation];
    [self setupTableView];
    [self setupCockpitHeader];
    [self setupEmptyStateView];
    [self startObservingInbox];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateNavigationButtons];
    
    NSString *currentUID = [FIRAuth auth].currentUser.uid ?: @"";
    if (![self.uid isEqualToString:currentUID] || (currentUID.length > 0 && !self.inboxListener)) {
        [self.inboxListener remove];
        self.inboxListener = nil;
        self.uid = currentUID;
        [self startObservingInbox];
    }
}

- (void)dealloc {
    [self.inboxListener remove];
    self.inboxListener = nil;
}

#pragma mark - Navigation

- (void)setupNavigation {
    NSString *navTitle = kLang(@"NotificationsTitle") ?: ([Language isRTL] ? @"الإشعارات" : @"Notifications");
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:navTitle showBack:YES];

    [self updateNavigationButtons];
}

- (void)updateNavigationButtons {
    // 1. Settings button
    UIButton *settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [settingsBtn setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    settingsBtn.tintColor = [UIColor ppPrimary];
    [settingsBtn addTarget:self action:@selector(openSettingsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self pp_navBarAddActionButton:settingsBtn key:@"notif_settings"];

    // 2. Compose broadcast button
    UIButton *composeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    composeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [composeBtn setImage:[UIImage systemImageNamed:@"paperplane.fill"] forState:UIControlStateNormal];
    composeBtn.tintColor = [UIColor ppPrimary];
    [composeBtn addTarget:self action:@selector(openComposerTapped) forControlEvents:UIControlEventTouchUpInside];
    [self pp_navBarAddActionButton:composeBtn key:@"notif_compose"];

    // 3. Mark all as read button
    UIButton *markAllBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    markAllBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [markAllBtn setImage:[UIImage systemImageNamed:@"checklist.checked"] forState:UIControlStateNormal];
    markAllBtn.tintColor = [UIColor ppPrimary];
    [markAllBtn addTarget:self action:@selector(markAllAsReadTapped) forControlEvents:UIControlEventTouchUpInside];
    [self pp_navBarAddActionButton:markAllBtn key:@"notif_mark_all"];
}

- (void)openSettingsTapped {
    [PPFunc pp_playTapEffect];
    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openComposerTapped {
    [PPFunc pp_playTapEffect];
    NotificationComposerViewController *vc = [[NotificationComposerViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)markAllAsReadTapped {
    [PPFunc pp_playTapEffect];
    
    NSArray<NotificationModel *> *unreadItems = [self.allNotifications filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isRead == NO"]];
    if (unreadItems.count == 0) {
        [PPHUD showSuccess:[Language isRTL] ? @"جميع الإشعارات مقروءة بالفعل" : @"All notifications already read"];
        return;
    }

    for (NotificationModel *m in unreadItems) {
        m.isRead = YES;
        [[NotificationManager shared] markRead:m forUser:self.uid completion:nil];
    }
    
    [self applyFilterAndRecomputeSections];
    [self updateCockpitKPIs];
    [self.tableView reloadData];
    
    NSString *msg = [Language isRTL]
        ? [NSString stringWithFormat:@"تم تحديد %ld تنبيه كمقروء", (long)unreadItems.count]
        : [NSString stringWithFormat:@"Marked %ld notifications as read", (long)unreadItems.count];
    [PPHUD showSuccess:msg];
}

#pragma mark - UI Setup

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 130.0;
    _tableView.sectionHeaderTopPadding = 8.0;
    _tableView.contentInset = UIEdgeInsetsMake(0, 0, 90, 0);
    [_tableView registerClass:[NotificationCell class] forCellReuseIdentifier:[NotificationCell reuseId]];

    _refreshControl = [[UIRefreshControl alloc] init];
    _refreshControl.tintColor = [UIColor ppPrimary];
    [_refreshControl addTarget:self action:@selector(onRefreshTriggered) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupCockpitHeader {
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenW, 310)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    // 1. Cockpit Metric Card
    UIView *metricsCard = [[UIView alloc] init];
    metricsCard.translatesAutoresizingMaskIntoConstraints = NO;
    metricsCard.backgroundColor = [UIColor ppSurfaceElevated];
    metricsCard.layer.borderWidth = 1.0;
    metricsCard.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(metricsCard, PPCornerCard);
    PPApplyCardShadow(metricsCard);
    [header addSubview:metricsCard];

    UIStackView *metricsGrid = [[UIStackView alloc] init];
    metricsGrid.translatesAutoresizingMaskIntoConstraints = NO;
    metricsGrid.axis = UILayoutConstraintAxisHorizontal;
    metricsGrid.distribution = UIStackViewDistributionFillEqually;
    metricsGrid.spacing = 8;
    [metricsCard addSubview:metricsGrid];

    _kpiTotalLabel = [self makeKPILabelWithColor:[UIColor ppTextPrimary]];
    _kpiUnreadLabel = [self makeKPILabelWithColor:[UIColor ppPrimary]];
    _kpiOrdersLabel = [self makeKPILabelWithColor:[UIColor ppQuickActionShopping] ?: [UIColor systemOrangeColor]];
    _kpiChatLabel = [self makeKPILabelWithColor:[UIColor ppQuickActionServices] ?: [UIColor systemGreenColor]];

    UIView *tileTotal = [self makeKPITileWithTitle:[Language isRTL] ? @"الإجمالي" : @"Total"
                                             icon:@"bell.fill"
                                            color:[UIColor ppTextPrimary]
                                       valueLabel:_kpiTotalLabel
                                              tag:PPAdminNotificationLensInbox];
    UIView *tileUnread = [self makeKPITileWithTitle:[Language isRTL] ? @"غير مقروء" : @"Unread"
                                              icon:@"envelope.badge.fill"
                                             color:[UIColor ppPrimary]
                                        valueLabel:_kpiUnreadLabel
                                               tag:PPAdminNotificationLensUnread];
    UIView *tileOrders = [self makeKPITileWithTitle:[Language isRTL] ? @"الطلبات" : @"Orders"
                                              icon:@"bag.fill"
                                             color:[UIColor ppQuickActionShopping] ?: [UIColor systemOrangeColor]
                                        valueLabel:_kpiOrdersLabel
                                               tag:PPAdminNotificationLensOrders];
    UIView *tileChat = [self makeKPITileWithTitle:[Language isRTL] ? @"الدعم" : @"Support"
                                            icon:@"bubble.left.and.bubble.right.fill"
                                           color:[UIColor ppQuickActionServices] ?: [UIColor systemGreenColor]
                                      valueLabel:_kpiChatLabel
                                             tag:PPAdminNotificationLensChat];

    [metricsGrid addArrangedSubview:tileTotal];
    [metricsGrid addArrangedSubview:tileUnread];
    [metricsGrid addArrangedSubview:tileOrders];
    [metricsGrid addArrangedSubview:tileChat];

    // 2. Omni-Search Field
    UIView *searchContainer = [[UIView alloc] init];
    searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    searchContainer.backgroundColor = [UIColor ppSurfaceElevated];
    searchContainer.layer.borderWidth = 1.0;
    searchContainer.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(searchContainer, PPCornerMedium);
    PPApplyCardShadow(searchContainer);
    [header addSubview:searchContainer];

    UIImageView *searchIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    searchIcon.translatesAutoresizingMaskIntoConstraints = NO;
    searchIcon.tintColor = [UIColor ppTextTertiary];
    searchIcon.contentMode = UIViewContentModeScaleAspectFit;
    [searchContainer addSubview:searchIcon];

    _searchField = [[UITextField alloc] init];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.placeholder = [Language isRTL] ? @"ابحث في التنبيهات، رقم الطلب، أو المحادثات..." : @"Search alerts, order #, or chat...";
    _searchField.font = [Styling fontMedium:14.5];
    _searchField.textColor = [UIColor ppTextPrimary];
    _searchField.textAlignment = Language.alignmentForCurrentLanguage;
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.clearButtonMode = UITextFieldViewModeNever;
    _searchField.delegate = self;
    [_searchField addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
    [searchContainer addSubview:_searchField];

    _searchClearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _searchClearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [_searchClearBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    _searchClearBtn.tintColor = [UIColor ppTextTertiary];
    _searchClearBtn.hidden = YES;
    [_searchClearBtn addTarget:self action:@selector(clearSearchTapped) forControlEvents:UIControlEventTouchUpInside];
    [searchContainer addSubview:_searchClearBtn];

    _searchCountLabel = [[UILabel alloc] init];
    _searchCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _searchCountLabel.font = [Styling fontBold:11.0];
    _searchCountLabel.textColor = [UIColor ppPrimary];
    _searchCountLabel.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    _searchCountLabel.textAlignment = NSTextAlignmentCenter;
    PPApplyContinuousCorners(_searchCountLabel, PPCornerPill);
    _searchCountLabel.hidden = YES;
    [searchContainer addSubview:_searchCountLabel];

    // 3. Triage Lens Rail
    _lensScrollView = [[UIScrollView alloc] init];
    _lensScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _lensScrollView.showsHorizontalScrollIndicator = NO;
    _lensScrollView.alwaysBounceHorizontal = YES;
    [header addSubview:_lensScrollView];

    _lensStackView = [[UIStackView alloc] init];
    _lensStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _lensStackView.axis = UILayoutConstraintAxisHorizontal;
    _lensStackView.spacing = 8;
    _lensStackView.alignment = UIStackViewAlignmentCenter;
    [_lensScrollView addSubview:_lensStackView];

    _lensButtons = [NSMutableArray array];
    NSArray *lensConfigs = @[
        @{@"title": [Language isRTL] ? @"الكل" : @"All", @"lens": @(PPAdminNotificationLensInbox)},
        @{@"title": [Language isRTL] ? @"غير مقروء" : @"Unread", @"lens": @(PPAdminNotificationLensUnread)},
        @{@"title": [Language isRTL] ? @"🛍️ الطلبات" : @"🛍️ Orders", @"lens": @(PPAdminNotificationLensOrders)},
        @{@"title": [Language isRTL] ? @"🚚 التوصيل" : @"🚚 Delivery", @"lens": @(PPAdminNotificationLensDelivery)},
        @{@"title": [Language isRTL] ? @"💬 المحادثات" : @"💬 Support", @"lens": @(PPAdminNotificationLensChat)},
        @{@"title": [Language isRTL] ? @"⚠️ تنبيهات" : @"⚠️ Alerts", @"lens": @(PPAdminNotificationLensAlerts)}
    ];

    for (NSDictionary *cfg in lensConfigs) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        btn.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
        btn.titleLabel.font = [Styling fontBold:13.0];
        [btn setTitle:cfg[@"title"] forState:UIControlStateNormal];
        PPApplyContinuousCorners(btn, PPCornerPill);
        btn.tag = [cfg[@"lens"] integerValue];
        [btn addTarget:self action:@selector(lensTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_lensStackView addArrangedSubview:btn];
        [_lensButtons addObject:btn];
    }
    [self updateLensButtonsSelection];

    [NSLayoutConstraint activateConstraints:@[
        // Metrics Card
        [metricsCard.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],
        [metricsCard.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [metricsCard.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [metricsCard.heightAnchor constraintEqualToConstant:86],

        [metricsGrid.topAnchor constraintEqualToAnchor:metricsCard.topAnchor constant:10],
        [metricsGrid.leadingAnchor constraintEqualToAnchor:metricsCard.leadingAnchor constant:10],
        [metricsGrid.trailingAnchor constraintEqualToAnchor:metricsCard.trailingAnchor constant:-10],
        [metricsGrid.bottomAnchor constraintEqualToAnchor:metricsCard.bottomAnchor constant:-10],

        // Search Container
        [searchContainer.topAnchor constraintEqualToAnchor:metricsCard.bottomAnchor constant:12],
        [searchContainer.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [searchContainer.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [searchContainer.heightAnchor constraintEqualToConstant:50],

        [searchIcon.leadingAnchor constraintEqualToAnchor:searchContainer.leadingAnchor constant:14],
        [searchIcon.centerYAnchor constraintEqualToAnchor:searchContainer.centerYAnchor],
        [searchIcon.widthAnchor constraintEqualToConstant:20],
        [searchIcon.heightAnchor constraintEqualToConstant:20],

        [_searchField.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:10],
        [_searchField.trailingAnchor constraintEqualToAnchor:_searchClearBtn.leadingAnchor constant:-8],
        [_searchField.centerYAnchor constraintEqualToAnchor:searchContainer.centerYAnchor],

        [_searchClearBtn.trailingAnchor constraintEqualToAnchor:_searchCountLabel.leadingAnchor constant:-6],
        [_searchClearBtn.centerYAnchor constraintEqualToAnchor:searchContainer.centerYAnchor],
        [_searchClearBtn.widthAnchor constraintEqualToConstant:24],
        [_searchClearBtn.heightAnchor constraintEqualToConstant:24],

        [_searchCountLabel.trailingAnchor constraintEqualToAnchor:searchContainer.trailingAnchor constant:-12],
        [_searchCountLabel.centerYAnchor constraintEqualToAnchor:searchContainer.centerYAnchor],
        [_searchCountLabel.heightAnchor constraintEqualToConstant:24],

        // Lens Scroll Rail
        [_lensScrollView.topAnchor constraintEqualToAnchor:searchContainer.bottomAnchor constant:12],
        [_lensScrollView.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16],
        [_lensScrollView.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16],
        [_lensScrollView.heightAnchor constraintEqualToConstant:40],

        [_lensStackView.topAnchor constraintEqualToAnchor:_lensScrollView.topAnchor],
        [_lensStackView.leadingAnchor constraintEqualToAnchor:_lensScrollView.leadingAnchor],
        [_lensStackView.trailingAnchor constraintEqualToAnchor:_lensScrollView.trailingAnchor],
        [_lensStackView.bottomAnchor constraintEqualToAnchor:_lensScrollView.bottomAnchor],
        [_lensStackView.heightAnchor constraintEqualToAnchor:_lensScrollView.heightAnchor]
    ]];

    _cockpitHeaderView = header;
    _tableView.tableHeaderView = _cockpitHeaderView;
}

- (UILabel *)makeKPILabelWithColor:(UIColor *)color {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [Styling fontBold:18.0];
    lbl.textColor = color;
    lbl.text = @"0";
    lbl.textAlignment = NSTextAlignmentCenter;
    return lbl;
}

- (UIView *)makeKPITileWithTitle:(NSString *)title
                            icon:(NSString *)iconName
                           color:(UIColor *)color
                      valueLabel:(UILabel *)valLabel
                             tag:(NSInteger)tag {
    UIView *tile = [[UIView alloc] init];
    tile.backgroundColor = [color colorWithAlphaComponent:0.06];
    PPApplyContinuousCorners(tile, PPCornerMedium);
    tile.userInteractionEnabled = YES;
    tile.tag = tag;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(kpiTileTapped:)];
    [tile addGestureRecognizer:tap];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = color;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [tile addSubview:icon];

    UILabel *titleL = [[UILabel alloc] init];
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    titleL.text = title;
    titleL.font = [Styling fontMedium:11.0];
    titleL.textColor = [UIColor ppTextSecondary];
    titleL.textAlignment = NSTextAlignmentCenter;
    [tile addSubview:titleL];

    [tile addSubview:valLabel];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:tile.topAnchor constant:8],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],

        [valLabel.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:2],
        [valLabel.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],

        [titleL.topAnchor constraintEqualToAnchor:valLabel.bottomAnchor constant:2],
        [titleL.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [titleL.bottomAnchor constraintLessThanOrEqualToAnchor:tile.bottomAnchor constant:-6]
    ]];
    return tile;
}

- (void)kpiTileTapped:(UITapGestureRecognizer *)gesture {
    [PPFunc pp_playTapEffect];
    self.activeLens = (PPAdminNotificationLens)gesture.view.tag;
    [self updateLensButtonsSelection];
    [self applyFilterAndRecomputeSections];
    [self.tableView reloadData];
}

- (void)updateLensButtonsSelection {
    for (UIButton *btn in self.lensButtons) {
        BOOL isSelected = (btn.tag == self.activeLens);
        if (isSelected) {
            btn.backgroundColor = [UIColor ppPrimary];
            [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            btn.layer.borderWidth = 0.0;
            PPApplyButtonShadow(btn);
        } else {
            btn.backgroundColor = [UIColor ppSurfaceElevated];
            [btn setTitleColor:[UIColor ppTextSecondary] forState:UIControlStateNormal];
            btn.layer.borderWidth = 1.0;
            btn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
            btn.layer.shadowOpacity = 0.0;
        }
    }
}

- (void)lensTapped:(UIButton *)sender {
    [PPFunc pp_playTapEffect];
    self.activeLens = (PPAdminNotificationLens)sender.tag;
    [self updateLensButtonsSelection];
    [self applyFilterAndRecomputeSections];
    [self.tableView reloadData];
}

- (void)setupEmptyStateView {
    _emptyStateView = [[UIView alloc] init];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    _emptyStateView.userInteractionEnabled = NO;
    [self.view addSubview:_emptyStateView];

    _emptyImageView = [[UIImageView alloc] init];
    _emptyImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyImageView.contentMode = UIViewContentModeScaleAspectFit;
    _emptyImageView.tintColor = [UIColor ppTextTertiary];
    [_emptyStateView addSubview:_emptyImageView];

    _emptyTitleLabel = [[UILabel alloc] init];
    _emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyTitleLabel.font = [Styling fontBold:17.0];
    _emptyTitleLabel.textColor = [UIColor ppTextPrimary];
    _emptyTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:_emptyTitleLabel];

    _emptySubtitleLabel = [[UILabel alloc] init];
    _emptySubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptySubtitleLabel.font = [Styling fontRegular:13.5];
    _emptySubtitleLabel.textColor = [UIColor ppTextSecondary];
    _emptySubtitleLabel.textAlignment = NSTextAlignmentCenter;
    _emptySubtitleLabel.numberOfLines = 2;
    [_emptyStateView addSubview:_emptySubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:60],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],

        [_emptyImageView.topAnchor constraintEqualToAnchor:_emptyStateView.topAnchor],
        [_emptyImageView.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [_emptyImageView.widthAnchor constraintEqualToConstant:64],
        [_emptyImageView.heightAnchor constraintEqualToConstant:64],

        [_emptyTitleLabel.topAnchor constraintEqualToAnchor:_emptyImageView.bottomAnchor constant:14],
        [_emptyTitleLabel.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [_emptyTitleLabel.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

        [_emptySubtitleLabel.topAnchor constraintEqualToAnchor:_emptyTitleLabel.bottomAnchor constant:6],
        [_emptySubtitleLabel.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [_emptySubtitleLabel.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],
        [_emptySubtitleLabel.bottomAnchor constraintEqualToAnchor:_emptyStateView.bottomAnchor]
    ]];
}

#pragma mark - Search Handling

- (void)searchChanged {
    self.searchQuery = [self.searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.searchClearBtn.hidden = (self.searchQuery.length == 0);
    [self applyFilterAndRecomputeSections];
    [self.tableView reloadData];
}

- (void)clearSearchTapped {
    [PPFunc pp_playTapEffect];
    self.searchField.text = @"";
    [self.searchField resignFirstResponder];
    [self searchChanged];
}

#pragma mark - Data Observation & Processing

- (void)onRefreshTriggered {
    [self startObservingInbox];
}

- (void)startObservingInbox {
    if (self.uid.length == 0) {
        [self.refreshControl endRefreshing];
        return;
    }

    [self.inboxListener remove];
    __weak typeof(self) weakSelf = self;
    
    self.inboxListener = [[NotificationManager shared] observeInboxForUser:self.uid stateHandler:^(NSArray<NotificationModel *> * _Nonnull items, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            [strongSelf.refreshControl endRefreshing];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
                return;
            }
            
            strongSelf.allNotifications = items ?: @[];
            [strongSelf updateCockpitKPIs];
            [strongSelf applyFilterAndRecomputeSections];
            [strongSelf.tableView reloadData];
        });
    }];
}

- (void)updateCockpitKPIs {
    NSInteger total = self.allNotifications.count;
    NSInteger unread = 0;
    NSInteger orders = 0;
    NSInteger chat = 0;

    for (NotificationModel *m in self.allNotifications) {
        if (!m.isRead) unread++;
        
        NSDictionary *meta = [m.meta isKindOfClass:NSDictionary.class] ? m.meta : @{};
        NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];
        if (m.type == PPNotificationTypeOrder || orderID.length > 0) {
            orders++;
        }
        
        NSString *type = [meta[@"type"] lowercaseString] ?: @"";
        NSString *title = [m.title lowercaseString] ?: @"";
        if ([type containsString:@"chat"] || [type containsString:@"support"] || [title containsString:@"support"] || meta[@"threadId"] || meta[@"conversationId"]) {
            chat++;
        }
    }

    self.kpiTotalLabel.text = [NSString stringWithFormat:@"%ld", (long)total];
    self.kpiUnreadLabel.text = [NSString stringWithFormat:@"%ld", (long)unread];
    self.kpiOrdersLabel.text = [NSString stringWithFormat:@"%ld", (long)orders];
    self.kpiChatLabel.text = [NSString stringWithFormat:@"%ld", (long)chat];
}

- (void)applyFilterAndRecomputeSections {
    NSMutableArray<NotificationModel *> *filtered = [NSMutableArray array];

    for (NotificationModel *m in self.allNotifications) {
        // 1. Lens filter
        BOOL passesLens = YES;
        NSDictionary *meta = [m.meta isKindOfClass:NSDictionary.class] ? m.meta : @{};
        NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];
        NSString *type = [meta[@"type"] lowercaseString] ?: @"";
        NSString *title = [m.title lowercaseString] ?: @"";

        switch (self.activeLens) {
            case PPAdminNotificationLensUnread:
                passesLens = !m.isRead;
                break;
            case PPAdminNotificationLensOrders:
                passesLens = (m.type == PPNotificationTypeOrder || orderID.length > 0);
                break;
            case PPAdminNotificationLensDelivery:
                passesLens = ([type containsString:@"delivery"] || [title containsString:@"delivery"] || [title containsString:@"توصيل"] || meta[@"requestId"]);
                break;
            case PPAdminNotificationLensChat:
                passesLens = ([type containsString:@"chat"] || [type containsString:@"support"] || [title containsString:@"support"] || meta[@"threadId"] || meta[@"conversationId"]);
                break;
            case PPAdminNotificationLensAlerts:
                passesLens = (m.type == PPNotificationTypeWarning || [type containsString:@"warn"] || [title containsString:@"warning"]);
                break;
            case PPAdminNotificationLensInbox:
            default:
                passesLens = YES;
                break;
        }

        if (!passesLens) continue;

        // 2. Search query filter
        if (self.searchQuery.length > 0) {
            NSString *body = m.body ?: @"";
            BOOL matchesTitle = ([m.title rangeOfString:self.searchQuery options:NSCaseInsensitiveSearch].location != NSNotFound);
            BOOL matchesBody = ([body rangeOfString:self.searchQuery options:NSCaseInsensitiveSearch].location != NSNotFound);
            BOOL matchesOrder = (orderID.length > 0 && [orderID rangeOfString:self.searchQuery options:NSCaseInsensitiveSearch].location != NSNotFound);
            if (!matchesTitle && !matchesBody && !matchesOrder) {
                continue;
            }
        }

        [filtered addObject:m];
    }

    self.filteredNotifications = filtered.copy;

    // Update search count badge
    if (self.searchQuery.length > 0) {
        self.searchCountLabel.hidden = NO;
        self.searchCountLabel.text = [NSString stringWithFormat:@" %ld ", (long)filtered.count];
    } else {
        self.searchCountLabel.hidden = YES;
    }

    // Chronological Day Grouping
    [self groupNotificationsIntoDaySections:filtered];

    // Update empty state
    BOOL isEmpty = (self.filteredNotifications.count == 0);
    self.emptyStateView.hidden = !isEmpty;
    if (isEmpty) {
        [self updateEmptyStateContent];
    }
}

- (void)groupNotificationsIntoDaySections:(NSArray<NotificationModel *> *)items {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];

    NSMutableArray<NotificationModel *> *todayItems = [NSMutableArray array];
    NSMutableArray<NotificationModel *> *yesterdayItems = [NSMutableArray array];
    NSMutableArray<NotificationModel *> *thisWeekItems = [NSMutableArray array];
    NSMutableArray<NotificationModel *> *olderItems = [NSMutableArray array];

    for (NotificationModel *m in items) {
        NSDate *date = m.createdAt ?: now;
        if ([cal isDateInToday:date]) {
            [todayItems addObject:m];
        } else if ([cal isDateInYesterday:date]) {
            [yesterdayItems addObject:m];
        } else {
            NSDateComponents *comp = [cal components:NSCalendarUnitDay fromDate:date toDate:now options:0];
            if (comp.day < 7) {
                [thisWeekItems addObject:m];
            } else {
                [olderItems addObject:m];
            }
        }
    }

    NSMutableArray<PPAdminDaySection *> *sections = [NSMutableArray array];
    if (todayItems.count > 0) {
        PPAdminDaySection *s = [[PPAdminDaySection alloc] init];
        s.title = [Language isRTL] ? @"اليوم" : @"Today";
        s.items = todayItems;
        [sections addObject:s];
    }
    if (yesterdayItems.count > 0) {
        PPAdminDaySection *s = [[PPAdminDaySection alloc] init];
        s.title = [Language isRTL] ? @"أمس" : @"Yesterday";
        s.items = yesterdayItems;
        [sections addObject:s];
    }
    if (thisWeekItems.count > 0) {
        PPAdminDaySection *s = [[PPAdminDaySection alloc] init];
        s.title = [Language isRTL] ? @"هذا الأسبوع" : @"This Week";
        s.items = thisWeekItems;
        [sections addObject:s];
    }
    if (olderItems.count > 0) {
        PPAdminDaySection *s = [[PPAdminDaySection alloc] init];
        s.title = [Language isRTL] ? @"سابقاً" : @"Older";
        s.items = olderItems;
        [sections addObject:s];
    }

    self.daySections = sections.copy;
}

- (void)updateEmptyStateContent {
    if (self.searchQuery.length > 0) {
        self.emptyImageView.image = [UIImage systemImageNamed:@"magnifyingglass.circle.fill"];
        self.emptyTitleLabel.text = [Language isRTL] ? @"لا توجد نتائج مطابقة" : @"No matching alerts";
        self.emptySubtitleLabel.text = [Language isRTL] ? @"يرجى التأكد من كتابة نص البحث بشكل صحيح" : @"Try searching with different keywords";
    } else {
        self.emptyImageView.image = [UIImage systemImageNamed:@"bell.slash.fill"];
        self.emptyTitleLabel.text = [Language isRTL] ? @"صندوق الوارد نظيف تماماً" : @"Inbox is clear";
        self.emptySubtitleLabel.text = [Language isRTL] ? @"لا توجد أي تنبيهات أو أحداث جديدة ضمن هذا القسم حالياً" : @"No new alerts or events under this category right now";
    }
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.daySections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.daySections[section].items.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    PPAdminDaySection *sec = self.daySections[section];
    
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 36)];
    h.backgroundColor = UIColor.clearColor;
    h.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *titleL = [[UILabel alloc] init];
    titleL.translatesAutoresizingMaskIntoConstraints = NO;
    titleL.font = [Styling fontBold:14.0];
    titleL.textColor = [UIColor ppTextSecondary];
    titleL.text = sec.title;
    titleL.textAlignment = Language.alignmentForCurrentLanguage;
    [h addSubview:titleL];

    UILabel *badge = [[UILabel alloc] init];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.font = [Styling fontBold:11.0];
    badge.textColor = [UIColor ppTextSecondary];
    badge.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.7];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.text = [NSString stringWithFormat:@" %ld ", (long)sec.items.count];
    PPApplyContinuousCorners(badge, PPCornerPill);
    [h addSubview:badge];

    [NSLayoutConstraint activateConstraints:@[
        [titleL.leadingAnchor constraintEqualToAnchor:h.leadingAnchor constant:20],
        [titleL.centerYAnchor constraintEqualToAnchor:h.centerYAnchor],

        [badge.leadingAnchor constraintEqualToAnchor:titleL.trailingAnchor constant:8],
        [badge.centerYAnchor constraintEqualToAnchor:h.centerYAnchor],
        [badge.heightAnchor constraintEqualToConstant:20]
    ]];

    return h;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 36.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 4.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return [UIView new];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NotificationCell *cell = [tableView dequeueReusableCellWithIdentifier:[NotificationCell reuseId] forIndexPath:indexPath];
    NotificationModel *m = self.daySections[indexPath.section].items[indexPath.row];
    [cell configure:m];
    
    __weak typeof(self) weakSelf = self;
    cell.onDirectActionTapped = ^(NotificationModel * _Nonnull model) {
        [weakSelf handleDirectActionForModel:model];
    };
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NotificationModel *m = self.daySections[indexPath.section].items[indexPath.row];
    [self handleDirectActionForModel:m];
}

- (void)handleDirectActionForModel:(NotificationModel *)m {
    [PPFunc pp_playTapEffect];
    
    if (!m.isRead) {
        m.isRead = YES;
        [[NotificationManager shared] markRead:m forUser:self.uid completion:nil];
        [self updateCockpitKPIs];
        [self.tableView reloadData];
    }

    NSDictionary *meta = [m.meta isKindOfClass:NSDictionary.class] ? m.meta : @{};
    NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];

    if (orderID.length > 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:PPAdminRouteToPaymentOrderNotification
                                                            object:nil
                                                          userInfo:@{ PPAdminRouteToPaymentOrderIDUserInfoKey: orderID }];
        return;
    }

    NotificationDetailViewController *detailVC = [[NotificationDetailViewController alloc] initWithModel:m userID:self.uid];
    [self.navigationController pushViewController:detailVC animated:YES];
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NotificationModel *m = self.daySections[indexPath.section].items[indexPath.row];
    
    NSString *actionTitle = m.isRead
        ? ([Language isRTL] ? @"كغير مقروء" : @"Unread")
        : ([Language isRTL] ? @"كمقروء" : @"Read");
    NSString *iconName = m.isRead ? @"envelope.badge.fill" : @"envelope.open.fill";

    UIContextualAction *action = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                         title:actionTitle
                                                                       handler:^(UIContextualAction * _Nonnull a, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [PPFunc pp_playTapEffect];
        m.isRead = !m.isRead;
        [[NotificationManager shared] markRead:m forUser:self.uid completion:nil];
        [self updateCockpitKPIs];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        completionHandler(YES);
    }];
    action.backgroundColor = [UIColor ppPrimary];
    action.image = [UIImage systemImageNamed:iconName];

    return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NotificationModel *m = self.daySections[indexPath.section].items[indexPath.row];

    UIContextualAction *detailAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                               title:[Language isRTL] ? @"تفاصيل" : @"Details"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [PPFunc pp_playTapEffect];
        NotificationDetailViewController *detailVC = [[NotificationDetailViewController alloc] initWithModel:m userID:self.uid];
        [self.navigationController pushViewController:detailVC animated:YES];
        completionHandler(YES);
    }];
    detailAction.backgroundColor = [UIColor ppTextSecondary];
    detailAction.image = [UIImage systemImageNamed:@"ellipsis.circle.fill"];

    return [UISwipeActionsConfiguration configurationWithActions:@[detailAction]];
}

@end
