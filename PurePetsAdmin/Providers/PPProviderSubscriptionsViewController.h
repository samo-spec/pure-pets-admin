#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPSSubscriptionDetailController : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, copy, nullable) void (^didClose)(void);
@property (nonatomic, strong) NSString *profileID;
@property (nonatomic, strong) NSString *actorUID;
@end

/// Embedded by the existing provider hub. Backend commands own all mutations.
@interface PPProviderSubscriptionsViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
