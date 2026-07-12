//
//  ItemModel.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 21/04/2025.
//

#import <Foundation/Foundation.h>
#import "XLFormOptionsObject.h"
NS_ASSUME_NONNULL_BEGIN




@interface ItemModel : NSObject<XLFormOptionObject>

@property  (nonatomic , strong) NSString *ID;
@property  (nonatomic , strong) NSString *ItemNameAr;
@property  (nonatomic , strong) NSString *ItemNameEn;

@end

NS_ASSUME_NONNULL_END
