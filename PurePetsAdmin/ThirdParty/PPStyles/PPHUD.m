//  PPHUD.m
#import "PPHUD.h"
@class XLFormRowDescriptor;
#import "Styling.h"

typedef NS_ENUM(NSInteger, PPHUDMode) {
    PPHUDModeIndeterminate,
    PPHUDModeRing,
    PPHUDModeSuccess,
    PPHUDModeError,
    PPHUDModeInfo
};

@interface PPHUDOverlayView : UIView
@property (nonatomic, strong) UIVisualEffectView *materialView;
@property (nonatomic, strong) UIView *indicatorHostView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UIImageView *symbolImageView;
@property (nonatomic, strong) CAShapeLayer *ringTrackLayer;
@property (nonatomic, strong) CAShapeLayer *ringProgressLayer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, assign) PPHUDMode mode;
@property (nonatomic, assign) CGFloat progress;

- (void)presentInView:(UIView *)host
                  mode:(PPHUDMode)mode
                 title:(nullable NSString *)title
              subtitle:(nullable NSString *)subtitle;
- (void)updateProgress:(CGFloat)progress title:(nullable NSString *)title;
- (void)dismissAnimated:(BOOL)animated completion:(nullable dispatch_block_t)completion;
@end

@implementation PPHUDOverlayView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self pp_commonInit];
    }
    return self;
}

- (void)pp_commonInit
{
    self.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.16];
    self.userInteractionEnabled = YES;
    self.accessibilityViewIsModal = YES;
    self.isAccessibilityElement = NO;

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    _materialView = [[UIVisualEffectView alloc] initWithEffect:effect];
    _materialView.translatesAutoresizingMaskIntoConstraints = NO;
    _materialView.clipsToBounds = YES;
    _materialView.layer.cornerRadius = 24.0;
    if (@available(iOS 13.0, *)) {
        _materialView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _materialView.layer.borderWidth = 1.0;
    _materialView.layer.shadowColor = UIColor.blackColor.CGColor;
    _materialView.layer.shadowOpacity = 0.16f;
    _materialView.layer.shadowRadius = 22.0f;
    _materialView.layer.shadowOffset = CGSizeMake(0.0, 12.0);
    [self addSubview:_materialView];

    UIView *contentView = _materialView.contentView;
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 7.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:stack];

    _indicatorHostView = [UIView new];
    _indicatorHostView.translatesAutoresizingMaskIntoConstraints = NO;
    _indicatorHostView.isAccessibilityElement = NO;
    [stack addArrangedSubview:_indicatorHostView];
    [_indicatorHostView.widthAnchor constraintEqualToConstant:52.0].active = YES;
    [_indicatorHostView.heightAnchor constraintEqualToConstant:52.0].active = YES;

    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _activityIndicator.hidesWhenStopped = YES;
    [_indicatorHostView addSubview:_activityIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:_indicatorHostView.centerXAnchor],
        [_activityIndicator.centerYAnchor constraintEqualToAnchor:_indicatorHostView.centerYAnchor]
    ]];

    _symbolImageView = [UIImageView new];
    _symbolImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolImageView.contentMode = UIViewContentModeScaleAspectFit;
    _symbolImageView.hidden = YES;
    [_indicatorHostView addSubview:_symbolImageView];
    [NSLayoutConstraint activateConstraints:@[
        [_symbolImageView.centerXAnchor constraintEqualToAnchor:_indicatorHostView.centerXAnchor],
        [_symbolImageView.centerYAnchor constraintEqualToAnchor:_indicatorHostView.centerYAnchor],
        [_symbolImageView.widthAnchor constraintEqualToConstant:29.0],
        [_symbolImageView.heightAnchor constraintEqualToConstant:29.0]
    ]];

    _ringTrackLayer = [CAShapeLayer layer];
    _ringTrackLayer.fillColor = UIColor.clearColor.CGColor;
    _ringTrackLayer.lineCap = kCALineCapRound;
    _ringTrackLayer.lineWidth = 4.0;
    _ringTrackLayer.hidden = YES;
    [_indicatorHostView.layer addSublayer:_ringTrackLayer];

    _ringProgressLayer = [CAShapeLayer layer];
    _ringProgressLayer.fillColor = UIColor.clearColor.CGColor;
    _ringProgressLayer.lineCap = kCALineCapRound;
    _ringProgressLayer.lineWidth = 4.0;
    _ringProgressLayer.strokeEnd = 0.0;
    _ringProgressLayer.hidden = YES;
    [_indicatorHostView.layer addSublayer:_ringProgressLayer];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.numberOfLines = 0;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [stack addArrangedSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.numberOfLines = 0;
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    _subtitleLabel.adjustsFontForContentSizeCategory = YES;
    [stack addArrangedSubview:_subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_materialView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_materialView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_materialView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24.0],
        [_materialView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-24.0],
        [_materialView.widthAnchor constraintGreaterThanOrEqualToConstant:172.0],
        [_materialView.widthAnchor constraintLessThanOrEqualToConstant:304.0],
        [stack.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:20.0],
        [stack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:22.0],
        [stack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-22.0],
        [stack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20.0],
        [_titleLabel.widthAnchor constraintLessThanOrEqualToConstant:260.0],
        [_subtitleLabel.widthAnchor constraintLessThanOrEqualToConstant:260.0]
    ]];

    [self pp_applyPalette];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect ringBounds = CGRectInset(self.indicatorHostView.bounds, 7.0, 7.0);
    UIBezierPath *ringPath = [UIBezierPath bezierPathWithOvalInRect:ringBounds];
    self.ringTrackLayer.frame = self.indicatorHostView.bounds;
    self.ringTrackLayer.path = ringPath.CGPath;
    self.ringProgressLayer.frame = self.indicatorHostView.bounds;
    self.ringProgressLayer.path = ringPath.CGPath;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if (!previousTraitCollection ||
            [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
            [self pp_applyPalette];
        }
    }
}

- (void)pp_applyPalette
{
    BOOL dark = NO;
    if (@available(iOS 13.0, *)) {
        dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }

    self.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:dark ? 0.28 : 0.16];
    self.materialView.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:dark ? 0.16 : 0.62].CGColor;
    self.titleLabel.textColor = UIColor.labelColor;
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.activityIndicator.color = UIColor.labelColor;
    self.ringTrackLayer.strokeColor = [UIColor.secondaryLabelColor colorWithAlphaComponent:0.24].CGColor;
    self.ringProgressLayer.strokeColor = UIColor.labelColor.CGColor;
}

- (void)presentInView:(UIView *)host
                  mode:(PPHUDMode)mode
                 title:(NSString *)title
              subtitle:(NSString *)subtitle
{
    BOOL isNewHost = self.superview != host;
    BOOL needsEntrance = isNewHost || self.alpha < 0.01;
    if (isNewHost) {
        [self removeFromSuperview];
        self.frame = host.bounds;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:self];
    }

    if (needsEntrance) {
        self.alpha = 0.0;
        self.materialView.transform = CGAffineTransformMakeScale(0.965, 0.965);
    }

    [self pp_applyMode:mode title:title subtitle:subtitle animated:!needsEntrance];

    if (needsEntrance) {
        if (UIAccessibilityIsReduceMotionEnabled()) {
            self.alpha = 1.0;
            self.materialView.transform = CGAffineTransformIdentity;
        } else {
            [UIView animateWithDuration:0.24
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                self.alpha = 1.0;
                self.materialView.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    }
}

- (void)pp_applyMode:(PPHUDMode)mode
                title:(NSString *)title
             subtitle:(NSString *)subtitle
             animated:(BOOL)animated
{
    void (^changes)(void) = ^{
        self.mode = mode;
        self.titleLabel.text = title ?: @"";
        self.subtitleLabel.text = subtitle ?: @"";
        self.subtitleLabel.hidden = subtitle.length == 0;

        UIFont *titleFont = [Styling fontBold:16.0] ?: [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        UIFont *subtitleFont = [Styling fontMedium:13.0] ?: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        self.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:titleFont];
        self.subtitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:subtitleFont];

        BOOL isLoading = mode == PPHUDModeIndeterminate;
        BOOL isRing = mode == PPHUDModeRing;
        BOOL isSuccess = mode == PPHUDModeSuccess;
        BOOL isError = mode == PPHUDModeError;
        BOOL isInfo = mode == PPHUDModeInfo;

        self.activityIndicator.hidden = !isLoading;
        if (isLoading) {
            [self.activityIndicator startAnimating];
        } else {
            [self.activityIndicator stopAnimating];
        }

        self.ringTrackLayer.hidden = !isRing;
        self.ringProgressLayer.hidden = !isRing;
        self.symbolImageView.hidden = !(isSuccess || isError || isInfo);
        if (isSuccess || isError || isInfo) {
            NSString *symbolName = isSuccess
                ? @"checkmark.circle.fill"
                : (isError ? @"xmark.octagon.fill" : @"info.circle.fill");
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:29.0 weight:UIImageSymbolWeightSemibold];
            self.symbolImageView.image = [UIImage systemImageNamed:symbolName withConfiguration:configuration];
            self.symbolImageView.tintColor = isSuccess
                ? UIColor.systemGreenColor
                : (isError ? UIColor.systemRedColor : UIColor.systemBlueColor);
        } else {
            self.symbolImageView.image = nil;
        }

        self.accessibilityLabel = self.subtitleLabel.hidden
            ? self.titleLabel.text
            : [NSString stringWithFormat:@"%@. %@", self.titleLabel.text, self.subtitleLabel.text];
    };

    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView transitionWithView:self.indicatorHostView
                          duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState
                        animations:changes
                        completion:nil];
    } else {
        changes();
    }
}

- (void)updateProgress:(CGFloat)progress title:(NSString *)title
{
    self.progress = MIN(MAX(progress, 0.0), 1.0);
    if (self.mode != PPHUDModeRing) {
        return;
    }

    if (title.length > 0) {
        self.titleLabel.text = title;
        self.accessibilityLabel = self.subtitleLabel.hidden
            ? title
            : [NSString stringWithFormat:@"%@. %@", title, self.subtitleLabel.text];
    }

    [CATransaction begin];
    [CATransaction setAnimationDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.0 : 0.16];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    self.ringProgressLayer.strokeEnd = self.progress;
    [CATransaction commit];
}

- (void)dismissAnimated:(BOOL)animated completion:(dispatch_block_t)completion
{
    void (^finish)(BOOL) = ^(__unused BOOL finished) {
        [self removeFromSuperview];
        if (completion) {
            completion();
        }
    };

    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        self.alpha = 0.0;
        self.materialView.transform = CGAffineTransformMakeScale(0.985, 0.985);
        finish(YES);
        return;
    }

    [UIView animateWithDuration:0.18
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.alpha = 0.0;
        self.materialView.transform = CGAffineTransformMakeScale(0.985, 0.985);
    } completion:finish];
}

@end

#pragma mark - Global coordinator

static PPHUDOverlayView *PPHUDCurrentOverlay;
static NSUInteger PPHUDPresentationGeneration;

static void PPHUDOnMain(void (^block)(void))
{
    if (NSThread.isMainThread) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static UIView *PPHUDHostView(UIView *preferred)
{
    if (preferred) {
        return preferred;
    }

    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            if (scene.windows.firstObject) {
                return scene.windows.firstObject;
            }
        }
    }

    return nil;
}

static PPHUDOverlayView *PPHUDOverlayForHost(UIView *host)
{
    if (PPHUDCurrentOverlay && PPHUDCurrentOverlay.superview != host) {
        [PPHUDCurrentOverlay dismissAnimated:NO completion:nil];
        PPHUDCurrentOverlay = nil;
    }

    if (!PPHUDCurrentOverlay) {
        PPHUDCurrentOverlay = [PPHUDOverlayView new];
    }
    return PPHUDCurrentOverlay;
}

static void PPHUDScheduleDismiss(NSTimeInterval delay)
{
    NSUInteger generation = ++PPHUDPresentationGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(delay, 0.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != PPHUDPresentationGeneration) {
            return;
        }
        [PPHUD dismiss];
    });
}

@implementation PPHUD

+ (void)showIndeterminateIn:(UIView *)view title:(NSString *)title subtitle:(NSString *)subtitle
{
    PPHUDOnMain(^{
        ++PPHUDPresentationGeneration;
        UIView *host = PPHUDHostView(view);
        if (!host) {
            return;
        }
        [PPHUDOverlayForHost(host) presentInView:host
                                           mode:PPHUDModeIndeterminate
                                          title:title
                                       subtitle:subtitle];
    });
}

+ (void)showRingIn:(UIView *)view title:(NSString *)title
{
    [self showRingIn:view title:title subtitle:nil];
}

+ (void)showRingIn:(UIView *)view title:(NSString *)title subtitle:(NSString *)subtitle
{
    PPHUDOnMain(^{
        ++PPHUDPresentationGeneration;
        UIView *host = PPHUDHostView(view);
        if (!host) {
            return;
        }
        PPHUDOverlayView *overlay = PPHUDOverlayForHost(host);
        [overlay presentInView:host mode:PPHUDModeRing title:title subtitle:subtitle];
        [overlay updateProgress:0.0 title:title];
    });
}

+ (void)setProgress:(CGFloat)progress title:(NSString *)title
{
    PPHUDOnMain(^{
        [PPHUDCurrentOverlay updateProgress:progress title:title];
    });
}

+ (void)showSuccess:(NSString *)title
{
    [self showSuccess:title subtitle:nil delay:0.9];
}

+ (void)showSuccess:(NSString *)title subtitle:(NSString *)subtitle
{
    [self showSuccess:title subtitle:subtitle delay:0.9];
}

+ (void)showSuccess:(NSString *)title subtitle:(NSString *)subtitle delay:(NSTimeInterval)delay
{
    PPHUDOnMain(^{
        UIView *host = PPHUDCurrentOverlay.superview ?: PPHUDHostView(nil);
        if (!host) {
            return;
        }
        ++PPHUDPresentationGeneration;
        [PPHUDOverlayForHost(host) presentInView:host
                                           mode:PPHUDModeSuccess
                                          title:title
                                       subtitle:subtitle];
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        if (title.length > 0) {
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, title);
        }
        PPHUDScheduleDismiss(delay > 0.0 ? delay : 0.9);
    });
}

+ (void)showError:(NSString *)title
{
    [self showError:title subtitle:nil delay:1.4];
}

+ (void)showError:(NSString *)title subtitle:(NSString *)subtitle
{
    [self showError:title subtitle:subtitle delay:1.4];
}

+ (void)showError:(NSString *)title subtitle:(NSString *)subtitle delay:(NSTimeInterval)delay
{
    PPHUDOnMain(^{
        UIView *host = PPHUDCurrentOverlay.superview ?: PPHUDHostView(nil);
        if (!host) {
            return;
        }
        ++PPHUDPresentationGeneration;
        [PPHUDOverlayForHost(host) presentInView:host
                                           mode:PPHUDModeError
                                          title:title
                                       subtitle:subtitle];
        UINotificationFeedbackGenerator *feedback = [UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:UINotificationFeedbackTypeError];
        if (title.length > 0) {
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, title);
        }
        PPHUDScheduleDismiss(delay > 0.0 ? delay : 1.4);
    });
}

+ (void)showInfo:(NSString *)title
{
    [self showInfo:title subtitle:nil delay:1.2];
}

+ (void)showInfo:(NSString *)title subtitle:(NSString *)subtitle
{
    [self showInfo:title subtitle:subtitle delay:1.2];
}

+ (void)showInfo:(NSString *)title subtitle:(NSString *)subtitle delay:(NSTimeInterval)delay
{
    PPHUDOnMain(^{
        UIView *host = PPHUDCurrentOverlay.superview ?: PPHUDHostView(nil);
        if (!host) {
            return;
        }
        ++PPHUDPresentationGeneration;
        [PPHUDOverlayForHost(host) presentInView:host
                                           mode:PPHUDModeInfo
                                          title:title
                                       subtitle:subtitle];
        if (title.length > 0) {
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, title);
        }
        PPHUDScheduleDismiss(delay > 0.0 ? delay : 1.2);
    });
}

+ (void)dismiss
{
    PPHUDOnMain(^{
        NSUInteger generation = ++PPHUDPresentationGeneration;
        PPHUDOverlayView *overlay = PPHUDCurrentOverlay;
        if (!overlay) {
            return;
        }
        [overlay dismissAnimated:YES completion:^{
            if (PPHUDCurrentOverlay == overlay && generation == PPHUDPresentationGeneration) {
                PPHUDCurrentOverlay = nil;
            }
        }];
    });
}

+ (BOOL)isVisible
{
    __block BOOL visible = NO;
    void (^readVisibility)(void) = ^{
        visible = PPHUDCurrentOverlay != nil && PPHUDCurrentOverlay.superview != nil && PPHUDCurrentOverlay.alpha > 0.01;
    };

    if (NSThread.isMainThread) {
        readVisibility();
    } else {
        dispatch_sync(dispatch_get_main_queue(), readVisibility);
    }
    return visible;
}

@end
