//
//  AnimalKindsClass.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "subSubKindModel.h"
#import "XLFormOptionsObject.h"

@class FIRDocumentSnapshot;
@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN


@interface SubKindModel : NSObject<XLFormOptionObject>

@property (nonatomic, strong) _Nullable id<FIRListenerRegistration> subSubKindsListener;


@property (nonatomic, assign) NSInteger ID;
@property (nonatomic, assign) NSInteger MainKindID;

@property (nonatomic, copy) NSString *SubKindNameAr;
@property (nonatomic, copy) NSString *SubKindNameEn;

@property (nonatomic, strong) NSString *SubKindImageName;

/** Local icon name (fallback / bundled) */
@property (nonatomic, copy) NSString *subKindIcon;

/** Remote icon url */
@property (nonatomic, copy) NSString *subKindIconUrl;

/** Cached resolved image */
@property (nonatomic, strong, nullable) UIImage *cachedIconImage;
@property (nonatomic, copy) NSString *subKindIconBlurHash;


- (void)loadSubKindIconWithCompletion:(void(^)(UIImage * _Nullable image))completion;


@property (nonatomic) NSInteger have_subSub;
@property (nonatomic) NSInteger have_items;
@property (nonatomic) NSInteger adultHood;
@property (nonatomic, strong) NSMutableArray<subSubKindModel *> *subSubKindArray;
- (NSDictionary *)toDict;
- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot;
- (instancetype)initWithDict:(NSDictionary *)dict;
@property (nonatomic, strong) NSString *SubKindName;
+(NSString*)getSubKindName:(NSInteger)subKindID subKindsArrayLocal:(NSArray<SubKindModel*> *)subKindsArrayLocal;
+(NSInteger)getSubKindID:(NSString *)subKindName subKindsArrayLocal:(NSArray<SubKindModel*> *)subKindsArrayLocal;
+ (void)addSubKind:(NSDictionary *)subKind
     toMainKindID:(NSString *)mainID
        completion:(void(^)(NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
