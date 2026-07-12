//
//  FUUserDoc.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 02/09/2025.
//


//  FUManager.h
//  Auth + Profile + UserDoc + Users list (no roles/permissions here)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class FIRAuthCredential;
@class FIRDocumentChange;
@class FIRDocumentReference;
@class FIRFirestore;
@class FIRFunctions;
@class FIRQuery;
@class FIRSnapshotMetadata;
@class FIRStorage;
@class FIRUser;
@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@class UserModel; // your app's model

// Callbacks
typedef void (^FUErrorBlock)(NSError * _Nullable error);
typedef void (^FUUserBlock)(FIRUser * _Nullable user, NSError * _Nullable error);
typedef void (^FUURLBlock)(NSURL * _Nullable url, NSError * _Nullable error);
typedef void (^FUAnyBlock)(id _Nullable obj, NSError * _Nullable error);

// Users list completions
typedef void (^FUUsersCompletion)(NSArray<UserModel *> * _Nullable users,
                                  FIRSnapshotMetadata * _Nullable metadata,
                                  NSError * _Nullable error);

typedef void (^FUUsersDiffCompletion)(NSArray<UserModel *> * _Nullable users,
                                      NSArray<FIRDocumentChange *> * _Nullable changes,
                                      FIRSnapshotMetadata * _Nullable metadata,
                                      NSError * _Nullable error);

/// Simple wrapper for a subset of UsersCol/<uid> fields we keep handy
@interface FUUserDoc : NSObject
@property (nonatomic, copy, nullable) NSString *uid;
@property (nonatomic, copy, nullable) NSString *email;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, strong, nullable) NSURL *photoURL;
@property (nonatomic, strong, nullable) NSDictionary *raw;
@end


typedef void (^FUProgressBlock)(double fraction); // 0..1



@interface FUManager : NSObject

- (void)updatePhotoImage:(UIImage *)image
         maxDimension_px:(NSUInteger)maxDim
                maxBytes:(NSUInteger)maxBytes
                progress:(FUProgressBlock _Nullable)progress
              completion:(FUURLBlock)completion;


+ (instancetype)shared;

#pragma mark - Photo URL helpers

/// Upload a PNG avatar (e.g., from HXPhotoPicker), store at
/// avatars/{uid}/{timestamp}.png, then update Auth.photoURL + UsersCol/{uid}.UserImageUrl.
/// Returns the final download URL.
- (void)uploadAvatarPNGData:(NSData *)pngData
                 completion:(FUURLBlock)completion;

/// Set the avatar *directly* from an existing URL (no upload).
/// Writes to Auth.photoURL and UsersCol/{uid}.UserImageUrl (and 'photoURL' mirror).
- (void)updatePhotoURL:(NSURL *)url
            completion:(FUErrorBlock)completion;

/// Convenience if you have a string URL
- (void)updatePhotoURLString:(NSString *)urlString
                  completion:(FUErrorBlock)completion;

/// Fetch the current user’s avatar URL. Prefers Auth.photoURL; falls back to Firestore UserImageUrl.
- (void)fetchCurrentUserPhotoURL:(FUURLBlock)completion;

/// Fetch another user’s avatar URL from Firestore.
- (void)fetchPhotoURLForUID:(NSString *)uid
                 completion:(FUURLBlock)completion;

/// Remove current user’s avatar.
/// If deleteFromStorage==YES and a 'UserImagePath' is present on the doc, it will be deleted (best effort).
- (void)removeCurrentUserPhotoWithDeleteFromStorage:(BOOL)deleteFromStorage
                                         completion:(FUErrorBlock)completion;


#pragma mark - Core Services & State

@property (nonatomic, strong) FIRFirestore *db;
@property (nonatomic, strong) FIRStorage *storage;
@property (nonatomic, strong) FIRFunctions *functions;
@property (nonatomic, strong, readwrite, nullable) FUUserDoc *currentUserDoc;
@property (nonatomic, strong, readonly, nullable) FIRUser *currentUser;

#pragma mark - Private helpers (intentionally public to keep exact signatures for linker)

- (NSError *)p_err:(NSString *)msg code:(NSInteger)code;
- (void)p_finishUser:(FIRUser * _Nullable)user
               error:(NSError * _Nullable)error
          completion:(FUUserBlock)completion;

- (void)p_applyDisplayName:(NSString * _Nullable)displayName
                  photoURL:(NSURL * _Nullable)photoURL
                    toUser:(FIRUser *)user
                completion:(FUErrorBlock)completion;

- (void)p_createOrMergeUserDocFor:(FIRUser *)user
                            extra:(NSDictionary * _Nullable)extra
                       completion:(FUErrorBlock)completion;

- (void)p_uploadProfileImage:(UIImage *)image
                      forUID:(NSString *)uid
                      maxDim:(NSUInteger)maxDim
                    maxBytes:(NSUInteger)maxBytes
                  completion:(FUURLBlock)completion;

- (NSArray<NSString *> *)p_providerIDsForUser:(FIRUser *)user;
- (UIImage *)p_scaleImage:(UIImage *)image maxDimension:(NSUInteger)maxDim;
- (NSData *)p_pngDataForImage:(UIImage *)image targetMaxBytes:(NSUInteger)maxBytes;
- (void)p_linkCredential:(FIRAuthCredential *)cred
              completion:(FUUserBlock)completion;

#pragma mark - Auth lifecycle

- (void)createUserWithEmail:(NSString *)email
                   password:(NSString *)password
                displayName:(nullable NSString *)displayName
                      photo:(nullable UIImage *)photo
                   metadata:(nullable NSDictionary *)metadata
                 completion:(FUUserBlock)completion;

- (void)signInWithEmail:(NSString *)email
               password:(NSString *)password
             completion:(FUUserBlock)completion;

- (void)signInWithGoogle:(UIViewController *)presentingVC
              completion:(FUUserBlock)completion;

- (BOOL)signOut:(NSError * _Nullable * _Nullable)error;
- (void)deleteCurrentUserWithCompletion:(FUErrorBlock)completion;

#pragma mark - Reauth / reload

- (void)reauthenticateWithEmail:(NSString *)email
                       password:(NSString *)password
                     completion:(FUErrorBlock)completion;

- (void)reauthenticateWithCredential:(FIRAuthCredential *)credential
                          completion:(FUErrorBlock)completion;

- (void)reloadCurrentUser:(FUErrorBlock)completion;

#pragma mark - Profile updates (Auth + Firestore + Storage)

- (void)updateDisplayName:(NSString *)displayName completion:(FUErrorBlock)completion;
- (void)updateEmail:(NSString *)email completion:(FUErrorBlock)completion;
- (void)updatePassword:(NSString *)newPassword completion:(FUErrorBlock)completion;

- (void)updatePhotoImage:(UIImage *)image
         maxDimension_px:(NSUInteger)maxDim
               maxBytes:(NSUInteger)maxBytes
              completion:(FUURLBlock)completion;

#pragma mark - Firestore user doc APIs

- (void)ensureUserDocumentExistsForCurrentUserWithExtra:(nullable NSDictionary *)extra
                                             completion:(FUErrorBlock)completion;

- (void)updateUserDocumentFields:(NSDictionary *)fields completion:(FUErrorBlock)completion;

- (nullable FIRDocumentReference *)userDocumentRefForUID:(NSString *)uid;

- (id<FIRListenerRegistration>)listenToCurrentUserDoc:(void(^)(FUUserDoc * _Nullable doc,
                                                                NSError * _Nullable error))block;

- (void)unlinkProvider:(NSString *)providerID completion:(FUUserBlock)completion;

#pragma mark - Apple nonce helpers (optional)

+ (NSString *)randomNonceString:(NSUInteger)length;
+ (NSString *)sha256:(NSString *)input;

#pragma mark - Combined modeler

- (UserModel * _Nullable)userModelFromAuth:(FIRUser * _Nullable)auth
                                       doc:(FUUserDoc * _Nullable)doc;

- (id<FIRListenerRegistration>)listenCombinedUser:(void(^)(UserModel * _Nullable u,
                                                           NSError * _Nullable err))block;

#pragma mark - Users listing (ordered by UserName + uid)

- (id<FIRListenerRegistration>)listenAllUsersOrderedBy:(NSString * _Nullable)orderField
                                             ascending:(BOOL)ascending
                                  includeMetadataChanges:(BOOL)includeMetadata
                                                 queue:(dispatch_queue_t _Nullable)callbackQueue
                                            completion:(FUUsersCompletion)completion;

- (id<FIRListenerRegistration>)listenAllUsersWithDiffsOrderedBy:(NSString * _Nullable)orderField
                                                       ascending:(BOOL)ascending
                                            includeMetadataChanges:(BOOL)includeMetadata
                                                           queue:(dispatch_queue_t _Nullable)callbackQueue
                                                        completion:(FUUsersDiffCompletion)completion;

- (void)fetchAllUsersOrderedBy:(NSString * _Nullable)orderField
                      ascending:(BOOL)ascending
                          queue:(dispatch_queue_t _Nullable)callbackQueue
                     completion:(FUUsersCompletion)completion;

/// Reusable query builder
+ (FIRQuery *)usersBaseQueryOrderedBy:(NSString * _Nullable)orderField
                            ascending:(BOOL)ascending;

#pragma mark - Auth Listener (top level)

- (void)startAuthListenerWithChangeBlock:(void(^)(FIRUser * _Nullable authUser,
                                                  UserModel * _Nullable userModel))block;

- (void)reloadCurrentUserWithCompletion:(void(^)(UserModel * _Nullable user,
                                                 NSError * _Nullable error))completion;

- (id<FIRListenerRegistration>)listenStaffUsersWithCompletion:(void(^)(NSArray<UserModel *> * _Nullable staff, NSError * _Nullable error))completion;

#pragma mark - Arbitrary field updates

- (void)updateUserFieldsForUID:(NSString *)uid
                        fields:(NSDictionary<NSString *, id> *)fields
                    completion:(FUErrorBlock)completion;

- (void)removeUserWithUID:(NSString *)uid
               completion:(FUErrorBlock)completion;

#pragma mark - Admin-side account creation (minimal write-through)

- (void)createUserWithEmail:(NSString *)email
                   password:(NSString *)password
                   username:(NSString *)username
                       role:(NSInteger)role            // stored as-is; no role logic here
                permissions:(NSDictionary<NSString *, NSNumber *> *)perms  // stored as-is
                    isAdmin:(BOOL)isAdmin
                 completion:(void(^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END


/*
 
 I have already UsersCol on fireStore handle the news user model and user manager, but my user manager are not flexible and not a professional and not following best practice. Now I will attach for you copy of my user Manager and copy of my user model that I’m using with my users collection and I want you to compare my user model with this function I will. I will attach after user model because I want after you finish you give me two files you give me two files users Manager.H and user Manager.M very clean files working very well handling user specification and user model converting from user modification user model and going back from user user authentication or certification I want them to be like one model, but but in real F5RE store model and my model

 Bro, please I want you to check these functions and glasses. I provided you very well and following best practice I want you to choose what should keep what should remove , also I will attach for you now name of my functions like I have functions calls like BB string PP safe integer PPsafeURL use it on this operation because I don’t need any kinds of issues or error errors
 
 ######### IMPORTANT ##########
 # All updates on UsersManager
 # only three FIRAuth methods allowed in my app 1)sign in using google email (Gmail).     2)sign in using Apple Id.     3)sign in using Mobile Number.
 # Using Profisstions and modren way to create this manage
 #############################
 // MY USER MANAGER
 
 
 NS_ASSUME_NONNULL_BEGIN
 @interface UserManager : NSObject
 @property (nonatomic, strong, readonly, nullable) UserModel *currentUser;
 + (instancetype)sharedManager;
 - (void)getUserWithUID:(NSString *)uid completion:(void (^)(UserModel * _Nullable user, NSError * _Nullable error))completion;
 - (void)observeUserWithUID:(NSString *)uid onUpdate:(void (^)(UserModel * _Nullable user, NSError * _Nullable error))onUpdate;
 - (BOOL)isUserLoggedIn;
 - (void)updateCurrentUserWithPPUserTokenID:(NSString *)PPUserTokenID SubID:(NSString *)SubID;
 - (void)updateUser:(UserModel *)user completion:(void (^)(BOOL success, NSError * _Nullable error))completion;;
 - (void)uploadUserImage:(UIImage *)image
          userImageName:(NSString *)imageName
              completion:(void (^)(NSError * _Nullable error, NSString * _Nullable imageURL))completion;

 - (void)addUser:(UserModel *)user
      completion:(void (^)(NSError * _Nullable error, NSString * _Nullable userID))completion;
 - (void)setUserImageForUser:(UserModel *)user toImageView:(UIImageView *)imageView;
 - (void)setUserImageForUser:(UserModel *)user toImageView:(UIImageView *)imageView  parentCircle:(UIView * _Nullable)circle;
 - (void)clearUserDefaults;
 - (void)logoutAndClearAll;
 - (void)cacheUser:(UserModel *)user;
 - (void)loadCachedUser;
 
 
 + (void)getUidByUserID:(NSString *)userID completion:(void (^)(NSString * _Nullable uid, NSError * _Nullable error))completion;
 + (NSString *)uidForID:(NSString *)userID;
 + (UserModel *)userModelForID:(NSString *)userID;
 + (NSString *)iDForUid:(NSString *)uid;
 + (void)showPromptOnTopController;

 // Batch update a single permission for many users (allow/deny)
 - (void)updatePermission:(UserPermission)flag
                  enabled:(BOOL)enabled
               forUserIDs:(NSArray<NSString *> *)userIDs
               completion:(void(^)(NSError * _Nullable error))completion;

 // Convenience: check current user’s permission quickly
 - (BOOL)currentUserCan:(UserPermission)flag;

 // Start/stop listening to current user’s permission subcollection (keeps currentUser.permissions live)
 - (void)startListeningCurrentUserPermissionsWithChange:(void (^_Nullable)(NSDictionary<NSString *, NSNumber *> *perms))onChange;
 - (void)stopListeningCurrentUserPermissions;

 - (void)PPUSER_SYNC_All; // PPUSER_SYNC_All will update user moel to firestore UsersCol and also will update FIRUser
 - (void)PPUSER_SYNC_COLLECTION_ONLY; // PPUSER_SYNC_COLLECTION_ONLY will update user moel to firestore UsersCol only
 - (void)PPUSER_SYNC_FIRUSER_ONLY; // PPUSER_SYNC_FIRUSER_ONLY  will update FIRUser only

 
and on add or update user model be sure that Token stored as PPUserTokenID
 because am use it to push Messaging to users
 
 
and UserLoginSource set it to UserLoginSourcePPUsers always

 
 
 // ========================================  FUM MANAGER SOURCE ==============================//


 // ========================================  FUM MANAGER SOURCE ==============================//
 @end
 NS_ASSUME_NONNULL_END

 
 
 // MY USER MODEL
 //
 //  UserModel.h
 //  PurePetsAdmin
 //
 //  Created by Mohammed Ahmed on 21/08/2025.
 //

 #import "PPRolePermission.h"
 @class UserModel;
 NS_ASSUME_NONNULL_BEGIN

 // ===== Login Source =====
 typedef NS_ENUM(NSInteger, UserLoginSource) {
     UserLoginSourceUnknown = 0,
     UserLoginSourcePPUsers = 1,   // From main PurePets app
     UserLoginSourcePPAdmin = 2    // From PurePets Admin app
 };



 @interface UserModel : NSObject <XLFormOptionObject, NSSecureCoding>

 -(NSString *)PPBestDisplayName;
 /// Permissions (subcollection map: permKey -> allowed)
 @property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *permissions;
 @property (nonatomic, strong, nullable) id<FIRListenerRegistration> permissionsListener;

 // ---- Permission APIs ----
 - (void)fetchPermissionsWithCompletion:(void (^_Nullable)(NSDictionary<NSString *, NSNumber *> *perms,
                                                          NSError * _Nullable error))completion;
 - (void)startListeningPermissionsWithChange:(void (^)(NSDictionary<NSString *, NSNumber *> *perms))changeBlock;
 - (void)stopListeningPermissions;
 - (void)setPermissionNamed:(NSString *)permName
                    allowed:(BOOL)allowed
                 completion:(void (^)(NSError * _Nullable error))completion;
 - (BOOL)hasPermissionNamed:(NSString *)permName;

 // ---- Initializers ----
 - (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot;
 - (instancetype)initWithDict:(NSDictionary *)dict;
 - (NSDictionary *)toDictionary;

 // ---- Identity ----
 @property (nonatomic, copy) NSString *uid;
 @property (nonatomic, copy) NSString *UserEmail;
 @property (nonatomic, copy) NSString *UserName;
 @property (nonatomic, strong) NSString *ID;

 // ---- From Server ----
 @property (nonatomic, strong, nullable) NSString *displayName;
 @property (nonatomic, strong, nullable) NSString *email;
 @property (nonatomic, strong, nullable) NSString *photoURL;

 // ---- Roles ----
 @property (nonatomic, assign) UserRole role;
 @property (nonatomic, assign) BOOL isAdmin;
 @property (nonatomic, assign) BOOL isSuperAdmin;
 @property (nonatomic, assign) BOOL isBlocked;

 // ---- Convenience (quick checks) ----
 @property (nonatomic, readonly) BOOL canPostAds;
 @property (nonatomic, readonly) BOOL canSellNew;
 @property (nonatomic, readonly) BOOL canSellUsed;
 @property (nonatomic, readonly) BOOL canAdoption;
 @property (nonatomic, readonly) BOOL canManageStore;
 @property (nonatomic, readonly) BOOL canModeration;
 @property (nonatomic, readonly) BOOL isAdminAll;

 // 🔥 New convenience flags for future roles
 @property (nonatomic, readonly) BOOL isStoreManager;
 @property (nonatomic, readonly) BOOL isFoodManager;
 @property (nonatomic, readonly) BOOL isModerator;
 @property (nonatomic, readonly) BOOL isOwner;
 @property (nonatomic, readonly) BOOL isVet;

 // ---- Profile info ----
 @property (nonatomic, strong, nullable) NSString *FirstName;
 @property (nonatomic, strong, nullable) NSString *LastName;
 @property (nonatomic, strong, nullable) NSString *MobileNo;
 @property (nonatomic, strong) NSString *UserImageName;
 @property (nonatomic, strong, nullable) NSString *UserAbout;
 @property (nonatomic, strong, nullable) NSURL *UserImageUrl;
 @property (nonatomic, strong, nullable) NSDate *loginDate;
 @property (nonatomic, strong, nullable) NSDate *updatedAt;
 @property (nonatomic, assign) NSInteger CountryID;
 @property (nonatomic, strong) NSString *PPUserTokenID;
 @property (nonatomic, strong) NSString *PPAdminTokenID;

 // ---- Other ----
 @property (nonatomic, assign, getter=isVerified) BOOL verified;
 @property (nonatomic, copy, nullable) NSString *plan;

 // ---- Login source ----
 @property (nonatomic, assign) UserLoginSource loginSource;
 @property (nonatomic, copy, nullable) NSString *authPassword;  // session-only
 @property (nonatomic, readonly) BOOL hasAuthCredentials;

 /// Wipes transient credentials from memory (call after using them)
 - (void)clearSensitiveAuthCache;

 /// Save / load helpers for offline cache & multi-user switching
 + (nullable instancetype)loadSavedUserWithUID:(NSString *)uid;
 - (void)saveToDisk;
 + (void)clearCachedUserWithUID:(NSString *)uid;

 /// Build a model from pieces (Auth user + UsersCol doc + permissions + claims).
 + (instancetype)fromAuthUser:(FIRUser *)auth
                      rootDoc:(nullable NSDictionary *)root
                  permissions:(nullable NSDictionary<NSString *, NSNumber *> *)perms
                       claims:(nullable NSDictionary *)claims;

 /// Convenience: load everything for the **current** user and return a hydrated model.
 + (void)loadCurrentUserModelWithCompletion:(void(^)(UserModel *_Nullable u,
                                                     NSError *_Nullable err))completion;

 /// Sync model back to Firestore
 - (void)SYNC:(void(^)(NSError * _Nullable error))completion;

 @end

 NS_ASSUME_NONNULL_END

 
 
 // MY PP Helper
 
 static inline NSString *PPJoinNames(NSString *first, NSString *last)
 static inline NSNumber *PPSafeNumber(id v)
 static inline NSInteger PPSafeInteger(id v)
 static inline NSInteger PPSafeFormInteger(id v)
 static inline double PPSafeDouble(id v)
 static inline NSDate *PPSafeDate(id v)
 // Safe array
 static inline NSArray *PPSafeArray(id v)
 // Safe dictionary
 static inline NSDictionary *PPSafeDict(id v)
 // Safe UUID joiner
 static inline NSString *UUIDJoin(NSString *string)
 /// Universal safe integer extractor
 static inline NSInteger PPSafeIntegerUniversal(id v)
 
 
 
 
 
 // SIMILAR OR EX..

 // MARK: - User Update Keys (Best Practice Constants)
 extern NSString *const FUUpdateKeyEmail;
 extern NSString *const FUUpdateKeyPhoneNumber;
 extern NSString *const FUUpdateKeyDisplayName;
 extern NSString *const FUUpdateKeyPhotoURL;
 extern NSString *const FUUpdateKeyCustomClaims;

 // MARK: - Error Domains
 extern NSString *const FUErrorDomain;
 extern NSErrorUserInfoKey const FUErrorDetailedDescriptionKey;

 typedef NS_ENUM(NSInteger, FUErrorCode) {
     FUErrorCodeInvalidParameter = 1000,
     FUErrorCodeUserNotFound = 1001,
     FUErrorCodeNetworkError = 1002,
     FUErrorCodePermissionDenied = 1003,
     FUErrorCodeInvalidCredentials = 1004,
     FUErrorCodeOperationNotAllowed = 1005,
     FUErrorCodeRequiresRecentLogin = 1006,
     FUErrorCodeCustomClaimError = 1007
 };


 // MARK: - Core Properties
 @property (nonatomic, strong, readonly) FIRFunctions *functions;
 @property (nonatomic, strong, readonly, nullable) FIRUser *currentAuthUser;

 // MARK: - Authentication Lifecycle Management
 #pragma mark Auth State Management
 - (void)startAuthStateMonitoringWithHandler:(FUAuthStateHandler)handler;
 - (void)stopAuthStateMonitoring;
 - (void)reloadCurrentUserWithCompletion:(FUUserCompletion)completion;

 #pragma mark Sign Out & Account Deletion
 - (void)signOutCurrentUserWithCompletion:(FUCompletion)completion;
 - (void)deleteCurrentUserAccountWithCompletion:(FUCompletion)completion;

 // MARK: - User Profile Management (FIRUser + Firestore)
 #pragma mark Comprehensive User Updates
 - (void)updateCurrentUserProfileWithValues:(NSDictionary<NSString *, id> *)values
                                 completion:(FUCompletion)completion;

 - (void)updateUserProfileForUID:(NSString *)userUID
                          values:(NSDictionary<NSString *, id> *)values
                      completion:(FUCompletion)completion;

 #pragma mark Individual Field Updates (Atomic Operations)
 - (void)updateCurrentUserGmail:(NSString *)Gmail
                     completion:(FUCompletion)completion;
 
 
 - (void)updateCurrentUserEmail:(NSString *)email
                     completion:(FUCompletion)completion;
 
 
 - (void)updateCurrentUserPhoneNumber:(NSString *)phoneNumber
                           completion:(FUCompletion)completion;

 - (void)updateCurrentUserDisplayName:(NSString *)displayName
                           completion:(FUCompletion)completion;


 // MARK: - Multi-Provider Account Management
 #pragma mark Provider Linking/Unlinking
 - (void)linkGMailProviderWithEmail:(NSString *)gmail
                           password:(NSString *)password
                         completion:(FUUserCompletion)completion;

 - (void)linkPhoneNumberProviderWithNumber:(NSString *)phoneNumber
                                completion:(FUUserCompletion)completion;

 - (void)linkAppleProviderWithIDToken:(NSString *)idToken
                           nonce:(NSString *)nonce
                       completion:(FUUserCompletion)completion;

 - (void)unlinkProvider:(NSString *)providerID
             completion:(FUUserCompletion)completion;

 - (void)fetchLinkedProvidersWithCompletion:(void(^)(NSArray<NSString *> *providers, NSError *error))completion;

 #pragma mark Provider-Specific Updates
 - (void)updatePhoneNumberForCurrentUser:(NSString *)phoneNumber
                              completion:(FUCompletion)completion;

 // MARK: - Photo/Avatar Management
 #pragma mark Avatar Operations
 - (void)uploadUserAvatar:(UIImage *)avatarImage
                maxDimension:(CGFloat)maxDimension
                 maxFileSize:(NSUInteger)maxFileSize
                  progress:(FUProgressHandler)progress
                completion:(FUURLCompletion)completion;

 - (void)updateUserAvatarWithURL:(NSURL *)avatarURL
                      completion:(FUCompletion)completion;

 - (void)deleteUserAvatarWithCompletion:(FUCompletion)completion;

 - (void)fetchUserAvatarURLForUID:(NSString *)userUID
                       completion:(FUURLCompletion)completion;



 // MARK: - User Data Operations (Firestore)
 #pragma mark Firestore User Document Management
 - (void)createUserDocumentForUID:(NSString *)userUID
                   initialData:(NSDictionary *)data
                    completion:(FUCompletion)completion;

 - (void)updateUserDocumentForUID:(NSString *)userUID
                           fields:(NSDictionary<NSString *, id> *)fields
                       completion:(FUCompletion)completion;

 - (void)fetchUserDocumentForUID:(NSString *)userUID
                      completion:(void(^)(NSDictionary *document, NSError *error))completion;

 - (void)deleteUserDocumentForUID:(NSString *)userUID
                       completion:(FUCompletion)completion;

 // MARK: - User Listing & Querying
 #pragma mark User Discovery & Listing
 - (id<FIRListenerRegistration>)observeAllUsersWithQuery:(FIRQuery *)query
                                               completion:(FUUsersListCompletion)completion;

 - (void)fetchUsersWithQuery:(FIRQuery *)query
                  completion:(FUUsersListCompletion)completion;

 - (void)searchUsersWithField:(NSString *)fieldName
                       value:(id)value
                  completion:(FUUsersListCompletion)completion;

 // MARK: - Security & Reauthentication
 #pragma mark Security Operations
 - (void)reauthenticateWithPhoneNumber:(NSString *)phoneNumber
                            completion:(FUCompletion)completion;


 // MARK: - Batch Operations
 #pragma mark Batch Processing
 - (void)batchUpdateUsers:(NSArray<NSString *> *)userUIDs
                   fields:(NSDictionary<NSString *, id> *)fields
               completion:(void(^)(NSArray<NSError *> *errors))completion;

 - (void)batchDeleteUsers:(NSArray<NSString *> *)userUIDs
               completion:(void(^)(NSArray<NSError *> *errors))completion;

 // MARK: - Analytics & Monitoring
 #pragma mark Usage Analytics
 - (void)logUserActivity:(NSString *)activity
              parameters:(NSDictionary *)parameters;

 - (void)trackUserEngagementMetric:(NSString *)metric
                            value:(NSNumber *)value;

 @end

 // MARK: - Constants Implementation
 extern NSString *const FUUpdateKeyEmail = @"email";
 extern NSString *const FUUpdateKeyPhoneNumber = @"phoneNumber";
 extern NSString *const FUUpdateKeyDisplayName = @"displayName";
 extern NSString *const FUUpdateKeyPhotoURL = @"photoURL";

 extern NSString *const FUErrorDomain = @"com.yourapp.FUManagerError";
 extern NSErrorUserInfoKey const FUErrorDetailedDescriptionKey = @"FUDetailedDescription";

 NS_ASSUME_NONNULL_END
 
 
 
 * ADD LOGS TO IMPORTANT LINES
 * ONLY USERS MAGAER .m and .h files  --->>> FULL , CLEANED, FOLLOW BEST PRACTICS
 
 
 
 
 
 
 
 
 
 
 
 Firestore structure: Is each user stored in the UsersCol/<uid> document? yes

 Do you use Firebase Authentication as the source of truth for login identity? Or are you storing user credentials elsewhere? yes Firebase Authentication

 Auth method support: You mentioned Gmail, Apple ID, and mobile number. Should I include helper methods for each login provider explicitly inside UserManager, or is login handled elsewhere? yes add it

 Image upload: Are images stored in Firebase Storage, and should the upload method also return a downloadable URL (as you hinted with uploadUserImage:userImageName:)? yes sure , and on fire Storage this path /users/{uid}/

 Should I preserve all XLForm dependencies in the new version or remove them? (You use it in your model) remove them
 
 
 
 */
