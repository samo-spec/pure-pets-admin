//
//  PPMediaReviewController.h
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import <UIKit/UIKit.h>
#import "PPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@class PPMediaReviewController;

@protocol PPMediaReviewControllerDelegate <NSObject>
- (void)mediaReviewController:(PPMediaReviewController *)controller didFinishWithMedia:(NSArray<PPMediaItem *> *)media;
- (void)mediaReviewControllerDidTapAddMore:(PPMediaReviewController *)controller;
@end

@interface PPMediaReviewController : UICollectionViewController

@property (nonatomic, weak) id<PPMediaReviewControllerDelegate> delegate;
@property (nonatomic, strong) NSMutableArray<PPMediaItem *> *mediaItems;

@end

NS_ASSUME_NONNULL_END
