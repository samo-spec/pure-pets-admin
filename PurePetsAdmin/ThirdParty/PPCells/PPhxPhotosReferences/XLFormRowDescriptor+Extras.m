//
//  XLFormRowDescriptor.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


// XLFormRowDescriptor+Extras.m
#import <objc/runtime.h>
#import "XLFormRowDescriptor+Extras.h"

@implementation XLFormRowDescriptor (Extras)

- (void)setExtraInfo:(NSDictionary *)extraInfo {
    objc_setAssociatedObject(self, @selector(extraInfo), extraInfo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)extraInfo {
    return objc_getAssociatedObject(self, @selector(extraInfo));
}

@end
