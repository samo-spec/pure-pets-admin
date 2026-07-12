//
//  PPBiometric.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 01/09/2025.
//

#import "PPBiometric.h"
#import <Security/Security.h>

static NSString * const kPPBiometricDomain      = @"PPBiometric";
static NSInteger const kPPBiometricDisabledCode = -999;
static NSString * const kPPBioService           = @"com.purepets.admin.biometric";
static NSString * const kPPBioAccount           = @"admin_login_credentials";
static NSString * const kPPBioEmailKey          = @"email";
static NSString * const kPPBioPasswordKey       = @"password";

@interface PPBiometric ()
@property (nonatomic, strong) LAContext *authContext;
@property (nonatomic, assign) BOOL isAuthenticating;
@end

@implementation PPBiometric

#pragma mark - Singleton
+ (instancetype)shared {
    static PPBiometric *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[self alloc] init];
        [inst disableBiometric];
    });
    return inst;
}

#pragma mark - Availability
- (BOOL)isBiometricAvailable {
    return NO;
}

- (LABiometryType)biometryType {
    return LABiometryTypeNone;
}

#pragma mark - Save / Remove
- (void)enableBiometricWithEmail:(NSString *)email password:(NSString *)password {
    (void)email;
    (void)password;
    DLog(@"[Biometric] Biometric service disabled; ignoring enable request");
    [self disableBiometric];
}

- (void)disableBiometric {
    self.isAuthenticating = NO;
    NSMutableDictionary *query = [[self baseKeychainQuery] mutableCopy];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

    if (status == errSecSuccess || status == errSecItemNotFound) {
        DLog(@"[Biometric] Credentials cleared");
    } else {
        DLog(@"[Biometric] Failed to clear credentials: %d", (int)status);
    }
}

- (BOOL)hasStoredCredentials {
    return NO;
}

#pragma mark - Authenticate
- (void)authenticateFrom:(UIViewController *)vc
                  reason:(NSString *)reason
              completion:(PPBiometricAuthCompletion)completion
{
    (void)vc;
    (void)reason;
    self.isAuthenticating = NO;
    if (!completion) {
        DLog(@"[Biometric] Authenticate called with nil completion block.");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, nil, [self biometricDisabledError]);
    });
}

- (void)authenticateUserPresenceWithReason:(NSString *)reason
                                completion:(PPBiometricPresenceCompletion)completion
{
    (void)reason;
    self.isAuthenticating = NO;
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(NO, [self biometricDisabledError]);
    });
}

#pragma mark - Private Helpers

- (void)retrieveStoredCredentialsWithCompletion:(PPBiometricAuthCompletion)completion {
    if (completion) {
        completion(nil, nil, [self biometricDisabledError]);
    }
}

- (NSMutableDictionary *)baseKeychainQuery {
    return [@{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : kPPBioService,
        (__bridge id)kSecAttrAccount : kPPBioAccount
    } mutableCopy];
}

- (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:kPPBiometricDomain
                               code:-1
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

- (NSError *)biometricDisabledError {
    return [NSError errorWithDomain:kPPBiometricDomain
                               code:kPPBiometricDisabledCode
                           userInfo:@{NSLocalizedDescriptionKey : @"Biometric authentication is disabled for this app build."}];
}

- (NSError *)biometricErrorFromStatus:(OSStatus)status {
    NSString *message = @"Biometric authentication failed.";
    NSInteger code = status;
    
    if (status == errSecItemNotFound) {
        message = @"No stored credentials found for biometric login.";
    } else if (status == errSecAuthFailed) {
        message = @"Authentication failed. Please try again.";
    } else if (status == errSecUserCanceled) {
        message = @"Authentication was cancelled.";
    } else if (status == errSecInteractionNotAllowed) {
        message = @"Authentication is not allowed right now.";
    } else if (@available(iOS 11.3, *)) {
        if (status == errSecNotAvailable) {
            message = @"Biometric authentication is currently unavailable.";
        }
    }
    
    return [NSError errorWithDomain:kPPBiometricDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

- (NSError *)presentableErrorFromLAError:(NSError *)error {
    if (!error) {
        return nil;
    }
    
    NSString *message = @"Biometric authentication failed.";
    LAError code = (LAError)error.code;
    
    switch (code) {
        case LAErrorAuthenticationFailed:
            message = @"Authentication failed. Please try again.";
            break;
        case LAErrorUserCancel:
            message = @"Authentication was cancelled.";
            break;
        case LAErrorUserFallback:
            message = @"User requested fallback to manual login.";
            break;
        case LAErrorSystemCancel:
            message = @"System cancelled authentication.";
            break;
        case LAErrorPasscodeNotSet:
            message = @"Device passcode is not set.";
            break;
        case LAErrorBiometryNotAvailable:
            // LAErrorTouchIDNotAvailable and LAErrorBiometryNotAvailable have same value
            message = @"Biometric authentication is not available.";
            break;
        case LAErrorBiometryNotEnrolled:
            // LAErrorTouchIDNotEnrolled and LAErrorBiometryNotEnrolled have same value
            message = @"Biometric is not enrolled.";
            break;
        case LAErrorBiometryLockout:
            // LAErrorTouchIDLockout and LAErrorBiometryLockout have same value
            message = @"Biometric has been locked. Please use passcode.";
            break;
        default:
            message = [NSString stringWithFormat:@"Authentication error: %@", error.localizedDescription];
            break;
    }
    
    return [NSError errorWithDomain:kPPBiometricDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

- (OSStatus)savePayload:(NSData *)data accessibility:(CFTypeRef)accessibility {
    if (!data) {
        return errSecParam;
    }
    
    CFErrorRef accessError = NULL;
    SecAccessControlRef access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        accessibility,
        kSecAccessControlBiometryCurrentSet,
        &accessError
    );
    
    if (!access) {
        if (accessError) {
            NSError *err = CFBridgingRelease(accessError);
            DLog(@"[Biometric] Failed to create access control: %@", err.localizedDescription);
        }
        return errSecParam;
    }
    
    NSMutableDictionary *attrs = [[self baseKeychainQuery] mutableCopy];
    attrs[(__bridge id)kSecValueData] = data;
    attrs[(__bridge id)kSecAttrAccessControl] = (__bridge id)access;
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attrs, nil);
    CFRelease(access);
    
    return status;
}

@end
