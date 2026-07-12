#ifndef PPFirebaseCompat_h
#define PPFirebaseCompat_h

#import <Foundation/Foundation.h>

// Firebase iOS 11+ ships several Swift-backed pods whose generated Objective-C
// compatibility headers are not always present in this workspace. This header
// provides the stable Objective-C surface the admin app relies on, while using
// direct non-module headers for Firestore types.

#if __has_include(<FirebaseAuth/FirebaseAuth.h>)
#import <FirebaseAuth/FirebaseAuth.h>
#define PP_FIREBASE_AUTH_IMPORTED 1
#define PP_FIREBASE_AUTH_ERRORS_IMPORTED 1
#elif __has_include("FirebaseAuth.h")
#import "FirebaseAuth.h"
#define PP_FIREBASE_AUTH_IMPORTED 1
#define PP_FIREBASE_AUTH_ERRORS_IMPORTED 1
#else
#if __has_include(<FirebaseAuth/FIRAuth.h>)
#import <FirebaseAuth/FIRAuth.h>
#define PP_FIREBASE_AUTH_IMPORTED 1
#endif
#if __has_include("FIRAuth.h")
#import "FIRAuth.h"
#define PP_FIREBASE_AUTH_IMPORTED 1
#endif

#if __has_include(<FirebaseAuth/FIRUser.h>)
#import <FirebaseAuth/FIRUser.h>
#endif
#if __has_include("FIRUser.h")
#import "FIRUser.h"
#endif

#if __has_include(<FirebaseAuth/FIRAuthErrors.h>)
#import <FirebaseAuth/FIRAuthErrors.h>
#define PP_FIREBASE_AUTH_ERRORS_IMPORTED 1
#elif __has_include("FIRAuthErrors.h")
#import "FIRAuthErrors.h"
#define PP_FIREBASE_AUTH_ERRORS_IMPORTED 1
#endif
#endif

#if __has_include("FirebaseCore.h")
#import "FirebaseCore.h"
#define PP_FIREBASE_CORE_TYPES_IMPORTED 1
#endif
#if !defined(PP_FIREBASE_CORE_TYPES_IMPORTED) && __has_include("FIRApp.h")
#import "FIRApp.h"
#endif
#if !defined(PP_FIREBASE_CORE_TYPES_IMPORTED) && __has_include("FIROptions.h")
#import "FIROptions.h"
#define PP_FIREBASE_CORE_TYPES_IMPORTED 1
#endif

#if __has_include("FIRFirestore.h")
#import "FIRFirestore.h"
#endif
#if __has_include("FIRFirestoreErrors.h")
#import "FIRFirestoreErrors.h"
#define PP_FIREBASE_FIRESTORE_ERRORS_IMPORTED 1
#endif
#if __has_include("FIRQuery.h")
#import "FIRQuery.h"
#endif
#if __has_include("FIRCollectionReference.h")
#import "FIRCollectionReference.h"
#endif
#if __has_include("FIRDocumentReference.h")
#import "FIRDocumentReference.h"
#endif
#if __has_include("FIRDocumentSnapshot.h")
#import "FIRDocumentSnapshot.h"
#endif
#if __has_include("FIRQuerySnapshot.h")
#import "FIRQuerySnapshot.h"
#endif
#if __has_include("FIRDocumentChange.h")
#import "FIRDocumentChange.h"
#endif
#if __has_include("FIRSnapshotMetadata.h")
#import "FIRSnapshotMetadata.h"
#endif
#if __has_include("FIRFieldValue.h")
#import "FIRFieldValue.h"
#endif
#if __has_include("FIRWriteBatch.h")
#import "FIRWriteBatch.h"
#endif
#if __has_include("FIRTransaction.h")
#import "FIRTransaction.h"
#endif
#if __has_include("FIRFirestoreSource.h")
#import "FIRFirestoreSource.h"
#endif
#if __has_include("FIRListenerRegistration.h")
#import "FIRListenerRegistration.h"
#endif
#if __has_include("FIRTimestamp.h")
#import "FIRTimestamp.h"
#endif

#if __has_include("FIRStorageTypedefs.h")
#import "FIRStorageTypedefs.h"
#define PP_FIREBASE_STORAGE_TYPEDEFS_IMPORTED 1
#endif

NS_ASSUME_NONNULL_BEGIN

#ifndef PP_FIREBASE_AUTH_ERRORS_IMPORTED
FOUNDATION_EXPORT NSString *const FIRAuthErrorDomain;
FOUNDATION_EXPORT NSString *const FIRAuthErrorUserInfoNameKey;

typedef NS_ENUM(NSInteger, FIRAuthErrorCode) {
    FIRAuthErrorCodeInvalidCredential = 17004,
    FIRAuthErrorCodeUserDisabled = 17005,
    FIRAuthErrorCodeWrongPassword = 17009,
    FIRAuthErrorCodeUserNotFound = 17011,
    FIRAuthErrorCodeNetworkError = 17020,
    FIRAuthErrorCodeInternalError = 17999,
};
#endif

#ifndef PP_FIREBASE_FIRESTORE_ERRORS_IMPORTED
FOUNDATION_EXPORT NSString * const FIRFirestoreErrorDomain;

#endif

#ifndef PP_FIREBASE_AUTH_IMPORTED
@protocol FIRUserInfo <NSObject>
@property(nonatomic, copy, readonly, nullable) NSString *providerID;
@property(nonatomic, copy, readonly, nullable) NSString *uid;
@property(nonatomic, copy, readonly, nullable) NSString *displayName;
@property(nonatomic, copy, readonly, nullable) NSString *email;
@property(nonatomic, strong, readonly, nullable) NSURL *photoURL;
@end
#endif


FOUNDATION_EXPORT NSString * const FIRFunctionsErrorDomain;
FOUNDATION_EXPORT NSString * const FIRFunctionsErrorDetailsKey;

#ifndef PP_FIREBASE_STORAGE_TYPEDEFS_IMPORTED
typedef NSString *FIRStorageHandle;
typedef void (^FIRStorageVoidDataError)(NSData *_Nullable data, NSError *_Nullable error);
typedef void (^FIRStorageVoidError)(NSError *_Nullable error);
typedef void (^FIRStorageVoidMetadataError)(id _Nullable metadata, NSError *_Nullable error);
typedef void (^FIRStorageVoidURLError)(NSURL *_Nullable URL, NSError *_Nullable error);
#endif

#ifndef PP_FIREBASE_AUTH_IMPORTED
@interface FIRAuthDataResult : NSObject
@property(nonatomic, strong, readonly, nullable) FIRUser *user;
@end

@interface FIRAuthTokenResult : NSObject
@property(nonatomic, copy, readonly, nullable) NSDictionary<NSString *, id> *claims;
@end

@interface FIRUserProfileChangeRequest : NSObject
@property(nonatomic, copy, nullable) NSString *displayName;
@property(nonatomic, strong, nullable) NSURL *photoURL;
- (void)commitChangesWithCompletion:(FIRUserProfileChangeCallback)completion;
@end

@interface FIRUser : NSObject
@property(nonatomic, copy, readonly) NSString *uid;
@property(nonatomic, copy, readonly, nullable) NSString *email;
@property(nonatomic, copy, readonly, nullable) NSString *displayName;
@property(nonatomic, strong, readonly, nullable) NSURL *photoURL;
@property(nonatomic, assign, readonly, getter=isAnonymous) BOOL anonymous;
@property(nonatomic, assign, readonly, getter=isEmailVerified) BOOL emailVerified;
@property(nonatomic, copy, readonly, nullable) NSArray<id<FIRUserInfo>> *providerData;
- (void)getIDTokenWithCompletion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;
- (void)getIDTokenForcingRefresh:(BOOL)forceRefresh
                      completion:(void (^)(NSString * _Nullable token, NSError * _Nullable error))completion;
- (void)getIDTokenResultWithCompletion:(FIRAuthTokenResultCallback)completion;
- (void)getIDTokenResultForcingRefresh:(BOOL)forceRefresh completion:(FIRAuthTokenResultCallback)completion;
- (void)reloadWithCompletion:(void (^)(NSError * _Nullable error))completion;
- (void)updateEmail:(NSString *)email completion:(FIRUserUpdateCallback)completion;
- (void)updatePassword:(NSString *)password completion:(FIRUserUpdateCallback)completion;
- (void)deleteWithCompletion:(void (^)(NSError * _Nullable error))completion;
- (void)reauthenticateWithCredential:(FIRAuthCredential *)credential
                          completion:(FIRAuthDataResultCallback)completion;
- (void)linkWithCredential:(FIRAuthCredential *)credential
                completion:(FIRAuthDataResultCallback)completion;
- (void)unlinkFromProvider:(NSString *)provider completion:(FIRAuthResultCallback)completion;
- (FIRUserProfileChangeRequest *)profileChangeRequest;
@end

@interface FIRAuth : NSObject
@property(nonatomic, strong, readonly, nullable) FIRUser *currentUser;
+ (nullable instancetype)auth;
+ (nullable instancetype)authWithApp:(FIRApp *)app;
- (FIRAuthStateDidChangeListenerHandle)addAuthStateDidChangeListener:(FIRAuthStateDidChangeListenerBlock)listener;
- (void)removeAuthStateDidChangeListener:(FIRAuthStateDidChangeListenerHandle)listenerHandle;
- (void)createUserWithEmail:(NSString *)email
                   password:(NSString *)password
                 completion:(FIRAuthDataResultCallback)completion;
- (void)signInWithEmail:(NSString *)email
               password:(NSString *)password
             completion:(FIRAuthDataResultCallback)completion;
- (void)sendPasswordResetWithEmail:(NSString *)email completion:(FIRSendPasswordResetCallback)completion;
- (BOOL)signOut:(NSError * _Nullable * _Nullable)error;
@end

@interface FIREmailAuthProvider : NSObject
+ (FIRAuthCredential *)credentialWithEmail:(NSString *)email password:(NSString *)password;
@end

@interface FIRGoogleAuthProvider : NSObject
+ (FIRAuthCredential *)credentialWithIDToken:(NSString *)idToken
                                 accessToken:(NSString *)accessToken;
@end
#endif

@class FIRStorageReference;

NS_ASSUME_NONNULL_END

#endif
