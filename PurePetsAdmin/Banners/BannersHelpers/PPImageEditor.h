#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PPImageEditCompletion)(UIImage * _Nullable editedImage, NSError * _Nullable error);
typedef void (^PPImageEditProgress)(CGFloat progress);

@interface PPImageEditor : NSObject

#pragma mark - Initialization
+ (instancetype)editorWithImage:(UIImage *)image;
+ (instancetype)editorWithImageView:(UIImageView *)imageView;
- (instancetype)initWithImage:(UIImage *)image;

#pragma mark - Basic Editing (Synchronous)
- (UIImage *)cropToRect:(CGRect)cropRect;
- (UIImage *)resizeToSize:(CGSize)newSize;
- (UIImage *)rotateByAngle:(CGFloat)angle; // Angle in degrees
- (UIImage *)flipHorizontal:(BOOL)horizontal vertical:(BOOL)vertical;

#pragma mark - Core Image Filters (Synchronous)
- (UIImage *)applyFilterWithName:(NSString *)filterName parameters:(NSDictionary * _Nullable)parameters;
- (UIImage *)adjustBrightness:(CGFloat)brightness contrast:(CGFloat)contrast saturation:(CGFloat)saturation;
- (UIImage *)autoEnhance; // Automatic image enhancement

#pragma mark - Drawing & Text (Synchronous)
- (UIImage *)drawOnImageWithPath:(UIBezierPath *)path color:(UIColor *)color width:(CGFloat)lineWidth;
- (UIImage *)addText:(NSString *)text atPoint:(CGPoint)point attributes:(NSDictionary<NSAttributedStringKey, id> * _Nullable)attributes;

#pragma mark - Advanced Editing (Asynchronous with Completion)
- (void)applyComplexFilter:(CIFilter *)filter completion:(PPImageEditCompletion)completion;
- (void)processImageOnBackgroundThreadWithBlock:(UIImage * (^)(UIImage *image))processBlock completion:(PPImageEditCompletion)completion;

#pragma mark - Utilities
- (void)revertToOriginal;
- (UIImage *)currentImage;
@property (nonatomic, strong, readonly) UIImage *originalImage;
@property (nonatomic, assign) BOOL highQualityProcessing; // Default YES

@end

// Convenience category for UIImageView
@interface UIImageView (PPImageEditor)
- (PPImageEditor *)imageEditor;
@end

NS_ASSUME_NONNULL_END
