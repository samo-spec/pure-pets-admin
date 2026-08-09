//
//  PPHero.m
//  Pure Pets
//
//  Reusable decorative glass background extracted from PPUserMenuViewController hero card.
//  The constellation uses restrained, lifecycle-safe ambient motion for premium depth.
//

#import "PPHero.h"
#import "PPMarketplaceHeroCardStyle.h"
#import "Language.h"

static NSString * const PPHeroGlassConstellationOpacityAnimationKey = @"pp.hero.glass.constellation.opacity";
static NSString * const PPHeroGlassConstellationTraceAnimationKey = @"pp.hero.glass.constellation.trace";
static NSString * const PPHeroGlassDotPulseAnimationKey = @"pp.hero.glass.dot.pulse";
static NSString * const PPHeroGlassDotHaloPulseAnimationKey = @"pp.hero.glass.dot.halo.pulse";

enum {
    PPHeroGlassDotCount = 14,
    PPHeroGlassAnchorDotCount = 3,
    PPHeroGlassVisibleConnectionCount = 10
};

typedef struct {
    NSUInteger fromIndex;
    NSUInteger toIndex;
    CGFloat distanceSquared;
} PPHeroGlassConnection;

static NSValue *PPHeroGlassConnectionValue(PPHeroGlassConnection connection)
{
    return [NSValue value:&connection withObjCType:@encode(PPHeroGlassConnection)];
}

static PPHeroGlassConnection PPHeroGlassConnectionFromValue(NSValue *value)
{
    PPHeroGlassConnection connection = {0, 0, 0.0};
    [value getValue:&connection];
    return connection;
}

static CGFloat PPHeroGlassRandomUnit(void)
{
    return ((CGFloat)arc4random_uniform(1000000U)) / 1000000.0;
}

static CGFloat PPHeroGlassRandomRange(CGFloat minimum, CGFloat maximum)
{
    return minimum + ((maximum - minimum) * PPHeroGlassRandomUnit());
}

static CGFloat PPHeroGlassNormalizedDistanceSquared(CGPoint first, CGPoint second)
{
    CGFloat deltaX = first.x - second.x;
    // Hero cards are wider than they are tall. Weight Y by the visual aspect ratio
    // so generated points keep comfortable spacing in actual rendered coordinates.
    CGFloat deltaY = (first.y - second.y) * 0.62;
    return (deltaX * deltaX) + (deltaY * deltaY);
}

#pragma mark - Color helpers

static UIColor *PPHeroGlassAccentColor(void)
{
    return AppPrimaryClr ?: UIColor.systemRedColor;
}

static UIColor *PPHeroGlassDotColor(UIColor *accent,
                                    UIColor *surfaceBase,
                                    BOOL darkMode,
                                    UITraitCollection *traitCollection)
{
    UIColor *overlay = darkMode ? UIColor.whiteColor : surfaceBase;
    UIColor *tone = PPMarketplaceHeroCardBlend(accent,
                                               overlay,
                                               darkMode ? 0.54 : 0.48,
                                               traitCollection);
    return [tone colorWithAlphaComponent:darkMode ? 0.42 : 0.38];
}

static UIColor *PPHeroGlassDotHaloColor(UIColor *accent,
                                        BOOL darkMode,
                                        UITraitCollection *traitCollection)
{
    UIColor *tone = PPMarketplaceHeroCardBlend(accent,
                                               UIColor.whiteColor,
                                               darkMode ? 0.70 : 0.54,
                                               traitCollection);
    return [tone colorWithAlphaComponent:darkMode ? 0.25 : 0.21];
}

static UIColor *PPHeroGlassConstellationLineColor(UIColor *accent,
                                                   UIColor *surfaceBase,
                                                   BOOL darkMode,
                                                   UITraitCollection *traitCollection)
{
    UIColor *tone = PPMarketplaceHeroCardBlend(accent,
                                               surfaceBase,
                                               darkMode ? 0.60 : 0.70,
                                               traitCollection);
    return [tone colorWithAlphaComponent:darkMode ? 0.22 : 0.19];
}

static UIColor *PPHeroGlassConstellationTraceColor(UIColor *accent,
                                                    BOOL darkMode,
                                                    UITraitCollection *traitCollection)
{
    UIColor *trace = PPMarketplaceHeroCardBlend(accent,
                                                UIColor.whiteColor,
                                                darkMode ? 0.66 : 0.46,
                                                traitCollection);
    return [trace colorWithAlphaComponent:darkMode ? 0.32 : 0.28];
}

static BOOL PPHeroGlassIsDark(UITraitCollection *traitCollection)
{
    if (@available(iOS 13.0, *)) {
        return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

static UIColor *PPHeroGlassSurfaceBaseColor(UITraitCollection *traitCollection)
{
    UIColor *fallback = [UIColor colorWithRed:0.992 green:0.989 blue:0.991 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        fallback = PPMarketplaceHeroCardResolvedColor(
            [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
                return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                    ? [UIColor colorWithWhite:0.104 alpha:1.0]
                    : [UIColor colorWithRed:0.992 green:0.989 blue:0.991 alpha:1.0];
            }],
            traitCollection
        );
    }
    return AppForgroundColr ?: fallback;
}

static UIColor *PPHeroGlassSurfaceHighlightColor(UIColor *surfaceBase,
                                                   BOOL darkMode,
                                                   UITraitCollection *traitCollection)
{
    return PPMarketplaceHeroCardBlend(surfaceBase,
                                      UIColor.whiteColor,
                                      darkMode ? 0.08 : 0.20,
                                      traitCollection);
}

static UIColor *PPHeroGlassBackgroundAccentColor(UIColor *primaryAccent,
                                                  UIColor *surfaceBase,
                                                  BOOL darkMode,
                                                  UITraitCollection *traitCollection)
{
    return PPMarketplaceHeroCardBlend(primaryAccent,
                                      surfaceBase,
                                      darkMode ? 0.12 : 0.18,
                                      traitCollection);
}

static UIColor *PPHeroGlassSurfaceTintColor(UIColor *surfaceBase,
                                             UIColor *backgroundAccent,
                                             BOOL darkMode,
                                             UITraitCollection *traitCollection)
{
    return PPMarketplaceHeroCardBlend(surfaceBase,
                                      backgroundAccent,
                                      darkMode ? 0.095 : 0.038,
                                      traitCollection);
}

static UIColor *PPHeroGlassSurfaceTailColor(UIColor *surfaceTint,
                                             UIColor *backgroundAccent,
                                             BOOL darkMode,
                                             UITraitCollection *traitCollection)
{
    return PPMarketplaceHeroCardBlend(surfaceTint,
                                      backgroundAccent,
                                      darkMode ? 0.062 : 0.024,
                                      traitCollection);
}

static UIColor *PPHeroGlassStrokeColor(BOOL darkMode)
{
    return [UIColor.whiteColor colorWithAlphaComponent:darkMode ? 0.12 : 0.78];
}

#pragma mark - Implementation

@interface PPHero ()
@property (nonatomic, strong) UIView *materialView;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) CAGradientLayer *depthLayer;
@property (nonatomic, strong) CAShapeLayer *constellationLayer;
@property (nonatomic, strong) CAShapeLayer *constellationTraceLayer;
@property (nonatomic, strong) NSArray<CAShapeLayer *> *dotHaloLayers;
@property (nonatomic, strong) NSArray<CAShapeLayer *> *dotLayers;
@property (nonatomic, copy) NSArray<NSValue *> *normalizedDotCenters;
@property (nonatomic, copy) NSArray<NSNumber *> *dotSizes;
@property (nonatomic, copy) NSArray<NSNumber *> *dotOpacities;
@property (nonatomic, copy) NSArray<NSNumber *> *dotAnimationDurations;
@property (nonatomic, copy) NSArray<NSNumber *> *dotAnimationDelays;
@property (nonatomic, copy) NSArray<NSValue *> *constellationConnections;
@property (nonatomic, copy) NSIndexSet *anchorDotIndexes;
@property (nonatomic, strong) UIView *accentView;
@property (nonatomic, assign) BOOL motionRunning;
- (void)pp_generateConstellationDefinition;
- (NSArray<NSValue *> *)pp_generateNormalizedDotCenters;
- (NSArray<NSValue *> *)pp_generateConnectionsForCenters:(NSArray<NSValue *> *)centers;
- (void)pp_applyAccentStyle;
- (void)pp_reduceMotionStatusDidChange:(NSNotification *)notification;
- (void)pp_applicationDidBecomeActive:(NSNotification *)notification;
@end

@implementation PPHero

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self pp_commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self pp_commonInit];
    }
    return self;
}

- (void)pp_commonInit
{
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;
     _accentStyle = PPHeroGlassAccentStyleBar;
     _cornerGlowOpacityMultiplier = 1.0;
     _animationsEnabled = YES;
    [self pp_generateConstellationDefinition];

    // Card-level chrome: border, shadow, continuous corners
    // (identical to headerCardView setup in PPUserMenuViewController)
    self.layer.borderWidth = 1.0;
    PPApplyContinuousCorners(self, PPCornerHero - 6.0);
    PPApplyElevatedShadow(self);
    self.layer.shadowOpacity = 0.08f;
    self.layer.shadowRadius = 20.0f;
    self.layer.shadowOffset = CGSizeMake(0.0, 10.0);

    // Material container (clipped, receives gradient + constellation + dots)
    UIView *material = [UIView new];
    material.userInteractionEnabled = NO;
    material.clipsToBounds = YES;
    material.backgroundColor = UIColor.clearColor;
    PPApplyContinuousCorners(material, PPCornerHero - 6.0);
    [self addSubview:material];
    self.materialView = material;

    // Gradient layer
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.drawsAsynchronously = YES;
    gradient.startPoint = Language.isRTL ? CGPointMake(1.0, 0.0) : CGPointMake(0.0, 0.0);
    gradient.endPoint = Language.isRTL ? CGPointMake(0.0, 1.0) : CGPointMake(1.0, 1.0);
    [material.layer insertSublayer:gradient atIndex:0];
    self.gradientLayer = gradient;

    // Depth layer
    CAGradientLayer *depth = [CAGradientLayer layer];
    depth.drawsAsynchronously = YES;
    depth.startPoint = CGPointMake(0.0, 0.0);
    depth.endPoint = CGPointMake(1.0, 1.0);
    [material.layer insertSublayer:depth above:gradient];
    self.depthLayer = depth;

    // Constellation line layer
    CAShapeLayer *constellation = [CAShapeLayer layer];
    constellation.fillColor = UIColor.clearColor.CGColor;
    constellation.lineWidth = 0.7;
    constellation.lineCap = kCALineCapRound;
    constellation.lineJoin = kCALineJoinRound;
    constellation.contentsScale = UIScreen.mainScreen.scale;
    [material.layer insertSublayer:constellation above:depth];
    self.constellationLayer = constellation;

    // A narrow moving highlight gives the network depth while the base lines stay calm.
    CAShapeLayer *constellationTrace = [CAShapeLayer layer];
    constellationTrace.fillColor = UIColor.clearColor.CGColor;
    constellationTrace.lineWidth = 1.05;
    constellationTrace.lineCap = kCALineCapRound;
    constellationTrace.lineJoin = kCALineJoinRound;
    constellationTrace.strokeStart = 0.0;
    constellationTrace.strokeEnd = 0.0;
    constellationTrace.opacity = 0.0;
    constellationTrace.contentsScale = UIScreen.mainScreen.scale;
    [material.layer insertSublayer:constellationTrace above:constellation];
    self.constellationTraceLayer = constellationTrace;

    // Soft halo rings sit behind the dot cores and animate only on anchor dots.
    NSMutableArray<CAShapeLayer *> *dotHaloLayers = [NSMutableArray arrayWithCapacity:PPHeroGlassDotCount];
    for (NSInteger index = 0; index < PPHeroGlassDotCount; index++) {
        CAShapeLayer *halo = [CAShapeLayer layer];
        halo.fillColor = UIColor.clearColor.CGColor;
        halo.lineWidth = 0.7;
        halo.opacity = 0.0;
        halo.contentsScale = UIScreen.mainScreen.scale;
        halo.allowsEdgeAntialiasing = YES;
        [material.layer insertSublayer:halo above:constellationTrace];
        [dotHaloLayers addObject:halo];
    }
    self.dotHaloLayers = dotHaloLayers.copy;

    NSMutableArray<CAShapeLayer *> *dotLayers = [NSMutableArray arrayWithCapacity:PPHeroGlassDotCount];
    for (NSInteger index = 0; index < PPHeroGlassDotCount; index++) {
        CAShapeLayer *dot = [CAShapeLayer layer];
        dot.lineWidth = 0.75;
        dot.opacity = 0.0;
        dot.contentsScale = UIScreen.mainScreen.scale;
        dot.allowsEdgeAntialiasing = YES;
        [material.layer addSublayer:dot];
        [dotLayers addObject:dot];
    }
    self.dotLayers = dotLayers.copy;

    // Top accent bar
    UIView *accent = [UIView new];
    accent.userInteractionEnabled = NO;
    accent.layer.cornerRadius = 2.0;
    accent.clipsToBounds = YES;
    if (@available(iOS 13.0, *)) {
        accent.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [self addSubview:accent];
    self.accentView = accent;

    [self pp_applyAccentStyle];

    // Apply initial palette
    [self reapplyPalette];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pp_reduceMotionStatusDidChange:)
                                                 name:UIAccessibilityReduceMotionStatusDidChangeNotification
                                               object:nil];
 
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pp_applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

#pragma mark - Constellation Definition

- (void)pp_generateConstellationDefinition
{
    NSArray<NSValue *> *centers = [self pp_generateNormalizedDotCenters];
    NSMutableIndexSet *anchors = [NSMutableIndexSet indexSet];
    while (anchors.count < PPHeroGlassAnchorDotCount) {
        NSUInteger index = arc4random_uniform((uint32_t)PPHeroGlassDotCount);
        [anchors addIndex:index];
    }

    NSMutableArray<NSNumber *> *sizes = [NSMutableArray arrayWithCapacity:PPHeroGlassDotCount];
    NSMutableArray<NSNumber *> *opacities = [NSMutableArray arrayWithCapacity:PPHeroGlassDotCount];
    NSMutableArray<NSNumber *> *durations = [NSMutableArray arrayWithCapacity:PPHeroGlassDotCount];
    NSMutableArray<NSNumber *> *delays = [NSMutableArray arrayWithCapacity:PPHeroGlassDotCount];
    for (NSUInteger index = 0; index < PPHeroGlassDotCount; index++) {
        BOOL anchor = [anchors containsIndex:index];
        [sizes addObject:@(anchor
            ? PPHeroGlassRandomRange(3.05, 3.45)
            : PPHeroGlassRandomRange(1.85, 2.75))];
        [opacities addObject:@(anchor
            ? PPHeroGlassRandomRange(0.86, 0.94)
            : PPHeroGlassRandomRange(0.64, 0.82))];
        [durations addObject:@(anchor
            ? PPHeroGlassRandomRange(6.8, 8.4)
            : PPHeroGlassRandomRange(5.9, 8.0))];
        [delays addObject:@(PPHeroGlassRandomRange(0.35, 4.20))];
    }

    self.normalizedDotCenters = centers;
    self.dotSizes = sizes.copy;
    self.dotOpacities = opacities.copy;
    self.dotAnimationDurations = durations.copy;
    self.dotAnimationDelays = delays.copy;
    self.constellationConnections = [self pp_generateConnectionsForCenters:centers];
    self.anchorDotIndexes = anchors.copy;
}

- (NSArray<NSValue *> *)pp_generateNormalizedDotCenters
{
    NSMutableArray<NSValue *> *centers = [NSMutableArray arrayWithCapacity:PPHeroGlassDotCount];
    const CGFloat minimumDistanceSquared = 0.0110;

    for (NSUInteger index = 0; index < PPHeroGlassDotCount; index++) {
        CGPoint selectedCandidate = CGPointMake(0.5, 0.5);
        CGPoint bestCandidate = selectedCandidate;
        CGFloat bestMinimumDistance = -1.0;
        BOOL foundSpacedCandidate = NO;

        for (NSUInteger attempt = 0; attempt < 84; attempt++) {
            CGPoint candidate = CGPointMake(PPHeroGlassRandomRange(0.065, 0.935),
                                             PPHeroGlassRandomRange(0.105, 0.895));
            CGFloat candidateMinimumDistance = CGFLOAT_MAX;
            for (NSValue *existingValue in centers) {
                CGFloat distance = PPHeroGlassNormalizedDistanceSquared(candidate, existingValue.CGPointValue);
                candidateMinimumDistance = MIN(candidateMinimumDistance, distance);
            }

            if (candidateMinimumDistance > bestMinimumDistance) {
                bestMinimumDistance = candidateMinimumDistance;
                bestCandidate = candidate;
            }
            if (candidateMinimumDistance >= minimumDistanceSquared) {
                selectedCandidate = candidate;
                foundSpacedCandidate = YES;
                break;
            }
        }

        if (!foundSpacedCandidate) {
            selectedCandidate = bestCandidate;
        }
        [centers addObject:[NSValue valueWithCGPoint:selectedCandidate]];
    }
    return centers.copy;
}

- (NSArray<NSValue *> *)pp_generateConnectionsForCenters:(NSArray<NSValue *> *)centers
{
    NSUInteger centerCount = MIN(centers.count, (NSUInteger)PPHeroGlassDotCount);
    if (centerCount < 2) {
        return @[];
    }

    BOOL visited[PPHeroGlassDotCount] = {NO};
    NSUInteger rootIndex = arc4random_uniform((uint32_t)centerCount);
    visited[rootIndex] = YES;
    NSMutableArray<NSValue *> *treeConnections = [NSMutableArray arrayWithCapacity:centerCount - 1];

    for (NSUInteger edgeIndex = 0; edgeIndex < centerCount - 1; edgeIndex++) {
        PPHeroGlassConnection bestConnection = {NSNotFound, NSNotFound, CGFLOAT_MAX};
        for (NSUInteger fromIndex = 0; fromIndex < centerCount; fromIndex++) {
            if (!visited[fromIndex]) {
                continue;
            }
            CGPoint fromPoint = centers[fromIndex].CGPointValue;
            for (NSUInteger toIndex = 0; toIndex < centerCount; toIndex++) {
                if (visited[toIndex]) {
                    continue;
                }
                CGFloat distance = PPHeroGlassNormalizedDistanceSquared(fromPoint,
                                                                         centers[toIndex].CGPointValue);
                if (distance < bestConnection.distanceSquared) {
                    bestConnection = (PPHeroGlassConnection){fromIndex, toIndex, distance};
                }
            }
        }

        if (bestConnection.toIndex == NSNotFound) {
            break;
        }
        visited[bestConnection.toIndex] = YES;
        [treeConnections addObject:PPHeroGlassConnectionValue(bestConnection)];
    }

    [treeConnections sortUsingComparator:^NSComparisonResult(NSValue *firstValue, NSValue *secondValue) {
        CGFloat firstDistance = PPHeroGlassConnectionFromValue(firstValue).distanceSquared;
        CGFloat secondDistance = PPHeroGlassConnectionFromValue(secondValue).distanceSquared;
        if (firstDistance < secondDistance) {
            return NSOrderedAscending;
        }
        if (firstDistance > secondDistance) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    NSUInteger visibleCount = MIN((NSUInteger)PPHeroGlassVisibleConnectionCount, treeConnections.count);
    return [treeConnections subarrayWithRange:NSMakeRange(0, visibleCount)];
}

#pragma mark - Layout

- (void)layoutSubviews
{
    [super layoutSubviews];
 
    // Manual layout to bypass Auto Layout constraints solver latency and race conditions
    self.materialView.frame = self.bounds;
 
    // Corner radius inheritance (self-healing)
    CGFloat materialRadius = MAX(0.0, self.layer.cornerRadius - self.layer.borderWidth);
    self.materialView.layer.cornerRadius = materialRadius;
    if (@available(iOS 13.0, *)) {
        self.materialView.layer.cornerCurve = self.layer.cornerCurve;
    }
 
    // Manual layout for accent view
    BOOL cornerGlow = self.accentStyle == PPHeroGlassAccentStyleCornerGlow;
    CGFloat diameter = 172.0;
    if (cornerGlow) {
        self.accentView.frame = CGRectMake(-58.0, -66.0, diameter, diameter);
    } else {
        CGFloat leadingConstant = 38.0;
        CGFloat x = [Language isRTL] ? (CGRectGetWidth(self.bounds) - leadingConstant - 44.0) : leadingConstant;
        self.accentView.frame = CGRectMake(x, 0.0, 44.0, 4.0);
    }
 
    if (CGRectIsEmpty(self.bounds)) {
        return;
    }
 
    CGRect materialBounds = self.materialView.bounds;
 
    self.gradientLayer.frame = materialBounds;
    self.depthLayer.frame = materialBounds;
    self.gradientLayer.cornerRadius = materialRadius;
    self.depthLayer.cornerRadius = materialRadius;
 
    [self pp_layoutConstellationInBounds:materialBounds];
 
    self.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                   cornerRadius:self.layer.cornerRadius].CGPath;
 
    // Self-healing animation trigger: Auto-start animations once we are on-screen with valid bounds!
    if (self.window) {
        [self startAnimations];
    }
}

#pragma mark - Constellation Layout

- (void)pp_layoutConstellationInBounds:(CGRect)bounds
{
    if (CGRectIsEmpty(bounds) ||
        self.dotLayers.count == 0 ||
        self.normalizedDotCenters.count == 0) {
        return;
    }

    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    UIBezierPath *lines = [UIBezierPath bezierPath];

    CGFloat displayScale = MAX(UIScreen.mainScreen.scale, 1.0);
    NSUInteger dotCount = MIN(self.dotLayers.count, self.dotHaloLayers.count);
    dotCount = MIN(dotCount, self.normalizedDotCenters.count);
    dotCount = MIN(dotCount, self.dotSizes.count);
    dotCount = MIN(dotCount, self.dotOpacities.count);
    for (NSUInteger index = 0; index < dotCount; index++) {
        CGPoint normalizedCenter = self.normalizedDotCenters[index].CGPointValue;
        CGFloat x = round(width * normalizedCenter.x * displayScale) / displayScale;
        CGFloat y = round(height * normalizedCenter.y * displayScale) / displayScale;
        CGFloat size = self.dotSizes[index].doubleValue;

        BOOL anchor = [self.anchorDotIndexes containsIndex:index];
        CGFloat haloSize = size + (anchor ? 7.0 : 5.0);
        CAShapeLayer *haloLayer = self.dotHaloLayers[index];
        haloLayer.bounds = CGRectMake(0.0, 0.0, haloSize, haloSize);
        haloLayer.position = CGPointMake(x, y);
        haloLayer.path = [UIBezierPath bezierPathWithOvalInRect:haloLayer.bounds].CGPath;
        haloLayer.opacity = 0.0;

        CAShapeLayer *dotLayer = self.dotLayers[index];
        dotLayer.bounds = CGRectMake(0.0, 0.0, size, size);
        dotLayer.position = CGPointMake(x, y);
        UIBezierPath *dotPath = [UIBezierPath bezierPathWithOvalInRect:dotLayer.bounds];
        dotLayer.path = dotPath.CGPath;
        dotLayer.shadowPath = dotPath.CGPath;
        dotLayer.opacity = self.dotOpacities[index].doubleValue;
    }

    for (NSValue *connectionValue in self.constellationConnections) {
        PPHeroGlassConnection connection = PPHeroGlassConnectionFromValue(connectionValue);
        if (connection.fromIndex >= dotCount || connection.toIndex >= dotCount) {
            continue;
        }

        CGPoint normalizedFrom = self.normalizedDotCenters[connection.fromIndex].CGPointValue;
        CGPoint normalizedTo = self.normalizedDotCenters[connection.toIndex].CGPointValue;
        CGPoint fromPoint = CGPointMake(round(width * normalizedFrom.x * displayScale) / displayScale,
                                        round(height * normalizedFrom.y * displayScale) / displayScale);
        CGPoint toPoint = CGPointMake(round(width * normalizedTo.x * displayScale) / displayScale,
                                      round(height * normalizedTo.y * displayScale) / displayScale);
        [lines moveToPoint:fromPoint];
        [lines addLineToPoint:toPoint];
    }

    self.constellationLayer.frame = bounds;
    self.constellationLayer.path = lines.CGPath;
    self.constellationTraceLayer.frame = bounds;
    self.constellationTraceLayer.path = lines.CGPath;
}

#pragma mark - Palette

- (void)setAccentStyle:(PPHeroGlassAccentStyle)accentStyle
{
    if (_accentStyle == accentStyle) {
        return;
    }
    _accentStyle = accentStyle;
    [self pp_applyAccentStyle];
    [self reapplyPalette];
}

- (void)setCornerGlowOpacityMultiplier:(CGFloat)cornerGlowOpacityMultiplier
{
    CGFloat clamped = MIN(MAX(cornerGlowOpacityMultiplier, 0.0), 1.0);
    if (fabs(_cornerGlowOpacityMultiplier - clamped) < 0.001) {
        return;
    }
    _cornerGlowOpacityMultiplier = clamped;
    [self reapplyPalette];
}

- (void)setAccentColorOverride:(UIColor *)accentColorOverride
{
    if (_accentColorOverride == accentColorOverride ||
        [_accentColorOverride isEqual:accentColorOverride]) {
        return;
    }
    _accentColorOverride = accentColorOverride;
    [self reapplyPalette];
}

- (void)pp_applyAccentStyle
{
    BOOL cornerGlow = self.accentStyle == PPHeroGlassAccentStyleCornerGlow;
    CGFloat diameter = 172.0;
 
    self.accentView.layer.cornerRadius = cornerGlow ? diameter * 0.5 : 2.0;
    self.accentView.clipsToBounds = !cornerGlow;
    self.accentView.layer.masksToBounds = !cornerGlow;
    self.accentView.layer.shadowOffset = CGSizeZero;
    self.accentView.layer.shadowPath = cornerGlow
        ? [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0.0, 0.0, diameter, diameter)].CGPath
        : nil;
    [self setNeedsLayout];
}

- (void)reapplyPalette
{
    UIColor *brand = self.accentColorOverride ?: PPHeroGlassAccentColor();
    BOOL darkMode = PPHeroGlassIsDark(self.traitCollection);

    self.backgroundColor = UIColor.clearColor;
    self.materialView.backgroundColor = UIColor.clearColor;
    [self pp_setBorderColor:PPHeroGlassStrokeColor(darkMode)];
    [self pp_setShadowColor:[UIColor colorWithWhite:0.0 alpha:1.0]];
    self.layer.shadowOpacity = 0.08f;
    self.layer.shadowRadius = 20.0f;
    self.layer.shadowOffset = CGSizeMake(0.0, 10.0);

    UIColor *surfaceBase = PPHeroGlassSurfaceBaseColor(self.traitCollection);
    UIColor *surfaceHighlight = PPHeroGlassSurfaceHighlightColor(surfaceBase, darkMode, self.traitCollection);
    UIColor *backgroundAccent = PPHeroGlassBackgroundAccentColor(brand, surfaceBase, darkMode, self.traitCollection);
    UIColor *surfaceTint = PPHeroGlassSurfaceTintColor(surfaceBase, backgroundAccent, darkMode, self.traitCollection);
    UIColor *surfaceTail = PPHeroGlassSurfaceTailColor(surfaceTint, backgroundAccent, darkMode, self.traitCollection);

    self.gradientLayer.opacity = darkMode ? 0.90 : 0.82;
    self.gradientLayer.colors = @[
        (id)PPMarketplaceHeroCardResolvedColor(surfaceHighlight, self.traitCollection).CGColor,
        (id)PPMarketplaceHeroCardResolvedColor(surfaceTint, self.traitCollection).CGColor,
        (id)PPMarketplaceHeroCardResolvedColor(surfaceTail, self.traitCollection).CGColor
    ];
    self.gradientLayer.locations = @[@0.0, @0.56, @1.0];
    self.gradientLayer.startPoint = Language.isRTL ? CGPointMake(1.0, 0.0) : CGPointMake(0.0, 0.0);
    self.gradientLayer.endPoint = Language.isRTL ? CGPointMake(0.0, 1.0) : CGPointMake(1.0, 1.0);

    self.depthLayer.colors = @[
        (__bridge id)[UIColor.clearColor CGColor],
        (__bridge id)[UIColor.clearColor CGColor]
    ];
    self.depthLayer.locations = @[@0.0, @1.0];
    self.depthLayer.opacity = 1.0;

    UIColor *dot = PPMarketplaceHeroCardResolvedColor(PPHeroGlassDotColor(brand,
                                                                         surfaceBase,
                                                                         darkMode,
                                                                         self.traitCollection),
                                                       self.traitCollection);
    UIColor *dotHalo = PPMarketplaceHeroCardResolvedColor(PPHeroGlassDotHaloColor(brand,
                                                                                 darkMode,
                                                                                 self.traitCollection),
                                                           self.traitCollection);
    UIColor *line = PPMarketplaceHeroCardResolvedColor(PPHeroGlassConstellationLineColor(AppBackgroundClr,
                                                                                         surfaceBase,
                                                                                         darkMode,
                                                                                         self.traitCollection),
                                                        self.traitCollection);
    UIColor *traceAccent = self.accentColorOverride ?: [AppPrimaryClrShiner colorWithAlphaComponent:(CGFloat)0.92];
    UIColor *trace = PPMarketplaceHeroCardResolvedColor(PPHeroGlassConstellationTraceColor(traceAccent,
                                                                                           darkMode,
                                                                                           self.traitCollection),
                                                         self.traitCollection);
    for (CAShapeLayer *haloLayer in self.dotHaloLayers) {
        haloLayer.fillColor = UIColor.clearColor.CGColor;
        haloLayer.strokeColor = dotHalo.CGColor;
        haloLayer.opacity = 0.0;
    }
    for (CAShapeLayer *dotLayer in self.dotLayers) {
        dotLayer.fillColor = dot.CGColor;
        dotLayer.strokeColor = dotHalo.CGColor;
        dotLayer.shadowColor = dot.CGColor;
        dotLayer.shadowOpacity = darkMode ? 0.26f : 0.16f;
        dotLayer.shadowRadius = darkMode ? 2.2 : 1.6;
        dotLayer.shadowOffset = CGSizeZero;
    }
    self.constellationLayer.strokeColor = line.CGColor;
    self.constellationLayer.opacity = darkMode ? 0.84 : 0.80;
    self.constellationTraceLayer.strokeColor = trace.CGColor;
    self.constellationTraceLayer.opacity = 0.0;

    BOOL cornerGlow = self.accentStyle == PPHeroGlassAccentStyleCornerGlow;
    CGFloat cornerGlowOpacity = MIN(MAX(self.cornerGlowOpacityMultiplier, 0.0), 1.0);
    self.accentView.backgroundColor =
        [brand colorWithAlphaComponent:cornerGlow ? ((darkMode ? 0.20 : 0.155) * cornerGlowOpacity) : 0.76];
    self.accentView.layer.shadowColor = brand.CGColor;
    self.accentView.layer.shadowOpacity = cornerGlow ? ((darkMode ? 0.24f : 0.17f) * cornerGlowOpacity) : 0.0f;
    self.accentView.layer.shadowRadius = cornerGlow ? 30.0f : 0.0f;
}

#pragma mark - Animation Lifecycle

- (void)startAnimations
{
    if (!self.animationsEnabled) {
        [self stopAnimations];
        return;
    }

    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self stopAnimations];
        return;
    }
 
    BOOL animationsActive = [self.constellationLayer animationForKey:PPHeroGlassConstellationOpacityAnimationKey] != nil;
    if ((self.motionRunning && animationsActive) ||
        !self.window ||
        !self.constellationLayer ||
        CGRectIsEmpty(self.materialView.bounds)) {
        return;
    }

    self.motionRunning = YES;
    [self.constellationLayer removeAllAnimations];
    [self.constellationTraceLayer removeAllAnimations];
    for (CAShapeLayer *haloLayer in self.dotHaloLayers) {
        [haloLayer removeAllAnimations];
    }
    for (CAShapeLayer *dotLayer in self.dotLayers) {
        [dotLayer removeAllAnimations];
    }

    // The base geometry breathes within a narrow range so it remains quietly legible.
    CGFloat baseLineOpacity = self.constellationLayer.opacity;
    CABasicAnimation *lineOpacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
    lineOpacity.fromValue = @(baseLineOpacity * 0.74);
    lineOpacity.toValue = @(MIN(1.0, baseLineOpacity + 0.10));
    lineOpacity.duration = 8.6;
    lineOpacity.autoreverses = YES;
    lineOpacity.repeatCount = HUGE_VALF;
    lineOpacity.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.constellationLayer addAnimation:lineOpacity forKey:PPHeroGlassConstellationOpacityAnimationKey];

    // A faint highlight travels through the network at long intervals.
    NSArray<NSNumber *> *traceKeyTimes = @[@0.0, @0.10, @0.32, @0.56, @0.78, @1.0];
    CAKeyframeAnimation *traceStart = [CAKeyframeAnimation animationWithKeyPath:@"strokeStart"];
    traceStart.values = @[@0.0, @0.0, @0.0, @0.31, @0.82, @1.0];
    traceStart.keyTimes = traceKeyTimes;

    CAKeyframeAnimation *traceEnd = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
    traceEnd.values = @[@0.0, @0.0, @0.22, @0.62, @1.0, @1.0];
    traceEnd.keyTimes = traceKeyTimes;

    CAKeyframeAnimation *traceOpacity = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    traceOpacity.values = @[@0.0, @0.0, @0.72, @0.56, @0.0, @0.0];
    traceOpacity.keyTimes = traceKeyTimes;

    CFTimeInterval hostTime = CACurrentMediaTime();
    CAAnimationGroup *traceGroup = [CAAnimationGroup animation];
    traceGroup.animations = @[traceStart, traceEnd, traceOpacity];
    traceGroup.duration = 11.8;
    traceGroup.beginTime = [self.constellationTraceLayer convertTime:hostTime fromLayer:nil]
        + PPHeroGlassRandomRange(0.65, 1.45);
    traceGroup.repeatCount = HUGE_VALF;
    traceGroup.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    traceGroup.removedOnCompletion = YES;
    [self.constellationTraceLayer addAnimation:traceGroup forKey:PPHeroGlassConstellationTraceAnimationKey];

    // Each dot twinkles around its own center. No drift means line endpoints stay precise.
    [self.dotLayers enumerateObjectsUsingBlock:^(CAShapeLayer *dotLayer, NSUInteger index, BOOL *stop) {
        if (index >= self.dotHaloLayers.count ||
            index >= self.dotAnimationDurations.count ||
            index >= self.dotAnimationDelays.count) {
            return;
        }

        CGFloat baseOpacity = dotLayer.opacity;
        BOOL anchorDot = [self.anchorDotIndexes containsIndex:index];
        CGFloat peakScale = anchorDot ? 1.26 : 1.16;
        CGFloat peakOpacity = MIN(1.0, baseOpacity + (anchorDot ? 0.10 : 0.06));
        CGFloat duration = self.dotAnimationDurations[index].doubleValue;
        CGFloat delay = self.dotAnimationDelays[index].doubleValue;
        NSArray<NSNumber *> *twinkleKeyTimes = @[@0.0, @0.40, @0.54, @0.68, @0.80, @1.0];

        CAKeyframeAnimation *scale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        scale.values = @[@1.0, @1.0, @(peakScale), @1.06, @0.99, @1.0];
        scale.keyTimes = twinkleKeyTimes;
        scale.calculationMode = kCAAnimationCubic;

        CAKeyframeAnimation *opacity = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        opacity.values = @[@(baseOpacity),
                           @(baseOpacity),
                           @(peakOpacity),
                           @(MIN(1.0, baseOpacity + 0.02)),
                           @(baseOpacity),
                           @(baseOpacity)];
        opacity.keyTimes = twinkleKeyTimes;
        opacity.calculationMode = kCAAnimationCubic;

        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[scale, opacity];
        group.duration = duration;
        group.beginTime = [dotLayer convertTime:hostTime fromLayer:nil] + delay;
        group.repeatCount = HUGE_VALF;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        group.removedOnCompletion = YES;
        [dotLayer addAnimation:group forKey:PPHeroGlassDotPulseAnimationKey];

        if (anchorDot) {
            CAShapeLayer *haloLayer = self.dotHaloLayers[index];
            CAKeyframeAnimation *haloScale = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            haloScale.values = @[@0.72, @0.72, @0.92, @1.30, @1.54, @1.58];
            haloScale.keyTimes = twinkleKeyTimes;
            haloScale.calculationMode = kCAAnimationCubic;

            CAKeyframeAnimation *haloOpacity = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            haloOpacity.values = @[@0.0, @0.0, @0.28, @0.12, @0.0, @0.0];
            haloOpacity.keyTimes = twinkleKeyTimes;
            haloOpacity.calculationMode = kCAAnimationCubic;

            CAAnimationGroup *haloGroup = [CAAnimationGroup animation];
            haloGroup.animations = @[haloScale, haloOpacity];
            haloGroup.duration = duration;
            haloGroup.beginTime = [haloLayer convertTime:hostTime fromLayer:nil] + delay;
            haloGroup.repeatCount = HUGE_VALF;
            haloGroup.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            haloGroup.removedOnCompletion = YES;
            [haloLayer addAnimation:haloGroup forKey:PPHeroGlassDotHaloPulseAnimationKey];
        }
    }];
}

- (void)stopAnimations
{
    self.motionRunning = NO;
    [self.constellationLayer removeAnimationForKey:PPHeroGlassConstellationOpacityAnimationKey];
    [self.constellationTraceLayer removeAnimationForKey:PPHeroGlassConstellationTraceAnimationKey];
    for (CAShapeLayer *haloLayer in self.dotHaloLayers) {
        [haloLayer removeAnimationForKey:PPHeroGlassDotHaloPulseAnimationKey];
    }
    for (CAShapeLayer *dotLayer in self.dotLayers) {
        [dotLayer removeAnimationForKey:PPHeroGlassDotPulseAnimationKey];
    }
}

- (void)pp_reduceMotionStatusDidChange:(NSNotification *)notification
{
    (void)notification;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self stopAnimations];
    } else {
        [self startAnimations];
    }
}
 
- (void)pp_applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    if (self.window) {
        [self stopAnimations];
        [self startAnimations];
    }
}

#pragma mark - Window Lifecycle

- (void)willMoveToWindow:(UIWindow *)newWindow
{
    [super willMoveToWindow:newWindow];
    if (!newWindow) {
        [self stopAnimations];
    }
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window) {
        [self startAnimations];
    }
}

#pragma mark - Trait Changes

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self stopAnimations];
    [self reapplyPalette];
    [self startAnimations];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
