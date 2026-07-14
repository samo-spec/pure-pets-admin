//
//  AnimalKindsClass.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "SubKindModel.h"

@class FIRDocumentSnapshot;
@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@interface MainKindsModel : NSObject<XLFormOptionObject>
@property (nonatomic, strong) NSArray<UIColor *> *cachedGradientColors;

@property (nonatomic) BOOL didSeedSubKinds;
@property (nonatomic) NSInteger ID;
@property (nonatomic) NSInteger sortingKey;
@property (nonatomic, strong) NSString *documentID;
@property (nonatomic, strong) NSString *KindNameAr;
@property (nonatomic, strong) NSString *KindNameEn;
@property (nonatomic, strong) NSString *KindImageNamed;
@property (nonatomic, strong) NSMutableArray<SubKindModel *> *SubKindsArray;
@property (nonatomic, strong) NSString *KindName;
- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot;
- (instancetype)initWithId:(NSString *)mainKindID dictionary:(NSDictionary *)dictionary;
@property (nonatomic, strong, nullable) NSString *KindImageUrl;
@property (nonatomic, strong) NSString *KindIconName;
@property (nonatomic, strong, nullable) NSString *PetColor;
@property (nonatomic, strong) UIImage *KindImageFile;
@property (nonatomic, assign) float LightenAmount;
@property (nonatomic, assign) float professionalAngle;
@property (nonatomic, strong) _Nullable id<FIRListenerRegistration> subKindsListener;

+ (NSString *)kindNameForID:(NSInteger)kindID inArray:(NSArray<MainKindsModel *> *)kindsArray;
+ (NSString *)kindNameForID:(NSInteger)kindID ;
+ (MainKindsModel *)mainKindClassForID:(NSInteger)kindID inArray:(NSArray<MainKindsModel *> *)kindsArray;
- (void)addSubKind:(SubKindModel *)subKind;
- (NSDictionary *)toFirestoreDictionary;  // Helper to convert model to Firestore data
- (SubKindModel *)subKindForID:(NSInteger)subID;
+ (MainKindsModel *)mainKindModelForID:(NSInteger)kindID;
@property (nonatomic, assign) BOOL is_visible_in_user_app;
@property (nonatomic, strong) UIImage *image;
//LightenAmount:(float)LightenAmount IconName:(NSString *)iconName
- (instancetype)initWithDict:(NSDictionary *)data ;
+ (MainKindsModel *)allKind;
-(UIColor *)kindColor;
@end

NS_ASSUME_NONNULL_END
