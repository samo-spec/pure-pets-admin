//
//  ArabicNormalizer.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 11/01/2026.
//


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ArabicNormalizer : NSObject

/// Normalize Arabic text for search & comparison
+ (NSString *)normalize:(NSString *)text;

@end

NS_ASSUME_NONNULL_END