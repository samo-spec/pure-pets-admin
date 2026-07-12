//
//  AdminCell.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


// AdminCell.h
#import <UIKit/UIKit.h>

@interface AdminCell : UITableViewCell

@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

- (void)configureWithIcon:(UIImage *)icon
                    title:(NSString *)title
                 subtitle:(NSString *)subtitle;

@end
