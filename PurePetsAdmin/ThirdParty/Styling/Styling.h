//
//  Styling.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 21/08/2025.
//

//
//  Styling.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>
#import "PPPaddingLabel.h"
NS_ASSUME_NONNULL_BEGIN

@class LOTAnimationView;

@interface Styling : NSObject

/// Reusable style helper: rounded corners, border, shadow
+ (void)applyStyleWithCornerRadius:(CGFloat)cornerRadius
                     backgroundColor:(UIColor *)backgroundColor
                         borderColor:(nullable UIColor *)borderColor
                         borderWidth:(CGFloat)borderWidth
                           addShadow:(BOOL)addShadow
                              toView:(UIView *)view;

/// Short version → references full method but ignores backgroundColor & borderWidth
+ (void)applyStyleWithCornerRadius:(CGFloat)cornerRadius
                        borderColor:(nullable UIColor *)borderColor
                          addShadow:(BOOL)addShadow
                             toView:(UIView *)view;

/// Preset: Card style (rounded, shadow, white bg)
+ (void)applyCardStyleToView:(UIView *)view;

/// Preset: Button style (rounded pill, primary bg, shadow)
+ (void)applyIconButtonStyle:(UIButton *)button
                   tintColor:(UIColor *)tintColor
             backgroundColor:(UIColor *)backgroundColor;

/// Preset: Header style (flat bg, no shadow, bold look)
+ (void)applyHeaderStyleToView:(UIView *)view;

+ (void)registerBrandFontsIfNeeded;
+ (UIFont *)fontBold:(CGFloat)size;
+ (UIFont *)fontMedium:(CGFloat)size;
+ (UIFont *)fontRegular:(CGFloat)size;

+ (void)applyButtonTextStyle:(UIButton *)button
                        size:(CGFloat)pointSize
                      weight:(UIFontWeight)weight
                       scale:(UIFontTextStyle)scale; // e.g. UIFontTextStyleBody

+ (void)applyButtonIconStyle:(UIButton *)button
                   tintColor:(UIColor *)tintColor
             backgroundColor:(UIColor *)backgroundColor
                cornerRadius:(CGFloat)cornerRadius
            symbolPointSize:(CGFloat)pointSize
                     weight:(UIImageSymbolWeight)weight
                       scale:(UIImageSymbolScale)scale;

/// Apply rounded corners + shadow to a grouped table cell
+ (void)applyGroupCellStyle:(UITableViewCell *)cell
               atIndexPath:(NSIndexPath *)indexPath
                inTableView:(UITableView *)tableView;

// ✅ Lottie Helpers
+ (void)setAnimationNamed:(NSString *)fileName
                   toView:(LOTAnimationView *)lot
                withSpeed:(float)animationSpeed
               completion:(void (^)(BOOL success))completion;

+ (void)fetchLottieJSONFromFirebasePath:(NSString *)storagePath
                             completion:(void (^)(NSDictionary *jsonDict, NSError *error))completion;

+ (void)setRowFonts:(XLFormRowDescriptor *)row;
+ (void)setRowButtonStyle:(XLFormRowDescriptor *)row;

+ (void)setupFormAppearance;

+ (void)applyGlobalStyleToRow:(XLFormRowDescriptor *)row;

/// Apply background style to a cell (Row-Card or Section-Card mode)
+ (void)applyBackgroundStyleForTableView:(UITableView *)tableView
                                    cell:(UITableViewCell *)cell
                               indexPath:(NSIndexPath *)indexPath
                           useRowCardMode:(BOOL)useRowCardMode;

+ (void)applyCorner:(CGFloat)cornerRadius
   backgroundColor:(UIColor *)backgroundColor
             toView:(UIView *)view;


// New signature
+ (void)applyBackgroundStyleForTableView:(UITableView *)tableView
                                   cell:(UITableViewCell *)cell
                              indexPath:(NSIndexPath *)indexPath
                          useRowCardMode:(BOOL)useRowCardMode
                        buttonRowIndex:(NSInteger)buttonRowIndex
                          buttonSection:(NSInteger)buttonSection;

// Liquid glass border (no-op stub for iOS picker compatibility)
+ (void)addLiquidGlassBorderToView:(UIView *)view cornerRadius:(CGFloat)radius;

@end

NS_ASSUME_NONNULL_END


