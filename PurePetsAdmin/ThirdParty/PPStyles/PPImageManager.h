//
//  PPImageManager.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 13/09/2025.
//


//
//  PPImageManager.h
//  PurePetsAdmin
//
//  Created by ChatGPT on 2025-09-13.
//  Wrapper around SDWebImage for consistent image loading, caching & transitions.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SDWebImageDefine.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPImageFadeType) {
    PPImageFadeTypeNone = 0,
    PPImageFadeTypeCrossDissolve,
    PPImageFadeTypeFlipFromLeft,
    PPImageFadeTypeFlipFromRight
};

@interface PPImageManager : NSObject

+ (instancetype)sharedManager;

#pragma mark - UIImageView set methods (convenience)

/// default: placeholder=nil, fadeType=CrossDissolve, duration=0.25, will use SDWebImageRetryFailed|HighPriority
- (void)setImageFromUrl:(nullable NSString *)urlString
           toImageView:(UIImageView *)imageView;

/// completion version
- (void)setImageFromUrl:(nullable NSString *)urlString
           toImageView:(UIImageView *)imageView
            completion:(nullable void(^)(UIImage * _Nullable image))completion;

/// placeholder version (placeholderName is image asset name OR SF symbol name)
- (void)setImageFromUrl:(nullable NSString *)urlString
           toImageView:(UIImageView *)imageView
      placeholderName:(nullable NSString *)placeholderName
            completion:(nullable void(^)(UIImage * _Nullable image))completion;

/// control transition
- (void)setImageFromUrl:(nullable NSString *)urlString
           toImageView:(UIImageView *)imageView
              fadeType:(PPImageFadeType)fadeType
              duration:(NSTimeInterval)duration
            completion:(nullable void(^)(UIImage * _Nullable image))completion;

/// full control (SDWebImage options + context)
- (void)setImageFromUrl:(nullable NSString *)urlString
           toImageView:(UIImageView *)imageView
                options:(NSUInteger)sdOptions
                context:(nullable NSDictionary<SDWebImageContextOption,id> *)context
           placeholder:(nullable NSString *)placeholderName
             fadeType:(PPImageFadeType)fadeType
             duration:(NSTimeInterval)duration
           completion:(nullable void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion;

#pragma mark - cancel
- (void)cancelLoadForImageView:(UIImageView *)imageView;

#pragma mark - image-only fetch
- (void)imageFromUrl:(nullable NSString *)urlString
          completion:(nullable void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion;

- (void)imageFromUrl:(nullable NSString *)urlString
             options:(NSUInteger)sdOptions
             context:(nullable NSDictionary<SDWebImageContextOption,id> *)context
          completion:(nullable void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion;

#pragma mark - prefetch
- (void)prefetchURLs:(NSArray<NSString *> *)urlStrings
          completion:(nullable void(^)(NSArray<NSURL *> * _Nullable finishedURLs, NSUInteger skippedCount))completion;

#pragma mark - cache operations
- (void)clearCacheForUrl:(NSString *)urlString completion:(nullable void(^)(void))completion;
- (void)clearAllCacheWithCompletion:(nullable void(^)(void))completion;
- (void)removeImageForKey:(NSString *)cacheKey completion:(nullable void(^)(void))completion;

/// Returns a cache-busted URL (appends ?v=token). If `token==nil` uses timestamp.
- (NSURL *)cacheBustedURLForURLString:(NSString *)urlString token:(nullable NSString *)token;

@end

NS_ASSUME_NONNULL_END


/*
 // simple
 [[PPImageManager sharedManager] setImageFromUrl:banner.sampleImageURL.absoluteString
                                     toImageView:cell.imageView];

 // placeholder + completion
 [[PPImageManager sharedManager] setImageFromUrl:urlString
                                     toImageView:cell.avatarImageView
                                placeholderName:@"Placeholder"
                                      completion:^(UIImage *image){
     // do something
 }];

 // With custom fade
 [[PPImageManager sharedManager] setImageFromUrl:urlString
                                     toImageView:cell.avatarImageView
                                        fadeType:PPImageFadeTypeCrossDissolve
                                        duration:0.35
                                      completion:nil];

 // fetch image without UIImageView
 [[PPImageManager sharedManager] imageFromUrl:url completion:^(UIImage *image, NSError *error, BOOL fromCache){
     // main thread guaranteed
 }];

 // clear cache for url (after you upload new image)
 [[PPImageManager sharedManager] clearCacheForUrl:oldUrl completion:^{
     // reload
 }];

 // alternative cache bust:
 NSURL *fresh = [[PPImageManager sharedManager] cacheBustedURLForURLString:oldUrl token:nil];
 // use fresh.absoluteString when reloading

 */
