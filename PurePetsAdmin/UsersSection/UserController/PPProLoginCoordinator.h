#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PPProLoginCompletion)(BOOL success, NSString * _Nullable message);

@interface PPProLoginCoordinator : NSObject

- (instancetype)initWithPresentingViewController:(UIViewController *)viewController NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, assign) BOOL suppressesHUD;

- (NSString *)savedEmail;
- (BOOL)isRememberMeEnabled;
- (BOOL)canUseBiometricLogin;
- (NSString *)biometricDisplayTitle;

- (void)signInWithEmail:(NSString *)email
               password:(NSString *)password
               remember:(BOOL)remember
             completion:(PPProLoginCompletion)completion;

- (void)signInWithGoogleWithCompletion:(PPProLoginCompletion)completion NS_SWIFT_NAME(signInWithGoogle(completion:));

- (void)signInWithAppleWithCompletion:(PPProLoginCompletion)completion NS_SWIFT_NAME(signInWithApple(completion:));

- (void)sendVerificationCodeToPhone:(NSString *)phoneNumber
                         completion:(void(^)(NSString * _Nullable verificationID, NSString * _Nullable error))completion NS_SWIFT_NAME(sendVerificationCode(toPhone:completion:));

- (void)signInWithPhoneVerificationID:(NSString *)verificationID
                                 code:(NSString *)code
                           completion:(PPProLoginCompletion)completion NS_SWIFT_NAME(signIn(withPhoneVerificationID:code:completion:));

- (void)requestPasswordResetForEmail:(NSString *)email
                          completion:(PPProLoginCompletion)completion;

- (void)signInWithBiometricWithCompletion:(PPProLoginCompletion)completion;

@end

NS_ASSUME_NONNULL_END
