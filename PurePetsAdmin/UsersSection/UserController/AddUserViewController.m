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
#import "PPHero.h"
#import "PPFormEngine.h"

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
static CGFloat const PPAddUserHeaderCornerRadius = 30.0;

static UIColor *PPAddUserSurfaceColor(void) {
    return AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
}

static UIColor *PPAddUserBackgroundColor(void) {
    return AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
}

static UIColor *PPAddUserPrimaryColor(void) {
    return AppPrimaryClr ?: UIColor.systemBlueColor;
}

static UIColor *PPAddUserPrimaryTextColor(void) {
    return PrimaryTextClr ?: UIColor.labelColor;
}

static UIColor *PPAddUserSecondaryTextColor(void) {
    return SeconderyTextClr ?: UIColor.secondaryLabelColor;
}

static UIColor *PPAddUserBorderColor(void) {
    return [PPAddUserPrimaryColor() colorWithAlphaComponent:0.08];
}

static NSString *PPAddUserSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSDictionary *PPAddUserSafeDict(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : @{};
}

@interface PPAddUserTagLabel : UILabel
- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha;
@end

@implementation PPAddUserTagLabel

- (instancetype)init {
    if (self = [super init]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.font = [Styling fontMedium:12];
        self.textAlignment = NSTextAlignmentCenter;
        self.numberOfLines = 1;
        self.lineBreakMode = NSLineBreakByTruncatingTail;
        self.layer.cornerRadius = 13.0;
        self.layer.masksToBounds = YES;
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:26.0],
            [self.widthAnchor constraintGreaterThanOrEqualToConstant:76.0],
            [self.widthAnchor constraintLessThanOrEqualToConstant:180.0]
        ]];
    }
    return self;
}

- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha {
    self.text = text;
    self.textColor = tintColor;
    self.backgroundColor = [tintColor colorWithAlphaComponent:fillAlpha];
}

@end

@interface AddUserViewController () <PPImageCollectionDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *contentStack;

@property (nonatomic, strong) UIView *headerRoot;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UIButton *addPhotoBtn;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
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
@property (nonatomic, strong) PPFormEngineView *permissionFormView;
@property (nonatomic, strong) UIView *embeddedSaveSectionView;
@property (nonatomic, strong) UIButton *embeddedSaveButton;

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
    [self.heroBackground startAnimations];
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

#pragma mark - Navigation

- (void)pp_configureNavigationBar {
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    [self pp_navBarWithOtherButton:save title:[self pp_navigationTitle]];
}

- (void)pp_updateNavigationAndEmbeddedAction {
    BOOL embedded = [self pp_isEmbeddedInStaffManagement];
    [self pp_updateEmbeddedSaveVisibility];
    if (embedded) {
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
    [header.heightAnchor constraintEqualToConstant:248.0].active = YES;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    card.layer.cornerRadius = PPAddUserHeaderCornerRadius;
    if (@available(iOS 13.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = PPAddUserBorderColor().CGColor;
    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1.0].CGColor;
    card.layer.shadowOpacity = 0.08;
    card.layer.shadowRadius = 24.0;
    card.layer.shadowOffset = CGSizeMake(0, 14.0);
    [header addSubview:card];
    self.heroCard = card;

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentColorOverride = PPAddUserPrimaryColor();
    [card addSubview:hero];
    self.heroBackground = hero;

    UIView *avatarShell = [[UIView alloc] init];
    avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    avatarShell.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.12];
    avatarShell.layer.cornerRadius = 32.0;
    if (@available(iOS 13.0, *)) avatarShell.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:avatarShell];

    UIImage *avatarImage = self.pendingAvatarImage ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.avatarIMV = [[UIImageView alloc] initWithImage:avatarImage];
    self.avatarIMV.translatesAutoresizingMaskIntoConstraints = NO;
    self.avatarIMV.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarIMV.tintColor = PPAddUserPrimaryColor();
    self.avatarIMV.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.08];
    self.avatarIMV.userInteractionEnabled = YES;
    self.avatarIMV.layer.cornerRadius = 28.0;
    self.avatarIMV.layer.masksToBounds = YES;
    [avatarShell addSubview:self.avatarIMV];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapAddPhoto)];
    [self.avatarIMV addGestureRecognizer:tap];

    self.addPhotoBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.addPhotoBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cameraConfig = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
    [self.addPhotoBtn setImage:[UIImage systemImageNamed:@"camera.fill" withConfiguration:cameraConfig] forState:UIControlStateNormal];
    [self.addPhotoBtn setTitle:kLang(@"Add Photo") forState:UIControlStateNormal];
    self.addPhotoBtn.titleLabel.font = [Styling fontMedium:12];
    self.addPhotoBtn.tintColor = PPAddUserPrimaryColor();
    self.addPhotoBtn.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.12];
    self.addPhotoBtn.contentEdgeInsets = UIEdgeInsetsMake(7.0, 12.0, 7.0, 12.0);
    self.addPhotoBtn.imageEdgeInsets = [Language isRTL] ? UIEdgeInsetsMake(0, 6.0, 0, -6.0) : UIEdgeInsetsMake(0, -6.0, 0, 6.0);
    self.addPhotoBtn.layer.cornerRadius = 17.0;
    if (@available(iOS 13.0, *)) self.addPhotoBtn.layer.cornerCurve = kCACornerCurveContinuous;
    [self.addPhotoBtn addTarget:self action:@selector(didTapAddPhoto) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.addPhotoBtn];

    UIView *iconShell = [[UIView alloc] init];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.12];
    iconShell.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) iconShell.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:iconShell];

    self.headerIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self pp_headerIconName]
                                                                     withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold]]];
    self.headerIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerIconView.tintColor = PPAddUserPrimaryColor();
    self.headerIconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:self.headerIconView];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitleLabel.font = [Styling fontBold:24];
    self.headerTitleLabel.textColor = PPAddUserPrimaryTextColor();
    self.headerTitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.headerTitleLabel.numberOfLines = 2;
    self.headerTitleLabel.text = [self pp_headerTitleText];
    [card addSubview:self.headerTitleLabel];

    self.headerSubtitleLabel = [[UILabel alloc] init];
    self.headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerSubtitleLabel.font = [Styling fontRegular:14];
    self.headerSubtitleLabel.textColor = [PPAddUserSecondaryTextColor() colorWithAlphaComponent:0.9];
    self.headerSubtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.headerSubtitleLabel.numberOfLines = 2;
    self.headerSubtitleLabel.text = [self pp_headerSubtitleText];
    [card addSubview:self.headerSubtitleLabel];

    self.modeTagLabel = [[PPAddUserTagLabel alloc] init];
    self.roleTagLabel = [[PPAddUserTagLabel alloc] init];
    self.permissionTagLabel = [[PPAddUserTagLabel alloc] init];

    UIStackView *tagStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.modeTagLabel, self.roleTagLabel, self.permissionTagLabel]];
    tagStack.translatesAutoresizingMaskIntoConstraints = NO;
    tagStack.axis = UILayoutConstraintAxisVertical;
    tagStack.alignment = UIStackViewAlignmentLeading;
    tagStack.spacing = 7.0;
    [card addSubview:tagStack];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:horizontalInset],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-horizontalInset],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14.0],

        [hero.topAnchor constraintEqualToAnchor:card.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [avatarShell.topAnchor constraintEqualToAnchor:card.topAnchor constant:24.0],
        [avatarShell.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22.0],
        [avatarShell.widthAnchor constraintEqualToConstant:84.0],
        [avatarShell.heightAnchor constraintEqualToConstant:84.0],

        [self.avatarIMV.centerXAnchor constraintEqualToAnchor:avatarShell.centerXAnchor],
        [self.avatarIMV.centerYAnchor constraintEqualToAnchor:avatarShell.centerYAnchor],
        [self.avatarIMV.widthAnchor constraintEqualToConstant:68.0],
        [self.avatarIMV.heightAnchor constraintEqualToConstant:68.0],

        [self.addPhotoBtn.centerXAnchor constraintEqualToAnchor:avatarShell.centerXAnchor],
        [self.addPhotoBtn.topAnchor constraintEqualToAnchor:avatarShell.bottomAnchor constant:10.0],
        [self.addPhotoBtn.heightAnchor constraintEqualToConstant:34.0],
        [self.addPhotoBtn.widthAnchor constraintGreaterThanOrEqualToConstant:108.0],

        [iconShell.topAnchor constraintEqualToAnchor:card.topAnchor constant:24.0],
        [iconShell.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22.0],
        [iconShell.widthAnchor constraintEqualToConstant:52.0],
        [iconShell.heightAnchor constraintEqualToConstant:52.0],

        [self.headerIconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [self.headerIconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],
        [self.headerIconView.widthAnchor constraintEqualToConstant:25.0],
        [self.headerIconView.heightAnchor constraintEqualToConstant:25.0],

        [self.headerTitleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:25.0],
        [self.headerTitleLabel.leadingAnchor constraintEqualToAnchor:iconShell.trailingAnchor constant:14.0],
        [self.headerTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:avatarShell.leadingAnchor constant:-14.0],

        [self.headerSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.headerTitleLabel.leadingAnchor],
        [self.headerSubtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:avatarShell.leadingAnchor constant:-14.0],
        [self.headerSubtitleLabel.topAnchor constraintEqualToAnchor:self.headerTitleLabel.bottomAnchor constant:8.0],

        [tagStack.leadingAnchor constraintEqualToAnchor:self.headerTitleLabel.leadingAnchor],
        [tagStack.trailingAnchor constraintLessThanOrEqualToAnchor:avatarShell.leadingAnchor constant:-14.0],
        [tagStack.topAnchor constraintEqualToAnchor:self.headerSubtitleLabel.bottomAnchor constant:12.0],
        [tagStack.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-18.0]
    ]];

    self.headerRoot = header;
    [self.contentStack insertArrangedSubview:header atIndex:0];
    [self pp_updateHeaderShadowPath];
    [self pp_refreshHeroStateAnimated:NO];
}

- (void)pp_buildFormSections {
    PPFormStyle *style = [self pp_formStyle];

    self.modeFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.modeFormView setFields:@[[self pp_modeField]]];
    self.modeSectionView = [self pp_makeSectionViewWithTitle:nil bodyView:self.modeFormView];
    [self.contentStack addArrangedSubview:self.modeSectionView];

    self.accountFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.accountFormView setFields:[self pp_accountFields]];
    self.createAccountSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_New_Account_Info") bodyView:self.accountFormView];
    [self.contentStack addArrangedSubview:self.createAccountSectionView];

    self.assignFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.assignFormView setFields:@[[self pp_existingUserField]]];
    self.assignExistingSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Select_Existing_User") bodyView:self.assignFormView];
    [self.contentStack addArrangedSubview:self.assignExistingSectionView];

    self.roleStatusFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.roleStatusFormView setFields:@[[self pp_roleField], [self pp_statusField]]];
    self.roleSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Staff_Role_Status") bodyView:self.roleStatusFormView];
    [self.contentStack addArrangedSubview:self.roleSectionView];

    self.featureFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.featureFormView setFields:[self pp_featureFields]];
    self.featuresSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Features") bodyView:self.featureFormView];
    [self.contentStack addArrangedSubview:self.featuresSectionView];

    self.permissionFormView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.permissionFormView setFields:[self pp_permissionFields]];
    self.permissionsSectionView = [self pp_makeSectionViewWithTitle:kLang(@"Permissions_Title") bodyView:self.permissionFormView];
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
    button.layer.cornerRadius = 24.0;
    if (@available(iOS 13.0, *)) button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.shadowColor = PPAddUserPrimaryColor().CGColor;
    button.layer.shadowOpacity = 0.18;
    button.layer.shadowRadius = 18.0;
    button.layer.shadowOffset = CGSizeMake(0, 10.0);
    button.titleLabel.font = [Styling fontBold:15.0];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.82;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 18.0, 0, 18.0);
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    [button setImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:config] forState:UIControlStateNormal];
    [button setTitle:kLang(@"Save") forState:UIControlStateNormal];
    button.imageEdgeInsets = [Language isRTL] ? UIEdgeInsetsMake(0, 8.0, 0, -8.0) : UIEdgeInsetsMake(0, -8.0, 0, 8.0);
    button.accessibilityLabel = kLang(@"Save");
    [button addTarget:self action:@selector(onSave) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    self.embeddedSaveButton = button;

    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [button.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPAddUserHorizontalInset],
        [button.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPAddUserHorizontalInset],
        [button.heightAnchor constraintEqualToConstant:52.0],
        [button.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-18.0],
    ]];

    return container;
}

- (void)pp_updateEmbeddedSaveVisibility {
    BOOL embedded = [self pp_isEmbeddedInStaffManagement];
    self.embeddedSaveSectionView.hidden = !embedded;
    NSString *title = self.editExistingStaff ? kLang(@"Save") : kLang(@"AddStaffMember");
    [self.embeddedSaveButton setTitle:title forState:UIControlStateNormal];
    self.embeddedSaveButton.accessibilityLabel = title;
}

- (PPFormStyle *)pp_formStyle {
    PPFormStyle *style = [PPFormStyle defaultStyle];
    style.accentColor = PPAddUserPrimaryColor();
    style.cardBackgroundColor = PPAddUserSurfaceColor();
     style.primaryTextColor = PPAddUserPrimaryTextColor();
    style.secondaryTextColor = PPAddUserSecondaryTextColor();
    style.cardBorderColor = PPAddUserBorderColor();
    style.fieldBorderColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.10];
    style.shadowOpacity = 0.03;
    style.shadowRadius = 16.0;
    style.shadowOffset = CGSizeMake(0, 8.0);
    style.cardCornerRadius = 24.0;
    style.fieldCornerRadius = 20.0;
    return style;
}

- (UIView *)pp_makeSectionViewWithTitle:(NSString *)title bodyView:(UIView *)bodyView {
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

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = [Styling fontMedium:13];
        label.textColor = [PPAddUserSecondaryTextColor() colorWithAlphaComponent:0.92];
        label.textAlignment = Language.alignmentForCurrentLanguage;
        label.text = title;
        [header addSubview:label];

        UIView *line = [[UIView alloc] init];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        line.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.12];
        line.layer.cornerRadius = 0.5;
        [header addSubview:line];

        [NSLayoutConstraint activateConstraints:@[
            [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:7.0],
            [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:2.0],
            [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8.0],

            [line.leadingAnchor constraintGreaterThanOrEqualToAnchor:label.trailingAnchor constant:12.0],
            [line.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
            [line.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-2.0],
            [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
            [line.widthAnchor constraintGreaterThanOrEqualToConstant:24.0]
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

- (NSArray<PPFormFieldConfig *> *)pp_permissionFields {
    NSMutableArray<PPFormFieldConfig *> *fields = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (PermissionModule *mod in [self pp_allPermissionModules]) {
        for (PermissionAction *action in mod.actions) {
            NSString *label = [Language isRTL] ? action.labelAr : action.labelEn;
            PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:action.key title:label placeholder:@"" inputType:PPFormInputTypeToggle];
            field.value = @"0";
            field.textChangeBlock = ^(PPFormFieldConfig *config, NSString *value) {
                (void)config;
                (void)value;
                [weakSelf pp_refreshHeroStateAnimated:YES];
            };
            [fields addObject:field];
        }
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
    self.heroCard.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.heroCard.bounds cornerRadius:self.heroCard.layer.cornerRadius].CGPath;
}

- (void)pp_refreshHeroStateAnimated:(BOOL)animated {
    if (!self.modeTagLabel || !self.roleTagLabel || !self.permissionTagLabel) return;

    NSString *modeText = [self pp_currentModeDisplayText];
    NSString *roleText = [self pp_currentRoleDisplayText];
    NSString *permissionText = [NSString stringWithFormat:@"%lu %@", (unsigned long)[self pp_selectedPermissionCount], kLang(@"Permissions_Title")];
    UIColor *accentColor = PPAddUserPrimaryColor();

    void (^updates)(void) = ^{
        self.headerTitleLabel.text = [self pp_headerTitleText];
        self.headerSubtitleLabel.text = [self pp_headerSubtitleText];
        self.headerIconView.image = [UIImage systemImageNamed:[self pp_headerIconName]
                                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold]];
        [self.modeTagLabel applyWithText:modeText tintColor:accentColor fillAlpha:0.12];
        [self.roleTagLabel applyWithText:roleText tintColor:PPAddUserPrimaryTextColor() fillAlpha:0.08];
        [self.permissionTagLabel applyWithText:permissionText tintColor:PPAddUserSecondaryTextColor() fillAlpha:0.09];
    };

    if (animated && self.heroCard) {
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

- (NSString *)pp_currentRoleDisplayText {
    return [PPStaffAuth localizedRoleName:self.selectedRoleValue ?: PPStaffRoleViewer];
}

- (NSUInteger)pp_selectedPermissionCount {
    NSUInteger count = 0;
    NSDictionary<NSString *, NSString *> *values = [self.permissionFormView values];
    for (NSString *key in values.allKeys) {
        if ([key containsString:@"."] && [values[key] boolValue]) {
            count += 1;
        }
    }
    return count;
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
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
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
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
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

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent]];
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
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
    for (PermissionModule *module in [self pp_allPermissionModules]) {
        for (PermissionAction *action in module.actions) {
            [self.permissionFormView setValue:([activePermissions containsObject:action.key] ? @"1" : @"0") forIdentifier:action.key];
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
        @{@"key": @"canUseStories", @"titleKey": @"Feature_CanUseStories"},
        @{@"key": @"canUseChat", @"titleKey": @"Feature_CanUseChat"},
        @{@"key": @"canAccessPremiumMarketplace", @"titleKey": @"Feature_CanAccessPremiumMarketplace"},
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
        @"canUseStories": @YES,
        @"canUseChat": @YES,
        @"canAccessPremiumMarketplace": @NO,
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
    AddUserMode mode = [self pp_currentMode];
    PPStaffRole role = self.selectedRoleValue.length > 0 ? (PPStaffRole)self.selectedRoleValue : PPStaffRoleViewer;
    NSDictionary<NSString *, NSNumber *> *features = [self pp_canManageUserFeatures] ? [self pp_featurePayload] : nil;

    NSMutableArray<NSString *> *permissions = [NSMutableArray array];
    NSDictionary<NSString *, NSString *> *permissionValues = [self.permissionFormView values];
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

        [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:@""];
        [AdminService createStaffMemberWithEmail:email name:name password:password role:role permissions:permissions scope:nil completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) {
                [PPHUD dismiss];
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

    [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:@""];

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
            [PPHUD showError:error.localizedDescription];
        } else {
            [self pp_finishStaffSaveForUID:user.uid features:features];
        }
    }];
}

- (void)pp_finishStaffSaveForUID:(NSString *)uid features:(NSDictionary<NSString *, NSNumber *> *)features {
    if (uid.length == 0) {
        [PPHUD dismiss];
        [PPHUD showError:kLang(@"MissingUserId_Title")];
        return;
    }

    if (!features.count) {
        [PPHUD dismiss];
        [PPHUD showSuccess:kLang(@"Success")];
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [AdminService updateUserFeatures:uid features:features completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:error.localizedDescription];
            return;
        }
        [PPHUD showSuccess:kLang(@"Success")];
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

#pragma mark - Data Helpers

- (NSArray<PermissionModule *> *)pp_allPermissionModules {
    static NSMutableArray<PermissionModule *> *modules = nil;
    if (modules) return modules;

    modules = [NSMutableArray array];

    PermissionModule *dashboard = [PermissionModule new];
    dashboard.key = @"dashboard";
    dashboard.labelEn = @"Dashboard";
    dashboard.labelAr = @"لوحة التحكم";
    PermissionAction *dView = [PermissionAction new]; dView.key = @"dashboard.view"; dView.labelEn = @"View dashboard"; dView.labelAr = @"عرض لوحة التحكم";
    dashboard.actions = @[dView];
    [modules addObject:dashboard];

    PermissionModule *staff = [PermissionModule new];
    staff.key = @"staff";
    staff.labelEn = @"Staff";
    staff.labelAr = @"الموظفون";
    PermissionAction *sView = [PermissionAction new]; sView.key = @"staff.view"; sView.labelEn = @"View staff"; sView.labelAr = @"عرض الموظفين";
    PermissionAction *sManage = [PermissionAction new]; sManage.key = @"staff.manage"; sManage.labelEn = @"Manage staff"; sManage.labelAr = @"إدارة الموظفين";
    staff.actions = @[sView, sManage];
    [modules addObject:staff];

    PermissionModule *users = [PermissionModule new];
    users.key = @"users";
    users.labelEn = @"Users";
    users.labelAr = @"المستخدمون";
    PermissionAction *uView = [PermissionAction new]; uView.key = @"users.view"; uView.labelEn = @"View users"; uView.labelAr = @"عرض المستخدمين";
    PermissionAction *uManage = [PermissionAction new]; uManage.key = @"users.manage"; uManage.labelEn = @"Manage users"; uManage.labelAr = @"إدارة المستخدمين";
    PermissionAction *uBlock = [PermissionAction new]; uBlock.key = @"users.block"; uBlock.labelEn = @"Block / unblock users"; uBlock.labelAr = @"حظر / إلغاء حظر المستخدمين";
    users.actions = @[uView, uManage, uBlock];
    [modules addObject:users];

    PermissionModule *stock = [PermissionModule new];
    stock.key = @"stock";
    stock.labelEn = @"Stock";
    stock.labelAr = @"المخزون";
    PermissionAction *stView = [PermissionAction new]; stView.key = @"stock.view"; stView.labelEn = @"View stock"; stView.labelAr = @"عرض المخزون";
    PermissionAction *stManage = [PermissionAction new]; stManage.key = @"stock.manage"; stManage.labelEn = @"Manage stock"; stManage.labelAr = @"إدارة المخزون";
    PermissionAction *stCreate = [PermissionAction new]; stCreate.key = @"stock.create"; stCreate.labelEn = @"Create stock items"; stCreate.labelAr = @"إنشاء عناصر المخزون";
    PermissionAction *stDelete = [PermissionAction new]; stDelete.key = @"stock.delete"; stDelete.labelEn = @"Delete stock items"; stDelete.labelAr = @"حذف عناصر المخزون";
    stock.actions = @[stView, stManage, stCreate, stDelete];
    [modules addObject:stock];

    PermissionModule *listings = [PermissionModule new];
    listings.key = @"listings";
    listings.labelEn = @"Listings";
    listings.labelAr = @"الإعلانات";
    PermissionAction *lView = [PermissionAction new]; lView.key = @"listings.view"; lView.labelEn = @"View listings"; lView.labelAr = @"عرض الإعلانات";
    PermissionAction *lManage = [PermissionAction new]; lManage.key = @"listings.manage"; lManage.labelEn = @"Manage listings"; lManage.labelAr = @"إدارة الإعلانات";
    PermissionAction *lModerate = [PermissionAction new]; lModerate.key = @"listings.moderate"; lModerate.labelEn = @"Moderate listings"; lModerate.labelAr = @"مراجعة الإعلانات";
    listings.actions = @[lView, lManage, lModerate];
    [modules addObject:listings];

    PermissionModule *payments = [PermissionModule new];
    payments.key = @"payments";
    payments.labelEn = @"Payments";
    payments.labelAr = @"المدفوعات";
    PermissionAction *pView = [PermissionAction new]; pView.key = @"payments.view"; pView.labelEn = @"View payments"; pView.labelAr = @"عرض المدفوعات";
    PermissionAction *pManage = [PermissionAction new]; pManage.key = @"payments.manage"; pManage.labelEn = @"Manage payments"; pManage.labelAr = @"إدارة المدفوعات";
    PermissionAction *pRefund = [PermissionAction new]; pRefund.key = @"payments.refund"; pRefund.labelEn = @"Process refunds"; pRefund.labelAr = @"معالجة الاسترجاعات";
    payments.actions = @[pView, pManage, pRefund];
    [modules addObject:payments];

    return modules;
}

#pragma mark - Avatar

- (void)didTapAddPhoto {
    [UIView animateWithDuration:0.12 animations:^{
        self.avatarIMV.transform = CGAffineTransformMakeScale(0.96, 0.96);
        self.addPhotoBtn.transform = CGAffineTransformMakeScale(0.97, 0.97);
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.22
                              delay:0.0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionAllowUserInteraction
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
