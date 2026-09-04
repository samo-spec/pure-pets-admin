#import "PPProviderAccountingViewController.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "Styling.h"
#import "PurePetsAdmin-Swift.h"

@interface PPProviderAccountingViewController ()
@property (nonatomic, strong) AdminProviderAccountingHostingController *hostingController;
@end

@implementation PPProviderAccountingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorNamed:@"AppBackgroundClr"] ?: [UIColor whiteColor];
    
    self.hostingController = [AdminProviderAccountingHostingController new];
    [self addChildViewController:self.hostingController];
    [self.view addSubview:self.hostingController.view];
    self.hostingController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.hostingController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.hostingController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.hostingController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.hostingController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    [self.hostingController didMoveToParentViewController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

@end
