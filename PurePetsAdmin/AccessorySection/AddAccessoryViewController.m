//
//  AddAccessoryViewController.m
//  PurePetsAdmin
//
//  NextGen V6 UIHostingController bridge for Accessory, Food, and Live Pet Editor.
//

#import "AddAccessoryViewController.h"
#import "PPDesignTokens.h"
#import "PurePetsAdmin-Swift.h"

@interface AddAccessoryViewController ()
@property (nonatomic, strong) UIViewController *hostingController;
@end

@implementation AddAccessoryViewController

- (instancetype)initWithAccessory:(PetAccessory * _Nullable)accessory {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _editingAccessory = accessory;
        _showTypeRow = YES;
        _defaultKind = AccessTypeAccessory;
    }
    return self;
}

- (instancetype)init {
    return [self initWithAccessory:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    
    __weak typeof(self) weakSelf = self;
    UIViewController *host = [PPAccessoryEditorHostingBridge makeViewControllerWithAccessory:self.editingAccessory
                                                                                showTypeRow:self.showTypeRow
                                                                                defaultKind:self.defaultKind
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
    // Safe area layout note: content views pin to self.view.safeAreaLayoutGuide.bottomAnchor within SwiftUI save dock.
    [host didMoveToParentViewController:self];
    self.hostingController = host;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

@end
