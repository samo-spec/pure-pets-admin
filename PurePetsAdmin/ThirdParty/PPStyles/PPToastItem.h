//
//  PPToastItem.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 25/08/2025.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSTimeInterval const kPPToastDefaultDuration = 2.0;
static CGFloat const kPPToastHorizontalInset = 24.0;
static CGFloat const kPPToastMaxWidthMultiplier = 0.9;
static CGFloat const kPPToastCornerRadius = 12.0;
static CGFloat const kPPToastVerticalPadding = 12.0;
static CGFloat const kPPToastHorizontalPadding = 14.0;
static CGFloat const kPPToastTranslate = 10.0;
static NSTimeInterval const kPPToastAnimationDuration = 0.28;


typedef NS_ENUM(NSInteger, PPToastStyle) {
    PPToastStyleInfo = 0,
    PPToastStyleSuccess,
    PPToastStyleError,
    PPToastStyleWarning
};

typedef NS_ENUM(NSInteger, PPToastPosition) {
    PPToastPositionBottom = 0,
    PPToastPositionCenter,
    PPToastPositionTop
};

@interface PPToastItem : NSObject
@property (nonatomic, copy) NSString *message;
@property (nonatomic, assign) PPToastStyle style;
@property (nonatomic, assign) BOOL haptic;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) PPToastPosition position;
@property (nonatomic, weak, nullable) UIView *inView;
@end

NS_ASSUME_NONNULL_END
