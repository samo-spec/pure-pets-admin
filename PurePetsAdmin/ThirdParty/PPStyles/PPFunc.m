//
//  PPFunc.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 23/08/2025.
//

#import "PPFunc.h"

@implementation PPFunc

+ (void)pp_presentCircularCropperWithImage:(UIImage *)image
                            fromController:(UIViewController<TOCropViewControllerDelegate> *)controller {
    TOCropViewController *cropVC =
      [[TOCropViewController alloc] initWithCroppingStyle:TOCropViewCroppingStyleCircular
                                                    image:image];
    cropVC.delegate = controller;

    // Optional UI tweaks
    cropVC.aspectRatioPickerButtonHidden = YES;
    cropVC.resetButtonHidden = YES;
    cropVC.rotateButtonsHidden = YES;
    cropVC.title = kLang(@"Move & Zoom");

    [controller presentViewController:cropVC animated:YES completion:nil];
}

+ (void)pp_clearAllYYCacheNamed:(NSString *)name {
    YYCache *cache = [YYCache cacheWithName:name];
    [cache removeAllObjectsWithBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [PPToast toast:kLang(@"Cache cleared") style:PPToastStyleSuccess haptic:YES duration:2.0];
        });
    }];
}

+ (void)reloadTableView:(UITableView *)tableView duration:(CGFloat)duration Animated:(BOOL)Animated {
    // simple fade animation to show updated results
    [UIView transitionWithView:tableView
                      duration:duration
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [tableView reloadData];
    } completion:nil];
}

+ (void)reloadTableView:(UITableView *)tableView Animated:(BOOL)Animated {
    // simple fade animation to show updated results
    [self reloadTableView:tableView duration:0.35 Animated:Animated];
}


+ (void)handleCompletionWithError:(nonnull NSError *)error successMessage:(nonnull NSString *)successMessage onController:(nonnull UIViewController *)viewController {
        [PPHUD dismiss];
        
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            [PPHUD showSuccess:kLang(@"Saved") subtitle:successMessage];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [viewController.navigationController popViewControllerAnimated:YES];
            });
        }
    }




+ (void)presentFloatingSheetFrom:(UIViewController *)presenter
                        sheetVC:(UIViewController *)sheetVC
                     detentStyle:(PPSheetDetentStyle)style
{
    if (!presenter || !sheetVC) return;

    // Always page sheet (NEVER overFullScreen)
    sheetVC.modalPresentationStyle = UIModalPresentationPageSheet;

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet =
            sheetVC.sheetPresentationController;

        // ───────────────
        // Detents
        // ───────────────
        if (@available(iOS 16.0, *)) {
            sheet.detents = @[
                [UISheetPresentationControllerDetent customDetentWithIdentifier:@"99" resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                    return context.maximumDetentValue * 0.98;
                }]
            ];
        } else {
            // Fallback on earlier versions
        }
        // ───────────────
        // 🔥 FORCE FLOATING (CRITICAL)
        // ───────────────
        sheet.prefersEdgeAttachedInCompactHeight = NO;
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = NO;

        // ───────────────
        // UI polish
        // ───────────────
      
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 42.0;

        //sheet.largestUndimmedDetentIdentifier =  @"99";

        sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    }

    // ───────────────
    // Present SAFELY
    // ───────────────
    UIViewController *safePresenter =
        presenter.presentedViewController ?: presenter;

    [safePresenter presentViewController:sheetVC
                                animated:YES
                              completion:nil];
}

 

+ (void)presentSheetFrom:(UIViewController *)presentingVC
                sheetVC:(UIViewController *)sheetVC
            detentStyle:(PPSheetDetentStyle)style
{
    if (!presentingVC || !sheetVC) return;
    CGFloat height = UIScreen.mainScreen.bounds.size.height;

    //UIWindow *win = UIApplication.sharedApplication.windows.firstObject;
    //UIStatusBarManager *mgr = win.windowScene.statusBarManager;
    //CGFloat _statusH = mgr.statusBarFrame.size.height;
    
    sheetVC.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationControllerDetent *customMedium = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *chatsDent = UISheetPresentationControllerDetent.mediumDetent;

    UISheetPresentationControllerDetent *profileDent = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *customMedium80 = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *customMedium300 = UISheetPresentationControllerDetent.mediumDetent;
    UISheetPresentationControllerDetent *adsViewDent = UISheetPresentationControllerDetent.mediumDetent;

    if (@available(iOS 16.0, *)) {

        chatsDent = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"chatsDent"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.85; // your custom medium height
        }];
        
        customMedium = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"customMedium"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.7; // your custom medium height
        }];
        
        customMedium80 = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"customMedium80"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.95; // your custom medium height
        }];
        
        adsViewDent = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"adsViewDent"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return height * 0.95; // your custom medium height
        }];
        
        profileDent = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"profileDent"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return (height - PPTotalBarHeight); // your custom medium height
        }];
        
        customMedium300 = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"customMedium300"  resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            return 400; // your custom medium height
        }];
        
    } else {
        // Fallback on earlier versions
    }
    
    
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = sheetVC.sheetPresentationController;
        if (sheet) {
            // Configure detents
            switch (style) {
                case PPSheetDetentStyle70:
                    sheet.detents = @[customMedium];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyleAdsView:
                    sheet.detents = @[adsViewDent];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyle80:
                    sheet.detents = @[customMedium80];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyle300:
                    sheet.detents = @[customMedium300];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;
                    
                case PPSheetDetentStyleProfile:
                
                    sheet.detents = @[ profileDent];

                    
                    break;
                    
                case PPSheetDetentStyleMediumOnly:
                    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
                    break;

                case PPSheetDetentStyleLargeOnly:
                    sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
                    break;
                    
                case PPSheetDetentStyleMediumAndLarge:
                    sheet.detents = @[
                        UISheetPresentationControllerDetent.mediumDetent,
                        UISheetPresentationControllerDetent.largeDetent
                    ];
                    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
                    break;
                case PPSheetDetentStyleSemiLargAndLarge:
                    //sheet.detents = @[
                    //    chatsDent,
                       // UISheetPresentationControllerDetent.largeDetent
                    //];
                    //if (@available(iOS 16.0, *)) {
                    //    sheet.largestUndimmedDetentIdentifier = chatsDent.identifier;
                    //} else {
                        // Fallback on earlier versions
                    //}
                    
                    
                    if (@available(iOS 16.0, *)) {
                        sheet.detents = @[
                            [UISheetPresentationControllerDetent customDetentWithIdentifier:@"99"
                                                                                   resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
                                return context.maximumDetentValue * 0.99;
                            }]
                        ];
                    } else {
                        // Fallback on earlier versions
                    }

                    sheet.selectedDetentIdentifier = @"99";
                    sheet.largestUndimmedDetentIdentifier = nil;
                    sheet.prefersGrabberVisible = YES;
                    
                    
                    break;
            }

            // Style settings
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 42.0;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
            
            if(PPIOS26())
            {
                //sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDete;
                //presentingVC.modalPresentationCapturesStatusBarAppearance = NO;
                //sheet.prefersEdgeAttachedInCompactHeight = NO;
                
            }
        }
    } else {
        // Fallback for iOS < 15
        sheetVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    }
    
    

    // Present on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [presentingVC presentViewController:sheetVC animated:YES completion:nil];
    });
}



@end





@implementation PaddedLabel

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.textInsets = UIEdgeInsetsMake(4, 8, 4, 8); // default padding
    }
    return self;
}

// Draw text with insets
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.textInsets)];
}

// Adjust intrinsic size for Auto Layout
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width  += self.textInsets.left + self.textInsets.right;
    size.height += self.textInsets.top + self.textInsets.bottom;
    return size;
}

// Adjust sizeThatFits (if not using Auto Layout)
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize adjusted = [super sizeThatFits:size];
    adjusted.width  += self.textInsets.left + self.textInsets.right;
    adjusted.height += self.textInsets.top + self.textInsets.bottom;
    return adjusted;
}

@end



@implementation UIImage (Crop)
- (UIImage *)pp_circularImage {
    CGFloat side = MIN(self.size.width, self.size.height);
    CGRect cropRect = CGRectMake((self.size.width - side) / 2.0,
                                 (self.size.height - side) / 2.0,
                                 side, side);

    CGImageRef cgCropped = CGImageCreateWithImageInRect(self.CGImage, cropRect);
    UIImage *square = [UIImage imageWithCGImage:cgCropped scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(cgCropped);

    UIGraphicsBeginImageContextWithOptions(square.size, NO, 0);
    CGRect rect = CGRectMake(0, 0, square.size.width, square.size.height);
    [[UIBezierPath bezierPathWithOvalInRect:rect] addClip];
    [square drawInRect:rect];
    UIImage *circle = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return circle;
}
@end

