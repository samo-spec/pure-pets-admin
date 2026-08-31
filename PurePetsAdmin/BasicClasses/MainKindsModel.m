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
@import FirebaseAuth;
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

 
