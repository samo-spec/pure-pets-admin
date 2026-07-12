//
//  AdminDashboardViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 21/08/2025.
//


//
//  AdminDashboardViewController.h
//  PurePetsAdmin
//

#import "PPParallax.h"
#import <PhotosUI/PhotosUI.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdminDashboardViewController : XLFormViewController<PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, assign) BOOL didAskForBiometric;
// .h
@property (nonatomic, strong) UIView *headerRoot;        // immersive hero container
@property (nonatomic, strong) PPParallax *parallax;

@end

NS_ASSUME_NONNULL_END
