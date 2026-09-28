//
//  PPDesignTokens.m
//  Pure Pets Admin
//
//  Objective-C implementation of the semantic UIKit bridge shared with the
//  consumer iOS design system.  Keep palette values here; callers should use
//  UIColor.pp* or the compatibility aliases in PPDesignTokens.h.
//

#import "PPDesignTokens.h"

static UIColor *PPDesignTokenColorFromHex(uint32_t hex, CGFloat alpha)
{
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

static UIColor *PPDesignTokenDynamicColor(UIColor *lightColor,
                                          UIColor *darkColor)
{
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? darkColor : lightColor;
        }];
    }
    return lightColor;
}

static UIColor *PPDesignTokenDynamicHex(uint32_t lightHex,
                                        uint32_t darkHex,
                                        CGFloat lightAlpha,
                                        CGFloat darkAlpha)
{
    return PPDesignTokenDynamicColor(PPDesignTokenColorFromHex(lightHex, lightAlpha),
                                     PPDesignTokenColorFromHex(darkHex, darkAlpha));
}

@implementation UIColor (PPDesignTokens)

#pragma mark - Brand and action

+ (UIColor *)ppPrimary
{
    return PPDesignTokenDynamicHex(0xCB2654, 0xCB2654, 1.0, 1.0);
}

+ (UIColor *)ppBrandPrimary
{
    return [UIColor ppPrimary];
}

+ (UIColor *)ppPressedAction
{
    return PPDesignTokenDynamicHex(0xA91E46, 0xA91E46, 1.0, 1.0);
}

+ (UIColor *)ppPrimaryDarker
{
    return [UIColor ppPressedAction];
}

+ (UIColor *)ppPrimaryShiner
{
    return PPDesignTokenDynamicHex(0xF6E2E8, 0x2A1C22, 1.0, 1.0);
}

+ (UIColor *)ppPremiumAccent
{
    return PPDesignTokenDynamicHex(0xE6C87D, 0xE6C87D, 1.0, 1.0);
}

+ (UIColor *)ppDiscount
{
    return PPDesignTokenDynamicHex(0xD63A50, 0xD63A50, 1.0, 1.0);
}

+ (UIColor *)ppAccent
{
    return [UIColor ppPrimary];
}

+ (UIColor *)ppAccentText
{
    return PPDesignTokenDynamicHex(0xCB2654, 0xFB7185, 1.0, 1.0);
}

+ (UIColor *)ppQuickActionShopping
{
    return PPDesignTokenDynamicHex(0xD14A61, 0xDF6A7D, 1.0, 1.0);
}

+ (UIColor *)ppQuickActionAnimals
{
    return PPDesignTokenDynamicHex(0x9E5CAD, 0xB881C2, 1.0, 1.0);
}

+ (UIColor *)ppQuickActionServices
{
    return PPDesignTokenDynamicHex(0x47929C, 0x64AAB0, 1.0, 1.0);
}

+ (UIColor *)ppCareAccent
{
    return [UIColor ppQuickActionServices];
}

+ (UIColor *)ppAdoptionAccent
{
    return [UIColor ppQuickActionAnimals];
}

+ (UIColor *)ppQuickActionCommunity
{
    return PPDesignTokenDynamicHex(0x618CB8, 0x7CA0C6, 1.0, 1.0);
}

+ (UIColor *)ppQuickActionAdoption
{
    return PPDesignTokenDynamicHex(0xD17F63, 0xDB9278, 1.0, 1.0);
}

#pragma mark - Surfaces and fields

+ (UIColor *)ppBackground
{
    return PPDesignTokenDynamicHex(0xF8F8F9, 0x000000, 1.0, 1.0);
}

+ (UIColor *)ppBackgroundSecondary
{
    return [self ppSecondarySurface];
}

+ (UIColor *)ppSurfaceBase
{
    return [UIColor ppBackground];
}

+ (UIColor *)ppSurface
{
    return PPDesignTokenDynamicHex(0xFFFFFF, 0x141416, 1.0, 1.0);
}

+ (UIColor *)ppSurfaceRaised
{
    return [UIColor ppSurface];
}

+ (UIColor *)ppElevatedSurface
{
    return PPDesignTokenDynamicHex(0xFFFDFC, 0x1C1C20, 1.0, 1.0);
}

+ (UIColor *)ppSurfaceElevated
{
    return [UIColor ppElevatedSurface];
}

+ (UIColor *)ppSurfaceOverlay
{
    return PPDesignTokenDynamicHex(0xFDF3F6, 0x242429, 1.0, 1.0);
}

+ (UIColor *)ppSurfaceBorder
{
    return PPDesignTokenDynamicHex(0xEEDDE3, 0x2A2A30, 1.0, 1.0);
}

+ (UIColor *)ppSecondarySurface
{
    return PPDesignTokenDynamicHex(0xF7F1ED, 0x1C1C20, 1.0, 1.0);
}

+ (UIColor *)ppForeground
{
    return [UIColor ppSurface];
}

+ (UIColor *)ppCard
{
    return [UIColor ppSurface];
}

+ (UIColor *)ppWarmPorcelain
{
    return PPDesignTokenDynamicHex(0xF7F1ED, 0x1C1C20, 1.0, 1.0);
}

+ (UIColor *)ppMineralBeige
{
    return PPDesignTokenDynamicHex(0xEEE3DA, 0x18181C, 1.0, 1.0);
}

+ (UIColor *)ppSoftRose
{
    return PPDesignTokenDynamicHex(0xF6E2E8, 0x23181C, 1.0, 1.0);
}

+ (UIColor *)ppQuietLilac
{
    return PPDesignTokenDynamicHex(0xEEEAF3, 0x1B1922, 1.0, 1.0);
}

+ (UIColor *)ppSeparator
{
    return PPDesignTokenDynamicHex(0xE6DADD, 0x2A2A30, 1.0, 1.0);
}

+ (UIColor *)ppBorder
{
    return PPDesignTokenDynamicHex(0xE6DADD, 0x2A2A30, 1.0, 1.0);
}

#pragma mark - Text

+ (UIColor *)ppTextPrimary
{
    return PPDesignTokenDynamicHex(0x2A1D21, 0xF4F4F6, 1.0, 1.0);
}

+ (UIColor *)ppTextSecondary
{
    return PPDesignTokenDynamicHex(0x75666B, 0xA1A1AA, 1.0, 1.0);
}

+ (UIColor *)ppTextTertiary
{
    return PPDesignTokenDynamicHex(0x75666B, 0x71717A, 0.72, 0.72);
}

#pragma mark - Semantic system colors

+ (UIColor *)ppSuccess
{
    return PPDesignTokenDynamicColor([UIColor colorWithRed:0.204 green:0.780 blue:0.349 alpha:1.0],
                                     [UIColor colorWithRed:0.188 green:0.820 blue:0.345 alpha:1.0]);
}

+ (UIColor *)ppWarning
{
    return PPDesignTokenDynamicColor([UIColor colorWithRed:1.000 green:0.584 blue:0.000 alpha:1.0],
                                     [UIColor colorWithRed:1.000 green:0.624 blue:0.039 alpha:1.0]);
}

+ (UIColor *)ppError
{
    return PPDesignTokenDynamicColor([UIColor colorWithRed:1.000 green:0.231 blue:0.188 alpha:1.0],
                                     [UIColor colorWithRed:1.000 green:0.271 blue:0.227 alpha:1.0]);
}

+ (UIColor *)ppInfo
{
    return PPDesignTokenDynamicColor([UIColor colorWithRed:0.000 green:0.478 blue:1.000 alpha:1.0],
                                     [UIColor colorWithRed:0.039 green:0.518 blue:1.000 alpha:1.0]);
}

+ (UIColor *)ppShadow
{
    return UIColor.blackColor;
}

@end
