//
//  PPQuickActionItem.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


//
//  PPQuickActionsView.h
//  PurePetsAdmin
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPQuickActionItem : NSObject
@property (nonatomic, copy) NSString *titleKey;    // kLang key
@property (nonatomic, copy) NSString *iconName;    // SF Symbol or asset
@property (nonatomic, copy, nullable) void (^handler)(void);
@property (nonatomic) CGFloat buttonWidth;  
+ (instancetype)itemWithTitleKey:(NSString *)titleKey
                         iconName:(NSString *)iconName
                            width:(CGFloat)width
                         handler:(void (^ _Nullable)(void))handler;
@end

@interface PPQuickActionsView : UIView

/// Provide the actions to render (max 4 per row recommended).
- (void)setActions:(NSArray<PPQuickActionItem *> *)actions;

/// Styling properties
@property (nonatomic) CGFloat buttonHeight;    // default 80
@property (nonatomic) CGFloat cornerRadius;    // default 18
@property (nonatomic, strong) UIColor *backgroundColorForButton;
@property (nonatomic, strong) UIColor *tintColorForIcon;
@property (nonatomic) CGFloat buttonWidth;    
@end

NS_ASSUME_NONNULL_END
