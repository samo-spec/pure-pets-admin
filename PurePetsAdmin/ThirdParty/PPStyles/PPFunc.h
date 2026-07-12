//
//  PPFunc.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 23/08/2025.
//

#import <Foundation/Foundation.h>

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


NS_ASSUME_NONNULL_END
