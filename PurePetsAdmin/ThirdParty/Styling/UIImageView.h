//
//  UIImageView.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 21/08/2025.
//


// UIImageView.h
#import <UIKit/UIKit.h>

@interface UIImageView (Remote)

+ (void)imageFromUrl:(NSString *)urlString completion:(void(^)(UIImage *image))completion; // 2
+ (UIImage *)imageFromUrl:(NSString *)urlString;


- (void)setImageFromUrl:(NSString *)urlString; // 3
- (void)setImageFromUrl:(NSString *)urlString completion:(void(^)(UIImage *image))completion; // 4
- (void)setImageFromUrl:(NSString *)urlString
                    Blr:(BOOL)blur
              Shimmering:(BOOL)shimmer
              completion:(void(^)(UIImage *image))completion; // 5
- (void)setImageFromUrl:(NSString *)urlString
                    Blr:(BOOL)blur
              Shimmering:(BOOL)shimmer; // 6

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName;

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName
             completion:(void(^)(UIImage *image))completion ;

- (void)setImageFromUrl:(NSString *)urlString
       placeholderImage:(NSString *)placeholderName
                    Blr:(BOOL)blur
              Shimmering:(BOOL)shimmer
             completion:(void(^)(UIImage *image))completion;

@end
