//
//  PPAddBannerViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 09/09/2025.
//


//  PPAddBannerViewController.h
//  PurePetsAdmin

#import <XLForm/XLForm.h>

@class MainBannerModel;

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSInteger, PPHXManager) {
    PPHXManagerBackgound = 1,  // default: e.g., view a specific accessory in app
    PPHXManagerSample = 2,
    PPHXManagerBadge = 3// open WhatsApp with a given number/chat
};

typedef NS_ENUM(NSInteger, PPEditMode) {
    PPEditModeNewGroup,
    PPEditModeGroupAndBanner,
    PPEditModeGroupOnly,   // Editing group-level (header edit button)
    PPEditModeBannerOnly,
    PPEditModeAddBannerToGroup  // Editing a single banner inside group (row edit button)
};

@interface PPAddBannerViewController : XLFormViewController<CLImageEditorDelegate>

@property (nonatomic, assign) PPEditMode editMode;
@property (nonatomic, strong) MainBannerModel *editingBannerGroup;
@property (nonatomic, strong) PPBannerViewModel *editingBanner;

- (instancetype)initWithEditMode:(PPEditMode)editMode
                            group:(nullable MainBannerModel *)group
                           banner:(nullable PPBannerViewModel *)banner;


- (instancetype)initWithMainBanner:(MainBannerModel * _Nullable)banner; // edit or add
- (instancetype)initWithBanner:(nullable PPBannerViewModel *)banner inGroup:(nullable MainBannerModel *)group;

@end

NS_ASSUME_NONNULL_END
