// In AdminLoginViewController.h
#import <UIKit/UIKit.h>
#import "XLForm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * const kBiometricDisabledUntilManualLogin = @"biometricDisabledUntilManualLogin";
static NSString * const kRememberMeKey   = @"rememberMe";
static NSString * const kSavedEmailKey   = @"savedEmail";
@interface AdminLoginViewController : XLFormViewController
@end

NS_ASSUME_NONNULL_END
