//
//  PPImageCacheHelper.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 13/09/2025.
//


//
//  PPImageCacheHelper.h
//  PurePets
//
//  Created by Admin on 13/09/2025.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPImageCacheHelper : NSObject

/// Shared singleton instance
+ (instancetype)shared;

/// Save an image to cache with a key
- (void)saveImage:(UIImage *)image forKey:(NSString *)key;

/// Retrieve an image synchronously (if available in memory/disk)
- (nullable UIImage *)imageForKey:(NSString *)key;

/// Retrieve an image asynchronously
- (void)imageForKey:(NSString *)key
          completion:(void(^)(UIImage * _Nullable image))completion;

/// Remove an image for a specific key
- (void)removeImageForKey:(NSString *)key;

/// Clear all cached images (memory + disk)
- (void)clearAllCache;

@end

NS_ASSUME_NONNULL_END
