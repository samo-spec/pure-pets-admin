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
typedef void(^PPInboxObserverStateHandler)(NSArray<NotificationModel *> *items, NSError *_Nullable error);

@interface NotificationManager : NSObject
+ (instancetype)shared;

// paths: admin notifications collection (global) and per-user inbox
- (FIRCollectionReference *)adminCollection;     // /admin/notifications/items
- (FIRCollectionReference *)inboxForUser:(NSString *)uid; // customer destination used only when composing

// reads
- (id<FIRListenerRegistration> _Nullable)observeInboxForUser:(NSString *)uid
                                                     handler:(void(^)(NSArray<NotificationModel *> *items))handler;

/// Error-aware observer for the canonical staff inbox. The items-only overload
/// remains available for legacy callers that cannot surface a listener error.
- (id<FIRListenerRegistration> _Nullable)observeInboxForUser:(NSString *)uid
                                                stateHandler:(PPInboxObserverStateHandler)handler;

- (void)listenInboxForUser:(NSString *)uid
                   handler:(void(^)(NSArray<NotificationModel *> *items))handler;

- (void)fetchInboxPageForUser:(NSString *)uid
                        limit:(NSInteger)limit
                     startAfter:(FIRDocumentSnapshot *_Nullable)startAfter
                      completion:(PPNotifPage)completion;

// writes
- (void)markRead:(NotificationModel *)model forUser:(NSString *_Nullable)uid completion:(void(^_Nullable)(NSError * _Nullable err ))completion;

// send (compose)
- (void)sendToUser:(NSString *)uid model:(NotificationModel *)model completion:(void(^)(NSError *_Nullable err))completion;
- (void)sendBroadcast:(NotificationModel *)model completion:(void(^)(NSError *_Nullable err))completion; // e.g., write to admin collection or Cloud Function triggers FCM



/// Send to one user (by UID or token)
+ (void)sendToUserWithUID:(NSString *)uid
                    title:(NSString *)title
                    body:(NSString *)body
               completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to multiple users (UIDs)
+ (void)sendToUsersWithUIDs:(NSArray<NSString *> *)uids
                      title:(NSString *)title
                      body:(NSString *)body
                completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to all users
+ (void)sendToAllUsersWithTitle:(NSString *)title
                           body:(NSString *)body
                     completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to all admins
+ (void)sendToAdminsWithTitle:(NSString *)title
                         body:(NSString *)body
                   completion:(void (^)(NSDictionary *response, NSError *error))completion;

/// Send to everyone (users + admins)
+ (void)sendToAllWithTitle:(NSString *)title
                      body:(NSString *)body
                completion:(void (^)(NSDictionary *response, NSError *error))completion;



@end
NS_ASSUME_NONNULL_END
