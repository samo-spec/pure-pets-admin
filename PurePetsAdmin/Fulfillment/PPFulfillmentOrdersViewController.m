#import "PPFulfillmentOrdersViewController.h"
#import "PPFulfillmentService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "PPHero.h"
#import "PPDesignTokens.h"
@import FirebaseFirestore;

#pragma mark - Haptic Helpers
/*
 
 static inline void PPHapticTouch(void) {
     [PPFunc pp_playTapEffect];
 }

 static inline void PPHapticSuccess(void) {
     [PPFunc pp_playSuccessEffect];
 }

 static inline void PPHapticError(void) {
     [PPFunc pp_playErrorEffect];
 }

 */
#pragma mark - Colors & Helpers

// Warm semantic palette — derived from Console FulfillmentOrders evidence:
// warm dark hero (#180F14 → #271219 → #3A1B1F), gold #D7A45C, success #49A874,
// danger #CF375B, warm ink #171513. Berry rose remains the brand accent only
// for avatars/icons (brand-soft), never as the universal signal.

static inline UIColor *PPF_AccentColor(void) {
    return AppPrimaryClr ?: UIColor.systemPinkColor;
}

static inline UIColor *PPF_WarmHex(NSString *hex) {
    return [UIColor colorWithHexString:hex];
}

static inline UIColor *PPF_GoldColor(void) { return PPF_WarmHex(@"#D7A45C"); }
static inline UIColor *PPF_GoldSoftColor(void) { return [PPF_WarmHex(@"#D7A45C") colorWithAlphaComponent:0.13]; }
static inline UIColor *PPF_GoldInkColor(void) { return PPF_WarmHex(@"#8A5F14"); }
static inline UIColor *PPF_SuccessColor(void) { return PPF_WarmHex(@"#49A874"); }
static inline UIColor *PPF_SuccessInkColor(void) { return PPF_WarmHex(@"#238754"); }
static inline UIColor *PPF_DangerColor(void) { return PPF_WarmHex(@"#CF375B"); }
static inline UIColor *PPF_DangerInkColor(void) { return PPF_WarmHex(@"#A62644"); }
static inline UIColor *PPF_NeutralToneColor(void) { return PPF_WarmHex(@"#8A8378"); }

static inline UIColor *PPF_CanvasColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? PPF_WarmHex(@"#131110")
                : PPF_WarmHex(@"#F6F3EE");
        }];
    }
    return PPF_WarmHex(@"#F6F3EE");
}

static inline UIColor *PPF_SurfaceColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? PPF_WarmHex(@"#201D1B")
                : PPF_WarmHex(@"#FFFDFB");
        }];
    }
    return [UIColor whiteColor];
}

static inline UIColor *PPF_InkColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.96 green:0.94 blue:0.92 alpha:1.0]
                : PPF_WarmHex(@"#171513");
        }];
    }
    return PPF_WarmHex(@"#171513");
}

static inline UIColor *PPF_SubInkColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.74 green:0.71 blue:0.68 alpha:1.0]
                : PPF_WarmHex(@"#5C564D");
        }];
    }
    return PPF_WarmHex(@"#5C564D");
}

static inline UIColor *PPF_TertiaryInkColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.55 green:0.52 blue:0.49 alpha:1.0]
                : PPF_WarmHex(@"#8A8378");
        }];
    }
    return PPF_WarmHex(@"#8A8378");
}

// Text-safe tone for light surfaces.
static inline UIColor *PPF_StatusColor(NSString *status) {
    NSString *s = [status.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s isEqualToString:@"completed"] || [s isEqualToString:@"ready_for_pickup"] || [s isEqualToString:@"accepted"]) {
        return PPF_SuccessInkColor();
    }
    if ([s isEqualToString:@"rejected"] || [s isEqualToString:@"cancelled"] || [s isEqualToString:@"failed"] || [s isEqualToString:@"returned"]) {
        return PPF_DangerInkColor();
    }
    if ([s isEqualToString:@"new_request"] || [s isEqualToString:@"preparing"] || [s isEqualToString:@"delivery_requested"] ||
        [s isEqualToString:@"delivery_assigned"] || [s isEqualToString:@"awaiting_handover"] || [s isEqualToString:@"handed_over"] ||
        [s isEqualToString:@"picked_up"] || [s isEqualToString:@"in_transit"] || [s isEqualToString:@"in_progress"]) {
        return PPF_GoldInkColor();
    }
    return PPF_NeutralToneColor();
}

// Soft pill background for the same status.
static inline UIColor *PPF_StatusTintColor(NSString *status) {
    return [PPF_StatusColor(status) colorWithAlphaComponent:0.12];
}

// Bright tone for the dark hero band.
static inline UIColor *PPF_StatusHeroColor(NSString *status) {
    NSString *s = [status.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s isEqualToString:@"completed"] || [s isEqualToString:@"ready_for_pickup"] || [s isEqualToString:@"accepted"]) {
        return PPF_SuccessColor();
    }
    if ([s isEqualToString:@"rejected"] || [s isEqualToString:@"cancelled"] || [s isEqualToString:@"failed"] || [s isEqualToString:@"returned"]) {
        return PPF_DangerColor();
    }
    if (s.length) return PPF_GoldColor();
    return PPF_NeutralToneColor();
}

// Console hero band palette.
static inline UIColor *PPF_HeroDeepColor(void) { return PPF_WarmHex(@"#180F14"); }
static inline UIColor *PPF_HeroMidColor(void) { return PPF_WarmHex(@"#271219"); }
static inline UIColor *PPF_HeroTopColor(void) { return PPF_WarmHex(@"#3A1B1F"); }
static inline UIColor *PPF_HeroTextColor(void) { return PPF_WarmHex(@"#FFF7ED"); }
static inline UIColor *PPF_HeroSubTextColor(void) { return [PPF_WarmHex(@"#FFEDD5") colorWithAlphaComponent:0.74]; }

static inline NSString *PPF_StatusKey(NSString *status) {
    NSString *s = status ?: @"";
    if ([s isEqualToString:@"new_request"]) return @"Fulfillment_Status_NewRequest";
    if ([s isEqualToString:@"preparing"]) return @"Fulfillment_Status_Preparing";
    if ([s isEqualToString:@"ready_for_pickup"]) return @"Fulfillment_Status_ReadyForPickup";
    if ([s isEqualToString:@"delivery_requested"]) return @"Fulfillment_Status_DeliveryRequested";
    if ([s isEqualToString:@"delivery_assigned"]) return @"Fulfillment_Status_DeliveryAssigned";
    if ([s isEqualToString:@"awaiting_handover"]) return @"Fulfillment_Status_AwaitingHandover";
    if ([s isEqualToString:@"handed_over"]) return @"Fulfillment_Status_HandedOver";
    if ([s isEqualToString:@"picked_up"]) return @"Fulfillment_Status_PickedUp";
    if ([s isEqualToString:@"in_transit"]) return @"Fulfillment_Status_InTransit";
    if ([s isEqualToString:@"accepted"]) return @"Fulfillment_Status_Accepted";
    if ([s isEqualToString:@"rejected"]) return @"Fulfillment_Status_Rejected";
    if ([s isEqualToString:@"completed"]) return @"Fulfillment_Status_Completed";
    if ([s isEqualToString:@"cancelled"]) return @"Fulfillment_Status_Cancelled";
    if ([s isEqualToString:@"failed"]) return @"Fulfillment_Status_Failed";
    if ([s isEqualToString:@"returned"]) return @"Fulfillment_Status_Returned";
    if ([s isEqualToString:@"pending"]) return @"Fulfillment_Status_Pending";
    if ([s isEqualToString:@"in_progress"]) return @"Fulfillment_Status_InProgress";
    return @"Fulfillment_Status_Unknown";
}

static inline NSString *PPF_StatusText(NSString *status) {
    if (!status || status.length == 0) return kLang(@"Fulfillment_Status_Unknown");
    NSString *key = PPF_StatusKey(status);
    NSString *localized = kLang(key);
    if (localized.length > 0 && ![localized isEqualToString:key]) return localized;
    return [status stringByReplacingOccurrencesOfString:@"_" withString:@" "].capitalizedString;
}

static inline NSString *PPF_DateString(NSDate *date) {
    if (!date) return @"—";
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    return [f stringFromDate:date];
}

static inline NSString *PPF_MoneyString(NSNumber *amount, NSString *currency) {
    double val = amount ? amount.doubleValue : 0.0;
    NSString *curr = currency.length ? currency : @"QAR";
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterCurrencyStyle;
    f.currencyCode = curr;
    f.maximumFractionDigits = 0;
    f.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    return [f stringFromNumber:@(val)] ?: [NSString stringWithFormat:@"%.0f %@", val, curr];
}

static inline NSString *PPF_ShortId(NSString *value, NSUInteger length) {
    if (!value || value.length == 0) return @"—";
    if (value.length > length) {
        return [NSString stringWithFormat:@"%@…", [value substringToIndex:length]];
    }
    return value;
}

static inline NSString *PPF_Initials(NSString *name) {
    if (!name || name.length == 0) return @"PP";
    NSArray *parts = [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length > 0) [clean addObject:p];
    }
    if (clean.count == 0) return @"PP";
    if (clean.count == 1) return [[[clean[0] substringToIndex:1] uppercaseString] copy];
    NSString *first = [clean[0] substringToIndex:1];
    NSString *second = [clean[1] substringToIndex:1];
    return [[NSString stringWithFormat:@"%@%@", first, second] uppercaseString];
}

static inline void PPF_ApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    view.layer.shadowRadius = 18.0;
    view.layer.shadowOpacity = 0.05;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;
}

#pragma mark - Custom UI Avatar View

@interface PPF_AvatarView : UIView
@property (nonatomic, strong) UILabel *initialsLabel;
@property (nonatomic, assign) BOOL heroStyle;
- (void)setName:(NSString *)name isLarge:(BOOL)isLarge;
@end

@implementation PPF_AvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.isAccessibilityElement = NO;
        self.backgroundColor = PPF_GoldSoftColor();
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = [PPF_GoldColor() colorWithAlphaComponent:0.35].CGColor;
        if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        
        _initialsLabel = [UILabel new];
        _initialsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _initialsLabel.font = [Styling fontBold:PPFontCaption1];
        _initialsLabel.textColor = PPF_GoldInkColor();
        _initialsLabel.textAlignment = NSTextAlignmentCenter;
        _initialsLabel.adjustsFontSizeToFitWidth = YES;
        _initialsLabel.minimumScaleFactor = 0.6;
        [self addSubview:_initialsLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_initialsLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_initialsLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_initialsLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:1.0],
            [_initialsLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-1.0],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) * 0.30;
}

- (void)setHeroStyle:(BOOL)heroStyle {
    _heroStyle = heroStyle;
    if (heroStyle) {
        self.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.08];
        self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.16].CGColor;
        self.initialsLabel.textColor = PPF_HeroTextColor();
    } else {
        self.backgroundColor = PPF_GoldSoftColor();
        self.layer.borderColor = [PPF_GoldColor() colorWithAlphaComponent:0.35].CGColor;
        self.initialsLabel.textColor = PPF_GoldInkColor();
    }
}

- (void)setName:(NSString *)name isLarge:(BOOL)isLarge {
    self.initialsLabel.text = PPF_Initials(name);
    self.initialsLabel.font = isLarge ? [Styling fontBold:PPFontSubheadline] : [Styling fontBold:PPFontCaption1];
}

@end

#pragma mark - Hero Band (dark warm gradient surface)

@interface PPF_HeroBandView : UIView
@property (nonatomic, strong, readonly) CAGradientLayer *glowLayer;
@property (nonatomic, assign) UIColor *glowColor;
- (void)setGlowColor:(UIColor *)glowColor animated:(BOOL)animated;
@end

@implementation PPF_HeroBandView {
    CAGradientLayer *_gradientLayer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.isAccessibilityElement = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;

        CAGradientLayer *gradient = [CAGradientLayer new];
        gradient.colors = @[
            (id)PPF_HeroDeepColor().CGColor,
            (id)PPF_HeroMidColor().CGColor,
            (id)PPF_HeroTopColor().CGColor
        ];
        gradient.startPoint = CGPointMake(0.18, 0.0);
        gradient.endPoint = CGPointMake(0.92, 1.0);
        [self.layer addSublayer:gradient];
        _gradientLayer = gradient;

        CAGradientLayer *glow = [CAGradientLayer new];
        glow.colors = @[
            (id)[PPF_GoldColor() colorWithAlphaComponent:0.20].CGColor,
            (id)[PPF_GoldColor() colorWithAlphaComponent:0.0].CGColor
        ];
        glow.startPoint = CGPointMake(0.0, 0.0);
        glow.endPoint = CGPointMake(1.0, 0.8);
        [self.layer addSublayer:glow];
        _glowLayer = glow;

        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0.0, 18.0);
        self.layer.shadowRadius = 34.0;
        self.layer.shadowOpacity = 0.18;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    _gradientLayer.frame = self.bounds;
    _glowLayer.frame = CGRectMake(0, 0, w, h * 0.9);
}

- (void)setGlowColor:(UIColor *)glowColor {
    [self setGlowColor:glowColor animated:NO];
}

- (void)setGlowColor:(UIColor *)glowColor animated:(BOOL)animated {
    _glowColor = glowColor ?: PPF_GoldColor();
    id color = (id)[_glowColor colorWithAlphaComponent:0.20].CGColor;
    id clear = (id)[_glowColor colorWithAlphaComponent:0.0].CGColor;
    if (animated) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.45];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        _glowLayer.colors = @[color, clear];
        [CATransaction commit];
    } else {
        _glowLayer.colors = @[color, clear];
    }
}

@end

#pragma mark - Command Hero View (dark hero with eyebrow, live pill, metrics)

@interface PPF_CommandHeroView : UIView
@property (nonatomic, strong, readonly) UIView *liveDot;
@property (nonatomic, strong, readonly) UILabel *syncCaptionLabel;
@property (nonatomic, strong, readonly) PPF_HeroBandView *bandView;
@property (nonatomic, strong, readonly) UILabel *eyebrowLabel;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UIView *livePill;
@property (nonatomic, strong, readonly) UILabel *liveLabel;

@property (nonatomic, strong) UILabel *activeCountLabel;
@property (nonatomic, strong) UILabel *waitingCountLabel;
@property (nonatomic, strong) UILabel *completedCountLabel;
@property (nonatomic, strong) UILabel *providerNetLabel;

- (void)updateMetricsWithActive:(NSInteger)active waiting:(NSInteger)waiting completed:(NSInteger)completed providerNet:(double)net currency:(NSString *)currency;
- (void)setSyncCaption:(NSString *)caption;
@end

@implementation PPF_CommandHeroView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        PPF_HeroBandView *band = [PPF_HeroBandView new];
        band.translatesAutoresizingMaskIntoConstraints = NO;
        band.layer.cornerRadius = PPCornerHero;
        [band setGlowColor:PPF_GoldColor() animated:NO];
        [self addSubview:band];
        _bandView = band;

        // Eyebrow pill
        UILabel *eyebrow = [UILabel new];
        eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
        eyebrow.text = kLang(@"Fulfillment_Eyebrow");
        eyebrow.font = [Styling fontBold:PPFontCaption1];
        eyebrow.textColor = PPF_WarmHex(@"#FDE68A");
        eyebrow.textAlignment = NSTextAlignmentCenter;
        eyebrow.layer.cornerRadius = PPCornerPill;
        eyebrow.layer.masksToBounds = YES;
        eyebrow.layer.borderWidth = 1.0;
        eyebrow.layer.borderColor = [[PPF_WarmHex(@"#FBBF24") colorWithAlphaComponent:0.28] CGColor];
        eyebrow.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.07];
        eyebrow.numberOfLines = 1;
        eyebrow.adjustsFontSizeToFitWidth = YES;
        eyebrow.minimumScaleFactor = 0.7;
        [self addSubview:eyebrow];
        _eyebrowLabel = eyebrow;

        // Title
        UILabel *title = [UILabel new];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.text = kLang(@"Fulfillment_Title");
        title.font = [Styling fontBold:PPFontTitle1];
        title.textColor = PPF_HeroTextColor();
        title.numberOfLines = 1;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.7;
        [self addSubview:title];
        _titleLabel = title;

        // Subtitle
        UILabel *subtitle = [UILabel new];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.text = kLang(@"Fulfillment_Subtitle");
        subtitle.font = [Styling fontRegular:PPFontSubheadline];
        subtitle.textColor = PPF_HeroSubTextColor();
        subtitle.numberOfLines = 2;
        [self addSubview:subtitle];
        _subtitleLabel = subtitle;

        // Live pill
        UIView *livePill = [UIView new];
        livePill.translatesAutoresizingMaskIntoConstraints = NO;
        livePill.backgroundColor = [[PPF_SuccessColor() colorWithAlphaComponent:0.20] colorWithAlphaComponent:1.0];
        livePill.layer.cornerRadius = PPCornerPill;
        livePill.layer.borderWidth = 1.0;
        livePill.layer.borderColor = [[PPF_SuccessColor() colorWithAlphaComponent:0.35] CGColor];
        livePill.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [self addSubview:livePill];
        _livePill = livePill;

        UIView *dot = [UIView new];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.backgroundColor = PPF_WarmHex(@"#77D8A0");
        dot.layer.cornerRadius = 4.0;
        dot.layer.shadowColor = PPF_WarmHex(@"#77D8A0").CGColor;
        dot.layer.shadowOpacity = 0.6;
        dot.layer.shadowRadius = 5.0;
        dot.layer.shadowOffset = CGSizeZero;
        [livePill addSubview:dot];
        _liveDot = dot;

        UILabel *liveLabel = [UILabel new];
        liveLabel.translatesAutoresizingMaskIntoConstraints = NO;
        liveLabel.font = [Styling fontBold:PPFontCaption1];
        liveLabel.textColor = PPF_WarmHex(@"#BBF7D0");
        liveLabel.text = kLang(@"Fulfillment_Live");
        liveLabel.textAlignment = NSTextAlignmentNatural;
        [livePill addSubview:liveLabel];
        _liveLabel = liveLabel;

        // Sync caption (right side of the live row)
        UILabel *sync = [UILabel new];
        sync.translatesAutoresizingMaskIntoConstraints = NO;
        sync.font = [Styling fontRegular:PPFontCaption2];
        sync.textColor = [PPF_HeroTextColor() colorWithAlphaComponent:0.55];
        sync.textAlignment = NSTextAlignmentNatural;
        sync.numberOfLines = 1;
        sync.adjustsFontSizeToFitWidth = YES;
        sync.minimumScaleFactor = 0.7;
        [self addSubview:sync];
        _syncCaptionLabel = sync;

        // Metrics tiles
        _activeCountLabel = [UILabel new];
        _waitingCountLabel = [UILabel new];
        _completedCountLabel = [UILabel new];
        _providerNetLabel = [UILabel new];

        UIStackView *metrics = [UIStackView new];
        metrics.translatesAutoresizingMaskIntoConstraints = NO;
        metrics.axis = UILayoutConstraintAxisHorizontal;
        metrics.distribution = UIStackViewDistributionFillEqually;
        metrics.alignment = UIStackViewAlignmentFill;
        metrics.spacing = 8.0;
        metrics.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [self addSubview:metrics];

        [metrics addArrangedSubview:[self buildTileWithIcon:@"clock.fill"
                                                      title:kLang(@"Fulfillment_Metric_Active")
                                                      label:_activeCountLabel
                                                      color:PPF_GoldColor()]];
        [metrics addArrangedSubview:[self buildTileWithIcon:@"shippingbox.fill"
                                                      title:kLang(@"Fulfillment_Metric_Waiting")
                                                      label:_waitingCountLabel
                                                      color:PPF_WarmHex(@"#E8B34B")]];
        [metrics addArrangedSubview:[self buildTileWithIcon:@"checkmark.circle.fill"
                                                      title:kLang(@"Fulfillment_Metric_Completed")
                                                      label:_completedCountLabel
                                                      color:PPF_SuccessColor()]];
        [metrics addArrangedSubview:[self buildTileWithIcon:@"banknote.fill"
                                                      title:kLang(@"Fulfillment_Metric_NetValue")
                                                      label:_providerNetLabel
                                                      color:PPF_GoldColor()]];

        [NSLayoutConstraint activateConstraints:@[
            [band.topAnchor constraintEqualToAnchor:self.topAnchor],
            [band.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [band.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [band.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [eyebrow.topAnchor constraintEqualToAnchor:self.topAnchor constant:PPSpaceLG],
            [eyebrow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceLG],
            [eyebrow.heightAnchor constraintEqualToConstant:30.0],
            [eyebrow.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],
            [eyebrow.widthAnchor constraintGreaterThanOrEqualToConstant:120.0],

            [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:10.0],
            [title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
            [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],

            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6.0],
            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],

            [livePill.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:12.0],
            [livePill.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [livePill.heightAnchor constraintEqualToConstant:28.0],

            [dot.leadingAnchor constraintEqualToAnchor:livePill.leadingAnchor constant:9.0],
            [dot.centerYAnchor constraintEqualToAnchor:livePill.centerYAnchor],
            [dot.widthAnchor constraintEqualToConstant:8.0],
            [dot.heightAnchor constraintEqualToConstant:8.0],

            [liveLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6.0],
            [liveLabel.centerYAnchor constraintEqualToAnchor:livePill.centerYAnchor],
            [liveLabel.trailingAnchor constraintEqualToAnchor:livePill.trailingAnchor constant:-11.0],

            [sync.leadingAnchor constraintEqualToAnchor:livePill.trailingAnchor constant:10.0],
            [sync.centerYAnchor constraintEqualToAnchor:livePill.centerYAnchor],
            [sync.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],

            [metrics.topAnchor constraintEqualToAnchor:livePill.bottomAnchor constant:PPSpaceBase],
            [metrics.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceBase],
            [metrics.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceBase],
            [metrics.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PPSpaceBase],
            [metrics.heightAnchor constraintEqualToConstant:64.0],
        ]];
    }
    return self;
}

- (UIView *)buildTileWithIcon:(NSString *)iconName title:(NSString *)title label:(UILabel *)label color:(UIColor *)color {
    UIView *tile = [UIView new];
    tile.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.06];
    tile.layer.cornerRadius = PPCornerSmall;
    if (@available(iOS 13.0, *)) tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    tile.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10] .CGColor;
    tile.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = color;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [tile addSubview:icon];

    UILabel *tLabel = [UILabel new];
    tLabel.translatesAutoresizingMaskIntoConstraints = NO;
    tLabel.text = title;
    tLabel.font = [Styling fontMedium:PPFontCaption2];
    tLabel.textColor = [PPF_HeroTextColor() colorWithAlphaComponent:0.62];
    tLabel.textAlignment = NSTextAlignmentNatural;
    tLabel.adjustsFontSizeToFitWidth = YES;
    tLabel.minimumScaleFactor = 0.7;
    [tile addSubview:tLabel];

    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [Styling fontBold:PPFontFootnote];
    label.textColor = PPF_HeroTextColor();
    label.textAlignment = NSTextAlignmentNatural;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.6;
    [tile addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:12.0],
        [icon.topAnchor constraintEqualToAnchor:tile.topAnchor constant:12.0],
        [icon.widthAnchor constraintEqualToConstant:16.0],
        [icon.heightAnchor constraintEqualToConstant:16.0],

        [tLabel.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:6.0],
        [tLabel.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [tLabel.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-8.0],

        [label.topAnchor constraintEqualToAnchor:tLabel.bottomAnchor constant:1.0],
        [label.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-8.0],
    ]];
    return tile;
}

- (void)updateMetricsWithActive:(NSInteger)active waiting:(NSInteger)waiting completed:(NSInteger)completed providerNet:(double)net currency:(NSString *)currency {
    self.activeCountLabel.text = [NSString stringWithFormat:@"%ld", (long)active];
    self.waitingCountLabel.text = [NSString stringWithFormat:@"%ld", (long)waiting];
    self.completedCountLabel.text = [NSString stringWithFormat:@"%ld", (long)completed];
    self.providerNetLabel.text = PPF_MoneyString(@(net), currency);
}

- (void)setSyncCaption:(NSString *)caption {
    self.syncCaptionLabel.text = caption ?: @"";
}

@end

#pragma mark - Cells

@interface PPF_OrderCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) PPF_AvatarView *customerAvatar;
@property (nonatomic, strong) UILabel *customerNameLabel;
@property (nonatomic, strong) UILabel *customerIdLabel;
@property (nonatomic, strong) UIImageView *routeArrow;
@property (nonatomic, strong) PPF_AvatarView *ownerAvatar;
@property (nonatomic, strong) UILabel *ownerNameLabel;
@property (nonatomic, strong) UILabel *ownerIdLabel;

@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *subtotalLabel;
@property (nonatomic, strong) UILabel *itemCountLabel;
@property (nonatomic, strong) UILabel *orderRefLabel;
@property (nonatomic, strong) UILabel *updatedAtLabel;
@property (nonatomic, strong) UIView *chevronCircle;

@property (nonatomic, assign) BOOL hasAnimatedEntrance;
@property (nonatomic, assign) BOOL hasPulsed;
- (void)configureWithRecord:(PPFulfillmentRecord *)record
               customerName:(nullable NSString *)customerName
                  ownerName:(nullable NSString *)ownerName
                   animated:(BOOL)animated
                      pulse:(BOOL)pulse;
@end

@implementation PPF_OrderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        _cardView.isAccessibilityElement = NO;
        PPF_ApplyCardChrome(_cardView, PPCornerCard);
        [self.contentView addSubview:_cardView];

        // Customer Person
        _customerAvatar = [PPF_AvatarView new];
        _customerAvatar.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_customerAvatar];

        _customerNameLabel = [UILabel new];
        _customerNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _customerNameLabel.font = [Styling fontBold:PPFontSubheadline];
        _customerNameLabel.textColor = PPF_InkColor();
        _customerNameLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _customerNameLabel.adjustsFontSizeToFitWidth = YES;
        _customerNameLabel.minimumScaleFactor = 0.8;
        [_cardView addSubview:_customerNameLabel];

        _customerIdLabel = [UILabel new];
        _customerIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _customerIdLabel.font = [Styling fontRegular:PPFontCaption2];
        _customerIdLabel.textColor = PPF_TertiaryInkColor();
        _customerIdLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_customerIdLabel];

        // Route arrow icon (gold)
        _routeArrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right"]];
        _routeArrow.translatesAutoresizingMaskIntoConstraints = NO;
        _routeArrow.tintColor = PPF_GoldColor();
        _routeArrow.contentMode = UIViewContentModeScaleAspectFit;
        if ([Language isRTL]) {
            _routeArrow.transform = CGAffineTransformMakeScale(-1.0, 1.0);
        }
        [_cardView addSubview:_routeArrow];

        // Owner Person
        _ownerAvatar = [PPF_AvatarView new];
        _ownerAvatar.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_ownerAvatar];

        _ownerNameLabel = [UILabel new];
        _ownerNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _ownerNameLabel.font = [Styling fontBold:PPFontSubheadline];
        _ownerNameLabel.textColor = PPF_InkColor();
        _ownerNameLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _ownerNameLabel.adjustsFontSizeToFitWidth = YES;
        _ownerNameLabel.minimumScaleFactor = 0.8;
        [_cardView addSubview:_ownerNameLabel];

        _ownerIdLabel = [UILabel new];
        _ownerIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _ownerIdLabel.font = [Styling fontRegular:PPFontCaption2];
        _ownerIdLabel.textColor = PPF_TertiaryInkColor();
        _ownerIdLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_ownerIdLabel];

        // Status pill (dot + label, tone-colored)
        _statusPill = [UIView new];
        _statusPill.translatesAutoresizingMaskIntoConstraints = NO;
        _statusPill.layer.cornerRadius = PPCornerPill;
        if (@available(iOS 13.0, *)) _statusPill.layer.cornerCurve = kCACornerCurveContinuous;
        _statusPill.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [_cardView addSubview:_statusPill];

        _statusDot = [UIView new];
        _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
        _statusDot.layer.cornerRadius = 3.5;
        _statusDot.clipsToBounds = YES;
        [_statusPill addSubview:_statusDot];

        _statusLabel = [UILabel new];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = [Styling fontBold:PPFontFootnote];
        _statusLabel.textColor = PPF_InkColor();
        _statusLabel.textAlignment = NSTextAlignmentNatural;
        _statusLabel.adjustsFontSizeToFitWidth = YES;
        _statusLabel.minimumScaleFactor = 0.7;
        [_statusPill addSubview:_statusLabel];

        // Subtotal & Items
        _subtotalLabel = [UILabel new];
        _subtotalLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtotalLabel.font = [Styling fontBold:PPFontTitle3];
        _subtotalLabel.textColor = PPF_InkColor();
        _subtotalLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_subtotalLabel];

        _itemCountLabel = [UILabel new];
        _itemCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _itemCountLabel.font = [Styling fontMedium:PPFontCaption1];
        _itemCountLabel.textColor = PPF_SubInkColor();
        _itemCountLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_itemCountLabel];

        // Order Ref & Updated At
        _orderRefLabel = [UILabel new];
        _orderRefLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _orderRefLabel.font = [Styling fontRegular:PPFontFootnote];
        _orderRefLabel.textColor = PPF_SubInkColor();
        _orderRefLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_orderRefLabel];

        _updatedAtLabel = [UILabel new];
        _updatedAtLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _updatedAtLabel.font = [Styling fontRegular:PPFontCaption1];
        _updatedAtLabel.textColor = PPF_TertiaryInkColor();
        _updatedAtLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_updatedAtLabel];

        // Circular chevron
        _chevronCircle = [UIView new];
        _chevronCircle.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronCircle.backgroundColor = [PPF_SurfaceColor() colorWithAlphaComponent:0.6];
        _chevronCircle.layer.cornerRadius = 16.0;
        _chevronCircle.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _chevronCircle.layer.borderColor = [PPF_TertiaryInkColor() colorWithAlphaComponent:0.25].CGColor;
        _chevronCircle.isAccessibilityElement = NO;
        [_cardView addSubview:_chevronCircle];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"]];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        chevron.tintColor = [PPF_TertiaryInkColor() colorWithAlphaComponent:0.75];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        if ([Language isRTL]) {
            chevron.transform = CGAffineTransformMakeScale(-1.0, 1.0);
        }
        [_chevronCircle addSubview:chevron];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            // Customer Identity Row
            [_customerAvatar.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14.0],
            [_customerAvatar.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_customerAvatar.widthAnchor constraintEqualToConstant:34.0],
            [_customerAvatar.heightAnchor constraintEqualToConstant:34.0],

            [_customerNameLabel.leadingAnchor constraintEqualToAnchor:_customerAvatar.trailingAnchor constant:10.0],
            [_customerNameLabel.topAnchor constraintEqualToAnchor:_customerAvatar.topAnchor],
            [_customerNameLabel.widthAnchor constraintLessThanOrEqualToConstant:104.0],

            [_customerIdLabel.leadingAnchor constraintEqualToAnchor:_customerNameLabel.leadingAnchor],
            [_customerIdLabel.topAnchor constraintEqualToAnchor:_customerNameLabel.bottomAnchor constant:2.0],

            // Route arrow
            [_routeArrow.leadingAnchor constraintEqualToAnchor:_customerNameLabel.trailingAnchor constant:6.0],
            [_routeArrow.centerYAnchor constraintEqualToAnchor:_customerAvatar.centerYAnchor],
            [_routeArrow.widthAnchor constraintEqualToConstant:15.0],
            [_routeArrow.heightAnchor constraintEqualToConstant:15.0],

            // Owner Identity
            [_ownerAvatar.leadingAnchor constraintEqualToAnchor:_routeArrow.trailingAnchor constant:6.0],
            [_ownerAvatar.topAnchor constraintEqualToAnchor:_customerAvatar.topAnchor],
            [_ownerAvatar.widthAnchor constraintEqualToConstant:34.0],
            [_ownerAvatar.heightAnchor constraintEqualToConstant:34.0],

            [_ownerNameLabel.leadingAnchor constraintEqualToAnchor:_ownerAvatar.trailingAnchor constant:10.0],
            [_ownerNameLabel.topAnchor constraintEqualToAnchor:_ownerAvatar.topAnchor],
            [_ownerNameLabel.widthAnchor constraintLessThanOrEqualToConstant:96.0],

            [_ownerIdLabel.leadingAnchor constraintEqualToAnchor:_ownerNameLabel.leadingAnchor],
            [_ownerIdLabel.topAnchor constraintEqualToAnchor:_ownerNameLabel.bottomAnchor constant:2.0],
            [_ownerIdLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusPill.leadingAnchor constant:-8.0],

            // Status pill top-trailing
            [_statusPill.trailingAnchor constraintEqualToAnchor:_chevronCircle.leadingAnchor constant:-10.0],
            [_statusPill.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:16.0],
            [_statusPill.heightAnchor constraintEqualToConstant:26.0],

            [_statusDot.leadingAnchor constraintEqualToAnchor:_statusPill.leadingAnchor constant:9.0],
            [_statusDot.centerYAnchor constraintEqualToAnchor:_statusPill.centerYAnchor],
            [_statusDot.widthAnchor constraintEqualToConstant:7.0],
            [_statusDot.heightAnchor constraintEqualToConstant:7.0],

            [_statusLabel.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:6.0],
            [_statusLabel.centerYAnchor constraintEqualToAnchor:_statusPill.centerYAnchor],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:_statusPill.trailingAnchor constant:-9.0],

            // Chevron circle
            [_chevronCircle.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14.0],
            [_chevronCircle.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_chevronCircle.widthAnchor constraintEqualToConstant:32.0],
            [_chevronCircle.heightAnchor constraintEqualToConstant:32.0],

            [chevron.centerXAnchor constraintEqualToAnchor:_chevronCircle.centerXAnchor],
            [chevron.centerYAnchor constraintEqualToAnchor:_chevronCircle.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:10.0],
            [chevron.heightAnchor constraintEqualToConstant:16.0],

            // Subtotal & Items
            [_subtotalLabel.leadingAnchor constraintEqualToAnchor:_customerAvatar.leadingAnchor],
            [_subtotalLabel.topAnchor constraintEqualToAnchor:_customerAvatar.bottomAnchor constant:14.0],

            [_itemCountLabel.leadingAnchor constraintEqualToAnchor:_subtotalLabel.trailingAnchor constant:8.0],
            [_itemCountLabel.firstBaselineAnchor constraintEqualToAnchor:_subtotalLabel.firstBaselineAnchor],
            [_itemCountLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusPill.leadingAnchor constant:-8.0],

            // Meta row
            [_orderRefLabel.leadingAnchor constraintEqualToAnchor:_customerAvatar.leadingAnchor],
            [_orderRefLabel.topAnchor constraintEqualToAnchor:_subtotalLabel.bottomAnchor constant:6.0],
            [_orderRefLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-14.0],

            [_updatedAtLabel.trailingAnchor constraintEqualToAnchor:_chevronCircle.leadingAnchor constant:-10.0],
            [_updatedAtLabel.centerYAnchor constraintEqualToAnchor:_orderRefLabel.centerYAnchor],
            [_updatedAtLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_orderRefLabel.trailingAnchor constant:8.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _hasAnimatedEntrance = NO;
    _hasPulsed = NO;
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
    _customerNameLabel.text = nil;
    _customerIdLabel.text = nil;
    _ownerNameLabel.text = nil;
    _ownerIdLabel.text = nil;
    _statusLabel.text = nil;
    _statusDot.backgroundColor = nil;
    _statusPill.backgroundColor = nil;
    _subtotalLabel.text = nil;
    _itemCountLabel.text = nil;
    _orderRefLabel.text = nil;
    _updatedAtLabel.text = nil;
}

- (void)configureWithRecord:(PPFulfillmentRecord *)record
               customerName:(nullable NSString *)customerName
                  ownerName:(nullable NSString *)ownerName
                   animated:(BOOL)animated
                      pulse:(BOOL)pulse {
    
    NSString *cName = customerName.length ? customerName : kLang(@"Fulfillment_UnknownCustomer");
    [self.customerAvatar setName:cName isLarge:NO];
    self.customerNameLabel.text = cName;
    self.customerIdLabel.text = PPF_ShortId(record.customerID, 8);

    BOOL isPlatform = [record.ownerType isEqualToString:@"platform"] || !record.ownerID.length;
    NSString *oName = isPlatform ? kLang(@"Fulfillment_Filter_Platform") : (ownerName.length ? ownerName : kLang(@"Fulfillment_UnknownCustomer"));
    [self.ownerAvatar setName:oName isLarge:NO];
    self.ownerNameLabel.text = oName;
    self.ownerIdLabel.text = isPlatform ? kLang(@"Fulfillment_Filter_Platform") : PPF_ShortId(record.ownerID, 8);

    UIColor *sColor = PPF_StatusColor(record.status);
    self.statusLabel.text = PPF_StatusText(record.status);
    self.statusLabel.textColor = sColor;
    self.statusPill.backgroundColor = PPF_StatusTintColor(record.status);
    self.statusDot.backgroundColor = sColor;

    NSNumber *subtotal = record.money[@"subtotal"];
    NSString *currency = record.money[@"currency"];
    self.subtotalLabel.text = PPF_MoneyString(subtotal, currency);

    NSString *itemsFormat = kLang(@"Fulfillment_ItemsCount_Format");
    self.itemCountLabel.text = [NSString stringWithFormat:itemsFormat, @(record.items.count)];

    NSString *orderRef = record.parentOrderNumber.length ? record.parentOrderNumber : PPF_ShortId(record.parentOrderID, 12);
    self.orderRefLabel.text = [NSString stringWithFormat:@"#%@", orderRef];

    self.updatedAtLabel.text = PPF_DateString(record.updatedAt);

    // VoiceOver: one concise reading of the whole handoff.
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ → %@، %@، %@، %@، %@",
                               cName, oName,
                               PPF_StatusText(record.status),
                               PPF_MoneyString(subtotal, currency),
                               self.itemCountLabel.text,
                               self.orderRefLabel.text];
    self.accessibilityTraits = UIAccessibilityTraitButton;

    if (animated && !_hasAnimatedEntrance) {
        _hasAnimatedEntrance = YES;
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            self.contentView.alpha = 0.0;
            self.contentView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
            [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.contentView.alpha = 1.0;
                self.contentView.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    }

    // Signature 1 — live "handoff commit" pulse on changed rows.
    if (pulse && !_hasPulsed) {
        _hasPulsed = YES;
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            self.routeArrow.transform = CGAffineTransformScale(CGAffineTransformMakeScale([Language isRTL] ? -1.0 : 1.0, 1.0), 0.6, 0.6);
            self.statusPill.alpha = 0.65;
            [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.routeArrow.transform = CGAffineTransformMakeScale([Language isRTL] ? -1.0 : 1.0, 1.0);
                self.statusPill.alpha = 1.0;
            } completion:nil];
        }
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    if (highlighted) {
        [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.contentView.transform = CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown);
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.20 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            self.contentView.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

@end

#pragma mark - Info Cell (Detail)

@interface PPFulfillmentInfoCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
- (void)configureTitle:(NSString *)title value:(NSString *)value isEmphasized:(BOOL)isEmphasized;
@end

@implementation PPFulfillmentInfoCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerMedium);
        [self.contentView addSubview:_cardView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontMedium:PPFontFootnote];
        _titleLabel.textColor = PPF_SubInkColor();
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_titleLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:PPFontBody];
        _valueLabel.textColor = PPF_InkColor();
        _valueLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _valueLabel.numberOfLines = 0;
        [_cardView addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],

            [_valueLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_valueLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _titleLabel.text = nil;
    _valueLabel.text = nil;
    _valueLabel.textColor = PPF_InkColor();
}

- (void)configureTitle:(NSString *)title value:(NSString *)value isEmphasized:(BOOL)isEmphasized {
    self.titleLabel.text = title ?: @"";
    self.valueLabel.text = value.length ? value : @"-";
    if (isEmphasized) {
        self.valueLabel.textColor = PPF_AccentColor();
        self.valueLabel.font = [Styling fontBold:PPFontTitle3];
    } else {
        self.valueLabel.textColor = PPF_InkColor();
        self.valueLabel.font = [Styling fontBold:PPFontBody];
    }
}

@end

#pragma mark - State Cell

@interface PPF_StateCell : UITableViewCell
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (void)configureWithText:(NSString *)text loading:(BOOL)loading;
@end

@implementation PPF_StateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _messageLabel = [UILabel new];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.font = [Styling fontMedium:PPFontCallout];
        _messageLabel.textColor = PPF_SubInkColor();
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 0;
        [self.contentView addSubview:_messageLabel];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        _spinner.color = PPF_AccentColor();
        [self.contentView addSubview:_spinner];

        [NSLayoutConstraint activateConstraints:@[
            [_messageLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_messageLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-12.0],
            [_messageLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceXL],
            [_messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceXL],

            [_spinner.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_spinner.topAnchor constraintEqualToAnchor:_messageLabel.bottomAnchor constant:PPSpaceMD],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:180.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _messageLabel.text = nil;
    [_spinner stopAnimating];
}

- (void)configureWithText:(NSString *)text loading:(BOOL)loading {
    _messageLabel.text = text;
    if (loading) {
        [_spinner startAnimating];
        _messageLabel.alpha = 0.7;
    } else {
        [_spinner stopAnimating];
        _messageLabel.alpha = 1.0;
    }
}

@end

#pragma mark - Empty State Cell

@interface PPF_EmptyStateCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) NSLayoutConstraint *subtitleBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *retryBottomConstraint;
@property (nonatomic, copy, nullable) void (^onRetry)(void);
- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                  iconName:(NSString *)iconName
                showsRetry:(BOOL)showsRetry;
@end

@implementation PPF_EmptyStateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _iconView = [UIImageView new];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = PPF_GoldInkColor();
        _iconView.backgroundColor = PPF_GoldSoftColor();
        _iconView.layer.cornerRadius = PPCornerMedium;
        if (@available(iOS 13.0, *)) _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        _iconView.isAccessibilityElement = NO;
        [self.contentView addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:PPFontTitle3];
        _titleLabel.textColor = PPF_InkColor();
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _titleLabel.numberOfLines = 0;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:PPFontSubheadline];
        _subtitleLabel.textColor = PPF_SubInkColor();
        _subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _subtitleLabel.numberOfLines = 0;
        [self.contentView addSubview:_subtitleLabel];

        _retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
        _retryButton.titleLabel.font = [Styling fontBold:PPFontCallout];
        _retryButton.tintColor = PPF_GoldInkColor();
        [_retryButton setTitleColor:PPF_GoldInkColor() forState:UIControlStateNormal];
        [_retryButton addTarget:self action:@selector(pp_handleRetry) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_retryButton];

        _subtitleBottomConstraint = [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceXL];
        _retryBottomConstraint = [self.retryButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceXL];
        _subtitleBottomConstraint.active = YES;
        _retryBottomConstraint.active = NO;

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceXXXL],
            [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:56.0],
            [_iconView.heightAnchor constraintEqualToConstant:56.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:PPSpaceMD],
            [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceXL],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceXL],
            [_titleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],
            [_subtitleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceXXL],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceXXL],
            [_subtitleLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],

            [_retryButton.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:PPSpaceBase],
            [_retryButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        ]];
    }
    return self;
}

- (void)pp_handleRetry {
    PPHapticTouch();
    if (self.onRetry) self.onRetry();
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _titleLabel.text = nil;
    _subtitleLabel.text = nil;
    _iconView.image = nil;
    _onRetry = nil;
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                  iconName:(NSString *)iconName
                showsRetry:(BOOL)showsRetry {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.iconView.image = [UIImage systemImageNamed:iconName];
    self.retryButton.hidden = !showsRetry;
    self.subtitleBottomConstraint.active = !showsRetry;
    self.retryBottomConstraint.active = showsRetry;
    if (showsRetry) {
        [self.retryButton setTitle:kLang(@"Fulfillment_Retry") forState:UIControlStateNormal];
    }
}

@end

#pragma mark - Overview Grid Cell (Detail)

@interface PPF_KeyValueGridCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
- (void)configureWithPairs:(NSArray<NSArray<NSString *> *> *)pairs;
@end

@implementation PPF_KeyValueGridCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerCard);
        [self.contentView addSubview:_cardView];

        UIStackView *grid = [UIStackView new];
        grid.translatesAutoresizingMaskIntoConstraints = NO;
        grid.axis = UILayoutConstraintAxisVertical;
        grid.distribution = UIStackViewDistributionFillEqually;
        grid.spacing = 10.0;
        grid.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [_cardView addSubview:grid];

        UIStackView *row1 = [self buildRow];
        UIStackView *row2 = [self buildRow];
        [grid addArrangedSubview:row1];
        [grid addArrangedSubview:row2];
        row1.tag = 601;
        row2.tag = 602;

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

            [grid.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:16.0],
            [grid.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [grid.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],
            [grid.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-16.0],
            [grid.heightAnchor constraintEqualToConstant:72.0],
        ]];
    }
    return self;
}

- (UIStackView *)buildRow {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 10.0;
    row.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [row addArrangedSubview:[self buildTile]];
    [row addArrangedSubview:[self buildTile]];
    return row;
}

- (UIView *)buildTile {
    UIView *tile = [UIView new];
    tile.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *tLabel = [UILabel new];
    tLabel.translatesAutoresizingMaskIntoConstraints = NO;
    tLabel.font = [Styling fontMedium:PPFontCaption1];
    tLabel.textColor = PPF_SubInkColor();
    tLabel.textAlignment = [Language alignmentForCurrentLanguage];
    tLabel.numberOfLines = 1;
    tLabel.adjustsFontSizeToFitWidth = YES;
    tLabel.minimumScaleFactor = 0.7;
    [tile addSubview:tLabel];

    UILabel *vLabel = [UILabel new];
    vLabel.translatesAutoresizingMaskIntoConstraints = NO;
    vLabel.font = [Styling fontBold:PPFontSubheadline];
    vLabel.textColor = PPF_InkColor();
    vLabel.textAlignment = [Language alignmentForCurrentLanguage];
    vLabel.numberOfLines = 1;
    vLabel.adjustsFontSizeToFitWidth = YES;
    vLabel.minimumScaleFactor = 0.6;
    [tile addSubview:vLabel];

    [NSLayoutConstraint activateConstraints:@[
        [tLabel.topAnchor constraintEqualToAnchor:tile.topAnchor],
        [tLabel.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
        [tLabel.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],

        [vLabel.topAnchor constraintEqualToAnchor:tLabel.bottomAnchor constant:3.0],
        [vLabel.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
        [vLabel.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
    ]];
    return tile;
}

- (void)configureWithPairs:(NSArray<NSArray<NSString *> *> *)pairs {
    UIStackView *grid = (UIStackView *)self.cardView.subviews.lastObject;
    for (NSInteger row = 0; row < 2; row++) {
        UIStackView *rowStack = (UIStackView *)grid.arrangedSubviews[row];
        for (NSInteger col = 0; col < 2; col++) {
            NSArray *pair = pairs[row * 2 + col];
            UIView *tile = rowStack.arrangedSubviews[col];
            UILabel *tLabel = tile.subviews[0];
            UILabel *vLabel = tile.subviews[1];
            tLabel.text = pair[0];
            vLabel.text = pair[1];
        }
    }
}

@end

#pragma mark - Item Row Cell (Detail)

@interface PPF_ItemCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *indexLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *qtyLabel;
@property (nonatomic, strong) UILabel *priceLabel;
- (void)configureWithIndex:(NSInteger)index name:(NSString *)name qty:(NSNumber *)qty price:(NSNumber *)price currency:(NSString *)currency;
@end

@implementation PPF_ItemCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerMedium);
        [self.contentView addSubview:_cardView];

        _indexLabel = [UILabel new];
        _indexLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _indexLabel.font = [Styling fontBold:PPFontCaption1];
        _indexLabel.textColor = PPF_GoldInkColor();
        _indexLabel.backgroundColor = PPF_GoldSoftColor();
        _indexLabel.textAlignment = NSTextAlignmentCenter;
        _indexLabel.layer.cornerRadius = 8.0;
        _indexLabel.layer.masksToBounds = YES;
        [_cardView addSubview:_indexLabel];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [Styling fontBold:PPFontSubheadline];
        _nameLabel.textColor = PPF_InkColor();
        _nameLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _nameLabel.numberOfLines = 2;
        [_cardView addSubview:_nameLabel];

        _qtyLabel = [UILabel new];
        _qtyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _qtyLabel.font = [Styling fontMedium:PPFontCaption1];
        _qtyLabel.textColor = PPF_SubInkColor();
        _qtyLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_qtyLabel];

        _priceLabel = [UILabel new];
        _priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _priceLabel.font = [Styling fontBold:PPFontCallout];
        _priceLabel.textColor = PPF_InkColor();
        _priceLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_priceLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

            [_indexLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14.0],
            [_indexLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_indexLabel.widthAnchor constraintEqualToConstant:30.0],
            [_indexLabel.heightAnchor constraintEqualToConstant:30.0],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_indexLabel.trailingAnchor constant:10.0],
            [_nameLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12.0],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_priceLabel.leadingAnchor constant:-10.0],

            [_qtyLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_qtyLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2.0],
            [_qtyLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-12.0],

            [_priceLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14.0],
            [_priceLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _indexLabel.text = nil;
    _nameLabel.text = nil;
    _qtyLabel.text = nil;
    _priceLabel.text = nil;
}

- (void)configureWithIndex:(NSInteger)index name:(NSString *)name qty:(NSNumber *)qty price:(NSNumber *)price currency:(NSString *)currency {
    self.indexLabel.text = [NSString stringWithFormat:@"%02ld", (long)index];
    self.nameLabel.text = name.length ? name : kLang(@"Fulfillment_Item");
    self.qtyLabel.text = [NSString stringWithFormat:@"×%ld", (long)qty.integerValue];
    self.priceLabel.text = PPF_MoneyString(price, currency);
}

@end

#pragma mark - Settlement Card Cell (Detail)

@interface PPF_SettlementCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
- (void)configureWithSubtotal:(NSNumber *)subtotal commission:(NSNumber *)commission net:(NSNumber *)net currency:(NSString *)currency;
@end

@implementation PPF_SettlementCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerCard);
        [self.contentView addSubview:_cardView];

        UIStackView *rows = [UIStackView new];
        rows.translatesAutoresizingMaskIntoConstraints = NO;
        rows.axis = UILayoutConstraintAxisVertical;
        rows.distribution = UIStackViewDistributionFillEqually;
        rows.spacing = 1.0;
        rows.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [_cardView addSubview:rows];

        UIView *subtotalRow = [self buildRowWithTitle:kLang(@"Fulfillment_Subtotal") emphasized:NO];
        UIView *commissionRow = [self buildRowWithTitle:kLang(@"Fulfillment_PlatformCommission") emphasized:NO];
        UIView *netRow = [self buildRowWithTitle:kLang(@"Fulfillment_ProviderNet") emphasized:YES];
        [rows addArrangedSubview:subtotalRow];
        [rows addArrangedSubview:commissionRow];
        [rows addArrangedSubview:netRow];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

            [rows.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:6.0],
            [rows.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [rows.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],
            [rows.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-6.0],
            [rows.heightAnchor constraintEqualToConstant:108.0],
        ]];
    }
    return self;
}

- (UIView *)buildRowWithTitle:(NSString *)title emphasized:(BOOL)emphasized {
    UIView *row = [UIView new];
    row.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    row.layer.cornerRadius = 10.0;
    if (emphasized) row.backgroundColor = PPF_GoldSoftColor();

    UILabel *tLabel = [UILabel new];
    tLabel.translatesAutoresizingMaskIntoConstraints = NO;
    tLabel.text = title;
    tLabel.font = [Styling fontMedium:PPFontFootnote];
    tLabel.textColor = emphasized ? PPF_GoldInkColor() : PPF_SubInkColor();
    tLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [row addSubview:tLabel];

    UILabel *vLabel = [UILabel new];
    vLabel.translatesAutoresizingMaskIntoConstraints = NO;
    vLabel.font = [Styling fontBold:emphasized ? PPFontTitle3 : PPFontBody];
    vLabel.textColor = emphasized ? PPF_GoldInkColor() : PPF_InkColor();
    vLabel.textAlignment = [Language alignmentForCurrentLanguage];
    vLabel.adjustsFontSizeToFitWidth = YES;
    vLabel.minimumScaleFactor = 0.6;
    [row addSubview:vLabel];
    vLabel.tag = 701;

    [NSLayoutConstraint activateConstraints:@[
        [tLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12.0],
        [tLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [tLabel.trailingAnchor constraintLessThanOrEqualToAnchor:vLabel.leadingAnchor constant:-8.0],

        [vLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12.0],
        [vLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [vLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],
    ]];
    return row;
}

- (void)configureWithSubtotal:(NSNumber *)subtotal commission:(NSNumber *)commission net:(NSNumber *)net currency:(NSString *)currency {
    UIStackView *rows = (UIStackView *)self.cardView.subviews.lastObject;
    for (NSInteger i = 0; i < 3; i++) {
        UIView *row = rows.arrangedSubviews[i];
        UILabel *vLabel = (UILabel *)[row viewWithTag:701];
        NSNumber *value = i == 0 ? subtotal : (i == 1 ? commission : net);
        vLabel.text = PPF_MoneyString(value, currency);
    }
}

@end

#pragma mark - Audit Row Cell (Detail)

@interface PPF_AuditCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *reasonLabel;
- (void)configureWithDate:(NSDate *)date actor:(NSString *)actor reason:(NSString *)reason;
@end

@implementation PPF_AuditCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerMedium);
        [self.contentView addSubview:_cardView];

        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.checkmark"]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = PPF_GoldInkColor();
        _iconView.backgroundColor = PPF_GoldSoftColor();
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.layer.cornerRadius = 10.0;
        _iconView.layer.masksToBounds = YES;
        _iconView.isAccessibilityElement = NO;
        [_cardView addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:PPFontSubheadline];
        _titleLabel.textColor = PPF_InkColor();
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_titleLabel];

        _metaLabel = [UILabel new];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel.font = [Styling fontRegular:PPFontCaption1];
        _metaLabel.textColor = PPF_SubInkColor();
        _metaLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _metaLabel.numberOfLines = 0;
        [_cardView addSubview:_metaLabel];

        _reasonLabel = [UILabel new];
        _reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _reasonLabel.font = [Styling fontMedium:PPFontFootnote];
        _reasonLabel.textColor = PPF_GoldInkColor();
        _reasonLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _reasonLabel.numberOfLines = 0;
        [_cardView addSubview:_reasonLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

            [_iconView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14.0],
            [_iconView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_iconView.widthAnchor constraintEqualToConstant:36.0],
            [_iconView.heightAnchor constraintEqualToConstant:36.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.topAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14.0],

            [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2.0],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

            [_reasonLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_reasonLabel.topAnchor constraintEqualToAnchor:_metaLabel.bottomAnchor constant:8.0],
            [_reasonLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_reasonLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _titleLabel.text = nil;
    _metaLabel.text = nil;
    _reasonLabel.text = nil;
}

- (void)configureWithDate:(NSDate *)date actor:(NSString *)actor reason:(NSString *)reason {
    self.titleLabel.text = kLang(@"Fulfillment_AdminOverride");
    NSString *meta = PPF_DateString(date);
    if (actor.length) meta = [NSString stringWithFormat:@"%@ · %@", meta, actor];
    self.metaLabel.text = meta;
    self.reasonLabel.text = reason.length ? reason : @"—";
}

@end

#pragma mark - Timeline Cell (Detail)

@interface PPF_TimelineCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *dotView;
@property (nonatomic, strong) UIView *connectorView;
@property (nonatomic, strong) UILabel *actionLabel;
@property (nonatomic, strong) UILabel *routeLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, assign) BOOL hasAnimatedEntrance;
- (void)configureWithAction:(NSString *)action
                 fromStatus:(NSString *)fromStatus
                   toStatus:(NSString *)toStatus
                       date:(nullable NSDate *)date
                      actor:(nullable NSString *)actor
                      color:(UIColor *)color
                     isLast:(BOOL)isLast
                   animated:(BOOL)animated;
@end

@implementation PPF_TimelineCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerMedium);
        [self.contentView addSubview:_cardView];

        // Marker: ring dot (Console parity)
        _dotView = [UIView new];
        _dotView.translatesAutoresizingMaskIntoConstraints = NO;
        _dotView.layer.cornerRadius = 6.0;
        _dotView.layer.borderWidth = 2.0;
        _dotView.layer.borderColor = PPF_SurfaceColor().CGColor;
        _dotView.layer.shadowColor = PPF_NeutralToneColor().CGColor;
        _dotView.layer.shadowOpacity = 0.3;
        _dotView.layer.shadowRadius = 3.0;
        _dotView.layer.shadowOffset = CGSizeMake(0, 0);
        _dotView.clipsToBounds = NO;
        [_cardView addSubview:_dotView];

        _connectorView = [UIView new];
        _connectorView.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_connectorView];

        _actionLabel = [UILabel new];
        _actionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _actionLabel.font = [Styling fontBold:PPFontSubheadline];
        _actionLabel.textColor = PPF_InkColor();
        _actionLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _actionLabel.numberOfLines = 0;
        [_cardView addSubview:_actionLabel];

        _routeLabel = [UILabel new];
        _routeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _routeLabel.font = [Styling fontBold:PPFontFootnote];
        _routeLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _routeLabel.numberOfLines = 0;
        [_cardView addSubview:_routeLabel];

        _metaLabel = [UILabel new];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel.font = [Styling fontRegular:PPFontCaption2];
        _metaLabel.textColor = PPF_TertiaryInkColor();
        _metaLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _metaLabel.numberOfLines = 0;
        [_cardView addSubview:_metaLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            [_dotView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_dotView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:17.0],
            [_dotView.widthAnchor constraintEqualToConstant:12.0],
            [_dotView.heightAnchor constraintEqualToConstant:12.0],

            [_connectorView.leadingAnchor constraintEqualToAnchor:_dotView.centerXAnchor constant:-1.0],
            [_connectorView.topAnchor constraintEqualToAnchor:_dotView.bottomAnchor],
            [_connectorView.widthAnchor constraintEqualToConstant:2.0],
            [_connectorView.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor],

            [_actionLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_actionLabel.leadingAnchor constraintEqualToAnchor:_dotView.trailingAnchor constant:12.0],
            [_actionLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],

            [_routeLabel.topAnchor constraintEqualToAnchor:_actionLabel.bottomAnchor constant:3.0],
            [_routeLabel.leadingAnchor constraintEqualToAnchor:_actionLabel.leadingAnchor],
            [_routeLabel.trailingAnchor constraintEqualToAnchor:_actionLabel.trailingAnchor],

            [_metaLabel.topAnchor constraintEqualToAnchor:_routeLabel.bottomAnchor constant:3.0],
            [_metaLabel.leadingAnchor constraintEqualToAnchor:_actionLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:_actionLabel.trailingAnchor],
            [_metaLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _hasAnimatedEntrance = NO;
    _actionLabel.text = nil;
    _routeLabel.text = nil;
    _metaLabel.text = nil;
    _connectorView.hidden = NO;
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
}

- (void)configureWithAction:(NSString *)action
                 fromStatus:(NSString *)fromStatus
                   toStatus:(NSString *)toStatus
                       date:(nullable NSDate *)date
                      actor:(nullable NSString *)actor
                      color:(UIColor *)color
                     isLast:(BOOL)isLast
                   animated:(BOOL)animated {
    self.actionLabel.text = action.length ? action : @"—";

    NSString *fromS = PPF_StatusText(fromStatus);
    NSString *toS = PPF_StatusText(toStatus);
    if (fromS.length && toS.length && ![fromS isEqualToString:toS]) {
        NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"%@  %@  %@", fromS, @"→", toS]
                attributes:@{ NSFontAttributeName: [Styling fontBold:PPFontFootnote],
                              NSForegroundColorAttributeName: PPF_SubInkColor() }];
        NSRange arrowRange = [attributed.string rangeOfString:@"→"];
        if (arrowRange.location != NSNotFound) {
            [attributed setAttributes:@{ NSFontAttributeName: [Styling fontBold:PPFontFootnote],
                                          NSForegroundColorAttributeName: PPF_GoldInkColor() }
                                range:arrowRange];
        }
        self.routeLabel.attributedText = attributed;
    } else if (toS.length) {
        self.routeLabel.attributedText = [[NSAttributedString alloc]
            initWithString:toS
                attributes:@{ NSFontAttributeName: [Styling fontBold:PPFontFootnote],
                              NSForegroundColorAttributeName: PPF_SubInkColor() }];
    } else {
        self.routeLabel.attributedText = nil;
    }

    NSMutableArray *meta = [NSMutableArray array];
    if (actor.length) [meta addObject:actor];
    if (date) [meta addObject:PPF_DateString(date)];
    self.metaLabel.text = meta.count ? [meta componentsJoinedByString:@"  ·  "] : @"—";

    self.dotView.backgroundColor = color;
    self.dotView.layer.borderColor = PPF_SurfaceColor().CGColor;
    self.dotView.layer.shadowColor = color.CGColor;
    self.connectorView.hidden = isLast;
    self.connectorView.backgroundColor = [color colorWithAlphaComponent:0.22];

    if (animated && !_hasAnimatedEntrance && !UIAccessibilityIsReduceMotionEnabled()) {
        _hasAnimatedEntrance = YES;
        self.contentView.alpha = 0.0;
        self.contentView.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
        [UIView animateWithDuration:0.34 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.contentView.alpha = 1.0;
            self.contentView.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

@end

#pragma mark - Detail View Controller

@interface PPFulfillmentDetailViewController ()
@property (nonatomic, strong) PPFulfillmentRecord *seedRecord;
@property (nonatomic, strong) PPFulfillmentRecord *detailRecord;
@property (nonatomic, copy) NSArray *events;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *userNames;
@property (nonatomic, strong) id<FIRListenerRegistration> eventsListener;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPF_HeroBandView *heroBand;
@property (nonatomic, strong) UILabel *statusPillLabel;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPFulfillmentDetailViewController

- (instancetype)initWithRecord:(PPFulfillmentRecord *)record {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _seedRecord = record;
        _detailRecord = record;
        _events = @[];
        _userNames = @{};
    }
    return self;
}

- (void)dealloc {
    [_eventsListener remove];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.seedRecord.parentOrderNumber.length ? [NSString stringWithFormat:@"#%@", self.seedRecord.parentOrderNumber] : self.seedRecord.fulfillmentID;
    self.view.backgroundColor = PPF_CanvasColor();
    self.tableView.backgroundColor = PPF_CanvasColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    [self.tableView registerClass:[PPFulfillmentInfoCell class] forCellReuseIdentifier:@"Info"];
    [self.tableView registerClass:[PPF_StateCell class] forCellReuseIdentifier:@"State"];
    [self.tableView registerClass:[PPF_KeyValueGridCell class] forCellReuseIdentifier:@"KVGrid"];
    [self.tableView registerClass:[PPF_ItemCell class] forCellReuseIdentifier:@"Item"];
    [self.tableView registerClass:[PPF_SettlementCell class] forCellReuseIdentifier:@"Settlement"];
    [self.tableView registerClass:[PPF_AuditCell class] forCellReuseIdentifier:@"Audit"];
    [self.tableView registerClass:[PPF_TimelineCell class] forCellReuseIdentifier:@"Timeline"];
    
    [self pp_buildHeader];
    [self pp_setupActionBar];
    [self loadDetail];
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = PPF_SurfaceColor();
    card.layer.cornerRadius = PPCornerHero;
    if (@available(iOS 13.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOffset = CGSizeMake(0.0, 18.0);
    card.layer.shadowRadius = 30.0;
    card.layer.shadowOpacity = 0.16;
    card.layer.masksToBounds = NO;
    [header addSubview:card];
    
    PPF_HeroBandView *band = [PPF_HeroBandView new];
    band.translatesAutoresizingMaskIntoConstraints = NO;
    band.layer.cornerRadius = PPCornerHero;
    [band setGlowColor:PPF_StatusHeroColor(self.detailRecord.status) animated:NO];
    [card addSubview:band];
    self.heroBand = band;

    PPF_AvatarView *cAvatar = [PPF_AvatarView new];
    cAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    cAvatar.heroStyle = YES;
    [card addSubview:cAvatar];

    UILabel *cName = [UILabel new];
    cName.translatesAutoresizingMaskIntoConstraints = NO;
    cName.font = [Styling fontBold:PPFontHeadline];
    cName.textColor = PPF_HeroTextColor();
    cName.adjustsFontSizeToFitWidth = YES;
    cName.minimumScaleFactor = 0.7;
    [card addSubview:cName];

    UIImageView *routeArrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right"]];
    routeArrow.translatesAutoresizingMaskIntoConstraints = NO;
    routeArrow.tintColor = PPF_GoldColor();
    if ([Language isRTL]) routeArrow.transform = CGAffineTransformMakeScale(-1.0, 1.0);
    [card addSubview:routeArrow];

    PPF_AvatarView *oAvatar = [PPF_AvatarView new];
    oAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    oAvatar.heroStyle = YES;
    [card addSubview:oAvatar];

    UILabel *oName = [UILabel new];
    oName.translatesAutoresizingMaskIntoConstraints = NO;
    oName.font = [Styling fontBold:PPFontHeadline];
    oName.textColor = PPF_HeroTextColor();
    oName.adjustsFontSizeToFitWidth = YES;
    oName.minimumScaleFactor = 0.7;
    [card addSubview:oName];

    UILabel *statusPill = [UILabel new];
    statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    statusPill.font = [Styling fontBold:PPFontFootnote];
    statusPill.textAlignment = NSTextAlignmentCenter;
    statusPill.layer.cornerRadius = PPCornerPill;
    statusPill.layer.masksToBounds = YES;
    [card addSubview:statusPill];
    self.statusPillLabel = statusPill;

    UILabel *modePill = [UILabel new];
    modePill.translatesAutoresizingMaskIntoConstraints = NO;
    modePill.font = [Styling fontMedium:PPFontCaption1];
    modePill.textColor = [PPF_HeroTextColor() colorWithAlphaComponent:0.66];
    modePill.textAlignment = NSTextAlignmentNatural;
    [card addSubview:modePill];

    NSString *custName = self.userNames[self.detailRecord.customerID] ?: self.detailRecord.customerName;
    if (!custName.length) custName = kLang(@"Fulfillment_UnknownCustomer");
    [cAvatar setName:custName isLarge:YES];
    cName.text = custName;

    BOOL isPlatform = [self.detailRecord.ownerType isEqualToString:@"platform"] || !self.detailRecord.ownerID.length;
    NSString *ownName = isPlatform ? kLang(@"Fulfillment_Filter_Platform") : (self.userNames[self.detailRecord.ownerID] ?: kLang(@"Fulfillment_UnknownCustomer"));
    [oAvatar setName:ownName isLarge:YES];
    oName.text = ownName;

    UIColor *sColor = PPF_StatusColor(self.detailRecord.status);
    statusPill.text = [NSString stringWithFormat:@"  %@  ", PPF_StatusText(self.detailRecord.status)];
    statusPill.textColor = [PPF_StatusHeroColor(self.detailRecord.status) colorWithAlphaComponent:1.0];
    statusPill.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.22];
    modePill.text = [self.detailRecord.fulfillmentMode isEqualToString:@"partner_managed"] ? kLang(@"Fulfillment_Filter_Partner") : kLang(@"Fulfillment_Filter_Platform");

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:16.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],

        [band.topAnchor constraintEqualToAnchor:card.topAnchor],
        [band.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [band.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [band.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [cAvatar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [cAvatar.topAnchor constraintEqualToAnchor:card.topAnchor constant:20.0],
        [cAvatar.widthAnchor constraintEqualToConstant:44.0],
        [cAvatar.heightAnchor constraintEqualToConstant:44.0],

        [cName.leadingAnchor constraintEqualToAnchor:cAvatar.trailingAnchor constant:10.0],
        [cName.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],
        [cName.widthAnchor constraintLessThanOrEqualToConstant:104.0],

        [routeArrow.leadingAnchor constraintEqualToAnchor:cName.trailingAnchor constant:8.0],
        [routeArrow.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],
        [routeArrow.widthAnchor constraintEqualToConstant:16.0],
        [routeArrow.heightAnchor constraintEqualToConstant:16.0],

        [oAvatar.leadingAnchor constraintEqualToAnchor:routeArrow.trailingAnchor constant:8.0],
        [oAvatar.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],
        [oAvatar.widthAnchor constraintEqualToConstant:44.0],
        [oAvatar.heightAnchor constraintEqualToConstant:44.0],

        [oName.leadingAnchor constraintEqualToAnchor:oAvatar.trailingAnchor constant:10.0],
        [oName.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],
        [oName.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-18.0],

        [statusPill.leadingAnchor constraintEqualToAnchor:cAvatar.leadingAnchor],
        [statusPill.topAnchor constraintEqualToAnchor:cAvatar.bottomAnchor constant:16.0],
        [statusPill.heightAnchor constraintEqualToConstant:30.0],
        [statusPill.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18.0],

        [modePill.leadingAnchor constraintEqualToAnchor:statusPill.trailingAnchor constant:12.0],
        [modePill.centerYAnchor constraintEqualToAnchor:statusPill.centerYAnchor],
        [modePill.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-18.0],
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_sizeHeaderToFit];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGRect frame = self.headerContainer.frame;
    frame.size.width = width;
    self.headerContainer.frame = frame;
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    frame.size.height = ceil(MAX(1.0, height));
    self.headerContainer.frame = frame;
    self.tableView.tableHeaderView = self.headerContainer;
}

- (void)pp_setupActionBar {
    UIBarButtonItem *overrideItem = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Fulfillment_AdminOverride") style:UIBarButtonItemStylePlain target:self action:@selector(presentAdminOverrideSheet)];
    overrideItem.tintColor = UIColor.systemRedColor;
    self.navigationItem.rightBarButtonItem = overrideItem;
}

- (void)loadDetail {
    self.isLoading = YES;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    
    [[PPFulfillmentService shared] fetchFulfillmentDetail:self.seedRecord.fulfillmentID completion:^(PPFulfillmentRecord *detail, NSArray *events, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                weakSelf.detailRecord = detail ?: weakSelf.seedRecord;
                weakSelf.events = events ?: @[];
                [weakSelf pp_buildHeader];
            }
            [weakSelf.tableView reloadData];
        });
    }];

    // Live event timeline
    self.eventsListener = [[PPFulfillmentService shared] observeFulfillmentEvents:self.seedRecord.fulfillmentID completion:^(NSArray<NSDictionary *> *events, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && events.count > 0) {
                weakSelf.events = events;
                [weakSelf.tableView reloadData];
            }
        });
    }];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5; // Overview, Composition, Settlement, Audit (if present), Timeline
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isLoading) return section == 0 ? 1 : 0;
    PPFulfillmentRecord *r = self.detailRecord ?: self.seedRecord;
    
    if (section == 0) return 1; // Overview grid card
    if (section == 1) return MAX(r.items.count, 1);
    if (section == 2) return 1; // Settlement card
    if (section == 3) return r.adminOverrideAt ? 1 : 0;
    return MAX(self.events.count, 1);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 3 && !self.detailRecord.adminOverrideAt) return 0.01;
    return 38.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 3 && !self.detailRecord.adminOverrideAt) return [UIView new];
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [Styling fontBold:PPFontTitle3];
    label.textColor = PPF_InkColor();
    label.textAlignment = [Language alignmentForCurrentLanguage];
    
    if (section == 0) label.text = kLang(@"Fulfillment_DetailOverview");
    else if (section == 1) label.text = kLang(@"Fulfillment_DetailItems");
    else if (section == 2) label.text = kLang(@"Fulfillment_DetailSettlement");
    else if (section == 3) label.text = kLang(@"Fulfillment_AdminOverride");
    else label.text = kLang(@"Fulfillment_DetailTimeline");
    
    [view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:PPScreenMargin],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-PPScreenMargin],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-4.0]
    ]];
    return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isLoading) {
        PPF_StateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"State" forIndexPath:indexPath];
        [cell configureWithText:kLang(@"Loading") loading:YES];
        return cell;
    }

    PPFulfillmentRecord *r = self.detailRecord ?: self.seedRecord;
    
    // Overview Section
    if (indexPath.section == 0) {
        PPF_KeyValueGridCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KVGrid" forIndexPath:indexPath];
        NSString *orderNum = r.parentOrderNumber.length ? r.parentOrderNumber : r.parentOrderID;
        NSDictionary *m = r.money ?: @{};
        NSString *currency = m[@"currency"];
        NSString *modeText = [r.fulfillmentMode isEqualToString:@"partner_managed"] ? kLang(@"Fulfillment_Filter_Partner") : kLang(@"Fulfillment_Filter_Platform");
        [cell configureWithPairs:@[
            @[kLang(@"Fulfillment_DetailOrder"), orderNum.length ? [NSString stringWithFormat:@"#%@", orderNum] : @"-"],
            @[kLang(@"Fulfillment_Ref"), r.fulfillmentID ?: @"-"],
            @[kLang(@"Fulfillment_DetailCreated"), PPF_DateString(r.createdAt)],
            @[kLang(@"Fulfillment_DetailUpdated"), PPF_DateString(r.updatedAt)],
            @[kLang(@"Fulfillment_DetailMode"), modeText],
            @[kLang(@"Fulfillment_ProviderNet"), PPF_MoneyString(m[@"providerNet"], currency)]
        ]];
        return cell;
    }

    // Items Section
    if (indexPath.section == 1) {
        if (r.items.count == 0) {
            PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
            [cell configureTitle:kLang(@"Fulfillment_Item") value:kLang(@"Fulfillment_NoItems") isEmphasized:NO];
            return cell;
        }
        PPF_ItemCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Item" forIndexPath:indexPath];
        NSDictionary *item = [r.items[indexPath.row] isKindOfClass:NSDictionary.class] ? r.items[indexPath.row] : @{};
        NSString *name = PPSafeString(item[@"name"]);
        if (!name.length) name = PPSafeString(item[@"title"]);
        if (!name.length) name = PPSafeString(item[@"itemName"]);
        if (!name.length) name = PPSafeString(item[@"itemId"]);
        NSNumber *qty = [item[@"quantity"] isKindOfClass:NSNumber.class] ? item[@"quantity"] : ([item[@"qty"] isKindOfClass:NSNumber.class] ? item[@"qty"] : @(1));
        NSNumber *price = [item[@"price"] isKindOfClass:NSNumber.class] ? item[@"price"] : nil;
        NSString *currency = r.money[@"currency"];
        [cell configureWithIndex:indexPath.row name:name.length ? name : kLang(@"Fulfillment_Item")
                             qty:qty price:price currency:currency];
        return cell;
    }

    // Settlement Section
    if (indexPath.section == 2) {
        PPF_SettlementCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Settlement" forIndexPath:indexPath];
        NSDictionary *m = r.money ?: @{};
        [cell configureWithSubtotal:m[@"subtotal"] commission:m[@"platformCommission"] net:m[@"providerNet"] currency:m[@"currency"]];
        return cell;
    }

    // Admin Audit Section
    if (indexPath.section == 3) {
        PPF_AuditCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Audit" forIndexPath:indexPath];
        NSString *by = r.adminOverrideBy.length ? r.adminOverrideBy : kLang(@"Fulfillment_Event");
        [cell configureWithDate:r.adminOverrideAt actor:by reason:r.adminOverrideReason.length ? r.adminOverrideReason : @"-"];
        return cell;
    }

    // Timeline Section
    PPF_TimelineCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Timeline" forIndexPath:indexPath];
    if (self.events.count == 0) {
        [cell configureWithAction:kLang(@"Fulfillment_Event")
                       fromStatus:nil
                         toStatus:kLang(@"Fulfillment_NoEvents")
                             date:nil
                            actor:nil
                            color:UIColor.systemGrayColor
                           isLast:YES
                         animated:NO];
        return cell;
    }
    NSDictionary *event = [self.events[indexPath.row] isKindOfClass:NSDictionary.class] ? self.events[indexPath.row] : @{};
    NSString *action = PPSafeString(event[@"action"]);
    if (!action.length) action = PPSafeString(event[@"type"]);
    NSString *fromStatus = PPSafeString(event[@"fromStatus"]);
    NSString *toStatus = PPSafeString(event[@"toStatus"]);
    NSString *actor = PPSafeString(event[@"actor"]);
    if (!actor.length) actor = PPSafeString(event[@"by"]);
    if (!actor.length) actor = PPSafeString(event[@"performedBy"]);
    if (!actor.length) actor = PPSafeString(event[@"userId"]);
    id createdAt = event[@"createdAt"];
    NSDate *date = [createdAt isKindOfClass:FIRTimestamp.class] ? [(FIRTimestamp *)createdAt dateValue] : nil;
    UIColor *color = PPF_StatusColor(toStatus.length ? toStatus : fromStatus);
    BOOL isLast = indexPath.row == (NSInteger)(self.events.count - 1);
    [cell configureWithAction:[action stringByReplacingOccurrencesOfString:@"_" withString:@" "].capitalizedString
                   fromStatus:fromStatus
                     toStatus:toStatus
                         date:date
                        actor:actor
                        color:color
                       isLast:isLast
                     animated:YES];
    return cell;
}

#pragma mark - Admin Override Action

- (void)presentAdminOverrideSheet {
    PPHapticTouch();
    PPFulfillmentRecord *r = self.detailRecord ?: self.seedRecord;
    NSArray *allowedTargets = [PPFulfillmentService allowedOverrideTargetsForStatus:r.status];
    
    if (allowedTargets.count == 0) {
        [AlertHelper showAlertIn:self title:kLang(@"Fulfillment_AdminOverride") subtitle:kLang(@"Fulfillment_OverrideSkipped")];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Fulfillment_AdminOverride")
                                                                   message:kLang(@"Fulfillment_ReasonPlaceholder")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *targetStatus in allowedTargets) {
        NSString *title = PPF_StatusText(targetStatus);
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self promptReasonAndSubmitOverrideForTargetStatus:targetStatus];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptReasonAndSubmitOverrideForTargetStatus:(NSString *)targetStatus {
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ → %@", kLang(@"Fulfillment_TargetStatus"), PPF_StatusText(targetStatus)]
                                                                    message:kLang(@"Fulfillment_Reason")
                                                             preferredStyle:UIAlertControllerStyleAlert];
    
    [prompt addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Fulfillment_ReasonPlaceholder");
    }];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Fulfillment_NotePlaceholder");
    }];

    __weak typeof(self) weakSelf = self;
    [prompt addAction:[UIAlertAction actionWithTitle:kLang(@"Fulfillment_ConfirmOverride") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSString *reason = prompt.textFields.firstObject.text;
        NSString *note = prompt.textFields.count > 1 ? prompt.textFields[1].text : @"";
        
        if (!reason.length) {
            PPHapticError();
            [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:kLang(@"Fulfillment_Reason")];
            return;
        }
        
        PPHapticTouch();
        [[PPFulfillmentService shared] adminOverrideFulfillment:weakSelf.seedRecord.fulfillmentID
                                                   targetStatus:targetStatus
                                                         reason:reason
                                                           note:note
                                                         notify:YES
                                                     completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    PPHapticError();
                    [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                } else {
                    PPHapticSuccess();
                    [AlertHelper showAlertIn:weakSelf title:kLang(@"Success") subtitle:kLang(@"Fulfillment_OverrideSuccess")];
                    [weakSelf pp_bloomStatusChange:targetStatus];
                    [weakSelf loadDetail];
                }
            });
        }];
    }]];
    
    [prompt addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:prompt animated:YES completion:nil];
}

#pragma mark - Status Bloom (override success signature)

- (void)pp_bloomStatusChange:(NSString *)status {
    UIColor *heroColor = PPF_StatusHeroColor(status);
    [self.heroBand setGlowColor:heroColor animated:YES];

    self.statusPillLabel.text = [NSString stringWithFormat:@"  %@  ", PPF_StatusText(status)];
    self.statusPillLabel.textColor = [PPF_StatusHeroColor(status) colorWithAlphaComponent:1.0];

    if (UIAccessibilityIsReduceMotionEnabled()) return;
    self.statusPillLabel.layer.transform = CATransform3DMakeScale(0.85, 0.85, 1.0);
    self.statusPillLabel.layer.opacity = 0.7f;
    [UIView animateWithDuration:0.5
                          delay:0
         usingSpringWithDamping:0.55
          initialSpringVelocity:0.7
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.statusPillLabel.layer.transform = CATransform3DIdentity;
        self.statusPillLabel.layer.opacity = 1.0f;
    } completion:nil];
}

@end

#pragma mark - Main List View Controller

@interface PPFulfillmentOrdersViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<PPFulfillmentRecord *> *records;
@property (nonatomic, strong) NSArray<PPFulfillmentRecord *> *visibleRecords;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *userNames;
@property (nonatomic, strong) id<FIRListenerRegistration> fulfillmentsListener;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPF_CommandHeroView *heroView;
@property (nonatomic, strong) UILabel *resultsHeadLabel;

@property (nonatomic, strong) UIScrollView *chipsScrollView;
@property (nonatomic, strong) UIStackView *chipsStack;
@property (nonatomic, strong) NSDate *lastSyncDate;
@property (nonatomic, strong) NSTimer *syncTimer;

@property (nonatomic, copy) NSString *filterStatus;
@property (nonatomic, copy) NSString *filterQuick;
@property (nonatomic, copy) NSString *filterOwnerType;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;

@property (nonatomic, strong) NSMutableSet<NSString *> *pulsingIDs;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *prevStatusByID;
@end

@implementation PPFulfillmentOrdersViewController

- (void)dealloc {
    [_fulfillmentsListener remove];
    [_syncTimer invalidate];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Fulfillment_Title");
    self.records = @[];
    self.visibleRecords = @[];
    self.userNames = @{};
    self.filterStatus = @"";
    self.filterQuick = @"";
    self.filterOwnerType = @"";
    self.pulsingIDs = [NSMutableSet set];
    self.prevStatusByID = @{};

    [self pp_configureTableView];
    [self pp_configureSearch];
    [self pp_buildHeader];
    [self pp_setupNavigationItems];
    [self pp_startSyncTimer];

    [self startLiveSubscription];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.syncTimer invalidate];
    self.syncTimer = nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_startSyncTimer];
    [self pp_updateLiveIndicator];
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPF_CanvasColor();
    self.tableView.backgroundColor = PPF_CanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 110.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    
    [self.tableView registerClass:[PPF_OrderCell class] forCellReuseIdentifier:@"Order"];
    [self.tableView registerClass:[PPF_StateCell class] forCellReuseIdentifier:@"State"];
    [self.tableView registerClass:[PPF_EmptyStateCell class] forCellReuseIdentifier:@"Empty"];

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = PPF_AccentColor();
    [refresh addTarget:self action:@selector(startLiveSubscription) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)pp_configureSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = kLang(@"Fulfillment_SearchPlaceholder");
    self.searchController.searchBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.searchController.searchBar.tintColor = PPF_AccentColor();
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)pp_setupNavigationItems {
    UIBarButtonItem *filterItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(presentFilterOptionsSheet)];
    filterItem.tintColor = PPF_AccentColor();

    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(startLiveSubscription)];
    refreshItem.tintColor = PPF_AccentColor();

    self.navigationItem.rightBarButtonItems = @[refreshItem, filterItem];
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    PPF_CommandHeroView *hero = [PPF_CommandHeroView new];
    [header addSubview:hero];
    self.heroView = hero;

    [self pp_buildChipsRow];
    [header addSubview:_chipsScrollView];

    UILabel *resultsHead = [UILabel new];
    resultsHead.translatesAutoresizingMaskIntoConstraints = NO;
    resultsHead.font = [Styling fontMedium:PPFontFootnote];
    resultsHead.textColor = PPF_SubInkColor();
    resultsHead.textAlignment = [Language alignmentForCurrentLanguage];
    resultsHead.numberOfLines = 1;
    [header addSubview:resultsHead];
    _resultsHeadLabel = resultsHead;

    [NSLayoutConstraint activateConstraints:@[
        [hero.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceBase],
        [hero.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [hero.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],

        [_chipsScrollView.topAnchor constraintEqualToAnchor:hero.bottomAnchor constant:PPSpaceBase],
        [_chipsScrollView.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [_chipsScrollView.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [_chipsScrollView.heightAnchor constraintEqualToConstant:44.0],

        [_resultsHeadLabel.topAnchor constraintEqualToAnchor:_chipsScrollView.bottomAnchor constant:12.0],
        [_resultsHeadLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [_resultsHeadLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [_resultsHeadLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-2.0],
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_sizeHeaderToFit];
    [self pp_updateChipSelection];
    [self pp_updateResultsHead];
    [self pp_startLivePulse];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGRect frame = self.headerContainer.frame;
    frame.size.width = width;
    self.headerContainer.frame = frame;
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    frame.size.height = ceil(MAX(1.0, height));
    self.headerContainer.frame = frame;
    self.tableView.tableHeaderView = self.headerContainer;
}

#pragma mark - Live Sync Indicator

- (void)pp_startLivePulse {
    if (UIAccessibilityIsReduceMotionEnabled() || !self.heroView.liveDot) return;
    [self.heroView.liveDot.layer removeAllAnimations];
    self.heroView.liveDot.alpha = 1.0;
    [UIView animateWithDuration:1.1 delay:0.2 options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse | UIViewAnimationOptionCurveEaseInOut animations:^{
        self.heroView.liveDot.alpha = 0.25;
    } completion:nil];
}

- (void)pp_startSyncTimer {
    if (self.syncTimer) return;
    self.syncTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(pp_updateLiveIndicator) userInfo:nil repeats:YES];
}

- (void)pp_updateLiveIndicator {
    if (!self.heroView.syncCaptionLabel) return;
    NSString *text = [self pp_relativeSyncText];
    if (![text isEqualToString:self.heroView.syncCaptionLabel.text]) {
        [self.heroView setSyncCaption:text];
    }
}

- (NSString *)pp_relativeSyncText {
    if (!self.lastSyncDate) return kLang(@"Fulfillment_UpdatedJustNow");
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:self.lastSyncDate];
    if (interval < 60.0) return kLang(@"Fulfillment_UpdatedJustNow");
    NSInteger minutes = (NSInteger)(interval / 60.0);
    if (minutes < 60) {
        return [NSString stringWithFormat:kLang(@"Fulfillment_UpdatedAgo_Format"), [NSString stringWithFormat:@"%ldm", (long)minutes]];
    }
    NSInteger hours = minutes / 60;
    return [NSString stringWithFormat:kLang(@"Fulfillment_UpdatedAgo_Format"), [NSString stringWithFormat:@"%ldh", (long)hours]];
}

- (void)pp_updateResultsHead {
    if (!self.resultsHeadLabel) return;
    self.resultsHeadLabel.text = [NSString stringWithFormat:kLang(@"Fulfillment_Showing_Format"),
                                  @(self.visibleRecords.count), @(self.records.count)];
}

#pragma mark - Filter Chips Row

- (void)pp_buildChipsRow {
    _chipsScrollView = [UIScrollView new];
    _chipsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _chipsScrollView.showsHorizontalScrollIndicator = NO;
    _chipsScrollView.showsVerticalScrollIndicator = NO;
    _chipsScrollView.alwaysBounceHorizontal = YES;
    _chipsScrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    _chipsStack = [UIStackView new];
    _chipsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _chipsStack.axis = UILayoutConstraintAxisHorizontal;
    _chipsStack.spacing = 8.0;
    _chipsStack.alignment = UIStackViewAlignmentCenter;
    _chipsStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [_chipsScrollView addSubview:_chipsStack];

    [NSLayoutConstraint activateConstraints:@[
        [_chipsStack.topAnchor constraintEqualToAnchor:_chipsScrollView.topAnchor],
        [_chipsStack.leadingAnchor constraintEqualToAnchor:_chipsScrollView.leadingAnchor],
        [_chipsStack.trailingAnchor constraintEqualToAnchor:_chipsScrollView.trailingAnchor],
        [_chipsStack.bottomAnchor constraintEqualToAnchor:_chipsScrollView.bottomAnchor],
        [_chipsStack.heightAnchor constraintEqualToConstant:44.0],
    ]];

    [_chipsStack addArrangedSubview:[self pp_makeChipWithTitle:kLang(@"Fulfillment_Filter_All") tag:1000 action:@selector(pp_statusChipTapped:)]];
    [_chipsStack addArrangedSubview:[self pp_makeChipWithTitle:kLang(@"Fulfillment_Filter_Active") tag:1001 action:@selector(pp_statusChipTapped:)]];
    [_chipsStack addArrangedSubview:[self pp_makeChipWithTitle:kLang(@"Fulfillment_Filter_Awaiting") tag:1002 action:@selector(pp_statusChipTapped:)]];
    [_chipsStack addArrangedSubview:[self pp_makeChipWithTitle:kLang(@"Fulfillment_Filter_Completed") tag:1003 action:@selector(pp_statusChipTapped:)]];

    UIView *separator = [UIView new];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [PPF_TertiaryInkColor() colorWithAlphaComponent:0.35];
    [separator.widthAnchor constraintEqualToConstant:1.0].active = YES;
    [separator.heightAnchor constraintEqualToConstant:24.0].active = YES;
    [_chipsStack addArrangedSubview:separator];

    [_chipsStack addArrangedSubview:[self pp_makeChipWithTitle:kLang(@"Fulfillment_Filter_All") tag:2000 action:@selector(pp_ownerChipTapped:)]];
    [_chipsStack addArrangedSubview:[self pp_makeChipWithTitle:kLang(@"Fulfillment_Filter_Platform") tag:2001 action:@selector(pp_ownerChipTapped:)]];
    [_chipsStack addArrangedSubview:[self pp_makeChipWithTitle:kLang(@"Fulfillment_Filter_Partner") tag:2002 action:@selector(pp_ownerChipTapped:)]];
}

- (UIButton *)pp_makeChipWithTitle:(NSString *)title tag:(NSInteger)tag action:(SEL)action {
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
    chip.tag = tag;
    chip.titleLabel.font = [Styling fontBold:PPFontSubheadline];
    [chip setTitle:title forState:UIControlStateNormal];
    [chip addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    chip.layer.cornerRadius = PPCornerPill;
    if (@available(iOS 13.0, *)) chip.layer.cornerCurve = kCACornerCurveContinuous;
    chip.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    [chip setContentEdgeInsets:UIEdgeInsetsMake(0, 16.0, 0, 16.0)];
    [chip.heightAnchor constraintEqualToConstant:44.0].active = YES;
    [self pp_applyChipChrome:chip selected:NO];
    return chip;
}

- (void)pp_applyChipChrome:(UIButton *)chip selected:(BOOL)selected {
    if (selected) {
        chip.backgroundColor = PPF_GoldSoftColor();
        chip.layer.borderColor = [PPF_GoldColor() colorWithAlphaComponent:0.55].CGColor;
        [chip setTitleColor:PPF_GoldInkColor() forState:UIControlStateNormal];
        chip.tintColor = PPF_GoldInkColor();
    } else {
        chip.backgroundColor = PPF_SurfaceColor();
        chip.layer.borderColor = [PPF_TertiaryInkColor() colorWithAlphaComponent:0.32].CGColor;
        [chip setTitleColor:PPF_SubInkColor() forState:UIControlStateNormal];
        chip.tintColor = PPF_SubInkColor();
    }
}

- (void)pp_statusChipTapped:(UIButton *)sender {
    PPHapticTouch();
    self.filterStatus = @"";
    if (sender.tag == 1000) self.filterQuick = @"";
    else if (sender.tag == 1001) self.filterQuick = @"active";
    else if (sender.tag == 1002) self.filterQuick = @"awaiting";
    else if (sender.tag == 1003) self.filterQuick = @"completed";
    [self pp_applySearchAndFilters];
}

- (void)pp_ownerChipTapped:(UIButton *)sender {
    PPHapticTouch();
    if (sender.tag == 2000) self.filterOwnerType = @"";
    else if (sender.tag == 2001) self.filterOwnerType = @"platform";
    else if (sender.tag == 2002) self.filterOwnerType = @"partner";
    [self pp_applySearchAndFilters];
}

- (void)pp_updateChipSelection {
    for (UIView *view in self.chipsStack.arrangedSubviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *chip = (UIButton *)view;
        BOOL selected = NO;
        if (chip.tag >= 1000 && chip.tag < 2000) {
            if (self.filterStatus.length > 0) {
                selected = NO;
            } else {
                NSString *quick = @"";
                if (chip.tag == 1001) quick = @"active";
                else if (chip.tag == 1002) quick = @"awaiting";
                else if (chip.tag == 1003) quick = @"completed";
                selected = [self.filterQuick isEqualToString:quick];
            }
        } else if (chip.tag >= 2000) {
            NSString *owner = @"";
            if (chip.tag == 2001) owner = @"platform";
            else if (chip.tag == 2002) owner = @"partner";
            selected = [self.filterOwnerType isEqualToString:owner];
        }
        [self pp_applyChipChrome:chip selected:selected];
    }
}

- (void)startLiveSubscription {
    self.isLoading = YES;
    self.errorMessage = nil;
    [self.tableView reloadData];

    [_fulfillmentsListener remove];
    __weak typeof(self) weakSelf = self;

    self.fulfillmentsListener = [[PPFulfillmentService shared] observeFulfillmentsWithCompletion:^(NSArray<PPFulfillmentRecord *> *records, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            [weakSelf.refreshControl endRefreshing];
            weakSelf.lastSyncDate = [NSDate date];
            [weakSelf pp_updateLiveIndicator];
            if (error) {
                weakSelf.errorMessage = error.localizedDescription;
            } else {
                weakSelf.records = records ?: @[];
                weakSelf.errorMessage = nil;
                [weakSelf pp_markChangedRecordsForPulse];
                [weakSelf fetchUserNamesForRecords:weakSelf.records];
            }
            [weakSelf pp_applySearchAndFilters];
        });
    }];
}

- (void)pp_markChangedRecordsForPulse {
    if (!self.pulsingIDs) self.pulsingIDs = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSString *> *prev = [NSMutableDictionary dictionaryWithDictionary:self.prevStatusByID ?: @{}];
    NSMutableDictionary<NSString *, NSString *> *next = [NSMutableDictionary dictionary];
    for (PPFulfillmentRecord *r in self.records) {
        next[r.fulfillmentID] = r.status ?: @"";
        NSString *oldStatus = prev[r.fulfillmentID];
        if (!oldStatus || ![oldStatus isEqualToString:(r.status ?: @"")]) {
            [self.pulsingIDs addObject:r.fulfillmentID];
        }
    }
    self.prevStatusByID = next;
}

- (void)fetchUserNamesForRecords:(NSArray<PPFulfillmentRecord *> *)records {
    NSMutableSet *uids = [NSMutableSet set];
    for (PPFulfillmentRecord *r in records) {
        if (r.customerID.length) [uids addObject:r.customerID];
        if (r.ownerID.length) [uids addObject:r.ownerID];
    }
    
    __weak typeof(self) weakSelf = self;
    [[PPFulfillmentService shared] resolveUserProfilesForIDs:uids.allObjects completion:^(NSDictionary<NSString *,NSString *> *names) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (names.count > 0) {
                NSMutableDictionary *next = [NSMutableDictionary dictionaryWithDictionary:weakSelf.userNames];
                [next addEntriesFromDictionary:names];
                weakSelf.userNames = next;
                [weakSelf pp_applySearchAndFilters];
            }
        });
    }];
}

- (void)pp_applySearchAndFilters {
    // 1. Calculate metrics
    NSInteger active = 0;
    NSInteger waiting = 0;
    NSInteger completed = 0;
    double providerNet = 0.0;
    NSString *curr = @"QAR";

    NSSet *terminalStatuses = [NSSet setWithArray:@[@"completed", @"cancelled", @"rejected", @"failed", @"returned"]];
    NSSet *waitingStatuses = [NSSet setWithArray:@[@"new_request", @"delivery_requested", @"awaiting_handover"]];

    for (PPFulfillmentRecord *r in self.records) {
        NSString *s = r.status.lowercaseString;
        if (![terminalStatuses containsObject:s]) active++;
        if ([waitingStatuses containsObject:s]) waiting++;
        if ([s isEqualToString:@"completed"]) completed++;
        
        NSNumber *net = r.money[@"providerNet"];
        if (net) providerNet += net.doubleValue;
        if (r.money[@"currency"]) curr = r.money[@"currency"];
    }

    [self.heroView updateMetricsWithActive:active waiting:waiting completed:completed providerNet:providerNet currency:curr];

    // 2. Filter records
    NSString *query = [self.searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    
    NSMutableArray *filtered = [NSMutableArray array];
    for (PPFulfillmentRecord *r in self.records) {
        NSString *status = r.status ?: @"";
        if (self.filterStatus.length > 0 && ![status isEqualToString:self.filterStatus]) {
            continue;
        }
        if (self.filterQuick.length > 0) {
            if ([self.filterQuick isEqualToString:@"active"]) {
                if ([terminalStatuses containsObject:status.lowercaseString]) continue;
            } else if ([self.filterQuick isEqualToString:@"awaiting"]) {
                if (![waitingStatuses containsObject:status.lowercaseString]) continue;
            } else if ([self.filterQuick isEqualToString:@"completed"]) {
                if (![status.lowercaseString isEqualToString:@"completed"]) continue;
            }
        }
        if (self.filterOwnerType.length > 0 && ![r.ownerType isEqualToString:self.filterOwnerType]) {
            continue;
        }
        if (query.length > 0) {
            NSString *custName = self.userNames[r.customerID] ?: r.customerName;
            NSString *ownName = self.userNames[r.ownerID] ?: @"";
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@",
                                  r.fulfillmentID ?: @"",
                                  r.parentOrderID ?: @"",
                                  r.parentOrderNumber ?: @"",
                                  r.customerID ?: @"",
                                  r.ownerID ?: @"",
                                  custName ?: @"",
                                  ownName ?: @""];
            if (![haystack.lowercaseString containsString:query]) {
                continue;
            }
        }
        [filtered addObject:r];
    }
    
    self.visibleRecords = filtered;
    [self pp_updateChipSelection];
    [self pp_updateResultsHead];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self pp_applySearchAndFilters];
}

#pragma mark - Filter Action Sheet

- (void)presentFilterOptionsSheet {
    PPHapticTouch();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Fulfillment_Filter_AllStatuses")
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Fulfillment_Filter_AllStatuses") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.filterStatus = @"";
        weakSelf.filterQuick = @"";
        [weakSelf pp_applySearchAndFilters];
    }]];

    // Unique statuses in records
    NSMutableSet *statuses = [NSMutableSet set];
    for (PPFulfillmentRecord *r in self.records) {
        if (r.status.length) [statuses addObject:r.status];
    }

    for (NSString *st in statuses.allObjects) {
        [sheet addAction:[UIAlertAction actionWithTitle:PPF_StatusText(st) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            weakSelf.filterStatus = st;
            weakSelf.filterQuick = @"";
            [weakSelf pp_applySearchAndFilters];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Fulfillment_Filter_Clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.filterStatus = @"";
        weakSelf.filterQuick = @"";
        weakSelf.filterOwnerType = @"";
        [weakSelf pp_applySearchAndFilters];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.visibleRecords.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.visibleRecords.count == 0) {
        if (self.isLoading) {
            PPF_StateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"State" forIndexPath:indexPath];
            [cell configureWithText:kLang(@"Loading") loading:YES];
            return cell;
        }
        if (self.errorMessage.length > 0) {
            PPF_EmptyStateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Empty" forIndexPath:indexPath];
            __weak typeof(self) weakSelf = self;
            cell.onRetry = ^{ [weakSelf startLiveSubscription]; };
            [cell configureWithTitle:kLang(@"Fulfillment_EmptyError_Title")
                            subtitle:self.errorMessage
                            iconName:@"wifi.exclamationmark"
                          showsRetry:YES];
            return cell;
        }
        BOOL hasActiveFilter = self.filterStatus.length > 0 || self.filterQuick.length > 0 || self.filterOwnerType.length > 0 || self.searchController.searchBar.text.length > 0;
        PPF_EmptyStateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Empty" forIndexPath:indexPath];
        if (hasActiveFilter) {
            [cell configureWithTitle:kLang(@"Fulfillment_EmptyFiltered_Title")
                            subtitle:kLang(@"Fulfillment_EmptyFiltered_Subtitle")
                            iconName:@"line.3.horizontal.decrease"
                          showsRetry:NO];
        } else {
            [cell configureWithTitle:kLang(@"Fulfillment_Empty_Title")
                            subtitle:kLang(@"Fulfillment_Empty_Subtitle")
                            iconName:@"shippingbox"
                          showsRetry:NO];
        }
        return cell;
    }

    PPFulfillmentRecord *record = self.visibleRecords[indexPath.row];
    PPF_OrderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Order" forIndexPath:indexPath];
    
    NSString *cName = self.userNames[record.customerID] ?: record.customerName;
    NSString *oName = self.userNames[record.ownerID];
    
    BOOL shouldPulse = [self.pulsingIDs containsObject:record.fulfillmentID];
    if (shouldPulse) [self.pulsingIDs removeObject:record.fulfillmentID];
    [cell configureWithRecord:record customerName:cName ownerName:oName animated:YES pulse:shouldPulse];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.visibleRecords.count) return;

    PPHapticTouch();
    PPFulfillmentRecord *record = self.visibleRecords[indexPath.row];
    PPFulfillmentDetailViewController *detail = [[PPFulfillmentDetailViewController alloc] initWithRecord:record];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
