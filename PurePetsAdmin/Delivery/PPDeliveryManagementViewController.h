#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PPDeliveryGlobalNavigationStateDidChangeBlock)(void);

@interface PPDeliveryManagementViewController : UITableViewController

/// The host owns global-navigation rendering. Delivery invokes this narrow
/// callback whenever its refresh affordance changes enabled or loading state.
@property (nonatomic, copy, nullable) PPDeliveryGlobalNavigationStateDidChangeBlock globalNavigationStateDidChange;

@end


NS_ASSUME_NONNULL_END