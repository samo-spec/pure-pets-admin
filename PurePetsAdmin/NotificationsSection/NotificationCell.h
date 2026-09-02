//
//  NotificationCell.h
//  PurePetsAdmin
//
//  Category-defining administrative notification card cell.
//

#import <UIKit/UIKit.h>
#import "NotificationModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface NotificationCell : UITableViewCell

@property (nonatomic, copy, nullable) void(^onDirectActionTapped)(NotificationModel *model);

- (void)configure:(NotificationModel *)m;
+ (NSString *)reuseId;

@end

NS_ASSUME_NONNULL_END