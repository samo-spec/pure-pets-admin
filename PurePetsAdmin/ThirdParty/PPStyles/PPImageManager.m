//
//  PPImageManager.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 13/09/2025.
//


//
//  PPImageManager.m
//  PurePetsAdmin
//
//  Created by ChatGPT on 2025-09-13.
//

#import "PPImageManager.h"
#import "UIImageView+WebCache.h"
#import "SDImageCache.h"
#import "SDWebImageManager.h"
#import "SDWebImagePrefetcher.h"

@implementation PPImageManager

+ (instancetype)sharedManager {
    static PPImageManager *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[PPImageManager alloc] init];
    });
    return inst;
}

#pragma mark - Convenience helpers

+ (UIImage *)_placeholderFromName:(nullable NSString *)name {
    if (!name) return nil;
    UIImage *img = [UIImage imageNamed:name];
    if (img) return img;
    if (@available(iOS 13.0, *)) {
        UIImage *sf = [UIImage systemImageNamed:name];
        if (sf) return sf;
    }
    return nil;
}

+ (NSURL *)_urlFromString:(NSString *)s {
    if (!s) return nil;
    return [NSURL URLWithString:s];
}

+ (void)_callOnMain:(void(^)(void))block {
    if (!block) return;
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

#pragma mark - Public set methods (simple overloads)

- (void)setImageFromUrl:(NSString *)urlString toImageView:(UIImageView *)imageView {
    [self setImageFromUrl:urlString
              toImageView:imageView
         placeholderName:nil
               completion:nil];
}

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
            completion:(void(^)(UIImage * _Nullable image))completion
{
    [self setImageFromUrl:urlString
              toImageView:imageView
          placeholderName:nil completion:^(UIImage * _Nullable image) {
        if (completion) completion(image);
    }];
}

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
              fadeType:(PPImageFadeType)fadeType
              duration:(NSTimeInterval)duration
            completion:(void(^)(UIImage * _Nullable image))completion
{
    // default placeholder nil
    [self setImageFromUrl:urlString
              toImageView:imageView
         placeholderImage:@"placeholder1x1" completion:^(UIImage * _Nullable image) {
     
        // perform custom fade
        if (image && fadeType != PPImageFadeTypeNone) {
            [PPImageManager _callOnMain:^{
                [UIView transitionWithView:imageView
                                  duration:duration > 0 ? duration : 0.25
                                   options:(fadeType == PPImageFadeTypeCrossDissolve ? UIViewAnimationOptionTransitionCrossDissolve :
                                            fadeType == PPImageFadeTypeFlipFromLeft ? UIViewAnimationOptionTransitionFlipFromLeft :
                                            UIViewAnimationOptionTransitionFlipFromRight)
                                animations:^{
                    imageView.image = image;
                } completion:nil];
            }];
        } else {
            [PPImageManager _callOnMain:^{
                imageView.image = image;
            }];
        }
        if (completion) completion(image);
    }];
}

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
      placeholderImage:(NSString *)placeholderName
            completion:(void(^)(UIImage * _Nullable image))completion
{
    [self setImageFromUrl:urlString
              toImageView:imageView
                   options:SDWebImageRetryFailed | SDWebImageHighPriority
                   context:nil
              placeholder:placeholderName
                fadeType:PPImageFadeTypeCrossDissolve
                duration:0.25
              completion:^(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache) {
        if (completion) completion(image);
    }];
}

#pragma mark - Full control

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
                options:(NSUInteger)sdOptions
                context:(nullable NSDictionary<SDWebImageContextOption,id> *)context
           placeholder:(nullable NSString *)placeholderName
             fadeType:(PPImageFadeType)fadeType
             duration:(NSTimeInterval)duration
           completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion
{
    if (!imageView) {
        if (completion) completion(nil, [NSError errorWithDomain:@"PPImageManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"imageView is nil"}], NO);
        return;
    }

    // Cancel prior load to avoid race conditions
    [self cancelLoadForImageView:imageView];

    UIImage *placeholder = [PPImageManager _placeholderFromName:placeholderName];

    NSURL *url = [PPImageManager _urlFromString:urlString];
    SDWebImageOptions options = (SDWebImageOptions)sdOptions;

    // If no URL: set placeholder and bail
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            imageView.image = placeholder;
            if (completion) completion(placeholder, nil, YES);
        });
        return;
    }

    __weak typeof(self) weakSelf = self;
    __weak UIImageView *weakImageView = imageView;

    // Use SDWebImage's sd_setImageWithURL which will handle memory/disk caches and progressive download
    [imageView sd_setImageWithURL:url
                 placeholderImage:placeholder
                          options:options
                          context:context
                         progress:nil
                        completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {

        //__strong typeof(weakSelf) strongSelf = weakSelf;
        UIImageView *iv = weakImageView;
        BOOL fromCache = (cacheType != SDImageCacheTypeNone);

        if (error) {
            // keep placeholder
            [PPImageManager _callOnMain:^{
                if (iv && !iv.image) iv.image = placeholder;
            }];
            if (completion) completion(nil, error, fromCache);
            return;
        }

        if (!image) {
            if (completion) completion(nil, nil, fromCache);
            return;
        }

        // If fadeType requested AND image didn't come from memory cache (or even if it did, you may want animation)
        // We'll animate manually to ensure consistent look.
        [PPImageManager _callOnMain:^{
            if (!iv) {
                if (completion) completion(image, nil, fromCache);
                return;
            }

            if (fadeType == PPImageFadeTypeNone) {
                iv.image = image;
                if (completion) completion(image, nil, fromCache);
                return;
            }

            UIViewAnimationOptions animOption = UIViewAnimationOptionTransitionCrossDissolve;
            if (fadeType == PPImageFadeTypeCrossDissolve) animOption = UIViewAnimationOptionTransitionCrossDissolve;
            else if (fadeType == PPImageFadeTypeFlipFromLeft) animOption = UIViewAnimationOptionTransitionFlipFromLeft;
            else if (fadeType == PPImageFadeTypeFlipFromRight) animOption = UIViewAnimationOptionTransitionFlipFromRight;

            [UIView transitionWithView:iv
                              duration:(duration > 0 ? duration : 0.25)
                               options:animOption | UIViewAnimationOptionAllowAnimatedContent
                            animations:^{
                iv.image = image;
            } completion:^(BOOL finished) {
                if (completion) completion(image, nil, fromCache);
            }];
        }];
    }];
}

#pragma mark - Cancel
- (void)cancelLoadForImageView:(UIImageView *)imageView {
    if (!imageView) return;
    [imageView sd_cancelCurrentImageLoad];
}

#pragma mark - image-only fetchers

- (void)imageFromUrl:(NSString *)urlString completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion {
    [self imageFromUrl:urlString options:SDWebImageRetryFailed | SDWebImageHighPriority context:nil completion:completion];
}

- (void)imageFromUrl:(NSString *)urlString
             options:(NSUInteger)sdOptions
             context:(nullable NSDictionary<SDWebImageContextOption,id> *)context
          completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion
{
    NSURL *url = [PPImageManager _urlFromString:urlString];
    if (!url) {
        if (completion) [PPImageManager _callOnMain:^{ completion(nil, [NSError errorWithDomain:@"PPImageManager" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Invalid URL"}], NO); }];
        return;
    }

    SDWebImageOptions options = (SDWebImageOptions)sdOptions;
    //__weak typeof(self) weakSelf = self;

    [[SDWebImageManager sharedManager] loadImageWithURL:url
                                                options:options
                                               progress:nil
                                              completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
        BOOL fromCache = (cacheType != SDImageCacheTypeNone);
        [PPImageManager _callOnMain:^{
            if (completion) completion(image, error, fromCache);
        }];
    }];
}

#pragma mark - prefetch
- (void)prefetchURLs:(NSArray<NSString *> *)urlStrings
          completion:(void(^)(NSArray<NSURL *> * _Nullable finishedURLs, NSUInteger skippedCount))completion
{
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *s in urlStrings) {
        NSURL *u = [PPImageManager _urlFromString:s];
        if (u) [urls addObject:u];
    }
    if (urls.count == 0) {
        if (completion) completion(@[], 0);
        return;
    }

    [[SDWebImagePrefetcher sharedImagePrefetcher] prefetchURLs:urls
                                                       progress:nil
                                                      completed:^(NSUInteger finishedCount, NSUInteger skippedCount) {
        if (completion) completion(urls, skippedCount);
    }];
}

#pragma mark - cache operations

- (void)clearCacheForUrl:(NSString *)urlString completion:(void(^)(void))completion {
    if (!urlString) {
        if (completion) completion();
        return;
    }
    NSString *key = urlString;
    // SDImageCache uses URL.absoluteString as key by default
    [[SDImageCache sharedImageCache] removeImageForKey:key fromDisk:YES withCompletion:^{
        if (completion) completion();
    }];
}

- (void)clearAllCacheWithCompletion:(void(^)(void))completion {
    [[SDImageCache sharedImageCache] clearMemory];
    [[SDImageCache sharedImageCache] clearDiskOnCompletion:^{
        if (completion) completion();
    }];
}

- (void)removeImageForKey:(NSString *)cacheKey completion:(void(^)(void))completion {
    if (!cacheKey) {
        if (completion) completion();
        return;
    }
    [[SDImageCache sharedImageCache] removeImageForKey:cacheKey fromDisk:YES withCompletion:^{
        if (completion) completion();
    }];
}

- (NSURL *)cacheBustedURLForURLString:(NSString *)urlString token:(nullable NSString *)token {
    if (!urlString) return nil;
    NSString *t = token.length ? token : [NSString stringWithFormat:@"%.0f", [NSDate date].timeIntervalSince1970 * 1000];
    NSURLComponents *c = [NSURLComponents componentsWithString:urlString];
    if (!c) return [NSURL URLWithString:urlString];
    // add query param 'v'
    NSMutableArray<NSURLQueryItem *> *items = c.queryItems ? [c.queryItems mutableCopy] : [NSMutableArray array];
    [items addObject:[NSURLQueryItem queryItemWithName:@"v" value:t]];
    c.queryItems = items;
    return c.URL;
}

@end
