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
        SEL origSel = @selector(textInputMode);
        SEL swzSel = @selector(pp_textInputMode);

        Method origMethod = class_getInstanceMethod(cls, origSel);
        Method swzMethod = class_getInstanceMethod(cls, swzSel);
        if (!origMethod || !swzMethod) return;

        // Use class_addMethod so we attach textInputMode to UITextField specifically,
        // without inadvertently mutating UIResponder's method implementation table.
        BOOL didAddMethod = class_addMethod(cls,
                                            origSel,
                                            method_getImplementation(swzMethod),
                                            method_getTypeEncoding(swzMethod));
        if (didAddMethod) {
            class_replaceMethod(cls,
                                swzSel,
                                method_getImplementation(origMethod),
                                method_getTypeEncoding(origMethod));
        } else {
            method_exchangeImplementations(origMethod, swzMethod);
        }
    });
}

- (UITextInputMode *)pp_textInputMode {
    // Guard 1: Ensure the receiver is strictly an instance of UITextField.
    // Prevents any non-UITextField responders (such as SwiftUI UIKitPlatformViewHost) from being queried.
    if (![self isKindOfClass:[UITextField class]]) {
        return [self pp_textInputMode];
    }

    @try {
        UITextField *textField = (UITextField *)self;
        if ([textField respondsToSelector:@selector(keyboardType)]) {
            UIKeyboardType type = textField.keyboardType;
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
        }
    } @catch (NSException *exception) {
        // Fail-safe protection against any dynamic dispatch or runtime traits anomaly
    }

    return [self pp_textInputMode];
}

@end
