//
//  AddUserViewController.m
//  PurePetsAdmin
//

#import "AddUserViewController.h"
#import "Styling.h"
#import "Language.h"
#import "AlertHelper.h"
#import "PPRolePermission.h"
#import "RPManager.h"
#import "AdminService.h"
#import "PPStaffAuth.h"
#import "UsersListVC.h"
#import "PPImageCollection.h"
#import "PPFormEngine.h"
#import "PPDesignTokens.h"

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseFirestore;

#ifndef RPM
#define RPM [RPManager shared]
#endif

typedef NS_ENUM(NSInteger, AddUserMode) {
    AddUserModeCreate = 0,
    AddUserModeAssign = 1
};

static NSString *const PPAddUserModeCreateValue = @"create";
static NSString *const PPAddUserModeAssignValue = @"assign";

static CGFloat const PPAddUserHorizontalInset = 18.0;
static CGFloat const PPAddUserWideHorizontalInset = 28.0;
static CGFloat const PPAddUserHeaderCornerRadius = PPCornerCard;

static UIFont *PPAddUserScaledFont(UIFont *baseFont, UIFontTextStyle textStyle) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
    }
    return baseFont;
}

static UIColor *PPAddUserSurfaceColor(void) {
    return [UIColor ppSurface];
}

static UIColor *PPAddUserBackgroundColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPAddUserPrimaryColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPAddUserPrimaryTextColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPAddUserSecondaryTextColor(void) {
    return [UIColor ppTextSecondary];
}

static UIColor *PPAddUserBorderColor(void) {
    return [UIColor ppSurfaceBorder];
}

static NSString *PPAddUserSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSDictionary *PPAddUserSafeDict(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : @{};
}

static PermissionAction *PPAddUserPermissionAction(NSString *key, NSString *localizedKey) {
    PermissionAction *action = [PermissionAction new];
    action.key = key ?: @"";
    // Keep the localization key until render time so a live language change
    // does not leave this long-lived editor with stale labels.
    action.labelEn = localizedKey ?: @"";
    action.labelAr = localizedKey ?: @"";
    return action;
}

static PermissionModule *PPAddUserPermissionModule(NSString *key,
                                                    NSString *localizedKey,
                                                    NSArray<PermissionAction *> *actions) {
    PermissionModule *module = [PermissionModule new];
    module.key = key ?: @"";
    module.labelEn = localizedKey ?: @"";
    module.labelAr = localizedKey ?: @"";
    module.actions = actions ?: @[];
    return module;
}

@interface PPAddUserTagLabel : UILabel
- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha;
@end

@implementation PPAddUserTagLabel

- (instancetype)init {
    if (self = [super init]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.font = PPAddUserScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
        self.textAlignment = NSTextAlignmentCenter;
        self.numberOfLines = 0;
        self.lineBreakMode = NSLineBreakByWordWrapping;
        self.adjustsFontForContentSizeCategory = YES;
    }
    return self;
}

- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha {
    (void)fillAlpha;
    self.text = text;
    self.textColor = tintColor;
    self.backgroundColor = UIColor.clearColor;
}

@end

@interface AddUserViewController () <PPImageCollectionDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *contentStack;

@property (nonatomic, strong) UIView *headerRoot;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UIButton *addPhotoBtn;
@property (nonatomic, strong) UILabel *headerEyebrowLabel;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
@property (nonatomic, strong) UILabel *headerIdentityLabel;
@property (nonatomic, strong) UILabel *headerOutcomeLabel;
@property (nonatomic, strong) UIImageView *headerIconView;
@property (nonatomic, strong) PPAddUserTagLabel *modeTagLabel;
@property (nonatomic, strong) PPAddUserTagLabel *roleTagLabel;
@property (nonatomic, strong) PPAddUserTagLabel *permissionTagLabel;

@property (nonatomic, strong) UIView *modeSectionView;
@property (nonatomic, strong) UIView *createAccountSectionView;
@property (nonatomic, strong) UIView *assignExistingSectionView;
@property (nonatomic, strong) UIView *roleSectionView;
@property (nonatomic, strong) UIView *featuresSectionView;
@property (nonatomic, strong) UIView *permissionsSectionView;

@property (nonatomic, strong) PPFormEngineView *modeFormView;
@property (nonatomic, strong) PPFormEngineView *accountFormView;
@property (nonatomic, strong) PPFormEngineView *assignFormView;
@property (nonatomic, strong) PPFormEngineView *roleStatusFormView;
@property (nonatomic, strong) PPFormEngineView *featureFormView;
@property (nonatomic, copy) NSArray<PPFormEngineView *> *permissionFormViews;
@property (nonatomic, strong) UIView *embeddedSaveSectionView;
@property (nonatomic, strong) UIButton *embeddedSaveButton;
@property (nonatomic, strong) UIButton *navigationSaveButton;

@property (nonatomic, strong) PPImageCollection *avatarPicker;
@property (nonatomic, strong, nullable) UIImage *pendingAvatarImage;
@property (nonatomic, strong, nullable) UserModel *selectedUser;

@property (nonatomic, strong) NSArray<StaffRoleTemplate *> *customRoles;
@property (nonatomic, copy) NSString *selectedRoleValue;
@property (nonatomic, assign) CGFloat headerWidth;
@property (nonatomic, assign) BOOL didPlayEntrance;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL editExistingStaff;
@property (nonatomic, assign) BOOL didApplyInitialUserContext;
@property (nonatomic, assign) BOOL suppressModePickerPresentation;
@property (nonatomic, assign) BOOL isSaving;
@end

@implementation AddUserViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _selectedRoleValue = PPStaffRoleViewer;
    }
    return self;
}

- (instancetype)initWithStaffMember:(UserModel *)staffMember {
    self = [self init];
    if (self) {
        _selectedUser = staffMember;
        _editExistingStaff = YES;
        self.userModel = staffMember;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self pp_buildUI];
    [self pp_updateRoleOptions];
    [self pp_applyDefaultPermissionsForRole:self.selectedRoleValue];
    [self pp_applyFeatureValuesForCurrentMode];
    [self pp_applyInitialUserContextIfNeeded];
    [self pp_updateFormVisibility];
    [self pp_prepareEntranceStateIfNeeded];

    __weak typeof(self) weakSelf = self;
    [[RPManager shared] listenStaffRoles:^(NSArray<StaffRoleTemplate *> * _Nullable roles, NSError * _Nullable error) {
        if (!error && roles) {
            weakSelf.customRoles = roles;
            [weakSelf pp_updateRoleOptions];
            if (weakSelf.editExistingStaff && weakSelf.selectedUser) {
                [weakSelf pp_applyStaffValuesFromUser:weakSelf.selectedUser];
            } else {
                [weakSelf pp_applyInitialUserContextIfNeeded];
            }
        }
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_removeNavBar];
    [self pp_updateNavigationAndEmbeddedAction];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self pp_playEntranceAnimationIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (fabs(width - self.headerWidth) > 1.0) {
        [self pp_installHeaderViewForWidth:width];
    } else {
        [self pp_updateHeaderShadowPath];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!self.isViewLoaded || !self.contentStack) return;

    BOOL contentSizeChanged = previousTraitCollection &&
        ![previousTraitCollection.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory];
    BOOL appearanceChanged = NO;
    if (@available(iOS 13.0, *)) {
        appearanceChanged = previousTraitCollection &&
            [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection];
    }
    if (contentSizeChanged || appearanceChanged) {
        [self pp_installHeaderViewForWidth:CGRectGetWidth(self.view.bounds)];
    }
}

#pragma mark - Navigation

- (void)pp_configureNavigationBar {
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    self.navigationSaveButton = save;
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto
                       button:save
                        title:[self pp_navigationTitle]
                     showBack:YES];
    [self pp_updateSaveActionPresentation];
}

- (void)pp_updateNavigationAndEmbeddedAction {
    BOOL embedded = [self pp_isEmbeddedInStaffManagement];
    [self pp_updateEmbeddedSaveVisibility];
    if (embedded) {
        self.navigationSaveButton = nil;
        [self pp_removeNavBar];
        return;
    }
    [self pp_configureNavigationBar];
}

- (NSString *)pp_navigationTitle {
    return self.editExistingStaff ? kLang(@"Staff_EditMember_Title") : kLang(@"AddStaffMember");
}

- (BOOL)pp_isEmbeddedInStaffManagement {
    return [self.parentViewController isKindOfClass:NSClassFromString(@"PPStaffManagementViewController")];
}

- (NSString *)pp_headerTitleText {
    return [self pp_navigationTitle];
}

- (NSString *)pp_headerSubtitleText {
    if (self.editExistingStaff) {
        return kLang(@"Staff_EditMember_Subtitle");
    }
    AddUserMode mode = [self pp_currentMode];
    return mode == AddUserModeAssign ? kLang(@"Staff_AssignExistingSubtitle") : kLang(@"AddStaffMemberSubtitle");
}

- (NSString *)pp_headerIconName {
    if (self.editExistingStaff) {
        return @"person.crop.circle.badge.checkmark";
    }
    return [self pp_currentMode] == AddUserModeAssign ? @"person.badge.key.fill" : @"person.badge.plus";
}

#pragma mark - UI

- (void)pp_buildUI {
    self.view.backgroundColor = PPAddUserBackgroundColor();

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = PPAddUserBackgroundColor();
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 18.0;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    [self.contentView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-36.0],
    ]];

    [self setupHeaderUI];
    [self pp_buildFormSections];
}

- (void)setupHeaderUI {
    [self pp_installHeaderViewForWidth:CGRectGetWidth(self.view.bounds)];
}

- (void)pp_installHeaderViewForWidth:(CGFloat)width {
    if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;
    self.headerWidth = width;

    if (self.headerRoot.superview) {
        [self.contentStack removeArrangedSubview:self.headerRoot];
        [self.headerRoot removeFromSuperview];
    }

    CGFloat horizontalInset = width > 800.0 ? PPAddUserWideHorizontalInset : PPAddUserHorizontalInset;
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = PPAddUserSurfaceColor();
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    card.layer.cornerRadius = PPAddUserHeaderCornerRadius;
    if (@available(iOS 13.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = PPAddUserBorderColor().CGColor;
    card.layer.shadowColor = [UIColor ppShadow].CGColor;
    card.layer.shadowOpacity = 0.0;
    [header addSubview:card];
    self.heroCard = card;

    UIView *avatarShell = [[UIView alloc] init];
    avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    avatarShell.backgroundColor = [UIColor ppSurfaceOverlay];
    avatarShell.layer.cornerRadius = PPCorner16;
    if (@available(iOS 13.0, *)) avatarShell.layer.cornerCurve = kCACornerCurveContinuous;
    avatarShell.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    avatarShell.layer.borderColor = PPAddUserBorderColor().CGColor;

    UIImage *avatarImage = self.pendingAvatarImage ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatarIMV = [[UIImageView alloc] initWithImage:avatarImage];
    self.avatarIMV.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarIMV.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarIMV.tintColor = PPAddUserPrimaryColor();
    self.avatarIMV.backgroundColor = UIColor.clearColor;
    self.avatarIMV.isAccessibilityElement = NO;
    self.avatarIMV.layer.cornerRadius = PPCornerSmall;
    self.avatarIMV.layer.masksToBounds = YES;
    [avatarShell addSubview:self.avatarIMV];

    self.addPhotoBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addPhotoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    self.addPhotoBtn.accessibilityLabel = kLang(@"Staff_Access_Preview_Photo");
    self.addPhotoBtn.accessibilityHint = kLang(@"Staff_Access_Preview_Photo_Hint");
    UIImageSymbolConfiguration *cameraConfig = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    [self.addPhotoBtn setImage:[UIImage systemImageNamed:@"camera.fill" withConfiguration:cameraConfig] forState:UIControlStateNormal];
    self.addPhotoBtn.tintColor = PPAddUserPrimaryColor();
    self.addPhotoBtn.backgroundColor = UIColor.clearColor;
    self.addPhotoBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentTrailing;
    self.addPhotoBtn.contentVerticalAlignment = UIControlContentVerticalAlignmentBottom;
    self.addPhotoBtn.imageEdgeInsets = [Language isRTL]
        ? UIEdgeInsetsMake(0.0, PPSpaceSM, PPSpaceSM, 0.0)
        : UIEdgeInsetsMake(0.0, 0.0, PPSpaceSM, PPSpaceSM);
    [self.addPhotoBtn addTarget:self action:@selector(didTapAddPhoto) forControlEvents:UIControlEventTouchUpInside];
    [avatarShell addSubview:self.addPhotoBtn];

    UIView *iconShell = [[UIView alloc] init];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.08];
    iconShell.layer.cornerRadius = PPCornerSmall;
    if (@available(iOS 13.0, *)) iconShell.layer.cornerCurve = kCACornerCurveContinuous;

    self.headerIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self pp_headerIconName]
                                                                     withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:PPFontTitle3 weight:UIImageSymbolWeightSemibold]]];
    self.headerIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerIconView.tintColor = PPAddUserPrimaryColor();
    self.headerIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.headerIconView.isAccessibilityElement = NO;
    [iconShell addSubview:self.headerIconView];

    self.headerEyebrowLabel = [[UILabel alloc] init];
    self.headerEyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerEyebrowLabel.font = PPAddUserScaledFont([Styling fontMedium:PPFontCaption1], UIFontTextStyleCaption1);
    self.headerEyebrowLabel.textColor = PPAddUserPrimaryColor();
    self.headerEyebrowLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.headerEyebrowLabel.numberOfLines = 1;
    self.headerEyebrowLabel.adjustsFontForContentSizeCategory = YES;
    self.headerEyebrowLabel.text = kLang(@"Staff_Access_Eyebrow");

    UIStackView *eyebrowRow = [[UIStackView alloc] initWithArrangedSubviews:@[iconShell, self.headerEyebrowLabel]];
    eyebrowRow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowRow.axis = UILayoutConstraintAxisHorizontal;
    eyebrowRow.alignment = UIStackViewAlignmentCenter;
    eyebrowRow.spacing = PPSpaceSM;
    eyebrowRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitleLabel.font = PPAddUserScaledFont([Styling fontBold:PPFontTitle2], UIFontTextStyleTitle2);
    self.headerTitleLabel.textColor = PPAddUserPrimaryTextColor();
    self.headerTitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.headerTitleLabel.numberOfLines = 0;
    self.headerTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.headerTitleLabel.text = [self pp_headerTitleText];

    self.headerSubtitleLabel = [[UILabel alloc] init];
    self.headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerSubtitleLabel.font = PPAddUserScaledFont([Styling fontRegular:PPFontSubheadline], UIFontTextStyleSubheadline);
    self.headerSubtitleLabel.textColor = [PPAddUserSecondaryTextColor() colorWithAlphaComponent:0.9];
    self.headerSubtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.headerSubtitleLabel.numberOfLines = 0;
    self.headerSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.headerSubtitleLabel.text = [self pp_headerSubtitleText];

    UILabel *identityLabel = [[UILabel alloc] init];
    identityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    identityLabel.font = PPAddUserScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
    identityLabel.textColor = PPAddUserSecondaryTextColor();
    identityLabel.textAlignment = Language.alignmentForCurrentLanguage;
    identityLabel.numberOfLines = 0;
    identityLabel.adjustsFontForContentSizeCategory = YES;
    identityLabel.hidden = YES;
    self.headerIdentityLabel = identityLabel;

    UIImageView *outcomeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"
                                                                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold]]];
    outcomeIcon.translatesAutoresizingMaskIntoConstraints = NO;
    outcomeIcon.tintColor = PPAddUserPrimaryColor();
    outcomeIcon.contentMode = UIViewContentModeScaleAspectFit;
    outcomeIcon.isAccessibilityElement = NO;

    self.headerOutcomeLabel = [[UILabel alloc] init];
    self.headerOutcomeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerOutcomeLabel.font = PPAddUserScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
    self.headerOutcomeLabel.textColor = PPAddUserPrimaryColor();
    self.headerOutcomeLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.headerOutcomeLabel.numberOfLines = 0;
    self.headerOutcomeLabel.adjustsFontForContentSizeCategory = YES;
    self.headerOutcomeLabel.text = [self pp_saveActionTitle];

    UIStackView *outcomeRow = [[UIStackView alloc] initWithArrangedSubviews:@[outcomeIcon, self.headerOutcomeLabel]];
    outcomeRow.translatesAutoresizingMaskIntoConstraints = NO;
    outcomeRow.axis = UILayoutConstraintAxisHorizontal;
    outcomeRow.alignment = UIStackViewAlignmentCenter;
    outcomeRow.spacing = PPSpaceMDHalf;
    outcomeRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *copyStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        eyebrowRow, self.headerTitleLabel, self.headerSubtitleLabel, identityLabel, outcomeRow
    ]];
    copyStack.translatesAutoresizingMaskIntoConstraints = NO;
    copyStack.axis = UILayoutConstraintAxisVertical;
    copyStack.alignment = UIStackViewAlignmentFill;
    copyStack.spacing = PPSpaceXS;
    [copyStack setCustomSpacing:PPSpaceSM afterView:self.headerSubtitleLabel];

    BOOL accessibilityCategory = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    UIStackView *dossierRow = [[UIStackView alloc] initWithArrangedSubviews:@[copyStack, avatarShell]];
    dossierRow.translatesAutoresizingMaskIntoConstraints = NO;
    dossierRow.axis = accessibilityCategory ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    dossierRow.alignment = accessibilityCategory ? UIStackViewAlignmentLeading : UIStackViewAlignmentTop;
    dossierRow.spacing = PPSpaceBase;
    dossierRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:dossierRow];

    self.modeTagLabel = [[PPAddUserTagLabel alloc] init];
    self.roleTagLabel = [[PPAddUserTagLabel alloc] init];
    self.permissionTagLabel = [[PPAddUserTagLabel alloc] init];

    UIView *modeDivider = [[UIView alloc] init];
    modeDivider.translatesAutoresizingMaskIntoConstraints = NO;
    modeDivider.backgroundColor = PPAddUserBorderColor();
    UIView *roleDivider = [[UIView alloc] init];
    roleDivider.translatesAutoresizingMaskIntoConstraints = NO;
    roleDivider.backgroundColor = PPAddUserBorderColor();

    UIStackView *evidenceStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.modeTagLabel, modeDivider, self.roleTagLabel, roleDivider, self.permissionTagLabel
    ]];
    evidenceStack.translatesAutoresizingMaskIntoConstraints = NO;
    evidenceStack.axis = accessibilityCategory ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    evidenceStack.alignment = accessibilityCategory ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
    evidenceStack.spacing = accessibilityCategory ? PPSpaceXS : PPSpaceSM;
    evidenceStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *evidenceSurface = [[UIView alloc] init];
    evidenceSurface.translatesAutoresizingMaskIntoConstraints = NO;
    evidenceSurface.backgroundColor = [UIColor ppSurfaceOverlay];
    evidenceSurface.layer.cornerRadius = PPCorner16;
    if (@available(iOS 13.0, *)) evidenceSurface.layer.cornerCurve = kCACornerCurveContinuous;
    evidenceSurface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    evidenceSurface.layer.borderColor = PPAddUserBorderColor().CGColor;
    [evidenceSurface addSubview:evidenceStack];
    [card addSubview:evidenceSurface];

    if (accessibilityCategory) {
        self.modeTagLabel.textAlignment = Language.alignmentForCurrentLanguage;
        self.roleTagLabel.textAlignment = Language.alignmentForCurrentLanguage;
        self.permissionTagLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [copyStack.widthAnchor constraintEqualToAnchor:dossierRow.widthAnchor].active = YES;
        [modeDivider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
        [roleDivider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    } else {
        [self.modeTagLabel.widthAnchor constraintEqualToAnchor:self.roleTagLabel.widthAnchor].active = YES;
        [self.roleTagLabel.widthAnchor constraintEqualToAnchor:self.permissionTagLabel.widthAnchor].active = YES;
        [modeDivider.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
        [modeDivider.heightAnchor constraintEqualToConstant:PPSpaceXL].active = YES;
        [roleDivider.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
        [roleDivider.heightAnchor constraintEqualToConstant:PPSpaceXL].active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceXS],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:horizontalInset],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-horizontalInset],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceXS],

        [dossierRow.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],
        [dossierRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [dossierRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],

        [avatarShell.widthAnchor constraintEqualToConstant:PPButtonHeightLG + PPSpaceBase],
        [avatarShell.heightAnchor constraintEqualToConstant:PPButtonHeightLG + PPSpaceBase],

        [self.avatarIMV.centerXAnchor constraintEqualToAnchor:avatarShell.centerXAnchor],
        [self.avatarIMV.centerYAnchor constraintEqualToAnchor:avatarShell.centerYAnchor],
        [self.avatarIMV.widthAnchor constraintEqualToConstant:PPButtonHeightMD + PPSpaceMD],
        [self.avatarIMV.heightAnchor constraintEqualToConstant:PPButtonHeightMD + PPSpaceMD],

        [self.addPhotoBtn.topAnchor constraintEqualToAnchor:avatarShell.topAnchor],
        [self.addPhotoBtn.leadingAnchor constraintEqualToAnchor:avatarShell.leadingAnchor],
        [self.addPhotoBtn.trailingAnchor constraintEqualToAnchor:avatarShell.trailingAnchor],
        [self.addPhotoBtn.bottomAnchor constraintEqualToAnchor:avatarShell.bottomAnchor],

        [iconShell.widthAnchor constraintEqualToConstant:PPButtonHeightXS],
        [iconShell.heightAnchor constraintEqualToConstant:PPButtonHeightXS],

        [self.headerIconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [self.headerIconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],
        [self.headerIconView.widthAnchor constraintEqualToConstant:PPSpaceLG],
        [self.headerIconView.heightAnchor constraintEqualToConstant:PPSpaceLG],

        [outcomeIcon.widthAnchor constraintEqualToConstant:PPSpaceBase],
        [outcomeIcon.heightAnchor constraintEqualToConstant:PPSpaceBase],

        [evidenceSurface.topAnchor constraintEqualToAnchor:dossierRow.bottomAnchor constant:PPSpaceMD],
        [evidenceSurface.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [evidenceSurface.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [evidenceSurface.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase],

        [evidenceStack.topAnchor constraintEqualToAnchor:evidenceSurface.topAnchor constant:PPSpaceSM],
        [evidenceStack.leadingAnchor constraintEqualToAnchor:evidenceSurface.leadingAnchor constant:PPSpaceMD],
        [evidenceStack.trailingAnchor constraintEqualToAnchor:evidenceSurface.trailingAnchor constant:-PPSpaceMD],
        [evidenceStack.bottomAnchor constraintEqualToAnchor:evidenceSurface.bottomAnchor constant:-PPSpaceSM]
    ]];

    self.headerRoot = header;
    [self.contentStack insertArrangedSubview:header atIndex:0];
    if (self.didPrepareEntrance && !self.didPlayEntrance) {
        card.alpha = 0.0;
        card.transform = CGAffineTransformMakeTranslation(0.0, 18.0);
    }
    [self pp_updateHeaderShadowPath];
    [self pp_refreshHeroStateAnimated:NO];
}

- (void)pp_buildFormSections {
    PPFormStyle *style = [self pp_formStyle];

    self.modeFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.modeFormView setFields:@[[self pp_modeField]]];
    self.modeSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Access_Start_Title")
                                                     subtitle:kLang(@"Staff_Access_Start_Subtitle")
                                                     bodyView:self.modeFormView];
    [self.contentStack addArrangedSubview:self.modeSectionView];

    self.accountFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.accountFormView setFields:[self pp_accountFields]];
    self.createAccountSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Access_Create_Title")
                                                              subtitle:kLang(@"Staff_Access_Create_Subtitle")
                                                              bodyView:self.accountFormView];
    [self.contentStack addArrangedSubview:self.createAccountSectionView];

    self.assignFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.assignFormView setFields:@[[self pp_existingUserField]]];
    self.assignExistingSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Access_Identity_Title")
                                                               subtitle:kLang(@"Staff_Access_Identity_Subtitle")
                                                               bodyView:self.assignFormView];
    [self.contentStack addArrangedSubview:self.assignExistingSectionView];

    self.roleStatusFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.roleStatusFormView setFields:@[[self pp_roleField], [self pp_statusField]]];
    self.roleSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Access_Posture_Title")
                                                     subtitle:kLang(@"Staff_Access_Posture_Subtitle")
                                                     bodyView:self.roleStatusFormView];
    [self.contentStack addArrangedSubview:self.roleSectionView];

    self.featureFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.featureFormView setFields:[self pp_featureFields]];
    self.featuresSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Access_Capabilities_Title")
                                                         subtitle:kLang(@"Staff_Access_Capabilities_Subtitle")
                                                         bodyView:self.featureFormView];
    [self.contentStack addArrangedSubview:self.featuresSectionView];

    UIView *permissionBody = [self pp_makePermissionBodyWithStyle:style];
    self.permissionsSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Access_Permissions_Title")
                                                            subtitle:kLang(@"Staff_Access_Permissions_Subtitle")
                                                            bodyView:permissionBody];
    [self.contentStack addArrangedSubview:self.permissionsSectionView];

    self.embeddedSaveSectionView = [self pp_makeEmbeddedSaveSection];
    [self.contentStack addArrangedSubview:self.embeddedSaveSectionView];
    [self pp_updateEmbeddedSaveVisibility];
}

- (UIView *)pp_makeEmbeddedSaveSection {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = UIColor.clearColor;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = PPAddUserPrimaryColor();
    button.tintColor = UIColor.whiteColor;
    button.layer.cornerRadius = PPCorner16;
    if (@available(iOS 13.0, *)) button.layer.cornerCurve = kCACornerCurveContinuous;
    button.titleLabel.font = PPAddUserScaledFont([Styling fontBold:PPFontCallout], UIFontTextStyleCallout);
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 18.0, 0, 18.0);
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    [button setImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:config] forState:UIControlStateNormal];
    [button setTitle:kLang(@"Staff_Access_Save") forState:UIControlStateNormal];
    button.imageEdgeInsets = [Language isRTL] ? UIEdgeInsetsMake(0, 8.0, 0, -8.0) : UIEdgeInsetsMake(0, -8.0, 0, 8.0);
    button.accessibilityLabel = kLang(@"Staff_Access_Save");
    [button addTarget:self action:@selector(onSave) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    self.embeddedSaveButton = button;

    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [button.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPAddUserHorizontalInset],
        [button.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPAddUserHorizontalInset],
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightLG],
        [button.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-18.0],
    ]];

    return container;
}

- (void)pp_updateEmbeddedSaveVisibility {
    BOOL embedded = [self pp_isEmbeddedInStaffManagement];
    self.embeddedSaveSectionView.hidden = !embedded;
    [self pp_updateSaveActionPresentation];
}

- (NSString *)pp_saveActionTitle {
    if (self.isSaving) {
        return kLang(@"Staff_Access_Saving");
    }
    return self.editExistingStaff ? kLang(@"Staff_Access_Save") : kLang(@"Staff_Access_Create");
}

- (void)pp_updateSaveActionPresentation {
    NSString *title = [self pp_saveActionTitle];
    BOOL enabled = !self.isSaving;

    self.headerOutcomeLabel.text = title;

    [self.embeddedSaveButton setTitle:title forState:UIControlStateNormal];
    self.embeddedSaveButton.accessibilityLabel = title;
    self.embeddedSaveButton.enabled = enabled;
    self.embeddedSaveButton.alpha = enabled ? 1.0 : 0.62;

    self.navigationSaveButton.accessibilityLabel = title;
    self.navigationSaveButton.enabled = enabled;
    self.navigationSaveButton.alpha = enabled ? 1.0 : 0.55;
}

- (void)pp_setSaving:(BOOL)saving {
    if (_isSaving == saving) return;
    _isSaving = saving;
    [self pp_updateSaveActionPresentation];
}

- (PPFormStyle *)pp_formStyle {
    PPFormStyle *style = [PPFormStyle defaultStyle];
    style.accentColor = PPAddUserPrimaryColor();
    style.cardBackgroundColor = UIColor.clearColor;
    style.primaryTextColor = PPAddUserPrimaryTextColor();
    style.secondaryTextColor = PPAddUserSecondaryTextColor();
    style.cardBorderColor = UIColor.clearColor;
    style.fieldBackgroundColor = [UIColor ppSurfaceOverlay];
    style.fieldBorderColor = PPAddUserBorderColor();
    style.cardBorderWidth = 0.0;
    style.shadowOpacity = 0.0;
    style.cardCornerRadius = PPCorner16;
    style.fieldCornerRadius = PPCornerSmall;
    style.titleFont = PPAddUserScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote);
    style.inputFont = PPAddUserScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
    style.placeholderFont = PPAddUserScaledFont([Styling fontRegular:PPFontCallout], UIFontTextStyleCallout);
    style.errorFont = PPAddUserScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
    style.attachmentTitleFont = PPAddUserScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote);
    style.attachmentSubtitleFont = PPAddUserScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
    return style;
}

- (UIView *)pp_makeSectionViewWithTitle:(NSString *)title
                                subtitle:(NSString *)subtitle
                                bodyView:(UIView *)bodyView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = UIColor.clearColor;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10.0;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPAddUserHorizontalInset],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPAddUserHorizontalInset],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];

    if (title.length > 0) {
        UIView *header = [[UIView alloc] init];
        header.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *copyStack = [[UIStackView alloc] init];
        copyStack.translatesAutoresizingMaskIntoConstraints = NO;
        copyStack.axis = UILayoutConstraintAxisVertical;
        copyStack.alignment = UIStackViewAlignmentFill;
        copyStack.spacing = 2.0;
        [header addSubview:copyStack];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = PPAddUserScaledFont([Styling fontMedium:PPFontSubheadline], UIFontTextStyleSubheadline);
        label.textColor = PPAddUserPrimaryTextColor();
        label.textAlignment = Language.alignmentForCurrentLanguage;
        label.text = title;
        label.numberOfLines = 0;
        label.adjustsFontForContentSizeCategory = YES;
        [copyStack addArrangedSubview:label];

        if (subtitle.length > 0) {
            UILabel *detailLabel = [[UILabel alloc] init];
            detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
            detailLabel.font = PPAddUserScaledFont([Styling fontRegular:PPFontFootnote], UIFontTextStyleFootnote);
            detailLabel.textColor = PPAddUserSecondaryTextColor();
            detailLabel.textAlignment = Language.alignmentForCurrentLanguage;
            detailLabel.text = subtitle;
            detailLabel.numberOfLines = 0;
            detailLabel.adjustsFontForContentSizeCategory = YES;
            [copyStack addArrangedSubview:detailLabel];
        }

        [NSLayoutConstraint activateConstraints:@[
            [copyStack.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceXS],
            [copyStack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPSpaceXXS],
            [copyStack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPSpaceXXS],
            [copyStack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceXS]
        ]];

        [stack addArrangedSubview:header];
    }

    [stack addArrangedSubview:bodyView];
    return container;
}

#pragma mark - Field Builders

- (PPFormFieldConfig *)pp_modeField {
    PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:@"mode"
                                                                title:@""
                                                          placeholder:@""
                                                            inputType:PPFormInputTypeSegmented];
    field.optionTitles = @[kLang(@"Staff_Create_New"), kLang(@"Staff_Assign_Existing")];
    field.optionValues = @[PPAddUserModeCreateValue, PPAddUserModeAssignValue];
    field.value = PPAddUserModeCreateValue;
    __weak typeof(self) weakSelf = self;
    field.textChangeBlock = ^(PPFormFieldConfig *config, NSString *value) {
        (void)config;
        [weakSelf pp_updateFormVisibility];
        [weakSelf pp_applyFeatureValuesForCurrentMode];
        if ([weakSelf pp_currentMode] == AddUserModeAssign && !weakSelf.suppressModePickerPresentation && !weakSelf.selectedUser) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf pp_presentExistingUserPicker];
            });
        }
    };
    return field;
}

- (NSArray<PPFormFieldConfig *> *)pp_accountFields {
    PPFormFieldConfig *name = [PPFormFieldConfig fieldWithIdentifier:@"name" title:kLang(@"Name") placeholder:kLang(@"Name") inputType:PPFormInputTypeText];
    PPFormFieldConfig *email = [PPFormFieldConfig fieldWithIdentifier:@"email" title:kLang(@"Email") placeholder:kLang(@"Email") inputType:PPFormInputTypeText];
    email.keyboardType = UIKeyboardTypeEmailAddress;
    PPFormFieldConfig *password = [PPFormFieldConfig fieldWithIdentifier:@"password" title:kLang(@"Password") placeholder:kLang(@"Password") inputType:PPFormInputTypeText];
    return @[name, email, password];
}

- (PPFormFieldConfig *)pp_existingUserField {
    PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:@"selectedUser" title:kLang(@"User") placeholder:kLang(@"Staff_Select_User_Search_Placeholder") inputType:PPFormInputTypePicker];
    __weak typeof(self) weakSelf = self;
    field.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        (void)config;
        (void)row;
        [weakSelf pp_presentExistingUserPicker];
    };
    return field;
}

- (PPFormFieldConfig *)pp_roleField {
    PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:@"role" title:kLang(@"Staff_Role") placeholder:kLang(@"Staff_Role") inputType:PPFormInputTypePicker];
    __weak typeof(self) weakSelf = self;
    field.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        (void)config;
        [weakSelf pp_presentRolePickerFromRow:row];
    };
    return field;
}

- (PPFormFieldConfig *)pp_statusField {
    PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:@"status" title:kLang(@"Active") placeholder:@"" inputType:PPFormInputTypeToggle];
    field.value = @"1";
    __weak typeof(self) weakSelf = self;
    field.textChangeBlock = ^(PPFormFieldConfig *config, NSString *value) {
        (void)config;
        (void)value;
        [weakSelf pp_refreshHeroStateAnimated:YES];
    };
    return field;
}

- (NSArray<PPFormFieldConfig *> *)pp_featureFields {
    NSMutableArray<PPFormFieldConfig *> *fields = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *feature in [self pp_featureDefinitions]) {
        NSString *featureKey = feature[@"key"];
        NSString *titleKey = feature[@"titleKey"];
        PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:[self pp_featureFormTagForKey:featureKey]
                                                                    title:kLang(titleKey)
                                                              placeholder:@""
                                                                inputType:PPFormInputTypeToggle];
        field.value = [[self pp_defaultUserFeatures][featureKey] boolValue] ? @"1" : @"0";
        [fields addObject:field];
    }
    return fields.copy;
}

- (UIView *)pp_makePermissionBodyWithStyle:(PPFormStyle *)style {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 16.0;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    NSMutableArray<PPFormEngineView *> *forms = [NSMutableArray array];
    for (PermissionModule *module in [self pp_allPermissionModules]) {
        [stack addArrangedSubview:[self pp_makePermissionModuleHeaderForModule:module]];

        PPFormEngineView *form = [[PPFormEngineView alloc] initWithStyle:style];
        [form setFields:[self pp_permissionFieldsForModule:module]];
        [forms addObject:form];
        [stack addArrangedSubview:form];
    }

    self.permissionFormViews = forms.copy;
    return container;
}

- (UIView *)pp_makePermissionModuleHeaderForModule:(PermissionModule *)module {
    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPAddUserScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote);
    titleLabel.textColor = PPAddUserPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.numberOfLines = 2;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.text = kLang(module.labelEn);
    [header addSubview:titleLabel];

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    countLabel.font = PPAddUserScaledFont([Styling fontMedium:PPFontCaption1], UIFontTextStyleCaption1);
    countLabel.textColor = PPAddUserSecondaryTextColor();
    countLabel.textAlignment = Language.alignmentForCurrentLanguage;
    countLabel.numberOfLines = 1;
    countLabel.adjustsFontForContentSizeCategory = YES;
    countLabel.text = [NSString localizedStringWithFormat:kLang(@"Staff_Access_Module_Permissions_Format"),
                       (unsigned long)module.actions.count];
    [header addSubview:countLabel];

    UIView *hairline = [[UIView alloc] init];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.12];
    [header addSubview:hairline];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:header.topAnchor constant:2.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:countLabel.leadingAnchor constant:-12.0],
        [titleLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4.0],

        [countLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [countLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],

        [hairline.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:10.0],
        [hairline.trailingAnchor constraintLessThanOrEqualToAnchor:countLabel.leadingAnchor constant:-8.0],
        [hairline.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [hairline.widthAnchor constraintGreaterThanOrEqualToConstant:18.0],
    ]];
    return header;
}

- (NSArray<PPFormFieldConfig *> *)pp_permissionFieldsForModule:(PermissionModule *)module {
    NSMutableArray<PPFormFieldConfig *> *fields = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (PermissionAction *action in module.actions) {
        PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:action.key
                                                                      title:kLang(action.labelEn)
                                                                placeholder:@""
                                                                  inputType:PPFormInputTypeToggle];
        field.value = @"0";
        field.textChangeBlock = ^(PPFormFieldConfig *config, NSString *value) {
            (void)config;
            (void)value;
            [weakSelf pp_refreshHeroStateAnimated:YES];
        };
        [fields addObject:field];
    }
    return fields.copy;
}

#pragma mark - State

- (NSString *)pp_trimmedStringValue:(NSString *)value {
    return [PPAddUserSafeString(value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (AddUserMode)pp_currentMode {
    NSString *value = [self.modeFormView valueForIdentifier:@"mode"];
    return [value isEqualToString:PPAddUserModeAssignValue] ? AddUserModeAssign : AddUserModeCreate;
}

- (void)pp_setMode:(AddUserMode)mode disabled:(BOOL)disabled {
    self.suppressModePickerPresentation = YES;
    [self.modeFormView setValue:(mode == AddUserModeAssign ? PPAddUserModeAssignValue : PPAddUserModeCreateValue) forIdentifier:@"mode"];
    [self.modeFormView setFieldEnabled:!disabled identifier:@"mode"];
    self.suppressModePickerPresentation = NO;
    [self pp_updateFormVisibility];
}

- (void)pp_updateFormVisibility {
    AddUserMode mode = [self pp_currentMode];
    BOOL showCreate = (mode == AddUserModeCreate);
    BOOL showAssign = (mode == AddUserModeAssign) || self.editExistingStaff || self.selectedUser != nil;

    self.modeSectionView.hidden = self.editExistingStaff;
    self.createAccountSectionView.hidden = !showCreate;
    self.assignExistingSectionView.hidden = !showAssign;
    self.featuresSectionView.hidden = ![self pp_canManageUserFeatures];

    [self pp_refreshHeroStateAnimated:YES];
}

- (void)pp_applyInitialUserContextIfNeeded {
    if (self.didApplyInitialUserContext) return;
    UserModel *initialUser = self.selectedUser ?: self.userModel;
    if (!initialUser) return;

    self.didApplyInitialUserContext = YES;
    self.selectedUser = initialUser;
    self.userModel = initialUser;
    self.editExistingStaff = YES;

    [self pp_setMode:AddUserModeAssign disabled:YES];
    [self pp_applySelectedUserDisplay:initialUser];
    [self pp_applyStaffValuesFromUser:initialUser];
    [self pp_updateNavigationAndEmbeddedAction];
}

- (void)pp_applySelectedUserDisplay:(UserModel *)user {
    NSString *display = [self pp_displayNameForUser:user];
    [self.assignFormView setValue:display forIdentifier:@"selectedUser"];
    [self pp_refreshHeroStateAnimated:YES];
}

- (NSString *)pp_displayNameForUser:(UserModel *)user {
    if (!user) return @"";
    NSString *name = PPAddUserSafeString(user.UserName);
    NSString *email = PPAddUserSafeString(user.UserEmail);
    if (name.length > 0 && email.length > 0) {
        return [NSString stringWithFormat:@"%@ • %@", name, email];
    }
    return name.length > 0 ? name : email;
}

#pragma mark - Header State

- (void)pp_updateHeaderShadowPath {
    if (!self.heroCard) return;
    self.heroCard.layer.shadowPath = nil;
}

- (void)pp_refreshHeroStateAnimated:(BOOL)animated {
    if (!self.modeTagLabel || !self.roleTagLabel || !self.permissionTagLabel) return;

    NSString *modeText = [self pp_currentStatusDisplayText];
    NSString *roleText = [self pp_currentRoleDisplayText];
    NSString *permissionText = [NSString localizedStringWithFormat:kLang(@"Staff_Access_Permissions_Summary_Format"),
                                (unsigned long)[self pp_selectedPermissionCount]];
    UIColor *accentColor = PPAddUserPrimaryColor();
    BOOL isActive = self.roleStatusFormView ? [[self.roleStatusFormView valueForIdentifier:@"status"] boolValue] : YES;
    UIColor *statusColor = isActive
        ? [UIColor ppSuccess]
        : [UIColor ppWarning];
    void (^updates)(void) = ^{
        self.headerTitleLabel.text = [self pp_headerTitleText];
        self.headerSubtitleLabel.text = [self pp_headerSubtitleText];
        self.headerSubtitleLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.headerSubtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        NSString *identityText = [self pp_displayNameForUser:self.selectedUser];
        self.headerIdentityLabel.text = identityText;
        self.headerIdentityLabel.hidden = identityText.length == 0;
        self.headerIdentityLabel.semanticContentAttribute = UISemanticContentAttributeUnspecified;
        self.headerIdentityLabel.textAlignment = NSTextAlignmentNatural;
        self.headerOutcomeLabel.text = [self pp_saveActionTitle];
        self.headerIconView.image = [UIImage systemImageNamed:[self pp_headerIconName]
                                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:PPFontTitle3 weight:UIImageSymbolWeightSemibold]];
        [self.modeTagLabel applyWithText:modeText tintColor:statusColor fillAlpha:0.12];
        [self.roleTagLabel applyWithText:roleText tintColor:PPAddUserPrimaryTextColor() fillAlpha:0.08];
        [self.permissionTagLabel applyWithText:permissionText tintColor:PPAddUserSecondaryTextColor() fillAlpha:0.09];
    };

    if (animated && self.heroCard && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView transitionWithView:self.heroCard duration:0.18 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:updates completion:nil];
    } else {
        updates();
    }
}

- (NSString *)pp_currentModeDisplayText {
    if (self.editExistingStaff && self.selectedUser) {
        return kLang(@"Staff_Edit_Existing");
    }
    return [self pp_currentMode] == AddUserModeAssign ? kLang(@"Staff_Assign_Existing") : kLang(@"Staff_Create_New");
}

- (NSString *)pp_currentStatusDisplayText {
    if (self.editExistingStaff || self.selectedUser) {
        BOOL isActive = self.roleStatusFormView ? [[self.roleStatusFormView valueForIdentifier:@"status"] boolValue] : YES;
        return isActive
            ? kLang(@"Active")
            : kLang(@"Disabled");
    }
    return [self pp_currentModeDisplayText];
}

- (NSString *)pp_currentRoleDisplayText {
    return [PPStaffAuth localizedRoleName:self.selectedRoleValue ?: PPStaffRoleViewer];
}

- (NSUInteger)pp_selectedPermissionCount {
    NSUInteger count = 0;
    NSDictionary<NSString *, NSString *> *values = [self pp_permissionValues];
    for (NSString *key in values.allKeys) {
        if ([key containsString:@"."] && [values[key] boolValue]) {
            count += 1;
        }
    }
    return count;
}

- (NSDictionary<NSString *, NSString *> *)pp_permissionValues {
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    for (PPFormEngineView *formView in self.permissionFormViews) {
        [values addEntriesFromDictionary:[formView values]];
    }
    return values.copy;
}

- (void)pp_playEntranceAnimationIfNeeded {
    if (self.didPlayEntrance) return;
    [self pp_prepareEntranceStateIfNeeded];
    self.didPlayEntrance = YES;

    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.heroCard.alpha = 1.0;
        self.heroCard.transform = CGAffineTransformIdentity;
        for (UIView *view in [self pp_entranceAnimatedSectionViews]) {
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        }
        return;
    }

    [UIView animateWithDuration:0.55
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.45
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.heroCard.alpha = 1.0;
        self.heroCard.transform = CGAffineTransformIdentity;
    } completion:nil];

    NSArray<UIView *> *animatedViews = [self pp_entranceAnimatedSectionViews];
    [animatedViews enumerateObjectsUsingBlock:^(UIView *view, NSUInteger idx, BOOL *stop) {
        (void)stop;
        if (view.hidden) return;
        [UIView animateWithDuration:0.34
                              delay:0.05 + (idx * 0.025)
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (NSArray<UIView *> *)pp_entranceAnimatedSectionViews {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    if (self.modeSectionView.superview) [views addObject:self.modeSectionView];
    if (self.createAccountSectionView.superview) [views addObject:self.createAccountSectionView];
    if (self.assignExistingSectionView.superview) [views addObject:self.assignExistingSectionView];
    if (self.roleSectionView.superview) [views addObject:self.roleSectionView];
    if (self.featuresSectionView.superview) [views addObject:self.featuresSectionView];
    if (self.permissionsSectionView.superview) [views addObject:self.permissionsSectionView];
    if (self.embeddedSaveSectionView.superview) [views addObject:self.embeddedSaveSectionView];
    return views.copy;
}

- (void)pp_prepareEntranceStateIfNeeded {
    if (self.didPrepareEntrance || self.didPlayEntrance) return;
    self.didPrepareEntrance = YES;
    self.heroCard.alpha = 0.0;
    self.heroCard.transform = CGAffineTransformMakeTranslation(0.0, 18.0);
    for (UIView *view in [self pp_entranceAnimatedSectionViews]) {
        if (view.hidden) continue;
        view.alpha = 0.0;
        view.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
    }
}

#pragma mark - Existing User Picker / Staff Editing

- (void)pp_presentExistingUserPicker {
    if (!self.isViewLoaded || self.presentedViewController) return;

    [self pp_setMode:AddUserModeAssign disabled:self.editExistingStaff];

    UsersListVC *picker = [[UsersListVC alloc] initWithViewFor:ViewForPicker];
    picker.searchPlaceholderText = kLang(@"Staff_Select_User_Search_Placeholder");

    __weak typeof(self) weakSelf = self;
    picker.onUserPicked = ^(UserModel *user) {
        [weakSelf pp_handlePickedExistingUser:user];
    };

    if (self.navigationController) {
        [self.navigationController pushViewController:picker animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)pp_handlePickedExistingUser:(UserModel *)user {
    if (!user) return;

    BOOL userIsStaff = [self pp_userLooksLikeStaff:user];
    if (self.selectedUser.uid.length > 0 &&
        [self.selectedUser.uid isEqualToString:user.uid] &&
        self.editExistingStaff == userIsStaff) {
        [self pp_applyFeatureValuesFromSelectedUser:user];
        return;
    }

    self.selectedUser = user;
    self.userModel = user;
    self.editExistingStaff = userIsStaff;
    [self pp_applySelectedUserDisplay:user];
    [self pp_setMode:AddUserModeAssign disabled:NO];

    if (userIsStaff) {
        [self pp_applyStaffValuesFromUser:user];
        [self pp_updateNavigationAndEmbeddedAction];
        return;
    }

    [self pp_showNormalUserUpgradePromptForUser:user];
}

- (void)pp_showNormalUserUpgradePromptForUser:(UserModel *)user {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Staff_NormalUserUpgrade_Title")
                                                                   message:kLang(@"Staff_NormalUserUpgrade_Message")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        weakSelf.selectedUser = nil;
        weakSelf.userModel = nil;
        weakSelf.editExistingStaff = NO;
        [weakSelf.assignFormView setValue:@"" forIdentifier:@"selectedUser"];
        [weakSelf pp_applyFeatureValuesForCurrentMode];
        [weakSelf pp_refreshHeroStateAnimated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Staff_NormalUserUpgrade_Confirm") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf pp_prepareNormalUserUpgrade:user];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pp_prepareNormalUserUpgrade:(UserModel *)user {
    self.selectedUser = user;
    self.userModel = user;
    self.editExistingStaff = NO;
    [self pp_applySelectedUserDisplay:user];
    [self pp_setMode:AddUserModeAssign disabled:NO];
    [self pp_applyFeatureValuesFromSelectedUser:user];
    [self pp_applyDefaultPermissionsForRole:self.selectedRoleValue];
    [self pp_updateNavigationAndEmbeddedAction];
}

- (BOOL)pp_userLooksLikeStaff:(UserModel *)user {
    NSString *accountType = PPAddUserSafeString(user.accountType).lowercaseString;
    if ([accountType isEqualToString:@"staff"]) return YES;
    if (user.staffProfile.count > 0) return YES;
    if (PPAddUserSafeString(user.staffRole).length > 0) return YES;
    return NO;
}

- (PPStaffRole)pp_staffRoleForUser:(UserModel *)user {
    NSDictionary *profile = PPAddUserSafeDict(user.staffProfile);
    NSString *role = PPAddUserSafeString(profile[@"role"]);
    if (role.length == 0) role = PPAddUserSafeString(user.staffRole);
    if (role.length == 0) role = PPAddUserSafeString(profile[@"roleName"]);
    if (role.length == 0) role = PPAddUserSafeString(profile[@"roleValue"]);
    if (role.length > 0) return (PPStaffRole)role;
    return [PPStaffAuth staffRoleFromLegacyRole:user.role];
}

- (NSArray<NSString *> *)pp_staffPermissionsForUser:(UserModel *)user role:(PPStaffRole)role {
    NSDictionary *profile = PPAddUserSafeDict(user.staffProfile);
    NSMutableOrderedSet<NSString *> *permissions = [NSMutableOrderedSet orderedSet];

    void (^collectFromValue)(id) = ^(id value) {
        if ([value isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)value) {
                NSString *key = PPAddUserSafeString(item);
                if ([key containsString:@"."]) [permissions addObject:key];
            }
        } else if ([value isKindOfClass:NSDictionary.class]) {
            NSDictionary *dictionary = (NSDictionary *)value;
            for (id rawKey in dictionary) {
                NSString *key = PPAddUserSafeString(rawKey);
                if (![key containsString:@"."]) continue;
                id rawValue = dictionary[rawKey];
                BOOL allowed = NO;
                if ([rawValue isKindOfClass:NSDictionary.class]) {
                    allowed = [rawValue[@"allowed"] respondsToSelector:@selector(boolValue)] ? [rawValue[@"allowed"] boolValue] : NO;
                } else if ([rawValue respondsToSelector:@selector(boolValue)]) {
                    allowed = [rawValue boolValue];
                }
                if (allowed) [permissions addObject:key];
            }
        }
    };

    collectFromValue(profile[@"permissions"]);
    collectFromValue(user.permissions);

    if (permissions.count == 0) {
        return [PPStaffAuth defaultPermissionsForStaffRole:role];
    }
    return permissions.array ?: @[];
}

- (BOOL)pp_staffUserIsActive:(UserModel *)user {
    NSDictionary *profile = PPAddUserSafeDict(user.staffProfile);
    NSString *status = PPAddUserSafeString(profile[@"status"]).lowercaseString;
    if (status.length == 0) status = PPAddUserSafeString(user.accountStatus).lowercaseString;
    if (status.length == 0) status = @"active";
    return ![status isEqualToString:PPStaffStatusDisabled] && ![status isEqualToString:@"blocked"] && !user.isBlocked;
}

- (void)pp_applyStaffValuesFromUser:(UserModel *)user {
    PPStaffRole role = [self pp_staffRoleForUser:user];
    NSArray<NSString *> *permissions = [self pp_staffPermissionsForUser:user role:role];

    [self pp_applyRoleValue:role];
    [self.roleStatusFormView setValue:([self pp_staffUserIsActive:user] ? @"1" : @"0") forIdentifier:@"status"];
    [self pp_applyPermissionValues:permissions];
    [self pp_applyFeatureValuesFromSelectedUser:user];
    [self pp_refreshHeroStateAnimated:YES];
}

#pragma mark - Role / Permission Controls

- (void)pp_updateRoleOptions {
    if (self.selectedRoleValue.length == 0) {
        self.selectedRoleValue = PPStaffRoleViewer;
    }
    [self pp_applyRoleDisplay];
}

- (void)pp_applyRoleDisplay {
    NSString *display = [PPStaffAuth localizedRoleName:self.selectedRoleValue ?: PPStaffRoleViewer];
    [self.roleStatusFormView setValue:display forIdentifier:@"role"];
    [self pp_refreshHeroStateAnimated:YES];
}

- (void)pp_presentRolePickerFromRow:(PPFormFieldRowView *)row {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Role_Title") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    NSArray<NSDictionary *> *options = [self pp_roleOptions];
    for (NSDictionary *option in options) {
        NSString *value = PPAddUserSafeString(option[@"value"]);
        NSString *title = PPAddUserSafeString(option[@"title"]);
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf pp_applyRoleValue:(PPStaffRole)value];
            [weakSelf pp_applyDefaultPermissionsForRole:value];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = row ?: self.view;
        popover.sourceRect = row ? row.bounds : self.view.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (NSArray<NSDictionary *> *)pp_roleOptions {
    NSMutableArray<NSDictionary *> *options = [NSMutableArray array];
    NSArray *systemRoles = @[
        PPStaffRoleSuperAdmin, PPStaffRoleOwner, PPStaffRoleOperationsManager,
        PPStaffRoleInventoryManager, PPStaffRolePaymentsManager, PPStaffRoleSupportAgent, PPStaffRoleViewer
    ];

    for (PPStaffRole role in systemRoles) {
        [options addObject:@{@"value": role ?: @"", @"title": [PPStaffAuth localizedRoleName:role] ?: @""}];
    }

    for (StaffRoleTemplate *role in self.customRoles) {
        NSString *name = [Language isRTL] ? PPAddUserSafeString(role.name[@"ar"]) : PPAddUserSafeString(role.name[@"en"]);
        [options addObject:@{@"value": [NSString stringWithFormat:@"custom_%@", role.id ?: @""], @"title": name ?: @""}];
    }
    return options.copy;
}

- (void)pp_applyRoleValue:(PPStaffRole)role {
    self.selectedRoleValue = role.length > 0 ? role : PPStaffRoleViewer;
    [self pp_applyRoleDisplay];
}

- (void)pp_applyPermissionValues:(NSArray<NSString *> *)permissions {
    NSSet<NSString *> *activePermissions = [NSSet setWithArray:permissions ?: @[]];
    for (PPFormEngineView *formView in self.permissionFormViews) {
        for (NSString *key in formView.rowsByIdentifier.allKeys) {
            [formView setValue:([activePermissions containsObject:key] ? @"1" : @"0") forIdentifier:key];
        }
    }
    [self pp_refreshHeroStateAnimated:YES];
}

- (void)pp_applyDefaultPermissionsForRole:(id)roleValue {
    PPStaffRole role = [roleValue isKindOfClass:NSString.class] ? (PPStaffRole)roleValue : PPStaffRoleViewer;
    NSArray *defaults = [PPStaffAuth defaultPermissionsForStaffRole:role];

    if ([role hasPrefix:@"custom_"]) {
        NSString *roleID = [role substringFromIndex:7];
        for (StaffRoleTemplate *t in self.customRoles) {
            if ([t.id isEqualToString:roleID]) {
                defaults = t.permissions;
                break;
            }
        }
    }

    [self pp_applyPermissionValues:defaults];
}

#pragma mark - Feature Controls

- (NSArray<NSDictionary<NSString *, NSString *> *> *)pp_featureDefinitions {
    return @[
        @{@"key": @"canPostPetAds", @"titleKey": @"Feature_CanPostPetAds"},
        @{@"key": @"canPostAdoption", @"titleKey": @"Feature_CanPostAdoption"},
        @{@"key": @"canSellAccessories", @"titleKey": @"Feature_CanSellAccessories"},
        @{@"key": @"canOfferServices", @"titleKey": @"Feature_CanOfferServices"},
        @{@"key": @"canDelivery", @"titleKey": @"Feature_CanDelivery"},
        @{@"key": @"canDeliveryCompany", @"titleKey": @"Feature_CanDeliveryCompany"},
        @{@"key": @"canUseStories", @"titleKey": @"Feature_CanUseStories"},
        @{@"key": @"canUseChat", @"titleKey": @"Feature_CanUseChat"},
        @{@"key": @"canAccessPremiumMarketplace", @"titleKey": @"Feature_CanAccessPremiumMarketplace"},
        @{@"key": @"canAccessProviderMarketplace", @"titleKey": @"Feature_CanAccessProviderMarketplace"},
        @{@"key": @"canPharmacy", @"titleKey": @"Feature_CanPharmacy"},
        @{@"key": @"canVet", @"titleKey": @"Feature_CanVet"}
    ];
}

- (BOOL)pp_canManageUserFeatures {
    PPStaffDoc *staffDoc = [PPStaffAuth shared].cachedCurrentStaff;
    if (!staffDoc) return YES;
    return [staffDoc hasPermission:kStaffPermUsersFeaturesManage];
}

- (NSDictionary<NSString *, NSNumber *> *)pp_defaultUserFeatures {
    return @{
        @"canPostPetAds": @YES,
        @"canPostAdoption": @YES,
        @"canSellAccessories": @YES,
        @"canOfferServices": @NO,
        @"canDelivery": @NO,
        @"canDeliveryCompany": @NO,
        @"canUseStories": @YES,
        @"canUseChat": @YES,
        @"canAccessPremiumMarketplace": @NO,
        @"canAccessProviderMarketplace": @NO,
        @"canPharmacy": @NO,
        @"canVet": @NO
    };
}

- (NSString *)pp_featureFormTagForKey:(NSString *)key {
    return [NSString stringWithFormat:@"feature_%@", key ?: @""];
}

- (void)pp_applyFeatureValuesForCurrentMode {
    if ([self pp_currentMode] == AddUserModeAssign) {
        [self pp_applyFeatureValuesFromSelectedUser:self.selectedUser];
        return;
    }
    [self pp_applyFeatureValues:[self pp_defaultUserFeatures]];
}

- (void)pp_applyFeatureValuesFromSelectedUser:(UserModel *)user {
    NSDictionary *features = user.features.count ? user.features : [self pp_defaultUserFeatures];
    [self pp_applyFeatureValues:features];
}

- (void)pp_applyFeatureValues:(NSDictionary *)features {
    NSDictionary *safeFeatures = features.count ? features : [self pp_defaultUserFeatures];
    for (NSDictionary<NSString *, NSString *> *feature in [self pp_featureDefinitions]) {
        NSString *featureKey = feature[@"key"];
        NSString *identifier = [self pp_featureFormTagForKey:featureKey];
        id value = safeFeatures[featureKey];
        BOOL enabled = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : [[self pp_defaultUserFeatures][featureKey] boolValue];
        [self.featureFormView setValue:(enabled ? @"1" : @"0") forIdentifier:identifier];
    }
}

- (NSDictionary<NSString *, NSNumber *> *)pp_featurePayload {
    NSMutableDictionary<NSString *, NSNumber *> *features = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, NSString *> *values = [self.featureFormView values];
    for (NSDictionary<NSString *, NSString *> *feature in [self pp_featureDefinitions]) {
        NSString *featureKey = feature[@"key"];
        NSString *tag = [self pp_featureFormTagForKey:featureKey];
        features[featureKey] = @([values[tag] boolValue]);
    }
    return features.copy;
}

#pragma mark - Save

- (void)onSave {
    if (self.isSaving) return;

    AddUserMode mode = [self pp_currentMode];
    PPStaffRole role = self.selectedRoleValue.length > 0 ? (PPStaffRole)self.selectedRoleValue : PPStaffRoleViewer;
    NSDictionary<NSString *, NSNumber *> *features = [self pp_canManageUserFeatures] ? [self pp_featurePayload] : nil;

    NSMutableArray<NSString *> *permissions = [NSMutableArray array];
    NSDictionary<NSString *, NSString *> *permissionValues = [self pp_permissionValues];
    for (NSString *key in permissionValues.allKeys) {
        if ([key containsString:@"."] && [permissionValues[key] boolValue]) {
            [permissions addObject:key];
        }
    }

    if (mode == AddUserModeCreate) {
        NSString *email = [[self pp_trimmedStringValue:[self.accountFormView valueForIdentifier:@"email"]] lowercaseString];
        NSString *name = [self pp_trimmedStringValue:[self.accountFormView valueForIdentifier:@"name"]];
        NSString *password = [self pp_trimmedStringValue:[self.accountFormView valueForIdentifier:@"password"]];

        if (name.length == 0) {
            [PPHUD showError:kLang(@"Name") ?: @"Name"];
            return;
        }
        if (email.length == 0 || [email rangeOfString:@"@"].location == NSNotFound) {
            [PPHUD showError:kLang(@"Email") ?: @"Email"];
            return;
        }
        if (password.length < 8) {
            [PPHUD showError:kLang(@"Staff_Error_Password_Min") ?: kLang(@"Password")];
            return;
        }

        [self pp_setSaving:YES];
        [PPHUD showRingIn:self.view title:kLang(@"Staff_Access_Saving") subtitle:@""];
        [AdminService createStaffMemberWithEmail:email name:name password:password role:role permissions:permissions scope:nil completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) {
                [PPHUD dismiss];
                [self pp_setSaving:NO];
                [PPHUD showError:error.localizedDescription];
            } else {
                NSString *uid = PPAddUserSafeString(result[@"uid"]);
                [self pp_finishStaffSaveForUID:uid features:features];
            }
        }];
        return;
    }

    UserModel *user = self.selectedUser;
    if (!user) {
        [PPHUD showError:kLang(@"Error_SelectUser")];
        return;
    }

    [self pp_setSaving:YES];
    [PPHUD showRingIn:self.view title:kLang(@"Staff_Access_Saving") subtitle:@""];

    BOOL active = [[self.roleStatusFormView valueForIdentifier:@"status"] boolValue];
    if ([self pp_userLooksLikeStaff:user]) {
        NSDictionary *updates = @{
            @"role": role ?: PPStaffRoleViewer,
            @"permissions": permissions ?: @[],
            @"status": active ? PPStaffStatusActive : PPStaffStatusDisabled
        };
        [AdminService updateStaffMember:user.uid updates:updates completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) {
                [PPHUD dismiss];
                [self pp_setSaving:NO];
                [PPHUD showError:error.localizedDescription];
            } else {
                [self pp_finishStaffSaveForUID:user.uid features:features];
            }
        }];
        return;
    }

    [AdminService assignExistingUserAsStaff:user.uid role:role permissions:permissions scope:nil completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
        if (error) {
            [PPHUD dismiss];
            [self pp_setSaving:NO];
            [PPHUD showError:error.localizedDescription];
        } else {
            [self pp_finishStaffSaveForUID:user.uid features:features];
        }
    }];
}

- (void)pp_finishStaffSaveForUID:(NSString *)uid features:(NSDictionary<NSString *, NSNumber *> *)features {
    if (uid.length == 0) {
        [PPHUD dismiss];
        [self pp_setSaving:NO];
        [PPHUD showError:kLang(@"MissingUserId_Title")];
        return;
    }

    if (!features.count) {
        [PPHUD dismiss];
        [self pp_setSaving:NO];
        [PPHUD showSuccess:kLang(@"Success")];
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [AdminService updateUserFeatures:uid features:features completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [self pp_setSaving:NO];
            [PPHUD showError:error.localizedDescription];
            return;
        }
        [self pp_setSaving:NO];
        [PPHUD showSuccess:kLang(@"Success")];
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

#pragma mark - Data Helpers

- (NSArray<PermissionModule *> *)pp_allPermissionModules {
    return @[
        PPAddUserPermissionModule(@"dashboard", @"Staff_Module_Dashboard", @[
            PPAddUserPermissionAction(kStaffPermDashboardView, @"StaffPerm_dashboard_view"),
        ]),
        PPAddUserPermissionModule(@"staff", @"Staff_Module_Staff", @[
            PPAddUserPermissionAction(kStaffPermStaffView, @"StaffPerm_staff_view"),
            PPAddUserPermissionAction(kStaffPermStaffManage, @"StaffPerm_staff_manage"),
        ]),
        PPAddUserPermissionModule(@"users", @"Staff_Module_Users", @[
            PPAddUserPermissionAction(kStaffPermUsersView, @"StaffPerm_users_view"),
            PPAddUserPermissionAction(kStaffPermUsersManage, @"StaffPerm_users_manage"),
            PPAddUserPermissionAction(kStaffPermUsersBlock, @"StaffPerm_users_block"),
            PPAddUserPermissionAction(kStaffPermUsersFeaturesView, @"StaffPerm_users_features_view"),
            PPAddUserPermissionAction(kStaffPermUsersFeaturesManage, @"StaffPerm_users_features_manage"),
            PPAddUserPermissionAction(kStaffPermUsersSubscriptionsView, @"StaffPerm_users_subscriptions_view"),
            PPAddUserPermissionAction(kStaffPermUsersSubscriptionsManage, @"StaffPerm_users_subscriptions_manage"),
            PPAddUserPermissionAction(kStaffPermUsersRestrictionsView, @"StaffPerm_users_restrictions_view"),
            PPAddUserPermissionAction(kStaffPermUsersRestrictionsManage, @"StaffPerm_users_restrictions_manage"),
        ]),
        PPAddUserPermissionModule(@"stock", @"Staff_Module_Stock", @[
            PPAddUserPermissionAction(kStaffPermStockView, @"StaffPerm_stock_view"),
            PPAddUserPermissionAction(kStaffPermStockManage, @"StaffPerm_stock_manage"),
            PPAddUserPermissionAction(kStaffPermStockCreate, @"StaffPerm_stock_create"),
            PPAddUserPermissionAction(kStaffPermStockDelete, @"StaffPerm_stock_delete"),
        ]),
        PPAddUserPermissionModule(@"listings", @"Staff_Module_Listings", @[
            PPAddUserPermissionAction(kStaffPermListingsView, @"StaffPerm_listings_view"),
            PPAddUserPermissionAction(kStaffPermListingsManage, @"StaffPerm_listings_manage"),
            PPAddUserPermissionAction(kStaffPermListingsModerate, @"StaffPerm_listings_moderate"),
        ]),
        PPAddUserPermissionModule(@"payments", @"Staff_Module_Payments", @[
            PPAddUserPermissionAction(kStaffPermPaymentsView, @"StaffPerm_payments_view"),
            PPAddUserPermissionAction(kStaffPermPaymentsManage, @"StaffPerm_payments_manage"),
            PPAddUserPermissionAction(kStaffPermPaymentsRefund, @"StaffPerm_payments_refund"),
        ]),
        PPAddUserPermissionModule(@"pos", @"Staff_Module_POS", @[
            PPAddUserPermissionAction(kStaffPermPosView, @"StaffPerm_pos_view"),
            PPAddUserPermissionAction(kStaffPermPosSell, @"StaffPerm_pos_sell"),
            PPAddUserPermissionAction(kStaffPermPosHistory, @"StaffPerm_pos_history"),
        ]),
        PPAddUserPermissionModule(@"branches", @"Staff_Module_Branches", @[
            PPAddUserPermissionAction(kStaffPermBranchesView, @"StaffPerm_branches_view"),
            PPAddUserPermissionAction(kStaffPermBranchesManage, @"StaffPerm_branches_manage"),
        ]),
        PPAddUserPermissionModule(@"agents", @"Staff_Module_Agents", @[
            PPAddUserPermissionAction(kStaffPermAgentsView, @"StaffPerm_agents_view"),
            PPAddUserPermissionAction(kStaffPermAgentsManage, @"StaffPerm_agents_manage"),
        ]),
        PPAddUserPermissionModule(@"support", @"Staff_Module_Support", @[
            PPAddUserPermissionAction(kStaffPermSupportView, @"StaffPerm_support_view"),
            PPAddUserPermissionAction(kStaffPermSupportManage, @"StaffPerm_support_manage"),
        ]),
        PPAddUserPermissionModule(@"services", @"Staff_Module_Services", @[
            PPAddUserPermissionAction(kStaffPermServicesView, @"StaffPerm_services_view"),
            PPAddUserPermissionAction(kStaffPermServicesManage, @"StaffPerm_services_manage"),
        ]),
        PPAddUserPermissionModule(@"providers", @"Staff_Module_Providers", @[
            PPAddUserPermissionAction(kStaffPermProvidersView, @"StaffPerm_providers_view"),
            PPAddUserPermissionAction(kStaffPermProvidersManage, @"StaffPerm_providers_manage"),
        ]),
        PPAddUserPermissionModule(@"settings", @"Staff_Module_Settings", @[
            PPAddUserPermissionAction(kStaffPermSettingsView, @"StaffPerm_settings_view"),
            PPAddUserPermissionAction(kStaffPermSettingsManage, @"StaffPerm_settings_manage"),
        ]),
        PPAddUserPermissionModule(@"notifications", @"Staff_Module_Notifications", @[
            PPAddUserPermissionAction(kStaffPermNotificationsView, @"StaffPerm_notifications_view"),
            PPAddUserPermissionAction(kStaffPermNotificationsSend, @"StaffPerm_notifications_send"),
        ]),
        PPAddUserPermissionModule(@"accounting", @"Staff_Module_Accounting", @[
            PPAddUserPermissionAction(kStaffPermAccountingView, @"StaffPerm_accounting_view"),
            PPAddUserPermissionAction(kStaffPermAccountingManage, @"StaffPerm_accounting_manage"),
        ]),
        PPAddUserPermissionModule(@"reports", @"Staff_Module_Reports", @[
            PPAddUserPermissionAction(kStaffPermReportsView, @"StaffPerm_reports_view"),
            PPAddUserPermissionAction(kStaffPermReportsExport, @"StaffPerm_reports_export"),
        ]),
        PPAddUserPermissionModule(@"audit", @"Staff_Module_Audit", @[
            PPAddUserPermissionAction(kStaffPermAuditView, @"StaffPerm_audit_view"),
        ]),
        PPAddUserPermissionModule(@"moderation", @"Staff_Module_Moderation", @[
            PPAddUserPermissionAction(kStaffPermModerationView, @"StaffPerm_moderation_view"),
            PPAddUserPermissionAction(kStaffPermModerationManage, @"StaffPerm_moderation_manage"),
        ]),
        PPAddUserPermissionModule(@"banners", @"Staff_Module_Banners", @[
            PPAddUserPermissionAction(kStaffPermBannersView, @"StaffPerm_banners_view"),
            PPAddUserPermissionAction(kStaffPermBannersManage, @"StaffPerm_banners_manage"),
        ]),
        PPAddUserPermissionModule(@"categories", @"Staff_Module_Categories", @[
            PPAddUserPermissionAction(kStaffPermCategoriesView, @"StaffPerm_categories_view"),
            PPAddUserPermissionAction(kStaffPermCategoriesManage, @"StaffPerm_categories_manage"),
        ]),
        PPAddUserPermissionModule(@"veterinarians", @"Staff_Module_Veterinarians", @[
            PPAddUserPermissionAction(kStaffPermVeterinariansView, @"StaffPerm_veterinarians_view"),
            PPAddUserPermissionAction(kStaffPermVeterinariansManage, @"StaffPerm_veterinarians_manage"),
        ]),
    ];
}

#pragma mark - Avatar

- (void)didTapAddPhoto {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self.avatarPicker showActionSheetForAddingImage];
        return;
    }
    [UIView animateWithDuration:PPAnimDurationFast delay:0.0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        self.avatarIMV.transform = CGAffineTransformMakeScale(0.96, 0.96);
        self.addPhotoBtn.transform = CGAffineTransformMakeScale(0.97, 0.97);
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.22
                              delay:0.0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self.avatarIMV.transform = CGAffineTransformIdentity;
            self.addPhotoBtn.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
    [self.avatarPicker showActionSheetForAddingImage];
}

- (PPImageCollection *)avatarPicker {
    if (_avatarPicker) return _avatarPicker;
    _avatarPicker = [[PPImageCollection alloc] initWithFrame:CGRectZero];
    _avatarPicker.maxImageCount = 1;
    _avatarPicker.delegate = self;
    return _avatarPicker;
}

- (void)imageCollection:(PPImageCollection *)collection didUpdateImages:(NSArray<UIImage *> *)images {
    (void)collection;
    UIImage *picked = images.firstObject;
    if (!picked) return;
    self.pendingAvatarImage = picked;
    self.avatarIMV.image = picked;
}

@end
