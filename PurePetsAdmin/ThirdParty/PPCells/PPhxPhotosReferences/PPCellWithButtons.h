//
//  PPCellWithButtons.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 07/09/2025.
//


#import <UIKit/UIKit.h>
@class UserModel;
@class PPCellWithButtons;
@class PPItem;
@class PaddedLabel;
@class MainBannerModel;
@class PPBannerViewModel;
NS_ASSUME_NONNULL_BEGIN

@protocol PPCellWithButtonsDelegate <NSObject>
@optional
- (void)cellWithButtons:(PPCellWithButtons *)cell didTapFirstButtonAtIndexPath:(NSIndexPath *)indexPath;
- (void)cellWithButtons:(PPCellWithButtons *)cell didTapSecondButtonAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface PPCellWithButtons : UITableViewCell

@property (nonatomic, strong) UIView *circleView;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) PaddedLabel *titleLabel;
@property (nonatomic, strong) PaddedLabel *subtitleLabel;
@property (nonatomic, strong) PaddedLabel *detailLabel; // 👈 new third label

@property (nonatomic, strong) UIButton *firstButton;
@property (nonatomic, strong) UIButton *secondButton;

/// Guard for async image setting to prevent image flicker on reuse
@property (nonatomic, strong, nullable) NSString *representedUID;

/// Model & context
@property (nonatomic, strong, nullable) UserModel *cellUser;
@property (nonatomic, strong) NSIndexPath *indexPath;
@property (nonatomic, weak) id<PPCellWithButtonsDelegate> delegate;

/// Configure cell with user data (sets title, subtitle, etc.)
- (void)configureWithUser:(UserModel *)user indexPath:(NSIndexPath *)indexPath;

/// Reuse identifier for this cell class
+ (NSString *)reuseIdentifier;
-(void)configureWithItem:(id)model;


// =========================================== For Banners ================================================= //
@property (nonatomic, strong) PPBannerViewModel *PPbannerModel;
@property (nonatomic, strong) MainBannerModel *PPGroubModel;

@end

NS_ASSUME_NONNULL_END
