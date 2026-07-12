//
//  PPImageEditor 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 11/09/2025.
//


#import "PPImageEditor.h"

@interface PPImageEditor ()
@property (nonatomic, strong) UIImage *originalImage;
@property (nonatomic, strong) UIImage *currentImage;
@property (nonatomic, strong) CIContext *ciContext;
@end

@implementation PPImageEditor

#pragma mark - Initialization

+ (instancetype)editorWithImage:(UIImage *)image {
    return [[self alloc] initWithImage:image];
}

+ (instancetype)editorWithImageView:(UIImageView *)imageView {
    return [[self alloc] initWithImage:imageView.image];
}

- (instancetype)initWithImage:(UIImage *)image {
    self = [super init];
    if (self) {
        _originalImage = image;
        _currentImage = image;
        _highQualityProcessing = YES;
        
        // Create Core Image context
        NSDictionary *options = @{kCIContextUseSoftwareRenderer : @NO};
        _ciContext = [CIContext contextWithOptions:options];
    }
    return self;
}

#pragma mark - Basic Editing (Synchronous)

- (UIImage *)cropToRect:(CGRect)cropRect {
    @autoreleasepool {
        CGImageRef imageRef = CGImageCreateWithImageInRect(self.currentImage.CGImage, cropRect);
        UIImage *croppedImage = [UIImage imageWithCGImage:imageRef scale:self.currentImage.scale orientation:self.currentImage.imageOrientation];
        CGImageRelease(imageRef);
        self.currentImage = croppedImage;
        return croppedImage;
    }
}

- (UIImage *)resizeToSize:(CGSize)newSize {
    @autoreleasepool {
        UIGraphicsBeginImageContextWithOptions(newSize, NO, self.highQualityProcessing ? self.currentImage.scale : 0.0);
        [self.currentImage drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
        UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        self.currentImage = resizedImage;
        return resizedImage;
    }
}

- (UIImage *)rotateByAngle:(CGFloat)angle {
    @autoreleasepool {
        // Convert degrees to radians
        CGFloat radians = angle * M_PI / 180.0;
        
        // Calculate the size of the rotated view's containing box
        UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.currentImage.size.width, self.currentImage.size.height)];
        CGAffineTransform t = CGAffineTransformMakeRotation(radians);
        rotatedViewBox.transform = t;
        CGSize rotatedSize = rotatedViewBox.frame.size;
        
        // Create the bitmap context
        UIGraphicsBeginImageContextWithOptions(rotatedSize, NO, self.highQualityProcessing ? self.currentImage.scale : 0.0);
        CGContextRef bitmap = UIGraphicsGetCurrentContext();
        
        // Move the origin to the middle of the image so we will rotate and scale around the center.
        CGContextTranslateCTM(bitmap, rotatedSize.width/2, rotatedSize.height/2);
        
        // Rotate the image context
        CGContextRotateCTM(bitmap, radians);
        
        // Now, draw the rotated/scaled image into the context
        CGContextScaleCTM(bitmap, 1.0, -1.0);
        CGContextDrawImage(bitmap, CGRectMake(-self.currentImage.size.width / 2, -self.currentImage.size.height / 2, self.currentImage.size.width, self.currentImage.size.height), self.currentImage.CGImage);
        
        UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        self.currentImage = rotatedImage;
        return rotatedImage;
    }
}

- (UIImage *)flipHorizontal:(BOOL)horizontal vertical:(BOOL)vertical {
    @autoreleasepool {
        CGSize size = self.currentImage.size;
        UIGraphicsBeginImageContextWithOptions(size, NO, self.highQualityProcessing ? self.currentImage.scale : 0.0);
        CGContextRef context = UIGraphicsGetCurrentContext();
        
        // Flip coordinates if needed
        if (horizontal) {
            CGContextTranslateCTM(context, size.width, 0);
            CGContextScaleCTM(context, -1.0, 1.0);
        }
        if (vertical) {
            CGContextTranslateCTM(context, 0, size.height);
            CGContextScaleCTM(context, 1.0, -1.0);
        }
        
        // Draw the image
        [self.currentImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
        
        UIImage *flippedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        self.currentImage = flippedImage;
        return flippedImage;
    }
}

#pragma mark - Core Image Filters (Synchronous)

- (UIImage *)applyFilterWithName:(NSString *)filterName parameters:(NSDictionary *)parameters {
    @autoreleasepool {
        CIImage *inputImage = [[CIImage alloc] initWithImage:self.currentImage];
        
        if (!inputImage) return self.currentImage;
        
        CIFilter *filter = [CIFilter filterWithName:filterName];
        [filter setValue:inputImage forKey:kCIInputImageKey];
        
        // Set custom parameters if provided
        [parameters enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [filter setValue:obj forKey:key];
        }];
        
        CIImage *outputImage = filter.outputImage;
        
        if (!outputImage) return self.currentImage;
        
        CGImageRef cgImage = [self.ciContext createCGImage:outputImage fromRect:outputImage.extent];
        UIImage *filteredImage = [UIImage imageWithCGImage:cgImage scale:self.currentImage.scale orientation:self.currentImage.imageOrientation];
        CGImageRelease(cgImage);
        
        self.currentImage = filteredImage;
        return filteredImage;
    }
}

- (UIImage *)adjustBrightness:(CGFloat)brightness contrast:(CGFloat)contrast saturation:(CGFloat)saturation {
    NSDictionary *params = @{
        kCIInputBrightnessKey: @(brightness),
        kCIInputContrastKey: @(contrast),
        kCIInputSaturationKey: @(saturation)
    };
    return [self applyFilterWithName:@"CIColorControls" parameters:params];
}

- (UIImage *)autoEnhance {
    @autoreleasepool {
        CIImage *inputImage = [[CIImage alloc] initWithImage:self.currentImage];
        
        if (!inputImage) return self.currentImage;
        
        NSArray *adjustments = [inputImage autoAdjustmentFiltersWithOptions:@{kCIImageAutoAdjustEnhance: @YES}];
        
        CIImage *outputImage = inputImage;
        for (CIFilter *filter in adjustments) {
            [filter setValue:outputImage forKey:kCIInputImageKey];
            outputImage = filter.outputImage;
        }
        
        if (!outputImage) return self.currentImage;
        
        CGImageRef cgImage = [self.ciContext createCGImage:outputImage fromRect:outputImage.extent];
        UIImage *enhancedImage = [UIImage imageWithCGImage:cgImage scale:self.currentImage.scale orientation:self.currentImage.imageOrientation];
        CGImageRelease(cgImage);
        
        self.currentImage = enhancedImage;
        return enhancedImage;
    }
}

#pragma mark - Drawing & Text (Synchronous)

- (UIImage *)drawOnImageWithPath:(UIBezierPath *)path color:(UIColor *)color width:(CGFloat)lineWidth {
    @autoreleasepool {
        UIGraphicsBeginImageContextWithOptions(self.currentImage.size, NO, self.highQualityProcessing ? self.currentImage.scale : 0.0);
        [self.currentImage drawAtPoint:CGPointZero];
        
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSetLineWidth(context, lineWidth);
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextAddPath(context, path.CGPath);
        CGContextStrokePath(context);
        
        UIImage *drawnImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        self.currentImage = drawnImage;
        return drawnImage;
    }
}

- (UIImage *)addText:(NSString *)text atPoint:(CGPoint)point attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes {
    @autoreleasepool {
        UIGraphicsBeginImageContextWithOptions(self.currentImage.size, NO, self.highQualityProcessing ? self.currentImage.scale : 0.0);
        [self.currentImage drawAtPoint:CGPointZero];
        
        // Default attributes if none provided
        if (!attributes) {
            attributes = @{
                NSFontAttributeName: [UIFont systemFontOfSize:36.0],
                NSForegroundColorAttributeName: [UIColor whiteColor],
                NSStrokeColorAttributeName: [UIColor blackColor],
                NSStrokeWidthAttributeName: @(-3.0)
            };
        }
        
        [text drawAtPoint:point withAttributes:attributes];
        
        UIImage *textImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        self.currentImage = textImage;
        return textImage;
    }
}

#pragma mark - Advanced Editing (Asynchronous with Completion)

- (void)applyComplexFilter:(CIFilter *)filter completion:(PPImageEditCompletion)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            CIImage *inputImage = [[CIImage alloc] initWithImage:self.currentImage];
            
            if (!inputImage) {
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, [NSError errorWithDomain:@"PPImageEditorError" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create CIImage"}]);
                    });
                }
                return;
            }
            
            [filter setValue:inputImage forKey:kCIInputImageKey];
            CIImage *outputImage = filter.outputImage;
            
            if (!outputImage) {
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, [NSError errorWithDomain:@"PPImageEditorError" code:1002 userInfo:@{NSLocalizedDescriptionKey: @"Filter produced no output"}]);
                    });
                }
                return;
            }
            
            CGImageRef cgImage = [self.ciContext createCGImage:outputImage fromRect:outputImage.extent];
            UIImage *filteredImage = [UIImage imageWithCGImage:cgImage scale:self.currentImage.scale orientation:self.currentImage.imageOrientation];
            CGImageRelease(cgImage);
            
            self.currentImage = filteredImage;
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(filteredImage, nil);
                });
            }
        }
    });
}

- (void)applyMultipleOperations:(NSArray<void (^)(void)> *)operations completion:(PPImageEditCompletion)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            UIImage *result = self.currentImage;
            PPImageEditor *tempEditor = [PPImageEditor editorWithImage:result];
            
            for (void (^operation)(void) in operations) {
                @autoreleasepool {
                    operation();
                    result = tempEditor.currentImage;
                }
            }
            
            self.currentImage = result;
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(result, nil);
                });
            }
        }
    });
}

- (void)processImageOnBackgroundThreadWithBlock:(UIImage * (^)(UIImage *image))processBlock completion:(PPImageEditCompletion)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            UIImage *result = processBlock(self.currentImage);
            self.currentImage = result;
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(result, nil);
                });
            }
        }
    });
}

#pragma mark - Utilities

- (void)revertToOriginal {
    self.currentImage = self.originalImage;
}

- (UIImage *)currentImage {
    return _currentImage;
}

@end

#pragma mark - UIImageView Category

@implementation UIImageView (PPImageEditor)

- (PPImageEditor *)imageEditor {
    return [PPImageEditor editorWithImageView:self];
}

@end