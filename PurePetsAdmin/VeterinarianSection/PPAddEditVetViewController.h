//
//  PPAddEditVetViewController.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPVetModel;

@interface PPAddEditVetViewController : XLFormViewController
@property (nonatomic, strong, nullable) PPVetModel *vetToEdit;
- (instancetype)initWithVet:(PPVetModel * _Nullable)vet;
@end

NS_ASSUME_NONNULL_END
