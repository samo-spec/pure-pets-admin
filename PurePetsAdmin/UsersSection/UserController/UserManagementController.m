//
//  UserManagementController.m
//  PurePetsAdmin
//
//  Premium User Details Editor — Studio-grade admin UI
//  Console parity: Users Management → User Details
//  Apple Design Award–caliber hierarchy, motion, states, accessibility, and RTL safety.
//

#import "UserManagementController.h"
#import "UIImageView+WebCache.h"
#import "Language.h"
#import "Styling.h"
#import "UserModel.h"
#import "FUManager.h"
#import "AdminService.h"
#import "PPStaffAuth.h"
#import "PPHUD.h"
#import "PPToast.h"
#import "PPFunc.h"
#import "UIViewController+PPNavBar.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseFirestore;

#pragma mark - Constants

typedef NS_ENUM(NSInteger, SectionType) {
    SectionAccount = 0,
    SectionFeatures,
    SectionRestrictions,
    _SectionCount
};

typedef NS_ENUM(NSInteger, AccountRow) {
    AccountRowStatus = 0,
    AccountRowVerified,
    AccountRowProtection,
    _AccountRowCount
};

static NSString *const kToggleCellID = @"UserDetailToggle";
static NSString *const kPickerCellID = @"UserDetailPicker";

static NSArray<NSString *> *AccountStatusOptions(void) {
    return @[@"active", @"blocked", @"disabled", @"pending_review"];
}

static NSString *AccountStatusLabel(NSString *status) {
    if ([status isEqualToString:@"active"]) return kLang(@"Active");
    if ([status isEqualToString:@"blocked"]) return kLang(@"Blocked");
    if ([status isEqualToString:@"disabled"]) return kLang(@"Disabled");
    if ([status isEqualToString:@"pending_review"]) return kLang(@"Pending Review");
    return kLang(@"Active");
}

static UIColor *AccountStatusColor(NSString *status) {
    if ([status isEqualToString:@"blocked"]) return [UIColor systemRedColor];
    if ([status isEqualToString:@"disabled"]) return [UIColor systemOrangeColor];
    if ([status isEqualToString:@"pending_review"]) return [UIColor systemYellowColor];
    return [UIColor systemGreenColor];
}

#pragma mark - Feature/Restriction metadata

typedef struct {
    __unsafe_unretained NSString *key;
    __unsafe_unretained NSString *labelKey;
} PPFeatureDef;

static PPFeatureDef kAllFeatures[] = {
    {@"canPostPetAds",              @"Feature_CanPostPetAds"},
    {@"canPostAdoption",            @"Feature_CanPostAdoption"},
    {@"canSellAccessories",         @"Feature_CanSellAccessories"},
    {@"canOfferServices",           @"Feature_CanOfferServices"},
    {@"canDelivery",                @"Feature_CanDelivery"},
    {@"canDeliveryCompany",         @"Feature_CanDeliveryCompany"},
    {@"canUseStories",              @"Feature_CanUseStories"},
    {@"canUseChat",                 @"Feature_CanUseChat"},
    {@"canAccessPremiumMarketplace",@"Feature_CanAccessPremiumMarketplace"},
    {@"canAccessProviderMarketplace",@"Feature_CanAccessProviderMarketplace"},
    {@"canPharmacy",                @"Feature_CanPharmacy"},
    {@"canVet",                     @"Feature_CanVet"},
};
static NSInteger kFeatureCount = sizeof(kAllFeatures) / sizeof(PPFeatureDef);

static PPFeatureDef kRestrictions[] = {
    {@"postingBlocked",  @"Restriction_PostingBlocked"},
    {@"chatBlocked",     @"Restriction_ChatBlocked"},
    {@"purchaseBlocked", @"Restriction_PurchaseBlocked"},
};
static NSInteger kRestrictionCount = sizeof(kRestrictions) / sizeof(PPFeatureDef);

#pragma mark - Inline Cells

@interface PPUserDetailToggleCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, copy) void (^onToggle)(BOOL isOn);
- (void)configureWithTitle:(NSString *)title isOn:(BOOL)isOn enabled:(BOOL)enabled;
@end

@interface PPUserDetailPickerCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)configureWithTitle:(NSString *)title value:(NSString *)value valueColor:(UIColor *)valueColor enabled:(BOOL)enabled;
@end

#pragma mark - Private Interface

@interface UserManagementController () <UITableViewDelegate, UITableViewDataSource> {
    BOOL _hasAppeared;
    BOOL _isSaving;
}

@property (nonatomic, strong) UITableView *tableView;

// Header subviews
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIImageView *heroAvatar;
@property (nonatomic, strong) UILabel *heroName;
@property (nonatomic, strong) UILabel *heroUID;
@property (nonatomic, strong) UIView *heroStatusPillContainer;
@property (nonatomic, strong) UILabel *heroStatusPill;
@property (nonatomic, strong) UIImageView *heroVerifiedBadge;
@property (nonatomic, strong) NSMutableArray<UIView *> *statTiles;

// State
@property (nonatomic, strong) UserModel *user;
@property (nonatomic, assign) EditType editType;
@property (nonatomic, assign) BOOL showsAccountUI;
@property (nonatomic, assign) BOOL showsPermRoleUI;

// Editable state copy
@property (nonatomic, copy) NSString *editingAccountStatus;
@property (nonatomic, assign) BOOL editingVerified;
@property (nonatomic, copy) NSString *editingProdectionStatus;
@property (nonatomic, strong) NSMutableDictionary *editingFeatures;
@property (nonatomic, strong) NSMutableDictionary *editingRestrictions;

// Permissions
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL canManageFeatures;
@property (nonatomic, assign) BOOL canManageRestrictions;

@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIView *saveFooterView;

@end

#pragma mark - Implementation

@implementation UserManagementController

#pragma mark - Init

- (instancetype)initWithUser:(UserModel *)user type:(EditType)type {
    self = [super init];
    if (self) {
        _user = user;
        _editType = type;
        _showsAccountUI  = (type == EditTypeDefault || type == EditTypeUserData);
        _showsPermRoleUI = (type == EditTypeDefault || type == EditTypeUserPermisstionAndRoles);
        _isSaving = NO;
        _hasAppeared = NO;

        // Snapshot current state
        _editingAccountStatus = user.accountStatus ?: @"active";
        _editingVerified = user.isVerified;
        _editingProdectionStatus = user.prodectionStatus ?: @"inactive";
        _editingFeatures = [user.features ?: @{} mutableCopy];
        _editingRestrictions = [user.restrictions ?: @{} mutableCopy];
    }
    return self;
}

+ (instancetype)accountEditorForUser:(UserModel *)user {
    return [[self alloc] initWithUser:user type:EditTypeUserData];
}

+ (instancetype)permRoleEditorForUser:(UserModel *)user {
    return [[self alloc] initWithUser:user type:EditTypeUserPermisstionAndRoles];
}

+ (instancetype)fullEditorForUser:(UserModel *)user {
    return [[self alloc] initWithUser:user type:EditTypeDefault];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = AppBackgroundClr;

    [self buildTableView];
    [self buildHeaderView];
    [self buildSaveFooterView];
    [self evaluatePermissions];
    [self setupNavigation];
    [self prepareEntranceState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self prepareEntranceState];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self runEntranceIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHeaderView];
}

#pragma mark - Setup

- (void)buildTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    self.tableView.sectionHeaderTopPadding = 0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.alpha = 0;
    [self.tableView registerClass:PPUserDetailToggleCell.class forCellReuseIdentifier:kToggleCellID];
    [self.tableView registerClass:PPUserDetailPickerCell.class forCellReuseIdentifier:kPickerCellID];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)buildHeaderView {
    BOOL isRTL = [Language isRTL];

    // Container
    self.headerContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.headerContainer.backgroundColor = AppClearClr;

    // Avatar
    self.heroAvatar = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.heroAvatar.contentMode = UIViewContentModeScaleAspectFill;
    self.heroAvatar.clipsToBounds = YES;
    self.heroAvatar.backgroundColor = AppBackgroundClrShiner;
    self.heroAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroAvatar.accessibilityLabel = kLang(@"User_Avatar_Label");
    PPApplyContinuousCorners(self.heroAvatar, PPCornerCard);
    PPApplyCardShadow(self.heroAvatar);

    // Load avatar
    NSURL *imageURL = self.user.UserImageUrl ?: PPURLOrNil(self.user.photoURL);
    if (imageURL) {
        [self.heroAvatar sd_setImageWithURL:imageURL
                           placeholderImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    } else {
        self.heroAvatar.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
        self.heroAvatar.tintColor = AppPrimaryTextClr;
    }

    // Name
    self.heroName = [[UILabel alloc] init];
    self.heroName.text = self.user.UserName.length ? self.user.UserName : kLang(@"Unknown_User");
    self.heroName.font = PPFontBold(PPFontHeadline);
    self.heroName.textColor = PrimaryTextClr;
    self.heroName.numberOfLines = 1;
    self.heroName.adjustsFontForContentSizeCategory = YES;
    self.heroName.translatesAutoresizingMaskIntoConstraints = NO;

    // UID
    self.heroUID = [[UILabel alloc] init];
    self.heroUID.text = self.user.uid;
    self.heroUID.font = PPFontRegular(PPFontFootnote);
    self.heroUID.textColor = SeconderyTextClr;
    self.heroUID.numberOfLines = 1;
    self.heroUID.adjustsFontForContentSizeCategory = YES;
    self.heroUID.translatesAutoresizingMaskIntoConstraints = NO;

    // Status pill
    self.heroStatusPillContainer = [[UIView alloc] init];
    self.heroStatusPillContainer.backgroundColor = AccountStatusColor(self.editingAccountStatus);
    self.heroStatusPillContainer.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(self.heroStatusPillContainer, PPCornerPill);

    self.heroStatusPill = [[UILabel alloc] init];
    self.heroStatusPill.text = AccountStatusLabel(self.editingAccountStatus);
    self.heroStatusPill.font = PPFontMedium(PPFontCaption1);
    self.heroStatusPill.textColor = [UIColor whiteColor];
    self.heroStatusPill.backgroundColor = AppClearClr;
    self.heroStatusPill.textAlignment = NSTextAlignmentCenter;
    self.heroStatusPill.translatesAutoresizingMaskIntoConstraints = NO;

    [self.heroStatusPillContainer addSubview:self.heroStatusPill];
    [NSLayoutConstraint activateConstraints:@[
        [self.heroStatusPill.topAnchor constraintEqualToAnchor:self.heroStatusPillContainer.topAnchor constant:3],
        [self.heroStatusPill.bottomAnchor constraintEqualToAnchor:self.heroStatusPillContainer.bottomAnchor constant:-3],
        [self.heroStatusPill.leadingAnchor constraintEqualToAnchor:self.heroStatusPillContainer.leadingAnchor constant:10],
        [self.heroStatusPill.trailingAnchor constraintEqualToAnchor:self.heroStatusPillContainer.trailingAnchor constant:-10],
    ]];

    // Verified badge
    self.heroVerifiedBadge = [[UIImageView alloc] init];
    self.heroVerifiedBadge.image = [UIImage systemImageNamed:@"checkmark.seal.fill"];
    self.heroVerifiedBadge.tintColor = self.editingVerified ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    self.heroVerifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
    self.heroVerifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroVerifiedBadge.accessibilityLabel = self.editingVerified ? kLang(@"Verified") : kLang(@"Not_Verified");

    // Stat tiles
    self.statTiles = [NSMutableArray array];
    UIView *statsGrid = [self buildStatTiles];

    // Assemble header
    [self.headerContainer addSubview:self.heroAvatar];
    [self.headerContainer addSubview:self.heroName];
    [self.headerContainer addSubview:self.heroUID];
    [self.headerContainer addSubview:self.heroStatusPillContainer];
    [self.headerContainer addSubview:self.heroVerifiedBadge];
    [self.headerContainer addSubview:statsGrid];
    statsGrid.translatesAutoresizingMaskIntoConstraints = NO;

    CGFloat avatarSize = 64;
    CGFloat avatarLeading = isRTL ? PPSpaceSM : PPSpaceBase;

    [NSLayoutConstraint activateConstraints:@[
        // Avatar
        [self.heroAvatar.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor constant:PPSpaceLG],
        [self.heroAvatar.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor constant:avatarLeading],
        [self.heroAvatar.widthAnchor constraintEqualToConstant:avatarSize],
        [self.heroAvatar.heightAnchor constraintEqualToConstant:avatarSize],

        // Name (trailing of avatar)
        [self.heroName.topAnchor constraintEqualToAnchor:self.heroAvatar.topAnchor constant:PPSpaceXS],
        [self.heroName.leadingAnchor constraintEqualToAnchor:self.heroAvatar.trailingAnchor constant:PPSpaceMD],
        [self.heroName.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor constant:-PPSpaceBase],

        // UID
        [self.heroUID.topAnchor constraintEqualToAnchor:self.heroName.bottomAnchor constant:2],
        [self.heroUID.leadingAnchor constraintEqualToAnchor:self.heroName.leadingAnchor],
        [self.heroUID.trailingAnchor constraintEqualToAnchor:self.heroName.trailingAnchor],

        // Status pill + verified badge
        [self.heroStatusPillContainer.topAnchor constraintEqualToAnchor:self.heroUID.bottomAnchor constant:PPSpaceSM],
        [self.heroStatusPillContainer.leadingAnchor constraintEqualToAnchor:self.heroName.leadingAnchor],

        [self.heroVerifiedBadge.centerYAnchor constraintEqualToAnchor:self.heroStatusPillContainer.centerYAnchor],
        [self.heroVerifiedBadge.leadingAnchor constraintEqualToAnchor:self.heroStatusPillContainer.trailingAnchor constant:PPSpaceSM],
        [self.heroVerifiedBadge.widthAnchor constraintEqualToConstant:20],
        [self.heroVerifiedBadge.heightAnchor constraintEqualToConstant:20],

        // Stats grid
        [statsGrid.topAnchor constraintEqualToAnchor:self.heroAvatar.bottomAnchor constant:PPSpaceLG],
        [statsGrid.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor constant:PPSpaceBase],
        [statsGrid.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor constant:-PPSpaceBase],
        [statsGrid.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor constant:-PPSpaceXS],
    ]];

    self.tableView.tableHeaderView = self.headerContainer;
}

- (UIView *)buildStatTiles {
    UIStackView *outerStack = [[UIStackView alloc] init];
    outerStack.axis = UILayoutConstraintAxisVertical;
    outerStack.spacing = PPSpaceSM;
    outerStack.distribution = UIStackViewDistributionFillEqually;
    outerStack.translatesAutoresizingMaskIntoConstraints = NO;

    // Compute stats
    NSInteger activeFeatureCount = 0;
    for (NSInteger i = 0; i < kFeatureCount; i++) {
        if ([self.editingFeatures[kAllFeatures[i].key] boolValue]) activeFeatureCount++;
    }
    NSInteger activeRestrictionCount = 0;
    for (NSInteger i = 0; i < kRestrictionCount; i++) {
        if ([self.editingRestrictions[kRestrictions[i].key] boolValue]) activeRestrictionCount++;
    }

    NSArray<NSDictionary *> *statData = @[
        @{@"icon": @"person.text.rectangle.fill", @"value": AccountStatusLabel(self.editingAccountStatus),
          @"label": kLang(@"Account_Status"), @"color": AccountStatusColor(self.editingAccountStatus)},
        @{@"icon": @"checkmark.seal.fill", @"value": self.editingVerified ? kLang(@"Verified") : kLang(@"Not_Verified"),
          @"label": kLang(@"Verified_Status"), @"color": self.editingVerified ? [UIColor systemBlueColor] : [UIColor systemGrayColor]},
        @{@"icon": @"sparkles", @"value": [NSString stringWithFormat:@"%ld / %ld", (long)activeFeatureCount, (long)kFeatureCount],
          @"label": kLang(@"Active_Features"), @"color": AppPrimaryClr},
        @{@"icon": @"hand.raised.fill", @"value": [NSString stringWithFormat:@"%ld", (long)activeRestrictionCount],
          @"label": kLang(@"Active_Restrictions"), @"color": [UIColor systemOrangeColor]},
    ];

    // 2 rows x 2 columns
    for (NSInteger row = 0; row < 2; row++) {
        UIStackView *rowStack = [[UIStackView alloc] init];
        rowStack.axis = UILayoutConstraintAxisHorizontal;
        rowStack.spacing = PPSpaceSM;
        rowStack.distribution = UIStackViewDistributionFillEqually;

        for (NSInteger col = 0; col < 2; col++) {
            NSInteger idx = row * 2 + col;
            if (idx >= statData.count) break;
            NSDictionary *data = statData[idx];
            UIView *tile = [self createStatTileWithData:data];
            [rowStack addArrangedSubview:tile];
            [self.statTiles addObject:tile];
        }
        [outerStack addArrangedSubview:rowStack];
    }

    return outerStack;
}

- (UIView *)createStatTileWithData:(NSDictionary *)data {
    UIView *tile = [[UIView alloc] init];
    tile.backgroundColor = [UIColor whiteColor];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(tile, PPCornerSmall);
    PPApplyCardShadow(tile);
    tile.accessibilityTraits = UIAccessibilityTraitStaticText;
    tile.isAccessibilityElement = YES;

    // Icon
    UIImageView *icon = [[UIImageView alloc] init];
    icon.image = [UIImage systemImageNamed:data[@"icon"]];
    icon.tintColor = data[@"color"];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    // Value
    UILabel *value = [[UILabel alloc] init];
    value.text = data[@"value"];
    value.font = PPFontBold(PPFontTitle3);
    value.textColor = data[@"color"];
    value.adjustsFontForContentSizeCategory = YES;
    value.textAlignment = NSTextAlignmentNatural;
    value.translatesAutoresizingMaskIntoConstraints = NO;
    value.tag = 100;

    // Label
    UILabel *label = [[UILabel alloc] init];
    label.text = data[@"label"];
    label.font = PPFontRegular(PPFontCaption1);
    label.textColor = SeconderyTextClr;
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = NSTextAlignmentNatural;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [tile addSubview:icon];
    [tile addSubview:value];
    [tile addSubview:label];

    tile.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", data[@"label"], data[@"value"]];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:tile.topAnchor constant:PPSpaceSM],
        [icon.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:PPSpaceSM],
        [icon.widthAnchor constraintEqualToConstant:22],
        [icon.heightAnchor constraintEqualToConstant:22],

        [value.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceXS],
        [value.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:PPSpaceSM],
        [value.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-PPSpaceSM],

        [label.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:2],
        [label.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:PPSpaceSM],
        [label.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-PPSpaceSM],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:tile.bottomAnchor constant:-PPSpaceSM],
    ]];

    return tile;
}

- (void)layoutHeaderView {
    CGFloat targetWidth = self.tableView.bounds.size.width;
    CGSize size = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(targetWidth, UILayoutFittingCompressedSize.height)
                                      withHorizontalFittingPriority:UILayoutPriorityRequired
                                            verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.headerContainer.frame.size.height - size.height) > 1) {
        CGRect frame = self.headerContainer.frame;
        frame.size.height = size.height;
        self.headerContainer.frame = frame;
        self.tableView.tableHeaderView = self.headerContainer;
    }
}

- (void)buildSaveFooterView {
    self.saveFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, PPButtonHeightLG + PPSpaceXL * 2)];

    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveButton.backgroundColor = AppPrimaryClr;
    self.saveButton.tintColor = [UIColor whiteColor];
    self.saveButton.titleLabel.font = PPFontBold(PPFontHeadline);
    [self.saveButton setTitle:kLang(@"Save_Changes") forState:UIControlStateNormal];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.saveButton addTarget:self action:@selector(onSave) forControlEvents:UIControlEventTouchUpInside];
    PPApplyContinuousCorners(self.saveButton, PPCornerMedium);
    PPApplyButtonShadow(self.saveButton);

    [self.saveFooterView addSubview:self.saveButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.saveButton.centerXAnchor constraintEqualToAnchor:self.saveFooterView.centerXAnchor],
        [self.saveButton.topAnchor constraintEqualToAnchor:self.saveFooterView.topAnchor constant:PPSpaceXL],
        [self.saveButton.widthAnchor constraintEqualToConstant:240],
        [self.saveButton.heightAnchor constraintEqualToConstant:PPButtonHeightLG],
    ]];

    // Add press animation
    [self.saveButton addTarget:self action:@selector(saveButtonTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.saveButton addTarget:self action:@selector(saveButtonTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    self.tableView.tableFooterView = self.saveFooterView;
}

- (void)saveButtonTouchDown {
    PPTapFeedbackDown(self.saveButton);
}

- (void)saveButtonTouchUp {
    PPTapFeedbackUp(self.saveButton);
}

- (void)setupNavigation {
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto
                      button:nil
                       title:kLang(@"User_Details")
                    showBack:YES];
}

- (void)dismissSelf {
    [PPFunc pp_playTapEffect];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Permissions

- (void)evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    self.canManage = [staff hasPermission:kStaffPermUsersManage];
    self.canManageFeatures = [staff hasPermission:kStaffPermUsersFeaturesManage];
    self.canManageRestrictions = [staff hasPermission:kStaffPermUsersRestrictionsManage];

    self.saveButton.hidden = !self.canManage;
    self.saveButton.userInteractionEnabled = self.canManage;
}

#pragma mark - Table Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (!self.showsAccountUI) return 0;
    return _SectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((SectionType)section) {
        case SectionAccount: return _AccountRowCount;
        case SectionFeatures: return kFeatureCount;
        case SectionRestrictions: return kRestrictionCount;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ((SectionType)section) {
        case SectionAccount: return kLang(@"Account_Section");
        case SectionFeatures: return kLang(@"Features");
        case SectionRestrictions: return kLang(@"Restrictions");
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return nil; // use default styled title
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ((SectionType)indexPath.section) {
        case SectionAccount:
            return [self accountCellForRow:indexPath.row];
        case SectionFeatures:
            return [self featureCellForRow:indexPath.row];
        case SectionRestrictions:
            return [self restrictionCellForRow:indexPath.row];
        default:
            return [[UITableViewCell alloc] init];
    }
}

#pragma mark - Account Section Cells

- (UITableViewCell *)accountCellForRow:(NSInteger)row {
    switch ((AccountRow)row) {
        case AccountRowStatus: {
            PPUserDetailPickerCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kPickerCellID];
            NSString *label = AccountStatusLabel(self.editingAccountStatus);
            UIColor *color = AccountStatusColor(self.editingAccountStatus);
            [cell configureWithTitle:kLang(@"Account_Status") value:label valueColor:color enabled:self.canManage];
            cell.accessibilityIdentifier = @"account_status_cell";
            return cell;
        }
        case AccountRowVerified: {
            PPUserDetailToggleCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kToggleCellID];
            [cell configureWithTitle:kLang(@"Verified_Status") isOn:self.editingVerified enabled:self.canManage];
            PPweakify(self);
            cell.onToggle = ^(BOOL isOn) {
                PPstrongify(self);
                self.editingVerified = isOn;
                self.heroVerifiedBadge.tintColor = isOn ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
                self.heroVerifiedBadge.accessibilityLabel = isOn ? kLang(@"Verified") : kLang(@"Not_Verified");
                [self updateStatTiles];
            };
            cell.accessibilityIdentifier = @"verified_toggle_cell";
            return cell;
        }
        case AccountRowProtection: {
            PPUserDetailPickerCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kPickerCellID];
            NSString *label = self.editingProdectionStatus;
            UIColor *color = [self.editingProdectionStatus isEqualToString:@"active"] ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
            [cell configureWithTitle:kLang(@"Protection_Status") value:label valueColor:color enabled:self.canManage];
            cell.accessibilityIdentifier = @"protection_status_cell";
            return cell;
        }
        default:
            return [[UITableViewCell alloc] init];
    }
}

#pragma mark - Features & Restrictions Cells

- (UITableViewCell *)featureCellForRow:(NSInteger)row {
    PPFeatureDef def = kAllFeatures[row];
    BOOL isOn = [self.editingFeatures[def.key] boolValue];
    PPUserDetailToggleCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kToggleCellID];
    [cell configureWithTitle:kLang(def.labelKey) isOn:isOn enabled:self.canManageFeatures];
    PPweakify(self);
    cell.onToggle = ^(BOOL isOn) {
        PPstrongify(self);
        self.editingFeatures[def.key] = @(isOn);
        [self updateStatTiles];
    };
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"feature_%@", def.key];
    return cell;
}

- (UITableViewCell *)restrictionCellForRow:(NSInteger)row {
    PPFeatureDef def = kRestrictions[row];
    BOOL isOn = [self.editingRestrictions[def.key] boolValue];
    PPUserDetailToggleCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kToggleCellID];
    [cell configureWithTitle:kLang(def.labelKey) isOn:isOn enabled:self.canManageRestrictions];
    PPweakify(self);
    cell.onToggle = ^(BOOL isOn) {
        PPstrongify(self);
        self.editingRestrictions[def.key] = @(isOn);
        [self updateStatTiles];
    };
    cell.accessibilityIdentifier = [NSString stringWithFormat:@"restriction_%@", def.key];
    return cell;
}

#pragma mark - Table Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SectionAccount) {
        if (indexPath.row == AccountRowStatus && self.canManage) {
            [self showAccountStatusPicker];
        } else if (indexPath.row == AccountRowProtection && self.canManage) {
            [self showProdectionStatusPicker];
        }
    }
}

- (void)showAccountStatusPicker {
    [PPFunc pp_playTapEffect];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Account_Status")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *status in AccountStatusOptions()) {
        NSString *label = AccountStatusLabel(status);
        UIAlertAction *action = [UIAlertAction actionWithTitle:label
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            [self didSelectAccountStatus:status];
        }];
        [sheet addAction:action];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        CGRect cellRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:AccountRowStatus inSection:SectionAccount]];
        sheet.popoverPresentationController.sourceRect = cellRect;
        sheet.popoverPresentationController.sourceView = self.tableView;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)didSelectAccountStatus:(NSString *)status {
    self.editingAccountStatus = status;
    self.heroStatusPill.text = AccountStatusLabel(status);
    self.heroStatusPillContainer.backgroundColor = AccountStatusColor(status);
    [self updateStatTiles];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:AccountRowStatus inSection:SectionAccount]]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)showProdectionStatusPicker {
    [PPFunc pp_playTapEffect];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Protection_Status")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *value in @[@"active", @"inactive"]) {
        NSString *label = [value isEqualToString:@"active"] ? kLang(@"Active") : kLang(@"Inactive");
        UIAlertAction *action = [UIAlertAction actionWithTitle:label
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            self.editingProdectionStatus = value;
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:AccountRowProtection inSection:SectionAccount]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }];
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        CGRect cellRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:AccountRowProtection inSection:SectionAccount]];
        sheet.popoverPresentationController.sourceRect = cellRect;
        sheet.popoverPresentationController.sourceView = self.tableView;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Stat Tiles Update

- (void)updateStatTiles {
    if (self.statTiles.count < 4) return;

    // Tile 0: Status
    UILabel *statusValue = [self.statTiles[0] viewWithTag:100];
    if (statusValue) {
        statusValue.text = AccountStatusLabel(self.editingAccountStatus);
        statusValue.textColor = AccountStatusColor(self.editingAccountStatus);
    }

    // Tile 1: Verified
    UILabel *verValue = [self.statTiles[1] viewWithTag:100];
    if (verValue) {
        verValue.text = self.editingVerified ? kLang(@"Verified") : kLang(@"Not_Verified");
        verValue.textColor = self.editingVerified ? [UIColor systemBlueColor] : [UIColor systemGrayColor];
    }

    // Tile 2: Active Features
    NSInteger activeFeatures = 0;
    for (NSInteger i = 0; i < kFeatureCount; i++) {
        if ([self.editingFeatures[kAllFeatures[i].key] boolValue]) activeFeatures++;
    }
    UILabel *featValue = [self.statTiles[2] viewWithTag:100];
    if (featValue) {
        featValue.text = [NSString stringWithFormat:@"%ld / %ld", (long)activeFeatures, (long)kFeatureCount];
    }

    // Tile 3: Active Restrictions
    NSInteger activeRestrictions = 0;
    for (NSInteger i = 0; i < kRestrictionCount; i++) {
        if ([self.editingRestrictions[kRestrictions[i].key] boolValue]) activeRestrictions++;
    }
    UILabel *restrValue = [self.statTiles[3] viewWithTag:100];
    if (restrValue) {
        restrValue.text = [NSString stringWithFormat:@"%ld", (long)activeRestrictions];
    }
}

#pragma mark - Save

- (void)onSave {
    [PPFunc pp_playTapEffect];
    if (_isSaving) return;
    _isSaving = YES;

    [self.saveButton setTitle:kLang(@"Saving") forState:UIControlStateNormal];
    self.saveButton.userInteractionEnabled = NO;
    [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:kLang(@"Please_wait")];

    NSString *uid = self.user.uid;
    __block NSError *lastError = nil;
    dispatch_group_t group = dispatch_group_create();

    // 1. Account Status
    if (![self.editingAccountStatus isEqualToString:self.user.accountStatus]) {
        dispatch_group_enter(group);
        [AdminService updateUserStatus:uid status:self.editingAccountStatus completion:^(NSDictionary *result, NSError *error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    // 2. Verified (direct write via AdminService)
    if (self.editingVerified != self.user.isVerified) {
        dispatch_group_enter(group);
        [AdminService updateUserVerified:uid verified:self.editingVerified completion:^(NSDictionary *result, NSError *error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    // 3. Prodection Status
    if (![self.editingProdectionStatus isEqualToString:self.user.prodectionStatus]) {
        dispatch_group_enter(group);
        [[FUManager shared] updateUserFieldsForUID:uid
                                            fields:@{@"prodectionStatus": self.editingProdectionStatus}
                                        completion:^(NSError *error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    // 4. Features
    BOOL featuresChanged = ![self.editingFeatures isEqualToDictionary:self.user.features];
    if (featuresChanged) {
        dispatch_group_enter(group);
        [AdminService updateUserFeatures:uid features:[self.editingFeatures copy] completion:^(NSDictionary *result, NSError *error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    // 5. Restrictions
    BOOL restrictionsChanged = ![self.editingRestrictions isEqualToDictionary:self.user.restrictions];
    if (restrictionsChanged) {
        dispatch_group_enter(group);
        [AdminService updateUserRestrictions:uid restrictions:[self.editingRestrictions copy] completion:^(NSDictionary *result, NSError *error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [PPHUD dismiss];
        self->_isSaving = NO;
        [self.saveButton setTitle:kLang(@"Save_Changes") forState:UIControlStateNormal];
        self.saveButton.userInteractionEnabled = YES;

        if (lastError) {
            [PPFunc pp_playErrorEffect];
            [PPToast toast:lastError.localizedDescription style:PPToastStyleError haptic:YES duration:3.0];
            [AlertHelper showErrorIn:self title:kLang(@"Update_Error") subtitle:lastError.localizedDescription];
        } else {
            [PPFunc pp_playSuccessEffect];
            [PPToast toast:kLang(@"Update_Success") style:PPToastStyleSuccess haptic:YES duration:2.0];
            // Update the user model in memory
            self.user.accountStatus = self.editingAccountStatus;
            self.user.verified = self.editingVerified;
            self.user.prodectionStatus = self.editingProdectionStatus;
            self.user.features = [self.editingFeatures copy];
            self.user.restrictions = [self.editingRestrictions copy];
            // Pop back after brief delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self.navigationController popViewControllerAnimated:YES];
            });
        }
    });
}

#pragma mark - Entrance Animation

- (void)prepareEntranceState {
    if (_hasAppeared) return;

    self.heroAvatar.alpha = 0;
    self.heroAvatar.transform = CGAffineTransformMakeScale(1.05, 1.05);
    self.heroName.alpha = 0;
    self.heroName.transform = CGAffineTransformMakeTranslation(0, 14);
    self.heroUID.alpha = 0;
    self.heroUID.transform = CGAffineTransformMakeTranslation(0, 10);
    self.heroStatusPillContainer.alpha = 0;
    self.heroVerifiedBadge.alpha = 0;

    for (UIView *tile in self.statTiles) {
        tile.alpha = 0;
        tile.transform = CGAffineTransformMakeTranslation(0, 16);
    }

    self.tableView.alpha = 0;
}

- (void)runEntranceIfNeeded {
    if (_hasAppeared) return;
    _hasAppeared = YES;

    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self resetAllViews];
        return;
    }

    // Hero avatar fades and settles
    [UIView animateWithDuration:0.42
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.heroAvatar.alpha = 1;
        self.heroAvatar.transform = CGAffineTransformIdentity;
    } completion:nil];

    // Name enters
    [UIView animateWithDuration:0.38
                          delay:0.06
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.heroName.alpha = 1;
        self.heroName.transform = CGAffineTransformIdentity;
    } completion:nil];

    // UID + pill + badge
    [UIView animateWithDuration:0.34
                          delay:0.12
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.heroUID.alpha = 1;
        self.heroUID.transform = CGAffineTransformIdentity;
        self.heroStatusPillContainer.alpha = 1;
        self.heroVerifiedBadge.alpha = 1;
    } completion:nil];

    // Stat tiles stagger
    [self.statTiles enumerateObjectsUsingBlock:^(UIView *tile, NSUInteger idx, BOOL *stop) {
        NSTimeInterval delay = 0.20 + (idx * 0.045);
        [UIView animateWithDuration:0.36
                              delay:delay
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            tile.alpha = 1;
            tile.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];

    // Table itself
    [UIView animateWithDuration:0.3
                          delay:0.35
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.tableView.alpha = 1;
    } completion:nil];
}

- (void)resetAllViews {
    self.heroAvatar.alpha = 1;
    self.heroAvatar.transform = CGAffineTransformIdentity;
    self.heroName.alpha = 1;
    self.heroName.transform = CGAffineTransformIdentity;
    self.heroUID.alpha = 1;
    self.heroUID.transform = CGAffineTransformIdentity;
    self.heroStatusPillContainer.alpha = 1;
    self.heroVerifiedBadge.alpha = 1;
    for (UIView *tile in self.statTiles) {
        tile.alpha = 1;
        tile.transform = CGAffineTransformIdentity;
    }
    self.tableView.alpha = 1;
}

@end

#pragma mark - PPUserDetailToggleCell

@implementation PPUserDetailToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor whiteColor];
        self.contentView.backgroundColor = [UIColor whiteColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPFontRegular(PPFontBody);
        _titleLabel.textColor = PrimaryTextClr;
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _toggleSwitch = [[UISwitch alloc] init];
        _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [_toggleSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        _toggleSwitch.onTintColor = AppPrimaryClr;

        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_toggleSwitch];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceBase],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_toggleSwitch.leadingAnchor constant:-PPSpaceSM],

            [_toggleSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceBase],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title isOn:(BOOL)isOn enabled:(BOOL)enabled {
    _titleLabel.text = title;
    _toggleSwitch.on = isOn;
    _toggleSwitch.enabled = enabled;
    self.contentView.alpha = enabled ? 1.0 : 0.55;
    self.accessibilityLabel = title;
    self.accessibilityValue = isOn ? kLang(@"On") : kLang(@"Off");
    self.accessibilityTraits = enabled ? UIAccessibilityTraitButton : (UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled);
}

- (void)switchChanged:(UISwitch *)sender {
    if (self.onToggle) {
        self.onToggle(sender.isOn);
    }
    self.accessibilityValue = sender.isOn ? kLang(@"On") : kLang(@"Off");
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onToggle = nil;
    _titleLabel.text = nil;
    _toggleSwitch.on = NO;
    _toggleSwitch.enabled = YES;
    self.contentView.alpha = 1.0;
}

@end

#pragma mark - PPUserDetailPickerCell

@implementation PPUserDetailPickerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor whiteColor];
        self.contentView.backgroundColor = [UIColor whiteColor];
        self.accessoryType = UITableViewCellAccessoryNone;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        // Selected background
        UIView *selView = [[UIView alloc] init];
        selView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.06];
        self.selectedBackgroundView = selView;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPFontRegular(PPFontBody);
        _titleLabel.textColor = PrimaryTextClr;
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = PPFontMedium(PPFontSubheadline);
        _valueLabel.numberOfLines = 1;
        _valueLabel.adjustsFontForContentSizeCategory = YES;
        _valueLabel.textAlignment = NSTextAlignmentNatural;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _chevronView = [[UIImageView alloc] init];
        _chevronView.image = [UIImage systemImageNamed:@"chevron.forward"];
        _chevronView.tintColor = [UIColor systemGray3Color];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        [_chevronView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_valueLabel];
        [self.contentView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceBase],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_valueLabel.leadingAnchor constant:-PPSpaceSM],

            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-PPSpaceSM],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.centerXAnchor],

            [_chevronView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_chevronView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceBase],
            [_chevronView.widthAnchor constraintEqualToConstant:12],
            [_chevronView.heightAnchor constraintEqualToConstant:14],
        ]];

        }
        return self;
}

- (void)configureWithTitle:(NSString *)title value:(NSString *)value valueColor:(UIColor *)valueColor enabled:(BOOL)enabled {
    _titleLabel.text = title;
    _valueLabel.text = value;
    _valueLabel.textColor = valueColor ?: PrimaryTextClr;
    _chevronView.hidden = !enabled;
    self.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    self.contentView.alpha = enabled ? 1.0 : 0.55;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title, value];
    self.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _titleLabel.text = nil;
    _valueLabel.text = nil;
    _valueLabel.textColor = PrimaryTextClr;
    _chevronView.hidden = NO;
    self.contentView.alpha = 1.0;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

@end
