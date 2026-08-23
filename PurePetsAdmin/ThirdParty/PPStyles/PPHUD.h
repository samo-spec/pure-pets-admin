//
//  PPHUD.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 03/09/2025.
//


//  PPHUD.h
//  PurePetsAdmin
//
//  Lightweight global UIKit HUD with native material, progress, and terminal states.
//  Usage (anywhere):
//    [PPHUD showIndeterminateIn:self.view title:kLang(@"Please wait") subtitle:nil];
//    [PPHUD showRingIn:self.view title:kLang(@"Uploading…") subtitle:nil];
//    [PPHUD setProgress:0.42 title:@"42%"];
//    [PPHUD showSuccess:kLang(@"Done") subtitle:nil];
//    [PPHUD showError:kLang(@"Failed") subtitle:error.localizedDescription];
//    [PPHUD dismiss];
//
//  If you show an alert, do: [PPHUD dismiss]; then call PPAlertHelper.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPHUD : NSObject

/// Indeterminate spinner (blocks touches while shown).
+ (void)showIndeterminateIn:(nullable UIView *)view
                      title:(nullable NSString *)title
                   subtitle:(nullable NSString *)subtitle;

/// Ring progress HUD (determinate). Call setProgress: to update.
+ (void)showRingIn:(nullable UIView *)view
             title:(nullable NSString *)title
          subtitle:(nullable NSString *)subtitle;
+ (void)showRingIn:(nullable UIView *)view
             title:(nullable NSString *)title;
/// Update progress for the current ring HUD (0.0 ... 1.0). Safe to call repeatedly.
+ (void)setProgress:(CGFloat)progress title:(nullable NSString *)title;

/// Swap to success state and auto-dismiss (default 0.9s).
+ (void)showSuccess:(nullable NSString *)title;
+ (void)showSuccess:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;
+ (void)showSuccess:(nullable NSString *)title subtitle:(nullable NSString *)subtitle delay:(NSTimeInterval)delay;

/// Swap to error state and auto-dismiss (default 1.4s).
+ (void)showError:(nullable NSString *)title;
+ (void)showError:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;
+ (void)showError:(nullable NSString *)title subtitle:(nullable NSString *)subtitle delay:(NSTimeInterval)delay;

/// Show a neutral informational state and auto-dismiss (default 1.2s).
+ (void)showInfo:(nullable NSString *)title;
+ (void)showInfo:(nullable NSString *)title subtitle:(nullable NSString *)subtitle;
+ (void)showInfo:(nullable NSString *)title subtitle:(nullable NSString *)subtitle delay:(NSTimeInterval)delay;

/// Dismiss if visible (safe to call anytime).
+ (void)dismiss;

/// Returns YES if currently visible.
+ (BOOL)isVisible;
@end

NS_ASSUME_NONNULL_END
