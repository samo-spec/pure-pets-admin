#import <UIKit/UIKit.h>
@class PPFulfillmentRecord;

NS_ASSUME_NONNULL_BEGIN

/// One native decision surface shared by Fulfillment and Order Management.
/// The service supplies scoped choices; the transition callable revalidates them.
@interface PPDeliveryPickupStoreViewController : UIViewController
+ (void)presentForRecord:(PPFulfillmentRecord *)record
                   from:(nullable UIViewController *)presenter
             completion:(void(^)(NSString * _Nullable branchID, BOOL confirmed))completion
    NS_SWIFT_NAME(present(for:from:completion:));
@end

NS_ASSUME_NONNULL_END
