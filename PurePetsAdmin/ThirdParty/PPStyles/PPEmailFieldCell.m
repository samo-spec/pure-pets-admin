//
//  PPEmailFieldCell.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//  Cleaned + logging + KVC-safe version
//

#import "PPEmailFieldCell.h"
#import "Styling.h"
#import "Language.h"
#import "PPButtonHelper.h"

#ifndef DLog
#define DLog(fmt, ...) NSLog((@"[PPLOG][EmailFieldCell] %s: " fmt), __FUNCTION__, ##__VA_ARGS__);
#endif

@implementation PPEmailFieldCell

@dynamic rowDescriptor;

#pragma mark - Load / Registration
+ (void)load {
    // Map custom row type => this cell (call once at app start)
    [XLFormViewController.cellClassesForRowDescriptorTypes setObject:self
                                                              forKey:@"XLFormRowDescriptorTypeEmailStacked"];
}

#pragma mark - Configure / Layout
- (void)configure {
    [super configure];

    self.selectionStyle = UITableViewCellSelectionStyleNone;

    // Title
    if (!_titleLabel) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [Styling fontMedium:15];
        _titleLabel.textColor = PrimaryTextClr;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [self.contentView addSubview:_titleLabel];
    }

    // Text field
    if (!_textField) {
        _textField = [UITextField new];
        _textField.font = [Styling fontMedium:16];
        _textField.textColor = PrimaryTextClr;
        _textField.keyboardType = UIKeyboardTypeEmailAddress;
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.textAlignment = Language.alignmentForCurrentLanguage;
        _textField.borderStyle = UITextBorderStyleNone;
        _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _textField.autocorrectionType = UITextAutocorrectionTypeNo;
        [_textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        [self.contentView addSubview:_textField];
    }

    // Pick button (on the right)
    if (!_pickButton) {
        _pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _pickButton.translatesAutoresizingMaskIntoConstraints = NO;
        _pickButton.tintColor = AppPrimaryClr;
        _pickButton.backgroundColor = AppForgroundColr;
        _pickButton.layer.cornerRadius = 20;
        _pickButton.backgroundColor = AppBackgroundClr;
        //_pickButton.layer.borderColor = AppPrimaryClrWithAlpha(0.5).CGColor;
        //_pickButton.layer.borderWidth = 1.0;
        _pickButton.layer.masksToBounds = YES;
        [_pickButton addTarget:self action:@selector(didTapPick) forControlEvents:UIControlEventTouchUpInside];
        [PPButtonHelper attachTapAnimationToButton:_pickButton style:PPButtonAnimationStyleDefault];
        [self.contentView addSubview:_pickButton];
    }

    // Default constraints (Title stacked above TextField, pickButton right)
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_pickButton.leadingAnchor constant:-8],

        [_textField.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_textField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_textField.trailingAnchor constraintLessThanOrEqualToAnchor:_pickButton.leadingAnchor constant:-8],
        [_textField.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        [_textField.heightAnchor constraintEqualToConstant:40],

        [_pickButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_pickButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_pickButton.widthAnchor constraintEqualToConstant:40],
        [_pickButton.heightAnchor constraintEqualToConstant:40]
    ]];

    // Ensure the accessoryView is hidden (we use our own pickButton inside contentView)
    self.accessoryView = nil;
}

void LogCurrentConfig(void) {
    NSLog(@"[PPLOG] [Config] Current config: ...");
}

#pragma mark - Update (called by XLForm)
- (void)update {
    [super update];

    LogCurrentConfig();

    // Title & placeholder
    _titleLabel.text = self.rowDescriptor.title ?: @"";
    NSString *placeholder = [self safeConfigForKey:@"textField.placeholder"] ?: @"";
    _textField.placeholder = placeholder;

    // Value: XLForm row may contain string or XLFormOptionsObject — present as string
    id value = self.rowDescriptor.value;
    if ([value isKindOfClass:[XLFormOptionsObject class]]) {
        _textField.text = [(XLFormOptionsObject *)value displayText] ?: @"";
    } else if ([value isKindOfClass:[NSString class]]) {
        _textField.text = (NSString *)value;
    } else if (value == nil || value == [NSNull null]) {
        _textField.text = @"";
    } else {
        // Fallback: try to convert
        _textField.text = [value description] ?: @"";
    }

    // showPickButton config (accept NSNumber or string like @"1" or @"YES")
    id rawShow = [self safeConfigForKey:@"showPickButton"];
    BOOL show = NO;
    if ([rawShow isKindOfClass:[NSNumber class]]) {
        show = [(NSNumber *)rawShow boolValue];
    } else if ([rawShow isKindOfClass:[NSString class]]) {
        show = [(NSString *)rawShow boolValue];
    }
    [self setShowPickButton:show];

    // pick button system image name
    NSString *sym = [self safeConfigForKey:@"pickButtonSystemName"];
    if (sym && [sym isKindOfClass:NSString.class] && sym.length) {
        UIImage *img = [UIImage systemImageNamed:sym];
        if (img) {
            [_pickButton setImage:img forState:UIControlStateNormal];
        }
    } else {
        // default icon
        [_pickButton setImage:[UIImage systemImageNamed:@"person.crop.circle.badge.plus"] forState:UIControlStateNormal];
    }

    // optional onPickTap block that may be stored in cellConfig (useful for inline wiring)
    id pickBlock = [self safeConfigForKey:@"onPickTap"];
    if (pickBlock && [pickBlock isKindOfClass:NSClassFromString(@"NSBlock")]) {
        // store to property so we can call it on tap (weak capture avoids retain cycle)
        self.onPickTap = pickBlock;
    }

    // semantic & alignment
    self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    _textField.textAlignment = Language.alignmentForCurrentLanguage;
}

#pragma mark - Helpers

// Safe read that checks both live config and configure-time config
- (id)safeConfigForKey:(NSString *)key {
    id val = self.rowDescriptor.cellConfig[key];
    if (val) return val;
    val = self.rowDescriptor.cellConfigAtConfigure[key];
    if (val) return val;
    return nil;
}

- (void)setShowPickButton:(BOOL)showPickButton { 
    DLog(@"setShowPickButton = %d", showPickButton);
    _showPickButton = showPickButton;
    self.pickButton.hidden = !showPickButton;
}

#pragma mark - Actions

- (void)didTapPick {
    DLog(@"didTapPick invoked");

    // first try cell-level block
    if (self.onPickTap && [self.onPickTap respondsToSelector:@selector(invoke)]) {
        // invoke block if it's an ObjC block
        void (^block)(XLFormRowDescriptor *) = self.onPickTap;
        if (block) {
            block(self.rowDescriptor);
            return;
        }
    }

    // delegate callback
    if (self.delegate && [self.delegate respondsToSelector:@selector(emailFieldCellDidTapPick:)]) {
        DLog(@"calling delegate emailFieldCellDidTapPick:");
        [self.delegate emailFieldCellDidTapPick:self.rowDescriptor];
        return;
    }

    // fallback: try XLForm action blocks
    if (self.rowDescriptor.onChangeBlock) {
        DLog(@"calling rowDescriptor.onChangeBlock fallback");
        self.rowDescriptor.onChangeBlock(self.rowDescriptor.value, self.rowDescriptor.value, self.rowDescriptor);
    }
}

- (void)textFieldDidChange:(UITextField *)tf {
    DLog(@"textFieldDidChange: %@", tf.text ?: @"");
    // Update XLForm row.value — keep same type (string)
    self.rowDescriptor.value = tf.text ?: @"";
    // notify the form controller
    // some XLForm API calls updateFormRow: — but we don't know parent here; caller can update
   /*
    @property (nonatomic, strong) UIView *searchContainer;
    */
    
}

#pragma mark - First responder helpers (XLForm expects these)
- (BOOL)formDescriptorCellCanBecomeFirstResponder {
    return YES;
}
- (BOOL)formDescriptorCellBecomeFirstResponder {
    return [_textField becomeFirstResponder];
}
- (BOOL)formDescriptorCellResignFirstResponder {
    return [_textField resignFirstResponder];
}

#pragma mark - KVC safety
// This prevents crashes if some nib or xib tries to set an undefined key (common cause of NSUnknownKeyException)
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    DLog(@"Ignored KVC set for undefined key: %@", key);
    // If you want to catch specific misnamed keys (e.g. 'showPickButton' wired in xib incorrectly),
    // add special handling here or raise an assert in debug builds.
}

/********** ISSUE CATCH / SUGGESTIONS **********

 1) If you still see: "this class is not key value coding-compliant for the key XYZ"
    -> check your XIB / storyboard for that cell. Remove or rename the incorrectly linked outlet.
    Suggestion:
      - Open the XIB/NIB for the cell, inspect connections inspector.
      - Remove stale outlets (pickButtonSystemName / showPickButton) that were wired to the wrong property name.
  
 2) If the pick button doesn't call the controller's handler:
    - Ensure your controller sets the cell's delegate (e.g. in tableView:cellForRowAtIndexPath:).
    - Or set rowDescriptor.action.formBlock or cellConfig[@"onPickTap"] to a block; this implementation will call that block.
  
 3) XLForm value types:
    - XLForm row value can be XLFormOptionsObject, NSString, NSNumber, etc.
    - Here we display string via displayText or description. If you need to store the raw object, do NOT overwrite rowDescriptor.value in textFieldDidChange: (or keep a separate property).
  
 4) If you want the row to update visually from the controller after picking:
    - Either call [form updateFormRow:row] from the controller or set row.value and then [self updateFormRow:row].
    - Example inside controller: row.value = display; [self updateFormRow:row];
  
 5) If you get "Auto property synthesis will not synthesize property 'rowDescriptor'":
    - Keep @dynamic rowDescriptor in the cell .m as above (XLForm supplies it). Do not add @synthesize.

 6) If you used KVC booleans like `cellConfigAtConfigure[@"showPickButton"] = @YES;` prefer NSNumber not bare BOOL.
  
 7) If you want pickButton to be in accessoryView instead:
    - Move pickButton as accessoryView and remove from contentView, but be careful with XLForm's own accessory usage.
*/
@end
