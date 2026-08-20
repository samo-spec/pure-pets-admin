#import "SceneDelegate.h"
#import "AppDelegate.h"
#import <GoogleSignIn/GoogleSignIn.h>
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "Payments/PPPaymentDetailsViewController.h"
#import "Payments/PPPaymentManagementService.h"
#import "Payments/PPPaymentManagementViewController.h"
#import "ThirdParty/PPStyles/PPHUD.h"
#import "ThirdParty/PPStyles/UIViewController+PPNavBar.h"
#import "ThirdParty/Styling/AlertHelper.h"
#import "PPStaffAuth.h"
#import "AdminDashboardViewController.h"
#import "HomeControl/PPHomeControlPanelViewController.h"
#import "NotificationsSection/NotificationsListViewController.h"
#import "ThirdParty/PPCells/PPChatsViewController.h"
#import "ThirdParty/PPCells/PPSettingsViewController.h"
#import "PurePetsAdmin-Swift.h"
@import Firebase;
@import FirebaseAuth;
extern NSString * const UserManagerAuthStateDidChangeNotification;

/// Login-in-progress flag — prevents SceneDelegate from re-routing while the
/// login controller's multi-step sign-in pipeline is active.
static BOOL _pp_adminLoginInProgress = NO;

BOOL PPAdminLoginInProgress(void) { return _pp_adminLoginInProgress; }
void PPAdminSetLoginInProgress(BOOL inProgress) { _pp_adminLoginInProgress = inProgress; }

NSString * const PPAdminRouteToPaymentOrderNotification = @"PPAdminRouteToPaymentOrderNotification";
NSString * const PPAdminRouteToPaymentOrderIDUserInfoKey = @"orderId";

static NSString * const PPAdminPaymentOrderRouteKey = @"payments_order";

static UIViewController *PPAdminCreateLoginRootController(void)
{
     return [PPProLoginHostingController new];
}

static NSString *PPAdminNotificationTrimmedString(id value)
{
     if (![value isKindOfClass:NSString.class]) return @"";
     return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *PPAdminNotificationOrderIDFromUserInfo(NSDictionary *userInfo)
{
     NSDictionary *safeUserInfo = [userInfo isKindOfClass:NSDictionary.class] ? userInfo : @{};
     NSDictionary *meta = [safeUserInfo[@"meta"] isKindOfClass:NSDictionary.class] ? safeUserInfo[@"meta"] : @{};
     NSString *route = PPAdminNotificationTrimmedString(safeUserInfo[@"route"]);
     if (route.length == 0) {
          route = PPAdminNotificationTrimmedString(meta[@"route"]);
     }

     NSString *orderID = PPAdminNotificationTrimmedString(safeUserInfo[@"orderId"]);
     if (orderID.length == 0) orderID = PPAdminNotificationTrimmedString(safeUserInfo[@"orderID"]);
     if (orderID.length == 0) orderID = PPAdminNotificationTrimmedString(meta[@"orderId"]);
     if (orderID.length == 0) orderID = PPAdminNotificationTrimmedString(meta[@"orderID"]);
     if (orderID.length == 0) return @"";

     if (route.length == 0 || [route isEqualToString:PPAdminPaymentOrderRouteKey]) {
          return orderID;
     }
     return @"";
}

@interface SceneDelegate ()
@property (nonatomic) AppRoot currentRoot;
@property (nonatomic) FIRAuthStateDidChangeListenerHandle authHandle;
@property (nonatomic) BOOL awaitingModel;
@property (nonatomic) BOOL pp_requiresForegroundUnlock;
@property (nonatomic) BOOL pp_isUnlockPromptRunning;
@property (nonatomic) BOOL pp_didAutoPromptForCurrentLockCycle;
@property (nonatomic) BOOL pp_requiresManualUnlockRetry;
@property (nonatomic) CFTimeInterval pp_lastUnlockPromptAt;
@property (nonatomic, strong, nullable) UIView *ppLockOverlay;
@property (nonatomic, strong, nullable) UIButton *ppUnlockButton;
@property (nonatomic) BOOL pp_skipNextDidBecomeActiveAutoPrompt;
@property (nonatomic, copy, nullable) NSString *pp_pendingPaymentOrderID;
@property (nonatomic) BOOL pp_isRoutingPaymentOrder;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
     
     
     [self setRoot:AppRootSplash animated:NO];
     static dispatch_once_t onceToken;
     dispatch_once(&onceToken, ^{
          // AppManager installs App Check provider factory before Firebase configure.
          [AppMgr configureFirebase];
     });
     
     // --- Core config ---
    

     // --- UI / Appearance ---
     [Styling setupFormAppearance];      // ✅ move from SceneDelegate
     
     if (![scene isKindOfClass:[UIWindowScene class]]) return;

     
    /*
     // Always start with splash
     //[self setRoot:AppRootSplash animated:NO];
     UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
     [appearance configureWithTransparentBackground];
     appearance.shadowColor = UIColor.clearColor;
     appearance.backgroundColor = UIColor.clearColor;
     
     [UINavigationBar appearance].standardAppearance = appearance;
     [UINavigationBar appearance].scrollEdgeAppearance = appearance;
     [UINavigationBar appearance].compactAppearance = appearance;
     [UINavigationBar appearance].tintColor = UIColor.clearColor;

     */
     
     UIWindowScene *windowScene = (UIWindowScene *)scene;
     if (!self.window) {
          self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
     }

#if !PP_ADMIN_LEGACY_ROOT
     // The Command Center owns the authenticated root in every normal build.
     // The legacy root remains an explicit compile-time rollback seam only.
     {
          AdminAppRootHostingController *adminRoot = [AdminAppRootHostingController new];
          self.window.rootViewController = adminRoot;
          [self.window makeKeyAndVisible];
          [[NSNotificationCenter defaultCenter] addObserver:self
                                                   selector:@selector(pp_handlePaymentOrderRouteNotification:)
                                                       name:PPAdminRouteToPaymentOrderNotification
                                                     object:nil];
          NSDictionary *coldStartPayload = connectionOptions.notificationResponse.notification.request.content.userInfo;
          NSString *pendingOrderID = [AppDelegate pp_isNotificationPayloadRoutable:coldStartPayload]
               ? PPAdminNotificationOrderIDFromUserInfo(coldStartPayload)
               : @"";
          if (pendingOrderID.length > 0) {
               [adminRoot routeToPaymentOrderID:pendingOrderID];
           }
           return;
     }
#else

      __weak typeof(self) weakSelf = self;
     [[FUManager shared] startAuthListenerWithChangeBlock:^(FIRUser * _Nullable authUser,
                                                            UserModel * _Nullable userModel) {
          (void)userModel;
          dispatch_async(dispatch_get_main_queue(), ^{
               [weakSelf pp_applyAdminRoutingForAuthUser:authUser animated:YES];
          });
     }];
     
     
     
     [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAuthChange)
                                                  name:UserManagerAuthStateDidChangeNotification
                                                object:nil];
     
     [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAuthChange)
                                                  name:LanguageDidChangeNotification
                                                object:nil];
     [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(pp_handlePaymentOrderRouteNotification:)
                                                  name:PPAdminRouteToPaymentOrderNotification
                                                object:nil];
     self.pp_requiresForegroundUnlock = NO;
     self.pp_didAutoPromptForCurrentLockCycle = NO;
     self.pp_requiresManualUnlockRetry = NO;
     self.pp_skipNextDidBecomeActiveAutoPrompt = NO;
     self.pp_lastUnlockPromptAt = 0;
     NSDictionary *coldStartPayload = connectionOptions.notificationResponse.notification.request.content.userInfo;
     NSString *pendingOrderID = [AppDelegate pp_isNotificationPayloadRoutable:coldStartPayload]
          ? PPAdminNotificationOrderIDFromUserInfo(coldStartPayload)
          : @"";
     if (pendingOrderID.length > 0) {
          self.pp_pendingPaymentOrderID = pendingOrderID;
      }
      [self handleAuthChange]; // set initial root
#endif
     
     
     
     
     //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadRootViewControllerForLanguageChange) name:LanguageDidChangeNotification object:nil];
}

- (void)pp_startFlowForAuthUser:(FIRUser * _Nullable)authUser userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {
     (void)userModel;
     [self pp_applyAdminRoutingForAuthUser:authUser animated:animated];
}

- (void)pp_applyAdminRoutingForAuthUser:(FIRUser * _Nullable)authUser animated:(BOOL)animated {
     // ── Guard: don't interfere while the login controller's pipeline is active ──
     if (PPAdminLoginInProgress()) {
          NSLog(@"[SceneDelegate] ⏸ skipping routing — login in progress");
          return;
     }

     if (!authUser) {
          self.pp_requiresForegroundUnlock = NO;
          self.pp_didAutoPromptForCurrentLockCycle = NO;
          self.pp_requiresManualUnlockRetry = NO;
          [self pp_hideLockOverlay];
          [self setRoot:AppRootLogin animated:animated];
          return;
     }

     __weak typeof(self) weakSelf = self;
     [AppMgr checkIfAdmin:^(BOOL isAdmin) {
          dispatch_async(dispatch_get_main_queue(), ^{
               if (!weakSelf) {
                    return;
               }
               // Re-check: login controller may have started between the async gap
               if (PPAdminLoginInProgress()) {
                    NSLog(@"[SceneDelegate] ⏸ skipping post-admin-check routing — login in progress");
                    return;
               }
               if (!isAdmin) {
                    weakSelf.pp_requiresForegroundUnlock = NO;
                    weakSelf.pp_didAutoPromptForCurrentLockCycle = NO;
                    weakSelf.pp_requiresManualUnlockRetry = NO;
                    [weakSelf pp_hideLockOverlay];
                    [UsrMgr signOut];
                    [weakSelf setRoot:AppRootLogin animated:animated];
                    return;
               }

               [weakSelf startFlowForAuthUser:authUser userModel:nil animated:animated];
               if (weakSelf.pp_requiresForegroundUnlock) {
                    [weakSelf pp_showLockOverlayIfNeeded];
               }
          });
     }];
 }

- (UITabBarController *)pp_buildDashboardTabBarController {
     UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightMedium];

     AdminDashboardViewController *dashVC = [[AdminDashboardViewController alloc] init];
     UINavigationController *dashNav = [[UINavigationController alloc] initWithRootViewController:dashVC];
     [dashNav pp_applyPurePetsNavAppearance];
     dashNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:kLang(@"AdminDashboard") ?: @"Dashboard"
                                                       image:[UIImage systemImageNamed:@"square.grid.2x2" withConfiguration:iconConfig]
                                               selectedImage:[UIImage systemImageNamed:@"square.grid.2x2.fill" withConfiguration:iconConfig]];

     PPChatsViewController *chatsVC = [[PPChatsViewController alloc] init];
     UINavigationController *chatsNav = [[UINavigationController alloc] initWithRootViewController:chatsVC];
     [chatsNav pp_applyPurePetsNavAppearance];
     chatsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:kLang(@"Chats") ?: @"Chats"
                                                       image:[UIImage systemImageNamed:@"bubble.left.and.bubble.right" withConfiguration:iconConfig]
                                               selectedImage:[UIImage systemImageNamed:@"bubble.left.and.bubble.right.fill" withConfiguration:iconConfig]];

     NotificationsListViewController *notifVC = [[NotificationsListViewController alloc] init];
     UINavigationController *notifNav = [[UINavigationController alloc] initWithRootViewController:notifVC];
     [notifNav pp_applyPurePetsNavAppearance];
     notifNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:kLang(@"Notifications") ?: @"Notifications"
                                                       image:[UIImage systemImageNamed:@"bell" withConfiguration:iconConfig]
                                               selectedImage:[UIImage systemImageNamed:@"bell.fill" withConfiguration:iconConfig]];

     PPSettingsViewController *settingsVC = [[PPSettingsViewController alloc] init];
     UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
     [settingsNav pp_applyPurePetsNavAppearance];
     settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:kLang(@"Settings") ?: @"Settings"
                                                       image:[UIImage systemImageNamed:@"gearshape" withConfiguration:iconConfig]
                                               selectedImage:[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:iconConfig]];

     UITabBarController *tabBarController = [[UITabBarController alloc] init];
     tabBarController.viewControllers = @[dashNav, chatsNav, notifNav, settingsNav];
     
     UIColor *tintColor = AppPrimaryClr;
     UIColor *unselectedColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.72];

     NSDictionary *normalAttrs = @{
          NSFontAttributeName: [Styling fontMedium:10.0],
          NSForegroundColorAttributeName: unselectedColor
     };
     NSDictionary *selectedAttrs = @{
          NSFontAttributeName: [Styling fontMedium:10.0],
          NSForegroundColorAttributeName: tintColor
     };

     if (@available(iOS 15.0, *)) {
          UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
          [appearance configureWithDefaultBackground];
          appearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
          
          appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs;
          appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs;
          appearance.inlineLayoutAppearance.normal.titleTextAttributes = normalAttrs;
          appearance.inlineLayoutAppearance.selected.titleTextAttributes = selectedAttrs;
          appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = normalAttrs;
          appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = selectedAttrs;
          
          tabBarController.tabBar.standardAppearance = appearance;
          tabBarController.tabBar.scrollEdgeAppearance = appearance;
     } else {
          [[UITabBarItem appearance] setTitleTextAttributes:normalAttrs forState:UIControlStateNormal];
          [[UITabBarItem appearance] setTitleTextAttributes:selectedAttrs forState:UIControlStateSelected];
     }
     
     tabBarController.tabBar.tintColor = tintColor;
     tabBarController.tabBar.unselectedItemTintColor = unselectedColor;
     
     return tabBarController;
}

- (void)pp_setRoot:(AppRoot)target userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {
     if (target == self.currentRoot && self.window.rootViewController) return;
     self.currentRoot = target;
     
     if (target == AppRootDashboard) {
          UITabBarController *tabBarController = [self pp_buildDashboardTabBarController];
          self.window.rootViewController = tabBarController;
          [self.window makeKeyAndVisible];
          return;
     }
     
     UIViewController *root;
     switch (target) {
          case AppRootSplash:    root = [SplashViewController new]; break;
          case AppRootLogin:     root = PPAdminCreateLoginRootController(); break;
          default:               root = [SplashViewController new]; break;
     }
     
     UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
     [nav pp_applyPurePetsNavAppearance];
     self.window.rootViewController = nav;
     [self.window makeKeyAndVisible];
}

- (void)pp_setRootDashboardWithUser:(UserModel *)model animated:(BOOL)animated {
     UITabBarController *tabBarController = [self pp_buildDashboardTabBarController];
     
     UIViewController *old = self.window.rootViewController;
     self.window.rootViewController = tabBarController;
     if (animated && old) {
          [old.presentedViewController dismissViewControllerAnimated:NO completion:nil];
          [UIView transitionWithView:self.window duration:0.25
                             options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionAllowAnimatedContent
                          animations:nil completion:nil];
     }
     [self pp_tryHandlePendingPaymentOrderRouteAnimated:NO];
}

#pragma mark - Flow

- (void)startFlowForAuthUser:(FIRUser * _Nullable)user userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {
     if (!user) {
          self.awaitingModel = NO;
          [self setRoot:AppRootLogin animated:animated];
          return;
     }
     
     // We’re signed in → fetch the UserModel first
     self.awaitingModel = YES;
     [self setRoot:AppRootSplash animated:animated]; // keep splash while loading
     
     __weak typeof(self) weakSelf = self;
     [UserManager.shared loadUserByUIDOrID:user.uid completion:^(UserModel * _Nullable user, NSError * _Nullable error) {
          
          weakSelf.awaitingModel = NO;
          
          UserModel *effectiveUser = user;
          if (!effectiveUser) {
               FIRUser *au = [FIRAuth auth].currentUser;
               if (au) {
                    effectiveUser = [[FUManager shared] userModelFromAuth:au doc:nil];
               }
          }
          if (effectiveUser) {
               UserManager.shared.currentUser = effectiveUser;
               [weakSelf setRoot:AppRootDashboard animated:YES];
               [weakSelf pp_tryHandlePendingPaymentOrderRouteAnimated:NO];
          } else {
               [weakSelf setRoot:AppRootLogin animated:YES];
          }
     }];
}

#pragma mark - Root switching

- (void)setRoot:(AppRoot)target animated:(BOOL)animated {
     if (target == self.currentRoot && self.window.rootViewController) return;
     self.currentRoot = target;
     
     UIViewController *rootController;
     if (target == AppRootDashboard) {
          rootController = [self pp_buildDashboardTabBarController];
     } else {
          UIViewController *root;
          switch (target) {
               case AppRootSplash:    root = [SplashViewController new]; break;
               case AppRootLogin:     root = PPAdminCreateLoginRootController(); break;
               default:               root = [SplashViewController new]; break;
          }
          rootController = [[UINavigationController alloc] initWithRootViewController:root];
          [rootController pp_applyPurePetsNavAppearance];
     }
     
     UIViewController *old = self.window.rootViewController;
     self.window.rootViewController = rootController;
     
     if (animated && old) {
          [old.presentedViewController dismissViewControllerAnimated:NO completion:nil];
          [UIView transitionWithView:self.window
                            duration:0.25
                             options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionAllowAnimatedContent
                          animations:nil
                          completion:nil];
     }
     if (target == AppRootDashboard) {
          [self pp_tryHandlePendingPaymentOrderRouteAnimated:NO];
     }
}

#pragma mark - Language rebuild

- (void)rebuildForLanguage {
     // Apply semantic direction + nav appearance, then rebuild current target.
     //UISemanticContentAttribute attr = [Language semanticAttributeForCurrentLanguage];
     //[UIView appearance].semanticContentAttribute = attr;
     //[UINavigationBar appearance].semanticContentAttribute = attr;
     //self.window.semanticContentAttribute = attr;
     [self pp_applyNavigationAppearance];
     
     // If we are waiting on model, keep splash; else rebuild the same target
     AppRoot target = self.awaitingModel ? AppRootSplash : self.currentRoot;
     [self setRoot:target animated:YES];
}

- (void)pp_applyNavigationAppearance { /* your existing nav appearance */ }

#pragma mark - Language

- (void)reloadRootViewControllerForLanguageChange {
     if ([self.window.rootViewController isKindOfClass:AdminAppRootHostingController.class]) {
          [(AdminAppRootHostingController *)self.window.rootViewController refreshForLanguageChange];
          return;
     }
     //UISemanticContentAttribute attr = [Language semanticAttributeForCurrentLanguage];
     //[UIView appearance].semanticContentAttribute = attr;
     //[UINavigationBar appearance].semanticContentAttribute = attr;
     //self.window.semanticContentAttribute = attr;
     
     // [self pp_applyNavigationAppearance];
     [self updateRootForUser:[FIRAuth auth].currentUser animated:YES];
}


- (void)handleAuthStateChange {
     [self pp_applyAdminRoutingForAuthUser:[FIRAuth auth].currentUser animated:YES];
}


- (void)pp_clearAllYYCacheNamed:(NSString *)name {
     YYCache *cache = [YYCache cacheWithName:name];
     [cache removeAllObjectsWithBlock:^{
          dispatch_async(dispatch_get_main_queue(), ^{
               [PPToast toast:kLang(@"Cache cleared") style:PPToastStyleSuccess haptic:YES duration:2.0];
          });
     }];
}



- (void)handleAuthChange {
     [self pp_applyAdminRoutingForAuthUser:[FIRAuth auth].currentUser animated:YES];
     
}

#pragma mark - Notification Routing

- (void)pp_handlePaymentOrderRouteNotification:(NSNotification *)notification
{
     NSString *orderID = PPAdminNotificationTrimmedString(notification.userInfo[PPAdminRouteToPaymentOrderIDUserInfoKey]);
     if (orderID.length == 0) return;
     if ([self.window.rootViewController isKindOfClass:AdminAppRootHostingController.class]) {
          [(AdminAppRootHostingController *)self.window.rootViewController routeToPaymentOrderID:orderID];
          return;
     }
     self.pp_pendingPaymentOrderID = orderID;
     [self pp_tryHandlePendingPaymentOrderRouteAnimated:YES];
}

- (void)pp_tryHandlePendingPaymentOrderRouteAnimated:(BOOL)animated
{
     NSString *orderID = PPAdminNotificationTrimmedString(self.pp_pendingPaymentOrderID);
     if (orderID.length == 0 || self.pp_isRoutingPaymentOrder) return;
     if (self.currentRoot != AppRootDashboard) return;

     UINavigationController *nav = [self.window.rootViewController isKindOfClass:UINavigationController.class]
          ? (UINavigationController *)self.window.rootViewController
          : nil;
     if (!nav) return;

     UIViewController *host = nav.topViewController ?: nav;
     self.pp_isRoutingPaymentOrder = YES;
     [PPHUD showIndeterminateIn:host.view
                          title:kLang(@"Loading")
                       subtitle:kLang(@"PaymentMgmt_Loading_PaymentDetails")];

     __weak typeof(self) weakSelf = self;
     [[PPPaymentManagementService shared] loadFullRecordForOrderID:orderID completion:^(PPPaymentAdminRecord * _Nullable record, NSError * _Nullable error) {
          __strong typeof(weakSelf) self = weakSelf;
          [PPHUD dismiss];
          self.pp_isRoutingPaymentOrder = NO;

          UIViewController *alertHost = nav.topViewController ?: nav;
          if (!record || error) {
               self.pp_pendingPaymentOrderID = nil;
               [AlertHelper showErrorIn:alertHost
                                  title:kLang(@"Error")
                               subtitle:error.localizedDescription ?: kLang(@"PaymentMgmt_Error_OrderNotFound")];
               return;
          }

          self.pp_pendingPaymentOrderID = nil;
          PPPaymentManagementViewController *paymentsVC = [PPPaymentManagementViewController new];
          PPPaymentDetailsViewController *detailsVC = [[PPPaymentDetailsViewController alloc] initWithRecord:record];

          UIViewController *root = nav.viewControllers.firstObject;
          NSMutableArray<UIViewController *> *stack = [NSMutableArray array];
          if (root &&
              ![root isKindOfClass:PPPaymentManagementViewController.class] &&
              ![root isKindOfClass:PPPaymentDetailsViewController.class]) {
               [stack addObject:root];
          }
          [stack addObject:paymentsVC];
          [stack addObject:detailsVC];

          void (^applyRoute)(void) = ^{
               [nav setViewControllers:stack animated:animated];
          };

          if (nav.presentedViewController) {
               [nav dismissViewControllerAnimated:NO completion:applyRoute];
          } else {
               applyRoute();
          }
     }];
}

#pragma mark - Public: called by [Language userSelectedLanguage:]
- (void)sceneDidBecomeActive:(UIScene *)scene {
     (void)scene;
     self.pp_requiresForegroundUnlock = NO;
     self.pp_didAutoPromptForCurrentLockCycle = NO;
     self.pp_requiresManualUnlockRetry = NO;
     self.pp_skipNextDidBecomeActiveAutoPrompt = NO;
     self.pp_isUnlockPromptRunning = NO;
     [self pp_hideLockOverlay];
}

- (void)sceneWillResignActive:(UIScene *)scene {
     (void)scene;
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
     (void)scene;
}

#pragma mark - Root swapping

- (void)updateRootForUser:(FIRUser *_Nullable)user animated:(BOOL)animated {
     [self pp_applyAdminRoutingForAuthUser:user animated:animated];
}

#pragma mark - Foreground Lock

- (UIViewController *)pp_topViewController {
     UIViewController *top = self.window.rootViewController;
     while (top.presentedViewController) {
          top = top.presentedViewController;
     }
     return top;
}

- (BOOL)pp_shouldProtectCurrentSession {
     return NO;
}

- (void)pp_showLockOverlayIfNeeded {
     [self pp_hideLockOverlay];
}

- (void)pp_hideLockOverlay {
     [self.ppLockOverlay removeFromSuperview];
     self.ppLockOverlay = nil;
     self.ppUnlockButton = nil;
}

- (void)pp_unlockButtonTapped {
     [self pp_hideLockOverlay];
}

- (void)pp_promptForegroundUnlockIfNeededForced:(BOOL)forced {
     (void)forced;
     self.pp_requiresForegroundUnlock = NO;
     self.pp_didAutoPromptForCurrentLockCycle = NO;
     self.pp_requiresManualUnlockRetry = NO;
     self.pp_skipNextDidBecomeActiveAutoPrompt = NO;
     self.pp_isUnlockPromptRunning = NO;
     [self pp_hideLockOverlay];
}

- (void)pp_armForegroundLockIfNeeded {
     self.pp_requiresForegroundUnlock = NO;
     self.pp_didAutoPromptForCurrentLockCycle = NO;
     self.pp_requiresManualUnlockRetry = NO;
     self.pp_skipNextDidBecomeActiveAutoPrompt = NO;
     self.pp_isUnlockPromptRunning = NO;
     [self pp_hideLockOverlay];
}

- (void)dealloc
{
     [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    UIOpenURLContext *context = URLContexts.anyObject;
    if (context) {
        [GIDSignIn.sharedInstance handleURL:context.URL];
    }
}

@end



/*
 
 
 @import FirebaseAuth;
 @import FirebaseFirestore;
 
 
 
 @interface SceneDelegate ()
 @property (nonatomic) AppRoot currentRoot;
 @property (nonatomic) FIRAuthStateDidChangeListenerHandle authHandle;
 @property (nonatomic) BOOL awaitingModel;
 @end
 
 @implementation SceneDelegate
 
 - (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
 if (![scene isKindOfClass:[UIWindowScene class]]) return;
 UIWindowScene *ws = (UIWindowScene *)scene;
 self.window = [[UIWindow alloc] initWithWindowScene:ws];
 self.window.frame = ws.coordinateSpace.bounds;
 
 // 1) Always start on Splash
 [self pp_setRoot:AppRootSplash userModel:nil animated:NO];
 
 // 2) Attach auth listener
 __weak typeof(self) weakSelf = self;
 self.authHandle = [[FIRAuth auth] addAuthStateDidChangeListener:^(FIRAuth *auth, FIRUser * _Nullable user) {
 FIRUser * _Nullable userAuth = user;
 [UsrMgr fetchAdminWithUID:user.uid cachePolicy:PPUserCachePolicyServerOnly completion:^(UserModel * _Nullable user, NSError * _Nullable error) {
 [weakSelf pp_startFlowForAuthUser:userAuth userModel:user animated:YES];
 
 // 3) Kick initial evaluation
 [self pp_startFlowForAuthUser:[FIRAuth auth].currentUser userModel:user animated:NO];
 
 [self.window makeKeyAndVisible];
 
 
 }];
 
 }];
 
 
 
 [[NSNotificationCenter defaultCenter] addObserver:self
 selector:@selector(reloadRootViewControllerForLanguageChange)
 name:LanguageDidChangeNotification
 object:nil];
 }
 
 - (void)pp_startFlowForAuthUser:(FIRUser * _Nullable)authUser userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {
 if (!authUser) { return; }
 
 // keep Splash while fetching model
 [self pp_setRoot:AppRootSplash userModel:userModel animated:animated];
 
 __weak typeof(self) weakSelf = self;
 [UserManager.shared loadUserByUIDOrID:authUser.uid completion:^(UserModel * _Nullable user, NSError * _Nullable error) {
 
 if (user) {
 [weakSelf pp_setRootDashboardWithUser:user animated:YES];
 } else {
 [weakSelf pp_setRoot:AppRootLogin userModel:user animated:YES];
 }
 }];
 }
 
 - (void)pp_setRoot:(AppRoot)target userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {
 static AppRoot current = -1;
 if (target == current && self.window.rootViewController) return;
 current = target;
 
 UIViewController *root = nil;
 switch (target) {
 case AppRootSplash:    root = [SplashViewController new]; break;
 case AppRootLogin:     root = PPAdminCreateLoginRootController(); break;
 case AppRootDashboard: root = [UIViewController new]; break;
 }
 UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
 
 UIViewController *old = self.window.rootViewController;
 self.window.rootViewController = nav;
 if (animated && old) {
 [old.presentedViewController dismissViewControllerAnimated:NO completion:nil];
 [UIView transitionWithView:self.window duration:0.45
 options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionAllowAnimatedContent
 animations:nil completion:nil];
 }
 }
 
 - (void)pp_setRootDashboardWithUser:(UserModel *)model animated:(BOOL)animated {
 AdminDashboardViewController *dash = [[AdminDashboardViewController alloc] init];
 UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:dash];
 
 UIViewController *old = self.window.rootViewController;
 self.window.rootViewController = nav;
 if (animated && old) {
 [old.presentedViewController dismissViewControllerAnimated:NO completion:nil];
 [UIView transitionWithView:self.window duration:0.25
 options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionAllowAnimatedContent
 animations:nil completion:nil];
 }
 }
 
 
 #pragma mark - Flow
 
 - (void)startFlowForAuthUser:(FIRUser * _Nullable)user userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {
 if (!user) {
 self.awaitingModel = NO;
 [self setRoot:AppRootLogin animated:animated];
 return;
 }
 
 // We’re signed in → fetch the UserModel first
 self.awaitingModel = YES;
 [self setRoot:AppRootSplash animated:animated]; // keep splash while loading
 
 __weak typeof(self) weakSelf = self;
 [UserManager.shared loadUserByUIDOrID:user.uid completion:^(UserModel * _Nullable user, NSError * _Nullable error) {
 
 weakSelf.awaitingModel = NO;
 
 if (user) {
 // Optional: set currentUser if you haven’t already inside the fetch
 UserManager.shared.currentUser = user;
 [weakSelf setRoot:AppRootDashboard animated:YES];
 } else {
 // If user doc missing or error, send to Login
 [weakSelf setRoot:AppRootLogin animated:YES];
 }
 }];
 }
 
 #pragma mark - Root switching
 
 - (void)setRoot:(AppRoot)target animated:(BOOL)animated {
 if (target == self.currentRoot && self.window.rootViewController) return;
 self.currentRoot = target;
 
 UIViewController *root;
 switch (target) {
 case AppRootSplash:    root = [SplashViewController new]; break;
 case AppRootLogin:     root = PPAdminCreateLoginRootController(); break;
 case AppRootDashboard: root = [[AdminDashboardViewController alloc]init]; break;
 default:               root = [SplashViewController new]; break;
 }
 UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
 
 UIViewController *old = self.window.rootViewController;
 self.window.rootViewController = nav;
 
 if (animated && old) {
 [old.presentedViewController dismissViewControllerAnimated:NO completion:nil];
 [UIView transitionWithView:self.window
 duration:0.25
 options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionAllowAnimatedContent
 animations:nil
 completion:nil];
 }
 }
 
 #pragma mark - Language rebuild
 
 - (void)rebuildForLanguage {
 // Apply semantic direction + nav appearance, then rebuild current target.
 UISemanticContentAttribute attr = [Language semanticAttributeForCurrentLanguage];
 [UIView appearance].semanticContentAttribute = attr;
 [UINavigationBar appearance].semanticContentAttribute = attr;
 self.window.semanticContentAttribute = attr;
 [self pp_applyNavigationAppearance];
 
 // If we are waiting on model, keep splash; else rebuild the same target
 AppRoot target = self.awaitingModel ? AppRootSplash : self.currentRoot;
 [self setRoot:target animated:YES];
 }
 
 - (void)pp_applyNavigationAppearance {  }
 
 #pragma mark - Language
 
 - (void)reloadRootViewControllerForLanguageChange {
 UISemanticContentAttribute attr = [Language semanticAttributeForCurrentLanguage];
 [UIView appearance].semanticContentAttribute = attr;
 [UINavigationBar appearance].semanticContentAttribute = attr;
 self.window.semanticContentAttribute = attr;
 
 [self pp_applyNavigationAppearance];
 [self updateRootForUser:[FIRAuth auth].currentUser animated:YES];
 }
 
 
 - (void)handleAuthStateChange {
 BOOL loggedIn = ([FIRAuth auth].currentUser != nil);
 AppRoot desired = loggedIn ? AppRootDashboard : AppRootLogin;
 if (desired == self.currentRoot) return; // already on right root
 
 if(loggedIn)
 {
 self.currentRoot = AppRootDashboard;
 
 AdminDashboardViewController *dash = [[AdminDashboardViewController alloc] init];
 UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:dash];
 self.window.rootViewController = nav;
 [self.window makeKeyAndVisible];
 
 }
 else
 {
 self.currentRoot = AppRootDashboard;
 UIViewController *rootVC = PPAdminCreateLoginRootController();
 UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
 self.window.rootViewController = nav;
 [self.window makeKeyAndVisible];
 
 }
 
 }
 
 
 - (void)pp_clearAllYYCacheNamed:(NSString *)name {
 YYCache *cache = [YYCache cacheWithName:name];
 [cache removeAllObjectsWithBlock:^{
 dispatch_async(dispatch_get_main_queue(), ^{
 [PPToast toast:kLang(@"Cache cleared") style:PPToastStyleSuccess haptic:YES duration:2.0];
 });
 }];
 }
 
 
 
 - (void)handleAuthChange {
 BOOL loggedIn = ([FIRAuth auth].currentUser != nil);
 if(loggedIn)
 {
 UIViewController *root =[[AdminDashboardViewController alloc] init];
 self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:root];
 [self.window makeKeyAndVisible];
 }
 else
 {
 UIViewController *root = PPAdminCreateLoginRootController();
 self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:root];
 [self.window makeKeyAndVisible];
 }
 }
 
 #pragma mark - Public: called by [Language userSelectedLanguage:]
 - (void)sceneDidBecomeActive:(UIScene *)scene {
 
 }
 
 
 
 
 - (void)sceneWillResignActive:(UIScene *)scene {
 // Called when the scene will move from an active state to an inactive state.
 // This may occur due to temporary interruptions (ex. an incoming phone call).
 }
 
 
 - (void)sceneWillEnterForeground:(UIScene *)scene {
 // Called as the scene transitions from the background to the foreground.
 // Use this method to undo the changes made on entering the background.
 }
 
 
 - (void)sceneDidEnterBackground:(UIScene *)scene {
 [[AppLockManager shared] didEnterBackground];
 }
 
 #pragma mark - Root swapping
 
 - (void)updateRootForUser:(FIRUser *_Nullable)user animated:(BOOL)animated {
 BOOL loggedIn = (user != nil);
 
 //if (desired == self.currentRoot) return; // already on right root
 
 if(loggedIn)
 {
 self.currentRoot = AppRootDashboard;
 
 AdminDashboardViewController *dash = [[AdminDashboardViewController alloc] init];
 UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:dash];
 self.window.rootViewController = nav;
 [self.window makeKeyAndVisible];
 
 }
 else
 {
 self.currentRoot = AppRootDashboard;
 UIViewController *rootVC = PPAdminCreateLoginRootController();
 UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
 self.window.rootViewController = nav;
 [self.window makeKeyAndVisible];
 
 }
 }
 
 
 
 @end
 
 
 */
