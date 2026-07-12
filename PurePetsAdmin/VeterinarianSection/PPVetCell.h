//
//  PPVetCell.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPVetModel;

@interface PPVetCell : UITableViewCell

@property (nonatomic, strong, readonly) UIImageView *logoView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic, strong, readonly) UILabel *statusBadge;
@property (nonatomic, strong, readonly) UILabel *subscriptionLabel;
@property (nonatomic, strong, readonly) UILabel *costLabel;
@property (nonatomic, strong, readonly) UIView *cardView;

+ (NSString *)reuseID;
+ (CGFloat)preferredHeight;
- (void)configureWithVet:(PPVetModel *)vet;

@end

NS_ASSUME_NONNULL_END
