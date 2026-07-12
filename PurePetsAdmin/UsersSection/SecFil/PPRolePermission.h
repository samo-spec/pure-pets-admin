//
//  PPRolePermission.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 02/09/2025.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UserRole) {
    UserRoleUnknown      = 0,
    UserRoleUser         = 1,
    UserRoleOwner        = 2,
    UserRoleVet          = 3,
    UserRoleModerator    = 4,
    UserRoleAdmin        = 5,
    UserRoleStoreManager = 6,
    UserRoleFoodManager  = 7,
    UserRoleSuperAdmin   = 8
};

typedef NS_OPTIONS(NSUInteger, UserPermission) {
    UserPermissionNone           = 0,
    UserPermissionPostAds        = 1 << 0,
    UserPermissionSellNew        = 1 << 1,
    UserPermissionSellUsed       = 1 << 2,
    UserPermissionAdoption       = 1 << 3,
    UserPermissionManageStore    = 1 << 4,
    UserPermissionModeration     = 1 << 5,
    UserPermissionAdminAll       = 1 << 6,
    UserPermissionManageFood     = 1 << 7,
    UserPermissionManageServices = 1 << 8,
    UserPermissionProduction     = 1 << 9,
    // Deprecated aliases kept for older call-sites.
    UserPermissionManageUsers          = UserPermissionAdoption,
    UserPermissionManageNotificatiuons = UserPermissionModeration,
    UserPermissionManageBanners        = UserPermissionPostAds,
};

// Canonical Firestore permission keys.
extern NSString * const kPermAdminAll;
extern NSString * const kPermPostAds;
extern NSString * const kPermSellNew;
extern NSString * const kPermSellUsed;
extern NSString * const kPermAdoption;
extern NSString * const kPermManageStore;
extern NSString * const kPermModeration;
extern NSString * const kPermManageFood;
extern NSString * const kPermManageServices;
extern NSString * const kPermProduction;

// Deprecated key aliases (mapped to canonical keys).
extern NSString * const kPermManageUsers;
extern NSString * const kPermManageNotificatiuons;
extern NSString * const kPermManageBanners;

#pragma mark - Firestore Paths

static NSString * const kPPUsersCol           = @"UsersCol";
static NSString * const kPPPermsSubCol        = @"permissions";
static NSString * const kPPLegacyPermsSubCol  = @"PermisstionsCol";
static NSString * const kPPLegacyPermsSubColAlt = @"PermissionsCol";
static NSString * const kPPPermAdminAll       = @"AdminAll";
static NSString * const kPPBranchesCol        = @"branches";
static NSString * const kPPAgentsCol          = @"agents";

#pragma mark - Role Helpers

static inline BOOL PPIsAllowedAdminRole(UserRole r) {
    switch (r) {
        case UserRoleOwner:
        case UserRoleVet:
        case UserRoleModerator:
        case UserRoleAdmin:
        case UserRoleStoreManager:
        case UserRoleFoodManager:
        case UserRoleSuperAdmin:
            return YES;
        default:
            return NO;
    }
}

static inline UserRole PPParseRoleFromUserDoc(NSDictionary *doc) {
    if (!doc) return UserRoleUnknown;

    NSDictionary *claims = [doc[@"claims"] isKindOfClass:NSDictionary.class] ? (NSDictionary *)doc[@"claims"] : nil;

    NSNumber *roleVal = (NSNumber *)doc[@"roleValue"];
    if (![roleVal isKindOfClass:NSNumber.class]) {
        roleVal = (NSNumber *)doc[@"role"];
    }
    if (![roleVal isKindOfClass:NSNumber.class]) {
        roleVal = (NSNumber *)claims[@"roleValue"];
    }
    if (![roleVal isKindOfClass:NSNumber.class]) {
        roleVal = (NSNumber *)claims[@"role"];
    }
    if ([roleVal isKindOfClass:NSNumber.class]) {
        return (UserRole)roleVal.integerValue;
    }

    BOOL isSuperAdmin = [doc[@"isSuperAdmin"] boolValue] ||
                        [doc[@"superAdmin"] boolValue] ||
                        [doc[@"superadmin"] boolValue] ||
                        [claims[@"isSuperAdmin"] boolValue] ||
                        [claims[@"superAdmin"] boolValue] ||
                        [claims[@"superadmin"] boolValue];
    if (isSuperAdmin) return UserRoleSuperAdmin;

    BOOL isAdmin = [doc[@"isAdmin"] boolValue] ||
                   [doc[@"admin"] boolValue] ||
                   [claims[@"isAdmin"] boolValue] ||
                   [claims[@"admin"] boolValue];
    if (isAdmin) return UserRoleAdmin;

    NSString *name = (NSString *)doc[@"roleName"];
    if (![name isKindOfClass:NSString.class]) {
        name = (NSString *)doc[@"role"];
    }
    if (![name isKindOfClass:NSString.class]) {
        name = (NSString *)doc[@"staffRole"];
    }
    if (![name isKindOfClass:NSString.class]) {
        name = (NSString *)claims[@"roleName"];
    }
    if (![name isKindOfClass:NSString.class]) {
        name = (NSString *)claims[@"role"];
    }
    if (![name isKindOfClass:NSString.class]) {
        name = (NSString *)claims[@"staffRole"];
    }
    if ([name isKindOfClass:NSString.class]) {
        NSString *n = name.lowercaseString;
        if ([n isEqualToString:@"admin"])        return UserRoleAdmin;
        if ([n isEqualToString:@"superadmin"])   return UserRoleSuperAdmin;
        if ([n isEqualToString:@"super_admin"])  return UserRoleSuperAdmin;
        if ([n isEqualToString:@"moderator"])    return UserRoleModerator;
        if ([n isEqualToString:@"owner"])        return UserRoleOwner;
        if ([n isEqualToString:@"operations_manager"]) return UserRoleModerator;
        if ([n isEqualToString:@"inventory_manager"])  return UserRoleStoreManager;
        if ([n isEqualToString:@"payments_manager"])   return UserRoleAdmin;
        if ([n isEqualToString:@"support_agent"])      return UserRoleVet;
        if ([n isEqualToString:@"viewer"])             return UserRoleUser;
        if ([n isEqualToString:@"vet"])          return UserRoleVet;
        if ([n isEqualToString:@"storemanager"]) return UserRoleStoreManager;
        if ([n isEqualToString:@"foodmanager"])  return UserRoleFoodManager;
    }
    return UserRoleUser;
}

static inline BOOL PPBoolFromClaim(NSDictionary *claims, NSString *key) {
    id val = claims[key];
    if (!val || val == [NSNull null]) return NO;
    if ([val isKindOfClass:[NSNumber class]]) return [(NSNumber *)val boolValue];
    if ([val isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)val lowercaseString];
        return [s isEqualToString:@"1"] || [s isEqualToString:@"true"] || [s isEqualToString:@"yes"];
    }
    return NO;
}

@interface PPRolePermission : NSObject
+ (NSString *)localizedRoleName:(UserRole)role;
+ (NSString *)localizedRoleDescription:(UserRole)role;
+ (NSArray<NSString *> *)defaultPermissionsForRole:(UserRole)role;
+ (NSString *)roleName:(UserRole)role;
+ (BOOL)role:(UserRole)role hasPermission:(NSString *)permKey;
@end

@interface PermissionAction : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *labelEn;
@property (nonatomic, copy) NSString *labelAr;
@end

@interface PermissionModule : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *labelEn;
@property (nonatomic, copy) NSString *labelAr;
@property (nonatomic, copy) NSArray<PermissionAction *> *actions;
@end

NS_ASSUME_NONNULL_END
