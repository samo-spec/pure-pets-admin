//
//  PPAdminButton.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 27/08/2025.
//


// in PPAdminButton.m
#import "PPAdminButton.h"

@implementation PPAdminButton

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.adjustsImageWhenHighlighted = YES;
        self.admin = NO;
        [self applyStateAnimated:NO];
        self.accessibilityIdentifier = @"admin-permission-toggle";
    }
    return self;
}

- (void)setAdmin:(BOOL)admin {
    if (_admin == admin) return;
    _admin = admin;
    [self applyStateAnimated:YES];
}

- (void)applyStateAnimated:(BOOL)animated {
    
    
   // UIImage *img = [UIImage imageNamed:(self.isAdmin ? @"adminTake" : @"adminGive")];
    NSString *acc = self.isAdmin ? @"Revoke admin permission" : @"Grant admin permission";
    
    
    UIImage *img = [UIImage imageNamed: @"updateperm"];
    //updateperm
    UIColor *tintColor = self.isAdmin ? AppPrimaryClr : SeconderyTextClr;
    //UIColor *backColor = self.isAdmin ? AppPrimaryClr : AppBackgroundClr;
    
    
    [self setImage:img forState:UIControlStateNormal];
    self.accessibilityLabel = acc;

    self.backgroundColor = UIColor.clearColor;
    self.tintColor = tintColor;
    self.layer.cornerRadius = self.hxh / 2;
    
    self.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.25].CGColor;
    self.layer.shadowOpacity = 0.2;
    self.layer.shadowRadius = 6.0;
    self.layer.shadowOffset = CGSizeMake(0, 3);
    self.layer.masksToBounds = NO;
    
    if (animated) {
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
        [UIView animateWithDuration:0.2
                              delay:0
             usingSpringWithDamping:0.6
              initialSpringVelocity:0.8
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{ self.transform = CGAffineTransformIdentity; }
                         completion:nil];
    }
}

@end
