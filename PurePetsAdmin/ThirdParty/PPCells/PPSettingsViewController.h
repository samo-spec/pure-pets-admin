//
//  PPSettingsViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 2026-07-13.
//  Reimagined from absolute first principles:
//  Category-defining Admin Profile & Identity Command Center,
//  Sovereign Permissions Inspector, and Security Vault.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UserModel;

@interface PPSettingsViewController : UIViewController
@end

@interface PPAdminProfileViewController : UIViewController
- (instancetype)initWithUser:(nullable UserModel *)user;
@end

@interface PPAdminPermissionsInspectorSheet : UIViewController
- (instancetype)initWithUser:(nullable UserModel *)user;
@end

@interface PPAdminSecurityVaultSheet : UIViewController
- (instancetype)initWithUser:(nullable UserModel *)user;
@end

NS_ASSUME_NONNULL_END
