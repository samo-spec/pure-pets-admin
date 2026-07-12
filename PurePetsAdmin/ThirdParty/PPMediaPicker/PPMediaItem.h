//
//  PPMediaItem.h
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPMediaItem : NSObject <NSSecureCoding>

@property (nonatomic, strong, nullable) PHAsset *asset;
@property (nonatomic, strong, nullable) UIImage *image;
@property (nonatomic, strong, nullable) UIImage *originalImage;
@property (nonatomic, strong, nullable) NSURL *videoURL;
@property (nonatomic, assign) BOOL isVideo;
@property (nonatomic, assign) BOOL isEdited;
@property (nonatomic, copy) NSString *uniqueID;

+ (instancetype)itemWithAsset:(PHAsset *)asset;
+ (instancetype)itemWithImage:(UIImage *)image;
+ (instancetype)itemWithVideoURL:(NSURL *)videoURL;

@end

NS_ASSUME_NONNULL_END
