//
//  UserManagementController.m
//  PurePetsAdmin
//
//  Reimagined NextGen V6 Customer Account & Access Control Case File.
//

#import "UserManagementController.h"
#import "PurePetsAdmin-Swift.h"
#import "Language.h"
#import "Styling.h"
#import "UserModel.h"
#import "AdminService.h"
#import "PPStaffAuth.h"
#import "PPHUD.h"
#import "PPToast.h"
#import "PPFunc.h"
#import "PPFunc+Haptics.h"
#import "PPDesignTokens.h"
#import "PPProviderUI.h"
#import "PPAlertHelper.h"

#pragma mark - Typography Helpers

static inline UIFont *PPAppFontBold(CGFloat size) {
    return [UIFont fontWithName:@"Beiruti-Bold" size:size] ?: [UIFont boldSystemFontOfSize:size];
}

static inline UIFont *PPAppFontSemiBold(CGFloat size) {
    return [UIFont fontWithName:@"Beiruti-SemiBold" size:size] ?: [UIFont fontWithName:@"Beiruti-Bold" size:size] ?: [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

static inline UIFont *PPAppFontMedium(CGFloat size) {
    return [UIFont fontWithName:@"Beiruti-Medium" size:size] ?: [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

static inline UIFont *PPAppFontRegular(CGFloat size) {
    return [UIFont fontWithName:@"Beiruti-Regular" size:size] ?: [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
}

static inline UIFont *PPAppFont(CGFloat size) {
    return PPAppFontMedium(size);
}

#pragma mark - Constants & Metadata

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

static NSString *const kNextGenSwitchCellID = @"PPNextGenSwitchCardCellID";
static NSString *const kNextGenPickerCellID = @"PPNextGenPickerCardCellID";

static NSArray<NSString *> *AccountStatusOptions(void) {
    return @[@"active", @"blocked", @"disabled", @"pending_review"];
}

static NSString *AccountStatusLabel(NSString *status) {
    if ([status isEqualToString:@"blocked"]) return kLang(@"MissionControl_UserDetail_Status_Blocked") ?: @"محظور";
    if ([status isEqualToString:@"disabled"]) return kLang(@"MissionControl_UserDetail_Status_Disabled") ?: @"معطّل";
    if ([status isEqualToString:@"pending_review"]) return kLang(@"MissionControl_UserDetail_Status_PendingReview") ?: @"قيد المراجعة";
    return kLang(@"MissionControl_UserDetail_Status_Active") ?: @"نشط";
}

static UIColor *AccountStatusColor(NSString *status) {
    if ([status isEqualToString:@"blocked"]) return [UIColor systemRedColor];
    if ([status isEqualToString:@"disabled"]) return [UIColor systemOrangeColor];
    if ([status isEqualToString:@"pending_review"]) return [UIColor systemYellowColor];
    return [UIColor ppSuccess];
}

static NSString *VerificationStatusLabel(BOOL verified) {
    return verified
        ? (kLang(@"MissionControl_UserDetail_Verification_Verified") ?: @"موثّق رسمياً")
        : (kLang(@"MissionControl_UserDetail_Verification_NotVerified") ?: @"غير موثّق");
}

static NSString *ProtectionStatusLabel(NSString *status) {
    return [status isEqualToString:@"active"]
        ? (kLang(@"MissionControl_UserDetail_Protection_Active") ?: @"حماية نشطة")
        : (kLang(@"MissionControl_UserDetail_Protection_Inactive") ?: @"غير نشطة");
}

#pragma mark - Feature & Restriction Definitions

typedef struct {
    __unsafe_unretained NSString *key;
    __unsafe_unretained NSString *labelKey;
    __unsafe_unretained NSString *descKey;
    __unsafe_unretained NSString *symbol;
    NSUInteger colorIndex; // 0:Teal, 1:Pink, 2:Indigo, 3:Purple, 4:Blue, 5:Orange, 6:Green, 7:Amber
} PPFeatureDef;

static PPFeatureDef kAllFeatures[] = {
    {@"canPostPetAds",              @"Feature_CanPostPetAds",              @"Feature_CanPostPetAds_Desc",              @"pawprint.fill",                     0},
    {@"canPostAdoption",            @"Feature_CanPostAdoption",            @"Feature_CanPostAdoption_Desc",            @"heart.circle.fill",                1},
    {@"canSellAccessories",         @"Feature_CanSellAccessories",         @"Feature_CanSellAccessories_Desc",         @"tag.fill",                          2},
    {@"canOfferServices",           @"Feature_CanOfferServices",           @"Feature_CanOfferServices_Desc",           @"cross.case.fill",                   3},
    {@"canDelivery",                @"Feature_CanDelivery",                @"Feature_CanDelivery_Desc",                @"bicycle",                           4},
    {@"canDeliveryCompany",         @"Feature_CanDeliveryCompany",         @"Feature_CanDeliveryCompany_Desc",         @"box.truck.fill",                    4},
    {@"canUseStories",              @"Feature_CanUseStories",              @"Feature_CanUseStories_Desc",              @"camera.metering.spot",              5},
    {@"canUseChat",                 @"Feature_CanUseChat",                 @"Feature_CanUseChat_Desc",                 @"bubble.left.and.bubble.right.fill", 6},
    {@"canAccessPremiumMarketplace",@"Feature_CanAccessPremiumMarketplace",@"Feature_CanAccessPremiumMarketplace_Desc",@"star.hexagonpath.fill",             7},
    {@"canAccessProviderMarketplace",@"Feature_CanAccessProviderMarketplace",@"Feature_CanAccessProviderMarketplace_Desc",@"building.2.crop.circle.fill",   2},
    {@"canPharmacy",                @"Feature_CanPharmacy",                @"Feature_CanPharmacy_Desc",                @"pills.fill",                        3},
    {@"canVet",                     @"Feature_CanVet",                     @"Feature_CanVet_Desc",                     @"stethoscope",                       6},
};
static NSInteger kFeatureCount = sizeof(kAllFeatures) / sizeof(PPFeatureDef);

typedef struct {
    __unsafe_unretained NSString *key;
    __unsafe_unretained NSString *labelKey;
    __unsafe_unretained NSString *descKey;
    __unsafe_unretained NSString *symbol;
} PPRestrictionDef;

static PPRestrictionDef kRestrictions[] = {
    {@"postingBlocked",    @"Restriction_PostingBlocked",    @"Restriction_PostingBlocked_Desc",    @"nosign"},
    {@"chatBlocked",       @"Restriction_ChatBlocked",       @"Restriction_ChatBlocked_Desc",       @"bubble.left.and.exclamationmark.bubble.right.fill"},
    {@"purchaseBlocked",   @"Restriction_PurchaseBlocked",   @"Restriction_PurchaseBlocked_Desc",   @"cart.badge.minus"},
    {@"withdrawalBlocked", @"MissionControl_UserDetail_Restriction_WithdrawalBlocked", @"Restriction_WithdrawalBlocked_Desc", @"banknote.fill"},
};
static NSInteger kRestrictionCount = sizeof(kRestrictions) / sizeof(PPRestrictionDef);

static UIColor *PPColorForIndex(NSUInteger idx) {
    switch (idx) {
        case 0: return [UIColor systemTealColor];
        case 1: return [UIColor systemPinkColor];
        case 2: return [UIColor systemIndigoColor];
        case 3: return [UIColor systemPurpleColor];
        case 4: return [UIColor systemBlueColor];
        case 5: return [UIColor systemOrangeColor];
        case 6: return [UIColor systemGreenColor];
        case 7: return [UIColor systemYellowColor];
        default: return PPProviderBrandColor();
    }
}

#pragma mark - NextGen V6 Switch Card Cell

@interface PPNextGenSwitchCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconShell;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIView *lockBadge;
@property (nonatomic, copy) void (^onToggle)(BOOL isOn);

- (void)configureWithTitle:(NSString *)title
               description:(NSString *)desc
                    symbol:(NSString *)symbol
                 tintColor:(UIColor *)tintColor
                      isOn:(BOOL)isOn
                   enabled:(BOOL)enabled
          isServerDisabled:(BOOL)isServerDisabled
             isRestriction:(BOOL)isRestriction;
@end

@implementation PPNextGenSwitchCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [self pp_setupCell];
    }
    return self;
}

- (void)pp_setupCell {
    _cardView = [UIView new];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(_cardView, 18.0);
    _cardView.layer.borderWidth = 1.0;
    _cardView.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.12].CGColor;
    _cardView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(_cardView);
    [self.contentView addSubview:_cardView];

    _iconShell = [UIView new];
    _iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_iconShell, 14.0);
    [_cardView addSubview:_iconShell];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_iconShell addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = PPAppFontBold(15.5);
    _titleLabel.textColor = PPProviderPrimaryTextColor();
    _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [_cardView addSubview:_titleLabel];

    _descLabel = [UILabel new];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.font = PPAppFontRegular(12.0);
    _descLabel.textColor = PPProviderSecondaryTextColor();
    _descLabel.numberOfLines = 2;
    _descLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [_cardView addSubview:_descLabel];

    _toggleSwitch = [UISwitch new];
    _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_toggleSwitch addTarget:self action:@selector(pp_switchChanged:) forControlEvents:UIControlEventValueChanged];
    [_cardView addSubview:_toggleSwitch];

    _lockBadge = [UIView new];
    _lockBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _lockBadge.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [[UIColor whiteColor] colorWithAlphaComponent:0.08]
            : [[UIColor blackColor] colorWithAlphaComponent:0.05];
    }];
    PPApplyContinuousCorners(_lockBadge, 8.0);
    _lockBadge.hidden = YES;
    [_cardView addSubview:_lockBadge];

    UIImageView *lockIcon = [UIImageView new];
    lockIcon.translatesAutoresizingMaskIntoConstraints = NO;
    lockIcon.contentMode = UIViewContentModeScaleAspectFit;
    UIImageSymbolConfiguration *lConf = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
    lockIcon.image = [[UIImage systemImageNamed:@"lock.fill" withConfiguration:lConf] imageWithTintColor:PPProviderSecondaryTextColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
    [_lockBadge addSubview:lockIcon];

    UILabel *lockLbl = [UILabel new];
    lockLbl.translatesAutoresizingMaskIntoConstraints = NO;
    lockLbl.font = PPAppFontMedium(11.0);
    lockLbl.textColor = PPProviderSecondaryTextColor();
    lockLbl.text = kLang(@"MissionControl_UserDetail_ServerManaged") ?: @"إدارة خادم";
    [_lockBadge addSubview:lockLbl];

    [NSLayoutConstraint activateConstraints:@[
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

        [_iconShell.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:12.0],
        [_iconShell.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_iconShell.widthAnchor constraintEqualToConstant:44.0],
        [_iconShell.heightAnchor constraintEqualToConstant:44.0],
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconShell.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconShell.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:22.0],
        [_iconView.heightAnchor constraintEqualToConstant:22.0],

        [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconShell.trailingAnchor constant:12.0],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggleSwitch.leadingAnchor constant:-10.0],

        [_descLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
        [_descLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_descLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggleSwitch.leadingAnchor constant:-10.0],
        [_descLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-12.0],

        [_toggleSwitch.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12.0],
        [_toggleSwitch.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],

        [_lockBadge.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12.0],
        [_lockBadge.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [lockIcon.leadingAnchor constraintEqualToAnchor:_lockBadge.leadingAnchor constant:6.0],
        [lockIcon.centerYAnchor constraintEqualToAnchor:_lockBadge.centerYAnchor],
        [lockIcon.widthAnchor constraintEqualToConstant:12.0],
        [lockIcon.heightAnchor constraintEqualToConstant:12.0],
        [lockLbl.leadingAnchor constraintEqualToAnchor:lockIcon.trailingAnchor constant:4.0],
        [lockLbl.trailingAnchor constraintEqualToAnchor:_lockBadge.trailingAnchor constant:-8.0],
        [lockLbl.centerYAnchor constraintEqualToAnchor:_lockBadge.centerYAnchor],
        [_lockBadge.heightAnchor constraintEqualToConstant:26.0]
    ]];
}

- (void)configureWithTitle:(NSString *)title
               description:(NSString *)desc
                    symbol:(NSString *)symbol
                 tintColor:(UIColor *)tintColor
                      isOn:(BOOL)isOn
                   enabled:(BOOL)enabled
          isServerDisabled:(BOOL)isServerDisabled
             isRestriction:(BOOL)isRestriction {
    _titleLabel.text = title;
    _descLabel.text = desc;
    _iconShell.backgroundColor = [tintColor colorWithAlphaComponent:0.12];

    UIImageSymbolConfiguration *symConf = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    _iconView.image = [[UIImage systemImageNamed:symbol withConfiguration:symConf] imageWithTintColor:tintColor renderingMode:UIImageRenderingModeAlwaysOriginal];

    _toggleSwitch.onTintColor = isRestriction ? [UIColor systemRedColor] : [UIColor ppPrimary];
    _toggleSwitch.on = isOn;
    _toggleSwitch.enabled = enabled && !isServerDisabled;

    if (isServerDisabled) {
        _toggleSwitch.hidden = YES;
        _lockBadge.hidden = NO;
    } else {
        _toggleSwitch.hidden = !enabled;
        _lockBadge.hidden = YES;
    }

    if (isRestriction && isOn) {
        _cardView.layer.borderColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.35].CGColor;
        _titleLabel.textColor = [UIColor systemRedColor];
    } else {
        _cardView.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.12].CGColor;
        _titleLabel.textColor = PPProviderPrimaryTextColor();
    }
}

- (void)pp_switchChanged:(UISwitch *)sender {
    [PPFunc pp_playSelectionEffect];
    if (self.onToggle) self.onToggle(sender.isOn);
}

@end

#pragma mark - NextGen V6 Picker Card Cell

@interface PPNextGenPickerCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconShell;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIView *valuePill;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIImageView *chevronView;

- (void)configureWithTitle:(NSString *)title
                     value:(NSString *)value
                valueColor:(UIColor *)valueColor
                    symbol:(NSString *)symbol
                      note:(nullable NSString *)note
                   enabled:(BOOL)enabled;
@end

@implementation PPNextGenPickerCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [self pp_setupCell];
    }
    return self;
}

- (void)pp_setupCell {
    _cardView = [UIView new];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(_cardView, 18.0);
    _cardView.layer.borderWidth = 1.0;
    _cardView.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.12].CGColor;
    _cardView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(_cardView);
    [self.contentView addSubview:_cardView];

    _iconShell = [UIView new];
    _iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_iconShell, 14.0);
    [_cardView addSubview:_iconShell];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_iconShell addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = PPAppFontBold(15.5);
    _titleLabel.textColor = PPProviderPrimaryTextColor();
    _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [_cardView addSubview:_titleLabel];

    _noteLabel = [UILabel new];
    _noteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _noteLabel.font = PPAppFontRegular(12.0);
    _noteLabel.textColor = PPProviderSecondaryTextColor();
    _noteLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [_cardView addSubview:_noteLabel];

    _valuePill = [UIView new];
    _valuePill.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_valuePill, 10.0);
    [_cardView addSubview:_valuePill];

    _valueLabel = [UILabel new];
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _valueLabel.font = PPAppFontBold(12.5);
    _valueLabel.textAlignment = NSTextAlignmentCenter;
    [_valuePill addSubview:_valueLabel];

    _chevronView = [UIImageView new];
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    BOOL isRTL = [[Language currentLanguageCode] isEqualToString:@"ar"];
    UIImageSymbolConfiguration *chvConf = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
    _chevronView.image = [[UIImage systemImageNamed:(isRTL ? @"chevron.backward" : @"chevron.forward") withConfiguration:chvConf]
                          imageWithTintColor:[PPProviderSecondaryTextColor() colorWithAlphaComponent:0.4] renderingMode:UIImageRenderingModeAlwaysOriginal];
    [_cardView addSubview:_chevronView];

    [NSLayoutConstraint activateConstraints:@[
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

        [_iconShell.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:12.0],
        [_iconShell.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_iconShell.widthAnchor constraintEqualToConstant:44.0],
        [_iconShell.heightAnchor constraintEqualToConstant:44.0],
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconShell.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconShell.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:22.0],
        [_iconView.heightAnchor constraintEqualToConstant:22.0],

        [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconShell.trailingAnchor constant:12.0],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_valuePill.leadingAnchor constant:-10.0],

        [_noteLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
        [_noteLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_noteLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_valuePill.leadingAnchor constant:-10.0],
        [_noteLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-12.0],

        [_valueLabel.topAnchor constraintEqualToAnchor:_valuePill.topAnchor constant:4.0],
        [_valueLabel.bottomAnchor constraintEqualToAnchor:_valuePill.bottomAnchor constant:-4.0],
        [_valueLabel.leadingAnchor constraintEqualToAnchor:_valuePill.leadingAnchor constant:10.0],
        [_valueLabel.trailingAnchor constraintEqualToAnchor:_valuePill.trailingAnchor constant:-10.0],

        [_valuePill.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_valuePill.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-8.0],

        [_chevronView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12.0],
        [_chevronView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_chevronView.widthAnchor constraintEqualToConstant:14.0],
        [_chevronView.heightAnchor constraintEqualToConstant:14.0]
    ]];
}

- (void)configureWithTitle:(NSString *)title
                     value:(NSString *)value
                valueColor:(UIColor *)valueColor
                    symbol:(NSString *)symbol
                      note:(NSString *)note
                   enabled:(BOOL)enabled {
    _titleLabel.text = title;
    _noteLabel.text = note;
    _valueLabel.text = value;
    _valueLabel.textColor = valueColor ?: PPProviderPrimaryTextColor();
    _valuePill.backgroundColor = [valueColor colorWithAlphaComponent:0.12];

    _iconShell.backgroundColor = [valueColor colorWithAlphaComponent:0.12];
    UIImageSymbolConfiguration *symConf = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    _iconView.image = [[UIImage systemImageNamed:symbol withConfiguration:symConf] imageWithTintColor:valueColor renderingMode:UIImageRenderingModeAlwaysOriginal];

    _chevronView.hidden = !enabled;
}

@end

#pragma mark - Main UserManagementController

@interface UserManagementController () <UITableViewDelegate, UITableViewDataSource> {
    BOOL _hasAppeared;
    BOOL _isSaving;
}

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIView *saveBottomBar;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UILabel *changesCountLabel;

// Custom In-View Navigation Bar
@property (nonatomic, strong) UIView *topNavContainer;
@property (nonatomic, strong) UIButton *navBackButton;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UILabel *navEyebrowLabel;
@property (nonatomic, strong) UIButton *navFastSaveButton;

// State
@property (nonatomic, strong) UserModel *user;
@property (nonatomic, assign) EditType editType;
@property (nonatomic, assign) BOOL showsAccountUI;
@property (nonatomic, assign) BOOL showsPermRoleUI;
@property (nonatomic, assign) BOOL targetIsStaff;

// Editable state copies
@property (nonatomic, copy) NSString *editingAccountStatus;
@property (nonatomic, assign) BOOL editingVerified;
@property (nonatomic, copy) NSString *editingProdectionStatus;
@property (nonatomic, strong) NSMutableDictionary *editingFeatures;
@property (nonatomic, strong) NSMutableDictionary *editingRestrictions;

// Permissions
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL canManageFeatures;
@property (nonatomic, assign) BOOL canManageRestrictions;

// Bento metrics references
@property (nonatomic, strong) UILabel *statusBentoValue;
@property (nonatomic, strong) UILabel *verifiedBentoValue;
@property (nonatomic, strong) UILabel *accessBentoValue;

@end

@implementation UserManagementController

#pragma mark - Init Constructors

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
    self.view.backgroundColor = PPProviderCanvasColor();
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self pp_configureNavigation];
    [self pp_buildTopNavigationBar];
    [self pp_buildTableView];
    [self pp_buildHeaderView];
    [self pp_buildSaveBottomBar];
    [self evaluatePermissions];
    [self pp_updateChangesCount];

    if (self.topNavContainer) {
        [self.view bringSubviewToFront:self.topNavContainer];
    }
    if (self.saveBottomBar) {
        [self.view bringSubviewToFront:self.saveBottomBar];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.hidesInternalNavigationBar) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    } else {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
        if (@available(iOS 13.0, *)) {
            UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
            [appearance configureWithTransparentBackground];
            appearance.backgroundColor = UIColor.clearColor;
            appearance.titleTextAttributes = @{
                NSForegroundColorAttributeName: PPProviderPrimaryTextColor(),
                NSFontAttributeName: PPAppFontBold(18.0)
            };
            appearance.shadowColor = UIColor.clearColor;
            appearance.shadowImage = [[UIImage alloc] init];
            self.navigationItem.standardAppearance = appearance;
            self.navigationItem.scrollEdgeAppearance = appearance;
            self.navigationItem.compactAppearance = appearance;
        }
        self.navigationController.navigationBar.tintColor = PPProviderBrandColor();
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_fitTableHeader];
}

#pragma mark - Custom In-View Navigation Bar

- (void)pp_buildTopNavigationBar {
    if (self.hidesInternalNavigationBar) return;

    _topNavContainer = [UIView new];
    _topNavContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _topNavContainer.backgroundColor = PPProviderSurfaceColor();
    _topNavContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:_topNavContainer];

    // Bottom hairline divider
    UIView *bottomDivider = [UIView new];
    bottomDivider.translatesAutoresizingMaskIntoConstraints = NO;
    bottomDivider.backgroundColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.22];
    [_topNavContainer addSubview:bottomDivider];

    // Content container aligned to safe area
    UIView *barContent = [UIView new];
    barContent.translatesAutoresizingMaskIntoConstraints = NO;
    barContent.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [_topNavContainer addSubview:barContent];

    // 1. Back Button Squircle
    BOOL isModal = (self.presentingViewController != nil && (!self.navigationController || self.navigationController.viewControllers.firstObject == self));
    NSString *backIconName = isModal ? @"xmark" : PPNavBackSymbolName();
    _navBackButton = [self pp_BackButtonWithSystemName:backIconName action:@selector(pp_handleBackOrClose)];
    _navBackButton.accessibilityLabel = isModal ? (kLang(@"Close") ?: @"إغلاق") : (kLang(@"Back") ?: @"رجوع");
    [barContent addSubview:_navBackButton];

    // 2. Title & Eyebrow Stack
    UIView *titleStack = [UIView new];
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    titleStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [barContent addSubview:titleStack];

    UIView *eyebrowRow = [UIView new];
    eyebrowRow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [titleStack addSubview:eyebrowRow];

    _navEyebrowLabel = [UILabel new];
    _navEyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navEyebrowLabel.font = PPAppFontMedium(11.0);
    _navEyebrowLabel.textColor = PPProviderSecondaryTextColor();
    _navEyebrowLabel.textAlignment = [Language alignmentForCurrentLanguage];
    _navEyebrowLabel.text = kLang(@"CommandCenter_Customers_Workspace") ?: @"عمليات العملاء / تفاصيل الحساب";
    [eyebrowRow addSubview:_navEyebrowLabel];

    // Security badge pill
    UIView *shieldBadge = [UIView new];
    shieldBadge.translatesAutoresizingMaskIntoConstraints = NO;
    shieldBadge.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(shieldBadge, 8.0);
    [eyebrowRow addSubview:shieldBadge];

    UIImageView *shieldIcon = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"lock.shield.fill"] imageWithTintColor:[UIColor ppSuccess] renderingMode:UIImageRenderingModeAlwaysOriginal]];
    shieldIcon.translatesAutoresizingMaskIntoConstraints = NO;
    shieldIcon.contentMode = UIViewContentModeScaleAspectFit;
    [shieldBadge addSubview:shieldIcon];

    UILabel *shieldLabel = [UILabel new];
    shieldLabel.translatesAutoresizingMaskIntoConstraints = NO;
    shieldLabel.font = PPAppFontBold(9.5);
    shieldLabel.textColor = [UIColor ppSuccess];
    shieldLabel.text = kLang(@"IAM_Verified") ?: @"مؤمّن";
    [shieldBadge addSubview:shieldLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_navEyebrowLabel.leadingAnchor constraintEqualToAnchor:eyebrowRow.leadingAnchor],
        [_navEyebrowLabel.centerYAnchor constraintEqualToAnchor:eyebrowRow.centerYAnchor],

        [shieldBadge.leadingAnchor constraintEqualToAnchor:_navEyebrowLabel.trailingAnchor constant:6.0],
        [shieldBadge.centerYAnchor constraintEqualToAnchor:eyebrowRow.centerYAnchor],
        [shieldBadge.trailingAnchor constraintLessThanOrEqualToAnchor:eyebrowRow.trailingAnchor],
        [shieldBadge.heightAnchor constraintEqualToConstant:16.0],

        [shieldIcon.leadingAnchor constraintEqualToAnchor:shieldBadge.leadingAnchor constant:5.0],
        [shieldIcon.centerYAnchor constraintEqualToAnchor:shieldBadge.centerYAnchor],
        [shieldIcon.widthAnchor constraintEqualToConstant:9.0],
        [shieldIcon.heightAnchor constraintEqualToConstant:9.0],

        [shieldLabel.leadingAnchor constraintEqualToAnchor:shieldIcon.trailingAnchor constant:3.0],
        [shieldLabel.trailingAnchor constraintEqualToAnchor:shieldBadge.trailingAnchor constant:-5.0],
        [shieldLabel.centerYAnchor constraintEqualToAnchor:shieldBadge.centerYAnchor],

        [eyebrowRow.topAnchor constraintEqualToAnchor:titleStack.topAnchor],
        [eyebrowRow.leadingAnchor constraintEqualToAnchor:titleStack.leadingAnchor],
        [eyebrowRow.trailingAnchor constraintEqualToAnchor:titleStack.trailingAnchor],
        [eyebrowRow.heightAnchor constraintEqualToConstant:16.0]
    ]];

    _navTitleLabel = [UILabel new];
    _navTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navTitleLabel.font = PPAppFontBold(16.5);
    _navTitleLabel.textColor = PPProviderPrimaryTextColor();
    _navTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    _navTitleLabel.text = self.user.UserName.length ? self.user.UserName : (kLang(@"MissionControl_UserDetail_Hero_Title") ?: @"تفاصيل الحساب وإدارة الصلاحيات");
    _navTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleStack addSubview:_navTitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_navTitleLabel.topAnchor constraintEqualToAnchor:eyebrowRow.bottomAnchor constant:1.0],
        [_navTitleLabel.leadingAnchor constraintEqualToAnchor:titleStack.leadingAnchor],
        [_navTitleLabel.trailingAnchor constraintEqualToAnchor:titleStack.trailingAnchor],
        [_navTitleLabel.bottomAnchor constraintEqualToAnchor:titleStack.bottomAnchor]
    ]];

    // 3. Fast Save Pill Button
    _navFastSaveButton = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    [barContent addSubview:_navFastSaveButton];

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [_topNavContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_topNavContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_topNavContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_topNavContainer.bottomAnchor constraintEqualToAnchor:barContent.bottomAnchor],

        [barContent.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [barContent.leadingAnchor constraintEqualToAnchor:_topNavContainer.leadingAnchor constant:PPScreenMargin],
        [barContent.trailingAnchor constraintEqualToAnchor:_topNavContainer.trailingAnchor constant:-PPScreenMargin],
        [barContent.heightAnchor constraintEqualToConstant:54.0],

        [bottomDivider.leadingAnchor constraintEqualToAnchor:_topNavContainer.leadingAnchor],
        [bottomDivider.trailingAnchor constraintEqualToAnchor:_topNavContainer.trailingAnchor],
        [bottomDivider.bottomAnchor constraintEqualToAnchor:_topNavContainer.bottomAnchor],
        [bottomDivider.heightAnchor constraintEqualToConstant:0.5],

        [_navBackButton.leadingAnchor constraintEqualToAnchor:barContent.leadingAnchor],
        [_navBackButton.centerYAnchor constraintEqualToAnchor:barContent.centerYAnchor],
        [_navBackButton.widthAnchor constraintEqualToConstant:44.0],
        [_navBackButton.heightAnchor constraintEqualToConstant:44.0],

        [titleStack.leadingAnchor constraintEqualToAnchor:_navBackButton.trailingAnchor constant:10.0],
        [titleStack.centerYAnchor constraintEqualToAnchor:barContent.centerYAnchor],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:_navFastSaveButton.leadingAnchor constant:-10.0],

        [_navFastSaveButton.trailingAnchor constraintEqualToAnchor:barContent.trailingAnchor],
        [_navFastSaveButton.centerYAnchor constraintEqualToAnchor:barContent.centerYAnchor],
        [_navFastSaveButton.heightAnchor constraintEqualToConstant:38.0]
    ]];
}

- (void)pp_handleBackOrClose {
    [PPFunc pp_playTapEffect];

    UIViewController *targetVC = self;
    while (targetVC.parentViewController && !targetVC.navigationController) {
        targetVC = targetVC.parentViewController;
    }

    if (targetVC.navigationController && targetVC.navigationController.viewControllers.count > 1) {
        [targetVC.navigationController popViewControllerAnimated:YES];
    } else if (targetVC.presentingViewController) {
        [targetVC dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Navigation Setup

- (void)pp_configureNavigation {
    self.title = self.user.UserName.length ? self.user.UserName : (kLang(@"MissionControl_UserDetail_Hero_Title") ?: @"تفاصيل الحساب وإدارة الصلاحيات");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    BOOL isModal = (self.presentingViewController != nil && (!self.navigationController || self.navigationController.viewControllers.firstObject == self));
    if (isModal) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:(kLang(@"Close") ?: @"إغلاق")
                                                                                 style:UIBarButtonItemStylePlain
                                                                                target:self
                                                                                action:@selector(pp_handleBackOrClose)];
    } else {
        UIImage *backImg = [UIImage systemImageNamed:PPNavBackSymbolName()];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:backImg
                                                                                 style:UIBarButtonItemStylePlain
                                                                                target:self
                                                                                action:@selector(pp_handleBackOrClose)];
    }

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:(kLang(@"Save") ?: @"حفظ")
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(onSave)];
}

#pragma mark - Table View Setup

- (void)pp_buildTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = PPProviderCanvasColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, 110.0, 0.0);

    [self.tableView registerClass:PPNextGenSwitchCardCell.class forCellReuseIdentifier:kNextGenSwitchCellID];
    [self.tableView registerClass:PPNextGenPickerCardCell.class forCellReuseIdentifier:kNextGenPickerCellID];
    [self.view addSubview:self.tableView];

    NSLayoutYAxisAnchor *topConstraintAnchor = (self.topNavContainer && !self.hidesInternalNavigationBar)
        ? self.topNavContainer.bottomAnchor
        : self.view.safeAreaLayoutGuide.topAnchor;

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:topConstraintAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

#pragma mark - Header View Building

- (void)pp_buildHeaderView {
    UIView *container = [UIView new];
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    // Main Case Surface
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(card, 24.0);
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.15].CGColor;
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(card);
    [container addSubview:card];

    // User Avatar Shell with Glowing Border & Verified Beacon
    UIView *avatarShell = [UIView new];
    avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    avatarShell.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(avatarShell, 20.0);
    avatarShell.layer.borderWidth = 2.0;
    avatarShell.layer.borderColor = (self.editingVerified ? [UIColor ppSuccess] : PPProviderBrandColor()).CGColor;
    [card addSubview:avatarShell];

    UIImageView *avatar = [[UIImageView alloc] init];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    PPApplyContinuousCorners(avatar, 18.0);
    [avatarShell addSubview:avatar];

    NSURL *imageURL = self.user.UserImageUrl ?: PPURLOrNil(self.user.photoURL);
    if (imageURL) {
        [PPAdminImageLoader setImageWithURLString:imageURL.absoluteString
                                       onImageView:avatar
                                       placeholder:[UIImage systemImageNamed:@"person.crop.circle.fill"]
                                       completion:nil];
    } else {
        UIImageSymbolConfiguration *sym = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightMedium];
        avatar.image = [[UIImage systemImageNamed:@"person.crop.circle.fill" withConfiguration:sym] imageWithTintColor:PPProviderBrandColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
    }

    // Role / Account Type Badge
    UILabel *typeBadge = [UILabel new];
    typeBadge.translatesAutoresizingMaskIntoConstraints = NO;
    typeBadge.font = PPAppFontBold(11.5);
    typeBadge.textColor = PPProviderBrandColor();
    typeBadge.textAlignment = [Language alignmentForCurrentLanguage];
    if (self.targetIsStaff) {
        typeBadge.text = kLang(@"User_Account_Type_Staff") ?: @"🛡️ طاقم إداري";
    } else if ([self.user.accountType.lowercaseString isEqualToString:@"provider"]) {
        typeBadge.text = kLang(@"User_Account_Type_Provider") ?: @"🏪 مزود معتمد";
    } else {
        typeBadge.text = kLang(@"User_Account_Type_Customer") ?: @"👤 عميل مسجل";
    }
    [card addSubview:typeBadge];

    // User Name
    UILabel *nameLabel = [UILabel new];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.font = PPAppFontBold(22.0);
    nameLabel.textColor = PPProviderPrimaryTextColor();
    nameLabel.text = self.user.UserName.length ? self.user.UserName : (kLang(@"MissionControl_UserDetail_Unknown_User") ?: @"حساب غير معروف");
    nameLabel.textAlignment = [Language alignmentForCurrentLanguage];
    nameLabel.numberOfLines = 1;
    [card addSubview:nameLabel];

    // Subtitle Briefing
    UILabel *briefingLabel = [UILabel new];
    briefingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    briefingLabel.font = PPAppFontRegular(13.5);
    briefingLabel.textColor = PPProviderSecondaryTextColor();
    briefingLabel.numberOfLines = 2;
    briefingLabel.text = kLang(@"MissionControl_Customers_Briefing") ?: @"راجع حالة الحساب وإمكانية الوصول والقيود من قائمة تشغيلية مباشرة.";
    briefingLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [card addSubview:briefingLabel];

    // Quick Contact Chips Row (PUID, Email, Phone)
    UIStackView *chipsStack = [UIStackView new];
    chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    chipsStack.axis = UILayoutConstraintAxisHorizontal;
    chipsStack.spacing = 8.0;
    chipsStack.alignment = UIStackViewAlignmentCenter;
    chipsStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:chipsStack];

    __weak typeof(self) weakSelf = self;

    // PUID Chip
    if (self.user.uid.length > 0) {
        NSString *puidShort = self.user.uid;
        UIButton *puidChip = [self pp_buildContactChipWithTitle:[NSString stringWithFormat:@"[ %@ ]", puidShort]
                                                         symbol:@"number"
                                                     actionCopy:puidShort
                                                     toastTitle:(kLang(@"User_ID_Copied") ?: @"تم نسخ معرّف الحساب")];
        [chipsStack addArrangedSubview:puidChip];
    }

    // Email Chip
    if (self.user.UserEmail.length > 0) {
        UIButton *emailChip = [self pp_buildContactChipWithTitle:self.user.UserEmail
                                                          symbol:@"envelope.fill"
                                                      actionCopy:self.user.UserEmail
                                                      toastTitle:(kLang(@"User_Email_Copied") ?: @"تم نسخ البريد الإلكتروني")];
        [chipsStack addArrangedSubview:emailChip];
    }

    // Phone Chip
    if (self.user.MobileNo.length > 0) {
        UIButton *phoneChip = [self pp_buildContactChipWithTitle:self.user.MobileNo
                                                          symbol:@"phone.fill"
                                                      actionCopy:self.user.MobileNo
                                                      toastTitle:(kLang(@"User_Phone_Copied") ?: @"تم نسخ رقم الجوال")];
        [chipsStack addArrangedSubview:phoneChip];
    }

    // 3-Metric Master Bento Horizon
    UIStackView *bentoGrid = [UIStackView new];
    bentoGrid.translatesAutoresizingMaskIntoConstraints = NO;
    bentoGrid.axis = UILayoutConstraintAxisHorizontal;
    bentoGrid.spacing = 8.0;
    bentoGrid.distribution = UIStackViewDistributionFillEqually;
    bentoGrid.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:bentoGrid];

    UIView *m1 = [self pp_buildMetricPillWithTitle:(kLang(@"MissionControl_UserDetail_Readout_Status") ?: @"الحالة")
                                          valueRef:&_statusBentoValue
                                              tint:AccountStatusColor(self.editingAccountStatus)
                                            action:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf.canManage) [strongSelf showAccountStatusPicker];
    }];

    UIView *m2 = [self pp_buildMetricPillWithTitle:(kLang(@"MissionControl_UserDetail_Readout_Verification") ?: @"التحقق")
                                          valueRef:&_verifiedBentoValue
                                              tint:self.editingVerified ? [UIColor ppSuccess] : [UIColor ppTextTertiary]
                                            action:nil];

    UIView *m3 = [self pp_buildMetricPillWithTitle:(kLang(@"MissionControl_UserDetail_Readout_Access") ?: @"الوصول")
                                          valueRef:&_accessBentoValue
                                              tint:PPProviderBrandColor()
                                            action:nil];

    [bentoGrid addArrangedSubview:m1];
    [bentoGrid addArrangedSubview:m2];
    [bentoGrid addArrangedSubview:m3];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],

        [avatarShell.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [avatarShell.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [avatarShell.widthAnchor constraintEqualToConstant:56.0],
        [avatarShell.heightAnchor constraintEqualToConstant:56.0],

        [avatar.topAnchor constraintEqualToAnchor:avatarShell.topAnchor constant:2.0],
        [avatar.leadingAnchor constraintEqualToAnchor:avatarShell.leadingAnchor constant:2.0],
        [avatar.trailingAnchor constraintEqualToAnchor:avatarShell.trailingAnchor constant:-2.0],
        [avatar.bottomAnchor constraintEqualToAnchor:avatarShell.bottomAnchor constant:-2.0],

        [typeBadge.topAnchor constraintEqualToAnchor:avatarShell.topAnchor],
        [typeBadge.leadingAnchor constraintEqualToAnchor:avatarShell.trailingAnchor constant:14.0],
        [typeBadge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [nameLabel.topAnchor constraintEqualToAnchor:typeBadge.bottomAnchor constant:2.0],
        [nameLabel.leadingAnchor constraintEqualToAnchor:typeBadge.leadingAnchor],
        [nameLabel.trailingAnchor constraintEqualToAnchor:typeBadge.trailingAnchor],

        [briefingLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:3.0],
        [briefingLabel.leadingAnchor constraintEqualToAnchor:typeBadge.leadingAnchor],
        [briefingLabel.trailingAnchor constraintEqualToAnchor:typeBadge.trailingAnchor],

        [chipsStack.topAnchor constraintEqualToAnchor:avatarShell.bottomAnchor constant:14.0],
        [chipsStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [chipsStack.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14.0],
        [chipsStack.heightAnchor constraintEqualToConstant:30.0],

        [bentoGrid.topAnchor constraintEqualToAnchor:chipsStack.bottomAnchor constant:14.0],
        [bentoGrid.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [bentoGrid.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [bentoGrid.heightAnchor constraintEqualToConstant:58.0],
        [bentoGrid.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
    ]];

    self.headerContainer = container;
    self.tableView.tableHeaderView = container;
    [self pp_refreshBentoReadouts];
    [self pp_fitTableHeader];
}

- (UIButton *)pp_buildContactChipWithTitle:(NSString *)title symbol:(NSString *)symbol actionCopy:(NSString *)copyValue toastTitle:(NSString *)toastTitle {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [[UIColor whiteColor] colorWithAlphaComponent:0.07]
            : [[UIColor blackColor] colorWithAlphaComponent:0.04];
    }];
    PPApplyContinuousCorners(btn, 10.0);

    NSString *display = [NSString stringWithFormat:@" %@ ", title];
    [btn setTitle:display forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightMedium];
    [btn setTitleColor:PPProviderSecondaryTextColor() forState:UIControlStateNormal];

    UIImageSymbolConfiguration *sConf = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold];
    [btn setImage:[[UIImage systemImageNamed:symbol withConfiguration:sConf] imageWithTintColor:PPProviderSecondaryTextColor() renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    btn.tintColor = PPProviderSecondaryTextColor();

    __weak typeof(self) weakSelf = self;
    [btn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        UIPasteboard.generalPasteboard.string = copyValue;
        [PPAlertHelper showSuccessIn:self title:toastTitle subtitle:nil];
        [PPFunc pp_playSuccessEffect];
    }] forControlEvents:UIControlEventTouchUpInside];

    return btn;
}

- (UIView *)pp_buildMetricPillWithTitle:(NSString *)title valueRef:(UILabel * __strong *)valueRef tint:(UIColor *)tint action:(nullable void (^)(void))action {
    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [tint colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(pill, 14.0);

    UILabel *valLbl = [UILabel new];
    valLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valLbl.font = PPAppFontBold(14.5);
    valLbl.textColor = tint;
    valLbl.textAlignment = NSTextAlignmentCenter;
    valLbl.text = @"-";
    [pill addSubview:valLbl];
    *valueRef = valLbl;

    UILabel *titLbl = [UILabel new];
    titLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titLbl.font = PPAppFontMedium(11.0);
    titLbl.textColor = PPProviderSecondaryTextColor();
    titLbl.textAlignment = NSTextAlignmentCenter;
    titLbl.text = title;
    [pill addSubview:titLbl];

    [NSLayoutConstraint activateConstraints:@[
        [valLbl.topAnchor constraintEqualToAnchor:pill.topAnchor constant:9.0],
        [valLbl.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],

        [titLbl.topAnchor constraintEqualToAnchor:valLbl.bottomAnchor constant:1.0],
        [titLbl.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
        [titLbl.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-9.0]
    ]];

    if (action) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pp_bentoTapped)];
        pill.userInteractionEnabled = YES;
        [pill addGestureRecognizer:tap];
    }

    return pill;
}

- (void)pp_bentoTapped {
    if (self.canManage) [self showAccountStatusPicker];
}

- (void)pp_refreshBentoReadouts {
    self.statusBentoValue.text = AccountStatusLabel(self.editingAccountStatus);
    self.statusBentoValue.textColor = AccountStatusColor(self.editingAccountStatus);
    self.statusBentoValue.superview.backgroundColor = [AccountStatusColor(self.editingAccountStatus) colorWithAlphaComponent:0.08];

    self.verifiedBentoValue.text = VerificationStatusLabel(self.editingVerified);
    self.verifiedBentoValue.textColor = self.editingVerified ? [UIColor ppSuccess] : [UIColor ppTextTertiary];

    NSInteger activeFeatures = 0;
    for (NSInteger i = 0; i < kFeatureCount; i++) {
        if ([self.editingFeatures[kAllFeatures[i].key] boolValue]) activeFeatures++;
    }
    NSInteger activeRestrictions = 0;
    for (NSInteger i = 0; i < kRestrictionCount; i++) {
        if ([self.editingRestrictions[kRestrictions[i].key] boolValue]) activeRestrictions++;
    }

    self.accessBentoValue.text = [NSString stringWithFormat:@"%lu ميزة · %lu قيود", (unsigned long)activeFeatures, (unsigned long)activeRestrictions];
    self.accessBentoValue.textColor = activeRestrictions > 0 ? [UIColor systemRedColor] : PPProviderBrandColor();
}

- (void)pp_fitTableHeader {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (!self.headerContainer || width <= 0.0) return;
    self.headerContainer.frame = CGRectMake(0.0, 0.0, width, MAX(self.headerContainer.frame.size.height, 1.0));
    CGSize size = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.headerContainer.frame.size.height - ceil(size.height)) > 0.5) {
        self.headerContainer.frame = CGRectMake(0.0, 0.0, width, ceil(size.height));
        self.tableView.tableHeaderView = self.headerContainer;
    }
}

#pragma mark - Save Bottom Bar

- (void)pp_buildSaveBottomBar {
    _saveBottomBar = [UIView new];
    _saveBottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    _saveBottomBar.backgroundColor = PPProviderSurfaceColor();
    _saveBottomBar.layer.borderWidth = 1.0;
    _saveBottomBar.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.18].CGColor;
    _saveBottomBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(_saveBottomBar);
    [self.view addSubview:_saveBottomBar];

    _changesCountLabel = [UILabel new];
    _changesCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _changesCountLabel.font = PPAppFontMedium(12.5);
    _changesCountLabel.textColor = PPProviderSecondaryTextColor();
    _changesCountLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [_saveBottomBar addSubview:_changesCountLabel];

    _saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    _saveButton.backgroundColor = PPProviderBrandColor();
    [_saveButton setTitle:(kLang(@"MissionControl_UserDetail_Save") ?: @"حفظ التغييرات المصرّح بها") forState:UIControlStateNormal];
    [_saveButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _saveButton.titleLabel.font = PPAppFontBold(16.0);
    PPApplyContinuousCorners(_saveButton, 16.0);
    [_saveButton addTarget:self action:@selector(onSave) forControlEvents:UIControlEventTouchUpInside];
    [_saveBottomBar addSubview:_saveButton];

    [NSLayoutConstraint activateConstraints:@[
        [_saveBottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_saveBottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_saveBottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_changesCountLabel.topAnchor constraintEqualToAnchor:_saveBottomBar.topAnchor constant:10.0],
        [_changesCountLabel.leadingAnchor constraintEqualToAnchor:_saveBottomBar.leadingAnchor constant:PPScreenMargin],
        [_changesCountLabel.trailingAnchor constraintEqualToAnchor:_saveBottomBar.trailingAnchor constant:-PPScreenMargin],

        [_saveButton.topAnchor constraintEqualToAnchor:_changesCountLabel.bottomAnchor constant:8.0],
        [_saveButton.leadingAnchor constraintEqualToAnchor:_saveBottomBar.leadingAnchor constant:PPScreenMargin],
        [_saveButton.trailingAnchor constraintEqualToAnchor:_saveBottomBar.trailingAnchor constant:-PPScreenMargin],
        [_saveButton.heightAnchor constraintEqualToConstant:50.0],
        [_saveButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10.0]
    ]];
}

- (void)pp_updateChangesCount {
    NSUInteger changes = 0;
    NSString *origStatus = self.user.accountStatus.length ? self.user.accountStatus : (self.user.isBlocked ? @"blocked" : @"active");
    if (![self.editingAccountStatus isEqualToString:origStatus]) changes++;

    for (NSInteger i = 0; i < kFeatureCount; i++) {
        NSString *k = kAllFeatures[i].key;
        NSNumber *orig = self.user.features[k] ?: @(NO);
        NSNumber *edit = self.editingFeatures[k] ?: @(NO);
        if (orig.boolValue != edit.boolValue) changes++;
    }

    for (NSInteger i = 0; i < kRestrictionCount; i++) {
        NSString *k = kRestrictions[i].key;
        NSNumber *orig = self.user.restrictions[k] ?: @(NO);
        NSNumber *edit = self.editingRestrictions[k] ?: @(NO);
        if (orig.boolValue != edit.boolValue) changes++;
    }

    if (changes > 0) {
        _changesCountLabel.text = [NSString stringWithFormat:kLang(@"Unsaved_Changes_Count_Format") ?: @"تم تعديل %lu حقول · اضغط للحفظ", (unsigned long)changes];
        _changesCountLabel.textColor = PPProviderBrandColor();
        [_navFastSaveButton setTitle:[NSString stringWithFormat:@"%@ (%lu)", (kLang(@"Save") ?: @"حفظ"), (unsigned long)changes] forState:UIControlStateNormal];
        _navFastSaveButton.alpha = 1.0;
    } else {
        _changesCountLabel.text = kLang(@"MissionControl_Customers_Signal_Clear") ?: @"لا توجد تغييرات معلقة";
        _changesCountLabel.textColor = PPProviderSecondaryTextColor();
        [_navFastSaveButton setTitle:(kLang(@"Save") ?: @"حفظ") forState:UIControlStateNormal];
        _navFastSaveButton.alpha = 0.88;
    }
}

#pragma mark - Permissions

- (void)evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    self.canManage = !self.targetIsStaff && [staff hasPermission:kStaffPermUsersManage];
    self.canManageFeatures = [staff hasPermission:kStaffPermUsersFeaturesManage];
    self.canManageRestrictions = [staff hasPermission:kStaffPermUsersRestrictionsManage];

    BOOL canSaveAny = self.canManage || self.canManageFeatures || self.canManageRestrictions;
    self.saveBottomBar.hidden = !canSaveAny;
    self.navFastSaveButton.hidden = !canSaveAny;
}

#pragma mark - Table View Data Source

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

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [UIView new];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = PPAppFontBold(16.5);
    label.textColor = (section == SectionRestrictions) ? [UIColor systemRedColor] : PPProviderPrimaryTextColor();
    label.textAlignment = [Language alignmentForCurrentLanguage];

    NSString *title = @"";
    switch ((SectionType)section) {
        case SectionAccount:
            title = kLang(@"MissionControl_UserDetail_Account_Header") ?: @"🏛️ نظرة عامة وبيانات الحساب";
            break;
        case SectionFeatures:
            title = kLang(@"MissionControl_UserDetail_Features_Header") ?: @"⚡ صلاحيات وميزات المنصة";
            break;
        case SectionRestrictions:
            title = kLang(@"MissionControl_UserDetail_Sanctions_Header") ?: @"🛡️ درع الأمان والقيود الإدارية";
            break;
    }
    label.text = title;
    [header addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:16.0],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8.0]
    ]];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 46.0;
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
            return [UITableViewCell new];
    }
}

#pragma mark - Account Cells

- (UITableViewCell *)accountCellForRow:(NSInteger)row {
    PPNextGenPickerCardCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kNextGenPickerCellID];
    switch ((AccountRow)row) {
        case AccountRowStatus: {
            NSString *label = AccountStatusLabel(self.editingAccountStatus);
            UIColor *color = AccountStatusColor(self.editingAccountStatus);
            NSString *note = self.canManage ? nil : (kLang(@"MissionControl_UserDetail_Permission_ReadOnly") ?: @"للقراءة فقط: يلزم إذن إدارة العملاء.");
            [cell configureWithTitle:(kLang(@"MissionControl_UserDetail_Account_Status") ?: @"حالة الحساب")
                               value:label
                          valueColor:color
                              symbol:@"person.badge.shield.checkmark.fill"
                                note:note
                             enabled:self.canManage];
            return cell;
        }
        case AccountRowVerified: {
            UIColor *color = self.editingVerified ? [UIColor ppSuccess] : [UIColor ppTextTertiary];
            [cell configureWithTitle:(kLang(@"MissionControl_UserDetail_Verification") ?: @"التوثيق")
                               value:VerificationStatusLabel(self.editingVerified)
                          valueColor:color
                              symbol:@"checkmark.seal.fill"
                                note:(kLang(@"MissionControl_UserDetail_ServerManaged") ?: @"للقراءة فقط · تتم إدارته من الخادم")
                             enabled:NO];
            return cell;
        }
        case AccountRowProtection: {
            UIColor *color = [self.editingProdectionStatus isEqualToString:@"active"] ? [UIColor ppSuccess] : [UIColor ppTextTertiary];
            [cell configureWithTitle:(kLang(@"MissionControl_UserDetail_Protection") ?: @"الحماية")
                               value:ProtectionStatusLabel(self.editingProdectionStatus)
                          valueColor:color
                              symbol:@"shield.fill"
                                note:(kLang(@"MissionControl_UserDetail_ServerManaged") ?: @"للقراءة فقط · تتم إدارته من الخادم")
                             enabled:NO];
            return cell;
        }
        default:
            return [UITableViewCell new];
    }
}

#pragma mark - Features & Restrictions Cells

- (UITableViewCell *)featureCellForRow:(NSInteger)row {
    PPFeatureDef def = kAllFeatures[row];
    BOOL isOn = [self.editingFeatures[def.key] boolValue];
    BOOL isServerDisabled = [def.key isEqualToString:@"canDelivery"];
    BOOL enabled = self.canManageFeatures && !isServerDisabled;

    PPNextGenSwitchCardCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kNextGenSwitchCellID];
    [cell configureWithTitle:kLang(def.labelKey)
                 description:kLang(def.descKey)
                      symbol:def.symbol
                   tintColor:PPColorForIndex(def.colorIndex)
                        isOn:isOn
                     enabled:enabled
            isServerDisabled:isServerDisabled
               isRestriction:NO];

    __weak typeof(self) weakSelf = self;
    cell.onToggle = ^(BOOL val) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.editingFeatures[def.key] = @(val);
        [self pp_refreshBentoReadouts];
        [self pp_updateChangesCount];
    };

    return cell;
}

- (UITableViewCell *)restrictionCellForRow:(NSInteger)row {
    PPRestrictionDef def = kRestrictions[row];
    BOOL isOn = [self.editingRestrictions[def.key] boolValue];

    PPNextGenSwitchCardCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kNextGenSwitchCellID];
    [cell configureWithTitle:kLang(def.labelKey)
                 description:kLang(def.descKey)
                      symbol:def.symbol
                   tintColor:[UIColor systemRedColor]
                        isOn:isOn
                     enabled:self.canManageRestrictions
            isServerDisabled:NO
               isRestriction:YES];

    __weak typeof(self) weakSelf = self;
    cell.onToggle = ^(BOOL val) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.editingRestrictions[def.key] = @(val);
        [self pp_refreshBentoReadouts];
        [self pp_updateChangesCount];
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:SectionRestrictions]] withRowAnimation:UITableViewRowAnimationNone];
    };

    return cell;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == SectionAccount && indexPath.row == AccountRowStatus && self.canManage) {
        [self showAccountStatusPicker];
    }
}

- (void)showAccountStatusPicker {
    [PPFunc pp_playSelectionEffect];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:(kLang(@"MissionControl_UserDetail_Account_Status") ?: @"حالة الحساب")
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

    [sheet addAction:[UIAlertAction actionWithTitle:(kLang(@"Cancel") ?: @"إلغاء") style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        CGRect cellRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:AccountRowStatus inSection:SectionAccount]];
        sheet.popoverPresentationController.sourceRect = cellRect;
        sheet.popoverPresentationController.sourceView = self.tableView;
    }

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)didSelectAccountStatus:(NSString *)status {
    self.editingAccountStatus = status;
    [self pp_refreshBentoReadouts];
    [self pp_updateChangesCount];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:AccountRowStatus inSection:SectionAccount]]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
    [PPFunc pp_playSelectionEffect];
}

#pragma mark - Save Operations

- (void)onSave {
    [PPFunc pp_playTapEffect];
    if (_isSaving) return;
    _isSaving = YES;

    [self.saveButton setTitle:(kLang(@"MissionControl_UserDetail_Saving") ?: @"جارٍ حفظ التغييرات...") forState:UIControlStateNormal];
    self.saveButton.userInteractionEnabled = NO;
    [self.navFastSaveButton setTitle:(kLang(@"MissionControl_UserDetail_Saving") ?: @"جارٍ الحفظ...") forState:UIControlStateNormal];
    self.navFastSaveButton.userInteractionEnabled = NO;
    [PPHUD showRingIn:self.view
                title:(kLang(@"MissionControl_UserDetail_Saving") ?: @"جارٍ حفظ التغييرات")
             subtitle:(kLang(@"MissionControl_UserDetail_Saving_Body") ?: @"جارٍ تطبيق كل تغيير مصرح به عبر خدمات خاضعة للتدقيق.")];

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

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [PPHUD dismiss];
        self->_isSaving = NO;
        [self.saveButton setTitle:(kLang(@"MissionControl_UserDetail_Save") ?: @"حفظ التغييرات المصرّح بها") forState:UIControlStateNormal];
        self.saveButton.userInteractionEnabled = self.canManage || self.canManageFeatures || self.canManageRestrictions;
        [self.navFastSaveButton setTitle:(kLang(@"Save") ?: @"حفظ") forState:UIControlStateNormal];
        self.navFastSaveButton.userInteractionEnabled = self.canManage || self.canManageFeatures || self.canManageRestrictions;

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
            [self pp_refreshBentoReadouts];
            [self pp_updateChangesCount];
            [self.tableView reloadData];
            [PPFunc pp_playErrorEffect];
            [PPToast toast:lastError.localizedDescription style:PPToastStyleError haptic:YES duration:3.0];
            [PPAlertHelper showErrorIn:self title:(kLang(@"Update_Error") ?: @"خطأ في التحديث") subtitle:lastError.localizedDescription];
        } else {
            [PPFunc pp_playSuccessEffect];
            [PPToast toast:(kLang(@"Update_Success") ?: @"تم حفظ التغييرات بنجاح") style:PPToastStyleSuccess haptic:YES duration:2.0];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pp_handleBackOrClose];
            });
        }
    });
}

@end
