//
//  QBAlbumCell.h
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
 
 

@interface AddButtonCell : UICollectionViewCell

/// Callback fired when user taps the (+) button
@property (nonatomic, copy, nullable) void (^onTap)(void);
@property (nonatomic, strong, readonly) UIButton *addButton;


/// Configure title (optional)
- (void)setButtonTitle:(NSString *)title;

/// Configure symbol (SF Symbol name)
- (void)setButtonSymbol:(NSString *)symbol;
/// Assign a contextual menu directly to the internal button (iOS 14+).
- (void)setPrimaryMenu:(nullable UIMenu *)menu API_AVAILABLE(ios(14.0));

@end

NS_ASSUME_NONNULL_END



NS_ASSUME_NONNULL_BEGIN

@interface PP_ImageCell : UICollectionViewCell

@property (nonatomic, strong, readonly) UIButton *deleteButton;
@property (nonatomic, strong, readonly) UIImageView *imageView;
/// Optional delete button callback
@property (nonatomic, copy, nullable) void (^onDelete)(void);
@property (nonatomic, copy, nullable) void (^onTap)(void);
/// Configure the cell with a UIImage
- (void)configureWithImage:(UIImage *)image;

/// Set whether delete button is visible
- (void)setDeleteVisible:(BOOL)visible;

@end

NS_ASSUME_NONNULL_END
