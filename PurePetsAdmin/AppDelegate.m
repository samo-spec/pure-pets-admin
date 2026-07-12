//
//  AppDelegate.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 20/08/2025.
//

#import "AppDelegate.h"
#import "SceneDelegate.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
 
#import "PurePetsAdmin-Swift.h"
// AppDelegate.m
#if DEBUG
#import <Foundation/Foundation.h>
#endif

static NSString * const PPAdminRemotePaymentOrderRouteKey = @"payments_order";

static UIViewController *PPAdminLegacyCompatibleLoginRootController(void)
{
    return [PPProLoginHostingController new];
}

static NSString *PPAdminRouteTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *PPAdminPaymentOrderIDFromRemoteNotification(NSDictionary *userInfo)
{
    NSDictionary *safeUserInfo = [userInfo isKindOfClass:NSDictionary.class] ? userInfo : @{};
    NSString *route = PPAdminRouteTrimmedString(safeUserInfo[@"route"]);
    NSString *orderID = PPAdminRouteTrimmedString(safeUserInfo[@"orderId"]);
    if (orderID.length == 0) orderID = PPAdminRouteTrimmedString(safeUserInfo[@"orderID"]);
    if (orderID.length == 0) return @"";
    if (route.length == 0 || [route isEqualToString:PPAdminRemotePaymentOrderRouteKey]) {
        return orderID;
    }
    return @"";
}

@interface AppDelegate ()
@property (nonatomic, assign) FIRAuthStateDidChangeListenerHandle authStateHandle;

@end

@implementation AppDelegate

extern BOOL PP_TouchDotsEnabled;

- (void)pp_storeFCMToken:(NSString *)token {
    NSString *safeToken = PPAdminRouteTrimmedString(token);
    if (safeToken.length == 0) {
        return;
    }

    self.fcmToken = safeToken;
    PPNotifications.deviceToken = safeToken;
}

- (void)pp_resolveCurrentFCMTokenWithCompletion:(void (^)(NSString * _Nullable token))completion {
    NSString *resolvedToken = PPAdminRouteTrimmedString(self.fcmToken);
    if (resolvedToken.length == 0) {
        resolvedToken = PPAdminRouteTrimmedString([FIRMessaging messaging].FCMToken);
    }
    if (resolvedToken.length > 0) {
        if (completion) completion(resolvedToken);
        return;
    }

    [[FIRMessaging messaging] tokenWithCompletion:^(NSString * _Nullable token, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *safeToken = PPAdminRouteTrimmedString(token);
            if (safeToken.length > 0) {
                [self pp_storeFCMToken:safeToken];
            } else if (error) {
                NSLog(@"[FIRMessaging] Unable to resolve current FCM token: %@", error.localizedDescription);
            }
            if (completion) completion(safeToken.length > 0 ? safeToken : nil);
        });
    }];
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // PPImageCollectionRow auto-registers via +load — no manual registration needed.

    // Configure Firebase as early as possible for Messaging/Auth consumers.
    [AppMgr configureFirebase];
    
    // In AppDelegate.m - application:didFinishLaunchingWithOptions:
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"_UIConstraintBasedLayoutLogUnsatisfiable"];
    
 
    [self setupAppAppearance];          // keep your existing method
    NSString *lang = [Language currentLanguageCode];
    [Language userSelectedLanguage:lang];

    
    [[NSUserDefaults standardUserDefaults] setObject:lang forKey:@"AppleLanguages"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSLog(@"AppleLanguages  lang %@" ,lang);
    // --- Push ---
    [application registerForRemoteNotifications];

    // Set Firebase Messaging delegate
        [FIRMessaging messaging].delegate = self;
        [self pp_registerForAdminTokenSync];
        
        // Register for remote notifications
        [self registerForRemoteNotifications];
    
    
    // ✅ Global UINavigationBar appearance so your PPNavBar integrates smoothly
      /*  UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.shadowColor = UIColor.clearColor;
        appearance.backgroundColor = UIColor.clearColor;

        [UINavigationBar appearance].standardAppearance = appearance;
        [UINavigationBar appearance].scrollEdgeAppearance = appearance;
        [UINavigationBar appearance].compactAppearance = appearance;
        [UINavigationBar appearance].tintColor = UIColor.clearColor;
  //  [UINavigationBar appearance].semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;  */
        // ✅ iOS 12 fallback (no SceneDelegate)
        if (@available(iOS 13.0, *)) {
            // handled by SceneDelegate
        } else {
            self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            UIViewController *rootVC = PPAdminLegacyCompatibleLoginRootController();
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
            self.window.rootViewController = nav;
            [self.window makeKeyAndVisible];
        }
    
    
    return YES;
}


#pragma mark - UISceneSession lifecycle (iOS 13+)

- (UISceneConfiguration *)application:(UIApplication *)application
  configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                               options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0)) {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                                 sessionRole:connectingSceneSession.role];
    config.delegateClass = [SceneDelegate class];
    return config;
}

// ===============================  NOTIFICATIONS ===========================================================//



#pragma mark - Remote Notifications Registration

- (void)registerForRemoteNotifications {
    if ([UNUserNotificationCenter class] != nil) {
        // iOS 10 or later
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                              completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Error requesting notification authorization: %@", error);
            }
        }];
    } else {
        // iOS 9 or earlier
        UIUserNotificationType allNotificationTypes = (UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge);
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:allNotificationTypes categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    }
    
    [[UIApplication sharedApplication] registerForRemoteNotifications];
}

#pragma mark - APNs Token Methods

// This method is called when APNs has assigned the device a unique token
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    // Convert device token to string
    const char *data = [deviceToken bytes];
    NSMutableString *tokenString = [NSMutableString string];
    for (NSUInteger i = 0; i < [deviceToken length]; i++) {
        [tokenString appendFormat:@"%02.2hhX", data[i]];
    }
    
    NSLog(@"[FIRMessaging] APNs Device Token: %@", tokenString);
    
    // Forward the token to Firebase Messaging
    [FIRMessaging messaging].APNSToken = deviceToken;
}

// This method is called if APNs registration fails
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"[FIRMessaging] Failed to register for remote notifications: %@", error);
}

#pragma mark - FIRMessagingDelegate Methods

// This method is called whenever FCM receives a new registration token
- (void)messaging:(FIRMessaging *)messaging didReceiveRegistrationToken:(NSString *)fcmToken {
    NSLog(@"[FIRMessaging] FCM Registration Token: %@", fcmToken);
    NSString *safeToken = PPAdminRouteTrimmedString(fcmToken);
    if (safeToken.length == 0) {
        return;
    }
    [self pp_storeFCMToken:safeToken];
    
    // Send token to your server if needed
    [self sendTokenToServer:safeToken];
    
    // Post notification that token has been updated
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FCMTokenUpdated" object:safeToken];
}

#pragma mark - Handle Token

- (void)pp_registerForAdminTokenSync {
    __weak typeof(self) weakSelf = self;
    [self pp_resolveCurrentFCMTokenWithCompletion:^(NSString * _Nullable token) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || token.length == 0) return;
        [strongSelf pp_syncAdminPushToken:token preferredUID:[FIRAuth auth].currentUser.uid];
    }];

    self.authStateHandle = [[FIRAuth auth] addAuthStateDidChangeListener:^(FIRAuth * _Nonnull auth, FIRUser * _Nullable user) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (user.uid.length == 0) {
            return;
        }
        [strongSelf pp_resolveCurrentFCMTokenWithCompletion:^(NSString * _Nullable token) {
            if (token.length == 0) {
                NSLog(@"[FIRMessaging] Admin token still unavailable after auth for %@", PPAdminRouteTrimmedString(user.uid));
                return;
            }
            [strongSelf pp_syncAdminPushToken:token preferredUID:user.uid];
        }];
    }];
}

- (void)pp_syncAdminPushToken:(NSString *)token preferredUID:(NSString *)preferredUID {
    NSString *safeToken = PPAdminRouteTrimmedString(token);
    if (safeToken.length == 0) {
        return;
    }

    if (UsrMgr.currentUser) {
        UsrMgr.currentUser.PPAdminTokenID = safeToken;
        [UsrMgr.currentUser SYNC:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"[FIRMessaging] Failed syncing cached admin token through UserModel: %@", error.localizedDescription);
            } else {
                NSLog(@"[FIRMessaging] Admin token synced through UserModel for %@", UsrMgr.currentUser.displayName ?: PPAdminRouteTrimmedString(preferredUID));
            }
        }];
        return;
    }

    NSLog(@"[FIRMessaging] Deferring admin token sync until UsrMgr.currentUser is available for %@", PPAdminRouteTrimmedString(preferredUID));
}

- (void)sendTokenToServer:(NSString *)token {
    // Implement your server communication here
    NSLog(@"[FIRMessaging] Sending token to server: %@", token);
    [self pp_storeFCMToken:token];
    [self pp_syncAdminPushToken:token preferredUID:nil];
    
    // Example: Send to your backend
    // [YourAPIManager updateDeviceToken:token completion:^(BOOL success, NSError *error) {
    //     if (success) {
    //         NSLog(@"Token successfully sent to server");
    //     } else {
    //         NSLog(@"Failed to send token to server: %@", error);
    //     }
    // }];
}

#pragma mark - Get Current Token

// Method to get current FCM token
- (NSString *)getCurrentFCMToken {
    return self.fcmToken ?: @"";
}

// Method to check if token is available
- (BOOL)isFCMTokenAvailable {
    return self.fcmToken != nil && self.fcmToken.length > 0;
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    (void)center;
    (void)notification;
    if (@available(iOS 14.0, *)) {
        completionHandler(UNNotificationPresentationOptionBanner |
                          UNNotificationPresentationOptionList |
                          UNNotificationPresentationOptionSound);
        return;
    }
    completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    (void)center;
    NSString *orderID = PPAdminPaymentOrderIDFromRemoteNotification(response.notification.request.content.userInfo);
    if (orderID.length > 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:PPAdminRouteToPaymentOrderNotification
                                                            object:nil
                                                          userInfo:@{ PPAdminRouteToPaymentOrderIDUserInfoKey: orderID }];
    }
    if (completionHandler) completionHandler();
}





// =======================================================================================================================================================================/

- (void)setupAppAppearance {
    NSLog(@"[AppDelegate] setupAppAppearance called");
    
    NSString *savedTheme = [[NSUserDefaults standardUserDefaults] stringForKey:@"themePreference"];
    NSLog(@"[AppDelegate] savedTheme = %@", savedTheme);

    if (@available(iOS 13.0, *)) {
        if ([savedTheme isEqualToString:@"dark"]) {
            NSLog(@"[AppDelegate] Applying dark theme");
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        } else {
            NSLog(@"[AppDelegate] Applying light theme");
            self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        }
    }
    
    NSLog(@"[AppDelegate] [Language languageVal] %ld",[Language languageVal]);
    //if(!Language.languageVal)
    //    [Language userSelectedLanguage:LanguageCode[1]];

}


#pragma mark - UISceneSession lifecycle



- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
