//
//  SplashViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 29/08/2025.
//
#import "SplashViewController.h"


@implementation SplashViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = AppBackgroundClr;
  UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
  sp.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:sp];
  [NSLayoutConstraint activateConstraints:@[
    [sp.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [sp.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
  ]];
  [sp startAnimating];
}
@end
