//
//  UsersListVC.h
//

#import <UIKit/UIKit.h>
#import <XLForm/XLForm.h>
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
@property (nonatomic, copy, nullable) void (^onCustomerAttachmentCancelled)(void);

- (instancetype)initWithViewFor:(ViewFor)mode; // convenience

/// Select an existing active customer account without exposing account edits.
+ (instancetype)posCustomerAttachmentPicker NS_SWIFT_NAME(makePOSCustomerAttachmentPicker());

/// UI
@property (nonatomic, strong) XLFormSectionDescriptor *usersSection;
@end
NS_ASSUME_NONNULL_END
