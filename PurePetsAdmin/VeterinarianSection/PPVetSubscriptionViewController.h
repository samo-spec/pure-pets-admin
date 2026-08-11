//
//  PPVetSubscriptionViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>
#import <XLForm/XLForm.h>

NS_ASSUME_NONNULL_BEGIN

@class PPVetModel;

@interface PPVetSubscriptionViewController : XLFormViewController
- (instancetype)initWithVet:(PPVetModel *)vet;
@end

NS_ASSUME_NONNULL_END
