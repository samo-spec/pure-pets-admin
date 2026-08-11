//
//  PPImageCollection 2.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 03/12/2025.
//


#import "PPImageCollection.h"
#import "QB.h"
#import <AVFoundation/AVFoundation.h>
#import "PurePetsAdmin-Swift.h"
#import "PetAccessory.h"

@class PetAccessory;
@interface PetAccessory (TopVC)
+ (UIViewController *)pp_topViewController;
@end

@interface PPImageCollection () <UISheetPresentationControllerDelegate>
@property (nonatomic, strong) UIView *titleContainer;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) QBImagePickerController *currentPicker;
@property (nonatomic, strong) UIImagePickerController *cameraPicker;
@property (nonatomic, strong) UILongPressGestureRecognizer *reorderLongPressGesture;
@property (nonatomic, assign) BOOL isPresentingMediaPicker;
@property (nonatomic, strong) UIView *loadingOverlay;
@property (nonatomic, strong) UIActivityIndicatorView *loadingSpinner;
@property (nonatomic, copy) dispatch_block_t loadingTimeoutBlock;
@end

@implementation PPImageCollection

#pragma mark - Initialization

- (instancetype)initWithFrame:(CGRect)frame maxImageCount:(NSInteger)maxCount useArabic:(BOOL)useArabic {
    self = [super initWithFrame:frame];
    if (self) {
        _maxImageCount = maxCount;
        _useArabic = useArabic;
        _allowsEditing = YES;
        _allowsReordering = YES;
        _selectedForEdit = -1;
        _arrayLock = [[NSRecursiveLock alloc] init];
        _mediaOutputArray = [[NSMutableArray alloc] init];
        
        [self setupImageManager];
        [self setupEditorBridge];
        [self setupUI];
        [self setupLoadingOverlay];
        [self setupNotifications];
        
        // Set default title
        [self setTitle:kLang(@"add.images.here") icon:nil];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame maxImageCount:8 useArabic:NO];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self pp_cancelLoadingTimeoutIfNeeded];
}

#pragma mark - Setup

- (void)setupImageManager {
    _imageManager = [PPPickerAssetManager sharedManager];
    [_imageManager clearAll];
    _imageManager.maxImageCount = self.maxImageCount;
    if (![_imageManager.selectedImages isKindOfClass:NSMutableArray.class]) {
        NSArray *snapshot =
            [_imageManager.selectedImages isKindOfClass:NSArray.class] ? (NSArray *)_imageManager.selectedImages : @[];
        _imageManager.selectedImages = [snapshot mutableCopy];
    }
}

- (void)setupEditorBridge {
    _editorBridge = [[PPEditorBridge alloc] init];
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(editorDidFinish:)
                                                 name:@"PPEditorBridgeDidFinish"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(editorDidCancel:)
                                                 name:@"PPEditorBridgeDidCancel"
                                               object:nil];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    
    // Setup title container
    [self setupTitleContainer];
    
    // Setup collection view
    [self setupCollectionView];
    
    // Layout constraints
    [self setupConstraints];
}

- (void)setupTitleContainer {
    _titleContainer = [[UIView alloc] init];
    _titleContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_titleContainer];
    
    // Icon
    UIImageSymbolConfiguration *symConfig = [[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular]
                                             configurationByApplyingConfiguration:
                                                 [UIImageSymbolConfiguration configurationWithPaletteColors:@[
                                                    [UIColor ppTextSecondary],
                                                    [AppPrimaryClr  colorWithAlphaComponent:1.1]
                                                 ]]];
    
    UIImage *icon = [UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:symConfig];
    _iconView = [[UIImageView alloc] initWithImage:icon];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = [UIColor ppTextPrimary];
    
    // Title label
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:14];
    _titleLabel.textColor = [UIColor ppTextSecondary];
    
    [_titleContainer addSubview:_iconView];
    [_titleContainer addSubview:_titleLabel];
}

- (void)setupCollectionView {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 4;
    layout.minimumLineSpacing = 4;
    layout.sectionInset = UIEdgeInsetsMake(8, 8, 8, 8);
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.backgroundColor = [AppForgroundColr colorWithAlphaComponent:1];
    _collectionView.delegate = self;
    _collectionView.dataSource = self;
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [_collectionView registerClass:[AddButtonCell class] forCellWithReuseIdentifier:@"AddButtonCell"];
    [_collectionView registerClass:[PP_ImageCell class] forCellWithReuseIdentifier:@"PP_ImageCell"];
    
    _collectionView.layer.masksToBounds = YES;
    _collectionView.layer.cornerRadius = 12;
    _collectionView.clipsToBounds = YES;

    _reorderLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(handleReorderLongPress:)];
    [_collectionView addGestureRecognizer:_reorderLongPressGesture];
    
    [self addSubview:_collectionView];
}

- (void)setupLoadingOverlay {
    _loadingOverlay = [[UIView alloc] initWithFrame:CGRectZero];
    _loadingOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.15];
    _loadingOverlay.layer.cornerRadius = 16;
    _loadingOverlay.hidden = YES;
    
    UIActivityIndicatorViewStyle style = UIActivityIndicatorViewStyleLarge;
    if (@available(iOS 13.0, *)) {
        style = UIActivityIndicatorViewStyleLarge;
    }
    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
    _loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _loadingSpinner.color = [UIColor ppPrimary];
    
    [_loadingOverlay addSubview:_loadingSpinner];
    [self addSubview:_loadingOverlay];
    
    [NSLayoutConstraint activateConstraints:@[
        [_loadingOverlay.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_loadingOverlay.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_loadingOverlay.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_loadingOverlay.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        
        [_loadingSpinner.centerXAnchor constraintEqualToAnchor:_loadingOverlay.centerXAnchor],
        [_loadingSpinner.centerYAnchor constraintEqualToAnchor:_loadingOverlay.centerYAnchor]
    ]];
}

- (void)pp_showLoadingOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.loadingOverlay.hidden = NO;
        [self.loadingSpinner startAnimating];
    });
}

- (void)pp_hideLoadingOverlay {
    [self pp_cancelLoadingTimeoutIfNeeded];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.loadingSpinner stopAnimating];
        self.loadingOverlay.hidden = YES;
    });
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // Title container
        [_titleContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_titleContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
        [_titleContainer.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-6],
        [_titleContainer.heightAnchor constraintEqualToConstant:30],
        
        // Icon
        [_iconView.leadingAnchor constraintEqualToAnchor:_titleContainer.leadingAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:20],
        [_iconView.heightAnchor constraintEqualToConstant:20],
        
        // Title label
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:6],
        [_titleLabel.topAnchor constraintEqualToAnchor:_titleContainer.topAnchor],
        [_titleLabel.bottomAnchor constraintEqualToAnchor:_titleContainer.bottomAnchor],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_titleContainer.trailingAnchor],
        
        // Collection view
        [_collectionView.topAnchor constraintEqualToAnchor:_titleContainer.bottomAnchor constant:4],
        [_collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

#pragma mark - Public Methods

- (void)pp_ensureMutableCollections
{
    if (![self.mediaOutputArray isKindOfClass:NSMutableArray.class]) {
        NSArray *snapshot =
            [self.mediaOutputArray isKindOfClass:NSArray.class] ? (NSArray *)self.mediaOutputArray : @[];
        self.mediaOutputArray = [snapshot mutableCopy];
    }
    if (!self.mediaOutputArray) {
        self.mediaOutputArray = [NSMutableArray array];
    }

    if (!self.imageManager) {
        self.imageManager = [PPPickerAssetManager sharedManager];
    }
    if (![self.imageManager.selectedImages isKindOfClass:NSMutableArray.class]) {
        NSArray *snapshot =
            [self.imageManager.selectedImages isKindOfClass:NSArray.class] ? (NSArray *)self.imageManager.selectedImages : @[];
        self.imageManager.selectedImages = [snapshot mutableCopy];
    }
    if (!self.imageManager.selectedImages) {
        self.imageManager.selectedImages = [NSMutableArray array];
    }
}

- (UIImage *)pp_normalizedImageForCollection:(UIImage *)image
{
    if (!image) return nil;
    if (image.size.width <= 0.0 || image.size.height <= 0.0) return nil;

    UIImage *source = image;
    CGFloat maxDimension = MAX(source.size.width, source.size.height);
    CGFloat targetMaxDimension = 1800.0; // keep memory stable for repeated picks/edits.

    CGSize targetSize = source.size;
    if (maxDimension > targetMaxDimension) {
        CGFloat scale = targetMaxDimension / maxDimension;
        targetSize = CGSizeMake(MAX(1.0, floor(source.size.width * scale)),
                                MAX(1.0, floor(source.size.height * scale)));
    }

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = source.scale > 0 ? source.scale : UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:targetSize format:format];
    UIImage *normalized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [source drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    }];
    return normalized ?: source;
}

- (BOOL)pp_isRenderableImage:(UIImage *)image
{
    return [image isKindOfClass:[UIImage class]] &&
           image.size.width > 0.0 &&
           image.size.height > 0.0;
}

- (NSArray<UIImage *> *)pp_sanitizedImagesFromArray:(NSArray *)images
{
    NSMutableArray<UIImage *> *sanitized = [NSMutableArray array];
    for (id candidate in images) {
        if (![candidate isKindOfClass:[UIImage class]]) {
            continue;
        }
        UIImage *normalized = [self pp_normalizedImageForCollection:(UIImage *)candidate];
        if ([self pp_isRenderableImage:normalized]) {
            [sanitized addObject:normalized];
        }
    }
    return [sanitized copy];
}

- (void)pp_syncImagesFromManager
{
    NSArray *managerImages = [self.imageManager.selectedImages copy] ?: @[];
    NSArray *managerAssets = [self.imageManager.assetArray.array copy] ?: @[];
    NSMutableArray<UIImage *> *sanitized = [NSMutableArray array];
    NSMutableOrderedSet *sanitizedAssets = [NSMutableOrderedSet orderedSet];

    for (NSUInteger idx = 0; idx < managerImages.count; idx++) {
        id candidate = managerImages[idx];
        if (![candidate isKindOfClass:[UIImage class]]) {
            continue;
        }
        UIImage *normalized = [self pp_normalizedImageForCollection:(UIImage *)candidate];
        if (![self pp_isRenderableImage:normalized]) {
            continue;
        }

        [sanitized addObject:normalized];
        if (idx < managerAssets.count) {
            id asset = managerAssets[idx];
            if (asset) {
                [sanitizedAssets addObject:asset];
            }
        }
    }

    [self.arrayLock lock];
    [self pp_ensureMutableCollections];
    [self.mediaOutputArray removeAllObjects];
    [self.mediaOutputArray addObjectsFromArray:sanitized];
    self.imageManager.selectedImages = [sanitized mutableCopy];
    self.imageManager.assetArray = sanitizedAssets;
    [self.arrayLock unlock];
}

- (void)pp_cancelLoadingTimeoutIfNeeded
{
    if (self.loadingTimeoutBlock) {
        dispatch_block_cancel(self.loadingTimeoutBlock);
        self.loadingTimeoutBlock = nil;
    }
}

- (void)setTitle:(NSString *)title icon:(UIImage *)icon {
    _titleText = [title copy];
    _titleLabel.text = _titleText;
    if (icon) {
        _iconView.image = icon;
    }
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    [self setTitle:_titleText icon:nil];
}

- (NSArray<UIImage *> *)allImages {
    [self.arrayLock lock];
    NSArray *copy = [self.mediaOutputArray copy];
    [self.arrayLock unlock];
    return copy;
}

- (NSInteger)imageCount {
    [self.arrayLock lock];
    NSInteger count = self.mediaOutputArray.count;
    [self.arrayLock unlock];
    return count;
}

- (void)addImage:(UIImage *)image {
    if (!image || [self imageCount] >= self.maxImageCount) return;
    UIImage *normalized = [self pp_normalizedImageForCollection:image];
    if (!normalized) return;
    
    [self.arrayLock lock];
    [self pp_ensureMutableCollections];
    [self.mediaOutputArray addObject:normalized];
    [self.imageManager addImage:normalized];
    [self.arrayLock unlock];
    
    [self reloadCollectionView];
    [self notifyDelegate];
}

- (void)addImages:(NSArray<UIImage *> *)images {
    if (images.count == 0) return;

    NSMutableArray<UIImage *> *normalizedCandidates = [NSMutableArray arrayWithCapacity:images.count];
    for (UIImage *candidate in images) {
        UIImage *normalized = [self pp_normalizedImageForCollection:candidate];
        if (normalized) {
            [normalizedCandidates addObject:normalized];
        }
    }

    if (normalizedCandidates.count == 0) return;

    NSInteger availableSlots = self.maxImageCount - [self imageCount];
    if (availableSlots <= 0) return;
    
    NSArray *imagesToAdd = normalizedCandidates;
    if (normalizedCandidates.count > availableSlots) {
        imagesToAdd = [normalizedCandidates subarrayWithRange:NSMakeRange(0, availableSlots)];
    }
    
    [self.arrayLock lock];
    [self pp_ensureMutableCollections];
    [self.mediaOutputArray addObjectsFromArray:imagesToAdd];
    
    for (UIImage *image in imagesToAdd) {
        [self.imageManager addImage:image];
    }
    [self.arrayLock unlock];
    
    [self reloadCollectionView];
    [self notifyDelegate];
}

- (void)removeImageAtIndex:(NSInteger)index {
    if (index < 0 || index >= [self imageCount]) return;
    
    [self.arrayLock lock];
    [self pp_ensureMutableCollections];
    [self.mediaOutputArray removeObjectAtIndex:index];
    [self.imageManager removeImageAtIndex:index];
    [self.arrayLock unlock];
    
    [self reloadCollectionView];
    [self notifyDelegate];
}

- (void)replaceImageAtIndex:(NSInteger)index withImage:(UIImage *)image {
    if (index < 0 || index >= [self imageCount] || !image) return;
    UIImage *normalized = [self pp_normalizedImageForCollection:image];
    if (!normalized) return;
    
    [self.arrayLock lock];
    [self pp_ensureMutableCollections];
    [self.mediaOutputArray replaceObjectAtIndex:index withObject:normalized];
    
    // For PPPickerAssetManager, we need to replace with asset if available
    PHAsset *asset = nil;
    if (index < self.imageManager.assetArray.count) {
        id obj = [self.imageManager.assetArray objectAtIndex:index];
        if ([obj isKindOfClass:[PHAsset class]]) {
            asset = obj;
        }
    }
    [self.imageManager replaceImageAtIndex:index withImage:normalized asset:asset];
    [self.arrayLock unlock];
    
    [self reloadCollectionView];
    [self notifyDelegate];
}

- (void)clearAllImages {
    [self.arrayLock lock];
    [self pp_ensureMutableCollections];
    [self.mediaOutputArray removeAllObjects];
    [self.imageManager clearAll];
    [self.arrayLock unlock];
    
    [self reloadCollectionView];
    [self notifyDelegate];
}

- (void)reloadCollectionView {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collectionView reloadData];
    });
}

- (void)notifyDelegate {
    if ([self.delegate respondsToSelector:@selector(imageCollection:didUpdateImages:)]) {
        [self.delegate imageCollection:self didUpdateImages:[self allImages]];
    }
}

#pragma mark - Preloading Images

- (void)preloadImagesFromURLs:(NSArray<NSString *> *)urls completion:(void(^)(void))completion {
    if (urls.count == 0) {
        if (completion) completion();
        return;
    }
    
    [self clearAllImages];
    
    // Create placeholders
    for (NSInteger i = 0; i < urls.count; i++) {
        [self.arrayLock lock];
        [self pp_ensureMutableCollections];
        [self.mediaOutputArray addObject:[UIImage new]];
        [self.imageManager.selectedImages addObject:[UIImage new]];
        [self.arrayLock unlock];
    }
    
    dispatch_group_t group = dispatch_group_create();
    
    for (NSInteger i = 0; i < urls.count; i++) {
        NSString *urlStr = urls[i];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) continue;
        
        dispatch_group_enter(group);
        
        // Using system URLSession for simplicity
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            UIImage *image = nil;
            if (data && !error) {
                image = [UIImage imageWithData:data];
            }
            
            UIImage *finalImage = image ?: [UIImage new];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.arrayLock lock];
                if (i < self.mediaOutputArray.count) {
                    [self.mediaOutputArray replaceObjectAtIndex:i withObject:finalImage];
                }
                if (i < self.imageManager.selectedImages.count) {
                    [self.imageManager.selectedImages replaceObjectAtIndex:i withObject:finalImage];
                }
                [self.arrayLock unlock];
                
                dispatch_group_leave(group);
            });
        }];
        [task resume];
    }
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSArray<UIImage *> *cleanImages = [self pp_sanitizedImagesFromArray:self.mediaOutputArray];
        [self.arrayLock lock];
        [self pp_ensureMutableCollections];
        [self.mediaOutputArray removeAllObjects];
        [self.mediaOutputArray addObjectsFromArray:cleanImages];
        self.imageManager.selectedImages = [cleanImages mutableCopy];
        [self.arrayLock unlock];
        
        [self reloadCollectionView];
        [self notifyDelegate];
        
        if (completion) completion();
    });
}

#pragma mark - Collection View Data Source

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSInteger imageCount = [self imageCount];
    BOOL shouldShowAddButton = (imageCount < self.maxImageCount);
    return imageCount + (shouldShowAddButton ? 1 : 0);
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger imageCount = [self imageCount];
    BOOL shouldShowAddButton = (imageCount < self.maxImageCount);
    BOOL isAddButtonCell = shouldShowAddButton && (indexPath.item == imageCount);
    
    if (isAddButtonCell) {
        AddButtonCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AddButtonCell" forIndexPath:indexPath];
        __weak typeof(self) weakSelf = self;
        if (@available(iOS 14.0, *)) {
            UIAction *galleryAction =
            [UIAction actionWithTitle:kLang(@"Photo_Library")
                                image:[UIImage systemImageNamed:@"photo.on.rectangle"]
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                UIViewController *presentingVC = [weakSelf pp_bestPresentingViewController:nil];
                [weakSelf openGalleryPickerFromViewController:presentingVC];
            }];

            UIAction *cameraAction =
            [UIAction actionWithTitle:kLang(@"Camera")
                                image:[UIImage systemImageNamed:@"camera"]
                           identifier:nil
                              handler:^(__kindof UIAction * _Nonnull action) {
                UIViewController *presentingVC = [weakSelf pp_bestPresentingViewController:nil];
                [weakSelf openCameraFromViewController:presentingVC];
            }];

            UIMenu *menu = [UIMenu menuWithTitle:@""
                                        children:@[galleryAction, cameraAction]];
            [cell setPrimaryMenu:menu];
            cell.onTap = nil;
        } else {
            cell.onTap = ^{
                [weakSelf openImagePicker];
            };
        }
        return cell;
    }
    
    // Image cell
    PP_ImageCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"PP_ImageCell" forIndexPath:indexPath];
    cell.imageView.image = nil;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.backgroundColor = UIColor.clearColor;
    
    NSArray *images = [self allImages];
    if (indexPath.item < imageCount) {
        UIImage *candidate = (indexPath.item < images.count && [images[indexPath.item] isKindOfClass:[UIImage class]])
            ? (UIImage *)images[indexPath.item]
            : nil;
        if ([self pp_isRenderableImage:candidate]) {
            cell.imageView.image = candidate;
            cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
            cell.imageView.backgroundColor = UIColor.clearColor;
        } else {
            UIImage *placeholder = [UIImage systemImageNamed:@"photo"];
            cell.imageView.image = placeholder;
            cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
            cell.imageView.tintColor = [UIColor ppTextSecondary];
            cell.imageView.backgroundColor = [UIColor tertiarySystemFillColor];
        }
    }
    
    __weak typeof(self) weakSelf = self;
    __weak PP_ImageCell *weakCell = cell;
    cell.onDelete = ^{
        PP_ImageCell *strongCell = weakCell;
        NSIndexPath *currentPath = [collectionView indexPathForCell:strongCell];
        if (!currentPath || currentPath.item >= [weakSelf imageCount]) return;
        [weakSelf removeImageAtIndex:currentPath.item];
    };
    
    cell.onTap = ^{
        PP_ImageCell *strongCell = weakCell;
        NSIndexPath *currentPath = [collectionView indexPathForCell:strongCell];
        if (!currentPath || currentPath.item >= [weakSelf imageCount]) return;
        [weakSelf handleImageTapAtIndex:currentPath.item];
    };
    
    return cell;
}

#pragma mark - Collection View Delegate

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat collectionHeight = CGRectGetHeight(collectionView.bounds);
    CGFloat collectionWidth = CGRectGetWidth(collectionView.bounds);
    CGFloat itemWidth = MAX(72.0, collectionHeight - 16.0);
    CGFloat maxAllowed = MAX(72.0, collectionWidth - 16.0);
    itemWidth = MIN(itemWidth, maxAllowed);
    return CGSizeMake(itemWidth, itemWidth);
}

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath
{
    return self.allowsReordering && (indexPath.item < [self imageCount]);
}

- (NSIndexPath *)collectionView:(UICollectionView *)collectionView
targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath *)originalIndexPath
            toProposedIndexPath:(NSIndexPath *)proposedIndexPath
{
    NSInteger currentCount = [self imageCount];
    if (currentCount <= 0) {
        return originalIndexPath;
    }
    NSInteger clampedItem = MIN(MAX(proposedIndexPath.item, 0), currentCount - 1);
    return [NSIndexPath indexPathForItem:clampedItem inSection:originalIndexPath.section];
}

- (void)collectionView:(UICollectionView *)collectionView
moveItemAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath
{
    NSInteger fromIndex = sourceIndexPath.item;
    NSInteger toIndex = destinationIndexPath.item;
    NSInteger count = [self imageCount];

    if (fromIndex == toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= count || toIndex >= count) {
        [self reloadCollectionView];
        return;
    }

    [self.arrayLock lock];
    [self pp_ensureMutableCollections];
    UIImage *movingImage = self.mediaOutputArray[fromIndex];
    if (!movingImage) {
        [self.arrayLock unlock];
        [self reloadCollectionView];
        return;
    }
    [self.mediaOutputArray removeObjectAtIndex:fromIndex];
    [self.mediaOutputArray insertObject:movingImage atIndex:toIndex];
    [self.arrayLock unlock];

    [self.imageManager moveImageFromIndex:fromIndex toIndex:toIndex];
    [self reloadCollectionView];
    [self notifyDelegate];
}

- (void)handleReorderLongPress:(UILongPressGestureRecognizer *)gesture
{
    if (!self.allowsReordering) return;

    CGPoint location = [gesture locationInView:self.collectionView];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:location];
            if (!indexPath || indexPath.item >= [self imageCount]) {
                return;
            }
            [self.collectionView beginInteractiveMovementForItemAtIndexPath:indexPath];
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.collectionView updateInteractiveMovementTargetPosition:location];
            break;
        case UIGestureRecognizerStateEnded:
            [self.collectionView endInteractiveMovement];
            break;
        default:
            [self.collectionView cancelInteractiveMovement];
            break;
    }
}

#pragma mark - Image Tap Handling

- (void)handleImageTapAtIndex:(NSInteger)index {
    if (index < 0 || index >= [self imageCount]) return;
    
    if (self.allowsEditing) {
        // Store selection and open editor
        self.selectedForEdit = index;
        
        NSArray *images = [self allImages];
        UIImage *image = images[index];
        
        // Present editor through the parent view controller
        if ([self.delegate respondsToSelector:@selector(imageCollection:didSelectImage:AtIndex:)]) {
            [self.delegate imageCollection:self didSelectImage:image AtIndex:index];
        }
        
        // You can also present editor directly if you have access to view controller
        //[self.editorBridge presentEditorFromViewController:AppMgr.topViewController withImage:image useArabic:self.useArabic];
    } else {
        NSArray *images = [self allImages];
        UIImage *image = images[index];
        
        // Just notify delegate
        if ([self.delegate respondsToSelector:@selector(imageCollection:didSelectImage:AtIndex:)]) {
            [self.delegate imageCollection:self didSelectImage:image AtIndex:index];
        }
    }
}
 

#pragma mark - Image Picker

- (void)openImagePicker {
    UIViewController *presentingVC = [self pp_bestPresentingViewController:nil];
    if (!presentingVC) {
        return;
    }
    [self openGalleryPickerFromViewController:presentingVC];
}

- (UIViewController *)pp_bestPresentingViewController:(UIViewController * _Nullable)preferredVC
{
    UIViewController *vc = preferredVC ?: [self pp_parentViewController] ?: [PetAccessory pp_topViewController];
    if (!vc) {
        return nil;
    }

    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        vc = nav.topViewController ?: nav;
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)vc;
        UIViewController *selected = tab.selectedViewController;
        if ([selected isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)selected;
            vc = nav.topViewController ?: nav;
        } else if (selected) {
            vc = selected;
        }
    }

    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }

    if ([vc isKindOfClass:[UIAlertController class]]) {
        vc = vc.presentingViewController ?: vc;
    }

    if ([vc isKindOfClass:[QBImagePickerController class]] ||
        [vc isKindOfClass:[UIImagePickerController class]]) {
        return nil;
    }

    if (vc.isBeingDismissed || vc.isBeingPresented) {
        return nil;
    }

    return vc;
}

- (UIViewController *)pp_parentViewController
{
    UIResponder *responder = self;
    while (responder) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

- (void)openGalleryPickerFromViewController:(UIViewController *)viewController
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self openGalleryPickerFromViewController:viewController];
        });
        return;
    }

    UIViewController *presentingVC = [self pp_bestPresentingViewController:viewController];
    if (!presentingVC) return;
    if (![self pp_canAddMoreImagesForPresenter:presentingVC]) return;
    if (self.isPresentingMediaPicker || self.currentPicker || self.cameraPicker) return;
    if (presentingVC.presentedViewController && !presentingVC.presentedViewController.isBeingDismissed) return;

    QBImagePickerController *imagePickerController = [QBImagePickerController new];
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    imagePickerController.showsNumberOfSelectedAssets = YES;
    imagePickerController.maximumNumberOfSelection = self.maxImageCount - [self imageCount];

    imagePickerController.mediaType = QBImagePickerMediaTypeImage;
    NSArray<PHAsset *> *preselected = [self.imageManager preselectedAssetsForPicker];
    if (preselected.count > 0) {
        imagePickerController.selectedAssets = [NSMutableOrderedSet orderedSetWithArray:preselected];
    }

    imagePickerController.modalPresentationStyle = UIModalPresentationPageSheet;
    imagePickerController.view.backgroundColor = AppClearClr;
    imagePickerController.modalInPresentation = YES;
    imagePickerController.view.backgroundColor = UIColor.clearColor;

    // Set flags before presentation
    self.isPresentingMediaPicker = YES;
    self.currentPicker = imagePickerController;
    
    [presentingVC presentViewController:imagePickerController
                               animated:YES
                             completion:^{
        NSLog(@"[PPImageCollection] Gallery picker presented successfully");
    }];
}

- (void)openCameraFromViewController:(UIViewController *)viewController
{
    // Ensure we're on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self openCameraFromViewController:viewController];
        });
        return;
    }

    if (!viewController) return;
    if (![self pp_canAddMoreImagesForPresenter:viewController]) return;
    
    // Check state flags to prevent concurrent presentations
    if (self.isPresentingMediaPicker || self.currentPicker || self.cameraPicker) return;

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self presentSimpleAlertOn:viewController
                             title:kLang(@"Camera")
                           message:kLang(@"camera_not_available")];
        return;
    }

    AVAuthorizationStatus auth = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (auth == AVAuthorizationStatusDenied || auth == AVAuthorizationStatusRestricted) {
        [self presentSimpleAlertOn:viewController
                             title:kLang(@"Camera")
                           message:kLang(@"camera_permission_needed")];
        return;
    }

    if (auth == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [weakSelf presentCameraPickerFromViewController:viewController];
                } else {
                    [weakSelf presentSimpleAlertOn:viewController
                                             title:kLang(@"Camera")
                                           message:kLang(@"camera_permission_needed")];
                }
            });
        }];
        return;
    }

    [self presentCameraPickerFromViewController:viewController];
}

- (BOOL)pp_canAddMoreImagesForPresenter:(UIViewController *)viewController
{
    if ([self imageCount] < self.maxImageCount) {
        return YES;
    }

    NSString *title = kLang(@"max_images_reached");
    if (![title isKindOfClass:[NSString class]] || title.length == 0 || [title isEqualToString:@"max_images_reached"]) {
        title = @"Maximum images reached";
    }

    NSString *hintPrefix = kLang(@"max_images_hint");
    if (![hintPrefix isKindOfClass:[NSString class]] || hintPrefix.length == 0 || [hintPrefix isEqualToString:@"max_images_hint"]) {
        hintPrefix = @"You can upload up to";
    }

    NSString *message = [NSString stringWithFormat:@"%@ %ld", hintPrefix, (long)self.maxImageCount];
    [self presentSimpleAlertOn:viewController title:title message:message];
    return NO;
}

- (void)presentCameraPickerFromViewController:(UIViewController *)viewController
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentCameraPickerFromViewController:viewController];
        });
        return;
    }

    UIViewController *presentingVC = [self pp_bestPresentingViewController:viewController];
    if (!presentingVC) return;
    if (self.isPresentingMediaPicker || self.currentPicker || self.cameraPicker) return;
    if (presentingVC.presentedViewController && !presentingVC.presentedViewController.isBeingDismissed) return;

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.delegate = self;
    picker.allowsEditing = NO;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // Set flags before presentation
    self.isPresentingMediaPicker = YES;
    self.cameraPicker = picker;

    // Present with completion handler to verify success
    [presentingVC presentViewController:picker animated:YES completion:^{
        NSLog(@"[PPImageCollection] Camera picker presented successfully");
    }];
}

- (void)presentSimpleAlertOn:(UIViewController *)viewController title:(NSString *)title message:(NSString *)message
{
    if (!viewController) return;
    NSString *finalTitle = title.length ? title : @"";
    NSString *finalMessage = message.length ? message : @"";
    UIAlertController *alert =
    [UIAlertController alertControllerWithTitle:finalTitle
                                        message:finalMessage
                                 preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [viewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - QBImagePickerControllerDelegate

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingAssets:(NSArray *)assets {
    __weak typeof(self) weakSelf = self;
    [self pp_showLoadingOverlay];
    [self pp_cancelLoadingTimeoutIfNeeded];

    __block BOOL didFinalize = NO;
    dispatch_block_t timeoutBlock = dispatch_block_create(0, ^{
        if (didFinalize || !weakSelf) return;
        didFinalize = YES;
        [weakSelf pp_syncImagesFromManager];
        [weakSelf reloadCollectionView];
        [weakSelf notifyDelegate];
        [weakSelf pp_hideLoadingOverlay];
    });
    self.loadingTimeoutBlock = timeoutBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   timeoutBlock);

    [self.imageManager addAssetsFromPicker:assets completion:^(BOOL didChange) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (didFinalize) {
                return;
            }
            didFinalize = YES;
            [weakSelf pp_cancelLoadingTimeoutIfNeeded];
            if (!didChange) {
                NSLog(@"[PPImageCollection] Picker returned no delta, syncing existing manager images");
            }
            [weakSelf pp_syncImagesFromManager];
            [weakSelf reloadCollectionView];
            [weakSelf notifyDelegate];
            [weakSelf pp_hideLoadingOverlay];
        });
    }];
    
    [self dismissPicker];
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController {
    [self pp_cancelLoadingTimeoutIfNeeded];
    [self dismissPicker];
    [self pp_hideLoadingOverlay];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info
{
    UIImage *pickedImage = info[UIImagePickerControllerOriginalImage];
    if (!pickedImage) {
        pickedImage = info[UIImagePickerControllerEditedImage];
    }

    if (pickedImage) {
        [self addImage:pickedImage];
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        self.isPresentingMediaPicker = NO;
        self.cameraPicker = nil;
        [self pp_hideLoadingOverlay];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:^{
        self.isPresentingMediaPicker = NO;
        self.cameraPicker = nil;
        [self pp_hideLoadingOverlay];
    }];
}

- (void)dismissPicker {
    if (self.currentPicker) {
        [self.currentPicker dismissViewControllerAnimated:YES completion:^{
            self.isPresentingMediaPicker = NO;
            self.currentPicker = nil;
            self.cameraPicker = nil;
            [self pp_cancelLoadingTimeoutIfNeeded];
        }];
    } else {
        self.isPresentingMediaPicker = NO;
        self.currentPicker = nil;
        self.cameraPicker = nil;
        [self pp_cancelLoadingTimeoutIfNeeded];
    }
}

#pragma mark - Editor Notifications

- (void)editorDidFinish:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    UIImage *editedImage = userInfo[@"image"];
    
    if (!editedImage) {
        // Try to get from URL
        NSURL *fileURL = userInfo[@"url"];
        if (fileURL) {
            NSData *imageData = [NSData dataWithContentsOfURL:fileURL];
            editedImage = [UIImage imageWithData:imageData];
        }
    }
    
    if (!editedImage) return;
    
    if (self.selectedForEdit >= 0 && self.selectedForEdit < [self imageCount]) {
        // Replace existing image
        [self replaceImageAtIndex:self.selectedForEdit withImage:editedImage];
    } else {
        // Add new image
        [self addImage:editedImage];
    }
    
    self.selectedForEdit = -1;
}

- (void)editorDidCancel:(NSNotification *)notification {
    self.selectedForEdit = -1;
}

#pragma mark - Convenience

- (void)presentPickerFromViewController:(UIViewController *)viewController {
    UIViewController *presentingVC = [self pp_bestPresentingViewController:viewController];
    [self openGalleryPickerFromViewController:presentingVC];
}

- (void)presentEditorForImageAtIndex:(NSInteger)index fromViewController:(UIViewController *)viewController {
    if (index < 0 || index >= [self imageCount] || !viewController) return;
    
    NSArray *images = [self allImages];
    UIImage *image = images[index];
    self.selectedForEdit = index;
    
    [self.editorBridge presentEditorFromViewController:viewController withImage:image useArabic:self.useArabic];
}

- (void)showActionSheetForAddingImage {
    UIViewController *presentingVC = [self pp_bestPresentingViewController:nil];
    if (!presentingVC) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Photo_Library")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
        [weakSelf openGalleryPickerFromViewController:presentingVC];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Camera")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
        [weakSelf openCameraFromViewController:presentingVC];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [presentingVC presentViewController:sheet animated:YES completion:nil];
}

@end
