//
//  PurePetsColorPattle.h
//  Pure Pets Admin
//
//  Qatar Maroon–based mobile application palette.
//  Header-only and ready to use from Objective-C / Objective-C++.
//

#ifndef PurePetsColorPattle_h
#define PurePetsColorPattle_h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Core Helpers

static inline UIColor *PPColorFromRGB(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

static inline UIColor *PPDynamicColor(uint32_t lightRGB,
                                      uint32_t darkRGB,
                                      CGFloat lightAlpha,
                                      CGFloat darkAlpha) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
            return PPColorFromRGB(dark ? darkRGB : lightRGB,
                                  dark ? darkAlpha : lightAlpha);
        }];
    }

    return PPColorFromRGB(lightRGB, lightAlpha);
}

#pragma mark - Qatar Maroon Scale

/// #F4DCE2
static inline UIColor *PPMaroon100Color(void) {
    return PPColorFromRGB(0xF4DCE2, 1.0);
}

/// #E3A9B7
static inline UIColor *PPMaroon200Color(void) {
    return PPColorFromRGB(0xE3A9B7, 1.0);
}

/// #CF788D
static inline UIColor *PPMaroon300Color(void) {
    return PPColorFromRGB(0xCF788D, 1.0);
}

/// #B84C68
static inline UIColor *PPMaroon400Color(void) {
    return PPColorFromRGB(0xB84C68, 1.0);
}

/// #A12C4D
static inline UIColor *PPMaroon500Color(void) {
    return PPColorFromRGB(0xA12C4D, 1.0);
}

/// Official Qatar maroon — #8A1538
static inline UIColor *PPMaroon600Color(void) {
    return PPColorFromRGB(0x8A1538, 1.0);
}

/// #73112E
static inline UIColor *PPMaroon700Color(void) {
    return PPColorFromRGB(0x73112E, 1.0);
}

/// #66102A
static inline UIColor *PPMaroon800Color(void) {
    return PPColorFromRGB(0x66102A, 1.0);
}

/// #4F0B20
static inline UIColor *PPMaroon900Color(void) {
    return PPColorFromRGB(0x4F0B20, 1.0);
}

#pragma mark - Supporting Palette

/// Soft Ivory — #FFF8F5
static inline UIColor *PPSoftIvoryColor(void) {
    return PPColorFromRGB(0xFFF8F5, 1.0);
}

/// Deep Charcoal — #1F2328
static inline UIColor *PPDeepCharcoalColor(void) {
    return PPColorFromRGB(0x1F2328, 1.0);
}

/// Warm Sand — #D9C2B0
static inline UIColor *PPWarmSandColor(void) {
    return PPColorFromRGB(0xD9C2B0, 1.0);
}

/// Muted Gold — #C9A35E
static inline UIColor *PPMutedGoldColor(void) {
    return PPColorFromRGB(0xC9A35E, 1.0);
}

/// Sage Accent — #8FA89A
static inline UIColor *PPSageAccentColor(void) {
    return PPColorFromRGB(0x8FA89A, 1.0);
}

/// Cool Gray — #E8EAED
static inline UIColor *PPCoolGrayColor(void) {
    return PPColorFromRGB(0xE8EAED, 1.0);
}

#pragma mark - Semantic Brand Colors

/// Main interactive brand color.
/// Light: #8A1538 | Dark: #CF788D
static inline UIColor *PPPrimaryColor(void) {
    return PPDynamicColor(0x8A1538, 0xCF788D, 1.0, 1.0);
}

/// Pressed/high-emphasis brand color.
/// Light: #73112E | Dark: #E3A9B7
static inline UIColor *PPPrimaryPressedColor(void) {
    return PPDynamicColor(0x73112E, 0xE3A9B7, 1.0, 1.0);
}

/// Subtle brand tint.
/// Light: #F4DCE2 | Dark: #4F0B20
static inline UIColor *PPPrimaryContainerColor(void) {
    return PPDynamicColor(0xF4DCE2, 0x4F0B20, 1.0, 1.0);
}

/// Foreground placed on PPPrimaryColor.
static inline UIColor *PPOnPrimaryColor(void) {
    return UIColor.whiteColor;
}

/// Main application background aligned to the Admin dashboard canvas.
/// Light: #F2F2F2 | Dark: #1C1C1E
static inline UIColor *PPBackgroundColor(void) {
    return PPDynamicColor(0xF2F2F2, 0x1C1C1E, 1.0, 1.0);
}

/// Standard card/surface color.
/// Light: #FFFFFF | Dark: #1B211E
static inline UIColor *PPSurfaceColor(void) {
    return PPDynamicColor(0xFFFFFF, 0x1B211E, 1.0, 1.0);
}

/// Elevated card/control surface.
/// Light: #FFFFFF | Dark: #242C28
static inline UIColor *PPElevatedSurfaceColor(void) {
    return PPDynamicColor(0xFFFFFF, 0x242C28, 1.0, 1.0);
}

/// Primary text/icon color.
/// Light: #1F2328 | Dark: #FFF8F5
static inline UIColor *PPTextPrimaryColor(void) {
    return PPDynamicColor(0x1F2328, 0xFFF8F5, 1.0, 1.0);
}

/// Secondary text/icon color.
/// Light: #5F6763 | Dark: #C8D0CC
static inline UIColor *PPTextSecondaryColor(void) {
    return PPDynamicColor(0x5F6763, 0xC8D0CC, 1.0, 1.0);
}

/// Tertiary/placeholder text.
/// Light: #7D8581 | Dark: #9FAAA4
static inline UIColor *PPTextTertiaryColor(void) {
    return PPDynamicColor(0x7D8581, 0x9FAAA4, 1.0, 1.0);
}

/// Fine separators and card outlines.
/// Light: #D9C2B0 at 45% | Dark: white at 12%
static inline UIColor *PPHairlineColor(void) {
    return PPDynamicColor(0xD9C2B0, 0xFFFFFF, 0.45, 0.12);
}

/// Glass/liquid card border.
/// Light: white at 82% | Dark: white at 15%
static inline UIColor *PPLiquidBorderColor(void) {
    return PPDynamicColor(0xFFFFFF, 0xFFFFFF, 0.82, 0.15);
}

/// Premium accent.
static inline UIColor *PPGoldAccentColor(void) {
    return PPMutedGoldColor();
}

/// Calm secondary accent.
static inline UIColor *PPSecondaryAccentColor(void) {
    return PPSageAccentColor();
}

/// Destructive / critical action.
/// Light: #A12C4D | Dark: #E3A9B7
static inline UIColor *PPCriticalColor(void) {
    return PPDynamicColor(0xA12C4D, 0xE3A9B7, 1.0, 1.0);
}

/// Disabled fill.
/// Light: #E8EAED | Dark: #303834
static inline UIColor *PPDisabledFillColor(void) {
    return PPDynamicColor(0xE8EAED, 0x303834, 1.0, 1.0);
}

/// Disabled text/icon.
/// Light: #8E9491 | Dark: #78817D
static inline UIColor *PPDisabledContentColor(void) {
    return PPDynamicColor(0x8E9491, 0x78817D, 1.0, 1.0);
}

#pragma mark - Common Component Colors

static inline UIColor *PPNavigationBarColor(void) {
    return PPSurfaceColor();
}

static inline UIColor *PPCardColor(void) {
    return PPSurfaceColor();
}

static inline UIColor *PPButtonFillColor(void) {
    return PPPrimaryColor();
}

static inline UIColor *PPButtonTitleColor(void) {
    return PPOnPrimaryColor();
}

static inline UIColor *PPInputBackgroundColor(void) {
    return PPDynamicColor(0xFFFFFF, 0x1B211E, 0.92, 0.94);
}

static inline UIColor *PPInputBorderColor(void) {
    return PPHairlineColor();
}

static inline UIColor *PPTabSelectedColor(void) {
    return PPPrimaryColor();
}

static inline UIColor *PPTabUnselectedColor(void) {
    return PPTextTertiaryColor();
}

NS_ASSUME_NONNULL_END

#endif /* PurePetsColorPattle_h */
