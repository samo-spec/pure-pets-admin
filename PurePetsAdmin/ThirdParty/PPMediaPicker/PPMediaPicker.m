//
//  PPMediaPicker.m
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import "PPMediaPicker.h"
#import "QBImagePickerController.h"
#import "PPMediaReviewController.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface PPMediaPicker () <QBImagePickerControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PPMediaReviewControllerDelegate>

@property (nonatomic, weak) UIViewController *presentingViewController;

@end

@implementation PPMediaPicker

- (instancetype)initWithPresentingViewController:(UIViewController *)presentingViewController {
    self = [super init];
    if (self) {
        _presentingViewController = presentingViewController;
        _selectedMedia = [NSMutableArray array];
        _maxCount = 10;
    }
    return self;
}

- (void)openLibrary {
    QBImagePickerController *imagePickerController = [QBImagePickerController new];
    imagePickerController.delegate = self;
    imagePickerController.allowsMultipleSelection = YES;
    imagePickerController.maximumNumberOfSelection = self.maxCount;
    imagePickerController.mediaType = QBImagePickerMediaTypeAny;
    
    // Pre-selection logic
    NSMutableOrderedSet *selectedAssets = [NSMutableOrderedSet orderedSet];
    for (PPMediaItem *item in self.selectedMedia) {
        if (item.asset) {
            [selectedAssets addObject:item.asset];
        }
    }
    imagePickerController.selectedAssets = selectedAssets;
    
    [self.presentingViewController presentViewController:imagePickerController animated:YES completion:nil];
}

- (void)openCamera {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        return;
    }
    
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.mediaTypes = @[(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie];
    
    [self.presentingViewController presentViewController:picker animated:YES completion:nil];
}

- (void)showReviewScreen {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    PPMediaReviewController *reviewVC = [[PPMediaReviewController alloc] initWithCollectionViewLayout:layout];
    reviewVC.mediaItems = self.selectedMedia;
    reviewVC.delegate = self;
    
    if (self.presentingViewController.navigationController) {
        [self.presentingViewController.navigationController pushViewController:reviewVC animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:reviewVC];
        [self.presentingViewController presentViewController:nav animated:YES completion:nil];
    }
}

#pragma mark - QBImagePickerControllerDelegate

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingAssets:(NSArray *)assets {
    [imagePickerController dismissViewControllerAnimated:YES completion:^{
        // Map PHAsset to PPMediaItem, preserving order from 'assets'
        NSMutableArray *newMedia = [NSMutableArray array];
        for (PHAsset *asset in assets) {
            // Find existing item or create new
            PPMediaItem *existingItem = nil;
            for (PPMediaItem *item in self.selectedMedia) {
                if ([item.asset.localIdentifier isEqualToString:asset.localIdentifier]) {
                    existingItem = item;
                    break;
                }
            }
            if (existingItem) {
                [newMedia addObject:existingItem];
            } else {
                [newMedia addObject:[PPMediaItem itemWithAsset:asset]];
            }
        }
        
        // Items from camera that were already in selectedMedia should be preserved if we want to support mixing?
        // Usually, if we reopen the picker, it returns the full set of library assets.
        // For simplicity, let's keep camera items at the end or handle them separately.
        for (PPMediaItem *item in self.selectedMedia) {
            if (!item.asset) { // Item from camera
                [newMedia addObject:item];
            }
        }
        
        self.selectedMedia = newMedia;
        [self showReviewScreen];
    }];
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController {
    [imagePickerController dismissViewControllerAnimated:YES completion:^{
        if ([self.delegate respondsToSelector:@selector(mediaPickerDidCancel:)]) {
            [self.delegate mediaPickerDidCancel:self];
        }
    }];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        NSString *mediaType = info[UIImagePickerControllerMediaType];
        if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
            UIImage *image = info[UIImagePickerControllerOriginalImage];
            [self.selectedMedia addObject:[PPMediaItem itemWithImage:image]];
        } else if ([mediaType isEqualToString:(NSString *)kUTTypeMovie]) {
            NSURL *videoURL = info[UIImagePickerControllerMediaURL];
            [self.selectedMedia addObject:[PPMediaItem itemWithVideoURL:videoURL]];
        }
        [self showReviewScreen];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - PPMediaReviewControllerDelegate

- (void)mediaReviewController:(PPMediaReviewController *)controller didFinishWithMedia:(NSArray<PPMediaItem *> *)media {
    self.selectedMedia = [media mutableCopy];
    [controller dismissViewControllerAnimated:YES completion:^{
        if ([self.delegate respondsToSelector:@selector(mediaPicker:didFinishWithMedia:)]) {
            [self.delegate mediaPicker:self didFinishWithMedia:self.selectedMedia];
        }
    }];
}

- (void)mediaReviewControllerDidTapAddMore:(PPMediaReviewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:^{
        [self openLibrary];
    }];
}

@end
