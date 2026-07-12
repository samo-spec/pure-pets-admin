//
//  PPTextFieldCell.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


// In PPTextFieldCell.h
#import <UIKit/UIKit.h>
#import "XLForm.h"
@class PPTextField;

extern NSString * const XLFormRowDescriptorTypePPTextField;

@interface PPTextFieldCell : XLFormBaseCell <UITextFieldDelegate>
@property (nonatomic, strong, readonly) PPTextField *textField;
@property (assign, nonatomic) UIKeyboardType keyboardType;
@property (assign, nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property (assign, nonatomic) UIReturnKeyType returnKeyType;
@property (assign, nonatomic) UITextAutocorrectionType autocorrectionType;
@property (assign, nonatomic) BOOL secure;



@end

