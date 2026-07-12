

// In UserManager.h
extern NSString * _Nullable const UserManagerAuthStateDidChangeNotification;
extern NSString * _Nullable const LanguageDidChangeNotification;



typedef NS_ENUM(NSInteger, PPUserCachePolicy) {
    PPUserCachePolicyMemoryFirstThenServer = 0,  // default: memory → disk → Firestore
    PPUserCachePolicyCacheOnly,                  // memory/disk only (no network)
    PPUserCachePolicyServerOnly                 // skip caches; fetch Firestore and refresh caches
};


@class UserModel;
@class LOTAnimationView;

NS_ASSUME_NONNULL_BEGIN

@interface UserManager : NSObject
+ (instancetype)shared;


- (void)p_writeUserToDisk:(UserModel *)user forUID:(NSString *)uid;
- (void)p_cacheUser:(UserModel *)user;
- (UserModel *)p_readUserFromDisk:(NSString *)uid;
- (void)invalidateUserCacheForUID:(NSString *)uid;


- (void)loadUserByUIDOrID:(NSString *)uid
               completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion;
/// Fetch one user by uid
- (void)fetchAdminWithUID:(NSString *)uid  cachePolicy:(PPUserCachePolicy)policy completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion;

/// Live listen for a user (caller holds the returned listener and removes it)
- (id<FIRListenerRegistration>)listenUserWithUID:(NSString *)uid
                                          change:(void(^)(UserModel * _Nullable user))change;

/// Update (merge) a subset of fields in UsersCol/<uid>
- (void)updateUserFieldsForUID:(NSString *)uid
                        fields:(NSDictionary *)fields
                    completion:(void(^)(NSError * _Nullable error))completion;

/// Save an entire UserModel to UsersCol/<uid> (merge = YES to avoid overwriting)
- (void)saveUserModel:(UserModel *)user
                merge:(BOOL)merge
           completion:(void(^)(NSError * _Nullable error))completion;

/// Convenience: set role (also mirrors isAdmin if role == Admin)
- (void)setRole:(UserRole)role
         forUID:(NSString *)uid
     completion:(void(^)(NSError * _Nullable error))completion;

/// Convenience: set isAdmin and optionally align role
- (void)setIsAdmin:(BOOL)isAdmin
            forUID:(NSString *)uid
 realignRoleIfNeeded:(BOOL)realign
        completion:(void(^)(NSError * _Nullable error))completion;



@property (nonatomic, strong, nullable) UserModel *currentUser;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> userListener;


/// Start real-time listening to current user document
- (void)startListeningUserWithUID:(NSString *)uid
                          onChange:(void(^)(UserModel * _Nullable user))onChange;

/// Stop the live listener
- (void)stopListening;

/// Create user document if not exists
- (void)createUserIfNotExistsWithUID:(NSString *)uid
                                data:(NSDictionary *)data
                          completion:(void(^)(NSError * _Nullable error))completion;

/// Sign out and clear cached user
- (void)signOut;

// Ensure user document exists when logging in with Firebase Auth
- (void)ensureUserDocumentExistsForAuthUser:(FIRUser *)authUser
                                 completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion;

// Admin helpers
- (void)makeUserAdmin:(NSString *)uid
           completion:(void(^)(NSError * _Nullable error))completion;

- (void)removeAdmin:(NSString *)uid
          completion:(void(^)(NSError * _Nullable error))completion;

/// Load current user profile image into UIImageView with cache + shimmer + fallback
- (void)loadUserProfileImageInto:(UIImageView *)imageView
                        shimmer:(BOOL)useShimmer
                           blur:(BOOL)useBlur
                            anim:(LOTAnimationView * _Nullable)anim
                     completion:(void(^)(UIImage * _Nullable image))completion;

- (void)loadUserProfileImageInto:(UIImageView *)imageView
                        shimmer:(BOOL)useShimmer
                     completion:(void(^)(UIImage * _Nullable image))completion;

- (void)fetchAllUsersWithCompletion:(void(^)(NSArray<UserModel *> * _Nullable users,
                                             NSError * _Nullable error))completion;

- (void)setUser:(UserModel *)user isPPAdmin:(BOOL)isAdmin;
// UserManager.h
- (void)toggleAdminForUser:(UserModel *)user;

- (void)toggleAdminForUser:(UserModel *)user
                newState:(BOOL)makeAdmin
                completion:(void(^)(NSError * _Nullable error))completion;


- (void)toggleAdminForUser:(UserModel *)user completion:(void(^)(NSError *error))completion;

- (void)listenAllUsersWithCompletion:(void(^)(NSArray<UserModel *> *users, NSError *error))completion;

@property (nonatomic, assign) NSTimeInterval userCacheTTL; // e.g., 300 (5 min)

@end

NS_ASSUME_NONNULL_END



//
//  UserManager.h
//  PurePetsAdmin
//
