//
//  AddUserViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 21/08/2025.
//


//
//  AddUserViewController.h
//  PurePetsAdmin
//
#import "PPParallax.h"
#import "XLFormViewController.h"
#import "UserModel.h"
@interface AddUserViewController : XLFormViewController <XLFormRowDescriptorViewController>
@property (nonatomic, strong) NSArray<NSDictionary *> * _Nullable permissions;
@property (nonatomic, strong) UserModel *_Nullable userModel; // not used for "add", but referenced by the account section builder

- (instancetype)initWithStaffMember:(UserModel *)staffMember;

@end
