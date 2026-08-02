//
//  PPFunc+Haptics.h
//  PurePetsAdmin
//
//  Created by Codex on 14/02/2026.
//

#import "PPFunc.h"

NS_ASSUME_NONNULL_BEGIN

@interface PPFunc (Haptics)

/// Main tap effect used for Home/dashboard navigation and button taps.
+ (void)pp_playTapEffect;

/// Selection-only haptic (no audible sound).
+ (void)pp_playSelectionEffect;

/// Notification-style feedback with sound + haptic.
+ (void)pp_playSuccessEffect;
+ (void)pp_playWarningEffect;
+ (void)pp_playErrorEffect;

/// String mapper used by alert/helper layers (success, warning, error, info).
+ (void)pp_playAlertEffectForType:(nullable NSString *)type;

@end

static inline void PPHapticTouch(void) {
    [PPFunc pp_playTapEffect];
}

static inline void PPHapticSuccess(void) {
    [PPFunc pp_playSuccessEffect];
}

static inline void PPHapticError(void) {
    [PPFunc pp_playErrorEffect];
}

NS_ASSUME_NONNULL_END
