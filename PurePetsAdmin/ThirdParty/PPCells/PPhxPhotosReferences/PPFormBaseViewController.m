//
//  PPFormBaseViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// PPFormBaseViewController.m
#import "PPFormBaseViewController.h"


@implementation PPFormBaseViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Replace nav bar with your PPNavBar
    // Example: only back + title
    
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:self.title showBack:YES];

}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.title = @""; // hide system nav title
}

@end
