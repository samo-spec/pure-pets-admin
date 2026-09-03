

//
//  UIViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 23/08/2025.
//


#import "UIViewController+PPNavBar.h"
#import <objc/runtime.h>

#pragma mark - Accessors

static inline UIView *PPBarForVC(UIViewController *vc) {
    return objc_getAssociatedObject(vc, kPPNavBarViewKey);
}
static inline UILabel *PPTitleForVC(UIViewController *vc) {
    return objc_getAssociatedObject(vc, kPPTitleLabelKey);
}
static inline UIStackView *PPLeftForVC(UIViewController *vc) {
    return objc_getAssociatedObject(vc, kPPLeftStackKey);
}
static inline UIStackView *PPRightForVC(UIViewController *vc) {
    return objc_getAssociatedObject(vc, kPPRightStackKey);
}
static inline NSMutableDictionary<NSString *, UIView *> *PPDictForVC(UIViewController *vc, BOOL create) {
    NSMutableDictionary *d = objc_getAssociatedObject(vc, kPPButtonsDictKey);
    if (!d && create) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(vc, kPPButtonsDictKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}

static const void *kPPCommandCenterNavigationManagedKey = &kPPCommandCenterNavigationManagedKey;
NSNotificationName const PPCommandCenterNavigationItemsDidChangeNotification = @"PPCommandCenterNavigationItemsDidChangeNotification";

void PPCommandCenterNavigationItemsDidChange(UIViewController *viewController) {
    if (!viewController) return;
    dispatch_block_t post = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PPCommandCenterNavigationItemsDidChangeNotification
                                                            object:viewController];
    };
    if ([NSThread isMainThread]) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

BOOL PPCommandCenterNavigationHasCustomBackAction(UIViewController *viewController) {
    if (!viewController) return NO;
    SEL selector = @selector(onBack);
    Method baseMethod = class_getInstanceMethod(UIViewController.class, selector);
    IMP baseImplementation = baseMethod ? method_getImplementation(baseMethod) : NULL;
    IMP visibleImplementation = [viewController methodForSelector:selector];
    return baseImplementation && visibleImplementation && visibleImplementation != baseImplementation;
}

void PPSetCommandCenterNavigationManaged(UINavigationController *navigationController, BOOL managed) {
    if (!navigationController) return;
    objc_setAssociatedObject(navigationController,
                             kPPCommandCenterNavigationManagedKey,
                             @(managed),
                              OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

BOOL PPCommandCenterNavigationIsManaged(UINavigationController *navigationController) {
    if (!navigationController) return NO;
    return [objc_getAssociatedObject(navigationController, kPPCommandCenterNavigationManagedKey) boolValue];
}

static BOOL PPUsesCommandCenterSystemNavigation(UIViewController *vc) {
    if (PPCommandCenterNavigationIsManaged(vc.navigationController)) {
        return YES;
    }
    if (vc.navigationController && vc.navigationController.isNavigationBarHidden) {
        return NO;
    }
    return vc.navigationController != nil;
}

static void PPRemoveOverlayNavigationBar(UIViewController *vc) {
    UIView *bar = PPBarForVC(vc);
    if (bar) [bar removeFromSuperview];
    objc_setAssociatedObject(vc, kPPNavBarViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(vc, kPPTitleLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(vc, kPPLeftStackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(vc, kPPRightStackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void PPRemoveCommandCenterSystemButton(UIViewController *vc, NSString *key) {
    UIButton *button = (UIButton *)PPDictForVC(vc, NO)[key];
    if (!button) return;

    UINavigationItem *item = vc.navigationItem;
    NSMutableArray<UIBarButtonItem *> *right = [item.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    NSMutableArray<UIBarButtonItem *> *left = [item.leftBarButtonItems mutableCopy] ?: [NSMutableArray array];
    NSIndexSet *rightMatches = [right indexesOfObjectsPassingTest:^BOOL(UIBarButtonItem *candidate, NSUInteger idx, BOOL *stop) {
        (void)idx;
        (void)stop;
        return candidate.customView == button;
    }];
    NSIndexSet *leftMatches = [left indexesOfObjectsPassingTest:^BOOL(UIBarButtonItem *candidate, NSUInteger idx, BOOL *stop) {
        (void)idx;
        (void)stop;
        return candidate.customView == button;
    }];
    [right removeObjectsAtIndexes:rightMatches];
    [left removeObjectsAtIndexes:leftMatches];
    item.rightBarButtonItems = right.count > 0 ? right : nil;
    item.leftBarButtonItems = left.count > 0 ? left : nil;
    [PPDictForVC(vc, NO) removeObjectForKey:key];
}

static void PPSetCommandCenterSystemButton(UIViewController *vc,
                                           UIButton *button,
                                           NSString *key,
                                           BOOL onRight) {
    if (!button || key.length == 0) return;
    PPRemoveCommandCenterSystemButton(vc, key);
    [button removeFromSuperview];

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:button];
    UINavigationItem *navigationItem = vc.navigationItem;
    NSMutableArray<UIBarButtonItem *> *items = [(onRight
                                                  ? navigationItem.rightBarButtonItems
                                                  : navigationItem.leftBarButtonItems) mutableCopy] ?: [NSMutableArray array];
    [items addObject:item];
    if (onRight) {
        navigationItem.rightBarButtonItems = items;
    } else {
        navigationItem.leftBarButtonItems = items;
        BOOL hasSystemBack = !navigationItem.hidesBackButton &&
            vc.navigationController.viewControllers.firstObject != vc;
        navigationItem.leftItemsSupplementBackButton = hasSystemBack;
    }
    PPDictForVC(vc, YES)[key] = button;
}

static UIView *PPConfigureCommandCenterSystemNavigation(UIViewController *vc,
                                                         UIButton * _Nullable actionButton,
                                                         NSString * _Nullable title,
                                                         BOOL showBack,
                                                         BOOL actionOnRight) {
    UINavigationController *navigationController = vc.navigationController;
    if (!navigationController) return nil;

    PPRemoveOverlayNavigationBar(vc);
    NSString *resolvedTitle = title.length > 0 ? title : vc.title;
    if (resolvedTitle.length > 0) {
        vc.navigationItem.title = resolvedTitle;
    }
    vc.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    BOOL isRoot = navigationController.viewControllers.firstObject == vc;
    vc.navigationItem.hidesBackButton = !showBack || isRoot;

    if (actionButton) {
        PPSetCommandCenterSystemButton(vc, actionButton, kPPKeyBaseButton, actionOnRight);
    } else {
        PPRemoveCommandCenterSystemButton(vc, kPPKeyBaseButton);
    }
    PPCommandCenterNavigationItemsDidChange(vc);
    return navigationController.navigationBar;
}

#pragma mark - Private helpers

static BOOL PPIsRTL(UIViewController *vc) {
    Class Lang = NSClassFromString(@"Language");
    if (Lang && [Lang respondsToSelector:@selector(isRTL)]) {
        BOOL (*isRTLFunc)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
        return isRTLFunc(Lang, @selector(isRTL));
    }
    
    return Language.isRTL;// (dir == UIUserInterfaceLayoutDirectionRightToLeft);
}

NSString *PPNavBackSymbolName(void) {
    return Language.isRTL ? @"arrow.right" : @"arrow.left";
}

#pragma mark - Command Bar tokens (shared semantic design tokens)

/// Warm settle surface — mapped to the shared elevated surface.
static inline UIColor *PPNavWarmSurface(void) {
    return [UIColor ppElevatedSurface];
}

/// Slightly raised surface for buttons.
static inline UIColor *PPNavWarmRaised(void) {
    return [UIColor ppSurface];
}

/// Premium ops signal from the shared design system.
static inline UIColor *PPNavGold(void) {
    return [UIColor ppPremiumAccent];
}

/// Accent ink — readable icon/text tone on warm surfaces.
static inline UIColor *PPNavGoldInk(void) {
    return [UIColor ppAccentText];
}

/// Accent hairline separator for the settle surface.
static inline UIColor *PPNavGoldHairline(void) {
    return [[UIColor ppPremiumAccent] colorWithAlphaComponent:0.35];
}

/// Ink chevron for the back button.
static inline UIColor *PPNavBackInk(void) {
    return [UIColor ppTextPrimary];
}

/// Title color — shared text primary.
static inline UIColor *PPNavInk(void) {
    return [UIColor ppTextPrimary];
}

/// Title attributes shared by the appearance and the overlay label.
static NSDictionary *PPNavTitleAttributes(void) {
    return @{
        NSFontAttributeName: [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:20.0]],
        NSForegroundColorAttributeName: PPNavInk()
    };
}



@implementation UIViewController (PPNavBar)

#pragma mark - Attach base bar (left/title/right)

- (UIView *)pp_navBarAttachWithTitle:(NSString *)titleString {
    NSAssert(self.navigationController, @"pp_navBar requires a UINavigationController.");
    if (PPUsesCommandCenterSystemNavigation(self)) {
        return PPConfigureCommandCenterSystemNavigation(self, nil, titleString, YES, YES);
    }
    UINavigationBar *navBar = self.navigationController.navigationBar;
    [self pp_applyPurePetsNavAppearance];
    UIView *bar = PPBarForVC(self);
    if (bar) { [self pp_navBarSetTitle:titleString]; return bar; }
    
    bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.clearColor;
    
    self.navigationItem.hidesBackButton = YES; // 🔒 Hide default back arrow
    
    UIStackView *left = [[UIStackView alloc] init];
    left.translatesAutoresizingMaskIntoConstraints = NO;
    left.axis = UILayoutConstraintAxisHorizontal;
    left.alignment = UIStackViewAlignmentCenter;
    left.spacing = 12;
    
    UILabel *titleLbl = [UILabel new];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.font = PPNavTitleAttributes()[NSFontAttributeName];
    titleLbl.textColor = PPNavInk();
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.adjustsFontSizeToFitWidth = YES;
    titleLbl.adjustsFontForContentSizeCategory = YES;
    titleLbl.minimumScaleFactor = 0.75;
    
    UIStackView *right = [[UIStackView alloc] init];
    right.translatesAutoresizingMaskIntoConstraints = NO;
    right.axis = UILayoutConstraintAxisHorizontal;
    right.alignment = UIStackViewAlignmentCenter;
    right.spacing = 8;
    
    [navBar addSubview:bar];
    [bar addSubview:left];
    [bar addSubview:titleLbl];
    [bar addSubview:right];
    
    UILayoutGuide *m = navBar.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:navBar.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:navBar.bottomAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:m.leadingAnchor constant:5],
        [bar.trailingAnchor constraintEqualToAnchor:m.trailingAnchor constant:-5],
        
        [left.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [left.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        
        [right.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [right.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        
        [titleLbl.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
        [titleLbl.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [titleLbl.leadingAnchor constraintGreaterThanOrEqualToAnchor:left.trailingAnchor constant:8],
        [titleLbl.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-8],
    ]];
    
    objc_setAssociatedObject(self, kPPNavBarViewKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kPPTitleLabelKey, titleLbl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kPPLeftStackKey, left, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kPPRightStackKey, right, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PPDictForVC(self, YES);
    
    [self pp_navBarSetTitle:titleString];
    return bar;
}

#pragma mark - Command Bar appearance (per-instance, RTL-safe)

- (void)pp_applyPurePetsNavAppearance {
    if (PPUsesCommandCenterSystemNavigation(self)) {
        return;
    }
    UINavigationBar *navBar = nil;
    if ([self isKindOfClass:UINavigationController.class]) {
        navBar = [(UINavigationController *)self navigationBar];
    } else {
        navBar = self.navigationController.navigationBar;
    }
    if (!navBar) return;

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *settle = [[UINavigationBarAppearance alloc] init];
        [settle configureWithTransparentBackground];
        settle.backgroundColor = [UIColor clearColor];
        settle.shadowColor = [UIColor clearColor];
        settle.shadowImage = [[UIImage alloc] init];
        settle.titleTextAttributes = PPNavTitleAttributes();

        navBar.standardAppearance = settle;
        navBar.compactAppearance = settle;
        navBar.scrollEdgeAppearance = settle;
        navBar.tintColor = PPNavGoldInk();
        navBar.translucent = YES;
    } else {
        navBar.barTintColor = [UIColor clearColor];
        navBar.backgroundColor = [UIColor clearColor];
        navBar.shadowImage = [[UIImage alloc] init];
        [navBar setBackgroundImage:[[UIImage alloc] init] forBarMetrics:UIBarMetricsDefault];
        navBar.tintColor = PPNavGoldInk();
        navBar.titleTextAttributes = PPNavTitleAttributes();
    }
}

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method origAppear = class_getInstanceMethod(self, @selector(viewWillAppear:));
        Method swzAppear  = class_getInstanceMethod(self, @selector(pp_swz_viewWillAppear:));
        method_exchangeImplementations(origAppear, swzAppear);
        
        Method origDisappear = class_getInstanceMethod(self, @selector(viewWillDisappear:));
        Method swzDisappear  = class_getInstanceMethod(self, @selector(pp_swz_viewWillDisappear:));
        method_exchangeImplementations(origDisappear, swzDisappear);
    });
}

#pragma mark - Swizzled implementations

- (void)pp_swz_viewWillAppear:(BOOL)animated {
    if (self.navigationController) {
        [self.navigationController pp_enableSwipeToPop];
    }

    BOOL usesSystemNavigation = PPUsesCommandCenterSystemNavigation(self);
    if (usesSystemNavigation) {
        PPRemoveOverlayNavigationBar(self);
    }

    // call original
    [self pp_swz_viewWillAppear:animated];

    if (usesSystemNavigation) {
        PPRemoveOverlayNavigationBar(self);
        return;
    }
    
    // if this VC already has a PPNavBar attached, make sure it's visible
    UIView *bar = objc_getAssociatedObject(self, kPPNavBarViewKey);
    if (bar) {
        [self pp_navBarSetVisible:YES animated:NO];
    }
}

- (void)pp_swz_viewWillDisappear:(BOOL)animated {
    // call original
    [self pp_swz_viewWillDisappear:animated];
    
    // 🔴 Auto-hide & remove nav bar so parent doesn't overlap with pushed VC
    [self pp_removeNavBar];
}





- (void)pp_navBarSetTitle:(NSString *)titleString {
    if (PPUsesCommandCenterSystemNavigation(self)) {
        NSString *resolvedTitle = titleString.length > 0 ? titleString : self.title;
        if (resolvedTitle.length > 0) {
            self.navigationItem.title = resolvedTitle;
        }
        PPCommandCenterNavigationItemsDidChange(self);
        return;
    }
    UILabel *lbl = PPTitleForVC(self);
    if (!lbl) { [self pp_navBarAttachWithTitle:titleString]; lbl = PPTitleForVC(self); }
    lbl.text = titleString ?: (self.title ?: @"");
}

#pragma mark - Your original API (compat)

- (UIView *)pp_navBarWithOtherButton:(UIButton * _Nullable)otherBtn
                               title:(NSString * _Nullable)titleString
{
    if (PPUsesCommandCenterSystemNavigation(self)) {
        return PPConfigureCommandCenterSystemNavigation(self, otherBtn, titleString, YES, YES);
    }
    UIView *bar = [self pp_navBarAttachWithTitle:titleString];
    
    // Ensure default back on LEFT (your old behavior)
    if (!PPDictForVC(self, NO)[kPPKeyBaseBack]) {
        UIButton *back = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(onBack)];
        [self _pp_addLeftButton:back key:kPPKeyBaseBack];
        [self _pp_springInBackButton:back];
    }
    
    // Trailing "other" (RIGHT)
    if (otherBtn) {
        [self _pp_addRightButton:otherBtn key:kPPKeyBaseButton];
    } else {
        [self pp_navBarRemoveButtonForKey:kPPKeyBaseButton];
    }
    return bar;
}

- (void)pp_removeNavBar {
    PPRemoveOverlayNavigationBar(self);
    if (!PPUsesCommandCenterSystemNavigation(self)) {
        objc_setAssociatedObject(self, kPPButtonsDictKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - Base layout you asked for

- (UIView * _Nullable)pp_navBarApplyBase:(PPNavBarBaseLayout)layout
                                  button:(UIButton * _Nullable)button
                                   title:(NSString * _Nullable)title
                                showBack:(BOOL)showBack
{
    if (PPUsesCommandCenterSystemNavigation(self)) {
        if (!button && !title && !showBack) {
            PPRemoveOverlayNavigationBar(self);
            return nil;
        }
        BOOL isRTL = (layout == PPNavBarBaseLayoutRTL)
            || (layout == PPNavBarBaseLayoutAuto && PPIsRTL(self));
        return PPConfigureCommandCenterSystemNavigation(self, button, title, showBack, !isRTL);
    }

    // [nil][nil][nil] → remove bar
    if (!button && !title && !showBack) { [self pp_removeNavBar]; return nil; }
    
    // Attach (or reuse)
    UIView *bar = [self pp_navBarAttachWithTitle:title];
    
    BOOL isRTL = (layout == PPNavBarBaseLayoutRTL)
        || (layout == PPNavBarBaseLayoutAuto && PPIsRTL(self));
    
    
    // Clean current base items
    [self pp_navBarRemoveButtonForKey:kPPKeyBaseBack];
    [self pp_navBarRemoveButtonForKey:kPPKeyBaseButton];
    
   
    if (showBack) {
        if (!PPDictForVC(self, NO)[kPPKeyBaseBack]) {
            UIButton *back = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(onBack)];
            if (isRTL) {
                [self _pp_addRightButton:back key:kPPKeyBaseBack];
            } else {
                [self _pp_addLeftButton:back key:kPPKeyBaseBack];
            }
            [self _pp_springInBackButton:back];
        }
    }
    
    if (button) {
        if (isRTL) {
            [self _pp_addLeftButton:button key:kPPKeyBaseButton];
        } else {
            [self _pp_addRightButton:button key:kPPKeyBaseButton];
        }
    } else {
        [self pp_navBarRemoveButtonForKey:kPPKeyBaseButton];
    }

    
    // Title (center)
    [self pp_navBarSetTitle:title];
    
    
    return bar;
}

- (UIView *)PPLTRNavigationBarWithButton:(UIButton *)button title:(NSString *)title showBack:(BOOL)showBack {
    return [self pp_navBarApplyBase:PPNavBarBaseLayoutLTR button:button title:title showBack:showBack];
}
- (UIView *)PPRTLNavigationBarWithButton:(UIButton *)button title:(NSString *)title showBack:(BOOL)showBack {
    return [self pp_navBarApplyBase:PPNavBarBaseLayoutRTL button:button title:title showBack:showBack];
}

#pragma mark - Visibility

- (void)pp_navBarSetVisible:(BOOL)visible animated:(BOOL)animated {
    UIView *bar = PPBarForVC(self); if (!bar) return;
    if (!animated) { bar.hidden = !visible; return; }
    if (visible) {
        bar.hidden = NO; bar.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{ bar.alpha = 1; }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{ bar.alpha = 0; } completion:^(BOOL f){ bar.hidden = YES; }];
    }
}

#pragma mark - Keyed icon buttons (advanced)

- (UIButton *)pp_navBarSetRightIcon:(NSString *)systemImage key:(NSString *)key
                              target:(id)target action:(SEL)action
                                 tap:(PPNavBarTapBlock)tapBlock
{
    if (PPUsesCommandCenterSystemNavigation(self)) {
        UIButton *btn = (UIButton *)PPDictForVC(self, NO)[key];
        if (!btn) {
            btn = [self _pp_makeIconButton:systemImage target:target action:action tap:tapBlock];
        } else {
            [btn setImage:[UIImage systemImageNamed:systemImage] forState:UIControlStateNormal];
            [self _pp_updateButton:btn target:target action:action tap:tapBlock];
        }
        PPSetCommandCenterSystemButton(self, btn, key, YES);
        PPCommandCenterNavigationItemsDidChange(self);
        return btn;
    }
    UIView *bar = PPBarForVC(self); if (!bar) [self pp_navBarAttachWithTitle:nil];
    UIButton *btn = (UIButton *)PPDictForVC(self, YES)[key];
    if (!btn) {
        btn = [self _pp_makeIconButton:systemImage target:target action:action tap:tapBlock];
        [self _pp_addRightButton:btn key:key];
    } else {
        [btn setImage:[UIImage systemImageNamed:systemImage] forState:UIControlStateNormal];
        [self _pp_updateButton:btn target:target action:action tap:tapBlock];
    }
    //btn.backgroundColor  = UIColor.clearColor;
    return btn;
}

- (UIButton *)pp_navBarSetLeftIcon:(NSString *)systemImage  key:(NSString *)key
                             target:(id)target action:(SEL)action
                                tap:(PPNavBarTapBlock)tapBlock
{
    if (PPUsesCommandCenterSystemNavigation(self)) {
        UIButton *btn = (UIButton *)PPDictForVC(self, NO)[key];
        if (!btn) {
            btn = [self _pp_makeIconButton:systemImage target:target action:action tap:tapBlock];
        } else {
            [btn setImage:[UIImage systemImageNamed:systemImage] forState:UIControlStateNormal];
            [self _pp_updateButton:btn target:target action:action tap:tapBlock];
        }
        PPSetCommandCenterSystemButton(self, btn, key, NO);
        PPCommandCenterNavigationItemsDidChange(self);
        return btn;
    }
    UIView *bar = PPBarForVC(self); if (!bar) [self pp_navBarAttachWithTitle:nil];
    UIButton *btn = (UIButton *)PPDictForVC(self, YES)[key];
    if (!btn) {
        btn = [self _pp_makeIconButton:systemImage target:target action:action tap:tapBlock];
        [self _pp_addLeftButton:btn key:key];
    } else {
        [btn setImage:[UIImage systemImageNamed:systemImage] forState:UIControlStateNormal];
        [self _pp_updateButton:btn target:target action:action tap:tapBlock];
    }
    return btn;
}

- (void)pp_navBarAddRightButton:(UIButton *)btn key:(NSString *)key {
    [self _pp_addRightButton:btn key:key];
}

- (void)pp_navBarAddLeftButton:(UIButton *)btn key:(NSString *)key {
    [self _pp_addLeftButton:btn key:key];
}

- (void)pp_navBarAddActionButton:(UIButton *)button key:(NSString *)key {
    BOOL isRTL = PPIsRTL(self);
    if (isRTL) {
        [self _pp_addLeftButton:button key:key];
    } else {
        [self _pp_addRightButton:button key:key];
    }
}

- (void)pp_navBarHideButtonForKey:(NSString *)key hidden:(BOOL)hidden animated:(BOOL)animated {
    UIButton *btn = (UIButton *)PPDictForVC(self, NO)[key];
    if (!btn) return;
    if (!animated) { btn.hidden = hidden; return; }
    [UIView animateWithDuration:0.2 animations:^{ btn.alpha = hidden ? 0.f : 1.f; } completion:^(BOOL f){ btn.hidden = hidden; }];
}

- (void)pp_navBarRemoveButtonForKey:(NSString *)key {
    if (PPUsesCommandCenterSystemNavigation(self)) {
        PPRemoveCommandCenterSystemButton(self, key);
        PPCommandCenterNavigationItemsDidChange(self);
        return;
    }
    NSMutableDictionary<NSString *, UIView *> *dict = PPDictForVC(self, NO);
    UIButton *btn = (UIButton *)dict[key]; if (!btn) return;
    [btn removeFromSuperview];
    [dict removeObjectForKey:key];
}

#pragma mark - Default back

- (void)onBack {
    UINavigationController *navigationController = self.navigationController;
    BOOL canPop = navigationController.topViewController == self &&
        navigationController.viewControllers.count > 1;
    if (canPop) {
        [navigationController popViewControllerAnimated:YES];
        return;
    }

    // A full-screen editor can be the root of its own presented navigation
    // controller. It has a navigationController but no stack entry to pop.
    if (navigationController.presentingViewController) {
        [navigationController dismissViewControllerAnimated:YES completion:nil];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - Your circle button helper


- (UIButton *)pp_ButtonWithSystemName:(NSString *)imageName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;

    if ([imageName isEqualToString:@"checkmark"]) {
        // Flagship Primary Action Pill (Matching "✓ حفظ" from Reference Design)
        btn.backgroundColor = [UIColor ppPrimary];
        btn.tintColor = UIColor.whiteColor;
        btn.layer.cornerRadius = 19.0;
        if (@available(iOS 13.0, *)) {
            btn.layer.cornerCurve = kCACornerCurveContinuous;
        }
        btn.layer.shadowColor = [UIColor ppPrimary].CGColor;
        btn.layer.shadowOffset = CGSizeMake(0, 3);
        btn.layer.shadowRadius = 6;
        btn.layer.shadowOpacity = 0.35;
        btn.titleLabel.font = [Styling fontBold:14];

        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightHeavy];
        UIImage *img = [[UIImage systemImageNamed:@"checkmark"] imageByApplyingSymbolConfiguration:cfg];
        [btn setImage:img forState:UIControlStateNormal];
        [btn setTitle:[NSString stringWithFormat:@"  %@", kLang(@"Save")] forState:UIControlStateNormal];
        btn.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
        [btn.heightAnchor constraintEqualToConstant:38].active = YES;
    } else {
        // Flagship Glass Squircle Button (44x44)
        CGFloat btnSize = 44.0;
        btn.backgroundColor = [UIColor ppSurface];
        btn.layer.cornerRadius = 14.0;
        if (@available(iOS 13.0, *)) {
            btn.layer.cornerCurve = kCACornerCurveContinuous;
        }
        btn.layer.borderWidth = 0.8;
        btn.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
        btn.layer.shadowColor = UIColor.blackColor.CGColor;
        btn.layer.shadowOpacity = 0.04;
        btn.layer.shadowOffset = CGSizeMake(0, 2);
        btn.layer.shadowRadius = 6;
        btn.layer.masksToBounds = NO;
        btn.tintColor = [UIColor ppTextPrimary];

        UIImage *icon = [UIImage systemImageNamed:imageName];
        if (!icon) {
            icon = [UIImage imageNamed:imageName];
            icon = [UIImage pp_resizedImage:icon toPointSize:16];
        }
        if (!icon) {
            icon = [UIImage new];
        }

        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
        UIImage *configuredIcon = [icon imageByApplyingSymbolConfiguration:config] ?: icon;
        [btn setImage:configuredIcon forState:UIControlStateNormal];
        btn.imageView.contentMode = UIViewContentModeScaleAspectFit;

        [btn.widthAnchor constraintEqualToConstant:btnSize].active = YES;
        [btn.heightAnchor constraintEqualToConstant:btnSize].active = YES;
    }

    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [PPButtonHelper attachTapAnimationToButton:btn style:PPButtonAnimationStylePulse];
    return btn;
}

- (UIButton *)pp_BackButtonWithSystemName:(NSString *)imageName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat btnSize = 44.0;

    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [UIColor ppSurface];
    btn.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) {
        btn.layer.cornerCurve = kCACornerCurveContinuous;
    }
    btn.layer.borderWidth = 0.8;
    btn.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
    btn.layer.shadowColor = UIColor.blackColor.CGColor;
    btn.layer.shadowOpacity = 0.04;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.shadowRadius = 6;
    btn.layer.masksToBounds = NO;
    btn.tintColor = [UIColor ppTextPrimary];

    NSString *effectiveSym = imageName.length > 0 ? imageName : PPNavBackSymbolName();
    UIImage *icon = [UIImage systemImageNamed:effectiveSym] ?: [UIImage systemImageNamed:PPNavBackSymbolName()];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold];
    UIImage *configuredIcon = [icon imageByApplyingSymbolConfiguration:config] ?: icon;
    [btn setImage:configuredIcon forState:UIControlStateNormal];
    btn.imageView.contentMode = UIViewContentModeScaleAspectFit;

    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [btn.widthAnchor constraintEqualToConstant:btnSize].active = YES;
    [btn.heightAnchor constraintEqualToConstant:btnSize].active = YES;

    [PPButtonHelper attachTapAnimationToButton:btn style:PPButtonAnimationStylePulse];
    return btn;
}

#pragma mark - Signature: back button spring-in (Reduce Motion guarded)

- (void)_pp_springInBackButton:(UIButton *)back {
    if (!back || UIAccessibilityIsReduceMotionEnabled()) return;
    back.transform = CGAffineTransformMakeScale(0.55, 0.55);
    back.alpha = 0.0;
    [UIView animateWithDuration:0.42
                          delay:0.05
         usingSpringWithDamping:0.6
          initialSpringVelocity:0.9
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        back.transform = CGAffineTransformIdentity;
        back.alpha = 1.0;
    } completion:nil];
}
/*
- (UIButton *)pp_ButtonWithSystemName:(NSString *)symbolName action:(SEL)action {
    UIButton *btn;
    if (@available(iOS 29.0, *)) {
        
        UIButtonConfiguration *cfg = [UIButtonConfiguration glassButtonConfiguration];
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 6, 6, 6);
        btn = [UIButton new];
        btn.configuration = cfg;
        [btn setImage:[UIImage systemImageNamed:symbolName] forState:UIControlStateNormal];
    }
    else if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 6, 6, 6);
        btn = [UIButton new];
        btn.configuration = cfg;
        btn.configuration.cornerStyle = UIButtonConfigurationCornerStyleFixed;
        btn.configuration.baseBackgroundColor = UIColor.whiteColor;
        btn.configuration.baseForegroundColor = [UIColor ppError];
        [btn setImage:[UIImage systemImageNamed:symbolName] forState:UIControlStateNormal];
    } else {
        btn = [UIButton new];
        [btn setImage:[UIImage systemImageNamed:symbolName] ?: [UIImage new] forState:UIControlStateNormal];
        btn.contentEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
    }
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.tintColor = AppPrimaryClr;
    
    
    
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [btn.widthAnchor constraintEqualToConstant:44].active = YES;
    [btn.heightAnchor constraintEqualToConstant:44].active = YES;
    
    btn.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.12].CGColor;
    btn.layer.shadowOpacity = 1.0;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.shadowRadius = 6;
    btn.layer.masksToBounds = NO; // shadow needs this
    
    
    // ⚡️ Detect if current image is SF Symbol (systemName based)
    UIImage *icon = [btn imageForState:UIControlStateNormal];
    if (icon && icon.configuration) {
        // Apply SF Symbol config
        UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:20
                                                        weight:UIImageSymbolWeightRegular
                                                         scale:UIImageSymbolScaleMedium];
        [btn setImage:[icon imageByApplyingSymbolConfiguration:config]
             forState:UIControlStateNormal];
        btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
    } else {
        DLog(@"[Styling] Normal image detected, skipping SF Symbol config ⚪️");
    }
    
    return btn;
} */

#pragma mark - Button plumbing

- (void)_pp_addRightButton:(UIButton *)btn key:(NSString *)key {
    UIStackView *right = PPRightForVC(self); if (!right) return;
    PPDictForVC(self, YES)[key] = btn;
    [right addArrangedSubview:btn];
}
- (void)_pp_addLeftButton:(UIButton *)btn key:(NSString *)key {
    UIStackView *left = PPLeftForVC(self); if (!left) return;
    PPDictForVC(self, YES)[key] = btn;
    [left addArrangedSubview:btn];
}
- (void)_pp_updateButton:(UIButton *)btn target:(id)target action:(SEL)action tap:(PPNavBarTapBlock)tapBlock {
    [btn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    if (target && action) [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(btn, kPPTapBlockKey, tapBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [btn addTarget:self action:@selector(_pp_tapRelay:) forControlEvents:UIControlEventTouchUpInside];
}
- (UIButton *)_pp_makeIconButton:(NSString *)systemImage target:(id)target action:(SEL)action tap:(PPNavBarTapBlock)tapBlock {
    UIButton *b = [self pp_ButtonWithSystemName:systemImage action:action ?: @selector(_pp_dummy)];
    [self _pp_updateButton:b target:target action:action tap:tapBlock];
    return b;
}
- (void)_pp_dummy {}
- (void)_pp_tapRelay:(UIButton *)sender {
    PPNavBarTapBlock blk = objc_getAssociatedObject(sender, kPPTapBlockKey);
    if (blk) blk();
}


#pragma mark - Force Replace Helpers
#pragma mark - Force Replace Helpers (RTL/LTR aware)

- (void)forceReplaceLeftButtonWith:(UIButton *)btn {
    UIStackView *left = PPLeftForVC(self);
    if (!left) return;
    
    // 🔥 Remove existing left buttons
    for (UIView *v in left.arrangedSubviews) {
        [left removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    
    // 🔹 Add new one
    if (btn) {
        [left addArrangedSubview:btn];
        // store with a stable key
        PPDictForVC(self, YES)[@"forceLeft"] = btn;
    }
    
    DLog(@"[PPNavBar] 🔄 Force replaced LEFT button (RTL=%d)", PPIsRTL(self));
}

- (void)forceReplaceRightButtonWith:(UIButton *)btn {
    UIStackView *right = PPRightForVC(self);
    if (!right) return;
    
    // 🔥 Remove existing right buttons
    for (UIView *v in right.arrangedSubviews) {
        [right removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    
    // 🔹 Add new one
    if (btn) {
        [right addArrangedSubview:btn];
        PPDictForVC(self, YES)[@"forceRight"] = btn;
    }
    
    DLog(@"[PPNavBar] 🔄 Force replaced RIGHT button (RTL=%d)", PPIsRTL(self));
}




//  ======================    Custom Title View

#pragma mark - Custom Title View

- (UIView * _Nullable)pp_navBarForeTitleView:(UIView *)navBarTitleView {
    NSAssert(self.navigationController, @"pp_navBarForeTitleView requires a UINavigationController.");
    
    // Remove old title if any
    UILabel *lbl = PPTitleForVC(self);
    if (lbl) {
        [lbl removeFromSuperview];
        objc_setAssociatedObject(self, kPPTitleLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    UIView *bar = PPBarForVC(self);
    if (!bar) {
        bar = [self pp_navBarAttachWithTitle:nil];
    }
    
    if (navBarTitleView) {
        navBarTitleView.translatesAutoresizingMaskIntoConstraints = NO;
        [bar addSubview:navBarTitleView];
        [NSLayoutConstraint activateConstraints:@[
            [navBarTitleView.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
            [navBarTitleView.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor]
        ]];
    }
    
    return navBarTitleView;
}

#pragma mark - Pill View [Image+Title] or [Title+Image]


- (UIView * _Nullable)pp_viewWithImage:(NSString *)imageName andTitle:(NSString *)title {
    BOOL isRTL = PPIsRTL(self);
    
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = PPNavWarmRaised();
    container.layer.cornerRadius = 27; // half of 44
    container.layer.masksToBounds = NO;
    container.layer.borderWidth = 1.0;
    container.layer.borderColor = PPNavGoldHairline().CGColor;
    container.layer.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.16].CGColor;
    container.layer.shadowOpacity = 0.14;
    container.layer.shadowOffset = CGSizeMake(0, 2);
    container.layer.shadowRadius = 6;
    
    UIImage *img = [UIImage imageNamed:imageName];
    if (!img) img = [UIImage systemImageNamed:imageName];
    
    
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleToFill;
    iv.tintColor = PPNavGoldInk();
    
    iv.layer.masksToBounds = NO;
    iv.layer.shadowColor = [PPNavGold() colorWithAlphaComponent:0.4].CGColor;
    iv.layer.shadowOpacity = 0.20;
    iv.layer.shadowOffset = CGSizeMake(0, 2);
    iv.layer.shadowRadius = 6;
    
    
    [NSLayoutConstraint activateConstraints:@[[iv.heightAnchor constraintEqualToConstant:44],[iv.widthAnchor constraintEqualToConstant:44]]];
    
    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.font = [Styling fontMedium:16];
    lbl.textColor = PPNavInk();
    lbl.textAlignment = NSTextAlignmentCenter;
    
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:isRTL ? @[lbl, iv] : @[iv, lbl]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8;
    
    [container addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [container.heightAnchor constraintEqualToConstant:54],
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:42],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-42]
    ]];
    
    return container;
}

#pragma mark - Force custom views on NavBar (Left/Right)

- (UIView * _Nullable)PPNavBarForceLeftView:(UIView *)navBarTitleView {
    NSAssert(self.navigationController, @"PPNavBarForceLeftView requires a UINavigationController.");
    UIView *bar = PPBarForVC(self);
    UIStackView *left = PPLeftForVC(self);
    /* If no custom nav bar is present yet, attach a new one (with no title) so we can add the custom left view.
     * (Note: forceReplaceLeftButtonWith: did not auto-attach; adding here for completeness.) */
    if (!bar) {
        bar = [self pp_navBarAttachWithTitle:nil];
        left = PPLeftForVC(self);
    }
    if (!left) return nil;
    /* Remove all existing subviews from the left stack (e.g., the default back button or other icons) before adding the new view.
     * Note: Any removed buttons/views still have entries in PPDictForVC (e.g., __base_back), which you might clear to avoid stale references. */
    for (UIView *v in left.arrangedSubviews) {
        [left removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    if (navBarTitleView) {
        [left addArrangedSubview:navBarTitleView];
        /* Storing the custom view in the dictionary under key "forceLeft" (originally used for forced left button).
         * This works (since UIView shares base properties with UIButton), but consider using a separate key or a generalized dictionary if needed for clarity. */
        PPDictForVC(self, YES)[@"forceLeft"] = navBarTitleView;
    }
    DLog(@"[PPNavBar] 🔄 Force replaced LEFT custom view (RTL=%d)", PPIsRTL(self));
    return navBarTitleView;
}

- (UIView * _Nullable)PPNavBarForceRightView:(UIView *)navBarTitleView {
    NSAssert(self.navigationController, @"PPNavBarForceRightView requires a UINavigationController.");
    UIView *bar = PPBarForVC(self);
    UIStackView *right = PPRightForVC(self);
    /* If no custom nav bar is present yet, attach a new one so we can add the custom right view. */
    if (!bar) {
        bar = [self pp_navBarAttachWithTitle:nil];
        right = PPRightForVC(self);
    }
    if (!right) return nil;
    /* Remove all existing subviews from the right stack before adding the new view.
     * Note: Removed items (like a __base_button or any forced right button) still have entries in the PPNavBar dictionary. You may want to remove those keys too to avoid confusion. */
    for (UIView *v in right.arrangedSubviews) {
        [right removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    if (navBarTitleView) {
        [right addArrangedSubview:navBarTitleView];
        /* Storing the custom view in the dictionary under key "forceRight" (used for forced right button).
         * This is okay, but if you need to differentiate this from a forced button, you might use a distinct key or data structure. */
        PPDictForVC(self, YES)[@"forceRight"] = navBarTitleView;
    }
    DLog(@"[PPNavBar] 🔄 Force replaced RIGHT custom view (RTL=%d)", PPIsRTL(self));
    return navBarTitleView;
}
@end

#pragma mark - Universal Swipe to Pop

static const void *kPPInteractivePopDelegateKey = &kPPInteractivePopDelegateKey;

@interface PPInteractivePopGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UINavigationController *navigationController;
/// UIKit's original recognizer delegate. Retained as a forwarding target so replacing
/// the delegate never strips UIKit's own interactive-transition callbacks.
@property (nonatomic, weak) id<UIGestureRecognizerDelegate> systemDelegate;
@end

@implementation PPInteractivePopGestureDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    UINavigationController *nav = self.navigationController;
    if (!nav) return NO;
    
    // Only allow swipe to pop when there are 2 or more view controllers on the stack
    if (nav.viewControllers.count <= 1) {
        return NO;
    }
    
    // Prevent starting pop gesture while an animated transition is in progress
    id<UIViewControllerTransitionCoordinator> coordinator = nav.transitionCoordinator;
    if (coordinator && [coordinator isAnimated]) {
        return NO;
    }

    // Do not bypass custom back action (e.g. unsaved changes prompt)
    if (PPCommandCenterNavigationHasCustomBackAction(nav.topViewController)) {
        return NO;
    }
    
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // Never install a failure requirement here. `UIScreenEdgePanGestureRecognizer` is itself a
    // `UIPanGestureRecognizer`, so requiring every pan to fail first made nested navigation
    // controllers depend on each other (a gesture dependency cycle) and blocked table scrolling.
    return NO;
}

#pragma mark Forwarding to UIKit's original delegate

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) {
        return YES;
    }
    id<UIGestureRecognizerDelegate> systemDelegate = self.systemDelegate;
    return systemDelegate != nil && [systemDelegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    id<UIGestureRecognizerDelegate> systemDelegate = self.systemDelegate;
    if (systemDelegate != nil && [systemDelegate respondsToSelector:aSelector]) {
        return systemDelegate;
    }
    return [super forwardingTargetForSelector:aSelector];
}

@end

@implementation UINavigationController (PPSwipeToPop)

- (void)pp_enableSwipeToPop {
    if (!self.interactivePopGestureRecognizer) return;

    PPInteractivePopGestureDelegate *popDelegate = objc_getAssociatedObject(self, kPPInteractivePopDelegateKey);
    if (!popDelegate) {
        popDelegate = [[PPInteractivePopGestureDelegate alloc] init];
        popDelegate.navigationController = self;
        objc_setAssociatedObject(self, kPPInteractivePopDelegateKey, popDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    id<UIGestureRecognizerDelegate> currentDelegate = self.interactivePopGestureRecognizer.delegate;
    if (currentDelegate != nil && currentDelegate != popDelegate) {
        popDelegate.systemDelegate = currentDelegate;
    }

    self.interactivePopGestureRecognizer.delegate = popDelegate;
    self.interactivePopGestureRecognizer.enabled = YES;

    BOOL isRTL = [Language isRTL];
    if ([self.interactivePopGestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        ((UIScreenEdgePanGestureRecognizer *)self.interactivePopGestureRecognizer).edges = isRTL ? UIRectEdgeRight : UIRectEdgeLeft;
    }
}

@end

/*
 
 and here two extra function
 
 -(void)forceReplaceLeftButtonWith:(Button *)btn    { complete this  }
 -(void)forceReplaceRightButtonWith:(Button *)btn    { complete this  }
 
 and sure this supporting (RTL,LTR)
 */
