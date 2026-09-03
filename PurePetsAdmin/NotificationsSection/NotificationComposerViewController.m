//
//  NotificationComposerViewController.m
//  PurePetsAdmin
//

#import "NotificationComposerViewController.h"
#import "PPAlertHelper.h"
#import "Language.h"
#import "PPPickOptionCell.h"
#import "PPNotificationsManager.h"
#import "PPSelectUsersViewController.h"
#import "PPDesignTokens.h"
#import "Styling.h"
#import "UserManager.h"
#import "UIViewController+PPNavBar.h"
#import <math.h>

typedef NS_ENUM(NSInteger, PPNotificationTargetKind) {
    PPNotificationTargetKindNone = 0,
    PPNotificationTargetKindSpecificUsers,
    PPNotificationTargetKindAllUsers,
    PPNotificationTargetKindAdmins,
    PPNotificationTargetKindEveryone
};

static inline NSString *PPNotifTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [((NSString *)value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static inline NSString *PPNotifFirstNonEmpty(NSArray<NSString *> *candidates) {
    for (NSString *candidate in candidates) {
        NSString *safe = PPNotifTrimmedString(candidate);
        if (safe.length > 0) return safe;
    }
    return @"";
}


static NSString * const kRowTitleTag = @"title";
static NSString * const kRowBodyTag = @"body";
static NSString * const kRowTypeTag = @"type";

static NSString * const kTargetNoneTag = @"t_none";
static NSString * const kTargetSpecificTag = @"t_specific";
static NSString * const kTargetAllUsersTag = @"t_allusers";
static NSString * const kTargetAdminsTag = @"t_admins";
static NSString * const kTargetEveryoneTag = @"t_everyone";

static NSString * const kSpecificPickRowTag = @"specific_users_picker";
static NSString * const kSpecificSummaryRowTag = @"specific_users_summary";
static NSString * const kSpecificUserRowPrefix = @"specific_user_row_";
static const NSUInteger kPPNotificationComposerRecipientLimit = 500;

typedef NS_ENUM(NSInteger, PPNotificationComposerDispatchState) {
    PPNotificationComposerDispatchStateDraft = 0,
    PPNotificationComposerDispatchStateSending,
    PPNotificationComposerDispatchStateSuccess,
    PPNotificationComposerDispatchStateWarning,
    PPNotificationComposerDispatchStateError
};

static UIFont *PPNotificationComposerScaledFont(UIFont *baseFont, UIFontTextStyle textStyle) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
    }
    return baseFont;
}

@interface NotificationComposerViewController () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) XLFormSectionDescriptor *specificUsersSection;
@property (nonatomic, assign) BOOL isSending;
@property (nonatomic, strong) UIButton *navigationSendButton;
@property (nonatomic, strong) UIView *dispatchHeader;
@property (nonatomic, strong) UILabel *dispatchContextLabel;
@property (nonatomic, strong) UILabel *dispatchTitleLabel;
@property (nonatomic, strong) UILabel *dispatchSubtitleLabel;
@property (nonatomic, strong) UIView *dispatchStateBanner;
@property (nonatomic, strong) UIImageView *dispatchStateIcon;
@property (nonatomic, strong) UIActivityIndicatorView *dispatchStateSpinner;
@property (nonatomic, strong) UILabel *dispatchStateLabel;
@property (nonatomic, assign) CGFloat dispatchHeaderMeasuredWidth;
@property (nonatomic, strong) UIView *sendDock;
@property (nonatomic, strong) UILabel *sendDockStatusLabel;
@property (nonatomic, strong) UIButton *sendDockButton;
@property (nonatomic, strong) NSLayoutConstraint *sendDockBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sendDockHeightConstraint;
@property (nonatomic, assign) UIEdgeInsets baseTableContentInset;
@property (nonatomic, assign) CGFloat keyboardOverlap;
@property (nonatomic, copy) NSString *dispatchOutcomeMessage;
@property (nonatomic, assign) PPNotificationComposerDispatchState dispatchOutcomeState;
@property (nonatomic, copy) NSString *currentDispatchID;
@property (nonatomic, strong) UIView *composerNavRow;
@end

@implementation NotificationComposerViewController

- (instancetype)init {
    XLFormDescriptor *form = [self buildForm];
    return [super initWithForm:form style:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.selectedUIDs = [NSMutableArray array];
    self.cachedUsers = @[];
    self.dispatchOutcomeState = PPNotificationComposerDispatchStateDraft;
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (!self.navigationSendButton) {
        self.navigationSendButton = [self pp_ButtonWithSystemName:@"paperplane.fill" action:@selector(onSend)];
        self.navigationSendButton.accessibilityLabel = kLang(@"NotificationComposer_Action_Send");
        self.navigationSendButton.accessibilityIdentifier = @"admin-notification-composer-send";
    }

    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.backgroundColor = [UIColor ppBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.baseTableContentInset = UIEdgeInsetsMake(PPSpaceSM, 0, PPSpaceSM, 0);
    self.tableView.contentInset = self.baseTableContentInset;
    [self pp_setupComposerNavBar];
    [self pp_setupDispatchHeader];
    [self pp_setupSendDock];
    [self pp_registerKeyboardNotifications];
    [self updateSpecificUsersSummary];
    [self prefetchUsers];
    [self pp_refreshDispatchStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    [self pp_refreshDispatchStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didTapBack {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)pp_setupComposerNavBar {
    if (self.composerNavRow) return;

    UIView *navRow = [[UIView alloc] init];
    navRow.translatesAutoresizingMaskIntoConstraints = NO;
    navRow.backgroundColor = [UIColor ppBackground];
    navRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIButton *backBtn = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(didTapBack)];
    backBtn.accessibilityIdentifier = @"admin-notification-composer-back";
    [navRow addSubview:backBtn];

    self.navigationSendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [navRow addSubview:self.navigationSendButton];

    UIView *hairline = [[UIView alloc] init];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = [[UIColor ppSeparator] colorWithAlphaComponent:0.4];
    [navRow addSubview:hairline];

    [self.view addSubview:navRow];

    [NSLayoutConstraint activateConstraints:@[
        [navRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [navRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [navRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [navRow.heightAnchor constraintEqualToConstant:50],

        [backBtn.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor constant:16],
        [backBtn.centerYAnchor constraintEqualToAnchor:navRow.centerYAnchor],
        [backBtn.widthAnchor constraintEqualToConstant:44],
        [backBtn.heightAnchor constraintEqualToConstant:44],

        [self.navigationSendButton.trailingAnchor constraintEqualToAnchor:navRow.trailingAnchor constant:-16],
        [self.navigationSendButton.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
        [self.navigationSendButton.heightAnchor constraintGreaterThanOrEqualToConstant:44],

        [hairline.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:navRow.trailingAnchor],
        [hairline.bottomAnchor constraintEqualToAnchor:navRow.bottomAnchor],
        [hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];

    self.composerNavRow = navRow;

    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSLayoutConstraint *c in self.view.constraints) {
        if ((c.firstItem == self.tableView && c.firstAttribute == NSLayoutAttributeTop) ||
            (c.secondItem == self.tableView && c.secondAttribute == NSLayoutAttributeTop)) {
            [self.view removeConstraint:c];
            break;
        }
    }
    [self.tableView.topAnchor constraintEqualToAnchor:navRow.bottomAnchor].active = YES;
    [self.view bringSubviewToFront:navRow];
}

- (void)pp_setupDispatchHeader {
    if (self.dispatchHeader) return;

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = PPSpaceSM;
    stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:stack];

    self.dispatchContextLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dispatchContextLabel.font = [Styling fontBold:12];
    self.dispatchContextLabel.textColor = [UIColor ppTextSecondary];
    self.dispatchContextLabel.text = kLang(@"NotificationComposer_Eyebrow");
    self.dispatchContextLabel.adjustsFontForContentSizeCategory = YES;
    self.dispatchContextLabel.textAlignment = NSTextAlignmentNatural;
    self.dispatchContextLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.dispatchTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dispatchTitleLabel.font = [Styling fontBold:22];
    self.dispatchTitleLabel.textColor = [UIColor ppTextPrimary];
    self.dispatchTitleLabel.text = kLang(@"Compose Notification");
    self.dispatchTitleLabel.numberOfLines = 0;
    self.dispatchTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.dispatchTitleLabel.textAlignment = NSTextAlignmentNatural;
    self.dispatchTitleLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.dispatchTitleLabel.accessibilityTraits = UIAccessibilityTraitHeader;

    self.dispatchSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dispatchSubtitleLabel.font = PPNotificationComposerScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
    self.dispatchSubtitleLabel.textColor = [UIColor ppTextSecondary];
    self.dispatchSubtitleLabel.text = kLang(@"NotificationComposer_Subtitle");
    self.dispatchSubtitleLabel.numberOfLines = 0;
    self.dispatchSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.dispatchSubtitleLabel.textAlignment = NSTextAlignmentNatural;
    self.dispatchSubtitleLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.dispatchStateBanner = [[UIView alloc] initWithFrame:CGRectZero];
    self.dispatchStateBanner.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(self.dispatchStateBanner, PPCornerSmall);
    self.dispatchStateBanner.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.dispatchStateBanner.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stateStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stateStack.translatesAutoresizingMaskIntoConstraints = NO;
    stateStack.axis = UILayoutConstraintAxisHorizontal;
    stateStack.alignment = UIStackViewAlignmentCenter;
    stateStack.spacing = PPSpaceSM;
    stateStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.dispatchStateBanner addSubview:stateStack];
    [NSLayoutConstraint activateConstraints:@[
        [stateStack.topAnchor constraintEqualToAnchor:self.dispatchStateBanner.topAnchor constant:PPSpaceSM],
        [stateStack.leadingAnchor constraintEqualToAnchor:self.dispatchStateBanner.leadingAnchor constant:PPSpaceSM],
        [stateStack.trailingAnchor constraintEqualToAnchor:self.dispatchStateBanner.trailingAnchor constant:-PPSpaceSM],
        [stateStack.bottomAnchor constraintEqualToAnchor:self.dispatchStateBanner.bottomAnchor constant:-PPSpaceSM]
    ]];

    self.dispatchStateIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.dispatchStateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.dispatchStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    [stateStack addArrangedSubview:self.dispatchStateIcon];
    [self.dispatchStateIcon.widthAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;
    [self.dispatchStateIcon.heightAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;

    self.dispatchStateSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.dispatchStateSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.dispatchStateSpinner.hidesWhenStopped = YES;
    [stateStack addArrangedSubview:self.dispatchStateSpinner];
    [self.dispatchStateSpinner.widthAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;
    [self.dispatchStateSpinner.heightAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;

    self.dispatchStateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dispatchStateLabel.font = PPNotificationComposerScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
    self.dispatchStateLabel.numberOfLines = 0;
    self.dispatchStateLabel.adjustsFontForContentSizeCategory = YES;
    self.dispatchStateLabel.textAlignment = NSTextAlignmentNatural;
    self.dispatchStateLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.dispatchStateLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [stateStack addArrangedSubview:self.dispatchStateLabel];

    [stack addArrangedSubview:self.dispatchContextLabel];
    [stack addArrangedSubview:self.dispatchTitleLabel];
    [stack addArrangedSubview:self.dispatchSubtitleLabel];
    [stack addArrangedSubview:self.dispatchStateBanner];

    UIView *rule = [[UIView alloc] initWithFrame:CGRectZero];
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    rule.backgroundColor = [UIColor ppSeparator];
    [stack addArrangedSubview:rule];
    [rule.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceSM],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceSM]
    ]];

    self.dispatchHeader = header;
    self.tableView.tableHeaderView = header;
}

- (void)pp_updateDispatchHeaderFrame {
    if (!self.dispatchHeader || !self.tableView) return;

    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;
    CGRect frame = self.dispatchHeader.frame;
    if (fabs(self.dispatchHeaderMeasuredWidth - width) < 0.5 && frame.size.height > 0.0) return;

    self.dispatchHeader.frame = CGRectMake(0.0, 0.0, width, 1.0);
    [self.dispatchHeader setNeedsLayout];
    [self.dispatchHeader layoutIfNeeded];
    CGSize fittingSize = [self.dispatchHeader systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                                withHorizontalFittingPriority:UILayoutPriorityRequired
                                                      verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.dispatchHeader.frame = CGRectMake(0.0, 0.0, width, MAX(PPSpace4XL, ceil(fittingSize.height)));
    self.dispatchHeaderMeasuredWidth = width;
    self.tableView.tableHeaderView = self.dispatchHeader;
}

- (void)pp_setupSendDock {
    if (self.sendDock) return;

    UIView *dock = [[UIView alloc] initWithFrame:CGRectZero];
    dock.translatesAutoresizingMaskIntoConstraints = NO;
    dock.backgroundColor = [UIColor ppSurface];
    dock.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyElevatedShadow(dock);
    [self.view addSubview:dock];

    UIView *hairline = [[UIView alloc] initWithFrame:CGRectZero];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = [UIColor ppSeparator];
    [dock addSubview:hairline];

    self.sendDockStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.sendDockStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendDockStatusLabel.font = PPNotificationComposerScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
    self.sendDockStatusLabel.textColor = [UIColor ppTextSecondary];
    self.sendDockStatusLabel.numberOfLines = 2;
    self.sendDockStatusLabel.adjustsFontForContentSizeCategory = YES;
    self.sendDockStatusLabel.textAlignment = NSTextAlignmentNatural;
    self.sendDockStatusLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [dock addSubview:self.sendDockStatusLabel];

    self.sendDockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendDockButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sendDockButton.accessibilityLabel = kLang(@"NotificationComposer_Action_Send");
    self.sendDockButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.sendDockButton addTarget:self action:@selector(onSend) forControlEvents:UIControlEventTouchUpInside];
    [dock addSubview:self.sendDockButton];

    self.sendDockHeightConstraint = [dock.heightAnchor constraintEqualToConstant:PPButtonHeightLG + PPSpaceBase];
    [NSLayoutConstraint activateConstraints:@[
        [dock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.sendDockHeightConstraint,
        [hairline.topAnchor constraintEqualToAnchor:dock.topAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor],
        [hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [self.sendDockButton.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-PPScreenMargin],
        [self.sendDockButton.centerYAnchor constraintEqualToAnchor:dock.centerYAnchor],
        [self.sendDockButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightLG],
        [self.sendDockStatusLabel.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:PPScreenMargin],
        [self.sendDockStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.sendDockButton.leadingAnchor constant:-PPSpaceMD],
        [self.sendDockStatusLabel.centerYAnchor constraintEqualToAnchor:self.sendDockButton.centerYAnchor]
    ]];

    self.sendDock = dock;
    self.sendDockBottomConstraint = [dock.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];
    self.sendDockBottomConstraint.active = YES;
}

- (void)pp_applySendDockButtonConfiguration {
    NSString *title = self.isSending ? kLang(@"NotificationComposer_Action_Sending") : kLang(@"NotificationComposer_Action_Send");
    self.sendDockButton.accessibilityLabel = title;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
        configuration.baseBackgroundColor = [UIColor ppPrimary];
        configuration.baseForegroundColor = PPOnPrimaryColor();
        configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);
        configuration.title = title;
        configuration.image = [UIImage systemImageNamed:@"paperplane.fill"];
        configuration.imagePadding = PPSpaceSM;
        configuration.showsActivityIndicator = self.isSending;
        self.sendDockButton.configuration = configuration;
    } else {
        [self.sendDockButton setTitle:title forState:UIControlStateNormal];
        self.sendDockButton.backgroundColor = [UIColor ppPrimary];
        [self.sendDockButton setTitleColor:PPOnPrimaryColor() forState:UIControlStateNormal];
        PPApplyContinuousCorners(self.sendDockButton, PPCornerSmall);
        self.sendDockButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);
    }
}

- (void)pp_registerKeyboardNotifications {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(pp_keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(pp_keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)pp_keyboardWillChange:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardFrameInView = [self.view convertRect:endFrame fromView:nil];
    BOOL isHiding = [notification.name isEqualToString:UIKeyboardWillHideNotification];
    self.keyboardOverlap = (isHiding || CGRectIsEmpty(endFrame))
        ? 0.0
        : MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboardFrameInView));

    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16) | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:duration delay:0.0 options:options animations:^{
        self.sendDockBottomConstraint.constant = -self.keyboardOverlap;
        [self.view layoutIfNeeded];
        [self pp_updateTableInsets];
    } completion:nil];
}

- (void)pp_updateTableInsets {
    if (!self.tableView) return;
    UIEdgeInsets insets = self.baseTableContentInset;
    insets.bottom += CGRectGetHeight(self.sendDock.bounds) + PPSpaceLG + self.keyboardOverlap;
    self.tableView.contentInset = insets;
    self.tableView.scrollIndicatorInsets = insets;
}

- (void)pp_clearDispatchOutcome {
    self.dispatchOutcomeMessage = nil;
    self.dispatchOutcomeState = PPNotificationComposerDispatchStateDraft;
    self.currentDispatchID = nil;
}

- (void)pp_refreshDispatchStatus {
    PPNotificationComposerDispatchState state = self.dispatchOutcomeState;
    NSString *message = self.dispatchOutcomeMessage;
    if (self.isSending) {
        state = PPNotificationComposerDispatchStateSending;
        message = kLang(@"NotificationComposer_Status_Sending");
    } else if (message.length == 0) {
        PPNotificationTargetKind target = [self currentTargetKind];
        if (target == PPNotificationTargetKindNone) {
            message = kLang(@"NotificationComposer_Status_SelectTarget");
        } else if (target == PPNotificationTargetKindSpecificUsers) {
            message = self.selectedUIDs.count > 0
                ? [NSString stringWithFormat:kLang(@"NotificationComposer_Status_RecipientsSelected"), (long)self.selectedUIDs.count]
                : kLang(@"NotificationComposer_Status_SelectRecipients");
        } else {
            message = kLang(@"NotificationComposer_Status_AudienceSelected");
        }
        state = PPNotificationComposerDispatchStateDraft;
    }
    [self pp_applyDispatchState:state message:message];
}

- (void)pp_applyDispatchState:(PPNotificationComposerDispatchState)state message:(NSString *)message {
    UIColor *tone = [UIColor ppTextSecondary];
    UIColor *background = [[UIColor ppSecondarySurface] colorWithAlphaComponent:0.72];
    UIImage *icon = [UIImage systemImageNamed:@"square.and.pencil"];
    BOOL showsSpinner = NO;

    switch (state) {
        case PPNotificationComposerDispatchStateSending:
            tone = [UIColor ppInfo];
            background = [[UIColor ppInfo] colorWithAlphaComponent:0.08];
            showsSpinner = YES;
            break;
        case PPNotificationComposerDispatchStateSuccess:
            tone = [UIColor ppSuccess];
            background = [[UIColor ppSuccess] colorWithAlphaComponent:0.08];
            icon = [UIImage systemImageNamed:@"checkmark.circle.fill"];
            break;
        case PPNotificationComposerDispatchStateWarning:
            tone = [UIColor ppWarning];
            background = [[UIColor ppWarning] colorWithAlphaComponent:0.10];
            icon = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
            break;
        case PPNotificationComposerDispatchStateError:
            tone = [UIColor ppError];
            background = [[UIColor ppError] colorWithAlphaComponent:0.08];
            icon = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
            break;
        case PPNotificationComposerDispatchStateDraft:
        default:
            break;
    }

    self.dispatchStateBanner.backgroundColor = background;
    self.dispatchStateBanner.layer.borderColor = [tone colorWithAlphaComponent:0.24].CGColor;
    self.dispatchStateLabel.text = message;
    self.dispatchStateLabel.textColor = tone;
    self.dispatchStateLabel.accessibilityLabel = message;
    self.dispatchStateIcon.image = icon;
    self.dispatchStateIcon.tintColor = tone;
    self.dispatchStateIcon.hidden = showsSpinner;
    self.dispatchStateSpinner.color = tone;
    if (showsSpinner) {
        [self.dispatchStateSpinner startAnimating];
    } else {
        [self.dispatchStateSpinner stopAnimating];
    }

    self.sendDockStatusLabel.text = message;
    self.sendDockStatusLabel.textColor = tone;
    self.sendDockButton.enabled = !self.isSending;
    self.navigationSendButton.enabled = !self.isSending;
    self.navigationItem.rightBarButtonItem.enabled = !self.isSending;
    self.tableView.userInteractionEnabled = !self.isSending;
    [self pp_applySendDockButtonConfiguration];
    self.dispatchHeaderMeasuredWidth = 0.0;
    [self pp_updateDispatchHeaderFrame];
    [self pp_updateTableInsets];
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)pp_formDidChange {
    if (self.isSending) return;
    [self pp_clearDispatchOutcome];
    [self pp_refreshDispatchStatus];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    (void)presentationController;
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.sendDockHeightConstraint.constant = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        ? PPButtonHeightLG + PPSpaceXL
        : PPButtonHeightLG + PPSpaceBase;
    [self pp_updateDispatchHeaderFrame];
    [self pp_updateTableInsets];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) {
        self.dispatchContextLabel.font = PPNotificationComposerScaledFont([Styling fontBold:PPFontCaption1], UIFontTextStyleCaption1);
        self.dispatchTitleLabel.font = PPNotificationComposerScaledFont([Styling fontBold:PPFontTitle2], UIFontTextStyleTitle2);
        self.dispatchSubtitleLabel.font = PPNotificationComposerScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
        self.dispatchStateLabel.font = PPNotificationComposerScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
        self.sendDockStatusLabel.font = PPNotificationComposerScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
        self.dispatchHeaderMeasuredWidth = 0.0;
        [self.tableView reloadData];
        [self pp_refreshDispatchStatus];
    }
}

#pragma mark - Form

- (XLFormDescriptor *)buildForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    XLFormSectionDescriptor *content = [XLFormSectionDescriptor formSection];
    [form addFormSection:content];

    XLFormRowDescriptor *title =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowTitleTag rowType:XLFormRowDescriptorTypeText title:kLang(@"Title")];
    title.required = YES;
    __weak typeof(self) weakSelf = self;
    title.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *rowDescriptor) {
        [weakSelf pp_formDidChange];
    };
    [Styling applyGlobalStyleToRow:title];
    [content addFormRow:title];

    XLFormRowDescriptor *body =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowBodyTag rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Body")];
    body.required = YES;
    body.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *rowDescriptor) {
        [weakSelf pp_formDidChange];
    };
    [Styling applyGlobalStyleToRow:body];
    [content addFormRow:body];

    XLFormRowDescriptor *type =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowTypeTag rowType:XLFormRowDescriptorTypeSelectorActionSheet title:kLang(@"Type")];
    type.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeGeneral) displayText:kLang(@"General")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeOrder) displayText:kLang(@"Order")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeAdReview) displayText:kLang(@"Ad Review")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeWarning) displayText:kLang(@"Warning")]
    ];
    type.value = type.selectorOptions.firstObject;
    type.height = 52.0;
    type.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *rowDescriptor) {
        [weakSelf pp_formDidChange];
    };
    [Styling applyGlobalStyleToRow:type];
    [content addFormRow:type];

    XLFormSectionDescriptor *target = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"NotificationComposer_Target")];
    [form addFormSection:target];

    [target addFormRow:[self targetRowWithTag:kTargetNoneTag title:kLang(@"Nobody") subtitle:kLang(@"NotificationComposer_Target_None_Subtitle") selected:YES]];
    [target addFormRow:[self targetRowWithTag:kTargetSpecificTag title:kLang(@"Specific Users") subtitle:kLang(@"NotificationComposer_Target_Specific_Subtitle") selected:NO]];
    [target addFormRow:[self targetRowWithTag:kTargetAllUsersTag title:kLang(@"All Users") subtitle:kLang(@"NotificationComposer_Target_AllUsers_Subtitle") selected:NO]];
    [target addFormRow:[self targetRowWithTag:kTargetAdminsTag title:kLang(@"NotificationComposer_Admins") subtitle:kLang(@"NotificationComposer_Target_Admins_Subtitle") selected:NO]];
    [target addFormRow:[self targetRowWithTag:kTargetEveryoneTag title:kLang(@"NotificationComposer_Everyone") subtitle:kLang(@"NotificationComposer_Target_Everyone_Subtitle") selected:NO]];

    self.specificUsersSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Specific Users")];

    XLFormRowDescriptor *pickUsers =
    [XLFormRowDescriptor formRowDescriptorWithTag:kSpecificPickRowTag rowType:XLFormRowDescriptorTypePickOption title:kLang(@"Select User")];
    pickUsers.height = 60.0;
    pickUsers.cellConfig[@"onPickTap"] = ^(XLFormRowDescriptor *sender) {
        __strong typeof(weakSelf) self = weakSelf;
        [self presentSpecificUserPickerForRow:sender];
    };
    [self.specificUsersSection addFormRow:pickUsers];

    return form;
}

- (XLFormRowDescriptor *)targetRowWithTag:(NSString *)tag
                                    title:(NSString *)title
                                 subtitle:(NSString *)subtitle
                                 selected:(BOOL)selected {
    XLFormRowDescriptor *row =
    [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:XLFormRowDescriptorTypeBooleanCheck title:title];
    row.value = @(selected);
    row.cellStyle = UITableViewCellStyleSubtitle;
    row.cellConfigAtConfigure[@"detailTextLabel.text"] = subtitle ?: @"";
    row.cellConfigAtConfigure[@"detailTextLabel.numberOfLines"] = @2;
    __weak typeof(self) weakSelf = self;
    row.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor * _Nonnull rowDescriptor) {
        __strong typeof(weakSelf) self = weakSelf;
        [self onTargetToggleChanged:rowDescriptor];
    };
    [Styling applyGlobalStyleToRow:row];
    return row;
}

#pragma mark - Target state

- (void)onTargetToggleChanged:(XLFormRowDescriptor *)rowDescriptor {
    if (self.isUpdatingTargets) return;

    self.isUpdatingTargets = YES;
    NSArray<NSString *> *allTargetTags = @[kTargetNoneTag, kTargetSpecificTag, kTargetAllUsersTag, kTargetAdminsTag, kTargetEveryoneTag];
    BOOL changedOn = [rowDescriptor.value boolValue];

    if (changedOn) {
        for (NSString *tag in allTargetTags) {
            if ([tag isEqualToString:rowDescriptor.tag]) continue;
            XLFormRowDescriptor *row = [self.form formRowWithTag:tag];
            row.value = @NO;
            [self updateFormRow:row];
        }
    } else {
        BOOL anyOn = NO;
        for (NSString *tag in allTargetTags) {
            XLFormRowDescriptor *row = [self.form formRowWithTag:tag];
            if ([row.value boolValue]) {
                anyOn = YES;
                break;
            }
        }
        if (!anyOn) {
            XLFormRowDescriptor *noneRow = [self.form formRowWithTag:kTargetNoneTag];
            noneRow.value = @YES;
            [self updateFormRow:noneRow];
        }
    }

    BOOL showSpecific = [[[self.form formRowWithTag:kTargetSpecificTag] value] boolValue];
    [self toggleSpecificUsersSection:showSpecific];
    [self pp_clearDispatchOutcome];
    [self updateSpecificUsersSummary];

    self.isUpdatingTargets = NO;
}

- (void)toggleSpecificUsersSection:(BOOL)show {
    BOOL isShown = [self.form.formSections containsObject:self.specificUsersSection];
    if (show == isShown) return;

    if (show) {
        [self.form addFormSection:self.specificUsersSection atIndex:self.form.formSections.count];
    } else {
        [self.form removeFormSection:self.specificUsersSection];
    }
    [self.tableView reloadData];
}

- (PPNotificationTargetKind)currentTargetKind {
    if ([[[self.form formRowWithTag:kTargetSpecificTag] value] boolValue]) return PPNotificationTargetKindSpecificUsers;
    if ([[[self.form formRowWithTag:kTargetAllUsersTag] value] boolValue]) return PPNotificationTargetKindAllUsers;
    if ([[[self.form formRowWithTag:kTargetAdminsTag] value] boolValue]) return PPNotificationTargetKindAdmins;
    if ([[[self.form formRowWithTag:kTargetEveryoneTag] value] boolValue]) return PPNotificationTargetKindEveryone;
    return PPNotificationTargetKindNone;
}

#pragma mark - Users

- (void)prefetchUsers {
    __weak typeof(self) weakSelf = self;
    [[UserManager shared] fetchAllUsersWithCompletion:^(NSArray<UserModel *> * _Nullable users, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error) return;
        self.cachedUsers = users ?: @[];
        [self updateSpecificUsersSummary];
    }];
}

- (void)presentSpecificUserPickerForRow:(XLFormRowDescriptor *)row {
    if (self.cachedUsers.count == 0) {
        __weak typeof(self) weakSelf = self;
        [[UserManager shared] fetchAllUsersWithCompletion:^(NSArray<UserModel *> * _Nullable users, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error) {
                [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription];
                return;
            }
            self.cachedUsers = users ?: @[];
            [self showSpecificUserPickerForRow:row ?: [self.form formRowWithTag:kSpecificPickRowTag]];
        }];
        return;
    }

    [self showSpecificUserPickerForRow:row ?: [self.form formRowWithTag:kSpecificPickRowTag]];
}

- (void)showSpecificUserPickerForRow:(XLFormRowDescriptor *)row {
    (void)row;
    NSArray *options = self.cachedUsers ?: @[];
    if (options.count == 0) {
        [PPAlertHelper showInfoIn:self
                           title:kLang(@"Info")
                        subtitle:kLang(@"NoUsersFound")];
        return;
    }

    __weak typeof(self) weakSelf = self;
    PPSelectUsersViewController *vc =
    [[PPSelectUsersViewController alloc] initWithCompletion:^(id selected) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSArray *selectedUsers = @[];
        if ([selected isKindOfClass:[NSArray class]]) {
            selectedUsers = (NSArray *)selected;
        } else if ([selected isKindOfClass:[UserModel class]]) {
            selectedUsers = @[selected];
        }

        NSMutableOrderedSet<NSString *> *uids = [NSMutableOrderedSet orderedSet];
        for (id item in selectedUsers) {
            if (![item isKindOfClass:[UserModel class]]) continue;
            UserModel *user = (UserModel *)item;
            NSString *uid = PPNotifFirstNonEmpty(@[user.uid, user.ID]);
            if (uid.length > 0) [uids addObject:uid];
        }

        self.selectedUIDs = [uids.array mutableCopy];
        [self pp_clearDispatchOutcome];
        [self updateSpecificUsersSummary];
    }];

    vc.allOptions = options;
    vc.filteredOptions = options;
    vc.preselectedOptionIDs = self.selectedUIDs.copy;
    vc.rowDescriptor = [self.form formRowWithTag:kSpecificPickRowTag];
    vc.parentForm = self;
    vc.imageLoaded = NO;
    vc.presentationStyle = PPSelectOptionPresentationSheet;
    vc.title = kLang(@"Select User");

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    nav.modalPresentationCapturesStatusBarAppearance = YES;
    nav.view.backgroundColor = [UIColor ppSurface];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[
                [UISheetPresentationControllerDetent mediumDetent],
                [UISheetPresentationControllerDetent largeDetent]
            ];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 26.0;
            sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
        }
    }
    // The picker owns its own navigation chrome and sheet dismissal. Pushing
    // the bare controller from a composer already inside a navigation stack
    // drops that chrome and can strand the user on a duplicate route.
    if (self.presentedViewController) return;
    [self presentViewController:nav animated:YES completion:^{
        nav.presentationController.delegate = self;
        PPCommandCenterNavigationItemsDidChange(self);
    }];
}

- (void)updateSpecificUsersSummary {
    XLFormRowDescriptor *pickerRow = [self.form formRowWithTag:kSpecificPickRowTag];
    if (!pickerRow || !self.specificUsersSection) return;

    NSMutableArray<XLFormRowDescriptor *> *rowsToRemove = [NSMutableArray array];
    for (XLFormRowDescriptor *row in self.specificUsersSection.formRows ?: @[]) {
        if ([row.tag isEqualToString:kSpecificSummaryRowTag] || [self isSpecificUserRowTag:row.tag]) {
            [rowsToRemove addObject:row];
        }
    }
    for (XLFormRowDescriptor *row in rowsToRemove) {
        [self.specificUsersSection removeFormRow:row];
    }

    self.selectedUIDs = [[self normalizedSelectedUIDs] mutableCopy];
    NSUInteger selectedCount = self.selectedUIDs.count;

    pickerRow.height = 60.0;
    pickerRow.cellConfig[@"showPickButton"] = @YES;
    pickerRow.cellConfig[@"showOptionImage"] = @YES;
    pickerRow.title = kLang(@"Select User");

    if (selectedCount == 0) {
        pickerRow.value = nil;
    } else if (selectedCount == 1) {
        UserModel *singleUser = [self userForUID:self.selectedUIDs.firstObject];
        pickerRow.value = singleUser;
        if (!singleUser) {
            pickerRow.title = [NSString stringWithFormat:@"%@ (1)", kLang(@"Select User")];
        }
    } else {
        pickerRow.value = nil;
        pickerRow.title = [NSString stringWithFormat:@"%@ (%lu)",
                            kLang(@"Select User"),
                           (unsigned long)selectedCount];

        for (NSString *uid in self.selectedUIDs) {
            UserModel *user = [self userForUID:uid];
            XLFormRowDescriptor *userRow =
            [XLFormRowDescriptor formRowDescriptorWithTag:[self specificUserRowTagForUID:uid]
                                                  rowType:XLFormRowDescriptorTypePickOption
                                                    title:[self displayNameForUser:user fallbackUID:uid]];
            userRow.value = user;
            userRow.height = 54.0;
            userRow.cellConfig[@"showPickButton"] = @NO;
            userRow.cellConfig[@"showOptionImage"] = @YES;
            [self.specificUsersSection addFormRow:userRow beforeRow:pickerRow];
        }
    }

    [self updateFormRow:pickerRow];
    [self.tableView reloadData];
    [self pp_refreshDispatchStatus];
}

- (NSArray<NSString *> *)normalizedSelectedUIDs {
    NSMutableOrderedSet<NSString *> *uids = [NSMutableOrderedSet orderedSet];
    for (id raw in self.selectedUIDs ?: @[]) {
        NSString *uid = PPNotifTrimmedString(raw);
        if (uid.length > 0) [uids addObject:uid];
    }
    return uids.array;
}

- (NSString *)displayNameForUser:(UserModel *)user fallbackUID:(NSString *)uid {
    return PPNotifFirstNonEmpty(@[
        [user PPBestDisplayName],
        user.UserName,
        user.displayName,
        user.UserEmail,
        user.MobileNo,
        uid ?: @""
    ]);
}

- (NSString *)specificUserRowTagForUID:(NSString *)uid {
    NSString *safeUID = PPNotifTrimmedString(uid);
    return [kSpecificUserRowPrefix stringByAppendingString:safeUID];
}

- (BOOL)isSpecificUserRowTag:(NSString *)tag {
    return [tag isKindOfClass:[NSString class]] && [tag hasPrefix:kSpecificUserRowPrefix];
}

- (NSString *)uidFromSpecificUserRowTag:(NSString *)tag {
    if (![self isSpecificUserRowTag:tag]) return @"";
    return [tag substringFromIndex:kSpecificUserRowPrefix.length];
}

- (XLFormRowDescriptor *)rowDescriptorForIndexPath:(NSIndexPath *)indexPath {
    if (!indexPath) return nil;
    if (indexPath.section >= self.form.formSections.count) return nil;
    XLFormSectionDescriptor *section = self.form.formSections[indexPath.section];
    if (indexPath.row >= section.formRows.count) return nil;
    return section.formRows[indexPath.row];
}

- (UserModel *)userForUID:(NSString *)uid {
    for (UserModel *user in self.cachedUsers) {
        if ([user.uid isEqualToString:uid] || [user.ID isEqualToString:uid]) return user;
    }
    return nil;
}

#pragma mark - Send

- (void)onSend {
    if (self.isSending) return;

    NSArray *errors = [self formValidationErrors];
    if (errors.count) {
        NSString *message = PPNotifTrimmedString(((NSError *)errors.firstObject).localizedDescription);
        if (message.length == 0) message = kLang(@"FillRequiredFields");
        self.dispatchOutcomeMessage = message;
        self.dispatchOutcomeState = PPNotificationComposerDispatchStateError;
        [self pp_refreshDispatchStatus];
        [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:message];
        return;
    }

    PPNotificationTargetKind target = [self currentTargetKind];
    if (target == PPNotificationTargetKindNone) {
        self.dispatchOutcomeMessage = kLang(@"NotificationComposer_Status_SelectTarget");
        self.dispatchOutcomeState = PPNotificationComposerDispatchStateError;
        [self pp_refreshDispatchStatus];
        [PPAlertHelper showInfoIn:self
                          title:kLang(@"Info")
                       subtitle:kLang(@"NotificationComposer_Status_SelectTarget")];
        return;
    }

    NSString *title = PPNotifTrimmedString([self.form formRowWithTag:kRowTitleTag].value);
    NSString *body = PPNotifTrimmedString([self.form formRowWithTag:kRowBodyTag].value);
    NSInteger typeValue = [self integerFromRowValue:[self.form formRowWithTag:kRowTypeTag].value];

    PPNotificationAudience audience = PPNotificationAudienceAllUsers;
    NSArray<NSString *> *userIDs = nil;

    switch (target) {
        case PPNotificationTargetKindSpecificUsers:
            if (self.selectedUIDs.count == 0) {
                self.dispatchOutcomeMessage = kLang(@"NotificationComposer_Status_SelectRecipients");
                self.dispatchOutcomeState = PPNotificationComposerDispatchStateError;
                [self pp_refreshDispatchStatus];
                [PPAlertHelper showInfoIn:self
                                  title:kLang(@"Info")
                               subtitle:kLang(@"NotificationComposer_Status_SelectRecipients")];
                return;
            }
            if (self.selectedUIDs.count > kPPNotificationComposerRecipientLimit) {
                NSString *message = [NSString stringWithFormat:kLang(@"NotificationComposer_Recipient_Limit"), (long)kPPNotificationComposerRecipientLimit];
                self.dispatchOutcomeMessage = message;
                self.dispatchOutcomeState = PPNotificationComposerDispatchStateError;
                [self pp_refreshDispatchStatus];
                [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:message];
                return;
            }
            audience = PPNotificationAudienceSpecificUsers;
            userIDs = self.selectedUIDs.copy;
            break;
        case PPNotificationTargetKindAllUsers:
            audience = PPNotificationAudienceAllUsers;
            break;
        case PPNotificationTargetKindAdmins:
            audience = PPNotificationAudienceAdmins;
            break;
        case PPNotificationTargetKindEveryone:
            audience = PPNotificationAudienceEveryone;
            break;
        case PPNotificationTargetKindNone:
        default:
            return;
    }

    [self setSending:YES];
    if (self.currentDispatchID.length == 0) {
        self.currentDispatchID = [[NSUUID UUID] UUIDString];
    }
    __weak typeof(self) weakSelf = self;
    [PPNotificationsManager sendConsoleNotificationWithTitle:title
                                                         body:body
                                                         type:typeValue
                                                     audience:audience
                                                      userIDs:userIDs
                                               idempotencyKey:self.currentDispatchID
                                                   completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        [self setSending:NO];
        NSInteger recipientCount = [response[@"recipientCount"] integerValue];
        NSInteger deliveryFailureCount = [response[@"failureCount"] integerValue];
        NSInteger requestFailureCount = [response[@"requestFailureCount"] integerValue];
        NSString *errorMessage = PPNotifTrimmedString(error.localizedDescription);

        if (error || recipientCount == 0) {
            NSString *message = errorMessage.length > 0 ? errorMessage : kLang(@"NotificationComposer_Failed_Message");
            self.dispatchOutcomeMessage = message;
            self.dispatchOutcomeState = PPNotificationComposerDispatchStateError;
            [self pp_refreshDispatchStatus];
            [PPAlertHelper showErrorIn:self title:kLang(@"Failed") subtitle:message];
            return;
        }

        if (requestFailureCount > 0 || deliveryFailureCount > 0) {
            NSInteger attentionCount = requestFailureCount + deliveryFailureCount;
            NSString *message = [NSString stringWithFormat:kLang(@"NotificationComposer_Status_Partial"), (long)recipientCount, (long)attentionCount];
            self.dispatchOutcomeMessage = message;
            self.dispatchOutcomeState = PPNotificationComposerDispatchStateWarning;
            [self pp_refreshDispatchStatus];
            [PPAlertHelper showInfoIn:self title:kLang(@"NotificationComposer_Partial_Title") subtitle:message];
            return;
        }

        NSString *message = [NSString stringWithFormat:kLang(@"NotificationComposer_Success_Message"), (long)recipientCount];
        self.dispatchOutcomeMessage = message;
        self.dispatchOutcomeState = PPNotificationComposerDispatchStateSuccess;
        [self pp_refreshDispatchStatus];
        [PPAlertHelper showSuccessIn:self title:kLang(@"Queued") subtitle:message];
    }];
}

- (void)setSending:(BOOL)isSending {
    _isSending = isSending;
    [self pp_refreshDispatchStatus];
}

#pragma mark - UI styling

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = [Styling fontMedium:14];
    header.textLabel.textColor = SeconderyTextClr;
    header.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self rowDescriptorForIndexPath:indexPath];
    if ([self isSpecificUserRowTag:row.tag]) {
        return YES;
    }
    return [super tableView:tableView canEditRowAtIndexPath:indexPath];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self rowDescriptorForIndexPath:indexPath];
    if ([self isSpecificUserRowTag:row.tag]) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    XLFormRowDescriptor *row = [self rowDescriptorForIndexPath:indexPath];
    if (![self isSpecificUserRowTag:row.tag]) return;

    NSString *uid = [self uidFromSpecificUserRowTag:row.tag];
    if (uid.length > 0) {
        [self.selectedUIDs removeObject:uid];
    }
    [self pp_clearDispatchOutcome];
    [self updateSpecificUsersSummary];
}

- (NSInteger)integerFromRowValue:(id)raw {
    if (raw == nil || raw == (id)kCFNull) return PPNotificationTypeGeneral;
    if ([raw isKindOfClass:[XLFormOptionsObject class]]) {
        XLFormOptionsObject *opt = raw;
        id fv = [opt respondsToSelector:@selector(formValue)] ? [opt formValue] : nil;
        if ([fv isKindOfClass:[NSNumber class]]) return [fv integerValue];
        if ([fv isKindOfClass:[NSString class]]) return [fv integerValue];
        return [[opt displayText] integerValue];
    }
    if ([raw isKindOfClass:[NSNumber class]]) return [raw integerValue];
    if ([raw isKindOfClass:[NSString class]]) return [raw integerValue];
    return PPNotificationTypeGeneral;
}

@end
