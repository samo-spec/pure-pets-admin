//
//  AnimalKindsClass.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "MainKindsArrayManager.h"
#import "MainKindsModel.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;

@implementation PPAccessoryCategoryModel

- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot mainKindID:(NSInteger)mainKindID {
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:snapshot.data ?: @{}];
    data[@"documentID"] = snapshot.documentID ?: @"";
    if (!data[@"id"]) data[@"id"] = snapshot.documentID ?: @"";
    return [self initWithDict:data mainKindID:mainKindID];
}

- (instancetype)initWithDict:(NSDictionary *)dict mainKindID:(NSInteger)mainKindID {
    self = [super init];
    if (self) {
        NSString *docID = [dict[@"documentID"] isKindOfClass:NSString.class] ? dict[@"documentID"] : @"";
        NSString *catID = [dict[@"id"] isKindOfClass:NSString.class] ? dict[@"id"] : nil;
        if (catID.length == 0 && [dict[@"categoryID"] isKindOfClass:NSString.class]) catID = dict[@"categoryID"];
        if (catID.length == 0) catID = docID;

        self.categoryID = catID ?: @"";
        self.documentID = docID.length ? docID : self.categoryID;
        self.nameAr = [dict[@"nameAr"] isKindOfClass:NSString.class] ? dict[@"nameAr"] : ([dict[@"name_ar"] isKindOfClass:NSString.class] ? dict[@"name_ar"] : @"");
        self.nameEn = [dict[@"nameEn"] isKindOfClass:NSString.class] ? dict[@"nameEn"] : ([dict[@"name_en"] isKindOfClass:NSString.class] ? dict[@"name_en"] : @"");
        self.mainKindID = mainKindID;
        self.sortingKey = dict[@"sortingKey"] ? [dict[@"sortingKey"] integerValue] : [dict[@"order"] integerValue];
        id enabledValue = dict[@"enabled"];
        self.enabled = enabledValue == nil ? YES : [enabledValue boolValue];
    }
    return self;
}

- (NSDictionary *)toCacheDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.categoryID ?: @"";
    dict[@"documentID"] = self.documentID ?: self.categoryID ?: @"";
    dict[@"nameAr"] = self.nameAr ?: @"";
    dict[@"nameEn"] = self.nameEn ?: @"";
    dict[@"mainKindID"] = @(self.mainKindID);
    dict[@"sortingKey"] = @(self.sortingKey);
    dict[@"enabled"] = @(self.enabled);
    return dict.copy;
}

- (NSString *)displayName {
    NSString *primary = [Language languageVal] == 0 ? self.nameEn : self.nameAr;
    NSString *fallback = [Language languageVal] == 0 ? self.nameAr : self.nameEn;
    if (primary.length) return primary;
    if (fallback.length) return fallback;
    return self.categoryID.length ? self.categoryID : (self.documentID ?: @"");
}

- (id)formValue {
    return self.categoryID ?: @"";
}

- (NSString *)formDisplayText {
    return [self displayName];
}

- (NSString *)description {
    return [self displayName];
}

@end

@implementation MainKindsModel

+ (NSString *)kindNameForID:(NSInteger)kindID inArray:(NSArray<MainKindsModel *> *)kindsArray {
    for (MainKindsModel *kind in kindsArray) {
        if (kind.ID == kindID) {
            // Return name based on device language
            return kind.KindName;
        }
    }
    return @""; // Return empty string if not found
}

+ (NSString *)kindNameForID:(NSInteger)kindID {
    for (MainKindsModel *kind in MainKindsArrayManager.shared.MainKindsArray) {
        if (kind.ID == kindID) {
            // Return name based on device language
            return kind.KindName;
        }
    }
    return @""; // Return empty string if not found
}


+ (MainKindsModel *)mainKindModelForID:(NSInteger)kindID {
    for (MainKindsModel *kind in MainKindsArrayManager.shared.MainKindsArray) {
        if (kind.ID == kindID) {
            // Return name based on device language
            return kind;
        }
    }
    return nil; // Return empty string if not found
}



+ (MainKindsModel *)mainKindClassForID:(NSInteger)kindID inArray:(NSArray<MainKindsModel *> *)kindsArray {
    for (MainKindsModel *kind in kindsArray) {
        if (kind.ID == kindID) {
            // Return name based on device language
            return kind;
        }
    }
    return nil; // Return empty string if not found
}

-(NSString *)KindName
{
    return [Language languageVal] == 0 ? self.KindNameEn : self.KindNameAr;
}
-(id)formValue
{
    return self;
}

- (nonnull NSString *)formDisplayText {
    return [Language languageVal] == 0 ? self.KindNameEn : self.KindNameAr ;
}

//[document.documentID integerValue]
- (instancetype)initWithId:(NSString *)mainKindID dictionary:(NSDictionary *)dictionary
{
    self = [super init];
    if (self) {
        
        self.documentID = dictionary[@"documentID"];
        self.ID = [mainKindID integerValue];
        self.sortingKey = [dictionary[@"sortingKey"]  integerValue];
        
        self.LightenAmount = [dictionary[@"LightenAmount"] floatValue];
        self.professionalAngle = [dictionary[@"professionalAngle"] floatValue];
        self.KindNameAr = dictionary[@"KindNameAr"];
        self.KindNameEn = dictionary[@"KindNameEn"];
        self.PetColor = dictionary[@"PetColor"];
        self.KindImageNamed = dictionary[@"KindImageNamed"];
        self.KindIconName = dictionary[@"KindIconName"];
        self.KindImageFile = [UIImage imageNamed:self.KindImageNamed];
        self.KindImageUrl = dictionary[@"KindImageUrl"];
        self.SubKindsArray = [[NSMutableArray<SubKindModel *> alloc] init];
        NSMutableDictionary *dic =dictionary[@"SubKindsArray"];
        
        for (NSDictionary *SubKind in dic) {
            // NSLog(@"subSubKind: %@", SubKind);
            SubKindModel *subKind = [[SubKindModel alloc] initWithDict:SubKind];
            [self.SubKindsArray addObject:subKind];
        }
        self.accessoryCategories = [[MainKindsModel canonicalAccessoryCategoriesForMainKindID:self.ID] mutableCopy];
        self.didSeedAccessoryCategories = YES;
    }
    return self;
}

- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot {
    self = [super init];
    if (self) {
        self.ID = [snapshot.data[@"ID"] integerValue];
        self.sortingKey = [snapshot.data[@"sortingKey"] integerValue];
        self.KindNameAr = snapshot.data[@"KindNameAr"];
        self.documentID = snapshot.documentID;
        self.KindNameEn = snapshot.data[@"KindNameEn"];
        self.PetColor = snapshot.data[@"PetColor"];
        self.KindImageNamed = snapshot.data[@"KindImageNamed"];
        self.KindImageUrl = snapshot.data[@"KindImageUrl"];
        self.KindIconName = snapshot.data[@"KindIconName"];
        self.KindImageFile = [UIImage imageNamed:self.KindImageNamed];
        //NSLog(@"[ImageLoader] KindImageUrl %@", self.KindImageUrl);
        
        // ✅ Correct type conversion
        self.LightenAmount = [snapshot.data[@"LightenAmount"] floatValue];
        self.professionalAngle = [snapshot.data[@"professionalAngle"] floatValue];
        self.is_visible_in_user_app = [snapshot.data[@"is_visible_in_user_app"] boolValue];
        if (snapshot.data[@"is_visible_in_user_app"] == nil) self.is_visible_in_user_app = YES;
        
        self.SubKindsArray = [[NSMutableArray<SubKindModel *> alloc] init];
        NSMutableDictionary *dic = snapshot.data[@"SubKindsArray"];
        for (NSDictionary *subKind in dic) {
            SubKindModel *subKindModel = [[SubKindModel alloc] initWithDict:subKind];
            [self.SubKindsArray addObject:subKindModel];
        }
        self.accessoryCategories = [[MainKindsModel canonicalAccessoryCategoriesForMainKindID:self.ID] mutableCopy];
        self.didSeedAccessoryCategories = YES;
    }
    return self;
}

- (instancetype)initWithDict:(NSDictionary *)data {
    self = [super init];
    if (self) {
        self.ID = [data[@"ID"] integerValue];
        self.sortingKey = [data[@"sortingKey"] integerValue];
        self.KindNameAr = data[@"KindNameAr"];
        self.documentID = [NSString stringWithFormat:@"%ld",[data[@"ID"] integerValue]];
        self.KindNameEn = data[@"KindNameEn"];
        self.PetColor = data[@"PetColor"];
        self.KindImageNamed = data[@"KindImageNamed"];
        self.KindIconName = data[@"KindIconName"];
        self.KindImageUrl = data[@"KindImageUrl"];
        self.KindImageFile = [UIImage imageNamed:self.KindImageNamed];
        //NSLog(@"[ImageLoader] KindImageUrl %@", self.KindImageUrl);
        
        // ✅ Correct type conversion
        self.LightenAmount = [data[@"LightenAmount"] floatValue];
        self.professionalAngle = [data[@"professionalAngle"] floatValue];
        self.is_visible_in_user_app = [data[@"is_visible_in_user_app"] boolValue];
        if (data[@"is_visible_in_user_app"] == nil) self.is_visible_in_user_app = YES;
        
        self.SubKindsArray = [[NSMutableArray<SubKindModel *> alloc] init];
        NSMutableDictionary *dic = data[@"SubKindsArray"];
        for (NSDictionary *subKind in dic) {
            SubKindModel *subKindModel = [[SubKindModel alloc] initWithDict:subKind];
            [self.SubKindsArray addObject:subKindModel];
        }
        self.accessoryCategories = [[MainKindsModel canonicalAccessoryCategoriesForMainKindID:self.ID] mutableCopy];
        self.didSeedAccessoryCategories = YES;
    }
    return self;
}

- (void)addSubKind:(SubKindModel *)subKind {
    if (!self.SubKindsArray) {
        self.SubKindsArray = [NSMutableArray array];
    }
    
    // Prevent duplicates
    for (SubKindModel *existingSubKind in self.SubKindsArray) {
        if (existingSubKind.ID == subKind.ID) {
            NSLog(@"SubKind with ID %ld already exists", (long)subKind.ID);
            return;
        }
    }
    
    subKind.MainKindID = self.ID;  // Ensure correct reference
    [self.SubKindsArray addObject:subKind];
}

// Convert MainKindsModel (including SubKindsArray) to Firestore-compatible dictionary
- (NSDictionary *)toFirestoreDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"ID"] = @(self.ID);
    dict[@"sortingKey"] = @(self.sortingKey);
    dict[@"KindNameAr"] = self.KindNameAr ?: @"";
    dict[@"KindNameEn"] = self.KindNameEn ?: @"";
    dict[@"KindImageNamed"] = self.KindImageNamed ?: @"";
    dict[@"KindIconName"] = self.KindIconName ?: @"";
    dict[@"PetColor"] = self.PetColor ?: @"";
    dict[@"documentID"] = self.documentID ?: @"";
    dict[@"KindImageUrl"] = self.KindImageUrl ?: @"";
    dict[@"LightenAmount"] = @(self.LightenAmount);
    dict[@"professionalAngle"] = @(self.professionalAngle);
    dict[@"is_visible_in_user_app"] = @(self.is_visible_in_user_app);
    
    // Convert SubKindsArray to an array of dictionaries
    NSMutableArray *subKindsData = [NSMutableArray array];
    for (SubKindModel *subKind in self.SubKindsArray) {
        [subKindsData addObject:@{
            @"ID": @(subKind.ID),
            @"MainKindID": @(subKind.MainKindID),
            @"SubKindNameAr": subKind.SubKindNameAr ?: @"",
            @"SubKindNameEn": subKind.SubKindNameEn ?: @"",
            @"subKindIconUrl": subKind.subKindIconUrl ?: @"",
            @"subKindIconBlurHash": subKind.subKindIconBlurHash ?: @"",
            @"have_subSub": @(subKind.have_subSub),
            @"have_items": @(subKind.have_items),
            @"adultHood": @(subKind.adultHood)
        }];
    }
    dict[@"SubKindsArray"] = subKindsData;
    
    return dict;
}


- (SubKindModel *)subKindForID:(NSInteger)subID {
    for (SubKindModel *sk in self.SubKindsArray) {
        if (sk.ID == subID) return sk;
    }
    return nil;
}

- (PPAccessoryCategoryModel *)accessoryCategoryForID:(NSString *)categoryID {
    if (categoryID.length == 0) return nil;
    for (PPAccessoryCategoryModel *category in self.accessoryCategories ?: @[]) {
        if ([category.categoryID isEqualToString:categoryID] || [category.documentID isEqualToString:categoryID]) {
            return category;
        }
    }
    // Check canonical fallback
    for (PPAccessoryCategoryModel *category in [MainKindsModel canonicalAccessoryCategoriesForMainKindID:self.ID]) {
        if ([category.categoryID isEqualToString:categoryID] || [category.documentID isEqualToString:categoryID]) {
            return category;
        }
    }
    return nil;
}

+ (NSArray<PPAccessoryCategoryModel *> *)canonicalAccessoryCategoriesForMainKindID:(NSInteger)mainKindID {
    static NSDictionary<NSNumber *, NSArray<NSDictionary *> *> *sCanonicalTaxonomy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sCanonicalTaxonomy = @{
            @(1): @[
                @{@"id": @"cages", @"sortingKey": @10, @"nameEn": @"Cages & Aviaries", @"nameAr": @"أقفاص وطيارات"},
                @{@"id": @"feeders", @"sortingKey": @20, @"nameEn": @"Feeders, Drinkers & Serving", @"nameAr": @"مآكل ومشارب وتغذية"},
                @{@"id": @"perches", @"sortingKey": @30, @"nameEn": @"Perches & Stands", @"nameAr": @"مجاثم وحوامل"},
                @{@"id": @"toys", @"sortingKey": @40, @"nameEn": @"Toys & Play", @"nameAr": @"ألعاب وتسلية"},
                @{@"id": @"nests", @"sortingKey": @50, @"nameEn": @"Nests, Breeding & Incubation", @"nameAr": @"أعشاش وتفريخ وحضانات"},
                @{@"id": @"clean", @"sortingKey": @60, @"nameEn": @"Care, Safety & Hand-Feeding", @"nameAr": @"عناية وأمان وتغذية يدوية"},
                @{@"id": @"general", @"sortingKey": @70, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(2): @[
                @{@"id": @"saddles", @"sortingKey": @10, @"nameEn": @"Saddles & Bridles", @"nameAr": @"سروج ولجام"},
                @{@"id": @"halters", @"sortingKey": @20, @"nameEn": @"Halters & Ropes", @"nameAr": @"رسن وحبال"},
                @{@"id": @"feeders", @"sortingKey": @30, @"nameEn": @"Feeders & Waterers", @"nameAr": @"معالف ومشارب"},
                @{@"id": @"grooming", @"sortingKey": @40, @"nameEn": @"Grooming & Brushes", @"nameAr": @"تنظيف وفرش"},
                @{@"id": @"covers", @"sortingKey": @50, @"nameEn": @"Covers & Sheets", @"nameAr": @"أغطية وجل"},
                @{@"id": @"nutrition", @"sortingKey": @60, @"nameEn": @"Nutrition & Supplements", @"nameAr": @"تغذية ومكملات"},
                @{@"id": @"general", @"sortingKey": @70, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(3): @[
                @{@"id": @"saddles", @"sortingKey": @10, @"nameEn": @"Saddles & Bridles", @"nameAr": @"سروج ولجام"},
                @{@"id": @"halters", @"sortingKey": @20, @"nameEn": @"Halters & Ropes", @"nameAr": @"رسن وحبال"},
                @{@"id": @"feeders", @"sortingKey": @30, @"nameEn": @"Feeders & Waterers", @"nameAr": @"معالف ومشارب"},
                @{@"id": @"grooming", @"sortingKey": @40, @"nameEn": @"Grooming & Brushes", @"nameAr": @"تنظيف وفرش"},
                @{@"id": @"covers", @"sortingKey": @50, @"nameEn": @"Covers & Sheets", @"nameAr": @"أغطية وجل"},
                @{@"id": @"nutrition", @"sortingKey": @60, @"nameEn": @"Nutrition & Supplements", @"nameAr": @"تغذية ومكملات"},
                @{@"id": @"general", @"sortingKey": @70, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(4): @[
                @{@"id": @"feeders", @"sortingKey": @10, @"nameEn": @"Feeders & Waterers", @"nameAr": @"معالف ومشارب"},
                @{@"id": @"grooming", @"sortingKey": @20, @"nameEn": @"Grooming & Brushes", @"nameAr": @"تنظيف وفرش"},
                @{@"id": @"covers", @"sortingKey": @30, @"nameEn": @"Covers & Sheets", @"nameAr": @"أغطية وجل"},
                @{@"id": @"nutrition", @"sortingKey": @40, @"nameEn": @"Nutrition & Supplements", @"nameAr": @"تغذية ومكملات"},
                @{@"id": @"care", @"sortingKey": @50, @"nameEn": @"Care Tools", @"nameAr": @"أدوات عناية"},
                @{@"id": @"general", @"sortingKey": @60, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(5): @[
                @{@"id": @"food_bowls", @"sortingKey": @10, @"nameEn": @"Food & Bowls", @"nameAr": @"طعام وأوعية"},
                @{@"id": @"carriers", @"sortingKey": @20, @"nameEn": @"Carriers & Cages", @"nameAr": @"حقائب تنقل وأقفاص"},
                @{@"id": @"collars", @"sortingKey": @30, @"nameEn": @"Collars & Harnesses", @"nameAr": @"أطواق وأحزمة"},
                @{@"id": @"toys", @"sortingKey": @40, @"nameEn": @"Toys & Scratchers", @"nameAr": @"ألعاب وخدش"},
                @{@"id": @"grooming", @"sortingKey": @50, @"nameEn": @"Grooming & Cleaning", @"nameAr": @"عناية ونظافة"},
                @{@"id": @"litter", @"sortingKey": @60, @"nameEn": @"Litter & Toilet Tools", @"nameAr": @"رمل وأدوات نظافة"},
                @{@"id": @"beds", @"sortingKey": @70, @"nameEn": @"Beds & Mats", @"nameAr": @"أسرة ومفارش"},
                @{@"id": @"general", @"sortingKey": @80, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(6): @[
                @{@"id": @"food_bowls", @"sortingKey": @10, @"nameEn": @"Food & Bowls", @"nameAr": @"طعام وأوعية"},
                @{@"id": @"carriers", @"sortingKey": @20, @"nameEn": @"Carriers & Cages", @"nameAr": @"حقائب تنقل وأقفاص"},
                @{@"id": @"collars", @"sortingKey": @30, @"nameEn": @"Collars, Leashes & Harnesses", @"nameAr": @"أطواق وسلاسل وأحزمة"},
                @{@"id": @"toys", @"sortingKey": @40, @"nameEn": @"Toys & Chews", @"nameAr": @"ألعاب وعضاضات"},
                @{@"id": @"grooming", @"sortingKey": @50, @"nameEn": @"Grooming & Cleaning", @"nameAr": @"عناية ونظافة"},
                @{@"id": @"beds", @"sortingKey": @60, @"nameEn": @"Beds & Mats", @"nameAr": @"أسرة ومفارش"},
                @{@"id": @"training", @"sortingKey": @70, @"nameEn": @"Training & Walking", @"nameAr": @"تدريب ومشي"},
                @{@"id": @"general", @"sortingKey": @80, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(7): @[
                @{@"id": @"aquariums", @"sortingKey": @10, @"nameEn": @"Aquariums", @"nameAr": @"أحواض"},
                @{@"id": @"filters", @"sortingKey": @20, @"nameEn": @"Filters & Pumps", @"nameAr": @"فلاتر ومضخات"},
                @{@"id": @"decorations", @"sortingKey": @30, @"nameEn": @"Decor & Substrate", @"nameAr": @"ديكور وأرضيات"},
                @{@"id": @"lighting", @"sortingKey": @40, @"nameEn": @"Lighting", @"nameAr": @"إضاءة"},
                @{@"id": @"general", @"sortingKey": @50, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(8): @[
                @{@"id": @"cages", @"sortingKey": @10, @"nameEn": @"Cages & Hutches", @"nameAr": @"أقفاص وبيوت"},
                @{@"id": @"feeders", @"sortingKey": @20, @"nameEn": @"Feeders & Waterers", @"nameAr": @"مآكل ومشارب"},
                @{@"id": @"beds", @"sortingKey": @30, @"nameEn": @"Beds & Mats", @"nameAr": @"أسرة ومفارش"},
                @{@"id": @"toys", @"sortingKey": @40, @"nameEn": @"Toys", @"nameAr": @"ألعاب"},
                @{@"id": @"grooming", @"sortingKey": @50, @"nameEn": @"Grooming & Care", @"nameAr": @"عناية ونظافة"},
                @{@"id": @"general", @"sortingKey": @60, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(9): @[
                @{@"id": @"cages", @"sortingKey": @10, @"nameEn": @"Cages & Enclosures", @"nameAr": @"أقفاص وحظائر"},
                @{@"id": @"feeders", @"sortingKey": @20, @"nameEn": @"Feeders & Waterers", @"nameAr": @"مآكل ومشارب"},
                @{@"id": @"toys", @"sortingKey": @30, @"nameEn": @"Toys & Enrichment", @"nameAr": @"ألعاب وإثراء"},
                @{@"id": @"grooming", @"sortingKey": @40, @"nameEn": @"Care & Cleaning", @"nameAr": @"عناية ونظافة"},
                @{@"id": @"general", @"sortingKey": @50, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(10): @[
                @{@"id": @"feeders", @"sortingKey": @10, @"nameEn": @"Feeders & Waterers", @"nameAr": @"معالف ومشارب"},
                @{@"id": @"grooming", @"sortingKey": @20, @"nameEn": @"Grooming & Brushes", @"nameAr": @"تنظيف وفرش"},
                @{@"id": @"covers", @"sortingKey": @30, @"nameEn": @"Covers & Sheets", @"nameAr": @"أغطية وجل"},
                @{@"id": @"nutrition", @"sortingKey": @40, @"nameEn": @"Nutrition & Supplements", @"nameAr": @"تغذية ومكملات"},
                @{@"id": @"care", @"sortingKey": @50, @"nameEn": @"Care Tools", @"nameAr": @"أدوات عناية"},
                @{@"id": @"general", @"sortingKey": @60, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(11): @[
                @{@"id": @"hoods", @"sortingKey": @10, @"nameEn": @"Hoods & Masks", @"nameAr": @"براقع وأقنعة"},
                @{@"id": @"gloves", @"sortingKey": @20, @"nameEn": @"Gloves", @"nameAr": @"دسوس"},
                @{@"id": @"stands", @"sortingKey": @30, @"nameEn": @"Stands & Perches", @"nameAr": @"حوامل ومجاثم"},
                @{@"id": @"jesses", @"sortingKey": @40, @"nameEn": @"Jesses, Leashes & Leather Gear", @"nameAr": @"سبوق ومرسل ومعدات جلدية"},
                @{@"id": @"tracking", @"sortingKey": @50, @"nameEn": @"Tracking & Telemetry", @"nameAr": @"تتبع وتليمترية"},
                @{@"id": @"general", @"sortingKey": @60, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
            @(12): @[
                @{@"id": @"cages", @"sortingKey": @10, @"nameEn": @"Cages & Aviaries", @"nameAr": @"أقفاص وطيارات"},
                @{@"id": @"feeders", @"sortingKey": @20, @"nameEn": @"Feeders, Drinkers & Serving", @"nameAr": @"مآكل ومشارب وتغذية"},
                @{@"id": @"perches", @"sortingKey": @30, @"nameEn": @"Perches & Stands", @"nameAr": @"مجاثم وحوامل"},
                @{@"id": @"toys", @"sortingKey": @40, @"nameEn": @"Toys & Play", @"nameAr": @"ألعاب وتسلية"},
                @{@"id": @"nests", @"sortingKey": @50, @"nameEn": @"Nests, Breeding & Incubation", @"nameAr": @"أعشاش وتفريخ وحضانات"},
                @{@"id": @"clean", @"sortingKey": @60, @"nameEn": @"Care & Safety", @"nameAr": @"عناية وأمان"},
                @{@"id": @"general", @"sortingKey": @70, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"},
            ],
        };
    });

    NSArray<NSDictionary *> *items = sCanonicalTaxonomy[@(mainKindID)];
    if (!items && mainKindID == 12) {
        items = sCanonicalTaxonomy[@(1)];
    }
    if (!items) {
        items = @[
            @{@"id": @"general", @"sortingKey": @10, @"nameEn": @"General Accessories", @"nameAr": @"إكسسوارات عامة"}
        ];
    }

    NSMutableArray<PPAccessoryCategoryModel *> *models = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *raw in items) {
        PPAccessoryCategoryModel *cat = [[PPAccessoryCategoryModel alloc] initWithDict:raw mainKindID:mainKindID];
        if (cat) [models addObject:cat];
    }
    return models.copy;
}

+ (MainKindsModel *)allKind
{
    MainKindsModel *model = [[MainKindsModel alloc]init];
    
    model.documentID = @"-1";
    model.ID = -1;
    model.KindNameAr = @"الكل";
    model.KindNameEn = @"all";
    model.KindImageNamed = @"square-layout";
    model.KindIconName = @"square-layout";
    model.KindImageFile = [UIImage imageNamed:@"square-layout"];
    model.SubKindsArray = [[NSMutableArray<SubKindModel *> alloc] init];
    model.accessoryCategories = [NSMutableArray array];
    model.didSeedAccessoryCategories = YES;
    return  model;
}

#pragma mark - Accent Color

- (UIColor *)accentColorForKind:(MainKindsModel *)kind
{
    if (!kind) {
        return [UIColor ppTextSecondary];
    }

    switch (kind.ID) {
        case 1: // Dogs
            return [UIColor ppQuickActionAnimals];
        case 2: // Cats
            return [UIColor ppQuickActionShopping];
        case 3: // Birds
            return [UIColor ppQuickActionServices];
        case 4: // Fish
            return [UIColor ppQuickActionCommunity];
        case 5: // Small Pets
            return [UIColor ppQuickActionAdoption];
        default:
            return [UIColor ppInfo];
    }
}


-(UIColor *)kindColor
{
    if (self.PetColor && self.PetColor.length > 0) {
        return [UIColor colorWithHexString:self.PetColor];
    }
    
    switch (self.ID) {
        case 1: return [UIColor ppQuickActionAnimals];
        case 2: return [UIColor ppQuickActionShopping];
        case 3: return [UIColor ppQuickActionServices];
        case 4: return [UIColor ppQuickActionCommunity];
        case 5: return [UIColor ppQuickActionAdoption];
        case 6: return [UIColor ppPremiumAccent];
        case 7: return [UIColor colorWithHexString:@"#0077BE"]; // Sea Blue (Fish)
        case 8: return [UIColor ppDiscount];
        case 9: return [UIColor ppPrimary];
        case 10: return [UIColor ppMineralBeige];
        case 11: return [UIColor ppQuietLilac];
        default: return [UIColor ppTextSecondary];
    }
    
}
@end

 
