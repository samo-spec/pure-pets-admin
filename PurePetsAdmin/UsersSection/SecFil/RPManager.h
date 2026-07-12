//
//  RPManager.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 02/09/2025.
//


//
//  RPManager.h
//  PurePetsAdmin
//
//  Roles & Permissions (clean, focused)
//

#import <Foundation/Foundation.h>

@class FIRCollectionReference;
@class FIRDocumentReference;
@class FIRFirestore;
@class FIRFunctions;
@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@class UserModel;

typedef void (^UserCreationCompletion)(UserModel * _Nullable user, NSError * _Nullable error);

// If your UserRole enum lives elsewhere (e.g. UserModel.h), import it.
// Adjust the path if needed.

// Reuse your existing block types or keep local ones:
typedef void (^RBErrorBlock)(NSError * _Nullable error);
typedef void (^RBAnyBlock)(id _Nullable obj, NSError * _Nullable error);

/// Firestore base paths
extern NSString * const kUsersCol;          // @"UsersCol"
extern NSString * const kRPSubCol;          // @"RPSubCol"
extern NSString * const kRPRoleDoc;         // @"role"
extern NSString * const kRPPermissionsCol;  // @"permissions"

/// Completion types
typedef void (^RPVoidError)(NSError * _Nullable error);
typedef void (^RPBoolError)(BOOL yes, NSError * _Nullable error);
typedef void (^RPPermsError)(NSDictionary<NSString *, NSNumber *> * _Nullable perms,
                             NSError * _Nullable error);
typedef void (^RPRoleError)(UserRole role, NSString * _Nullable roleName,
                            NSError * _Nullable error);

@interface StaffRoleTemplate : NSObject
@property (nonatomic, copy) NSString *id;
@property (nonatomic, copy) NSDictionary *name; // @{"en":..., "ar":...}
@property (nonatomic, copy) NSDictionary *roleDescription;
@property (nonatomic, copy) NSArray<NSString *> *permissions;
@end

@interface RPManager : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) FIRFirestore *db;

#pragma mark - Staff Roles (Custom Roles)
- (void)listenStaffRoles:(void(^)(NSArray<StaffRoleTemplate *> * _Nullable roles, NSError * _Nullable error))completion;
- (void)createStaffRole:(NSDictionary *)data completion:(void(^)(NSString * _Nullable roleID, NSError * _Nullable error))completion;
- (void)updateStaffRole:(NSString *)roleID data:(NSDictionary *)data completion:(void(^)(NSError * _Nullable error))completion;
- (void)deleteStaffRole:(NSString *)roleID completion:(void(^)(NSError * _Nullable error))completion;


#pragma mark - Paths (you won’t call these directly usually)
- (FIRDocumentReference *)userDoc:(NSString *)uid;
- (FIRCollectionReference *)rpPermisstionsCol:(NSString *)uid;                  // UsersCol/{uid}/RP/permissions

#pragma mark - Roles (store in RP/meta)
- (void)setRole:(UserRole)role
         forUID:(NSString *)uid
     completion:(void(^ _Nullable)(NSError * _Nullable error))completion;

- (void)fetchRoleForUID:(NSString *)uid
             completion:(void(^)(UserRole role, NSDictionary * _Nullable meta, NSError * _Nullable error))completion;

#pragma mark - Permissions (subcollection)
- (void)setPermissionNamed:(NSString *)permName
                    forUID:(NSString *)uid
                   allowed:(BOOL)allowed
                completion:(void(^ _Nullable)(NSError * _Nullable error))completion;

- (void)fetchPermissionsForUID:(NSString *)uid
                    completion:(void(^)(NSDictionary<NSString *, NSNumber *> * _Nullable perms,
                                        NSError * _Nullable error))completion;

- (id<FIRListenerRegistration>)listenPermissionsForUID:(NSString *)uid
                                              onChange:(void(^)(NSDictionary<NSString *, NSNumber *> *perms,
                                                                NSError * _Nullable error))block;



/// ---------- Create user (Auth + Firestore + RP) ----------
- (void)createUserWithEmail:(NSString *)email
                   password:(NSString *)password
                   username:(NSString *)username
                       role:(UserRole)role
                permissions:(nullable NSDictionary<NSString *, NSNumber *> *)perms // optional overrides
                    isAdmin:(BOOL)isAdmin                                         // optional mirror
                 completion:(UserCreationCompletion)completion;;

/// ---------- Role (set & fetch) ----------
- (void)setRole:(UserRole)role
         forUID:(NSString *)uid
        roleName:(nullable NSString *)roleName // if nil, infer from enum
applyDefaultPermissions:(BOOL)applyDefaults   // YES → write default permissions
      completion:(RPVoidError)completion;



/// ---------- Permissions (set / fetch / listen / check) ----------
- (void)setPermission:(NSString *)permName
               forUID:(NSString *)uid
              allowed:(BOOL)allowed
           completion:(RPVoidError)completion;

- (void)allowPermission:(NSString *)permName
                 forUID:(NSString *)uid
             completion:(RPVoidError)completion;

- (void)denyPermission:(NSString *)permName
                forUID:(NSString *)uid
            completion:(RPVoidError)completion;

/// Async check a single permission
- (void)checkPermission:(NSString *)permName
                 forUID:(NSString *)uid
             completion:(RPBoolError)completion;

/// Convenience: default permission keys for a role
- (NSArray<NSString *> *)defaultPermissionsForRole:(UserRole)role;

/// Block/unblock user and keep UsersCol + custom-claims in sync.
- (void)setBlocked:(BOOL)blocked
            forUID:(NSString *)uid
            reason:(nullable NSString *)reason
          duration:(nullable NSString *)duration
        completion:(RPVoidError)completion;

/// Remove user from UsersCol (soft-hard hybrid): block first, then delete doc + permissions.
- (void)removeUserByUID:(NSString *)uid
             completion:(RPVoidError)completion;


- (FIRCollectionReference *)permsCol:(NSString *)uid;
- (FIRDocumentReference *)permDoc:(NSString *)uid name:(NSString *)name;


/// Firebase Functions (region set in init)
@property (nonatomic, strong) FIRFunctions *functions;

/// Get current user's ID token claims (forces refresh)
- (void)fetchIDTokenClaims:(void(^)(NSDictionary * _Nullable claims,
                                    NSError * _Nullable error))completion;

#pragma mark - Role → Permission helpers

/// Returns YES if the given role's default permissions include `permKey`.
- (BOOL)role:(UserRole)role hasPermission:(NSString *)permKey;


/// Optional shim so older call sites still compile; just forwards to setRole:forUID:
- (void)setRoleValue:(UserRole)role
           roleName:(nullable NSString *)roleName
             forUID:(NSString *)uid
         completion:(void(^)(NSError * _Nullable error))completion;


- (void)setUserRole:(NSString *)functionName
         identifier:(NSString *)identifier
             status:(BOOL)status
         completion:(void (^)(BOOL success, NSString *message))completion;

- (void)listenForRoleChangesOfUser:(NSString *)uid
                        completion:(void(^)(UserModel * _Nullable user, NSError * _Nullable error))completion;
@end



NS_ASSUME_NONNULL_END
