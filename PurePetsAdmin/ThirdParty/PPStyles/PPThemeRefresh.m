//
//  PPThemeRefresh.m
//  Pure Pets
//
//  Automatic dark/light theme refresh for the entire view hierarchy.
//

#import "PPThemeRefresh.h"
#import <objc/runtime.h>

NSNotificationName const PPThemeDidChangeNotification = @"PPThemeDidChangeNotification";

static const void *kPPDynamicBorderColorKey = &kPPDynamicBorderColorKey;
static const void *kPPDynamicShadowColorKey = &kPPDynamicShadowColorKey;

#pragma mark - UIView+PPTheme

@implementation UIView (PPTheme)

- (void)pp_setBorderColor:(nullable UIColor *)color
{
    objc_setAssociatedObject(self, kPPDynamicBorderColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (color) {
        UIColor *resolved = [color resolvedColorWithTraitCollection:self.traitCollection];
        self.layer.borderColor = resolved.CGColor;
    } else {
        self.layer.borderColor = nil;
    }
}

- (void)pp_setShadowColor:(nullable UIColor *)color
{
    objc_setAssociatedObject(self, kPPDynamicShadowColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (color) {
        UIColor *resolved = [color resolvedColorWithTraitCollection:self.traitCollection];
        self.layer.shadowColor = resolved.CGColor;
    } else {
        self.layer.shadowColor = nil;
    }
}

- (void)pp_resolveLayerColors
{
    UIColor *borderColor = objc_getAssociatedObject(self, kPPDynamicBorderColorKey);
    if (borderColor) {
        UIColor *resolved = [borderColor resolvedColorWithTraitCollection:self.traitCollection];
        self.layer.borderColor = resolved.CGColor;
    }
    UIColor *shadowColor = objc_getAssociatedObject(self, kPPDynamicShadowColorKey);
    if (shadowColor) {
        UIColor *resolved = [shadowColor resolvedColorWithTraitCollection:self.traitCollection];
        self.layer.shadowColor = resolved.CGColor;
    }
}

- (void)pp_resolveLayerColorsRecursively
{
    [self pp_resolveLayerColors];
    for (UIView *child in self.subviews) {
        [child pp_resolveLayerColorsRecursively];
    }
}

@end

#pragma mark - UIViewController+PPTheme

@implementation UIViewController (PPTheme)

- (void)pp_refreshThemeColors
{
    [self.view pp_resolveLayerColorsRecursively];

    if ([self.view isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)self.view;
        [tv reloadData];
    }
    if ([self isKindOfClass:[UITableViewController class]]) {
        [(UITableViewController *)self tableView].visibleCells;
        [[(UITableViewController *)self tableView] reloadData];
    }
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UITableView class]]) {
            [(UITableView *)subview reloadData];
        } else if ([subview isKindOfClass:[UICollectionView class]]) {
            [(UICollectionView *)subview reloadData];
        }
    }
}

@end

__attribute__((constructor))
static void PPThemeRefreshInstallSwizzle(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [UIViewController class];
        SEL originalSel = @selector(traitCollectionDidChange:);
        SEL swizzledSel = @selector(pp_swizzled_traitCollectionDidChange:);

        Method originalMethod = class_getInstanceMethod(cls, originalSel);
        Method swizzledMethod = class_getInstanceMethod(cls, swizzledSel);

        BOOL didAdd = class_addMethod(cls,
                                      originalSel,
                                      method_getImplementation(swizzledMethod),
                                      method_getTypeEncoding(swizzledMethod));
        if (didAdd) {
            class_replaceMethod(cls,
                                swizzledSel,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

@interface UIViewController (PPThemeSwizzle)
@end

@implementation UIViewController (PPThemeSwizzle)

- (void)pp_swizzled_traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [self pp_swizzled_traitCollectionDidChange:previousTraitCollection];

    if (![self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        return;
    }

    [self pp_refreshThemeColors];
}

@end
