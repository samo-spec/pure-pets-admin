//
//  SceneDelegate.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 20/08/2025.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, AppRoot) { AppRootSplash, AppRootLogin, AppRootDashboard };

FOUNDATION_EXTERN NSString * const PPAdminRouteToPaymentOrderNotification;
FOUNDATION_EXTERN NSString * const PPAdminRouteToPaymentOrderIDUserInfoKey;

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow * window;

- (void)reloadRootViewControllerForLanguageChange;
@end

