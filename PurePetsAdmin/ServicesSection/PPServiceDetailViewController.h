//
//  PPServiceDetailViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPServiceModel;

@interface PPServiceDetailViewController : UIViewController

- (instancetype)initWithService:(PPServiceModel *)service;

@end

NS_ASSUME_NONNULL_END
