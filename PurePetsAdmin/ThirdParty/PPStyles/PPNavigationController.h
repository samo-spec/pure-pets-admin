//
//  PPNavigationController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 07/09/2025.
//


// In PPNavigationController.h
#import <UIKit/UIKit.h>

/// Button configuration styles used by setButtonAsBackroundButtonWithStyle:configType:
typedef NS_ENUM(NSUInteger, PPButtonConfigration) {
    PPButtonConfigrationGlass = 0,
    PPButtonConfigrationClearGlass,
    PPButtonConfigrationPromp,
    PPButtonConfigrationClearPromp,
    PPButtonConfigrationTinted,
    PPButtonConfigrationTintedBorderd,
    PPButtonConfigrationFilled
};

@interface PPNavigationController : UINavigationController

/// Creates a styled background button (glass on iOS 26+, frosted fallback on older).
+ (UIButton *)setButtonAsBackroundButtonWithStyle:(UIButtonConfigurationCornerStyle)style;
+ (UIButton *)setButtonAsBackroundButtonWithStyle:(UIButtonConfigurationCornerStyle)style
                                       configType:(PPButtonConfigration)configType;

@end