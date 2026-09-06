//
//  UITextField+PPEnglishNumberKeyboard.h
//  PurePetsAdmin
//
//  Created for PurePets Admin Sovereign Catalog Editors.
//  Enforces English number keyboard layout for numeric and decimal input fields.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PPForcedKeyboardLanguageEnglish;
FOUNDATION_EXPORT NSString * const PPForcedKeyboardLanguageArabic;

@interface UITextField (PPEnglishNumberKeyboard)
@property (nonatomic, copy, nullable) NSString *pp_forcedKeyboardLanguage;
@end

@interface UITextView (PPKeyboardLanguage)
@property (nonatomic, copy, nullable) NSString *pp_forcedKeyboardLanguage;
@end

NS_ASSUME_NONNULL_END
