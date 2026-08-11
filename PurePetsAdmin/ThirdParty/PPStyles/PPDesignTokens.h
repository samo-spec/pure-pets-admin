//
//  PPDesignTokens.h
//  Pure Pets Admin
//
//  The Admin UIKit token surface mirrors the consumer iOS PPDesignTokens
//  contract.  Color values are implemented in PPDesignTokens.m; this header
//  exposes the semantic UIKit bridge plus the legacy names used by the
//  existing Admin controllers.
//

#ifndef PPDesignTokens_h
#define PPDesignTokens_h

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Canonical semantic UIKit colors

/// These class properties are the Admin app's single runtime color source.
/// Their light/dark values intentionally match the consumer iOS design system.
@interface UIColor (PPDesignTokens)

@property (class, nonatomic, readonly) UIColor *ppPrimary;
@property (class, nonatomic, readonly) UIColor *ppBrandPrimary;
@property (class, nonatomic, readonly) UIColor *ppPressedAction;
@property (class, nonatomic, readonly) UIColor *ppPrimaryDarker;
@property (class, nonatomic, readonly) UIColor *ppPrimaryShiner;
@property (class, nonatomic, readonly) UIColor *ppPremiumAccent;
@property (class, nonatomic, readonly) UIColor *ppDiscount;
@property (class, nonatomic, readonly) UIColor *ppAccent;
@property (class, nonatomic, readonly) UIColor *ppAccentText;
@property (class, nonatomic, readonly) UIColor *ppQuickActionShopping;
@property (class, nonatomic, readonly) UIColor *ppQuickActionAnimals;
@property (class, nonatomic, readonly) UIColor *ppQuickActionServices;
@property (class, nonatomic, readonly) UIColor *ppCareAccent;
@property (class, nonatomic, readonly) UIColor *ppAdoptionAccent;
@property (class, nonatomic, readonly) UIColor *ppQuickActionCommunity;
@property (class, nonatomic, readonly) UIColor *ppQuickActionAdoption;

@property (class, nonatomic, readonly) UIColor *ppBackground;
@property (class, nonatomic, readonly) UIColor *ppSurfaceBase;
@property (class, nonatomic, readonly) UIColor *ppSurface;
@property (class, nonatomic, readonly) UIColor *ppSurfaceRaised;
@property (class, nonatomic, readonly) UIColor *ppElevatedSurface;
@property (class, nonatomic, readonly) UIColor *ppSurfaceElevated;
@property (class, nonatomic, readonly) UIColor *ppSurfaceOverlay;
@property (class, nonatomic, readonly) UIColor *ppSurfaceBorder;
@property (class, nonatomic, readonly) UIColor *ppSecondarySurface;
@property (class, nonatomic, readonly) UIColor *ppForeground;
@property (class, nonatomic, readonly) UIColor *ppCard;
@property (class, nonatomic, readonly) UIColor *ppWarmPorcelain;
@property (class, nonatomic, readonly) UIColor *ppMineralBeige;
@property (class, nonatomic, readonly) UIColor *ppSoftRose;
@property (class, nonatomic, readonly) UIColor *ppQuietLilac;
@property (class, nonatomic, readonly) UIColor *ppSeparator;
@property (class, nonatomic, readonly) UIColor *ppBorder;

@property (class, nonatomic, readonly) UIColor *ppTextPrimary;
@property (class, nonatomic, readonly) UIColor *ppTextSecondary;
@property (class, nonatomic, readonly) UIColor *ppTextTertiary;

@property (class, nonatomic, readonly) UIColor *ppSuccess;
@property (class, nonatomic, readonly) UIColor *ppWarning;
@property (class, nonatomic, readonly) UIColor *ppError;
@property (class, nonatomic, readonly) UIColor *ppInfo;

/// Semantic shadow color used by the shared UIKit shadow helpers.
@property (class, nonatomic, readonly) UIColor *ppShadow;

@end

static inline UIColor * _Nonnull pp_canvasColor(void) {
    return [UIColor ppBackground];
}

#pragma mark - Spacing (8pt Grid)

#define PPSpaceXXS       2.0f
#define PPSpaceXS        4.0f
#define PPSpaceSM        8.0f
#define PPSpaceMD        12.0f
#define PPSpaceMDHalf    6.0f
#define PPSpaceBase      16.0f
#define PPSpaceLG        20.0f
#define PPSpaceXL        24.0f
#define PPSpaceXXL       32.0f
#define PPSpaceXXXL      40.0f
#define PPSpace4XL       48.0f

#define PPScreenMargin   20.0f

#pragma mark - Corner Radii

#define PPCornerSmall    12.0f
#define PPCorner16       16.0f
#define PPCornerMedium   18.0f
#define PPCornerCard     22.0f
#define PPCornerHero     32.0f
#define PPCornerLarge    42.0f
#define PPCornerPill     9999.0f

#pragma mark - Typography Scale (Beiruti via GM helpers)

// GM.boldFontWithSize: adds +1pt internally, so these values match the
// consumer iOS target sizes after the helper's adjustment.
#define PPFontLargeTitle   33.0f
#define PPFontTitle1       27.0f
#define PPFontTitle2       21.0f
#define PPFontTitle3       18.0f
#define PPFontHeadline     16.0f
#define PPFontBody         16.0f
#define PPFontCallout      15.0f
#define PPFontSubheadline  14.0f
#define PPFontFootnote     12.0f
#define PPFontCaption1     11.0f
#define PPFontCaption2     10.0f

#pragma mark - Touch Targets (Apple HIG)

#define PPTouchTargetMin   44.0f
#define PPButtonHeightLG   52.0f
#define PPButtonHeightMD   48.0f
#define PPButtonHeightSM   44.0f
#define PPButtonHeightXS   36.0f

#pragma mark - Shadow Presets

#define PPShadowCardRadius       24.0f
#define PPShadowCardOffsetY      8.0f
#define PPShadowCardOpacity      0.06f

#define PPShadowElevatedRadius   24.0f
#define PPShadowElevatedOffsetY  14.0f
#define PPShadowElevatedOpacity  0.12f

#define PPShadowButtonRadius     12.0f
#define PPShadowButtonOffsetY    6.0f
#define PPShadowButtonOpacity    0.15f

#define PPShadowSubtleRadius     8.0f
#define PPShadowSubtleOffsetY    2.0f
#define PPShadowSubtleOpacity    0.04f

#pragma mark - Animation Constants

#define PPAnimDurationFast       0.12
#define PPAnimDurationNormal     0.25
#define PPAnimDurationSlow       0.4
#define PPAnimSpringDamping      0.75
#define PPAnimSpringVelocity     0.8

#define PPTapScaleDown           0.96
#define PPTapCardScaleDown       0.98

#pragma mark - Semantic color aliases

// These functions preserve source compatibility for older Admin screens.
// They deliberately contain no palette values; every result resolves through
// the UIColor (PPDesignTokens) bridge above.
static inline UIColor *PPPrimaryColor(void)             { return [UIColor ppPrimary]; }
static inline UIColor *PPPrimaryPressedColor(void)      { return [UIColor ppPressedAction]; }
static inline UIColor *PPPrimaryContainerColor(void)    { return [UIColor ppPrimaryShiner]; }
static inline UIColor *PPOnPrimaryColor(void)           { return UIColor.whiteColor; }
static inline UIColor *PPBackgroundColor(void)          { return [UIColor ppBackground]; }
static inline UIColor *PPSurfaceColor(void)             { return [UIColor ppSurface]; }
static inline UIColor *PPElevatedSurfaceColor(void)     { return [UIColor ppElevatedSurface]; }
static inline UIColor *PPTextPrimaryColor(void)         { return [UIColor ppTextPrimary]; }
static inline UIColor *PPTextSecondaryColor(void)       { return [UIColor ppTextSecondary]; }
static inline UIColor *PPTextTertiaryColor(void)        { return [UIColor ppTextTertiary]; }
static inline UIColor *PPHairlineColor(void)            { return [UIColor ppSurfaceBorder]; }
static inline UIColor *PPLiquidBorderColor(void)        { return [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.82]; }
static inline UIColor *PPGoldAccentColor(void)          { return [UIColor ppPremiumAccent]; }
static inline UIColor *PPSecondaryAccentColor(void)     { return [UIColor ppQuickActionServices]; }
static inline UIColor *PPCriticalColor(void)            { return [UIColor ppError]; }
static inline UIColor *PPDisabledFillColor(void)        { return [UIColor ppSecondarySurface]; }
static inline UIColor *PPDisabledContentColor(void)      { return [UIColor ppTextTertiary]; }
static inline UIColor *PPNavigationBarColor(void)       { return [UIColor ppSurface]; }
static inline UIColor *PPCardColor(void)                 { return [UIColor ppCard]; }
static inline UIColor *PPButtonFillColor(void)           { return [UIColor ppPrimary]; }
static inline UIColor *PPButtonTitleColor(void)          { return UIColor.whiteColor; }
static inline UIColor *PPInputBackgroundColor(void)      { return [UIColor ppSurface]; }
static inline UIColor *PPInputBorderColor(void)          { return [UIColor ppSurfaceBorder]; }
static inline UIColor *PPTabSelectedColor(void)          { return [UIColor ppPrimary]; }
static inline UIColor *PPTabUnselectedColor(void)        { return [UIColor ppTextTertiary]; }

// Compatibility names from the removed Admin maroon palette.  They are now
// semantic aliases, not a second color scale.
static inline UIColor *PPSoftIvoryColor(void)            { return [UIColor ppSurfaceOverlay]; }
static inline UIColor *PPDeepCharcoalColor(void)         { return [UIColor ppShadow]; }
static inline UIColor *PPWarmSandColor(void)             { return [UIColor ppMineralBeige]; }
static inline UIColor *PPMutedGoldColor(void)            { return [UIColor ppPremiumAccent]; }
static inline UIColor *PPSageAccentColor(void)           { return [UIColor ppSuccess]; }
static inline UIColor *PPCoolGrayColor(void)             { return [UIColor ppSecondarySurface]; }

#pragma mark - Admin compatibility macros

#ifndef AppBackgroundClrShiner
#define AppBackgroundClrShiner         [UIColor ppElevatedSurface]
#endif
#ifndef AppBackgroundClrDarker
#define AppBackgroundClrDarker         [UIColor ppWarmPorcelain]
#endif
#ifndef AppPrimaryClr
#define AppPrimaryClr                  [UIColor ppPrimary]
#endif
#ifndef AppPrimaryClrDarker
#define AppPrimaryClrDarker            [UIColor ppPressedAction]
#endif
#ifndef AppPrimaryClrShiner
#define AppPrimaryClrShiner            [UIColor ppPrimaryShiner]
#endif
#ifndef AppSecondaryClr
#define AppSecondaryClr                [UIColor ppQuickActionServices]
#endif
#ifndef AppBackgroundClr
#define AppBackgroundClr               [UIColor ppBackground]
#endif
#ifndef AppPrimaryTextClr
#define AppPrimaryTextClr              [UIColor ppTextPrimary]
#endif
#ifndef AppSecondaryTextClr
#define AppSecondaryTextClr            [UIColor ppTextSecondary]
#endif
#ifndef PrimaryTextClr
#define PrimaryTextClr                 [UIColor ppTextPrimary]
#endif
#ifndef SeconderyTextClr
#define SeconderyTextClr               [UIColor ppTextSecondary]
#endif
#ifndef AppForgroundColr
#define AppForgroundColr               [UIColor ppElevatedSurface]
#endif
#ifndef AppShadowColor
#define AppShadowColor                 [UIColor ppShadow]
#endif
#ifndef AppShadowClr
#define AppShadowClr                   AppShadowColor
#endif
#ifndef AppClearClr
#define AppClearClr                    [UIColor clearColor]
#endif
#ifndef AppPrimaryClr_CG
#define AppPrimaryClr_CG               AppPrimaryClr.CGColor
#endif
#ifndef AppPrimaryClrWithAlpha
#define AppPrimaryClrWithAlpha(alpha)  [AppPrimaryClr colorWithAlphaComponent:(alpha)]
#endif

#ifndef AppTertiaryTextClr
#define AppTertiaryTextClr             [UIColor ppTextTertiary]
#endif
#ifndef AppPlaceholderTextClr
#define AppPlaceholderTextClr          [UIColor ppTextTertiary]
#endif
#ifndef AppSuccessClr
#define AppSuccessClr                  [UIColor ppSuccess]
#endif
#ifndef AppWarningClr
#define AppWarningClr                  [UIColor ppWarning]
#endif
#ifndef AppErrorClr
#define AppErrorClr                    [UIColor ppError]
#endif
#ifndef AppInfoClr
#define AppInfoClr                     [UIColor ppInfo]
#endif

#pragma mark - Gradient tokens

#define PPGradientHeroStart            [UIColor ppPrimary]
#define PPGradientHeroMid              [UIColor ppPrimaryShiner]
#define PPGradientHeroEnd              [UIColor ppPressedAction]
#define PPGradientCardStart            [UIColor ppElevatedSurface]
#define PPGradientCardEnd              [UIColor ppWarmPorcelain]
#define PPGradientOverlayStart         [[UIColor ppShadow] colorWithAlphaComponent:0.0]
#define PPGradientOverlayEnd           [[UIColor ppShadow] colorWithAlphaComponent:0.65]

#pragma mark - Convenience helpers

static inline CALayer *PPLayerForDesignTokenTarget(id target) {
    if ([target isKindOfClass:[UIView class]]) {
        return ((UIView *)target).layer;
    }
    if ([target isKindOfClass:[CALayer class]]) {
        return (CALayer *)target;
    }
    return nil;
}

static inline void PPApplyCardShadow(id target) {
    CALayer *layer = PPLayerForDesignTokenTarget(target);
    if (!layer) { return; }
    layer.shadowColor = [UIColor ppShadow].CGColor;
    layer.shadowOpacity = PPShadowCardOpacity;
    layer.shadowRadius = PPShadowCardRadius;
    layer.shadowOffset = CGSizeMake(0, PPShadowCardOffsetY);
}

static inline void PPApplyElevatedShadow(id target) {
    CALayer *layer = PPLayerForDesignTokenTarget(target);
    if (!layer) { return; }
    layer.shadowColor = [UIColor ppShadow].CGColor;
    layer.shadowOpacity = PPShadowElevatedOpacity;
    layer.shadowRadius = PPShadowElevatedRadius;
    layer.shadowOffset = CGSizeMake(0, PPShadowElevatedOffsetY);
}

static inline void PPApplyButtonShadow(id target) {
    CALayer *layer = PPLayerForDesignTokenTarget(target);
    if (!layer) { return; }
    layer.shadowColor = [UIColor ppShadow].CGColor;
    layer.shadowOpacity = PPShadowButtonOpacity;
    layer.shadowRadius = PPShadowButtonRadius;
    layer.shadowOffset = CGSizeMake(0, PPShadowButtonOffsetY);
}

static inline void PPApplyContinuousCorners(id target, CGFloat radius) {
    CALayer *layer = PPLayerForDesignTokenTarget(target);
    if (!layer) { return; }
    layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static inline void PPTapFeedbackDown(UIView *view) {
    [UIView animateWithDuration:PPAnimDurationFast
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        view.transform = CGAffineTransformMakeScale(PPTapScaleDown, PPTapScaleDown);
    } completion:nil];
}

static inline void PPTapFeedbackUp(UIView *view) {
    [UIView animateWithDuration:PPAnimDurationNormal
                          delay:0
         usingSpringWithDamping:PPAnimSpringDamping
          initialSpringVelocity:PPAnimSpringVelocity
                        options:0
                     animations:^{
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}

NS_ASSUME_NONNULL_END

#endif /* PPDesignTokens_h */
