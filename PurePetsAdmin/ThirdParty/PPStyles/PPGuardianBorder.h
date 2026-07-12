//
//  UIView.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


// in UIView+PPGuardianBorder.h
#import <UIKit/UIKit.h>

@interface UIView (PPGuardianBorder)

- (void)pp_applyGuardianBorder;
- (void)pp_applyGuardianBorderWithRadius:(CGFloat)radius;

- (void)pp_applyGuardianBorderWithColors:(NSArray<UIColor *> *)colorsArr;
- (void)pp_applyGuardianBorderWithColors:(NSArray<UIColor *> *)colorsArr radius:(CGFloat)radius;
- (void)pp_applyDefualtGuardianWithRadius:(CGFloat)radius;
- (void)pp_applyDefualtGuardianWithRadius:(CGFloat)radius borderWidth:(CGFloat)borderWidth;
@end
