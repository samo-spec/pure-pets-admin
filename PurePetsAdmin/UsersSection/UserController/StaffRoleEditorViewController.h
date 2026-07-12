//
//  StaffRoleEditorViewController.h
//  PurePetsAdmin
//

#import "XLFormViewController.h"
#import "RPManager.h"
#import "PPRolePermission.h"

NS_ASSUME_NONNULL_BEGIN

@interface StaffRoleEditorViewController : XLFormViewController

@property (nonatomic, strong, nullable) StaffRoleTemplate *roleTemplate;

- (instancetype)initWithRole:(nullable StaffRoleTemplate *)role;

@end

NS_ASSUME_NONNULL_END
