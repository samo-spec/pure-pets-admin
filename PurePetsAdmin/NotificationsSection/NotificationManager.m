//
//  NotificationManager.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//

#import "NotificationManager.h"
#import "PPNotificationsManager.h"

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

@interface PPCombinedNotificationListener : NSObject <FIRListenerRegistration>
@property (nonatomic, copy) NSArray<id<FIRListenerRegistration>> *registrations;
- (instancetype)initWithRegistrations:(NSArray<id<FIRListenerRegistration>> *)registrations;
@end

@implementation PPCombinedNotificationListener

- (instancetype)initWithRegistrations:(NSArray<id<FIRListenerRegistration>> *)registrations {
    self = [super init];
    if (self) {
        _registrations = [registrations copy] ?: @[];
    }
    return self;
}

- (void)remove {
    for (id<FIRListenerRegistration> registration in self.registrations) {
        [registration remove];
    }
}

@end

@implementation NotificationManager

+ (instancetype)shared {
    static NotificationManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [NotificationManager new];
    });
    return shared;
}

- (FIRCollectionReference *)adminCollection {
    return [[[[FIRFirestore firestore] collectionWithPath:@"admin"]
             documentWithPath:@"notifications"]
            collectionWithPath:@"items"];
}

- (FIRCollectionReference *)staffInboxForUser:(NSString *)uid {
    NSString *safeUID = [uid isKindOfClass:NSString.class]
      ? [uid stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
      : @"";
    if (safeUID.length == 0) return nil;
    return [[[[FIRFirestore firestore] collectionWithPath:@"staff_users"]
             documentWithPath:safeUID]
            collectionWithPath:@"inbox"];
}

- (FIRCollectionReference *)inboxForUser:(NSString *)uid {
    FIRCollectionReference *ref = [UsrMgrCls inboxRefForUID:uid];
    if (ref) return ref;
    return [UsrMgrCls inboxRefForCurrentUser];
}

- (NSArray<NotificationModel *> *)mergedNotificationsWithUserItems:(NSArray<NotificationModel *> *)userItems
                                                        staffItems:(NSArray<NotificationModel *> *)staffItems {
    NSMutableDictionary<NSString *, NotificationModel *> *byKey = [NSMutableDictionary dictionary];
    for (NotificationModel *item in userItems ?: @[]) {
        if (![item isKindOfClass:NotificationModel.class]) continue;
        NSString *key = [NSString stringWithFormat:@"%@::%@", item.sourcePath ?: @"UsersCol", item.nid ?: @""];
        byKey[key] = item;
    }
    for (NotificationModel *item in staffItems ?: @[]) {
        if (![item isKindOfClass:NotificationModel.class]) continue;
        NSString *key = [NSString stringWithFormat:@"%@::%@", item.sourcePath ?: @"staff_users", item.nid ?: @""];
        byKey[key] = item;
    }

    NSArray<NotificationModel *> *merged = byKey.allValues;
    return [merged sortedArrayUsingComparator:^NSComparisonResult(NotificationModel * _Nonnull lhs, NotificationModel * _Nonnull rhs) {
        NSDate *leftDate = lhs.createdAt ?: [NSDate distantPast];
        NSDate *rightDate = rhs.createdAt ?: [NSDate distantPast];
        return [rightDate compare:leftDate];
    }];
}

- (FIRCollectionReference *)inboxReferenceForModel:(NotificationModel *)model user:(NSString *_Nullable)uid {
    NSString *safePath = model.sourcePath ?: @"";
    if ([safePath hasPrefix:@"staff_users/"]) {
        return [self staffInboxForUser:uid];
    }
    return [self inboxForUser:uid];
}

#pragma mark - Reads

- (id<FIRListenerRegistration>)observeInboxForUser:(NSString *)uid
                                           handler:(void (^)(NSArray<NotificationModel *> *))handler {
    FIRCollectionReference *userRef = [self inboxForUser:uid];
    FIRCollectionReference *staffRef = [self staffInboxForUser:uid];
    if (!userRef && !staffRef) {
        if (handler) handler(@[]);
        return nil;
    }

    NSMutableArray<id<FIRListenerRegistration>> *registrations = [NSMutableArray array];
    __block NSArray<NotificationModel *> *userItems = @[];
    __block NSArray<NotificationModel *> *staffItems = @[];
    __weak typeof(self) weakSelf = self;
    void (^emitMerged)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !handler) return;
        handler([self mergedNotificationsWithUserItems:userItems staffItems:staffItems]);
    };

    if (userRef) {
        id<FIRListenerRegistration> registration =
        [[userRef queryOrderedByField:@"createdAt" descending:YES]
         addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
            if (error || !snap) {
                userItems = @[];
                emitMerged();
                return;
            }

            NSMutableArray<NotificationModel *> *items = [NSMutableArray arrayWithCapacity:snap.documents.count];
            for (FIRDocumentSnapshot *doc in snap.documents) {
                [items addObject:[NotificationModel fromDoc:doc]];
            }
            userItems = items.copy;
            emitMerged();
        }];
        if (registration) [registrations addObject:registration];
    }

    if (staffRef) {
        id<FIRListenerRegistration> registration =
        [[staffRef queryOrderedByField:@"createdAt" descending:YES]
         addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
            if (error || !snap) {
                staffItems = @[];
                emitMerged();
                return;
            }

            NSMutableArray<NotificationModel *> *items = [NSMutableArray arrayWithCapacity:snap.documents.count];
            for (FIRDocumentSnapshot *doc in snap.documents) {
                [items addObject:[NotificationModel fromDoc:doc]];
            }
            staffItems = items.copy;
            emitMerged();
        }];
        if (registration) [registrations addObject:registration];
    }

    return [[PPCombinedNotificationListener alloc] initWithRegistrations:registrations];
}

- (void)listenInboxForUser:(NSString *)uid handler:(void (^)(NSArray<NotificationModel *> *))handler {
    [self observeInboxForUser:uid handler:handler];
}

- (void)fetchInboxPageForUser:(NSString *)uid
                        limit:(NSInteger)limit
                   startAfter:(FIRDocumentSnapshot *)startAfter
                   completion:(PPNotifPage)completion {
    FIRCollectionReference *userRef = [self inboxForUser:uid];
    FIRCollectionReference *staffRef = [self staffInboxForUser:uid];
    if (!userRef && !staffRef) {
        if (completion) completion(@[], nil, [self.class pp_notificationErrorWithMessage:@"User inbox reference not found."]);
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    __block NSArray<NotificationModel *> *userItems = @[];
    __block NSArray<NotificationModel *> *staffItems = @[];
    __block NSError *lastError = nil;
    NSInteger safeLimit = MAX(limit, 1);

    void (^fetchBlock)(FIRCollectionReference *, BOOL) = ^(FIRCollectionReference *ref, BOOL isStaff) {
        if (!ref) return;
        dispatch_group_enter(group);
        FIRQuery *query = [ref queryOrderedByField:@"createdAt" descending:YES];
        query = [query queryLimitedTo:safeLimit];
        if (startAfter) query = [query queryStartingAfterDocument:startAfter];
        [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error || !snapshot) {
                lastError = error;
                dispatch_group_leave(group);
                return;
            }

            NSMutableArray<NotificationModel *> *items = [NSMutableArray arrayWithCapacity:snapshot.documents.count];
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                [items addObject:[NotificationModel fromDoc:doc]];
            }
            if (isStaff) {
                staffItems = items.copy;
            } else {
                userItems = items.copy;
            }
            dispatch_group_leave(group);
        }];
    };

    fetchBlock(userRef, NO);
    fetchBlock(staffRef, YES);

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (lastError) {
            if (completion) completion(@[], nil, lastError);
            return;
        }
        NSArray<NotificationModel *> *merged = [self mergedNotificationsWithUserItems:userItems staffItems:staffItems];
        NSArray<NotificationModel *> *page = (merged.count > safeLimit) ? [merged subarrayWithRange:NSMakeRange(0, safeLimit)] : merged;
        if (completion) completion(page, nil, nil);
    });
}

#pragma mark - Writes

- (void)markRead:(NotificationModel *)model
         forUser:(NSString *_Nullable)uid
      completion:(void (^)(NSError * _Nullable))completion {
    FIRCollectionReference *ref = [self inboxReferenceForModel:model user:uid];
    if (!ref) {
        if (completion) completion([self.class pp_notificationErrorWithMessage:@"Unable to mark notification as read."]);
        return;
    }
    [[ref documentWithPath:model.nid] updateData:@{@"isRead" : @YES} completion:completion];
}

- (void)deleteNotification:(NotificationModel *)model
                   forUser:(NSString *)uid
                completion:(void (^)(NSError * _Nullable))completion {
    FIRCollectionReference *ref = [self inboxReferenceForModel:model user:uid];
    if (!ref) {
        if (completion) completion([self.class pp_notificationErrorWithMessage:@"Unable to delete notification."]);
        return;
    }
    [[ref documentWithPath:model.nid] deleteDocumentWithCompletion:completion];
}

- (void)sendToUser:(NSString *)uid
             model:(NotificationModel *)model
        completion:(void (^)(NSError * _Nullable))completion {
    FIRCollectionReference *ref = [self inboxForUser:uid];
    if (!ref) {
        if (completion) completion([self.class pp_notificationErrorWithMessage:@"Unable to resolve inbox for user."]);
        return;
    }

    NSMutableDictionary *payload = model.toDict.mutableCopy;
    payload[@"isRead"] = @NO;
    [[ref documentWithAutoID] setData:payload completion:completion];
}

- (void)sendBroadcast:(NotificationModel *)model completion:(void (^)(NSError * _Nullable))completion {
    [[[self adminCollection] documentWithAutoID] setData:model.toDict completion:completion];
}

#pragma mark - Cloud function wrappers

+ (void)sendToUserWithUID:(NSString *)uid
                    title:(NSString *)title
                     body:(NSString *)body
                     data:(NSDictionary *)data
               completion:(void (^)(NSDictionary *, NSError *))completion {
    [PPNotificationsManager sendToUser:uid title:title body:body data:data completion:completion];
}

+ (void)sendToUserWithToken:(NSString *)token
                      title:(NSString *)title
                       body:(NSString *)body
                       data:(NSDictionary *)data
                 completion:(void (^)(NSDictionary *, NSError *))completion {
    [PPNotificationsManager sendToToken:token title:title body:body data:data completion:completion];
}

+ (void)sendToUsersWithUIDs:(NSArray<NSString *> *)uids
                      title:(NSString *)title
                       body:(NSString *)body
                       data:(NSDictionary *)data
                 completion:(void (^)(NSDictionary *, NSError *))completion {
    [PPNotificationsManager sendToUsers:uids title:title body:body data:data completion:completion];
}

+ (void)sendToAllUsersWithTitle:(NSString *)title
                           body:(NSString *)body
                           data:(NSDictionary *)data
                     completion:(void (^)(NSDictionary *, NSError *))completion {
    [PPNotificationsManager sendToAllUsersWithTitle:title body:body data:data completion:completion];
}

+ (void)sendToAdminsWithTitle:(NSString *)title
                         body:(NSString *)body
                         data:(NSDictionary *)data
                   completion:(void (^)(NSDictionary *, NSError *))completion {
    [PPNotificationsManager sendToAdminsWithTitle:title body:body data:data completion:completion];
}

+ (void)sendToAllWithTitle:(NSString *)title
                      body:(NSString *)body
                      data:(NSDictionary *)data
                completion:(void (^)(NSDictionary *, NSError *))completion {
    [PPNotificationsManager sendToAllWithTitle:title body:body data:data completion:completion];
}

+ (NSError *)pp_notificationErrorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"NotificationManager"
                               code:404
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Notification operation failed."}];
}

@end
