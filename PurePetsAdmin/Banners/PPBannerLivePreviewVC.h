//
//  PPBannerLivePreviewVC.h
//  PurePetsAdmin
//
//  Live In-Situ Consumer App Simulation & Preview Modal
//

#import <UIKit/UIKit.h>
#import "MainBannerModel.h"
#import "PPBannerViewModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface PPBannerLivePreviewVC : UIViewController

- (instancetype)initWithBanner:(PPBannerViewModel *)banner
                         group:(MainBannerModel *)group;

@property (nonatomic, copy, nullable) void (^onEditRequested)(PPBannerViewModel *banner, MainBannerModel *group);

@end

NS_ASSUME_NONNULL_END
