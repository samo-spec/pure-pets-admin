//
//  PPListingsAdminViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed.
//  Updated for NextGen V6 Sovereign Listings Command Center Bridge.
//

#import "PPListingsAdminViewController.h"
#import "PPDesignTokens.h"
#import "PurePetsAdmin-Swift.h"

@interface PPListingsAdminViewController ()
@property (nonatomic, strong) UIViewController *hostingController;
@end

@implementation PPListingsAdminViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];

    __weak typeof(self) weakSelf = self;
    UIViewController *host = [PPListingsCommandCenterHostingBridge makeViewControllerWithOnDismiss:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (self.navigationController && self.navigationController.viewControllers.count > 1) {
            [self.navigationController popViewControllerAnimated:YES];
        } else {
            [PPAdminNavigationFallback popOrDismissFrom:self];
        }
    }];

    [self addChildViewController:host];
    [self.view addSubview:host.view];
    host.view.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [host.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [host.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [host.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [host.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [host didMoveToParentViewController:self];
    self.hostingController = host;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
}

@end
