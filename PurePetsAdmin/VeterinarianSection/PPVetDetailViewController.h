//
//  PPVetDetailViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPVetModel;

@interface PPVetDetailViewController : UIViewController
- (instancetype)initWithVet:(PPVetModel *)vet;
@end

NS_ASSUME_NONNULL_END
