//
//  AnimalKindsClass.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "XLFormOptionsObject.h"
#import "Language.h"

@class FIRDocumentSnapshot;

NS_ASSUME_NONNULL_BEGIN

@interface subKindItemsModel : NSObject<XLFormOptionObject>

@property (nonatomic) NSInteger ID;
@property (nonatomic) NSInteger subSubKindID;
@property (nonatomic, strong) NSString *itemNameAr;
@property (nonatomic, strong) NSString *itemNameEn;
@property (nonatomic, strong) NSString *Male;
@property (nonatomic, strong) NSString *Female;
- (NSDictionary *)toDict;
- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot;
- (instancetype)initWithDict:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END
