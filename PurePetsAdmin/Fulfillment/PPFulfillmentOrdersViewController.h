#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPFulfillmentRecord;

@interface PPFulfillmentOrdersViewController : UITableViewController
@end

@interface PPFulfillmentDetailViewController : UITableViewController
- (instancetype)initWithRecord:(PPFulfillmentRecord *)record;
@end

NS_ASSUME_NONNULL_END