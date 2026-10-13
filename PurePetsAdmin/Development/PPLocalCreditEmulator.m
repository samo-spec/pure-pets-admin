#import "PPLocalCreditEmulator.h"

#ifndef PP_LOCAL_CREDIT_QA
#define PP_LOCAL_CREDIT_QA 0
#endif
#if PP_LOCAL_CREDIT_QA && !DEBUG
#error Local credit emulators are forbidden in a Release build.
#endif

#if PP_LOCAL_CREDIT_QA
@import FirebaseCore;
@import FirebaseAuth;
@import FirebaseFirestore;
@import FirebaseFunctions;
@import FirebaseStorage;
@import FirebaseAppCheck;
#import <arpa/inet.h>

// App Check has no local emulator. Fail closed; never manufacture an attestation
// or exchange production tokens for this synthetic project.
@interface PPLocalCreditAppCheckProvider : NSObject <FIRAppCheckProvider, FIRAppCheckProviderFactory>
@end
@implementation PPLocalCreditAppCheckProvider
- (id<FIRAppCheckProvider>)createProviderWithApp:(FIRApp *)app { return self; }
- (void)getTokenWithCompletion:(void (^)(FIRAppCheckToken * _Nullable, NSError * _Nullable))handler {
    handler(nil, [NSError errorWithDomain:@"PPLocalCreditEmulator" code:1
                                userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"POS_Credit_Unavailable", nil)}]);
}
@end

static void PPRequireLocalCredit(BOOL condition, NSString *reason) {
    if (!condition) @throw [NSException exceptionWithName:@"PPLocalCreditIsolation" reason:reason userInfo:nil];
}

static NSString *PPLocalCreditHost(void) {
    id raw = [NSBundle.mainBundle objectForInfoDictionaryKey:@"PPLocalCreditEmulatorHost"];
    PPRequireLocalCredit([raw isKindOfClass:NSString.class], @"Missing explicit local emulator host.");
    struct in_addr address;
    PPRequireLocalCredit(inet_pton(AF_INET, [raw UTF8String], &address) == 1, @"Invalid local emulator host.");
    uint32_t value = ntohl(address.s_addr);
    BOOL isPrivate = (value >> 24) == 10 || (value >> 20) == 0xAC1 || (value >> 16) == 0xC0A8;
    PPRequireLocalCredit(isPrivate, @"Physical-device QA requires the Mac's private IPv4 address.");
    return raw;
}
#endif

// Keep the inert class in every target configuration: AppManager/AppDelegate
// call its guards in production. Emulator imports/behavior compile only with
// the explicit QA macro; enabling that macro in Release is a compile error.
@implementation PPLocalCreditEmulator
+ (BOOL)isEnabled {
    return PP_LOCAL_CREDIT_QA == 1;
}

+ (BOOL)configureIfEnabled {
#if PP_LOCAL_CREDIT_QA
    PPRequireLocalCredit([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"Ali-Ahmed.PurePetsAdmin.CreditQA"], @"QA build cannot use the production bundle identity.");
    NSString *host = PPLocalCreditHost();
    PPRequireLocalCredit(FIRApp.defaultApp == nil, @"QA Firebase must be configured before any consumer.");
    PPRequireLocalCredit([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"PPLocalCreditProject"] isEqual:@"demo-pure-pets-credit"], @"Unexpected QA project.");
    [FIRAppCheck setAppCheckProviderFactory:[PPLocalCreditAppCheckProvider new]];
    FIROptions *options = [[FIROptions alloc] initWithGoogleAppID:@"1:1234567890:ios:0123456789abcdef012345" GCMSenderID:@"1234567890"];
    options.projectID = @"demo-pure-pets-credit";
    options.APIKey = @"local-credit-emulator-no-production-key";
    options.bundleID = @"Ali-Ahmed.PurePetsAdmin.CreditQA";
    options.storageBucket = @"demo-pure-pets-credit.appspot.com";
    [FIRApp configureWithOptions:options];
    [[FIRAuth auth] useEmulatorWithHost:host port:19099];
    [[FIRFirestore firestore] useEmulatorWithHost:host port:18822];
    [[FIRFunctions functions] useEmulatorWithHost:host port:15001];
    [[FIRStorage storage] useEmulatorWithHost:host port:19199];
    return YES;
#else
    // A signing/flag mistake must never turn the separately installed QA app into a production client.
    if ([NSBundle.mainBundle.bundleIdentifier hasSuffix:@".CreditQA"]) {
        @throw [NSException exceptionWithName:@"PPLocalCreditIsolation" reason:@"QA identity requires an explicit Debug emulator build." userInfo:nil];
    }
    return NO;
#endif
}

+ (void)signInFixture {
#if PP_LOCAL_CREDIT_QA
    PPRequireLocalCredit([FIRApp.defaultApp.options.projectID isEqualToString:@"demo-pure-pets-credit"], @"Fixture Auth requires the demo project.");
    NSString *actor = [NSBundle.mainBundle objectForInfoDictionaryKey:@"PPLocalCreditActor"];
    PPRequireLocalCredit([@[@"seller", @"denied", @"foreign", @"disabled"] containsObject:actor ?: @""], @"Unknown local fixture actor.");
    NSString *uid = [@"qa-credit-" stringByAppendingString:actor];
    // Preserve a valid local session across relaunch, including pending-command recovery.
    if ([[FIRAuth auth].currentUser.uid isEqualToString:uid]) return;
    NSError *signOutError;
    if (![[FIRAuth auth] signOut:&signOutError]) {
        NSLog(@"[CreditQA] Fixture sign-out failed (%ld).", (long)signOutError.code);
        return;
    }
    [[FIRAuth auth] signInWithEmail:[NSString stringWithFormat:@"credit-%@@example.test", actor]
                        password:@"LocalCreditFixtureOnly!42"
                      completion:^(FIRAuthDataResult *result, NSError *error) {
        // Existing AdminSessionStore/PPStaffAuth restores the real emulator staff record.
        NSLog(@"[CreditQA] Synthetic Auth %@ (error code %ld).", result ? @"ready" : @"failed", (long)error.code);
    }];
#endif
}
@end
