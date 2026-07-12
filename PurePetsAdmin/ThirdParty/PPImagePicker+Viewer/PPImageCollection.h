//
//  PPImageCollection.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 03/12/2025.
//


#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import "PPPickerAssetManager.h"
#import "PPImageCollection.h"
#import "QBImagePickerController.h"

// PPImageCollection – imported via PrefixHeader.pch
@class PPEditorBridge;


NS_ASSUME_NONNULL_BEGIN

@class PPImageCollection;

@protocol PPImageCollectionDelegate <NSObject>
@optional
- (void)imageCollection:(PPImageCollection *)collection didUpdateImages:(NSArray<UIImage *> *)images;
- (void)imageCollection:(PPImageCollection *)collection didSelectImage:(UIImage *)selectedImage  AtIndex:(NSInteger)index;
- (void)imageCollectionDidRequestAddImage:(PPImageCollection *)collection;
@end

@interface PPImageCollection : UIView <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, QBImagePickerControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, weak) id<PPImageCollectionDelegate> delegate;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) NSMutableArray<UIImage *> *mediaOutputArray;
@property (nonatomic, strong) PPPickerAssetManager *imageManager;
@property (nonatomic, strong) PPEditorBridge *editorBridge;

// Configuration
@property (nonatomic, assign) NSInteger maxImageCount;
@property (nonatomic, assign) BOOL useArabic;
@property (nonatomic, assign) BOOL allowsEditing;
@property (nonatomic, assign) BOOL allowsReordering;
@property (nonatomic, strong) NSString *titleText;

// State
@property (nonatomic, assign) NSInteger selectedForEdit;
@property (nonatomic, strong) NSRecursiveLock *arrayLock;

// Initialization
- (instancetype)initWithFrame:(CGRect)frame maxImageCount:(NSInteger)maxCount useArabic:(BOOL)useArabic;
- (void)presentEditorForImageAtIndex:(NSInteger)index fromViewController:(UIViewController *)viewController ;
- (void)presentPickerFromViewController:(UIViewController *)viewController;
// Image Management
- (void)addImage:(UIImage *)image;
- (void)addImages:(NSArray<UIImage *> *)images;
- (void)removeImageAtIndex:(NSInteger)index;
- (void)replaceImageAtIndex:(NSInteger)index withImage:(UIImage *)image;
- (void)clearAllImages;
- (NSArray<UIImage *> *)allImages;
- (NSInteger)imageCount;

// UI Management
- (void)reloadCollectionView;
- (void)setTitle:(NSString *)title icon:(UIImage * _Nullable)icon;

// Preloading
- (void)preloadImagesFromURLs:(NSArray<NSString *> *)urls completion:(void(^)(void))completion;

/// Present a Gallery / Camera action sheet (useful for headless picker flows like avatar selection).
- (void)showActionSheetForAddingImage;

@end

NS_ASSUME_NONNULL_END
