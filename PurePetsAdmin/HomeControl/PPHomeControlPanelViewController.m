#import "PPHomeControlPanelViewController.h"
@import FirebaseFirestore;
@import FirebaseAuth;
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "AppManager.h"
#import "PPHero.h"
#import "PPFormEngine.h"

typedef NS_ENUM(NSInteger, PPHomeSectionID) {
    PPHomeSectionPremiumSearch = 0,
    PPHomeSectionMarketplaceHero = 1,
    PPHomeSectionProviderCategoryNav = 2,
    PPHomeSectionHero = 3,
    PPHomeSectionPremiumCare = 4,
    PPHomeSectionQuickActions = 5,
    PPHomeSectionMainKinds = 6,
    PPHomeSectionCurrentOrders = 7,
    PPHomeSectionAccessories = 8,
    PPHomeSectionSuggestions = 9,
    PPHomeSectionCarousel = 10,
    PPHomeSectionLastFood = 11,
    PPHomeSectionAdsNearBy = 12,
    PPHomeSectionPetProfile = 13,
    PPHomeSectionNearbyServices = 14,
    PPHomeSectionAdopt = 15,
    PPHomeSectionBuyAgain = 16,
    PPHomeSectionServices = 17
};

static NSString * const PPHomeControlFieldTitleMode = @"titleViewMode";
static NSString * const PPHomeControlFieldNovaFloating = @"novaFloatingVisible";
static NSString * const PPHomeControlFieldBackgroundGlows = @"backgroundGlowsFaded";
static NSString * const PPHomeControlFieldUsedAccessories = @"AllwedUsedAccessories";
static NSString * const PPHomeControlFieldReusableVideo = @"PP_REUSABLE_VIDEO_MEDIA_ENABLED";
static NSString * const PPHomeControlFieldUltraCare = @"PPULTRA_CARE_IS_ACTIVATED";
static NSString * const PPHomeControlFieldLegacyBar = @"PPUSE_LEGACY_BAR";

@class PPHomeSectionMeta;
static PPHomeSectionMeta *PPHomeSectionMetaWithValues(PPHomeSectionID sid, NSString *type, NSString *en, NSString *ar, NSString *descEn, NSString *descAr, BOOL visible, BOOL critical, BOOL conditional);

static UIColor *PPHomeControlAccentColor(void) {
    return AppPrimaryClr ?: UIColor.systemPinkColor;
}

static UIColor *PPHomeControlCanvasColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGroupedBackgroundColor;
    return [UIColor colorWithWhite:0.96 alpha:1.0];
}

static UIColor *PPHomeControlSurfaceColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondarySystemGroupedBackgroundColor;
    return UIColor.whiteColor;
}

static UIColor *PPHomeControlInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.labelColor;
    return UIColor.blackColor;
}

static UIColor *PPHomeControlSubInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondaryLabelColor;
    return [UIColor colorWithWhite:0.38 alpha:1.0];
}

static void PPHomeControlApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    view.layer.shadowRadius = 22.0;
    view.layer.shadowOpacity = 0.055;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.62].CGColor;
}

static NSString *PPHomeControlBoolString(FIRDocumentSnapshot *snapshot, NSString *key, BOOL fallback) {
    id value = snapshot.exists ? snapshot[key] : nil;
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue] ? @"1" : @"0";
    }
    return fallback ? @"1" : @"0";
}

@interface PPHomeSectionMeta : NSObject
@property (nonatomic, assign) PPHomeSectionID sectionID;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *labelEn;
@property (nonatomic, copy) NSString *labelAr;
@property (nonatomic, copy) NSString *descEn;
@property (nonatomic, copy) NSString *descAr;
@property (nonatomic, assign) BOOL defaultVisible;
@property (nonatomic, assign) BOOL critical;
@property (nonatomic, assign) BOOL conditional;
@end

@implementation PPHomeSectionMeta
@end

@interface PPHomeSectionState : NSObject
@property (nonatomic, assign) PPHomeSectionID sectionID;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, assign) BOOL visible;
@end

@implementation PPHomeSectionState
@end

@interface PPHomeControlSectionCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, copy) void (^visibilityChanged)(BOOL visible);
- (void)configureWithMeta:(PPHomeSectionMeta *)meta visible:(BOOL)visible;
@end

@implementation PPHomeControlSectionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPHomeControlSurfaceColor();
        PPHomeControlApplyCardChrome(_cardView, 22.0);
        [self.contentView addSubview:_cardView];

        _symbolView = [UIImageView new];
        _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolView.contentMode = UIViewContentModeCenter;
        _symbolView.tintColor = PPHomeControlAccentColor();
        _symbolView.backgroundColor = [PPHomeControlAccentColor() colorWithAlphaComponent:0.11];
        _symbolView.layer.cornerRadius = 18.0;
        if (@available(iOS 13.0, *)) _symbolView.layer.cornerCurve = kCACornerCurveContinuous;
        [_cardView addSubview:_symbolView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:16];
        _titleLabel.textColor = PPHomeControlInkColor();
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.82;
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:12];
        _subtitleLabel.textColor = PPHomeControlSubInkColor();
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_subtitleLabel];

        _badgeLabel = [UILabel new];
        _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _badgeLabel.font = [Styling fontMedium:11];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.textColor = PPHomeControlAccentColor();
        _badgeLabel.backgroundColor = [PPHomeControlAccentColor() colorWithAlphaComponent:0.10];
        _badgeLabel.layer.cornerRadius = 12.0;
        _badgeLabel.layer.masksToBounds = YES;
        _badgeLabel.adjustsFontSizeToFitWidth = YES;
        _badgeLabel.minimumScaleFactor = 0.78;
        [_cardView addSubview:_badgeLabel];

        _toggleSwitch = [UISwitch new];
        _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        _toggleSwitch.onTintColor = PPHomeControlAccentColor();
        [_toggleSwitch addTarget:self action:@selector(pp_switchChanged:) forControlEvents:UIControlEventValueChanged];
        [_cardView addSubview:_toggleSwitch];

        CGFloat sideInset = 18.0;
        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-7.0],

            [_symbolView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:sideInset],
            [_symbolView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:16.0],
            [_symbolView.widthAnchor constraintEqualToConstant:46.0],
            [_symbolView.heightAnchor constraintEqualToConstant:46.0],

            [_toggleSwitch.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-sideInset],
            [_toggleSwitch.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_symbolView.trailingAnchor constant:14.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggleSwitch.leadingAnchor constant:-14.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:16.0],

            [_badgeLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_badgeLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8.0],
            [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:74.0],
            [_badgeLabel.heightAnchor constraintEqualToConstant:24.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_toggleSwitch.leadingAnchor constant:-14.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_badgeLabel.bottomAnchor constant:7.0],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-15.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.visibilityChanged = nil;
}

- (void)configureWithMeta:(PPHomeSectionMeta *)meta visible:(BOOL)visible {
    NSString *langCode = [Language currentLanguageCode];
    BOOL isArabic = [langCode isEqualToString:@"ar"];
    self.titleLabel.text = isArabic ? meta.labelAr : meta.labelEn;
    self.subtitleLabel.text = isArabic ? meta.descAr : meta.descEn;
    self.toggleSwitch.on = visible;
    self.badgeLabel.text = meta.critical ? kLang(@"HomeControl_Critical") : (meta.conditional ? kLang(@"HomeControl_Conditional") : (visible ? kLang(@"HomeControl_Visible") : kLang(@"HomeControl_Hidden")));

    NSString *symbol = @"rectangle.stack.fill";
    UIColor *tint = PPHomeControlAccentColor();
    if (meta.critical) {
        symbol = @"exclamationmark.shield.fill";
        tint = UIColor.systemOrangeColor;
    } else if (meta.conditional) {
        symbol = @"sparkles";
        tint = UIColor.systemBlueColor;
    } else if (!visible) {
        symbol = @"eye.slash.fill";
        tint = PPHomeControlSubInkColor();
    }
    self.symbolView.image = [UIImage systemImageNamed:symbol];
    self.symbolView.tintColor = tint;
    self.symbolView.backgroundColor = [tint colorWithAlphaComponent:0.11];
    self.badgeLabel.textColor = tint;
    self.badgeLabel.backgroundColor = [tint colorWithAlphaComponent:0.10];
}

- (void)pp_switchChanged:(UISwitch *)sender {
    if (self.visibilityChanged) self.visibilityChanged(sender.isOn);
}

@end

@interface PPHomeControlPanelViewController ()
@property (nonatomic, strong) NSMutableArray<PPHomeSectionState *> *sections;
@property (nonatomic, strong) NSArray<PPHomeSectionMeta *> *catalog;
@property (nonatomic, strong) PPFormEngineView *globalFormView;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, assign) BOOL isDirty;
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, strong) FIRDocumentReference *configRef;
@end

@implementation PPHomeControlPanelViewController

static NSArray<PPHomeSectionMeta *> *PPBuildHomeCatalog(void) {
    return @[ PPHomeSectionMetaWithValues(PPHomeSectionPremiumSearch, @"PPHomeSectionPremiumSearch", @"Premium Search Bar", @"شريط البحث المتميز", @"In-feed premium search slot.", @"موضع البحث المتميز داخل الصفحة الرئيسية.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionMarketplaceHero, @"PPHomeSectionMarketplaceHero", @"Marketplace Hero", @"بطاقة السوق الرئيسية", @"Provider marketplace hero card.", @"بطاقة السوق الرئيسية للمزودين.", NO, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionProviderCategoryNav, @"PPHomeSectionProviderCategoryNav", @"Provider Categories", @"فئات المزودين", @"Provider marketplace navigation.", @"شريط تنقل فئات المزودين.", NO, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionHero, @"PPHomeSectionHero", @"Hero Banner", @"البانر الرئيسي", @"Top welcome card.", @"بطاقة الترحيب العلوية.", YES, YES, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionPremiumCare, @"PPHomeSectionPremiumCare", @"Premium Pet Care", @"الرعاية المتميزة", @"Premium pet-care gateway.", @"بطاقة بوابة الرعاية المتميزة.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionQuickActions, @"PPHomeSectionQuickActions", @"Quick Actions", @"الإجراءات السريعة", @"Horizontal shortcuts row.", @"صف اختصارات سريعة.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionMainKinds, @"PPHomeSectionMainKinds", @"Pet Categories", @"أنواع الحيوانات", @"Pet category grid.", @"شبكة فئات الحيوانات.", YES, YES, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionCurrentOrders, @"PPHomeSectionCurrentOrders", @"Current Orders", @"الطلبات الحالية", @"Live order status.", @"حالة الطلبات المباشرة.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionAccessories, @"PPHomeSectionAccessories", @"Pet Accessories", @"إكسسوارات الحيوانات", @"Accessories grid.", @"شبكة إكسسوارات.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionSuggestions, @"PPHomeSectionSuggestions", @"Smart Suggestions", @"اقتراحات ذكية", @"Personalized suggestions.", @"اقتراحات شخصية.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionCarousel, @"PPHomeSectionCarousel", @"Promo Carousel", @"شريط العروض", @"Auto-scrolling banners.", @"بانرات ترويجية متحركة.", YES, YES, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionLastFood, @"PPHomeSectionLastFood", @"Recent Food", @"آخر الأطعمة", @"Recently added food.", @"آخر أصناف الطعام.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionAdsNearBy, @"PPHomeSectionAdsNearBy", @"Ads Nearby", @"إعلانات قريبة", @"Location-based ads.", @"إعلانات قريبة من الموقع.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionPetProfile, @"PPHomeSectionPetProfile", @"Pet Profile Card", @"بطاقة ملف الحيوان", @"Primary pet profile.", @"ملف الحيوان الرئيسي.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionNearbyServices, @"PPHomeSectionNearbyServices", @"Nearby Services", @"خدمات قريبة", @"Geo-aware providers.", @"مزودو الخدمات حسب الموقع.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionAdopt, @"PPHomeSectionAdopt", @"Adopt a Pet", @"تبني حيوان", @"Adoption CTA card.", @"بطاقة دعوة للتبني.", YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionBuyAgain, @"PPHomeSectionBuyAgain", @"Buy It Again", @"اشترِ مرة أخرى", @"Re-order shortcut.", @"اختصار إعادة الطلب.", YES, NO, YES),
        PPHomeSectionMetaWithValues(PPHomeSectionServices, @"PPHomeSectionServices", @"Professional Services", @"خدمات احترافية", @"Service shortcuts.", @"اختصارات الخدمات.", NO, NO, NO)
    ];
}

static PPHomeSectionMeta *PPHomeSectionMetaWithValues(PPHomeSectionID sid, NSString *type, NSString *en, NSString *ar, NSString *descEn, NSString *descAr, BOOL visible, BOOL critical, BOOL conditional) {
    PPHomeSectionMeta *m = [PPHomeSectionMeta new];
    m.sectionID = sid; m.type = type; m.labelEn = en; m.labelAr = ar;
    m.descEn = descEn; m.descAr = descAr; m.defaultVisible = visible;
    m.critical = critical; m.conditional = conditional;
    return m;
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"HomeControl_Title");
    self.catalog = PPBuildHomeCatalog();
    self.configRef = [[[FIRFirestore firestore] collectionWithPath:@"AppConfigCol"] documentWithPath:@"HomeConfig"];

    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_buildHeader];
    [self loadConfig];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroBackground startAnimations];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.heroBackground stopAnimations];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_updateInsets];
    [self pp_sizeHeaderToFit];
}

- (void)pp_configureNavigation {
    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Save") style:UIBarButtonItemStyleDone target:self action:@selector(didTapSave)];
    self.navigationItem.rightBarButtonItem = saveBtn;
    [self pp_updateSaveButton];
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPHomeControlCanvasColor();
    self.tableView.backgroundColor = PPHomeControlCanvasColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 112.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    [self.tableView registerClass:PPHomeControlSectionCell.class forCellReuseIdentifier:@"PPHomeControlSectionCell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"PPHomeControlStateCell"];
}

- (PPFormStyle *)pp_formStyle {
    PPFormStyle *style = [[PPFormStyle defaultStyle] copy];
    style.accentColor = PPHomeControlAccentColor();
    style.cardBackgroundColor = PPHomeControlSurfaceColor();
     style.primaryTextColor = PPHomeControlInkColor();
    style.secondaryTextColor = PPHomeControlSubInkColor();
    style.cardCornerRadius = 22.0;
    style.fieldCornerRadius = 16.0;
    style.shadowOpacity = 0.045;
    style.stackSpacing = 10.0;
    return style;
}

- (PPFormFieldConfig *)pp_toggleFieldWithIdentifier:(NSString *)identifier titleKey:(NSString *)titleKey {
    PPFormFieldConfig *field = [PPFormFieldConfig fieldWithIdentifier:identifier title:kLang(titleKey) placeholder:@"" inputType:PPFormInputTypeToggle];
    __weak typeof(self) weakSelf = self;
    field.textChangeBlock = ^(PPFormFieldConfig *config, NSString *value) {
        (void)config; (void)value;
        weakSelf.isDirty = YES;
        [weakSelf pp_updateSaveButton];
    };
    return field;
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18.0;
    stack.alignment = UIStackViewAlignmentFill;
    [header addSubview:stack];

    UIView *heroCard = [UIView new];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    heroCard.clipsToBounds = NO;
    [stack addArrangedSubview:heroCard];
    [heroCard.heightAnchor constraintGreaterThanOrEqualToConstant:168.0].active = YES;

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.72;
    hero.accentColorOverride = PPHomeControlAccentColor();
    [heroCard addSubview:hero];
    self.heroBackground = hero;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = PPHomeControlAccentColor();
    icon.backgroundColor = [PPHomeControlAccentColor() colorWithAlphaComponent:0.12];
    icon.contentMode = UIViewContentModeCenter;
    icon.layer.cornerRadius = 20.0;
    if (@available(iOS 13.0, *)) icon.layer.cornerCurve = kCACornerCurveContinuous;
    [heroCard addSubview:icon];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = kLang(@"HomeControl_Title");
    title.font = [Styling fontBold:28];
    title.textColor = PPHomeControlInkColor();
    title.textAlignment = [Language alignmentForCurrentLanguage];
    title.numberOfLines = 2;
    [heroCard addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = kLang(@"HomeControl_Subtitle");
    subtitle.font = [Styling fontRegular:14];
    subtitle.textColor = PPHomeControlSubInkColor();
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.numberOfLines = 2;
    [heroCard addSubview:subtitle];

    UIView *countPill = [UIView new];
    countPill.translatesAutoresizingMaskIntoConstraints = NO;
    countPill.backgroundColor = [PPHomeControlAccentColor() colorWithAlphaComponent:0.10];
    countPill.layer.cornerRadius = 17.0;
    countPill.layer.masksToBounds = YES;
    [heroCard addSubview:countPill];

    UILabel *countLabel = [UILabel new];
    countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    countLabel.font = [Styling fontBold:13];
    countLabel.textColor = PPHomeControlAccentColor();
    countLabel.textAlignment = NSTextAlignmentCenter;
    countLabel.adjustsFontSizeToFitWidth = YES;
    countLabel.minimumScaleFactor = 0.74;
    [countPill addSubview:countLabel];
    self.heroCountLabel = countLabel;

    UILabel *settingsTitle = [UILabel new];
    settingsTitle.translatesAutoresizingMaskIntoConstraints = NO;
    settingsTitle.text = kLang(@"HomeControl_GlobalSettings");
    settingsTitle.font = [Styling fontBold:20];
    settingsTitle.textColor = PPHomeControlInkColor();
    settingsTitle.textAlignment = [Language alignmentForCurrentLanguage];
    [stack addArrangedSubview:settingsTitle];

    self.globalFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *titleMode = [PPFormFieldConfig fieldWithIdentifier:PPHomeControlFieldTitleMode title:kLang(@"HomeControl_TitleViewMode") placeholder:@"" inputType:PPFormInputTypeSegmented];
    titleMode.optionTitles = @[kLang(@"HomeControl_TitleViewLocation"), kLang(@"HomeControl_TitleViewSearch")];
    titleMode.optionValues = @[@"location", @"search"];
    titleMode.value = @"location";
    __weak typeof(self) weakSelf = self;
    titleMode.textChangeBlock = ^(PPFormFieldConfig *config, NSString *value) {
        (void)config; (void)value;
        weakSelf.isDirty = YES;
        [weakSelf pp_updateSaveButton];
    };

    [self.globalFormView setFields:@[
        titleMode,
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldNovaFloating titleKey:@"HomeControl_NovaFloating"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldBackgroundGlows titleKey:@"HomeControl_BackgroundGlows"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldUsedAccessories titleKey:@"HomeControl_UsedAccessories"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldReusableVideo titleKey:@"HomeControl_ReusableVideo"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldUltraCare titleKey:@"HomeControl_UltraCare"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldLegacyBar titleKey:@"HomeControl_LegacyBar"]
    ]];
    [stack addArrangedSubview:self.globalFormView];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:18.0],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-18.0],

        [hero.topAnchor constraintEqualToAnchor:heroCard.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:heroCard.bottomAnchor],

        [icon.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:24.0],
        [icon.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:24.0],
        [icon.widthAnchor constraintEqualToConstant:54.0],
        [icon.heightAnchor constraintEqualToConstant:54.0],

        [countPill.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-24.0],
        [countPill.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:24.0],
        [countPill.widthAnchor constraintGreaterThanOrEqualToConstant:112.0],
        [countPill.heightAnchor constraintEqualToConstant:34.0],

        [countLabel.topAnchor constraintEqualToAnchor:countPill.topAnchor],
        [countLabel.leadingAnchor constraintEqualToAnchor:countPill.leadingAnchor constant:12.0],
        [countLabel.trailingAnchor constraintEqualToAnchor:countPill.trailingAnchor constant:-12.0],
        [countLabel.bottomAnchor constraintEqualToAnchor:countPill.bottomAnchor],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:22.0],
        [title.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:24.0],
        [title.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-24.0],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.bottomAnchor constraintLessThanOrEqualToAnchor:heroCard.bottomAnchor constant:-24.0],
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_updateHeroCount];
    [self pp_sizeHeaderToFit];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;

    CGRect frame = self.headerContainer.frame;
    if (fabs(frame.size.width - width) > 0.5) {
        frame.size.width = width;
        self.headerContainer.frame = frame;
    }

    [self.headerContainer setNeedsLayout];
    [self.headerContainer layoutIfNeeded];
    CGSize target = CGSizeMake(width, UILayoutFittingCompressedSize.height);
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:target
                                         withHorizontalFittingPriority:UILayoutPriorityRequired
                                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    height = MAX(1.0, ceil(height));
    if (fabs(frame.size.height - height) > 0.5) {
        frame.size.height = height;
        self.headerContainer.frame = frame;
        self.tableView.tableHeaderView = self.headerContainer;
    }
}

- (void)pp_updateInsets {
    CGFloat tabHeight = self.tabBarController ? CGRectGetHeight(self.tabBarController.tabBar.bounds) : 0.0;
    CGFloat bottom = MAX(28.0, tabHeight + 34.0);
    UIEdgeInsets inset = self.tableView.contentInset;
    inset.bottom = bottom;
    self.tableView.contentInset = inset;
    self.tableView.scrollIndicatorInsets = inset;
}

- (void)loadConfig {
    self.isLoading = YES;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [self.configRef getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                [weakSelf.tableView reloadData];
                return;
            }
            [weakSelf buildSectionsFromSnapshot:snapshot];
            [weakSelf pp_applyGlobalValuesFromSnapshot:snapshot];
            weakSelf.isDirty = NO;
            [weakSelf pp_updateHeroCount];
            [weakSelf pp_updateSaveButton];
            [weakSelf.tableView reloadData];
            [weakSelf pp_sizeHeaderToFit];
        });
    }];
}

- (void)buildSectionsFromSnapshot:(FIRDocumentSnapshot *)snapshot {
    self.sections = [NSMutableArray array];

    if (snapshot.exists) {
        NSArray *rawSections = snapshot[@"sections"];
        if ([rawSections isKindOfClass:NSArray.class]) {
            for (NSDictionary *raw in rawSections) {
                if (![raw isKindOfClass:NSDictionary.class]) continue;
                NSNumber *sidNum = raw[@"id"];
                NSNumber *visNum = raw[@"visible"];
                PPHomeSectionID sid = sidNum ? (PPHomeSectionID)[sidNum integerValue] : -1;
                PPHomeSectionMeta *meta = [self metaForID:sid];
                if (!meta) continue;

                PPHomeSectionState *state = [PPHomeSectionState new];
                state.sectionID = sid;
                state.visible = visNum ? [visNum boolValue] : meta.defaultVisible;
                state.type = meta.type;
                [self.sections addObject:state];
            }
        }
    }

    for (PPHomeSectionMeta *meta in self.catalog) {
        BOOL found = NO;
        for (PPHomeSectionState *s in self.sections) {
            if (s.sectionID == meta.sectionID) { found = YES; break; }
        }
        if (!found) {
            PPHomeSectionState *state = [PPHomeSectionState new];
            state.sectionID = meta.sectionID;
            state.type = meta.type;
            state.visible = meta.defaultVisible;
            [self.sections addObject:state];
        }
    }
}

- (void)pp_applyGlobalValuesFromSnapshot:(FIRDocumentSnapshot *)snapshot {
    NSString *mode = @"location";
    id rawMode = snapshot.exists ? snapshot[@"titleViewMode"] : nil;
    if ([rawMode isKindOfClass:NSString.class] && [rawMode length] > 0) {
        mode = rawMode;
    }

    [self.globalFormView setValues:@{
        PPHomeControlFieldTitleMode: mode,
        PPHomeControlFieldNovaFloating: PPHomeControlBoolString(snapshot, PPHomeControlFieldNovaFloating, NO),
        PPHomeControlFieldBackgroundGlows: PPHomeControlBoolString(snapshot, PPHomeControlFieldBackgroundGlows, NO),
        PPHomeControlFieldUsedAccessories: PPHomeControlBoolString(snapshot, PPHomeControlFieldUsedAccessories, NO),
        PPHomeControlFieldReusableVideo: PPHomeControlBoolString(snapshot, PPHomeControlFieldReusableVideo, NO),
        PPHomeControlFieldUltraCare: PPHomeControlBoolString(snapshot, PPHomeControlFieldUltraCare, NO),
        PPHomeControlFieldLegacyBar: PPHomeControlBoolString(snapshot, PPHomeControlFieldLegacyBar, NO)
    }];
}

- (PPHomeSectionMeta *)metaForID:(PPHomeSectionID)sid {
    for (PPHomeSectionMeta *m in self.catalog) {
        if (m.sectionID == sid) return m;
    }
    return nil;
}

- (void)didTapSave {
    if (self.isSaving) return;
    self.isSaving = YES;
    [self pp_updateSaveButton];

    NSMutableArray *sectionsPayload = [NSMutableArray array];
    for (PPHomeSectionState *s in self.sections) {
        [sectionsPayload addObject:@{
            @"id": @(s.sectionID),
            @"type": s.type ?: @"",
            @"visible": @(s.visible)
        }];
    }

    NSDictionary<NSString *, NSString *> *formValues = [self.globalFormView values];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"sections"] = sectionsPayload;
    payload[@"titleViewMode"] = formValues[PPHomeControlFieldTitleMode].length ? formValues[PPHomeControlFieldTitleMode] : @"location";
    payload[@"novaFloatingVisible"] = @([formValues[PPHomeControlFieldNovaFloating] boolValue]);
    payload[@"backgroundGlowsFaded"] = @([formValues[PPHomeControlFieldBackgroundGlows] boolValue]);
    payload[@"AllwedUsedAccessories"] = @([formValues[PPHomeControlFieldUsedAccessories] boolValue]);
    payload[@"PP_REUSABLE_VIDEO_MEDIA_ENABLED"] = @([formValues[PPHomeControlFieldReusableVideo] boolValue]);
    payload[@"PPULTRA_CARE_IS_ACTIVATED"] = @([formValues[PPHomeControlFieldUltraCare] boolValue]);
    payload[@"PPUSE_LEGACY_BAR"] = @([formValues[PPHomeControlFieldLegacyBar] boolValue]);
    payload[@"updatedAt"] = [FIRTimestamp timestampWithDate:[NSDate date]];

    __weak typeof(self) weakSelf = self;
    [self.configRef setData:payload merge:YES completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isSaving = NO;
            [weakSelf pp_updateSaveButton];
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                weakSelf.isDirty = NO;
                [weakSelf pp_updateSaveButton];
                [PPFunc pp_playSuccessEffect];
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Success_Title") subtitle:kLang(@"HomeControl_Saved")];
            }
        });
    }];
}

- (void)pp_updateSaveButton {
    self.navigationItem.rightBarButtonItem.enabled = !self.isSaving && !self.isLoading;
    self.navigationItem.rightBarButtonItem.title = self.isSaving ? kLang(@"Loading") : kLang(@"Save");
}

- (void)pp_updateHeroCount {
    NSInteger enabled = 0;
    for (PPHomeSectionState *state in self.sections) {
        if (state.visible) enabled += 1;
    }
    NSString *format = kLang(@"HomeControl_EnabledCount_Format");
    self.heroCountLabel.text = [NSString stringWithFormat:format, @(enabled), @(self.sections.count)];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isLoading && self.sections.count == 0) return 1;
    return MAX(self.sections.count, 1);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 58.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.clearColor;

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = kLang(@"HomeControl_SectionOrder");
    label.font = [Styling fontBold:20];
    label.textColor = PPHomeControlInkColor();
    label.textAlignment = [Language alignmentForCurrentLanguage];
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:22.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-22.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-9.0]
    ]];
    return container;
}

- (UITableViewCell *)pp_stateCellWithText:(NSString *)text {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"PPHomeControlStateCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PPHomeControlStateCell"];
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = text;
    cell.textLabel.font = [Styling fontMedium:15];
    cell.textLabel.textColor = PPHomeControlSubInkColor();
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.sections.count == 0) {
        return [self pp_stateCellWithText:self.isLoading ? kLang(@"Loading") : kLang(@"HomeControl_EmptySections")];
    }

    PPHomeSectionState *state = self.sections[indexPath.row];
    PPHomeSectionMeta *meta = [self metaForID:state.sectionID];
    PPHomeControlSectionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PPHomeControlSectionCell" forIndexPath:indexPath];
    [cell configureWithMeta:meta visible:state.visible];

    __weak typeof(self) weakSelf = self;
    cell.visibilityChanged = ^(BOOL visible) {
        state.visible = visible;
        weakSelf.isDirty = YES;
        [weakSelf pp_updateHeroCount];
        [weakSelf pp_updateSaveButton];
        [weakSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    };
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0.0, 18.0);
    [UIView animateWithDuration:0.42 delay:MIN(indexPath.row * 0.026, 0.22) usingSpringWithDamping:0.86 initialSpringVelocity:0.35 options:UIViewAnimationOptionCurveEaseOut animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
