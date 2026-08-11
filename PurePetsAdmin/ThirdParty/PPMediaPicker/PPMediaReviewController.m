//
//  PPMediaReviewController.m
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import "PPMediaReviewController.h"
#import "PPMediaReviewCell.h"
#import "CLImageEditor.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface PPMediaReviewController () <UICollectionViewDragDelegate, UICollectionViewDropDelegate, CLImageEditorDelegate, UIVideoEditorControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) NSIndexPath *editingIndexPath;

@end

@implementation PPMediaReviewController

static NSString * const reuseIdentifier = @"PPMediaReviewCell";

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Review Media";
    self.collectionView.backgroundColor = [UIColor ppBackground];
    [self.collectionView registerClass:[PPMediaReviewCell class] forCellWithReuseIdentifier:reuseIdentifier];
    
    self.collectionView.dragInteractionEnabled = YES;
    self.collectionView.dragDelegate = self;
    self.collectionView.dropDelegate = self;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(doneTapped)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add" style:UIBarButtonItemStylePlain target:self action:@selector(addTapped)];
}

- (void)doneTapped {
    if ([self.delegate respondsToSelector:@selector(mediaReviewController:didFinishWithMedia:)]) {
        [self.delegate mediaReviewController:self didFinishWithMedia:self.mediaItems];
    }
}

- (void)addTapped {
    if ([self.delegate respondsToSelector:@selector(mediaReviewControllerDidTapAddMore:)]) {
        [self.delegate mediaReviewControllerDidTapAddMore:self];
    }
}

#pragma mark <UICollectionViewDataSource>

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.mediaItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    PPMediaReviewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    PPMediaItem *item = self.mediaItems[indexPath.item];
    [cell configureWithItem:item];
    
    __weak typeof(self) weakSelf = self;
    cell.deleteHandler = ^{
        [weakSelf.mediaItems removeObjectAtIndex:indexPath.item];
        [weakSelf.collectionView deleteItemsAtIndexPaths:@[indexPath]];
        [weakSelf.collectionView reloadData];
    };
    
    cell.editHandler = ^{
        weakSelf.editingIndexPath = indexPath;
        if (item.isVideo) {
            [weakSelf startVideoEditorForItem:item];
        } else {
            [weakSelf startImageEditorForItem:item];
        }
    };
    
    return cell;
}

#pragma mark - Editing

- (void)startImageEditorForItem:(PPMediaItem *)item {
    // We need the full image
    if (item.image) {
        CLImageEditor *editor = [[CLImageEditor alloc] initWithImage:item.image];
        editor.delegate = self;
        [self presentViewController:editor animated:YES completion:nil];
    } else if (item.asset) {
        PHImageRequestOptions *options = [PHImageRequestOptions new];
        options.networkAccessAllowed = YES;
        options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        options.synchronous = YES;
        
        [[PHImageManager defaultManager] requestImageForAsset:item.asset
                                                   targetSize:PHImageManagerMaximumSize
                                                  contentMode:PHImageContentModeAspectFit
                                                      options:options
                                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            if (result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    CLImageEditor *editor = [[CLImageEditor alloc] initWithImage:result];
                    editor.delegate = self;
                    [self presentViewController:editor animated:YES completion:nil];
                });
            }
        }];
    }
}

- (void)startVideoEditorForItem:(PPMediaItem *)item {
    if (item.videoURL) {
        [self presentVideoEditorWithURL:item.videoURL];
    } else if (item.asset) {
        PHVideoRequestOptions *options = [PHImageRequestOptions new];
        options.networkAccessAllowed = YES;
        
        [[PHImageManager defaultManager] requestAVAssetForVideo:item.asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
            if ([asset isKindOfClass:[AVURLAsset class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentVideoEditorWithURL:((AVURLAsset *)asset).URL];
                });
            }
        }];
    }
}

- (void)presentVideoEditorWithURL:(NSURL *)url {
    if ([UIVideoEditorController canEditVideoAtPath:url.path]) {
        UIVideoEditorController *editor = [[UIVideoEditorController alloc] init];
        editor.videoPath = url.path;
        editor.delegate = self;
        [self presentViewController:editor animated:YES completion:nil];
    }
}

#pragma mark - CLImageEditorDelegate

- (void)imageEditor:(CLImageEditor *)editor didFinishEditingWithImage:(UIImage *)image {
    [editor dismissViewControllerAnimated:YES completion:^{
        if (self.editingIndexPath) {
            PPMediaItem *item = self.mediaItems[self.editingIndexPath.item];
            item.image = image;
            item.isEdited = YES;
            [self.collectionView reloadItemsAtIndexPaths:@[self.editingIndexPath]];
        }
    }];
}

#pragma mark - UIVideoEditorControllerDelegate

- (void)videoEditorController:(UIVideoEditorController *)editor didSaveEditedVideoToPath:(NSString *)editedVideoPath {
    [editor dismissViewControllerAnimated:YES completion:^{
        if (self.editingIndexPath) {
            PPMediaItem *item = self.mediaItems[self.editingIndexPath.item];
            item.videoURL = [NSURL fileURLWithPath:editedVideoPath];
            item.isEdited = YES;
            [self.collectionView reloadItemsAtIndexPaths:@[self.editingIndexPath]];
        }
    }];
}

#pragma mark - UICollectionViewDragDelegate

- (NSArray<UIDragItem *> *)collectionView:(UICollectionView *)collectionView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    PPMediaItem *item = self.mediaItems[indexPath.item];
    NSItemProvider *itemProvider = [[NSItemProvider alloc] initWithObject:item.uniqueID];
    UIDragItem *dragItem = [[UIDragItem alloc] initWithItemProvider:itemProvider];
    dragItem.localObject = item;
    return @[dragItem];
}

#pragma mark - UICollectionViewDropDelegate

- (void)collectionView:(UICollectionView *)collectionView performDropWithCoordinator:(id<UICollectionViewDropCoordinator>)coordinator {
    NSIndexPath *destinationIndexPath = coordinator.destinationIndexPath ?: [NSIndexPath indexPathForItem:self.mediaItems.count - 1 inSection:0];
    
    for (id<UICollectionViewDropItem> item in coordinator.items) {
        if (item.sourceIndexPath) {
            [collectionView performBatchUpdates:^{
                PPMediaItem *mediaItem = item.dragItem.localObject;
                [self.mediaItems removeObjectAtIndex:item.sourceIndexPath.item];
                [self.mediaItems insertObject:mediaItem atIndex:destinationIndexPath.item];
                [collectionView deleteItemsAtIndexPaths:@[item.sourceIndexPath]];
                [collectionView insertItemsAtIndexPaths:@[destinationIndexPath]];
            } completion:nil];
            [coordinator dropItem:item.dragItem toItemAtIndexPath:destinationIndexPath];
        }
    }
}

- (UICollectionViewDropProposal *)collectionView:(UICollectionView *)collectionView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(nullable NSIndexPath *)destinationIndexPath {
    return [[UICollectionViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UICollectionViewDropIntentInsertAtDestinationIndexPath];
}

@end
