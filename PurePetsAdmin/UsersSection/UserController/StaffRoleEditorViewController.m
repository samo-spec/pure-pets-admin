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
        _permissionModules = [self pp_generatedPermissionModules];
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
    NSString *moduleLabel = [Language isRTL] ? module.labelAr : module.labelEn;
    UIView *section = [self pp_makePlainSectionWithTitle:moduleLabel
                                                subtitle:[NSString stringWithFormat:@"%lu %@", (unsigned long)module.actions.count, kLang(@"Permissions_Title")]];
    UIStackView *stack = (UIStackView *)section.subviews.firstObject;

    PPFormEngineView *formView = [[PPFormEngineView alloc] initWithStyle:[self pp_permissionFormStyle]];
    NSSet<NSString *> *activePerms = [NSSet setWithArray:self.roleTemplate.permissions ?: @[]];
    NSMutableArray<PPFormFieldConfig *> *fields = [NSMutableArray arrayWithCapacity:module.actions.count];
    __weak typeof(self) weakSelf = self;

    for (PermissionAction *action in module.actions) {
        PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:action.key
                                                                    title:([Language isRTL] ? action.labelAr : action.labelEn)
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

    NSMutableDictionary *payload = [@{
        @"name": @{@"en": nameEn, @"ar": nameAr},
        @"description": @{
            @"en": [self pp_trimmedValue:values[@"descEn"]] ?: @"",
            @"ar": [self pp_trimmedValue:values[@"descAr"]] ?: @""
        },
        @"permissions": perms.copy
    } mutableCopy];
    if (self.roleTemplate) payload[@"expectedRevision"] = @(MAX(0, self.roleTemplate.revision));

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

- (NSArray<PermissionModule *> *)pp_generatedPermissionModules {
    NSMutableArray<PermissionModule *> *modules = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *moduleValue in PPStaffPermissionModules()) {
        if (![moduleValue isKindOfClass:NSDictionary.class]) continue;

        PermissionModule *module = [PermissionModule new];
        module.key = [moduleValue[@"key"] isKindOfClass:NSString.class] ? moduleValue[@"key"] : @"";
        module.labelEn = [moduleValue[@"labelEn"] isKindOfClass:NSString.class] ? moduleValue[@"labelEn"] : module.key;
        module.labelAr = [moduleValue[@"labelAr"] isKindOfClass:NSString.class] ? moduleValue[@"labelAr"] : module.labelEn;

        NSMutableArray<PermissionAction *> *actions = [NSMutableArray array];
        NSArray *actionValues = [moduleValue[@"actions"] isKindOfClass:NSArray.class] ? moduleValue[@"actions"] : @[];
        for (NSDictionary<NSString *, id> *actionValue in actionValues) {
            if (![actionValue isKindOfClass:NSDictionary.class]) continue;
            PermissionAction *action = [PermissionAction new];
            action.key = [actionValue[@"key"] isKindOfClass:NSString.class] ? actionValue[@"key"] : @"";
            action.labelEn = [actionValue[@"labelEn"] isKindOfClass:NSString.class] ? actionValue[@"labelEn"] : action.key;
            action.labelAr = [actionValue[@"labelAr"] isKindOfClass:NSString.class] ? actionValue[@"labelAr"] : action.labelEn;
            if (action.key.length > 0) [actions addObject:action];
        }
        module.actions = actions.copy;
        if (module.key.length > 0 && module.actions.count > 0) [modules addObject:module];
    }
    return modules.copy;
}


@end
