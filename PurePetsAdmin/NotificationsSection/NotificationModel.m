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

@implementation NotificationModel
+ (instancetype)fromDoc:(FIRDocumentSnapshot *)doc {
    NotificationModel *m = [NotificationModel new];
    m.nid = doc.documentID;
    NSDictionary *d = doc.data ?: @{};
    m.title = d[@"title"] ?: @"";
    m.body  = d[@"body"] ?: @"";
    m.targetUserID = d[@"targetUserID"];
    m.type = [d[@"type"] integerValue];
    m.isRead = [d[@"isRead"] boolValue];
    m.meta = d[@"meta"] ?: @{};
    m.sourcePath = doc.reference.path ?: @"";
    id ts = d[@"createdAt"];
    if ([ts isKindOfClass:[FIRTimestamp class]]) m.createdAt = ((FIRTimestamp *)ts).dateValue;
    else m.createdAt = [NSDate date];
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
        @"createdAt": [FIRTimestamp timestampWithDate:self.createdAt ?: [NSDate date]]
    };
}
@end
