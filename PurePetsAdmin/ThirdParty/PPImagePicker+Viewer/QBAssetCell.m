//
//  QBAssetCell.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBAssetCell.h"

@interface QBAssetCell ()

@property (weak, nonatomic) IBOutlet UIView *overlayView;

@end

@implementation QBAssetCell

// QBAssetCell.m

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setupOrderBadge];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self pp_setSelectionIndex:0]; // hide by default
}

- (void)setupOrderBadge {
    if (self.pp_orderLabel) return;
    
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectZero];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = [AppForgroundColr colorWithAlphaComponent:0.8];
    badge.textColor = AppPrimaryClr;
    badge.font = [UIFont fontWithName:@"Beiruti-Bold" size:14];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.layer.cornerRadius = 14;
    badge.layer.masksToBounds = YES;
    badge.hidden = YES;
    badge.layer.borderColor = AppPrimaryClr.CGColor;
    badge.layer.borderWidth = 1.0;
    [self.contentView addSubview:badge];
    self.pp_orderLabel = badge;
    
    // Top-right corner
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintGreaterThanOrEqualToConstant:28],
        [badge.heightAnchor constraintEqualToConstant:28],
        [badge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [badge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4]
    ]];
}

- (void)pp_setSelectionIndex:(NSInteger)index {
    if (index <= 0) {
        self.pp_orderLabel.hidden = YES;
        self.pp_orderLabel.text = @"";
    } else {
        self.pp_orderLabel.hidden = NO;
        self.pp_orderLabel.text = [NSString stringWithFormat:@"%ld", (long)index];
    }
}


- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    
    // Show/hide overlay view
    self.overlayView.hidden = !(selected && self.showsOverlayViewWhenSelected);
}

@end
