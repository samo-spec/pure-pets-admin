//
//  StaffRolesViewController.m
//  PurePetsAdmin
//
//  NextGen V6 UIHostingController bridge for Sovereign Role Rank & Security Levels Matrix.
//

#import "StaffRolesViewController.h"
#import "PPDesignTokens.h"
#import "PurePetsAdmin-Swift.h"

@interface StaffRolesViewController ()
@property (nonatomic, strong) UIViewController *hostingController;
@end

@implementation StaffRolesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];

    __weak typeof(self) weakSelf = self;
    UIViewController *host = [AdminRoleRankHostingBridge makeViewControllerWithOnDismiss:^{
        [weakSelf pp_handleDismiss];
    }];
    self.hostingController = host;
    [self addChildViewController:host];
    [self.view addSubview:host.view];
    host.view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [host.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [host.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [host.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [host.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    [host didMoveToParentViewController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
}

- (void)pp_handleDismiss {
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
