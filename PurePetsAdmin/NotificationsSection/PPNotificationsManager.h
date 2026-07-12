//
//  PPDeviceTokenManager.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 14/09/2025.
//


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPNotificationAudience) {
    PPNotificationAudienceSpecificUsers = 0,
    PPNotificationAudienceAllUsers,
    PPNotificationAudienceAdmins,
    PPNotificationAudienceEveryone
};

@interface PPNotificationsManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, strong) NSString *deviceToken;
@property (nonatomic, assign, readonly) BOOL isTokenAvailable;

// Get current token (async)
- (void)getDeviceTokenWithCompletion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;

// Refresh token if needed
- (void)refreshTokenWithCompletion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;

// Check notification permissions
- (void)checkNotificationPermissions:(void (^)(BOOL granted, BOOL provisional))completion;

- (void)sendMessageToUser:(NSString *)receiverId
                    title:(NSString *)title
                     body:(NSString *)body;

// Functions URL configuration (override is optional)
+ (NSString *)functionsBaseURL;
+ (void)setFunctionsBaseURLOverride:(nullable NSString *)baseURL;

// Unified audience-based send API
+ (void)sendNotificationWithTitle:(NSString *)title
                             body:(NSString *)body
                             data:(nullable NSDictionary *)data
                         audience:(PPNotificationAudience)audience
                          userIDs:(nullable NSArray<NSString *> *)userIDs
                       completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

//=======================================================================================================================================//

+ (void)sendToUser:(NSString *)uid
             title:(NSString *)title
              body:(NSString *)body
              data:(NSDictionary *)data
        completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

+ (void)sendToToken:(NSString *)token
              title:(NSString *)title
               body:(NSString *)body
               data:(NSDictionary *)data
         completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

+ (void)sendToUsers:(NSArray<NSString *> *)uids
              title:(NSString *)title
               body:(NSString *)body
               data:(NSDictionary *)data
         completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

+ (void)sendToAllUsersWithTitle:(NSString *)title
                           body:(NSString *)body
                           data:(NSDictionary *)data
                     completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

+ (void)sendToAdminsWithTitle:(NSString *)title
                         body:(NSString *)body
                         data:(NSDictionary *)data
                   completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

+ (void)sendToAllWithTitle:(NSString *)title
                      body:(NSString *)body
                      data:(NSDictionary *)data
                completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
