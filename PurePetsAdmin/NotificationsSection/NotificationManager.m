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
@import FirebaseFunctions;

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

#pragma mark - Reads

- (id<FIRListenerRegistration>)observeInboxForUser:(NSString *)uid
                                           handler:(void (^)(NSArray<NotificationModel *> *))handler {
    return [self observeInboxForUser:uid stateHandler:^(NSArray<NotificationModel *> *items, __unused NSError *error) {
        if (handler) handler(items);
    }];
}

- (id<FIRListenerRegistration>)observeInboxForUser:(NSString *)uid
                                       stateHandler:(PPInboxObserverStateHandler)handler {
    FIRCollectionReference *staffRef = [self staffInboxForUser:uid];
    if (!staffRef) {
        if (handler) {
            handler(@[], [self.class pp_notificationErrorWithMessage:@"Staff inbox reference not found."]);
        }
        return nil;
    }

    return [[staffRef queryOrderedByField:@"createdAt" descending:YES]
            addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (error || !snap) {
            NSError *resolvedError = error ?: [self.class pp_notificationErrorWithMessage:@"Staff inbox snapshot unavailable."];
            if (handler) handler(@[], resolvedError);
            return;
        }
        NSMutableArray<NotificationModel *> *items = [NSMutableArray arrayWithCapacity:snap.documents.count];
        for (FIRDocumentSnapshot *doc in snap.documents) {
            [items addObject:[NotificationModel fromDoc:doc]];
        }
        if (handler) handler(items.copy, nil);
    }];
}

- (void)listenInboxForUser:(NSString *)uid handler:(void (^)(NSArray<NotificationModel *> *))handler {
    [self observeInboxForUser:uid handler:handler];
}

- (void)fetchInboxPageForUser:(NSString *)uid
                        limit:(NSInteger)limit
                   startAfter:(FIRDocumentSnapshot *)startAfter
                   completion:(PPNotifPage)completion {
    FIRCollectionReference *staffRef = [self staffInboxForUser:uid];
    if (!staffRef) {
        if (completion) completion(@[], nil, [self.class pp_notificationErrorWithMessage:@"Staff inbox reference not found."]);
        return;
    }

    NSInteger safeLimit = MAX(limit, 1);
    FIRQuery *query = [[staffRef queryOrderedByField:@"createdAt" descending:YES] queryLimitedTo:safeLimit];
    if (startAfter) query = [query queryStartingAfterDocument:startAfter];
    [query getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error || !snapshot) {
            NSError *resolvedError = error ?: [self.class pp_notificationErrorWithMessage:@"Staff inbox page unavailable."];
            if (completion) completion(@[], nil, resolvedError);
            return;
        }
        NSMutableArray<NotificationModel *> *items = [NSMutableArray arrayWithCapacity:snapshot.documents.count];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [items addObject:[NotificationModel fromDoc:doc]];
        }
        if (completion) completion(items.copy, snapshot.documents.lastObject, nil);
    }];
}

#pragma mark - Writes

- (void)markRead:(NotificationModel *)model
         forUser:(NSString *_Nullable)uid
      completion:(void (^)(NSError * _Nullable))completion {
    (void)uid;
    if (![model isKindOfClass:NotificationModel.class] || model.nid.length == 0) {
        if (completion) completion([self.class pp_notificationErrorWithMessage:@"Staff notification id is required."]);
        return;
    }
    NSString *sourcePath = [model.sourcePath stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![sourcePath hasPrefix:@"staff_users/"]) {
        if (completion) completion([self.class pp_notificationErrorWithMessage:@"Staff notification source is required."]);
        return;
    }
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"staffNotificationInboxReadAck"];
    [callable callWithObject:@{@"notificationId": model.nid} completion:^(__unused FIRHTTPSCallableResult *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    }];
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
