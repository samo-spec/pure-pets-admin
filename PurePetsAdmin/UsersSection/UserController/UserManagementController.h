//
//  UserManagementController.h
//  PurePetsAdmin
//
//  Premium User Details Editor — Studio-grade admin UI
//  Console parity: Users Management → User Details
//
//  Built without XLForm for maximum control, hierarchy, and state precision.

#import <UIKit/UIKit.h>

@class UserModel;

typedef NS_ENUM(NSInteger, EditType) {
    EditTypeDefault = 0,                 // Account + Roles + Permissions
    EditTypeUserData = 1,                // Account only
    EditTypeUserPermisstionAndRoles = 2  // Roles + Permissions only
};

@interface UserManagementController : UIViewController

- (instancetype)initWithUser:(UserModel *)user type:(EditType)type;

/// Account-only editor
+ (instancetype)accountEditorForUser:(UserModel *)user;

/// Roles + permissions editor
+ (instancetype)permRoleEditorForUser:(UserModel *)user;

/// Full combined editor (default)
+ (instancetype)fullEditorForUser:(UserModel *)user;

/// Set to YES if an enclosing container provides its own navigation header. Default is NO.
@property (nonatomic, assign) BOOL hidesInternalNavigationBar;

@end
