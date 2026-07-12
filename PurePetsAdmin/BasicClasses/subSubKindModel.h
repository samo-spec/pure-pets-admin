//
//  AnimalKindsClass.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "Language.h"
#import "subKindItemsModel.h"
#import "XLFormOptionsObject.h"

@class FIRDocumentSnapshot;
@protocol FIRListenerRegistration;


NS_ASSUME_NONNULL_BEGIN

@interface subSubKindModel : NSObject<XLFormOptionObject>

@property (nonatomic) NSInteger ID;
@property (nonatomic) NSInteger subKindID;
@property (nonatomic, strong) NSString *nameAr;
@property (nonatomic, strong) NSString *nameEn;
- (NSDictionary *)toDict;
@property (nonatomic, strong) NSMutableArray<subKindItemsModel *> *subKindItemsArray;
@property (nonatomic, strong) NSMutableArray *subKindItemsStringArray;
- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot;
- (instancetype)initWithDict:(NSDictionary *)dict;
@property (nonatomic, strong) _Nullable id<FIRListenerRegistration> subKindItemsListener;
@end

NS_ASSUME_NONNULL_END
