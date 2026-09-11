//
//  PPFunc.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 23/08/2025.
//

#import "PPFunc.h"
#import <objc/runtime.h>

@implementation PPFunc

+ (void)pp_presentCircularCropperWithImage:(UIImage *)image
                            fromController:(UIViewController<TOCropViewControllerDelegate> *)controller {
    TOCropViewController *cropVC =
      [[TOCropViewController alloc] initWithCroppingStyle:TOCropViewCroppingStyleCircular
                                                    image:image];
    cropVC.delegate = controller;

    // Optional UI tweaks
    cropVC.aspectRatioPickerButtonHidden = YES;
    cropVC.resetButtonHidden = YES;
    cropVC.rotateButtonsHidden = YES;
    cropVC.title = kLang(@"Move & Zoom");

    if (controller.navigationController) {
        [controller.navigationController pushViewController:cropVC animated:YES];
    } else {
        [controller presentViewController:cropVC animated:YES completion:nil];
    }
}

+ (void)pp_clearAllYYCacheNamed:(NSString *)name {
    YYCache *cache = [YYCache cacheWithName:name];
    [cache removeAllObjectsWithBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [PPToast toast:kLang(@"Cache cleared") style:PPToastStyleSuccess haptic:YES duration:2.0];
        });
    }];
}

+ (void)reloadTableView:(UITableView *)tableView duration:(CGFloat)duration Animated:(BOOL)Animated {
    // simple fade animation to show updated results
    [UIView transitionWithView:tableView
                      duration:duration
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [tableView reloadData];
    } completion:nil];
}

+ (void)reloadTableView:(UITableView *)tableView Animated:(BOOL)Animated {
    // simple fade animation to show updated results
    [self reloadTableView:tableView duration:0.35 Animated:Animated];
}


+ (void)handleCompletionWithError:(nonnull NSError *)error successMessage:(nonnull NSString *)successMessage onController:(nonnull UIViewController *)viewController {
        [PPHUD dismiss];
        
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            [PPHUD showSuccess:kLang(@"Saved") subtitle:successMessage];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [viewController.navigationController popViewControllerAnimated:YES];
            });
        }
    }




+ (void)presentFloatingSheetFrom:(UIViewController *)presenter
                        sheetVC:(UIViewController *)sheetVC
                     detentStyle:(PPSheetDetentStyle)style
{
    if (!presenter || !sheetVC) return;

    // Always page sheet (NEVER overFullScreen)
    sheetVC.modalPresentationStyle = UIModalPresentationPageSheet;

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet =
            sheetVC.sheetPresentationController;

        // ───────────────
        // Detents
        // ───────────────
        if (@available(iOS 16.0, *)) {
            sheet.detents = @[
                [UISheetPresentationControllerDetent customDetentWithIdentifier:@"99" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                    return context.maximumDetentValue * 0.98;
                }]
            ];
        } else {
            // Fallback on earlier versions
        }
        // ───────────────
        // 🔥 FORCE FLOATING (CRITICAL)
        // ───────────────
        sheet.prefersEdgeAttachedInCompactHeight = NO;
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = NO;

        // ───────────────
        // UI polish
        // ───────────────
      
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 42.0;

        //sheet.largestUndimmedDetentIdentifier =  @"99";

        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }

    // ───────────────
    // Present SAFELY
    // ───────────────
    UIViewController *safePresenter =
        presenter.presentedViewController ?: presenter;

    [safePresenter presentViewController:sheetVC
                                animated:YES
                              completion:nil];
}

 

+ (void)presentSheetFrom:(UIViewController *)presentingVC
                sheetVC:(UIViewController *)sheetVC
            detentStyle:(PPSheetDetentStyle)style
{
    if (!presentingVC || !sheetVC) return;
    CGFloat height = UIScreen.mainScreen.bounds.size.height;

    //UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    //UIStatusBarManager *mgr = win.windowScene.statusBarManager;
    //CGFloat _statusH = mgr.statusBarFrame.size.height;
    
    sheetVC.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationControllerDetent *customMedium = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *chatsDent = UISheetPresentationControllerDetent.mediumDetent;

    UISheetPresentationControllerDetent *profileDent = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *customMedium80 = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *customMedium300 = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *adsViewDent = UISheetPresentationControllerDetent.mediumDetent;

    if (@available(iOS 16.0, *)) {

        chatsDent = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"chatsDent"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.85; // your custom medium height
        }];
        
        customMedium = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"customMedium"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.7; // your custom medium height
        }];
        
        customMedium80 = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"customMedium80"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.95; // your custom medium height
        }];
        
        adsViewDent = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"adsViewDent"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.95; // your custom medium height
        }];
        
        profileDent = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"profileDent"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return (height - PPTotalBarHeight); // your custom medium height
        }];
        
        customMedium300 = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"customMedium300"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return 400; // your custom medium height
        }];
        
    } else {
        // Fallback on earlier versions
    }
    
    
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = sheetVC.sheetPresentationController;
        if (sheet) {
            // Configure detents
            switch (style) {
                case PPSheetDetentStyle70:
                    sheet.detents = @[customMedium];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyleAdsView:
                    sheet.detents = @[adsViewDent];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyle80:
                    sheet.detents = @[customMedium80];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyle300:
                    sheet.detents = @[customMedium300];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyleProfile:
                
                    sheet.detents = @[ profileDent];

                    
                    break;
                    
                case PPSheetDetentStyleMediumOnly:
                    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;

                case PPSheetDetentStyleLargeOnly:
                    sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
                    break;
                    
                case PPSheetDetentStyleMediumAndLarge:
                    sheet.detents = @[
                        UISheetPresentationControllerDetent.mediumDetent,
                        UISheetPresentationControllerDetent.largeDetent
                    ];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
                    break;
                case PPSheetDetentStyleSemiLargAndLarge:
                    //sheet.detents = @[
                    //    chatsDent,
                       // UISheetPresentationControllerDetent.largeDetent
                    //];
                    //if (@available(iOS 16.0, *)) {
                    //    sheet.largestUndimmedDetentIdentifier = chatsDent.identifier;
                    //} else {
                        // Fallback on earlier versions
                    //}
                    
                    
                    if (@available(iOS 16.0, *)) {
                        sheet.detents = @[
                            [UISheetPresentationControllerDetent customDetentWithIdentifier:@"99"
                                                                                   resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                                return context.maximumDetentValue * 0.99;
                            }]
                        ];
                    } else {
                        // Fallback on earlier versions
                    }

                    sheet.selectedDetentIdentifier = @"99";
                    sheet.largestUndimmedDetentIdentifier = nil;
                    sheet.prefersGrabberVisible = YES;
                    
                    
                    break;
            }

            // Style settings
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 42.0;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
            
            if(PPIOS26())
            {
                //sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDete;
                //presentingVC.modalPresentationCapturesStatusBarAppearance = NO;
                //sheet.prefersEdgeAttachedInCompactHeight = NO;
                
            }
        }
    } else {
        // Fallback for iOS < 15
        sheetVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    }
    
    

    // Present on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [presentingVC presentViewController:sheetVC animated:YES completion:nil];
    });
}



@end





@implementation PaddedLabel

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.textInsets = UIEdgeInsetsMake(4, 8, 4, 8); // default padding
    }
    return self;
}

// Draw text with insets
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.textInsets)];
}

// Adjust intrinsic size for Auto Layout
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width  += self.textInsets.left + self.textInsets.right;
    size.height += self.textInsets.top + self.textInsets.bottom;
    return size;
}

// Adjust sizeThatFits (if not using Auto Layout)
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize adjusted = [super sizeThatFits:size];
    adjusted.width  += self.textInsets.left + self.textInsets.right;
    adjusted.height += self.textInsets.top + self.textInsets.bottom;
    return adjusted;
}

@end



@implementation UIImage (Crop)
- (UIImage *)pp_circularImage {
    CGFloat side = MIN(self.size.width, self.size.height);
    CGRect cropRect = CGRectMake((self.size.width - side) / 2.0,
                                 (self.size.height - side) / 2.0,
                                 side, side);

    CGImageRef cgCropped = CGImageCreateWithImageInRect(self.CGImage, cropRect);
    UIImage *square = [UIImage imageWithCGImage:cgCropped scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(cgCropped);

    UIGraphicsBeginImageContextWithOptions(square.size, NO, 0);
    CGRect rect = CGRectMake(0, 0, square.size.width, square.size.height);
    [[UIBezierPath bezierPathWithOvalInRect:rect] addClip];
    [square drawInRect:rect];
    UIImage *circle = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return circle;
}
@end


// =========================================  PPActionButton  ===========================================//
@implementation PPActionButton

+ (void)applyStyleToAction:(UIAction *)action
                      font:(nullable UIFont *)font
                     color:(nullable UIColor *)color
{
    if (!action) return;
    NSString *title = action.title ?: @"";
    if (title.length == 0) return;

    NSMutableDictionary<NSAttributedStringKey, id> *attributes = [NSMutableDictionary dictionary];
    attributes[NSFontAttributeName] = font ?: [Styling fontMedium:15] ?: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    if (color) {
        attributes[NSForegroundColorAttributeName] = color;
    }

    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:attributes];
    @try {
        [action setValue:attributedTitle forKey:@"attributedTitle"];
    } @catch (__unused NSException *exception) {
    }
}

+ (UIAction *)actionWithTitle:(NSString *)title
              systemImageName:(nullable NSString *)systemImageName
                         font:(nullable UIFont *)font
                        color:(nullable UIColor *)color
                      handler:(void (^)(UIAction *action))handler
{
    UIImage *icon = systemImageName.length ? [UIImage systemImageNamed:systemImageName] : nil;
    UIAction *action = [UIAction actionWithTitle:title
                                           image:icon
                                      identifier:nil
                                         handler:^(__kindof UIAction * _Nonnull act) {
        if (handler) handler(act);
    }];
    [self applyStyleToAction:action font:font color:color];
    return action;
}

+ (UIAction *)deleteActionWithHandler:(void (^)(UIAction *action))handler {
    return [self actionWithTitle:kLang(@"Delete")
                 systemImageName:@"trash"
                            font:[Styling fontBold:15]
                           color:UIColor.systemRedColor
                         handler:handler];
}

+ (UIAction *)editActionWithHandler:(void (^)(UIAction *action))handler {
    return [self actionWithTitle:kLang(@"Edit")
                 systemImageName:@"pencil"
                            font:[Styling fontMedium:15]
                           color:UIColor.labelColor
                         handler:handler];
}

+ (UIAction *)shareActionWithHandler:(void (^)(UIAction *action))handler {
    return [self actionWithTitle:kLang(@"Share")
                 systemImageName:@"square.and.arrow.up"
                            font:[Styling fontMedium:15]
                           color:UIColor.labelColor
                         handler:handler];
}

+ (UIAction *)showProfileActionWithHandler:(void (^)(UIAction *action))handler {
    return [self actionWithTitle:kLang(@"showProfile")
                 systemImageName:@"person.circle.fill"
                            font:[Styling fontMedium:15]
                           color:UIColor.labelColor
                         handler:handler];
}

+ (UIAction *)settingsActionWithHandler:(void (^)(UIAction *action))handler {
    return [self actionWithTitle:kLang(@"Setting")
                 systemImageName:@"gear"
                            font:[Styling fontMedium:15]
                           color:UIColor.labelColor
                         handler:handler];
}

+ (UIAction *)logoutActionWithHandler:(void (^)(UIAction *action))handler {
    UIAction *action = [self actionWithTitle:kLang(@"Logout")
                             systemImageName:@"rectangle.portrait.and.arrow.right"
                                        font:[Styling fontMedium:15]
                                       color:UIColor.systemRedColor
                                     handler:handler];
    action.attributes = UIMenuElementAttributesDestructive;
    return action;
}

@end


// ============================================================================================== //
// MARK: - Category-Defining Context Menu & Action Title Typography Swizzle (Beiruti Brand Font)
// ============================================================================================== //

static void PPSwizzleInstanceMethod(Class cls, SEL origSel, SEL swizzledSel) {
    if (!cls) return;
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method swizzMethod = class_getInstanceMethod(cls, swizzledSel);
    if (!origMethod || !swizzMethod) return;

    BOOL didAdd = class_addMethod(cls, origSel, method_getImplementation(swizzMethod), method_getTypeEncoding(swizzMethod));
    if (didAdd) {
        class_replaceMethod(cls, swizzledSel, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, swizzMethod);
    }
}

static BOOL PPIsViewInsideContextMenu(UIView *view) {
    if (!view) return NO;

    NSString *selfCls = NSStringFromClass([view class]);
    if ([selfCls containsString:@"ContextMenu"] ||
        [selfCls containsString:@"UIActionSheet"] ||
        [selfCls containsString:@"_UIMenu"] ||
        [selfCls containsString:@"_UIAlertControllerView"] ||
        [selfCls containsString:@"_UIInterfaceAction"] ||
        [selfCls containsString:@"_UICutoutShadowView"] ||
        [selfCls containsString:@"Popover"] ||
        [selfCls containsString:@"Platter"]) {
        return YES;
    }

    UIView *v = view.superview;
    while (v) {
        NSString *clsName = NSStringFromClass([v class]);
        if ([clsName containsString:@"ContextMenu"] ||
            [clsName containsString:@"UIActionSheet"] ||
            [clsName containsString:@"_UIMenu"] ||
            [clsName containsString:@"_UIAlertControllerView"] ||
            [clsName containsString:@"_UIInterfaceAction"] ||
            [clsName containsString:@"_UICutoutShadowView"] ||
            [clsName containsString:@"Popover"] ||
            [clsName containsString:@"Platter"]) {
            return YES;
        }
        v = v.superview;
    }

    if (view.window) {
        NSString *winCls = NSStringFromClass([view.window class]);
        if ([winCls containsString:@"ContextMenu"] ||
            [winCls containsString:@"_UIPopoverView"]) {
            return YES;
        }
    }
    return NO;
}

static void PPApplyBrandFontToLabel(UILabel *label) {
    if (!label) return;
    [Styling registerBrandFontsIfNeeded];

    CGFloat ptSize = label.font.pointSize;
    if (ptSize <= 0.0) {
        ptSize = 16.0;
    }

    UIFont *brandFont = nil;
    if (ptSize <= 13.0) {
        brandFont = [Styling fontMedium:ptSize] ?: [UIFont fontWithName:@"Beiruti-Medium" size:ptSize];
    } else {
        brandFont = [Styling fontBold:ptSize] ?: [UIFont fontWithName:@"Beiruti-Bold" size:ptSize];
    }

    if (!brandFont) return;

    if (![label.font.fontName containsString:@"Beiruti"]) {
        label.font = brandFont;
    }

    if (label.attributedText.length > 0) {
        __block BOOL needsFontUpdate = NO;
        [label.attributedText enumerateAttribute:NSFontAttributeName
                                         inRange:NSMakeRange(0, label.attributedText.length)
                                         options:0
                                      usingBlock:^(id value, NSRange range, BOOL *stop) {
            UIFont *f = (UIFont *)value;
            if (!f || ![f.fontName containsString:@"Beiruti"]) {
                needsFontUpdate = YES;
                *stop = YES;
            }
        }];

        if (needsFontUpdate) {
            NSMutableAttributedString *mattr = [label.attributedText mutableCopy];
            [mattr enumerateAttribute:NSFontAttributeName
                              inRange:NSMakeRange(0, mattr.length)
                              options:0
                           usingBlock:^(id value, NSRange range, BOOL *stop) {
                UIFont *orig = (UIFont *)value;
                CGFloat currentPt = orig ? orig.pointSize : ptSize;
                UIFont *bf = (currentPt <= 13.0)
                    ? ([Styling fontMedium:currentPt] ?: [UIFont fontWithName:@"Beiruti-Medium" size:currentPt])
                    : ([Styling fontBold:currentPt] ?: [UIFont fontWithName:@"Beiruti-Bold" size:currentPt]);
                if (bf) {
                    [mattr addAttribute:NSFontAttributeName value:bf range:range];
                }
            }];
            label.attributedText = mattr;
        }
    }
}

static void PPApplyBrandFontRecursively(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) {
        PPApplyBrandFontToLabel((UILabel *)view);
    }
    for (UIView *sub in view.subviews) {
        PPApplyBrandFontRecursively(sub);
    }
}

@interface UILabel (PPContextMenuBrandFont)
@end

@implementation UILabel (PPContextMenuBrandFont)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PPSwizzleInstanceMethod(self, @selector(layoutSubviews), @selector(pp_contextMenu_layoutSubviews));
        PPSwizzleInstanceMethod(self, @selector(didMoveToSuperview), @selector(pp_contextMenu_didMoveToSuperview));
        PPSwizzleInstanceMethod(self, @selector(didMoveToWindow), @selector(pp_contextMenu_didMoveToWindow));
        PPSwizzleInstanceMethod(self, @selector(setFont:), @selector(pp_contextMenu_setFont:));
        PPSwizzleInstanceMethod(self, @selector(setAttributedText:), @selector(pp_contextMenu_setAttributedText:));
        PPSwizzleInstanceMethod(self, @selector(setText:), @selector(pp_contextMenu_setText:));
        PPSwizzleInstanceMethod(self, @selector(drawTextInRect:), @selector(pp_contextMenu_drawTextInRect:));
        PPSwizzleInstanceMethod(self, @selector(sizeThatFits:), @selector(pp_contextMenu_sizeThatFits:));
        PPSwizzleInstanceMethod(self, @selector(intrinsicContentSize), @selector(pp_contextMenu_intrinsicContentSize));
    });
}

- (void)pp_contextMenu_setFont:(UIFont *)font {
    if (PPIsViewInsideContextMenu(self)) {
        [Styling registerBrandFontsIfNeeded];
        CGFloat ptSize = font.pointSize > 0 ? font.pointSize : 16.0;
        UIFont *brandFont = (ptSize <= 13.0)
            ? ([Styling fontMedium:ptSize] ?: [UIFont fontWithName:@"Beiruti-Medium" size:ptSize])
            : ([Styling fontBold:ptSize] ?: [UIFont fontWithName:@"Beiruti-Bold" size:ptSize]);
        if (brandFont) {
            [self pp_contextMenu_setFont:brandFont];
            return;
        }
    }
    [self pp_contextMenu_setFont:font];
}

- (void)pp_contextMenu_setAttributedText:(NSAttributedString *)attributedText {
    if (attributedText.length > 0 && PPIsViewInsideContextMenu(self)) {
        [Styling registerBrandFontsIfNeeded];
        NSMutableAttributedString *m = [attributedText mutableCopy];
        CGFloat defaultPt = self.font.pointSize > 0 ? self.font.pointSize : 16.0;

        [m enumerateAttribute:NSFontAttributeName
                      inRange:NSMakeRange(0, m.length)
                      options:0
                   usingBlock:^(id value, NSRange range, BOOL *stop) {
            UIFont *orig = (UIFont *)value;
            CGFloat pt = orig ? orig.pointSize : defaultPt;
            UIFont *bf = (pt <= 13.0)
                ? ([Styling fontMedium:pt] ?: [UIFont fontWithName:@"Beiruti-Medium" size:pt])
                : ([Styling fontBold:pt] ?: [UIFont fontWithName:@"Beiruti-Bold" size:pt]);
            if (bf) {
                [m addAttribute:NSFontAttributeName value:bf range:range];
            }
        }];
        [self pp_contextMenu_setAttributedText:m];
        return;
    }
    [self pp_contextMenu_setAttributedText:attributedText];
}

- (void)pp_contextMenu_setText:(NSString *)text {
    [self pp_contextMenu_setText:text];
    if (PPIsViewInsideContextMenu(self)) {
        PPApplyBrandFontToLabel(self);
    }
}

- (void)pp_contextMenu_layoutSubviews {
    [self pp_contextMenu_layoutSubviews];
    if (PPIsViewInsideContextMenu(self)) {
        PPApplyBrandFontToLabel(self);
    }
}

- (void)pp_contextMenu_didMoveToSuperview {
    [self pp_contextMenu_didMoveToSuperview];
    if (PPIsViewInsideContextMenu(self)) {
        PPApplyBrandFontToLabel(self);
    }
}

- (void)pp_contextMenu_didMoveToWindow {
    [self pp_contextMenu_didMoveToWindow];
    if (PPIsViewInsideContextMenu(self)) {
        PPApplyBrandFontToLabel(self);
    }
}

- (void)pp_contextMenu_drawTextInRect:(CGRect)rect {
    if (PPIsViewInsideContextMenu(self)) {
        PPApplyBrandFontToLabel(self);
    }
    [self pp_contextMenu_drawTextInRect:rect];
}

- (CGSize)pp_contextMenu_sizeThatFits:(CGSize)size {
    if (PPIsViewInsideContextMenu(self)) {
        PPApplyBrandFontToLabel(self);
    }
    return [self pp_contextMenu_sizeThatFits:size];
}

- (CGSize)pp_contextMenu_intrinsicContentSize {
    if (PPIsViewInsideContextMenu(self)) {
        PPApplyBrandFontToLabel(self);
    }
    return [self pp_contextMenu_intrinsicContentSize];
}

@end


// ============================================================================================== //
// MARK: - Context Menu Cell Container Hook
// ============================================================================================== //

@interface UIView (PPContextMenuCellHook)
@end

@implementation UIView (PPContextMenuCellHook)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *targetClasses = @[
            @"_UIContextMenuCell",
            @"_UIContextMenuActionView",
            @"_UIContextMenuActionsListView",
            @"_UIContextMenuView",
            @"_UIContextMenuCellContentView",
            @"UIListContentView",
            @"_UIListContentView",
            @"_UIContextMenuPlatterView",
            @"_UIContextMenuContainerView"
        ];

        for (NSString *className in targetClasses) {
            Class cls = NSClassFromString(className);
            if (cls) {
                PPSwizzleInstanceMethod(cls, @selector(layoutSubviews), @selector(pp_contextMenuContainer_layoutSubviews));
            }
        }
    });
}

- (void)pp_contextMenuContainer_layoutSubviews {
    [self pp_contextMenuContainer_layoutSubviews];
    PPApplyBrandFontRecursively(self);
}

@end


// ============================================================================================== //
// MARK: - UIAction Title Brand Font
// ============================================================================================== //

@interface UIAction (PPMenuActionTitleFont)
@end

@implementation UIAction (PPMenuActionTitleFont)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMethod = class_getClassMethod(self, @selector(actionWithTitle:image:identifier:handler:));
        Method swizzledMethod = class_getClassMethod(self, @selector(pp_purepets_admin_actionWithTitle:image:identifier:handler:));
        if (originalMethod && swizzledMethod) {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }

        PPSwizzleInstanceMethod(self, @selector(setTitle:), @selector(pp_purepets_admin_setTitle:));
    });
}

+ (void)pp_applyBrandFontToAction:(UIAction *)action title:(NSString *)title {
    if (!action || title.length == 0) return;
    [Styling registerBrandFontsIfNeeded];
    UIFont *font = [Styling fontBold:16] ?: [UIFont fontWithName:@"Beiruti-Bold" size:16];
    if (!font) return;

    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:title
                                                                           attributes:@{
        NSFontAttributeName: font
    }];

    if ([action respondsToSelector:@selector(setAttributedTitle:)]) {
        action.attributedTitle = attributedTitle;
    }
    @try {
        [action setValue:attributedTitle forKey:@"attributedTitle"];
    } @catch (__unused NSException *exception) {
    }
    @try {
        [action setValue:attributedTitle forKey:@"_attributedTitle"];
    } @catch (__unused NSException *exception) {
    }
}

+ (instancetype)pp_purepets_admin_actionWithTitle:(NSString *)title
                                            image:(UIImage *)image
                                       identifier:(UIActionIdentifier)identifier
                                          handler:(void (^)(__kindof UIAction *action))handler
{
    UIAction *action = [self pp_purepets_admin_actionWithTitle:title
                                                         image:image
                                                    identifier:identifier
                                                       handler:handler];
    [self pp_applyBrandFontToAction:action title:title];
    return action;
}

- (void)pp_purepets_admin_setTitle:(NSString *)title {
    [self pp_purepets_admin_setTitle:title];
    [UIAction pp_applyBrandFontToAction:self title:title];
}

@end


