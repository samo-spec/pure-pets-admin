//
//  NotificationModel.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationModel.m
#import "NotificationModel.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

static NSString *PPNotificationMetadataString(id value)
{
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return @"";
}

@implementation NotificationModel
+ (instancetype)fromDoc:(FIRDocumentSnapshot *)doc {
    NotificationModel *m = [NotificationModel new];
    m.nid = doc.documentID;
    NSDictionary *d = doc.data ?: @{};
    m.title = [d[@"title"] isKindOfClass:NSString.class] ? d[@"title"] : @"";
    m.body  = [d[@"body"] isKindOfClass:NSString.class] ? d[@"body"] : @"";
    m.targetUserID = [d[@"targetUserID"] isKindOfClass:NSString.class] ? d[@"targetUserID"] : nil;
    m.type = [d[@"type"] integerValue];
    m.isRead = [d[@"isRead"] boolValue];
    NSMutableDictionary *normalizedMeta = [([d[@"meta"] isKindOfClass:NSDictionary.class] ? d[@"meta"] : @{}) mutableCopy];
    // Notification V2 payloads may carry routing metadata at the document
    // root (legacy inboxes did), while newer writers place it under `meta`.
    // Normalize both shapes once so every selector can safely consume strings.
    NSArray<NSString *> *metadataKeys = @[
        @"type", @"orderId", @"orderID", @"orderReference", @"threadId",
        @"conversationId", @"conversationThreadID", @"route", @"targetApp",
        @"targetAppId", @"appId", @"requestId", @"contextId", @"sourceApp"
    ];
    for (NSString *key in metadataKeys) {
        NSString *value = PPNotificationMetadataString(normalizedMeta[key]);
        if (value.length == 0) value = PPNotificationMetadataString(d[key]);
        if (value.length > 0) normalizedMeta[key] = value;
    }
    m.meta = normalizedMeta.copy ?: @{};
    m.sourcePath = doc.reference.path ?: @"";
    id ts = d[@"createdAt"];
    if ([ts isKindOfClass:[FIRTimestamp class]]) m.createdAt = ((FIRTimestamp *)ts).dateValue;
    else if ([ts isKindOfClass:[NSDate class]]) m.createdAt = ts;
    else m.createdAt = [NSDate distantPast];
    return m;
}

- (NSDictionary *)toDict {
    return @{
        @"title": self.title ?: @"",
        @"body":  self.body ?: @"",
        @"targetUserID": self.targetUserID ?: [NSNull null],
        @"type": @(self.type),
        @"isRead": @(self.isRead),
        @"meta": self.meta ?: @{},
        @"createdAt": [FIRTimestamp timestampWithDate:self.createdAt ?: [NSDate distantPast]]
    };
}
@end
