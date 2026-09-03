//
//  PPFlagshipBannerCardCell.h
//  PurePetsAdmin
//
//  Flagship Beyond-FAANG Apple-grade Banner Card Interface
//

#import <UIKit/UIKit.h>
#import "MainBannerModel.h"
#import "PPBannerViewModel.h"

NS_ASSUME_NONNULL_BEGIN

@class PPFlagshipBannerCardCell;

@protocol PPFlagshipBannerCardDelegate <NSObject>
@optional
- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didTapPreviewForBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group;
- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didTapEditForBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group;
- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didToggleActive:(BOOL)active forBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group;
- (void)bannerCardCell:(PPFlagshipBannerCardCell *)cell didTapMoreOptionsForBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group sourceView:(UIView *)sourceView;
@end

@interface PPFlagshipBannerCardCell : UITableViewCell

@property (nonatomic, strong, readonly) MainBannerModel *groupModel;
@property (nonatomic, strong, readonly) PPBannerViewModel *bannerModel;
@property (nonatomic, weak, nullable) id<PPFlagshipBannerCardDelegate> delegate;

+ (NSString *)reuseIdentifier;

- (void)configureWithBanner:(PPBannerViewModel *)banner
                      group:(MainBannerModel *)group
                  indexPath:(NSIndexPath *)indexPath;

@end

NS_ASSUME_NONNULL_END
