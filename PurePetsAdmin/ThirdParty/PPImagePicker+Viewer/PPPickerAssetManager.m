


// PPPickerAssetManager.m

#import "PPPickerAssetManager.h"

@interface PPPickerAssetManager ()
@property (nonatomic, strong) PHImageRequestOptions *defaultRequestOptions;
@end

@implementation PPPickerAssetManager

+ (instancetype)sharedManager {
    static PPPickerAssetManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PPPickerAssetManager alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (!self) return nil;
    
    _selectedImages = [NSMutableArray array];
    _existingAssetIDs = [NSMutableArray array];
    _maxImageCount = 8; // default
     _assetArray = [NSMutableOrderedSet orderedSet];
    _defaultRequestOptions = [[PHImageRequestOptions alloc] init];
    _defaultRequestOptions.networkAccessAllowed = YES;
    _defaultRequestOptions.resizeMode = PHImageRequestOptionsResizeModeFast;
    _defaultRequestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    _defaultRequestOptions.synchronous = NO;

    return self;
}

- (instancetype)init {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"Use +[PPPickerAssetManager sharedManager]"
                                 userInfo:nil];
}

- (void)pp_ensureMutableState
{
    if (![self.selectedImages isKindOfClass:NSMutableArray.class]) {
        NSArray *snapshot =
            [self.selectedImages isKindOfClass:NSArray.class] ? (NSArray *)self.selectedImages : @[];
        self.selectedImages = [snapshot mutableCopy];
    }
    if (!self.selectedImages) {
        self.selectedImages = [NSMutableArray array];
    }

    if (![self.existingAssetIDs isKindOfClass:NSMutableArray.class]) {
        NSArray *snapshot =
            [self.existingAssetIDs isKindOfClass:NSArray.class] ? (NSArray *)self.existingAssetIDs : @[];
        self.existingAssetIDs = [snapshot mutableCopy];
    }
    if (!self.existingAssetIDs) {
        self.existingAssetIDs = [NSMutableArray array];
    }

    if (![self.assetArray isKindOfClass:NSMutableOrderedSet.class]) {
        NSOrderedSet *ordered =
            [self.assetArray isKindOfClass:NSOrderedSet.class] ? (NSOrderedSet *)self.assetArray : [NSOrderedSet orderedSet];
        self.assetArray = [ordered mutableCopy];
    }
    if (!self.assetArray) {
        self.assetArray = [NSMutableOrderedSet orderedSet];
    }
}

- (void)addAssetsFromPicker:(NSArray<PHAsset *> *)assets completion:(void(^)(BOOL didChange))completion {
    [self pp_ensureMutableState];

    if (!assets || assets.count == 0) {
        if (completion) completion(NO);
        return;
    }

    // Ensure assetArray exists
    [self pp_ensureMutableState];

    // Detect full-selection (picker returned the full set)
    BOOL looksLikeFullSelection = NO;
    BOOL hasNonPHAssetEntries = NO;
    if (self.assetArray.count > 0) {
        NSSet *incomingIds = [NSSet setWithArray:[assets valueForKey:@"localIdentifier"]];
        NSMutableSet *existingIds = [NSMutableSet set];
        for (id a in self.assetArray) {
            if ([a isKindOfClass:[PHAsset class]] && ((PHAsset *)a).localIdentifier) {
                [existingIds addObject:((PHAsset *)a).localIdentifier];
            } else {
                hasNonPHAssetEntries = YES;
            }
        }
        // If array contains camera/manual images, do append mode to preserve them.
        if (!hasNonPHAssetEntries && [existingIds isSubsetOfSet:incomingIds]) {
            looksLikeFullSelection = YES;
        }
    }

    PHImageManager *mgr = [PHImageManager defaultManager];
    CGSize targetSize = [self _targetSizeForScreenScale];

    // -------- Full selection: replace assetArray with picker's order --------
    if (looksLikeFullSelection) {
        // Replace ordered set with picker's order (preserves order and uniqueness)
        // Filter nil values — NSMutableOrderedSet crashes on nil insertion
        NSMutableArray *safeAssets = [NSMutableArray arrayWithCapacity:assets.count];
        for (id a in assets) { if (a) [safeAssets addObject:a]; }
        self.assetArray = [NSMutableOrderedSet orderedSetWithArray:safeAssets];

        // Prepare selectedImages placeholders (NSNull) so indexes match
        [self.selectedImages removeAllObjects];
        for (NSUInteger i = 0; i < self.assetArray.count; i++) {
            [self.selectedImages addObject:[UIImage new]];
        }

        dispatch_group_t group = dispatch_group_create();

        // Iterate by index so we can put images at the correct index
        NSArray<PHAsset *> *ordered = self.assetArray.array;
        for (NSUInteger idx = 0; idx < ordered.count; idx++) {
            PHAsset *asset = ordered[idx];
            dispatch_group_enter(group);

            [mgr requestImageForAsset:asset
                           targetSize:targetSize
                          contentMode:PHImageContentModeAspectFill
                              options:self.defaultRequestOptions
                        resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
                UIImage *img = result ?: [UIImage new];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self pp_ensureMutableState];
                    if (idx < self.selectedImages.count) {
                        [self.selectedImages replaceObjectAtIndex:idx withObject:img];
                    } else {
                        // fallback safety
                        [self.selectedImages addObject:img];
                    }
                    dispatch_group_leave(group);
                });
            }];
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            // Clean guard: remove any NSNull leftover (shouldn't be necessary)
            NSMutableArray *clean = [NSMutableArray array];
            [self pp_ensureMutableState];
            for (id o in self.selectedImages) {
                if ([o isKindOfClass:[UIImage class]]) [clean addObject:o];
            }
            self.selectedImages = [clean mutableCopy];

            if (completion) completion(self.selectedImages.count > 0);
        });

        return;
    }

    // -------- Append-only: picker returned only new assets --------
    // Fast lookup of existing identifiers (PHAsset entries only).
    NSMutableSet *existingIdsMutable = [NSMutableSet set];
    for (id existingObj in self.assetArray.array) {
        if ([existingObj isKindOfClass:[PHAsset class]]) {
            NSString *existingID = ((PHAsset *)existingObj).localIdentifier;
            if (existingID.length) [existingIdsMutable addObject:existingID];
        }
    }
    NSSet *existingIdsSet = [existingIdsMutable copy];
    NSMutableArray<PHAsset *> *toAdd = [NSMutableArray array];

    for (PHAsset *asset in assets) {
        if (!asset) continue;
        if ([existingIdsSet containsObject:asset.localIdentifier]) continue; // skip duplicates
        [toAdd addObject:asset];
    }

    if (toAdd.count == 0) {
        if (completion) completion(NO);
        return;
    }

    // Respect max count
    NSInteger availableSlots = self.maxImageCount - self.selectedImages.count;
    if (availableSlots <= 0) {
        if (completion) completion(NO);
        return;
    }
    if (toAdd.count > availableSlots) {
        toAdd = [[toAdd subarrayWithRange:NSMakeRange(0, availableSlots)] mutableCopy];
    }

    // Append to ordered set (keeps uniqueness). Using addObjectsFromArray adds each in order.
    [self.assetArray addObjectsFromArray:toAdd];

    // Insert placeholders into selectedImages so indexes remain aligned
    NSUInteger startIndex = self.selectedImages.count;
    for (NSUInteger i = 0; i < toAdd.count; i++) {
        [self.selectedImages addObject:[UIImage new]];
    }

    // Fetch thumbnails and place them at correct indices
    dispatch_group_t fetchGroup = dispatch_group_create();
    for (NSUInteger i = 0; i < toAdd.count; i++) {
        PHAsset *asset = toAdd[i];
        NSUInteger targetIndex = startIndex + i;

        dispatch_group_enter(fetchGroup);
        [mgr requestImageForAsset:asset
                       targetSize:targetSize
                      contentMode:PHImageContentModeAspectFill
                          options:self.defaultRequestOptions
                    resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            UIImage *img = result ?: [UIImage new];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self pp_ensureMutableState];
                if (targetIndex < self.selectedImages.count) {
                    [self.selectedImages replaceObjectAtIndex:targetIndex withObject:img];
                } else {
                    // fallback safety
                    [self.selectedImages addObject:img];
                }
                dispatch_group_leave(fetchGroup);
            });
        }];
    }

    dispatch_group_notify(fetchGroup, dispatch_get_main_queue(), ^{
        if (completion) completion(YES);
    });
}



#pragma mark - Fetch images helpers

- (CGSize)_targetSizeForScreenScale {
    CGFloat scale = UIScreen.mainScreen.scale;
    // Provide a reasonably large target size (you can customize)
    CGSize screen = UIScreen.mainScreen.bounds.size;
    return CGSizeMake(screen.width * scale, screen.width * scale); // square thumbnails using screen width
}

- (void)fetchImagesFromAssets:(NSArray<PHAsset *> *)assets targetSize:(CGSize)targetSize completion:(PPImageFetchCompletion)completion {
    if (!assets || assets.count == 0) {
        if (completion) completion(@[]);
        return;
    }

    PHImageManager *mgr = [PHImageManager defaultManager];
    NSMutableArray<UIImage *> *resultImages = [NSMutableArray arrayWithCapacity:assets.count];
    dispatch_group_t group = dispatch_group_create();

    for (PHAsset *asset in assets) {
        dispatch_group_enter(group);
        [mgr requestImageForAsset:asset
                       targetSize:targetSize
                      contentMode:PHImageContentModeAspectFill
                          options:self.defaultRequestOptions
                    resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            UIImage *img = result ?: [UIImage new];
            // resultHandler may fire on arbitrary threads — synchronize
            @synchronized (resultImages) {
                [resultImages addObject:img];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSArray *snapshot;
        @synchronized (resultImages) {
            snapshot = [resultImages copy];
        }
        if (completion) completion(snapshot);
    });
}

- (void)fetchImageFromAsset:(PHAsset *)asset targetSize:(CGSize)targetSize completion:(PPImageFetchSingleCompletion)completion {
    if (!asset) {
        if (completion) completion(nil);
        return;
    }
    PHImageManager *mgr = [PHImageManager defaultManager];
    [mgr requestImageForAsset:asset
                   targetSize:targetSize
                  contentMode:PHImageContentModeAspectFill
                      options:self.defaultRequestOptions
                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result);
        });
    }];
}

#pragma mark - Add UIImage directly

- (BOOL)addImage:(UIImage *)image {
    [self pp_ensureMutableState];

    if (!image) return NO;
    if (self.selectedImages.count >= self.maxImageCount) return NO;

    [self.selectedImages addObject:image];
    id uuid =  UUIDJoin(@"HX");
    // Camera images have no PHAsset — keep index alignment with NSNull
    [self.assetArray addObject:uuid];
    NSLog(@"Added uuid %@",uuid);
    return YES;
}

- (void)removeImageAtIndex:(NSInteger)index {
    [self pp_ensureMutableState];
    if (!(0 <= index && index < self.selectedImages.count)) return;

    // 1) Remove UIImage
    [self.selectedImages removeObjectAtIndex:index];

    // 2) Remove PHAsset from assetArray (ordered set) if present
    if (index < self.assetArray.count) {
        // -objectAtIndex: returns id, -removeObjectAtIndex: removes by index
        id obj = [self.assetArray objectAtIndex:index];
        if (obj) {
            [self.assetArray removeObjectAtIndex:index];
        }
    }
}



- (void)removeAssetAtIndex:(NSInteger)index {
    [self pp_ensureMutableState];
    if (!(0 <= index && index < self.assetArray.count)) return;
    [self.assetArray removeObjectAtIndex:index];

    if (index < self.selectedImages.count) {
        [self.selectedImages removeObjectAtIndex:index];
    }
}

- (void)replaceImageAtIndex:(NSInteger)index withImage:(UIImage *)image asset:(PHAsset *)asset {
    [self pp_ensureMutableState];
    if (!(0 <= index && index < self.selectedImages.count)) return;
    if (!image) return;

    [self.selectedImages replaceObjectAtIndex:index withObject:image];
    

    if (asset) {
        // If existingAsset contains asset already at another index, remove duplicate first
        if ([self.assetArray containsObject:asset]) {
            NSUInteger oldIndex = [self.assetArray indexOfObject:asset];
            if (oldIndex != NSNotFound) {
                [self.assetArray removeObjectAtIndex:oldIndex];
                // If removed an item before the replacement index, adjust if needed
            }
        }

        // Ensure ordered set maintains 1:1 positional mapping — try to insert at same index
        if (index <= self.assetArray.count) {
            [self.assetArray insertObject:asset atIndex:index];
        } else {
            [self.assetArray addObject:asset];
        }
    }
}

- (void)moveImageFromIndex:(NSInteger)fromIndex toIndex:(NSInteger)toIndex {
    [self pp_ensureMutableState];
    if (!(0 <= fromIndex && fromIndex < self.selectedImages.count)) return;
    if (!(0 <= toIndex && toIndex < self.selectedImages.count)) return;
    if (fromIndex == toIndex) return;

    // Move image in selectedImages
    UIImage *img = self.selectedImages[fromIndex];
    if (!img) return;
    [self.selectedImages removeObjectAtIndex:fromIndex];
    NSInteger safeToIndex = MIN(MAX(toIndex, 0), self.selectedImages.count);
    [self.selectedImages insertObject:img atIndex:safeToIndex];

    // Move asset in ordered set (work with .array or perform remove+insert)
    if (fromIndex < self.assetArray.count) {
        id assetObj = [self.assetArray objectAtIndex:fromIndex];
        if (!assetObj) return;
        // remove then insert at new index
        [self.assetArray removeObjectAtIndex:fromIndex];
        NSInteger safeAssetToIndex = MIN(MAX(toIndex, 0), self.assetArray.count);
        if (safeAssetToIndex <= self.assetArray.count) {
            [self.assetArray insertObject:assetObj atIndex:safeAssetToIndex];
        } else {
            [self.assetArray addObject:assetObj];
        }
    }
}



#pragma mark - Preselection helpers

- (NSArray<PHAsset *> *)preselectedAssetsForPicker {
    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    for (id obj in self.assetArray.array) {
        if ([obj isKindOfClass:[PHAsset class]]) {
            [assets addObject:(PHAsset *)obj];
        }
    }
    return [assets copy];
}

- (NSArray<NSString *> *)preselectedAssetLocalIdentifiers {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (id obj in self.assetArray) {
        if ([obj isKindOfClass:[PHAsset class]]) {
            PHAsset *asset = (PHAsset *)obj;
            if (asset.localIdentifier) [ids addObject:asset.localIdentifier];
        }
    }
    return [ids copy];
}



#pragma mark - Clear

- (void)clearAll {
    [self pp_ensureMutableState];
    [self.selectedImages removeAllObjects];
    [self.assetArray removeAllObjects];
    [self.existingAssetIDs removeAllObjects];
}

@end
