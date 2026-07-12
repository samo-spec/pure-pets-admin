//
//  UIView.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 21/08/2025.
//


//
//  UIView+HXFrame.m
//  PurePetsAdmin
//

#import "UIView.h"

@implementation UIView (HXFrame)

#pragma mark - Width / Height
- (CGFloat)hxw { return self.frame.size.width; }
- (void)setHxw:(CGFloat)hxw {
    CGRect f = self.frame;
    f.size.width = hxw;
    self.frame = f;
    //DLog(@"[HXFrame] Set width -> %.2f", hxw);
}

- (CGFloat)hxh { return self.frame.size.height; }
- (void)setHxh:(CGFloat)hxh {
    CGRect f = self.frame;
    f.size.height = hxh;
    self.frame = f;
    DLog(@"[HXFrame] Set height -> %.2f", hxh);
}

#pragma mark - X / Y
- (CGFloat)hxx { return self.frame.origin.x; }
- (void)setHxx:(CGFloat)hxx {
    CGRect f = self.frame;
    f.origin.x = hxx;
    self.frame = f;
    //DLog(@"[HXFrame] Set X -> %.2f", hxx);
}

- (CGFloat)hxy { return self.frame.origin.y; }
- (void)setHxy:(CGFloat)hxy {
    CGRect f = self.frame;
    f.origin.y = hxy;
    self.frame = f;
    //DLog(@"[HXFrame] Set Y -> %.2f", hxy);
}

#pragma mark - Max / Min
- (CGFloat)hxmax { return CGRectGetMaxX(self.frame); }
- (CGFloat)hxmaxy { return CGRectGetMaxY(self.frame); }
- (CGFloat)hxminx { return CGRectGetMinX(self.frame); }
- (CGFloat)hxminy { return CGRectGetMinY(self.frame); }

- (CGRect)hxFrame { return CGRectMake(self.frame.origin.x, self.frame.origin.y, self.frame.size.width, self.frame.size.height); }
- (void)setHxFrame:(CGRect)hxFrame
{
    CGRect f = self.frame;
    f.origin.x = hxFrame.origin.x;
    f.origin.y = hxFrame.origin.y;
    f.size.width = hxFrame.size.width;
    f.size.height= hxFrame.size.height;
    self.frame = f;
}


// ======================================= PLACE ICON ABOVE OTHER VIEW  < PASS ICON POSITION =============================================//

// In UIView+HXFrame.m

#pragma mark - Place Icon (Overlay style above view, not inside)

- (void)placeIcon:(NSString *)icon onPostions:(IconPostions)Postions {
    if (!icon.length) return;
    if (!self.superview) {
        //DLog(@"[HXFrame] ⚠️ No superview to place overlay icon on %@", self);
        return;
    }

    // Remove old one if any (avoid duplicates)
    for (UIView *sub in self.superview.subviews) {
        if (sub.tag == 909090 && [sub isKindOfClass:UIImageView.class]) {
            [sub removeFromSuperview];
        }
        
        if (sub.tag == 9090901 && [sub isKindOfClass:UIImageView.class]) {
            [sub removeFromSuperview];
        }
    }

    UIImage *img = [UIImage imageNamed:icon];
    if (!img) img = [UIImage systemImageNamed:icon];
    if (!img) return;
    
    
    
            
    UIImageView *bgImageView = [[UIImageView alloc] initWithImage:[UIImage pp_symbolNamed:@"seal.fill" pointSize:20 weight:UIImageSymbolWeightLight scale:UIImageSymbolScaleDefault palette:@[AppForgroundColr] makeTemplate:YES]];
    bgImageView.contentMode = UIViewContentModeScaleToFill;
    bgImageView.tag = 9090901;
    bgImageView.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat bgImageViewSize = 28;
    [NSLayoutConstraint activateConstraints:@[
        [bgImageView.widthAnchor constraintEqualToConstant:bgImageViewSize],
        [bgImageView.heightAnchor constraintEqualToConstant:bgImageViewSize]
    ]];
    bgImageView.tintColor = UIColor.whiteColor;
    [self.superview addSubview:bgImageView];
    
    
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.tag = 909090;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.backgroundColor = UIColor.clearColor; // transparent by default
    iv.layer.masksToBounds = NO;

    [self.superview addSubview:iv];
    
    CGFloat size = 24;
    [NSLayoutConstraint activateConstraints:@[
        [iv.widthAnchor constraintEqualToConstant:size],
        [iv.heightAnchor constraintEqualToConstant:size]
    ]];

    CGFloat pad = 4;

    switch (Postions) {
        case IconPostionsTopLeft:
            [iv.topAnchor constraintEqualToAnchor:self.topAnchor constant:-pad].active = YES;
            [iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-pad].active = YES;
            break;
        case IconPostionsTopRight:
            [iv.topAnchor constraintEqualToAnchor:self.topAnchor constant:-pad].active = YES;
            [iv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:pad].active = YES;
            break;
        case IconPostionsTopMiddle:
            [iv.topAnchor constraintEqualToAnchor:self.topAnchor constant:-pad].active = YES;
            [iv.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
            break;
        case IconPostionsBottomLeft:
            [iv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:pad].active = YES;
            [iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-pad].active = YES;
            break;
        case IconPostionsBottomRight:
            [iv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:pad].active = YES;
            [iv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:pad].active = YES;
            break;
        case IconPostionsBottomMiddle:
            [iv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:pad].active = YES;
            [iv.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
            break;
        case IconPostionsMiddleLeft:
            [iv.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
            [iv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-pad].active = YES;
            break;
        case IconPostionsMiddleRight:
            [iv.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
            [iv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:pad].active = YES;
            break;
    }
    [bgImageView.centerYAnchor constraintEqualToAnchor:iv.centerYAnchor].active = YES;
    [bgImageView.centerXAnchor constraintEqualToAnchor:iv.centerXAnchor].active = YES;
    
    bgImageView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.32].CGColor;
    bgImageView.layer.shadowOpacity = 1.0;
    bgImageView.layer.shadowOffset = CGSizeMake(0, 0);
    bgImageView.layer.shadowRadius = 3;
    bgImageView.layer.masksToBounds = NO;
    

}



@end
