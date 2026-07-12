//
//  PPToast.m
//  PurePetsAdmin
//
//  Created by ChatGPT on 2025-08-25.
//  Fixed: ensure UIKit/Foundation imports are present so NSTimeInterval/CGFloat are known.
//

#import "PPToast.h"

@interface PPToast ()
@property (nonatomic, strong) NSMutableArray<PPToastItem *> *queue;
@property (nonatomic, assign) BOOL showing;
@property (nonatomic, strong, nullable) UIView *currentToastView;
@property (nonatomic, strong) dispatch_queue_t internalQueue;
@end

@implementation PPToast

+ (instancetype)shared {
    static PPToast *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [PPToast new];
        s.queue = [NSMutableArray array];
        s.internalQueue = dispatch_queue_create("com.pptoast.queue", DISPATCH_QUEUE_SERIAL);
        s.showing = NO;
    });
    return s;
}

#pragma mark - Public API

+ (void)toast:(NSString *)message {
    [self toast:message style:PPToastStyleInfo haptic:NO duration:kPPToastDefaultDuration];
}

+ (void)toast:(NSString *)message style:(PPToastStyle)style haptic:(BOOL)doHaptic duration:(NSTimeInterval)duration {
    [self toast:message style:style haptic:doHaptic duration:duration position:PPToastPositionBottom inView:nil];
}

+ (void)toast:(NSString *)message
        style:(PPToastStyle)style
       haptic:(BOOL)doHaptic
      duration:(NSTimeInterval)duration
      position:(PPToastPosition)position
        inView:(UIView *)inView
{
    if (message.length == 0) return;
    PPToastItem *item = [PPToastItem new];
    item.message = message;
    item.style = style;
    item.haptic = doHaptic;
    item.duration = (duration <= 0) ? kPPToastDefaultDuration : duration;
    item.position = position;
    item.inView = inView;
    
    PPToast *mgr = [PPToast shared];
    dispatch_async(mgr.internalQueue, ^{
        [mgr.queue addObject:item];
        dispatch_async(dispatch_get_main_queue(), ^{
            [mgr tryShowNext];
        });
    });
}

+ (void)showImmediateToast:(NSString *)message
                     style:(PPToastStyle)style
                    haptic:(BOOL)doHaptic
                   duration:(NSTimeInterval)duration
                   position:(PPToastPosition)position
                     inView:(UIView *)inView
{
    if (message.length == 0) return;
    PPToast *mgr = [PPToast shared];
    dispatch_async(mgr.internalQueue, ^{
        [mgr.queue removeAllObjects];
        PPToastItem *item = [PPToastItem new];
        item.message = message;
        item.style = style;
        item.haptic = doHaptic;
        item.duration = (duration <= 0) ? kPPToastDefaultDuration : duration;
        item.position = position;
        item.inView = inView;
        [mgr.queue insertObject:item atIndex:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            [mgr hideCurrentToastAnimated:YES completion:^{
                [mgr tryShowNext];
            }];
        });
    });
}

+ (void)cancelAll {
    PPToast *mgr = [PPToast shared];
    dispatch_async(mgr.internalQueue, ^{
        [mgr.queue removeAllObjects];
        dispatch_async(dispatch_get_main_queue(), ^{
            [mgr hideCurrentToastAnimated:YES completion:nil];
        });
    });
}

+ (BOOL)isShowing {
    return [PPToast shared].showing;
}

#pragma mark - Internal queue handling

- (void)tryShowNext {
    if (self.showing) return;
    if (self.queue.count == 0) return;
    PPToastItem *item = self.queue.firstObject;
    if (!item) return;
    [self.queue removeObjectAtIndex:0];
    [self showItem:item];
}

- (void)showItem:(PPToastItem *)item {
    self.showing = YES;
    
    if (item.haptic) {
        [self performHapticForStyle:item.style];
    }
    
    UIView *container = [self toastViewForMessage:item.message style:item.style];
    container.alpha = 0.0;
    
    UIView *target = item.inView ?: [self topMostWindowView];
    if (!target) {
        target = UIApplication.sharedApplication.keyWindow;
        if (!target) {
            self.showing = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self tryShowNext];
            });
            return;
        }
    }
    
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [target addSubview:container];
    
    CGFloat maxWidth = MIN(target.bounds.size.width - (kPPToastHorizontalInset * 2),
                           target.bounds.size.width * kPPToastMaxWidthMultiplier);
    NSLayoutConstraint *w = [container.widthAnchor constraintLessThanOrEqualToConstant:maxWidth];
    w.active = YES;
    
    NSLayoutConstraint *centerX = [container.centerXAnchor constraintEqualToAnchor:target.centerXAnchor];
    centerX.active = YES;
    
    NSLayoutConstraint *posConstraint = nil;
    UILayoutGuide *safe = target.safeAreaLayoutGuide;
    switch (item.position) {
        case PPToastPositionTop: {
            posConstraint = [container.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16.0];
            break;
        }
        case PPToastPositionCenter: {
            posConstraint = [container.centerYAnchor constraintEqualToAnchor:target.centerYAnchor];
            break;
        }
        case PPToastPositionBottom:
        default: {
            posConstraint = [container.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-40.0];
            break;
        }
    }
    posConstraint.active = YES;
    
    self.currentToastView = container;
    [target layoutIfNeeded];
    
    CGAffineTransform initialTransform = CGAffineTransformMakeTranslation(0, (item.position == PPToastPositionTop ? -kPPToastTranslate : kPPToastTranslate));
    container.transform = initialTransform;
    [UIView animateWithDuration:kPPToastAnimationDuration
                          delay:0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        container.alpha = 1.0;
        container.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(item.duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strong = weakSelf;
            if (!strong) return;
            [strong hideCurrentToastAnimated:YES completion:^{
                strong.showing = NO;
                [strong tryShowNext];
            }];
        });
    }];
}

- (void)hideCurrentToastAnimated:(BOOL)animated completion:(void (^ _Nullable)(void))completion {
    UIView *v = self.currentToastView;
    if (!v) {
        if (completion) completion();
        return;
    }
    self.currentToastView = nil;
    NSTimeInterval dur = animated ? kPPToastAnimationDuration : 0;
    [UIView animateWithDuration:dur
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        v.alpha = 0.0;
        v.transform = CGAffineTransformMakeTranslation(0, kPPToastTranslate * (v.frame.origin.y < 100 ? -1 : 1));
    } completion:^(BOOL finished) {
        [v removeFromSuperview];
        if (completion) completion();
    }];
}

#pragma mark - Helpers (view building, style, haptic)

- (UIView *)toastViewForMessage:(NSString *)message style:(PPToastStyle)style {
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [self backgroundColorForStyle:style];
    container.layer.cornerRadius = kPPToastCornerRadius;
    container.layer.masksToBounds = NO;
    container.layer.shadowColor = [UIColor blackColor].CGColor;
    container.layer.shadowOpacity = 0.12;
    container.layer.shadowOffset = CGSizeMake(0, 4);
    container.layer.shadowRadius = 8;
    container.alpha = 0.0;
    
    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.text = message;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textColor = [self textColorForStyle:style];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:kPPToastHorizontalPadding],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-kPPToastHorizontalPadding],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:kPPToastVerticalPadding],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-kPPToastVerticalPadding]
    ]];
    
    return container;
}

- (UIColor *)backgroundColorForStyle:(PPToastStyle)style {
    switch (style) {
        case PPToastStyleSuccess: return [UIColor colorWithRed:0.0 green:0.62 blue:0.35 alpha:1.0];
        case PPToastStyleError:   return [UIColor colorWithRed:0.86 green:0.23 blue:0.21 alpha:1.0];
        case PPToastStyleInfo:    return [UIColor colorWithRed:0.24 green:0.48 blue:0.82 alpha:1.0];
        case PPToastStyleWarning: return [UIColor colorWithRed:0.96 green:0.65 blue:0.14 alpha:1.0];
    }
}
- (UIColor *)textColorForStyle:(PPToastStyle)style {
    return UIColor.whiteColor;
}

- (void)performHapticForStyle:(PPToastStyle)style {
    if (@available(iOS 10.0, *)) {
        if (style == PPToastStyleError) {
            UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
            [gen notificationOccurred:UINotificationFeedbackTypeError];
        } else if (style == PPToastStyleSuccess) {
            UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
            [gen notificationOccurred:UINotificationFeedbackTypeSuccess];
        } else {
            UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [g impactOccurred];
        }
    }
}

- (UIView *)topMostWindowView {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows.reverseObjectEnumerator) {
                if (w.isHidden) continue;
                if (w.windowLevel != UIWindowLevelNormal) continue;
                return w;
            }
        }
    } else {
        UIWindow *w = UIApplication.sharedApplication.keyWindow;
        if (w && !w.isHidden) return w;
    }
    return UIApplication.sharedApplication.keyWindow;
}

@end
