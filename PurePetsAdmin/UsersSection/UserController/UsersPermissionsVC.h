//
//  UsersPermissionsVC.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 02/09/2025.
//


//  UsersPermissionsVC.h
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UsersPermissionsVC : UITableViewController

/// Target user to manage. If nil/empty, falls back to [FUManager shared].currentUser.uid
@property (nonatomic, copy, nullable) NSString *targetUID;

/// Convenience initializer
- (instancetype)initWithUID:(nullable NSString *)uid;

@end

NS_ASSUME_NONNULL_END
