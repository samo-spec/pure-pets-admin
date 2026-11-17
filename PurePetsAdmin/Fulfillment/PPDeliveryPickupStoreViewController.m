#import "PPDeliveryPickupStoreViewController.h"
#import "PPFulfillmentService.h"
#import "Language.h"
#import "Styling.h"
#import "PurePetsAdmin-Swift.h"
@import FirebaseAuth;

@interface PPDeliveryPickupStoreViewController ()
@end

@implementation PPDeliveryPickupStoreViewController

+ (void)presentForRecord:(PPFulfillmentRecord *)record from:(UIViewController *)presenter
             completion:(void (^)(NSString * _Nullable, BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Pickup store presentation must run on the main thread.");
    [PPDeliveryPickupStoreLauncher presentForRecord:record from:presenter completion:completion];
}

@end
