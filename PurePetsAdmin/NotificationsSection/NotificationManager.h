//
//  NotificationManager.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationManager.h
#import <Foundation/Foundation.h>
#import "NotificationModel.h"
NS_ASSUME_NONNULL_BEGIN

@class FIRDocumentSnapshot;
@class FIRCollectionReference;
@protocol FIRListenerRegistration;

typedef void(^PPNotifPage)(NSArray<NotificationModel *> *items, FIRDocumentSnapshot *_Nullable lastDoc, NSError *_Nullable err);

@interface NotificationManager : NSObject
+ (instancetype)shared;

// paths: admin notifications collection (global) and per-user inbox
- (FIRCollectionReference *)adminCollection;     // /admin/notifications/items
- (FIRCollectionReference *)inboxForUser:(NSString *)uid; // /users/{uid}/inbox

// reads
- (id<FIRListenerRegistration> _Nullable)observeInboxForUser:(NSString *)uid
                                                     handler:(void(^)(NSArray<NotificationModel *> *items))handler;

- (void)listenInboxForUser:(NSString *)uid
                   handler:(void(^)(NSArray<NotificationModel *> *items))handler;

- (void)fetchInboxPageForUser:(NSString *)uid
                        limit:(NSInteger)limit
                     startAfter:(FIRDocumentSnapshot *_Nullable)startAfter
                      completion:(PPNotifPage)completion;

// writes
- (void)markRead:(NotificationModel *)model forUser:(NSString *_Nullable)uid completion:(void(^_Nullable)(NSError * _Nullable err ))completion;
- (void)deleteNotification:(NotificationModel *)model forUser:(NSString *)uid completion:(void(^)(NSError *_Nullable err))completion;

// send (compose)
- (void)sendToUser:(NSString *)uid model:(NotificationModel *)model completion:(void(^)(NSError *_Nullable err))completion;
- (void)sendBroadcast:(NotificationModel *)model completion:(void(^)(NSError *_Nullable err))completion; // e.g., write to admin collection or Cloud Function triggers FCM



/// Send to one user (by UID or token)
+ (void)sendToUserWithUID:(NSString *)uid
                    title:(NSString *)title
                     body:(NSString *)body
                     data:(NSDictionary *)data
               completion:(void (^)(NSDictionary *response, NSError *error))completion;

+ (void)sendToUserWithToken:(NSString *)token
                      title:(NSString *)title
                       body:(NSString *)body
                       data:(NSDictionary *)data
                 completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to multiple users (UIDs)
+ (void)sendToUsersWithUIDs:(NSArray<NSString *> *)uids
                      title:(NSString *)title
                       body:(NSString *)body
                       data:(NSDictionary *)data
                 completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to all users
+ (void)sendToAllUsersWithTitle:(NSString *)title
                           body:(NSString *)body
                           data:(NSDictionary *)data
                     completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to all admins
+ (void)sendToAdminsWithTitle:(NSString *)title
                         body:(NSString *)body
                         data:(NSDictionary *)data
                   completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to everyone (users + admins)
+ (void)sendToAllWithTitle:(NSString *)title
                      body:(NSString *)body
                      data:(NSDictionary *)data
                completion:(void (^)(NSDictionary *response, NSError *error))completion;



@end
NS_ASSUME_NONNULL_END
