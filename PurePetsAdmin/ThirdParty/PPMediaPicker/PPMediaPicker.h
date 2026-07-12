//
//  PPMediaPicker.h
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@class PPMediaPicker;

@protocol PPMediaPickerDelegate <NSObject>
- (void)mediaPicker:(PPMediaPicker *)picker didFinishWithMedia:(NSArray<PPMediaItem *> *)media;
- (void)mediaPickerDidCancel:(PPMediaPicker *)picker;
@end

@interface PPMediaPicker : NSObject

@property (nonatomic, weak) id<PPMediaPickerDelegate> delegate;
@property (nonatomic, strong) NSMutableArray<PPMediaItem *> *selectedMedia;
@property (nonatomic, assign) NSInteger maxCount;

- (instancetype)initWithPresentingViewController:(UIViewController *)presentingViewController;

- (void)openLibrary;
- (void)openCamera;
- (void)showReviewScreen;

@end

NS_ASSUME_NONNULL_END
