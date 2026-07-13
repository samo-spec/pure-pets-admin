//
//  PPHero.h
//  Pure Pets
//
//  Reusable decorative glass background extracted from PPUserMenuViewController hero card.
//  Contains gradient, constellation lines, animated dots, and top accent bar.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPHeroGlassAccentStyle) {
    PPHeroGlassAccentStyleBar = 0,
    PPHeroGlassAccentStyleCornerGlow
};

/// A reusable background-only UIView that renders the premium hero glass surface
/// used behind header content across the app.
///
/// Includes:
/// - Three-stop diagonal gradient
/// - Depth gradient layer
/// - Animated constellation lines
/// - 14 animated dot particles with halos
/// - Top accent bar
/// - Continuous corner radius, border, and shadow
///
/// Does NOT contain any profile-specific content (avatar, name, labels, buttons).
///
/// Usage:
/// @code
///   PPHero *bg = [PPHero new];
///   bg.translatesAutoresizingMaskIntoConstraints = NO;
///   [myCard insertSubview:bg atIndex:0];
///   // pin to all edges of myCard ...
///   [bg startAnimations];
/// @endcode
@interface PPHero : UIView

/// Optional accent override for screens that need the hero glass surface to
/// follow local state (for example, an order status color).
/// Leave nil to preserve the default shared hero accent palette.
@property (nonatomic, strong, nullable) UIColor *accentColorOverride;

/// Controls how the accent is rendered. Defaults to the original slim top bar.
@property (nonatomic, assign) PPHeroGlassAccentStyle accentStyle;

/// Multiplies the decorative corner-glow opacity when `accentStyle` is
/// `PPHeroGlassAccentStyleCornerGlow`. Defaults to 1.0.
@property (nonatomic, assign) CGFloat cornerGlowOpacityMultiplier;

/// Starts constellation line and dot pulse animations.
/// Safe to call multiple times — will not duplicate animations.
- (void)startAnimations;

/// Stops all running animations.
- (void)stopAnimations;

/// Re-applies the full color palette for the current trait collection.
/// Call this after a trait-collection change to update colors/opacities.
- (void)reapplyPalette;

@end

NS_ASSUME_NONNULL_END
