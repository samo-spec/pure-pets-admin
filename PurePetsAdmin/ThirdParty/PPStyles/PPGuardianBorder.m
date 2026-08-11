//
//  UIView.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


// in PPGuardianBorder.m
#import "PPGuardianBorder.h"

@implementation UIView (PPGuardianBorder)

- (void)pp_applyGuardianBorder {
    [self pp_applyGuardianBorderWithRadius:12.0]; // default
}

- (void)pp_applyGuardianBorderWithRadius:(CGFloat)radius {
    self.layer.cornerRadius = radius;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor colorWithWhite:0.85 alpha:1.0].CGColor;
}

/// Gradient border with default radius
- (void)pp_applyGuardianBorderWithColors:(NSArray<UIColor *> *)colorsArr {
    [self pp_applyGuardianBorderWithColors:colorsArr radius:12.0];
}

/// Gradient border with custom radius
- (void)pp_applyGuardianBorderWithColors:(NSArray<UIColor *> *)colorsArr radius:(CGFloat)radius {
   
    

    // Remove old gradient layer if exists
    for (CALayer *layer in self.layer.sublayers.copy) {
        if ([layer.name isEqualToString:@"PPGuardianBorderLayer"]) {
            [layer removeFromSuperlayer];
        }
    }

    self.layer.cornerRadius = radius;
    self.layer.masksToBounds = YES;

    // Gradient layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.name = @"PPGuardianBorderLayer";
    gradient.frame = self.bounds;
    
    // Accent gradient colors are sourced from PPDesignTokens.
    gradient.colors = @[(__bridge id)[UIColor ppError].CGColor,
                                             (__bridge id)[UIColor ppWarning].CGColor,
                                             (__bridge id)[UIColor ppPremiumAccent].CGColor];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1, 0.5);

    // Mask to only stroke the border
    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.lineWidth = 2.5;
    shape.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
    shape.fillColor = UIColor.clearColor.CGColor;
    shape.strokeColor = UIColor.blackColor.CGColor;
    gradient.mask = shape;

    [self.layer addSublayer:gradient];
}


- (void)pp_applyDefualtGuardianWithRadius:(CGFloat)radius {

    // Remove old gradient layer if exists
    for (CALayer *layer in self.layer.sublayers.copy) {
        if ([layer.name isEqualToString:@"PPGuardianBorderLayer"]) {
            [layer removeFromSuperlayer];
        }
    }

    self.layer.cornerRadius = radius;
    self.layer.masksToBounds = YES;

    
    UIColor *c1  = [AppPrimaryClr colorWithAlphaComponent:0.5];
    UIColor *c2  = [[UIColor ppPremiumAccent] colorWithAlphaComponent:0.5];
    UIColor *c3  = [AppPrimaryClrShiner colorWithAlphaComponent:0.5];
    UIColor *c4  = [[UIColor ppError] colorWithAlphaComponent:0.5];
    UIColor *c5  = [[UIColor ppPremiumAccent] colorWithAlphaComponent:0.5];
    UIColor *c6  = [AppPrimaryClrDarker colorWithAlphaComponent:0.5];
    
    
    // Gradient layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.name = @"PPGuardianBorderLayer";
    gradient.frame = self.bounds;
    gradient.colors = @[(__bridge id)c1.CGColor,
                                             (__bridge id)c2.CGColor,
                                             (__bridge id)c3.CGColor,
                        (__bridge id)c4.CGColor,
                        (__bridge id)c5.CGColor,
                        (__bridge id)c6.CGColor
                       ];
   

  
    // Mask to border shape
    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.lineWidth = 4.0;
    shape.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
    shape.fillColor = UIColor.clearColor.CGColor;
    shape.strokeColor = UIColor.blackColor.CGColor;
    gradient.mask = shape;

    [self.layer addSublayer:gradient];
}



- (void)pp_applyDefualtGuardianWithRadius:(CGFloat)radius borderWidth:(CGFloat)borderWidth{

    // Remove old gradient layer if exists
    for (CALayer *layer in self.layer.sublayers.copy) {
        if ([layer.name isEqualToString:@"PPGuardianBorderLayer"]) {
            [layer removeFromSuperlayer];
        }
    }

    self.layer.cornerRadius = radius;
    self.layer.masksToBounds = YES;

    // Gradient layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.name = @"PPGuardianBorderLayer";
    gradient.frame = self.bounds;
    gradient.colors = @[(__bridge id)AppPrimaryClrDarker.CGColor,
                                             (__bridge id)AppPrimaryClr.CGColor,
                                             (__bridge id)AppPrimaryClrShiner.CGColor];

    // 🔥 Randomize direction (so each cell border is unique)
    CGFloat randX1 = (arc4random_uniform(100)) / 100.0; // 0 → 1
    CGFloat randY1 = (arc4random_uniform(100)) / 100.0;
    CGFloat randX2 = (arc4random_uniform(100)) / 100.0;
    CGFloat randY2 = (arc4random_uniform(100)) / 100.0;

    gradient.startPoint = CGPointMake(randX1, randY1);
    gradient.endPoint   = CGPointMake(randX2, randY2);

    // Mask to border shape
    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.lineWidth = borderWidth;
    shape.path = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
    shape.fillColor = UIColor.clearColor.CGColor;
    shape.strokeColor = UIColor.blackColor.CGColor;
    gradient.mask = shape;

    [self.layer addSublayer:gradient];
}
@end
