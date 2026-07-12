//
//  NotificationManager 2.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationManager+Targets.m
#import "NotificationManager+Targets.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

static NSString * const kUsersCollection = @"UsersCol"; // ✅ your collection name

@implementation NotificationManager (Targets)

#pragma mark - Public

- (void)sendToAudience:(PPAudience)audience
                 model:(NotificationModel *)model
            completion:(void(^)(NSError * _Nullable error))completion
{
    if (audience == PPAudienceAllUsers) {
        // Reuse your existing broadcast
        [self sendBroadcast:model completion:completion];
        return;
    }

    // PPAudienceAppUsers -> fetch all app users (adjust filters if you need)
    FIRFirestore *db = [FIRFirestore firestore];
    [[[db collectionWithPath:kUsersCollection] queryLimitedTo:1000] // adjust paging if huge
     getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) { if (completion) completion(error); return; }

        NSMutableArray<NSString *> *userIDs = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            // If you need to exclude admins/moderators, add checks here using doc.data[@"role"]
            [userIDs addObject:doc.documentID];
        }
        [self pp_sendToUserIDs:userIDs model:model completion:completion];
    }];
}

- (void)sendToRoles:(NSArray<NSNumber *> *)roles
              model:(NotificationModel *)model
         completion:(void(^)(NSError * _Nullable error))completion
{
    if (roles.count == 0) { if (completion) completion(nil); return; }

    FIRFirestore *db = [FIRFirestore firestore];

    // Firestore "in" supports up to 10 values; chunk if needed
    NSArray<NSArray<NSNumber *> *> *chunks = [self pp_chunkArray:roles size:10];
    dispatch_group_t group = dispatch_group_create();
    __block NSMutableOrderedSet<NSString *> *allIDs = [NSMutableOrderedSet orderedSet];
    __block NSError *lastError = nil;

    for (NSArray<NSNumber *> *chunk in chunks) {
        dispatch_group_enter(group);
        [[[db collectionWithPath:kUsersCollection]
           queryWhereField:@"role" in:chunk]
         getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) { lastError = error; dispatch_group_leave(group); return; }
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                [allIDs addObject:doc.documentID];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (lastError) { if (completion) completion(lastError); return; }
        [self pp_sendToUserIDs:allIDs.array model:model completion:completion];
    });
}

#pragma mark - Helpers

- (NSArray<NSArray *> *)pp_chunkArray:(NSArray *)array size:(NSUInteger)size {
    if (size == 0 || array.count == 0) return @[array ?: @[]];
    NSMutableArray *chunks = [NSMutableArray array];
    for (NSUInteger i = 0; i < array.count; i += size) {
        NSRange r = NSMakeRange(i, MIN(size, array.count - i));
        [chunks addObject:[array subarrayWithRange:r]];
    }
    return chunks;
}

- (void)pp_sendToUserIDs:(NSArray<NSString *> *)userIDs
                   model:(NotificationModel *)model
              completion:(void(^)(NSError * _Nullable error))completion
{
    if (userIDs.count == 0) { if (completion) completion(nil); return; }

    dispatch_group_t g = dispatch_group_create();
    __block NSError *lastErr = nil;

    for (NSString *uid in userIDs) {
        if (uid.length == 0) continue;
        dispatch_group_enter(g);
        // Reuse your existing per-user API
        [self sendToUser:uid model:model completion:^(NSError * _Nullable error) {
            if (error) lastErr = error;
            dispatch_group_leave(g);
        }];
    }

    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        if (completion) completion(lastErr);
    });
}

@end
