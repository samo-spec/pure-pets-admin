//
//  AdminService.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 06/09/2025.
//


// In AdminService.h
#import <Foundation/Foundation.h>
#import "PPRolePermission.h"
#import "PPStaffAuth.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^AdminServiceCompletion)(NSDictionary * _Nullable result, NSError * _Nullable error);

@interface AdminService : NSObject

#pragma mark - Staff Management (new — calls staff Cloud Functions)

+ (void)createStaffMemberWithEmail:(NSString *)email
                              name:(NSString *)name
                          password:(NSString *)password
                              role:(PPStaffRole)role
                       permissions:(nullable NSArray<NSString *> *)permissions
                             scope:(nullable NSDictionary *)scope
                        completion:(AdminServiceCompletion)completion;

+ (void)assignExistingUserAsStaff:(NSString *)uid
                             role:(PPStaffRole)role
                      permissions:(nullable NSArray<NSString *> *)permissions
                            scope:(nullable NSDictionary *)scope
                       completion:(AdminServiceCompletion)completion;

+ (void)updateStaffMember:(NSString *)uid
                  updates:(NSDictionary *)updates
               completion:(AdminServiceCompletion)completion;

+ (void)disableStaffMember:(NSString *)uid
                completion:(AdminServiceCompletion)completion;

#pragma mark - User Access Management (new)

+ (void)updateUserFeatures:(NSString *)uid
                  features:(NSDictionary *)features
                completion:(AdminServiceCompletion)completion;

+ (void)updateUserRestrictions:(NSString *)uid
                  restrictions:(NSDictionary *)restrictions
                    completion:(AdminServiceCompletion)completion;

+ (void)updateUserStatus:(NSString *)uid
                  status:(NSString *)status
              completion:(AdminServiceCompletion)completion;

+ (void)updateUserSubscription:(NSString *)uid
                  subscription:(NSDictionary *)subscription
                    completion:(AdminServiceCompletion)completion;

+ (void)updateUserVerified:(NSString *)uid
                  verified:(BOOL)verified
                completion:(AdminServiceCompletion)completion;

#pragma mark - Legacy (kept for migration bridge — will be removed)

+ (void)setAdminFor:(NSString *)emailOrUID
               isUID:(BOOL)isUID
               admin:(BOOL)admin
          superAdmin:(BOOL)superAdmin
          completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

+ (void)setUserPermissionsForUser:(NSString *)emailOrUID
                        isUID:(BOOL)isUID
                         role:(UserRole)role
                       admin:(BOOL)admin
                  superAdmin:(BOOL)superAdmin
                      blocked:(BOOL)blocked
                   completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

+ (void)setUserRoleFor:(NSString *)emailOrUID
                 isUID:(BOOL)isUID
                  role:(UserRole)role
            completion:(AdminServiceCompletion)completion;

+ (void)setAdmin:(NSString *)emailOrUID
           isUID:(BOOL)isUID
        setAdmin:(BOOL)admin
      completion:(AdminServiceCompletion)completion;

+ (void)setUserBlockedFor:(NSString *)emailOrUID
                   isUID:(BOOL)isUID
                  Blocked:(BOOL)blocked
              completion:(AdminServiceCompletion)completion;

+ (void)setUserPermissionsFor:(NSString *)emailOrUID
                        isUID:(BOOL)isUID
                 customClaims:(NSDictionary * _Nullable)claims
                   completion:(AdminServiceCompletion)completion;

+ (void)updateUserClaimsFor:(NSString *)emailOrUID
                      isUID:(BOOL)isUID
                     claims:(NSDictionary *)claims
                 completion:(void(^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END


