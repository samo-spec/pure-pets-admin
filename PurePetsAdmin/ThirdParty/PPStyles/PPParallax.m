//
//  PPParallax 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 03/09/2025.
//


//  PPParallax.m
#import "PPParallax.h"

#ifndef PPLOG
#define PPLOG(fmt, ...) NSLog((@"[PPParallax] " fmt), ##__VA_ARGS__)
#endif

@interface PPParallax ()
@property (nonatomic, weak) UIScrollView *scroll;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, weak) UIView *bg;
@property (nonatomic, weak) UIView *top;
@property (nonatomic, weak) UIView *stats;
@property (nonatomic, weak) UIImageView *avatar;
@property (nonatomic) BOOL attached;
@end

@implementation PPParallax

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self pp_applyDefaults];
    }
    return self;
}

- (instancetype)initWithScrollView:(UIScrollView *)scrollView
                        headerView:(UIView *)headerView
                   backgroundView:(UIView *)bgView
                            topRow:(UIView *)topRow
                          statsRow:(UIView *)statsRow
                       avatarImage:(UIImageView *)avatar
{
    if ((self = [super initWithFrame:(bgView ?: headerView).bounds])) {
        [self pp_applyDefaults];
        _scroll = scrollView;
        _header = headerView;
        _bg     = bgView ?: self;
        _top    = topRow;
        _stats  = statsRow;
        _avatar = avatar;
    }
    return self;
}

- (void)attach {
    if (self.attached || !self.scroll || !self.header) return;

    UIView *backgroundView = self.bg ?: self;
    if (backgroundView == self && self.superview != self.header) {
        self.frame = self.header.bounds;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.header insertSubview:self atIndex:0];
    }

    // Put header inside the scrollView, above its content.
    // We'll use contentInset to “reserve” space for it.
    [self.scroll addSubview:self.header];
    self.header.clipsToBounds = NO;
    self.header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // Reserve space and start at expanded position
    UIEdgeInsets insets = self.scroll.contentInset;
    insets.top = self.baseHeight;
    self.scroll.contentInset = insets;
    self.scroll.scrollIndicatorInsets = insets;

    // Place header just above the first content pixel
    CGFloat width = self.scroll.bounds.size.width;
    self.header.frame = CGRectMake(0, -self.baseHeight, width, self.baseHeight);

    // Make sure we start with the header fully visible
    if (self.scroll.contentOffset.y > -self.baseHeight) {
        self.scroll.contentOffset = CGPointMake(0, -self.baseHeight);
    }

    self.attached = YES;
    if (self.debugLogging) PPLOG(@"attached (base=%.1f)", self.baseHeight);
}

- (void)updateLayout {
    if (!self.attached) return;
    CGFloat width = self.scroll.bounds.size.width;
    CGRect f = self.header.frame;
    f.origin.x = 0;
    f.size.width = width;
    self.header.frame = f;
}

#pragma mark - Scrolling

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!self.attached) return;

    CGFloat y = scrollView.contentOffset.y;
    CGFloat width = scrollView.bounds.size.width;

    // Height we want to render at this moment
    CGFloat currentHeight = MAX(-y, self.baseHeight);
    BOOL    stretching    = (currentHeight > self.baseHeight);
    CGFloat stretch       = currentHeight - self.baseHeight;

    // Layout header by frame math (no Auto Layout churn)
    self.header.frame = CGRectMake(0, y, width, currentHeight);

    if (stretching) {
        // Pulling down → scale bg & avatar, don't translate rows
        CGFloat stretchNorm = MIN(stretch / self.maxStretch, 1.0); // 0..1
        CGFloat scale = 1.0 + (self.avatarMaxScale - 1.0) * stretchNorm;
        UIView *backgroundView = self.bg ?: self;

        if (backgroundView) {
            // subtle bg scale (slower than avatar)
            CGFloat bgScale = 1.0 + 0.30 * stretchNorm;
            backgroundView.transform = CGAffineTransformMakeScale(bgScale, bgScale);
            backgroundView.center = CGPointMake(width*0.5, currentHeight*0.5); // keep centered
        }
        if (self.avatar) {
            self.avatar.transform = CGAffineTransformMakeScale(scale, scale);
            self.avatar.alpha = 1.0;
        }
        if (self.top)   self.top.transform   = CGAffineTransformIdentity;
        if (self.stats) self.stats.transform = CGAffineTransformIdentity;

        if (self.debugLogging) {
            static NSInteger lastBucket = NSIntegerMin;
            NSInteger b = (NSInteger)floor(stretch/20.0);
            if (b != lastBucket) { lastBucket = b; PPLOG(@"STRETCH h=%.1f (+%.1f) scale=%.2f", currentHeight, stretch, scale); }
        }
    } else {
        // Scrolling up within/above header → parallax translations, fade avatar
        CGFloat delta = MIN(self.baseHeight, y + self.baseHeight); // 0..base
        CGFloat tBG   = -delta * self.bgParallaxFactor;
        CGFloat tTop  = -delta * self.topParallaxFactor;
        CGFloat tStat = -delta * self.statsParallaxFactor;
        UIView *backgroundView = self.bg ?: self;

        if (backgroundView) backgroundView.transform = CGAffineTransformMakeTranslation(0, tBG);
        if (self.top)   self.top.transform   = CGAffineTransformMakeTranslation(0, tTop);
        if (self.stats) self.stats.transform = CGAffineTransformMakeTranslation(0, tStat);

        if (self.avatar) {
            self.avatar.transform = CGAffineTransformIdentity;
            CGFloat fade = MAX(0.0, 1.0 - (delta / self.avatarFadeDistance));
            self.avatar.alpha = fade;
        }

        if (self.debugLogging) {
            static NSInteger lastBucket = NSIntegerMin;
            NSInteger b = (NSInteger)floor(delta/20.0);
            if (b != lastBucket) { lastBucket = b; PPLOG(@"PARALLAX delta=%.1f bg=%.1f top=%.1f stats=%.1f", delta, tBG, tTop, tStat); }
        }
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) [self resetAnimated:YES];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self resetAnimated:YES];
}

- (void)resetAnimated:(BOOL)animated {
    if (!self.attached) return;

    void (^changes)(void) = ^{
        // snap transforms & header frame to base state
        self.header.frame = CGRectMake(0, -self.baseHeight, self.scroll.bounds.size.width, self.baseHeight);
        UIView *backgroundView = self.bg ?: self;
        if (backgroundView) backgroundView.transform = CGAffineTransformIdentity;
        if (self.top)   self.top.transform   = CGAffineTransformIdentity;
        if (self.stats) self.stats.transform = CGAffineTransformIdentity;
        if (self.avatar){
            self.avatar.transform = CGAffineTransformIdentity;
            self.avatar.alpha = 1.0;
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.20 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)pp_applyDefaults {
    self.contentMode = UIViewContentModeScaleAspectFill;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;

    _baseHeight          = 220.0;
    _maxStretch          = 180.0;

    _bgParallaxFactor    = 0.35;
    _topParallaxFactor   = 0.15;
    _statsParallaxFactor = 0.05;

    _avatarMaxScale      = 1.40;
    _avatarFadeDistance  = 240.0;
}

@end
