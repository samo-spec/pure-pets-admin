//
//  QBAlbumsViewController.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBAlbumsViewController.h"
#import <Photos/Photos.h>

// Views
#import "QBAlbumCell.h"

// ViewControllers
#import "QBImagePickerController.h"
#import "QBAssetsViewController.h"

static CGSize CGSizeScale(CGSize size, CGFloat scale) {
    return CGSizeMake(size.width * scale, size.height * scale);
}

@interface QBImagePickerController (Private)

@property (nonatomic, strong) NSBundle *assetBundle;

@end

@interface QBAlbumsViewController () <PHPhotoLibraryChangeObserver>

@property (nonatomic, strong) IBOutlet UIBarButtonItem *doneButton;

@property (nonatomic, copy) NSArray *fetchResults;
@property (nonatomic, copy) NSArray *assetCollections;
// Add at top of file (private)
@property (nonatomic, strong) PHCachingImageManager *cachingImageManager;

@end

@implementation QBAlbumsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerClass:QBAlbumCell.class forCellReuseIdentifier:@"QBAlbumCell"];

    [self setUpToolbarItems];
    
    // Fetch user albums and smart albums — guard nil (restricted photo access can return nil)
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    PHFetchResult *userAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    NSMutableArray *fetchResultsArr = [NSMutableArray arrayWithCapacity:2];
    if (smartAlbums) [fetchResultsArr addObject:smartAlbums];
    if (userAlbums)  [fetchResultsArr addObject:userAlbums];
    self.fetchResults = fetchResultsArr;
    
    [self updateAssetCollections];
    
    // Register observer
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.navigationController.navigationBar.translucent = YES;
    self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
    self.navigationController.navigationBar.tintColor = UIColor.blackColor;
    self.navigationController.navigationBar.backgroundColor = UIColor.clearColor;

    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = PPIOS26() ? UIColor.clearColor : AppBackgroundClr;
        appearance.shadowColor = UIColor.clearColor;
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: AppPrimaryTextClr,
            NSFontAttributeName: [UIFont fontWithName:@"Beiruti-Bold" size:18] ?: [UIFont systemFontOfSize:18 weight:UIFontWeightBold]
        };
        appearance.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.blackColor };
 
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.compactAppearance = appearance;
        self.navigationController.navigationBar.prefersLargeTitles = NO;
 
        NSDictionary *titleAttributes = @{
            NSForegroundColorAttributeName: [UIColor labelColor],
            NSFontAttributeName: [UIFont fontWithName:@"Beiruti-Bold" size:18] ?: [UIFont systemFontOfSize:18 weight:UIFontWeightBold]
        };
        [[UINavigationBar appearance] setTitleTextAttributes:titleAttributes];
    }
    

    // Configure navigation item
    self.navigationItem.title = kLang(@"albums.title");
    //self.navigationItem.prompt = self.imagePickerController.prompt;
    
    // Show/hide 'Done' button
    if (self.imagePickerController.allowsMultipleSelection) {
        [self.navigationItem setRightBarButtonItem:self.doneButton animated:NO];
    } else {
        [self.navigationItem setRightBarButtonItem:nil animated:NO];
    }
    
   
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:PPSYSImage(@"multiply") style:UIBarButtonItemStylePlain target:self action:@selector(onDissmiss)];
    
    [self updateControlState];
    [self updateSelectionInfo];
    
    self.tableView.backgroundColor = AppClearClr;
    self.view.backgroundColor = AppClearClr;
    
    if(!PPIOS26()){
        self.view.layer.cornerRadius = 25;
        self.view.clipsToBounds = YES;
        
        self.navigationController.navigationBar.layer.cornerRadius = 25;
        self.navigationController.navigationBar.clipsToBounds = YES;
        
        self.navigationController.navigationBar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    

}

- (void)dealloc
{
    // Deregister observer
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}


#pragma mark - Storyboard

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    QBAssetsViewController *assetsViewController = segue.destinationViewController;
    assetsViewController.imagePickerController = self.imagePickerController;
    assetsViewController.assetCollection = self.assetCollections[self.tableView.indexPathForSelectedRow.row];
    assetsViewController.view.backgroundColor = AppBackgroundClr;
    assetsViewController.collectionView.backgroundColor = AppBackgroundClr;
}


#pragma mark - Actions

- (IBAction)cancel:(id)sender
{
    if ([self.imagePickerController.delegate respondsToSelector:@selector(qb_imagePickerControllerDidCancel:)]) {
        [self.imagePickerController.delegate qb_imagePickerControllerDidCancel:self.imagePickerController];
    }
}

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
    // Space
    UIBarButtonItem *leftSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
    UIBarButtonItem *rightSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
    
    // Info label
    NSDictionary *attributes = @{ NSForegroundColorAttributeName: [UIColor blackColor] };
    UIBarButtonItem *infoButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:NULL];
    infoButtonItem.enabled = NO;
    [infoButtonItem setTitleTextAttributes:attributes forState:UIControlStateNormal];
    [infoButtonItem setTitleTextAttributes:attributes forState:UIControlStateDisabled];
    
    self.toolbarItems = @[leftSpace, infoButtonItem, rightSpace];
}

- (void)updateSelectionInfo {

    NSMutableOrderedSet *selectedAssets = self.imagePickerController.selectedAssets;

    // STEP 1 — Create pill container
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 160, 44)];
    pill.backgroundColor = [AppForgroundColr colorWithAlphaComponent:PPIOS26() ? 0.0 : 0.3];
    pill.layer.cornerRadius = 22;
    pill.clipsToBounds = YES;

    // STEP 2 — Label inside pill
    UILabel *lbl = [[UILabel alloc] initWithFrame:pill.bounds];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont fontWithName:@"Beiruti-Bold" size:16];
    lbl.textColor = UIColor.labelColor;

    if (selectedAssets.count == 0) {
        lbl.text = [NSString stringWithFormat:@"%ld %@", (long)selectedAssets.count,
                    kLang(@"assets.toolbar.item-zero")];
    } else if (selectedAssets.count == 1) {
        lbl.text = [NSString stringWithFormat:@"%ld %@", (long)selectedAssets.count,
                    kLang(@"assets.toolbar.item-selected")];
    } else {
        lbl.text = [NSString stringWithFormat:@"%ld %@", (long)selectedAssets.count,
                    kLang(@"assets.toolbar.items-selected")];
    }

    [pill addSubview:lbl];

    // STEP 3 — Turn pill into toolbar item
    UIBarButtonItem *pillItem = [[UIBarButtonItem alloc] initWithCustomView:pill];

    // STEP 4 — Add flexible spaces left & right to center it
    UIBarButtonItem *flex1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:
                              UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *flex2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:
                              UIBarButtonSystemItemFlexibleSpace target:nil action:nil];

    self.toolbarItems = @[flex1, pillItem, flex2];
    
    if (selectedAssets.count == 0) {
        // Hide toolbar
        [self.navigationController setToolbarHidden:YES animated:YES];
    }
}


- (void)installCustomNavButtons
{
     
    NSString *backSymbol =  @"multiply";
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:[self pp_ButtonWithSystemName:backSymbol action:@selector(onDissmiss)]];
    self.navigationItem.leftBarButtonItem = backItem;
    
    // Right (done) button — keep self.doneButton reference for other code
    NSString *doneSymbol = @"checkmark";
    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithCustomView:[self pp_ButtonWithSystemName:doneSymbol action:@selector(done:)]];
    self.doneButton = doneItem; // keep the property so updateControlState can enable/disable
    
    // Set tint for done button to indicate disabled/enabled
    //[self updateDoneButtonAppearance];
    
    // Place on nav bar
    if (self.imagePickerController.allowsMultipleSelection) {
        self.navigationItem.rightBarButtonItem = self.doneButton;
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}



#pragma mark - Fetching Asset Collections

- (void)onDissmiss {
    [self cancel:nil];
}

- (void)updateAssetCollections
{
    NSArray *assetCollectionSubtypes = self.imagePickerController.assetCollectionSubtypes;
    NSMutableDictionary *smartAlbums = [NSMutableDictionary dictionary];
    NSMutableArray *userAlbums = [NSMutableArray array];

    // Iterate through all fetchResults (smart + user)
    for (PHFetchResult *fetchResult in self.fetchResults) {
        [fetchResult enumerateObjectsUsingBlock:^(PHAssetCollection *collection, NSUInteger index, BOOL *stop) {
            if (!collection) return; // guard nil from PHFetchResult edge cases

            // Fetch assets count in this album
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

            PHFetchResult *assets = [PHAsset fetchAssetsInAssetCollection:collection options:options];

            // ❗ Skip empty albums
            if (assets.count == 0) {
                return; // SKIP this album
            }

            // Categorize
            PHAssetCollectionSubtype subtype = collection.assetCollectionSubtype;

            if (subtype == PHAssetCollectionSubtypeAlbumRegular) {
                [userAlbums addObject:collection];
            } else if ([assetCollectionSubtypes containsObject:@(subtype)]) {
                if (!smartAlbums[@(subtype)]) {
                    smartAlbums[@(subtype)] = [NSMutableArray array];
                }
                [smartAlbums[@(subtype)] addObject:collection];
            }
        }];
    }

    // Build final list
    NSMutableArray *finalCollections = [NSMutableArray array];

    // First smart albums (ordered)
    for (NSNumber *subtype in assetCollectionSubtypes) {
        NSArray *albums = smartAlbums[subtype];
        if (albums.count > 0) {
            [finalCollections addObjectsFromArray:albums];
        }
    }

    // Then user albums (only non-empty due to filtering above)
    [finalCollections addObjectsFromArray:userAlbums];

    self.assetCollections = finalCollections;
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

- (void)updateControlState
{
    self.doneButton.enabled = [self isMinimumSelectionLimitFulfilled];
}


#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.assetCollections.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    QBAlbumCell *cell = [tableView dequeueReusableCellWithIdentifier:[QBAlbumCell reuseIdentifier] forIndexPath:indexPath];
    cell.tag = indexPath.row;
    
    cell.tag = indexPath.row;
 
    // Ensure layout so imageView frames are valid (for target size)
    [cell layoutIfNeeded];

    // Prepare options for fetch
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

    PHAssetCollection *assetCollection = self.assetCollections[indexPath.row];
    PHFetchResult<PHAsset *> *fetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];

    // Compute a safe image view size (points) and the pixel target size for PHImageManager
    CGSize ivSize = cell.imageView1.bounds.size;
    if (CGSizeEqualToSize(ivSize, CGSizeZero) || ivSize.width <= 0 || ivSize.height <= 0) {
        // fallback to the same size you used when creating the cell (keep in sync with QBAlbumCell)
        ivSize = CGSizeMake(60.0, 60.0);
    }
    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize targetPixelSize = CGSizeMake(ceil(ivSize.width * scale), ceil(ivSize.height * scale));

    UIImage *placeholder = [self placeholderImageWithSize:ivSize];

    // Always set placeholders immediately (prevents empty covers)
    cell.imageView1.image = placeholder;
    cell.imageView2.image = placeholder;
    cell.imageView3.image = placeholder;
    cell.imageView1.hidden = NO;
    cell.imageView2.hidden = NO;
    cell.imageView3.hidden = NO;

    if (fetchResult.count == 0) {
        // nothing else to do
    } else {
        // choose last up to 3 assets, keep the order returned by fetchResult (left->right oldest->newest)
        NSUInteger showCount = MIN(3, fetchResult.count);
        NSInteger startIndex = (NSInteger)fetchResult.count - (NSInteger)showCount;

        // PHImageRequestOptions
        PHImageRequestOptions *reqOptions = [PHImageRequestOptions new];
        reqOptions.networkAccessAllowed = YES;
        reqOptions.resizeMode = PHImageRequestOptionsResizeModeFast;
        reqOptions.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic; // get quick preview then full
        reqOptions.synchronous = NO;

        // Use caching manager for better performance
        PHCachingImageManager *mgr = self.cachingImageManager ?: [PHCachingImageManager new];

        // For each asset request, capture indexPath and position so we can verify reuse
        for (NSInteger i = startIndex; i < fetchResult.count; i++) {
            NSUInteger pos = (NSUInteger)(i - startIndex); // 0,1,2
            PHAsset *asset = fetchResult[i];
            NSIndexPath *capturedIndexPath = indexPath;

            // Request image (asynchronously)
            [mgr requestImageForAsset:asset
                            targetSize:targetPixelSize
                           contentMode:PHImageContentModeAspectFill
                               options:reqOptions
                         resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {

                // Always update UI on main thread
                dispatch_async(dispatch_get_main_queue(),
 ^{
                    // Make sure the cell is still visible and not reused for another row
                    QBAlbumCell *visibleCell = (QBAlbumCell *)[tableView cellForRowAtIndexPath:capturedIndexPath];
                    if (!visibleCell) {
                        // cell not visible -> nothing to update
                        return;
                    }
                    if (visibleCell.tag != capturedIndexPath.row) {
                        // reused for a different row
                        return;
                    }

                    UIImage *img = result ?: placeholder;
                    switch (pos) {
                        case 0: {
                            visibleCell.imageView1.image = img; visibleCell.imageView1
                            .hidden = NO; } break;
                        case 1:{ visibleCell.imageView2.image = img; visibleCell.imageView2
                            .hidden = NO; }break;
                        case 2:{ visibleCell.imageView3.image = img; visibleCell.imageView3
                            .hidden = NO; }break;
                        default: break;
                    }
                });
            }];
        }

       
    }

    // Title and count
    cell.titleLabel.text = assetCollection.localizedTitle ?: @"";
    cell.countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)fetchResult.count];

    if(indexPath.row == self.assetCollections.count-1)
        cell.containerSep.hidden = YES;
    else
        cell.containerSep.hidden = NO;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    // Create assets controller
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"QBImagePicker" bundle:self.imagePickerController.assetBundle];
    QBAssetsViewController *vc = [sb instantiateViewControllerWithIdentifier:@"QBAssetsViewController"];

    vc.imagePickerController = self.imagePickerController;
    vc.assetCollection = self.assetCollections[indexPath.row];

    [self.navigationController pushViewController:vc animated:YES];
 
}

-(CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 120.0;

}
-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 120.0;
}

// Safe placeholder generator (uses UIGraphicsImageRenderer)
- (UIImage *)placeholderImageWithSize:(CGSize)size {
    // Guard - avoid zero-size contexts
    if (CGSizeEqualToSize(size, CGSizeZero) || size.width <= 0 || size.height <= 0) {
        // choose a sensible fallback (thumbnail size)
        size = CGSizeMake(44.0, 44.0);
    }

    // Ensure integer pixel sizes for crisp rendering
    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize pixelSize = CGSizeMake(ceil(size.width * scale) / scale, ceil(size.height * scale) / scale);

    if (@available(iOS 10.0, *)) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = scale;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:pixelSize format:format];

        UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
            CGRect r = CGRectMake(0, 0, pixelSize.width, pixelSize.height);

            // background
            [[UIColor colorWithWhite:0.92 alpha:1.0] setFill];
            UIRectFill(r);

            // a simple center chevron or plus icon — draw a faint cross
            CGContextRef cg = ctx.CGContext;
            CGContextSetStrokeColorWithColor(cg, [UIColor colorWithWhite:0.8 alpha:1.0].CGColor);
            CGContextSetLineWidth(cg, 2.0);

            CGFloat inset = MIN(pixelSize.width, pixelSize.height) * 0.2;
            CGContextMoveToPoint(cg, inset, inset);
            CGContextAddLineToPoint(cg, pixelSize.width - inset, pixelSize.height - inset);
            CGContextMoveToPoint(cg, pixelSize.width - inset, inset);
            CGContextAddLineToPoint(cg, inset, pixelSize.height - inset);
            CGContextStrokePath(cg);
        }];

        return img;
    } else {
        // Fallback for older iOS
        UIGraphicsBeginImageContextWithOptions(pixelSize, YES, scale);
        CGRect r = CGRectMake(0, 0, pixelSize.width, pixelSize.height);
        [[UIColor colorWithWhite:0.92 alpha:1.0] setFill];
        UIRectFill(r);

        CGContextRef cg = UIGraphicsGetCurrentContext();
        CGContextSetStrokeColorWithColor(cg, [UIColor colorWithWhite:0.8 alpha:1.0].CGColor);
        CGContextSetLineWidth(cg, 2.0);

        CGFloat inset = MIN(pixelSize.width, pixelSize.height) * 0.2;
        CGContextMoveToPoint(cg, inset, inset);
        CGContextAddLineToPoint(cg, pixelSize.width - inset, pixelSize.height - inset);
        CGContextMoveToPoint(cg, pixelSize.width - inset, inset);
        CGContextAddLineToPoint(cg, inset, pixelSize.height - inset);
        CGContextStrokePath(cg);

        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return img;
    }
}


#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.fetchResults) return;
        
        // Update fetch results
        NSMutableArray *fetchResults = [self.fetchResults mutableCopy];
        if (!fetchResults) return;
        
        [self.fetchResults enumerateObjectsUsingBlock:^(PHFetchResult *fetchResult, NSUInteger index, BOOL *stop) {
            PHFetchResultChangeDetails *changeDetails = [changeInstance changeDetailsForFetchResult:fetchResult];
            
            if (changeDetails) {
                PHFetchResult *afterChanges = changeDetails.fetchResultAfterChanges;
                if (afterChanges && index < fetchResults.count) {
                    [fetchResults replaceObjectAtIndex:index withObject:afterChanges];
                }
            }
        }];
        
        if (![self.fetchResults isEqualToArray:fetchResults]) {
            self.fetchResults = fetchResults;
            
            // Reload albums
            [self updateAssetCollections];
            [self.tableView reloadData];
        }
    });
}


-(void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
   // [Styling addLiquidGlassBorderToView:(UIBarButtonItem *)self.toolbarItems[1]]
}
@end
