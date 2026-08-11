#import <UIKit/UIKit.h>

NS_INLINE UIColor *PPMarketplaceHeroCardResolvedColor(UIColor *color, UITraitCollection *traitCollection)
{
    if (!color) {
        return UIColor.clearColor;
    }
    if (@available(iOS 13.0, *)) {
        return [color resolvedColorWithTraitCollection:(traitCollection ?: [UITraitCollection currentTraitCollection])];
    }
    return color;
}

NS_INLINE UIColor *PPMarketplaceHeroCardBlend(UIColor *baseColor,
                                              UIColor *overlayColor,
                                              CGFloat amount,
                                              UITraitCollection *traitCollection)
{
    UIColor *base = PPMarketplaceHeroCardResolvedColor(baseColor, traitCollection);
    UIColor *overlay = PPMarketplaceHeroCardResolvedColor(overlayColor, traitCollection);

    CGFloat baseRed = 0.0;
    CGFloat baseGreen = 0.0;
    CGFloat baseBlue = 0.0;
    CGFloat baseAlpha = 0.0;
    CGFloat overlayRed = 0.0;
    CGFloat overlayGreen = 0.0;
    CGFloat overlayBlue = 0.0;
    CGFloat overlayAlpha = 0.0;
    if (![base getRed:&baseRed green:&baseGreen blue:&baseBlue alpha:&baseAlpha] ||
        ![overlay getRed:&overlayRed green:&overlayGreen blue:&overlayBlue alpha:&overlayAlpha]) {
        return baseColor ?: overlayColor ?: UIColor.clearColor;
    }

    CGFloat t = MIN(MAX(amount, 0.0), 1.0);
    return [UIColor colorWithRed:(baseRed * (1.0 - t)) + (overlayRed * t)
                           green:(baseGreen * (1.0 - t)) + (overlayGreen * t)
                            blue:(baseBlue * (1.0 - t)) + (overlayBlue * t)
                           alpha:(baseAlpha * (1.0 - t)) + (overlayAlpha * t)];
}

NS_INLINE UIColor *PPMarketplaceHeroCardAccentColor(void)
{
    return [UIColor ppPrimary];
}

NS_INLINE UIColor *PPMarketplaceHeroCardSurfaceBaseColor(UITraitCollection *traitCollection)
{
    return PPMarketplaceHeroCardResolvedColor([UIColor ppElevatedSurface], traitCollection);
}

NS_INLINE UIColor *PPMarketplaceHeroCardSurfaceHighlightColor(UITraitCollection *traitCollection)
{
    BOOL dark = NO;
    if (@available(iOS 13.0, *)) {
        dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return PPMarketplaceHeroCardBlend(PPMarketplaceHeroCardSurfaceBaseColor(traitCollection),
                                      UIColor.whiteColor,
                                      dark ? 0.08 : 0.20,
                                      traitCollection);
}

NS_INLINE UIColor *PPMarketplaceHeroCardSurfaceTintColor(UITraitCollection *traitCollection)
{
    BOOL dark = NO;
    if (@available(iOS 13.0, *)) {
        dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return PPMarketplaceHeroCardBlend(PPMarketplaceHeroCardSurfaceBaseColor(traitCollection),
                                      PPMarketplaceHeroCardAccentColor(),
                                      dark ? 0.11 : 0.045,
                                      traitCollection);
}

NS_INLINE UIColor *PPMarketplaceHeroCardSurfaceTailColor(UITraitCollection *traitCollection)
{
    BOOL dark = NO;
    if (@available(iOS 13.0, *)) {
        dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return PPMarketplaceHeroCardBlend(PPMarketplaceHeroCardSurfaceTintColor(traitCollection),
                                      PPMarketplaceHeroCardAccentColor(),
                                      dark ? 0.08 : 0.03,
                                      traitCollection);
}

NS_INLINE UIColor *PPMarketplaceHeroCardStrokeColor(UITraitCollection *traitCollection)
{
    BOOL dark = NO;
    if (@available(iOS 13.0, *)) {
        dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return [UIColor.whiteColor colorWithAlphaComponent:(dark ? 0.12 : 0.78)];
}

NS_INLINE BOOL PPMarketplaceHeroCardIsDark(UITraitCollection *traitCollection)
{
    if (@available(iOS 13.0, *)) {
        return (traitCollection ?: UITraitCollection.currentTraitCollection).userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

NS_INLINE UIColor *PPMarketplaceHeroCardBackgroundAccentColor(UIColor *accentColor,
                                                              UITraitCollection *traitCollection)
{
    BOOL dark = PPMarketplaceHeroCardIsDark(traitCollection);
    UIColor *surfaceBase = PPMarketplaceHeroCardSurfaceBaseColor(traitCollection);
    return PPMarketplaceHeroCardBlend(accentColor ?: PPMarketplaceHeroCardAccentColor(),
                                      surfaceBase,
                                      dark ? 0.12 : 0.18,
                                      traitCollection);
}

NS_INLINE UIColor *PPMarketplaceHeroCardSurfaceTintColorForAccent(UIColor *accentColor,
                                                                  UITraitCollection *traitCollection)
{
    BOOL dark = PPMarketplaceHeroCardIsDark(traitCollection);
    UIColor *surfaceBase = PPMarketplaceHeroCardSurfaceBaseColor(traitCollection);
    UIColor *backgroundAccent = PPMarketplaceHeroCardBackgroundAccentColor(accentColor, traitCollection);
    return PPMarketplaceHeroCardBlend(surfaceBase,
                                      backgroundAccent,
                                      dark ? 0.095 : 0.038,
                                      traitCollection);
}

NS_INLINE UIColor *PPMarketplaceHeroCardSurfaceTailColorForAccent(UIColor *accentColor,
                                                                  UITraitCollection *traitCollection)
{
    BOOL dark = PPMarketplaceHeroCardIsDark(traitCollection);
    UIColor *surfaceTint = PPMarketplaceHeroCardSurfaceTintColorForAccent(accentColor, traitCollection);
    UIColor *backgroundAccent = PPMarketplaceHeroCardBackgroundAccentColor(accentColor, traitCollection);
    return PPMarketplaceHeroCardBlend(surfaceTint,
                                      backgroundAccent,
                                      dark ? 0.062 : 0.024,
                                      traitCollection);
}

NS_INLINE UIColor *PPMarketplaceHeroCardSupportGlowColor(UIColor *accentColor,
                                                         UITraitCollection *traitCollection)
{
    BOOL dark = PPMarketplaceHeroCardIsDark(traitCollection);
    UIColor *backgroundAccent = PPMarketplaceHeroCardBackgroundAccentColor(accentColor, traitCollection);
    return PPMarketplaceHeroCardBlend(backgroundAccent,
                                      [UIColor ppQuickActionServices],
                                      dark ? 0.18 : 0.22,
                                      traitCollection);
}

NS_INLINE void PPMarketplaceHeroCardApplySurfaceChrome(UIView *view,
                                                       CGFloat cornerRadius,
                                                       UITraitCollection *traitCollection)
{
    if (!view) {
        return;
    }

    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = cornerRadius;
    if (@available(iOS 13.0, *)) {
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = PPMarketplaceHeroCardStrokeColor(traitCollection).CGColor;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.08f;
    view.layer.shadowRadius = 20.0f;
    view.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    view.layer.masksToBounds = NO;
}

NS_INLINE void PPMarketplaceHeroCardConfigureSurfaceGradient(CAGradientLayer *gradientLayer,
                                                             UIColor *accentColor,
                                                             UITraitCollection *traitCollection,
                                                             BOOL isRTL)
{
    if (!gradientLayer) {
        return;
    }

    BOOL dark = PPMarketplaceHeroCardIsDark(traitCollection);
    UIColor *surfaceHighlight = PPMarketplaceHeroCardSurfaceHighlightColor(traitCollection);
    UIColor *surfaceTint = PPMarketplaceHeroCardSurfaceTintColorForAccent(accentColor, traitCollection);
    UIColor *surfaceTail = PPMarketplaceHeroCardSurfaceTailColorForAccent(accentColor, traitCollection);
    gradientLayer.opacity = dark ? 0.90 : 0.72;
    gradientLayer.colors = @[
        (id)PPMarketplaceHeroCardResolvedColor(surfaceHighlight, traitCollection).CGColor,
        (id)PPMarketplaceHeroCardResolvedColor(surfaceTint, traitCollection).CGColor,
        (id)PPMarketplaceHeroCardResolvedColor(surfaceTail, traitCollection).CGColor
    ];
    gradientLayer.locations = @[@0.0, @0.56, @1.0];
    gradientLayer.startPoint = isRTL ? CGPointMake(1.0, 0.0) : CGPointMake(0.0, 0.0);
    gradientLayer.endPoint = isRTL ? CGPointMake(0.0, 1.0) : CGPointMake(1.0, 1.0);
}

NS_INLINE UIColor *PPMarketplaceHeroCardTopAccentColor(UITraitCollection *traitCollection)
{
    (void)traitCollection;
    return [PPMarketplaceHeroCardAccentColor() colorWithAlphaComponent:0.58];
}

NS_INLINE UIColor *PPMarketplaceHeroCardOrbColor(UITraitCollection *traitCollection)
{
    BOOL dark = NO;
    if (@available(iOS 13.0, *)) {
        dark = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return [PPMarketplaceHeroCardAccentColor() colorWithAlphaComponent:(dark ? 0.15 : 0.10)];
}

NS_INLINE UIColor *PPMarketplaceHeroCardPrimaryTextColor(void)
{
    return [UIColor ppTextPrimary];
}

NS_INLINE UIColor *PPMarketplaceHeroCardSecondaryTextColor(void)
{
    return [UIColor ppTextSecondary];
}
