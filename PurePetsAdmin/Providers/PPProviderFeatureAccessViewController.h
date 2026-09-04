#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPProviderFeatureAccessViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

NS_ASSUME_NONNULL_END
