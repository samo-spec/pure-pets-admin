#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * const PPAdminRouteToDriverTaskNotification;
FOUNDATION_EXPORT NSString * const PPDriverTasksDidChangeNotification;
/// Shared push/inbox parser. Returns an empty dictionary for a non-driver or malformed route.
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *PPDriverTaskRoute(NSDictionary *payload);
@interface PPDriverWorkspaceViewController : UIViewController
- (instancetype)initWithTaskID:(nullable NSString *)taskID authority:(nullable NSString *)authority;
@property (nonatomic, copy, nullable) void (^onOpenTask)(NSString *taskID, NSString *authority);
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, copy, nullable) void (^onNotifications)(void);
@end
NS_ASSUME_NONNULL_END
