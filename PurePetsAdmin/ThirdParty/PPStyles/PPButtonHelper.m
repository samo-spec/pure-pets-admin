

//  PPButtonHelper.m
#import "PPButtonHelper.h"
#import "PPFunc+Haptics.h"

@implementation PPButtonHelper

+ (void)attachTapAnimationToButton:(UIButton *)button
                             style:(PPButtonAnimationStyle)style
{
    [button addTarget:self
               action:@selector(_pp_handleTap:)
     forControlEvents:UIControlEventTouchUpInside];

    // Store style in button (so each button remembers its animation style)
    objc_setAssociatedObject(button, @"ppAnimStyle", @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)attachTapAnimationToButton:(UIButton *)button {
    [self attachTapAnimationToButton:button style:PPButtonAnimationStyleDefault];
}

+ (void)animateTapOnView:(UIView *)view {
    [PPButtonHelper animateTapOnView:view completion:nil];
}

+ (void)animateTapOnView:(UIView *)view
              completion:(void (^ _Nullable)(BOOL finished))completion {
    [self _pp_playSound]; // 👈 play sound whenever animation runs
    
    [UIView animateWithDuration:0.1 animations:^{
        view.transform = CGAffineTransformMakeScale(0.95, 0.95);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2
                              delay:0
             usingSpringWithDamping:0.4
              initialSpringVelocity:3
                            options:0
                         animations:^{
            view.transform = CGAffineTransformIdentity;
        } completion:^(BOOL innerFinished) {
            if (completion) {
                completion(innerFinished);
            }
        }];
    }];
}


#pragma mark - Private

+ (void)_pp_handleTap:(UIButton *)sender {
    // sound 👇
    [self _pp_playSound];

    NSNumber *styleNum = objc_getAssociatedObject(sender, @"ppAnimStyle");
    PPButtonAnimationStyle style = styleNum ? styleNum.integerValue : PPButtonAnimationStyleDefault;

    switch (style) {
        case PPButtonAnimationStyleDefault:
            [self animateTapOnView:sender];
            break;
        case PPButtonAnimationStylePulse:
            [self _pp_pulse:sender];
            break;
        case PPButtonAnimationStyleGlow:
            [self _pp_glow:sender];
            break;
        case PPButtonAnimationStyleShake:
            [self _pp_shake:sender];
            break;
    }
}

+ (void)_pp_playSound {
    [PPFunc pp_playTapEffect];
}


#pragma mark - Animations

+ (void)_pp_pulse:(UIView *)view {
    [self _pp_playSound];
    [UIView animateWithDuration:0.1 animations:^{
        view.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            view.transform = CGAffineTransformIdentity;
        }];
    }];
}

+ (void)_pp_glow:(UIView *)view {
    [self _pp_playSound];
    view.layer.shadowColor = AppShadowColor.CGColor;
    view.layer.shadowOpacity = 0.1;
    view.layer.shadowRadius = 5;
    [self animateTapOnView:view];
}

+ (void)_pp_shake:(UIView *)view {
    [self _pp_playSound];
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = @[ @(-8), @(8), @(-5), @(5), @(0) ];
    shake.duration = 0.4;
    [view.layer addAnimation:shake forKey:@"shake"];
}

@end








/*

 
 
 
 
 //  PPButtonHelper.m
 //  PurePetsAdmin
 //
 //  Created by Mohammed Ahmed on 24/08/2025.
 //

 #import "PPButtonHelper.h"
 #import <AudioToolbox/AudioToolbox.h>

 @implementation PPButtonHelper

 + (void)attachTapAnimationToButton:(UIButton *)button {
     [self attachTapAnimationToButton:button style:PPButtonAnimationStyleDefault];
 }

 + (void)attachTapAnimationToButton:(UIButton *)button
                              style:(PPButtonAnimationStyle)style {
     [button addTarget:self action:@selector(_pp_handleTap:) forControlEvents:UIControlEventTouchUpInside];
     objc_setAssociatedObject(button, @selector(_pp_handleTap:), @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 }

 + (void)_pp_handleTap:(UIButton *)sender {
     NSNumber *styleNum = objc_getAssociatedObject(sender, @selector(_pp_handleTap:));
     PPButtonAnimationStyle style = styleNum ? styleNum.integerValue : PPButtonAnimationStyleDefault;

     // 🔊 Play modern tap sound
     AudioServicesPlaySystemSound(1104);

     // 🔄 Animate
     [self animateView:sender style:style];
 }

 + (void)animateTapOnView:(UIView *)view {
     [self animateView:view style:PPButtonAnimationStyleDefault];
 }

 + (void)animateView:(UIView *)view style:(PPButtonAnimationStyle)style {
     
     switch (style) {
         case PPButtonAnimationStyleDefault:
         {
             [UIView animateWithDuration:0.1 animations:^{
                 view.transform = CGAffineTransformMakeScale(0.95, 0.95);
             } completion:^(BOOL finished) {
                 [UIView animateWithDuration:0.15 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:3 options:0 animations:^{
                     view.transform = CGAffineTransformIdentity;
                 } completion:nil];
             }];
         }
             break;
             
         case PPButtonAnimationStylePulse:
         {
             [UIView animateWithDuration:0.1 animations:^{
                 view.transform = CGAffineTransformMakeScale(1.05, 1.05);
             } completion:^(BOOL finished) {
                 [UIView animateWithDuration:0.2 animations:^{
                     view.transform = CGAffineTransformIdentity;
                 }];
             }];
         }
             break;
             
         case PPButtonAnimationStyleGlow:
         {
             view.layer.shadowColor = [UIColor ppPrimary].CGColor;
             view.layer.shadowOpacity = 0.6;
             view.layer.shadowRadius = 6;
             view.layer.shadowOffset = CGSizeZero;
             [UIView animateWithDuration:0.2 animations:^{
                 view.transform = CGAffineTransformMakeScale(1.05, 1.05);
             } completion:^(BOOL finished) {
                 [UIView animateWithDuration:0.2 animations:^{
                     view.transform = CGAffineTransformIdentity;
                     view.layer.shadowOpacity = 0.0;
                 }];
             }];
         }
             break;
             
         case PPButtonAnimationStyleShake:
         {
             [UIView animateWithDuration:0.05 animations:^{
                 view.transform = CGAffineTransformMakeTranslation(-5, 0);
             } completion:^(BOOL finished) {
                 [UIView animateWithDuration:0.05 animations:^{
                     view.transform = CGAffineTransformMakeTranslation(5, 0);
                 } completion:^(BOOL finished) {
                     view.transform = CGAffineTransformIdentity;
                 }];
             }];
         }
             break;
             
         default:
             break;
     }
     
 }

 @end
 
 
 
//  PPButtonHelper.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


//
//  PPButtonHelper.m
//
#import "PPButtonHelper.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation PPButtonHelper

+ (void)attachTapAnimationToButton:(UIButton *)button
                             style:(PPButtonAnimationStyle)style {
    button.adjustsImageWhenHighlighted = NO;
    [button addTarget:self
               action:@selector(_pp_handleTap:)
     forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, "pp_animStyle", @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)_pp_handleTap:(UIButton *)sender {
    NSNumber *styleNum = objc_getAssociatedObject(sender, "pp_animStyle");
    PPButtonAnimationStyle style = styleNum ? styleNum.integerValue : PPButtonAnimationStyleDefault;

    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];

    switch (style) {
        case PPButtonAnimationStyleDefault:
            [self _defaultAnimation:sender];
            break;
        case PPButtonAnimationStylePulse:
            [self _pulseAnimation:sender];
            break;
        case PPButtonAnimationStyleGlow:
            [self _glowAnimation:sender];
            break;
        case PPButtonAnimationStyleShake:
            [self _shakeAnimation:sender];
            break;
    }
}

#pragma mark - Animations

+ (void)_defaultAnimation:(UIButton *)btn {
    [UIView animateWithDuration:0.1 animations:^{
        btn.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2
                              delay:0
             usingSpringWithDamping:0.4
              initialSpringVelocity:6
                            options:0
                         animations:^{
            btn.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

+ (void)_pulseAnimation:(UIButton *)btn {
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.duration = 0.15;
    pulse.fromValue = @1.0;
    pulse.toValue = @1.15;
    pulse.autoreverses = YES;
    [btn.layer addAnimation:pulse forKey:@"pulse"];
}

+ (void)_glowAnimation:(UIButton *)btn {
    btn.layer.shadowColor = btn.tintColor.CGColor;
    btn.layer.shadowRadius = 8.0;
    btn.layer.shadowOpacity = 0.8;
    btn.layer.shadowOffset = CGSizeZero;

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    pulse.duration = 0.15;
    pulse.fromValue = @1.0;
    pulse.toValue = @1.12;
    pulse.autoreverses = YES;
    [btn.layer addAnimation:pulse forKey:@"glowPulse"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        btn.layer.shadowOpacity = 0;
    });
}

+ (void)_shakeAnimation:(UIButton *)btn {
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = @[ @(-8), @(8), @(-5), @(5), @(0) ];
    shake.duration = 0.4;
    [btn.layer addAnimation:shake forKey:@"shake"];
}




+ (void)attachTapAnimationToButton:(UIButton *)button {
    // Avoid multiple adds
    [button removeTarget:self action:@selector(_pp_onTouchDown:) forControlEvents:UIControlEventTouchDown];
    [button removeTarget:self action:@selector(_pp_onTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    [button addTarget:self action:@selector(_pp_onTouchDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(_pp_onTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

+ (void)animateTapOnView:(UIView *)view {
    [self _animateScaleOnView:view];
    [self _hapticFeedback];
}

#pragma mark - Private

+ (void)_pp_onTouchDown:(UIButton *)btn {
    [UIView animateWithDuration:0.1
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        btn.transform = CGAffineTransformMakeScale(0.95, 0.95);
        btn.alpha = 0.9;
    } completion:nil];
}

+ (void)_pp_onTouchUp:(UIButton *)btn {
    [UIView animateWithDuration:0.15
                          delay:0
         usingSpringWithDamping:0.5
          initialSpringVelocity:3.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        btn.transform = CGAffineTransformIdentity;
        btn.alpha = 1.0;
    } completion:nil];

    [self _hapticFeedback];
}

+ (void)_animateScaleOnView:(UIView *)view {
    view.transform = CGAffineTransformMakeScale(0.95, 0.95);
    [UIView animateWithDuration:0.25
                          delay:0
         usingSpringWithDamping:0.5
          initialSpringVelocity:3.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}

+ (void)_hapticFeedback {
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [impact impactOccurred];
    } else {
        AudioServicesPlaySystemSound(1519); // fallback "tap" vibration
    }
}






@end

 
 
 UIButton *save = [self pp_circleButtonWithSystemName:@"checkmark" action:@selector(onSave)];
 [PPButtonHelper attachTapAnimationToButton:save style:PPButtonAnimationStyleDefault];

 UIButton *delete = [self pp_circleButtonWithSystemName:@"trash" action:@selector(onDelete)];
 [PPButtonHelper attachTapAnimationToButton:delete style:PPButtonAnimationStyleShake];

 UIButton *filter = [self pp_circleButtonWithSystemName:@"line.3.horizontal.decrease.circle" action:@selector(onFilter)];
 [PPButtonHelper attachTapAnimationToButton:filter style:PPButtonAnimationStylePulse];

 
 
 UIButton *save = [self pp_circleButtonWithSystemName:@"checkmark" action:@selector(onSave)];
 [PPButtonHelper attachTapAnimationToButton:save];

 
 UIButton *filterBtn = [UIButton buttonWithType:UIButtonTypeSystem];
 [filterBtn setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] forState:UIControlStateNormal];
 filterBtn.tintColor = AppPrimaryClr;

 [PPButtonHelper attachTapAnimationToButton:filterBtn];

 [PPButtonHelper attachTapAnimationToButton:btn style:PPButtonAnimationStylePulse];

 */
