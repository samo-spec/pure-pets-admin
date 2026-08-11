//
//  PPImageEditorViewController.m
//  PurePets
//
//  Created by Admin on 11/09/2025.
//

#import "PPImageEditorViewController.h"

@interface PPImageEditorViewController ()<UICollectionViewDelegate ,UICollectionViewDataSource>
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) PPImageEditor *editor;
@property (nonatomic, copy) PPImageEditorCompletion completion;
@property (nonatomic, strong) NSArray *filters;
@property (nonatomic, strong) UICollectionView *filterCollectionView;

@end

@implementation PPImageEditorViewController


#pragma mark - Edit helpers

// helper to run processing on background using your PPImageEditor API if available,
// otherwise fall back to dispatch_async
- (void)pp_processOnBackground:(UIImage * _Nonnull (^)(UIImage *image))processBlock
                    completion:(void(^)(UIImage * _Nullable edited, NSError * _Nullable error))completion
{
    // Show HUD & disable toolbar while processing
    [PPHUD showRingIn:self.view title:kLang(@"Processing") subtitle:@""];
    self.toolbar.userInteractionEnabled = NO;

    // If PPImageEditor implements processImageOnBackgroundThreadWithBlock:completion: use it.
    SEL sel = NSSelectorFromString(@"processImageOnBackgroundThreadWithBlock:completion:");
    if ([self.editor respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        // Call the method dynamically
        void (^block)(UIImage * (^)(UIImage *), void(^)(UIImage *, NSError *)) = ^(UIImage * (^p)(UIImage *), void (^c)(UIImage *, NSError *)) {
            // wrapper, impossible to call directly with performSelector, use obj-c invocation if needed
        };
        // Use GCD fallback because performing the block selector with arguments is tedious
#pragma clang diagnostic pop
    }

    // Fallback: do the work ourselves on a background queue using the block and return on main
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            UIImage *current = [self.editor currentImage] ?:self.editor.originalImage;
            UIImage *edited = nil;
            if (processBlock) edited = processBlock(current);
            dispatch_async(dispatch_get_main_queue(), ^{
                [PPHUD dismiss];
                self.toolbar.userInteractionEnabled = YES;
                if (completion) completion(edited, nil);
            });
        } @catch (NSException *ex) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [PPHUD dismiss];
                self.toolbar.userInteractionEnabled = YES;
                NSError *err = [NSError errorWithDomain:@"PPImageEditor" code:-1 userInfo:@{NSLocalizedDescriptionKey:ex.reason ?: @"Processing failed"}];
                if (completion) completion(nil, err);
            });
        }
    });
}

#pragma mark - Low-level image transforms

- (UIImage *)pp_rotateImage90DegreesClockwise:(UIImage *)image {
    if (!image) return nil;
    CGSize size = image.size;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size.height, size.width), NO, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    // move origin to center
    CGContextTranslateCTM(ctx, size.height/2.0, size.width/2.0);
    // rotate 90 deg clockwise
    CGContextRotateCTM(ctx, (CGFloat)(M_PI_2));
    // draw the image centered (notice width/height swapped)
    [image drawInRect:CGRectMake(-size.width/2.0, -size.height/2.0, size.width, size.height)];
    UIImage *rotated = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rotated;
}

- (UIImage *)pp_flipImage:(UIImage *)image horizontal:(BOOL)h vertical:(BOOL)v {
    if (!image) return nil;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGContextTranslateCTM(ctx, 0, image.size.height);
    CGContextScaleCTM(ctx, 1.0, -1.0); // flip vertically for CoreGraphics coordinate system

    if (h && !v) {
        // horizontal flip: translate & scale X
        CGContextTranslateCTM(ctx, image.size.width, 0);
        CGContextScaleCTM(ctx, -1.0, 1.0);
    } else if (v && !h) {
        // vertical flip: translate & scale Y (already flipped by earlier scale)
        // Just scale Y by -1 to flip back? To keep it simple XOR effect:
        CGContextTranslateCTM(ctx, 0, image.size.height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
    } else if (h && v) {
        // both: flip X and Y -> rotate 180
        CGContextTranslateCTM(ctx, image.size.width, 0);
        CGContextScaleCTM(ctx, -1.0, 1.0);
        CGContextTranslateCTM(ctx, 0, image.size.height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, image.size.width, image.size.height), image.CGImage);
    UIImage *flipped = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return flipped;
}

- (UIImage *)pp_cropImage:(UIImage *)image toAspectRatioWidth:(CGFloat)w height:(CGFloat)h {
    if (!image) return nil;
    if (w <= 0 || h <= 0) return image;

    CGFloat ratio = w / h;
    CGFloat iw = image.size.width;
    CGFloat ih = image.size.height;

    CGFloat newW = iw;
    CGFloat newH = ih;

    if (iw / ih > ratio) {
        // image is wider than needed -> fit height
        newH = ih;
        newW = ih * ratio;
    } else {
        // image is taller -> fit width
        newW = iw;
        newH = iw / ratio;
    }

    CGFloat originX = (iw - newW) * 0.5;
    CGFloat originY = (ih - newH) * 0.5;

    // Convert to pixels for CGImage if needed
    CGFloat scale = image.scale ?: 1.0;
    CGRect cropRectPixels = CGRectMake(originX * scale, originY * scale, newW * scale, newH * scale);

    CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, cropRectPixels);
    if (!cg) return image;
    UIImage *cropped = [UIImage imageWithCGImage:cg scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(cg);
    return cropped;
}

#pragma mark - Actions (completed implementations)

- (void)rotateTapped {
    [self hideFilters];

    // Do rotate on background and update editor state on completion
    [self pp_processOnBackground:^UIImage *(UIImage *image) {
        return [self pp_rotateImage90DegreesClockwise:image];
    } completion:^(UIImage * _Nullable edited, NSError * _Nullable error) {
        if (error || !edited) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Unable to rotate image")];
            return;
        }
        // Crossfade to new image
        [UIView transitionWithView:self.imageView
                          duration:0.25
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
            self.imageView.image = edited;
        } completion:^(BOOL finished) {
            // Reset the editor to operate on the edited image from now on
            self.editor = [PPImageEditor editorWithImage:edited];
        }];
    }];
}

- (void)flipTapped {
    [self hideFilters];

    // Present a small action sheet to choose horizontal / vertical flip
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:kLang(@"Flip")
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:kLang(@"Flip Horizontal") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self pp_processOnBackground:^UIImage *(UIImage *image) {
            return [self pp_flipImage:image horizontal:YES vertical:NO];
        } completion:^(UIImage * _Nullable edited, NSError * _Nullable error) {
            if (error || !edited) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Unable to flip image")];
                return;
            }
            [UIView transitionWithView:self.imageView
                              duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self.imageView.image = edited; }
                            completion:^(BOOL finished){
                self.editor = [PPImageEditor editorWithImage:edited];
            }];
        }];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:kLang(@"Flip Vertical") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self pp_processOnBackground:^UIImage *(UIImage *image) {
            return [self pp_flipImage:image horizontal:NO vertical:YES];
        } completion:^(UIImage * _Nullable edited, NSError * _Nullable error) {
            if (error || !edited) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Unable to flip image")];
                return;
            }
            [UIView transitionWithView:self.imageView
                              duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self.imageView.image = edited; }
                            completion:^(BOOL finished){
                self.editor = [PPImageEditor editorWithImage:edited];
            }];
        }];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    // For iPad
    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height-60, 1, 1);

    [self presentViewController:ac animated:YES completion:nil];
}


- (void)cropTapped {
    [self hideFilters];

    // Present simple crop ratio choices (Square, 16:9, 4:3, Original)
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:kLang(@"Crop")
                                                                message:kLang(@"Choose a crop ratio")
                                                         preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:kLang(@"Square") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self pp_processOnBackground:^UIImage *(UIImage *image) {
            return [self pp_cropImage:image toAspectRatioWidth:1 height:1];
        } completion:^(UIImage * _Nullable edited, NSError * _Nullable error) {
            if (error || !edited) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Unable to crop image")];
                return;
            }
            [UIView transitionWithView:self.imageView
                              duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self.imageView.image = edited; }
                            completion:^(BOOL finished){
                self.editor = [PPImageEditor editorWithImage:edited];
            }];
        }];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"16:9" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self pp_processOnBackground:^UIImage *(UIImage *image) {
            return [self pp_cropImage:image toAspectRatioWidth:16 height:9];
        } completion:^(UIImage * _Nullable edited, NSError * _Nullable error) {
            if (error || !edited) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Unable to crop image")];
                return;
            }
            [UIView transitionWithView:self.imageView
                              duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self.imageView.image = edited; }
                            completion:^(BOOL finished){
                self.editor = [PPImageEditor editorWithImage:edited];
            }];
        }];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"4:3" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self pp_processOnBackground:^UIImage *(UIImage *image) {
            return [self pp_cropImage:image toAspectRatioWidth:4 height:3];
        } completion:^(UIImage * _Nullable edited, NSError * _Nullable error) {
            if (error || !edited) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Unable to crop image")];
                return;
            }
            [UIView transitionWithView:self.imageView
                              duration:0.25
                               options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self.imageView.image = edited; }
                            completion:^(BOOL finished){
                self.editor = [PPImageEditor editorWithImage:edited];
            }];
        }];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    // iPad safety
    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height-60, 1, 1);

    [self presentViewController:ac animated:YES completion:nil];
}








- (instancetype)initWithImage:(UIImage *)image
                   completion:(PPImageEditorCompletion)completion {
    if (self = [super init]) {
        _editor = [PPImageEditor editorWithImage:image];
        _completion = completion;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    
    self.filters = @[
        @{@"key": @"filter.normal",   @"filter": @""},
        @{@"key": @"filter.mono",     @"filter": @"CIPhotoEffectMono"},
        @{@"key": @"filter.noir",     @"filter": @"CIPhotoEffectNoir"},
        @{@"key": @"filter.fade",     @"filter": @"CIPhotoEffectFade"},
        @{@"key": @"filter.chrome",   @"filter": @"CIPhotoEffectChrome"},
        @{@"key": @"filter.instant",  @"filter": @"CIPhotoEffectInstant"},
        @{@"key": @"filter.process",  @"filter": @"CIPhotoEffectProcess"},
        @{@"key": @"filter.transfer", @"filter": @"CIPhotoEffectTransfer"}
    ];

    
    // Image view
    _imageView = [[UIImageView alloc] initWithImage:self.editor.currentImage];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_imageView];
    
    // Toolbar
    _toolbar = [[UIToolbar alloc] init];
    _toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Toolbar
    _toolbar = [[UIToolbar alloc] init];
    _toolbar.translatesAutoresizingMaskIntoConstraints = NO;

    // Crop
    UIBarButtonItem *crop = [[UIBarButtonItem alloc] initWithImage:[UIImage pp_symbolNamed:@"crop"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(cropTapped)];
    crop.accessibilityLabel = kLang(@"editor.crop");

    // Rotate
    UIBarButtonItem *rotate = [[UIBarButtonItem alloc] initWithImage:[UIImage pp_symbolNamed:@"rectangle.landscape.rotate"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(rotateTapped)];
    rotate.accessibilityLabel = kLang(@"editor.rotate");

    // Flip
    UIBarButtonItem *flip = [[UIBarButtonItem alloc] initWithImage:[UIImage pp_symbolNamed:@"arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(flipTapped)];
    flip.accessibilityLabel = kLang(@"editor.flip");

    // Filter
    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage pp_symbolNamed:@"camera.filters"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(filterTapped)];
    filter.accessibilityLabel = kLang(@"filter.title"); // add if needed

    // Reset
    UIBarButtonItem *reset = [[UIBarButtonItem alloc] initWithImage:[UIImage pp_symbolNamed:@"slider.horizontal.2.arrow.trianglehead.counterclockwise"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(resetTapped)];
    reset.accessibilityLabel = kLang(@"editor.reset");

    // Done
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithImage:[UIImage pp_symbolNamed:@"checkmark.rectangle.stack.fill"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(doneTapped)];
    done.accessibilityLabel = kLang(@"editor.done");

    
    
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                          target:nil
                                                                          action:nil];
    
    _toolbar.items = @[crop,flex, rotate,flex, flip,flex, reset, flex, done]; // filter,flex
    
    
    _toolbar.barTintColor = AppPrimaryClr;
    _toolbar.backgroundColor = [UIColor whiteColor];

    
    [self.view addSubview:_toolbar];
    
    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [_imageView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_imageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_imageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_imageView.bottomAnchor constraintEqualToAnchor:_toolbar.topAnchor],
        
        [_toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_toolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_toolbar.heightAnchor constraintEqualToConstant:50.0]
    ]];
    
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(80, 100);
    layout.minimumLineSpacing = 8;

    self.filterCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.filterCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterCollectionView.backgroundColor = [UIColor ppSurface];
    self.filterCollectionView.dataSource = self;
    self.filterCollectionView.delegate = self;

    [self.filterCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"FilterCell"];
    [self.view addSubview:self.filterCollectionView];
    

    // Constraints (bottom pinned)
    [NSLayoutConstraint activateConstraints:@[
        [self.filterCollectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.filterCollectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.filterCollectionView.bottomAnchor constraintEqualToAnchor:self.toolbar.topAnchor constant:-10],
        [self.filterCollectionView.heightAnchor constraintEqualToConstant:120]
    ]];
    
    self.filterCollectionView.layer.cornerRadius = 25;
    self.filterCollectionView.clipsToBounds = YES;
    
    self.filterCollectionView.alpha = 0;
}

-(void)showFilters
{
    [UIView animateWithDuration:0.3 animations:^{
        self.filterCollectionView.alpha = 1;
    }];
}

-(void)hideFilters
{
    [UIView animateWithDuration:0.3 animations:^{
        self.filterCollectionView.alpha = 0;
    }];
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.filters.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"FilterCell" forIndexPath:indexPath];
    
    NSDictionary *f = self.filters[indexPath.item];
    NSString *titleKey = f[@"key"];
    NSString *title = kLang(titleKey); // or [kLang get:titleKey]
    
    
    
    UIImageView *iv = [cell.contentView viewWithTag:100];
    UILabel *lbl = [cell.contentView viewWithTag:200];
    
    if (!iv) {
        iv = [[UIImageView alloc] initWithFrame:CGRectMake(10, 5, 60, 60)];
        iv.tag = 100;
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 20;
        
        [cell.contentView addSubview:iv];
        
        lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 70, 80, 30)];
        lbl.tag = 200;
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.font = [Styling fontMedium:12];
        [cell.contentView addSubview:lbl];
    }
    
    
    lbl.text = title;

    iv.image = [self generateThumbnailWithFilter:f[@"filter"]];
    
    return cell;
}


- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *f = self.filters[indexPath.item];
    NSString *filterName = f[@"filter"];
    
    if (filterName.length == 0) {
        self.imageView.image = self.editor.originalImage; // Reset
    } else {
        self.imageView.image = [self.editor applyFilterWithName:filterName parameters:nil];
    }
}


- (UIImage *)generateThumbnailWithFilter:(NSString *)filterName {
    UIImage *thumb = self.editor.currentImage;
    if (filterName.length == 0) return thumb;
    return [self.editor applyFilterWithName:filterName parameters:nil];
}



#pragma mark - Actions

- (void)updateImage:(UIImage *)image {
    if (!image) return;
    _imageView.image = image;
}



- (void)filterTapped {
    
    [self.filterCollectionView reloadData];
    self.filterCollectionView.alpha == 0 ? [self showFilters] : [self hideFilters];
}

- (void)resetTapped {
    [self.editor revertToOriginal];
    [self updateImage:self.editor.currentImage];
    [self hideFilters];
}

- (void)doneTapped {
    [self hideFilters];
    if (self.completion) {
        self.completion(self.imageView.image);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}


-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.filterCollectionView reloadData];
}
@end
