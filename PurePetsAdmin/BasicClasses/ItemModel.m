//
//  ItemModel.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 21/04/2025.
//

#import "ItemModel.h"

@implementation ItemModel

-(id)formValue
{
    return self;
}

- (nonnull NSString *)formDisplayText {
    return [Language languageVal] == 0 ? self.ItemNameAr : self.ItemNameEn;
}


@end
