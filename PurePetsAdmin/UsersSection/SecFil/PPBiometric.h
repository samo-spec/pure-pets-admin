//
//  PPBiometric.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 01/09/2025.
//


// In PPBiometric.h
#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^PPBiometricAuthCompletion)(NSString * _Nullable email,
                                         NSString * _Nullable password,
                                         NSError  * _Nullable error);
typedef void(^PPBiometricPresenceCompletion)(BOOL success,
                                             NSError * _Nullable error);

@interface PPBiometric : NSObject

/// Shared instance
+ (instancetype)shared;

/// Check if device supports Face ID / Touch ID
- (BOOL)isBiometricAvailable;

/// The type of biometric available (Face ID / Touch ID / none)
- (LABiometryType)biometryType;

/// Enable biometric by saving credentials securely
- (void)enableBiometricWithEmail:(NSString *)email
                        password:(NSString *)password;

/// Authenticate user using biometric (Face ID / Touch ID)
- (void)authenticateFrom:(UIViewController *)vc
                  reason:(NSString *)reason
              completion:(PPBiometricAuthCompletion)completion;

/// Authenticate device owner presence for app unlock (biometric / passcode).
- (void)authenticateUserPresenceWithReason:(NSString *)reason
                                completion:(PPBiometricPresenceCompletion)completion;

/// Remove saved credentials (disable biometric)
- (void)disableBiometric;

/// Check if credentials are stored
- (BOOL)hasStoredCredentials;
@end

NS_ASSUME_NONNULL_END
