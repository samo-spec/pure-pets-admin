//
//  PPAddBannerViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 09/09/2025.
//  Updated for NextGen V6 Sovereign Banner Creative Studio Bridge.
//

#import "PPAddBannerViewController.h"
#import "MainBannerModel.h"
#import "PPBannerViewModel.h"
#import "PPDesignTokens.h"
#import "PurePetsAdmin-Swift.h"

@interface PPAddBannerViewController ()
@property (nonatomic, strong) UIViewController *hostingController;
@end

@implementation PPAddBannerViewController

#pragma mark - Initializers

- (instancetype)initWithEditMode:(PPEditMode)editMode
                            group:(MainBannerModel * _Nullable)group
                           banner:(PPBannerViewModel * _Nullable)banner {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _editMode = editMode;
        _editingBannerGroup = group;
        _editingBanner = banner;
    }
    return self;
}

- (instancetype)initWithMainBanner:(MainBannerModel * _Nullable)banner {
    return [self initWithEditMode:(banner ? PPEditModeGroupOnly : PPEditModeNewGroup)
                            group:banner
                           banner:nil];
}

- (instancetype)initWithBanner:(PPBannerViewModel * _Nullable)banner inGroup:(MainBannerModel * _Nullable)group {
    return [self initWithEditMode:PPEditModeBannerOnly
                            group:group
                           banner:banner];
}

- (instancetype)init {
    return [self initWithEditMode:PPEditModeNewGroup group:nil banner:nil];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];

    __weak typeof(self) weakSelf = self;
    UIViewController *host = [PPAddBannerEditorHostingBridge makeViewControllerWithEditMode:self.editMode
                                                                                      group:self.editingBannerGroup
                                                                                     banner:self.editingBanner
                                                                                  onDismiss:^{
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
