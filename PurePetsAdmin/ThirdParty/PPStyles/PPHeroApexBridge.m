//
//  PPHeroApexBridge.m
//  PurePetsAdmin
//
//  Objective-C compatibility adapter for the Swift PPHeroApexView. The legacy
//  PPHero.h contract remains unchanged, so all existing hero call sites keep
//  their current ownership and behavior.
//

#import "PPHero.h"
#import "PurePetsAdmin-Swift.h"

@interface PPHero ()
@property (nonatomic, strong) PPHeroApexView *apexView;
@end

@implementation PPHero

@synthesize accentColorOverride = _accentColorOverride;
@synthesize accentStyle = _accentStyle;
@synthesize cornerGlowOpacityMultiplier = _cornerGlowOpacityMultiplier;

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self pp_installApexImplementation];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self pp_installApexImplementation];
    }
    return self;
}

- (void)pp_installApexImplementation
{
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;

    _accentStyle = PPHeroGlassAccentStyleBar;
    _cornerGlowOpacityMultiplier = 1.0;

    PPHeroApexView *apexView = [[PPHeroApexView alloc] initWithFrame:self.bounds];
    apexView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    apexView.accentStyle = _accentStyle;
    apexView.cornerGlowOpacityMultiplier = _cornerGlowOpacityMultiplier;
    [self addSubview:apexView];
    self.apexView = apexView;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.apexView.frame = self.bounds;
}

- (void)setAccentColorOverride:(UIColor *)accentColorOverride
{
    if (_accentColorOverride == accentColorOverride ||
        [_accentColorOverride isEqual:accentColorOverride]) {
        return;
    }

    _accentColorOverride = accentColorOverride;
    self.apexView.accentColorOverride = accentColorOverride;
}

- (void)setAccentStyle:(PPHeroGlassAccentStyle)accentStyle
{
    if (_accentStyle == accentStyle) {
        return;
    }

    _accentStyle = accentStyle;
    self.apexView.accentStyle = accentStyle;
}

- (void)setCornerGlowOpacityMultiplier:(CGFloat)cornerGlowOpacityMultiplier
{
    CGFloat clamped = MIN(MAX(cornerGlowOpacityMultiplier, 0.0), 1.0);
    if (fabs(_cornerGlowOpacityMultiplier - clamped) < 0.001) {
        return;
    }

    _cornerGlowOpacityMultiplier = clamped;
    self.apexView.cornerGlowOpacityMultiplier = clamped;
}

- (void)startAnimations
{
    [self.apexView startAnimations];
}

- (void)stopAnimations
{
    [self.apexView stopAnimations];
}

- (void)reapplyPalette
{
    [self.apexView reapplyPalette];
}

@end
