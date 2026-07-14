//
//  UsersListVC.h
//

#import <UIKit/UIKit.h>
#import "XLForm.h"
#import "PPS.h"
#import "PPPickOptionCell.h"
@class UserModel;

#import "PPUserCell.h"
NS_ASSUME_NONNULL_BEGIN
@interface UsersListVC : UIViewController <PPPickOptionCellDelegate, PPSDelegate, XLFormRowDescriptorViewController>
@property (nonatomic, assign) ViewFor viewForMode;  // <— NEW
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPS *searchView;
@property (nonatomic, strong) NSMutableArray<UserModel *> *allUsers;
@property (nonatomic, strong) NSMutableArray<UserModel *> *filteredUsers;

@property (nonatomic, copy) NSString *currentQuery;
@property (nonatomic, copy, nullable) NSString *searchPlaceholderText;
@property (nonatomic, copy, nullable) void (^onUserPicked)(UserModel *user);

- (instancetype)initWithViewFor:(ViewFor)mode; // convenience

/// UI
@property (nonatomic, strong) XLFormSectionDescriptor *usersSection;
@end
NS_ASSUME_NONNULL_END
