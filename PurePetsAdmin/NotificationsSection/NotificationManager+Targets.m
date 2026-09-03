//
//  NotificationManager 2.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationManager+Targets.m
#import "NotificationManager+Targets.h"
#import "Language.h"

@implementation NotificationManager (Targets)

#pragma mark - Public

- (void)sendToAudience:(PPAudience)audience
                 model:(NotificationModel *)model
            completion:(void(^)(NSError * _Nullable error))completion
{
    if (![model isKindOfClass:NotificationModel.class]) {
        if (completion) completion([NSError errorWithDomain:@"NotificationManager"
                                                         code:400
                                                     userInfo:@{NSLocalizedDescriptionKey: kLang(@"SomethingWentWrong")}]);
        return;
    }
    PPNotificationAudience target = audience == PPAudienceAllUsers
        ? PPNotificationAudienceEveryone
        : PPNotificationAudienceAllUsers;
    [PPNotificationsManager sendConsoleNotificationWithTitle:model.title
                                                         body:model.body
                                                         type:model.type
                                                     audience:target
                                                      userIDs:nil
                                               idempotencyKey:NSUUID.UUID.UUIDString
                                                   completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}

- (void)sendToRoles:(NSArray<NSNumber *> *)roles
              model:(NotificationModel *)model
         completion:(void(^)(NSError * _Nullable error))completion
{
    (void)roles;
    (void)model;
    if (completion) completion([NSError errorWithDomain:@"NotificationManager"
                                                   code:405
                                               userInfo:@{NSLocalizedDescriptionKey: kLang(@"SomethingWentWrong")}]);
}

@end
