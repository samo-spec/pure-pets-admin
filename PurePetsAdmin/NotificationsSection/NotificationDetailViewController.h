//
//  NotificationDetailViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationDetailViewController.h
#import <UIKit/UIKit.h>
#import "NotificationModel.h"

@interface NotificationDetailViewController : UIViewController
- (instancetype)initWithModel:(NotificationModel *)model userID:(NSString *)uid;
@end