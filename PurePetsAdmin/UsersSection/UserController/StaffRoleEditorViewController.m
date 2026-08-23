//
//  StaffRoleEditorViewController.m
//  PurePetsAdmin
//

#import "StaffRoleEditorViewController.h"
#import "Styling.h"
#import "Language.h"
#import "PPStaffAuth.h"
#import "AdminService.h"
#import "PPToast.h"
#import "PPAlertHelper.h"
#import "PPRolePermission.h"
#import "PPHero.h"
#import "PPFormEngine.h"

static CGFloat const PPRoleEditorHorizontalInset = 18.0;
static CGFloat const PPRoleEditorWideHorizontalInset = 28.0;

static UIColor *PPRoleEditorSurfaceColor(void) {
    return [UIColor ppElevatedSurface];
}

static UIColor *PPRoleEditorBackgroundColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPRoleEditorPrimaryColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPRoleEditorPrimaryTextColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPRoleEditorSecondaryTextColor(void) {
    return [UIColor ppTextSecondary];
}

static UIColor *PPRoleEditorBorderColor(void) {
    return [PPRoleEditorPrimaryColor() colorWithAlphaComponent:0.08];
}

static PermissionAction *PPRoleEditorAction(NSString *key, NSString *labelKey) {
    PermissionAction *action = [PermissionAction new];
    action.key = key ?: @"";
    action.labelEn = labelKey ?: @"";
    action.labelAr = labelKey ?: @"";
    return action;
}

static PermissionModule *PPRoleEditorModule(NSString *key, NSString *labelKey, NSArray<PermissionAction *> *actions) {
    PermissionModule *module = [PermissionModule new];
    module.key = key ?: @"";
    module.labelEn = labelKey ?: @"";
    module.labelAr = labelKey ?: @"";
    module.actions = actions ?: @[];
    return module;
}

@interface StaffRoleEditorViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *permissionSummaryLabel;
@property (nonatomic, strong) PPFormEngineView *infoFormView;
@property (nonatomic, strong) NSMutableArray<PPFormEngineView *> *permissionFormViews;
@property (nonatomic, copy) NSArray<PermissionModule *> *permissionModules;
@property (nonatomic, assign) BOOL didPlayEntrance;
@end

@implementation StaffRoleEditorViewController

- (instancetype)initWithRole:(StaffRoleTemplate *)role {
    self = [super init];
    if (self) {
        _roleTemplate = role;
        _permissionFormViews = [NSMutableArray array];
        _permissionModules = [self pp_allPermissionModules];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self pp_buildUI];
    [self pp_prepareEntranceState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    [self pp_navBarWithOtherButton:save title:[self pp_navigationTitle]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroBackground startAnimations];
    [self pp_playEntranceIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.heroBackground stopAnimations];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.heroBackground reapplyPalette];
    }
}

#pragma mark - UI

- (NSString *)pp_navigationTitle {
    return self.roleTemplate ? kLang(@"EditRole") : kLang(@"NewRole");
}

- (void)pp_buildUI {
    self.view.backgroundColor = PPRoleEditorBackgroundColor();

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = PPRoleEditorBackgroundColor();
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
    self.contentStack.alignment = UIStackViewAlignmentFill;
    self.contentStack.spacing = 16.0;
    self.contentStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.contentView addSubview:self.contentStack];

    CGFloat horizontalInset = CGRectGetWidth(UIScreen.mainScreen.bounds) > 800.0 ? PPRoleEditorWideHorizontalInset : PPRoleEditorHorizontalInset;
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

        [self.contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:horizontalInset],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-horizontalInset],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-34.0],
    ]];

    [self.contentStack addArrangedSubview:[self pp_buildHeroCard]];
    [self.contentStack addArrangedSubview:[self pp_buildInfoSection]];
    [self.contentStack addArrangedSubview:[self pp_buildPermissionsIntroSection]];

    for (PermissionModule *module in self.permissionModules) {
        [self.contentStack addArrangedSubview:[self pp_buildPermissionSectionForModule:module]];
    }

    [self pp_updatePermissionSummary];
}

- (UIView *)pp_buildHeroCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    [card.heightAnchor constraintEqualToConstant:174.0].active = YES;
    self.heroCard = card;

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentColorOverride = PPRoleEditorPrimaryColor();
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.62;
    [card addSubview:hero];
    self.heroBackground = hero;

    UIView *iconShell = [[UIView alloc] init];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPRoleEditorPrimaryColor() colorWithAlphaComponent:0.13];
    iconShell.layer.cornerRadius = 20.0;
    [card addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = PPRoleEditorPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = [self pp_navigationTitle];
    titleLabel.font = [Styling fontBold:26.0];
    titleLabel.textColor = PPRoleEditorPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.82;
    [card addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = kLang(@"RoleEditor_Subtitle");
    subtitleLabel.font = [Styling fontRegular:14.0];
    subtitleLabel.textColor = [PPRoleEditorSecondaryTextColor() colorWithAlphaComponent:0.92];
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.numberOfLines = 2;
    [card addSubview:subtitleLabel];

    UILabel *summary = [[UILabel alloc] init];
    summary.translatesAutoresizingMaskIntoConstraints = NO;
    summary.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
    summary.textColor = PPRoleEditorPrimaryColor();
    summary.textAlignment = NSTextAlignmentCenter;
    summary.backgroundColor = [PPRoleEditorPrimaryColor() colorWithAlphaComponent:0.1];
    summary.layer.cornerRadius = 15.0;
    summary.layer.masksToBounds = YES;
    [card addSubview:summary];
    self.permissionSummaryLabel = summary;

    [NSLayoutConstraint activateConstraints:@[
        [hero.topAnchor constraintEqualToAnchor:card.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [iconShell.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22.0],
        [iconShell.topAnchor constraintEqualToAnchor:card.topAnchor constant:24.0],
        [iconShell.widthAnchor constraintEqualToConstant:56.0],
        [iconShell.heightAnchor constraintEqualToConstant:56.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [summary.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22.0],
        [summary.topAnchor constraintEqualToAnchor:card.topAnchor constant:24.0],
        [summary.widthAnchor constraintGreaterThanOrEqualToConstant:86.0],
        [summary.heightAnchor constraintEqualToConstant:30.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconShell.trailingAnchor constant:14.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:summary.leadingAnchor constant:-12.0],
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:26.0],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22.0],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10.0],
    ]];

    return card;
}

- (UIView *)pp_buildInfoSection {
    UIView *section = [self pp_makePlainSectionWithTitle:kLang(@"Role_Info") subtitle:nil];
    UIStackView *stack = (UIStackView *)section.subviews.firstObject;

    self.infoFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    self.infoFormView.validatesOnChange = NO;

    PPFormFieldConfig *nameEn = [PPFormFieldConfig fieldWithIdentifier:@"nameEn"
                                                                  title:kLang(@"RoleNameEn")
                                                            placeholder:kLang(@"RoleNameEn")
                                                              inputType:PPFormInputTypeText];
    nameEn.value = [self pp_localizedRoleValueForKey:@"en" source:self.roleTemplate.name];
    nameEn.required = YES;

    PPFormFieldConfig *nameAr = [PPFormFieldConfig fieldWithIdentifier:@"nameAr"
                                                                  title:kLang(@"RoleNameAr")
                                                            placeholder:kLang(@"RoleNameAr")
                                                              inputType:PPFormInputTypeText];
    nameAr.value = [self pp_localizedRoleValueForKey:@"ar" source:self.roleTemplate.name];
    nameAr.required = YES;

    PPFormFieldConfig *descEn = [PPFormFieldConfig fieldWithIdentifier:@"descEn"
                                                                  title:kLang(@"RoleDescEn")
                                                            placeholder:kLang(@"RoleDescEn")
                                                              inputType:PPFormInputTypeTextView];
    descEn.value = [self pp_localizedRoleValueForKey:@"en" source:self.roleTemplate.roleDescription];

    PPFormFieldConfig *descAr = [PPFormFieldConfig fieldWithIdentifier:@"descAr"
                                                                  title:kLang(@"RoleDescAr")
                                                            placeholder:kLang(@"RoleDescAr")
                                                              inputType:PPFormInputTypeTextView];
    descAr.value = [self pp_localizedRoleValueForKey:@"ar" source:self.roleTemplate.roleDescription];

    [self.infoFormView setFields:@[nameEn, nameAr, descEn, descAr]];
    [stack addArrangedSubview:self.infoFormView];
    return section;
}

- (UIView *)pp_buildPermissionsIntroSection {
    UIView *section = [self pp_makePlainSectionWithTitle:kLang(@"Permissions_Title")
                                                subtitle:kLang(@"RoleEditor_Permissions_Subtitle")];
    return section;
}

- (UIView *)pp_buildPermissionSectionForModule:(PermissionModule *)module {
    UIView *section = [self pp_makePlainSectionWithTitle:kLang(module.labelEn)
                                                subtitle:[NSString stringWithFormat:@"%lu %@", (unsigned long)module.actions.count, kLang(@"Permissions_Title")]];
    UIStackView *stack = (UIStackView *)section.subviews.firstObject;

    PPFormEngineView *formView = [[PPFormEngineView alloc] initWithStyle:[self pp_permissionFormStyle]];
    NSSet<NSString *> *activePerms = [NSSet setWithArray:self.roleTemplate.permissions ?: @[]];
    NSMutableArray<PPFormFieldConfig *> *fields = [NSMutableArray arrayWithCapacity:module.actions.count];
    __weak typeof(self) weakSelf = self;

    for (PermissionAction *action in module.actions) {
        PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:action.key
                                                                    title:kLang(action.labelEn)
                                                              placeholder:@""
                                                                inputType:PPFormInputTypeToggle];
        field.value = [activePerms containsObject:action.key] ? @"1" : @"0";
        field.textChangeBlock = ^(__unused PPFormFieldConfig *config, __unused NSString *value) {
            [weakSelf pp_updatePermissionSummary];
        };
        [fields addObject:field];
    }

    [formView setFields:fields];
    [self.permissionFormViews addObject:formView];
    [stack addArrangedSubview:formView];
    return section;
}

- (UIView *)pp_makePlainSectionWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UIView *section = [[UIView alloc] init];
    section.translatesAutoresizingMaskIntoConstraints = NO;
    section.backgroundColor = UIColor.clearColor;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 10.0;
    [section addSubview:stack];

    UIView *header = [[UIView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:header];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title ?: @"";
    titleLabel.font = [Styling fontBold:19.0];
    titleLabel.textColor = PPRoleEditorPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.numberOfLines = 1;
    [header addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.text = subtitle ?: @"";
    subtitleLabel.font = [Styling fontRegular:13.0];
    subtitleLabel.textColor = [PPRoleEditorSecondaryTextColor() colorWithAlphaComponent:0.88];
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.hidden = subtitle.length == 0;
    [header addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:section.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:section.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:section.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:section.bottomAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:header.topAnchor],
        [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
    ]];

    if (subtitle.length == 0) {
        [header.heightAnchor constraintEqualToConstant:28.0].active = YES;
    }

    return section;
}

- (PPFormStyle *)pp_formStyle {
    PPFormStyle *style = [PPFormStyle defaultStyle];
    style.cardBackgroundColor = PPRoleEditorSurfaceColor();
     style.accentColor = PPRoleEditorPrimaryColor();
    style.primaryTextColor = PPRoleEditorPrimaryTextColor();
    style.secondaryTextColor = PPRoleEditorSecondaryTextColor();
    style.cardBorderColor = PPRoleEditorBorderColor();
    style.fieldBorderColor = [PPRoleEditorPrimaryColor() colorWithAlphaComponent:0.1];
    style.titleFont = [Styling fontBold:12.0];
    style.inputFont = [Styling fontMedium:15.0];
    style.placeholderFont = [Styling fontRegular:14.0];
    style.errorFont = [Styling fontMedium:11.0];
    style.stackSpacing = 12.0;
    style.cardCornerRadius = 20.0;
    style.fieldCornerRadius = 16.0;
    style.minimumTextViewFieldHeight = 92.0;
    return style;
}

- (PPFormStyle *)pp_permissionFormStyle {
    PPFormStyle *style = [self pp_formStyle];
    style.stackSpacing = 10.0;
    style.cardCornerRadius = 18.0;
    style.shadowOpacity = 0.025;
    return style;
}

#pragma mark - Actions

- (void)onSave {
    if (![self.infoFormView validate]) {
        [PPToast toast:kLang(@"Error_FillAllFields")];
        return;
    }

    NSDictionary<NSString *, NSString *> *values = [self.infoFormView values];
    NSString *nameEn = [self pp_trimmedValue:values[@"nameEn"]];
    NSString *nameAr = [self pp_trimmedValue:values[@"nameAr"]];

    if (nameEn.length == 0 || nameAr.length == 0) {
        [PPToast toast:kLang(@"Error_FillAllFields")];
        return;
    }

    NSMutableArray<NSString *> *perms = [NSMutableArray array];
    for (PPFormEngineView *formView in self.permissionFormViews) {
        NSDictionary<NSString *, NSString *> *permissionValues = [formView values];
        for (NSString *key in permissionValues) {
            if ([permissionValues[key] boolValue]) {
                [perms addObject:key];
            }
        }
    }

    NSDictionary *payload = @{
        @"name": @{@"en": nameEn, @"ar": nameAr},
        @"description": @{
            @"en": [self pp_trimmedValue:values[@"descEn"]] ?: @"",
            @"ar": [self pp_trimmedValue:values[@"descAr"]] ?: @""
        },
        @"permissions": perms.copy
    };

    [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:@""];

    if (self.roleTemplate) {
        [[RPManager shared] updateStaffRole:self.roleTemplate.id data:payload completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) [PPToast toast:error.localizedDescription];
            else [self.navigationController popViewControllerAnimated:YES];
        }];
    } else {
        [[RPManager shared] createStaffRole:payload completion:^(__unused NSString * _Nullable roleID, NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) [PPToast toast:error.localizedDescription];
            else [self.navigationController popViewControllerAnimated:YES];
        }];
    }
}

#pragma mark - Motion

- (void)pp_prepareEntranceState {
    if (self.didPlayEntrance) return;
    self.heroCard.alpha = 0.0;
    self.heroCard.transform = CGAffineTransformMakeScale(1.025, 1.025);
    self.contentStack.alpha = 0.0;
    self.contentStack.transform = CGAffineTransformMakeTranslation(0.0, 14.0);
}

- (void)pp_playEntranceIfNeeded {
    if (self.didPlayEntrance) return;
    self.didPlayEntrance = YES;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.heroCard.alpha = 1.0;
        self.heroCard.transform = CGAffineTransformIdentity;
        self.contentStack.alpha = 1.0;
        self.contentStack.transform = CGAffineTransformIdentity;
        return;
    }

    [UIView animateWithDuration:0.38
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.heroCard.alpha = 1.0;
        self.heroCard.transform = CGAffineTransformIdentity;
    } completion:nil];

    [UIView animateWithDuration:0.42
                          delay:0.07
         usingSpringWithDamping:0.9
          initialSpringVelocity:0.25
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.contentStack.alpha = 1.0;
        self.contentStack.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Data Helpers

- (NSString *)pp_trimmedValue:(NSString *)value {
    if (![value isKindOfClass:NSString.class]) return @"";
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)pp_localizedRoleValueForKey:(NSString *)key source:(NSDictionary *)source {
    if (![source isKindOfClass:NSDictionary.class]) return @"";
    NSString *value = source[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

- (NSUInteger)pp_totalPermissionCount {
    NSUInteger total = 0;
    for (PermissionModule *module in self.permissionModules) {
        total += module.actions.count;
    }
    return total;
}

- (NSUInteger)pp_activePermissionCount {
    NSUInteger total = 0;
    for (PPFormEngineView *formView in self.permissionFormViews) {
        for (NSString *value in [formView values].allValues) {
            if (value.boolValue) total += 1;
        }
    }
    return total;
}

- (void)pp_updatePermissionSummary {
    self.permissionSummaryLabel.text = [NSString stringWithFormat:@"%lu / %lu",
                                        (unsigned long)[self pp_activePermissionCount],
                                        (unsigned long)[self pp_totalPermissionCount]];
}

- (NSArray<PermissionModule *> *)pp_allPermissionModules {
    return @[
        PPRoleEditorModule(@"dashboard", @"Staff_Module_Dashboard", @[
            PPRoleEditorAction(kStaffPermDashboardView, @"StaffPerm_dashboard_view"),
        ]),
        PPRoleEditorModule(@"staff", @"Staff_Module_Staff", @[
            PPRoleEditorAction(kStaffPermStaffView, @"StaffPerm_staff_view"),
            PPRoleEditorAction(kStaffPermStaffManage, @"StaffPerm_staff_manage"),
        ]),
        PPRoleEditorModule(@"users", @"Staff_Module_Users", @[
            PPRoleEditorAction(kStaffPermUsersView, @"StaffPerm_users_view"),
            PPRoleEditorAction(kStaffPermUsersManage, @"StaffPerm_users_manage"),
            PPRoleEditorAction(kStaffPermUsersBlock, @"StaffPerm_users_block"),
            PPRoleEditorAction(kStaffPermUsersFeaturesView, @"StaffPerm_users_features_view"),
            PPRoleEditorAction(kStaffPermUsersFeaturesManage, @"StaffPerm_users_features_manage"),
            PPRoleEditorAction(kStaffPermUsersSubscriptionsView, @"StaffPerm_users_subscriptions_view"),
            PPRoleEditorAction(kStaffPermUsersSubscriptionsManage, @"StaffPerm_users_subscriptions_manage"),
            PPRoleEditorAction(kStaffPermUsersRestrictionsView, @"StaffPerm_users_restrictions_view"),
            PPRoleEditorAction(kStaffPermUsersRestrictionsManage, @"StaffPerm_users_restrictions_manage"),
        ]),
        PPRoleEditorModule(@"stock", @"Staff_Module_Stock", @[
            PPRoleEditorAction(kStaffPermStockView, @"StaffPerm_stock_view"),
            PPRoleEditorAction(kStaffPermStockManage, @"StaffPerm_stock_manage"),
            PPRoleEditorAction(kStaffPermStockCreate, @"StaffPerm_stock_create"),
            PPRoleEditorAction(kStaffPermStockDelete, @"StaffPerm_stock_delete"),
        ]),
        PPRoleEditorModule(@"listings", @"Staff_Module_Listings", @[
            PPRoleEditorAction(kStaffPermListingsView, @"StaffPerm_listings_view"),
            PPRoleEditorAction(kStaffPermListingsManage, @"StaffPerm_listings_manage"),
            PPRoleEditorAction(kStaffPermListingsModerate, @"StaffPerm_listings_moderate"),
        ]),
        PPRoleEditorModule(@"payments", @"Staff_Module_Payments", @[
            PPRoleEditorAction(kStaffPermPaymentsView, @"StaffPerm_payments_view"),
            PPRoleEditorAction(kStaffPermPaymentsManage, @"StaffPerm_payments_manage"),
            PPRoleEditorAction(kStaffPermPaymentsRefund, @"StaffPerm_payments_refund"),
        ]),
        PPRoleEditorModule(@"pos", @"Staff_Module_POS", @[
            PPRoleEditorAction(kStaffPermPosView, @"StaffPerm_pos_view"),
            PPRoleEditorAction(kStaffPermPosSell, @"StaffPerm_pos_sell"),
            PPRoleEditorAction(kStaffPermPosHistory, @"StaffPerm_pos_history"),
        ]),
        PPRoleEditorModule(@"branches", @"Staff_Module_Branches", @[
            PPRoleEditorAction(kStaffPermBranchesView, @"StaffPerm_branches_view"),
            PPRoleEditorAction(kStaffPermBranchesManage, @"StaffPerm_branches_manage"),
        ]),
        PPRoleEditorModule(@"agents", @"Staff_Module_Agents", @[
            PPRoleEditorAction(kStaffPermAgentsView, @"StaffPerm_agents_view"),
            PPRoleEditorAction(kStaffPermAgentsManage, @"StaffPerm_agents_manage"),
        ]),
        PPRoleEditorModule(@"support", @"Staff_Module_Support", @[
            PPRoleEditorAction(kStaffPermSupportView, @"StaffPerm_support_view"),
            PPRoleEditorAction(kStaffPermSupportManage, @"StaffPerm_support_manage"),
        ]),
        PPRoleEditorModule(@"services", @"Staff_Module_Services", @[
            PPRoleEditorAction(kStaffPermServicesView, @"StaffPerm_services_view"),
            PPRoleEditorAction(kStaffPermServicesManage, @"StaffPerm_services_manage"),
        ]),
        PPRoleEditorModule(@"providers", @"Staff_Module_Providers", @[
            PPRoleEditorAction(kStaffPermProvidersView, @"StaffPerm_providers_view"),
            PPRoleEditorAction(kStaffPermProvidersManage, @"StaffPerm_providers_manage"),
        ]),
        PPRoleEditorModule(@"settings", @"Staff_Module_Settings", @[
            PPRoleEditorAction(kStaffPermSettingsView, @"StaffPerm_settings_view"),
            PPRoleEditorAction(kStaffPermSettingsManage, @"StaffPerm_settings_manage"),
        ]),
        PPRoleEditorModule(@"notifications", @"Staff_Module_Notifications", @[
            PPRoleEditorAction(kStaffPermNotificationsView, @"StaffPerm_notifications_view"),
            PPRoleEditorAction(kStaffPermNotificationsSend, @"StaffPerm_notifications_send"),
        ]),
        PPRoleEditorModule(@"accounting", @"Staff_Module_Accounting", @[
            PPRoleEditorAction(kStaffPermAccountingView, @"StaffPerm_accounting_view"),
            PPRoleEditorAction(kStaffPermAccountingManage, @"StaffPerm_accounting_manage"),
        ]),
        PPRoleEditorModule(@"reports", @"Staff_Module_Reports", @[
            PPRoleEditorAction(kStaffPermReportsView, @"StaffPerm_reports_view"),
            PPRoleEditorAction(kStaffPermReportsExport, @"StaffPerm_reports_export"),
        ]),
        PPRoleEditorModule(@"audit", @"Staff_Module_Audit", @[
            PPRoleEditorAction(kStaffPermAuditView, @"StaffPerm_audit_view"),
        ]),
        PPRoleEditorModule(@"moderation", @"Staff_Module_Moderation", @[
            PPRoleEditorAction(kStaffPermModerationView, @"StaffPerm_moderation_view"),
            PPRoleEditorAction(kStaffPermModerationManage, @"StaffPerm_moderation_manage"),
        ]),
        PPRoleEditorModule(@"banners", @"Staff_Module_Banners", @[
            PPRoleEditorAction(kStaffPermBannersView, @"StaffPerm_banners_view"),
            PPRoleEditorAction(kStaffPermBannersManage, @"StaffPerm_banners_manage"),
        ]),
        PPRoleEditorModule(@"categories", @"Staff_Module_Categories", @[
            PPRoleEditorAction(kStaffPermCategoriesView, @"StaffPerm_categories_view"),
            PPRoleEditorAction(kStaffPermCategoriesManage, @"StaffPerm_categories_manage"),
        ]),
        PPRoleEditorModule(@"veterinarians", @"Staff_Module_Veterinarians", @[
            PPRoleEditorAction(kStaffPermVeterinariansView, @"StaffPerm_veterinarians_view"),
            PPRoleEditorAction(kStaffPermVeterinariansManage, @"StaffPerm_veterinarians_manage"),
        ]),
    ];
}

@end
