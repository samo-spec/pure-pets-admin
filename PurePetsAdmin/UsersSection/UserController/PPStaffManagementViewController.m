#import "PPStaffManagementViewController.h"
#import "StaffMembersViewController.h"
#import "AddUserViewController.h"
#import "StaffRolesViewController.h"
#import "PPStaffPreviewViewController.h"
#import "PPStaffAuth.h"
#import "Styling.h"
#import "Language.h"
@import Firebase;

static NSUInteger const PPStaffManagementTabCount = 4;

@interface PPStaffManagementViewController ()

@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) NSArray<UIViewController *> *childControllers;
@property (nonatomic, assign) NSUInteger selectedIndex;

@end

@implementation PPStaffManagementViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    self.selectedIndex = 0;
    [self pp_buildSegmentedControl];
    [self pp_buildContainer];
    [self pp_buildChildControllers];
    [self pp_showTabAtIndex:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat segHeight = 44.0;
    CGFloat segY = self.view.safeAreaInsets.top + 8.0;
    CGFloat segW = self.view.bounds.size.width - 24.0;
    self.segmentedControl.frame = CGRectMake(12.0, segY, segW, segHeight);

    CGFloat containerY = CGRectGetMaxY(self.segmentedControl.frame) + 8.0;
    CGFloat containerH = self.view.bounds.size.height - containerY - self.view.safeAreaInsets.bottom;
    self.containerView.frame = CGRectMake(0, containerY, self.view.bounds.size.width, containerH);
}

#pragma mark - Build

- (void)pp_buildSegmentedControl {
    NSArray *titles = @[
        kLang(@"Staff_List_Tab"),
        kLang(@"Staff_Create_Tab"),
        kLang(@"Staff_Roles_Tab"),
        kLang(@"Staff_Preview_Tab")
    ];

    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:titles];
    seg.selectedSegmentIndex = 0;
    [seg addTarget:self action:@selector(pp_segmentChanged:) forControlEvents:UIControlEventValueChanged];
    seg.backgroundColor = [AppForgroundColr ?: UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.5];
    seg.selectedSegmentTintColor = AppPrimaryClr ?: UIColor.systemBlueColor;

    NSDictionary *normalAttrs = @{NSForegroundColorAttributeName: (PrimaryTextClr ?: UIColor.labelColor)};
    NSDictionary *selectedAttrs = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    [seg setTitleTextAttributes:normalAttrs forState:UIControlStateNormal];
    [seg setTitleTextAttributes:selectedAttrs forState:UIControlStateSelected];

    [self.view addSubview:seg];
    self.segmentedControl = seg;
}

- (void)pp_buildContainer {
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.clipsToBounds = YES;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:container];
    self.containerView = container;
}

- (void)pp_buildChildControllers {
    StaffMembersViewController *staffList = [StaffMembersViewController new];
    staffList.title = kLang(@"Staff_List_Tab");

    AddUserViewController *createStaff = [AddUserViewController new];
    createStaff.title = kLang(@"Staff_Create_Tab");

    StaffRolesViewController *staffRoles = [StaffRolesViewController new];
    staffRoles.title = kLang(@"Staff_Roles_Tab");

    PPStaffPreviewViewController *preview = [PPStaffPreviewViewController new];
    preview.title = kLang(@"Staff_Preview_Tab");

    self.childControllers = @[staffList, createStaff, staffRoles, preview];
}

#pragma mark - Actions

- (void)pp_segmentChanged:(UISegmentedControl *)sender {
    [self pp_showTabAtIndex:sender.selectedSegmentIndex];
}

- (void)pp_showTabAtIndex:(NSUInteger)index {
    if (index >= self.childControllers.count) return;

    UIViewController *previousVC = (self.selectedIndex < self.childControllers.count)
        ? self.childControllers[self.selectedIndex]
        : nil;
    UIViewController *nextVC = self.childControllers[index];

    if (previousVC && previousVC.parentViewController == self) {
        [previousVC willMoveToParentViewController:nil];
        [previousVC.view removeFromSuperview];
        [previousVC removeFromParentViewController];
    }

    [self addChildViewController:nextVC];
    nextVC.view.frame = self.containerView.bounds;
    nextVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerView addSubview:nextVC.view];
    [nextVC didMoveToParentViewController:self];

    self.selectedIndex = index;
}

@end
