//
//  UIViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


#import "PPNavBar.h"
#import <objc/runtime.h>

static const void *kPPNavBarViewKey = &kPPNavBarViewKey;

@implementation UIViewController (PPNavBar)

#pragma mark - Public

- (UIView *)pp_navBar {
    NSAssert(self.navigationController, @"pp_navBar requires the view controller to be in a UINavigationController.");

    UIView *existing = objc_getAssociatedObject(self, kPPNavBarViewKey);
    if (existing) return existing;

    // Create container
    UINavigationBar *navBar = self.navigationController.navigationBar;
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.semanticContentAttribute = UISemanticContentAttributeUnspecified; // will inherit RTL/LTR
    bar.backgroundColor = UIColor.clearColor;
    bar.tag = 4242;

    // Subviews: back, title, save
    UIButton *back = [self pp_circleButtonWithSystemName:@"chevron.backward"
                                                  action:@selector(onBack)];
    UIButton *save = [self pp_circleButtonWithSystemName:@"checkmark.circle.fill"
                                                  action:@selector(onSave)];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    title.textColor = [UIColor ppTextPrimary];
    title.text = self.title.length ? self.title : @"";
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.75;

    [bar addSubview:back];
    [bar addSubview:title];
    [bar addSubview:save];
    [navBar addSubview:bar];

    // Layout inside the nav bar
    UILayoutGuide *margins = navBar.layoutMarginsGuide;
    CGFloat buttonSide = 32.0;

    [NSLayoutConstraint activateConstraints:@[
        // Pin container to nav bar height & margins horizontally
        [bar.topAnchor constraintEqualToAnchor:navBar.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:navBar.bottomAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],

        // Back button (leading)
        [back.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [back.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [back.widthAnchor constraintEqualToConstant:buttonSide],
        [back.heightAnchor constraintEqualToConstant:buttonSide],

        // Save button (trailing)
        [save.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [save.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [save.widthAnchor constraintEqualToConstant:buttonSide],
        [save.heightAnchor constraintEqualToConstant:buttonSide],

        // Title centered, with hugging vs buttons
        [title.centerXAnchor constraintEqualToAnchor:bar.centerXAnchor],
        [title.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [title.leadingAnchor constraintGreaterThanOrEqualToAnchor:back.trailingAnchor constant:8.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:save.leadingAnchor constant:-8.0],
    ]];

    // Save association
    objc_setAssociatedObject(self, kPPNavBarViewKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return bar;
}

- (void)pp_removeNavBar {
    UIView *bar = objc_getAssociatedObject(self, kPPNavBarViewKey);
    if (bar) {
        [bar removeFromSuperview];
        objc_setAssociatedObject(self, kPPNavBarViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - Helpers

- (UIButton *)pp_circleButtonWithSystemName:(NSString *)symbolName act*_*
