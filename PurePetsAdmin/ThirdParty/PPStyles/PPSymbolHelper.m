//
//  UIImage.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


#import "PPSymbolHelper.h"

@implementation UIImage (PPSymbol)


+ (UIImage *)pp_symbolNamed:(NSString *)name
{
    return [UIImage pp_symbolNamed:name pointSize:18 weight:UIImageSymbolWeightMedium scale:UIImageSymbolScaleDefault palette:@[AppForgroundColr , AppBackgroundClr] makeTemplate:NO];
}


+ (UIImage *)pp_symbolNamed:(NSString *)name
                  pointSize:(CGFloat)pointSize
                     weight:(UIImageSymbolWeight)weight
                      scale:(UIImageSymbolScale)scale
                    palette:(NSArray<UIColor *> *)palette
              makeTemplate:(BOOL)makeTemplate
{
    UIImage *img = [UIImage imageNamed:name];
#if __IPHONE_13_0
    if (!img) { img = [UIImage systemImageNamed:name]; } // allow using a real SF symbol name too
#endif
    if (!img) { return nil; }

#if __IPHONE_13_0
    // Try to apply symbol configuration (has effect only for symbol images)
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                       weight:weight
                                                        scale:scale];

#if __IPHONE_15_0
    if (palette.count > 0) {
        UIImageSymbolConfiguration *pal = [UIImageSymbolConfiguration configurationWithPaletteColors:palette];
        cfg = [cfg configurationByApplyingConfiguration:pal];
    }
#endif

    UIImage *configured = [img imageByApplyingSymbolConfiguration:cfg];
    if (configured) {
        return configured;
    }
#endif

    // Not a symbol → make it a template so tint works, and optionally resize to approx. point size.
    UIImage *templ = makeTemplate ? [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : img;
    return [self pp_resizedImage:templ toPointSize:pointSize];
}

+ (UIImage *)pp_resizedImage:(UIImage *)image toPointSize:(CGFloat)pointSize {
    if (!image) return nil;

    // Treat pointSize as target height; keep aspect
    CGFloat targetH = MAX(pointSize, 1.0);
    CGFloat aspect = image.size.width / MAX(image.size.height, 0.001);
    CGSize targetSize = CGSizeMake(targetH * aspect, targetH);

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:targetSize];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
        [image drawInRect:(CGRect){.origin=CGPointZero, .size=targetSize}];
    }];
}

@end


@implementation UIButton (PPSymbol)

- (void)pp_setSymbolNamed:(NSString *)name
                pointSize:(CGFloat)pointSize
                   weight:(UIImageSymbolWeight)weight
                    scale:(UIImageSymbolScale)scale
                     tint:(UIColor *)tint
                  palette:(NSArray<UIColor *> *)palette
{
    UIImage *img =
    [UIImage pp_symbolNamed:name
                  pointSize:pointSize
                     weight:weight
                      scale:scale
                    palette:palette
              makeTemplate:YES];

    [self setImage:img forState:UIControlStateNormal];
    self.tintColor = tint ?: self.tintColor;

#if __IPHONE_13_0
    // If it's a real symbol, this gives dynamic behavior with text styles too
    self.imageView.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                       weight:weight
                                                        scale:scale];
#endif

    // Make sure image fills nicely without squeezing
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
}

- (void)pp_setCircularStyleWithDiameter:(CGFloat)diameter
                             background:(UIColor *)background
                                   tint:(UIColor *)tint
{
    self.backgroundColor = background;
    self.tintColor = tint ?: self.tintColor;

    if (diameter > 0) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:diameter],
            [self.heightAnchor constraintEqualToConstant:diameter]
        ]];
        self.layer.cornerRadius = diameter * 0.5;
        self.layer.masksToBounds = YES;
    }

    // Place the glyph comfortably
    CGFloat inset = MAX( (diameter - 24.0) * 0.5, 6.0 ); // heuristic
    self.contentEdgeInsets = UIEdgeInsetsMake(inset, inset, inset, inset);
}

@end
