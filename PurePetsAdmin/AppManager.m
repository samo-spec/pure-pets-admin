//
//  AppManager.m
//  PurePetsAdmin
//






#import "AppManager.h"
@import FirebaseCore;
@import FirebaseAppCheck;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import GoogleSignIn;
#import "PPStaffAuth.h"
#import "PPRolePermission.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@interface PPStaffAuth (PPAppManagerCacheAccess)
@property (nonatomic, strong, nullable, readwrite) PPStaffDoc *cachedCurrentStaff;
@end
#import <TargetConditionals.h>

static BOOL PPAppCheckTruthyString(NSString *value) {
    NSString *trimmed = [value isKindOfClass:NSString.class]
        ? [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString]
        : @"";
    if (trimmed.length == 0) {
        return NO;
    }
    return [@[@"1", @"true", @"yes", @"y", @"on"] containsObject:trimmed];
}

static NSString *PPAdminSafeClaimString(id value)
{
    if ([value isKindOfClass:NSString.class]) {
        return [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            lowercaseString];
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *valueString = [(NSString *)[value stringValue] ?: @"" copy];
        return [[valueString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    }
    return @"";
}

static BOOL PPAdminSafeClaimBoolValue(id value)
{
    if ([value isKindOfClass:NSNumber.class] ||
        [value isKindOfClass:NSString.class] ||
        [value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return NO;
}

static BOOL PPShouldUseDebugAppCheckProvider(void) {
#if TARGET_OS_SIMULATOR || DEBUG
    return YES;
#else
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSDictionary<NSString *, NSString *> *env = processInfo.environment ?: @{};
    NSString *forceEnv = env[@"PP_FORCE_APPCHECK_DEBUG_PROVIDER"];
    NSString *debugTokenEnv = env[@"FIRAAppCheckDebugToken"];
    BOOL forceFromEnv = PPAppCheckTruthyString(forceEnv);
    BOOL hasDebugTokenEnv = [debugTokenEnv isKindOfClass:NSString.class] && debugTokenEnv.length > 0;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id forceDefaultsValue = [defaults objectForKey:@"PPForceAppCheckDebugProvider"];
    BOOL forceDefaultsEnabled = NO;
    if ([forceDefaultsValue isKindOfClass:NSNumber.class]) {
        forceDefaultsEnabled = [(NSNumber *)forceDefaultsValue boolValue];
    } else if ([forceDefaultsValue isKindOfClass:NSString.class]) {
        forceDefaultsEnabled = PPAppCheckTruthyString((NSString *)forceDefaultsValue);
    }
    return forceFromEnv || hasDebugTokenEnv || forceDefaultsEnabled;
#endif
}

static BOOL PPShouldUseAppAttestAppCheckProvider(void) {
#if TARGET_OS_SIMULATOR
    return NO;
#else
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSDictionary<NSString *, NSString *> *env = processInfo.environment ?: @{};
    NSString *forceEnv = env[@"PP_FORCE_APPCHECK_APPACTEST_PROVIDER"];
    BOOL forceFromEnv = PPAppCheckTruthyString(forceEnv);

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id forceDefaultsValue = [defaults objectForKey:@"PPForceAppCheckAppAttestProvider"];
    BOOL forceDefaultsEnabled = NO;
    if ([forceDefaultsValue isKindOfClass:NSNumber.class]) {
        forceDefaultsEnabled = [(NSNumber *)forceDefaultsValue boolValue];
    } else if ([forceDefaultsValue isKindOfClass:NSString.class]) {
        forceDefaultsEnabled = PPAppCheckTruthyString((NSString *)forceDefaultsValue);
    }

    return forceFromEnv || forceDefaultsEnabled;
#endif
}

static void PPFetchAppCheckTokenFromProvider(id<FIRAppCheckProvider> provider,
                                             BOOL limitedUse,
                                             void (^handler)(FIRAppCheckToken * _Nullable, NSError * _Nullable)) {
    if (!provider) {
        if (handler) {
            handler(nil, [NSError errorWithDomain:@"PPAppCheckError" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Missing provider"}]);
        }
        return;
    }
    if (limitedUse && [provider respondsToSelector:@selector(getLimitedUseTokenWithCompletion:)]) {
        [provider getLimitedUseTokenWithCompletion:handler];
    } else {
        [provider getTokenWithCompletion:handler];
    }
}

static BOOL PPAppCheckErrorLooksLikeAppAttestFailure(NSError *error) {
    if (!error) return NO;
    NSString *domain = error.domain ?: @"";
    if ([domain containsString:@"AppCheck"] || [domain containsString:@"AppAttest"]) {
        return YES;
    }
    return NO;
}

@interface PPResilientAppCheckProvider : NSObject <FIRAppCheckProvider>
- (instancetype)initWithAppAttestProvider:(id<FIRAppCheckProvider>)appAttestProvider
                      deviceCheckProvider:(id<FIRAppCheckProvider>)deviceCheckProvider;
@end

@interface PPResilientAppCheckProvider ()
@property (nonatomic, strong, nullable) id<FIRAppCheckProvider> appAttestProvider;
@property (nonatomic, strong, nullable) id<FIRAppCheckProvider> deviceCheckProvider;
@property (atomic, assign) BOOL usingDeviceCheckFallback;
@end

@implementation PPResilientAppCheckProvider

- (instancetype)initWithAppAttestProvider:(id<FIRAppCheckProvider>)appAttestProvider
                      deviceCheckProvider:(id<FIRAppCheckProvider>)deviceCheckProvider {
    self = [super init];
    if (self) {
        _appAttestProvider = appAttestProvider;
        _deviceCheckProvider = deviceCheckProvider;
        _usingDeviceCheckFallback = NO;
    }
    return self;
}

- (void)getTokenWithCompletion:(void (^)(FIRAppCheckToken * _Nullable, NSError * _Nullable))handler {
    [self pp_getTokenLimitedUse:NO completion:handler];
}

- (void)getLimitedUseTokenWithCompletion:(void (^)(FIRAppCheckToken * _Nullable, NSError * _Nullable))handler {
    [self pp_getTokenLimitedUse:YES completion:handler];
}

- (void)pp_getTokenLimitedUse:(BOOL)limitedUse completion:(void (^)(FIRAppCheckToken * _Nullable, NSError * _Nullable))handler {
    id<FIRAppCheckProvider> deviceCheckProvider = self.deviceCheckProvider;
    if (self.usingDeviceCheckFallback || !self.appAttestProvider) {
        PPFetchAppCheckTokenFromProvider(deviceCheckProvider, limitedUse, handler);
        return;
    }

    __weak typeof(self) weakSelf = self;
    PPFetchAppCheckTokenFromProvider(self.appAttestProvider, limitedUse, ^(FIRAppCheckToken * _Nullable token, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            if (handler) {
                handler(token, error);
            }
            return;
        }

        if (!error || !PPAppCheckErrorLooksLikeAppAttestFailure(error)) {
            if (handler) {
                handler(token, error);
            }
            return;
        }

        self.usingDeviceCheckFallback = YES;
        NSLog(@"[AppCheck] App Attest failed for Pure Pets Admin. Falling back to DeviceCheck for this launch. Error: %@",
              error.localizedDescription ?: @"unknown error");
        PPFetchAppCheckTokenFromProvider(deviceCheckProvider, limitedUse, ^(FIRAppCheckToken * _Nullable fallbackToken, NSError * _Nullable fallbackError) {
            if (fallbackToken || !fallbackError) {
                if (handler) {
                    handler(fallbackToken, nil);
                }
                return;
            }

            if (handler) {
                handler(nil, fallbackError ?: error);
            }
        });
    });
}

@end

@interface PPAppCheckProviderFactory : NSObject <FIRAppCheckProviderFactory>
@end

@implementation PPAppCheckProviderFactory

- (id<FIRAppCheckProvider>)createProviderWithApp:(FIRApp *)app {
    if (PPShouldUseDebugAppCheckProvider()) {
        NSLog(@"[AppCheck] Using Debug provider for PurePetsAdmin.");
        return [[FIRAppCheckDebugProvider alloc] initWithApp:app];
    }

    if (PPShouldUseAppAttestAppCheckProvider() && @available(iOS 14.0, *)) {
        NSLog(@"[AppCheck] AppAttest provider forced via PP_FORCE_APPCHECK_APPACTEST_PROVIDER or PPForceAppCheckAppAttestProvider.");
        id<FIRAppCheckProvider> attestProvider = [[FIRAppAttestProvider alloc] initWithApp:app];
        if (attestProvider) {
            return attestProvider;
        }
        NSLog(@"[AppCheck] AppAttest provider forced but unavailable. Falling back to DeviceCheck for PurePetsAdmin.");
    }
    
    // Best practice fallback sequence for iOS:
    if (@available(iOS 14.0, *)) {
        id<FIRAppCheckProvider> attestProvider = [[FIRAppAttestProvider alloc] initWithApp:app];
        if (attestProvider) {
            id<FIRAppCheckProvider> deviceCheckProvider = [[FIRDeviceCheckProvider alloc] initWithApp:app];
            if (deviceCheckProvider) {
                NSLog(@"[AppCheck] Using App Attest provider with DeviceCheck fallback.");
                return [[PPResilientAppCheckProvider alloc] initWithAppAttestProvider:attestProvider
                                                                   deviceCheckProvider:deviceCheckProvider];
            }
            NSLog(@"[AppCheck] Using App Attest provider.");
            return attestProvider;
        }
    }

    NSLog(@"[AppCheck] Using DeviceCheck provider for PurePetsAdmin.");
    return [[FIRDeviceCheckProvider alloc] initWithApp:app];

}

@end

@implementation AppManager

- (void)pp_logAndProbeDebugAppCheckIfNeeded {
    if (!PPShouldUseDebugAppCheckProvider()) {
        return;
    }

    FIRApp *defaultApp = [FIRApp defaultApp];
    if (!defaultApp) {
        return;
    }

    FIRAppCheckDebugProvider *provider = [[FIRAppCheckDebugProvider alloc] initWithApp:defaultApp];
    if (provider) {
        NSLog(@"[AppCheck] Local debug token: '%@'", provider.localDebugToken ?: @"");
        NSLog(@"[AppCheck] Current debug token: '%@'", provider.currentDebugToken ?: @"");
    }

    [[FIRAppCheck appCheck] tokenForcingRefresh:YES completion:^(FIRAppCheckToken * _Nullable token, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AppCheck] Debug token exchange failed for app %@ (%@): %@",
                  defaultApp.options.googleAppID ?: @"unknown-app",
                  defaultApp.options.projectID ?: @"unknown-project",
                  error.localizedDescription ?: @"unknown error");
            return;
        }

        NSLog(@"[AppCheck] Debug token exchange succeeded. Token expiration: %@",
              token.expirationDate ?: [NSNull null]);
    }];
}

+ (instancetype)shared {
    static AppManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initPrivate];
    });
    return sharedInstance;
}

- (instancetype)initPrivate {
    if (self = [super init]) {
        _appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        DLog(@"Initialized AppManager, version: %@", _appVersion);
    }
    return self;
}

- (instancetype)init {
    @throw [NSException exceptionWithName:@"Singleton"
                                   reason:@"Use +[AppManager shared]"
                                 userInfo:nil];
    return nil;
}

#pragma mark - Firebase

- (void)configureFirebase {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [FIRAppCheck setAppCheckProviderFactory:[[PPAppCheckProviderFactory alloc] init]];
        if (PPShouldUseDebugAppCheckProvider()) {
            NSLog(@"[AppCheck] Debug provider active. If requests are still blocked, register the printed debug token in Firebase Console > App Check > Manage debug tokens.");
        }

        if (![FIRApp defaultApp]) {
            [FIRApp configure];
            DLog(@"Firebase configured ✅");
            [self pp_logAndProbeDebugAppCheckIfNeeded];
            [GIDSignIn.sharedInstance configureWithCompletion:nil];
            
            [FUM startAuthListenerWithChangeBlock:^(FIRUser * _Nullable authUser, UserModel * _Nullable userModel) { }];
            
        } else {
            DLog(@"Firebase already configured, skipping");
            [self pp_logAndProbeDebugAppCheckIfNeeded];
        }
    });
}

- (void)checkIfAdmin:(void(^)(BOOL isAdmin))completion {
    FIRUser *user = [FIRAuth auth].currentUser;
    self.currentUser = user;
    
    if (!user) {
        if (completion) completion(NO);
        return;
    }
    
    __weak typeof(self) weakSelf = self;

    [[PPStaffAuth shared] fetchStaffDoc:user.uid completion:^(PPStaffDoc * _Nullable staffDoc, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;

        if (error) {
            DLog(@"[AdminAccess] ❌ canonical staff_users access read failed: %@", error.localizedDescription);
            if (completion) completion(NO);
            return;
        }

        BOOL allowed = staffDoc.canAccessStaffWorkspace;
        [PPStaffAuth shared].cachedCurrentStaff = allowed ? staffDoc : nil;
        DLog(@"[AdminAccess] %@ via canonical staff_users role=%@ status=%@",
             allowed ? @"✅ Allowed" : @"❌ Denied",
             staffDoc.role ?: @"",
             staffDoc.status ?: @"");
        if (completion) completion(allowed);
    }];
}

#pragma mark - MainKinds

- (void)fetchMainKindsWithCompletion:(void(^)(NSArray<MainKindsModel *> * _Nullable kinds, NSError * _Nullable error))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    
    DLog(@"Fetching MainKindsCollection from Firestore…");
    [[db collectionWithPath:@"MainKindsCollection"] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot,
                                                                                 NSError * _Nullable error) {
        if (error) {
            DLog(@"❌ Error fetching MainKinds: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        
        NSMutableArray<MainKindsModel *> *result = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            MainKindsModel *kind = [[MainKindsModel alloc] initWithSnapshot:doc];
            [result addObject:kind];
            DLog(@"Loaded MainKind: %@ (id=%@)", kind.KindNameEn ?: @"?", doc.documentID);
        }
        
        self.MainKindsArray = result;
        DLog(@"✅ Finished fetching MainKinds. Count = %lu", (unsigned long)result.count);
        
        if (completion) completion(result, nil);
    }];
}


- (void)startListeningCountsWithCallback:(void(^)(NSInteger adsCount, NSInteger usersCount, NSInteger accessoriesCount, NSError *error))callback {
    FIRFirestore *db = [FIRFirestore firestore];
    
    __block NSInteger adsCount = 0;
    __block NSInteger usersCount = 0;
    __block NSInteger accessoriesCount = 0;
    
    // 🔹 pet_ads listener
    self.adsListener = [[db collectionWithPath:@"pet_ads"]
        addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) { callback(0,0,0,error); return; }
            adsCount = snapshot.documents.count;
            callback(adsCount, usersCount, accessoriesCount, nil);
    }];
    
    // 🔹 UsersCol listener
    self.usersListener = [[db collectionWithPath:@"UsersCol"]
        addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) { callback(0,0,0,error); return; }
            usersCount = snapshot.documents.count;
            callback(adsCount, usersCount, accessoriesCount, nil);
    }];
    
    // 🔹 petAccessories listener
    self.accessoriesListener = [[db collectionWithPath:@"petAccessories"]
        addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) { callback(0,0,0,error); return; }
            accessoriesCount = snapshot.documents.count;
            callback(adsCount, usersCount, accessoriesCount, nil);
    }];
}

- (void)stopCountsListening {
    if (self.adsListener) [(id<FIRListenerRegistration>)self.adsListener remove];
    if (self.usersListener) [(id<FIRListenerRegistration>)self.usersListener remove];
    if (self.accessoriesListener) [(id<FIRListenerRegistration>)self.accessoriesListener remove];
}



@end
