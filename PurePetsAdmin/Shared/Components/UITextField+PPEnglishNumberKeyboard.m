//
//  UITextField+PPEnglishNumberKeyboard.m
//  PurePetsAdmin
//
//  Created for PurePets Admin Sovereign Catalog Editors.
//  Enforces English number keyboard layout for numeric and decimal input fields.
//

#import "UITextField+PPEnglishNumberKeyboard.h"
#import <objc/runtime.h>

NSString * const PPForcedKeyboardLanguageEnglish = @"en";
NSString * const PPForcedKeyboardLanguageArabic  = @"ar";

static char kPPForcedKeyboardLangKey;

static UITextInputMode * _Nullable PPFindInputModeForLanguage(NSString *prefix) {
    if (!prefix || prefix.length == 0) return nil;
    NSString *needle = [prefix lowercaseString];
    for (UITextInputMode *mode in [UITextInputMode activeInputModes]) {
        NSString *lang = [mode.primaryLanguage lowercaseString];
        if (lang && ([lang hasPrefix:needle] || [lang isEqualToString:needle])) {
            return mode;
        }
    }
    return nil;
}

static NSString * _Nullable PPResolvedForcedLanguage(id responder) {
    // 1. Explicit associated object property
    NSString *forced = objc_getAssociatedObject(responder, &kPPForcedKeyboardLangKey);
    if (forced.length > 0) return forced;

    // 2. Accessibility identifier inspection
    if ([responder respondsToSelector:@selector(accessibilityIdentifier)]) {
        NSString *ident = [responder accessibilityIdentifier];
        if (ident.length > 0) {
            if ([ident rangeOfString:@"force_ar" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [ident rangeOfString:@"keyboard_ar" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return PPForcedKeyboardLanguageArabic;
            }
            if ([ident rangeOfString:@"force_en" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [ident rangeOfString:@"keyboard_en" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return PPForcedKeyboardLanguageEnglish;
            }
        }
    }
    return nil;
}

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

- (void)setPp_forcedKeyboardLanguage:(NSString *)pp_forcedKeyboardLanguage {
    NSString *previous = objc_getAssociatedObject(self, &kPPForcedKeyboardLangKey);
    objc_setAssociatedObject(self, &kPPForcedKeyboardLangKey, pp_forcedKeyboardLanguage, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (self.isFirstResponder && ![previous isEqualToString:pp_forcedKeyboardLanguage]) {
        // reloadInputViews alone does NOT re-query textInputMode.
        // A full responder cycle is the only reliable way to switch
        // the active keyboard language.
        [self resignFirstResponder];
        [self becomeFirstResponder];
    }
}

- (NSString *)pp_forcedKeyboardLanguage {
    return objc_getAssociatedObject(self, &kPPForcedKeyboardLangKey);
}

- (UITextInputMode *)pp_textInputMode {
    if (![self isKindOfClass:[UITextField class]]) {
        return [self pp_textInputMode];
    }

    @try {
        UITextField *textField = (UITextField *)self;
        
        // 1. Explicit forced language (Arabic or English)
        NSString *forcedLang = PPResolvedForcedLanguage(textField);
        if (forcedLang) {
            UITextInputMode *mode = PPFindInputModeForLanguage(forcedLang);
            if (mode) return mode;
        }

        // 2. Numeric pad or ASCII-capable fallback (English)
        if ([textField respondsToSelector:@selector(keyboardType)]) {
            UIKeyboardType type = textField.keyboardType;
            if (type == UIKeyboardTypeDecimalPad ||
                type == UIKeyboardTypeNumberPad ||
                type == UIKeyboardTypeASCIICapableNumberPad ||
                type == UIKeyboardTypeASCIICapable) {
                
                UITextInputMode *enMode = PPFindInputModeForLanguage(@"en");
                if (enMode) return enMode;
            }
        }

        // 3. Right-to-Left alignment fallback (Arabic)
        if (textField.textAlignment == NSTextAlignmentRight ||
            textField.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft) {
            UITextInputMode *arMode = PPFindInputModeForLanguage(@"ar");
            if (arMode) return arMode;
        }
    } @catch (NSException *exception) {
    }

    return [self pp_textInputMode];
}

@end

@implementation UITextView (PPKeyboardLanguage)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [UITextView class];
        SEL origSel = @selector(textInputMode);
        SEL swzSel = @selector(pp_textView_textInputMode);

        Method origMethod = class_getInstanceMethod(cls, origSel);
        Method swzMethod = class_getInstanceMethod(cls, swzSel);
        if (!origMethod || !swzMethod) return;

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

- (void)setPp_forcedKeyboardLanguage:(NSString *)pp_forcedKeyboardLanguage {
    NSString *previous = objc_getAssociatedObject(self, &kPPForcedKeyboardLangKey);
    objc_setAssociatedObject(self, &kPPForcedKeyboardLangKey, pp_forcedKeyboardLanguage, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (self.isFirstResponder && ![previous isEqualToString:pp_forcedKeyboardLanguage]) {
        [self resignFirstResponder];
        [self becomeFirstResponder];
    }
}

- (NSString *)pp_forcedKeyboardLanguage {
    return objc_getAssociatedObject(self, &kPPForcedKeyboardLangKey);
}

- (UITextInputMode *)pp_textView_textInputMode {
    if (![self isKindOfClass:[UITextView class]]) {
        return [self pp_textView_textInputMode];
    }

    @try {
        UITextView *textView = (UITextView *)self;
        // 1. Explicit forced language (Arabic or English)
        NSString *forcedLang = PPResolvedForcedLanguage(textView);
        if (forcedLang) {
            UITextInputMode *mode = PPFindInputModeForLanguage(forcedLang);
            if (mode) return mode;
        }

        // 2. ASCII-capable fallback (English)
        if ([textView respondsToSelector:@selector(keyboardType)]) {
            if (textView.keyboardType == UIKeyboardTypeASCIICapable) {
                UITextInputMode *enMode = PPFindInputModeForLanguage(@"en");
                if (enMode) return enMode;
            }
        }

        // 3. Right-to-Left alignment fallback (Arabic)
        if (textView.textAlignment == NSTextAlignmentRight ||
            textView.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft) {
            UITextInputMode *arMode = PPFindInputModeForLanguage(@"ar");
            if (arMode) return arMode;
        }
    } @catch (NSException *exception) {
    }

    return [self pp_textView_textInputMode];
}

@end

