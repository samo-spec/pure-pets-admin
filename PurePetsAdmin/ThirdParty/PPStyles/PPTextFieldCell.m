//
//  PPTextFieldCell 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


// In PPTextFieldCell.m
#import "PPTextFieldCell.h"


NSString * const XLFormRowDescriptorTypePPTextField = @"XLFormRowDescriptorTypePPTextField";

@interface PPTextFieldCell ()
@property (nonatomic, strong, readwrite) PPTextField *textField;
@end

@implementation PPTextFieldCell

+ (void)load {
    [XLFormViewController.cellClassesForRowDescriptorTypes setObject:self forKey:XLFormRowDescriptorTypePPTextField];
}

- (void)configure {
    [super configure];

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;

    self.textField = [[PPTextField alloc] initWithFrame:CGRectZero];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;
    _textField.delegate = self;
 
    
    _textField.font = [Styling fontMedium:16];

    // Direction
    _textField.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;

    [self.contentView addSubview:_textField];

    // Layout with comfy vertical padding to mimic the screenshot
    CGFloat vPad = 5.0;
    [NSLayoutConstraint activateConstraints:@[
        [_textField.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:vPad],
        [_textField.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-vPad],
        [_textField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_textField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
    ]];

    // Listen to editing changed to push value back to the form
    [_textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
}

- (void)update {
    [super update];

    // Placeholder from rowDescriptor.placeholder (recommended)
    _textField.placeholder = self.rowDescriptor.title;

    // Value
    id val = self.rowDescriptor.value;
    NSString *value = [val isKindOfClass:NSString.class] ? val : nil;
    _textField.text = value;

    // Enabled / Disabled
    _textField.enabled = !self.rowDescriptor.isDisabled;

    // Keyboard type / secure / autocap from cellConfig if provided
    id kb = self.rowDescriptor.cellConfigAtConfigure[@"keyboardType"];
    if ([kb isKindOfClass:NSNumber.class]) _textField.keyboardType = [kb integerValue];

    id sc = self.rowDescriptor.cellConfigAtConfigure[@"secure"];
    _textField.secureTextEntry = [sc boolValue];

    id ac = self.rowDescriptor.cellConfigAtConfigure[@"autocapitalizationType"];
    if ([ac isKindOfClass:NSNumber.class]) _textField.autocapitalizationType = [ac integerValue];

    id cr = self.rowDescriptor.cellConfigAtConfigure[@"returnKeyType"];
    if ([cr isKindOfClass:NSNumber.class]) _textField.returnKeyType = [cr integerValue];
    
    id act = self.rowDescriptor.cellConfigAtConfigure[@"autocorrectionType"];
    if ([act isKindOfClass:NSNumber.class]) _textField.autocorrectionType = [act integerValue];

    // Direction (re-apply if language changed on the fly)
    _textField.textAlignment = Language.alignmentForCurrentLanguage;
    _textField.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
}

#pragma mark - XLForm First Responder

- (BOOL)formDescriptorCellCanBecomeFirstResponder {
    return !_textField.isEnabled ? NO : YES;
}

- (BOOL)formDescriptorCellBecomeFirstResponder {
    return [_textField becomeFirstResponder];
}

#pragma mark - UITextField

- (void)textFieldDidChange:(UITextField *)sender {
    self.rowDescriptor.value = sender.text.length ? sender.text : nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // Advance to next row
    [self.formViewController.tableView endEditing:YES];
    return YES;
}

@end

