//
//  PPAuditLogViewController.h
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Sovereign Audit & Forensic Command Center.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPAuditLogViewController : UIViewController

@property (nonatomic, copy, nullable) void (^onDismiss)(void);

- (instancetype)initWithOnDismiss:(nullable void (^)(void))onDismiss;

@end

NS_ASSUME_NONNULL_END
