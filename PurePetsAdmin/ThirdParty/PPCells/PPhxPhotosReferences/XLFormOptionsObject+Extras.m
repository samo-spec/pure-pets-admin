//
//  XLFormOptionsObject.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


// XLFormOptionsObject+Extras.m
#import "XLFormOptionsObject+Extras.h"


@implementation XLFormOptionsObject (Extras)

- (void)setUserInfo:(NSDictionary *)userInfo {
    objc_setAssociatedObject(self, @selector(userInfo), userInfo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)userInfo {
    return objc_getAssociatedObject(self, @selector(userInfo));
}

// XLFormOptionsObject+Extras.m
+ (instancetype)formOptionsObjectWithValue:(id)value
                                displayText:(NSString *)displayText
                                   userInfo:(NSDictionary *)userInfo {
    XLFormOptionsObject *obj = [XLFormOptionsObject formOptionsObjectWithValue:value displayText:displayText];
    obj.userInfo = userInfo;
    return obj;
}

@end
