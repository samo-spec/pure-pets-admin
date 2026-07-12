//
//  QBCheckmarkView.h
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface QBCheckmarkView : UIView

@property (nonatomic, strong, readonly) UIImageView *imageView;
- (void)setChecked:(BOOL)checked animated:(BOOL)animated;
@end
