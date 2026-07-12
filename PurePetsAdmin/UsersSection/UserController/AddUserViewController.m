//
//  AddUserViewController.m
//  PurePetsAdmin
//

#import "AddUserViewController.h"
#import "Styling.h"
#import "Language.h"
#import "AlertHelper.h"
#import "RoleOptionsViewController.h"
#import "PPTextFieldCell.h" // Add import for the custom text field cell

#import "PPRolePermission.h"
#import "RPManager.h"
#import "AdminService.h"
#import "PPStaffAuth.h"
#import "SetUserPermissionViewController.h"

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseFirestore;

#import "PPImageCollection.h"

#ifndef RPM
#define RPM [RPManager shared]
#endif

typedef NS_ENUM(NSInteger, AddUserMode) {
    AddUserModeCreate = 0,
    AddUserModeAssign = 1
};

static CGFloat const PPAddUserHorizontalInset = 18.0;
static CGFloat const PPAddUserWideHorizontalInset = 28.0;
static CGFloat const PPAddUserCardCornerRadius = 28.0;
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
@property (nonatomic, strong) UIView *headerRoot;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UIButton *addPhotoBtn;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
@property (nonatomic, strong) UIImageView *headerIconView;
@property (nonatomic, strong) PPAddUserTagLabel *modeTagLabel;
@property (nonatomic, strong) PPAddUserTagLabel *roleTagLabel;
@property (nonatomic, strong) PPAddUserTagLabel *permissionTagLabel;
@property (nonatomic, strong) XLFormSectionDescriptor *createAccountSection;
@property (nonatomic, strong) XLFormSectionDescriptor *assignExistingSection;

@property (nonatomic, strong) PPImageCollection *avatarPicker;
@property (nonatomic, strong, nullable) UIImage *pendingAvatarImage;
@property (nonatomic, strong, nullable) UserModel *selectedUser;

@property (nonatomic, strong) NSArray<StaffRoleTemplate *> *customRoles;
@property (nonatomic, assign) CGFloat headerWidth;
@property (nonatomic, assign) BOOL didPlayEntrance;
@property (nonatomic, assign) BOOL editExistingStaff;
@property (nonatomic, assign) BOOL didApplyInitialUserContext;
@property (nonatomic, assign) BOOL suppressModePickerPresentation;
@end

@implementation AddUserViewController
@synthesize rowDescriptor;

- (NSString *)pp_trimmedStringValue:(id)value
{
    NSString *stringValue = @"";
    if ([value isKindOfClass:[XLFormOptionsObject class]]) {
        id formValue = [(XLFormOptionsObject *)value formValue];
        if ([formValue isKindOfClass:[NSString class]]) {
            stringValue = (NSString *)formValue;
        }
    } else if ([value isKindOfClass:[NSString class]]) {
        stringValue = (NSString *)value;
    }
    return [stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (AddUserMode)pp_resolvedModeFromValue:(id)value
{
    return (AddUserMode)PPSafeFormInteger(value);
}

- (PPStaffRole)pp_resolvedRoleFromValue:(id)value
{
    if ([value isKindOfClass:[XLFormOptionsObject class]]) {
        id formValue = [(XLFormOptionsObject *)value formValue];
        if ([formValue isKindOfClass:[NSString class]] && ((NSString *)formValue).length > 0) {
            return (PPStaffRole)formValue;
        }
    } else if ([value isKindOfClass:[NSString class]] && ((NSString *)value).length > 0) {
        return (PPStaffRole)value;
    }
    return PPStaffRoleViewer;
}

- (nullable UserModel *)pp_resolvedSelectedUserFromValue:(id)value
{
    if ([value isKindOfClass:[UserModel class]]) {
        return (UserModel *)value;
    }
    if ([value isKindOfClass:[XLFormOptionsObject class]]) {
        id formValue = [(XLFormOptionsObject *)value formValue];
        if ([formValue isKindOfClass:[UserModel class]]) {
            return (UserModel *)formValue;
        }
    }
    return nil;
}

- (nullable XLFormOptionsObject *)pp_optionMatchingFormValue:(id)formValue
                                                   inOptions:(NSArray<XLFormOptionsObject *> *)options
{
    for (XLFormOptionsObject *option in options) {
        id candidate = option.formValue;
        if ((candidate == formValue) || [candidate isEqual:formValue]) {
            return option;
        }
    }
    return nil;
}

- (instancetype)init {
    XLFormDescriptor *form = [self buildAddUserForm];
    return [super initWithForm:form style:UITableViewStyleInsetGrouped];
}

- (instancetype)initWithStaffMember:(UserModel *)staffMember {
    XLFormDescriptor *form = [self buildAddUserForm];
    self = [super initWithForm:form style:UITableViewStyleInsetGrouped];
    if (self) {
        _selectedUser = staffMember;
        _editExistingStaff = YES;
        self.userModel = staffMember;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self pp_configureTableView];
    [self setupHeaderUI];
    [self pp_updateRoleOptions];
    [self pp_applyDefaultPermissionsForRole:[self.form formRowWithTag:@"role"].value];
    [self pp_applyInitialUserContextIfNeeded];
    [self pp_updateFormVisibility];
    
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
    [self pp_configureNavigationBar];
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self pp_playEntranceAnimationIfNeeded];
}

#pragma mark - Navigation

- (void)pp_configureNavigationBar {
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    [self pp_navBarWithOtherButton:save title:[self pp_navigationTitle]];
}

- (NSString *)pp_navigationTitle {
    return self.editExistingStaff ? kLang(@"Staff_EditMember_Title") : kLang(@"AddStaffMember");
}

- (NSString *)pp_headerTitleText {
    return [self pp_navigationTitle];
}

- (NSString *)pp_headerSubtitleText {
    if (self.editExistingStaff) {
        return kLang(@"Staff_EditMember_Subtitle");
    }

    XLFormRowDescriptor *modeRow = [self.form formRowWithTag:@"mode"];
    AddUserMode mode = [self pp_resolvedModeFromValue:modeRow.value];
    return mode == AddUserModeAssign ? kLang(@"Staff_AssignExistingSubtitle") : kLang(@"AddStaffMemberSubtitle");
}

- (NSString *)pp_headerIconName {
    if (self.editExistingStaff) {
        return @"person.crop.circle.badge.checkmark";
    }

    XLFormRowDescriptor *modeRow = [self.form formRowWithTag:@"mode"];
    AddUserMode mode = [self pp_resolvedModeFromValue:modeRow.value];
    return mode == AddUserModeAssign ? @"person.badge.key.fill" : @"person.badge.plus";
}

#pragma mark - Screen Chrome

- (void)pp_configureTableView {
    self.view.backgroundColor = PPAddUserBackgroundColor();
    self.tableView.backgroundColor = PPAddUserBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 62.0;
    self.tableView.contentInset = UIEdgeInsetsMake(6.0, 0.0, 36.0, 0.0);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 20)];
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
}

#pragma mark - Header (Avatar + Access Summary)

- (void)setupHeaderUI {
    [self pp_installHeaderViewForWidth:CGRectGetWidth(self.view.bounds)];
}

- (void)pp_installHeaderViewForWidth:(CGFloat)width {
    if (width <= 0.0) {
        width = UIScreen.mainScreen.bounds.size.width;
    }
    self.headerWidth = width;

    CGFloat horizontalInset = width > 800.0 ? PPAddUserWideHorizontalInset : PPAddUserHorizontalInset;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 248.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = PPAddUserSurfaceColor();
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    card.layer.cornerRadius = PPAddUserHeaderCornerRadius;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = PPAddUserBorderColor().CGColor;
    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1.0].CGColor;
    card.layer.shadowOpacity = 0.08;
    card.layer.shadowRadius = 24.0;
    card.layer.shadowOffset = CGSizeMake(0, 14.0);
    [header addSubview:card];
    self.heroCard = card;

    UIView *accentWash = [[UIView alloc] init];
    accentWash.translatesAutoresizingMaskIntoConstraints = NO;
    accentWash.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.08];
    accentWash.layer.cornerRadius = 70.0;
    accentWash.layer.masksToBounds = YES;
    [card addSubview:accentWash];

    UIView *avatarShell = [[UIView alloc] init];
    avatarShell.translatesAutoresizingMaskIntoConstraints = NO;
    avatarShell.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.11];
    avatarShell.layer.cornerRadius = 32.0;
    avatarShell.layer.cornerCurve = kCACornerCurveContinuous;
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
    self.addPhotoBtn.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.1];
    self.addPhotoBtn.contentEdgeInsets = UIEdgeInsetsMake(7.0, 12.0, 7.0, 12.0);
    self.addPhotoBtn.imageEdgeInsets = [Language isRTL] ? UIEdgeInsetsMake(0, 6.0, 0, -6.0) : UIEdgeInsetsMake(0, -6.0, 0, 6.0);
    self.addPhotoBtn.layer.cornerRadius = 17.0;
    self.addPhotoBtn.layer.cornerCurve = kCACornerCurveContinuous;
    self.addPhotoBtn.accessibilityLabel = kLang(@"Add Photo");
    [self.addPhotoBtn addTarget:self action:@selector(didTapAddPhoto) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:self.addPhotoBtn];

    UIView *iconShell = [[UIView alloc] init];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.12];
    iconShell.layer.cornerRadius = 18.0;
    iconShell.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self pp_headerIconName]
                                                                       withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = PPAddUserPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];
    self.headerIconView = iconView;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:24];
    titleLabel.textColor = PPAddUserPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.numberOfLines = 2;
    titleLabel.text = [self pp_headerTitleText];
    [card addSubview:titleLabel];
    self.headerTitleLabel = titleLabel;

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [Styling fontRegular:14];
    subtitleLabel.textColor = [PPAddUserSecondaryTextColor() colorWithAlphaComponent:0.9];
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.text = [self pp_headerSubtitleText];
    [card addSubview:subtitleLabel];
    self.headerSubtitleLabel = subtitleLabel;

    self.modeTagLabel = [[PPAddUserTagLabel alloc] init];
    self.roleTagLabel = [[PPAddUserTagLabel alloc] init];
    self.permissionTagLabel = [[PPAddUserTagLabel alloc] init];

    UIStackView *tagStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.modeTagLabel, self.roleTagLabel, self.permissionTagLabel]];
    tagStack.translatesAutoresizingMaskIntoConstraints = NO;
    tagStack.axis = UILayoutConstraintAxisVertical;
    tagStack.alignment = UIStackViewAlignmentLeading;
    tagStack.spacing = 7.0;
    tagStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:tagStack];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:horizontalInset],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-horizontalInset],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14.0],

        [accentWash.widthAnchor constraintEqualToConstant:140.0],
        [accentWash.heightAnchor constraintEqualToConstant:140.0],
        [accentWash.topAnchor constraintEqualToAnchor:card.topAnchor constant:-34.0],
        [accentWash.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:24.0],

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

        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:25.0],
        [iconView.heightAnchor constraintEqualToConstant:25.0],

        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:25.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:iconShell.trailingAnchor constant:14.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:avatarShell.leadingAnchor constant:-14.0],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:avatarShell.leadingAnchor constant:-14.0],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],

        [tagStack.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [tagStack.trailingAnchor constraintLessThanOrEqualToAnchor:avatarShell.leadingAnchor constant:-14.0],
        [tagStack.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:12.0],
        [tagStack.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-18.0]
    ]];

    self.headerRoot = header;
    self.tableView.tableHeaderView = header;
    [header setNeedsLayout];
    [header layoutIfNeeded];
    [self pp_updateHeaderShadowPath];
    [self pp_refreshHeroStateAnimated:NO];
}

- (void)pp_updateHeaderShadowPath {
    if (!self.heroCard) return;
    self.heroCard.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.heroCard.bounds
                                                                cornerRadius:self.heroCard.layer.cornerRadius].CGPath;
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
        [UIView transitionWithView:self.heroCard
                          duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:updates
                        completion:nil];
    } else {
        updates();
    }
}

- (NSString *)pp_currentModeDisplayText {
    if (self.editExistingStaff && self.selectedUser) {
        return kLang(@"Staff_Edit_Existing");
    }
    XLFormRowDescriptor *modeRow = [self.form formRowWithTag:@"mode"];
    if ([modeRow.value isKindOfClass:[XLFormOptionsObject class]]) {
        NSString *displayText = [(XLFormOptionsObject *)modeRow.value displayText];
        if (displayText.length > 0) return displayText;
    }
    AddUserMode mode = [self pp_resolvedModeFromValue:modeRow.value];
    return mode == AddUserModeAssign ? kLang(@"Staff_Assign_Existing") : kLang(@"Staff_Create_New");
}

- (NSString *)pp_currentRoleDisplayText {
    XLFormRowDescriptor *roleRow = [self.form formRowWithTag:@"role"];
    if ([roleRow.value isKindOfClass:[XLFormOptionsObject class]]) {
        NSString *displayText = [(XLFormOptionsObject *)roleRow.value displayText];
        if (displayText.length > 0) return displayText;
    }
    return [PPStaffAuth localizedRoleName:[self pp_resolvedRoleFromValue:roleRow.value]];
}

- (NSUInteger)pp_selectedPermissionCount {
    NSUInteger count = 0;
    for (XLFormSectionDescriptor *section in self.form.formSections) {
        for (XLFormRowDescriptor *row in section.formRows) {
            if ([row.tag containsString:@"."] && [row.value boolValue]) {
                count += 1;
            }
        }
    }
    return count;
}

- (void)pp_playEntranceAnimationIfNeeded {
    if (self.didPlayEntrance) return;
    self.didPlayEntrance = YES;

    self.heroCard.alpha = 0.0;
    self.heroCard.transform = CGAffineTransformMakeTranslation(0.0, 18.0);
    [UIView animateWithDuration:0.55
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.45
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.heroCard.alpha = 1.0;
        self.heroCard.transform = CGAffineTransformIdentity;
    } completion:nil];

    NSArray<UITableViewCell *> *visibleCells = self.tableView.visibleCells;
    [visibleCells enumerateObjectsUsingBlock:^(UITableViewCell *cell, NSUInteger idx, BOOL *stop) {
        cell.alpha = 0.0;
        cell.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
        [UIView animateWithDuration:0.34
                              delay:0.05 + (idx * 0.025)
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

#pragma mark - Form Construction

- (XLFormDescriptor *)buildAddUserForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    // Section: Mode
    XLFormSectionDescriptor *modeSection = [XLFormSectionDescriptor formSection];
    modeSection.hidden = @(self.editExistingStaff);
    [form addFormSection:modeSection];

    XLFormRowDescriptor *modeRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"mode" rowType:XLFormRowDescriptorTypeSelectorSegmentedControl];
    modeRow.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(AddUserModeCreate) displayText:kLang(@"Staff_Create_New")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(AddUserModeAssign) displayText:kLang(@"Staff_Assign_Existing")]
    ];
    modeRow.value = modeRow.selectorOptions.firstObject;
    __weak typeof(self) weakSelf = self;
    modeRow.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *row) {
        [weakSelf pp_updateFormVisibility];
        [weakSelf pp_applyFeatureValuesForCurrentMode];
        if ([weakSelf pp_resolvedModeFromValue:newValue] == AddUserModeAssign && !weakSelf.suppressModePickerPresentation) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf pp_presentExistingUserPickerFromRow:[weakSelf.form formRowWithTag:@"selectedUser"]];
            });
        }
    };
    modeRow.height = 83;
    [modeSection addFormRow:modeRow];

    // Section: Create User Info
    XLFormSectionDescriptor *createSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Staff_New_Account_Info")];
    createSection.hidden = @NO;
    self.createAccountSection = createSection;
    [form addFormSection:createSection];

    [createSection addFormRow:[self pp_textFieldRowWithTag:@"name"
                                                      title:kLang(@"Name")
                                               keyboardType:UIKeyboardTypeDefault
                                                     secure:NO
                                             capitalization:UITextAutocapitalizationTypeWords]];
    [createSection addFormRow:[self pp_textFieldRowWithTag:@"email"
                                                      title:kLang(@"Email")
                                               keyboardType:UIKeyboardTypeEmailAddress
                                                     secure:NO
                                             capitalization:UITextAutocapitalizationTypeNone]];
    [createSection addFormRow:[self pp_textFieldRowWithTag:@"password"
                                                      title:kLang(@"Password")
                                               keyboardType:UIKeyboardTypeDefault
                                                     secure:YES
                                             capitalization:UITextAutocapitalizationTypeNone]];

    // Section: Assign User Info
    XLFormSectionDescriptor *assignSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Staff_Select_Existing_User")];
    assignSection.hidden = @YES;
    self.assignExistingSection = assignSection;
    [form addFormSection:assignSection];

    XLFormRowDescriptor *userPicker = [XLFormRowDescriptor formRowDescriptorWithTag:@"selectedUser" rowType:XLFormRowDescriptorTypeSelectorPush title:kLang(@"User")];
    userPicker.action.formBlock = ^(XLFormRowDescriptor * _Nonnull rowDescriptor) {
        [weakSelf pp_presentExistingUserPickerFromRow:rowDescriptor];
    };
    userPicker.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *row) {
        UserModel *user = [weakSelf pp_resolvedSelectedUserFromValue:newValue];
        if (user && ![weakSelf.selectedUser.uid isEqualToString:user.uid]) {
            [weakSelf pp_handlePickedExistingUser:user row:row];
        } else {
            [weakSelf pp_applyFeatureValuesFromSelectedUserValue:newValue];
        }
    };
    [assignSection addFormRow:userPicker];

    // Section: Role & Status
    XLFormSectionDescriptor *roleSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Staff_Role_Status")];
    [form addFormSection:roleSection];

    XLFormRowDescriptor *roleRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"role" rowType:XLFormRowDescriptorTypeSelectorPush title:kLang(@"Staff_Role")];
    roleRow.action.viewControllerClass = [PPOptionsViewController class];
    roleRow.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *row) {
        [weakSelf pp_applyDefaultPermissionsForRole:newValue];
    };
    [roleSection addFormRow:roleRow];

    XLFormRowDescriptor *statusRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"status" rowType:XLFormRowDescriptorTypeBooleanSwitch title:kLang(@"Active")];
    statusRow.value = @YES;
    [roleSection addFormRow:statusRow];

    // Section: User Features
    XLFormSectionDescriptor *featuresSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Features")];
    featuresSection.hidden = @(![self pp_canManageUserFeatures]);
    [form addFormSection:featuresSection];
    for (NSDictionary<NSString *, NSString *> *feature in [self pp_featureDefinitions]) {
        NSString *featureKey = feature[@"key"];
        NSString *titleKey = feature[@"titleKey"];
        XLFormRowDescriptor *featureRow = [XLFormRowDescriptor formRowDescriptorWithTag:[self pp_featureFormTagForKey:featureKey]
                                                                                rowType:XLFormRowDescriptorTypeBooleanSwitch
                                                                                  title:kLang(titleKey)];
        featureRow.value = @([[self pp_defaultUserFeatures][featureKey] boolValue]);
        [featuresSection addFormRow:featureRow];
    }

    // Section: Permissions
    XLFormSectionDescriptor *permSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Permissions_Title")];
    [form addFormSection:permSection];

    for (PermissionModule *mod in [self pp_allPermissionModules]) {
        for (PermissionAction *action in mod.actions) {
            NSString *label = [Language isRTL] ? action.labelAr : action.labelEn;
            XLFormRowDescriptor *pRow = [XLFormRowDescriptor formRowDescriptorWithTag:action.key rowType:XLFormRowDescriptorTypeBooleanSwitch title:label];
            pRow.value = @NO;
            pRow.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *row) {
                [weakSelf pp_refreshHeroStateAnimated:YES];
            };
            [permSection addFormRow:pRow];
        }
    }

    self.form = form;
    return form;
}

- (void)pp_updateFormVisibility {
    XLFormRowDescriptor *modeRow = [self.form formRowWithTag:@"mode"];
    AddUserMode mode = [self pp_resolvedModeFromValue:modeRow.value];
    BOOL isCreateMode = (mode == AddUserModeCreate) || self.editExistingStaff;

    self.createAccountSection.hidden = @(!isCreateMode);
    self.assignExistingSection.hidden = @(isCreateMode);

    [UIView transitionWithView:self.tableView
                      duration:0.18
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{
        [self.tableView reloadData];
    } completion:nil];
    [self pp_refreshHeroStateAnimated:YES];
}

#pragma mark - Existing User Picker / Staff Editing

- (void)pp_applyInitialUserContextIfNeeded {
    if (self.didApplyInitialUserContext) return;

    UserModel *initialUser = self.selectedUser ?: self.userModel;
    if (!initialUser) return;

    self.didApplyInitialUserContext = YES;
    self.selectedUser = initialUser;
    self.userModel = initialUser;
    self.editExistingStaff = YES;

    [self pp_setMode:AddUserModeAssign disabled:YES];
    XLFormRowDescriptor *userRow = [self.form formRowWithTag:@"selectedUser"];
    userRow.value = initialUser;
    [self reloadFormRow:userRow];
    [self pp_applyStaffValuesFromUser:initialUser];
    [self pp_configureNavigationBar];
}

- (void)pp_setMode:(AddUserMode)mode disabled:(BOOL)disabled {
    XLFormRowDescriptor *modeRow = [self.form formRowWithTag:@"mode"];
    XLFormOptionsObject *option = [self pp_optionMatchingFormValue:@(mode) inOptions:modeRow.selectorOptions];

    self.suppressModePickerPresentation = YES;
    modeRow.value = option ?: @(mode);
    modeRow.disabled = @(disabled);
    self.suppressModePickerPresentation = NO;

    [self reloadFormRow:modeRow];
    [self pp_updateFormVisibility];
}

- (void)pp_presentExistingUserPickerFromRow:(XLFormRowDescriptor *)rowDescriptor {
    if (!self.isViewLoaded || self.presentedViewController) {
        return;
    }

    XLFormRowDescriptor *targetRow = rowDescriptor ?: [self.form formRowWithTag:@"selectedUser"];
    [self pp_setMode:AddUserModeAssign disabled:self.editExistingStaff];

    SetUserPermissionViewController *picker = [[SetUserPermissionViewController alloc] initWithViewFor:ViewForPicker];
    picker.rowDescriptor = targetRow;
    picker.searchPlaceholderText = kLang(@"Staff_Select_User_Search_Placeholder");

    __weak typeof(self) weakSelf = self;
    picker.onUserPicked = ^(UserModel *user) {
        [weakSelf pp_handlePickedExistingUser:user row:targetRow];
    };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[
            [UISheetPresentationControllerDetent mediumDetent],
            [UISheetPresentationControllerDetent largeDetent]
        ];
        sheet.prefersGrabberVisible = YES;
        sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    }

    [self presentViewController:nav animated:YES completion:nil];
}

- (void)pp_handlePickedExistingUser:(UserModel *)user row:(XLFormRowDescriptor *)row {
    if (!user) return;

    BOOL userIsStaff = [self pp_userLooksLikeStaff:user];
    if (self.selectedUser.uid.length > 0 &&
        [self.selectedUser.uid isEqualToString:user.uid] &&
        self.editExistingStaff == userIsStaff) {
        [self pp_applyFeatureValuesFromSelectedUserValue:user];
        return;
    }

    self.selectedUser = user;
    self.userModel = user;
    self.editExistingStaff = userIsStaff;

    XLFormRowDescriptor *targetRow = row ?: [self.form formRowWithTag:@"selectedUser"];
    targetRow.value = user;
    [self reloadFormRow:targetRow];
    [self pp_setMode:AddUserModeAssign disabled:NO];

    if (userIsStaff) {
        [self pp_applyStaffValuesFromUser:user];
        [self pp_configureNavigationBar];
        return;
    }

    [self pp_showNormalUserUpgradePromptForUser:user row:targetRow];
}

- (void)pp_showNormalUserUpgradePromptForUser:(UserModel *)user row:(XLFormRowDescriptor *)row {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Staff_NormalUserUpgrade_Title")
                                                                   message:kLang(@"Staff_NormalUserUpgrade_Message")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        weakSelf.selectedUser = nil;
        weakSelf.userModel = nil;
        weakSelf.editExistingStaff = NO;
        row.value = nil;
        [weakSelf reloadFormRow:row];
        [weakSelf pp_applyFeatureValuesForCurrentMode];
        [weakSelf pp_refreshHeroStateAnimated:YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Staff_NormalUserUpgrade_Confirm")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf pp_prepareNormalUserUpgrade:user];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pp_prepareNormalUserUpgrade:(UserModel *)user {
    self.selectedUser = user;
    self.userModel = user;
    self.editExistingStaff = NO;
    [self pp_setMode:AddUserModeAssign disabled:NO];
    [self pp_applyFeatureValuesFromSelectedUserValue:user];
    [self pp_applyDefaultPermissionsForRole:[self.form formRowWithTag:@"role"].value];
    [self pp_configureNavigationBar];
}

- (BOOL)pp_userLooksLikeStaff:(UserModel *)user {
    NSString *accountType = PPSafeString(user.accountType).lowercaseString;
    if ([accountType isEqualToString:@"staff"]) return YES;
    if (user.staffProfile.count > 0) return YES;
    if (PPSafeString(user.staffRole).length > 0) return YES;
    return NO;
}

- (PPStaffRole)pp_staffRoleForUser:(UserModel *)user {
    NSDictionary *profile = PPSafeDict(user.staffProfile);
    NSString *role = PPSafeString(profile[@"role"]);
    if (role.length == 0) role = PPSafeString(user.staffRole);
    if (role.length == 0) role = PPSafeString(profile[@"roleName"]);
    if (role.length == 0) role = PPSafeString(profile[@"roleValue"]);
    if (role.length > 0) return (PPStaffRole)role;
    return [PPStaffAuth staffRoleFromLegacyRole:user.role];
}

- (NSArray<NSString *> *)pp_staffPermissionsForUser:(UserModel *)user role:(PPStaffRole)role {
    NSDictionary *profile = PPSafeDict(user.staffProfile);
    NSMutableOrderedSet<NSString *> *permissions = [NSMutableOrderedSet orderedSet];

    void (^collectFromValue)(id) = ^(id value) {
        if ([value isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)value) {
                NSString *key = PPSafeString(item);
                if ([key containsString:@"."]) {
                    [permissions addObject:key];
                }
            }
        } else if ([value isKindOfClass:NSDictionary.class]) {
            NSDictionary *dictionary = (NSDictionary *)value;
            for (id rawKey in dictionary) {
                NSString *key = PPSafeString(rawKey);
                if (![key containsString:@"."]) continue;

                id rawValue = dictionary[rawKey];
                BOOL allowed = NO;
                if ([rawValue isKindOfClass:NSDictionary.class]) {
                    allowed = [rawValue[@"allowed"] respondsToSelector:@selector(boolValue)] ? [rawValue[@"allowed"] boolValue] : NO;
                } else if ([rawValue respondsToSelector:@selector(boolValue)]) {
                    allowed = [rawValue boolValue];
                }
                if (allowed) {
                    [permissions addObject:key];
                }
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
    NSDictionary *profile = PPSafeDict(user.staffProfile);
    NSString *status = PPSafeString(profile[@"status"]).lowercaseString;
    if (status.length == 0) status = PPSafeString(user.accountStatus).lowercaseString;
    if (status.length == 0) status = @"active";
    return ![status isEqualToString:PPStaffStatusDisabled] && ![status isEqualToString:@"blocked"] && !user.isBlocked;
}

- (void)pp_applyStaffValuesFromUser:(UserModel *)user {
    PPStaffRole role = [self pp_staffRoleForUser:user];
    NSArray<NSString *> *permissions = [self pp_staffPermissionsForUser:user role:role];

    [self pp_applyRoleValue:role];

    XLFormRowDescriptor *statusRow = [self.form formRowWithTag:@"status"];
    statusRow.value = @([self pp_staffUserIsActive:user]);
    [self reloadFormRow:statusRow];

    [self pp_applyPermissionValues:permissions];
    [self pp_applyFeatureValuesFromSelectedUserValue:user];
    [self pp_refreshHeroStateAnimated:YES];
}

- (void)pp_applyRoleValue:(PPStaffRole)role {
    XLFormRowDescriptor *roleRow = [self.form formRowWithTag:@"role"];
    XLFormOptionsObject *option = [self pp_optionMatchingFormValue:role inOptions:roleRow.selectorOptions];
    if (option) {
        roleRow.value = option;
        [self reloadFormRow:roleRow];
    }
}

- (void)pp_applyPermissionValues:(NSArray<NSString *> *)permissions {
    NSSet<NSString *> *activePermissions = [NSSet setWithArray:permissions ?: @[]];
    for (XLFormSectionDescriptor *sec in self.form.formSections) {
        for (XLFormRowDescriptor *row in sec.formRows) {
            if ([row.tag containsString:@"."]) {
                row.value = @([activePermissions containsObject:row.tag]);
                [self reloadFormRow:row];
            }
        }
    }
}

- (XLFormRowDescriptor *)pp_textFieldRowWithTag:(NSString *)tag
                                          title:(NSString *)title
                                   keyboardType:(UIKeyboardType)keyboardType
                                         secure:(BOOL)secure
                                 capitalization:(UITextAutocapitalizationType)capitalization {
    XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:tag
                                                                     rowType:XLFormRowDescriptorTypePPTextField
                                                                       title:title];
    row.cellConfigAtConfigure[@"keyboardType"] = @(keyboardType);
    row.cellConfigAtConfigure[@"secure"] = @(secure);
    row.cellConfigAtConfigure[@"autocapitalizationType"] = @(capitalization);
    row.cellConfigAtConfigure[@"autocorrectionType"] = @(UITextAutocorrectionTypeNo);
    row.cellConfigAtConfigure[@"returnKeyType"] = @(UIReturnKeyDone);
    [Styling setRowFonts:row];
    return row;
}

- (void)pp_updateRoleOptions {
    NSMutableArray *options = [NSMutableArray array];
    
    // System Roles
    NSArray *systemRoles = @[
        PPStaffRoleSuperAdmin, PPStaffRoleOwner, PPStaffRoleOperationsManager,
        PPStaffRoleInventoryManager, PPStaffRolePaymentsManager, PPStaffRoleSupportAgent, PPStaffRoleViewer
    ];
    
    for (PPStaffRole role in systemRoles) {
        [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:role displayText:[PPStaffAuth localizedRoleName:role]]];
    }
    
    // Custom Roles
    for (StaffRoleTemplate *role in self.customRoles) {
        NSString *name = [Language isRTL] ? role.name[@"ar"] : role.name[@"en"];
        [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:[NSString stringWithFormat:@"custom_%@", role.id] displayText:name]];
    }
    
    XLFormRowDescriptor *roleRow = [self.form formRowWithTag:@"role"];
    roleRow.selectorOptions = options;
    XLFormOptionsObject *currentOption = [self pp_optionMatchingFormValue:[self pp_resolvedRoleFromValue:roleRow.value]
                                                                inOptions:options];
    XLFormOptionsObject *viewerOption = [self pp_optionMatchingFormValue:PPStaffRoleViewer inOptions:options];
    roleRow.value = currentOption ?: viewerOption ?: options.firstObject;
    [self reloadFormRow:roleRow];
    [self pp_refreshHeroStateAnimated:YES];
}

- (void)pp_applyDefaultPermissionsForRole:(id)roleValue {
    PPStaffRole role = [self pp_resolvedRoleFromValue:roleValue];
    NSArray *defaults = [PPStaffAuth defaultPermissionsForStaffRole:role];
    
    // If custom role, find it and use its permissions
    if ([role hasPrefix:@"custom_"]) {
        NSString *roleID = [role substringFromIndex:7];
        for (StaffRoleTemplate *t in self.customRoles) {
            if ([t.id isEqualToString:roleID]) {
                defaults = t.permissions;
                break;
            }
        }
    }
    
    for (XLFormSectionDescriptor *sec in self.form.formSections) {
        for (XLFormRowDescriptor *row in sec.formRows) {
            if ([row.tag containsString:@"."]) { // It's a permission row
                row.value = @([defaults containsObject:row.tag]);
                [self reloadFormRow:row];
            }
        }
    }
    [self pp_refreshHeroStateAnimated:YES];
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
    NSDictionary *values = [self formValues];
    AddUserMode mode = [self pp_resolvedModeFromValue:values[@"mode"]];
    if (mode == AddUserModeAssign) {
        [self pp_applyFeatureValuesFromSelectedUserValue:values[@"selectedUser"]];
        return;
    }
    [self pp_applyFeatureValues:[self pp_defaultUserFeatures]];
}

- (void)pp_applyFeatureValuesFromSelectedUserValue:(id)value {
    UserModel *user = [self pp_resolvedSelectedUserFromValue:value];
    NSDictionary *features = user.features.count ? user.features : [self pp_defaultUserFeatures];
    [self pp_applyFeatureValues:features];
}

- (void)pp_applyFeatureValues:(NSDictionary *)features {
    NSDictionary *safeFeatures = features.count ? features : [self pp_defaultUserFeatures];
    for (NSDictionary<NSString *, NSString *> *feature in [self pp_featureDefinitions]) {
        NSString *featureKey = feature[@"key"];
        XLFormRowDescriptor *row = [self.form formRowWithTag:[self pp_featureFormTagForKey:featureKey]];
        if (!row) continue;
        id value = safeFeatures[featureKey];
        row.value = @([value respondsToSelector:@selector(boolValue)] ? [value boolValue] : [[self pp_defaultUserFeatures][featureKey] boolValue]);
        [self reloadFormRow:row];
    }
}

- (NSDictionary<NSString *, NSNumber *> *)pp_featurePayloadFromValues:(NSDictionary *)values {
    NSMutableDictionary<NSString *, NSNumber *> *features = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, NSString *> *feature in [self pp_featureDefinitions]) {
        NSString *featureKey = feature[@"key"];
        NSString *tag = [self pp_featureFormTagForKey:featureKey];
        id value = values[tag];
        features[featureKey] = @([value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO);
    }
    return features.copy;
}

#pragma mark - Save

- (void)onSave {
    NSDictionary *values = [self formValues];
    AddUserMode mode = [self pp_resolvedModeFromValue:values[@"mode"]];
    PPStaffRole role = [self pp_resolvedRoleFromValue:values[@"role"]];
    NSDictionary<NSString *, NSNumber *> *features = [self pp_canManageUserFeatures] ? [self pp_featurePayloadFromValues:values] : nil;
    
    NSMutableArray *permissions = [NSMutableArray array];
    for (NSString *key in values.allKeys) {
        if ([key containsString:@"."] && [values[key] boolValue]) {
            [permissions addObject:key];
        }
    }

    if (mode == AddUserModeCreate) {
        NSString *email = [[self pp_trimmedStringValue:values[@"email"]] lowercaseString];
        NSString *name = [self pp_trimmedStringValue:values[@"name"]];
        NSString *password = [self pp_trimmedStringValue:values[@"password"]];

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
            }
            else {
                NSString *uid = PPSafeString(result[@"uid"]);
                [self pp_finishStaffSaveForUID:uid features:features];
            }
        }];
    } else {
        UserModel *user = self.selectedUser ?: [self pp_resolvedSelectedUserFromValue:values[@"selectedUser"]];
        if (!user) {
            [PPHUD showError:kLang(@"Error_SelectUser")];
            return;
        }

        [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:@""];

        BOOL active = [values[@"status"] respondsToSelector:@selector(boolValue)] ? [values[@"status"] boolValue] : YES;
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
                }
                else {
                    [self pp_finishStaffSaveForUID:user.uid features:features];
                }
            }];
            return;
        }

        [AdminService assignExistingUserAsStaff:user.uid role:role permissions:permissions scope:nil completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) {
                [PPHUD dismiss];
                [PPHUD showError:error.localizedDescription];
            }
            else {
                [self pp_finishStaffSaveForUID:user.uid features:features];
            }
        }];
    }
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
    
    // Dashboard
    PermissionModule *dashboard = [PermissionModule new];
    dashboard.key = @"dashboard";
    dashboard.labelEn = @"Dashboard";
    dashboard.labelAr = @"لوحة التحكم";
    PermissionAction *dView = [PermissionAction new]; dView.key = @"dashboard.view"; dView.labelEn = @"View dashboard"; dView.labelAr = @"عرض لوحة التحكم";
    dashboard.actions = @[dView];
    [modules addObject:dashboard];
    
    // Staff
    PermissionModule *staff = [PermissionModule new];
    staff.key = @"staff";
    staff.labelEn = @"Staff";
    staff.labelAr = @"الموظفون";
    PermissionAction *sView = [PermissionAction new]; sView.key = @"staff.view"; sView.labelEn = @"View staff"; sView.labelAr = @"عرض الموظفين";
    PermissionAction *sManage = [PermissionAction new]; sManage.key = @"staff.manage"; sManage.labelEn = @"Manage staff"; sManage.labelAr = @"إدارة الموظفين";
    staff.actions = @[sView, sManage];
    [modules addObject:staff];
    
    // Users
    PermissionModule *users = [PermissionModule new];
    users.key = @"users";
    users.labelEn = @"Users";
    users.labelAr = @"المستخدمون";
    PermissionAction *uView = [PermissionAction new]; uView.key = @"users.view"; uView.labelEn = @"View users"; uView.labelAr = @"عرض المستخدمين";
    PermissionAction *uManage = [PermissionAction new]; uManage.key = @"users.manage"; uManage.labelEn = @"Manage users"; uManage.labelAr = @"إدارة المستخدمين";
    PermissionAction *uBlock = [PermissionAction new]; uBlock.key = @"users.block"; uBlock.labelEn = @"Block / unblock users"; uBlock.labelAr = @"حظر / إلغاء حظر المستخدمين";
    users.actions = @[uView, uManage, uBlock];
    [modules addObject:users];
    
    // Stock
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

    // Listings
    PermissionModule *listings = [PermissionModule new];
    listings.key = @"listings";
    listings.labelEn = @"Listings";
    listings.labelAr = @"الإعلانات";
    PermissionAction *lView = [PermissionAction new]; lView.key = @"listings.view"; lView.labelEn = @"View listings"; lView.labelAr = @"عرض الإعلانات";
    PermissionAction *lManage = [PermissionAction new]; lManage.key = @"listings.manage"; lManage.labelEn = @"Manage listings"; lManage.labelAr = @"إدارة الإعلانات";
    PermissionAction *lModerate = [PermissionAction new]; lModerate.key = @"listings.moderate"; lModerate.labelEn = @"Moderate listings"; lModerate.labelAr = @"مراجعة الإعلانات";
    listings.actions = @[lView, lManage, lModerate];
    [modules addObject:listings];

    // Payments
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

#pragma mark - Table Styling

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    XLFormSectionDescriptor *formSection = [self.form formSectionAtIndex:section];
    if (formSection.title.length == 0) {
        return [UIView new];
    }

    UIView *container = [[UIView alloc] init];
    container.backgroundColor = UIColor.clearColor;
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontMedium:13];
    titleLabel.textColor = [PPAddUserSecondaryTextColor() colorWithAlphaComponent:0.92];
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.text = formSection.title;
    [container addSubview:titleLabel];

    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [PPAddUserPrimaryColor() colorWithAlphaComponent:0.12];
    line.layer.cornerRadius = 0.5;
    [container addSubview:line];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:7.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPAddUserHorizontalInset + 2.0],
        [titleLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],

        [line.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLabel.trailingAnchor constant:12.0],
        [line.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-(PPAddUserHorizontalInset + 2.0)],
        [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [line.widthAnchor constraintGreaterThanOrEqualToConstant:24.0]
    ]];

    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    XLFormSectionDescriptor *formSection = [self.form formSectionAtIndex:section];
    return formSection.title.length > 0 ? 34.0 : 12.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == tableView.numberOfSections - 1 ? 12.0 : 16.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    UIView *footer = [[UIView alloc] init];
    footer.backgroundColor = UIColor.clearColor;
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self.form formRowAtIndex:indexPath];
    if ([row.rowType isEqualToString:XLFormRowDescriptorTypePPTextField]) {
        return 64.0;
    }
    if ([row.rowType isEqualToString:XLFormRowDescriptorTypeSelectorSegmentedControl]) {
        return 58.0;
    }
    return 58.0;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self.form formRowAtIndex:indexPath];
    BOOL isModeRow = [row.tag isEqualToString:@"mode"];
    BOOL isFeatureRow = [row.tag hasPrefix:@"feature_"];
    BOOL isPermissionRow = [row.tag containsString:@"."];
    UIColor *accentColor = PPAddUserPrimaryColor();

    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.clipsToBounds = NO;
    cell.layer.shadowOpacity = 0.0;
    cell.separatorInset = UIEdgeInsetsMake(0, tableView.bounds.size.width, 0, 0);
    cell.tintColor = accentColor;

    UIEdgeInsets insets = UIEdgeInsetsMake(isModeRow ? 4.0 : 0.0,
                                           PPAddUserHorizontalInset,
                                           isModeRow ? 4.0 : 0.0,
                                           PPAddUserHorizontalInset);
    CGRect backgroundFrame = UIEdgeInsetsInsetRect(cell.bounds, insets);
    UIView *backgroundView = cell.backgroundView ?: [[UIView alloc] initWithFrame:backgroundFrame];
    backgroundView.frame = backgroundFrame;
    backgroundView.layer.cornerRadius = isModeRow ? 24.0 : PPAddUserCardCornerRadius;
    backgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    backgroundView.layer.maskedCorners = [self pp_maskedCornersForIndexPath:indexPath standalone:isModeRow];
    backgroundView.layer.masksToBounds = YES;
    backgroundView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    backgroundView.layer.borderColor = (isFeatureRow || isPermissionRow
        ? [accentColor colorWithAlphaComponent:0.1]
        : PPAddUserBorderColor()).CGColor;
    backgroundView.backgroundColor = isModeRow
        ? [accentColor colorWithAlphaComponent:0.08]
        : PPAddUserSurfaceColor();
    cell.backgroundView = backgroundView;

    UIView *selectedBackgroundView = cell.selectedBackgroundView ?: [[UIView alloc] initWithFrame:backgroundFrame];
    selectedBackgroundView.frame = backgroundFrame;
    selectedBackgroundView.layer.cornerRadius = backgroundView.layer.cornerRadius;
    selectedBackgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    selectedBackgroundView.layer.maskedCorners = backgroundView.layer.maskedCorners;
    selectedBackgroundView.layer.masksToBounds = YES;
    selectedBackgroundView.backgroundColor = [accentColor colorWithAlphaComponent:0.09];
    cell.selectedBackgroundView = selectedBackgroundView;

    cell.textLabel.font = [Styling fontMedium:15];
    cell.textLabel.textColor = PPAddUserPrimaryTextColor();
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.textAlignment = Language.alignmentForCurrentLanguage;
    cell.detailTextLabel.font = [Styling fontBold:15];
    cell.detailTextLabel.textColor = PPAddUserPrimaryTextColor();
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;

    if ([cell isKindOfClass:PPTextFieldCell.class]) {
        PPTextFieldCell *fieldCell = (PPTextFieldCell *)cell;
        fieldCell.textField.backgroundColor = [accentColor colorWithAlphaComponent:0.055];
        fieldCell.textField.textColor = PPAddUserPrimaryTextColor();
        fieldCell.textField.layer.cornerRadius = 20.0;
        fieldCell.textField.layer.cornerCurve = kCACornerCurveContinuous;
        fieldCell.textField.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        fieldCell.textField.layer.borderColor = [accentColor colorWithAlphaComponent:0.1].CGColor;
        fieldCell.textField.clipsToBounds = YES;
    } else if ([row.rowType isEqualToString:XLFormRowDescriptorTypeBooleanSwitch]) {
        cell.textLabel.font = [Styling fontBold:(isFeatureRow ? 15 : 14)];
        UISwitch *switchControl = [cell.accessoryView isKindOfClass:UISwitch.class] ? (UISwitch *)cell.accessoryView : nil;
        switchControl.onTintColor = accentColor;
    } else if ([row.rowType isEqualToString:XLFormRowDescriptorTypeSelectorSegmentedControl] && [cell isKindOfClass:XLFormSegmentedCell.class]) {
        XLFormSegmentedCell *segmentedCell = (XLFormSegmentedCell *)cell;
        segmentedCell.textLabel.textColor = UIColor.clearColor;
        segmentedCell.textLabel.font = [Styling fontMedium:1];
        segmentedCell.segmentedControl.selectedSegmentTintColor = accentColor;
        segmentedCell.segmentedControl.backgroundColor = [accentColor colorWithAlphaComponent:0.08];
        segmentedCell.segmentedControl.layer.cornerRadius = 20.0;
        segmentedCell.segmentedControl.layer.cornerCurve = kCACornerCurveContinuous;
        segmentedCell.segmentedControl.layer.masksToBounds = YES;
        segmentedCell.segmentedControl.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        segmentedCell.segmentedControl.layer.borderColor = [accentColor colorWithAlphaComponent:0.12].CGColor;
        NSDictionary *normalAttributes = @{
            NSFontAttributeName: [Styling fontMedium:13],
            NSForegroundColorAttributeName: PPAddUserPrimaryTextColor()
        };
        NSDictionary *selectedAttributes = @{
            NSFontAttributeName: [Styling fontBold:13],
            NSForegroundColorAttributeName: UIColor.whiteColor
        };
        [segmentedCell.segmentedControl setTitleTextAttributes:normalAttributes forState:UIControlStateNormal];
        [segmentedCell.segmentedControl setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
    }
}

- (CACornerMask)pp_maskedCornersForIndexPath:(NSIndexPath *)indexPath standalone:(BOOL)standalone {
    if (standalone) {
        return kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }

    NSInteger rows = [self.tableView numberOfRowsInSection:indexPath.section];
    if (rows <= 1) {
        return kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    if (indexPath.row == 0) {
        return kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    if (indexPath.row == rows - 1) {
        return kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    return 0;
}

#pragma mark - PPImageCollectionDelegate

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
    UIImage *picked = images.firstObject;
    if (!picked) return;
    self.pendingAvatarImage = picked;
    self.avatarIMV.image = picked;
}

- (void)reloadFormRow:(XLFormRowDescriptor *)row {
    if (!row) return;
    NSIndexPath *ip = [self.form indexPathOfFormRow:row];
    if (ip) [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

@end
