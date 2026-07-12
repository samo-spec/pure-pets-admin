//
//  PPButtonHelper.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


//
//  PPButtonHelper.h
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PPButtonAnimationStyle) {
    PPButtonAnimationStyleDefault,  // shrink + spring
    PPButtonAnimationStylePulse,    // subtle pulse
    PPButtonAnimationStyleGlow,     // pulse with glow shadow
    PPButtonAnimationStyleShake     // shake for errors
};



@interface PPButtonHelper : NSObject

+ (void)attachTapAnimationToButton:(UIButton *_Nullable)button
                             style:(PPButtonAnimationStyle)style;

/// Attach a tap animation to a button (scale + haptic).
+ (void)attachTapAnimationToButton:(UIButton *_Nullable)button;

/// Manual trigger (if you want to animate programmatically).
+ (void)animateTapOnView:(UIView *_Nullable)view;

+ (void)animateTapOnView:(UIView *_Nullable)view
              completion:(void (^ _Nullable)(BOOL finished))completion;
@end

