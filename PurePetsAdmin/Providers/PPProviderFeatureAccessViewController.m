#import "PPProviderFeatureAccessViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "PPAlertHelper.h"
#import "PPFunc+Haptics.h"

static NSString * const PPFeatureEntitlementCellID = @"PPFeatureEntitlementCellID";

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

#pragma mark - Visual Helpers

static UIColor *PPColorForProviderType(NSString *providerType) {
    NSString *token = providerType.lowercaseString ?: @"";
    if ([token containsString:@"market"] || [token containsString:@"store"]) {
        return [UIColor systemBlueColor];
    } else if ([token containsString:@"pharm"] || [token containsString:@"med"]) {
        return [UIColor systemPurpleColor];
    } else if ([token containsString:@"clinic"] || [token containsString:@"vet"]) {
        return [UIColor systemGreenColor];
    } else if ([token containsString:@"hotel"] || [token containsString:@"board"]) {
        return [UIColor systemIndigoColor];
    } else if ([token containsString:@"train"]) {
        return [UIColor systemOrangeColor];
    } else if ([token containsString:@"groom"] || [token containsString:@"salon"]) {
        return [UIColor systemPinkColor];
    }
    return [UIColor systemTealColor];
}

static NSString *PPSymbolForProviderType(NSString *providerType) {
    NSString *token = providerType.lowercaseString ?: @"";
    if ([token containsString:@"market"] || [token containsString:@"store"]) {
        return @"cart.fill";
    } else if ([token containsString:@"pharm"] || [token containsString:@"med"]) {
        return @"cross.case.fill";
    } else if ([token containsString:@"clinic"] || [token containsString:@"vet"]) {
        return @"stethoscope";
    } else if ([token containsString:@"hotel"] || [token containsString:@"board"]) {
        return @"bed.double.fill";
    } else if ([token containsString:@"train"]) {
        return @"figure.walk";
    } else if ([token containsString:@"groom"] || [token containsString:@"salon"]) {
        return @"scissors";
    }
    return @"shield.lefthalf.filled.badge.checkmark";
}

#pragma mark - Pushed Feature Detail View Controller

@interface PPFeatureDetailViewController : UIViewController
@property (nonatomic, strong) NSDictionary *feature;
@end

@implementation PPFeatureDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_Features_Detail_Title") ?: @"تفاصيل الصلاحية والميزة";
    self.view.backgroundColor = PPProviderCanvasColor();
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self pp_setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
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

- (void)pp_setupUI {
    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:scrollView];

    UIView *contentView = [UIView new];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [scrollView addSubview:contentView];

    // Data parsing
    NSString *featureKey = [self.feature[@"featureKey"] isKindOfClass:NSString.class] ? self.feature[@"featureKey"] : @"";
    NSString *title = PPProviderLocalizedText(self.feature[@"title"], featureKey);
    NSString *planName = PPProviderLocalizedText(self.feature[@"planName"], self.feature[@"planID"]);
    NSString *provider = PPProviderLocalizedType(self.feature[@"providerType"]);
    NSString *limit = [self.feature[@"limitValue"] isKindOfClass:NSString.class] ? self.feature[@"limitValue"] : @"";
    NSString *planStatus = [self.feature[@"planStatus"] isKindOfClass:NSString.class] ? self.feature[@"planStatus"] : @"active";
    BOOL enabled = ![self.feature[@"enabled"] isKindOfClass:NSNumber.class] || [self.feature[@"enabled"] boolValue];
    NSString *providerType = [self.feature[@"providerType"] isKindOfClass:NSString.class] ? self.feature[@"providerType"] : @"";
    UIColor *typeColor = PPColorForProviderType(providerType);
    NSString *typeSymbol = PPSymbolForProviderType(providerType);

    // 1. Hero Card
    UIView *heroCard = [UIView new];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    heroCard.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(heroCard, 24.0);
    heroCard.layer.borderWidth = 1.0;
    heroCard.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.15].CGColor;
    heroCard.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(heroCard);
    [contentView addSubview:heroCard];

    UIView *iconShell = [UIView new];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [typeColor colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(iconShell, 22.0);
    [heroCard addSubview:iconShell];

    UIImageView *iconView = [UIImageView new];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    UIImageSymbolConfiguration *symConf = [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightBold];
    iconView.image = [[UIImage systemImageNamed:typeSymbol withConfiguration:symConf] imageWithTintColor:typeColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    [iconShell addSubview:iconView];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPAppFontBold(22.0);
    titleLabel.textColor = PPProviderPrimaryTextColor();
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    titleLabel.text = title;
    [heroCard addSubview:titleLabel];

    // Status & Sector Badges Stack
    UIStackView *heroBadgesStack = [UIStackView new];
    heroBadgesStack.translatesAutoresizingMaskIntoConstraints = NO;
    heroBadgesStack.axis = UILayoutConstraintAxisHorizontal;
    heroBadgesStack.spacing = 8.0;
    heroBadgesStack.alignment = UIStackViewAlignmentCenter;
    heroBadgesStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [heroCard addSubview:heroBadgesStack];

    UIView *statusBadge = [UIView new];
    statusBadge.backgroundColor = enabled ? [[UIColor ppSuccess] colorWithAlphaComponent:0.12] : [[UIColor ppTextSecondary] colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(statusBadge, 10.0);

    UILabel *statusLabel = [UILabel new];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.font = PPAppFontBold(13.0);
    statusLabel.textColor = enabled ? [UIColor ppSuccess] : [UIColor ppTextSecondary];
    statusLabel.text = enabled ? (kLang(@"Providers_Status_Active") ?: @"مفعل بالخطة") : (kLang(@"Providers_Status_Inactive") ?: @"معطل");
    [statusBadge addSubview:statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [statusLabel.topAnchor constraintEqualToAnchor:statusBadge.topAnchor constant:4.0],
        [statusLabel.bottomAnchor constraintEqualToAnchor:statusBadge.bottomAnchor constant:-4.0],
        [statusLabel.leadingAnchor constraintEqualToAnchor:statusBadge.leadingAnchor constant:10.0],
        [statusLabel.trailingAnchor constraintEqualToAnchor:statusBadge.trailingAnchor constant:-10.0],
    ]];
    [heroBadgesStack addArrangedSubview:statusBadge];

    UIView *sectorBadge = [UIView new];
    sectorBadge.backgroundColor = [typeColor colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(sectorBadge, 10.0);

    UILabel *sectorLabel = [UILabel new];
    sectorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sectorLabel.font = PPAppFontBold(13.0);
    sectorLabel.textColor = typeColor;
    sectorLabel.text = provider;
    [sectorBadge addSubview:sectorLabel];

    [NSLayoutConstraint activateConstraints:@[
        [sectorLabel.topAnchor constraintEqualToAnchor:sectorBadge.topAnchor constant:4.0],
        [sectorLabel.bottomAnchor constraintEqualToAnchor:sectorBadge.bottomAnchor constant:-4.0],
        [sectorLabel.leadingAnchor constraintEqualToAnchor:sectorBadge.leadingAnchor constant:10.0],
        [sectorLabel.trailingAnchor constraintEqualToAnchor:sectorBadge.trailingAnchor constant:-10.0],
    ]];
    [heroBadgesStack addArrangedSubview:sectorBadge];

    // 2. Specifications Card
    UIView *specsCard = [UIView new];
    specsCard.translatesAutoresizingMaskIntoConstraints = NO;
    specsCard.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(specsCard, 24.0);
    specsCard.layer.borderWidth = 1.0;
    specsCard.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.15].CGColor;
    specsCard.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(specsCard);
    [contentView addSubview:specsCard];

    UILabel *secHeader = [UILabel new];
    secHeader.translatesAutoresizingMaskIntoConstraints = NO;
    secHeader.font = PPAppFontBold(16.0);
    secHeader.textColor = PPProviderPrimaryTextColor();
    secHeader.text = kLang(@"Providers_Feature_Info_Section") ?: @"المعلومات التقنية والترخيص";
    secHeader.textAlignment = [Language alignmentForCurrentLanguage];
    [specsCard addSubview:secHeader];

    UIStackView *detailsStack = [UIStackView new];
    detailsStack.translatesAutoresizingMaskIntoConstraints = NO;
    detailsStack.axis = UILayoutConstraintAxisVertical;
    detailsStack.spacing = 10.0;
    detailsStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [specsCard addSubview:detailsStack];

    __weak typeof(self) weakSelf = self;
    UIView *keyRow = [self pp_buildInfoRowWithTitle:(kLang(@"Providers_FeatureKey_Title") ?: @"المفتاح البرمجي")
                                              value:featureKey
                                             isMono:YES
                                         copyAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UIPasteboard.generalPasteboard.string = featureKey;
        [PPAlertHelper showSuccessIn:strongSelf title:(kLang(@"Copied_To_Clipboard") ?: @"تم نسخ المفتاح إلى الحافظة") subtitle:nil];
        [PPFunc pp_playSuccessEffect];
    }];
    [detailsStack addArrangedSubview:keyRow];

    UIView *planRow = [self pp_buildInfoRowWithTitle:(kLang(@"Providers_Plan_Title") ?: @"الخطة المربوطة")
                                               value:planName
                                              isMono:NO
                                          copyAction:nil];
    [detailsStack addArrangedSubview:planRow];

    UIView *typeRow = [self pp_buildInfoRowWithTitle:(kLang(@"Providers_Type_Title") ?: @"نوع المزود")
                                               value:provider
                                              isMono:NO
                                          copyAction:nil];
    [detailsStack addArrangedSubview:typeRow];

    NSString *limitDisplay = limit.length > 0 ? [NSString stringWithFormat:@"%@ %@", limit, (kLang(@"limit_units") ?: @"عنصر")] : (kLang(@"unlimited_limit") ?: @"غير محدود");
    UIView *limitRow = [self pp_buildInfoRowWithTitle:(kLang(@"Providers_Limit_Title") ?: @"قيمة الحد الأقصى")
                                                value:limitDisplay
                                               isMono:NO
                                           copyAction:nil];
    [detailsStack addArrangedSubview:limitRow];

    UIView *planStatusRow = [self pp_buildInfoRowWithTitle:(kLang(@"Providers_Plan_Status") ?: @"حالة الخطة")
                                                     value:planStatus.uppercaseString
                                                    isMono:NO
                                                copyAction:nil];
    [detailsStack addArrangedSubview:planStatusRow];

    // 3. Primary Action Button (Copy Key)
    UIButton *copyMainBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyMainBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [copyMainBtn setTitle:(kLang(@"Providers_Copy_Key") ?: @"نسخ المفتاح البرمجي") forState:UIControlStateNormal];
    copyMainBtn.titleLabel.font = PPAppFontBold(16.0);
    [copyMainBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyMainBtn.backgroundColor = PPProviderBrandColor();
    PPApplyContinuousCorners(copyMainBtn, 18.0);
    [copyMainBtn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        UIPasteboard.generalPasteboard.string = featureKey;
        [PPAlertHelper showSuccessIn:strongSelf title:(kLang(@"Copied_To_Clipboard") ?: @"تم نسخ المفتاح إلى الحافظة") subtitle:nil];
        [PPFunc pp_playSuccessEffect];
    }] forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:copyMainBtn];

    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentView.topAnchor constraintEqualToAnchor:scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],

        // Hero Card Constraints
        [heroCard.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:16.0],
        [heroCard.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:PPScreenMargin],
        [heroCard.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-PPScreenMargin],

        [iconShell.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:24.0],
        [iconShell.centerXAnchor constraintEqualToAnchor:heroCard.centerXAnchor],
        [iconShell.widthAnchor constraintEqualToConstant:68.0],
        [iconShell.heightAnchor constraintEqualToConstant:68.0],
        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:iconShell.bottomAnchor constant:14.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:20.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-20.0],

        [heroBadgesStack.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:12.0],
        [heroBadgesStack.centerXAnchor constraintEqualToAnchor:heroCard.centerXAnchor],
        [heroBadgesStack.bottomAnchor constraintEqualToAnchor:heroCard.bottomAnchor constant:-20.0],

        // Specs Card Constraints
        [specsCard.topAnchor constraintEqualToAnchor:heroCard.bottomAnchor constant:16.0],
        [specsCard.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:PPScreenMargin],
        [specsCard.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-PPScreenMargin],

        [secHeader.topAnchor constraintEqualToAnchor:specsCard.topAnchor constant:16.0],
        [secHeader.leadingAnchor constraintEqualToAnchor:specsCard.leadingAnchor constant:16.0],
        [secHeader.trailingAnchor constraintEqualToAnchor:specsCard.trailingAnchor constant:-16.0],

        [detailsStack.topAnchor constraintEqualToAnchor:secHeader.bottomAnchor constant:14.0],
        [detailsStack.leadingAnchor constraintEqualToAnchor:specsCard.leadingAnchor constant:16.0],
        [detailsStack.trailingAnchor constraintEqualToAnchor:specsCard.trailingAnchor constant:-16.0],
        [detailsStack.bottomAnchor constraintEqualToAnchor:specsCard.bottomAnchor constant:-16.0],

        // Main Copy Button
        [copyMainBtn.topAnchor constraintEqualToAnchor:specsCard.bottomAnchor constant:20.0],
        [copyMainBtn.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:PPScreenMargin],
        [copyMainBtn.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-PPScreenMargin],
        [copyMainBtn.heightAnchor constraintEqualToConstant:52.0],
        [copyMainBtn.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-32.0]
    ]];
}

- (UIView *)pp_buildInfoRowWithTitle:(NSString *)title value:(NSString *)value isMono:(BOOL)isMono copyAction:(void (^)(void))copyAction {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [[UIColor whiteColor] colorWithAlphaComponent:0.04]
            : [[UIColor blackColor] colorWithAlphaComponent:0.03];
    }];
    PPApplyContinuousCorners(row, 14.0);
    row.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *titleLbl = [UILabel new];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.font = PPAppFontMedium(14.0);
    titleLbl.textColor = PPProviderSecondaryTextColor();
    titleLbl.text = title;
    titleLbl.textAlignment = [Language alignmentForCurrentLanguage];
    [row addSubview:titleLbl];

    UILabel *valLbl = [UILabel new];
    valLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valLbl.font = isMono ? [UIFont monospacedSystemFontOfSize:13.5 weight:UIFontWeightBold] : PPAppFontBold(14.5);
    valLbl.textColor = PPProviderPrimaryTextColor();
    valLbl.text = value;
    valLbl.textAlignment = NSTextAlignmentNatural;
    [row addSubview:valLbl];

    [NSLayoutConstraint activateConstraints:@[
        [titleLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14.0],
        [titleLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],

        [valLbl.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:copyAction ? -44.0 : -14.0],
        [valLbl.leadingAnchor constraintGreaterThanOrEqualToAnchor:titleLbl.trailingAnchor constant:8.0],
        [valLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:46.0]
    ]];

    if (copyAction) {
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
        UIImageSymbolConfiguration *cSym = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
        [copyBtn setImage:[[UIImage systemImageNamed:@"doc.on.doc" withConfiguration:cSym] imageWithTintColor:PPProviderBrandColor() renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
        [copyBtn addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
            if (copyAction) copyAction();
        }] forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:copyBtn];

        [NSLayoutConstraint activateConstraints:@[
            [copyBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8.0],
            [copyBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [copyBtn.widthAnchor constraintEqualToConstant:32.0],
            [copyBtn.heightAnchor constraintEqualToConstant:32.0]
        ]];
    }

    return row;
}

@end

#pragma mark - NextGen V6 Entitlement Feature Cell

@interface PPFeatureEntitlementCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconShell;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *keyLabel;
@property (nonatomic, strong) UILabel *typeTag;
@property (nonatomic, strong) UILabel *planTag;
@property (nonatomic, strong) UILabel *limitTag;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)configureWithFeature:(NSDictionary *)feature;
@end

@implementation PPFeatureEntitlementCardCell

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
    PPApplyContinuousCorners(_cardView, 20.0);
    _cardView.layer.borderWidth = 1.0;
    _cardView.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.12].CGColor;
    _cardView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(_cardView);
    [self.contentView addSubview:_cardView];

    // Leading Icon Shell
    _iconShell = [UIView new];
    _iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_iconShell, 14.0);
    [_cardView addSubview:_iconShell];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_iconShell addSubview:_iconView];

    // Title Label
    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = PPAppFontBold(16.5);
    _titleLabel.textColor = PPProviderPrimaryTextColor();
    _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [_cardView addSubview:_titleLabel];

    // Technical Key Badge
    _keyLabel = [UILabel new];
    _keyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _keyLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightMedium];
    _keyLabel.textColor = PPProviderSecondaryTextColor();
    _keyLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [_cardView addSubview:_keyLabel];

    // Badges Row Stack
    UIStackView *tagStack = [UIStackView new];
    tagStack.translatesAutoresizingMaskIntoConstraints = NO;
    tagStack.axis = UILayoutConstraintAxisHorizontal;
    tagStack.spacing = 6.0;
    tagStack.alignment = UIStackViewAlignmentCenter;
    tagStack.distribution = UIStackViewDistributionEqualSpacing;
    tagStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [_cardView addSubview:tagStack];

    _typeTag = [self pp_createBadgeLabelWithBg:[PPProviderBrandColor() colorWithAlphaComponent:0.08] textClr:PPProviderBrandColor()];
    [tagStack addArrangedSubview:_typeTag];

    _planTag = [self pp_createBadgeLabelWithBg:[UIColor.systemGrayColor colorWithAlphaComponent:0.10] textClr:PPProviderPrimaryTextColor()];
    [tagStack addArrangedSubview:_planTag];

    _limitTag = [self pp_createBadgeLabelWithBg:[UIColor.systemOrangeColor colorWithAlphaComponent:0.10] textClr:UIColor.systemOrangeColor];
    [tagStack addArrangedSubview:_limitTag];

    // Trailing Status View
    UIView *statusContainer = [UIView new];
    statusContainer.translatesAutoresizingMaskIntoConstraints = NO;
    statusContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [_cardView addSubview:statusContainer];

    _statusDot = [UIView new];
    _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    _statusDot.layer.cornerRadius = 4.0;
    _statusDot.clipsToBounds = YES;
    [statusContainer addSubview:_statusDot];

    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = PPAppFontBold(12.5);
    [statusContainer addSubview:_statusLabel];

    // Chevron Accessory
    _chevronView = [UIImageView new];
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    BOOL isRTL = [[Language currentLanguageCode] isEqualToString:@"ar"];
    UIImageSymbolConfiguration *chvConf = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
    _chevronView.image = [[UIImage systemImageNamed:(isRTL ? @"chevron.backward" : @"chevron.forward") withConfiguration:chvConf]
                          imageWithTintColor:[PPProviderSecondaryTextColor() colorWithAlphaComponent:0.4] renderingMode:UIImageRenderingModeAlwaysOriginal];
    [_cardView addSubview:_chevronView];

    [NSLayoutConstraint activateConstraints:@[
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

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
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:statusContainer.leadingAnchor constant:-8.0],

        [_keyLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
        [_keyLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_keyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:statusContainer.leadingAnchor constant:-8.0],

        [tagStack.topAnchor constraintEqualToAnchor:_keyLabel.bottomAnchor constant:8.0],
        [tagStack.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [tagStack.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-12.0],

        [statusContainer.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-8.0],
        [_chevronView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12.0],
        [_chevronView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_chevronView.widthAnchor constraintEqualToConstant:14.0],
        [_chevronView.heightAnchor constraintEqualToConstant:14.0],

        [_statusDot.leadingAnchor constraintEqualToAnchor:statusContainer.leadingAnchor],
        [_statusDot.centerYAnchor constraintEqualToAnchor:statusContainer.centerYAnchor],
        [_statusDot.widthAnchor constraintEqualToConstant:8.0],
        [_statusDot.heightAnchor constraintEqualToConstant:8.0],

        [_statusLabel.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:5.0],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:statusContainer.trailingAnchor],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:statusContainer.centerYAnchor],
        [statusContainer.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor]
    ]];
}

- (UILabel *)pp_createBadgeLabelWithBg:(UIColor *)bg textClr:(UIColor *)textClr {
    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = PPAppFontBold(11.5);
    lbl.textColor = textClr;
    lbl.backgroundColor = bg;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.layer.cornerRadius = 6.0;
    lbl.clipsToBounds = YES;
    lbl.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(2, 6, 2, 6);
    return lbl;
}

- (void)configureWithFeature:(NSDictionary *)feature {
    NSString *featureKey = [feature[@"featureKey"] isKindOfClass:NSString.class] ? feature[@"featureKey"] : @"";
    NSString *title = PPProviderLocalizedText(feature[@"title"], featureKey);
    NSString *planName = PPProviderLocalizedText(feature[@"planName"], feature[@"planID"]);
    NSString *provider = PPProviderLocalizedType(feature[@"providerType"]);
    NSString *limit = [feature[@"limitValue"] isKindOfClass:NSString.class] ? feature[@"limitValue"] : @"";
    BOOL enabled = ![feature[@"enabled"] isKindOfClass:NSNumber.class] || [feature[@"enabled"] boolValue];
    NSString *providerType = [feature[@"providerType"] isKindOfClass:NSString.class] ? feature[@"providerType"] : @"";

    UIColor *typeColor = PPColorForProviderType(providerType);
    NSString *typeSymbol = PPSymbolForProviderType(providerType);

    _iconShell.backgroundColor = [typeColor colorWithAlphaComponent:0.12];
    UIImageSymbolConfiguration *symConf = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    _iconView.image = [[UIImage systemImageNamed:typeSymbol withConfiguration:symConf] imageWithTintColor:typeColor renderingMode:UIImageRenderingModeAlwaysOriginal];

    _titleLabel.text = title;
    _keyLabel.text = [NSString stringWithFormat:@"[ %@ ]", featureKey];
    _typeTag.text = [NSString stringWithFormat:@" %@ ", provider];
    _planTag.text = [NSString stringWithFormat:@" %@ ", planName];

    if (limit.length > 0) {
        _limitTag.hidden = NO;
        _limitTag.text = [NSString stringWithFormat:@" 🔢 %@ ", limit];
    } else {
        _limitTag.hidden = YES;
    }

    if (enabled) {
        _statusDot.backgroundColor = [UIColor ppSuccess];
        _statusLabel.textColor = [UIColor ppSuccess];
        _statusLabel.text = kLang(@"Providers_Status_Active") ?: @"نشط";
    } else {
        _statusDot.backgroundColor = [UIColor ppTextSecondary];
        _statusLabel.textColor = [UIColor ppTextSecondary];
        _statusLabel.text = kLang(@"Providers_Status_Inactive") ?: @"معطل";
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [UIView animateWithDuration:0.18 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
        self.cardView.alpha = highlighted ? 0.90 : 1.0;
    } completion:nil];
}

@end

#pragma mark - Main View Controller

@interface PPProviderFeatureAccessViewController () <UISearchBarDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *allFeatures;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredFeatures;
@property (nonatomic, strong) NSArray<NSString *> *availableProviderTypes;
@property (nonatomic, copy, nullable) NSString *selectedProviderType;
@property (nonatomic, copy, nullable) NSString *searchQuery;

@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UILabel *totalMetricValue;
@property (nonatomic, strong) UILabel *activeMetricValue;
@property (nonatomic, strong) UILabel *typesMetricValue;
@property (nonatomic, strong) UILabel *limitsMetricValue;

@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIScrollView *chipsScrollView;
@property (nonatomic, strong) UIStackView *chipsStackView;
@property (nonatomic, strong) PPProviderStateView *stateView;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPProviderFeatureAccessViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.allFeatures = @[];
    self.filteredFeatures = @[];
    self.availableProviderTypes = @[];
    [self pp_evaluatePermissions];
    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_buildHeader];
    [self loadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: PPProviderPrimaryTextColor(),
            NSFontAttributeName: PPAppFontBold(18.0)
        };
        appearance.largeTitleTextAttributes = @{
            NSForegroundColorAttributeName: PPProviderPrimaryTextColor(),
            NSFontAttributeName: PPAppFontBold(28.0)
        };
        appearance.shadowColor = UIColor.clearColor;
        appearance.shadowImage = [[UIImage alloc] init];
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
    }
    self.navigationController.navigationBar.tintColor = PPProviderBrandColor();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_fitTableHeader];
}

#pragma mark - Setup

- (void)pp_evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (![staff hasAnyPermission:@[kStaffPermProvidersView, kStaffPermProvidersManage]]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self.navigationController popViewControllerAnimated:YES]; });
    }
}

- (void)pp_configureNavigation {
    self.title = kLang(@"Providers_Features_HeroTitle") ?: @"دليل الصلاحيات والميزات";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                              target:self
                                                                              action:@selector(loadData)];
    refresh.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = refresh;
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPProviderCanvasColor();
    self.tableView.backgroundColor = PPProviderCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 110.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, PPSpaceXXL, 0.0);
    [self.tableView registerClass:PPFeatureEntitlementCardCell.class forCellReuseIdentifier:PPFeatureEntitlementCellID];

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = PPProviderBrandColor();
    [refresh addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.stateView = [PPProviderStateView new];
    __weak typeof(self) weakSelf = self;
    self.stateView.retryHandler = ^{ [weakSelf loadData]; };
    self.tableView.backgroundView = self.stateView;
}

#pragma mark - Header Building

- (void)pp_buildHeader {
    UIView *container = [UIView new];
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    // Card Surface
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(card, 24.0);
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [PPProviderSeparatorColor() colorWithAlphaComponent:0.15].CGColor;
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyCardShadow(card);
    [container addSubview:card];

    // Hero Row: Icon + Title + Subtitle
    UIView *iconShell = [UIView new];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(iconShell, 18.0);
    [card addSubview:iconShell];

    UIImageView *iconView = [UIImageView new];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    UIImageSymbolConfiguration *symConf = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightBold];
    iconView.image = [[UIImage systemImageNamed:@"shield.lefthalf.filled.badge.checkmark" withConfiguration:symConf] imageWithTintColor:PPProviderBrandColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
    [iconShell addSubview:iconView];

    UILabel *badgeLbl = [UILabel new];
    badgeLbl.translatesAutoresizingMaskIntoConstraints = NO;
    badgeLbl.font = PPAppFontBold(12.5);
    badgeLbl.textColor = PPProviderBrandColor();
    badgeLbl.text = kLang(@"Providers_Features_Tag") ?: @"🛡️ تراخيص وميزات المزودين";
    badgeLbl.textAlignment = [Language alignmentForCurrentLanguage];
    [card addSubview:badgeLbl];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPAppFontBold(22.0);
    titleLabel.textColor = PPProviderPrimaryTextColor();
    titleLabel.text = kLang(@"Providers_Features_HeroTitle") ?: @"دليل الصلاحيات والميزات";
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [card addSubview:titleLabel];

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = PPAppFontRegular(13.5);
    subtitleLabel.textColor = PPProviderSecondaryTextColor();
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.text = kLang(@"Providers_Features_HeroSubtitle") ?: @"استعراض وتدقيق قيود وميزات الخطط المعتمدة لجميع أنواع المزودين.";
    subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [card addSubview:subtitleLabel];

    // Bento 4-Metrics Horizon
    UIStackView *bentoGrid = [UIStackView new];
    bentoGrid.translatesAutoresizingMaskIntoConstraints = NO;
    bentoGrid.axis = UILayoutConstraintAxisHorizontal;
    bentoGrid.spacing = 8.0;
    bentoGrid.distribution = UIStackViewDistributionFillEqually;
    bentoGrid.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:bentoGrid];

    UIView *m1 = [self pp_buildMetricPillWithTitle:(kLang(@"total_features_word") ?: @"الإجمالي") valueRef:&_totalMetricValue tint:PPProviderBrandColor()];
    UIView *m2 = [self pp_buildMetricPillWithTitle:(kLang(@"active_features_word") ?: @"المفعلة") valueRef:&_activeMetricValue tint:[UIColor ppSuccess]];
    UIView *m3 = [self pp_buildMetricPillWithTitle:(kLang(@"types_count_word") ?: @"القطاعات") valueRef:&_typesMetricValue tint:UIColor.systemIndigoColor];
    UIView *m4 = [self pp_buildMetricPillWithTitle:(kLang(@"limits_count_word") ?: @"القيود") valueRef:&_limitsMetricValue tint:UIColor.systemOrangeColor];

    [bentoGrid addArrangedSubview:m1];
    [bentoGrid addArrangedSubview:m2];
    [bentoGrid addArrangedSubview:m3];
    [bentoGrid addArrangedSubview:m4];

    // Search Bar
    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.placeholder = kLang(@"Providers_Features_Search_Placeholder") ?: @"بحث باسم الميزة، المفتاح، الخطة أو المزود...";
    _searchBar.delegate = self;
    _searchBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    if (@available(iOS 13.0, *)) {
        _searchBar.searchTextField.font = PPAppFontMedium(13.5);
    }
    [card addSubview:_searchBar];

    // Category Chips Island
    _chipsScrollView = [UIScrollView new];
    _chipsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _chipsScrollView.showsHorizontalScrollIndicator = NO;
    _chipsScrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:_chipsScrollView];

    _chipsStackView = [UIStackView new];
    _chipsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _chipsStackView.axis = UILayoutConstraintAxisHorizontal;
    _chipsStackView.spacing = 8.0;
    _chipsStackView.alignment = UIStackViewAlignmentCenter;
    _chipsStackView.distribution = UIStackViewDistributionFill;
    _chipsStackView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [_chipsScrollView addSubview:_chipsStackView];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],

        [iconShell.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [iconShell.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [iconShell.widthAnchor constraintEqualToConstant:50.0],
        [iconShell.heightAnchor constraintEqualToConstant:50.0],
        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [badgeLbl.topAnchor constraintEqualToAnchor:iconShell.topAnchor],
        [badgeLbl.leadingAnchor constraintEqualToAnchor:iconShell.trailingAnchor constant:12.0],
        [badgeLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],

        [titleLabel.topAnchor constraintEqualToAnchor:badgeLbl.bottomAnchor constant:2.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:badgeLbl.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:badgeLbl.trailingAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:badgeLbl.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:badgeLbl.trailingAnchor],

        [bentoGrid.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:16.0],
        [bentoGrid.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [bentoGrid.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [bentoGrid.heightAnchor constraintEqualToConstant:56.0],

        [_searchBar.topAnchor constraintEqualToAnchor:bentoGrid.bottomAnchor constant:10.0],
        [_searchBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:6.0],
        [_searchBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-6.0],
        [_searchBar.heightAnchor constraintEqualToConstant:44.0],

        [_chipsScrollView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:6.0],
        [_chipsScrollView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [_chipsScrollView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [_chipsScrollView.heightAnchor constraintEqualToConstant:36.0],
        [_chipsScrollView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],

        [_chipsStackView.topAnchor constraintEqualToAnchor:_chipsScrollView.topAnchor],
        [_chipsStackView.leadingAnchor constraintEqualToAnchor:_chipsScrollView.leadingAnchor],
        [_chipsStackView.trailingAnchor constraintEqualToAnchor:_chipsScrollView.trailingAnchor],
        [_chipsStackView.bottomAnchor constraintEqualToAnchor:_chipsScrollView.bottomAnchor],
        [_chipsStackView.heightAnchor constraintEqualToAnchor:_chipsScrollView.heightAnchor]
    ]];

    self.headerContainer = container;
    self.tableView.tableHeaderView = container;
    [self pp_fitTableHeader];
}

- (UIView *)pp_buildMetricPillWithTitle:(NSString *)title valueRef:(UILabel * __strong *)valueRef tint:(UIColor *)tint {
    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [tint colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(pill, 12.0);

    UILabel *valLbl = [UILabel new];
    valLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valLbl.font = PPAppFontBold(16.0);
    valLbl.textColor = tint;
    valLbl.textAlignment = NSTextAlignmentCenter;
    valLbl.text = @"-";
    [pill addSubview:valLbl];
    *valueRef = valLbl;

    UILabel *titLbl = [UILabel new];
    titLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titLbl.font = PPAppFontMedium(11.5);
    titLbl.textColor = PPProviderSecondaryTextColor();
    titLbl.textAlignment = NSTextAlignmentCenter;
    titLbl.text = title;
    [pill addSubview:titLbl];

    [NSLayoutConstraint activateConstraints:@[
        [valLbl.topAnchor constraintEqualToAnchor:pill.topAnchor constant:8.0],
        [valLbl.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],

        [titLbl.topAnchor constraintEqualToAnchor:valLbl.bottomAnchor constant:1.0],
        [titLbl.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
        [titLbl.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-8.0]
    ]];

    return pill;
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

#pragma mark - Chips Filter Setup

- (void)pp_rebuildChips {
    for (UIView *v in self.chipsStackView.arrangedSubviews) {
        [self.chipsStackView removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    // "All" Chip
    [self pp_addChipWithTitle:(kLang(@"All") ?: @"الكل")
                        count:self.allFeatures.count
                   isSelected:(self.selectedProviderType == nil)
                   actionType:nil];

    // Provider Type Chips
    for (NSString *type in self.availableProviderTypes) {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"providerType ==[cd] %@", type];
        NSUInteger count = [self.allFeatures filteredArrayUsingPredicate:pred].count;
        BOOL selected = [self.selectedProviderType isEqualToString:type];
        NSString *localized = PPProviderLocalizedType(type);
        [self pp_addChipWithTitle:localized count:count isSelected:selected actionType:type];
    }
}

- (void)pp_addChipWithTitle:(NSString *)title count:(NSUInteger)count isSelected:(BOOL)isSelected actionType:(NSString *)type {
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *btnTitle = [NSString stringWithFormat:@" %@ (%lu) ", title, (unsigned long)count];
    [chip setTitle:btnTitle forState:UIControlStateNormal];
    chip.titleLabel.font = isSelected ? PPAppFontBold(13.0) : PPAppFontMedium(12.5);
    [chip setTitleColor:isSelected ? UIColor.whiteColor : PPProviderPrimaryTextColor() forState:UIControlStateNormal];
    chip.backgroundColor = isSelected ? PPProviderBrandColor() : [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [[UIColor whiteColor] colorWithAlphaComponent:0.07]
            : [[UIColor blackColor] colorWithAlphaComponent:0.04];
    }];
    PPApplyContinuousCorners(chip, 14.0);

    __weak typeof(self) weakSelf = self;
    [chip addAction:[UIAction actionWithHandler:^(UIAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.selectedProviderType = type;
        [self pp_rebuildChips];
        [self pp_applyFiltering];
        [self.tableView reloadData];
        [self.tableView setContentOffset:CGPointZero animated:YES];
        [PPFunc pp_playSelectionEffect];
    }] forControlEvents:UIControlEventTouchUpInside];

    [self.chipsStackView addArrangedSubview:chip];
    [chip.heightAnchor constraintEqualToConstant:32.0].active = YES;
}

#pragma mark - Data Loading & Filtering

- (void)loadData {
    if (self.isLoading) return;
    self.isLoading = YES;
    self.currentError = nil;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self pp_updateState];

    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchPlansWithCompletion:^(NSArray<PPProviderPlan *> *plans, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            [self.refreshControl endRefreshing];
            self.currentError = error;
            if (!error) {
                self.allFeatures = [self pp_flattenFeaturesFromPlans:plans];
                [self pp_extractProviderTypes];
                [self pp_rebuildChips];
            }
            [self pp_refreshHeaderMetrics];
            [self pp_applyFiltering];
            [self pp_updateState];
            [self.tableView reloadData];
            if (error && self.allFeatures.count > 0) {
                [PPAlertHelper showAlertIn:self title:kLang(@"Providers_Features_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
            }
        });
    }];
}

- (void)pp_extractProviderTypes {
    NSMutableOrderedSet<NSString *> *types = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *feat in self.allFeatures) {
        NSString *type = [feat[@"providerType"] isKindOfClass:NSString.class] ? feat[@"providerType"] : @"";
        if (type.length > 0) [types addObject:type];
    }
    self.availableProviderTypes = types.array;
}

- (void)pp_applyFiltering {
    NSArray *result = self.allFeatures;

    // Filter by Provider Type
    if (self.selectedProviderType.length > 0) {
        NSPredicate *typePred = [NSPredicate predicateWithFormat:@"providerType ==[cd] %@", self.selectedProviderType];
        result = [result filteredArrayUsingPredicate:typePred];
    }

    // Filter by Search Query
    if (self.searchQuery.length > 0) {
        NSString *q = self.searchQuery;
        NSPredicate *searchPred = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *feat, NSDictionary<NSString *,id> *bindings) {
            NSString *key = feat[@"featureKey"] ?: @"";
            NSString *titleAr = feat[@"title"][@"ar"] ?: @"";
            NSString *titleEn = feat[@"title"][@"en"] ?: @"";
            NSString *planAr = feat[@"planName"][@"ar"] ?: @"";
            NSString *planEn = feat[@"planName"][@"en"] ?: @"";
            NSString *pType = feat[@"providerType"] ?: @"";
            return [key localizedCaseInsensitiveContainsString:q] ||
                   [titleAr localizedCaseInsensitiveContainsString:q] ||
                   [titleEn localizedCaseInsensitiveContainsString:q] ||
                   [planAr localizedCaseInsensitiveContainsString:q] ||
                   [planEn localizedCaseInsensitiveContainsString:q] ||
                   [pType localizedCaseInsensitiveContainsString:q];
        }];
        result = [result filteredArrayUsingPredicate:searchPred];
    }

    self.filteredFeatures = result;
}

- (NSArray<NSDictionary *> *)pp_flattenFeaturesFromPlans:(NSArray<PPProviderPlan *> *)plans {
    NSMutableArray<NSDictionary *> *features = [NSMutableArray array];
    for (PPProviderPlan *plan in plans) {
        for (NSDictionary *document in plan.featureDocuments) {
            NSMutableDictionary *feature = [document mutableCopy];
            feature[@"planID"] = plan.planID ?: @"";
            feature[@"planName"] = plan.name ?: @{};
            feature[@"providerType"] = plan.providerType ?: @"";
            feature[@"planStatus"] = plan.status ?: @"inactive";
            [features addObject:feature.copy];
        }
    }
    return features.copy;
}

- (void)pp_refreshHeaderMetrics {
    NSUInteger total = self.allFeatures.count;
    NSUInteger enabled = 0;
    NSUInteger limits = 0;
    NSMutableSet<NSString *> *types = [NSMutableSet set];

    for (NSDictionary *feature in self.allFeatures) {
        if (![feature[@"enabled"] isKindOfClass:NSNumber.class] || [feature[@"enabled"] boolValue]) enabled++;
        NSString *limit = [feature[@"limitValue"] isKindOfClass:NSString.class] ? feature[@"limitValue"] : @"";
        if (limit.length > 0) limits++;
        NSString *type = [feature[@"providerType"] isKindOfClass:NSString.class] ? feature[@"providerType"] : @"";
        if (type.length) [types addObject:type];
    }

    self.totalMetricValue.text = [NSString stringWithFormat:@"%lu", (unsigned long)total];
    self.activeMetricValue.text = [NSString stringWithFormat:@"%lu", (unsigned long)enabled];
    self.typesMetricValue.text = [NSString stringWithFormat:@"%lu", (unsigned long)types.count];
    self.limitsMetricValue.text = [NSString stringWithFormat:@"%lu", (unsigned long)limits];
}

- (void)pp_updateState {
    self.stateView.hidden = self.filteredFeatures.count > 0;
    if (self.filteredFeatures.count > 0) return;
    if (self.isLoading) {
        [self.stateView showLoadingWithTitle:kLang(@"Providers_Features_Loading") subtitle:kLang(@"Providers_Features_Subtitle")];
    } else if (self.currentError) {
        [self.stateView showErrorWithTitle:kLang(@"Providers_Features_LoadFailed") subtitle:kLang(@"Providers_Load_Error_Subtitle")];
    } else {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Features_Empty") subtitle:kLang(@"Providers_Features_Empty_Subtitle") symbol:@"shield.lefthalf.filled.badge.checkmark"];
    }
}

#pragma mark - Search Bar Delegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchQuery = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self pp_applyFiltering];
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Table View DataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredFeatures.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPFeatureEntitlementCardCell *cell = [tableView dequeueReusableCellWithIdentifier:PPFeatureEntitlementCellID forIndexPath:indexPath];
    NSDictionary *feature = self.filteredFeatures[(NSUInteger)indexPath.row];
    [cell configureWithFeature:feature];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *feature = self.filteredFeatures[(NSUInteger)indexPath.row];
    PPFeatureDetailViewController *detailVC = [PPFeatureDetailViewController new];
    detailVC.feature = feature;
    [self.navigationController pushViewController:detailVC animated:YES];
    [PPFunc pp_playSelectionEffect];
}

@end
