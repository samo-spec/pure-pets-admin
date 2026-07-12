
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface QBAlbumCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UIView *imageContainer;

@property (nonatomic, strong) UIView *containerSep;
@property (nonatomic, strong, readonly) UIImageView *imageView1;
@property (nonatomic, strong, readonly) UIImageView *imageView2;
@property (nonatomic, strong, readonly) UIImageView *imageView3;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *countLabel;

@property (nonatomic, assign) CGFloat borderWidth;

+ (NSString *)reuseIdentifier;

/// Ask the cell to load the provided PHAssets (0..3). The cell will set placeholders immediately and fetch thumbnails asynchronously.
/// - assets: array of PHAsset to display (order left->right). Provide up to 3 assets (if less, remaining imageViews will be hidden).
/// - imageManager: PHImageManager or PHCachingImageManager to request images
/// - targetSize: pixel size to pass to requestImageForAsset: (use CGSizeMake(width*scale, height*scale))
/// - placeholder: placeholder UIImage to show immediately
/// - tableView + indexPath: used for reuse-safety (cell will only set images if it is still the visible cell for that indexPath)


@end

NS_ASSUME_NONNULL_END


