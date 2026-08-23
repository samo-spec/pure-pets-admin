//
//  UserManagementController.m
//  PurePetsAdmin
//
//  Customer account operational case file.
//

#import "UserManagementController.h"
#import "UIImageView+WebCache.h"
#import "Language.h"
#import "Styling.h"
#import "UserModel.h"
#import "AdminService.h"
#import "PPStaffAuth.h"
#import "PPHUD.h"
#import "PPToast.h"
#import "PPFunc.h"
#import "PPDesignTokens.h"
#import "UIViewController+PPNavBar.h"

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
    if ([status isEqualToString:@"blocked"]) return kLang(@"MissionControl_UserDetail_Status_Blocked");
    if ([status isEqualToString:@"disabled"]) return kLang(@"MissionControl_UserDetail_Status_Disabled");
    if ([status isEqualToString:@"pending_review"]) return kLang(@"MissionControl_UserDetail_Status_PendingReview");
    return kLang(@"MissionControl_UserDetail_Status_Active");
}

static UIColor *AccountStatusColor(NSString *status) {
    if ([status isEqualToString:@"blocked"]) return [UIColor ppError];
    if ([status isEqualToString:@"disabled"]) return [UIColor ppWarning];
    if ([status isEqualToString:@"pending_review"]) return [UIColor ppWarning];
    return [UIColor ppSuccess];
}

static NSString *VerificationStatusLabel(BOOL verified) {
    return verified
        ? kLang(@"MissionControl_UserDetail_Verification_Verified")
        : kLang(@"MissionControl_UserDetail_Verification_NotVerified");
}

static NSString *ProtectionStatusLabel(NSString *status) {
    return [status isEqualToString:@"active"]
        ? kLang(@"MissionControl_UserDetail_Protection_Active")
        : kLang(@"MissionControl_UserDetail_Protection_Inactive");
}

static NSString *PPUserDetailLTRIsolate(NSString *value) {
    NSString *safe = [value isKindOfClass:NSString.class] ? value : @"";
    return safe.length ? [NSString stringWithFormat:@"\u2066%@\u2069", safe] : @"";
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
    {@"withdrawalBlocked", @"MissionControl_UserDetail_Restriction_WithdrawalBlocked"},
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
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)configureWithTitle:(NSString *)title
                     value:(NSString *)value
                valueColor:(UIColor *)valueColor
                      note:(nullable NSString *)note
                   enabled:(BOOL)enabled;
@end

#pragma mark - Private Interface

@interface UserManagementController () <UITableViewDelegate, UITableViewDataSource> {
    BOOL _hasAppeared;
    BOOL _isSaving;
}

@property (nonatomic, strong) UITableView *tableView;

// Header subviews
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIView *caseSurface;
@property (nonatomic, strong) UIImageView *heroAvatar;
@property (nonatomic, strong) UILabel *heroName;
@property (nonatomic, strong) UILabel *heroContact;
@property (nonatomic, strong) UILabel *heroUID;
@property (nonatomic, strong) UIStackView *readoutRail;
@property (nonatomic, strong) NSMutableArray<UIView *> *readoutItems;

// State
@property (nonatomic, strong) UserModel *user;
@property (nonatomic, assign) EditType editType;
@property (nonatomic, assign) BOOL showsAccountUI;
@property (nonatomic, assign) BOOL showsPermRoleUI;
@property (nonatomic, assign) BOOL targetIsStaff;

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

- (CGFloat)pp_saveFooterHeight;
- (void)pp_updateSaveFooterHeight;

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
        _targetIsStaff = [user.accountType.lowercaseString isEqualToString:@"staff"];
        _isSaving = NO;
        _hasAppeared = NO;

        // Snapshot current state
        _editingAccountStatus = user.accountStatus.length ? user.accountStatus : (user.isBlocked ? @"blocked" : @"active");
        _editingVerified = user.isVerified;
        _editingProdectionStatus = user.prodectionStatus.length ? user.prodectionStatus : @"inactive";
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

    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

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

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.caseSurface.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        self.readoutRail.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    }
    if (![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) {
        self.readoutRail.axis = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
            ? UILayoutConstraintAxisVertical
            : UILayoutConstraintAxisHorizontal;
        [self pp_updateSaveFooterHeight];
        [self.tableView reloadData];
        [self layoutHeaderView];
    }
}

#pragma mark - Setup

- (void)buildTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor ppBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor ppSurfaceBorder];
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, PPSpaceBase, 0.0, PPSpaceBase);
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56.0;
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
    self.headerContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.headerContainer.backgroundColor = UIColor.clearColor;
    self.headerContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.caseSurface = [UIView new];
    self.caseSurface.translatesAutoresizingMaskIntoConstraints = NO;
    self.caseSurface.backgroundColor = [UIColor ppElevatedSurface];
    self.caseSurface.layer.cornerRadius = PPCorner16;
    self.caseSurface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.caseSurface.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    self.caseSurface.layer.masksToBounds = YES;
    self.caseSurface.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    if (@available(iOS 13.0, *)) {
        self.caseSurface.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self.headerContainer addSubview:self.caseSurface];

    self.heroAvatar = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.heroAvatar.contentMode = UIViewContentModeScaleAspectFill;
    self.heroAvatar.clipsToBounds = YES;
    self.heroAvatar.backgroundColor = [UIColor ppSecondarySurface];
    self.heroAvatar.tintColor = [UIColor ppPrimary];
    self.heroAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroAvatar.isAccessibilityElement = YES;
    self.heroAvatar.accessibilityLabel = kLang(@"MissionControl_UserDetail_Avatar_Label");
    PPApplyContinuousCorners(self.heroAvatar, PPCorner16);

    NSURL *imageURL = self.user.UserImageUrl ?: PPURLOrNil(self.user.photoURL);
    if (imageURL) {
        [self.heroAvatar sd_setImageWithURL:imageURL
                           placeholderImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    } else {
        self.heroAvatar.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    }

    self.heroName = [[UILabel alloc] init];
    self.heroName.text = self.user.UserName.length ? self.user.UserName : kLang(@"MissionControl_UserDetail_Unknown_User");
    self.heroName.font = PPFontBold(PPFontHeadline);
    self.heroName.textColor = [UIColor ppTextPrimary];
    self.heroName.numberOfLines = 2;
    self.heroName.adjustsFontForContentSizeCategory = YES;
    self.heroName.textAlignment = [Language alignmentForCurrentLanguage];
    self.heroName.translatesAutoresizingMaskIntoConstraints = NO;

    NSMutableArray<NSString *> *contactParts = [NSMutableArray array];
    if (self.user.UserEmail.length) [contactParts addObject:self.user.UserEmail];
    if (self.user.MobileNo.length) [contactParts addObject:self.user.MobileNo];
    self.heroContact = [[UILabel alloc] init];
    self.heroContact.text = [contactParts componentsJoinedByString:@"  •  "];
    self.heroContact.font = PPFontRegular(PPFontSubheadline);
    self.heroContact.textColor = [UIColor ppTextSecondary];
    self.heroContact.numberOfLines = 2;
    self.heroContact.adjustsFontForContentSizeCategory = YES;
    self.heroContact.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.heroContact.textAlignment = NSTextAlignmentNatural;
    self.heroContact.translatesAutoresizingMaskIntoConstraints = NO;

    self.heroUID = [[UILabel alloc] init];
    self.heroUID.text = self.user.uid;
    self.heroUID.font = PPFontRegular(PPFontFootnote);
    self.heroUID.textColor = [UIColor ppTextTertiary];
    self.heroUID.numberOfLines = 2;
    self.heroUID.adjustsFontForContentSizeCategory = YES;
    self.heroUID.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.heroUID.textAlignment = NSTextAlignmentNatural;
    self.heroUID.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroUID.accessibilityLabel = [NSString stringWithFormat:kLang(@"MissionControl_UserDetail_UID_Accessibility_Format"),
                                        PPUserDetailLTRIsolate(self.user.uid)];

    self.readoutItems = [NSMutableArray array];
    self.readoutRail = [self buildOperationalReadoutRail];

    [self.caseSurface addSubview:self.heroAvatar];
    [self.caseSurface addSubview:self.heroName];
    [self.caseSurface addSubview:self.heroContact];
    [self.caseSurface addSubview:self.heroUID];
    [self.caseSurface addSubview:self.readoutRail];

    NSLayoutConstraint *preferredReadoutTop = [self.readoutRail.topAnchor constraintEqualToAnchor:self.heroAvatar.bottomAnchor constant:PPSpaceBase];
    preferredReadoutTop.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [self.caseSurface.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor constant:PPSpaceMD],
        [self.caseSurface.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor constant:PPSpaceBase],
        [self.caseSurface.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor constant:-PPSpaceBase],
        [self.caseSurface.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor constant:-PPSpaceSM],

        [self.heroAvatar.topAnchor constraintEqualToAnchor:self.caseSurface.topAnchor constant:PPSpaceBase],
        [self.heroAvatar.leadingAnchor constraintEqualToAnchor:self.caseSurface.leadingAnchor constant:PPSpaceBase],
        [self.heroAvatar.widthAnchor constraintEqualToConstant:56.0],
        [self.heroAvatar.heightAnchor constraintEqualToConstant:56.0],

        [self.heroName.topAnchor constraintEqualToAnchor:self.heroAvatar.topAnchor],
        [self.heroName.leadingAnchor constraintEqualToAnchor:self.heroAvatar.trailingAnchor constant:PPSpaceMD],
        [self.heroName.trailingAnchor constraintEqualToAnchor:self.caseSurface.trailingAnchor constant:-PPSpaceBase],

        [self.heroContact.topAnchor constraintEqualToAnchor:self.heroName.bottomAnchor constant:PPSpaceXXS],
        [self.heroContact.leadingAnchor constraintEqualToAnchor:self.heroName.leadingAnchor],
        [self.heroContact.trailingAnchor constraintEqualToAnchor:self.heroName.trailingAnchor],

        [self.heroUID.topAnchor constraintEqualToAnchor:self.heroContact.bottomAnchor constant:PPSpaceXXS],
        [self.heroUID.leadingAnchor constraintEqualToAnchor:self.heroName.leadingAnchor],
        [self.heroUID.trailingAnchor constraintEqualToAnchor:self.heroName.trailingAnchor],

        [self.readoutRail.topAnchor constraintGreaterThanOrEqualToAnchor:self.heroAvatar.bottomAnchor constant:PPSpaceBase],
        [self.readoutRail.topAnchor constraintGreaterThanOrEqualToAnchor:self.heroUID.bottomAnchor constant:PPSpaceBase],
        preferredReadoutTop,
        [self.readoutRail.leadingAnchor constraintEqualToAnchor:self.caseSurface.leadingAnchor constant:PPSpaceBase],
        [self.readoutRail.trailingAnchor constraintEqualToAnchor:self.caseSurface.trailingAnchor constant:-PPSpaceBase],
        [self.readoutRail.bottomAnchor constraintEqualToAnchor:self.caseSurface.bottomAnchor constant:-PPSpaceBase],
    ]];

    self.tableView.tableHeaderView = self.headerContainer;
}

- (UIStackView *)buildOperationalReadoutRail {
    NSInteger activeFeatureCount = 0;
    for (NSInteger i = 0; i < kFeatureCount; i++) {
        if ([self.editingFeatures[kAllFeatures[i].key] boolValue]) activeFeatureCount++;
    }
    NSInteger activeRestrictionCount = 0;
    for (NSInteger i = 0; i < kRestrictionCount; i++) {
        if ([self.editingRestrictions[kRestrictions[i].key] boolValue]) activeRestrictionCount++;
    }

    NSString *accessSummary = [NSString stringWithFormat:kLang(@"MissionControl_UserDetail_Access_Format"),
                               [NSNumberFormatter localizedStringFromNumber:@(activeFeatureCount) numberStyle:NSNumberFormatterDecimalStyle],
                               [NSNumberFormatter localizedStringFromNumber:@(activeRestrictionCount) numberStyle:NSNumberFormatterDecimalStyle]];
    NSArray<NSDictionary *> *readoutData = @[
        @{@"icon": @"person.text.rectangle.fill", @"value": AccountStatusLabel(self.editingAccountStatus),
          @"label": kLang(@"MissionControl_UserDetail_Readout_Status"), @"color": AccountStatusColor(self.editingAccountStatus)},
        @{@"icon": @"checkmark.seal.fill", @"value": VerificationStatusLabel(self.editingVerified),
          @"label": kLang(@"MissionControl_UserDetail_Readout_Verification"), @"color": self.editingVerified ? [UIColor ppSuccess] : [UIColor ppTextTertiary]},
        @{@"icon": @"slider.horizontal.3", @"value": accessSummary,
          @"label": kLang(@"MissionControl_UserDetail_Readout_Access"), @"color": activeRestrictionCount > 0 ? [UIColor ppWarning] : [UIColor ppInfo]},
    ];

    UIStackView *rail = [UIStackView new];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    rail.axis = UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory)
        ? UILayoutConstraintAxisVertical
        : UILayoutConstraintAxisHorizontal;
    rail.alignment = UIStackViewAlignmentFill;
    rail.distribution = UIStackViewDistributionFillEqually;
    rail.spacing = 0.0;
    rail.backgroundColor = [UIColor ppSurface];
    rail.layer.cornerRadius = PPCornerSmall;
    rail.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    rail.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    rail.layer.masksToBounds = YES;
    rail.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    for (NSDictionary *data in readoutData) {
        UIView *item = [self createOperationalReadoutItemWithData:data];
        [rail addArrangedSubview:item];
        [self.readoutItems addObject:item];
    }

    return rail;
}

- (UIView *)createOperationalReadoutItemWithData:(NSDictionary *)data {
    UIView *item = [UIView new];
    item.translatesAutoresizingMaskIntoConstraints = NO;
    item.backgroundColor = [UIColor ppSurface];
    item.accessibilityTraits = UIAccessibilityTraitStaticText;
    item.isAccessibilityElement = YES;

    UIImageView *icon = [[UIImageView alloc] init];
    icon.image = [UIImage systemImageNamed:data[@"icon"]];
    icon.tintColor = data[@"color"];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.isAccessibilityElement = NO;
    icon.tag = 102;

    UILabel *value = [[UILabel alloc] init];
    value.text = data[@"value"];
    value.font = PPFontMedium(PPFontSubheadline);
    value.textColor = data[@"color"];
    value.adjustsFontForContentSizeCategory = YES;
    value.textAlignment = [Language alignmentForCurrentLanguage];
    value.numberOfLines = 0;
    value.translatesAutoresizingMaskIntoConstraints = NO;
    value.tag = 100;
    value.isAccessibilityElement = NO;

    UILabel *label = [[UILabel alloc] init];
    label.text = data[@"label"];
    label.font = PPFontRegular(PPFontCaption1);
    label.textColor = [UIColor ppTextSecondary];
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = [Language alignmentForCurrentLanguage];
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.tag = 101;
    label.isAccessibilityElement = NO;

    [item addSubview:icon];
    [item addSubview:value];
    [item addSubview:label];

    item.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", data[@"label"], data[@"value"]];

    [NSLayoutConstraint activateConstraints:@[
        [item.heightAnchor constraintGreaterThanOrEqualToConstant:64.0],
        [icon.topAnchor constraintEqualToAnchor:item.topAnchor constant:PPSpaceSM],
        [icon.leadingAnchor constraintEqualToAnchor:item.leadingAnchor constant:PPSpaceSM],
        [icon.widthAnchor constraintEqualToConstant:18.0],
        [icon.heightAnchor constraintEqualToConstant:18.0],

        [label.topAnchor constraintEqualToAnchor:item.topAnchor constant:PPSpaceSM],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:PPSpaceSM],
        [label.trailingAnchor constraintEqualToAnchor:item.trailingAnchor constant:-PPSpaceSM],

        [value.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:PPSpaceXXS],
        [value.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
        [value.trailingAnchor constraintEqualToAnchor:label.trailingAnchor],
        [value.bottomAnchor constraintEqualToAnchor:item.bottomAnchor constant:-PPSpaceSM],
    ]];

    return item;
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
    self.saveFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, [self pp_saveFooterHeight])];
    self.saveFooterView.backgroundColor = UIColor.clearColor;

    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveButton.backgroundColor = [UIColor ppPrimary];
    self.saveButton.tintColor = PPOnPrimaryColor();
    self.saveButton.titleLabel.font = PPFontBold(PPFontHeadline);
    self.saveButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.saveButton.titleLabel.numberOfLines = 2;
    [self.saveButton setTitle:kLang(@"MissionControl_UserDetail_Save") forState:UIControlStateNormal];
    [self.saveButton setTitleColor:PPOnPrimaryColor() forState:UIControlStateNormal];
    [self.saveButton addTarget:self action:@selector(onSave) forControlEvents:UIControlEventTouchUpInside];
    self.saveButton.accessibilityLabel = kLang(@"MissionControl_UserDetail_Save");
    self.saveButton.accessibilityHint = kLang(@"MissionControl_UserDetail_Save_Hint");
    PPApplyContinuousCorners(self.saveButton, PPCornerSmall);

    [self.saveFooterView addSubview:self.saveButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.saveButton.topAnchor constraintEqualToAnchor:self.saveFooterView.topAnchor constant:PPSpaceBase],
        [self.saveButton.leadingAnchor constraintEqualToAnchor:self.saveFooterView.leadingAnchor constant:PPSpaceBase],
        [self.saveButton.trailingAnchor constraintEqualToAnchor:self.saveFooterView.trailingAnchor constant:-PPSpaceBase],
        [self.saveButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightLG],
        [self.saveButton.bottomAnchor constraintLessThanOrEqualToAnchor:self.saveFooterView.bottomAnchor constant:-PPSpaceBase],
    ]];

    // Add press animation
    [self.saveButton addTarget:self action:@selector(saveButtonTouchDown) forControlEvents:UIControlEventTouchDown];
    [self.saveButton addTarget:self action:@selector(saveButtonTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    self.tableView.tableFooterView = self.saveFooterView;
}

- (CGFloat)pp_saveFooterHeight {
    return UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        ? 132.0
        : PPButtonHeightLG + PPSpaceXXL + PPSpaceSM;
}

- (void)pp_updateSaveFooterHeight {
    if (!self.saveFooterView) return;
    CGRect frame = self.saveFooterView.frame;
    frame.size.height = [self pp_saveFooterHeight];
    self.saveFooterView.frame = frame;
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
                       title:kLang(self.targetIsStaff ? @"User_Details" : @"MissionControl_UserDetail_Title")
                    showBack:YES];
}

- (void)dismissSelf {
    [PPFunc pp_playTapEffect];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Permissions

- (void)evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    self.canManage = !self.targetIsStaff && [staff hasPermission:kStaffPermUsersManage];
    self.canManageFeatures = [staff hasPermission:kStaffPermUsersFeaturesManage];
    self.canManageRestrictions = [staff hasPermission:kStaffPermUsersRestrictionsManage];

    BOOL canSaveAnyDomain = self.canManage || self.canManageFeatures || self.canManageRestrictions;
    self.saveButton.hidden = !canSaveAnyDomain;
    self.saveButton.userInteractionEnabled = canSaveAnyDomain;
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
        case SectionAccount: return kLang(@"MissionControl_UserDetail_Section_Account");
        case SectionFeatures: return kLang(@"MissionControl_UserDetail_Section_Features");
        case SectionRestrictions: return kLang(@"MissionControl_UserDetail_Section_Restrictions");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch ((SectionType)section) {
        case SectionAccount:
            return kLang(@"MissionControl_UserDetail_Account_ServerManaged_Footer");
        case SectionFeatures:
            return self.canManageFeatures ? nil : kLang(@"MissionControl_UserDetail_Features_ReadOnly_Footer");
        case SectionRestrictions:
            return self.canManageRestrictions ? nil : kLang(@"MissionControl_UserDetail_Restrictions_ReadOnly_Footer");
        default:
            return nil;
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
            NSString *note = self.canManage ? nil : kLang(@"MissionControl_UserDetail_Permission_ReadOnly");
            [cell configureWithTitle:kLang(@"MissionControl_UserDetail_Account_Status")
                               value:label
                          valueColor:color
                                note:note
                             enabled:self.canManage];
            cell.accessibilityIdentifier = @"account_status_cell";
            return cell;
        }
        case AccountRowVerified: {
            PPUserDetailPickerCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kPickerCellID];
            UIColor *color = self.editingVerified ? [UIColor ppSuccess] : [UIColor ppTextTertiary];
            [cell configureWithTitle:kLang(@"MissionControl_UserDetail_Verification")
                               value:VerificationStatusLabel(self.editingVerified)
                          valueColor:color
                                note:kLang(@"MissionControl_UserDetail_ServerManaged")
                             enabled:NO];
            cell.accessibilityIdentifier = @"verified_readout_cell";
            return cell;
        }
        case AccountRowProtection: {
            PPUserDetailPickerCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kPickerCellID];
            UIColor *color = [self.editingProdectionStatus isEqualToString:@"active"] ? [UIColor ppSuccess] : [UIColor ppTextTertiary];
            [cell configureWithTitle:kLang(@"MissionControl_UserDetail_Protection")
                               value:ProtectionStatusLabel(self.editingProdectionStatus)
                          valueColor:color
                                note:kLang(@"MissionControl_UserDetail_ServerManaged")
                             enabled:NO];
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
    BOOL isServerDisabled = [def.key isEqualToString:@"canDelivery"];
    BOOL enabled = self.canManageFeatures && !isServerDisabled;
    PPUserDetailToggleCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kToggleCellID];
    [cell configureWithTitle:kLang(def.labelKey) isOn:isOn enabled:enabled];
    if (isServerDisabled) {
        cell.toggleSwitch.accessibilityHint = kLang(@"MissionControl_UserDetail_ServerManaged");
    } else {
        PPweakify(self);
        cell.onToggle = ^(BOOL isOn) {
            PPstrongify(self);
            self.editingFeatures[def.key] = @(isOn);
            [self updateOperationalReadouts];
        };
    }
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
        [self updateOperationalReadouts];
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
        }
    }
}

- (void)showAccountStatusPicker {
    [PPFunc pp_playTapEffect];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"MissionControl_UserDetail_Account_Status")
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
    [self updateOperationalReadouts];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:AccountRowStatus inSection:SectionAccount]]
                           withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Operational Readouts

- (void)updateOperationalReadouts {
    if (self.readoutItems.count < 3) return;

    NSInteger activeFeatures = 0;
    for (NSInteger i = 0; i < kFeatureCount; i++) {
        if ([self.editingFeatures[kAllFeatures[i].key] boolValue]) activeFeatures++;
    }
    NSInteger activeRestrictions = 0;
    for (NSInteger i = 0; i < kRestrictionCount; i++) {
        if ([self.editingRestrictions[kRestrictions[i].key] boolValue]) activeRestrictions++;
    }

    NSArray<NSString *> *values = @[
        AccountStatusLabel(self.editingAccountStatus),
        VerificationStatusLabel(self.editingVerified),
        [NSString stringWithFormat:kLang(@"MissionControl_UserDetail_Access_Format"),
         [NSNumberFormatter localizedStringFromNumber:@(activeFeatures) numberStyle:NSNumberFormatterDecimalStyle],
         [NSNumberFormatter localizedStringFromNumber:@(activeRestrictions) numberStyle:NSNumberFormatterDecimalStyle]],
    ];
    NSArray<UIColor *> *colors = @[
        AccountStatusColor(self.editingAccountStatus),
        self.editingVerified ? [UIColor ppSuccess] : [UIColor ppTextTertiary],
        activeRestrictions > 0 ? [UIColor ppWarning] : [UIColor ppInfo],
    ];

    [self.readoutItems enumerateObjectsUsingBlock:^(UIView *item, NSUInteger index, BOOL *stop) {
        UILabel *valueLabel = [item viewWithTag:100];
        UILabel *label = [item viewWithTag:101];
        UIImageView *icon = [item viewWithTag:102];
        valueLabel.text = values[index];
        valueLabel.textColor = colors[index];
        icon.tintColor = colors[index];
        item.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", label.text ?: @"", values[index]];
    }];
}

#pragma mark - Save

- (void)onSave {
    [PPFunc pp_playTapEffect];
    if (_isSaving) return;
    _isSaving = YES;

    [self.saveButton setTitle:kLang(@"MissionControl_UserDetail_Saving") forState:UIControlStateNormal];
    self.saveButton.userInteractionEnabled = NO;
    [PPHUD showRingIn:self.view
                title:kLang(@"MissionControl_UserDetail_Saving")
             subtitle:kLang(@"MissionControl_UserDetail_Saving_Body")];

    NSString *uid = self.user.uid;
    __block NSError *lastError = nil;
    __block BOOL statusSucceeded = NO;
    __block BOOL featuresSucceeded = NO;
    __block BOOL restrictionsSucceeded = NO;
    __block NSDictionary *returnedFeatures = nil;
    __block NSDictionary *returnedRestrictions = nil;
    dispatch_group_t group = dispatch_group_create();

    NSString *originalStatus = self.user.accountStatus.length
        ? self.user.accountStatus
        : (self.user.isBlocked ? @"blocked" : @"active");
    if (self.canManage && ![self.editingAccountStatus isEqualToString:originalStatus]) {
        dispatch_group_enter(group);
        [AdminService updateUserStatus:uid status:self.editingAccountStatus completion:^(NSDictionary *result, NSError *error) {
            (void)result;
            if (error && !lastError) lastError = error;
            if (!error) statusSucceeded = YES;
            dispatch_group_leave(group);
        }];
    }

    NSMutableDictionary *featurePayload = [NSMutableDictionary dictionary];
    for (NSInteger index = 0; index < kFeatureCount; index++) {
        NSString *key = kAllFeatures[index].key;
        NSNumber *editedValue = self.editingFeatures[key];
        NSNumber *originalValue = self.user.features[key];
        if (editedValue && (!originalValue || editedValue.boolValue != originalValue.boolValue)) {
            featurePayload[key] = @(editedValue.boolValue);
        }
    }
    if (self.canManageFeatures && featurePayload.count > 0) {
        dispatch_group_enter(group);
        [AdminService updateUserFeatures:uid features:featurePayload completion:^(NSDictionary *result, NSError *error) {
            if (error && !lastError) lastError = error;
            if (!error) {
                featuresSucceeded = YES;
                if ([result[@"features"] isKindOfClass:NSDictionary.class]) returnedFeatures = result[@"features"];
            }
            dispatch_group_leave(group);
        }];
    }

    NSMutableDictionary *restrictionPayload = [NSMutableDictionary dictionary];
    for (NSInteger index = 0; index < kRestrictionCount; index++) {
        NSString *key = kRestrictions[index].key;
        NSNumber *editedValue = self.editingRestrictions[key];
        NSNumber *originalValue = self.user.restrictions[key];
        if (editedValue && (!originalValue || editedValue.boolValue != originalValue.boolValue)) {
            restrictionPayload[key] = @(editedValue.boolValue);
        }
    }
    if (self.canManageRestrictions && restrictionPayload.count > 0) {
        dispatch_group_enter(group);
        [AdminService updateUserRestrictions:uid restrictions:restrictionPayload completion:^(NSDictionary *result, NSError *error) {
            if (error && !lastError) lastError = error;
            if (!error) {
                restrictionsSucceeded = YES;
                if ([result[@"restrictions"] isKindOfClass:NSDictionary.class]) returnedRestrictions = result[@"restrictions"];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group,
 dispatch_get_main_queue(),
 ^{
        [PPHUD dismiss];
        self->_isSaving = NO;
        [self.saveButton setTitle:kLang(@"MissionControl_UserDetail_Save") forState:UIControlStateNormal];
        self.saveButton.userInteractionEnabled = self.canManage || self.canManageFeatures || self.canManageRestrictions;

        if (statusSucceeded) self.user.accountStatus = self.editingAccountStatus;
        if (featuresSucceeded) {
            if (returnedFeatures) {
                self.user.features = returnedFeatures;
                self.editingFeatures = returnedFeatures.mutableCopy;
            } else {
                NSMutableDictionary *merged = [self.user.features ?: @{} mutableCopy];
                [merged addEntriesFromDictionary:featurePayload];
                self.user.features = merged.copy;
            }
        }
        if (restrictionsSucceeded) {
            if (returnedRestrictions) {
                self.user.restrictions = returnedRestrictions;
                self.editingRestrictions = returnedRestrictions.mutableCopy;
            } else {
                NSMutableDictionary *merged = [self.user.restrictions ?: @{} mutableCopy];
                [merged addEntriesFromDictionary:restrictionPayload];
                self.user.restrictions = merged.copy;
            }
        }

        if (lastError) {
            [self updateOperationalReadouts];
            [self.tableView reloadData];
            [PPFunc pp_playErrorEffect];
            [PPToast toast:lastError.localizedDescription style:PPToastStyleError haptic:YES duration:3.0];
            [PPAlertHelper showErrorIn:self title:kLang(@"Update_Error") subtitle:lastError.localizedDescription];
        } else {
            [PPFunc pp_playSuccessEffect];
            [PPToast toast:kLang(@"Update_Success") style:PPToastStyleSuccess haptic:YES duration:2.0];
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
    self.tableView.alpha = 0;
    self.tableView.transform = CGAffineTransformMakeTranslation(0.0, 8.0);
}

- (void)runEntranceIfNeeded {
    if (_hasAppeared) return;
    _hasAppeared = YES;

    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.tableView.alpha = 1.0;
        self.tableView.transform = CGAffineTransformIdentity;
        return;
    }

    [UIView animateWithDuration:0.30
                           delay:0
                         options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                      animations:^{
        self.tableView.alpha = 1;
        self.tableView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - PPUserDetailToggleCell

@implementation PPUserDetailToggleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor ppSurface];
        self.contentView.backgroundColor = [UIColor ppSurface];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.isAccessibilityElement = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPFontRegular(PPFontBody);
        _titleLabel.textColor = [UIColor ppTextPrimary];
        _titleLabel.numberOfLines = 0;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _titleLabel.isAccessibilityElement = NO;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _toggleSwitch = [[UISwitch alloc] init];
        _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        [_toggleSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        _toggleSwitch.onTintColor = [UIColor ppPrimary];

        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_toggleSwitch];

        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:52.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceBase],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_toggleSwitch.leadingAnchor constant:-PPSpaceSM],
            [_titleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
            [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],

            [_toggleSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceBase],
            [_toggleSwitch.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title isOn:(BOOL)isOn enabled:(BOOL)enabled {
    _titleLabel.text = title;
    _toggleSwitch.on = isOn;
    _toggleSwitch.enabled = enabled;
    self.contentView.alpha = enabled ? 1.0 : 0.62;
    _toggleSwitch.accessibilityLabel = title;
    _toggleSwitch.accessibilityValue = isOn ? kLang(@"On") : kLang(@"Off");
    _toggleSwitch.accessibilityHint = nil;
}

- (void)switchChanged:(UISwitch *)sender {
    if (self.onToggle) {
        self.onToggle(sender.isOn);
    }
    sender.accessibilityValue = sender.isOn ? kLang(@"On") : kLang(@"Off");
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.onToggle = nil;
    _titleLabel.text = nil;
    _toggleSwitch.on = NO;
    _toggleSwitch.enabled = YES;
    _toggleSwitch.accessibilityLabel = nil;
    _toggleSwitch.accessibilityValue = nil;
    _toggleSwitch.accessibilityHint = nil;
    self.contentView.alpha = 1.0;
}

@end

#pragma mark - PPUserDetailPickerCell

@implementation PPUserDetailPickerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor ppSurface];
        self.contentView.backgroundColor = [UIColor ppSurface];
        self.accessoryType = UITableViewCellAccessoryNone;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.isAccessibilityElement = YES;

        UIView *selView = [[UIView alloc] init];
        selView.backgroundColor = [[UIColor ppSoftRose] colorWithAlphaComponent:0.55];
        self.selectedBackgroundView = selView;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPFontRegular(PPFontBody);
        _titleLabel.textColor = [UIColor ppTextPrimary];
        _titleLabel.numberOfLines = 0;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _titleLabel.isAccessibilityElement = NO;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = PPFontMedium(PPFontSubheadline);
        _valueLabel.numberOfLines = 0;
        _valueLabel.adjustsFontForContentSizeCategory = YES;
        _valueLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _valueLabel.isAccessibilityElement = NO;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _noteLabel = [[UILabel alloc] init];
        _noteLabel.font = PPFontRegular(PPFontCaption1);
        _noteLabel.textColor = [UIColor ppTextSecondary];
        _noteLabel.numberOfLines = 0;
        _noteLabel.adjustsFontForContentSizeCategory = YES;
        _noteLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _noteLabel.isAccessibilityElement = NO;
        _noteLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _chevronView = [[UIImageView alloc] init];
        _chevronView.image = [UIImage systemImageNamed:@"chevron.forward"];
        _chevronView.tintColor = [UIColor ppTextTertiary];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        [_chevronView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *valueStack = [[UIStackView alloc] initWithArrangedSubviews:@[_valueLabel, _noteLabel]];
        valueStack.translatesAutoresizingMaskIntoConstraints = NO;
        valueStack.axis = UILayoutConstraintAxisVertical;
        valueStack.alignment = UIStackViewAlignmentFill;
        valueStack.spacing = PPSpaceXXS;
        valueStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:valueStack];
        [self.contentView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:52.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceBase],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:valueStack.leadingAnchor constant:-PPSpaceSM],
            [_titleLabel.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
            [_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],

            [valueStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
            [valueStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],
            [valueStack.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-PPSpaceSM],
            [valueStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.centerXAnchor],

            [_chevronView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_chevronView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceBase],
            [_chevronView.widthAnchor constraintEqualToConstant:12],
            [_chevronView.heightAnchor constraintEqualToConstant:14],
        ]];

        }
        return self;
}

- (void)configureWithTitle:(NSString *)title
                     value:(NSString *)value
                valueColor:(UIColor *)valueColor
                      note:(NSString *)note
                   enabled:(BOOL)enabled {
    _titleLabel.text = title;
    _valueLabel.text = value;
    _valueLabel.textColor = valueColor ?: [UIColor ppTextPrimary];
    _noteLabel.text = note;
    _noteLabel.hidden = note.length == 0;
    _chevronView.hidden = !enabled;
    self.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    self.contentView.alpha = enabled ? 1.0 : 0.84;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title, value];
    self.accessibilityHint = note;
    self.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _titleLabel.text = nil;
    _valueLabel.text = nil;
    _valueLabel.textColor = [UIColor ppTextPrimary];
    _noteLabel.text = nil;
    _noteLabel.hidden = YES;
    _chevronView.hidden = NO;
    self.contentView.alpha = 1.0;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    self.accessibilityLabel = nil;
    self.accessibilityHint = nil;
}

@end
