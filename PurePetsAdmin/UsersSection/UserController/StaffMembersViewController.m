//
//  StaffMembersViewController.m
//  PurePetsAdmin
//

#import "StaffMembersViewController.h"
#import "UserModel.h"
#import "PPStaffAuth.h"
#import "Styling.h"
#import "Language.h"
#import "AddUserViewController.h"
#import "AdminService.h"
#import "PPToast.h"
#import "AlertHelper.h"
#import "PPDesignTokens.h"
@import Firebase;
@import FirebaseAuth;

static NSString * const PPStaffMemberCardCellID = @"PPStaffMemberCardCell";

typedef NS_ENUM(NSUInteger, PPStaffMembersListState) {
    PPStaffMembersListStateContent,
    PPStaffMembersListStateLoading,
    PPStaffMembersListStateListenerError,
    PPStaffMembersListStateAccessDenied,
    PPStaffMembersListStateSourceEmpty,
    PPStaffMembersListStateFilteredEmpty,
};

static UIFont *PPStaffMembersScaledFont(UIFont *baseFont, UIFontTextStyle textStyle) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
    }
    return baseFont;
}

static UIColor *PPStaffMembersSurfaceColor(void) {
    return [UIColor ppSurface];
}

static UIColor *PPStaffMembersBackgroundColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPStaffMembersPrimaryColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPStaffMembersPrimaryTextColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPStaffMembersSecondaryTextColor(void) {
    return [UIColor ppTextSecondary];
}

static UIColor *PPStaffMembersBorderColor(void) {
    return [UIColor ppSurfaceBorder];
}

static NSString *PPStaffMembersSafeString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if ([value isKindOfClass:NSNumber.class]) {
        return [(NSNumber *)value stringValue];
    }
    return @"";
}

static NSDictionary *PPStaffMembersSafeDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : @{};
}

static UserModel *PPStaffMembersUserModelFromStaffDoc(PPStaffDoc *staff) {
    if (!staff.uid.length) return nil;

    NSMutableDictionary *profile = [@{
        @"role": staff.roleIdentifier ?: PPStaffRoleViewer,
        @"status": staff.status ?: PPStaffStatusDisabled,
        @"permissions": staff.permissions ?: @[],
        @"scope": staff.scope ?: @{}
    } mutableCopy];
    if (staff.roleName.length) profile[@"roleName"] = staff.roleName;

    NSMutableDictionary *values = [@{
        @"ID": staff.uid,
        @"uid": staff.uid,
        @"accountType": @"staff",
        @"staffRole": staff.roleIdentifier ?: PPStaffRoleViewer,
        @"staffProfile": profile,
        @"accountStatus": staff.status ?: PPStaffStatusDisabled,
        @"verified": @(staff.isVerified)
    } mutableCopy];
    if (staff.displayName.length) {
        values[@"UserName"] = staff.displayName;
        values[@"displayName"] = staff.displayName;
    }
    if (staff.email.length) {
        values[@"UserEmail"] = staff.email;
        values[@"email"] = staff.email;
    }
    if (staff.phone.length) values[@"MobileNo"] = staff.phone;
    if (staff.photoURL.length) {
        values[@"UserImageUrl"] = staff.photoURL;
        values[@"photoURL"] = staff.photoURL;
    }
    return [[UserModel alloc] initWithDict:values];
}

static NSString *PPStaffMembersLocalizedCount(NSUInteger count) {
    return [NSNumberFormatter localizedStringFromNumber:@(count) numberStyle:NSNumberFormatterDecimalStyle];
}

static NSString *PPStaffMembersLTRIsolate(NSString *value) {
    NSString *safe = PPStaffMembersSafeString(value);
    return safe.length ? [NSString stringWithFormat:@"\u2066%@\u2069", safe] : @"";
}

static NSString *PPStaffMembersResolvedStatus(UserModel *user) {
    NSDictionary *profile = PPStaffMembersSafeDictionary(user.staffProfile);
    NSString *status = PPStaffMembersSafeString(profile[@"status"]).lowercaseString;
    if ([status isEqualToString:PPStaffStatusActive] || [status isEqualToString:PPStaffStatusDisabled]) return status;
    NSString *accountStatus = PPStaffMembersSafeString(user.accountStatus).lowercaseString;
    if (user.isBlocked || [accountStatus isEqualToString:@"blocked"]) return @"blocked";
    if ([accountStatus isEqualToString:@"disabled"]) return PPStaffStatusDisabled;
    return PPStaffStatusDisabled;
}

static NSString *PPStaffMembersStatusText(UserModel *user) {
    NSString *status = PPStaffMembersResolvedStatus(user);
    if ([status isEqualToString:@"blocked"]) {
        return kLang(@"Blocked");
    }
    if ([status isEqualToString:PPStaffStatusDisabled]) {
        return kLang(@"Disabled");
    }
    if ([status isEqualToString:@"pending_review"]) {
        return kLang(@"Pending Review");
    }
    return [status isEqualToString:PPStaffStatusActive] ? kLang(@"Active") : kLang(@"Disabled");
}

static UIColor *PPStaffMembersStatusColor(UserModel *user) {
    NSString *status = PPStaffMembersResolvedStatus(user);
    if ([status isEqualToString:@"blocked"]) {
        return [UIColor ppError];
    }
    if ([status isEqualToString:PPStaffStatusDisabled]) {
        return [UIColor ppTextSecondary];
    }
    if ([status isEqualToString:@"pending_review"]) {
        return [UIColor ppWarning];
    }
    return [status isEqualToString:PPStaffStatusActive] ? [UIColor ppSuccess] : [UIColor ppTextSecondary];
}

static BOOL PPStaffMembersIsBuiltInRole(NSString *role) {
    static NSSet<NSString *> *roles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        roles = [NSSet setWithArray:@[
            PPStaffRoleSuperAdmin, PPStaffRoleOwner, PPStaffRoleOperationsManager,
            PPStaffRoleInventoryManager, PPStaffRolePaymentsManager,
            PPStaffRoleSupportAgent, PPStaffRoleViewer,
            @"SuperAdmin", @"Owner", @"Accountant", @"InventoryManager", @"Staff", @"Viewer"
        ]];
    });
    return [roles containsObject:role];
}

static NSString *PPStaffMembersRoleText(UserModel *user) {
    NSDictionary *profile = PPStaffMembersSafeDictionary(user.staffProfile);
    NSString *roleName = PPStaffMembersSafeString(profile[@"roleName"]);
    if (roleName.length > 0) return roleName;
    NSString *role = PPStaffMembersSafeString(user.staffRole);
    if (role.length == 0) role = PPStaffMembersSafeString(profile[@"role"]);
    if (role.length > 0) {
        return PPStaffMembersIsBuiltInRole(role)
            ? [PPStaffAuth localizedRoleName:(PPStaffRole)role]
            : role;
    }
    if (user.isSuperAdmin) {
        return [PPStaffAuth localizedRoleName:PPStaffRoleSuperAdmin];
    }
    if (user.isAdmin) {
        PPStaffRole legacyRole = [PPStaffAuth staffRoleFromLegacyRole:user.role];
        return [legacyRole isEqualToString:PPStaffRoleViewer]
            ? kLang(@"Role_Admin")
            : [PPStaffAuth localizedRoleName:legacyRole];
    }
    return [PPStaffAuth localizedRoleName:PPStaffRoleViewer];
}

@interface PPStaffMemberTagLabel : UILabel
- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha;
@end

@implementation PPStaffMemberTagLabel

- (instancetype)init {
    if (self = [super init]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.font = PPStaffMembersScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
        self.textAlignment = NSTextAlignmentNatural;
        self.adjustsFontForContentSizeCategory = YES;
        self.numberOfLines = 1;
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:PPSpaceLG]
        ]];
    }
    return self;
}

- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha {
    (void)fillAlpha;
    self.text = text;
    self.textColor = tintColor;
    self.backgroundColor = UIColor.clearColor;
    self.hidden = text.length == 0;
}

@end

@interface PPStaffMemberCardCell : UITableViewCell
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *statusRailView;
@property (nonatomic, strong) UIView *avatarShellView;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIStackView *tagsStackView;
@property (nonatomic, strong) PPStaffMemberTagLabel *statusTagLabel;
@property (nonatomic, strong) PPStaffMemberTagLabel *roleTagLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, copy) NSString *representedUID;
@property (nonatomic, assign) BOOL actionable;
- (void)configureWithUser:(UserModel *)user actionable:(BOOL)actionable;
@end

@implementation PPStaffMemberCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        _surfaceView = [[UIView alloc] init];
        _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
        _surfaceView.backgroundColor = PPStaffMembersSurfaceColor();
        _surfaceView.layer.cornerRadius = PPCornerSmall;
        _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _surfaceView.layer.borderColor = PPStaffMembersBorderColor().CGColor;
        _surfaceView.layer.shadowOpacity = 0.0;

        _statusRailView = [[UIView alloc] init];
        _statusRailView.translatesAutoresizingMaskIntoConstraints = NO;
        _statusRailView.backgroundColor = [UIColor ppSuccess];
        _statusRailView.layer.cornerRadius = PPSpaceXXS;
        _statusRailView.isAccessibilityElement = NO;

        _avatarShellView = [[UIView alloc] init];
        _avatarShellView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarShellView.backgroundColor = [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.12];
        _avatarShellView.layer.cornerRadius = PPCornerCard;

        _avatarImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarImageView.tintColor = PPStaffMembersPrimaryColor();
        _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarImageView.layer.cornerRadius = PPSpaceLG;
        _avatarImageView.clipsToBounds = YES;
        _avatarImageView.isAccessibilityElement = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = PPStaffMembersScaledFont([Styling fontBold:PPFontHeadline], UIFontTextStyleHeadline);
        _titleLabel.textColor = PPStaffMembersPrimaryTextColor();
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _titleLabel.numberOfLines = 2;
        _titleLabel.adjustsFontForContentSizeCategory = YES;

        UIImageSymbolConfiguration *verifiedConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        _verifiedBadgeView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill" withConfiguration:verifiedConfig]];
        _verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _verifiedBadgeView.tintColor = [UIColor ppInfo];
        _verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;
        _verifiedBadgeView.hidden = YES;
        _verifiedBadgeView.isAccessibilityElement = NO;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = PPStaffMembersScaledFont([Styling fontRegular:PPFontFootnote], UIFontTextStyleFootnote);
        _subtitleLabel.textColor = PPStaffMembersSecondaryTextColor();
        _subtitleLabel.textAlignment = NSTextAlignmentNatural;
        _subtitleLabel.numberOfLines = 0;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;

        _statusTagLabel = [[PPStaffMemberTagLabel alloc] init];
        _statusTagLabel.font = PPStaffMembersScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote);
        _roleTagLabel = [[PPStaffMemberTagLabel alloc] init];

        _tagsStackView = [[UIStackView alloc] initWithArrangedSubviews:@[_statusTagLabel, _roleTagLabel]];
        _tagsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _tagsStackView.axis = UILayoutConstraintAxisHorizontal;
        _tagsStackView.alignment = UIStackViewAlignmentLeading;
        _tagsStackView.spacing = PPSpaceSM;
        _tagsStackView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        UIImageSymbolConfiguration *chevronConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:chevronConfig]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.tintColor = [PPStaffMembersSecondaryTextColor() colorWithAlphaComponent:0.72];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;

        [self.contentView addSubview:_surfaceView];
        [_surfaceView addSubview:_statusRailView];
        [_surfaceView addSubview:_avatarShellView];
        [_avatarShellView addSubview:_avatarImageView];
        [_surfaceView addSubview:_titleLabel];
        [_surfaceView addSubview:_verifiedBadgeView];
        [_surfaceView addSubview:_subtitleLabel];
        [_surfaceView addSubview:_tagsStackView];
        [_surfaceView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceXXS],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceBase],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceBase],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceXXS],

            [_statusRailView.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceSM],
            [_statusRailView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor],
            [_statusRailView.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceSM],
            [_statusRailView.widthAnchor constraintEqualToConstant:PPSpaceXS],

            [_avatarShellView.leadingAnchor constraintEqualToAnchor:_statusRailView.trailingAnchor constant:PPSpaceMD],
            [_avatarShellView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_avatarShellView.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
            [_avatarShellView.heightAnchor constraintEqualToConstant:PPTouchTargetMin],

            [_avatarImageView.centerXAnchor constraintEqualToAnchor:_avatarShellView.centerXAnchor],
            [_avatarImageView.centerYAnchor constraintEqualToAnchor:_avatarShellView.centerYAnchor],
            [_avatarImageView.widthAnchor constraintEqualToConstant:PPSpaceXXXL],
            [_avatarImageView.heightAnchor constraintEqualToConstant:PPSpaceXXXL],

            [_chevronView.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-PPSpaceMD],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:PPSpaceBase],
            [_chevronView.heightAnchor constraintEqualToConstant:PPSpaceBase],

            [_titleLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceMD],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_avatarShellView.trailingAnchor constant:PPSpaceMD],

            [_verifiedBadgeView.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:PPSpaceMDHalf],
            [_verifiedBadgeView.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_verifiedBadgeView.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-PPSpaceMD],
            [_verifiedBadgeView.widthAnchor constraintEqualToConstant:PPSpaceBase],
            [_verifiedBadgeView.heightAnchor constraintEqualToConstant:PPSpaceBase],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-PPSpaceMD],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],

            [_tagsStackView.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_tagsStackView.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:PPSpaceSM],
            [_tagsStackView.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-PPSpaceMD],
            [_tagsStackView.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceMD]
        ]];

        [self pp_updateMetadataAxis];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self pp_updateMetadataAxis];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.surfaceView.backgroundColor = PPStaffMembersSurfaceColor();
        self.surfaceView.layer.borderColor = PPStaffMembersBorderColor().CGColor;
    }
}

- (void)pp_updateMetadataAxis {
    BOOL accessibilityCategory = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    self.tagsStackView.axis = accessibilityCategory ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.tagsStackView.spacing = accessibilityCategory ? PPSpaceXS : PPSpaceSM;
    self.titleLabel.numberOfLines = accessibilityCategory ? 0 : 2;
    self.statusTagLabel.numberOfLines = accessibilityCategory ? 0 : 1;
    self.roleTagLabel.numberOfLines = accessibilityCategory ? 0 : 1;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedUID = nil;
    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.verifiedBadgeView.hidden = YES;
    self.roleTagLabel.hidden = YES;
    self.statusRailView.backgroundColor = [UIColor ppSuccess];
    self.actionable = NO;
    self.surfaceView.transform = CGAffineTransformIdentity;
    self.surfaceView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
    self.contentView.alpha = 1.0;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [self pp_updateInteractionStateHighlighted:highlighted];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [self pp_updateInteractionStateHighlighted:selected];
}

- (void)pp_updateInteractionStateHighlighted:(BOOL)highlighted {
    if (!self.actionable) {
        self.surfaceView.alpha = 1.0;
        self.surfaceView.transform = CGAffineTransformIdentity;
        return;
    }
    CGFloat scale = highlighted ? 0.985 : 1.0;
    CGFloat alpha = highlighted ? 0.96 : 1.0;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.surfaceView.alpha = alpha;
        return;
    }
    [UIView animateWithDuration:PPAnimDurationFast
                          delay:0.0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.surfaceView.transform = CGAffineTransformMakeScale(scale, scale);
        self.surfaceView.alpha = alpha;
    } completion:nil];
}

- (void)configureWithUser:(UserModel *)user actionable:(BOOL)actionable {
    self.representedUID = user.uid;
    self.actionable = actionable;
    self.selectionStyle = actionable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    self.chevronView.hidden = !actionable;

    NSString *displayName = PPStaffMembersSafeString(user.UserName);
    NSString *email = PPStaffMembersSafeString(user.UserEmail);
    NSString *phone = PPStaffMembersSafeString(user.MobileNo);

    self.titleLabel.text = displayName.length ? displayName : (email.length ? email : @"—");
    self.verifiedBadgeView.hidden = !user.isVerified;

    if (email.length && phone.length) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"%@\n%@", email, phone];
    } else if (email.length) {
        self.subtitleLabel.text = email;
    } else if (phone.length) {
        self.subtitleLabel.text = phone;
    } else {
        self.subtitleLabel.text = user.uid.length ? user.uid : @"—";
    }

    UIColor *statusTint = PPStaffMembersStatusColor(user);
    self.statusRailView.backgroundColor = statusTint;
    [self.statusTagLabel applyWithText:PPStaffMembersStatusText(user) tintColor:statusTint fillAlpha:0.14];
    NSString *role = PPStaffMembersRoleText(user);
    [self.roleTagLabel applyWithText:role tintColor:PPStaffMembersSecondaryTextColor() fillAlpha:0.0];

    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    if (user.UserImageUrl.absoluteString.length > 0) {
        [self.avatarImageView setImageFromUrl:user.UserImageUrl.absoluteString Blr:NO Shimmering:NO];
    }

    NSString *status = PPStaffMembersStatusText(user);
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithArray:@[
        self.titleLabel.text ?: @"",
        PPStaffMembersLTRIsolate(self.subtitleLabel.text),
        status ?: @"",
        role ?: @""
    ]];
    if (user.isVerified) [parts addObject:kLang(@"Verified_Users")];
    self.accessibilityLabel = [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@", "];
    self.accessibilityHint = actionable ? kLang(@"Staff_EditMember_Title") : nil;
    self.accessibilityTraits = actionable ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
}

@end

@interface StaffMembersViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) id<FIRListenerRegistration> staffReg;
@property (nonatomic, strong) NSMutableArray<UserModel *> *allStaff;
@property (nonatomic, strong) NSMutableArray<UserModel *> *filteredStaff;
@property (nonatomic, copy) NSString *currentQuery;
@property (nonatomic, strong) UILabel *visibleCountLabel;
@property (nonatomic, strong) UILabel *totalCountLabel;
@property (nonatomic, strong) UILabel *activeCountLabel;
@property (nonatomic, strong) UILabel *disabledCountLabel;
@property (nonatomic, strong) UIView *visibleMetricView;
@property (nonatomic, strong) UIView *totalMetricView;
@property (nonatomic, strong) UIView *activeMetricView;
@property (nonatomic, strong) UIView *disabledMetricView;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, strong) UIImageView *stateIconView;
@property (nonatomic, strong) UILabel *stateTitleLabel;
@property (nonatomic, strong) UILabel *stateSubtitleLabel;
@property (nonatomic, strong) UIButton *stateRetryButton;
@property (nonatomic, assign) CGFloat headerWidth;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedStaffIDs;
@property (nonatomic, assign) BOOL loadingStaff;
@property (nonatomic, strong) NSError *listenerError;
@property (nonatomic, assign) BOOL accessDenied;
@end

@implementation StaffMembersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PPStaffMembersBackgroundColor();
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.allStaff = [NSMutableArray array];
    self.filteredStaff = [NSMutableArray array];
    self.animatedStaffIDs = [NSMutableSet set];
    self.currentQuery = @"";
    self.loadingStaff = YES;

    [self pp_configureTableView];
    [self setupHeaderUI];
    [self pp_refreshBriefingMetrics];
    [self pp_updateListState];

    self.accessDenied = ![self pp_hasStaffViewAccess];
    if (self.accessDenied) {
        self.loadingStaff = NO;
        [self pp_updateListState];
    } else {
        [self pp_startStaffListener];
    }
}

- (BOOL)pp_hasStaffViewAccess {
    return [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermStaffView];
}

- (void)pp_startStaffListener {
    [self.staffReg remove];
    self.staffReg = nil;
    self.accessDenied = ![self pp_hasStaffViewAccess];
    if (self.accessDenied) {
        self.loadingStaff = NO;
        [self pp_updateListState];
        return;
    }

    self.loadingStaff = self.allStaff.count == 0;
    self.listenerError = nil;
    [self pp_updateListState];
    __weak typeof(self) weakSelf = self;
    self.staffReg = [[PPStaffAuth shared] listenAllStaff:^(NSArray<PPStaffDoc *> * _Nullable staff, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.loadingStaff = NO;
            if (error) {
                self.listenerError = error;
                [self pp_updateListState];
                [self.tableView reloadData];
                if (self.view.window && self.allStaff.count == 0) {
                    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.stateTitleLabel.text);
                }
                return;
            }
            self.listenerError = nil;
            NSMutableArray<UserModel *> *mappedStaff = [NSMutableArray arrayWithCapacity:staff.count];
            for (PPStaffDoc *staffDoc in staff ?: @[]) {
                UserModel *user = PPStaffMembersUserModelFromStaffDoc(staffDoc);
                if (user) [mappedStaff addObject:user];
            }
            self.allStaff = mappedStaff;
            [self _applyFilterAndReload];
        });
    }];
}

- (void)pp_retryStaffListener {
    [self pp_startStaffListener];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    BOOL deniedNow = ![self pp_hasStaffViewAccess];
    if (deniedNow && !self.accessDenied) {
        self.accessDenied = YES;
        [self.staffReg remove];
        self.staffReg = nil;
        [self.allStaff removeAllObjects];
        [self.filteredStaff removeAllObjects];
        [self pp_refreshBriefingMetrics];
        [self pp_updateListState];
    } else if (!deniedNow && self.accessDenied) {
        [self pp_startStaffListener];
    }
    [self.tableView reloadData];
    if ([self pp_isEmbeddedInStaffManagement]) {
        [self pp_removeNavBar];
        return;
    }
    [self pp_configureNavigationBar];
}

- (void)dealloc {
    [self.staffReg remove];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    BOOL contentSizeChanged = previousTraitCollection &&
        ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory];
    if (contentSizeChanged) {
        CGFloat width = CGRectGetWidth(self.view.bounds);
        self.headerWidth = width;
        [self pp_installHeaderViewForWidth:width withText:self.currentQuery ?: @""];
        [self pp_refreshBriefingMetrics];
    }
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.view.backgroundColor = PPStaffMembersBackgroundColor();
        self.tableView.backgroundColor = PPStaffMembersBackgroundColor();
        self.searchView.backgroundColor = PPStaffMembersSurfaceColor();
        self.searchView.strokeColor = PPStaffMembersBorderColor();
        [self.searchView setNeedsLayout];
        [self.tableView reloadData];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (fabs(width - self.headerWidth) > 1.0) {
        self.headerWidth = width;
        NSString *currentText = self.currentQuery ?: @"";
        [self pp_installHeaderViewForWidth:width withText:currentText];
        [self pp_refreshBriefingMetrics];
    }
}

- (void)pp_configureNavigationBar {
    UIButton *addButton = [self pp_ButtonWithSystemName:@"plus" action:@selector(didTapAddStaff)];
    BOOL canMutateStaff = [self pp_canMutateStaffMembers];
    addButton.enabled = canMutateStaff;
    addButton.hidden = !canMutateStaff;
    if (!canMutateStaff) {
        addButton.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    }
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:addButton title:kLang(@"StaffMembers_Title") showBack:YES];
}

- (BOOL)pp_isEmbeddedInStaffManagement {
    return [self.parentViewController isKindOfClass:NSClassFromString(@"PPStaffManagementViewController")];
}

- (void)pp_configureTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = PPStaffMembersBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 104.0;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, PPSpaceXXL, 0.0);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, PPSpaceLG)];
    [self.tableView registerClass:PPStaffMemberCardCell.class forCellReuseIdentifier:PPStaffMemberCardCellID];
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }

    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.emptyStateView = [self pp_buildListStateView];
    self.emptyStateView.hidden = YES;
    self.tableView.backgroundView = self.emptyStateView;
}

- (void)setupHeaderUI {
    [self pp_installHeaderViewForWidth:CGRectGetWidth(self.view.bounds) withText:self.currentQuery ?: @""];
}

- (void)pp_installHeaderViewForWidth:(CGFloat)width withText:(NSString *)text {
    width = MAX(width, 1.0);
    CGFloat horizontalInset = width > 800.0 ? PPSpaceXL : PPSpaceBase;
    BOOL accessibilityCategory = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *contentStack = [[UIStackView alloc] init];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.alignment = UIStackViewAlignmentFill;
    contentStack.spacing = PPSpaceMD;
    contentStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:contentStack];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.font = PPStaffMembersScaledFont([Styling fontBold:PPFontTitle2], UIFontTextStyleTitle2);
    titleLabel.textColor = PPStaffMembersPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.numberOfLines = 2;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.text = kLang(@"StaffMembers_Title");
    titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [contentStack addArrangedSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.font = PPStaffMembersScaledFont([Styling fontRegular:PPFontSubheadline], UIFontTextStyleSubheadline);
    subtitleLabel.textColor = PPStaffMembersSecondaryTextColor();
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.adjustsFontForContentSizeCategory = YES;
    subtitleLabel.text = kLang(@"StaffMembers_Subtitle");
    [contentStack addArrangedSubview:subtitleLabel];

    self.visibleCountLabel = [UILabel new];
    self.totalCountLabel = [UILabel new];
    self.activeCountLabel = [UILabel new];
    self.disabledCountLabel = [UILabel new];
    self.visibleMetricView = [self pp_metricViewWithCountLabel:self.visibleCountLabel
                                                        title:kLang(@"Visible")
                                                         tint:PPStaffMembersPrimaryColor()];
    self.totalMetricView = [self pp_metricViewWithCountLabel:self.totalCountLabel
                                                      title:kLang(@"MissionControl_Staff_Total")
                                                       tint:PPStaffMembersPrimaryTextColor()];
    self.activeMetricView = [self pp_metricViewWithCountLabel:self.activeCountLabel
                                                       title:kLang(@"Active")
                                                        tint:[UIColor ppSuccess]];
    self.disabledMetricView = [self pp_metricViewWithCountLabel:self.disabledCountLabel
                                                         title:kLang(@"Disabled")
                                                          tint:PPStaffMembersSecondaryTextColor()];

    UIStackView *metricsStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.visibleMetricView, self.totalMetricView, self.activeMetricView, self.disabledMetricView
    ]];
    metricsStack.axis = accessibilityCategory ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    metricsStack.alignment = UIStackViewAlignmentFill;
    metricsStack.distribution = UIStackViewDistributionFillEqually;
    metricsStack.spacing = accessibilityCategory ? PPSpaceXS : PPSpaceSM;
    metricsStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [contentStack addArrangedSubview:metricsStack];

    UIView *divider = [UIView new];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [UIColor ppSurfaceBorder];
    [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    [contentStack addArrangedSubview:divider];

    self.searchView = [[PPS alloc] initWithFrame:CGRectZero];
    self.searchView.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchView.delegate = self;
    self.searchView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.searchView.textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.searchView.textField.textAlignment = Language.alignmentForCurrentLanguage;
    self.searchView.textField.font = PPStaffMembersScaledFont([Styling fontMedium:PPFontBody], UIFontTextStyleBody);
    self.searchView.textField.adjustsFontForContentSizeCategory = YES;
    self.searchView.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchView.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchView.textField.placeholder = kLang(@"SetPermissions_Search_Placeholder");
    self.searchView.textField.accessibilityLabel = kLang(@"SetPermissions_Search_Placeholder");
    self.searchView.textField.text = text;
    self.searchView.blurEnabled = NO;
    self.searchView.shadowEnabled = NO;
    self.searchView.backgroundColor = PPStaffMembersSurfaceColor();
    self.searchView.strokeColor = PPStaffMembersBorderColor();
    self.searchView.cornerRadius = PPCornerSmall;
    self.searchView.layer.cornerRadius = PPCornerSmall;
    self.searchView.layer.borderWidth = 0.0;
    self.searchView.layer.shadowOpacity = 0.0;
    [self pp_configureSearchAdornmentForView:self.searchView];
    [self.searchView.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;
    [contentStack addArrangedSubview:self.searchView];

    [NSLayoutConstraint activateConstraints:@[
        [contentStack.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceMD],
        [contentStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:horizontalInset],
        [contentStack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-horizontalInset],
        [contentStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceMD]
    ]];

    CGSize fittingSize = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                               withHorizontalFittingPriority:UILayoutPriorityRequired
                                     verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect headerFrame = header.frame;
    headerFrame.size.height = ceil(MAX(fittingSize.height, 1.0));
    header.frame = headerFrame;

    self.tableView.tableHeaderView = header;
}

- (UIView *)pp_metricViewWithCountLabel:(UILabel *)countLabel title:(NSString *)title tint:(UIColor *)tint {
    BOOL accessibilityCategory = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.clearColor;
    container.isAccessibilityElement = YES;
    container.accessibilityTraits = UIAccessibilityTraitStaticText;

    countLabel.font = PPStaffMembersScaledFont([Styling fontBold:PPFontTitle3], UIFontTextStyleHeadline);
    countLabel.textColor = tint;
    countLabel.textAlignment = accessibilityCategory ? Language.alignmentForCurrentLanguage : NSTextAlignmentCenter;
    countLabel.adjustsFontForContentSizeCategory = YES;
    countLabel.text = @"0";
    countLabel.isAccessibilityElement = NO;

    UILabel *titleLabel = [UILabel new];
    titleLabel.font = PPStaffMembersScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
    titleLabel.textColor = PPStaffMembersSecondaryTextColor();
    titleLabel.textAlignment = accessibilityCategory ? Language.alignmentForCurrentLanguage : NSTextAlignmentCenter;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 2;
    titleLabel.text = title;
    titleLabel.isAccessibilityElement = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[countLabel, titleLabel]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = accessibilityCategory ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    stack.alignment = accessibilityCategory ? UIStackViewAlignmentCenter : UIStackViewAlignmentFill;
    stack.spacing = accessibilityCategory ? PPSpaceSM : PPSpaceXXS;
    stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:PPSpaceXS],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceXS],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceXS],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceXS],
        [container.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin]
    ]];
    return container;
}

- (void)pp_configureSearchAdornmentForView:(PPS *)searchView {
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    UIImage *iconImage = [UIImage systemImageNamed:@"magnifyingglass" withConfiguration:iconConfig];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
    iconView.tintColor = [PPStaffMembersSecondaryTextColor() colorWithAlphaComponent:0.85];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(0, 0, 18.0, 18.0);

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28.0, 18.0)];
    iconView.center = CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds));
    [container addSubview:iconView];

    searchView.textField.leftView = nil;
    searchView.textField.rightView = nil;
    if ([Language isRTL]) {
        searchView.textField.rightView = container;
        searchView.textField.rightViewMode = UITextFieldViewModeAlways;
    } else {
        searchView.textField.leftView = container;
        searchView.textField.leftViewMode = UITextFieldViewModeAlways;
    }
}

- (UIView *)pp_buildListStateView {
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.backgroundColor = UIColor.clearColor;
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    container.isAccessibilityElement = NO;

    UIImageSymbolConfiguration *iconConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:PPFontTitle1 weight:UIImageSymbolWeightMedium];
    self.stateIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.3.sequence.fill" withConfiguration:iconConfiguration]];
    self.stateIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateIconView.tintColor = PPStaffMembersPrimaryColor();
    self.stateIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.stateIconView.isAccessibilityElement = NO;

    self.stateTitleLabel = [UILabel new];
    self.stateTitleLabel.font = PPStaffMembersScaledFont([Styling fontBold:PPFontTitle3], UIFontTextStyleTitle3);
    self.stateTitleLabel.textColor = PPStaffMembersPrimaryTextColor();
    self.stateTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateTitleLabel.numberOfLines = 0;
    self.stateTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.stateTitleLabel.isAccessibilityElement = YES;
    self.stateTitleLabel.accessibilityTraits = UIAccessibilityTraitHeader;

    self.stateSubtitleLabel = [UILabel new];
    self.stateSubtitleLabel.font = PPStaffMembersScaledFont([Styling fontRegular:PPFontSubheadline], UIFontTextStyleSubheadline);
    self.stateSubtitleLabel.textColor = PPStaffMembersSecondaryTextColor();
    self.stateSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateSubtitleLabel.numberOfLines = 0;
    self.stateSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.stateSubtitleLabel.isAccessibilityElement = YES;

    self.stateRetryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stateRetryButton setTitle:kLang(@"Retry") forState:UIControlStateNormal];
    [self.stateRetryButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
    self.stateRetryButton.titleLabel.font = PPStaffMembersScaledFont([Styling fontMedium:PPFontBody], UIFontTextStyleBody);
    self.stateRetryButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.stateRetryButton.tintColor = PPStaffMembersPrimaryColor();
    self.stateRetryButton.backgroundColor = [UIColor ppSurface];
    self.stateRetryButton.layer.cornerRadius = PPCornerSmall;
    self.stateRetryButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.stateRetryButton.layer.borderColor = PPStaffMembersBorderColor().CGColor;
    self.stateRetryButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);
    [self.stateRetryButton addTarget:self action:@selector(pp_retryStaffListener) forControlEvents:UIControlEventTouchUpInside];
    self.stateRetryButton.hidden = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.stateIconView, self.stateTitleLabel, self.stateSubtitleLabel, self.stateRetryButton
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = PPSpaceSM;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:PPSpaceXL],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-PPSpaceXL],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:420.0],
        [self.stateIconView.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.stateIconView.heightAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.stateRetryButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin]
    ]];

    return container;
}

- (void)didTapAddStaff {
    if (![self pp_canMutateStaffMembers]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        return;
    }
    AddUserViewController *vc = [AddUserViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Search

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.currentQuery = text ?: @"";
    [self _applyFilterAndReload];
}

- (void)searchViewDidSubmit:(PPS *)view {
    [view unfocus];
}

- (void)_applyFilterAndReload {
    NSString *query = self.currentQuery ?: @"";
    if (query.length == 0) {
        self.filteredStaff = self.allStaff.mutableCopy ?: [NSMutableArray array];
    } else {
        NSString *needle = query.lowercaseString;
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(UserModel *user, __unused NSDictionary *bindings) {
            NSString *name = PPStaffMembersSafeString(user.UserName).lowercaseString;
            NSString *email = PPStaffMembersSafeString(user.UserEmail).lowercaseString;
            NSString *uid = PPStaffMembersSafeString(user.uid).lowercaseString;
            NSString *phone = PPStaffMembersSafeString(user.MobileNo).lowercaseString;
            return [name containsString:needle] ||
                   [email containsString:needle] ||
                   [uid containsString:needle] ||
                   [phone containsString:needle];
        }];
        self.filteredStaff = [[self.allStaff filteredArrayUsingPredicate:predicate] mutableCopy] ?: [NSMutableArray array];
    }

    [self pp_refreshBriefingMetrics];
    [self pp_updateListState];
    [self.tableView reloadData];
    if (self.view.window) {
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.searchView ?: self.tableView);
    }
}

- (void)pp_refreshBriefingMetrics {
    NSUInteger activeCount = 0;
    for (UserModel *user in self.allStaff) {
        if ([PPStaffMembersResolvedStatus(user) isEqualToString:PPStaffStatusActive]) {
            activeCount += 1;
        }
    }
    NSUInteger disabledCount = self.allStaff.count - activeCount;

    self.visibleCountLabel.text = PPStaffMembersLocalizedCount(self.filteredStaff.count);
    self.totalCountLabel.text = PPStaffMembersLocalizedCount(self.allStaff.count);
    self.activeCountLabel.text = PPStaffMembersLocalizedCount(activeCount);
    self.disabledCountLabel.text = PPStaffMembersLocalizedCount(disabledCount);

    [self pp_setMetricAccessibilityForView:self.visibleMetricView label:kLang(@"Visible") count:self.visibleCountLabel.text];
    [self pp_setMetricAccessibilityForView:self.totalMetricView label:kLang(@"MissionControl_Staff_Total") count:self.totalCountLabel.text];
    [self pp_setMetricAccessibilityForView:self.activeMetricView label:kLang(@"Active") count:self.activeCountLabel.text];
    [self pp_setMetricAccessibilityForView:self.disabledMetricView label:kLang(@"Disabled") count:self.disabledCountLabel.text];
}

- (void)pp_setMetricAccessibilityForView:(UIView *)view label:(NSString *)label count:(NSString *)count {
    view.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", label ?: @"", count ?: @"0"];
}

- (PPStaffMembersListState)pp_currentListState {
    if (self.accessDenied) return PPStaffMembersListStateAccessDenied;
    if (self.loadingStaff && self.allStaff.count == 0) return PPStaffMembersListStateLoading;
    if (self.listenerError && self.allStaff.count == 0) return PPStaffMembersListStateListenerError;
    if (self.allStaff.count == 0) return PPStaffMembersListStateSourceEmpty;
    if (self.filteredStaff.count == 0) return PPStaffMembersListStateFilteredEmpty;
    return PPStaffMembersListStateContent;
}

- (void)pp_updateListState {
    PPStaffMembersListState state = [self pp_currentListState];
    NSString *iconName = nil;
    NSString *title = nil;
    NSString *subtitle = nil;
    UIColor *tintColor = PPStaffMembersPrimaryColor();
    self.stateRetryButton.hidden = YES;

    switch (state) {
        case PPStaffMembersListStateAccessDenied:
            iconName = @"lock.fill";
            title = kLang(@"CommandCenter_Permission_Denied_Title");
            subtitle = kLang(@"CommandCenter_Permission_Denied_Message");
            tintColor = [UIColor ppError];
            break;
        case PPStaffMembersListStateLoading:
            iconName = @"arrow.triangle.2.circlepath";
            title = kLang(@"Loading");
            subtitle = kLang(@"MissionControl_Staff_Loading_Subtitle");
            break;
        case PPStaffMembersListStateListenerError:
            iconName = @"exclamationmark.triangle";
            title = kLang(@"Staff_Preview_Load_Error");
            subtitle = kLang(@"Staff_Preview_Load_Error_Subtitle");
            tintColor = [UIColor ppWarning];
            self.stateRetryButton.hidden = NO;
            break;
        case PPStaffMembersListStateSourceEmpty:
            iconName = @"person.3.sequence";
            title = kLang(@"Staff_Preview_Empty");
            subtitle = kLang(@"MissionControl_Staff_SourceEmpty_Subtitle");
            break;
        case PPStaffMembersListStateFilteredEmpty:
            iconName = @"magnifyingglass";
            title = kLang(@"MissionControl_Staff_FilteredEmpty_Title");
            subtitle = kLang(@"MissionControl_Staff_FilteredEmpty_Subtitle");
            break;
        case PPStaffMembersListStateContent:
            break;
    }

    self.emptyStateView.hidden = state == PPStaffMembersListStateContent;
    if (state != PPStaffMembersListStateContent) {
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:PPFontTitle1 weight:UIImageSymbolWeightMedium];
        self.stateIconView.image = [UIImage systemImageNamed:iconName withConfiguration:configuration];
        self.stateIconView.tintColor = tintColor;
        self.stateTitleLabel.text = title;
        self.stateSubtitleLabel.text = subtitle;
        self.emptyStateView.accessibilityLabel = [@[title ?: @"", subtitle ?: @""] componentsJoinedByString:@", "];
    } else {
        self.emptyStateView.accessibilityLabel = nil;
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredStaff.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return PPSpaceSM;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), PPSpaceSM)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPStaffMemberCardCell *cell = [tableView dequeueReusableCellWithIdentifier:PPStaffMemberCardCellID forIndexPath:indexPath];
    UserModel *user = self.filteredStaff[indexPath.row];
    BOOL isCurrentStaff = [[FIRAuth auth].currentUser.uid isEqualToString:user.uid];
    [cell configureWithUser:user actionable:[self pp_canMutateStaffMembers] && !isCurrentStaff];
    return cell;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UserModel *user = self.filteredStaff[indexPath.row];
    BOOL isCurrentStaff = [[FIRAuth auth].currentUser.uid isEqualToString:user.uid];
    return [self pp_canMutateStaffMembers] && !isCurrentStaff ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (![self pp_canMutateStaffMembers]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        return;
    }

    UserModel *user = self.filteredStaff[indexPath.row];
    if ([[FIRAuth auth].currentUser.uid isEqualToString:user.uid]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        return;
    }
    AddUserViewController *vc = [[AddUserViewController alloc] initWithStaffMember:user];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.filteredStaff.count || UIAccessibilityIsReduceMotionEnabled()) return;

    UserModel *user = self.filteredStaff[indexPath.row];
    NSString *identifier = user.uid.length ? user.uid : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedStaffIDs containsObject:identifier]) return;
    [self.animatedStaffIDs addObject:identifier];

    cell.contentView.alpha = 0.0;
    cell.contentView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    NSTimeInterval delay = MIN(indexPath.row, 8) * 0.025;
    [UIView animateWithDuration:PPAnimDurationNormal
                          delay:delay
                         options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        cell.contentView.alpha = 1.0;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self pp_canMutateStaffMembers] || indexPath.row >= self.filteredStaff.count) return nil;
    UserModel *user = self.filteredStaff[indexPath.row];
    if ([[FIRAuth auth].currentUser.uid isEqualToString:user.uid] ||
        [PPStaffMembersResolvedStatus(user) isEqualToString:PPStaffStatusDisabled]) return nil;

    UIContextualAction *disableAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:kLang(@"Service_Action_Disable") handler:^(__unused UIContextualAction * _Nonnull action, __unused __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self pp_confirmDisableStaff:user completion:completionHandler];
    }];
    disableAction.backgroundColor = [UIColor ppWarning];
    disableAction.image = [UIImage systemImageNamed:@"person.slash"];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[disableAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (void)pp_confirmDisableStaff:(UserModel *)user completion:(void(^)(BOOL handled))completion {
    if (![self pp_canMutateStaffMembers]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        if (completion) completion(NO);
        return;
    }
    if ([[FIRAuth auth].currentUser.uid isEqualToString:user.uid]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        if (completion) completion(NO);
        return;
    }

    NSString *displayName = PPStaffMembersSafeString(user.UserName);
    NSString *subtitle = [NSString stringWithFormat:@"%@ %@", kLang(@"Service_Action_Disable"), displayName.length ? displayName : PPStaffMembersSafeString(user.UserEmail)];
    [AlertHelper showConfirmationIn:self title:kLang(@"Confirm") subtitle:subtitle placeholder:nil confirmButton:kLang(@"Confirm") cancelButton:kLang(@"Cancel") icon:nil confirmBlock:^{
        [AdminService disableStaffMember:user.uid completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) [PPToast toast:error.localizedDescription];
            else [PPToast toast:kLang(@"Success")];
            if (completion) completion(error == nil);
        }];
    } cancelBlock:^{
        if (completion) completion(NO);
    }];
}

#pragma mark - Access

- (BOOL)pp_canMutateStaffMembers {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [staff hasPermission:kStaffPermStaffManage];
}

@end
