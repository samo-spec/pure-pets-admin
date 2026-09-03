#import "PPNotificationsManager.h"
#import "AppDelegate.h"
#import "NotificationModel.h"
#import <UserNotifications/UserNotifications.h>
#import <UIKit/UIKit.h>
@import Firebase;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseFunctions;
@import FirebaseAuth;
@import FirebaseMessaging;

static NSString * const kPPNotificationTokenDefaultsKey = @"SavedDeviceToken";
// Keep the explicit-recipient path aligned with the callable's server limit.
static const NSUInteger kPPConsoleNotificationRecipientLimit = 500;

static NSString * const kPPNotificationV2AdminAppID = @"admin_ios";
static NSString * const kPPNotificationV2AdminBindingDefaultsKey = @"PPNotificationV2AdminBindingV1";

static NSString *PPNotificationV2AdminEnvironment(void)
{
#if DEBUG
    return @"sandbox";
#else
    return @"production";
#endif
}

@interface PPNotificationsManager ()
+ (void)pp_sendConsoleNotificationToUsers:(NSArray<NSString *> *)userIDs
                                     title:(NSString *)title
                                      body:(NSString *)body
                                      type:(NSInteger)type
                            idempotencyKey:(NSString *)idempotencyKey
                                completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;
+ (void)pp_callConsoleNotificationWithPayload:(NSDictionary *)payload
                                    completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;
@end

@implementation PPNotificationsManager
@synthesize deviceToken = _deviceToken;

+ (instancetype)sharedManager {
    static PPNotificationsManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tokenUpdated:)
                                                     name:@"FCMTokenUpdated"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Token lifecycle

- (void)tokenUpdated:(NSNotification *)notification {
    NSString *token = notification.object;
    if (![token isKindOfClass:[NSString class]] || token.length == 0) return;
    self.deviceToken = token;
}

- (void)setDeviceToken:(NSString *)deviceToken {
    NSString *safeToken = [PPNotificationsManager pp_trimmedString:deviceToken];
    _deviceToken = [safeToken copy];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (safeToken.length) {
        [defaults setObject:safeToken forKey:kPPNotificationTokenDefaultsKey];
    } else {
        [defaults removeObjectForKey:kPPNotificationTokenDefaultsKey];
    }
    [defaults synchronize];
}

- (NSString *)deviceToken {
    NSString *cached = _deviceToken;
    if (cached.length) return cached;
    cached = [[NSUserDefaults standardUserDefaults] stringForKey:kPPNotificationTokenDefaultsKey];
    _deviceToken = [[PPNotificationsManager pp_trimmedString:cached] copy];
    return _deviceToken;
}

- (BOOL)isTokenAvailable {
    return self.deviceToken.length > 0;
}

- (void)getDeviceTokenWithCompletion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    if (self.isTokenAvailable) {
        if (completion) completion(self.deviceToken, nil);
        return;
    }

    [[FIRMessaging messaging] tokenWithCompletion:^(NSString * _Nullable token, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                if (completion) completion(nil, error);
                return;
            }

            NSString *safe = [PPNotificationsManager pp_trimmedString:token];
            if (safe.length == 0) {
                NSError *noTokenError = [NSError errorWithDomain:@"PPNotificationsManager"
                                                             code:1001
                                                         userInfo:@{NSLocalizedDescriptionKey: @"No token available"}];
                if (completion) completion(nil, noTokenError);
                return;
            }

            self.deviceToken = safe;
            if (completion) completion(safe, nil);
        });
    }];
}

- (void)refreshTokenWithCompletion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    [[FIRMessaging messaging] deleteTokenWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }
        [self getDeviceTokenWithCompletion:completion];
    }];
}

- (void)deactivateNotificationDeviceV2WithReason:(NSString *)reason
                                      completion:(void (^)(NSError * _Nullable))completion {
    NSString *safeUID = [PPNotificationsManager pp_trimmedString:[FIRAuth auth].currentUser.uid];
    NSString *safeReason = [PPNotificationsManager pp_trimmedString:reason];
    NSSet<NSString *> *allowedReasons = [NSSet setWithArray:@[@"logout", @"account_switch", @"token_deleted", @"manual"]];
    if (safeUID.length == 0 || ![allowedReasons containsObject:safeReason]) {
        NSLog(@"PPLAB NotificationsV2 admin deactivation skipped | appId=%@ hasUID=%@ validReason=%@",
              kPPNotificationV2AdminAppID,
              safeUID.length > 0 ? @"yes" : @"no",
              [allowedReasons containsObject:safeReason] ? @"yes" : @"no");
        if (completion) completion(nil);
        return;
    }

    NSDictionary *binding = [NSUserDefaults.standardUserDefaults dictionaryForKey:kPPNotificationV2AdminBindingDefaultsKey];
    NSString *bindingUID = [PPNotificationsManager pp_trimmedString:binding[@"uid"]];
    NSString *installationId = [PPNotificationsManager pp_trimmedString:binding[@"installationId"]];
    NSString *appId = [PPNotificationsManager pp_trimmedString:binding[@"appId"]];
    NSString *environment = [PPNotificationsManager pp_trimmedString:binding[@"environment"]];
    NSString *bindingGeneration = [PPNotificationsManager pp_trimmedString:binding[@"bindingGeneration"]];
    NSString *fcmTokenHash = [PPNotificationsManager pp_trimmedString:binding[@"fcmTokenHash"]];
    BOOL bindingMatchesSession = [bindingUID isEqualToString:safeUID] &&
        [appId isEqualToString:kPPNotificationV2AdminAppID] &&
        [environment isEqualToString:PPNotificationV2AdminEnvironment()] &&
        installationId.length > 0 && bindingGeneration.length > 0 && fcmTokenHash.length > 0;
    if (!bindingMatchesSession) {
        NSLog(@"PPLAB NotificationsV2 admin deactivation skipped | appId=%@ reason=%@ binding_match=no",
              kPPNotificationV2AdminAppID,
              safeReason);
        if (completion) completion(nil);
        return;
    }

    NSString *activeUID = [PPNotificationsManager pp_trimmedString:[FIRAuth auth].currentUser.uid];
    if (![activeUID isEqualToString:safeUID]) {
        NSLog(@"PPLAB NotificationsV2 admin deactivation cancelled | appId=%@ reason=%@ auth_changed=yes",
              kPPNotificationV2AdminAppID,
              safeReason);
        if (completion) completion(nil);
        return;
    }

    NSDictionary *payload = @{
        @"installationId": installationId,
        @"reason": safeReason,
        @"appId": @"admin_ios",
        @"environment": environment,
        @"bindingGeneration": bindingGeneration,
        @"expectedFcmTokenHash": fcmTokenHash
    };
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"deactivateNotificationDeviceV2"];
    callable.timeoutInterval = 30.0;
    NSLog(@"PPLAB NotificationsV2 admin deactivation start | appId=%@ reason=%@ hasBinding=yes",
          kPPNotificationV2AdminAppID,
          safeReason);

    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"PPLAB NotificationsV2 admin deactivation failed | appId=%@ reason=%@ error=%@",
                      kPPNotificationV2AdminAppID,
                      safeReason,
                      error.localizedDescription ?: @"unknown");
                if (completion) completion(error);
                return;
            }

            NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : @{};
            BOOL ok = [response[@"ok"] respondsToSelector:@selector(boolValue)] && [response[@"ok"] boolValue];
            BOOL deactivated = [response[@"deactivated"] respondsToSelector:@selector(boolValue)] && [response[@"deactivated"] boolValue];
            BOOL stale = [response[@"stale"] respondsToSelector:@selector(boolValue)] && [response[@"stale"] boolValue];
            if (ok) {
                NSDictionary *storedBinding = [NSUserDefaults.standardUserDefaults dictionaryForKey:kPPNotificationV2AdminBindingDefaultsKey];
                if ([[PPNotificationsManager pp_trimmedString:storedBinding[@"uid"]] isEqualToString:safeUID] &&
                    [[PPNotificationsManager pp_trimmedString:storedBinding[@"bindingGeneration"]] isEqualToString:bindingGeneration]) {
                    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPPNotificationV2AdminBindingDefaultsKey];
                }
            }
            NSLog(@"PPLAB NotificationsV2 admin deactivation finish | appId=%@ reason=%@ ok=%@ deactivated=%@ stale=%@",
                  kPPNotificationV2AdminAppID,
                  safeReason,
                  ok ? @"yes" : @"no",
                  deactivated ? @"yes" : @"no",
                  stale ? @"yes" : @"no");
            if (completion) completion(nil);
        });
    }];
}

- (void)invalidateLocalDeviceTokenWithCompletion:(void (^)(NSError * _Nullable))completion {
    self.deviceToken = @"";
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPPNotificationV2AdminBindingDefaultsKey];

    id<UIApplicationDelegate> applicationDelegate = UIApplication.sharedApplication.delegate;
    if ([applicationDelegate isKindOfClass:AppDelegate.class]) {
        ((AppDelegate *)applicationDelegate).fcmToken = @"";
    }

    [[FIRMessaging messaging] deleteTokenWithCompletion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"PPLAB NotificationsV2 admin token delete finish | appId=%@ ok=%@",
                  kPPNotificationV2AdminAppID,
                  error ? @"no" : @"yes");
            if (completion) completion(error);
        });
    }];
}

- (void)checkNotificationPermissions:(void (^)(BOOL granted, BOOL provisional))completion {
    if (@available(iOS 10.0, *)) {
        [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            BOOL granted = settings.authorizationStatus == UNAuthorizationStatusAuthorized;
            BOOL provisional = settings.authorizationStatus == UNAuthorizationStatusProvisional;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(granted, provisional);
            });
        }];
        return;
    }

    UIUserNotificationSettings *settings = [[UIApplication sharedApplication] currentUserNotificationSettings];
    BOOL granted = (settings.types != UIUserNotificationTypeNone);
    if (completion) completion(granted, NO);
}

#pragma mark - Unified notification send API

+ (void)sendConsoleNotificationWithTitle:(NSString *)title
                                     body:(NSString *)body
                                     type:(NSInteger)type
                                 audience:(PPNotificationAudience)audience
                                  userIDs:(NSArray<NSString *> * _Nullable)userIDs
                          idempotencyKey:(NSString *)idempotencyKey
                              completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *safeTitle = [self pp_trimmedString:title];
    NSString *safeBody = [self pp_trimmedString:body];
    NSString *safeKey = [self pp_trimmedString:idempotencyKey];
    NSArray<NSString *> *safeUserIDs = [self pp_uniqueNonEmptyStrings:userIDs];
    BOOL isSpecificAudience = audience == PPNotificationAudienceSpecificUsers;

    if (safeTitle.length == 0 || safeBody.length == 0 || safeKey.length == 0 ||
        (isSpecificAudience && safeUserIDs.count == 0) ||
        (isSpecificAudience && safeUserIDs.count > kPPConsoleNotificationRecipientLimit)) {
        NSError *error = [NSError errorWithDomain:@"PPNotificationsManager" code:400 userInfo:nil];
        [self pp_completeOnMain:completion response:nil error:error];
        return;
    }

    NSInteger normalizedType = MIN(MAX(type, PPNotificationTypeGeneral), PPNotificationTypeWarning);
    if (isSpecificAudience) {
        [self pp_sendConsoleNotificationToUsers:safeUserIDs
                                           title:safeTitle
                                            body:safeBody
                                            type:normalizedType
                                  idempotencyKey:safeKey
                                      completion:completion];
        return;
    }

    NSString *audienceValue = @"everyone";
    switch (audience) {
        case PPNotificationAudienceAllUsers:
            audienceValue = @"users";
            break;
        case PPNotificationAudienceAdmins:
            audienceValue = @"admins";
            break;
        case PPNotificationAudienceEveryone:
        default:
            break;
    }

    NSDictionary *payload = @{
        @"title": safeTitle,
        @"body": safeBody,
        @"type": @(normalizedType),
        @"targetMode": @"broadcast",
        @"audience": audienceValue,
        @"idempotencyKey": safeKey
    };
    [self pp_callConsoleNotificationWithPayload:payload completion:completion];
}

+ (void)pp_sendConsoleNotificationToUsers:(NSArray<NSString *> *)userIDs
                                     title:(NSString *)title
                                      body:(NSString *)body
                                      type:(NSInteger)type
                            idempotencyKey:(NSString *)idempotencyKey
                                completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSObject *resultLock = [NSObject new];
    __block NSInteger recipientCount = 0;
    __block NSInteger pushRecipientCount = 0;
    __block NSInteger successCount = 0;
    __block NSInteger failureCount = 0;
    __block NSInteger requestFailureCount = 0;
    __block NSError *lastError = nil;

    // Keep explicit-recipient fan-out bounded. A single dispatch group over
    // hundreds of HTTPS callables can saturate the Admin process and APNs
    // quota; advancing one small batch at a time preserves ordering and
    // keeps retry pressure predictable.
    const NSUInteger batchSize = 20;
    __block void (^sendBatch)(NSUInteger);
    sendBatch = ^(NSUInteger offset) {
        if (offset >= userIDs.count) {
            NSDictionary *response = nil;
            NSError *error = nil;
            @synchronized (resultLock) {
                response = @{
                    @"ok": @(requestFailureCount == 0),
                    @"recipientCount": @(recipientCount),
                    @"pushRecipientCount": @(pushRecipientCount),
                    @"successCount": @(successCount),
                    @"failureCount": @(failureCount),
                    @"requestFailureCount": @(requestFailureCount)
                };
                error = requestFailureCount == userIDs.count ? lastError : nil;
            }
            sendBatch = nil;
            if (completion) completion(response, error);
            return;
        }

        NSUInteger end = MIN(offset + batchSize, userIDs.count);
        dispatch_group_t group = dispatch_group_create();
        for (NSUInteger index = offset; index < end; index++) {
            NSString *userID = userIDs[index];
            dispatch_group_enter(group);
            NSDictionary *payload = @{
                @"title": title,
                @"body": body,
                @"type": @(type),
                @"targetMode": @"user",
                @"audience": @"users",
                @"targetUserID": userID,
                @"idempotencyKey": [NSString stringWithFormat:@"%@:%@", idempotencyKey, userID]
            };
            [self pp_callConsoleNotificationWithPayload:payload completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
                @synchronized (resultLock) {
                    if (error) {
                        requestFailureCount += 1;
                        lastError = error;
                    } else {
                        // Preserve the server's exact zero-recipient response.
                        recipientCount += MAX(0, [response[@"recipientCount"] integerValue]);
                        pushRecipientCount += MAX(0, [response[@"pushRecipientCount"] integerValue]);
                        successCount += MAX(0, [response[@"successCount"] integerValue]);
                        failureCount += MAX(0, [response[@"failureCount"] integerValue]);
                    }
                }
                dispatch_group_leave(group);
            }];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            sendBatch(end);
        });
    };
    sendBatch(0);
}

+ (void)pp_callConsoleNotificationWithPayload:(NSDictionary *)payload
                                    completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"sendConsoleNotification"];
    callable.timeoutInterval = 30.0;
    [callable callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : @{};
        [self pp_completeOnMain:completion response:response error:error];
    }];
}

+ (void)sendNotificationWithTitle:(NSString *)title
                             body:(NSString *)body
                         audience:(PPNotificationAudience)audience
                          userIDs:(NSArray<NSString *> *)userIDs
                       completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *safeTitle = [self pp_trimmedString:title];
    NSString *safeBody = [self pp_trimmedString:body];
    if (safeTitle.length == 0 || safeBody.length == 0) {
        NSError *err = [NSError errorWithDomain:@"PPNotificationsManager"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: kLang(@"FillRequiredFields")}];
        [self pp_completeOnMain:completion response:nil error:err];
        return;
    }

    [self sendConsoleNotificationWithTitle:safeTitle
                                      body:safeBody
                                      type:PPNotificationTypeGeneral
                                  audience:audience
                                   userIDs:userIDs
                            idempotencyKey:NSUUID.UUID.UUIDString
                                completion:completion];
}

#pragma mark - Backward compatible wrappers

- (void)sendMessageToUser:(NSString *)receiverId
                    title:(NSString *)title
                     body:(NSString *)body {
    [PPNotificationsManager sendToUser:receiverId
                                 title:title
                                  body:body
                            completion:nil];
}

+ (void)sendToUser:(NSString *)uid
             title:(NSString *)title
             body:(NSString *)body
         completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                           audience:PPNotificationAudienceSpecificUsers
                            userIDs:uid.length ? @[uid] : @[]
                         completion:completion];
}

+ (void)sendToUsers:(NSArray<NSString *> *)uids
              title:(NSString *)title
              body:(NSString *)body
         completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                           audience:PPNotificationAudienceSpecificUsers
                            userIDs:uids
                         completion:completion];
}

+ (void)sendToAllUsersWithTitle:(NSString *)title
                           body:(NSString *)body
                     completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                           audience:PPNotificationAudienceAllUsers
                            userIDs:nil
                         completion:completion];
}

+ (void)sendToAdminsWithTitle:(NSString *)title
                         body:(NSString *)body
                   completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                           audience:PPNotificationAudienceAdmins
                            userIDs:nil
                         completion:completion];
}

+ (void)sendToAllWithTitle:(NSString *)title
                      body:(NSString *)body
                completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                           audience:PPNotificationAudienceEveryone
                            userIDs:nil
                         completion:completion];
}

#pragma mark - Helpers

+ (void)pp_completeOnMain:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion
                 response:(NSDictionary *)response
                    error:(NSError *)error {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(response, error);
    });
}

+ (NSArray<NSString *> *)pp_uniqueNonEmptyStrings:(NSArray<NSString *> *)strings {
    if (![strings isKindOfClass:[NSArray class]]) return @[];
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    for (id item in strings) {
        if (![item isKindOfClass:[NSString class]]) continue;
        NSString *trimmed = [self pp_trimmedString:item];
        if (trimmed.length == 0) continue;
        [set addObject:trimmed];
    }
    return set.array;
}

+ (NSDictionary *)pp_safeDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *safe = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (!key) return;
        safe[key] = obj ?: [NSNull null];
    }];
    return safe;
}

+ (NSDictionary *)pp_stringDataDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *safe = [NSMutableDictionary dictionaryWithCapacity:dictionary.count];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) return;
        NSString *stringValue = @"";
        if ([obj isKindOfClass:[NSString class]]) {
            stringValue = (NSString *)obj;
        } else if ([obj isKindOfClass:[NSNumber class]]) {
            stringValue = [(NSNumber *)obj stringValue];
        } else if ([obj isKindOfClass:[NSNull class]] || obj == nil) {
            stringValue = @"";
        } else if ([NSJSONSerialization isValidJSONObject:obj]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
            stringValue = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : [obj description];
        } else {
            stringValue = [obj description] ?: @"";
        }
        safe[(NSString *)key] = stringValue ?: @"";
    }];
    return safe;
}

+ (NSString *)pp_trimmedString:(NSString *)value {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)pp_serverMessageFromJSON:(NSDictionary *)json raw:(NSString *)raw {
    NSString *jsonMessage = @"";
    if ([json isKindOfClass:[NSDictionary class]]) {
        id errorMessage = json[@"error"] ?: json[@"message"] ?: json[@"msg"];
        if ([errorMessage isKindOfClass:[NSString class]]) {
            jsonMessage = [self pp_trimmedString:errorMessage];
        }
    }

    if (jsonMessage.length) return jsonMessage;
    NSString *rawMessage = [self pp_trimmedString:raw];
    if (rawMessage.length) return rawMessage;
    return @"Server request failed.";
}

@end
