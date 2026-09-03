//
//  PPAddBannerViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 09/09/2025.
//  Updated for NextGen V6 Sovereign Banner Creative Studio Bridge.
//

#import <UIKit/UIKit.h>

@class MainBannerModel;
@class PPBannerViewModel;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPHXManager) {
    PPHXManagerBackgound = 1,
    PPHXManagerSample = 2,
    PPHXManagerBadge = 3
};

typedef NS_ENUM(NSInteger, PPEditMode) {
    PPEditModeNewGroup,
    PPEditModeGroupAndBanner,
    PPEditModeGroupOnly,        // Editing group-level (header edit button)
    PPEditModeBannerOnly,        // Editing single banner inside group
    PPEditModeAddBannerToGroup  // Adding banner to an existing group
};

@interface PPAddBannerViewController : UIViewController

@property (nonatomic, assign) PPEditMode editMode;
@property (nonatomic, strong, nullable) MainBannerModel *editingBannerGroup;
@property (nonatomic, strong, nullable) PPBannerViewModel *editingBanner;

- (instancetype)initWithEditMode:(PPEditMode)editMode
                            group:(nullable MainBannerModel *)group
                           banner:(nullable PPBannerViewModel *)banner;

- (instancetype)initWithMainBanner:(nullable MainBannerModel *)banner;
- (instancetype)initWithBanner:(nullable PPBannerViewModel *)banner inGroup:(nullable MainBannerModel *)group;

@end

NS_ASSUME_NONNULL_END
