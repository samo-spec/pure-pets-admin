//
//  ImageViewerController.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 30/09/2025.
//


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ImageViewerSourceType) {
    ImageViewerSourceTypeURLs,
    ImageViewerSourceTypeImages
};

@interface ImageViewerController : UIViewController

/// Create viewer with URLs
- (instancetype)initWithImageURLs:(NSArray<NSString *> *)urls;

/// Create viewer with UIImages
- (instancetype)initWithImages:(NSArray<UIImage *> *)images;

@end

NS_ASSUME_NONNULL_END
