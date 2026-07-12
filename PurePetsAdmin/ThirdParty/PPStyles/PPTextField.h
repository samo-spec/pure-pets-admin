//
//  PPTextField.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


// In PPTextField.h
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPTextField : UITextField

/// Insets for text/placeholder (default: {0,14,0,14})
@property (nonatomic, assign) UIEdgeInsets textInsets;


/// Update placeholder color (call after setting placeholder if you change it dynamically)
- (void)applyPlaceholderStyle;

/// Force LTR or RTL if you like; otherwise it follows current app direction.
/// Set this *before* the field is on screen.
- (void)applySemanticDirectionAutomatically;



@end

NS_ASSUME_NONNULL_END
