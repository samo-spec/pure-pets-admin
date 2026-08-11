//
//  PPTextField 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


// In PPTextField.m
#import "PPTextField.h"



@implementation PPTextField

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _textInsets = UIEdgeInsetsMake(0, 14, 0, 14);
      

        self.backgroundColor = UIColor.clearColor;
        self.borderStyle = UITextBorderStyleNone;
        self.clearButtonMode = UITextFieldViewModeWhileEditing;
        self.tintColor = AppPrimaryClr; // caret

        
        self.font = [Styling fontMedium:16];
        
        // Placeholder style (initial)
        [self applyPlaceholderStyle];

        // Direction by language
        [self applySemanticDirectionAutomatically];

        // Editing state changes
        [self addTarget:self action:@selector(_editingDidBegin) forControlEvents:UIControlEventEditingDidBegin];
        [self addTarget:self action:@selector(_editingDidEnd)   forControlEvents:UIControlEventEditingDidEnd];
        [self addTarget:self action:@selector(_editingChanged)  forControlEvents:UIControlEventEditingChanged];
        
        /*
         @property (assign, nonatomic) UIKeyboardType keyboardType;
         @property (assign, nonatomic) UITextAutocapitalizationType autocapitalizationType;
         @property (assign, nonatomic) UIReturnKeyType returnKeyType;
         */
        
        
        
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
}

#pragma mark - Insets

- (CGRect)textRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}
- (CGRect)editingRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}
- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    return UIEdgeInsetsInsetRect(bounds, self.textInsets);
}

#pragma mark - Placeholder styling

- (void)applyPlaceholderStyle {
    if (!self.placeholder) return;
    UIColor *ph = [UIColor ppTextSecondary];
    self.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.placeholder attributes:@{NSForegroundColorAttributeName: ph}];
}

#pragma mark - Semantic / Direction

- (void)applySemanticDirectionAutomatically {

    self.textAlignment = Language.alignmentForCurrentLanguage;
    self.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    
}

#pragma mark - State

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.textColor = enabled ? PrimaryTextClr : SeconderyTextClr;
}

- (void)_editingDidBegin {
    [self setNeedsLayout];
}
- (void)_editingDidEnd {
    [self setNeedsLayout];
}
- (void)_editingChanged {
    // reserved for future validation / formatting
}

@end
