#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PPAdminSessionBridgeErrorDomain;

typedef NS_ENUM(NSInteger, PPAdminSessionBridgeErrorCode) {
    PPAdminSessionBridgeErrorUnauthorized = 403,
    PPAdminSessionBridgeErrorMissingUser = 404,
    PPAdminSessionBridgeErrorDisabled = 423,
};

NS_SWIFT_SENDABLE
@interface PPAdminSessionSnapshot : NSObject

@property (nonatomic, copy, readonly) NSString *uid;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *email;
@property (nonatomic, copy, readonly) NSString *roleIdentifier;
@property (nonatomic, copy, readonly) NSString *localizedRoleName;
@property (nonatomic, copy, readonly) NSArray<NSString *> *permissions;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *scope;
@property (nonatomic, assign, readonly) BOOL grantsAllPermissions;

- (BOOL)hasPermission:(NSString *)permission;
- (BOOL)hasAnyPermission:(NSArray<NSString *> *)permissions;
- (BOOL)hasGlobalScope;

@end

NS_SWIFT_SENDABLE
@interface PPAdminSessionObservation : NSObject
- (void)invalidate;
@end

typedef void (^PPAdminSessionRestoreCompletion)(PPAdminSessionSnapshot * _Nullable snapshot,
                                                NSError * _Nullable error);

@interface PPAdminSessionBridge : NSObject

+ (void)restoreCurrentSessionWithCompletion:(PPAdminSessionRestoreCompletion)completion
    NS_SWIFT_NAME(restoreCurrentSession(completion:));
+ (PPAdminSessionObservation *)observeCurrentSessionWithChange:(PPAdminSessionRestoreCompletion)change
    NS_SWIFT_NAME(observeCurrentSession(onChange:));
+ (NSString *)localizedRoleNameForRoleIdentifier:(NSString *)roleIdentifier
    NS_SWIFT_NAME(localizedRoleName(for:));
+ (void)signOutWithCompletion:(void (^ _Nullable)(NSError * _Nullable error))completion
    NS_SWIFT_NAME(signOut(completion:));

@end

NS_ASSUME_NONNULL_END
