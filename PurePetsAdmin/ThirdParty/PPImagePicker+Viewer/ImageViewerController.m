//
//  ImageViewerController 2.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 30/09/2025.
//


#import "ImageViewerController.h"
#import "JGProgressHUD.h"
#import <SDWebImage/UIImageView+WebCache.h>

@interface ImageViewerController () <UIScrollViewDelegate>

@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) ImageViewerSourceType sourceType;
@property (nonatomic, strong) NSMutableArray<UIImage *> *images;
@property (nonatomic, strong) UIScrollView *pagingScrollView;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) NSMutableArray<UIScrollView *> *zoomScrollViews;

@end

@implementation ImageViewerController

#pragma mark - Zoom Delegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    if ([self.zoomScrollViews containsObject:scrollView]) {
        return [scrollView viewWithTag:999];
    }
    return nil;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    UIImageView *imageView = [scrollView viewWithTag:999];
    if (!imageView) return;
    
    CGSize boundsSize = scrollView.bounds.size;
    CGRect imageFrame = imageView.frame;
    
    CGFloat offsetX = (boundsSize.width > imageFrame.size.width) ?
                      (boundsSize.width - imageFrame.size.width) / 2.0 : 0.0;
    CGFloat offsetY = (boundsSize.height > imageFrame.size.height) ?
                      (boundsSize.height - imageFrame.size.height) / 2.0 : 0.0;
    
    imageView.center = CGPointMake(imageFrame.size.width / 2.0 + offsetX,
                                   imageFrame.size.height / 2.0 + offsetY);
}


#pragma mark - Init

- (instancetype)initWithImageURLs:(NSArray<NSString *> *)urls {
    if (self = [super init]) {
        self.items = urls;
        self.images = [[NSMutableArray<UIImage *> alloc]init];
        self.sourceType = ImageViewerSourceTypeURLs;
    }
    return self;
}

- (instancetype)initWithImages:(NSArray<UIImage *> *)images {
    if (self = [super init]) {
        self.items = images;
        self.sourceType = ImageViewerSourceTypeImages;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    
    [self setupPagingScrollView];
    [self setupPageControl];
    [self loadPages];
    
    
   
}


- (void)handleSwipeDown:(UISwipeGestureRecognizer *)gesture {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Setup

- (void)setupPagingScrollView {
    CGRect psFrame = self.view.bounds;
    psFrame.origin.y = 0;
    self.pagingScrollView = [[UIScrollView alloc] initWithFrame:psFrame];
    self.pagingScrollView.pagingEnabled = YES;
    self.pagingScrollView.delegate = self;
    self.pagingScrollView.showsHorizontalScrollIndicator = NO;
    self.pagingScrollView.showsVerticalScrollIndicator = NO;
    self.pagingScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pagingScrollView];
    
    self.zoomScrollViews = [NSMutableArray array];
}

- (void)setupPageControl {
    self.pageControl = [[UIPageControl alloc] init];
    self.pageControl.numberOfPages = self.items.count;
    self.pageControl.currentPage = 0;
    self.pageControl.currentPageIndicatorTintColor = [UIColor whiteColor];
    self.pageControl.pageIndicatorTintColor = [UIColor lightGrayColor];
    self.pageControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pageControl];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.pageControl.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [self.pageControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];
}

#pragma mark - Load Pages

- (void)loadPages {
    // 🧹 Clear old pages first to avoid duplicates
    for (UIView *subview in self.pagingScrollView.subviews) {
        [subview removeFromSuperview];
    }
    [self.zoomScrollViews removeAllObjects];
    [self.images removeAllObjects];
    
    CGFloat width = CGRectGetWidth(self.view.bounds);
    // Use safe area top inset as status bar height surrogate when available
    CGFloat statusBarHeight = 0.0;
    if (@available(iOS 11.0, *)) {
        statusBarHeight = self.view.safeAreaInsets.top;
    }
    CGFloat height = CGRectGetHeight(self.view.bounds) - statusBarHeight;
    if (height < 0.0) { height = 0.0; }
    self.pagingScrollView.contentSize = CGSizeMake(width * (CGFloat)self.items.count, height);
    
    for (NSInteger i = 0; i < (NSInteger)self.items.count; i++) {
        CGRect frame = CGRectMake(width * (CGFloat)i, (CGFloat)-60.0, width, height);
        
        // Create zoomable scroll view
        UIScrollView *zoomScrollView = [[UIScrollView alloc] initWithFrame:frame];
        zoomScrollView.delegate = self;
        zoomScrollView.minimumZoomScale = 1.0;
        zoomScrollView.maximumZoomScale = 3.0;
        zoomScrollView.bouncesZoom = YES;
        zoomScrollView.showsHorizontalScrollIndicator = NO;
        zoomScrollView.showsVerticalScrollIndicator = NO;
        zoomScrollView.tag = i;
        
        // Create image view inside zoom scroll view
        UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        imageView.tag = 999;
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.userInteractionEnabled = YES;
        [zoomScrollView addSubview:imageView];
        
        // Add scroll view to main paging scroll
        [self.pagingScrollView addSubview:zoomScrollView];
        [self.zoomScrollViews addObject:zoomScrollView];
        
        // Add gestures
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        [imageView addGestureRecognizer:doubleTap];
        
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        [imageView addGestureRecognizer:longPress];
        
        UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeDown:)];
        swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
        [imageView addGestureRecognizer:swipeDown];
        
        // Load image depending on source type
        if (self.sourceType == ImageViewerSourceTypeURLs) {
            NSString *urlString = self.items[i];
            JGProgressHUD *hud = [JGProgressHUD progressHUDWithStyle:JGProgressHUDStyleDark];
            [hud showInView:imageView];
            
            [imageView sd_setImageWithURL:[NSURL URLWithString:urlString]
                          placeholderImage:[UIImage imageNamed:@"placeholder"]
                                 completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [hud dismiss];
                    if (image) {
                        [self.images addObject:image];
                        imageView.image = image;
                    }
                    [self centerImageInScrollView:zoomScrollView imageView:imageView];
                });
            }];
        } else {
            UIImage *img = self.items[i];
            imageView.image = img;
            [self.images addObject:img];
            [self centerImageInScrollView:zoomScrollView imageView:imageView];
        }
    }
}

- (void)centerImageInScrollView:(UIScrollView *)scrollView imageView:(UIImageView *)imageView {
    if (!imageView.image) return;
    
    CGSize boundsSize = scrollView.bounds.size;
    CGSize imageSize = imageView.image.size;
    
    CGFloat minScale = MIN(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height);
    scrollView.minimumZoomScale = minScale;
    scrollView.zoomScale = minScale;
    
    CGSize imageFrameSize = CGSizeMake(imageSize.width * minScale, imageSize.height * minScale);
    imageView.frame = CGRectMake(0,
                                 0,
                                 imageFrameSize.width,
                                 imageFrameSize.height);
    imageView.frame = CGRectMake(0, 0, scrollView.bounds.size.width, scrollView.bounds.size.height);
    imageView.center = CGPointMake(scrollView.bounds.size.width / 2.0, scrollView.bounds.size.height / 2.0);
    
    imageView.backgroundColor = UIColor.clearColor;
}


#pragma mark - Zoom Delegate



- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) {
        NSInteger page = scrollView.contentOffset.x / scrollView.bounds.size.width;
        self.pageControl.currentPage = page;
    }
}

#pragma mark - Actions
- (void)longPress:(UILongPressGestureRecognizer *)g {
    UIImage *imageToShare = [self.images objectAtIndex:self.pageControl.currentPage];
    
    if(imageToShare)
    {
        UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[imageToShare] applicationActivities:nil];
        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            activityViewController.popoverPresentationController.sourceView = g.view;
            CGPoint point = [g locationInView:g.view];
            activityViewController.popoverPresentationController.sourceRect = CGRectMake(point.x, point.y, 1, 1);
        }
        [self presentViewController:activityViewController animated:YES completion:nil];
    }
}
- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    UIScrollView *zoomScrollView = (UIScrollView *)gesture.view.superview;
    if (zoomScrollView.zoomScale > 1.0) {
        [zoomScrollView setZoomScale:1.0 animated:YES];
    } else {
        CGPoint pointInView = [gesture locationInView:gesture.view];
        CGFloat newZoomScale = zoomScrollView.maximumZoomScale;
        CGFloat w = zoomScrollView.bounds.size.width / newZoomScale;
        CGFloat h = zoomScrollView.bounds.size.height / newZoomScale;
        CGFloat x = pointInView.x - (w / 2.0);
        CGFloat y = pointInView.y - (h / 2.0);
        [zoomScrollView zoomToRect:CGRectMake(x, y, w, h) animated:YES];
    }
}

-(void)shareAdBTN
{
    
}

-(void)dissmisBTNTapped
{
    [self dismissViewControllerAnimated:YES completion:nil];
}


-(void)DownloadBTNTapped
{
    
}


-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    UIButton *shareBtn = [self pp_ButtonWithSystemName:@"square.and.arrow.up" action:@selector(shareAdBTN)];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:shareBtn title:@"" showBack:YES];
    //UIButton *DownloadBTN = [self pp_ButtonWithSystemName:@"square.and.arrow.down" action:@selector(DownloadBTNTapped)];
    [self pp_navBarSetLeftIcon:@"multiply" key:kPPKeyBaseBack target:self action:@selector(dissmisBTNTapped) tap:^{}];
     
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
 }
@end

