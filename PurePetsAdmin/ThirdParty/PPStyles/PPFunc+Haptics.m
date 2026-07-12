//
//  PPFunc+Haptics.m
//  PurePetsAdmin
//
//  Created by Codex on 14/02/2026.
//

#import "PPFunc+Haptics.h"
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

@implementation PPFunc (Haptics)

+ (BOOL)_pp_shouldPlayKey:(NSString *)key minInterval:(CFTimeInterval)minInterval {
    static NSMutableDictionary<NSString *, NSNumber *> *lastPlayByKey = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lastPlayByKey = [NSMutableDictionary dictionary];
    });

    CFTimeInterval now = CACurrentMediaTime();
    @synchronized (lastPlayByKey) {
        CFTimeInterval last = [lastPlayByKey[key] doubleValue];
        if ((now - last) < minInterval) {
            return NO;
        }
        lastPlayByKey[key] = @(now);
        return YES;
    }
}

+ (void)_pp_playSystemSound:(SystemSoundID)soundID key:(NSString *)key minInterval:(CFTimeInterval)minInterval {
    if (![self _pp_shouldPlayKey:key minInterval:minInterval]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(soundID);
    });
}

+ (void)pp_playTapEffect {
    if (![self _pp_shouldPlayKey:@"tap" minInterval:0.10]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [impact prepare];
            [impact impactOccurred];
        }
        AudioServicesPlaySystemSound(1104);
    });
}

+ (void)pp_playSelectionEffect {
    if (![self _pp_shouldPlayKey:@"selection" minInterval:0.06]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 10.0, *)) {
            UISelectionFeedbackGenerator *selection = [UISelectionFeedbackGenerator new];
            [selection prepare];
            [selection selectionChanged];
        } else {
            AudioServicesPlaySystemSound(1519);
        }
    });
}

+ (void)pp_playSuccessEffect {
    if (![self _pp_shouldPlayKey:@"success" minInterval:0.25]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
            [gen prepare];
            [gen notificationOccurred:UINotificationFeedbackTypeSuccess];
        }
        AudioServicesPlaySystemSound(1110);
    });
}

+ (void)pp_playWarningEffect {
    if (![self _pp_shouldPlayKey:@"warning" minInterval:0.25]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
            [gen prepare];
            [gen notificationOccurred:UINotificationFeedbackTypeWarning];
        }
        AudioServicesPlaySystemSound(1111);
    });
}

+ (void)pp_playErrorEffect {
    if (![self _pp_shouldPlayKey:@"error" minInterval:0.25]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 10.0, *)) {
            UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
            [gen prepare];
            [gen notificationOccurred:UINotificationFeedbackTypeError];
        }
        AudioServicesPlaySystemSound(1053);
    });
}

+ (void)pp_playAlertEffectForType:(NSString *)type {
    NSString *normalized = [[type ?: @"info" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([normalized isEqualToString:@"success"]) {
        [self pp_playSuccessEffect];
        return;
    }

    if ([normalized isEqualToString:@"warning"]) {
        [self pp_playWarningEffect];
        return;
    }

    if ([normalized isEqualToString:@"error"]) {
        [self pp_playErrorEffect];
        return;
    }

    [self _pp_playSystemSound:1104 key:@"info" minInterval:0.12];
}

@end
