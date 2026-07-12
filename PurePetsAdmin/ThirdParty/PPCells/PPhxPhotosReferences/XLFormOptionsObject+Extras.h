//
//  XLFormOptionsObject.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


// XLFormOptionsObject+Extras.h

@interface XLFormOptionsObject (Extras)
@property (nonatomic, strong) NSDictionary *userInfo;

// XLFormOptionsObject+Extras.h
+ (instancetype)formOptionsObjectWithValue:(id)value
                                displayText:(NSString *)displayText
                                   userInfo:(NSDictionary *)userInfo;


@end
