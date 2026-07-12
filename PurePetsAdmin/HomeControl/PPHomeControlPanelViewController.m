#import "PPHomeControlPanelViewController.h"
@import FirebaseFirestore;
@import FirebaseAuth;
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "AppManager.h"

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

@interface PPHomeControlPanelViewController ()
@property (nonatomic, strong) NSMutableArray<PPHomeSectionState *> *sections;
@property (nonatomic, strong) NSArray<PPHomeSectionMeta *> *catalog;
@property (nonatomic, strong) UISwitch *novaFloatingSwitch;
@property (nonatomic, strong) UISwitch *backgroundGlowsSwitch;
@property (nonatomic, strong) UISwitch *usedAccessoriesSwitch;
@property (nonatomic, strong) UISwitch *reusableVideoSwitch;
@property (nonatomic, strong) UISwitch *ultraCareSwitch;
@property (nonatomic, strong) UISwitch *legacyBarSwitch;
@property (nonatomic, strong) UISegmentedControl *titleViewModeSegment;
@property (nonatomic, assign) BOOL isDirty;
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, strong) FIRDocumentReference *configRef;
@end

@implementation PPHomeControlPanelViewController

static NSArray<PPHomeSectionMeta *> *PPBuildHomeCatalog(void) {
    return @[
        [PPHomeSectionMetaWithValues(PPHomeSectionPremiumSearch, @"PPHomeSectionPremiumSearch", @"Premium Search Bar", @"شريط البحث المتميز", @"In-feed premium search slot.", @"موضع البحث المتميز داخل الصفحة الرئيسية.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionMarketplaceHero, @"PPHomeSectionMarketplaceHero", @"Marketplace Hero", @"بطاقة السوق الرئيسية", @"Provider marketplace hero card.", @"بطاقة السوق الرئيسية للمزودين.", NO, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionProviderCategoryNav, @"PPHomeSectionProviderCategoryNav", @"Provider Categories", @"فئات المزودين", @"Provider marketplace navigation.", @"شريط تنقل فئات المزودين.", NO, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionHero, @"PPHomeSectionHero", @"Hero Banner", @"البانر الرئيسي", @"Top welcome card.", @"بطاقة الترحيب العلوية.", YES, YES, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionPremiumCare, @"PPHomeSectionPremiumCare", @"Premium Pet Care", @"الرعاية المتميزة", @"Premium pet-care gateway.", @"بطاقة بوابة الرعاية المتميزة.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionQuickActions, @"PPHomeSectionQuickActions", @"Quick Actions", @"الإجراءات السريعة", @"Horizontal shortcuts row.", @"صف اختصارات سريعة.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionMainKinds, @"PPHomeSectionMainKinds", @"Pet Categories", @"أنواع الحيوانات", @"Pet category grid.", @"شبكة فئات الحيوانات.", YES, YES, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionCurrentOrders, @"PPHomeSectionCurrentOrders", @"Current Orders", @"الطلبات الحالية", @"Live order status.", @"حالة الطلبات المباشرة.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionAccessories, @"PPHomeSectionAccessories", @"Pet Accessories", @"إكسسوارات الحيوانات", @"Accessories grid.", @"شبكة إكسسوارات.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionSuggestions, @"PPHomeSectionSuggestions", @"Smart Suggestions", @"اقتراحات ذكية", @"Personalized suggestions.", @"اقتراحات شخصية.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionCarousel, @"PPHomeSectionCarousel", @"Promo Carousel", @"شريط العروض", @"Auto-scrolling banners.", @"بانرات ترويجية متحركة.", YES, YES, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionLastFood, @"PPHomeSectionLastFood", @"Recent Food", @"آخر الأطعمة", @"Recently added food.", @"آخر أصناف الطعام.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionAdsNearBy, @"PPHomeSectionAdsNearBy", @"Ads Nearby", @"إعلانات قريبة", @"Location-based ads.", @"إعلانات قريبة من الموقع.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionPetProfile, @"PPHomeSectionPetProfile", @"Pet Profile Card", @"بطاقة ملف الحيوان", @"Primary pet profile.", @"ملف الحيوان الرئيسي.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionNearbyServices, @"PPHomeSectionNearbyServices", @"Nearby Services", @"خدمات قريبة", @"Geo-aware providers.", @"مزودو الخدمات حسب الموقع.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionAdopt, @"PPHomeSectionAdopt", @"Adopt a Pet", @"تبني حيوان", @"Adoption CTA card.", @"بطاقة دعوة للتبني.", YES, NO, NO)],
        [PPHomeSectionMetaWithValues(PPHomeSectionBuyAgain, @"PPHomeSectionBuyAgain", @"Buy It Again", @"اشترِ مرة أخرى", @"Re-order shortcut.", @"اختصار إعادة الطلب.", YES, NO, YES)],
        [PPHomeSectionMetaWithValues(PPHomeSectionServices, @"PPHomeSectionServices", @"Professional Services", @"خدمات احترافية", @"Service shortcuts.", @"اختصارات الخدمات.", NO, NO, NO)],
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
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"Cell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"SwitchCell"];
    
    self.catalog = PPBuildHomeCatalog();
    self.configRef = [[FIRFirestore firestore] collectionWithPath:@"AppConfigCol"] documentWithPath:@"HomeConfig"];
    
    UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Save") style:UIBarButtonItemStyleDone target:self action:@selector(didTapSave)];
    self.navigationItem.rightBarButtonItem = saveBtn;
    
    [self loadConfig];
}

- (void)loadConfig {
    __weak typeof(self) weakSelf = self;
    [self.configRef getDocumentWithCompletion:^(FIRDocumentSnapshot *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                return;
            }
            [weakSelf buildSectionsFromSnapshot:snapshot];
            [weakSelf.tableView reloadData];
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
                BOOL visible = visNum ? [visNum boolValue] : YES;
                
                PPHomeSectionState *state = [PPHomeSectionState new];
                state.sectionID = sid;
                state.visible = visible;
                PPHomeSectionMeta *meta = [self metaForID:sid];
                state.type = meta.type;
                [self.sections addObject:state];
            }
        }
        
        id mode = snapshot[@"titleViewMode"];
        if ([mode isKindOfClass:NSString.class]) {
            self.titleViewModeSegment.selectedSegmentIndex = [mode isEqualToString:@"search"] ? 1 : 0;
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

- (PPHomeSectionMeta *)metaForID:(PPHomeSectionID)sid {
    for (PPHomeSectionMeta *m in self.catalog) {
        if (m.sectionID == sid) return m;
    }
    return nil;
}

- (void)didTapSave {
    if (self.isSaving) return;
    self.isSaving = YES;
    
    NSMutableArray *sectionsPayload = [NSMutableArray array];
    for (PPHomeSectionState *s in self.sections) {
        [sectionsPayload addObject:@{
            @"id": @(s.sectionID),
            @"type": s.type ?: @"",
            @"visible": @(s.visible)
        }];
    }
    
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"sections"] = sectionsPayload;
    payload[@"titleViewMode"] = self.titleViewModeSegment.selectedSegmentIndex == 1 ? @"search" : @"location";
    payload[@"novaFloatingVisible"] = @(self.novaFloatingSwitch.on);
    payload[@"backgroundGlowsFaded"] = @(self.backgroundGlowsSwitch.on);
    payload[@"AllwedUsedAccessories"] = @(self.usedAccessoriesSwitch.on);
    payload[@"PP_REUSABLE_VIDEO_MEDIA_ENABLED"] = @(self.reusableVideoSwitch.on);
    payload[@"PPULTRA_CARE_IS_ACTIVATED"] = @(self.ultraCareSwitch.on);
    payload[@"PPUSE_LEGACY_BAR"] = @(self.legacyBarSwitch.on);
    payload[@"updatedAt"] = [FIRTimestamp timestampWithDate:[NSDate date]];
    
    __weak typeof(self) weakSelf = self;
    [self.configRef setData:payload merge:YES completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isSaving = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                [PPFunc pp_playSuccessEffect];
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Success_Title") subtitle:kLang(@"HomeControl_Saved")];
            }
        });
    }];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return kLang(@"HomeControl_GlobalSettings");
    return kLang(@"HomeControl_SectionOrder");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
        cell.textLabel.text = kLang(@"HomeControl_TitleViewMode");
        cell.textLabel.font = [Styling fontMedium:16];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = self.titleViewModeSegment;
        cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        return cell;
    }
    
    PPHomeSectionState *state = self.sections[indexPath.row];
    PPHomeSectionMeta *meta = [self metaForID:state.sectionID];
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SwitchCell" forIndexPath:indexPath];
    NSString *langCode = [Language currentLanguageCode];
    BOOL isArabic = [langCode isEqualToString:@"ar"];
    cell.textLabel.text = isArabic ? meta.labelAr : meta.labelEn;
    cell.textLabel.font = [Styling fontMedium:15];
    cell.detailTextLabel.text = isArabic ? meta.descAr : meta.descEn;
    cell.detailTextLabel.font = [Styling fontRegular:12];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;
    
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = state.visible;
    sw.tag = indexPath.row;
    [sw addTarget:self action:@selector(sectionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.textLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.detailTextLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    if (meta.critical) {
        cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
        cell.imageView.tintColor = UIColor.systemYellowColor;
    } else if (meta.conditional) {
        cell.imageView.image = [UIImage systemImageNamed:@"questionmark.circle.fill"];
        cell.imageView.tintColor = UIColor.systemBlueColor;
    } else {
        cell.imageView.image = nil;
    }
    
    return cell;
}

- (void)sectionSwitchChanged:(UISwitch *)sender {
    PPHomeSectionState *state = self.sections[sender.tag];
    state.visible = sender.on;
}

@end