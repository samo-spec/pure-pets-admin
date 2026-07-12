//
//  ArabicNormalizer.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 11/01/2026.
//


#import "ArabicNormalizer.h"

@implementation ArabicNormalizer

+ (NSString *)normalize:(NSString *)text
{
    if (text.length == 0) return @"";

    NSMutableString *s = [text mutableCopy];

    // 1️⃣ Remove Arabic diacritics (tashkeel)
    NSCharacterSet *diacritics =
    [NSCharacterSet characterSetWithCharactersInString:
     @"ًٌٍَُِّْ"];
    NSArray *parts = [s componentsSeparatedByCharactersInSet:diacritics];
    s = [[parts componentsJoinedByString:@""] mutableCopy];

    // 2️⃣ Normalize letters
    NSDictionary<NSString *, NSString *> *map = @{
        @"أ": @"ا",
        @"إ": @"ا",
        @"آ": @"ا",
        @"ى": @"ي",
        @"ة": @"ه",
        @"ؤ": @"و",
        @"ئ": @"ي",
    };

    for (NSString *key in map) {
        [s replaceOccurrencesOfString:key
                            withString:map[key]
                               options:0
                                 range:NSMakeRange(0, s.length)];
    }

    // 3️⃣ Trim whitespace
    NSString *result =
    [s stringByTrimmingCharactersInSet:
     [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    return result;
}

@end
