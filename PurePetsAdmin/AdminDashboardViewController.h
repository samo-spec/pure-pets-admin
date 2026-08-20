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
@property (nonatomic, strong) UIView *headerRoot;        // immersive hero container
@property (nonatomic, strong) PPParallax *parallax;
@property (nonatomic, assign) BOOL pp_isCommandSpine;

@end

FOUNDATION_EXTERN UIViewController *PPAdminCreateCommandSpineDashboardController(void);

NS_ASSUME_NONNULL_END
