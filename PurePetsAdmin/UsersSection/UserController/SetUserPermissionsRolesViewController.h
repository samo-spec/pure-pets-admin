//
//  SetUserPermissionsRolesViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//

//
//  SetUserPermissionsRolesViewController.h
//  PurePetsAdmin
//

typedef NS_ENUM(NSInteger, EditType) {
    EditTypeDefault = 0,                 // Account + Roles + Permissions
    EditTypeUserData = 1,                // Account only
    EditTypeUserPermisstionAndRoles = 2  // Roles + Permissions only
};

@class PPImageCollection;

@interface SetUserPermissionsRolesViewController : XLFormViewController


// Photo header
@property (nonatomic, strong) UIView *photoHeaderRoot;
@property (nonatomic, strong) UIImageView *avatarIMV;
@property (nonatomic, strong) UIButton *addPhotoPill;

@property (nonatomic, strong) PPImageCollection *avatarPicker;
@property (nonatomic, strong) JGProgressHUD *hud;


- (instancetype)initWithUser:(UserModel *)user type:(EditType)type;

/// Nice-to-have convenience creators
+ (instancetype)accountEditorForUser:(UserModel *)user;          // EditTypeUserData
+ (instancetype)permRoleEditorForUser:(UserModel *)user;         // EditTypeUserPermisstionAndRoles
+ (instancetype)fullEditorForUser:(UserModel *)user;             // EditTypeDefault

@end


/*
 // Account-only screen
 UIViewController *vc1 = [SetUserPermissionsRolesViewController accountEditorForUser:user];

 // Roles + permissions screen
 UIViewController *vc2 = [SetUserPermissionsRolesViewController permRoleEditorForUser:user];

 // Full combined screen (default)
 UIViewController *vc3 = [SetUserPermissionsRolesViewController fullEditorForUser:user];

 // Or directly:
 UIViewController *vcFlag = [[SetUserPermissionsRolesViewController alloc] initWithUser:user
                                                                                   type:EditTypeUserPermisstionAndRoles];

 */
