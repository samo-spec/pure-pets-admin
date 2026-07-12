//
//  PPAddEditServiceViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPServiceModel;

@interface PPAddEditServiceViewController : XLFormViewController

- (instancetype)initWithService:(nullable PPServiceModel *)service;

@end

NS_ASSUME_NONNULL_END
