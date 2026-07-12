//
//  UIViewController+PMotal.h
//  PresentViewController
//
//  Created by PXJ on 2019/4/23.
//  Copyright © 2019 CMRead. All rights reserved.
//



typedef NS_ENUM(NSInteger,PVCDirection)
{
    PVCDirectionCenter = 0,
    PVCDirectionTop,
    PVCDirectionLeft,
    PVCDirectionRight,
    PVCDirectionBottom
};

NS_ASSUME_NONNULL_BEGIN

typedef void(^PresentCompletion)(void);

@interface UIViewController (PVCMotal)

- (void)presentViewController:(UIViewController *)viewController inSize:(CGSize)size direction:(PVCDirection)direction completion:(PresentCompletion)completion;



@end

NS_ASSUME_NONNULL_END
