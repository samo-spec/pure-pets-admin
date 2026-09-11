//
//  PPAddEditServiceViewController.m
//  PurePetsAdmin
//
//  NextGen V6 Sovereign Service Creative Studio Host Bridge.
//

#import "PPAddEditServiceViewController.h"
#import "PPServiceModel.h"
#import "PPDesignTokens.h"
#import "PurePetsAdmin-Swift.h"

@interface PPAddEditServiceViewController ()
@property (nonatomic, strong) PPServiceModel *serviceToEdit;
@property (nonatomic, strong) UIViewController *hostingController;
@end

@implementation PPAddEditServiceViewController

- (instancetype)initWithService:(PPServiceModel *)service {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _serviceToEdit = service;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];

    __weak typeof(self) weakSelf = self;
    UIViewController *host = [PPServiceEditorHostingBridge makeViewControllerWithService:self.serviceToEdit
                                                                               onDismiss:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (self.navigationController && self.navigationController.viewControllers.count > 1) {
            [self.navigationController popViewControllerAnimated:YES];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }
                                                                               onSuccess:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (self.navigationController && self.navigationController.viewControllers.count > 1) {
            [self.navigationController popViewControllerAnimated:YES];
        } else {
            [self dismissViewControllerAnimated:YES completion:nil];
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
