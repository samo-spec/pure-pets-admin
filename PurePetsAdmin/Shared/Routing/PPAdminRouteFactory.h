#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPAdminRouteFactory : NSObject

+ (nullable UIViewController *)viewControllerForRouteIdentifier:(NSString *)identifier
                                                        payload:(nullable NSString *)payload
    NS_SWIFT_NAME(viewController(routeIdentifier:payload:));

@end

NS_ASSUME_NONNULL_END
