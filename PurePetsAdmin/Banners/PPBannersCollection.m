//
//  PPBannersCollection 2.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 08/09/2025.
//


//
//  PPBannersCollection.m
//  PurePets
//

#import "PPBannersCollection.h"
static NSString * const kReuseBannerCell = @"PPBannerCell";

@interface PPBannersCollection () <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>


@property (nonatomic, strong) NSTimer *autoScrollTimer;

@end

@implementation PPBannersCollection


- (void)layoutSubviews {
    [super layoutSubviews];

    self.collectionView.frame = self.bounds;

    // Size page control to fit its dots
    CGSize size = [self.pageControl sizeForNumberOfPages:self.pageControl.numberOfPages];
    CGFloat pcH = MAX(14, size.height);
    CGFloat pcW = MIN(self.bounds.size.width - 32, size.width + 12); // pad a bit

    self.pageControl.frame = CGRectMake((self.bounds.size.width - pcW) * 0.5,
                                        self.bounds.size.height - pcH - 8,
                                        pcW,
                                        pcH);

    [self bringSubviewToFront:self.pageControl];
}



- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat pageWidth = MAX(scrollView.bounds.size.width, 1);
    NSInteger page = (NSInteger)llround(scrollView.contentOffset.x / pageWidth);
    page = MAX(0, MIN(page, (NSInteger)self.pageControl.numberOfPages - 1));
    self.pageControl.currentPage = page;
}



- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self startAutoScroll];
    } else {
        [self stopAutoScroll];
    }
}

// If the interval changes later, restart timer
- (void)setAutoScrollInterval:(NSTimeInterval)autoScrollInterval {
    _autoScrollInterval = autoScrollInterval;
    [self startAutoScroll];
}

- (void)startAutoScroll {
    [self stopAutoScroll];
    if (self.autoScrollInterval <= 0 || self.banners.count <= 1) return;

    // Use a timer and add it to the run loop in common modes,
    // so it still fires even when the scroll view is not in default mode.
    self.autoScrollTimer = [NSTimer timerWithTimeInterval:self.autoScrollInterval
                                                   target:self
                                                 selector:@selector(scrollToNext)
                                                 userInfo:nil
                                                  repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.autoScrollTimer forMode:NSRunLoopCommonModes];
}

- (void)stopAutoScroll {
    [self.autoScrollTimer invalidate];
    self.autoScrollTimer = nil;
}


- (void)setBanners:(NSArray<PPBannerViewModel *> *)banners {
    _banners = [banners copy];
    self.pageControl.numberOfPages = _banners.count;
    self.pageControl.currentPage = 0;

    // Reset position & reload
    [self.collectionView setContentOffset:CGPointZero animated:NO];
    [self.collectionView reloadData];

    // If you auto-scroll, restart so timing aligns with new data
    [self startAutoScroll];

    // Make sure the dots are on top
    [self bringSubviewToFront:self.pageControl];
}


- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self stopAutoScroll];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        // Resume after a small delay so it doesn't fight the user
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startAutoScroll];
        });
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    NSInteger page = (NSInteger)round(scrollView.contentOffset.x / MAX(scrollView.bounds.size.width, 1));
    self.pageControl.currentPage = page;

    // Resume auto scroll after user stops
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startAutoScroll];
    });
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        self.banners = @[];
        [self setupCollectionView];
        [self setupPageControl];
    }
    return self;
}

- (instancetype)initWithBanners:(NSArray<PPBannerViewModel *> *)banners {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.banners = banners;
        [self setupCollectionView];
        [self setupPageControl];
    }
    return self;
}


#pragma mark - Setup

- (void)setupCollectionView {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 0;

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.pagingEnabled = YES;
    _collectionView.showsHorizontalScrollIndicator = NO;
    _collectionView.delegate = self;
    _collectionView.dataSource = self;
    _collectionView.backgroundColor = AppForgroundColr;
    // In HomeViewController.m (where you create the collection view)
    [self.collectionView registerClass:[PPBannerCell class] forCellWithReuseIdentifier:kReuseBannerCell];
    _collectionView.layer.cornerRadius = 0.0;
    _collectionView.clipsToBounds=YES;
    [self addSubview:_collectionView];

    self.collectionView.frame = self.bounds;

  

}

- (void)setupPageControl {
    _pageControl = [UIPageControl new];
    _pageControl.numberOfPages = self.banners.count;
    _pageControl.currentPage = 0;
    _pageControl.pageIndicatorTintColor = AppForgroundColr;
    _pageControl.currentPageIndicatorTintColor = AppForgroundColr;
    self.pageControl.hidesForSinglePage = YES; // optional
    self.pageControl.userInteractionEnabled = NO; // ignore taps if you don’t handle them

    [self addSubview:_pageControl];
}

// In -scrollToNext
- (void)scrollToNext {
    if (self.banners.count == 0) return;

    CGFloat pageWidth = self.collectionView.bounds.size.width;
    NSInteger currentPage = (NSInteger)round(self.collectionView.contentOffset.x / MAX(pageWidth, 1));
    NSInteger nextPage = (currentPage + 1) % self.banners.count;
    CGPoint target = CGPointMake(nextPage * pageWidth, 0);

    if (self.autoScrollStyle == PPBannersAutoScrollStyleFade) {
        // Cross-dissolve while jumping to target without “scroll” animation
        [UIView transitionWithView:self.collectionView
                          duration:self.autoScrollAnimationDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowAnimatedContent
                        animations:^{
                            [self.collectionView setContentOffset:target animated:NO];
                        } completion:nil];
    } else {
        // Slide (custom speed)
        [UIView animateWithDuration:self.autoScrollAnimationDuration
                              delay:0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
                             self.collectionView.contentOffset = target;
                         } completion:nil];
    }

    self.pageControl.currentPage = nextPage;
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.banners.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    PPBannerCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kReuseBannerCell forIndexPath:indexPath];
    id banner = self.banners[indexPath.item];
    [cell configureWithModel:(PPBannerViewModel *)banner];
    
   
    
    
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return collectionView.bounds.size;
}

-(void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    PPBannerViewModel *vm = self.banners[indexPath.item];
    
    [self.delegate didTapOn_BannerViewModel:vm inGroup:self.pannerGroup];

}


@end
