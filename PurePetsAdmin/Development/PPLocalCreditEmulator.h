#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Opt-in Debug tooling. It never supplies a session, staff permissions or a callable result.
@interface PPLocalCreditEmulator : NSObject
+ (BOOL)isEnabled;
+ (BOOL)configureIfEnabled;
+ (void)signInFixture;
@end
NS_ASSUME_NONNULL_END
