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
static CGFloat const PPStaffManagementSelectionRailHeight = PPSpaceXXS;

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
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *segmentContainerView;
@property (nonatomic, strong) UIView *segmentRailView;
@property (nonatomic, strong) UIView *segmentSelectionView;
@property (nonatomic, strong) UIStackView *segmentStackView;
@property (nonatomic, copy) NSArray<UIButton *> *segmentButtons;
@property (nonatomic, strong) NSLayoutConstraint *segmentHeightConstraint;
@property (nonatomic, assign) BOOL isTransitioningTabs;

@end

@implementation PPStaffManagementViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Staff_Management");
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.selectedIndex = 0;

    [self pp_buildTopBar];
    [self pp_buildSegmentedControl];
    [self pp_buildContainer];
    [self pp_buildChildControllers];
    [self pp_refreshAccessState];
    [self pp_showTabAtIndex:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!PPCommandCenterNavigationIsManaged(self.navigationController)) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
    [self pp_refreshAccessState];
    [self pp_updateBackButtonVisibility];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (!PPCommandCenterNavigationIsManaged(self.navigationController)) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_layoutSelectionRailAnimated:NO];
}

#pragma mark - Build

- (void)pp_buildTopBar {
    self.topBarView = [UIView new];
    self.topBarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.topBarView.backgroundColor = [UIColor ppBackground];
    self.topBarView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:self.topBarView];

    // MARK: - Top Nav Row
    UIView *navRow = [UIView new];
    navRow.translatesAutoresizingMaskIntoConstraints = NO;
    navRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.topBarView addSubview:navRow];

    self.backButton = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(didTapBack)];
    [navRow addSubview:self.backButton];

    // MARK: - Eyebrow Label
    UILabel *eyebrowLabel = [UILabel new];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:12.0]];
    eyebrowLabel.textColor = [UIColor ppTextSecondary];
    eyebrowLabel.textAlignment = Language.alignmentForCurrentLanguage;
    eyebrowLabel.adjustsFontForContentSizeCategory = YES;
    eyebrowLabel.numberOfLines = 1;
    eyebrowLabel.text = [NSString stringWithFormat:@"%@ / %@", kLang(@"CommandCenter_Customers_Workspace"), kLang(@"Staff_Management")];
    [self.topBarView addSubview:eyebrowLabel];

    // MARK: - Title Label
    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:22.0]];
    self.titleLabel.textColor = [UIColor ppTextPrimary];
    self.titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.text = kLang(@"Staff_Management");
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.topBarView addSubview:self.titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.topBarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [navRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4.0],
        [navRow.leadingAnchor constraintEqualToAnchor:self.topBarView.leadingAnchor constant:PPSpaceBase],
        [navRow.trailingAnchor constraintEqualToAnchor:self.topBarView.trailingAnchor constant:-PPSpaceBase],
        [navRow.heightAnchor constraintEqualToConstant:44.0],

        [self.backButton.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor],
        [self.backButton.centerYAnchor constraintEqualToAnchor:navRow.centerYAnchor],
        [self.backButton.widthAnchor constraintEqualToConstant:44.0],
        [self.backButton.heightAnchor constraintEqualToConstant:44.0],

        [eyebrowLabel.topAnchor constraintEqualToAnchor:navRow.bottomAnchor constant:2.0],
        [eyebrowLabel.leadingAnchor constraintEqualToAnchor:self.topBarView.leadingAnchor constant:PPSpaceBase],
        [eyebrowLabel.trailingAnchor constraintEqualToAnchor:self.topBarView.trailingAnchor constant:-PPSpaceBase],

        [self.titleLabel.topAnchor constraintEqualToAnchor:eyebrowLabel.bottomAnchor constant:2.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.topBarView.leadingAnchor constant:PPSpaceBase],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.topBarView.trailingAnchor constant:-PPSpaceBase],
    ]];
}

- (void)pp_buildSegmentedControl {
    NSArray *titles = @[
        kLang(@"Staff_List_Tab"),
        kLang(@"Staff_Create_Tab"),
        kLang(@"Staff_Roles_Tab"),
        kLang(@"Staff_Preview_Tab")
    ];

    self.segmentContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.segmentContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentContainerView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.segmentContainerView.clipsToBounds = YES;
    [self.topBarView addSubview:self.segmentContainerView];

    self.segmentRailView = [[UIView alloc] initWithFrame:CGRectZero];
    self.segmentRailView.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentRailView.userInteractionEnabled = NO;
    [self.segmentContainerView addSubview:self.segmentRailView];

    self.segmentSelectionView = [[UIView alloc] initWithFrame:CGRectZero];
    self.segmentSelectionView.userInteractionEnabled = NO;
    [self.segmentContainerView addSubview:self.segmentSelectionView];

    self.segmentStackView = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.segmentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentStackView.axis = UILayoutConstraintAxisHorizontal;
    self.segmentStackView.alignment = UIStackViewAlignmentFill;
    self.segmentStackView.distribution = UIStackViewDistributionFillEqually;
    self.segmentStackView.spacing = 0.0;
    self.segmentStackView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.segmentContainerView addSubview:self.segmentStackView];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithCapacity:titles.count];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        (void)stop;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = idx;
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceXS, PPSpaceXS, PPSpaceSM, PPSpaceXS);
        [button setTitle:title forState:UIControlStateNormal];
        [button addTarget:self action:@selector(pp_segmentButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.accessibilityLabel = title;
        button.accessibilityTraits = UIAccessibilityTraitButton;
        [self.segmentStackView addArrangedSubview:button];
        [buttons addObject:button];
    }];
    self.segmentButtons = buttons.copy;

    self.segmentHeightConstraint = [self.segmentContainerView.heightAnchor constraintEqualToConstant:[self pp_segmentHeightForCurrentContentSize]];
    NSLayoutConstraint *segmentTop = self.titleLabel
        ? [self.segmentContainerView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:PPSpaceXS]
        : [self.segmentContainerView.topAnchor constraintEqualToAnchor:self.topBarView.topAnchor constant:PPSpaceXS];
    [NSLayoutConstraint activateConstraints:@[
        segmentTop,
        [self.segmentContainerView.leadingAnchor constraintEqualToAnchor:self.topBarView.leadingAnchor constant:PPSpaceBase],
        [self.segmentContainerView.trailingAnchor constraintEqualToAnchor:self.topBarView.trailingAnchor constant:-PPSpaceBase],
        [self.segmentContainerView.bottomAnchor constraintEqualToAnchor:self.topBarView.bottomAnchor constant:-PPSpaceXS],
        self.segmentHeightConstraint,

        [self.segmentStackView.topAnchor constraintEqualToAnchor:self.segmentContainerView.topAnchor],
        [self.segmentStackView.leadingAnchor constraintEqualToAnchor:self.segmentContainerView.leadingAnchor],
        [self.segmentStackView.trailingAnchor constraintEqualToAnchor:self.segmentContainerView.trailingAnchor],
        [self.segmentStackView.bottomAnchor constraintEqualToAnchor:self.segmentContainerView.bottomAnchor],

        [self.segmentRailView.leadingAnchor constraintEqualToAnchor:self.segmentContainerView.leadingAnchor],
        [self.segmentRailView.trailingAnchor constraintEqualToAnchor:self.segmentContainerView.trailingAnchor],
        [self.segmentRailView.bottomAnchor constraintEqualToAnchor:self.segmentContainerView.bottomAnchor],
        [self.segmentRailView.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];

    if (@available(iOS 13.0, *)) {
        self.segmentContainerView.accessibilityContainerType = UIAccessibilityContainerTypeSemanticGroup;
    }

    [self pp_applyPremiumSegmentedStyle];
}

- (void)pp_applyPremiumSegmentedStyle {
    UIColor *accentColor = [UIColor ppPrimary];
    UIColor *textColor = [UIColor ppTextPrimary];

    self.topBarView.backgroundColor = PPCommandCenterNavigationIsManaged(self.navigationController)
        ? [UIColor ppBackground]
        : [UIColor ppSurface];
    self.titleLabel.textColor = textColor;
    self.backButton.backgroundColor = UIColor.clearColor;
    self.backButton.layer.cornerRadius = 0.0;
    self.backButton.tintColor = textColor;
    self.backButton.layer.shadowOpacity = 0.0;

    self.segmentContainerView.backgroundColor = UIColor.clearColor;
    self.segmentContainerView.layer.cornerRadius = 0.0;
    self.segmentContainerView.layer.borderWidth = 0.0;
    self.segmentContainerView.layer.shadowOpacity = 0.0;
    self.segmentRailView.backgroundColor = [UIColor ppSurfaceBorder];

    self.segmentSelectionView.backgroundColor = accentColor;
    self.segmentSelectionView.layer.cornerRadius = PPStaffManagementSelectionRailHeight / 2.0;
    self.segmentSelectionView.layer.shadowOpacity = 0.0;

    [self pp_updateSegmentButtonStates];
    [self pp_layoutSelectionRailAnimated:NO];
}

- (void)didTapBack {
    UINavigationController *navigationController = self.navigationController;
    NSUInteger index = [navigationController.viewControllers indexOfObject:self];
    if (navigationController && index != NSNotFound && index > 0) {
        [navigationController popViewControllerAnimated:YES];
        return;
    }
    if (navigationController.presentingViewController) {
        [navigationController dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)pp_updateBackButtonVisibility {
    UINavigationController *navigationController = self.navigationController;
    NSUInteger index = [navigationController.viewControllers indexOfObject:self];
    BOOL canPop = navigationController && index != NSNotFound && index > 0;
    BOOL canDismiss = navigationController.presentingViewController || self.presentingViewController;
    self.backButton.hidden = !(canPop || canDismiss);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.segmentHeightConstraint.constant = [self pp_segmentHeightForCurrentContentSize];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self pp_applyPremiumSegmentedStyle];
    }
    [self pp_updateSegmentButtonStates];
    [self.view setNeedsLayout];
}

- (void)pp_buildContainer {
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.clipsToBounds = YES;
    container.backgroundColor = [UIColor ppBackground];
    [self.view addSubview:container];
    self.containerView = container;
    [NSLayoutConstraint activateConstraints:@[
        [container.topAnchor constraintEqualToAnchor:self.topBarView.bottomAnchor],
        [container.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [container.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
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
    if (!sender.enabled) return;
    [self pp_showTabAtIndex:(NSUInteger)sender.tag];
}

- (void)pp_showTabAtIndex:(NSUInteger)index {
    if (index >= self.childControllers.count) return;
    if (![self pp_tabIsEnabledAtIndex:index]) return;
    if (self.isTransitioningTabs) return;
    if (index == self.selectedIndex && self.childControllers[index].parentViewController == self) {
        [self pp_updateSegmentButtonStates];
        [self pp_layoutSelectionRailAnimated:YES];
        return;
    }

    UIViewController *previousVC = (self.selectedIndex < self.childControllers.count)
        ? self.childControllers[self.selectedIndex]
        : nil;
    UIViewController *nextVC = self.childControllers[index];
    BOOL movesForward = index > self.selectedIndex;
    CGFloat previousTranslation = movesForward ? -12.0 : 12.0;
    CGFloat nextTranslation = movesForward ? 14.0 : -14.0;
    if ([Language isRTL]) {
        previousTranslation *= -1.0;
        nextTranslation *= -1.0;
    }
    self.isTransitioningTabs = YES;

    self.selectedIndex = index;
    [self pp_updateSegmentButtonStates];
    [self pp_layoutSelectionRailAnimated:YES];

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
                previousVC.view.transform = CGAffineTransformMakeTranslation(previousTranslation, 0.0);
            } completion:^(__unused BOOL finished) {
                removePrevious();
            }];
        }
    }

    [self addChildViewController:nextVC];
    nextVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    nextVC.view.alpha = UIAccessibilityIsReduceMotionEnabled() ? 1.0 : 0.0;
    nextVC.view.transform = UIAccessibilityIsReduceMotionEnabled()
        ? CGAffineTransformIdentity
        : CGAffineTransformMakeTranslation(nextTranslation, 0.0);
    [self.containerView addSubview:nextVC.view];
    [NSLayoutConstraint activateConstraints:@[
        [nextVC.view.topAnchor constraintEqualToAnchor:self.containerView.topAnchor],
        [nextVC.view.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [nextVC.view.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [nextVC.view.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor]
    ]];
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
                         } completion:^(__unused BOOL finished) {
            self.isTransitioningTabs = NO;
        }];
    } else {
        self.isTransitioningTabs = NO;
    }
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nextVC.view);
}

- (void)pp_updateSegmentButtonStates {
    UIColor *accentColor = [UIColor ppPrimary];
    UIColor *textColor = [UIColor ppTextPrimary];
    UIColor *secondaryColor = [UIColor ppTextSecondary];
    UIColor *disabledColor = [UIColor ppTextTertiary];

    [self.segmentButtons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger idx, BOOL *stop) {
        (void)stop;
        BOOL selected = idx == self.selectedIndex;
        BOOL enabled = [self pp_tabIsEnabledAtIndex:idx];
        UIColor *titleColor = selected ? accentColor : textColor;
        button.enabled = enabled;
        [button setTitleColor:titleColor forState:UIControlStateNormal];
        [button setTitleColor:disabledColor forState:UIControlStateDisabled];
        button.titleLabel.font = selected
            ? PPStaffManagementScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote)
            : PPStaffManagementScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
        UIAccessibilityTraits traits = UIAccessibilityTraitButton;
        if (selected) traits |= UIAccessibilityTraitSelected;
        if (!enabled) traits |= UIAccessibilityTraitNotEnabled;
        button.accessibilityTraits = traits;
        button.accessibilityHint = enabled ? nil : kLang(@"StatusNoAccess");
        button.tintColor = selected ? accentColor : secondaryColor;
        button.alpha = enabled ? 1.0 : 0.62;
        button.backgroundColor = UIColor.clearColor;
    }];
    self.segmentSelectionView.backgroundColor = accentColor;
}

- (void)pp_layoutSelectionRailAnimated:(BOOL)animated {
    if (self.segmentButtons.count == 0 || CGRectIsEmpty(self.segmentContainerView.bounds)) return;

    NSUInteger selectedIndex = MIN(self.selectedIndex, self.segmentButtons.count - 1);
    UIButton *selectedButton = self.segmentButtons[selectedIndex];
    [self.segmentStackView layoutIfNeeded];
    CGRect buttonFrame = [selectedButton convertRect:selectedButton.bounds toView:self.segmentContainerView];
    CGFloat horizontalInset = MIN(PPSpaceMD, CGRectGetWidth(buttonFrame) / 4.0);
    CGRect targetFrame = CGRectMake(CGRectGetMinX(buttonFrame) + horizontalInset,
                                    CGRectGetHeight(self.segmentContainerView.bounds) - PPStaffManagementSelectionRailHeight,
                                    MAX(CGRectGetWidth(buttonFrame) - (horizontalInset * 2.0), 0.0),
                                    PPStaffManagementSelectionRailHeight);
    self.segmentSelectionView.hidden = !selectedButton.enabled;

    void (^changes)(void) = ^{
        self.segmentSelectionView.frame = targetFrame;
    };

    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:PPAnimDurationNormal
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

#pragma mark - Access

- (CGFloat)pp_segmentHeightForCurrentContentSize {
    return UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        ? PPButtonHeightLG + PPSpace4XL
        : PPButtonHeightLG;
}

- (BOOL)pp_canManageStaffRoles {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [staff hasPermission:kStaffPermStaffManage];
}

- (BOOL)pp_canMutateStaffMembers {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [staff hasPermission:kStaffPermStaffManage];
}

- (BOOL)pp_tabIsEnabledAtIndex:(NSUInteger)index {
    if (index >= PPStaffManagementTabCount) return NO;
    if (index == 0) return [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermStaffView];
    if (index == 1) return [self pp_canMutateStaffMembers];
    if (index == 2) return [self pp_canManageStaffRoles];
    if (index == 3) return [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermStaffView];
    return YES;
}

- (void)pp_refreshAccessState {
    if (self.childControllers.count == PPStaffManagementTabCount &&
        ![self pp_tabIsEnabledAtIndex:self.selectedIndex]) {
        [self pp_showTabAtIndex:0];
        return;
    }
    [self pp_updateSegmentButtonStates];
    [self pp_layoutSelectionRailAnimated:NO];
}

@end
