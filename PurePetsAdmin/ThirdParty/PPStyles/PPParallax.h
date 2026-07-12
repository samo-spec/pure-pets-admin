//
//  PPParallax.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 03/09/2025.
//


//  PPParallax.h
//  Smooth header parallax for UITableView/UIScrollView
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPParallax : UIImageView

/// Designated init. Pass any views you have; nil is OK and will be ignored.
- (instancetype)initWithScrollView:(UIScrollView *)scrollView
                        headerView:(UIView *)headerView      // container to render as the header
                   backgroundView:(nullable UIView *)bgView  // e.g. UIImageView to parallax/scale
                            topRow:(nullable UIView *)topRow  // e.g. avatar + name row
                          statsRow:(nullable UIView *)statsRow
                       avatarImage:(nullable UIImageView *)avatar;

/// Call once after you’ve created the header subviews (e.g. in viewDidLoad / after layout).
- (void)attach;

/// Forward your scroll delegate methods to these:
- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;

/// If size changes (rotation / split view), call this.
- (void)updateLayout;

/// Snap back to base state.
- (void)resetAnimated:(BOOL)animated;

#pragma mark - Tuning

@property (nonatomic) CGFloat baseHeight;          // visible header height (default 220)
@property (nonatomic) CGFloat maxStretch;          // extra height when pulling down (default 180)

@property (nonatomic) CGFloat bgParallaxFactor;    // how much bg moves vs scroll (0..1, default 0.35)
@property (nonatomic) CGFloat topParallaxFactor;   // top row move (default 0.15)
@property (nonatomic) CGFloat statsParallaxFactor; // stats move (default 0.05)

@property (nonatomic) CGFloat avatarMaxScale;      // on pull down (default 1.4)
@property (nonatomic) CGFloat avatarFadeDistance;  // fade out while scrolling up (pts, default 240)

@property (nonatomic) BOOL debugLogging;

@end

NS_ASSUME_NONNULL_END
