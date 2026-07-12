//
//  PPQAccessBarItem.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 15/09/2025.
//


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPQAccessBar;

// Delegate protocol for handling button taps
@protocol PPQAccessBarDelegate <NSObject>
@optional
- (void)accessBar:(PPQAccessBar *)accessBar didSelectItemAtIndex:(NSInteger)index;
@end

// Configuration model for each accessory item
@interface PPQAccessBarItem : NSObject

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;

+ (instancetype)itemWithImage:(UIImage *)image title:(NSString *)title subtitle:(NSString *)subtitle;

@end

// Main accessory bar class
@interface PPQAccessBar : UIView

@property (nonatomic, weak) id<PPQAccessBarDelegate> delegate;
@property (nonatomic, strong) NSArray<PPQAccessBarItem *> *items;
@property (nonatomic, assign) BOOL shouldAnimateSelection; // Default: YES

// Initializers
- (instancetype)initWithItems:(NSArray<PPQAccessBarItem *> *)items;
- (instancetype)initWithFrame:(CGRect)frame items:(NSArray<PPQAccessBarItem *> *)items;

// Appearance customization
@property (nonatomic, strong) UIColor *itemTintColor UI_APPEARANCE_SELECTOR;
@property (nonatomic, strong) UIColor *selectedItemTintColor UI_APPEARANCE_SELECTOR;
@property (nonatomic, strong) UIColor *titleColor UI_APPEARANCE_SELECTOR;
@property (nonatomic, strong) UIColor *subtitleColor UI_APPEARANCE_SELECTOR;
@property (nonatomic, strong) UIFont *titleFont UI_APPEARANCE_SELECTOR;
@property (nonatomic, strong) UIFont *subtitleFont UI_APPEARANCE_SELECTOR;

@end

NS_ASSUME_NONNULL_END