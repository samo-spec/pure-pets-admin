//
//  UITextField+PPEnglishNumberKeyboard.m
//  PurePetsAdmin
//
//  Created for PurePets Admin Sovereign Catalog Editors.
//  Enforces English number keyboard layout for numeric and decimal input fields.
//

#import "UITextField+PPEnglishNumberKeyboard.h"
#import <objc/runtime.h>

@implementation UITextField (PPEnglishNumberKeyboard)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [UITextField class];
        Method origMethod = class_getInstanceMethod(cls, @selector(textInputMode));
        Method swzMethod = class_getInstanceMethod(cls, @selector(pp_textInputMode));
        if (origMethod && swzMethod) {
            method_exchangeImplementations(origMethod, swzMethod);
        }
    });
}

- (UITextInputMode *)pp_textInputMode {
    UIKeyboardType type = self.keyboardType;
    if (type == UIKeyboardTypeDecimalPad ||
        type == UIKeyboardTypeNumberPad ||
        type == UIKeyboardTypeASCIICapableNumberPad) {
        
        for (UITextInputMode *mode in [UITextInputMode activeInputModes]) {
            NSString *lang = mode.primaryLanguage;
            if ([lang hasPrefix:@"en"]) {
                return mode;
            }
        }
    }
    return [self pp_textInputMode];
}

@end
