//
//  NotificationModel.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationModel.h
#import <Foundation/Foundation.h>

@class FIRDocumentSnapshot;

typedef NS_ENUM(NSInteger, PPNotificationType) {
    PPNotificationTypeGeneral = 0,
    PPNotificationTypeOrder,
    PPNotificationTypeAdReview,
    PPNotificationTypeWarning
};

@interface NotificationModel : NSObject
@property (nonatomic, copy)   NSString *nid;          // doc id
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *body;
@property (nonatomic, copy)   NSString *targetUserID; // optional (nil = broadcast or topic)
@property (nonatomic, assign) PPNotificationType type;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, assign) BOOL isRead;
@property (nonatomic, copy)   NSDictionary *meta;     // any extra (adId, orderId, etc.)
@property (nonatomic, copy)   NSString *sourcePath;   // UsersCol/{uid}/inbox or staff_users/{uid}/inbox

+ (instancetype)fromDoc:(FIRDocumentSnapshot *)doc;
- (NSDictionary *)toDict;
@end
