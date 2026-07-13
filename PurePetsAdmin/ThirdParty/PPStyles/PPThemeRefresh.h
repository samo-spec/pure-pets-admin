//
//  PPThemeRefresh.h
//  Pure Pets
//
//  Automatic dark/light theme refresh for the entire view hierarchy.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PPThemeDidChangeNotification;

#pragma mark - UIView+PPTheme

@interface UIView (PPTheme)

- (void)pp_setBorderColor:(nullable UIColor *)color;
- (void)pp_setShadowColor:(nullable UIColor *)color;
- (void)pp_resolveLayerColors;
- (void)pp_resolveLayerColorsRecursively;

@end

#pragma mark - UIViewController+PPTheme

@interface UIViewController (PPTheme)

- (void)pp_refreshThemeColors;

@end

NS_ASSUME_NONNULL_END
