//
//  PPAddEditVetViewController.m
//  PurePetsAdmin
//

#import "PPAddEditVetViewController.h"
#import "PPVetModel.h"
#import "PPVetManager.h"
#import "PurePetsAdmin-Swift.h"

@interface PPAddEditVetViewController ()
@property (nonatomic, strong) PPVetEditorHostingController *hostingController;
@end

@implementation PPAddEditVetViewController

- (instancetype)initWithVet:(PPVetModel *)vet {
    self = [super init];
    if (self) {
        _vetToEdit = vet;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.hostingController = [[PPVetEditorHostingController alloc] initWithVetToEdit:self.vetToEdit];
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
