//
//  QBAssetCell.h
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QBVideoIndicatorView;

// QBAssetCell.h

@interface QBAssetCell : UICollectionViewCell

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet QBVideoIndicatorView *videoIndicatorView;
@property (nonatomic, assign) BOOL showsOverlayViewWhenSelected;

// ADD:
@property (nonatomic, strong) UILabel *pp_orderLabel;
- (void)pp_setSelectionIndex:(NSInteger)index; // index >=1 shows badge, <=0 hides

@end
