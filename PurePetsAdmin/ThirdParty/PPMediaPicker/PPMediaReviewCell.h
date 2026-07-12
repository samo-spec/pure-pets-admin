//
//  PPMediaReviewCell.h
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import <UIKit/UIKit.h>
#import "PPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface PPMediaReviewCell : UICollectionViewCell

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UIView *videoIndicator;
@property (nonatomic, copy) void (^deleteHandler)(void);
@property (nonatomic, copy) void (^editHandler)(void);

- (void)configureWithItem:(PPMediaItem *)item;

@end

NS_ASSUME_NONNULL_END
