#import "PPNotificationsManager.h"
#import <UserNotifications/UserNotifications.h>
#import <UIKit/UIKit.h>
@import Firebase;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import FirebaseMessaging;

static NSString * const kPPNotificationTokenDefaultsKey = @"SavedDeviceToken";
static NSString * const kPPNotificationFunctionsBaseURLDefault = @"https://us-central1-pure-pets-49199.cloudfunctions.net";

static NSString * _Nullable sFunctionsBaseURLOverride = nil;

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

#pragma mark - Public config

+ (NSString *)functionsBaseURL {
    if (sFunctionsBaseURLOverride.length) {
        return [self pp_trimmedString:sFunctionsBaseURLOverride];
    }

    NSString *plistURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"PPCloudFunctionsBaseURL"];
    if (plistURL.length) {
        return [self pp_trimmedString:plistURL];
    }
    return kPPNotificationFunctionsBaseURLDefault;
}

+ (void)setFunctionsBaseURLOverride:(NSString *)baseURL {
    sFunctionsBaseURLOverride = [self pp_trimmedString:baseURL];
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

+ (void)sendNotificationWithTitle:(NSString *)title
                             body:(NSString *)body
                             data:(NSDictionary *)data
                         audience:(PPNotificationAudience)audience
                          userIDs:(NSArray<NSString *> *)userIDs
                       completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *safeTitle = [self pp_trimmedString:title];
    NSString *safeBody = [self pp_trimmedString:body];
    NSDictionary *safeData = [self pp_stringDataDictionary:data];

    if (safeTitle.length == 0 || safeBody.length == 0) {
        NSError *err = [NSError errorWithDomain:@"PPNotificationsManager"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Title and body are required."}];
        [self pp_completeOnMain:completion response:nil error:err];
        return;
    }

    NSMutableDictionary *params = [@{
        @"title": safeTitle,
        @"body": safeBody,
        @"data": safeData
    } mutableCopy];

    NSString *endpoint = @"";
    switch (audience) {
        case PPNotificationAudienceSpecificUsers: {
            NSArray<NSString *> *safeUIDs = [self pp_uniqueNonEmptyStrings:userIDs];
            if (safeUIDs.count == 0) {
                NSError *err = [NSError errorWithDomain:@"PPNotificationsManager"
                                                   code:400
                                               userInfo:@{NSLocalizedDescriptionKey: @"Please select at least one user."}];
                [self pp_completeOnMain:completion response:nil error:err];
                return;
            }
            if (safeUIDs.count == 1) {
                params[@"uid"] = safeUIDs.firstObject;
                endpoint = @"sendToUser";
            } else {
                params[@"uids"] = safeUIDs;
                endpoint = @"sendToUsers";
            }
            break;
        }
        case PPNotificationAudienceAllUsers:
            endpoint = @"sendToAllUsers";
            break;
        case PPNotificationAudienceAdmins:
            endpoint = @"sendToAdmins";
            break;
        case PPNotificationAudienceEveryone:
            endpoint = @"sendToAll";
            break;
    }

    [self callFunction:endpoint params:params completion:completion];
}

#pragma mark - Backward compatible wrappers

- (void)sendMessageToUser:(NSString *)receiverId
                    title:(NSString *)title
                     body:(NSString *)body {
    [PPNotificationsManager sendToUser:receiverId
                                 title:title
                                  body:body
                                  data:@{}
                            completion:nil];
}

+ (void)sendToUser:(NSString *)uid
             title:(NSString *)title
              body:(NSString *)body
              data:(NSDictionary *)data
        completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                               data:data
                           audience:PPNotificationAudienceSpecificUsers
                            userIDs:uid.length ? @[uid] : @[]
                         completion:completion];
}

+ (void)sendToUsers:(NSArray<NSString *> *)uids
              title:(NSString *)title
               body:(NSString *)body
               data:(NSDictionary *)data
         completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                               data:data
                           audience:PPNotificationAudienceSpecificUsers
                            userIDs:uids
                         completion:completion];
}

+ (void)sendToToken:(NSString *)token
              title:(NSString *)title
               body:(NSString *)body
               data:(NSDictionary *)data
         completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *safeToken = [self pp_trimmedString:token];
    NSString *safeTitle = [self pp_trimmedString:title];
    NSString *safeBody = [self pp_trimmedString:body];
    if (safeToken.length == 0) {
        NSError *err = [NSError errorWithDomain:@"PPNotificationsManager"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Token is required."}];
        [self pp_completeOnMain:completion response:nil error:err];
        return;
    }
    if (safeTitle.length == 0 || safeBody.length == 0) {
        NSError *err = [NSError errorWithDomain:@"PPNotificationsManager"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Title and body are required."}];
        [self pp_completeOnMain:completion response:nil error:err];
        return;
    }

    NSMutableDictionary *params = [@{
        @"token": safeToken,
        @"title": safeTitle,
        @"body": safeBody,
        @"data": [self pp_stringDataDictionary:data]
    } mutableCopy];

    [self callFunction:@"sendToUser" params:params completion:completion];
}

+ (void)sendToAllUsersWithTitle:(NSString *)title
                           body:(NSString *)body
                           data:(NSDictionary *)data
                     completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                               data:data
                           audience:PPNotificationAudienceAllUsers
                            userIDs:nil
                         completion:completion];
}

+ (void)sendToAdminsWithTitle:(NSString *)title
                         body:(NSString *)body
                         data:(NSDictionary *)data
                   completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                               data:data
                           audience:PPNotificationAudienceAdmins
                            userIDs:nil
                         completion:completion];
}

+ (void)sendToAllWithTitle:(NSString *)title
                      body:(NSString *)body
                      data:(NSDictionary *)data
                completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    [self sendNotificationWithTitle:title
                               body:body
                               data:data
                           audience:PPNotificationAudienceEveryone
                            userIDs:nil
                         completion:completion];
}

#pragma mark - HTTP transport

+ (void)callFunction:(NSString *)functionName
              params:(NSDictionary *)params
          completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSString *safeFunction = [self pp_trimmedString:functionName];
    if (safeFunction.length == 0) {
        NSError *err = [NSError errorWithDomain:@"PPNotificationsManager"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Function name is required."}];
        [self pp_completeOnMain:completion response:nil error:err];
        return;
    }

    NSString *baseURL = [self functionsBaseURL];
    NSString *urlString = [NSString stringWithFormat:@"%@/%@", baseURL, safeFunction];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *err = [NSError errorWithDomain:@"PPNotificationsManager"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid Cloud Functions URL."}];
        [self pp_completeOnMain:completion response:nil error:err];
        return;
    }

    NSError *jsonError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:[self pp_safeDictionary:params] options:0 error:&jsonError];
    if (jsonError) {
        [self pp_completeOnMain:completion response:nil error:jsonError];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 30.0;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    request.HTTPBody = bodyData;

    FIRUser *user = [FIRAuth auth].currentUser;
    if (user) {
        [user getIDTokenWithCompletion:^(NSString * _Nullable idToken, NSError * _Nullable error) {
            if (error) {
                [self pp_completeOnMain:completion response:nil error:error];
                return;
            }
            if (idToken.length) {
                [request setValue:[NSString stringWithFormat:@"Bearer %@", idToken]
               forHTTPHeaderField:@"Authorization"];
            }
            [self executeRequest:request completion:completion];
        }];
        return;
    }

    [self executeRequest:request completion:completion];
}

+ (void)executeRequest:(NSURLRequest *)request
            completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData * _Nullable data,
                                                                                     NSURLResponse * _Nullable response,
                                                                                     NSError * _Nullable error) {
        if (error) {
            [self pp_completeOnMain:completion response:nil error:error];
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        NSInteger statusCode = httpResp.statusCode;

        NSDictionary *json = nil;
        NSString *responseString = @"";
        if (data.length) {
            NSError *parseError = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            if ([parsed isKindOfClass:[NSDictionary class]]) {
                json = parsed;
            }
            if (parseError || !json) {
                responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
            }
        }

        if (statusCode >= 200 && statusCode < 300) {
            NSDictionary *payload = json ?: @{@"ok": @YES, @"raw": responseString ?: @""};
            [self pp_completeOnMain:completion response:payload error:nil];
            return;
        }

        NSString *serverMessage = [self pp_serverMessageFromJSON:json raw:responseString];
        NSError *statusError = [NSError errorWithDomain:@"PPNotificationsManager"
                                                   code:statusCode
                                               userInfo:@{NSLocalizedDescriptionKey: serverMessage}];
        [self pp_completeOnMain:completion response:json error:statusError];
    }];
    [task resume];
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
