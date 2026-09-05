//
//  PPStaffAuth.h
//  PurePetsAdmin
//
//  Staff authorization is sourced from canonical `staff_users/{uid}` records.
//  A staff record must be explicitly active and permissioned before it can enter
//  the Admin workspace. `UsersCol` remains profile compatibility data only.
//

#import <Foundation/Foundation.h>
#import "PPStaffAuthCatalog.generated.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Staff Status

typedef NSString * PPStaffStatus NS_TYPED_ENUM;

extern PPStaffStatus const PPStaffStatusActive;
extern PPStaffStatus const PPStaffStatusDisabled;

#pragma mark - Staff Document Model

@interface PPStaffDoc : NSObject

@property (nonatomic, copy) NSString *uid;
@property (nonatomic, copy) NSString *accountType;
@property (nonatomic, copy) PPStaffRole role;
@property (nonatomic, copy) NSString *roleIdentifier;
@property (nonatomic, copy, nullable) NSString *roleName;
@property (nonatomic, copy) PPStaffStatus status;
@property (nonatomic, copy) NSArray<NSString *> *permissions;
@property (nonatomic, copy, nullable) NSDictionary *scope;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *email;
@property (nonatomic, copy, nullable) NSString *phone;
@property (nonatomic, copy, nullable) NSString *photoURL;
@property (nonatomic, assign, getter=isVerified) BOOL verified;
@property (nonatomic, assign) NSInteger claimsVersion;
@property (nonatomic, copy, nullable) NSString *updatedBy;

@property (nonatomic, copy, readonly) NSArray<NSString *> *assignedBranchIDs;
@property (nonatomic, copy, readonly, nullable) NSString *defaultBranchID;
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, NSArray<NSString *> *> *branchPermissions;

- (instancetype)initWithDictionary:(NSDictionary *)dict uid:(NSString *)uid;
- (BOOL)isActive;
- (BOOL)isAdmin;
- (BOOL)hasGlobalScope;
- (BOOL)canAccessStaffWorkspace;
- (BOOL)hasPermission:(NSString *)perm;
- (BOOL)hasAnyPermission:(NSArray<NSString *> *)perms;
- (BOOL)hasAccessToBranch:(NSString *)branchID;
- (BOOL)hasPermission:(NSString *)perm inBranch:(NSString * _Nullable)branchID;
- (NSString *)localizedRoleName;

@end

#pragma mark - PPStaffAuth Singleton

@protocol FIRListenerRegistration;

typedef void (^PPStaffDocCompletion)(PPStaffDoc * _Nullable doc, NSError * _Nullable error);
typedef void (^PPStaffListCompletion)(NSArray<PPStaffDoc *> * _Nullable docs, NSError * _Nullable error);

@interface PPStaffAuth : NSObject

+ (instancetype)shared;

/// Fetch a single staff doc by UID.
- (void)fetchStaffDoc:(NSString *)uid completion:(PPStaffDocCompletion)completion;

/// Listen to a single staff doc (real-time updates).
- (id<FIRListenerRegistration>)listenStaffDoc:(NSString *)uid
                                     onChange:(PPStaffDocCompletion)block;

/// Fetch all active staff members from canonical staff_users.
- (void)fetchAllStaff:(PPStaffListCompletion)completion;

/// Listen to all staff members from canonical staff_users.
- (id<FIRListenerRegistration>)listenAllStaff:(PPStaffListCompletion)block;

/// Check if current user is active staff.
- (void)checkCurrentUserIsStaff:(void(^)(BOOL isStaff, PPStaffDoc * _Nullable doc))completion;

/// Get cached staff doc for current user (nil if not fetched yet).
@property (nonatomic, strong, nullable, readonly) PPStaffDoc *cachedCurrentStaff;

/// Refresh cached staff doc for current user.
- (void)refreshCurrentStaff:(nullable PPStaffDocCompletion)completion;

#pragma mark - Role Mapping (legacy → new)

/// Map legacy UserRole integer to new staff role string.
+ (PPStaffRole)staffRoleFromLegacyRole:(NSInteger)legacyRole;

/// Map new staff role string to legacy UserRole integer (for backward compat).
+ (NSInteger)legacyRoleFromStaffRole:(PPStaffRole)staffRole;

/// Default permissions for a staff role.
+ (NSArray<NSString *> *)defaultPermissionsForStaffRole:(PPStaffRole)role;

/// All admin roles.
+ (BOOL)isAdminRole:(PPStaffRole)role;

/// Localized role label.
+ (NSString *)localizedRoleName:(PPStaffRole)role;

@end

/// Resolves a requested permission key against granted catalog permissions,
/// taking into account canonical hierarchy and fine-grained sub-actions across the 18 modules (45 permissions).
FOUNDATION_EXPORT BOOL PPStaffMatchesPermission(NSArray<NSString *> * _Nullable granted, NSString * _Nullable perm);

NS_ASSUME_NONNULL_END
