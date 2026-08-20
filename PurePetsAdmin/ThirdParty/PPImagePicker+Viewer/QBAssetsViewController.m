//
//  QBAssetsViewController.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBAssetsViewController.h"
#import <Photos/Photos.h>

// Views
#import "QBImagePickerController.h"
#import "QBAssetCell.h"
#import "QBVideoIndicatorView.h"

static CGSize CGSizeScale(CGSize size, CGFloat scale) {
    return CGSizeMake(size.width * scale, size.height * scale);
}

@interface QBImagePickerController (Private)

@property (nonatomic, strong) NSBundle *assetBundle;

@end

@implementation NSIndexSet (Convenience)

- (NSArray *)qb_indexPathsFromIndexesWithSection:(NSUInteger)section
{
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:self.count];
    [self enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexPaths addObject:[NSIndexPath indexPathForItem:idx inSection:section]];
    }];
    return indexPaths;
}

@end

@implementation UICollectionView (Convenience)

- (NSArray *)qb_indexPathsForElementsInRect:(CGRect)rect
{
    NSArray *allLayoutAttributes = [self.collectionViewLayout layoutAttributesForElementsInRect:rect];
    if (allLayoutAttributes.count == 0) { return nil; }
    
    NSMutableArray *indexPaths = [NSMutableArray arrayWithCapacity:allLayoutAttributes.count];
    for (UICollectionViewLayoutAttributes *layoutAttributes in allLayoutAttributes) {
        NSIndexPath *indexPath = layoutAttributes.indexPath;
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}

@end

@interface QBAssetsViewController () <PHPhotoLibraryChangeObserver, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) IBOutlet UIBarButtonItem *doneButton;
@property (nonatomic, strong) UIButton *infoBTN;
@property (nonatomic, strong) PHFetchResult *fetchResult;

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, assign) CGRect previousPreheatRect;

@property (nonatomic, assign) BOOL disableScrollToBottom;
@property (nonatomic, strong) NSIndexPath *lastSelectedItemIndexPath;

@end

@implementation QBAssetsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    _infoBTN.hidden = YES;
    [self pp_buttonWithTitle:@""];
    [self.view addSubview:self.infoBTN];
    
    [self setUpToolbarItems];
    [self resetCachedAssets];
    
    // Register observer
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // Configure navigation item
    self.navigationItem.title = self.assetCollection.localizedTitle;
    //self.navigationItem.prompt = self.imagePickerController.prompt;
    
    // Configure collection view
    self.collectionView.allowsMultipleSelection = self.imagePickerController.allowsMultipleSelection;
    
    // Show/hide 'Done' button
    if (self.imagePickerController.allowsMultipleSelection) {
        [self.navigationItem setRightBarButtonItem:self.doneButton animated:NO];
    } else {
        [self.navigationItem setRightBarButtonItem:nil animated:NO];
    }
    
    [self updateDoneButtonState];
    [self updateSelectionInfo];
    [self.collectionView reloadData];
    self.disableScrollToBottom = NO;
    // Scroll to bottom
    if (self.fetchResult.count > 0 && self.isMovingToParentViewController && !self.disableScrollToBottom) {
        // when presenting as a .FormSheet on iPad, the frame is not correct until just after viewWillAppear:
        // dispatching to the main thread waits one run loop until the frame is update and the layout is complete
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:(self.fetchResult.count - 1) inSection:0];
            [self.collectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionTop animated:NO];
        });
    }
    
    //UIImage *img = [[UIImage systemImageNamed:PPIsRL ? @"arrow.right" : @"arrow.left"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    //self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:img style:UIBarButtonItemStylePlain target:self action:@selector(onBack)];
    [self installCustomNavButtons];
    
    
    [self.view bringSubviewToFront:self.infoBTN];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    self.disableScrollToBottom = NO;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.disableScrollToBottom = NO;
    
    [self updateCachedAssets];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    // Save indexPath for the last item
    NSIndexPath *indexPath = [[self.collectionView indexPathsForVisibleItems] lastObject];
    
    // Update layout
    [self.collectionViewLayout invalidateLayout];
    
    // Restore scroll position
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.collectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    }];
}

- (void)dealloc
{
    // Deregister observer
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}


#pragma mark - Accessors

- (void)setAssetCollection:(PHAssetCollection *)assetCollection
{
    _assetCollection = assetCollection;
    
    [self updateFetchRequest];
    [self.collectionView reloadData];
}

- (PHCachingImageManager *)imageManager
{
    if (_imageManager == nil) {
        _imageManager = [PHCachingImageManager new];
    }
    
    return _imageManager;
}

- (BOOL)isAutoDeselectEnabled
{
    return (self.imagePickerController.maximumNumberOfSelection == 1
            && self.imagePickerController.maximumNumberOfSelection >= self.imagePickerController.minimumNumberOfSelection);
}


#pragma mark - Actions

- (IBAction)done:(id)sender
{
    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didFinishPickingAssets:)]) {
        [self.imagePickerController.delegate qb_imagePickerController:self.imagePickerController
                                               didFinishPickingAssets:self.imagePickerController.selectedAssets.array];
    }
}


#pragma mark - Toolbar

- (void)setUpToolbarItems
{
    [self updateSelectionInfo];
}
- (void)setUpToolbarItemsaction
{
    [self updateSelectionInfo];
}

- (void)updateSelectionInfo {

    NSMutableOrderedSet *selectedAssets = self.imagePickerController.selectedAssets;

    // STEP 1 — Create pill container
    

    // STEP 2 — Label inside pill
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) {
        config = [UIButtonConfiguration glassButtonConfiguration];
    } else {
        config =    [UIButtonConfiguration filledButtonConfiguration];
    }
    // STEP 1 — lbl pill container
    
    NSString  *lblTitle;
    if (selectedAssets.count == 0) {
        [self.infoBTN setHidden:YES];
        lblTitle = [NSString stringWithFormat:@"%ld %@", (long)selectedAssets.count,
                    kLang(@"assets.toolbar.item-zero")];
    } else if (selectedAssets.count == 1) {
        [self.infoBTN setHidden:NO];
        lblTitle = [NSString stringWithFormat:@"%ld %@", (long)selectedAssets.count,
                    kLang(@"assets.toolbar.item-selected")];
    } else {
        [self.infoBTN setHidden:NO];
        lblTitle = [NSString stringWithFormat:@"%ld %@", (long)selectedAssets.count,
                    kLang(@"assets.toolbar.items-selected")];
    }
    
    [self pp_buttonWithTitle:lblTitle];
    // STEP 3 — Turn pill into toolbar item
    
}

-(void)updateSelectCount:(NSInteger)count
{
    NSString  *lblTitle;
    if (count == 0) {
        lblTitle = [NSString stringWithFormat:@"%ld %@", count,
                    kLang(@"assets.toolbar.item-zero")];
    } else if (count == 1) {
        lblTitle = [NSString stringWithFormat:@"%ld %@", count,
                    kLang(@"assets.toolbar.item-selected")];
    } else {
        lblTitle = [NSString stringWithFormat:@"%ld %@", count,
                    kLang(@"assets.toolbar.items-selected")];
    }
    
    [self pp_buttonWithTitle:lblTitle];
}
- (void)pp_buttonWithTitle:(nullable NSString *)title
{
    
    if(self.infoBTN)
    {
        UIButtonConfiguration *cfg = self.infoBTN.configuration;

        cfg.attributedTitle =
        [[NSAttributedString alloc] initWithString:title
                                        attributes:@{
            NSFontAttributeName: [UIFont fontWithName:@"Beiruti-Bold" size:16]            }];
        
        // CRITICAL: forces true centered title
        cfg.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
        self.infoBTN.configuration = cfg;
        
        [self.infoBTN layoutIfNeeded];
        return;
    }
    
    // Default size (will center properly with constraints)
    CGFloat height = 60;
    CGFloat width  = 170;
    // -------------------
    // Create button
    // -------------------.v
   
    self.infoBTN = [UIButton buttonWithType:UIButtonTypeSystem];
    self.infoBTN.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.infoBTN];
    [NSLayoutConstraint activateConstraints:@[
        [self.infoBTN.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:0],
        [self.infoBTN.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12],
        [self.infoBTN.widthAnchor constraintEqualToConstant:width],
        [self.infoBTN.heightAnchor constraintEqualToConstant:height]
    ]];

    
    UIButtonConfiguration *cfg;

    if (@available(iOS 26.0, *)) {
        cfg = [UIButtonConfiguration glassButtonConfiguration];
        cfg.background.backgroundColor = AppClearClr;
        cfg.baseBackgroundColor = AppClearClr;
    } else if (@available(iOS 15.0, *)) {
        cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.background.backgroundColor = AppClearClr;
        cfg.baseBackgroundColor = AppClearClr;
        cfg.background.cornerRadius = height / 2;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(6, 14, 6, 14);
    } else {
        // Legacy fallback — manual styling
        self.infoBTN.layer.cornerRadius = height / 2;
        self.infoBTN.backgroundColor = [UIColor ppBackground];
        [self.infoBTN setTitleColor:[UIColor ppTextPrimary] forState:UIControlStateNormal];
        self.infoBTN.titleLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:16];
    }

    // -------------------
    // Centered Title (ALL iOS versions)
    // -------------------
    if (title) {
        if (@available(iOS 15.0, *)) {
            cfg.attributedTitle =
            [[NSAttributedString alloc] initWithString:title
                                            attributes:@{
                NSFontAttributeName: [UIFont fontWithName:@"Beiruti-Bold" size:16]            }];
            
            // CRITICAL: forces true centered title
            cfg.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
        } else {
            [self.infoBTN setTitle:title forState:UIControlStateNormal];
            self.infoBTN.titleLabel.textAlignment = NSTextAlignmentCenter;
        }
    }
    [self.infoBTN addTarget:self action:@selector(done:) forControlEvents:UIControlEventTouchUpInside];
    // -------------------
    // Apply configuration
    // -------------------
    if (@available(iOS 15.0, *)) {
        [self.infoBTN setConfiguration:cfg];
    }

    // -------------------
    // Shadow (modern subtle)
    // -------------------
    self.infoBTN.layer.shadowColor = AppShadowClr.CGColor;
    self.infoBTN.layer.shadowOpacity = 0.10;
    self.infoBTN.layer.shadowOffset = CGSizeMake(0, 3);
    self.infoBTN.layer.shadowRadius = 8;
    self.infoBTN.layer.masksToBounds = NO;
}


- (void)installCustomNavButtons
{
   
    // Left (back) button
    NSString *backSymbol = PPIsRL ? @"arrow.right" : @"arrow.left";
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:[self pp_ButtonWithSystemName:backSymbol action:@selector(onBack)]];
    self.navigationItem.leftBarButtonItem = backItem;
    
    // Right (done) button — keep self.doneButton reference for other code
    NSString *doneSymbol = @"checkmark";
    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithCustomView:[self pp_ButtonWithSystemName:doneSymbol action:@selector(done:)]];
    self.doneButton = doneItem; // keep the property so updateControlState can enable/disable
    
    // Set tint for done button to indicate disabled/enabled
    //[self updateDoneButtonAppearance];
    
    // Place on nav bar
    if (self.imagePickerController.allowsMultipleSelection) {
        self.navigationItem.rightBarButtonItem = doneItem;
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)updateDoneButtonAppearance
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIBarButtonItem *doneItem = self.doneButton;
        UIView *customView = doneItem.customView;
        if (![customView isKindOfClass:[UIButton class]]) return;
        UIButton *btn = (UIButton *)customView;
        
        BOOL enabled = [self isMinimumSelectionLimitFulfilled];
        btn.userInteractionEnabled = enabled;
        
        // Visual state: tinted fill when enabled, light background when disabled
        if (enabled) {
            btn.backgroundColor = [UIColor ppPrimary]; // change color to match app primary color
            btn.tintColor = UIColor.whiteColor;
            btn.layer.shadowOpacity = 0.18;
        } else {
            btn.backgroundColor = [UIColor ppSurface];
            btn.tintColor = [UIColor ppTextPrimary];
            btn.layer.shadowOpacity = 0.06;
        }
        
        // update accessibility value
        btn.accessibilityValue = enabled ? NSLocalizedString(@"Enabled", @"Enabled") : NSLocalizedString(@"Disabled", @"Disabled");
    });
}


#pragma mark - Fetching Assets

- (void)updateFetchRequest
{
    if (self.assetCollection) {
        PHFetchOptions *options = [PHFetchOptions new];
        
        switch (self.imagePickerController.mediaType) {
            case QBImagePickerMediaTypeImage:
                options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeImage];
                break;
                
            case QBImagePickerMediaTypeVideo:
                options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeVideo];
                break;
                
            default:
                break;
        }
        
        self.fetchResult = [PHAsset fetchAssetsInAssetCollection:self.assetCollection options:options];
        
        if ([self isAutoDeselectEnabled] && self.imagePickerController.selectedAssets.count > 0) {
            // Get index of previous selected asset
            PHAsset *asset = [self.imagePickerController.selectedAssets firstObject];
            NSInteger assetIndex = [self.fetchResult indexOfObject:asset];
            if (assetIndex != NSNotFound) {
                self.lastSelectedItemIndexPath = [NSIndexPath indexPathForItem:assetIndex inSection:0];
            } else {
                self.lastSelectedItemIndexPath = nil;
            }
        }
    } else {
        self.fetchResult = nil;
    }
}


#pragma mark - Checking for Selection Limit

- (BOOL)isMinimumSelectionLimitFulfilled
{
   return (self.imagePickerController.minimumNumberOfSelection <= self.imagePickerController.selectedAssets.count);
}

- (BOOL)isMaximumSelectionLimitReached
{
    NSUInteger minimumNumberOfSelection = MAX(1, self.imagePickerController.minimumNumberOfSelection);
   
    if (minimumNumberOfSelection <= self.imagePickerController.maximumNumberOfSelection) {
        return (self.imagePickerController.maximumNumberOfSelection <= self.imagePickerController.selectedAssets.count);
    }
   
    return NO;
}

- (void)updateDoneButtonState
{
    self.doneButton.enabled = [self isMinimumSelectionLimitFulfilled];
}


#pragma mark - Asset Caching

- (void)resetCachedAssets
{
    [self.imageManager stopCachingImagesForAllAssets];
    self.previousPreheatRect = CGRectZero;
}

- (void)updateCachedAssets
{
    BOOL isViewVisible = [self isViewLoaded] && self.view.window != nil;
    if (!isViewVisible) { return; }
    
    // The preheat window is twice the height of the visible rect
    CGRect preheatRect = self.collectionView.bounds;
    preheatRect = CGRectInset(preheatRect, 0.0, -0.5 * CGRectGetHeight(preheatRect));
    
    // If scrolled by a "reasonable" amount...
    CGFloat delta = ABS(CGRectGetMidY(preheatRect) - CGRectGetMidY(self.previousPreheatRect));
    
    if (delta > CGRectGetHeight(self.collectionView.bounds) / 3.0) {
        // Compute the assets to start caching and to stop caching
        NSMutableArray *addedIndexPaths = [NSMutableArray array];
        NSMutableArray *removedIndexPaths = [NSMutableArray array];
        
        [self computeDifferenceBetweenRect:self.previousPreheatRect andRect:preheatRect addedHandler:^(CGRect addedRect) {
            NSArray *indexPaths = [self.collectionView qb_indexPathsForElementsInRect:addedRect];
            [addedIndexPaths addObjectsFromArray:indexPaths];
        } removedHandler:^(CGRect removedRect) {
            NSArray *indexPaths = [self.collectionView qb_indexPathsForElementsInRect:removedRect];
            [removedIndexPaths addObjectsFromArray:indexPaths];
        }];
        
        NSArray *assetsToStartCaching = [self assetsAtIndexPaths:addedIndexPaths];
        NSArray *assetsToStopCaching = [self assetsAtIndexPaths:removedIndexPaths];
        
        CGSize itemSize = [(UICollectionViewFlowLayout *)self.collectionViewLayout itemSize];
        CGSize targetSize = CGSizeScale(itemSize, [[UIScreen mainScreen] scale]);
        
        [self.imageManager startCachingImagesForAssets:assetsToStartCaching
                                            targetSize:targetSize
                                           contentMode:PHImageContentModeAspectFill
                                               options:nil];
        [self.imageManager stopCachingImagesForAssets:assetsToStopCaching
                                           targetSize:targetSize
                                          contentMode:PHImageContentModeAspectFill
                                              options:nil];
        
        self.previousPreheatRect = preheatRect;
    }
}

- (void)computeDifferenceBetweenRect:(CGRect)oldRect andRect:(CGRect)newRect addedHandler:(void (^)(CGRect addedRect))addedHandler removedHandler:(void (^)(CGRect removedRect))removedHandler
{
    if (CGRectIntersectsRect(newRect, oldRect)) {
        CGFloat oldMaxY = CGRectGetMaxY(oldRect);
        CGFloat oldMinY = CGRectGetMinY(oldRect);
        CGFloat newMaxY = CGRectGetMaxY(newRect);
        CGFloat newMinY = CGRectGetMinY(newRect);
        
        if (newMaxY > oldMaxY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, oldMaxY, newRect.size.width, (newMaxY - oldMaxY));
            addedHandler(rectToAdd);
        }
        if (oldMinY > newMinY) {
            CGRect rectToAdd = CGRectMake(newRect.origin.x, newMinY, newRect.size.width, (oldMinY - newMinY));
            addedHandler(rectToAdd);
        }
        if (newMaxY < oldMaxY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, newMaxY, newRect.size.width, (oldMaxY - newMaxY));
            removedHandler(rectToRemove);
        }
        if (oldMinY < newMinY) {
            CGRect rectToRemove = CGRectMake(newRect.origin.x, oldMinY, newRect.size.width, (newMinY - oldMinY));
            removedHandler(rectToRemove);
        }
    } else {
        addedHandler(newRect);
        removedHandler(oldRect);
    }
}

- (NSArray *)assetsAtIndexPaths:(NSArray *)indexPaths
{
    if (indexPaths.count == 0) { return nil; }
    
    NSMutableArray *assets = [NSMutableArray arrayWithCapacity:indexPaths.count];
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.item < self.fetchResult.count) {
            PHAsset *asset = self.fetchResult[indexPath.item];
            if (asset) [assets addObject:asset];
        }
    }
    return assets;
}


#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    dispatch_async(dispatch_get_main_queue(), ^{
        PHFetchResultChangeDetails *collectionChanges = [changeInstance changeDetailsForFetchResult:self.fetchResult];
        
        if (collectionChanges) {
            // Get the new fetch result
            self.fetchResult = [collectionChanges fetchResultAfterChanges];
            
            if (![collectionChanges hasIncrementalChanges] || [collectionChanges hasMoves]) {
                // We need to reload all if the incremental diffs are not available
                [self.collectionView reloadData];
            } else {
                // If we have incremental diffs, tell the collection view to animate insertions and deletions
                [self.collectionView performBatchUpdates:^{
                    NSIndexSet *removedIndexes = [collectionChanges removedIndexes];
                    if ([removedIndexes count]) {
                        [self.collectionView deleteItemsAtIndexPaths:[removedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }
                    
                    NSIndexSet *insertedIndexes = [collectionChanges insertedIndexes];
                    if ([insertedIndexes count]) {
                        [self.collectionView insertItemsAtIndexPaths:[insertedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }
                    
                    NSIndexSet *changedIndexes = [collectionChanges changedIndexes];
                    if ([changedIndexes count]) {
                        [self.collectionView reloadItemsAtIndexPaths:[changedIndexes qb_indexPathsFromIndexesWithSection:0]];
                    }
                } completion:NULL];
            }
            
            [self resetCachedAssets];
        }
    });
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateCachedAssets];
}


#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.fetchResult.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    QBAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"AssetCell"
                                                                  forIndexPath:indexPath];
    cell.tag = indexPath.item;
    cell.showsOverlayViewWhenSelected = self.imagePickerController.allowsMultipleSelection;
    
    // Image
    PHAsset *asset = self.fetchResult[indexPath.item];
    CGSize itemSize = [(UICollectionViewFlowLayout *)collectionView.collectionViewLayout itemSize];
    CGSize targetSize = CGSizeScale(itemSize, [[UIScreen mainScreen] scale]);
    
    [self.imageManager requestImageForAsset:asset
                                 targetSize:targetSize
                                contentMode:PHImageContentModeAspectFill
                                    options:nil
                              resultHandler:^(UIImage *result, NSDictionary *info) {
        if (cell.tag == indexPath.item) {
            cell.imageView.image = result;
        }
    }];
    
    // Video indicator (keep your existing code)
    if (asset.mediaType == PHAssetMediaTypeVideo) {
        cell.videoIndicatorView.hidden = NO;
        NSInteger minutes = (NSInteger)(asset.duration / 60.0);
        NSInteger seconds = (NSInteger)ceil(asset.duration - 60.0 * (double)minutes);
        cell.videoIndicatorView.timeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld",
                                                  (long)minutes, (long)seconds];
        if (asset.mediaSubtypes & PHAssetMediaSubtypeVideoHighFrameRate) {
            cell.videoIndicatorView.videoIcon.hidden = YES;
            cell.videoIndicatorView.slomoIcon.hidden = NO;
        } else {
            cell.videoIndicatorView.videoIcon.hidden = NO;
            cell.videoIndicatorView.slomoIcon.hidden = YES;
        }
    } else {
        cell.videoIndicatorView.hidden = YES;
    }
    
    // Selected state + ORDER BADGE
    NSMutableOrderedSet *selectedAssets = self.imagePickerController.selectedAssets;
    NSInteger selectionIndex = [selectedAssets indexOfObject:asset];
    if (selectionIndex != NSNotFound) {
        // order is index+1
        [cell setSelected:YES];
        [collectionView selectItemAtIndexPath:indexPath
                                     animated:NO
                               scrollPosition:UICollectionViewScrollPositionNone];
        [cell pp_setSelectionIndex:selectionIndex + 1];
    } else {
        [cell setSelected:NO];
        [cell pp_setSelectionIndex:0];
    }
    
    return cell;
}

- (void)pp_updateSelectionOrderBadges {
    NSMutableOrderedSet *selectedAssets = self.imagePickerController.selectedAssets;
    
    for (NSIndexPath *indexPath in [self.collectionView indexPathsForVisibleItems]) {
        if (indexPath.item >= self.fetchResult.count) continue;
        
        PHAsset *asset = self.fetchResult[indexPath.item];
        QBAssetCell *cell = (QBAssetCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
        if (![cell isKindOfClass:[QBAssetCell class]]) continue;
        
        NSInteger selectionIndex = [selectedAssets indexOfObject:asset];
        if (selectionIndex != NSNotFound) {
            [cell pp_setSelectionIndex:selectionIndex + 1];
        } else {
            [cell pp_setSelectionIndex:0];
        }
    }
}


- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if (kind == UICollectionElementKindSectionFooter) {
        UICollectionReusableView *footerView = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                                                                  withReuseIdentifier:@"FooterView"
                                                                                         forIndexPath:indexPath];
        
        // Number of assets
        UILabel *label = (UILabel *)[footerView viewWithTag:1];
        
        label.backgroundColor = AppClearClr;
        NSUInteger numberOfPhotos = [self.fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeImage];
        NSUInteger numberOfVideos = [self.fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeVideo];
        
        switch (self.imagePickerController.mediaType) {
            case QBImagePickerMediaTypeAny:
            {
                NSString *format;
                if (numberOfPhotos == 1) {
                    if (numberOfVideos == 1) {
                        format = kLang(@"assets.footer.photo-and-video");
                    } else {
                        format = kLang(@"assets.footer.photo-and-videos");
                    }
                } else if (numberOfVideos == 1) {
                    format = kLang(@"assets.footer.photos-and-video");
                } else {
                    format = kLang(@"assets.footer.photos-and-videos");
                }
                
                label.text = [NSString stringWithFormat:format, numberOfPhotos, numberOfVideos];
            }
                break;
                
            case QBImagePickerMediaTypeImage:
            {
                NSString *key = (numberOfPhotos == 1) ? @"assets.footer.photo" : @"assets.footer.photos";
                NSString *format = kLang(key);
                
                label.text = [NSString stringWithFormat:format, numberOfPhotos];
            }
                break;
                
            case QBImagePickerMediaTypeVideo:
            {
                NSString *key = (numberOfVideos == 1) ? @"assets.footer.video" : @"assets.footer.videos";
                NSString *format = kLang(key);
                
                label.text = [NSString stringWithFormat:format, numberOfVideos];
            }
                break;
        }
        label.backgroundColor = AppClearClr;
        footerView.backgroundColor = AppClearClr;
        return footerView;
    }
    
    return nil;
}


#pragma mark - UICollectionViewDelegate

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.item >= self.fetchResult.count) {
        return NO;
    }

    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:shouldSelectAsset:)]) {
        PHAsset *asset = self.fetchResult[indexPath.item];
        return [self.imagePickerController.delegate qb_imagePickerController:self.imagePickerController shouldSelectAsset:asset];
    }
    
    if ([self isAutoDeselectEnabled]) {
        return YES;
    }
    
    return ![self isMaximumSelectionLimitReached];
}

- (void)collectionView:(UICollectionView *)collectionView
didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.item >= self.fetchResult.count) {
        return;
    }

    QBImagePickerController *imagePickerController = self.imagePickerController;
    NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;
    PHAsset *asset = self.fetchResult[indexPath.item];
    if (!asset) return; // guard nil — prevents insertObject:nil crashes downstream
    
    if (imagePickerController.allowsMultipleSelection) {
        if ([self isAutoDeselectEnabled] && selectedAssets.count > 0) {
            [selectedAssets removeObjectAtIndex:0];
            if (self.lastSelectedItemIndexPath
                && self.lastSelectedItemIndexPath.item < self.fetchResult.count) {
                [collectionView deselectItemAtIndexPath:self.lastSelectedItemIndexPath
                                               animated:NO];
            }
        }
        
        [selectedAssets addObject:asset];
        self.lastSelectedItemIndexPath = indexPath;
        
        [self updateDoneButtonState];
        if (imagePickerController.showsNumberOfSelectedAssets) {
            [self updateSelectionInfo];
            if (selectedAssets.count == 1) {
                [self.navigationController setToolbarHidden:NO animated:YES];
            }
        }
        
        // IMPORTANT: refresh order badges
        [self pp_updateSelectionOrderBadges];
    } else {
        // single selection flow unchanged...
        if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didFinishPickingAssets:)]) {
            [imagePickerController.delegate qb_imagePickerController:imagePickerController
                                             didFinishPickingAssets:@[asset]];
        }
    }
    
    if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didSelectAsset:)]) {
        [imagePickerController.delegate qb_imagePickerController:imagePickerController
                                                   didSelectAsset:asset];
    }
}


- (void)collectionView:(UICollectionView *)collectionView
didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.imagePickerController.allowsMultipleSelection) {
        return;
    }
    if (indexPath.item >= self.fetchResult.count) {
        return;
    }
    
    QBImagePickerController *imagePickerController = self.imagePickerController;
    NSMutableOrderedSet *selectedAssets = imagePickerController.selectedAssets;
    PHAsset *asset = self.fetchResult[indexPath.item];
    
    [selectedAssets removeObject:asset];
    self.lastSelectedItemIndexPath = nil;
    
    [self updateDoneButtonState];
    if (imagePickerController.showsNumberOfSelectedAssets) {
        [self updateSelectionInfo];
        if (selectedAssets.count == 0) {
            [self.navigationController setToolbarHidden:YES animated:YES];
        }
    }
    
    // IMPORTANT: refresh order badges after removing
    [self pp_updateSelectionOrderBadges];
    
    if ([imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerController:didDeselectAsset:)]) {
        [imagePickerController.delegate qb_imagePickerController:imagePickerController
                                                   didDeselectAsset:asset];
    }
}



#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSUInteger numberOfColumns;
    if (UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation])) {
        numberOfColumns = self.imagePickerController.numberOfColumnsInPortrait;
    } else {
        numberOfColumns = self.imagePickerController.numberOfColumnsInLandscape;
    }
    
    CGFloat width = (CGRectGetWidth(self.view.frame) - 2.0 * (numberOfColumns - 1)) / numberOfColumns;
    
    return CGSizeMake(width, width);
}

@end
