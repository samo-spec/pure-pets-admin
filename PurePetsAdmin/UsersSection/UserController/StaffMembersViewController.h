//
//  StaffMembersViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>
#import "PPS.h"

NS_ASSUME_NONNULL_BEGIN

@interface StaffMembersViewController : UIViewController <PPSDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPS *searchView;

@end

NS_ASSUME_NONNULL_END
