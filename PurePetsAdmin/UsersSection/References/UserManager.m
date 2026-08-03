
// In UserManager.m
// NOTE: uses collection name "UsersCol" as per your project

#import "UserManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPRolePermission.h"
#import "Lottie.h"
#import "UIImageView+WebCache.h"
#import "AppDelegate.h"
@import Firebase;
@import FirebaseAuth;

@interface AppDelegate (PPNotificationV2LogoutBarrier)
- (void)pp_beginNotificationV2LogoutBarrierWithCompletion:(dispatch_block_t)completion;
- (void)pp_endNotificationV2LogoutBarrier;
- (void)pp_abortNotificationV2LogoutBarrierAndRefreshForReason:(NSString *)reason;
@end

static AppDelegate *PPAdminNotificationV2AppDelegate(void)
{
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    return [delegate isKindOfClass:AppDelegate.class] ? (AppDelegate *)delegate : nil;
}

static UIViewController *PPAdminUserManagerTopViewController(void)
{
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
        if (window) break;
    }

    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        controller = ((UINavigationController *)controller).topViewController ?: controller;
    } else if ([controller isKindOfClass:UITabBarController.class]) {
        controller = ((UITabBarController *)controller).selectedViewController ?: controller;
    }
    return controller;
}

NSString * const UserManagerAuthStateDidChangeNotification = @"UserManagerAuthStateDidChangeNotification";
NSString * const LanguageDidChangeNotification = @"LanguageDidChangeNotification";

@interface UserManager ()
@property (nonatomic, strong) NSArray<UserModel *> *cachedUsers;
@property (nonatomic, strong) NSDate *lastUsersFetchAt;

@property (nonatomic, strong) NSCache<NSString *, UserModel *> *userCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *userCacheAges;
@property (nonatomic, strong) dispatch_queue_t cacheQueue; // thread-safety for disk ops
@property (nonatomic, assign) BOOL signOutInProgress;
@property (nonatomic, strong) NSMutableArray *pendingSignOutCompletions;
- (void)p_queryUsersColField:(NSString *)field
                     equalTo:(NSString *)value
          tryServerThenCache:(BOOL)serverFirst
                  completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion;
- (FIRDocumentReference *)_userDoc:(NSString *)uid;
- (void)pp_finishSignOutWithError:(NSError * _Nullable)error;

@end



@implementation UserManager

- (instancetype)init {
    if ((self = [super init])) {
        
        
        _userCache = [NSCache new];
        _userCache.countLimit = 500;

        _userCacheAges = [NSMutableDictionary new];
        _cacheQueue = dispatch_queue_create("com.purepets.usercache.q", DISPATCH_QUEUE_SERIAL);

        _userCacheTTL = 5 * 60; // 5 minutes default
    }
    return self;
}

- (void)fetchAdminWithUID:(NSString *)uid cachePolicy:(PPUserCachePolicy)policy completion:(void (^)(UserModel * _Nullable, NSError * _Nullable))completion
{
    NSString *resolvedUID = PPSafeString(uid);
    if (resolvedUID.length == 0) {
        resolvedUID = PPSafeString(self.currentUser.uid.length ? self.currentUser.uid : self.currentUser.ID);
    }
    if (resolvedUID.length == 0) {
        resolvedUID = PPSafeString([FIRAuth auth].currentUser.uid);
    }

    if (!resolvedUID.length) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"UserManager"
                                                code:-1
                                            userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]);
        }
        return;
    }

    switch (policy) {
        case PPUserCachePolicyCacheOnly: {
            UserModel *cached = [self.userCache objectForKey:resolvedUID];
            if (!cached) {
                cached = [self p_readUserFromDisk:resolvedUID];
            }
            if (cached) {
                [self p_cacheUser:cached];
                self.currentUser = cached;
            }
            if (completion) completion(cached, nil);
            return;
        }
        case PPUserCachePolicyServerOnly: {
            [self p_queryUsersColField:@"uid" equalTo:resolvedUID tryServerThenCache:NO completion:^(UserModel * _Nullable user, NSError * _Nullable error) {
                if (error) {
                    if (completion) completion(nil, error);
                    return;
                }
                if (user) {
                    [self p_cacheUser:user];
                    self.currentUser = user;
                    if (completion) completion(user, nil);
                    return;
                }

                [[self _userDoc:resolvedUID] getDocumentWithSource:FIRFirestoreSourceServer completion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable docError) {
                    if (docError) {
                        if (completion) completion(nil, docError);
                        return;
                    }
                    if (!snapshot.exists) {
                        if (completion) completion(nil, nil);
                        return;
                    }

                    UserModel *docUser = [[UserModel alloc] initWithSnapshot:snapshot];
                    if (docUser) {
                        [self p_cacheUser:docUser];
                        self.currentUser = docUser;
                    }
                    if (completion) completion(docUser, nil);
                }];
            }];
            return;
        }
        case PPUserCachePolicyMemoryFirstThenServer:
        default:
            [self loadUserByUIDOrID:resolvedUID completion:completion];
            return;
    }
}

- (void)loadUserByUIDOrID:(NSString *)uid
               completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion
{
    
    
    [self p_queryUsersColField:@"uid" equalTo:uid tryServerThenCache:YES completion:^(UserModel * _Nullable user, NSError * _Nullable error) {
       
        if (error) { if (completion) completion(nil, error); return; }
        if (!user) {
            [[self _userDoc:uid] getDocumentWithSource:FIRFirestoreSourceServer completion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable docError) {
                if (docError) {
                    if (completion) completion(nil, docError);
                    return;
                }
                if (!snapshot.exists) {
                    if (completion) completion(nil, nil);
                    return;
                }

                UserModel *docUser = [[UserModel alloc] initWithSnapshot:snapshot];
                if (docUser) {
                    [self p_cacheUser:docUser];
                    self.currentUser = docUser;
                }
                if (completion) completion(docUser, nil);
            }];
            return;
        }
        [self p_cacheUser:user];
        self.currentUser = user;

        DLog(@"[Fetch Admin]query self.currentUser ID == %@", self.currentUser.ID);
        DLog(@"query user m == %@", user.ID);
        
        if (completion) completion(user, nil);
    }];
}

/// Private helper that queries UsersCol where {field} == value.
/// If no match, it continues to try field "ID" (only when field was "uid").
/// `tryServerThenCache` performs server fetch, then falls back to cache on error.
- (void)p_queryUsersColField:(NSString *)field
                    equalTo:(NSString *)value
         tryServerThenCache:(BOOL)serverFirst
                 completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion
{
    NSString *cleanValue = PPSafeString(value);
    if (cleanValue.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"UserManager"
                                                code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Missing query value"}]);
        }
        return;
    }
    
    UserModel *restoredUser = [self p_readUserFromDisk:cleanValue];
    if(restoredUser)
    {
        if (completion) completion(restoredUser, nil);
        return;
    }
    
    FIRFirestore *db =   [FIRFirestore firestore];
    FIRQuery *q = [[[db collectionWithPath:@"UsersCol"] queryWhereField:field isEqualTo:cleanValue] queryLimitedTo:1];

    void (^handleSnap)(FIRQuerySnapshot *, NSError *) = ^(FIRQuerySnapshot *snap, NSError *err){
        if (err) {
            DLog(@"query %@ == %@ error: %@", field, cleanValue, err.localizedDescription);
            if (serverFirst) {
                // Try cache once
                [q getDocumentsWithSource:FIRFirestoreSourceCache completion:^(FIRQuerySnapshot * _Nullable csnap, NSError * _Nullable cerr) {
                    if (!cerr && csnap.documents.count > 0) {
                        FIRDocumentSnapshot *doc = csnap.documents.firstObject;
                        UserModel *u = [[UserModel alloc] initWithSnapshot:doc];
                        [self p_cacheUser:u];
                        DLog(@"✅ query cache hit %@ == %@", field, value);
                        if (completion) completion(u, nil);
                    } else {
                        // If we were checking 'uid' and failed, fall back to 'ID'
                        if ([field isEqualToString:@"uid"]) {
                            DLog(@"fallback: trying field ID == %@", cleanValue);
                            [self p_queryUsersColField:@"ID" equalTo:cleanValue tryServerThenCache:YES completion:completion];
                        } else {
                            if (completion) completion(nil, err ?: cerr);
                        }
                    }
                }];
            } else {
                if (completion) completion(nil, err);
            }
            return;
        }

        if (snap.documents.count > 0) {
            FIRDocumentSnapshot *doc = snap.documents.firstObject;
            UserModel *u = [[UserModel alloc] initWithSnapshot:doc];
            [self p_cacheUser:u];
            DLog(@"✅ query match %@ == %@ (docID=%@)", field, cleanValue, doc.documentID);
            if (completion) completion(u, nil);
        } else {
            if ([field isEqualToString:@"uid"]) {
                // 2) Not found by 'uid' → try 'ID'
                DLog(@"no match for uid == %@ → try ID", cleanValue);
                [self p_queryUsersColField:@"ID" equalTo:cleanValue tryServerThenCache:serverFirst completion:completion];
            } else {
                DLog(@"no match for %@ == %@", field, cleanValue);
                if (completion) completion(nil, nil);
            }
        }
    };

    if (serverFirst) {
        DLog(@"try: query %@ == %@ (server)", field, cleanValue);
        [q getDocumentsWithSource:FIRFirestoreSourceServer completion:handleSnap];
    } else {
        [q getDocumentsWithCompletion:handleSnap];
    }
}



- (void)fetchUserWithUID:(NSString *)uid
              completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion
{
    if (!uid.length) {
        if (completion) completion(nil, [NSError errorWithDomain:@"UserManager"
                                                            code:-1
                                                        userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]);
        return;
    }
    
    __block BOOL didReturn = NO;
        void (^returnOnce)(UserModel *, NSError *) = ^(UserModel *u, NSError *e){
            if (didReturn) return;
            didReturn = YES;
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(u,e); });
        };
    
    
    [[self _userDoc:uid] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable err) {
        if (err) { if (completion) completion(nil, err); return; }
        if (!snapshot.exists) { if (completion) completion(nil, nil); return; }
        UserModel *m = [[UserModel alloc] initWithSnapshot:snapshot];
        [self p_cacheUser:m];
        if (completion) completion(m, nil);
    }];
}

#pragma mark - Cache helpers

- (void)p_cacheUser:(UserModel *)user {
    if (!user) { DLog(@"p_cacheUser: user=nil (skip)"); return; }
    NSString *uid = (user.ID.length ? user.ID : user.uid);
    if (uid.length == 0) { DLog(@"p_cacheUser: uid is empty (skip)"); return; }

    // Memory
    [self.userCache setObject:user forKey:uid];
    self.userCacheAges[uid] = [NSDate date];
    DLog(@"p_cacheUser: ✅ memory cached uid=%@ (age now)", uid);

    // Disk (async)
    dispatch_async(self.cacheQueue, ^{
        DLog(@"p_cacheUser: ⌛️ disk write begin uid=%@", uid);
        [self p_writeUserToDisk:user forUID:uid];
        [self p_writeUserAgeToDisk:[NSDate date] forUID:uid];
        DLog(@"p_cacheUser: 💾 disk write end uid=%@", uid);
    });
}

- (NSString *)p_userCacheDir {
    NSArray<NSURL *> *dirs = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
    NSURL *dir = dirs.firstObject;
    NSURL *pp = [dir URLByAppendingPathComponent:@"PurePetsUserCache" isDirectory:YES];

    NSError *mkErr = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:pp withIntermediateDirectories:YES attributes:nil error:&mkErr];
    if (mkErr) { DLog(@"p_cacheUser: p_userCacheDir: ❌ createDirectory error=%@", mkErr); }

    // Avoid iCloud backup
    NSError *exErr = nil;
    BOOL ok = [pp setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&exErr];
    if (!ok || exErr) { DLog(@"p_cacheUser: p_userCacheDir: ⚠️ exclude-from-backup failed: %@", exErr); }

    DLog(@"p_cacheUser: p_userCacheDir: path=%@", pp.path);
    return pp.path;
}

- (NSString *)p_userPathForUID:(NSString *)uid {
    NSString *p = [[self p_userCacheDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.archive", uid]];
    return p;
}

- (NSString *)p_agePathForUID:(NSString *)uid {
    NSString *p = [[self p_userCacheDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.age", uid]];
    return p;
}

+ (NSDictionary *)sanitizeUserDict:(NSDictionary *)dict {
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:NSNull.class]) {
            clean[key] = @"";
        } else {
            clean[key] = obj;
        }
    }];
    return clean;
}



// Write to disk
- (void)p_writeUserToDisk:(UserModel *)user forUID:(NSString *)uid {
    if (!user || uid.length == 0) { DLog(@"p_cacheUser: p_writeUserToDisk: invalid args (user=%@ uid=%@)", user ? @"non-nil" : @"nil", uid); return; }
    NSString *path = [self p_userPathForUID:uid];
    NSError *err = nil;
    //NSDictionary *safe = [UserManager sanitizeUserDict:user.toDictionary];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:user
                                         requiringSecureCoding:YES
                                                         error:&err];
    
    if (!data || err) {
        DLog(@"p_cacheUser: p_writeUserToDisk: ❌ archive fail uid=%@ err=%@", uid, err);
        return;
    }

    BOOL ok = [data writeToFile:path atomically:YES];
    if (ok) {
        DLog(@"p_cacheUser: p_writeUserToDisk: ✅ wrote %lu bytes → %@", (unsigned long)data.length, path);
    } else {
        DLog(@"p_cacheUser: p_writeUserToDisk: ❌ write failed → %@", path);
    }
}

- (UserModel *)p_readUserFromDisk:(NSString *)uid {
    if (!uid.length) return nil;
    
    NSString *path = [self p_userPathForUID:uid];
    NSError *err = nil;
    NSData *userData = [NSData dataWithContentsOfFile:path];
    UserModel *u = [NSKeyedUnarchiver unarchivedObjectOfClass:UserModel.class
                                                     fromData:userData
                                                        error:&err];
    if (!u) {
        // Legacy fallback
        NSSet *allowed = [NSSet setWithObjects:
                          [NSDictionary class],
                          [NSMutableDictionary class],
                          [NSString class],
                          [NSNumber class],
                          nil];

        NSDictionary *dict = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowed
                                                                 fromData:userData
                                                                    error:nil];
        if ([dict isKindOfClass:[NSDictionary class]]) {
            DLog(@"[UserManager] ⚠️ Found legacy dict cache, migrating…");
            u = [[UserModel alloc] initWithDict:dict];
            if (u) {
                [self p_writeUserToDisk:u forUID:uid]; // overwrite properly
            }
        }
    }


    
    return u;
}


- (void)p_writeUserAgeToDisk:(NSDate *)date forUID:(NSString *)uid {
    if (!date) { DLog(@"p_cacheUser: p_writeUserAgeToDisk: date=nil (skip)"); return; }
    NSTimeInterval t = date.timeIntervalSince1970;
    NSData *d = [NSData dataWithBytes:&t length:sizeof(t)];
    NSString *path = [self p_agePathForUID:uid];
    BOOL ok = [d writeToFile:path atomically:YES];
    if (ok) {
        DLog(@"p_writeUserAgeToDisk: ✅ wrote age=%.0fs since 1970 → %@", t, path);
    } else {
        DLog(@"p_writeUserAgeToDisk: ❌ write failed → %@", path);
    }
}

- (NSDate *)p_readUserAgeFromDisk:(NSString *)uid {
    NSString *path = [self p_agePathForUID:uid];
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d || d.length != sizeof(NSTimeInterval)) {
        DLog(@"p_cacheUser: p_readUserAgeFromDisk: (nil) no/invalid age file for uid=%@ at %@", uid, path);
        return nil;
    }
    NSTimeInterval t = 0;
    [d getBytes:&t length:sizeof(t)];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:t];
    DLog(@"p_cacheUser: p_readUserAgeFromDisk: ✅ age file read uid=%@ (age=%.1fs old)", uid, [[NSDate date] timeIntervalSinceDate:date]);
    return date;
}

#pragma mark - Public cache maintenance

- (void)invalidateUserCacheForUID:(NSString *)uid {
    if (!uid.length) { DLog(@"p_cacheUser: invalidateUserCacheForUID: empty uid"); return; }

    [self.userCache removeObjectForKey:uid];
    [self.userCacheAges removeObjectForKey:uid];
    DLog(@"p_cacheUser: invalidateUserCacheForUID: 🧹 memory cleared uid=%@", uid);

    dispatch_async(self.cacheQueue, ^{
        NSError *e1 = nil, *e2 = nil;
        NSString *up = [self p_userPathForUID:uid];
        NSString *ap = [self p_agePathForUID:uid];

        BOOL ok1 = [[NSFileManager defaultManager] removeItemAtPath:up error:&e1];
        BOOL ok2 = [[NSFileManager defaultManager] removeItemAtPath:ap error:&e2];

        DLog(@"p_cacheUser: invalidateUserCacheForUID: disk user=%@ (%@) age=%@ (%@)",
             ok1 ? @"✅ removed" : @"—",
             e1 ? e1.localizedDescription : @"",
             ok2 ? @"✅ removed" : @"—",
             e2 ? e2.localizedDescription : @"");
    });
}

- (void)clearUserCache {
    [self.userCache removeAllObjects];
    [self.userCacheAges removeAllObjects];
    DLog(@"p_cacheUser: clearUserCache: 🧹 memory caches cleared");

    dispatch_async(self.cacheQueue, ^{
        NSString *dir = [self p_userCacheDir];
        NSError *lsErr = nil;
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:&lsErr];
        if (lsErr) {
            DLog(@"p_cacheUser: clearUserCache: ❌ list dir error=%@", lsErr);
            return;
        }
        NSUInteger removed = 0;
        for (NSString *f in files) {
            NSError *rmErr = nil;
            BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:f] error:&rmErr];
            if (ok) removed++;
            else DLog(@"p_cacheUser: clearUserCache: ⚠️ remove %@ failed: %@", f, rmErr);
        }
        DLog(@"p_cacheUser: clearUserCache: 💾 removed %lu files from %@", (unsigned long)removed, dir);
    });
}


+ (instancetype)shared {
    static UserManager *mgr;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mgr = [UserManager new]; });
    return mgr;
}

#pragma mark - Real-time Listener

- (void)startListeningUserWithUID:(NSString *)uid
                         onChange:(void(^)(UserModel * _Nullable user))onChange {
    [self stopListening]; // avoid duplicate listeners
    
    if (!uid.length) return;
    
    FIRDocumentReference *doc = [[[FIRFirestore firestore] collectionWithPath:@"UsersCol"] documentWithPath:uid];
    self.userListener = [doc addSnapshotListener:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            DLog(@"❌ Failed to listen user: %@", error.localizedDescription);
            return;
        }
        if (!snapshot.exists) {
            DLog(@"⚠️ User %@ not found during listen", uid);
            return;
        }
        
        self.currentUser = [[UserModel alloc] initWithSnapshot:snapshot];
        DLog(@"🔄 User updated: %@", self.currentUser.UserName);
        if (onChange) onChange(self.currentUser);
    }];
}

- (void)stopListening {
    if (self.userListener) {
        [self.userListener remove];
        self.userListener = nil;
        DLog(@"🛑 Stopped user listener");
    }
}

#pragma mark - Create if not exists

- (void)createUserIfNotExistsWithUID:(NSString *)uid
                                data:(NSDictionary *)data
                          completion:(void(^)(NSError * _Nullable error))completion {
    if (!uid.length) {
        if (completion) completion([NSError errorWithDomain:@"UserManager"
                                                       code:400
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Missing UID"}]);
        return;
    }
    
    FIRDocumentReference *doc = [[[FIRFirestore firestore] collectionWithPath:@"UsersCol"] documentWithPath:uid];
    [doc getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        if (snapshot.exists) {
            DLog(@"ℹ️ User %@ already exists", uid);
            if (completion) completion(nil);
            return;
        }
        
        NSMutableDictionary *dict = [data mutableCopy] ?: [NSMutableDictionary dictionary];
        dict[@"ID"] = uid;
        dict[@"uid"] = uid;
        dict[@"UserName"] = PPSafeString(dict[@"UserName"]);
        dict[@"UserEmail"] = PPSafeString(dict[@"UserEmail"]);
        NSString *existingDisplayName = PPSafeString(dict[@"displayName"]);
        NSString *existingEmail = PPSafeString(dict[@"email"]);
        dict[@"displayName"] = existingDisplayName.length ? existingDisplayName : PPSafeString(dict[@"UserName"]);
        dict[@"email"] = existingEmail.length ? existingEmail : PPSafeString(dict[@"UserEmail"]);
        dict[@"isAdmin"] = @([dict[@"isAdmin"] boolValue]);
        dict[@"isSuperAdmin"] = @([dict[@"isSuperAdmin"] boolValue]);
        dict[@"isBlocked"] = @([dict[@"isBlocked"] boolValue]);
        BOOL emailVerified = [dict[@"emailVerified"] boolValue];
        dict[@"emailVerified"] = @(emailVerified);
        dict[@"verified"] = @([dict[@"verified"] boolValue] || emailVerified);
        dict[@"role"] = dict[@"role"] ?: @(UserRoleUser);
        dict[@"createdAt"] = dict[@"createdAt"] ?: [FIRFieldValue fieldValueForServerTimestamp];
        dict[@"loginDate"] = [FIRFieldValue fieldValueForServerTimestamp];
        dict[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        
        [doc setData:dict completion:^(NSError * _Nullable error) {
            if (error) {
                DLog(@"❌ Failed to create user: %@", error.localizedDescription);
            } else {
                DLog(@"✅ User %@ created", uid);
            }
            if (completion) completion(error);
        }];
    }];
}

#pragma mark - Sign Out

- (void)signOut {
    [self signOutWithCompletion:nil];
}

- (void)signOutWithCompletion:(void (^)(NSError * _Nullable))completion {
    if (completion) {
        if (!self.pendingSignOutCompletions) {
            self.pendingSignOutCompletions = [NSMutableArray array];
        }
        [self.pendingSignOutCompletions addObject:[completion copy]];
    }
    if (self.signOutInProgress) {
        return;
    }
    self.signOutInProgress = YES;

    NSString *userID = PPSafeString([FIRAuth auth].currentUser.uid);
    if (userID.length == 0) {
        userID = PPSafeString(self.currentUser.uid.length > 0 ? self.currentUser.uid : self.currentUser.ID);
    }

    AppDelegate *notificationAppDelegate = PPAdminNotificationV2AppDelegate();
    __weak typeof(self) weakSelf = self;
    dispatch_block_t beginDeactivationAfterRegistrationSettles = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        __block BOOL didContinueAfterDeactivation = NO;
        void (^continueAfterDeactivation)(NSError * _Nullable) = ^(NSError * _Nullable deactivateError) {
            if (didContinueAfterDeactivation) return;
            didContinueAfterDeactivation = YES;

            if (deactivateError) {
                NSLog(@"PPLAB NotificationsV2 admin logout continuing | deactivation_ok=no error=%@",
                      deactivateError.localizedDescription ?: @"unknown");
            }

            [strongSelf invalidateUserCacheForUID:userID];
            [strongSelf clearUserCache];
            [strongSelf stopListening];

            NSError *signOutError = nil;
            [[FUManager shared] signOut:&signOutError];
            if (signOutError) {
                [notificationAppDelegate pp_abortNotificationV2LogoutBarrierAndRefreshForReason:@"auth_signout_failed"];
                UIViewController *presenter = PPAdminUserManagerTopViewController();
                if (presenter) {
                    [AlertHelper showErrorIn:presenter title:kLang(@"Error") subtitle:signOutError.localizedDescription];
                }
                [strongSelf pp_finishSignOutWithError:signOutError];
                return;
            }

            strongSelf.currentUser = nil;
            __block BOOL didFinishLocalTokenInvalidation = NO;
            void (^finishSignOut)(NSError * _Nullable) = ^(NSError * _Nullable tokenError) {
                if (didFinishLocalTokenInvalidation) return;
                didFinishLocalTokenInvalidation = YES;
                if (tokenError) {
                    NSLog(@"PPLAB NotificationsV2 admin logout token delete failed | error=%@",
                          tokenError.localizedDescription ?: @"unknown");
                }
                [notificationAppDelegate pp_endNotificationV2LogoutBarrier];
                [[NSNotificationCenter defaultCenter] postNotificationName:UserManagerAuthStateDidChangeNotification
                                                                    object:nil];
                [strongSelf pp_finishSignOutWithError:nil];
            };

            [PPNotifications invalidateLocalDeviceTokenWithCompletion:finishSignOut];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (didFinishLocalTokenInvalidation) return;
                NSLog(@"PPLAB NotificationsV2 admin token delete timeout | continuing=yes");
                finishSignOut(nil);
            });
        };

        [PPNotifications deactivateNotificationDeviceV2WithReason:@"logout" completion:continueAfterDeactivation];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (didContinueAfterDeactivation) return;
            NSLog(@"PPLAB NotificationsV2 admin deactivation timeout | continuing=yes");
            continueAfterDeactivation(nil);
        });
    };

    if (notificationAppDelegate) {
        [notificationAppDelegate pp_beginNotificationV2LogoutBarrierWithCompletion:beginDeactivationAfterRegistrationSettles];
    } else {
        beginDeactivationAfterRegistrationSettles();
    }
}

- (void)pp_finishSignOutWithError:(NSError * _Nullable)error
{
    self.signOutInProgress = NO;
    NSArray *callbacks = [self.pendingSignOutCompletions copy] ?: @[];
    [self.pendingSignOutCompletions removeAllObjects];
    for (id callbackObject in callbacks) {
        void (^callback)(NSError * _Nullable) = callbackObject;
        callback(error);
    }
}


#pragma mark - Ensure User Document

- (void)ensureUserDocumentExistsForAuthUser:(FIRUser *)authUser
                                 completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion
{
    if (!authUser) {
        if (completion) completion(nil, [NSError errorWithDomain:@"UserManager"
                                                            code:401
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Auth user is nil"}]);
        return;
    }
    
    NSString *uid = authUser.uid;
    FIRDocumentReference *docRef = [[[FIRFirestore firestore] collectionWithPath:@"UsersCol"] documentWithPath:uid];
    
    [docRef getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot,
                                        NSError * _Nullable error) {
        if (error) {
            DLog(@"❌ Firestore fetch error: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        
        if (snapshot.exists) {
            // ✅ User exists
            UserModel *user = [[UserModel alloc] initWithSnapshot:snapshot];
            self.currentUser = user;
            [self p_cacheUser:user];
            DLog(@"✅ User already exists: %@", user.uid);
            if (completion) completion(user, nil);
        }
        
        else {
            // ❌ User not found → create
            DLog(@"ℹ️ User does not exist, creating new doc for %@", uid);
            
            NSMutableDictionary *data = [NSMutableDictionary dictionary];
            
            data[@"ID"]           = uid;
            data[@"uid"]          = uid;
            data[@"UserEmail"]    = authUser.email ?: @"";
            data[@"UserName"]     = authUser.displayName ?: authUser.email ?: @"";
            data[@"UserImageName"] = @"";
            data[@"UserImageUrl"]  = authUser.photoURL ? authUser.photoURL.absoluteString : @"";
            data[@"displayName"]  = authUser.displayName ?: authUser.email ?: @"";
            data[@"email"]        = authUser.email ?: @"";
            data[@"photoURL"]     = authUser.photoURL ? authUser.photoURL.absoluteString : @"";
            data[@"createdAt"]    = [FIRFieldValue fieldValueForServerTimestamp];
            data[@"loginDate"]    = [FIRFieldValue fieldValueForServerTimestamp];
            data[@"updatedAt"]    = [FIRFieldValue fieldValueForServerTimestamp];
            data[@"role"]         = @(UserRoleUser);
            data[@"isAdmin"]      = @NO;
            data[@"isSuperAdmin"] = @NO;
            data[@"isBlocked"]    = @NO;
            data[@"verified"]     = @(authUser.isEmailVerified);
            data[@"emailVerified"] = @(authUser.isEmailVerified);
            data[@"plan"]         = @"free";
            data[@"loginSource"]  = @(UserLoginSourcePPAdmin); // Or PPUsers depending on app
            data[@"permissions"]  = @{};
            
            [docRef setData:data completion:^(NSError * _Nullable error) {
                if (error) {
                    DLog(@"❌ Failed to create user doc: %@", error.localizedDescription);
                    if (completion) completion(nil, error);
                } else {
                    DLog(@"✅ User doc created successfully for %@", uid);
                    UserModel *newUser = [[UserModel alloc] initWithDict:data];
                    self.currentUser = newUser;
                    [self p_cacheUser:newUser];
                    if (completion) completion(newUser, nil);
                }
            }];
            
        }
    }];
}

#pragma mark - Permissions Helpers

- (void)makeUserAdmin:(NSString *)uid
           completion:(void(^)(NSError * _Nullable error))completion {
    DLog(@"🚀 Making %@ an Admin", uid);
    FIRDocumentReference *userRef = [[[FIRFirestore firestore] collectionWithPath:@"UsersCol"] documentWithPath:uid];
    FIRWriteBatch *batch = [[FIRFirestore firestore] batch];
    NSDictionary *payload = @{@"allowed": @YES,
                              @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]};
    [batch setData:payload
       forDocument:[[userRef collectionWithPath:kPPPermsSubCol] documentWithPath:kPermAdminAll]
             merge:YES];
    [batch setData:payload
       forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubCol] documentWithPath:@"AdminAll"]
             merge:YES];
    [batch setData:payload
       forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubColAlt] documentWithPath:@"AdminAll"]
             merge:YES];
    [batch commitWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"❌ Failed to grant admin: %@", error.localizedDescription);
        } else {
            DLog(@"✅ %@ is now Admin", uid);
        }
        if (completion) completion(error);
    }];
}

- (void)removeAdmin:(NSString *)uid
         completion:(void(^)(NSError * _Nullable error))completion {
    DLog(@"🔒 Removing Admin role from %@", uid);
    FIRDocumentReference *userRef = [[[FIRFirestore firestore] collectionWithPath:@"UsersCol"] documentWithPath:uid];
    FIRWriteBatch *batch = [[FIRFirestore firestore] batch];
    NSDictionary *payload = @{@"allowed": @NO,
                              @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]};
    [batch setData:payload
       forDocument:[[userRef collectionWithPath:kPPPermsSubCol] documentWithPath:kPermAdminAll]
             merge:YES];
    [batch setData:payload
       forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubCol] documentWithPath:@"AdminAll"]
             merge:YES];
    [batch setData:payload
       forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubColAlt] documentWithPath:@"AdminAll"]
             merge:YES];
    [batch commitWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"❌ Failed to remove admin: %@", error.localizedDescription);
        } else {
            DLog(@"✅ Admin removed for %@", uid);
        }
        if (completion) completion(error);
    }];
}

-(void)loadUserProfileImageInto:(UIImageView *)imageView shimmer:(BOOL)useShimmer completion:(void (^)(UIImage * _Nullable))completion
{
    [self loadUserProfileImageInto:imageView shimmer:useShimmer blur:NO anim:nil completion:completion];
}
- (void)loadUserProfileImageInto:(UIImageView *)imageView
                         shimmer:(BOOL)useShimmer
                            blur:(BOOL)useBlur
                            anim:(LOTAnimationView * _Nullable)anim
                      completion:(void(^)(UIImage * _Nullable image))completion {
    
    NSString *cachedUrl = self.currentUser.UserImageUrl.absoluteString;
    DLog(@"[ProfileImage] Starting load. Cached URL = %@", cachedUrl);
    
    if (!cachedUrl || cachedUrl.length == 0) {
        // ❌ No image at all → fallback to Lottie animation
        DLog(@"[ProfileImage] No cached image URL. Showing Lottie placeholder.");
        [Styling setAnimationNamed:@"Main Admin"
                            toView:anim
                         withSpeed:0.1
                        completion:^(BOOL success) {
            DLog(@"[ProfileImage] Lottie load success = %d", success);
            if (success) [anim play];
        }];
        
        if (completion) completion(nil);
        return;
    }
    
    // ✅ Add shimmer/blur before loading
    UIView *loadingOverlay = [[UIView alloc] initWithFrame:imageView.bounds];
    loadingOverlay.backgroundColor = [UIColor systemGray5Color];
    loadingOverlay.tag = 9999;
    loadingOverlay.layer.cornerRadius = imageView.layer.cornerRadius;
    loadingOverlay.layer.masksToBounds = YES;
    [imageView addSubview:loadingOverlay];
    DLog(@"[ProfileImage] Added shimmer/blur overlay. shimmer=%d blur=%d", useShimmer, useBlur);
    
    if (useShimmer) {
        DLog(@"[ProfileImage] Applying shimmer animation.");
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = loadingOverlay.bounds;
        gradient.colors = @[(__bridge id)[UIColor systemGray4Color].CGColor,
                            (__bridge id)[UIColor systemGray6Color].CGColor,
                            (__bridge id)[UIColor systemGray4Color].CGColor];
        gradient.startPoint = CGPointMake(0, 0.5);
        gradient.endPoint = CGPointMake(1, 0.5);
        gradient.locations = @[@0.0, @0.5, @1.0];
        
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"locations"];
        anim.fromValue = @[@0.0, @0.0, @0.25];
        anim.toValue = @[@0.75, @1.0, @1.0];
        anim.duration = 1.0;
        anim.repeatCount = HUGE_VALF;
        [gradient addAnimation:anim forKey:@"shimmer"];
        [loadingOverlay.layer addSublayer:gradient];
    }
    
    if (useBlur) {
        DLog(@"[ProfileImage] Applying blur effect.");
        UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:effect];
        blurView.frame = loadingOverlay.bounds;
        blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [loadingOverlay addSubview:blurView];
    }
    
    // ✅ Load from cache or Firebase URL
    DLog(@"[ProfileImage] Start loading from URL: %@", cachedUrl);
    [imageView sd_setImageWithURL:[NSURL URLWithString:cachedUrl]
                 placeholderImage:nil
                          options:SDWebImageHighPriority
                        completed:^(UIImage * _Nullable image,
                                    NSError * _Nullable error,
                                    SDImageCacheType cacheType,
                                    NSURL * _Nullable imageURL) {
        // Remove shimmer/blur overlay
        [[imageView viewWithTag:9999] removeFromSuperview];
        DLog(@"[ProfileImage] Finished loading. CacheType=%ld Error=%@", (long)cacheType, error);
        
        if (!error && image) {
            DLog(@"[ProfileImage] ✅ Image loaded successfully.");
            if (completion) completion(image);
        } else {
            // ❌ fallback to Lottie if failed
            DLog(@"[ProfileImage] ❌ Failed to load image. Showing Lottie fallback.");
            LOTAnimationView *anim = [[LOTAnimationView alloc] initWithFrame:imageView.bounds];
            anim.contentMode = UIViewContentModeScaleAspectFit;
            anim.loopAnimation = YES;
            [imageView addSubview:anim];
            //Seo Expert Man seo Pen LoginAnimation
            [Styling setAnimationNamed:@"Main Admin"
                                toView:anim
                             withSpeed:0.1
                            completion:^(BOOL success) {
                DLog(@"[ProfileImage] Fallback Lottie load success = %d", success);
                if (success) [anim play];
            }];
            if (completion) completion(nil);
        }
    }];
}

#pragma mark - Fetch All Users

- (void)fetchAllUsersWithCompletion:(void(^)(NSArray<UserModel *> * _Nullable users,
                                             NSError * _Nullable error))completion {
    [self fetchAllUsersForceRefresh:YES completion:completion];
}

- (void)fetchAllUsersForceRefresh:(BOOL)force
                       completion:(void(^)(NSArray<UserModel *> * _Nullable users,
                                           NSError * _Nullable error))completion {
    // ✅ Return cached users if available and not forced
    if (!force && self.cachedUsers.count > 0) {
        DLog(@"[UserManager] Returning %lu cached users", (unsigned long)self.cachedUsers.count);
        if (completion) completion(self.cachedUsers, nil);
        return;
    }
    
    FIRCollectionReference *usersCol = [[FIRFirestore firestore] collectionWithPath:@"UsersCol"];
    [[usersCol queryOrderedByField:@"UserName" descending:NO] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot,
                                           NSError * _Nullable error) {
        if (error) {
            DLog(@"❌ Failed to fetch all users: %@", error.localizedDescription);
            if (completion) completion(nil, error);
            return;
        }
        
        NSMutableArray *arr = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            UserModel *u = [[UserModel alloc] initWithSnapshot:doc];
            if (u) [arr addObject:u];
        }
        
        self.cachedUsers = arr;
        self.lastUsersFetchAt = [NSDate date];
        DLog(@"✅ Loaded %lu users from Firestore", (unsigned long)arr.count);
        
        if (completion) completion(arr, nil);
    }];
}

- (void)setUser:(UserModel *)user isPPAdmin:(BOOL)isAdmin {
    [self setUser:user isPPAdmin:isAdmin completion:nil];
}

// UserManager.m
- (void)toggleAdminForUser:(UserModel *)user {
    NSString *targetUID = user.uid.length ? user.uid : user.ID;
    if (!targetUID.length) {
        NSLog(@"[UserManager] ❌ Missing user ID");
        return;
    }
    
    BOOL newState = !user.isAdmin;
    [self setUser:user isPPAdmin:newState];
}


// 🔁 Public helper that flips current state
- (void)toggleAdminForUser:(UserModel *)user completion:(void(^)(NSError *error))completion {
    BOOL next = !user.isAdmin;
    [self setUser:user isPPAdmin:next completion:completion];
}

// ✅ Main method: sets custom claim via CF + updates UsersCol
- (void)setUser:(UserModel *)user
      isPPAdmin:(BOOL)makeAdmin
     completion:(void(^)(NSError *error))completion
{
    if (!user) {
        if (completion) completion([NSError errorWithDomain:@"UserManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Missing user model"}]);
        return;
    }

    NSString *targetUID = user.uid.length ? user.uid : user.ID;
    if (!targetUID.length) {
        if (completion) completion([NSError errorWithDomain:@"UserManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Missing user uid"}]);
        return;
    }
    user.uid = targetUID;
    
    // 1) Call your HTTPS Callable to set/clear the custom claim
    FIRFunctions *functions = [FIRFunctions functionsForRegion:@"us-central1"]; // 👈 match your deploy region
    NSDictionary *payload = @{ @"uid": targetUID, @"makeAdmin": @(makeAdmin) };
    
    
    [[functions HTTPSCallableWithName:@"setAdminClaim"] callWithObject:payload completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        
        
        if (error) {
            NSLog(@"❌ setAdminClaim failed: %@", error);
            if (completion) completion(error);
            return;
        }

        NSLog(@"✅ setAdminClaim success: %@", result.data);

        user.isAdmin = makeAdmin;
        user.verified = YES;
        if (makeAdmin) {
            if (user.role == UserRoleUnknown || user.role == UserRoleUser) {
                user.role = UserRoleAdmin;
            }
        } else if (user.role == UserRoleAdmin || user.role == UserRoleSuperAdmin) {
            user.role = UserRoleUser;
        }
        user.isSuperAdmin = (user.role == UserRoleSuperAdmin);

        [UsrMgr saveUserModel:user merge:YES completion:^(NSError * _Nullable saveError) {
            if (saveError) {
                NSLog(@"❌ saveUserModel failed for %@: %@", targetUID, saveError.localizedDescription);
                if (completion) completion(saveError);
                return;
            }

            FIRFirestore *db = [FIRFirestore firestore];
            FIRDocumentReference *userRef = [[db collectionWithPath:@"UsersCol"] documentWithPath:targetUID];
            NSDictionary *permPayload = @{
                @"allowed": @(makeAdmin),
                @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]
            };
            FIRWriteBatch *batch = [db batch];
            [batch setData:permPayload
               forDocument:[[userRef collectionWithPath:kPPPermsSubCol] documentWithPath:kPermAdminAll]
                     merge:YES];
            [batch setData:permPayload
               forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubCol] documentWithPath:@"AdminAll"]
                     merge:YES];
            [batch setData:permPayload
               forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubColAlt] documentWithPath:@"AdminAll"]
                     merge:YES];

            [batch commitWithCompletion:^(NSError * _Nullable permError) {
                if (permError) {
                    NSLog(@"⚠️ AdminAll permission sync failed for %@: %@", targetUID, permError.localizedDescription);
                }

                FIRUser *current = [FIRAuth auth].currentUser;
                BOOL isCurrentUser = (current != nil) && [current.uid isEqualToString:targetUID];
                if (!isCurrentUser) {
                    if (completion) completion(permError);
                    return;
                }

                [current getIDTokenResultForcingRefresh:YES completion:^(__unused FIRAuthTokenResult * _Nullable tokenResult, NSError * _Nullable tokenErr) {
                    if (tokenErr) {
                        NSLog(@"⚠️ Token refresh failed: %@", tokenErr.localizedDescription);
                    } else {
                        NSLog(@"🔄 ID token refreshed.");
                    }
                    if (completion) completion(permError ?: tokenErr);
                }];
            }];
        }];
        
    }];
    
    
   
}


- (void)toggleAdminForUser:(UserModel *)user
                  newState:(BOOL)makeAdmin
                completion:(void(^)(NSError * _Nullable error))completion
{
    // disable UI hint happens in VC; this is pure logic
    [self setUser:user isPPAdmin:makeAdmin completion:^(NSError *error) {
        if (completion) completion(error);
    }];
}

#pragma mark - Private

- (FIRDocumentReference *)_userDoc:(NSString *)uid {
    return [[[FIRFirestore firestore] collectionWithPath:@"UsersCol"] documentWithPath:uid];
}

#pragma mark - Fetch


- (id<FIRListenerRegistration>)listenUserWithUID:(NSString *)uid
                                          change:(void(^)(UserModel * _Nullable user))change
{
    if (!uid.length) return nil;
    return [[self _userDoc:uid]
            addSnapshotListener:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error || !snapshot.exists) { if (change) change(nil); return; }
        UserModel *m = [[UserModel alloc] initWithSnapshot:snapshot];
        if (change) change(m);
    }];
}

#pragma mark - Partial update (merge)

- (void)updateUserFieldsForUID:(NSString *)uid
                        fields:(NSDictionary *)fields
                    completion:(void(^)(NSError * _Nullable error))completion
{
    if (!uid.length) {
        if (completion) completion([NSError errorWithDomain:@"UserManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]);
        return;
    }
    
    // Add server timestamp automatically
    NSMutableDictionary *payload = [fields mutableCopy] ?: [NSMutableDictionary new];
    payload[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
    
    [[self _userDoc:uid] setData:payload merge:YES completion:^(NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}

#pragma mark - Save entire model

- (void)saveUserModel:(UserModel *)user
                merge:(BOOL)merge
           completion:(void(^)(NSError * _Nullable error))completion
{
    NSString *uid = user.uid.length ? user.uid : user.ID;
    if (!uid.length) {
        if (completion) completion([NSError errorWithDomain:@"UserManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey:@"UserModel has no uid"}]);
        return;
    }
    
    // Let your model build a clean dict (avoid nils/NSNulls inside)
    NSMutableDictionary *dict = [[user toDictionary] mutableCopy];
    if (!dict) dict = [NSMutableDictionary new];
    
    // Ensure canonical fields we often update from the admin
    dict[@"ID"]       = uid;
    dict[@"uid"]      = uid;
    dict[@"role"]     = @(user.role);
    dict[@"isAdmin"]  = @(user.isAdmin);
    dict[@"isSuperAdmin"] = @(user.isSuperAdmin);
    dict[@"isBlocked"] = @(user.isBlocked);
    dict[@"displayName"] = PPSafeString(user.displayName.length ? user.displayName : user.UserName);
    dict[@"email"]       = PPSafeString(user.email.length ? user.email : user.UserEmail);
    dict[@"photoURL"]    = PPSafeString(user.photoURL.length ? user.photoURL : user.UserImageUrl.absoluteString);
    dict[@"verified"] = @(user.isVerified);
    dict[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
    
    [[self _userDoc:uid] setData:dict merge:merge completion:^(NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}


#pragma mark - Role / Admin utilities

- (void)setRole:(UserRole)role
         forUID:(NSString *)uid
     completion:(void(^)(NSError * _Nullable error))completion
{
    if (!uid.length) {
        if (completion) completion([NSError errorWithDomain:@"UserManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]);
        return;
    }

    BOOL isAdmin = (role == UserRoleAdmin || role == UserRoleSuperAdmin);
    NSDictionary *fields = @{
        @"role"        : @(role),
        @"isAdmin"     : @(isAdmin),
        @"isSuperAdmin": @(role == UserRoleSuperAdmin),
        @"updatedAt"   : [FIRFieldValue fieldValueForServerTimestamp]
    };
    [[self _userDoc:uid] setData:fields merge:YES completion:^(NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSDictionary *permPayload = @{@"allowed": @(isAdmin),
                                      @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]};
        FIRWriteBatch *batch = [[FIRFirestore firestore] batch];
        FIRDocumentReference *userRef = [self _userDoc:uid];
        [batch setData:permPayload
           forDocument:[[userRef collectionWithPath:kPPPermsSubCol] documentWithPath:kPermAdminAll]
                 merge:YES];
        [batch setData:permPayload
           forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubCol] documentWithPath:@"AdminAll"]
                 merge:YES];
        [batch setData:permPayload
           forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubColAlt] documentWithPath:@"AdminAll"]
                 merge:YES];
        [batch commitWithCompletion:^(NSError * _Nullable permError) {
            if (completion) completion(permError);
        }];
    }];
}

- (void)setIsAdmin:(BOOL)isAdmin
            forUID:(NSString *)uid
 realignRoleIfNeeded:(BOOL)realign
        completion:(void(^)(NSError * _Nullable error))completion
{
    if (!uid.length) {
        if (completion) completion([NSError errorWithDomain:@"UserManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey:@"Missing uid"}]);
        return;
    }

    NSMutableDictionary *fields = [@{
        @"isAdmin"  : @(isAdmin),
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]
    } mutableCopy];

    if (realign) {
        fields[@"role"] = @(isAdmin ? UserRoleAdmin : UserRoleUser);
    }
    if (!isAdmin || realign) {
        fields[@"isSuperAdmin"] = @NO;
    }

    [[self _userDoc:uid] setData:fields merge:YES completion:^(NSError * _Nullable error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        NSDictionary *permPayload = @{@"allowed": @(isAdmin),
                                      @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]};
        FIRWriteBatch *batch = [[FIRFirestore firestore] batch];
        FIRDocumentReference *userRef = [self _userDoc:uid];
        [batch setData:permPayload
           forDocument:[[userRef collectionWithPath:kPPPermsSubCol] documentWithPath:kPermAdminAll]
                 merge:YES];
        [batch setData:permPayload
           forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubCol] documentWithPath:@"AdminAll"]
                 merge:YES];
        [batch setData:permPayload
           forDocument:[[userRef collectionWithPath:kPPLegacyPermsSubColAlt] documentWithPath:@"AdminAll"]
                 merge:YES];
        [batch commitWithCompletion:^(NSError * _Nullable permError) {
            if (completion) completion(permError);
        }];
    }];
}

// in UserManager.m
- (void)listenAllUsersWithCompletion:(void(^)(NSArray<UserModel *> *users, NSError *error))completion {
    FIRFirestore *db = [FIRFirestore firestore];

    [[db collectionWithPath:@"UsersCol"]
     addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        NSMutableArray *arr = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            UserModel *u = [[UserModel alloc] initWithSnapshot:doc];
            [arr addObject:u];
        }

        if (completion) completion(arr, nil);
    }];
}

@end


/*
 // Default behavior (memory→disk→server)
 [UsrMgr loadUserWithUID:uid completion:^(UserModel *user, NSError *error) {
     // use user
 }];

 // Force server refresh
 [UsrMgr loadUserWithUID:uid cachePolicy:PPUserCachePolicyServerOnly completion:^(UserModel *user, NSError *error) {
     // fresh data
 }];

 // Cache-only (no network)
 [UsrMgr loadUserWithUID:uid cachePolicy:PPUserCachePolicyCacheOnly completion:^(UserModel *user, NSError *error) {
     // user may be nil if not cached
 }];
 */
