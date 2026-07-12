// PPPickerAssetManager.h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^PPImageFetchCompletion)(NSArray<UIImage *> *images);
typedef void(^PPImageFetchSingleCompletion)(UIImage * _Nullable image);

@interface PPPickerAssetManager : NSObject

@property (nonatomic, strong) NSMutableArray<UIImage *> *selectedImages; // UIImages for upload/display
@property (nonatomic, strong) NSMutableArray<NSString *> *existingAssetIDs; // PHAssets for QB preselection (keeps order & uniqueness)
@property (nonatomic, assign) NSInteger maxImageCount;
@property (nonatomic, strong) NSMutableOrderedSet *assetArray; // elements: PHAsset * or [NSNull null]

+ (instancetype)sharedManager;

// Add assets (PHAsset array coming from QB delegate)
- (void)addAssetsFromPicker:(NSArray<PHAsset *> *)assets
                 completion:(void(^)(BOOL didChange))completion;

// Convert PHAsset(s) -> UIImage(s) asynchronously (calls completion on main thread)
- (void)fetchImagesFromAssets:(NSArray<PHAsset *> *)assets
                    targetSize:(CGSize)targetSize
                    completion:(PPImageFetchCompletion)completion;

- (void)fetchImageFromAsset:(PHAsset *)asset
                 targetSize:(CGSize)targetSize
                 completion:(PPImageFetchSingleCompletion)completion;

// Directly add UIImage (e.g. camera or already available)
- (BOOL)addImage:(UIImage *)image; // returns YES if added, NO if rejected (duplicate / over limit)

// Delete / Replace / Move
- (void)removeImageAtIndex:(NSInteger)index;
- (void)removeAssetAtIndex:(NSInteger)index;
- (void)replaceImageAtIndex:(NSInteger)index withImage:(UIImage *)image asset:(nullable PHAsset *)asset;
- (void)moveImageFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex;

// Helpers for QBImagePicker preselection — returns an NSArray of PHAsset or asset identifiers that QB can use
- (NSArray<PHAsset *> *)preselectedAssetsForPicker;
- (NSArray<NSString *> *)preselectedAssetLocalIdentifiers;

// Clear all
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
