//
//  UIImageView.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 21/08/2025.
//


// UIImageView+Remote.m
#import "UIImageView.h"
#import "UIImageView+WebCache.h"
#import "SDImageCache.h"
#import "SDWebImageManager.h"
#import <Accelerate/Accelerate.h>   // for blur

@implementation UIImageView (Remote)
#pragma mark - Static helpers

+ (nullable UIImage *)imageFromUrl:(NSString *)urlString {
    if (!urlString.length) return nil;
    
    SDImageCache *cache = [SDImageCache sharedImageCache];
    NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:[NSURL URLWithString:urlString]];
    
    // Try memory cache first
    UIImage *image = [cache imageFromMemoryCacheForKey:key];
    if (image) return image;
    
    // Try disk cache (synchronous read)
    image = [cache imageFromDiskCacheForKey:key];
    return image;
}

+ (void)imageFromUrl:(NSString *)urlString
          completion:(void(^)(UIImage * _Nullable image))completion {
    if (!urlString.length) {
        if (completion) completion(nil);
        return;
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil);
        return;
    }
    
    [[SDWebImageManager sharedManager] loadImageWithURL:url
                                                options:SDWebImageHighPriority
                                               progress:nil
                                              completed:^(UIImage * _Nullable image,
                                                          NSData * _Nullable data,
                                                          NSError * _Nullable error,
                                                          SDImageCacheType cacheType,
                                                          BOOL finished,
                                                          NSURL * _Nullable imageURL) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(image);
            });
        }
    }];
}


#pragma mark - Instance
- (void)setImageFromUrl:(NSString *)urlString {
    [self setImageFromUrl:urlString Blr:NO Shimmering:YES completion:nil];
}

- (void)setImageFromUrl:(NSString *)urlString completion:(void(^)(UIImage *image))completion {
    [self setImageFromUrl:urlString Blr:NO Shimmering:NO completion:completion];
}

- (void)setImageFromUrl:(NSString *)urlString
                    Blr:(BOOL)blur
              Shimmering:(BOOL)shimmer {
    [self setImageFromUrl:urlString Blr:blur Shimmering:shimmer completion:nil];
}

- (void)setImageFromUrl:(NSString *)urlString
                    Blr:(BOOL)blur
              Shimmering:(BOOL)shimmer
              completion:(void(^)(UIImage *image))completion {
    
    if (shimmer) {
        UIView *shimmerView = [[UIView alloc] initWithFrame:self.bounds];
        shimmerView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
        shimmerView.tag = 9999;
        shimmerView.layer.cornerRadius = self.layer.cornerRadius;
        shimmerView.clipsToBounds = YES;
        [self addSubview:shimmerView];
        // you can replace with real shimmer lib (FBShimmeringView)
    }
    
    // Synchronous (if already cached)
    UIImage *cached = [PPImageCacheHelper.shared imageForKey:urlString];
    if (cached) {
        if (completion) completion(cached);
    }
    __weak typeof(self) weakSelf = self;
    // Asynchronous (recommended)
    [UIImageView imageFromUrl:urlString completion:^(UIImage * _Nullable image) {
        if (image) {
            if (completion) completion(image);
        }
    }];
    
    
   
    [self sd_setImageWithURL:[NSURL URLWithString:urlString]
            placeholderImage:[UIImage imageNamed:@"Placeholder"]
                     options:SDWebImageRetryFailed | SDWebImageHighPriority
                   completed:^(UIImage * _Nullable image, NSError * _Nullable error,
                               SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
        
        [[weakSelf viewWithTag:9999] removeFromSuperview]; // remove shimmer
        
        if (blur && image) {
            image = [weakSelf blurredImage:image];
        }
        if (completion) completion(image);
    }];
}

#pragma mark - Private
- (UIImage *)blurredImage:(UIImage *)image {
    CIImage *ciImage = [[CIImage alloc] initWithImage:image];
    CIFilter *blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blurFilter setValue:ciImage forKey:kCIInputImageKey];
    [blurFilter setValue:@(10.0) forKey:kCIInputRadiusKey];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:blurFilter.outputImage fromRect:[ciImage extent]];
    UIImage *blurred = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return blurred;
}

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName {
    [self setImageFromUrl:urlString
          placeholderImage:placeholderName
                       Blr:NO
                 Shimmering:NO
                 completion:nil];
}

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName
             completion:(void(^)(UIImage *image))completion {
    [self setImageFromUrl:urlString
          placeholderImage:placeholderName
                       Blr:NO
                 Shimmering:YES
                 completion:completion];
}

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName
                    Blr:(BOOL)blur
              Shimmering:(BOOL)shimmer
              completion:(void(^)(UIImage *image))completion {
    
    UIImage *placeholder = placeholderName ? [UIImage imageNamed:placeholderName] ? [UIImage imageNamed:placeholderName] : [UIImage systemImageNamed:placeholderName] : nil;
    
    if (shimmer) {
        UIView *shimmerView = [[UIView alloc] initWithFrame:self.bounds];
        shimmerView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
        shimmerView.tag = 9999;
        shimmerView.layer.cornerRadius = self.layer.cornerRadius;
        shimmerView.clipsToBounds = YES;
        [self addSubview:shimmerView];
    }
    
    __weak typeof(self) weakSelf = self;
    [self sd_setImageWithURL:[NSURL URLWithString:urlString]
            placeholderImage:placeholder
                     options:SDWebImageRetryFailed | SDWebImageHighPriority | SDWebImageRefreshCached
                   completed:^(UIImage * _Nullable image, NSError * _Nullable error,
                               SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
        
        [[weakSelf viewWithTag:9999] removeFromSuperview]; // remove shimmer
        
        if (blur && image) {
            image = [weakSelf blurredImage:image];
        }
        if (completion) completion(image ?: placeholder);
    }];
}


@end

