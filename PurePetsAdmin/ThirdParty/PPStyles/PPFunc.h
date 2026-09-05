//
//  PPFunc.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 23/08/2025.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol TOCropViewControllerDelegate;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, PPSheetDetentStyle) {
    PPSheetDetentStyleMediumOnly,
    PPSheetDetentStyle70,
    PPSheetDetentStyle80,
    PPSheetDetentStyleAdsView,
    PPSheetDetentStyle300,
    PPSheetDetentStyleLargeOnly,
    PPSheetDetentStyleMediumAndLarge,
    PPSheetDetentStyleSemiLargAndLarge,
    PPSheetDetentStyleProfile
};
 
// =========================================  UIImage   ===========================================//
@interface PPFunc : NSObject
+ (void)pp_presentCircularCropperWithImage:(UIImage *)image
                            fromController:(UIViewController<TOCropViewControllerDelegate> *)controller;

+ (void)pp_clearAllYYCacheNamed:(NSString *)name;
+ (void)reloadTableView:(UITableView *)tableView duration:(CGFloat)duration Animated:(BOOL)Animated;
+ (void)reloadTableView:(UITableView *)tableView  Animated:(BOOL)Animated;
// Create a helper method for HUD handling
+ (void)handleCompletionWithError:(NSError *)error successMessage:(NSString *)successMessage onController:(UIViewController *)viewController;

+ (void)presentSheetFrom:(UIViewController *)presentingVC
                sheetVC:(UIViewController *)sheetVC
             detentStyle:(PPSheetDetentStyle)style;

+ (void)presentFloatingSheetFrom:(UIViewController *)presenter
                        sheetVC:(UIViewController *)sheetVC
                     detentStyle:(PPSheetDetentStyle)style;


@end



// =========================================  PaddedLabel   ===========================================//
@interface PaddedLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets textInsets;
@end



// =========================================  UIImage   ===========================================//
@interface UIImage (Crop)
- (UIImage *)pp_circularImage;
@end


// =========================================  PPActionButton  ===========================================//
// Factory for creating styled UIActions with custom brand font
@interface PPActionButton : NSObject

+ (UIAction *)actionWithTitle:(NSString *)title
              systemImageName:(nullable NSString *)systemImageName
                         font:(nullable UIFont *)font
                        color:(nullable UIColor *)color
                      handler:(void (^)(UIAction *action))handler;

+ (void)applyStyleToAction:(UIAction *)action
                      font:(nullable UIFont *)font
                     color:(nullable UIColor *)color;

+ (UIAction *)deleteActionWithHandler:(void (^)(UIAction *action))handler;
+ (UIAction *)editActionWithHandler:(void (^)(UIAction *action))handler;
+ (UIAction *)shareActionWithHandler:(void (^)(UIAction *action))handler;
+ (UIAction *)showProfileActionWithHandler:(void (^)(UIAction *action))handler;
+ (UIAction *)settingsActionWithHandler:(void (^)(UIAction *action))handler;
+ (UIAction *)logoutActionWithHandler:(void (^)(UIAction *action))handler;

@end

NS_ASSUME_NONNULL_END
