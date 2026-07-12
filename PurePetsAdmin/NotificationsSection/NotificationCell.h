//
//  NotificationCell.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationCell.h
#import <UIKit/UIKit.h>
#import "NotificationModel.h"

@interface NotificationCell : UITableViewCell
- (void)configure:(NotificationModel *)m;
+ (NSString *)reuseId;
@end