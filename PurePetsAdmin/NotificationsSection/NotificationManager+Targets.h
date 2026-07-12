//
//  NotificationManager 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationManager+Targets.h
#import "NotificationManager.h"

typedef NS_ENUM(NSInteger, PPAudience) {
    PPAudienceAppUsers = 0,   // all registered app users
    PPAudienceAllUsers = 1    // literally everyone (falls back to broadcast)
};

@interface NotificationManager (Targets)

/// Send to a logical audience (app users vs all users)
- (void)sendToAudience:(PPAudience)audience
                 model:(NotificationModel *_Nullable)model
            completion:(void(^_Nullable)(NSError * _Nullable error))completion;

/// Send to users with any of the given roles (e.g. Moderator/Admin)
/// Pass NSNumber-wrapped integers of your UserRole enum.
- (void)sendToRoles:(NSArray<NSNumber * > *_Nullable)roles
              model:(NotificationModel *_Nullable)model
         completion:(void(^_Nullable)(NSError * _Nullable error))completion;

@end
