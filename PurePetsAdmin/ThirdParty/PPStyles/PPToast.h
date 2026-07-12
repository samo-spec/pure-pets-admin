//
//  PPToast.h
//  PurePetsAdmin
//
//  Created by ChatGPT (recommended) on 2025-08-25.
//  Production-ready toast helper with queueing, positions, haptics and showInView support.
//

#import "PPToastItem.h"

NS_ASSUME_NONNULL_BEGIN


@interface PPToast : NSObject

/// Default simple toast (bottom, default style, haptic=NO, duration=2.0)
+ (void)toast:(NSString *)message;

/// Full convenience API. `inView` may be nil (then window's keyWindow or scene window is used).
+ (void)toast:(NSString *)message
        style:(PPToastStyle)style
       haptic:(BOOL)doHaptic
      duration:(NSTimeInterval)duration;

/// More specific: control position and target view.
+ (void)toast:(NSString *)message
        style:(PPToastStyle)style
       haptic:(BOOL)doHaptic
      duration:(NSTimeInterval)duration
      position:(PPToastPosition)position
        inView:(nullable UIView *)inView;

/// Show immediately bypassing queue (use sparingly)
+ (void)showImmediateToast:(NSString *)message
                     style:(PPToastStyle)style
                    haptic:(BOOL)doHaptic
                   duration:(NSTimeInterval)duration
                   position:(PPToastPosition)position
                     inView:(nullable UIView *)inView;

/// Cancel any queued toasts and hide the current toast (animated).
+ (void)cancelAll;

/// Check if a toast is currently visible
+ (BOOL)isShowing;

@end

NS_ASSUME_NONNULL_END
