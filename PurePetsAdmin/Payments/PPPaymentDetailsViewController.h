#import <UIKit/UIKit.h>

@class PPPaymentAdminRecord;

NS_ASSUME_NONNULL_BEGIN

@interface PPPaymentDetailsViewController : UITableViewController

- (instancetype)initWithRecord:(PPPaymentAdminRecord *)record;

@end

NS_ASSUME_NONNULL_END
