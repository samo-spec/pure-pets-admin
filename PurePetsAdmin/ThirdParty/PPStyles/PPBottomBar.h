//
//  PPBottomBar.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 12/09/2025.
//


#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, BarLayout) {
    BarLayoutStickToBottom,
    BarLayoutFloating
};

@interface PPBottomBar : UIView

@property (nonatomic, assign) BarLayout layout;
@property (nonatomic, strong) UIButton *centerButton;
@property (nonatomic, strong) NSArray<UIButton *> *leftButtons;
@property (nonatomic, strong) NSArray<UIButton *> *rightButtons;
@property (nonatomic, strong) UIColor *themeColor;
- (instancetype)initWithLayout:(BarLayout)layout;
- (void)setupConstraintsInView:(UIView *)superview;

@end
