//
//  Language.m
//

#import "Language.h"
@import UIKit;  // <— needed for UIApplication/scenes

static NSBundle *bundle = nil;
static NSString *cachedLanguageCode = nil;
static BOOL isSettingLanguage = NO;
NSString *const LanguageCodeIdIndentifier = @"AppLanguage";
NSString * const LanguageDidChangeNotification = @"LanguageDidChangeNotification";
NSString * const PPLanguageDidChangeNotification = @"PPLanguageDidChangeNotification";

@implementation Language

+ (NSString *)_normalize:(NSString *)code {
    if (code.length == 0) return @"en";
    NSString *lower = code.lowercaseString;
    NSString *base  = [[lower componentsSeparatedByString:@"-"] firstObject] ?: lower;
    if ([LanguageCode containsObject:base]) return base;
    if ([base hasPrefix:@"ar"]) return @"ar";
    return @"en";
}

+ (void)pp_loadLanguage:(NSString *)language notifyChange:(BOOL)notifyChange {
    NSString *norm = [self _normalize:language];
    NSString *path = [[NSBundle mainBundle] pathForResource:norm ofType:@"lproj"];

    DLog(@"[Language] loadLanguage: %@ -> normalized=%@ (path=%@ notify=%d)", language, norm, path ?: @"<main bundle>", (int)notifyChange);

    @synchronized (Language.class) {
        if (path) {
            bundle = [NSBundle bundleWithPath:path];
        } else {
            bundle = [NSBundle mainBundle];
        }
        cachedLanguageCode = norm;
    }

    // Cache selection
    [[NSUserDefaults standardUserDefaults] setObject:norm forKey:LanguageCodeIdIndentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (!notifyChange) {
        return;
    }

    // Notify app
    [[NSNotificationCenter defaultCenter] postNotificationName:LanguageDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:PPLanguageDidChangeNotification object:nil];
    DLog(@"[Language] posted %@ & %@ (isRTL=%d)", LanguageDidChangeNotification, PPLanguageDidChangeNotification, (int)[self isRTL]);
}

+ (void)setLanguage:(NSString *)language {
    NSString *norm = [self _normalize:language];
    BOOL didChange = ![norm isEqualToString:[self currentLanguageCode]];
    BOOL needsBundle = (bundle == nil);

    if (isSettingLanguage) {
        [self pp_loadLanguage:norm notifyChange:NO];
        return;
    }

    isSettingLanguage = YES;
    [self pp_loadLanguage:norm notifyChange:(didChange && !needsBundle)];
    isSettingLanguage = NO;
}

+ (NSString *)currentLanguageCode {
    if (cachedLanguageCode.length > 0) {
        return cachedLanguageCode;
    }

    id savedObject = [[NSUserDefaults standardUserDefaults] objectForKey:LanguageCodeIdIndentifier];
    NSString *saved = [savedObject isKindOfClass:NSString.class] ? (NSString *)savedObject : nil;
    if (!saved && [savedObject isKindOfClass:NSArray.class]) {
        saved = [(NSArray *)savedObject firstObject];
    }
    if (![saved isKindOfClass:NSString.class]) {
        saved = nil;
    }

    if (saved.length > 0) {
        NSString *norm = [self _normalize:saved];
        cachedLanguageCode = norm;
        return norm;
    }

    NSString *system = [NSLocale preferredLanguages].firstObject ?: @"en";
    NSString *norm = [self _normalize:system];
    cachedLanguageCode = norm;
    return norm;
}

+ (NSInteger)languageVal {
    return [[self currentLanguageCode] isEqualToString:@"en"] ? 0 : 1;
}

#pragma mark - 🔴 MAIN ENTRY: user explicitly chose a language

+ (void)userSelectedLanguage:(NSString *)selectedLanguage {
    DLog(@"[Language] userSelectedLanguage: %@", selectedLanguage);

    // 1) Persist & load bundle, post notification
    [self setLanguage:selectedLanguage];

    // 2) Apply semantic direction globally (affects NEW views)
    UISemanticContentAttribute attr = [self semanticAttributeForCurrentLanguage];
    [UIView appearance].semanticContentAttribute        = attr;
    [UINavigationBar appearance].semanticContentAttribute = attr;
    DLog(@"[Language] applied appearance semanticAttribute=%ld", (long)attr);

    // 3) Reload all scenes so EXISTING UI rebuilds under new direction
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    w.semanticContentAttribute = attr;
                    [w setNeedsLayout];
                    [w layoutIfNeeded];
                }
                id delegate = ws.delegate;

                if ([delegate respondsToSelector:@selector(reloadRootViewControllerForLanguageChange)]) {
                    DLog(@"[Language] asking SceneDelegate to reload UI for %@", ws);
                    [delegate reloadRootViewControllerForLanguageChange];
                }
            }
        } else {
            // iOS 12 and earlier fallback
            UIWindow *w = UIApplication.sharedApplication.keyWindow;
            w.semanticContentAttribute = attr;
            [w setNeedsLayout];
            [w layoutIfNeeded];
        }
    });
}

#pragma mark - Strings

static NSString * const kPPNotFoundSentinel = @"__PP_LANG_NOT_FOUND__";

+ (BOOL)_containsArabic:(NSString *)string {
    if (!string || string.length == 0) return NO;
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if ((c >= 0x0600 && c <= 0x06FF) || (c >= 0x0750 && c <= 0x077F) ||
            (c >= 0x08A0 && c <= 0x08FF) || (c >= 0xFB50 && c <= 0xFDFF) ||
            (c >= 0xFE70 && c <= 0xFEFF)) {
            return YES;
        }
    }
    return NO;
}

+ (NSString *)get:(NSString *)key alter:(NSString *)alternate {
    if (!key || key.length == 0) {
        return (alternate && alternate.length > 0) ? alternate : @"";
    }

    if (!bundle) {
        [self pp_loadLanguage:[self currentLanguageCode] notifyChange:NO];
    }

    NSBundle *targetBundle = bundle ?: [NSBundle mainBundle];
    NSString *val = nil;

    @try {
        val = [targetBundle localizedStringForKey:key value:kPPNotFoundSentinel table:nil];
    } @catch (NSException *exception) {
        val = nil;
    }

    // 1) Key exists and was localized in the active language bundle: honor it immediately.
    if (val && ![val isEqualToString:kPPNotFoundSentinel] && val.length > 0) {
        return val;
    }

    // 2) Key was not found in the active bundle.
    if ([self isRTL]) {
        // Arabic mode: prefer developer-provided Arabic alternate if available
        if (alternate && alternate.length > 0) {
            return alternate;
        }
        // Fallback to mainBundle only if alternate was not provided
        if (targetBundle != [NSBundle mainBundle]) {
            @try {
                NSString *mainVal = [[NSBundle mainBundle] localizedStringForKey:key value:kPPNotFoundSentinel table:nil];
                if (mainVal && ![mainVal isEqualToString:kPPNotFoundSentinel] && mainVal.length > 0) {
                    return mainVal;
                }
            } @catch (NSException *exception) {}
        }
        return key;
    } else {
        // English mode: check mainBundle first if targetBundle is a separate lproj
        if (targetBundle != [NSBundle mainBundle]) {
            @try {
                NSString *mainVal = [[NSBundle mainBundle] localizedStringForKey:key value:kPPNotFoundSentinel table:nil];
                if (mainVal && ![mainVal isEqualToString:kPPNotFoundSentinel] && mainVal.length > 0) {
                    return mainVal;
                }
            } @catch (NSException *exception) {}
        }
        // If alternate was provided:
        if (alternate && alternate.length > 0) {
            // Guard against leaking Arabic alternate into English mode when key is English text
            if ([self _containsArabic:alternate] && ![self _containsArabic:key]) {
                return key;
            }
            return alternate;
        }
        return key;
    }
}

#pragma mark - Direction helpers

+ (BOOL)isRTL {
    return Language.languageVal == 1;
}

+ (UISemanticContentAttribute)semanticAttributeForCurrentLanguage {
    return [Language languageVal] == 1
        ? UISemanticContentAttributeForceRightToLeft
        : UISemanticContentAttributeForceLeftToRight;
}

+ (NSTextAlignment)alignmentForCurrentLanguage {
    return ([Language languageVal] == 1) ? NSTextAlignmentRight : NSTextAlignmentLeft;
}



@end
