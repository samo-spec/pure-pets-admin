//
//  StaffRoleEditorViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>
#import "RPManager.h"
#import "PPRolePermission.h"

NS_ASSUME_NONNULL_BEGIN

@interface StaffRoleEditorViewController : UIViewController

@property (nonatomic, strong, nullable) StaffRoleTemplate *roleTemplate;

- (instancetype)initWithRole:(nullable StaffRoleTemplate *)role;

@end

NS_ASSUME_NONNULL_END
