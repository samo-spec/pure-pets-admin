//
//  PPVetSubscriptionViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPVetModel;

@interface PPVetSubscriptionViewController : XLFormViewController
- (instancetype)initWithVet:(PPVetModel *)vet;
@end

NS_ASSUME_NONNULL_END
