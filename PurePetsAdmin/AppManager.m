//
//  AppManager.m
//  PurePetsAdmin
//






#import "AppManager.h"
#import "Development/PPLocalCreditEmulator.h"
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
#import <DeviceCheck/DeviceCheck.h>

NSString * const PPAdminGoogleAppCheckErrorDomain = @"PurePetsAdmin.GoogleAppCheck";

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
#if DEBUG
#if TARGET_OS_SIMULATOR
    return YES;
#else
    // In Debug builds (e.g. running from Xcode on connected physical device),
    // default to Debug provider unless explicitly forced to production App Attest.
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSDictionary<NSString *, NSString *> *env = processInfo.environment ?: @{};
    if (PPAppCheckTruthyString(env[@"PP_FORCE_APPCHECK_APPACTEST_PROVIDER"])) {
        return NO;
    }
    return YES;
#endif
#else
    // A runtime environment variable or preference must never enable Debug
    // attestation in a distributed Release build.
    return NO;
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

static BOOL PPAppCheckTextLooksLikeAppAttestFailure(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) {
        return NO;
    }

    NSString *lower = text.lowercaseString;
    return [lower containsString:@"appattest"] ||
           [lower containsString:@"app attest"] ||
           [lower containsString:@"app_attest"] ||
           [lower containsString:@"app attestation"] ||
           [lower containsString:@"exchangeappattestattestation"] ||
           [lower containsString:@"attestation"] ||
           [lower containsString:@"dc"] ||
           [lower containsString:@"devicecheck"] ||
           [lower containsString:@"attestkey"] ||
           [lower containsString:@"keyid"] ||
           [lower containsString:@"invalidkey"] ||
           [lower containsString:@"unsupported"] ||
           [lower containsString:@"featureunsupported"];
}

static BOOL PPAppCheckTokenIsNilOrEmpty(FIRAppCheckToken *token) {
    if (!token) return YES;
    if (![token isKindOfClass:FIRAppCheckToken.class]) return YES;
    if (![token.token isKindOfClass:NSString.class]) return YES;
    if (token.token.length == 0) return YES;
    return NO;
}

static BOOL PPAppCheckErrorLooksLikeAppAttestFailure(NSError *error) {
    if (!error) return NO;

    if (PPAppCheckTextLooksLikeAppAttestFailure(error.domain) ||
        PPAppCheckTextLooksLikeAppAttestFailure(error.localizedDescription) ||
        PPAppCheckTextLooksLikeAppAttestFailure(error.localizedFailureReason) ||
        PPAppCheckTextLooksLikeAppAttestFailure(error.localizedRecoverySuggestion)) {
        return YES;
    }

    NSDictionary *userInfo = [error.userInfo isKindOfClass:NSDictionary.class] ? error.userInfo : nil;
    for (id value in userInfo.allValues) {
        if ([value isKindOfClass:NSString.class] &&
            PPAppCheckTextLooksLikeAppAttestFailure((NSString *)value)) {
            return YES;
        }

        if ([value isKindOfClass:NSError.class] &&
            PPAppCheckErrorLooksLikeAppAttestFailure((NSError *)value)) {
            return YES;
        }
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

        // Valid token — use it directly
        if (!PPAppCheckTokenIsNilOrEmpty(token)) {
            if (handler) {
                handler(token, nil);
            }
            return;
        }

        // Token is nil/empty or App Attest failed — fall back to DeviceCheck unconditionally
        self.usingDeviceCheckFallback = YES;
        NSLog(@"[AppCheck] App Attest returned nil/empty token (error=%@). Falling back to DeviceCheck for PurePetsAdmin.",
              error.localizedDescription ?: @"none");
        PPFetchAppCheckTokenFromProvider(deviceCheckProvider, limitedUse, ^(FIRAppCheckToken * _Nullable fallbackToken, NSError * _Nullable fallbackError) {
            if (!PPAppCheckTokenIsNilOrEmpty(fallbackToken)) {
                if (handler) {
                    handler(fallbackToken, nil);
                }
                return;
            }

            NSLog(@"[AppCheck] DeviceCheck fallback also failed (error=%@). Original App Attest error=%@",
                  fallbackError.localizedDescription ?: @"none",
                  error.localizedDescription ?: @"none");

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

    BOOL isAppAttestSupported = NO;
    if (@available(iOS 14.0, *)) {
        if ([DCAppAttestService class]) {
            isAppAttestSupported = [DCAppAttestService sharedService].isSupported;
        }
    }

    if (PPShouldUseAppAttestAppCheckProvider() && @available(iOS 14.0, *)) {
        if (isAppAttestSupported) {
            NSLog(@"[AppCheck] AppAttest provider forced via PP_FORCE_APPCHECK_APPACTEST_PROVIDER or PPForceAppCheckAppAttestProvider.");
            id<FIRAppCheckProvider> attestProvider = [[FIRAppAttestProvider alloc] initWithApp:app];
            if (attestProvider) {
                return attestProvider;
            }
        }
        NSLog(@"[AppCheck] AppAttest provider forced but unavailable on this device. Falling back to DeviceCheck for PurePetsAdmin.");
    }
    
    // Best practice fallback sequence for iOS:
    if (@available(iOS 14.0, *)) {
        if (isAppAttestSupported) {
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
        } else {
            NSLog(@"[AppCheck] DCAppAttestService is not supported on this hardware (e.g. A10/A11 or pre-A12 device). Using DeviceCheck provider directly.");
        }
    }

    NSLog(@"[AppCheck] Using DeviceCheck provider for PurePetsAdmin.");
    return [[FIRDeviceCheckProvider alloc] initWithApp:app];

}

@end

@interface AppManager ()
@property (nonatomic, assign) BOOL googleSignInAppCheckReady;
@property (nonatomic, assign) BOOL googleSignInAppCheckConfiguring;
@property (nonatomic, assign) NSUInteger googleSignInAppCheckGeneration;
@property (nonatomic, strong) NSMutableArray *googleSignInAppCheckCompletions;
@end

@implementation AppManager

- (void)pp_logAndProbeDebugAppCheckIfNeeded {
#if DEBUG
    if (!PPShouldUseDebugAppCheckProvider()) {
        return;
    }

    FIRApp *defaultApp = [FIRApp defaultApp];
    if (!defaultApp) {
        return;
    }

    [[FIRAppCheck appCheck] tokenForcingRefresh:YES completion:^(FIRAppCheckToken * _Nullable token, NSError * _Nullable error) {
        if (error) {
            DLog(@"[AppCheck] Debug exchange failed (%@/%ld).", error.domain, (long)error.code);
            return;
        }

        DLog(@"[AppCheck] Debug exchange succeeded.");
    }];
#endif
}

- (void)prepareGoogleSignInWithCompletion:(void (^ _Nullable)(NSError * _Nullable))callback {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self prepareGoogleSignInWithCompletion:callback];
        });
        return;
    }
    if (self.googleSignInAppCheckReady) {
        if (callback) callback(nil);
        return;
    }

    if (!self.googleSignInAppCheckCompletions) {
        self.googleSignInAppCheckCompletions = [NSMutableArray array];
    }
    if (callback) [self.googleSignInAppCheckCompletions addObject:[callback copy]];
    if (self.googleSignInAppCheckConfiguring) return;

    self.googleSignInAppCheckConfiguring = YES;
    NSUInteger generation = ++self.googleSignInAppCheckGeneration;
    void (^finish)(NSError * _Nullable) = ^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Ignore late/duplicate completions from a timed-out setup attempt.
            if (self.googleSignInAppCheckGeneration != generation || !self.googleSignInAppCheckConfiguring) return;
            self.googleSignInAppCheckConfiguring = NO;
            self.googleSignInAppCheckReady = error == nil;

            NSError *reportedError = nil;
            if (error) {
                BOOL networkError = NO;
                NSError *cause = error;
                for (NSUInteger depth = 0; cause && depth < 8; depth++) {
                    if ([cause.domain isEqualToString:NSURLErrorDomain]) {
                        networkError = YES;
                        break;
                    }
                    id underlying = cause.userInfo[NSUnderlyingErrorKey];
                    cause = [underlying isKindOfClass:NSError.class] ? underlying : nil;
                }
                reportedError = [NSError errorWithDomain:PPAdminGoogleAppCheckErrorDomain code:110 userInfo:@{
                    NSLocalizedDescriptionKey: networkError ? kLang(@"StatusNetworkError") : kLang(@"auth_google_verification_failed"),
                    NSUnderlyingErrorKey: error
                }];
                DLog(@"[GoogleSignIn][AppCheck] Setup failed (%@/%ld).", error.domain, (long)error.code);
            }

            NSArray *callbacks = [self.googleSignInAppCheckCompletions copy];
            [self.googleSignInAppCheckCompletions removeAllObjects];
            for (void (^pending)(NSError * _Nullable) in callbacks) pending(reportedError);
        });
    };

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.googleSignInAppCheckGeneration == generation && self.googleSignInAppCheckConfiguring) {
            finish([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);
        }
    });

    FIRApp *defaultApp = [FIRApp defaultApp];
    if (!defaultApp) {
        finish([NSError errorWithDomain:PPAdminGoogleAppCheckErrorDomain code:1 userInfo:nil]);
        return;
    }
#if DEBUG
    if (PPShouldUseDebugAppCheckProvider()) {
        // Google Identity owns a separate App Check client and debug token.
        // Firebase's provider factory does not configure Google Sign-In.
        NSString *apiKey = defaultApp.options.APIKey;
        if (apiKey.length == 0) {
            finish([NSError errorWithDomain:PPAdminGoogleAppCheckErrorDomain code:2 userInfo:nil]);
            return;
        }
        [GIDSignIn.sharedInstance configureDebugProviderWithAPIKey:apiKey completion:finish];
        return;
    }
#endif
    [GIDSignIn.sharedInstance configureWithCompletion:finish];
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
        if ([PPLocalCreditEmulator configureIfEnabled]) {
            [FUM startAuthListenerWithChangeBlock:^(FIRUser * _Nullable authUser, UserModel * _Nullable userModel) { }];
            [PPLocalCreditEmulator signInFixture];
            return;
        }
        [FIRAppCheck setAppCheckProviderFactory:[[PPAppCheckProviderFactory alloc] init]];
        if (PPShouldUseDebugAppCheckProvider()) {
            DLog(@"[AppCheck] Debug provider active. Firebase and Google Identity debug tokens require registration for this app.");
        }

        if (![FIRApp defaultApp]) {
            [FIRApp configure];
            DLog(@"Firebase configured ✅");
            [FUM startAuthListenerWithChangeBlock:^(FIRUser * _Nullable authUser, UserModel * _Nullable userModel) { }];
            
        } else {
            DLog(@"Firebase already configured, skipping");
        }
        [self prepareGoogleSignInWithCompletion:nil];
        [self pp_logAndProbeDebugAppCheckIfNeeded];
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
    FIRQuery *query = [[db collectionWithPath:@"MainKindsCollection"] queryOrderedByField:@"sortingKey" descending:NO];
    
    DLog(@"Fetching fresh MainKindsCollection from Firestore (Server first)…");
    [query getDocumentsWithSource:FIRFirestoreSourceServer completion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error || !snapshot) {
            DLog(@"⚠️ Server fetch failed (%@), trying default cache...", error.localizedDescription);
            [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable cacheSnap, NSError * _Nullable cacheErr) {
                if (cacheErr) {
                    DLog(@"❌ Error fetching MainKinds: %@", cacheErr.localizedDescription);
                    if (completion) completion(nil, cacheErr);
                    return;
                }
                NSMutableArray<MainKindsModel *> *result = [NSMutableArray array];
                for (FIRDocumentSnapshot *doc in cacheSnap.documents) {
                    MainKindsModel *kind = [[MainKindsModel alloc] initWithSnapshot:doc];
                    [result addObject:kind];
                }
                self.MainKindsArray = result;
                if (completion) completion(result, nil);
            }];
            return;
        }
        
        NSMutableArray<MainKindsModel *> *result = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            MainKindsModel *kind = [[MainKindsModel alloc] initWithSnapshot:doc];
            [result addObject:kind];
        }
        
        self.MainKindsArray = result;
        DLog(@"✅ Finished fetching fresh MainKinds from server. Count = %lu", (unsigned long)result.count);
        
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
