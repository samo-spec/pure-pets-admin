//
//  AppDelegate.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 20/08/2025.
//

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <FirebaseMessaging/FIRMessaging.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, FIRMessagingDelegate, UNUserNotificationCenterDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) NSString *fcmToken;

@end
