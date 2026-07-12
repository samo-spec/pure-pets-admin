//
//  PPServiceCell.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPServiceModel;

@interface PPServiceCell : UITableViewCell

+ (NSString *)reuseID;
+ (CGFloat)preferredHeight;
- (void)configureWithService:(PPServiceModel *)service;

@end

NS_ASSUME_NONNULL_END
