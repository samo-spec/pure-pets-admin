#import "PPProLoginCoordinator.h"

#import "AdminLoginViewController.h"
#import "AppManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPHUD.h"
#import "UserManager.h"
#import "FUManager.h"
#import "PPBiometric.h"
#import "PPRolePermission.h"
#import "PPStaffAuth.h"
#import "RPManager.h"
@import Firebase;
@import FirebaseAuth;

@interface PPStaffAuth (PPProLoginCoordinatorCacheAccess)
@property (nonatomic, strong, nullable, readwrite) PPStaffDoc *cachedCurrentStaff;
@end

extern BOOL PPAdminLoginInProgress(void);
extern void PPAdminSetLoginInProgress(BOOL inProgress);

static NSString * const kPPFIRAuthInternalErrorDomain = @"FIRAuthInternalErrorDomain";
static NSString * const kPPFIRAuthDeserializedResponseKey = @"FIRAuthErrorUserInfoDeserializedResponseKey";

@interface PPProLoginCoordinator ()
@property (nonatomic, weak) UIViewController *presentingViewController;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> combinedReg;
@end

@implementation PPProLoginCoordinator

- (instancetype)initWithPresentingViewController:(UIViewController *)viewController {
    self = [super init];
    if (self) {
        _presentingViewController = viewController;
    }
    return self;
}

- (void)dealloc {
    [self.combinedReg remove];
    self.combinedReg = nil;
}

- (NSString *)savedEmail {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kSavedEmailKey];
    return [saved isKindOfClass:NSString.class] ? saved : @"";
}

- (BOOL)isRememberMeEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kRememberMeKey];
}

- (BOOL)canUseBiometricLogin {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kBiometricDisabledUntilManualLogin]) {
        return NO;
    }
    return [PPBiometric.shared isBiometricAvailable] && [PPBiometric.shared hasStoredCredentials];
}

- (NSString *)biometricDisplayTitle {
    switch (PPBiometric.shared.biometryType) {
        case LABiometryTypeFaceID:
            return kLang(@"LoginWithFaceID");
        case LABiometryTypeTouchID:
            return kLang(@"LoginWithTouchID");
        default:
            return kLang(@"LoginWithFaceID");
    }
}

- (void)signInWithEmail:(NSString *)email
               password:(NSString *)password
               remember:(BOOL)remember
             completion:(PPProLoginCompletion)completion
{
    NSString *trimmedEmail = [((NSString *)email ?: @"")
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safePassword = password ?: @"";

    if (trimmedEmail.length == 0 || safePassword.length == 0) {
        if (completion) completion(NO, kLang(@"StatusEnterBoth"));
        return;
    }

    [self pp_persistRememberMe:remember email:trimmedEmail];

    PPAdminSetLoginInProgress(YES);
    [self pp_signInWithEmail:trimmedEmail
                    password:safePassword
               fromBiometric:NO
                  completion:completion
    allowRetryOnInternalError:YES];
}

- (void)signInWithGoogleWithCompletion:(PPProLoginCompletion)completion {
    PPAdminSetLoginInProgress(YES);
    [PPHUD showIndeterminateIn:self.presentingViewController.view
                          title:kLang(@"Please wait")
                       subtitle:kLang(@"StatusLoggingIn")];

    __weak typeof(self) weakSelf = self;
    [[FUManager shared] signInWithGoogle:self.presentingViewController completion:^(FIRUser * _Nullable user, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (error || !user) {
            [PPHUD dismiss];
            PPAdminSetLoginInProgress(NO);
            if (completion) {
                if (error.code == -5) {
                    completion(NO, nil);
                } else {
                    completion(NO, [self pp_authErrorSubtitle:error]);
                }
            }
            return;
        }

        [self pp_gatekeepStaffAccessForUID:user.uid
                                  email:user.email ?: @""
                               password:@""
                          fromBiometric:NO
                             completion:completion];
    }];
}

- (void)requestPasswordResetForEmail:(NSString *)email
                          completion:(PPProLoginCompletion)completion
{
    NSString *trimmedEmail = [((NSString *)email ?: @"")
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedEmail.length == 0) {
        if (completion) completion(NO, kLang(@"EnterEmailFirst"));
        return;
    }

    [[FIRAuth auth] sendPasswordResetWithEmail:trimmedEmail completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(error == nil, error ? [self pp_authErrorSubtitle:error] : kLang(@"PasswordResetEmailSent"));
            }
        });
    }];
}

- (void)signInWithBiometricWithCompletion:(PPProLoginCompletion)completion {
    if (![self canUseBiometricLogin]) {
        if (completion) completion(NO, kLang(@"BiometricNotAvailable"));
        return;
    }

    PPAdminSetLoginInProgress(YES);
    __weak typeof(self) weakSelf = self;
    [PPBiometric.shared authenticateFrom:self.presentingViewController
                                  reason:kLang(@"AuthenticateToLogin")
                              completion:^(NSString * _Nullable email,
                                           NSString * _Nullable password,
                                           NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (error || email.length == 0 || password.length == 0) {
            PPAdminSetLoginInProgress(NO);
            if (completion) {
                completion(NO, error.localizedDescription ?: kLang(@"BiometricFailed"));
            }
            return;
        }

        [self pp_signInWithEmail:email
                        password:password
                   fromBiometric:YES
                      completion:completion
        allowRetryOnInternalError:YES];
    }];
}

#pragma mark - Private

- (void)pp_persistRememberMe:(BOOL)remember email:(NSString *)email {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:remember forKey:kRememberMeKey];
    if (remember) {
        [ud setObject:email forKey:kSavedEmailKey];
    } else {
        [ud removeObjectForKey:kSavedEmailKey];
    }
    [ud synchronize];
}

- (void)pp_signInWithEmail:(NSString *)email
                  password:(NSString *)password
             fromBiometric:(BOOL)fromBiometric
                completion:(PPProLoginCompletion)completion
allowRetryOnInternalError:(BOOL)allowRetryOnInternalError
{
    [PPHUD showIndeterminateIn:self.presentingViewController.view
                          title:kLang(@"Please wait")
                       subtitle:kLang(@"StatusLoggingIn")];

    __weak typeof(self) weakSelf = self;
    [[FUManager shared] signInWithEmail:email password:password completion:^(FIRUser * _Nullable user, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        FIRUser *effectiveUser = user ?: [FIRAuth auth].currentUser;
        BOOL recoveredFromTransientError =
            (error != nil && effectiveUser != nil && [self pp_shouldRetryInternalAuthError:error]);

        if ((error && !recoveredFromTransientError) || !effectiveUser) {
            if (error) {
                [self pp_logAuthError:error context:@"signIn"];
            }

            if (fromBiometric && [self pp_shouldDisableBiometricForAuthError:error]) {
                [PPBiometric.shared disableBiometric];
                [self pp_setBiometricDisabledUntilManualLogin:YES];
            }

            if (allowRetryOnInternalError && [self pp_shouldRetryInternalAuthError:error]) {
                [UsrMgr signOutWithCompletion:^(__unused NSError * _Nullable signOutError) {
                    [PPHUD dismiss];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(350 * NSEC_PER_MSEC)),
                                   dispatch_get_main_queue(), ^{
                        [self pp_signInWithEmail:email
                                        password:password
                                   fromBiometric:fromBiometric
                                      completion:completion
                        allowRetryOnInternalError:NO];
                    });
                }];
                return;
            }

            [PPHUD dismiss];
            PPAdminSetLoginInProgress(NO);
            if (completion) completion(NO, [self pp_authErrorSubtitle:error]);
            return;
        }

        if (error && recoveredFromTransientError) {
            [self pp_logAuthError:error context:@"signIn_recovered_transient"];
        }

        [effectiveUser getIDTokenResultForcingRefresh:YES completion:^(FIRAuthTokenResult * _Nullable tokenResult, NSError * _Nullable refreshError) {
            (void)tokenResult;
            if (refreshError) return;
            [[RPManager shared] fetchIDTokenClaims:^(NSDictionary * _Nullable claims, NSError * _Nullable claimsErr) {
                if (!claimsErr) {
                    DLog(@"[PPProLogin] claims=%@", claims ?: @{});
                }
            }];
        }];

        [[FUManager shared] ensureUserDocumentExistsForCurrentUserWithExtra:nil completion:^(NSError * _Nullable eDoc) {
            if (eDoc && ![self pp_shouldContinueAfterEnsureUserDocError:eDoc]) {
                [PPHUD dismiss];
                PPAdminSetLoginInProgress(NO);
                if (completion) completion(NO, [self pp_firestoreAccessSubtitleForError:eDoc]);
                return;
            }

            [self pp_gatekeepStaffAccessForUID:effectiveUser.uid
                                      email:email
                                   password:password
                              fromBiometric:fromBiometric
                                 completion:completion];
        }];
    }];
}

- (BOOL)pp_shouldContinueAfterEnsureUserDocError:(NSError * _Nullable)error {
    if (!error) return YES;

    if ([self pp_errorLooksLikeAppCheckFailure:error]) {
        return NO;
    }

    if ([error.domain isEqualToString:FIRFirestoreErrorDomain] &&
        error.code == FIRFirestoreErrorCodePermissionDenied) {
        return YES;
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        [underlying.domain isEqualToString:FIRFirestoreErrorDomain] &&
        underlying.code == FIRFirestoreErrorCodePermissionDenied) {
        return YES;
    }

    return NO;
}

- (void)pp_gatekeepStaffAccessForUID:(NSString *)uid
                            email:(NSString *)email
                         password:(NSString *)password
                    fromBiometric:(BOOL)fromBiometric
                       completion:(PPProLoginCompletion)completion
{
    if (uid.length == 0) {
        [PPHUD dismiss];
        PPAdminSetLoginInProgress(NO);
        [UsrMgr signOut];
        if (completion) completion(NO, kLang(@"StatusUserDocError"));
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[PPStaffAuth shared] fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable staffDoc, NSError * _Nullable staffError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (staffError) {
            if ([self pp_errorLooksLikeAppCheckFailure:staffError]) {
                [PPHUD dismiss];
                PPAdminSetLoginInProgress(NO);
                if (completion) completion(NO, [self pp_firestoreAccessSubtitleForError:staffError]);
                return;
            }

            [PPHUD dismiss];
            PPAdminSetLoginInProgress(NO);
            [UsrMgr signOut];
            if (completion) completion(NO, kLang(@"StatusUserDocError"));
            return;
        }

        if (staffDoc.canAccessStaffWorkspace) {
            [PPStaffAuth shared].cachedCurrentStaff = staffDoc;
            [self pp_finishLoginAndStartUserStreamWithEmail:email
                                                   password:password
                                              fromBiometric:fromBiometric
                                                 completion:completion];
            return;
        }

        if (fromBiometric) {
            [PPBiometric.shared disableBiometric];
            [self pp_setBiometricDisabledUntilManualLogin:YES];
        }
        [PPHUD dismiss];
        PPAdminSetLoginInProgress(NO);
        [UsrMgr signOut];
        if (completion) {
            completion(NO, staffDoc && !staffDoc.isActive
                       ? kLang(@"StatusAccountDisabled")
                       : kLang(@"StatusNoAccess"));
        }
    }];
}

- (void)pp_finishLoginAndStartUserStreamWithEmail:(NSString *)email
                                         password:(NSString *)password
                                    fromBiometric:(BOOL)fromBiometric
                                       completion:(PPProLoginCompletion)completion
{
    (void)fromBiometric;
    if (self.combinedReg) {
        [self.combinedReg remove];
        self.combinedReg = nil;
    }

    __weak typeof(self) weakSelf = self;
    self.combinedReg = [[FUManager shared] listenCombinedUser:^(UserModel * _Nullable u, NSError * _Nullable err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (err || !u) {
            PPAdminSetLoginInProgress(NO);
            [PPHUD dismiss];
            [self.combinedReg remove];
            self.combinedReg = nil;
            if (![self pp_errorLooksLikeAppCheckFailure:err]) {
                [UsrMgr signOut];
            }
            if (completion) completion(NO, [self pp_firestoreAccessSubtitleForError:err]);
            return;
        }

        [PPBiometric.shared enableBiometricWithEmail:email password:password];
        [self pp_setBiometricDisabledUntilManualLogin:NO];

        [UsrMgr p_writeUserToDisk:u forUID:u.uid];

        [PPHUD dismiss];
        [self.combinedReg remove];
        self.combinedReg = nil;
        PPAdminSetLoginInProgress(NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:UserManagerAuthStateDidChangeNotification object:nil];
        });

        if (completion) completion(YES, nil);
    }];
}

- (void)pp_setBiometricDisabledUntilManualLogin:(BOOL)disabled {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:disabled forKey:kBiometricDisabledUntilManualLogin];
    [ud synchronize];
}

- (BOOL)pp_shouldDisableBiometricForAuthError:(NSError * _Nullable)error {
    if (![self pp_isFirebaseAuthError:error]) return NO;
    FIRAuthErrorCode code = [self pp_normalizedAuthErrorCode:error];
    switch (code) {
        case FIRAuthErrorCodeInvalidCredential:
        case FIRAuthErrorCodeWrongPassword:
        case FIRAuthErrorCodeUserDisabled:
        case FIRAuthErrorCodeUserNotFound:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)pp_hasUnderlyingFirebaseAuthError:(NSError * _Nullable)error {
    if (!error) return NO;
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (![underlying isKindOfClass:NSError.class]) return NO;
    return [underlying.domain isEqualToString:FIRAuthErrorDomain] ||
           [underlying.domain isEqualToString:kPPFIRAuthInternalErrorDomain];
}

- (NSString *)pp_authBackendMessageFromDeserializedPayload:(NSDictionary * _Nullable)payload {
    if (![payload isKindOfClass:NSDictionary.class]) return @"";

    NSString *(^asString)(id) = ^NSString *(id value) {
        return [value isKindOfClass:NSString.class] ? value : @"";
    };

    NSString *message = asString(payload[@"message"]);
    if (message.length > 0) return message;

    NSDictionary *errorPayload = [payload[@"error"] isKindOfClass:NSDictionary.class] ? payload[@"error"] : nil;
    if (errorPayload) {
        message = asString(errorPayload[@"message"]);
        if (message.length > 0) return message;

        NSArray *errors = [errorPayload[@"errors"] isKindOfClass:NSArray.class] ? errorPayload[@"errors"] : nil;
        NSDictionary *firstError = errors.count > 0 && [errors.firstObject isKindOfClass:NSDictionary.class] ? errors.firstObject : nil;
        message = asString(firstError[@"message"]);
        if (message.length > 0) return message;
    }

    return @"";
}

- (NSString *)pp_authBackendMessageFromError:(NSError * _Nullable)error {
    if (!error) return @"";

    NSString *message = [self pp_authBackendMessageFromDeserializedPayload:error.userInfo[kPPFIRAuthDeserializedResponseKey]];
    if (message.length > 0) return message;

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class]) {
        message = [self pp_authBackendMessageFromDeserializedPayload:underlying.userInfo[kPPFIRAuthDeserializedResponseKey]];
        if (message.length > 0) return message;

        NSError *deepUnderlying = underlying.userInfo[NSUnderlyingErrorKey];
        if ([deepUnderlying isKindOfClass:NSError.class]) {
            message = [self pp_authBackendMessageFromDeserializedPayload:deepUnderlying.userInfo[kPPFIRAuthDeserializedResponseKey]];
            if (message.length > 0) return message;
        }
    }

    return @"";
}

- (BOOL)pp_errorLooksLikeAppCheckFailure:(NSError * _Nullable)error {
    if (![error isKindOfClass:NSError.class]) return NO;

    NSArray<NSString *> *messages = @[
        error.localizedDescription ?: @"",
        [self pp_authBackendMessageFromError:error] ?: @""
    ];
    for (NSString *message in messages) {
        NSString *lower = [message lowercaseString];
        if ([lower containsString:@"appcheck"] ||
            [lower containsString:@"app check"] ||
            [lower containsString:@"app attest"] ||
            [lower containsString:@"app attestation failed"] ||
            [lower containsString:@"app check token is invalid"] ||
            [lower containsString:@"exchangeappattestattestation"]) {
            return YES;
        }
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] && underlying != error) {
        return [self pp_errorLooksLikeAppCheckFailure:underlying];
    }

    return NO;
}

- (NSString *)pp_firestoreAccessSubtitleForError:(NSError * _Nullable)error {
    if ([self pp_errorLooksLikeAppCheckFailure:error]) {
        return kLang(@"StatusAppCheckInvalid");
    }
    return kLang(@"StatusUserDocError");
}

- (NSString *)pp_authErrorSubtitle:(NSError * _Nullable)error {
    NSString *fallback = kLang(@"StatusLoginFailed");
    if (!error) return fallback;

    if ([self pp_isFirebaseAuthError:error]) {
        switch ([self pp_normalizedAuthErrorCode:error]) {
            case FIRAuthErrorCodeInvalidCredential:
            case FIRAuthErrorCodeWrongPassword:
            case FIRAuthErrorCodeUserNotFound:
                return kLang(@"StatusInvalidCredentials");
            case FIRAuthErrorCodeUserDisabled:
                return kLang(@"StatusAccountDisabled");
            case FIRAuthErrorCodeNetworkError:
                return kLang(@"StatusNetworkError");
            default:
                break;
        }
    }

    NSString *backendMessage = [self pp_authBackendMessageFromError:error];
    if (backendMessage.length > 0) {
        if ([backendMessage rangeOfString:@"app check token is invalid"
                                  options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return kLang(@"StatusAppCheckInvalid");
        }
        return backendMessage;
    }

    NSString *description = error.localizedDescription;
    if (description.length > 0 && ![description isEqualToString:@"(null)"]) {
        return description;
    }

    return fallback;
}

- (BOOL)pp_shouldRetryInternalAuthError:(NSError * _Nullable)error {
    if (![self pp_isFirebaseAuthError:error]) return NO;

    NSString *backendMessage = [self pp_authBackendMessageFromError:error];
    if ([backendMessage rangeOfString:@"app check token is invalid" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [backendMessage rangeOfString:@"app attestation failed" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return NO;
    }

    FIRAuthErrorCode code = [self pp_normalizedAuthErrorCode:error];
    switch (code) {
        case FIRAuthErrorCodeInternalError:
        case FIRAuthErrorCodeNetworkError:
            return YES;
        default:
            if (![error.domain isEqualToString:kPPFIRAuthInternalErrorDomain]) {
                return NO;
            }
            return ![self pp_hasUnderlyingFirebaseAuthError:error];
    }
}

- (BOOL)pp_isFirebaseAuthError:(NSError * _Nullable)error {
    if (!error) return NO;
    if ([error.domain isEqualToString:FIRAuthErrorDomain]) return YES;
    if ([error.domain isEqualToString:kPPFIRAuthInternalErrorDomain]) return YES;

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        ([underlying.domain isEqualToString:FIRAuthErrorDomain] ||
         [underlying.domain isEqualToString:kPPFIRAuthInternalErrorDomain])) {
        return YES;
    }
    return NO;
}

- (FIRAuthErrorCode)pp_normalizedAuthErrorCode:(NSError *)error {
    if ([error.domain isEqualToString:FIRAuthErrorDomain]) {
        return (FIRAuthErrorCode)error.code;
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        [underlying.domain isEqualToString:FIRAuthErrorDomain]) {
        return (FIRAuthErrorCode)underlying.code;
    }
    return (FIRAuthErrorCode)error.code;
}

- (void)pp_logAuthError:(NSError *)error context:(NSString *)context {
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    NSDictionary *deserialized = error.userInfo[kPPFIRAuthDeserializedResponseKey];
    NSLog(@"[PPProLogin] %@ auth error domain=%@ code=%ld normalizedCode=%ld name=%@ desc=%@ underlyingDomain=%@ underlyingCode=%ld deserialized=%@ userInfo=%@",
          context ?: @"",
          error.domain ?: @"",
          (long)error.code,
          (long)[self pp_normalizedAuthErrorCode:error],
          error.userInfo[FIRAuthErrorUserInfoNameKey] ?: @"",
          error.localizedDescription ?: @"",
          underlying.domain ?: @"",
          (long)underlying.code,
          deserialized ?: @{},
          error.userInfo ?: @{});
}

@end
