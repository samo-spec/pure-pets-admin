//
//  PPColorUtils.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 09/09/2025.
//


#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PPColorToneAdjustment) {
    PPColorToneAdjustmentNone,
    PPColorToneAdjustmentLighten,
    PPColorToneAdjustmentDarken
};

@interface PPColorUtils : NSObject

/// Extracts dominant color from UIImageView and applies gradient background to target view
/// @param imageView Source UIImageView
/// @param targetView View to apply gradient to
/// @param adjustment PPColorToneAdjustment (None / Lighten / Darken)
/// @param degree Gradient direction in degrees (0 = left to right, 90 = top to bottom)
+ (void)applyGradientFromImage:(UIImageView *)imageView
                   toView:(UIView *)targetView
         withToneAdjustment:(PPColorToneAdjustment)adjustment
                    degree:(CGFloat)degree;


+ (UIImage *)imageNamed:(NSString *)name
              pointSize:(CGFloat)pointSize
                 weight:(UIImageSymbolWeight)weight
                  scale:(UIImageSymbolScale)scale
                palette:(nullable NSArray<UIColor *> *)palette
           fallbackTint:(nullable UIColor *)fallbackTint
         renderOriginal:(BOOL)original;


+ (UIButton *)buttonWithSymbolName:(NSString *)name
                         pointSize:(CGFloat)pointSize
                            weight:(UIImageSymbolWeight)weight
                             scale:(UIImageSymbolScale)scale
                           palette:(nullable NSArray<UIColor *> *)palette
                      fallbackTint:(nullable UIColor *)fallbackTint
                    renderOriginal:(BOOL)original
                            target:(nullable id)target
                            action:(nullable SEL)action;


+ (void)setSymImage:(NSString *)image  toButton:(UIButton *)button;

+ (UIColor *)pp_selectedCellColorFromPrimary;
+ (UIColor *)pp_selectedCellColorFromPrimaryWithAlpha:(float)cusAlpha;
+ (UIColor *)pp_selectedCellColorFromPrimaryFull;

@end


// Safe color fallback: if 'c' is nil, use fallback
static inline UIColor *PPColorOr(UIColor *c, UIColor *fallback) {
    return c ?: fallback;
}


NS_ASSUME_NONNULL_END
//NS_ASSUME_NONNULL_BEGIN

