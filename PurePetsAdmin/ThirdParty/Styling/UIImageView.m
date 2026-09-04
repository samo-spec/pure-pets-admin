//
//  UIImageView+Remote.m
//  PurePetsAdmin
//

#import "UIImageView.h"
#import "PurePetsAdmin-Swift.h"
#import <Accelerate/Accelerate.h>

@implementation UIImageView (Remote)

+ (nullable UIImage *)imageFromUrl:(NSString *)urlString {
    return [PPAdminImageLoader cachedImageForURLString:urlString];
}

+ (void)imageFromUrl:(NSString *)urlString
          completion:(void(^)(UIImage * _Nullable image))completion {
    [PPAdminImageLoader loadImageWithURLString:urlString completion:^(UIImage * _Nullable image, NSError * _Nullable error, BOOL fromCache) {
        if (completion) completion(image);
    }];
}

- (void)setImageFromUrl:(NSString *)urlString {
    [self setImageFromUrl:urlString Blr:NO Shimmering:YES completion:nil];
}

- (void)setImageFromUrl:(NSString *)urlString completion:(void(^)(UIImage * _Nullable image))completion {
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
              completion:(void(^)(UIImage * _Nullable image))completion {
    [self pp_setImageFromUrl:urlString placeholder:[UIImage imageNamed:@"Placeholder"] blur:blur shimmering:shimmer completion:completion];
}

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName {
    [self setImageFromUrl:urlString placeholderImage:placeholderName completion:nil];
}

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName
             completion:(void(^)(UIImage * _Nullable image))completion {
    [self setImageFromUrl:urlString placeholderImage:placeholderName Blr:NO Shimmering:YES completion:completion];
}

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName
                    Blr:(BOOL)blur
              Shimmering:(BOOL)shimmer
             completion:(void(^)(UIImage * _Nullable image))completion {
    UIImage *placeholder = placeholderName ? ([UIImage imageNamed:placeholderName] ?: [UIImage systemImageNamed:placeholderName]) : nil;
    [self pp_setImageFromUrl:urlString placeholder:placeholder blur:blur shimmering:shimmer completion:completion];
}

- (void)pp_setImageFromUrl:(NSString *)urlString
               placeholder:(UIImage *)placeholder
                      blur:(BOOL)blur
                shimmering:(BOOL)shimmer
                completion:(void(^)(UIImage * _Nullable image))completion {
    if (shimmer) {
        UIView *shimmerView = [[UIView alloc] initWithFrame:self.bounds];
        shimmerView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
        shimmerView.tag = 9999;
        shimmerView.layer.cornerRadius = self.layer.cornerRadius;
        shimmerView.clipsToBounds = YES;
        [self addSubview:shimmerView];
    }

    __weak typeof(self) weakSelf = self;
    [PPAdminImageLoader setImageWithURLString:urlString onImageView:self placeholder:placeholder completion:^(UIImage * _Nullable image) {
        UIImageView *strongSelf = weakSelf;
        if (!strongSelf) return;
        [[strongSelf viewWithTag:9999] removeFromSuperview];
        UIImage *finalImage = blur && image ? [strongSelf blurredImage:image] : image;
        if (blur && finalImage) strongSelf.image = finalImage;
        if (completion) completion(finalImage);
    }];
}

- (UIImage *)blurredImage:(UIImage *)image {
    CIImage *ciImage = [[CIImage alloc] initWithImage:image];
    if (!ciImage) return image;
    CIFilter *blurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blurFilter setValue:ciImage forKey:kCIInputImageKey];
    [blurFilter setValue:@(10.0) forKey:kCIInputRadiusKey];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:blurFilter.outputImage fromRect:[ciImage extent]];
    if (!cgImage) return image;
    UIImage *blurred = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return blurred;
}

@end
