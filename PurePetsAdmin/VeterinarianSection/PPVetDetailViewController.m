//
//  PPVetDetailViewController.m
//  PurePetsAdmin
//

#import "PPVetDetailViewController.h"
#import "PPVetModel.h"
#import "PPVetManager.h"
#import "PPAddEditVetViewController.h"
#import "PPVetSubscriptionViewController.h"
#import "PurePetsAdmin-Swift.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;

@interface PPVetDetailViewController ()
@property (nonatomic, strong) PPVetModel *vet;
@property (nonatomic, strong) PPVetDetailDossierHostingController *hostingController;
@end

@implementation PPVetDetailViewController

- (instancetype)initWithVet:(PPVetModel *)vet {
    self = [super init];
    if (self) {
        _vet = vet;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.hostingController = [[PPVetDetailDossierHostingController alloc] initWithVet:self.vet];
    [self addChildViewController:self.hostingController];
    self.hostingController.view.frame = self.view.bounds;
    self.hostingController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.hostingController.view];
    [self.hostingController didMoveToParentViewController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

@end
