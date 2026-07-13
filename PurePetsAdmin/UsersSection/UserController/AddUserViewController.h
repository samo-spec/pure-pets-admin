#import <UIKit/UIKit.h>
#import "UserModel.h"

@interface AddUserViewController : UIViewController
@property (nonatomic, strong) NSArray<NSDictionary *> * _Nullable permissions;
@property (nonatomic, strong) UserModel *_Nullable userModel;
- (instancetype)initWithStaffMember:(UserModel *)staffMember;
@end
