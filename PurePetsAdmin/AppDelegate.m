//
//  AppDelegate.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 20/08/2025.
//

#import "AppDelegate.h"
#import "SceneDelegate.h"
#import <sys/utsname.h>
#import "FirebaseInstallations/FIRInstallations.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseFunctions;
@import FirebaseMessaging;
@import FirebaseAuth;
 
#import "PurePetsAdmin-Swift.h"
// AppDelegate.m
#if DEBUG
#import <Foundation/Foundation.h>
#endif

static NSString * const PPAdminRemotePaymentOrderRouteKey = @"payments_order";
static NSString * const PPAdminNotificationV2AppID = @"admin_ios";
static NSString * const PPAdminNotificationV2BindingDefaultsKey = @"PPNotificationV2AdminBindingV1";

static UIViewController *PPAdminLegacyCompatibleLoginRootController(void)
{
    return [PPProLoginHostingController new];
}

static NSString *PPAdminRouteTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *PPAdminNotificationEnvironment(void)
{
    NSString *configuredEnvironment = [PPAdminRouteTrimmedString(
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"PPNotificationsEnvironment"]
    ) lowercaseString];
    if ([configuredEnvironment isEqualToString:@"sandbox"] ||
        [configuredEnvironment isEqualToString:@"production"]) {
        return configuredEnvironment;
    }

    // Admin is connected to the production Firebase project in every build
    // configuration. Notifications V2 uses this as a logical event-routing
    // environment, so a Debug build must not become invisible to production
    // staff events merely because its APNs entitlement is development.
    return @"production";
}

static NSString *PPAdminCurrentDeviceModel(void)
{
    struct utsname systemInfo;
    if (uname(&systemInfo) != 0) {
        return PPAdminRouteTrimmedString(UIDevice.currentDevice.model);
    }
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"";
}

static BOOL PPAdminPayloadTargetsOtherApp(NSDictionary *payload)
{
    NSDictionary *safePayload = [payload isKindOfClass:NSDictionary.class] ? payload : @{};
    NSString *targetApp = [PPAdminRouteTrimmedString(safePayload[@"targetApp"] ?: safePayload[@"targetAppId"] ?: safePayload[@"appId"]) lowercaseString];
    return targetApp.length > 0 && ![targetApp isEqualToString:@"admin_ios"];
}

static BOOL PPAdminPayloadHasSupportedSchema(NSDictionary *payload)
{
    NSDictionary *safePayload = [payload isKindOfClass:NSDictionary.class] ? payload : @{};
    NSDictionary *meta = [safePayload[@"meta"] isKindOfClass:NSDictionary.class] ? safePayload[@"meta"] : @{};
    id rawSchema = safePayload[@"schemaVersion"] ?: meta[@"schemaVersion"];
    if (!rawSchema) return YES;

    NSString *schema = @"";
    if ([rawSchema isKindOfClass:NSString.class]) {
        schema = [PPAdminRouteTrimmedString(rawSchema) lowercaseString];
    } else if ([rawSchema isKindOfClass:NSNumber.class]) {
        schema = [[(NSNumber *)rawSchema stringValue] lowercaseString];
    }
    if (schema.length == 0) return NO;

    static NSSet<NSString *> *supportedSchemas;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supportedSchemas = [NSSet setWithArray:@[@"1", @"2", @"order.lifecycle.v1", @"order.fulfillment.v1"]];
    });
    return [supportedSchemas containsObject:schema];
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
@property (nonatomic, copy) NSString *apnsTokenHexString;
@property (nonatomic, assign) BOOL notificationV2RegistrationInFlight;
@property (nonatomic, assign) BOOL notificationV2RegistrationNeedsForegroundRetry;
@property (nonatomic, copy) NSString *notificationV2PendingReason;
@property (nonatomic, assign) BOOL notificationV2LogoutBarrierActive;
@property (nonatomic, assign) NSUInteger notificationV2LifecycleEpoch;
@property (nonatomic, strong) NSMutableArray *notificationV2LogoutBarrierWaiters;

- (void)pp_attemptAdminNotificationV2RegistrationForReason:(NSString *)reason;
- (void)pp_finishAdminNotificationV2RegistrationCycle;
- (void)pp_releaseNotificationV2LogoutBarrierWaiters;
- (BOOL)pp_hasCurrentAdminNotificationV2BindingForUID:(NSString *)uid;
- (void)pp_handleAdminApplicationDidBecomeActive:(NSNotification *)notification;
- (BOOL)pp_adminNotificationV2RegistrationIsCurrentForUID:(NSString *)uid epoch:(NSUInteger)epoch;
- (void)pp_compensateStaleAdminNotificationV2Registration:(NSDictionary *)response
                                                       uid:(NSString *)uid
                                            installationId:(NSString *)installationId
                                                environment:(NSString *)environment
                                                 completion:(dispatch_block_t)completion;
@end

@implementation AppDelegate

+ (BOOL)pp_isNotificationPayloadRoutable:(NSDictionary *)payload
{
    return PPAdminPayloadHasSupportedSchema(payload) && !PPAdminPayloadTargetsOtherApp(payload);
}

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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pp_handleAdminApplicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        
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
    
    self.apnsTokenHexString = [tokenString copy];
    NSLog(@"PPLAB NotificationsV2 admin APNS update | hasToken=%@",
          self.apnsTokenHexString.length > 0 ? @"yes" : @"no");
    
    // Forward the token to Firebase Messaging
    [FIRMessaging messaging].APNSToken = deviceToken;
    [self pp_attemptAdminNotificationV2RegistrationForReason:@"apns_registration"];
}

// This method is called if APNs registration fails
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"[FIRMessaging] Failed to register for remote notifications: %@", error);
}

#pragma mark - FIRMessagingDelegate Methods

// This method is called whenever FCM receives a new registration token
- (void)messaging:(FIRMessaging *)messaging didReceiveRegistrationToken:(NSString *)fcmToken {
    (void)messaging;
    NSLog(@"PPLAB NotificationsV2 admin FCM update | hasToken=%@", fcmToken.length > 0 ? @"yes" : @"no");
    NSString *safeToken = PPAdminRouteTrimmedString(fcmToken);
    if (safeToken.length == 0) {
        return;
    }
    [self pp_storeFCMToken:safeToken];
    
    // Send token to your server if needed
    [self sendTokenToServer:safeToken];
    [self pp_attemptAdminNotificationV2RegistrationForReason:@"fcm_refresh"];
    
    // Post notification that token has been updated
    [[NSNotificationCenter defaultCenter] postNotificationName:@"FCMTokenUpdated" object:safeToken];
}

#pragma mark - Handle Token

- (void)pp_registerForAdminTokenSync {
    __weak typeof(self) weakSelf = self;
    [self pp_resolveCurrentFCMTokenWithCompletion:^(NSString * _Nullable token) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || token.length == 0) return;
        NSString *currentUID = PPAdminRouteTrimmedString([FIRAuth auth].currentUser.uid);
        [strongSelf pp_syncAdminPushToken:token preferredUID:currentUID];
        [strongSelf pp_attemptAdminNotificationV2RegistrationForReason:@"launch_sync"];
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
            [strongSelf pp_attemptAdminNotificationV2RegistrationForReason:@"auth_change"];
        }];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pp_adminSessionDidBecomeAvailable:)
                                                 name:UserManagerAuthStateDidChangeNotification
                                               object:nil];
}

- (void)pp_adminSessionDidBecomeAvailable:(NSNotification *)notification
{
    (void)notification;
    [self pp_attemptAdminNotificationV2RegistrationForReason:@"staff_session_ready"];
}

- (BOOL)pp_hasCurrentAdminNotificationV2BindingForUID:(NSString *)uid
{
    NSString *safeUID = PPAdminRouteTrimmedString(uid);
    NSDictionary *binding = [NSUserDefaults.standardUserDefaults dictionaryForKey:PPAdminNotificationV2BindingDefaultsKey];
    if (![binding isKindOfClass:NSDictionary.class] || safeUID.length == 0) {
        return NO;
    }

    NSString *bindingUID = PPAdminRouteTrimmedString(binding[@"uid"]);
    NSString *installationId = PPAdminRouteTrimmedString(binding[@"installationId"]);
    NSString *appId = PPAdminRouteTrimmedString(binding[@"appId"]);
    NSString *environment = PPAdminRouteTrimmedString(binding[@"environment"]);
    NSString *bindingGeneration = PPAdminRouteTrimmedString(binding[@"bindingGeneration"]);
    NSString *fcmTokenHash = PPAdminRouteTrimmedString(binding[@"fcmTokenHash"]);
    return [bindingUID isEqualToString:safeUID] &&
        [appId isEqualToString:PPAdminNotificationV2AppID] &&
        [environment isEqualToString:PPAdminNotificationEnvironment()] &&
        installationId.length > 0 && bindingGeneration.length > 0 && fcmTokenHash.length > 0;
}

- (void)pp_handleAdminApplicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_handleAdminApplicationDidBecomeActive:nil];
        });
        return;
    }
    if (self.notificationV2LogoutBarrierActive) {
        return;
    }

    NSString *uid = PPAdminRouteTrimmedString([FIRAuth auth].currentUser.uid);
    if (uid.length == 0) {
        return;
    }
    if (!self.notificationV2RegistrationNeedsForegroundRetry &&
        [self pp_hasCurrentAdminNotificationV2BindingForUID:uid]) {
        return;
    }

    [self pp_attemptAdminNotificationV2RegistrationForReason:@"foreground_retry"];
}

- (void)pp_syncAdminPushToken:(NSString *)token preferredUID:(NSString *)preferredUID {
    NSString *safeToken = PPAdminRouteTrimmedString(token);
    NSString *uid = PPAdminRouteTrimmedString(preferredUID);
    NSString *authUID = PPAdminRouteTrimmedString([FIRAuth auth].currentUser.uid);
    NSString *modelUID = PPAdminRouteTrimmedString(UsrMgr.currentUser.uid.length > 0 ? UsrMgr.currentUser.uid : UsrMgr.currentUser.ID);
    if (safeToken.length == 0 || uid.length == 0 ||
        ![authUID isEqualToString:uid] || ![modelUID isEqualToString:uid]) {
        NSLog(@"PPLAB NotificationsV2 admin legacy sync skipped | canonical_session=no");
        return;
    }

    if (UsrMgr.currentUser && [UsrMgr.currentUser.uid isEqualToString:uid]) {
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
    NSLog(@"PPLAB NotificationsV2 admin legacy sync start | hasToken=%@", token.length > 0 ? @"yes" : @"no");
    [self pp_storeFCMToken:token];
    [self pp_syncAdminPushToken:token preferredUID:[FIRAuth auth].currentUser.uid];
    
    // Example: Send to your backend
    // [YourAPIManager updateDeviceToken:token completion:^(BOOL success, NSError *error) {
    //     if (success) {
    //         NSLog(@"Token successfully sent to server");
    //     } else {
    //         NSLog(@"Failed to send token to server: %@", error);
    //     }
    // }];
}

- (void)pp_beginNotificationV2LogoutBarrierWithCompletion:(dispatch_block_t)completion
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_beginNotificationV2LogoutBarrierWithCompletion:completion];
        });
        return;
    }

    if (!self.notificationV2LogoutBarrierActive) {
        self.notificationV2LogoutBarrierActive = YES;
        self.notificationV2LifecycleEpoch += 1;
        self.notificationV2PendingReason = nil;
        NSLog(@"PPLAB NotificationsV2 admin logout barrier raised | appId=%@ epoch=%lu inFlight=%@",
              PPAdminNotificationV2AppID,
              (unsigned long)self.notificationV2LifecycleEpoch,
              self.notificationV2RegistrationInFlight ? @"yes" : @"no");

    }

    if (completion) {
        if (!self.notificationV2LogoutBarrierWaiters) {
            self.notificationV2LogoutBarrierWaiters = [NSMutableArray array];
        }
        [self.notificationV2LogoutBarrierWaiters addObject:[completion copy]];
    }

    NSUInteger barrierEpoch = self.notificationV2LifecycleEpoch;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.notificationV2LogoutBarrierActive ||
            strongSelf.notificationV2LifecycleEpoch != barrierEpoch ||
            strongSelf.notificationV2LogoutBarrierWaiters.count == 0) {
            return;
        }
        NSLog(@"PPLAB NotificationsV2 admin logout barrier timeout | appId=%@ epoch=%lu inFlight=%@ continuing=yes",
              PPAdminNotificationV2AppID,
              (unsigned long)barrierEpoch,
              strongSelf.notificationV2RegistrationInFlight ? @"yes" : @"no");
        [strongSelf pp_releaseNotificationV2LogoutBarrierWaiters];
    });

    if (!self.notificationV2RegistrationInFlight) {
        [self pp_releaseNotificationV2LogoutBarrierWaiters];
    }
}

- (void)pp_releaseNotificationV2LogoutBarrierWaiters
{
    NSArray *waiters = [self.notificationV2LogoutBarrierWaiters copy] ?: @[];
    [self.notificationV2LogoutBarrierWaiters removeAllObjects];
    for (id waiterObject in waiters) {
        dispatch_block_t waiter = (dispatch_block_t)waiterObject;
        waiter();
    }
}

- (void)pp_endNotificationV2LogoutBarrier
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_endNotificationV2LogoutBarrier];
        });
        return;
    }

    self.notificationV2LogoutBarrierActive = NO;
    self.notificationV2PendingReason = nil;
    [self.notificationV2LogoutBarrierWaiters removeAllObjects];
    NSLog(@"PPLAB NotificationsV2 admin logout barrier lowered | appId=%@ epoch=%lu",
          PPAdminNotificationV2AppID,
          (unsigned long)self.notificationV2LifecycleEpoch);
}

- (void)pp_abortNotificationV2LogoutBarrierAndRefreshForReason:(NSString *)reason
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_abortNotificationV2LogoutBarrierAndRefreshForReason:reason];
        });
        return;
    }

    [self pp_endNotificationV2LogoutBarrier];
    NSString *safeReason = PPAdminRouteTrimmedString(reason);
    [self pp_attemptAdminNotificationV2RegistrationForReason:safeReason.length > 0 ? safeReason : @"logout_aborted"];
}

- (BOOL)pp_adminNotificationV2RegistrationIsCurrentForUID:(NSString *)uid epoch:(NSUInteger)epoch
{
    NSString *activeUID = PPAdminRouteTrimmedString([FIRAuth auth].currentUser.uid);
    NSString *activeModelUID = PPAdminRouteTrimmedString(UsrMgr.currentUser.uid.length > 0 ? UsrMgr.currentUser.uid : UsrMgr.currentUser.ID);
    NSString *safeUID = PPAdminRouteTrimmedString(uid);
    return !self.notificationV2LogoutBarrierActive &&
        epoch == self.notificationV2LifecycleEpoch &&
        [activeUID isEqualToString:safeUID] &&
        [activeModelUID isEqualToString:safeUID];
}

- (void)pp_compensateStaleAdminNotificationV2Registration:(NSDictionary *)response
                                                       uid:(NSString *)uid
                                            installationId:(NSString *)installationId
                                                environment:(NSString *)environment
                                                 completion:(dispatch_block_t)completion
{
    dispatch_block_t finish = completion ?: ^{};
    BOOL ok = [response[@"ok"] respondsToSelector:@selector(boolValue)] && [response[@"ok"] boolValue];
    NSString *bindingGeneration = PPAdminRouteTrimmedString(response[@"bindingGeneration"]);
    NSString *fcmTokenHash = PPAdminRouteTrimmedString(response[@"fcmTokenHash"]);
    NSString *activeUID = PPAdminRouteTrimmedString([FIRAuth auth].currentUser.uid);
    if (!ok || ![activeUID isEqualToString:PPAdminRouteTrimmedString(uid)] ||
        PPAdminRouteTrimmedString(installationId).length == 0 ||
        bindingGeneration.length == 0 || fcmTokenHash.length == 0) {
        NSLog(@"PPLAB NotificationsV2 admin stale registration discarded | appId=%@ compensated=no hasAuth=%@ hasBinding=%@",
              PPAdminNotificationV2AppID,
              [activeUID isEqualToString:PPAdminRouteTrimmedString(uid)] ? @"yes" : @"no",
              bindingGeneration.length > 0 && fcmTokenHash.length > 0 ? @"yes" : @"no");
        finish();
        return;
    }

    NSDictionary *payload = @{
        @"installationId": PPAdminRouteTrimmedString(installationId),
        @"reason": @"logout",
        @"appId": PPAdminNotificationV2AppID,
        @"environment": PPAdminRouteTrimmedString(environment).length > 0 ? PPAdminRouteTrimmedString(environment) : PPAdminNotificationEnvironment(),
        @"bindingGeneration": bindingGeneration,
        @"expectedFcmTokenHash": fcmTokenHash
    };
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"deactivateNotificationDeviceV2"];
    callable.timeoutInterval = 10.0;
    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *deactivateResponse = [result.data isKindOfClass:NSDictionary.class] ? result.data : @{};
            BOOL deactivateOK = [deactivateResponse[@"ok"] respondsToSelector:@selector(boolValue)] && [deactivateResponse[@"ok"] boolValue];
            NSLog(@"PPLAB NotificationsV2 admin stale registration compensated | appId=%@ ok=%@ error=%@",
                  PPAdminNotificationV2AppID,
                  deactivateOK ? @"yes" : @"no",
                  error.localizedDescription ?: @"none");
            finish();
        });
    }];
}

- (void)pp_attemptAdminNotificationV2RegistrationForReason:(NSString *)reason
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_attemptAdminNotificationV2RegistrationForReason:reason];
        });
        return;
    }

    NSString *safeReason = PPAdminRouteTrimmedString(reason);
    if (self.notificationV2LogoutBarrierActive) {
        NSLog(@"PPLAB NotificationsV2 admin registration blocked | reason=%@ appId=%@ logoutBarrier=yes epoch=%lu",
              safeReason.length > 0 ? safeReason : @"unknown",
              PPAdminNotificationV2AppID,
              (unsigned long)self.notificationV2LifecycleEpoch);
        return;
    }

    NSString *uid = PPAdminRouteTrimmedString([FIRAuth auth].currentUser.uid);
    NSString *modelUID = PPAdminRouteTrimmedString(UsrMgr.currentUser.uid.length > 0 ? UsrMgr.currentUser.uid : UsrMgr.currentUser.ID);
    if (uid.length == 0 || ![modelUID isEqualToString:uid]) {
        NSLog(@"PPLAB NotificationsV2 admin registration skipped | reason=%@ canonical_session=no appId=%@",
              safeReason.length > 0 ? safeReason : @"unknown",
              PPAdminNotificationV2AppID);
        return;
    }

    if (self.notificationV2RegistrationInFlight) {
        self.notificationV2PendingReason = safeReason.length > 0 ? safeReason : @"coalesced";
        NSLog(@"PPLAB NotificationsV2 admin registration coalesced | reason=%@ appId=%@",
              self.notificationV2PendingReason,
              PPAdminNotificationV2AppID);
        return;
    }
    NSUInteger registrationEpoch = self.notificationV2LifecycleEpoch;
    self.notificationV2RegistrationInFlight = YES;

    __weak typeof(self) weakSelf = self;
    [AppMgr checkIfAdmin:^(BOOL isAdmin) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (!isAdmin || ![strongSelf pp_adminNotificationV2RegistrationIsCurrentForUID:uid epoch:registrationEpoch]) {
                NSLog(@"PPLAB NotificationsV2 admin registration skipped | reason=%@ authorized_staff=no appId=%@",
                      safeReason.length > 0 ? safeReason : @"unknown",
                      PPAdminNotificationV2AppID);
                [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                return;
            }

            PPStaffDoc *staffSession = [PPStaffAuth shared].cachedCurrentStaff;
            BOOL hasNotificationsView = [staffSession hasPermission:kStaffPermNotificationsView];
            if (!hasNotificationsView) {
                NSLog(@"PPLAB NotificationsV2 admin registration skipped | reason=%@ scope_permissions=no appId=%@",
                      safeReason.length > 0 ? safeReason : @"unknown",
                      PPAdminNotificationV2AppID);
                [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                return;
            }

            [strongSelf pp_resolveCurrentFCMTokenWithCompletion:^(NSString * _Nullable token) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;

                NSString *safeToken = PPAdminRouteTrimmedString(token);
                BOOL registrationIsCurrent = [strongSelf pp_adminNotificationV2RegistrationIsCurrentForUID:uid epoch:registrationEpoch];
                if (!registrationIsCurrent || safeToken.length == 0) {
                    NSLog(@"PPLAB NotificationsV2 admin registration skipped | reason=%@ auth_changed_or_stale=%@ hasFCM=%@ appId=%@",
                          safeReason.length > 0 ? safeReason : @"unknown",
                          registrationIsCurrent ? @"no" : @"yes",
                          safeToken.length > 0 ? @"yes" : @"no",
                          PPAdminNotificationV2AppID);
                    [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                    return;
                }

                [PPFIRInstallation installationIDWithCompletion:^(NSString * _Nullable installationId, NSError * _Nullable installationError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) return;

                        NSString *safeInstallationId = PPAdminRouteTrimmedString(installationId);
                        BOOL registrationIsCurrent = [strongSelf pp_adminNotificationV2RegistrationIsCurrentForUID:uid epoch:registrationEpoch];
                        if (!registrationIsCurrent || safeInstallationId.length == 0) {
                            NSLog(@"PPLAB NotificationsV2 admin registration skipped | reason=%@ auth_changed_or_stale=%@ hasInstallation=%@ appId=%@ error=%@",
                                  safeReason.length > 0 ? safeReason : @"unknown",
                                  registrationIsCurrent ? @"no" : @"yes",
                                  safeInstallationId.length > 0 ? @"yes" : @"no",
                                  PPAdminNotificationV2AppID,
                                  installationError.localizedDescription ?: @"none");
                            [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                            return;
                        }

                        NSMutableArray<NSString *> *notificationScopes = [NSMutableArray array];
                        BOOL hasPayments = [staffSession hasPermission:kStaffPermPaymentsView] ||
                            [staffSession hasPermission:kStaffPermPaymentsManage] ||
                            [staffSession hasPermission:kStaffPermPaymentsRefund];
                        BOOL hasSupport = [staffSession hasPermission:kStaffPermSupportView] ||
                            [staffSession hasPermission:kStaffPermSupportManage];
                        BOOL hasModeration = [staffSession hasPermission:kStaffPermModerationView] ||
                            [staffSession hasPermission:kStaffPermModerationManage];
                        if (hasPayments) {
                            [notificationScopes addObjectsFromArray:@[@"staff.orders", @"staff.payments", @"staff.delivery"]];
                        }
                        if (hasSupport) [notificationScopes addObject:@"staff.support"];
                        if (hasModeration) [notificationScopes addObject:@"staff.moderation"];
                        if ([staffSession hasPermission:kStaffPermNotificationsSend]) [notificationScopes addObject:@"staff.manual"];
                        if (notificationScopes.count == 0) {
                            NSLog(@"PPLAB NotificationsV2 admin registration skipped | reason=scope_permissions_no_v2_scope appId=%@", PPAdminNotificationV2AppID);
                            [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                            return;
                        }
                        NSMutableDictionary *payload = [@{
                            @"installationId": safeInstallationId,
                            @"platform": @"ios",
                            @"appId": @"admin_ios",
                            @"bundleId": PPAdminRouteTrimmedString(NSBundle.mainBundle.bundleIdentifier),
                            @"environment": PPAdminNotificationEnvironment(),
                            @"fcmToken": safeToken,
                            @"notificationScopes": notificationScopes,
                            @"providerIds": @[],
                            @"capabilities": @{
                                @"customer": @NO,
                                @"provider": @NO,
                                @"staff": @YES
                            },
                            @"locale": PPAdminRouteTrimmedString([Language currentLanguageCode]),
                            @"timezone": PPAdminRouteTrimmedString(NSTimeZone.localTimeZone.name),
                            @"appVersion": PPAdminRouteTrimmedString(AppMgr.appVersion),
                            @"osVersion": PPAdminRouteTrimmedString(UIDevice.currentDevice.systemVersion),
                            @"deviceModel": PPAdminCurrentDeviceModel()
                        } mutableCopy];
                        NSString *apnsTokenHash = PPAdminRouteTrimmedString(strongSelf.apnsTokenHexString);
                        if (apnsTokenHash.length > 0) payload[@"apnsTokenHash"] = apnsTokenHash;

                        FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"registerNotificationDeviceV2"];
                        callable.timeoutInterval = 30.0;
                        NSLog(@"PPLAB NotificationsV2 admin registration start | reason=%@ appId=%@ scopes=%lu",
                              safeReason.length > 0 ? safeReason : @"unknown",
                              PPAdminNotificationV2AppID,
                              (unsigned long)notificationScopes.count);

                        [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                __strong typeof(weakSelf) strongSelf = weakSelf;
                                if (!strongSelf) return;

                                if (error) {
                                    strongSelf.notificationV2RegistrationNeedsForegroundRetry = YES;
                                    NSLog(@"PPLAB NotificationsV2 admin registration failed | reason=%@ appId=%@ error=%@",
                                          safeReason.length > 0 ? safeReason : @"unknown",
                                          PPAdminNotificationV2AppID,
                                          error.localizedDescription ?: @"unknown");
                                    [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                                    return;
                                }

                                NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : @{};
                                if (![strongSelf pp_adminNotificationV2RegistrationIsCurrentForUID:uid epoch:registrationEpoch]) {
                                    NSLog(@"PPLAB NotificationsV2 admin registration ignored | reason=%@ appId=%@ auth_changed_or_stale=yes",
                                          safeReason.length > 0 ? safeReason : @"unknown",
                                          PPAdminNotificationV2AppID);
                                    [strongSelf pp_compensateStaleAdminNotificationV2Registration:response
                                                                                          uid:uid
                                                                               installationId:safeInstallationId
                                                                                   environment:PPAdminNotificationEnvironment()
                                                                                    completion:^{
                                        [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                                    }];
                                    return;
                                }

                                BOOL ok = [response[@"ok"] respondsToSelector:@selector(boolValue)] && [response[@"ok"] boolValue];
                                NSString *bindingGeneration = PPAdminRouteTrimmedString(response[@"bindingGeneration"]);
                                NSString *fcmTokenHash = PPAdminRouteTrimmedString(response[@"fcmTokenHash"]);
                                NSString *environment = PPAdminRouteTrimmedString(response[@"environment"]);
                                if (environment.length == 0) environment = PPAdminNotificationEnvironment();
                                BOOL storedCurrentBinding = NO;
                                if (ok && bindingGeneration.length > 0 && fcmTokenHash.length > 0) {
                                    NSDictionary *binding = @{
                                        @"uid": uid,
                                        @"installationId": safeInstallationId,
                                        @"appId": PPAdminNotificationV2AppID,
                                        @"environment": environment,
                                        @"bindingGeneration": bindingGeneration,
                                        @"fcmTokenHash": fcmTokenHash
                                    };
                                    [NSUserDefaults.standardUserDefaults setObject:binding forKey:PPAdminNotificationV2BindingDefaultsKey];
                                    storedCurrentBinding = YES;
                                }
                                strongSelf.notificationV2RegistrationNeedsForegroundRetry = !storedCurrentBinding;
                                NSLog(@"PPLAB NotificationsV2 admin registration finish | reason=%@ appId=%@ ok=%@ hasBinding=%@",
                                      safeReason.length > 0 ? safeReason : @"unknown",
                                      PPAdminNotificationV2AppID,
                                      ok ? @"yes" : @"no",
                                      bindingGeneration.length > 0 && fcmTokenHash.length > 0 ? @"yes" : @"no");
                                [strongSelf pp_finishAdminNotificationV2RegistrationCycle];
                            });
                        }];
                    });
                }];
            }];
        });
    }];
}

- (void)pp_finishAdminNotificationV2RegistrationCycle
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_finishAdminNotificationV2RegistrationCycle];
        });
        return;
    }

    self.notificationV2RegistrationInFlight = NO;
    if (self.notificationV2LogoutBarrierActive) {
        self.notificationV2PendingReason = nil;
        [self pp_releaseNotificationV2LogoutBarrierWaiters];
        return;
    }

    NSString *pendingReason = PPAdminRouteTrimmedString(self.notificationV2PendingReason);
    self.notificationV2PendingReason = nil;
    if (pendingReason.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pp_attemptAdminNotificationV2RegistrationForReason:pendingReason];
        });
    }
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
    NSDictionary *payload = notification.request.content.userInfo;
    if (![AppDelegate pp_isNotificationPayloadRoutable:payload]) {
        NSLog(@"PPLAB NotificationsV2 admin receive suppressed | targetApp_mismatch=yes appId=%@", PPAdminNotificationV2AppID);
        completionHandler(UNNotificationPresentationOptionNone);
        return;
    }
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
    NSDictionary *payload = response.notification.request.content.userInfo;
    if (![AppDelegate pp_isNotificationPayloadRoutable:payload]) {
        NSLog(@"PPLAB NotificationsV2 admin tap ignored | targetApp_mismatch=yes appId=%@", PPAdminNotificationV2AppID);
        if (completionHandler) completionHandler();
        return;
    }
    NSString *orderID = PPAdminPaymentOrderIDFromRemoteNotification(payload);
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
