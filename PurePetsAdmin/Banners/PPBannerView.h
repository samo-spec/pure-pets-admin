// In PPBannerView.h
//
//  PPBannerView.h
//  PurePets
//
//  Reusable banner (UIControl) with manual CGRect layout:
//  - Background image + gradient
//  - Left text (title/desc/date)
//  - Right images (badge + sample) on the visual trailing edge (RTL/LTR aware)
//  - Dynamic Type-friendly fonts, shadow, rounded corners
//

#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface PPBannerView : UIControl

/// Insets around inner content. Default {12,12,12,12}
@property (nonatomic, assign) UIEdgeInsets contentInsets;

/// Rounded corners for the outer card. Default 25.0
@property (nonatomic, assign) CGFloat cornerRadius;

/// Shadow toggle. Default YES
@property (nonatomic, assign) BOOL showsShadow;

/// Configure with a view-model. Safe to call multiple times.
- (void)configureWithModel:(PPBannerViewModel *)model;

/// Reset view to placeholders (useful before reuse).
- (void)prepareForReuse;


@end

NS_ASSUME_NONNULL_END
