//
//  PPColorUtils.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 09/09/2025.
//


#import "PPColorUtils.h"

@implementation PPColorUtils

+ (UIImage *)imageNamed:(NSString *)name
              pointSize:(CGFloat)pointSize
                 weight:(UIImageSymbolWeight)weight
                  scale:(UIImageSymbolScale)scale
                palette:(NSArray<UIColor *> * _Nullable)palette
           fallbackTint:(UIColor * _Nullable)fallbackTint
         renderOriginal:(BOOL)original
{
    UIImage *base = nil;

    // Prefer SF Symbols if available
    if (@available(iOS 13.0, *)) {
        base = [UIImage systemImageNamed:name];
    }
    // Fallback to asset catalog
    if (!base) {
        base = [UIImage imageNamed:name];
        if (!base) { return nil; }
    }

    // Build symbol configuration (size/weight/scale)
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                            weight:weight
                                                             scale:scale];
        base = [base imageByApplyingSymbolConfiguration:cfg];
    }

    // Apply palette when supported (iOS 15+). If not, fallbackTint if provided.
    if (@available(iOS 15.0, *)) {
        if (palette.count > 0) {
            UIImageSymbolConfiguration *paletteCfg =
                [UIImageSymbolConfiguration configurationWithPaletteColors:palette];
            base = [base imageByApplyingSymbolConfiguration:paletteCfg];
        } else if (fallbackTint) {
            base = [base imageWithTintColor:fallbackTint renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    } else if (fallbackTint) {
        base = [base imageWithTintColor:fallbackTint];
    }

    // Rendering mode preference
    base = [base imageWithRenderingMode:(original ? UIImageRenderingModeAlwaysOriginal
                                                  : UIImageRenderingModeAlwaysTemplate)];
    return base;
}

+ (void)applyGradientFromImage:(UIImageView *)imageView
                        toView:(UIView *)targetView
             withToneAdjustment:(PPColorToneAdjustment)adjustment
                        degree:(CGFloat)degree {

    UIColor *baseColor = [self dominantColorFromImage:imageView.image];
    if (!baseColor) return;

    UIColor *startColor = [self adjustColor:baseColor tone:adjustment intensity:0.2];
    UIColor *endColor = [self adjustColor:baseColor tone:adjustment intensity:0.05];

    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = targetView.bounds;
    gradientLayer.colors = @[(__bridge id)startColor.CGColor,
                             (__bridge id)endColor.CGColor];

    // Convert degree to startPoint and endPoint
    CGFloat radians = degree * M_PI / 180.0;
    CGFloat x = cos(radians);
    CGFloat y = sin(radians);
    gradientLayer.startPoint = CGPointMake(0.5 - x / 2.0, 0.5 - y / 2.0);
    gradientLayer.endPoint   = CGPointMake(0.5 + x / 2.0, 0.5 + y / 2.0);

    // Clean existing gradients
    for (CALayer *layer in targetView.layer.sublayers.copy) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }

    [targetView.layer insertSublayer:gradientLayer atIndex:0];
}

// Extract dominant color using CIFilter
+ (UIColor *)dominantColorFromImage:(UIImage *)image {
    if (!image) return nil;

    CIImage *ciImage = [[CIImage alloc] initWithImage:image];
    CIFilter *filter = [CIFilter filterWithName:@"CIAreaAverage"
                                  keysAndValues: kCIInputImageKey, ciImage,
                        kCIInputExtentKey, [CIVector vectorWithCGRect:ciImage.extent], nil];

    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef outputImage = [context createCGImage:filter.outputImage fromRect:CGRectMake(0, 0, 1, 1)];

    unsigned char pixel[4] = {0};
    CGContextRef bitmap = CGBitmapContextCreate(pixel, 1, 1, 8, 4,
                                                 CGColorSpaceCreateDeviceRGB(),
                                                 kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, 1, 1), outputImage);
    CGContextRelease(bitmap);
    CGImageRelease(outputImage);

    return [UIColor colorWithRed:pixel[0] / 255.0
                           green:pixel[1] / 255.0
                            blue:pixel[2] / 255.0
                           alpha:1.0];
}

// Lighten or darken color
+ (UIColor *)adjustColor:(UIColor *)color tone:(PPColorToneAdjustment)tone intensity:(CGFloat)intensity {
    CGFloat h, s, b, a;
    if (![color getHue:&h saturation:&s brightness:&b alpha:&a]) {
        return color;
    }

    switch (tone) {
        case PPColorToneAdjustmentLighten:
            b = MIN(b + intensity, 1.0);
            break;
        case PPColorToneAdjustmentDarken:
            b = MAX(b - intensity, 0.0);
            break;
        default:
            break;
    }

    return [UIColor colorWithHue:h saturation:s brightness:b alpha:a];
}




+ (UIButton *)buttonWithSymbolName:(NSString *)name
                         pointSize:(CGFloat)pointSize
                            weight:(UIImageSymbolWeight)weight
                             scale:(UIImageSymbolScale)scale
                           palette:(NSArray<UIColor *> * _Nullable)palette
                      fallbackTint:(UIColor * _Nullable)fallbackTint
                    renderOriginal:(BOOL)original
                            target:(id)target
                            action:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;

    UIImage *symbolImage = [PPColorUtils imageNamed:name
                                             pointSize:pointSize
                                                weight:weight
                                                 scale:scale
                                               palette:palette
                                          fallbackTint:fallbackTint
                                        renderOriginal:original];

    [button setImage:symbolImage forState:UIControlStateNormal];

    if (target && action) {
        [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    }

    // Optional: standardize appearance
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.tintColor = fallbackTint ?: [UIColor ppPrimary];

    return button;
}


+ (void)setSymImage:(NSString *)image  toButton:(UIButton *)button
{
    UIImage *img =
    [PPColorUtils imageNamed:image
                      pointSize:16
                         weight:UIImageSymbolWeightSemibold
                          scale:UIImageSymbolScaleLarge
                        palette:@[AppPrimaryClr, SeconderyTextClr]
                   fallbackTint:AppPrimaryClr
                 renderOriginal:NO];

    // Example: set on an image view
    [button setImage:img forState:UIControlStateNormal];
}

#pragma mark - Selected Cell Color

+ (UIColor *)pp_selectedCellColorFromPrimary {
    return [self pp_selectedCellColorFromPrimaryWithAlpha:0.1];
}

+ (UIColor *)pp_selectedCellColorFromPrimaryWithAlpha:(float)cusAlpha {
    UIColor *baseColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.5];
    CGFloat hue, sat, bright, alpha;
    [baseColor getHue:&hue saturation:&sat brightness:&bright alpha:&alpha];
    return [UIColor colorWithHue:hue saturation:sat brightness:MIN(bright + 0.2, 1.0) alpha:cusAlpha];
}

+ (UIColor *)pp_selectedCellColorFromPrimaryFull {
    UIColor *baseColor = [UIColor ppPrimary];
    CGFloat hue, sat, bright, alpha;
    [baseColor getHue:&hue saturation:&sat brightness:&bright alpha:&alpha];
    return [UIColor colorWithHue:hue saturation:sat brightness:MIN(bright + 0.2, 1.0) alpha:1.1];
}

@end
