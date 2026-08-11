//
//  Language.h
//
//  Created by Aufree on 12/5/15.
//  Copyright (c) 2015 The EST Group. All rights reserved.
//
//
//  Language.h
//
#import <objc/message.h>
#define kLang(key) [Language get:key alter:nil]
#define LanguageCode @[@"en", @"ar"]

NS_ASSUME_NONNULL_BEGIN

@interface Language : NSObject

+ (void)setLanguage:(NSString *)language; // "en" or "ar"
+ (NSString *)currentLanguageCode;        // normalized ("en" / "ar")
+ (NSInteger)languageVal;                 // 0 = en, 1 = ar
+ (void)userSelectedLanguage:(NSString *)selectedLanguage;
+ (NSString *)get:(NSString *)key alter:(nullable NSString *)alternate;

+ (BOOL)isRTL;
+ (UISemanticContentAttribute)semanticAttributeForCurrentLanguage;
+ (NSTextAlignment)alignmentForCurrentLanguage;

@end

NS_ASSUME_NONNULL_END

