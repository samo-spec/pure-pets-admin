//
//  Language.m
//

#import "Language.h"
@import UIKit;  // <— needed for UIApplication/scenes

static NSBundle *bundle = nil;
NSString *const LanguageCodeIdIndentifier = @"AppLanguage";
// You already use this in your app:
static NSString * const kLanguageDidChangeNotification = @"LanguageDidChangeNotification";

@implementation Language

+ (NSString *)_normalize:(NSString *)code {
    if (code.length == 0) return @"en";
    NSString *lower = code.lowercaseString;
    NSString *base  = [[lower componentsSeparatedByString:@"-"] firstObject] ?: lower;
    if ([LanguageCode containsObject:base]) return base;
    if ([base hasPrefix:@"ar"]) return @"ar";
    return @"en";
}

+ (void)setLanguage:(NSString *)language {
    NSString *norm = [self _normalize:language];
    NSString *path = [[NSBundle mainBundle] pathForResource:norm ofType:@"lproj"];

    DLog(@"[Language] setLanguage: %@ → normalized=%@ (path=%@)", language, norm, path ?: @"<main bundle>");

    if (path) {
        bundle = [NSBundle bundleWithPath:path];
    } else {
        bundle = [NSBundle mainBundle];
    }

    // Cache selection
    [[NSUserDefaults standardUserDefaults] setObject:norm forKey:LanguageCodeIdIndentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Notify app
    [[NSNotificationCenter defaultCenter] postNotificationName:kLanguageDidChangeNotification object:nil];
    DLog(@"[Language] posted %@ (isRTL=%d)", kLanguageDidChangeNotification, (int)[self isRTL]);
}

+ (NSString *)currentLanguageCode {
    NSString *saved = [[NSUserDefaults standardUserDefaults] objectForKey:LanguageCodeIdIndentifier];
    if (saved.length) {
        NSString *norm = [self _normalize:saved];
        return norm;
    }
    NSString *system = [NSLocale preferredLanguages].firstObject ?: @"en";
    return [self _normalize:system];
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
                id delegate = ws.delegate;

                if ([delegate respondsToSelector:@selector(reloadRootViewControllerForLanguageChange)]) {
                    DLog(@"[Language] asking SceneDelegate to reload UI for %@", ws);
                    // Call your method you already implemented in SceneDelegate
                    [delegate reloadRootViewControllerForLanguageChange];
                } else {
                    // Soft fallback (no full rebuild, just flip window direction)
                    DLog(@"[Language] fallback reload for %@", ws);
                    for (UIWindow *w in ws.windows) {
                        w.semanticContentAttribute = attr;
                        [w setNeedsLayout];
                        [w layoutIfNeeded];
                    }
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

+ (NSString *)get:(NSString *)key alter:(NSString *)alternate {
    if (!bundle) {
        // Ensure bundle loads cached language at first call
        [self setLanguage:[self currentLanguageCode]];
    }
    NSString *val = [bundle localizedStringForKey:key value:alternate table:nil];
    // Optional debug (comment out if noisy)
    // DLog(@"[Language] get key='%@' → '%@'", key, val ?: key);
    return val ?: key;
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
