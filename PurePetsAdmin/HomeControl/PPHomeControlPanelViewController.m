#import "PPHomeControlPanelViewController.h"
@import FirebaseFirestore;
@import FirebaseAuth;
#import "Language.h"
#import "Styling.h"
#import "PPAlertHelper.h"
#import "PPFunc+Haptics.h"
#import "AppManager.h"
#import "PPHero.h"
#import "PPFormEngine.h"
#import "PPAlertHelper.h"

typedef NS_ENUM(NSInteger, PPHomeSectionID) {
    // These raw values are the shared iOS HomeConfig contract. Do not
    // renumber them to match the order in which the catalog is presented.
    PPHomeSectionHero = 0,
    PPHomeSectionQuickActions = 1,
    PPHomeSectionCurrentOrders = 2,
    PPHomeSectionCarousel = 4,
    PPHomeSectionMainKinds = 5,
    PPHomeSectionSuggestions = 6,
    PPHomeSectionAccessories = 7,
    PPHomeSectionPetProfile = 8,
    PPHomeSectionPremiumCare = 9,
    PPHomeSectionLastFood = 10,
    PPHomeSectionNearbyServices = 11,
    PPHomeSectionAdsNearBy = 12,
    PPHomeSectionAdopt = 13,
    PPHomeSectionBuyAgain = 14,
    PPHomeSectionPremiumSearch = 15,
    PPHomeSectionProviderCategoryNav = 16,
    PPHomeSectionMarketplaceHero = 17,
    PPHomeSectionSuggestionAds = 18,
    PPHomeSectionSuggestionAccessories = 19
};

static NSString * const PPHomeControlFieldTitleMode = @"titleViewMode";
static NSString * const PPHomeControlFieldNovaFloating = @"novaFloatingVisible";
static NSString * const PPHomeControlFieldBackgroundGlows = @"backgroundGlowsFaded";
static NSString * const PPHomeControlFieldPureLens = @"pureLensVisible";
static NSString * const PPHomeControlFieldUsedAccessories = @"AllwedUsedAccessories";
static NSString * const PPHomeControlFieldReusableVideo = @"PP_REUSABLE_VIDEO_MEDIA_ENABLED";
static NSString * const PPHomeControlFieldReusableVideoLegacy = @"PPReusableVideoMediaEnabled";
static NSString * const PPHomeControlFieldUltraCare = @"PPULTRA_CARE_IS_ACTIVATED";
static NSString * const PPHomeControlFieldLegacyBar = @"PPUSE_LEGACY_BAR";
static NSString * const PPHomeControlFieldUniversalCells = @"BBUniversalCellUseSwiftUI";
static NSString * const PPHomeControlFieldPremiumCareVisible = @"premiumCareVisible";
static NSNotificationName const PPHomeControlNavigationItemsDidChangeNotification = @"PPHomeControlNavigationItemsDidChangeNotification";

@class PPHomeSectionMeta;
static PPHomeSectionMeta *PPHomeSectionMetaWithValues(PPHomeSectionID sid, NSString *type, NSString *en, NSString *ar, NSString *descEn, NSString *descAr, BOOL visible, BOOL critical, BOOL conditional);

static UIColor *PPHomeControlAccentColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPHomeControlCanvasColor(void) {
    return UIColor.clearColor;
}

static UIColor *PPHomeControlSurfaceColor(void) {
    return [UIColor ppElevatedSurface];
}

static UIColor *PPHomeControlInkColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPHomeControlSubInkColor(void) {
    return [UIColor ppTextSecondary];
}

static void PPHomeControlApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = [UIColor ppShadow].CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    view.layer.shadowRadius = 22.0;
    view.layer.shadowOpacity = 0.055;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.72].CGColor;
}

static NSString *PPHomeControlBoolString(FIRDocumentSnapshot *snapshot, NSString *key, BOOL fallback) {
    id value = snapshot.exists ? snapshot[key] : nil;
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue] ? @"1" : @"0";
    }
    return fallback ? @"1" : @"0";
}

static NSString *PPHomeControlLocalizedValue(NSString *key, NSString *languageCode) {
    if ([languageCode isEqualToString:[Language currentLanguageCode]]) {
        return kLang(key);
    }

    NSString *path = [[NSBundle mainBundle] pathForResource:languageCode ofType:@"lproj"];
    NSBundle *languageBundle = path.length > 0 ? [NSBundle bundleWithPath:path] : [NSBundle mainBundle];
    return NSLocalizedStringFromTableInBundle(key, nil, languageBundle, @"");
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
        _titleLabel.adjustsFontForContentSizeCategory = YES;
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
        _badgeLabel.adjustsFontForContentSizeCategory = YES;
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
    if (!meta) return;
    NSString *langCode = [Language currentLanguageCode];
    BOOL isArabic = [langCode isEqualToString:@"ar"];
    NSString *localizedTitle = isArabic ? meta.labelAr : meta.labelEn;
    NSString *visibilityText = visible ? kLang(@"HomeControl_Visible") : kLang(@"HomeControl_Hidden");
    self.titleLabel.text = isArabic ? meta.labelAr : meta.labelEn;
    self.subtitleLabel.text = isArabic ? meta.descAr : meta.descEn;
    self.toggleSwitch.on = visible;
    self.badgeLabel.text = meta.critical ? kLang(@"HomeControl_Critical") : (meta.conditional ? kLang(@"HomeControl_Conditional") : (visible ? kLang(@"HomeControl_Visible") : kLang(@"HomeControl_Hidden")));
    self.toggleSwitch.accessibilityLabel = localizedTitle;
    self.toggleSwitch.accessibilityValue = visibilityText;

    NSString *symbol = @"rectangle.stack.fill";
    UIColor *tint = PPHomeControlAccentColor();
    if (meta.critical) {
        symbol = @"exclamationmark.shield.fill";
        tint = [UIColor ppWarning];
    } else if (meta.conditional) {
        symbol = @"sparkles";
        tint = [UIColor ppInfo];
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

@interface PPHomeControlPanelViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSMutableArray<PPHomeSectionState *> *sections;
@property (nonatomic, strong) NSArray<PPHomeSectionMeta *> *catalog;
@property (nonatomic, strong) PPFormEngineView *globalFormView;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, strong) UIButton *globalSettingsToggleButton;
@property (nonatomic, strong) UIView *previewFooterView;
@property (nonatomic, strong) UIStackView *previewStackView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *filterText;
@property (nonatomic, copy) NSArray<PPHomeSectionState *> *savedSections;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *savedGlobalValues;
@property (nonatomic, assign) BOOL isDirty;
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL globalSettingsExpanded;
@property (nonatomic, assign) BOOL isSizingHeader;
@property (nonatomic, strong) FIRDocumentReference *configRef;

- (NSArray<PPHomeSectionState *> *)pp_defaultSectionStates;
- (NSArray<PPHomeSectionState *> *)pp_copySections:(NSArray<PPHomeSectionState *> *)sections;
- (NSDictionary<NSString *, NSString *> *)pp_defaultGlobalValues;
- (NSArray<PPHomeSectionState *> *)pp_filteredSections;
- (void)pp_updateGlobalSettingsAppearance;
- (void)pp_updatePreview;
- (void)pp_updateNavigationItems;
- (void)pp_updateSaveButton;
- (PPHomeSectionMeta *)metaForID:(PPHomeSectionID)sid;
- (void)pp_commitSaveWithSections:(NSArray<PPHomeSectionState *> *)sections;
- (void)resetToDefaults;
- (void)revertChanges;
@end

@implementation PPHomeControlPanelViewController

static NSArray<PPHomeSectionMeta *> *PPBuildHomeCatalog(void) {
    // Keep this catalog order identical to Console's IOS_SECTION_CATALOG and
    // the consumer iOS fallback order. The IDs are sparse by contract.
    return @[ PPHomeSectionMetaWithValues(PPHomeSectionPremiumSearch, @"PPHomeSectionPremiumSearch", PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumSearch_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumSearch_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumSearch_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumSearch_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionMarketplaceHero, @"PPHomeSectionMarketplaceHero", PPHomeControlLocalizedValue(@"HomeControl_Section_MarketplaceHero_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_MarketplaceHero_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_MarketplaceHero_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_MarketplaceHero_Description", @"ar"), NO, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionProviderCategoryNav, @"PPHomeSectionProviderCategoryNav", PPHomeControlLocalizedValue(@"HomeControl_Section_ProviderCategoryNav_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_ProviderCategoryNav_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_ProviderCategoryNav_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_ProviderCategoryNav_Description", @"ar"), NO, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionHero, @"PPHomeSectionHero", PPHomeControlLocalizedValue(@"HomeControl_Section_Hero_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Hero_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_Hero_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Hero_Description", @"ar"), YES, YES, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionMainKinds, @"PPHomeSectionMainKinds", PPHomeControlLocalizedValue(@"HomeControl_Section_MainKinds_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_MainKinds_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_MainKinds_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_MainKinds_Description", @"ar"), YES, YES, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionPremiumCare, @"PPHomeSectionPremiumCare", PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumCare_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumCare_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumCare_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_PremiumCare_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionQuickActions, @"PPHomeSectionQuickActions", PPHomeControlLocalizedValue(@"HomeControl_Section_QuickActions_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_QuickActions_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_QuickActions_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_QuickActions_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionCurrentOrders, @"PPHomeSectionCurrentOrders", PPHomeControlLocalizedValue(@"HomeControl_Section_CurrentOrders_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_CurrentOrders_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_CurrentOrders_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_CurrentOrders_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionAccessories, @"PPHomeSectionAccessories", PPHomeControlLocalizedValue(@"HomeControl_Section_Accessories_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Accessories_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_Accessories_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Accessories_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionSuggestionAds, @"PPHomeSectionSuggestionAds", PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAds_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAds_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAds_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAds_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionSuggestionAccessories, @"PPHomeSectionSuggestionAccessories", PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAccessories_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAccessories_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAccessories_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_SuggestionAccessories_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionSuggestions, @"PPHomeSectionSuggestions", PPHomeControlLocalizedValue(@"HomeControl_Section_Suggestions_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Suggestions_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_Suggestions_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Suggestions_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionCarousel, @"PPHomeSectionCarousel", PPHomeControlLocalizedValue(@"HomeControl_Section_Carousel_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Carousel_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_Carousel_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Carousel_Description", @"ar"), YES, YES, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionLastFood, @"PPHomeSectionLastFood", PPHomeControlLocalizedValue(@"HomeControl_Section_LastFood_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_LastFood_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_LastFood_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_LastFood_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionAdsNearBy, @"PPHomeSectionAdsNearBy", PPHomeControlLocalizedValue(@"HomeControl_Section_AdsNearBy_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_AdsNearBy_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_AdsNearBy_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_AdsNearBy_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionNearbyServices, @"PPHomeSectionNearbyServices", PPHomeControlLocalizedValue(@"HomeControl_Section_NearbyServices_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_NearbyServices_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_NearbyServices_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_NearbyServices_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionAdopt, @"PPHomeSectionAdopt", PPHomeControlLocalizedValue(@"HomeControl_Section_Adopt_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Adopt_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_Adopt_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_Adopt_Description", @"ar"), YES, NO, NO),
        PPHomeSectionMetaWithValues(PPHomeSectionBuyAgain, @"PPHomeSectionBuyAgain", PPHomeControlLocalizedValue(@"HomeControl_Section_BuyAgain_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_BuyAgain_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_BuyAgain_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_BuyAgain_Description", @"ar"), YES, NO, YES),
        PPHomeSectionMetaWithValues(PPHomeSectionPetProfile, @"PPHomeSectionPetProfile", PPHomeControlLocalizedValue(@"HomeControl_Section_PetProfile_Label", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_PetProfile_Label", @"ar"), PPHomeControlLocalizedValue(@"HomeControl_Section_PetProfile_Description", @"en"), PPHomeControlLocalizedValue(@"HomeControl_Section_PetProfile_Description", @"ar"), YES, NO, NO)
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
    self.sections = [[self pp_defaultSectionStates] mutableCopy];
    self.savedSections = [self pp_copySections:[self pp_defaultSectionStates]];
    self.savedGlobalValues = [self pp_defaultGlobalValues];
    self.filterText = @"";
    self.globalSettingsExpanded = NO;
    self.configRef = [[[FIRFirestore firestore] collectionWithPath:@"AppConfigCol"] documentWithPath:@"HomeConfig"];

    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_buildHeader];
    [self pp_buildPreviewFooter];
    [self loadConfig];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [self.heroBackground startAnimations];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.backgroundColor = PPHomeControlCanvasColor();
    self.tableView.backgroundColor = PPHomeControlCanvasColor();
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
    UIBarButtonItem *reload = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadConfig)];
    reload.accessibilityLabel = kLang(@"HomeControl_Reload");
    self.navigationItem.leftBarButtonItems = @[reload];
    [self pp_updateNavigationItems];
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPHomeControlCanvasColor();
    self.view.opaque = NO;
    self.tableView.backgroundColor = PPHomeControlCanvasColor();
    self.tableView.opaque = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 112.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.editing = YES;
    [self.tableView registerClass:PPHomeControlSectionCell.class forCellReuseIdentifier:@"PPHomeControlSectionCell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"PPHomeControlStateCell"];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = kLang(@"HomeControl_SearchPlaceholder");
    self.searchController.searchBar.accessibilityLabel = kLang(@"HomeControl_SearchSections");
    self.definesPresentationContext = YES;
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
        [weakSelf pp_updateNavigationItems];
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

    [stack addArrangedSubview:self.searchController.searchBar];
    [self.searchController.searchBar.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;

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

    UIView *settingsHeader = [UIView new];
    settingsHeader.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *settingsTitle = [UILabel new];
    settingsTitle.translatesAutoresizingMaskIntoConstraints = NO;
    settingsTitle.text = kLang(@"HomeControl_GlobalSettings");
    settingsTitle.font = [Styling fontBold:20];
    settingsTitle.textColor = PPHomeControlInkColor();
    settingsTitle.textAlignment = [Language alignmentForCurrentLanguage];
    settingsTitle.adjustsFontForContentSizeCategory = YES;
    [settingsHeader addSubview:settingsTitle];

    UIButton *settingsToggle = [UIButton buttonWithType:UIButtonTypeSystem];
    settingsToggle.translatesAutoresizingMaskIntoConstraints = NO;
    settingsToggle.tintColor = PPHomeControlSubInkColor();
    settingsToggle.accessibilityLabel = kLang(@"HomeControl_GlobalSettings");
    settingsToggle.accessibilityTraits = UIAccessibilityTraitButton;
    [settingsToggle addTarget:self action:@selector(toggleGlobalSettings) forControlEvents:UIControlEventTouchUpInside];
    [settingsHeader addSubview:settingsToggle];
    self.globalSettingsToggleButton = settingsToggle;
    [stack addArrangedSubview:settingsHeader];

    self.globalFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *titleMode = [PPFormFieldConfig fieldWithIdentifier:PPHomeControlFieldTitleMode title:kLang(@"HomeControl_TitleViewMode") placeholder:@"" inputType:PPFormInputTypeSegmented];
    titleMode.optionTitles = @[kLang(@"HomeControl_TitleViewLocation"), kLang(@"HomeControl_TitleViewSearch")];
    titleMode.optionValues = @[@"location", @"search"];
    titleMode.value = @"location";
    __weak typeof(self) weakSelf = self;
    titleMode.textChangeBlock = ^(PPFormFieldConfig *config, NSString *value) {
        (void)config; (void)value;
        weakSelf.isDirty = YES;
        [weakSelf pp_updateNavigationItems];
    };

    [self.globalFormView setFields:@[
        titleMode,
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldNovaFloating titleKey:@"HomeControl_NovaFloating"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldPureLens titleKey:@"HomeControl_PureLens"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldBackgroundGlows titleKey:@"HomeControl_BackgroundGlows"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldUsedAccessories titleKey:@"HomeControl_UsedAccessories"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldReusableVideo titleKey:@"HomeControl_ReusableVideo"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldUltraCare titleKey:@"HomeControl_UltraCare"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldLegacyBar titleKey:@"HomeControl_LegacyBar"],
        [self pp_toggleFieldWithIdentifier:PPHomeControlFieldUniversalCells titleKey:@"HomeControl_UniversalCells"]
    ]];
    [self.globalFormView setValues:[self pp_defaultGlobalValues]];
    [stack addArrangedSubview:self.globalFormView];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:18.0],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-18.0],

        [settingsHeader.heightAnchor constraintGreaterThanOrEqualToConstant:42.0],
        [settingsTitle.leadingAnchor constraintEqualToAnchor:settingsHeader.leadingAnchor],
        [settingsTitle.trailingAnchor constraintLessThanOrEqualToAnchor:settingsToggle.leadingAnchor constant:-12.0],
        [settingsTitle.centerYAnchor constraintEqualToAnchor:settingsHeader.centerYAnchor],
        [settingsToggle.trailingAnchor constraintEqualToAnchor:settingsHeader.trailingAnchor],
        [settingsToggle.centerYAnchor constraintEqualToAnchor:settingsHeader.centerYAnchor],
        [settingsToggle.widthAnchor constraintGreaterThanOrEqualToConstant:42.0],
        [settingsToggle.heightAnchor constraintGreaterThanOrEqualToConstant:42.0],

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
    [self pp_updateGlobalSettingsAppearance];
    [self pp_updateHeroCount];
    [self pp_sizeHeaderToFit];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer || self.isSizingHeader) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;

    self.isSizingHeader = YES;

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
    self.isSizingHeader = NO;
}

- (NSArray<PPHomeSectionState *> *)pp_defaultSectionStates {
    NSMutableArray<PPHomeSectionState *> *states = [NSMutableArray arrayWithCapacity:self.catalog.count];
    for (PPHomeSectionMeta *meta in self.catalog) {
        PPHomeSectionState *state = [PPHomeSectionState new];
        state.sectionID = meta.sectionID;
        state.type = meta.type;
        state.visible = meta.defaultVisible;
        [states addObject:state];
    }
    return states.copy;
}

- (NSArray<PPHomeSectionState *> *)pp_copySections:(NSArray<PPHomeSectionState *> *)sections {
    NSMutableArray<PPHomeSectionState *> *copies = [NSMutableArray arrayWithCapacity:sections.count];
    for (PPHomeSectionState *source in sections ?: @[]) {
        PPHomeSectionState *copy = [PPHomeSectionState new];
        copy.sectionID = source.sectionID;
        copy.type = source.type;
        copy.visible = source.visible;
        [copies addObject:copy];
    }
    return copies.copy;
}

- (NSDictionary<NSString *, NSString *> *)pp_defaultGlobalValues {
    return @{
        PPHomeControlFieldTitleMode: @"location",
        PPHomeControlFieldNovaFloating: @"1",
        PPHomeControlFieldPureLens: @"1",
        PPHomeControlFieldBackgroundGlows: @"1",
        PPHomeControlFieldUsedAccessories: @"0",
        PPHomeControlFieldReusableVideo: @"1",
        PPHomeControlFieldUltraCare: @"1",
        PPHomeControlFieldLegacyBar: @"0",
        PPHomeControlFieldUniversalCells: @"1"
    };
}

- (NSArray<PPHomeSectionState *> *)pp_filteredSections {
    NSString *needle = [self.filterText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (needle.length == 0) return self.sections.copy ?: @[];

    NSMutableArray<PPHomeSectionState *> *filtered = [NSMutableArray array];
    for (PPHomeSectionState *state in self.sections) {
        PPHomeSectionMeta *meta = [self metaForID:state.sectionID];
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@", state.type ?: @"", meta.labelEn ?: @"", meta.labelAr ?: @""];
        if ([haystack localizedCaseInsensitiveContainsString:needle]) {
            [filtered addObject:state];
        }
    }
    return filtered.copy;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.filterText = searchController.searchBar.text ?: @"";
    [self.tableView reloadData];
}

- (void)toggleGlobalSettings {
    self.globalSettingsExpanded = !self.globalSettingsExpanded;
    [self pp_updateGlobalSettingsAppearance];
}

- (void)pp_updateNavigationItems {
    if (!self.navigationItem) return;

    UIBarButtonItem *reload = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadConfig)];
    reload.accessibilityLabel = kLang(@"HomeControl_Reload");
    reload.enabled = !self.isLoading && !self.isSaving;

    UIBarButtonItem *defaults = [[UIBarButtonItem alloc] initWithTitle:kLang(@"HomeControl_Defaults") style:UIBarButtonItemStylePlain target:self action:@selector(resetToDefaults)];
    defaults.accessibilityLabel = kLang(@"HomeControl_Defaults");
    defaults.enabled = !self.isLoading && !self.isSaving;

    NSMutableArray<UIBarButtonItem *> *leftItems = [NSMutableArray arrayWithObjects:reload, defaults, nil];
    if (self.isDirty) {
        UIBarButtonItem *revert = [[UIBarButtonItem alloc] initWithTitle:kLang(@"HomeControl_Revert") style:UIBarButtonItemStylePlain target:self action:@selector(revertChanges)];
        revert.accessibilityLabel = kLang(@"HomeControl_Revert");
        revert.enabled = !self.isLoading && !self.isSaving;
        [leftItems addObject:revert];
    }
    self.navigationItem.leftBarButtonItems = leftItems;
    [self pp_updateSaveButton];
    PPCommandCenterNavigationItemsDidChange(self);
    [[NSNotificationCenter defaultCenter] postNotificationName:PPHomeControlNavigationItemsDidChangeNotification
                                                        object:self];
}

- (void)pp_updateGlobalSettingsAppearance {
    if (!self.globalFormView || !self.globalSettingsToggleButton) return;
    self.globalFormView.hidden = !self.globalSettingsExpanded;
    NSString *imageName = self.globalSettingsExpanded ? @"chevron.up" : @"chevron.down";
    [self.globalSettingsToggleButton setImage:[UIImage systemImageNamed:imageName] forState:UIControlStateNormal];
    self.globalSettingsToggleButton.accessibilityValue = self.globalSettingsExpanded
        ? kLang(@"HomeControl_Collapse")
        : kLang(@"HomeControl_Expand");
    [self pp_sizeHeaderToFit];
}

- (void)pp_buildPreviewFooter {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    footer.backgroundColor = UIColor.clearColor;
    footer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = kLang(@"HomeControl_LivePreview");
    title.font = [Styling fontBold:20];
    title.textColor = PPHomeControlInkColor();
    title.textAlignment = [Language alignmentForCurrentLanguage];
    title.adjustsFontForContentSizeCategory = YES;
    [footer addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = kLang(@"HomeControl_LivePreview_Subtitle");
    subtitle.font = [Styling fontRegular:13];
    subtitle.textColor = PPHomeControlSubInkColor();
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.numberOfLines = 0;
    subtitle.adjustsFontForContentSizeCategory = YES;
    [footer addSubview:subtitle];

    UIView *previewCard = [UIView new];
    previewCard.translatesAutoresizingMaskIntoConstraints = NO;
    previewCard.backgroundColor = PPHomeControlSurfaceColor();
    PPHomeControlApplyCardChrome(previewCard, 22.0);
    [footer addSubview:previewCard];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.alignment = UIStackViewAlignmentFill;
    [previewCard addSubview:stack];
    self.previewStackView = stack;
    self.previewFooterView = footer;

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:footer.topAnchor constant:20.0],
        [title.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:22.0],
        [title.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-22.0],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [previewCard.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:12.0],
        [previewCard.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20.0],
        [previewCard.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20.0],
        [previewCard.bottomAnchor constraintEqualToAnchor:footer.bottomAnchor constant:-20.0],

        [stack.topAnchor constraintEqualToAnchor:previewCard.topAnchor constant:14.0],
        [stack.leadingAnchor constraintEqualToAnchor:previewCard.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:previewCard.trailingAnchor constant:-14.0],
        [stack.bottomAnchor constraintEqualToAnchor:previewCard.bottomAnchor constant:-14.0]
    ]];

    self.tableView.tableFooterView = footer;
    [self pp_updatePreview];
}

- (void)pp_updatePreview {
    if (!self.previewStackView) return;
    for (UIView *view in self.previewStackView.arrangedSubviews.copy) {
        [self.previewStackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSMutableArray<PPHomeSectionState *> *visibleStates = [NSMutableArray array];
    for (PPHomeSectionState *state in self.sections) {
        if (state.visible) [visibleStates addObject:state];
    }
    if (visibleStates.count == 0) {
        UILabel *empty = [UILabel new];
        empty.font = [Styling fontMedium:14];
        empty.textColor = PPHomeControlSubInkColor();
        empty.text = kLang(@"HomeControl_NoVisibleSections");
        empty.textAlignment = [Language alignmentForCurrentLanguage];
        empty.numberOfLines = 0;
        empty.adjustsFontForContentSizeCategory = YES;
        [self.previewStackView addArrangedSubview:empty];
    } else {
        NSInteger index = 0;
        BOOL isArabic = [[Language currentLanguageCode] isEqualToString:@"ar"];
        for (PPHomeSectionState *state in visibleStates) {
            index += 1;
            PPHomeSectionMeta *meta = [self metaForID:state.sectionID];
            UIView *row = [UIView new];
            row.translatesAutoresizingMaskIntoConstraints = NO;
            row.isAccessibilityElement = YES;
            row.accessibilityTraits = UIAccessibilityTraitStaticText;
            row.backgroundColor = [PPHomeControlAccentColor() colorWithAlphaComponent:0.055];
            row.layer.cornerRadius = 12.0;
            if (@available(iOS 13.0, *)) row.layer.cornerCurve = kCACornerCurveContinuous;

            UILabel *number = [UILabel new];
            number.translatesAutoresizingMaskIntoConstraints = NO;
            number.text = [NSString stringWithFormat:@"%ld", (long)index];
            number.font = [Styling fontBold:12];
            number.textColor = PPHomeControlAccentColor();
            number.textAlignment = NSTextAlignmentCenter;
            number.backgroundColor = [PPHomeControlAccentColor() colorWithAlphaComponent:0.12];
            number.layer.cornerRadius = 10.0;
            number.layer.masksToBounds = YES;
            [row addSubview:number];

            UILabel *label = [UILabel new];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.text = isArabic ? meta.labelAr : meta.labelEn;
            label.font = [Styling fontMedium:14];
            label.textColor = PPHomeControlInkColor();
            label.textAlignment = [Language alignmentForCurrentLanguage];
            label.numberOfLines = 2;
            label.adjustsFontForContentSizeCategory = YES;
            [row addSubview:label];
            row.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", [NSString stringWithFormat:kLang(@"HomeControl_PreviewIndex_Format"), @(index)], label.text ?: @""];

            [NSLayoutConstraint activateConstraints:@[
                [row.heightAnchor constraintGreaterThanOrEqualToConstant:40.0],
                [number.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10.0],
                [number.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
                [number.widthAnchor constraintEqualToConstant:28.0],
                [number.heightAnchor constraintEqualToConstant:28.0],
                [label.leadingAnchor constraintEqualToAnchor:number.trailingAnchor constant:10.0],
                [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12.0],
                [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:8.0],
                [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8.0]
            ]];
            [self.previewStackView addArrangedSubview:row];
        }
    }

    [self.previewFooterView setNeedsLayout];
    [self.previewFooterView layoutIfNeeded];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width > 0.0) {
        CGRect frame = self.previewFooterView.frame;
        frame.size.width = width;
        self.previewFooterView.frame = frame;
        CGFloat height = [self.previewFooterView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                                withHorizontalFittingPriority:UILayoutPriorityRequired
                                                      verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
        frame.size.height = MAX(1.0, ceil(height));
        self.previewFooterView.frame = frame;
        self.tableView.tableFooterView = self.previewFooterView;
    }
}

- (void)pp_updateInsets {
    CGFloat tabHeight = self.tabBarController ? CGRectGetHeight(self.tabBarController.tabBar.bounds) : 0.0;
    CGFloat bottom = MAX(28.0, tabHeight + 34.0);
    UIEdgeInsets inset = self.tableView.contentInset;
    if (fabs(inset.bottom - bottom) > 0.5) {
        inset.bottom = bottom;
        self.tableView.contentInset = inset;
        self.tableView.scrollIndicatorInsets = inset;
    }
}

- (void)loadConfig {
    self.isLoading = YES;
    [self.tableView reloadData];
    [self pp_updateNavigationItems];

    __weak typeof(self) weakSelf = self;
    [self.configRef getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [PPAlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                [weakSelf.tableView reloadData];
                [weakSelf pp_updateNavigationItems];
                return;
            }
            [weakSelf buildSectionsFromSnapshot:snapshot];
            [weakSelf pp_applyGlobalValuesFromSnapshot:snapshot];
            if (!snapshot.exists) {
                [PPAlertHelper showAlertIn:weakSelf title:kLang(@"HomeControl_DefaultLoaded_Title") subtitle:kLang(@"HomeControl_DefaultLoaded_Message")];
            }
            weakSelf.isDirty = NO;
            weakSelf.savedSections = [weakSelf pp_copySections:weakSelf.sections];
            weakSelf.savedGlobalValues = [[weakSelf.globalFormView values] copy];
            [weakSelf pp_updateHeroCount];
            [weakSelf pp_updateNavigationItems];
            [weakSelf pp_updatePreview];
            [weakSelf.tableView reloadData];
            [weakSelf pp_sizeHeaderToFit];
        });
    }];
}

- (PPHomeSectionMeta *)metaForRawValue:(id)rawValue {
    NSInteger numericID = NSNotFound;
    if ([rawValue isKindOfClass:NSNumber.class]) {
        numericID = [(NSNumber *)rawValue integerValue];
    } else if ([rawValue isKindOfClass:NSString.class]) {
        NSString *trimmed = [(NSString *)rawValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([trimmed rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound && trimmed.length > 0) {
            numericID = trimmed.integerValue;
        } else if (trimmed.length > 0) {
            for (PPHomeSectionMeta *meta in self.catalog) {
                if ([meta.type isEqualToString:trimmed]) return meta;
            }
        }
    }
    return numericID != NSNotFound ? [self metaForID:(PPHomeSectionID)numericID] : nil;
}

- (void)buildSectionsFromSnapshot:(FIRDocumentSnapshot *)snapshot {
    self.sections = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seenIDs = [NSMutableSet set];
    BOOL hasPremiumCareSection = NO;

    if (snapshot.exists) {
        NSArray *rawSections = snapshot[@"sections"];
        if ([rawSections isKindOfClass:NSArray.class]) {
            for (id rawValue in rawSections) {
                NSDictionary *raw = [rawValue isKindOfClass:NSDictionary.class] ? rawValue : nil;
                if (![raw isKindOfClass:NSDictionary.class]) continue;
                PPHomeSectionMeta *meta = [self metaForRawValue:raw[@"id"]];
                if (!meta) meta = [self metaForRawValue:raw[@"type"]];
                if (!meta) continue;
                if ([seenIDs containsObject:@(meta.sectionID)]) continue;
                [seenIDs addObject:@(meta.sectionID)];
                if (meta.sectionID == PPHomeSectionPremiumCare) hasPremiumCareSection = YES;

                PPHomeSectionState *state = [PPHomeSectionState new];
                state.sectionID = meta.sectionID;
                id rawVisible = raw[@"visible"];
                state.visible = [rawVisible respondsToSelector:@selector(boolValue)] ? [rawVisible boolValue] : meta.defaultVisible;
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

    // Preserve the legacy mirror when older documents do not yet contain a
    // canonical PremiumCare section row, matching the Console loader.
    if (!hasPremiumCareSection && snapshot.exists) {
        id legacyVisible = snapshot[PPHomeControlFieldPremiumCareVisible];
        if ([legacyVisible respondsToSelector:@selector(boolValue)]) {
            for (PPHomeSectionState *state in self.sections) {
                if (state.sectionID == PPHomeSectionPremiumCare) {
                    state.visible = [legacyVisible boolValue];
                    break;
                }
            }
        }
    }
}

- (void)pp_applyGlobalValuesFromSnapshot:(FIRDocumentSnapshot *)snapshot {
    NSString *mode = @"location";
    id rawMode = snapshot.exists ? snapshot[@"titleViewMode"] : nil;
    if ([rawMode isKindOfClass:NSString.class] && ([rawMode isEqualToString:@"location"] || [rawMode isEqualToString:@"search"])) {
        mode = rawMode;
    }

    BOOL videoFallback = YES;
    if (snapshot.exists && snapshot[PPHomeControlFieldReusableVideo] == nil) {
        videoFallback = [PPHomeControlBoolString(snapshot, PPHomeControlFieldReusableVideoLegacy, YES) boolValue];
    } else {
        videoFallback = [PPHomeControlBoolString(snapshot, PPHomeControlFieldReusableVideo, YES) boolValue];
    }

    [self.globalFormView setValues:@{
        PPHomeControlFieldTitleMode: mode,
        PPHomeControlFieldNovaFloating: PPHomeControlBoolString(snapshot, PPHomeControlFieldNovaFloating, YES),
        PPHomeControlFieldPureLens: PPHomeControlBoolString(snapshot, PPHomeControlFieldPureLens, YES),
        PPHomeControlFieldBackgroundGlows: PPHomeControlBoolString(snapshot, PPHomeControlFieldBackgroundGlows, YES),
        PPHomeControlFieldUsedAccessories: PPHomeControlBoolString(snapshot, PPHomeControlFieldUsedAccessories, NO),
        PPHomeControlFieldReusableVideo: videoFallback ? @"1" : @"0",
        PPHomeControlFieldUltraCare: PPHomeControlBoolString(snapshot, PPHomeControlFieldUltraCare, YES),
        PPHomeControlFieldLegacyBar: PPHomeControlBoolString(snapshot, PPHomeControlFieldLegacyBar, NO),
        PPHomeControlFieldUniversalCells: PPHomeControlBoolString(snapshot, PPHomeControlFieldUniversalCells, YES)
    }];
}

- (PPHomeSectionMeta *)metaForID:(PPHomeSectionID)sid {
    for (PPHomeSectionMeta *m in self.catalog) {
        if (m.sectionID == sid) return m;
    }
    return nil;
}

- (void)didTapSave {
    if (self.isSaving || self.isLoading) return;

    NSArray<PPHomeSectionState *> *sectionsToSave = [self pp_copySections:self.sections];
    if (sectionsToSave.count == 0) {
        [PPAlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"HomeControl_NoValidSections")];
        return;
    }

    NSInteger visibleCount = 0;
    NSInteger criticalCount = 0;
    NSInteger hiddenCriticalCount = 0;
    for (PPHomeSectionState *state in sectionsToSave) {
        if (state.visible) visibleCount += 1;
        PPHomeSectionMeta *meta = [self metaForID:state.sectionID];
        if (meta.critical) {
            criticalCount += 1;
            if (!state.visible) hiddenCriticalCount += 1;
        }
    }

    NSString *title = nil;
    NSString *message = nil;
    if (visibleCount == 0) {
        title = kLang(@"HomeControl_AllSectionsHidden_Title");
        message = kLang(@"HomeControl_AllSectionsHidden_Message");
    } else if (criticalCount > 0 && hiddenCriticalCount == criticalCount) {
        title = kLang(@"HomeControl_CoreSectionsHidden_Title");
        message = kLang(@"HomeControl_CoreSectionsHidden_Message");
    }

    if (title.length > 0 && message.length > 0) {
        __weak typeof(self) weakSelf = self;
        [PPAlertHelper showConfirmationIn:self title:title subtitle:message confirmButton:kLang(@"HomeControl_Continue") cancelButton:kLang(@"HomeControl_Cancel") icon:nil confirmBlock:^(NSString * _Nullable text, BOOL didConfirm) {
            if (didConfirm) {
                [weakSelf pp_commitSaveWithSections:sectionsToSave];
            }
        } cancelBlock:nil];
        return;
    }

    [self pp_commitSaveWithSections:sectionsToSave];
}

- (void)pp_commitSaveWithSections:(NSArray<PPHomeSectionState *> *)sections {
    if (self.isSaving || sections.count == 0) return;

    self.isSaving = YES;
    [self pp_updateNavigationItems];

    NSMutableArray *sectionsPayload = [NSMutableArray arrayWithCapacity:sections.count];
    for (PPHomeSectionState *state in sections) {
        [sectionsPayload addObject:@{
            @"id": @(state.sectionID),
            @"type": state.type ?: @"",
            @"visible": @(state.visible)
        }];
    }

    NSDictionary<NSString *, NSString *> *formValues = [self.globalFormView values];
    BOOL premiumCareVisible = YES;
    for (PPHomeSectionState *state in sections) {
        if (state.sectionID == PPHomeSectionPremiumCare) {
            premiumCareVisible = state.visible;
            break;
        }
    }

    BOOL reusableVideoEnabled = [formValues[PPHomeControlFieldReusableVideo] boolValue];
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"sections"] = sectionsPayload;
    payload[PPHomeControlFieldTitleMode] = formValues[PPHomeControlFieldTitleMode].length ? formValues[PPHomeControlFieldTitleMode] : @"location";
    payload[PPHomeControlFieldPremiumCareVisible] = @(premiumCareVisible);
    payload[PPHomeControlFieldNovaFloating] = @([formValues[PPHomeControlFieldNovaFloating] boolValue]);
    payload[PPHomeControlFieldBackgroundGlows] = @([formValues[PPHomeControlFieldBackgroundGlows] boolValue]);
    payload[PPHomeControlFieldPureLens] = @([formValues[PPHomeControlFieldPureLens] boolValue]);
    payload[PPHomeControlFieldUsedAccessories] = @([formValues[PPHomeControlFieldUsedAccessories] boolValue]);
    payload[PPHomeControlFieldReusableVideo] = @(reusableVideoEnabled);
    // Keep the legacy spelling in sync for older iOS consumers.
    payload[PPHomeControlFieldReusableVideoLegacy] = @(reusableVideoEnabled);
    payload[PPHomeControlFieldUltraCare] = @([formValues[PPHomeControlFieldUltraCare] boolValue]);
    payload[PPHomeControlFieldLegacyBar] = @([formValues[PPHomeControlFieldLegacyBar] boolValue]);
    payload[PPHomeControlFieldUniversalCells] = @([formValues[PPHomeControlFieldUniversalCells] boolValue]);
    payload[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];

    __weak typeof(self) weakSelf = self;
    [self.configRef setData:payload merge:YES completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isSaving = NO;
            if (error) {
                [weakSelf pp_updateNavigationItems];
                [PPAlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                weakSelf.isDirty = NO;
                weakSelf.savedSections = [weakSelf pp_copySections:sections];
                weakSelf.savedGlobalValues = [[weakSelf.globalFormView values] copy];
                [weakSelf pp_updateHeroCount];
                [weakSelf pp_updateNavigationItems];
                [weakSelf pp_updatePreview];
                [PPFunc pp_playSuccessEffect];
                [PPAlertHelper showAlertIn:weakSelf title:kLang(@"Success_Title") subtitle:kLang(@"HomeControl_Saved")];
            }
        });
    }];
}

- (void)resetToDefaults {
    if (self.isLoading || self.isSaving) return;
    self.sections = [[self pp_defaultSectionStates] mutableCopy];
    [self.globalFormView setValues:[self pp_defaultGlobalValues]];
    self.isDirty = YES;
    [self pp_updateHeroCount];
    [self pp_updatePreview];
    [self.tableView reloadData];
    [self pp_sizeHeaderToFit];
    [self pp_updateNavigationItems];
}

- (void)revertChanges {
    if (self.isLoading || self.isSaving || !self.isDirty) return;
    NSArray<PPHomeSectionState *> *savedSections = self.savedSections.count ? self.savedSections : [self pp_defaultSectionStates];
    NSDictionary<NSString *, NSString *> *savedValues = self.savedGlobalValues.count ? self.savedGlobalValues : [self pp_defaultGlobalValues];
    self.sections = [[self pp_copySections:savedSections] mutableCopy];
    [self.globalFormView setValues:savedValues];
    self.isDirty = NO;
    [self pp_updateHeroCount];
    [self pp_updatePreview];
    [self.tableView reloadData];
    [self pp_sizeHeaderToFit];
    [self pp_updateNavigationItems];
}

- (void)pp_updateSaveButton {
    self.navigationItem.rightBarButtonItem.enabled = !self.isSaving && !self.isLoading;
    self.navigationItem.rightBarButtonItem.title = (self.isSaving || self.isLoading) ? kLang(@"Loading") : kLang(@"Save");
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
    NSArray<PPHomeSectionState *> *filteredSections = [self pp_filteredSections];
    return MAX(filteredSections.count, 1);
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
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.isAccessibilityElement = YES;
    cell.accessibilityLabel = text;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.sections.count == 0) {
        return [self pp_stateCellWithText:self.isLoading ? kLang(@"Loading") : kLang(@"HomeControl_EmptySections")];
    }

    NSArray<PPHomeSectionState *> *filteredSections = [self pp_filteredSections];
    if (filteredSections.count == 0) {
        return [self pp_stateCellWithText:kLang(@"HomeControl_NoMatchingSections")];
    }

    PPHomeSectionState *state = filteredSections[indexPath.row];
    PPHomeSectionMeta *meta = [self metaForID:state.sectionID];
    PPHomeControlSectionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PPHomeControlSectionCell" forIndexPath:indexPath];
    [cell configureWithMeta:meta visible:state.visible];
    cell.showsReorderControl = YES;

    __weak typeof(self) weakSelf = self;
    cell.visibilityChanged = ^(BOOL visible) {
        state.visible = visible;
        weakSelf.isDirty = YES;
        [weakSelf pp_updateHeroCount];
        [weakSelf pp_updatePreview];
        [weakSelf.tableView reloadData];
        [weakSelf pp_updateNavigationItems];
    };
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return !self.isLoading && [self pp_filteredSections].count > 1;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSArray<PPHomeSectionState *> *filteredSections = [self pp_filteredSections];
    if (sourceIndexPath.row >= filteredSections.count || destinationIndexPath.row >= filteredSections.count) return;

    PPHomeSectionState *movingState = filteredSections[sourceIndexPath.row];
    PPHomeSectionState *targetState = filteredSections[destinationIndexPath.row];
    if (movingState == targetState) return;

    NSUInteger sourceIndex = [self.sections indexOfObjectIdenticalTo:movingState];
    NSUInteger targetIndex = [self.sections indexOfObjectIdenticalTo:targetState];
    if (sourceIndex == NSNotFound || targetIndex == NSNotFound) return;

    [self.sections removeObjectAtIndex:sourceIndex];
    targetIndex = [self.sections indexOfObjectIdenticalTo:targetState];
    if (targetIndex == NSNotFound) return;

    NSUInteger insertionIndex = sourceIndexPath.row < destinationIndexPath.row ? targetIndex + 1 : targetIndex;
    insertionIndex = MIN(insertionIndex, self.sections.count);
    [self.sections insertObject:movingState atIndex:insertionIndex];

    self.isDirty = YES;
    [self pp_updateHeroCount];
    [self pp_updatePreview];
    [self.tableView reloadData];
    [self pp_updateNavigationItems];
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
