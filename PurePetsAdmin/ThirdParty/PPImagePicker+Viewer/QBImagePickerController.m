//
//  QBImagePickerController.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
//

#import "QBImagePickerController.h"
#import <Photos/Photos.h>

// ViewControllers
#import "QBAlbumsViewController.h"

@interface QBImagePickerController ()

@property (nonatomic,
           strong) PPNavigationController *albumsNavigationController;

@property (nonatomic, strong) NSBundle *assetBundle;

@end

@implementation QBImagePickerController

@synthesize selectedAssets = _selectedAssets;

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        // Set default values
        self.assetCollectionSubtypes = @[
            // Main Smart Albums
            @(PHAssetCollectionSubtypeSmartAlbumUserLibrary),       // Camera Roll / All Photos
            @(PHAssetCollectionSubtypeSmartAlbumFavorites),
            @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded),
            @(PHAssetCollectionSubtypeSmartAlbumVideos),
            @(PHAssetCollectionSubtypeSmartAlbumSelfPortraits),
            @(PHAssetCollectionSubtypeSmartAlbumTimelapses),
            @(PHAssetCollectionSubtypeSmartAlbumBursts),
            @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
            @(PHAssetCollectionSubtypeSmartAlbumLivePhotos),
            @(PHAssetCollectionSubtypeSmartAlbumDepthEffect),
            @(PHAssetCollectionSubtypeSmartAlbumLongExposures),
            @(PHAssetCollectionSubtypeSmartAlbumAnimated),
            
            // Shared & My Photo Stream (only if still enabled)
            @(PHAssetCollectionSubtypeAlbumMyPhotoStream),
            @(PHAssetCollectionSubtypeAlbumCloudShared),

            // Regular albums
            @(PHAssetCollectionSubtypeAlbumRegular),
            
            // Synced / Imported (rare but harmless)
            @(PHAssetCollectionSubtypeAlbumImported),
            @(PHAssetCollectionSubtypeAlbumSyncedEvent),
            @(PHAssetCollectionSubtypeAlbumSyncedFaces),
            @(PHAssetCollectionSubtypeAlbumSyncedAlbum)
        ];

        self.minimumNumberOfSelection = 1;
        self.numberOfColumnsInPortrait = 5;
        self.numberOfColumnsInLandscape = 8;
        
        if (!_selectedAssets) {
            _selectedAssets = [NSMutableOrderedSet orderedSet];
        }
        
        // Get asset bundle
        self.assetBundle = [NSBundle bundleForClass:[self class]];
        NSString *bundlePath = [self.assetBundle pathForResource:@"QBImagePicker" ofType:@"bundle"];
        if (bundlePath) {
            self.assetBundle = [NSBundle bundleWithPath:bundlePath];
        }
        
        [self setUpAlbumsViewController];
    }
    
    return self;
}

- (NSMutableOrderedSet *)selectedAssets
{
    if (!_selectedAssets) {
        _selectedAssets = [NSMutableOrderedSet orderedSet];
    }
    return _selectedAssets;
}

- (void)setSelectedAssets:(NSMutableOrderedSet *)selectedAssets
{
    id incoming = selectedAssets;
    if (!incoming) {
        _selectedAssets = [NSMutableOrderedSet orderedSet];
        return;
    }

    if ([incoming isKindOfClass:[NSMutableOrderedSet class]]) {
        _selectedAssets = (NSMutableOrderedSet *)incoming;
        return;
    }

    if ([incoming isKindOfClass:[NSOrderedSet class]]) {
        _selectedAssets = [(NSOrderedSet *)incoming mutableCopy];
        return;
    }

    if ([incoming isKindOfClass:[NSArray class]]) {
        _selectedAssets = [NSMutableOrderedSet orderedSetWithArray:(NSArray *)incoming];
        return;
    }

    _selectedAssets = [NSMutableOrderedSet orderedSetWithObject:incoming];
}

- (void)setUpAlbumsViewController
{
    // Add QBAlbumsViewController as a child
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"QBImagePicker" bundle:self.assetBundle];
    PPNavigationController *navigationController = [storyboard instantiateViewControllerWithIdentifier:@"QBAlbumsNavigationController"];

    // Set imagePickerController BEFORE accessing .view (which triggers viewDidLoad)
    QBAlbumsViewController *albumsVC = (QBAlbumsViewController *)navigationController.topViewController;
    albumsVC.imagePickerController = self;

    [self addChildViewController:navigationController];
    navigationController.view.backgroundColor = AppClearClr;
    navigationController.view.frame = self.view.bounds;
    [self.view addSubview:navigationController.view];
    
    [navigationController didMoveToParentViewController:self];
    
    self.albumsNavigationController = navigationController;
}

@end
