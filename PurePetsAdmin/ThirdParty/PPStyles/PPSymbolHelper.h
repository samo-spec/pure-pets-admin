//
//  PPSymbolHelper.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (PPSymbol)
+ (UIImage *)pp_symbolNamed:(NSString *)name;
/// Loads either a *custom SF Symbol* from your asset catalog (recommended) or a normal image,
/// and applies symbol configuration when possible.
/// - name: asset name (try custom symbol first; falls back to system symbol; then plain image)
/// - pointSize/weight/scale: applied only when the image is a symbol
/// - palette: optional colors for hierarchical/palette rendering (iOS 15+)
/// - makeTemplate: for non-symbols, force template rendering so tint works
+ (UIImage *)pp_symbolNamed:(NSString *)name
                  pointSize:(CGFloat)pointSize
                     weight:(UIImageSymbolWeight)weight
                      scale:(UIImageSymbolScale)scale
                    palette:(NSArray<UIColor *> * _Nullable)palette
              makeTemplate:(BOOL)makeTemplate;

/// Resizes a non-symbol image to roughly match a symbol point size (maintains aspect).
+ (UIImage *)pp_resizedImage:(UIImage *)image toPointSize:(CGFloat)pointSize;

@end


@interface UIButton (PPSymbol)

/// Applies a symbol (or template image fallback) to a system button.
/// If the image is a symbol, uses preferredSymbolConfiguration. Otherwise sizes via constraints.
- (void)pp_setSymbolNamed:(NSString *)name
                pointSize:(CGFloat)pointSize
                   weight:(UIImageSymbolWeight)weight
                    scale:(UIImageSymbolScale)scale
                     tint:(UIColor *)tint
                  palette:(NSArray<UIColor *> * _Nullable)palette;

/// Nice circular style used across your app (diameter auto → make a circle).
- (void)pp_setCircularStyleWithDiameter:(CGFloat)diameter
                             background:(UIColor *)background
                                   tint:(UIColor *)tint;

@end

NS_ASSUME_NONNULL_END
