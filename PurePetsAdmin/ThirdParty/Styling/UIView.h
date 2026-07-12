//
//  UIView.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 21/08/2025.
//


//
//  UIView+HXFrame.h
//  PurePetsAdmin
//153200

// ===== Icon Postions =====
typedef NS_ENUM(NSInteger, IconPostions) {
    IconPostionsTopLeft                 = 1,
    IconPostionsTopRight                = 2,
    IconPostionsTopMiddle               = 3,
    IconPostionsBottomLeft              = 4,
    IconPostionsBottomRight             = 5,
    IconPostionsBottomMiddle            = 6,
    IconPostionsMiddleLeft              = 7,
    IconPostionsMiddleRight             = 8
};

NS_ASSUME_NONNULL_BEGIN

@interface UIView (HXFrame)



@property (nonatomic, assign) CGFloat hxw;     // width
@property (nonatomic, assign) CGFloat hxh;     // height
@property (nonatomic, assign) CGFloat hxx;     // origin.x
@property (nonatomic, assign) CGFloat hxy;     // origin.y

@property (nonatomic, assign, readonly) CGFloat hxmax;   // maxX
@property (nonatomic, assign, readonly) CGFloat hxmaxy;  // maxY
@property (nonatomic, assign, readonly) CGFloat hxminx;  // minX
@property (nonatomic, assign, readonly) CGFloat hxminy;  // minY

@property (nonatomic, assign) CGRect hxFrame;

- (void)placeIcon:(NSString *)icon onPostions:(IconPostions)Postions;




@end

NS_ASSUME_NONNULL_END
