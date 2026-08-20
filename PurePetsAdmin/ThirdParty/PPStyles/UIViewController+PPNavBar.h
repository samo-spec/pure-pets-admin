
//
//  UIViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 23/08/2025.
//


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^PPNavBarTapBlock)(void);

typedef NS_ENUM(NSInteger, PPNavBarBaseLayout) {
    PPNavBarBaseLayoutAuto = 0,   // uses Language.isRTL if available, otherwise system direction
    PPNavBarBaseLayoutLTR,        // [back][title][button]
    PPNavBarBaseLayoutRTL         // [button][title][back]
};

/// Marks a navigation stack as a Command Center workflow. Legacy controllers
/// on that stack keep their actions but render through native UINavigationItem
/// APIs, preventing their overlay bar from colliding with the workflow chrome.
FOUNDATION_EXPORT void PPSetCommandCenterNavigationManaged(UINavigationController * _Nullable navigationController,
                                                            BOOL managed);
FOUNDATION_EXPORT BOOL PPCommandCenterNavigationIsManaged(UINavigationController * _Nullable navigationController);

/// Posted whenever a legacy controller updates the navigation item mirrored by
/// the Command Center's global navigation host.
FOUNDATION_EXPORT NSNotificationName const PPCommandCenterNavigationItemsDidChangeNotification;
FOUNDATION_EXPORT void PPCommandCenterNavigationItemsDidChange(UIViewController * _Nullable viewController);
FOUNDATION_EXPORT BOOL PPCommandCenterNavigationHasCustomBackAction(UIViewController * _Nullable viewController);

// ===== Associated keys =====
static const void *kPPNavBarViewKey  = &kPPNavBarViewKey;
static const void *kPPTitleLabelKey  = &kPPTitleLabelKey;
static const void *kPPLeftStackKey   = &kPPLeftStackKey;
static const void *kPPRightStackKey  = &kPPRightStackKey;
static const void *kPPButtonsDictKey = &kPPButtonsDictKey;
static const void *kPPTapBlockKey    = &kPPTapBlockKey;

// Base keys (so base layout can update/remove cleanly)
static NSString * const kPPKeyBaseBack   = @"__base_back";
static NSString * const kPPKeyBaseButton = @"__base_button";

@interface UIViewController (PPNavBar)

/// ===== Your original API (still works) =====
- (UIView *)pp_navBarWithOtherButton:(UIButton * _Nullable)otherBtn
                               title:(NSString * _Nullable)titleString;
- (void)pp_removeNavBar;


- (UIButton *)pp_ButtonWithSystemName:(NSString *)symbolName action:(SEL)action;

/// ===== New: one-call “base” layout you described =====
/// Passing (button=nil, title=nil, showBack=NO) removes the bar (your [nil][nil][nil] rule).
- (UIView * _Nullable)pp_navBarApplyBase:(PPNavBarBaseLayout)layout
                                  button:(UIButton * _Nullable)button
                                   title:(NSString * _Nullable)title
                                showBack:(BOOL)showBack;

/// Sugar for your names:
- (UIView * _Nullable)PPLTRNavigationBarWithButton:(UIButton * _Nullable)button
                                             title:(NSString * _Nullable)title
                                          showBack:(BOOL)showBack;
- (UIView * _Nullable)PPRTLNavigationBarWithButton:(UIButton * _Nullable)button
                                             title:(NSString * _Nullable)title
                                          showBack:(BOOL)showBack;

/// ===== Extra controls (optional) =====
- (void)pp_navBarSetTitle:(NSString * _Nullable)titleString;
- (void)pp_navBarSetVisible:(BOOL)visible animated:(BOOL)animated;

// Keyed icon buttons (advanced)
- (UIButton *)pp_navBarSetRightIcon:(NSString *)systemImage key:(NSString *)key
                             target:(id _Nullable)target action:(SEL _Nullable)action
                                tap:(PPNavBarTapBlock _Nullable)tapBlock;
- (UIButton *)pp_navBarSetLeftIcon:(NSString *)systemImage  key:(NSString *)key
                             target:(id _Nullable)target action:(SEL _Nullable)action
                                tap:(PPNavBarTapBlock _Nullable)tapBlock;
- (void)pp_navBarHideButtonForKey:(NSString *)key hidden:(BOOL)hidden animated:(BOOL)animated;
- (void)pp_navBarRemoveButtonForKey:(NSString *)key;


- (void)forceReplaceRightButtonWith:(UIButton *)btn;
- (void)forceReplaceLeftButtonWith:(UIButton *)btn;

/// ===== Custom Title View =====

- (UIView * _Nullable)pp_navBarForeTitleView:(UIView *)navBarTitleView;
- (UIView * _Nullable)pp_viewWithImage:(NSString *)imageName andTitle:(NSString *)title;

/// ===== Command Bar appearance =====
/// Applies the shared PurePets nav look (warm settle surface, gold hairline,
/// gold-ink tint, Beiruti-Bold 20 title) to this controller's bar instance.
/// Safe on any UINavigationController or UIViewController.
- (void)pp_applyPurePetsNavAppearance;
- (UIButton *)pp_BackButtonWithSystemName:(NSString *)symbolName action:(SEL)action;


- (UIView * _Nullable)PPNavBarForceLeftView:(UIView *)navBarTitleView ;
- (UIView * _Nullable)PPNavBarForceRightView:(UIView *)navBarTitleView ;
@end

NS_ASSUME_NONNULL_END
