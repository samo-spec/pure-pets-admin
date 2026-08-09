#import "PPStaffManagementViewController.h"
#import "StaffMembersViewController.h"
#import "AddUserViewController.h"
#import "StaffRolesViewController.h"
#import "PPStaffPreviewViewController.h"
#import "PPStaffAuth.h"
#import "Styling.h"
#import "Language.h"
#import "PPDesignTokens.h"
@import Firebase;

static NSUInteger const PPStaffManagementTabCount = 4;
static CGFloat const PPStaffManagementChromeHeight = 72.0;
static CGFloat const PPStaffManagementChromeInset = 16.0;

static UIFont *PPStaffManagementScaledFont(UIFont *baseFont, UIFontTextStyle textStyle) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
    }
    return baseFont;
}

@interface PPStaffManagementViewController ()

@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) NSArray<UIViewController *> *childControllers;
@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, strong) UIView *topBarView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIView *segmentContainerView;
@property (nonatomic, strong) UIView *segmentSelectionView;
@property (nonatomic, strong) UIStackView *segmentStackView;
@property (nonatomic, copy) NSArray<UIButton *> *segmentButtons;

@end

@implementation PPStaffManagementViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.selectedIndex = 0;

    [self pp_buildTopBar];
    [self pp_buildSegmentedControl];
    [self pp_buildContainer];
    [self pp_buildChildControllers];
    [self pp_showTabAtIndex:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat topSafeArea = self.view.safeAreaInsets.top;
    CGFloat topBarHeight = topSafeArea + PPStaffManagementChromeHeight;

    self.topBarView.frame = CGRectMake(0.0, 0.0, self.view.bounds.size.width, topBarHeight);

    CGFloat btnSize = 48.0;
    CGFloat btnY = topSafeArea + (PPStaffManagementChromeHeight - btnSize) / 2.0;

    BOOL isRTL = [Language isRTL];
    CGFloat backBtnX = isRTL ? (self.view.bounds.size.width - btnSize - PPStaffManagementChromeInset) : PPStaffManagementChromeInset;
    self.backButton.frame = CGRectMake(backBtnX, btnY, btnSize, btnSize);

    CGFloat segHeight = 48.0;
    CGFloat segY = topSafeArea + (PPStaffManagementChromeHeight - segHeight) / 2.0;

    CGFloat segW = self.view.bounds.size.width - btnSize - (PPStaffManagementChromeInset * 2.0) - 12.0;
    CGFloat segX = isRTL ? PPStaffManagementChromeInset : (backBtnX + btnSize + 12.0);
    self.segmentContainerView.frame = CGRectMake(segX, segY, segW, segHeight);
    self.segmentStackView.frame = self.segmentContainerView.bounds;
    [self pp_layoutSelectionPillAnimated:NO];

    CGFloat containerY = topBarHeight;
    CGFloat containerH = self.view.bounds.size.height - containerY - self.view.safeAreaInsets.bottom;
    self.containerView.frame = CGRectMake(0, containerY, self.view.bounds.size.width, containerH);
}

#pragma mark - Build

- (void)pp_buildTopBar {
    self.topBarView = [UIView new];
    self.topBarView.backgroundColor = UIColor.clearColor;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    blur.frame = self.topBarView.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.topBarView addSubview:blur];

    UIView *separator = [UIView new];
    separator.backgroundColor = [[UIColor separatorColor] colorWithAlphaComponent:0.18];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBarView addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:self.topBarView.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.topBarView.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:self.topBarView.bottomAnchor],
        [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];

    [self.view addSubview:self.topBarView];

    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *backConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    NSString *backImageName = [Language isRTL] ? @"chevron.right" : @"chevron.left";
    [self.backButton setImage:[UIImage systemImageNamed:backImageName withConfiguration:backConfig] forState:UIControlStateNormal];
    [self.backButton addTarget:self action:@selector(didTapBack) forControlEvents:UIControlEventTouchUpInside];
    self.backButton.accessibilityLabel = kLang(@"Back");
    self.backButton.accessibilityHint = kLang(@"Back");
    [self.topBarView addSubview:self.backButton];
}

- (void)pp_buildSegmentedControl {
    NSArray *titles = @[
        kLang(@"Staff_List_Tab"),
        kLang(@"Staff_Create_Tab"),
        kLang(@"Staff_Roles_Tab"),
        kLang(@"Staff_Preview_Tab")
    ];

    self.segmentContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.segmentContainerView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.segmentContainerView.clipsToBounds = NO;
    [self.topBarView addSubview:self.segmentContainerView];

    self.segmentSelectionView = [[UIView alloc] initWithFrame:CGRectZero];
    self.segmentSelectionView.userInteractionEnabled = NO;
    [self.segmentContainerView addSubview:self.segmentSelectionView];

    self.segmentStackView = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.segmentStackView.axis = UILayoutConstraintAxisHorizontal;
    self.segmentStackView.alignment = UIStackViewAlignmentFill;
    self.segmentStackView.distribution = UIStackViewDistributionFillEqually;
    self.segmentStackView.spacing = 0.0;
    self.segmentStackView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.segmentContainerView addSubview:self.segmentStackView];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:titles.count];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        (void)stop;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = idx;
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.titleLabel.numberOfLines = 2;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 6);
        [button setTitle:title forState:UIControlStateNormal];
        [button addTarget:self action:@selector(pp_segmentButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.accessibilityLabel = title;
        button.accessibilityTraits = UIAccessibilityTraitButton;
        [self.segmentStackView addArrangedSubview:button];
        [buttons addObject:button];
    }];
    self.segmentButtons = buttons.copy;

    [self pp_applyPremiumSegmentedStyle];
}

- (void)pp_applyPremiumSegmentedStyle {
    UIColor *surfaceColor = AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
    UIColor *accentColor = AppPrimaryClr ?: [UIColor colorWithRed:0.20 green:0.66 blue:0.48 alpha:1.0];
    UIColor *textColor = PrimaryTextClr ?: UIColor.labelColor;

    self.backButton.backgroundColor = surfaceColor;
    self.backButton.layer.cornerRadius = 24.0;
    self.backButton.tintColor = textColor;
    self.backButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.backButton.layer.shadowOpacity = 0.07;
    self.backButton.layer.shadowRadius = 18.0;
    self.backButton.layer.shadowOffset = CGSizeMake(0, 8);

    self.segmentContainerView.backgroundColor = [surfaceColor colorWithAlphaComponent:0.82];
    self.segmentContainerView.layer.cornerRadius = 24.0;
    self.segmentContainerView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.segmentContainerView.layer.borderColor = [[UIColor separatorColor] colorWithAlphaComponent:0.14].CGColor;
    self.segmentContainerView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.segmentContainerView.layer.shadowOpacity = 0.07;
    self.segmentContainerView.layer.shadowRadius = 18.0;
    self.segmentContainerView.layer.shadowOffset = CGSizeMake(0, 8);

    self.segmentSelectionView.backgroundColor = accentColor;
    self.segmentSelectionView.layer.cornerRadius = 20.0;
    self.segmentSelectionView.layer.shadowColor = accentColor.CGColor;
    self.segmentSelectionView.layer.shadowOpacity = 0.18;
    self.segmentSelectionView.layer.shadowRadius = 12.0;
    self.segmentSelectionView.layer.shadowOffset = CGSizeMake(0, 5);

    [self pp_updateSegmentButtonStates];
    [self pp_layoutSelectionPillAnimated:NO];
}

- (void)didTapBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self pp_applyPremiumSegmentedStyle];
    }
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

- (void)pp_segmentButtonTapped:(UIButton *)sender {
    [self pp_showTabAtIndex:(NSUInteger)sender.tag];
}

- (void)pp_showTabAtIndex:(NSUInteger)index {
    if (index >= self.childControllers.count) return;
    if (index == self.selectedIndex && self.childControllers[index].parentViewController == self) {
        [self pp_updateSegmentButtonStates];
        [self pp_layoutSelectionPillAnimated:YES];
        return;
    }

    UIViewController *previousVC = (self.selectedIndex < self.childControllers.count)
        ? self.childControllers[self.selectedIndex]
        : nil;
    UIViewController *nextVC = self.childControllers[index];
    BOOL movesForward = index > self.selectedIndex;

    self.selectedIndex = index;
    [self pp_updateSegmentButtonStates];
    [self pp_layoutSelectionPillAnimated:YES];

    if (previousVC && previousVC.parentViewController == self) {
        [previousVC willMoveToParentViewController:nil];
        void (^removePrevious)(void) = ^{
            [previousVC.view removeFromSuperview];
            [previousVC removeFromParentViewController];
        };
        if (UIAccessibilityIsReduceMotionEnabled()) {
            removePrevious();
        } else {
            [UIView animateWithDuration:PPAnimDurationFast
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                previousVC.view.alpha = 0.0;
                previousVC.view.transform = CGAffineTransformMakeTranslation(movesForward ? -12.0 : 12.0, 0.0);
            } completion:^(__unused BOOL finished) {
                removePrevious();
            }];
        }
    }

    [self addChildViewController:nextVC];
    nextVC.view.frame = self.containerView.bounds;
    nextVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    nextVC.view.alpha = UIAccessibilityIsReduceMotionEnabled() ? 1.0 : 0.0;
    nextVC.view.transform = UIAccessibilityIsReduceMotionEnabled()
        ? CGAffineTransformIdentity
        : CGAffineTransformMakeTranslation(movesForward ? 14.0 : -14.0, 0.0);
    [self.containerView addSubview:nextVC.view];
    [nextVC didMoveToParentViewController:self];

    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:PPAnimDurationNormal
                              delay:0.02
             usingSpringWithDamping:0.9
              initialSpringVelocity:0.25
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            nextVC.view.alpha = 1.0;
            nextVC.view.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nextVC.view);
}

- (void)pp_updateSegmentButtonStates {
    UIColor *accentColor = AppPrimaryClr ?: [UIColor colorWithRed:0.20 green:0.66 blue:0.48 alpha:1.0];
    UIColor *textColor = PrimaryTextClr ?: UIColor.labelColor;
    UIColor *secondaryColor = SeconderyTextClr ?: UIColor.secondaryLabelColor;

    [self.segmentButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger idx, BOOL *stop) {
        (void)stop;
        BOOL selected = idx == self.selectedIndex;
        UIColor *titleColor = selected ? UIColor.whiteColor : [textColor colorWithAlphaComponent:0.86];
        [button setTitleColor:titleColor forState:UIControlStateNormal];
        button.titleLabel.font = selected
            ? PPStaffManagementScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote)
            : PPStaffManagementScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
        button.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
        button.tintColor = selected ? UIColor.whiteColor : secondaryColor;
        button.backgroundColor = UIColor.clearColor;
    }];
    self.segmentSelectionView.backgroundColor = accentColor;
}

- (void)pp_layoutSelectionPillAnimated:(BOOL)animated {
    if (self.segmentButtons.count == 0 || CGRectIsEmpty(self.segmentContainerView.bounds)) return;

    CGFloat inset = 4.0;
    CGFloat itemWidth = CGRectGetWidth(self.segmentContainerView.bounds) / MAX((CGFloat)self.segmentButtons.count, 1.0);
    NSUInteger visualIndex = [Language isRTL]
        ? (self.segmentButtons.count - 1 - MIN(self.selectedIndex, self.segmentButtons.count - 1))
        : MIN(self.selectedIndex, self.segmentButtons.count - 1);
    CGRect targetFrame = CGRectMake((itemWidth * visualIndex) + inset,
                                    inset,
                                    MAX(itemWidth - (inset * 2.0), 0.0),
                                    CGRectGetHeight(self.segmentContainerView.bounds) - (inset * 2.0));

    void (^changes)(void) = ^{
        self.segmentSelectionView.frame = targetFrame;
    };

    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.28
                              delay:0.0
             usingSpringWithDamping:0.86
              initialSpringVelocity:0.35
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

@end
