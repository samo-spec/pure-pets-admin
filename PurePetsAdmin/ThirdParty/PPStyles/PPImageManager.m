//
//  PPImageManager.m
//  PurePetsAdmin
//
//  Compatibility façade for established UIKit callers. All retrieval now routes
//  through PPAdminImageLoader / Kingfisher's shared Admin disk cache.

#import "PPImageManager.h"
#import "PurePetsAdmin-Swift.h"

@implementation PPImageManager

+ (instancetype)sharedManager {
    static PPImageManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[PPImageManager alloc] init]; });
    return manager;
}

+ (UIImage *)pp_placeholderFromName:(NSString *)name {
    if (!name.length) return nil;
    return [UIImage imageNamed:name] ?: [UIImage systemImageNamed:name];
}

+ (void)pp_onMain:(dispatch_block_t)block {
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

- (void)setImageFromUrl:(NSString *)urlString toImageView:(UIImageView *)imageView {
    [self setImageFromUrl:urlString toImageView:imageView placeholderName:nil completion:nil];
}

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
            completion:(void(^)(UIImage * _Nullable image))completion {
    [self setImageFromUrl:urlString toImageView:imageView placeholderName:nil completion:completion];
}

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
      placeholderName:(NSString *)placeholderName
            completion:(void(^)(UIImage * _Nullable image))completion {
    [self setImageFromUrl:urlString
              toImageView:imageView
                   options:0
                   context:nil
              placeholder:placeholderName
                fadeType:PPImageFadeTypeCrossDissolve
                duration:0.25
              completion:^(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache) {
        if (completion) completion(image);
    }];
}

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
              fadeType:(PPImageFadeType)fadeType
              duration:(NSTimeInterval)duration
            completion:(void(^)(UIImage * _Nullable image))completion {
    [self setImageFromUrl:urlString
              toImageView:imageView
                   options:0
                   context:nil
              placeholder:@"placeholder1x1"
                fadeType:fadeType
                duration:duration
              completion:^(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache) {
        if (completion) completion(image);
    }];
}

- (void)setImageFromUrl:(NSString *)urlString
           toImageView:(UIImageView *)imageView
                options:(NSUInteger)sdOptions
                context:(NSDictionary *)context
           placeholder:(NSString *)placeholderName
             fadeType:(PPImageFadeType)fadeType
             duration:(NSTimeInterval)duration
           completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion {
    if (!imageView) {
        if (completion) completion(nil, [NSError errorWithDomain:@"PPImageManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"imageView is nil"}], NO);
        return;
    }

    [self cancelLoadForImageView:imageView];
    UIImage *placeholder = [PPImageManager pp_placeholderFromName:placeholderName];
    if (!urlString.length) {
        imageView.image = placeholder;
        if (completion) completion(placeholder, nil, YES);
        return;
    }

    __weak UIImageView *weakImageView = imageView;
    [PPAdminImageLoader setImageWithURLString:urlString onImageView:imageView placeholder:placeholder completion:^(UIImage * _Nullable image) {
        UIImageView *view = weakImageView;
        if (!view) return;
        void (^finish)(void) = ^{
            if (completion) completion(image, nil, NO);
        };
        if (image && fadeType != PPImageFadeTypeNone) {
            UIViewAnimationOptions option = fadeType == PPImageFadeTypeFlipFromLeft ? UIViewAnimationOptionTransitionFlipFromLeft :
                fadeType == PPImageFadeTypeFlipFromRight ? UIViewAnimationOptionTransitionFlipFromRight :
                UIViewAnimationOptionTransitionCrossDissolve;
            [UIView transitionWithView:view duration:(duration > 0 ? duration : 0.25) options:option | UIViewAnimationOptionAllowAnimatedContent animations:^{
                view.image = image;
            } completion:^(__unused BOOL finished) { finish(); }];
        } else {
            finish();
        }
    }];
}

- (void)cancelLoadForImageView:(UIImageView *)imageView {
    if (imageView) [PPAdminImageLoader cancelLoadForImageView:imageView];
}

- (void)imageFromUrl:(NSString *)urlString
          completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion {
    [self imageFromUrl:urlString options:0 context:nil completion:completion];
}

- (void)imageFromUrl:(NSString *)urlString
             options:(NSUInteger)sdOptions
             context:(NSDictionary *)context
          completion:(void(^)(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache))completion {
    [PPAdminImageLoader loadImageWithURLString:urlString completion:^(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache) {
        if (completion) completion(image, error, fromCache);
    }];
}

- (void)prefetchURLs:(NSArray<NSString *> *)urlStrings
          completion:(void(^)(NSArray<NSURL *> * _Nullable finishedURLs, NSUInteger skippedCount))completion {
    NSMutableArray<NSURL *> *validURLs = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    for (NSString *urlString in urlStrings) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) continue;
        [validURLs addObject:url];
        dispatch_group_enter(group);
        [PPAdminImageLoader loadImageWithURLString:urlString completion:^(__unused UIImage *image, __unused NSError *error, __unused BOOL fromCache) {
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) completion(validURLs, urlStrings.count - validURLs.count);
    });
}

- (void)clearCacheForUrl:(NSString *)urlString completion:(void(^)(void))completion {
    [PPAdminImageLoader removeImageForCacheKey:urlString completion:completion];
}

- (void)clearAllCacheWithCompletion:(void(^)(void))completion {
    [PPAdminImageLoader clearAllCachedImagesWithCompletion:completion];
}

- (void)removeImageForKey:(NSString *)cacheKey completion:(void(^)(void))completion {
    [PPAdminImageLoader removeImageForCacheKey:cacheKey completion:completion];
}

- (NSURL *)cacheBustedURLForURLString:(NSString *)urlString token:(NSString *)token {
    if (!urlString.length) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    if (!components) return [NSURL URLWithString:urlString];
    NSMutableArray<NSURLQueryItem *> *items = [components.queryItems mutableCopy] ?: [NSMutableArray array];
    NSString *version = token.length ? token : [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000];
    [items addObject:[NSURLQueryItem queryItemWithName:@"v" value:version]];
    components.queryItems = items;
    return components.URL;
}

@end
