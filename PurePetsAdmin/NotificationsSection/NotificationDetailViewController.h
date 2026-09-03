//
//  NotificationDetailViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//

#import <UIKit/UIKit.h>
#import "NotificationModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface NotificationDetailViewController : UIViewController

@property (nonatomic, copy, nullable) void (^onDismiss)(void);

- (instancetype)initWithModel:(NotificationModel *)model userID:(NSString *)uid;
- (instancetype)initWithModel:(NotificationModel *)model userID:(NSString *)uid onDismiss:(nullable void (^)(void))onDismiss;

@end

NS_ASSUME_NONNULL_END