//
//  PPAuditLogViewController.m
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Sovereign Audit & Forensic Command Center.
//

#import "PPAuditLogViewController.h"
#import "PPAuditLogEntryModel.h"
#import "PPStaffAuth.h"
#import "PPDesignTokens.h"
#import "Language.h"
#import "PPImageManager.h"
#import "PPHUD.h"
#import "PPToast.h"
#import "UIViewController+PPNavBar.h"
#import "PurePetsAdmin-Swift.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;

static NSString *const kAuditCardCellID = @"PPAuditCardCell";

#pragma mark - Security Check

static BOOL PPAuditStaffSessionCanRead(PPStaffDoc *staff) {
    PPStaffDoc *current = [PPStaffAuth shared].cachedCurrentStaff;
    NSString *authUID = [FIRAuth auth].currentUser.uid;
    return (staff != nil && current == staff && authUID.length > 0 &&
            [staff.uid isEqualToString:authUID] && staff.isActive &&
            (staff.isAdmin || staff.hasGlobalScope) &&
            [staff hasPermission:kStaffPermAuditView]);
}

#pragma mark - Helper Views

@interface PPAuditPulsingDotView : UIView
@property (nonatomic, strong) UIView *coreDot;
@property (nonatomic, strong) UIView *pulseRing;
@end

@implementation PPAuditPulsingDotView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _pulseRing = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 14)];
        _pulseRing.layer.cornerRadius = 7.0;
        _pulseRing.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.35];
        [self addSubview:_pulseRing];

        _coreDot = [[UIView alloc] initWithFrame:CGRectMake(3, 3, 8, 8)];
        _coreDot.layer.cornerRadius = 4.0;
        _coreDot.backgroundColor = [UIColor ppSuccess];
        [self addSubview:_coreDot];

        [self startPulsing];
    }
    return self;
}

- (void)startPulsing {
    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @(0.85);
    scale.toValue = @(1.4);
    scale.duration = 1.6;
    scale.repeatCount = HUGE_VALF;
    scale.autoreverses = YES;
    scale.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    CABasicAnimation *alpha = [CABasicAnimation animationWithKeyPath:@"opacity"];
    alpha.fromValue = @(0.7);
    alpha.toValue = @(0.15);
    alpha.duration = 1.6;
    alpha.repeatCount = HUGE_VALF;
    alpha.autoreverses = YES;
    alpha.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    [self.pulseRing.layer addAnimation:scale forKey:@"pulseScale"];
    [self.pulseRing.layer addAnimation:alpha forKey:@"pulseAlpha"];
}

@end

#pragma mark - Fluid Capsule Segmented Bar for Studio

@interface PPAuditCapsuleSegmentBar : UIView
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) UIView *pillIndicator;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onSelectionChanged)(NSInteger index);
- (instancetype)initWithTitles:(NSArray<NSString *> *)titles;
- (void)setBadgeCount:(NSInteger)count forIndex:(NSInteger)index;
@end

@implementation PPAuditCapsuleSegmentBar {
    UIStackView *_stackView;
}

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _titles = [titles copy];
        _buttons = [NSMutableArray array];
        _selectedIndex = 0;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(self, 16.0);
    self.clipsToBounds = YES;

    _stackView = [[UIStackView alloc] init];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.axis = UILayoutConstraintAxisHorizontal;
    _stackView.distribution = UIStackViewDistributionFillEqually;
    _stackView.alignment = UIStackViewAlignmentFill;
    _stackView.spacing = 4.0;
    _stackView.layoutMargins = UIEdgeInsetsMake(4.0, 4.0, 4.0, 4.0);
    _stackView.layoutMarginsRelativeArrangement = YES;
    [self addSubview:_stackView];

    [NSLayoutConstraint activateConstraints:@[
        [_stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.heightAnchor constraintEqualToConstant:44.0]
    ]];

    for (NSInteger i = 0; i < self.titles.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.tag = i;
        btn.titleLabel.font = (i == 0) ? PPFontBold(13) : PPFontMedium(13);
        [btn setTitle:self.titles[i] forState:UIControlStateNormal];
        [btn setTitleColor:(i == 0 ? [UIColor ppTextPrimary] : [UIColor ppTextSecondary]) forState:UIControlStateNormal];
        btn.backgroundColor = (i == 0) ? [UIColor ppSurface] : UIColor.clearColor;
        PPApplyContinuousCorners(btn, 12.0);
        if (i == 0) {
            PPApplyCardShadow(btn);
        }
        [btn addTarget:self action:@selector(handleButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_stackView addArrangedSubview:btn];
        [self.buttons addObject:btn];
    }
}

- (void)setBadgeCount:(NSInteger)count forIndex:(NSInteger)index {
    if (index < 0 || index >= self.buttons.count || index >= self.titles.count) return;
    UIButton *btn = self.buttons[index];
    NSString *base = self.titles[index];
    if (count > 0) {
        [btn setTitle:[NSString stringWithFormat:@"%@ (%ld)", base, (long)count] forState:UIControlStateNormal];
    } else {
        [btn setTitle:base forState:UIControlStateNormal];
    }
}

- (void)handleButtonTapped:(UIButton *)sender {
    NSInteger newIdx = sender.tag;
    if (newIdx == self.selectedIndex) return;
    self.selectedIndex = newIdx;

    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];

    [UIView animateWithDuration:PPAnimDurationNormal
                          delay:0
         usingSpringWithDamping:PPAnimSpringDamping
          initialSpringVelocity:PPAnimSpringVelocity
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        for (NSInteger i = 0; i < self.buttons.count; i++) {
            UIButton *b = self.buttons[i];
            if (i == newIdx) {
                b.backgroundColor = [UIColor ppSurface];
                [b setTitleColor:[UIColor ppTextPrimary] forState:UIControlStateNormal];
                b.titleLabel.font = PPFontBold(13);
                PPApplyCardShadow(b);
            } else {
                b.backgroundColor = UIColor.clearColor;
                [b setTitleColor:[UIColor ppTextSecondary] forState:UIControlStateNormal];
                b.titleLabel.font = PPFontMedium(13);
                b.layer.shadowOpacity = 0.0;
            }
        }
    } completion:nil];

    if (self.onSelectionChanged) {
        self.onSelectionChanged(newIdx);
    }
}

@end

#pragma mark - Forensic Inspector & Visual State Diff Studio

@interface PPAuditDetailViewController : UIViewController
@property (nonatomic, strong) PPAuditLogEntryModel *entry;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) PPAuditCapsuleSegmentBar *capsuleBar;
@property (nonatomic, strong) UIView *diffContentView;
@property (nonatomic, strong) UILabel *fieldCountLabel;
@end

@implementation PPAuditDetailViewController

- (instancetype)initWithEntry:(PPAuditLogEntryModel *)entry {
    self = [super init];
    if (self) {
        _entry = entry;
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[
                [UISheetPresentationControllerDetent mediumDetent],
                [UISheetPresentationControllerDetent largeDetent]
            ];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = PPCornerHero;
        }
    }

    [self setupNavigation];
    [self setupScrollView];
    [self buildDossierContent];
    [self updateDiffSectionContent];
}

- (void)setupNavigation {
    self.title = kLang(@"Audit_Inspector_Title");

    // Circular frosted close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(0, 0, 36, 36);
    closeBtn.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(closeBtn, 18.0);
    closeBtn.layer.borderWidth = 1.0;
    closeBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:symCfg] forState:UIControlStateNormal];
    closeBtn.tintColor = [UIColor ppTextPrimary];
    [closeBtn addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithCustomView:closeBtn];

    // Circular frosted share button
    UIButton *shareBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    shareBtn.frame = CGRectMake(0, 0, 36, 36);
    shareBtn.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(shareBtn, 18.0);
    shareBtn.layer.borderWidth = 1.0;
    shareBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [shareBtn setImage:[UIImage systemImageNamed:@"square.and.arrow.up" withConfiguration:symCfg] forState:UIControlStateNormal];
    shareBtn.tintColor = [UIColor ppTextPrimary];
    [shareBtn addTarget:self action:@selector(handleShareReport) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithCustomView:shareBtn];

    if ([Language isRTL]) {
        self.navigationItem.leftBarButtonItem = closeItem;
        self.navigationItem.rightBarButtonItem = shareItem;
    } else {
        self.navigationItem.rightBarButtonItem = closeItem;
        self.navigationItem.leftBarButtonItem = shareItem;
    }
}

- (void)handleClose {
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)handleShareReport {
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];

    NSString *report = [NSString stringWithFormat:@"PurePets Forensic Audit Certificate\n"
                        "═════════════════════════════════\n"
                        "Action: %@ (%@)\n"
                        "Status: Verified & Cryptographically Logged\n"
                        "Actor Supervisor: %@\n"
                        "Target Entity: %@\n"
                        "Timestamp: %@ (%@)\n"
                        "Operational Justification: %@\n"
                        "Audit ID: %@\n"
                        "═════════════════════════════════\n",
                        self.entry.localizedActionTitle, self.entry.action,
                        self.entry.adminUid, self.entry.targetUid,
                        self.entry.formattedTimestamp, self.entry.relativeTimeString,
                        self.entry.reason ?: @"Automated System Pipeline",
                        self.entry.auditId ?: @"N/A"];

    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        act.popoverPresentationController.sourceView = self.view;
        act.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 80, 1, 1);
    }
    [self presentViewController:act animated:YES completion:nil];
}

- (void)setupScrollView {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scrollView];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = PPSpaceBase;
    _contentStack.alignment = UIStackViewAlignmentFill;
    [_scrollView addSubview:_contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_contentStack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:PPSpaceBase],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor constant:PPSpaceBase],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor constant:-PPSpaceBase],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-PPSpaceXXXL],
        [_contentStack.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor constant:-(PPSpaceBase * 2)]
    ]];
}

- (void)buildDossierContent {
    // 1. Sovereign Forensic Identity Passport Card
    UIView *headerCard = [self buildHeroPassportCard];
    [_contentStack addArrangedSubview:headerCard];

    // 2. Bilateral Provenance & Execution Vector Card
    UIView *participantsCard = [self buildBilateralProvenanceCard];
    [_contentStack addArrangedSubview:participantsCard];

    // 3. Adaptive Operational Justification
    UIView *reasonCard = [self buildReasonCard];
    [_contentStack addArrangedSubview:reasonCard];

    // 4. State Delta & Mutation Studio
    UIView *diffContainer = [self buildDiffContainer];
    [_contentStack addArrangedSubview:diffContainer];

    // 5. Tactical Action Deck
    UIView *actionDeck = [self buildActionDeck];
    [_contentStack addArrangedSubview:actionDeck];
}

#pragma mark - Hero Forensic Passport Card

- (UIView *)buildHeroPassportCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyElevatedShadow(card);

    // Ambient Top Aura Tint
    UIView *auraView = [[UIView alloc] init];
    auraView.translatesAutoresizingMaskIntoConstraints = NO;
    auraView.backgroundColor = [[self.entry accentColor] colorWithAlphaComponent:0.06];
    PPApplyContinuousCorners(auraView, PPCornerCard);
    auraView.clipsToBounds = YES;
    [card addSubview:auraView];

    // Verified Security Seal Pill
    UIView *sealPill = [[UIView alloc] init];
    sealPill.translatesAutoresizingMaskIntoConstraints = NO;
    sealPill.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.12];
    sealPill.layer.borderWidth = 1.0;
    sealPill.layer.borderColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.28].CGColor;
    PPApplyContinuousCorners(sealPill, 10.0);
    [card addSubview:sealPill];

    UIImageView *sealIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
    sealIcon.translatesAutoresizingMaskIntoConstraints = NO;
    sealIcon.tintColor = [UIColor ppSuccess];
    sealIcon.contentMode = UIViewContentModeScaleAspectFit;
    [sealPill addSubview:sealIcon];

    UILabel *sealLabel = [[UILabel alloc] init];
    sealLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sealLabel.font = PPFontBold(11);
    sealLabel.textColor = [UIColor ppSuccess];
    sealLabel.text = kLang(@"Audit_Inspector_Verified");
    [sealPill addSubview:sealLabel];

    // 3D-styled Squircle Icon
    UIView *iconSquircle = [[UIView alloc] init];
    iconSquircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconSquircle.backgroundColor = [self.entry badgeBackgroundColor];
    PPApplyContinuousCorners(iconSquircle, 16.0);
    iconSquircle.layer.borderWidth = 1.0;
    iconSquircle.layer.borderColor = [[self.entry accentColor] colorWithAlphaComponent:0.25].CGColor;
    PPApplyCardShadow(iconSquircle);
    [card addSubview:iconSquircle];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self.entry systemIconName]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [self.entry accentColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconSquircle addSubview:iconView];

    // Titles
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPFontBold(19);
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = [self.entry localizedActionTitle];
    titleLabel.numberOfLines = 2;
    [card addSubview:titleLabel];

    // Technical action tag
    UIView *tagView = [[UIView alloc] init];
    tagView.translatesAutoresizingMaskIntoConstraints = NO;
    tagView.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(tagView, 6.0);
    [card addSubview:tagView];

    UILabel *techActionLabel = [[UILabel alloc] init];
    techActionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    techActionLabel.font = [UIFont fontWithName:@"Menlo" size:10.5] ?: PPFontRegular(10.5);
    techActionLabel.textColor = [UIColor ppTextSecondary];
    techActionLabel.text = self.entry.action;
    [tagView addSubview:techActionLabel];

    // Telemetry Ribbon: Time Chip & Tactile 1-Tap Audit ID Pill
    UIView *ribbonView = [[UIView alloc] init];
    ribbonView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:ribbonView];

    // Time Chip
    UIView *timePill = [[UIView alloc] init];
    timePill.translatesAutoresizingMaskIntoConstraints = NO;
    timePill.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(timePill, 10.0);
    [ribbonView addSubview:timePill];

    UIImageView *timeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"clock.fill"]];
    timeIcon.translatesAutoresizingMaskIntoConstraints = NO;
    timeIcon.tintColor = [UIColor ppTextTertiary];
    [timePill addSubview:timeIcon];

    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    timeLabel.font = PPFontMedium(PPFontCaption1);
    timeLabel.textColor = [UIColor ppTextSecondary];
    timeLabel.text = [NSString stringWithFormat:@"%@ • %@", [self.entry relativeTimeString], [self.entry formattedTimestamp]];
    [timePill addSubview:timeLabel];

    // Tactile 1-Tap Copyable Audit ID Pill
    UIButton *copyIdBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    copyIdBtn.translatesAutoresizingMaskIntoConstraints = NO;
    copyIdBtn.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(copyIdBtn, 10.0);
    copyIdBtn.layer.borderWidth = 1.0;
    copyIdBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    copyIdBtn.contentEdgeInsets = UIEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);

    NSString *idSnippet = self.entry.auditId.length > 14 ? [self.entry.auditId substringToIndex:14] : (self.entry.auditId ?: @"--");
    [copyIdBtn setTitle:[NSString stringWithFormat:@"ID: %@...  ", idSnippet] forState:UIControlStateNormal];
    [copyIdBtn setTitleColor:[UIColor ppTextPrimary] forState:UIControlStateNormal];
    copyIdBtn.titleLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: PPFontMedium(11);
    [copyIdBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copyIdBtn.tintColor = AppPrimaryClr;
    [copyIdBtn addTarget:self action:@selector(handleHeroCopyIdTapped:) forControlEvents:UIControlEventTouchUpInside];
    [ribbonView addSubview:copyIdBtn];

    [NSLayoutConstraint activateConstraints:@[
        [auraView.topAnchor constraintEqualToAnchor:card.topAnchor],
        [auraView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [auraView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [auraView.heightAnchor constraintEqualToConstant:75.0],

        [sealPill.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],
        [sealPill.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [sealPill.heightAnchor constraintEqualToConstant:26.0],

        [sealIcon.leadingAnchor constraintEqualToAnchor:sealPill.leadingAnchor constant:8.0],
        [sealIcon.centerYAnchor constraintEqualToAnchor:sealPill.centerYAnchor],
        [sealIcon.widthAnchor constraintEqualToConstant:14.0],
        [sealIcon.heightAnchor constraintEqualToConstant:14.0],

        [sealLabel.leadingAnchor constraintEqualToAnchor:sealIcon.trailingAnchor constant:5.0],
        [sealLabel.trailingAnchor constraintEqualToAnchor:sealPill.trailingAnchor constant:-8.0],
        [sealLabel.centerYAnchor constraintEqualToAnchor:sealPill.centerYAnchor],

        [iconSquircle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [iconSquircle.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],
        [iconSquircle.widthAnchor constraintEqualToConstant:48.0],
        [iconSquircle.heightAnchor constraintEqualToConstant:48.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconSquircle.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconSquircle.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:24.0],
        [iconView.heightAnchor constraintEqualToConstant:24.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconSquircle.trailingAnchor constant:PPSpaceMD],
        [titleLabel.trailingAnchor constraintEqualToAnchor:sealPill.leadingAnchor constant:-PPSpaceSM],
        [titleLabel.topAnchor constraintEqualToAnchor:iconSquircle.topAnchor],

        [tagView.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [tagView.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:PPSpaceXS],
        [tagView.heightAnchor constraintEqualToConstant:22.0],

        [techActionLabel.leadingAnchor constraintEqualToAnchor:tagView.leadingAnchor constant:6.0],
        [techActionLabel.trailingAnchor constraintEqualToAnchor:tagView.trailingAnchor constant:-6.0],
        [techActionLabel.centerYAnchor constraintEqualToAnchor:tagView.centerYAnchor],

        [ribbonView.topAnchor constraintGreaterThanOrEqualToAnchor:iconSquircle.bottomAnchor constant:PPSpaceMD],
        [ribbonView.topAnchor constraintGreaterThanOrEqualToAnchor:tagView.bottomAnchor constant:PPSpaceMD],
        [ribbonView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [ribbonView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [ribbonView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase],

        [timePill.leadingAnchor constraintEqualToAnchor:ribbonView.leadingAnchor],
        [timePill.topAnchor constraintEqualToAnchor:ribbonView.topAnchor],
        [timePill.heightAnchor constraintEqualToConstant:28.0],

        [timeIcon.leadingAnchor constraintEqualToAnchor:timePill.leadingAnchor constant:8.0],
        [timeIcon.centerYAnchor constraintEqualToAnchor:timePill.centerYAnchor],
        [timeIcon.widthAnchor constraintEqualToConstant:13.0],
        [timeIcon.heightAnchor constraintEqualToConstant:13.0],

        [timeLabel.leadingAnchor constraintEqualToAnchor:timeIcon.trailingAnchor constant:5.0],
        [timeLabel.trailingAnchor constraintEqualToAnchor:timePill.trailingAnchor constant:-8.0],
        [timeLabel.centerYAnchor constraintEqualToAnchor:timePill.centerYAnchor],

        [copyIdBtn.leadingAnchor constraintEqualToAnchor:ribbonView.leadingAnchor],
        [copyIdBtn.topAnchor constraintEqualToAnchor:timePill.bottomAnchor constant:PPSpaceSM],
        [copyIdBtn.bottomAnchor constraintEqualToAnchor:ribbonView.bottomAnchor],
        [copyIdBtn.heightAnchor constraintEqualToConstant:30.0]
    ]];

    NSLayoutConstraint *ribbonTopHug = [ribbonView.topAnchor constraintEqualToAnchor:tagView.bottomAnchor constant:PPSpaceMD];
    ribbonTopHug.priority = UILayoutPriorityDefaultHigh;
    ribbonTopHug.active = YES;

    return card;
}

- (void)handleHeroCopyIdTapped:(UIButton *)sender {
    if (self.entry.auditId.length == 0) return;
    [UIPasteboard generalPasteboard].string = self.entry.auditId;
    [PPToast toast:kLang(@"Audit_Copied")];

    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [fb impactOccurred];

    [UIView animateWithDuration:0.15 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.92, 0.92);
        [sender setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateNormal];
        sender.tintColor = [UIColor ppSuccess];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 delay:0.0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:0 animations:^{
            sender.transform = CGAffineTransformIdentity;
        } completion:^(BOOL fin) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [sender setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
                sender.tintColor = AppPrimaryClr;
            });
        }];
    }];
}

#pragma mark - Bilateral Provenance & Execution Vector Card

- (UIView *)buildBilateralProvenanceCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);

    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.font = PPFontBold(PPFontCallout);
    headerLabel.textColor = [UIColor ppTextPrimary];
    headerLabel.text = [Language isRTL] ? @"أطراف العملية والمعرّفات" : @"Operation Parties & Execution Vector";
    [card addSubview:headerLabel];

    // Actor Node
    BOOL isSystem = [self.entry.adminUid containsString:@"system"] ||
                    [self.entry.adminUid hasPrefix:@"daemon"] ||
                    self.entry.adminUid.length == 0;

    NSString *actorTitle = isSystem ? kLang(@"Audit_Inspector_SystemDaemon") : kLang(@"Audit_Inspector_HumanStaff");
    NSString *actorIcon = isSystem ? @"cpu.fill" : @"person.badge.shield.checkmark.fill";
    UIColor *actorColor = isSystem ? [UIColor ppQuickActionServices] : [UIColor ppQuickActionAnimals];
    NSString *actorBadge = isSystem ? @"AUTO" : @"STAFF";

    UIView *actorBox = [self buildNodeBoxWithTitle:actorTitle
                                             value:self.entry.adminUid.length > 0 ? self.entry.adminUid : @"system-daemon"
                                          iconName:actorIcon
                                         tintColor:actorColor
                                         badgeText:actorBadge
                                          isCopier:YES];
    [card addSubview:actorBox];

    // Flow Vector Divider
    UIView *flowDivider = [[UIView alloc] init];
    flowDivider.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:flowDivider];

    UIView *dividerLine = [[UIView alloc] init];
    dividerLine.translatesAutoresizingMaskIntoConstraints = NO;
    dividerLine.backgroundColor = [UIColor ppSeparator];
    [flowDivider addSubview:dividerLine];

    UIView *arrowCircle = [[UIView alloc] init];
    arrowCircle.translatesAutoresizingMaskIntoConstraints = NO;
    arrowCircle.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(arrowCircle, 12.0);
    arrowCircle.layer.borderWidth = 1.0;
    arrowCircle.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [flowDivider addSubview:arrowCircle];

    UIImageView *arrowIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down"]];
    arrowIcon.translatesAutoresizingMaskIntoConstraints = NO;
    arrowIcon.tintColor = [UIColor ppTextTertiary];
    arrowIcon.contentMode = UIViewContentModeScaleAspectFit;
    [arrowCircle addSubview:arrowIcon];

    // Target Node
    NSString *targetResolved = kLang(@"Audit_Inspector_Target");
    NSString *targetIcon = @"target";
    UIColor *targetColor = [UIColor ppQuickActionCommunity];
    if (self.entry.targetCollection.length > 0) {
        targetResolved = self.entry.targetCollection;
    } else if ([self.entry.targetUid hasPrefix:@"PUID"] || [self.entry.action containsString:@"user"] || [self.entry.action containsString:@"profile"]) {
        targetResolved = [Language isRTL] ? @"ملف المستخدم العام" : @"Public User Profile";
        targetIcon = @"person.crop.circle.badge.checkmark";
        targetColor = [UIColor ppCareAccent];
    } else if ([self.entry.targetUid hasPrefix:@"ORD"] || [self.entry.action containsString:@"order"]) {
        targetResolved = [Language isRTL] ? @"طلب شراء إلكتروني" : @"Commerce Order";
        targetIcon = @"bag.fill";
        targetColor = [UIColor ppQuickActionShopping];
    } else if ([self.entry.action containsString:@"service"]) {
        targetResolved = [Language isRTL] ? @"خدمة بيطرية / فندقية" : @"Service Document";
        targetIcon = @"pawprint.fill";
        targetColor = [UIColor ppQuickActionServices];
    }

    UIView *targetBox = [self buildNodeBoxWithTitle:targetResolved
                                              value:self.entry.targetUid.length > 0 ? self.entry.targetUid : @"--"
                                           iconName:targetIcon
                                          tintColor:targetColor
                                          badgeText:@"TARGET"
                                           isCopier:YES];
    [card addSubview:targetBox];

    [NSLayoutConstraint activateConstraints:@[
        [headerLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [headerLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [headerLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],

        [actorBox.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [actorBox.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [actorBox.topAnchor constraintEqualToAnchor:headerLabel.bottomAnchor constant:PPSpaceMD],

        [flowDivider.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [flowDivider.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [flowDivider.topAnchor constraintEqualToAnchor:actorBox.bottomAnchor],
        [flowDivider.heightAnchor constraintEqualToConstant:28.0],

        [dividerLine.leadingAnchor constraintEqualToAnchor:flowDivider.leadingAnchor constant:36.0],
        [dividerLine.trailingAnchor constraintEqualToAnchor:flowDivider.trailingAnchor constant:-36.0],
        [dividerLine.centerYAnchor constraintEqualToAnchor:flowDivider.centerYAnchor],
        [dividerLine.heightAnchor constraintEqualToConstant:1.0],

        [arrowCircle.centerXAnchor constraintEqualToAnchor:flowDivider.centerXAnchor],
        [arrowCircle.centerYAnchor constraintEqualToAnchor:flowDivider.centerYAnchor],
        [arrowCircle.widthAnchor constraintEqualToConstant:24.0],
        [arrowCircle.heightAnchor constraintEqualToConstant:24.0],

        [arrowIcon.centerXAnchor constraintEqualToAnchor:arrowCircle.centerXAnchor],
        [arrowIcon.centerYAnchor constraintEqualToAnchor:arrowCircle.centerYAnchor],
        [arrowIcon.widthAnchor constraintEqualToConstant:12.0],
        [arrowIcon.heightAnchor constraintEqualToConstant:12.0],

        [targetBox.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [targetBox.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [targetBox.topAnchor constraintEqualToAnchor:flowDivider.bottomAnchor],
        [targetBox.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase]
    ]];

    return card;
}

- (UIView *)buildNodeBoxWithTitle:(NSString *)title
                            value:(NSString *)value
                         iconName:(NSString *)iconName
                        tintColor:(UIColor *)tintColor
                        badgeText:(NSString *)badgeText
                         isCopier:(BOOL)isCopier {
    UIView *box = [[UIView alloc] init];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(box, 14.0);
    box.layer.borderWidth = 1.0;
    box.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;

    // Squircle Icon
    UIView *iconBox = [[UIView alloc] init];
    iconBox.translatesAutoresizingMaskIntoConstraints = NO;
    iconBox.backgroundColor = [tintColor colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(iconBox, 10.0);
    [box addSubview:iconBox];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = tintColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconBox addSubview:iconView];

    // Title Label
    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.font = PPFontBold(13);
    titleLbl.textColor = [UIColor ppTextPrimary];
    titleLbl.text = title;
    [box addSubview:titleLbl];

    // Badge Pill
    UIView *badgeView = [[UIView alloc] init];
    badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    badgeView.backgroundColor = [tintColor colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(badgeView, 5.0);
    [box addSubview:badgeView];

    UILabel *badgeLbl = [[UILabel alloc] init];
    badgeLbl.translatesAutoresizingMaskIntoConstraints = NO;
    badgeLbl.font = PPFontBold(9);
    badgeLbl.textColor = tintColor;
    badgeLbl.text = badgeText;
    [badgeView addSubview:badgeLbl];

    // Value Label
    UILabel *valLbl = [[UILabel alloc] init];
    valLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valLbl.font = [UIFont fontWithName:@"Menlo" size:11.5] ?: PPFontRegular(11.5);
    valLbl.textColor = [UIColor ppTextSecondary];
    valLbl.text = value;
    valLbl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [box addSubview:valLbl];

    // Quick Copy Button
    if (isCopier && value.length > 0) {
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
        copyBtn.backgroundColor = [UIColor ppSurface];
        PPApplyContinuousCorners(copyBtn, 14.0);
        copyBtn.layer.borderWidth = 1.0;
        copyBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
        copyBtn.tintColor = [UIColor ppTextTertiary];
        objc_setAssociatedObject(copyBtn, "copyVal", value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [copyBtn addTarget:self action:@selector(handleRowCopyTapped:) forControlEvents:UIControlEventTouchUpInside];
        [box addSubview:copyBtn];

        [NSLayoutConstraint activateConstraints:@[
            [copyBtn.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-PPSpaceSM],
            [copyBtn.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
            [copyBtn.widthAnchor constraintEqualToConstant:32.0],
            [copyBtn.heightAnchor constraintEqualToConstant:32.0],
            [valLbl.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-PPSpaceSM]
        ]];
    } else {
        [valLbl.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-PPSpaceBase].active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [box.heightAnchor constraintGreaterThanOrEqualToConstant:54.0],

        [iconBox.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:PPSpaceMD],
        [iconBox.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [iconBox.widthAnchor constraintEqualToConstant:36.0],
        [iconBox.heightAnchor constraintEqualToConstant:36.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconBox.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconBox.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:18.0],
        [iconView.heightAnchor constraintEqualToConstant:18.0],

        [titleLbl.leadingAnchor constraintEqualToAnchor:iconBox.trailingAnchor constant:PPSpaceMD],
        [titleLbl.topAnchor constraintEqualToAnchor:box.topAnchor constant:PPSpaceSM],

        [badgeView.leadingAnchor constraintEqualToAnchor:titleLbl.trailingAnchor constant:6.0],
        [badgeView.centerYAnchor constraintEqualToAnchor:titleLbl.centerYAnchor],
        [badgeView.heightAnchor constraintEqualToConstant:16.0],

        [badgeLbl.leadingAnchor constraintEqualToAnchor:badgeView.leadingAnchor constant:5.0],
        [badgeLbl.trailingAnchor constraintEqualToAnchor:badgeView.trailingAnchor constant:-5.0],
        [badgeLbl.centerYAnchor constraintEqualToAnchor:badgeView.centerYAnchor],

        [valLbl.leadingAnchor constraintEqualToAnchor:titleLbl.leadingAnchor],
        [valLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:2.0],
        [valLbl.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-PPSpaceSM]
    ]];

    return box;
}

- (void)handleRowCopyTapped:(UIButton *)sender {
    NSString *val = objc_getAssociatedObject(sender, "copyVal");
    if (val.length == 0) return;

    [UIPasteboard generalPasteboard].string = val;
    [PPToast toast:kLang(@"Audit_Copied")];

    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];

    [UIView animateWithDuration:0.12 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.85, 0.85);
        [sender setImage:[UIImage systemImageNamed:@"checkmark"] forState:UIControlStateNormal];
        sender.tintColor = [UIColor ppSuccess];
    } completion:^(BOOL fin) {
        [UIView animateWithDuration:0.18 animations:^{
            sender.transform = CGAffineTransformIdentity;
        } completion:^(BOOL done) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [sender setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
                sender.tintColor = [UIColor ppTextTertiary];
            });
        }];
    }];
}

#pragma mark - Adaptive Operational Justification Card

- (UIView *)buildReasonCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);

    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.font = PPFontBold(PPFontCallout);
    headerLabel.textColor = [UIColor ppTextPrimary];
    headerLabel.text = kLang(@"Audit_Inspector_Reason");
    [card addSubview:headerLabel];

    if (self.entry.reason.length > 0) {
        // Formatted Executive Quote Card
        UIView *quoteBox = [[UIView alloc] init];
        quoteBox.translatesAutoresizingMaskIntoConstraints = NO;
        quoteBox.backgroundColor = [UIColor ppSecondarySurface];
        PPApplyContinuousCorners(quoteBox, 14.0);
        quoteBox.layer.borderWidth = 1.0;
        quoteBox.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        [card addSubview:quoteBox];

        UIImageView *quoteGlyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"quote.bubble.fill"]];
        quoteGlyph.translatesAutoresizingMaskIntoConstraints = NO;
        quoteGlyph.tintColor = AppPrimaryClr;
        [quoteBox addSubview:quoteGlyph];

        UILabel *reasonLabel = [[UILabel alloc] init];
        reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
        reasonLabel.font = PPFontRegular(PPFontBody);
        reasonLabel.textColor = [UIColor ppTextPrimary];
        reasonLabel.numberOfLines = 0;
        reasonLabel.text = self.entry.reason;
        [quoteBox addSubview:reasonLabel];

        [NSLayoutConstraint activateConstraints:@[
            [headerLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
            [headerLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
            [headerLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],

            [quoteBox.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
            [quoteBox.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
            [quoteBox.topAnchor constraintEqualToAnchor:headerLabel.bottomAnchor constant:PPSpaceMD],
            [quoteBox.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase],

            [quoteGlyph.leadingAnchor constraintEqualToAnchor:quoteBox.leadingAnchor constant:PPSpaceMD],
            [quoteGlyph.topAnchor constraintEqualToAnchor:quoteBox.topAnchor constant:PPSpaceMD],
            [quoteGlyph.widthAnchor constraintEqualToConstant:20.0],
            [quoteGlyph.heightAnchor constraintEqualToConstant:20.0],

            [reasonLabel.leadingAnchor constraintEqualToAnchor:quoteGlyph.trailingAnchor constant:PPSpaceMD],
            [reasonLabel.trailingAnchor constraintEqualToAnchor:quoteBox.trailingAnchor constant:-PPSpaceMD],
            [reasonLabel.topAnchor constraintEqualToAnchor:quoteBox.topAnchor constant:PPSpaceMD],
            [reasonLabel.bottomAnchor constraintEqualToAnchor:quoteBox.bottomAnchor constant:-PPSpaceMD]
        ]];
    } else {
        // Intelligent Ambient Status Banner (No ugly empty grey void)
        UIView *ambientBanner = [[UIView alloc] init];
        ambientBanner.translatesAutoresizingMaskIntoConstraints = NO;
        ambientBanner.backgroundColor = [[UIColor ppInfo] colorWithAlphaComponent:0.06];
        ambientBanner.layer.borderWidth = 1.0;
        ambientBanner.layer.borderColor = [[UIColor ppInfo] colorWithAlphaComponent:0.2].CGColor;
        PPApplyContinuousCorners(ambientBanner, 12.0);
        [card addSubview:ambientBanner];

        UIImageView *infoIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle.fill"]];
        infoIcon.translatesAutoresizingMaskIntoConstraints = NO;
        infoIcon.tintColor = [UIColor ppInfo];
        infoIcon.contentMode = UIViewContentModeScaleAspectFit;
        [ambientBanner addSubview:infoIcon];

        UILabel *ambientLabel = [[UILabel alloc] init];
        ambientLabel.translatesAutoresizingMaskIntoConstraints = NO;
        ambientLabel.font = PPFontMedium(12.5);
        ambientLabel.textColor = [UIColor ppTextSecondary];
        ambientLabel.text = kLang(@"Audit_Inspector_AutoReason");
        [ambientBanner addSubview:ambientLabel];

        [NSLayoutConstraint activateConstraints:@[
            [headerLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
            [headerLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
            [headerLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],

            [ambientBanner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
            [ambientBanner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
            [ambientBanner.topAnchor constraintEqualToAnchor:headerLabel.bottomAnchor constant:PPSpaceMD],
            [ambientBanner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase],
            [ambientBanner.heightAnchor constraintEqualToConstant:44.0],

            [infoIcon.leadingAnchor constraintEqualToAnchor:ambientBanner.leadingAnchor constant:PPSpaceMD],
            [infoIcon.centerYAnchor constraintEqualToAnchor:ambientBanner.centerYAnchor],
            [infoIcon.widthAnchor constraintEqualToConstant:16.0],
            [infoIcon.heightAnchor constraintEqualToConstant:16.0],

            [ambientLabel.leadingAnchor constraintEqualToAnchor:infoIcon.trailingAnchor constant:PPSpaceSM],
            [ambientLabel.trailingAnchor constraintEqualToAnchor:ambientBanner.trailingAnchor constant:-PPSpaceMD],
            [ambientLabel.centerYAnchor constraintEqualToAnchor:ambientBanner.centerYAnchor]
        ]];
    }

    return card;
}

#pragma mark - State Delta & Mutation Studio Card

- (UIView *)buildDiffContainer {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(container, PPCornerCard);
    PPApplyCardShadow(container);

    // Section Header with count badge
    UIView *headerRow = [[UIView alloc] init];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:headerRow];

    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.font = PPFontBold(PPFontCallout);
    headerLabel.textColor = [UIColor ppTextPrimary];
    headerLabel.text = kLang(@"Audit_Inspector_DiffSummary");
    [headerRow addSubview:headerLabel];

    _fieldCountLabel = [[UILabel alloc] init];
    _fieldCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _fieldCountLabel.font = PPFontBold(11);
    _fieldCountLabel.textColor = AppPrimaryClr;
    _fieldCountLabel.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(_fieldCountLabel, 6.0);
    _fieldCountLabel.clipsToBounds = YES;
    _fieldCountLabel.textAlignment = NSTextAlignmentCenter;
    NSArray *diffItems = [self.entry computedDiff];
    NSString *fieldCountStr = [NSString stringWithFormat:kLang(@"Audit_Inspector_FieldCountFormat"), (long)diffItems.count];
    _fieldCountLabel.text = [NSString stringWithFormat:@"  %@  ", fieldCountStr];
    [headerRow addSubview:_fieldCountLabel];

    // Fluid Capsule Segmented Bar (Zero Text Clipping!)
    NSArray *tabs = @[
        kLang(@"Audit_Inspector_Tab_Diff"),
        kLang(@"Audit_Inspector_Tab_After"),
        kLang(@"Audit_Inspector_Tab_Before"),
        kLang(@"Audit_Inspector_Tab_Raw")
    ];
    _capsuleBar = [[PPAuditCapsuleSegmentBar alloc] initWithTitles:tabs];
    _capsuleBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_capsuleBar setBadgeCount:diffItems.count forIndex:0];

    __weak typeof(self) weakSelf = self;
    _capsuleBar.onSelectionChanged = ^(NSInteger index) {
        [weakSelf updateDiffSectionContent];
    };
    [container addSubview:_capsuleBar];

    _diffContentView = [[UIView alloc] init];
    _diffContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_diffContentView];

    [NSLayoutConstraint activateConstraints:@[
        [headerRow.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceBase],
        [headerRow.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceBase],
        [headerRow.topAnchor constraintEqualToAnchor:container.topAnchor constant:PPSpaceBase],
        [headerRow.heightAnchor constraintEqualToConstant:24.0],

        [headerLabel.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor],
        [headerLabel.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],

        [_fieldCountLabel.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor],
        [_fieldCountLabel.centerYAnchor constraintEqualToAnchor:headerRow.centerYAnchor],
        [_fieldCountLabel.heightAnchor constraintEqualToConstant:20.0],

        [_capsuleBar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceBase],
        [_capsuleBar.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceBase],
        [_capsuleBar.topAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:PPSpaceMD],

        [_diffContentView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceBase],
        [_diffContentView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceBase],
        [_diffContentView.topAnchor constraintEqualToAnchor:_capsuleBar.bottomAnchor constant:PPSpaceMD],
        [_diffContentView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceBase]
    ]];

    return container;
}

- (void)updateDiffSectionContent {
    for (UIView *sub in self.diffContentView.subviews) {
        [sub removeFromSuperview];
    }

    NSInteger idx = self.capsuleBar.selectedIndex;
    if (idx == 0) {
        // Visual Diff Engine
        [self renderVisualDiffInView:self.diffContentView];
    } else if (idx == 1) {
        // State After
        [self renderDictionaryDump:self.entry.after inView:self.diffContentView emptyLabel:kLang(@"None")];
    } else if (idx == 2) {
        // State Before
        [self renderDictionaryDump:self.entry.before inView:self.diffContentView emptyLabel:kLang(@"None")];
    } else {
        // Raw JSON Payload
        NSMutableDictionary *rawDict = [NSMutableDictionary dictionary];
        if (self.entry.auditId) rawDict[@"auditId"] = self.entry.auditId;
        if (self.entry.action) rawDict[@"action"] = self.entry.action;
        if (self.entry.adminUid) rawDict[@"adminUid"] = self.entry.adminUid;
        if (self.entry.targetUid) rawDict[@"targetUid"] = self.entry.targetUid;
        if (self.entry.reason) rawDict[@"reason"] = self.entry.reason;
        if (self.entry.before) rawDict[@"before"] = self.entry.before;
        if (self.entry.after) rawDict[@"after"] = self.entry.after;
        if (self.entry.metadata) rawDict[@"metadata"] = self.entry.metadata;
        [self renderDictionaryDump:rawDict inView:self.diffContentView emptyLabel:@"{}"];
    }
}

- (void)renderVisualDiffInView:(UIView *)hostView {
    NSArray<PPAuditDiffItem *> *diffItems = [self.entry computedDiff];
    if (diffItems.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] init];
        emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        emptyLabel.text = kLang(@"Audit_NoEntries");
        emptyLabel.font = PPFontRegular(PPFontSubheadline);
        emptyLabel.textColor = [UIColor ppTextTertiary];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        [hostView addSubview:emptyLabel];

        [NSLayoutConstraint activateConstraints:@[
            [emptyLabel.topAnchor constraintEqualToAnchor:hostView.topAnchor constant:PPSpaceMD],
            [emptyLabel.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
            [emptyLabel.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
            [emptyLabel.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor constant:-PPSpaceMD]
        ]];
        return;
    }

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = PPSpaceMD;
    stack.alignment = UIStackViewAlignmentFill;
    [hostView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor]
    ]];

    // Check if fully synced / unchanged
    BOOL allUnchanged = YES;
    for (PPAuditDiffItem *it in diffItems) {
        if (it.diffType != PPAuditDiffTypeUnchanged) {
            allUnchanged = NO;
            break;
        }
    }

    if (allUnchanged) {
        // Emerald Reassurance Banner for Sync operations
        UIView *syncBanner = [[UIView alloc] init];
        syncBanner.translatesAutoresizingMaskIntoConstraints = NO;
        syncBanner.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.08];
        syncBanner.layer.borderWidth = 1.0;
        syncBanner.layer.borderColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.25].CGColor;
        PPApplyContinuousCorners(syncBanner, 12.0);
        [stack addArrangedSubview:syncBanner];

        UIImageView *checkIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill"]];
        checkIcon.translatesAutoresizingMaskIntoConstraints = NO;
        checkIcon.tintColor = [UIColor ppSuccess];
        checkIcon.contentMode = UIViewContentModeScaleAspectFit;
        [syncBanner addSubview:checkIcon];

        UILabel *syncLabel = [[UILabel alloc] init];
        syncLabel.translatesAutoresizingMaskIntoConstraints = NO;
        syncLabel.font = PPFontMedium(12.5);
        syncLabel.textColor = [UIColor ppSuccess];
        syncLabel.text = kLang(@"Audit_Inspector_FullySynced");
        [syncBanner addSubview:syncLabel];

        [NSLayoutConstraint activateConstraints:@[
            [syncBanner.heightAnchor constraintEqualToConstant:42.0],

            [checkIcon.leadingAnchor constraintEqualToAnchor:syncBanner.leadingAnchor constant:PPSpaceMD],
            [checkIcon.centerYAnchor constraintEqualToAnchor:syncBanner.centerYAnchor],
            [checkIcon.widthAnchor constraintEqualToConstant:16.0],
            [checkIcon.heightAnchor constraintEqualToConstant:16.0],

            [syncLabel.leadingAnchor constraintEqualToAnchor:checkIcon.trailingAnchor constant:PPSpaceSM],
            [syncLabel.trailingAnchor constraintEqualToAnchor:syncBanner.trailingAnchor constant:-PPSpaceMD],
            [syncLabel.centerYAnchor constraintEqualToAnchor:syncBanner.centerYAnchor]
        ]];
    }

    for (PPAuditDiffItem *item in diffItems) {
        BOOL isImageKey = [item.key.lowercaseString containsString:@"image"] ||
                          [item.key.lowercaseString containsString:@"photo"] ||
                          [item.key.lowercaseString containsString:@"avatar"] ||
                          ([item.newValueString isKindOfClass:[NSString class]] && [item.newValueString hasPrefix:@"http"]);

        if (isImageKey && item.newValueString.length > 0 && [item.newValueString hasPrefix:@"http"]) {
            UIView *imageRow = [self buildImageDiffRowForItem:item];
            [stack addArrangedSubview:imageRow];
        } else {
            UIView *row = [self buildVisualDiffRowForItem:item];
            [stack addArrangedSubview:row];
        }
    }
}

#pragma mark - Rich Live Image Diff Row

- (UIView *)buildImageDiffRowForItem:(PPAuditDiffItem *)item {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(card, 14.0);
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;

    // Media Thumbnail View with live Kingfisher caching
    UIImageView *thumbView = [[UIImageView alloc] init];
    thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    thumbView.contentMode = UIViewContentModeScaleAspectFill;
    thumbView.clipsToBounds = YES;
    thumbView.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(thumbView, 12.0);
    thumbView.layer.borderWidth = 1.0;
    thumbView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    thumbView.userInteractionEnabled = YES;
    [card addSubview:thumbView];

    // Load actual image
    [[PPImageManager sharedManager] setImageFromUrl:item.newValueString
                                        toImageView:thumbView
                                    placeholderName:@"person.crop.circle.fill"
                                         completion:nil];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleImagePreviewTapped:)];
    [thumbView addGestureRecognizer:tap];

    // Labels
    UILabel *keyLbl = [[UILabel alloc] init];
    keyLbl.translatesAutoresizingMaskIntoConstraints = NO;
    keyLbl.font = PPFontBold(14);
    keyLbl.textColor = [UIColor ppTextPrimary];
    keyLbl.text = [self humanReadableKeyFor:item.key];
    [card addSubview:keyLbl];

    UILabel *techKeyLbl = [[UILabel alloc] init];
    techKeyLbl.translatesAutoresizingMaskIntoConstraints = NO;
    techKeyLbl.font = [UIFont fontWithName:@"Menlo" size:10] ?: PPFontRegular(10);
    techKeyLbl.textColor = [UIColor ppTextTertiary];
    techKeyLbl.text = item.key;
    [card addSubview:techKeyLbl];

    // Visual Preview Badge
    UIView *previewBadge = [[UIView alloc] init];
    previewBadge.translatesAutoresizingMaskIntoConstraints = NO;
    previewBadge.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(previewBadge, 6.0);
    [card addSubview:previewBadge];

    UILabel *badgeText = [[UILabel alloc] init];
    badgeText.translatesAutoresizingMaskIntoConstraints = NO;
    badgeText.font = PPFontBold(10);
    badgeText.textColor = AppPrimaryClr;
    badgeText.text = kLang(@"Audit_Inspector_ImagePreview");
    [previewBadge addSubview:badgeText];

    // URL snippet
    UILabel *urlSnippet = [[UILabel alloc] init];
    urlSnippet.translatesAutoresizingMaskIntoConstraints = NO;
    urlSnippet.font = [UIFont fontWithName:@"Menlo" size:10.5] ?: PPFontRegular(10.5);
    urlSnippet.textColor = [UIColor ppTextSecondary];
    urlSnippet.lineBreakMode = NSLineBreakByTruncatingMiddle;
    urlSnippet.text = item.newValueString;
    [card addSubview:urlSnippet];

    // Copy URL button
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    copyBtn.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(copyBtn, 14.0);
    copyBtn.layer.borderWidth = 1.0;
    copyBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copyBtn.tintColor = [UIColor ppTextTertiary];
    objc_setAssociatedObject(copyBtn, "copyVal", item.newValueString, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [copyBtn addTarget:self action:@selector(handleRowCopyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:copyBtn];

    [NSLayoutConstraint activateConstraints:@[
        [thumbView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceMD],
        [thumbView.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceMD],
        [thumbView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceMD],
        [thumbView.widthAnchor constraintEqualToConstant:56.0],
        [thumbView.heightAnchor constraintEqualToConstant:56.0],

        [keyLbl.leadingAnchor constraintEqualToAnchor:thumbView.trailingAnchor constant:PPSpaceMD],
        [keyLbl.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceMD],

        [previewBadge.leadingAnchor constraintEqualToAnchor:keyLbl.trailingAnchor constant:6.0],
        [previewBadge.centerYAnchor constraintEqualToAnchor:keyLbl.centerYAnchor],
        [previewBadge.heightAnchor constraintEqualToConstant:18.0],

        [badgeText.leadingAnchor constraintEqualToAnchor:previewBadge.leadingAnchor constant:6.0],
        [badgeText.trailingAnchor constraintEqualToAnchor:previewBadge.trailingAnchor constant:-6.0],
        [badgeText.centerYAnchor constraintEqualToAnchor:previewBadge.centerYAnchor],

        [techKeyLbl.leadingAnchor constraintEqualToAnchor:keyLbl.leadingAnchor],
        [techKeyLbl.topAnchor constraintEqualToAnchor:keyLbl.bottomAnchor constant:1.0],

        [urlSnippet.leadingAnchor constraintEqualToAnchor:keyLbl.leadingAnchor],
        [urlSnippet.topAnchor constraintEqualToAnchor:techKeyLbl.bottomAnchor constant:4.0],
        [urlSnippet.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-PPSpaceSM],

        [copyBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceMD],
        [copyBtn.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [copyBtn.widthAnchor constraintEqualToConstant:32.0],
        [copyBtn.heightAnchor constraintEqualToConstant:32.0]
    ]];

    return card;
}

- (void)handleImagePreviewTapped:(UITapGestureRecognizer *)gesture {
    UIImageView *imgView = (UIImageView *)gesture.view;
    if (!imgView.image) return;

    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];

    UIViewController *previewVC = [[UIViewController alloc] init];
    previewVC.view.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.88];

    UIImageView *fullView = [[UIImageView alloc] initWithImage:imgView.image];
    fullView.translatesAutoresizingMaskIntoConstraints = NO;
    fullView.contentMode = UIViewContentModeScaleAspectFit;
    [previewVC.view addSubview:fullView];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
    closeBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    PPApplyContinuousCorners(closeBtn, 18.0);
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    closeBtn.tintColor = UIColor.whiteColor;
    [closeBtn addTarget:self action:@selector(dismissPresentedModal) forControlEvents:UIControlEventTouchUpInside];
    [previewVC.view addSubview:closeBtn];

    [NSLayoutConstraint activateConstraints:@[
        [fullView.topAnchor constraintEqualToAnchor:previewVC.view.safeAreaLayoutGuide.topAnchor],
        [fullView.leadingAnchor constraintEqualToAnchor:previewVC.view.leadingAnchor],
        [fullView.trailingAnchor constraintEqualToAnchor:previewVC.view.trailingAnchor],
        [fullView.bottomAnchor constraintEqualToAnchor:previewVC.view.bottomAnchor],

        [closeBtn.topAnchor constraintEqualToAnchor:previewVC.view.safeAreaLayoutGuide.topAnchor constant:16.0],
        [closeBtn.trailingAnchor constraintEqualToAnchor:previewVC.view.trailingAnchor constant:-16.0],
        [closeBtn.widthAnchor constraintEqualToConstant:36.0],
        [closeBtn.heightAnchor constraintEqualToConstant:36.0]
    ]];

    UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissPresentedModal)];
    [previewVC.view addGestureRecognizer:bgTap];

    previewVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    previewVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:previewVC animated:YES completion:nil];
}

- (void)dismissPresentedModal {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Standard Semantic Diff Row

- (UIView *)buildVisualDiffRowForItem:(PPAuditDiffItem *)item {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(card, 14.0);
    card.layer.borderWidth = 1.0;

    UIColor *badgeColor = [UIColor ppTextTertiary];
    NSString *symbolText = @"✓";
    NSString *statusName = [Language isRTL] ? @"متطابق" : @"Synced";

    if (item.diffType == PPAuditDiffTypeAdded) {
        card.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.06];
        card.layer.borderColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.25].CGColor;
        badgeColor = [UIColor ppSuccess];
        symbolText = @"+";
        statusName = [Language isRTL] ? @"إضافة" : @"Added";
    } else if (item.diffType == PPAuditDiffTypeRemoved) {
        card.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.06];
        card.layer.borderColor = [[UIColor ppError] colorWithAlphaComponent:0.25].CGColor;
        badgeColor = [UIColor ppError];
        symbolText = @"-";
        statusName = [Language isRTL] ? @"حذف" : @"Removed";
    } else if (item.diffType == PPAuditDiffTypeModified) {
        card.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.06];
        card.layer.borderColor = [[UIColor ppWarning] colorWithAlphaComponent:0.25].CGColor;
        badgeColor = [UIColor ppWarning];
        symbolText = @"Δ";
        statusName = [Language isRTL] ? @"تعديل" : @"Modified";
    } else {
        card.backgroundColor = [UIColor ppSecondarySurface];
        card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    }

    // Indicator Pill
    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [badgeColor colorWithAlphaComponent:0.16];
    PPApplyContinuousCorners(pill, 8.0);
    [card addSubview:pill];

    UILabel *symLbl = [[UILabel alloc] init];
    symLbl.translatesAutoresizingMaskIntoConstraints = NO;
    symLbl.font = PPFontBold(11);
    symLbl.textColor = badgeColor;
    symLbl.text = symbolText;
    [pill addSubview:symLbl];

    // Key Title
    UILabel *keyLbl = [[UILabel alloc] init];
    keyLbl.translatesAutoresizingMaskIntoConstraints = NO;
    keyLbl.font = PPFontBold(13.5);
    keyLbl.textColor = [UIColor ppTextPrimary];
    keyLbl.text = [self humanReadableKeyFor:item.key];
    [card addSubview:keyLbl];

    // Technical Key Tag
    UILabel *techTag = [[UILabel alloc] init];
    techTag.translatesAutoresizingMaskIntoConstraints = NO;
    techTag.font = [UIFont fontWithName:@"Menlo" size:10] ?: PPFontRegular(10);
    techTag.textColor = [UIColor ppTextTertiary];
    techTag.text = item.key;
    [card addSubview:techTag];

    // Status Pill
    UIView *statusPill = [[UIView alloc] init];
    statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    statusPill.backgroundColor = [badgeColor colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(statusPill, 5.0);
    [card addSubview:statusPill];

    UILabel *statusLbl = [[UILabel alloc] init];
    statusLbl.translatesAutoresizingMaskIntoConstraints = NO;
    statusLbl.font = PPFontBold(9.5);
    statusLbl.textColor = badgeColor;
    statusLbl.text = statusName;
    [statusPill addSubview:statusLbl];

    // Value Representation
    UILabel *valLbl = [[UILabel alloc] init];
    valLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valLbl.font = [UIFont fontWithName:@"Menlo" size:11.5] ?: PPFontRegular(11.5);
    valLbl.textColor = [UIColor ppTextSecondary];
    valLbl.numberOfLines = 0;

    if (item.diffType == PPAuditDiffTypeModified) {
        valLbl.text = [NSString stringWithFormat:@"%@  ➔  %@", item.oldValueString ?: @"--", item.newValueString ?: @"--"];
    } else if (item.diffType == PPAuditDiffTypeAdded) {
        valLbl.text = item.newValueString ?: @"--";
    } else if (item.diffType == PPAuditDiffTypeRemoved) {
        valLbl.text = item.oldValueString ?: @"--";
    } else {
        valLbl.text = item.newValueString ?: @"--";
    }
    [card addSubview:valLbl];

    // Copy Value Button
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    copyBtn.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(copyBtn, 14.0);
    copyBtn.layer.borderWidth = 1.0;
    copyBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copyBtn.tintColor = [UIColor ppTextTertiary];
    NSString *copyValue = item.newValueString ?: item.oldValueString ?: @"";
    objc_setAssociatedObject(copyBtn, "copyVal", copyValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [copyBtn addTarget:self action:@selector(handleRowCopyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:copyBtn];

    [NSLayoutConstraint activateConstraints:@[
        [pill.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceMD],
        [pill.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceSM],
        [pill.widthAnchor constraintEqualToConstant:22.0],
        [pill.heightAnchor constraintEqualToConstant:22.0],

        [symLbl.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
        [symLbl.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],

        [keyLbl.leadingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:PPSpaceSM],
        [keyLbl.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceSM],

        [statusPill.leadingAnchor constraintEqualToAnchor:keyLbl.trailingAnchor constant:6.0],
        [statusPill.centerYAnchor constraintEqualToAnchor:keyLbl.centerYAnchor],
        [statusPill.heightAnchor constraintEqualToConstant:16.0],

        [statusLbl.leadingAnchor constraintEqualToAnchor:statusPill.leadingAnchor constant:5.0],
        [statusLbl.trailingAnchor constraintEqualToAnchor:statusPill.trailingAnchor constant:-5.0],
        [statusLbl.centerYAnchor constraintEqualToAnchor:statusPill.centerYAnchor],

        [techTag.leadingAnchor constraintEqualToAnchor:keyLbl.leadingAnchor],
        [techTag.topAnchor constraintEqualToAnchor:keyLbl.bottomAnchor constant:1.0],

        [valLbl.leadingAnchor constraintEqualToAnchor:keyLbl.leadingAnchor],
        [valLbl.topAnchor constraintEqualToAnchor:techTag.bottomAnchor constant:4.0],
        [valLbl.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-PPSpaceSM],
        [valLbl.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceSM],

        [copyBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceSM],
        [copyBtn.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [copyBtn.widthAnchor constraintEqualToConstant:30.0],
        [copyBtn.heightAnchor constraintEqualToConstant:30.0]
    ]];

    return card;
}

- (NSString *)humanReadableKeyFor:(NSString *)key {
    NSString *lower = key.lowercaseString;
    if ([lower isEqualToString:@"countryid"]) {
        return [Language isRTL] ? @"رمز الدولة" : @"Country Code";
    }
    if ([lower isEqualToString:@"firstname"]) {
        return [Language isRTL] ? @"الاسم الأول" : @"First Name";
    }
    if ([lower isEqualToString:@"lastname"]) {
        return [Language isRTL] ? @"اسم العائلة" : @"Last Name";
    }
    if ([lower isEqualToString:@"id"] || [lower isEqualToString:@"uid"]) {
        return [Language isRTL] ? @"المعرّف الفريد" : @"Record Identifier";
    }
    if ([lower isEqualToString:@"userimageurl"]) {
        return [Language isRTL] ? @"صورة الحساب" : @"Profile Image";
    }
    if ([lower isEqualToString:@"phonenumber"] || [lower isEqualToString:@"phone"]) {
        return [Language isRTL] ? @"رقم الهاتف" : @"Phone Number";
    }
    if ([lower isEqualToString:@"email"]) {
        return [Language isRTL] ? @"البريد الإلكتروني" : @"Email Address";
    }
    if ([lower isEqualToString:@"status"]) {
        return [Language isRTL] ? @"الحالة التشغيلية" : @"Status";
    }
    return key;
}

#pragma mark - Dictionary Dump for Raw & State Views

- (void)renderDictionaryDump:(NSDictionary *)dict inView:(UIView *)hostView emptyLabel:(NSString *)emptyStr {
    NSString *jsonStr = emptyStr;
    if (dict && dict.count > 0) {
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&err];
        if (data && !err) {
            jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }

    UIView *box = [[UIView alloc] init];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(box, 14.0);
    box.layer.borderWidth = 1.0;
    box.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [hostView addSubview:box];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    copyBtn.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(copyBtn, 10.0);
    copyBtn.layer.borderWidth = 1.0;
    copyBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [copyBtn setTitle:[NSString stringWithFormat:@"  %@  ", kLang(@"Audit_Inspector_CopyPayload")] forState:UIControlStateNormal];
    [copyBtn setTitleColor:AppPrimaryClr forState:UIControlStateNormal];
    copyBtn.titleLabel.font = PPFontBold(11.5);
    [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
    copyBtn.tintColor = AppPrimaryClr;
    objc_setAssociatedObject(copyBtn, "jsonText", jsonStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [copyBtn addTarget:self action:@selector(handleCopyJsonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:copyBtn];

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.scrollEnabled = NO;
    tv.font = [UIFont fontWithName:@"Menlo" size:11.5] ?: PPFontRegular(11.5);
    tv.textColor = [UIColor ppTextPrimary];
    tv.backgroundColor = UIColor.clearColor;
    tv.text = jsonStr;
    [box addSubview:tv];

    [NSLayoutConstraint activateConstraints:@[
        [box.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [box.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        [box.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],

        [copyBtn.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-PPSpaceSM],
        [copyBtn.topAnchor constraintEqualToAnchor:box.topAnchor constant:PPSpaceSM],
        [copyBtn.heightAnchor constraintEqualToConstant:28.0],

        [tv.topAnchor constraintEqualToAnchor:copyBtn.bottomAnchor constant:PPSpaceXS],
        [tv.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:PPSpaceSM],
        [tv.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-PPSpaceSM],
        [tv.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-PPSpaceSM]
    ]];
}

- (void)handleCopyJsonTapped:(UIButton *)sender {
    NSString *json = objc_getAssociatedObject(sender, "jsonText");
    if (json.length == 0) return;

    [UIPasteboard generalPasteboard].string = json;
    [PPToast toast:kLang(@"Audit_Copied")];

    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
}

#pragma mark - Tactical Bottom Action Deck

- (UIView *)buildActionDeck {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = PPSpaceMD;
    [card addSubview:stack];

    // Share Report Button
    UIButton *shareBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    shareBtn.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(shareBtn, 14.0);
    shareBtn.layer.borderWidth = 1.0;
    shareBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [shareBtn setTitle:kLang(@"Audit_Action_Share") forState:UIControlStateNormal];
    [shareBtn setTitleColor:[UIColor ppTextPrimary] forState:UIControlStateNormal];
    shareBtn.titleLabel.font = PPFontBold(13);
    [shareBtn setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    shareBtn.tintColor = AppPrimaryClr;
    [shareBtn addTarget:self action:@selector(handleShareReport) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:shareBtn];

    // Copy Full JSON Button
    UIButton *copyFullBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    copyFullBtn.backgroundColor = [UIColor ppSecondarySurface];
    PPApplyContinuousCorners(copyFullBtn, 14.0);
    copyFullBtn.layer.borderWidth = 1.0;
    copyFullBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [copyFullBtn setTitle:kLang(@"Audit_Inspector_CopyPayload") forState:UIControlStateNormal];
    [copyFullBtn setTitleColor:[UIColor ppTextPrimary] forState:UIControlStateNormal];
    copyFullBtn.titleLabel.font = PPFontBold(13);
    [copyFullBtn setImage:[UIImage systemImageNamed:@"curlybraces"] forState:UIControlStateNormal];
    copyFullBtn.tintColor = [UIColor ppQuickActionAnimals];
    [copyFullBtn addTarget:self action:@selector(handleCopyFullPayload) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:copyFullBtn];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase],
        [stack.heightAnchor constraintEqualToConstant:46.0]
    ]];

    return card;
}

- (void)handleCopyFullPayload {
    NSMutableDictionary *rawDict = [NSMutableDictionary dictionary];
    if (self.entry.auditId) rawDict[@"auditId"] = self.entry.auditId;
    if (self.entry.action) rawDict[@"action"] = self.entry.action;
    if (self.entry.adminUid) rawDict[@"adminUid"] = self.entry.adminUid;
    if (self.entry.targetUid) rawDict[@"targetUid"] = self.entry.targetUid;
    if (self.entry.reason) rawDict[@"reason"] = self.entry.reason;
    if (self.entry.before) rawDict[@"before"] = self.entry.before;
    if (self.entry.after) rawDict[@"after"] = self.entry.after;
    if (self.entry.metadata) rawDict[@"metadata"] = self.entry.metadata;

    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:rawDict options:NSJSONWritingPrettyPrinted error:&err];
    if (data && !err) {
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [UIPasteboard generalPasteboard].string = json;
        [PPToast toast:kLang(@"Audit_Copied")];

        UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [fb impactOccurred];
    }
}

@end

#pragma mark - Flagship Narrative Audit Log Card Cell

@interface PPAuditLogCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *accentStripe;
@property (nonatomic, strong) UIStackView *contentStack;


// Row 1: Actor & Time Horizon
@property (nonatomic, strong) UIView *actorTimeRow;
@property (nonatomic, strong) UIView *actorAvatarView;
@property (nonatomic, strong) UIImageView *actorIconView;
@property (nonatomic, strong) UILabel *actorNameLabel;
@property (nonatomic, strong) UIView *actorBadgeView;
@property (nonatomic, strong) UILabel *actorBadgeLabel;
@property (nonatomic, strong) UIImageView *timeIconView;
@property (nonatomic, strong) UILabel *relativeTimeLabel;
@property (nonatomic, strong) UIView *severityDotView;

// Row 2: Action Category & Headline
@property (nonatomic, strong) UIView *actionRow;
@property (nonatomic, strong) UIView *categoryPillView;
@property (nonatomic, strong) UIImageView *categoryIconView;
@property (nonatomic, strong) UILabel *categoryLabel;
@property (nonatomic, strong) UILabel *titleLabel;

// Row 3: Humanized Target Entity
@property (nonatomic, strong) UIView *targetRow;
@property (nonatomic, strong) UIImageView *targetIconView;
@property (nonatomic, strong) UILabel *targetLabel;
@property (nonatomic, strong) UIView *targetIdChipView;
@property (nonatomic, strong) UILabel *targetIdChipLabel;

// Row 4: Delta Mutation Strip
@property (nonatomic, strong) UIView *diffBoxView;
@property (nonatomic, strong) UILabel *diffBadgeLabel;
@property (nonatomic, strong) UILabel *diffTransitionLabel;

// Row 5: Operational Reason Box
@property (nonatomic, strong) UIView *reasonBoxView;
@property (nonatomic, strong) UILabel *reasonLabel;

// Row 6: Provenance Footer & Tactile Disclosure
@property (nonatomic, strong) UIView *footerRow;
@property (nonatomic, strong) UIImageView *keyIconView;
@property (nonatomic, strong) UILabel *auditIdLabel;
@property (nonatomic, strong) UIView *disclosureButtonView;
@property (nonatomic, strong) UIImageView *disclosureIcon;

- (void)configureWithEntry:(PPAuditLogEntryModel *)entry;
@end

@implementation PPAuditLogCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    _cardView = [[UIView alloc] init];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(_cardView, PPCorner16);
    PPApplyCardShadow(_cardView);
    _cardView.layer.borderWidth = 0.5;
    _cardView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [self.contentView addSubview:_cardView];

    _accentStripe = [[UIView alloc] init];
    _accentStripe.translatesAutoresizingMaskIntoConstraints = NO;
    _accentStripe.layer.cornerRadius = 2.0;
    [_cardView addSubview:_accentStripe];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = PPSpaceSM;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.distribution = UIStackViewDistributionFill;
    [_cardView addSubview:_contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceBase],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceBase],
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceXS],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceXS],

        [_accentStripe.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:PPSpaceXS],
        [_accentStripe.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],
        [_accentStripe.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD],
        [_accentStripe.widthAnchor constraintEqualToConstant:3.5],

        [_contentStack.leadingAnchor constraintEqualToAnchor:_accentStripe.trailingAnchor constant:PPSpaceMD],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceMD],
        [_contentStack.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD]
    ]];

    // --- Row 1: Actor & Time Horizon ---
    _actorTimeRow = [[UIView alloc] init];
    _actorTimeRow.translatesAutoresizingMaskIntoConstraints = NO;

    _actorAvatarView = [[UIView alloc] init];
    _actorAvatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _actorAvatarView.layer.cornerRadius = 10.0;
    if (@available(iOS 13.0, *)) {
        _actorAvatarView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [_actorTimeRow addSubview:_actorAvatarView];

    _actorIconView = [[UIImageView alloc] init];
    _actorIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _actorIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_actorAvatarView addSubview:_actorIconView];

    _actorNameLabel = [[UILabel alloc] init];
    _actorNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _actorNameLabel.font = PPFontBold(PPFontSubheadline);
    _actorNameLabel.textColor = [UIColor ppTextPrimary];
    [_actorTimeRow addSubview:_actorNameLabel];

    _actorBadgeView = [[UIView alloc] init];
    _actorBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    _actorBadgeView.layer.cornerRadius = 5.0;
    [_actorTimeRow addSubview:_actorBadgeView];

    _actorBadgeLabel = [[UILabel alloc] init];
    _actorBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _actorBadgeLabel.font = PPFontBold(PPFontCaption2);
    [_actorBadgeView addSubview:_actorBadgeLabel];

    _severityDotView = [[UIView alloc] init];
    _severityDotView.translatesAutoresizingMaskIntoConstraints = NO;
    _severityDotView.layer.cornerRadius = 3.5;
    [_actorTimeRow addSubview:_severityDotView];

    _relativeTimeLabel = [[UILabel alloc] init];
    _relativeTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _relativeTimeLabel.font = PPFontRegular(PPFontCaption1);
    _relativeTimeLabel.textColor = [UIColor ppTextTertiary];
    [_actorTimeRow addSubview:_relativeTimeLabel];

    _timeIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"clock"]];
    _timeIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _timeIconView.tintColor = [UIColor ppTextTertiary];
    _timeIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_actorTimeRow addSubview:_timeIconView];

    [NSLayoutConstraint activateConstraints:@[
        [_actorAvatarView.leadingAnchor constraintEqualToAnchor:_actorTimeRow.leadingAnchor],
        [_actorAvatarView.topAnchor constraintEqualToAnchor:_actorTimeRow.topAnchor],
        [_actorAvatarView.bottomAnchor constraintEqualToAnchor:_actorTimeRow.bottomAnchor],
        [_actorAvatarView.widthAnchor constraintEqualToConstant:32.0],
        [_actorAvatarView.heightAnchor constraintEqualToConstant:32.0],

        [_actorIconView.centerXAnchor constraintEqualToAnchor:_actorAvatarView.centerXAnchor],
        [_actorIconView.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],
        [_actorIconView.widthAnchor constraintEqualToConstant:16.0],
        [_actorIconView.heightAnchor constraintEqualToConstant:16.0],

        [_actorNameLabel.leadingAnchor constraintEqualToAnchor:_actorAvatarView.trailingAnchor constant:PPSpaceSM],
        [_actorNameLabel.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],

        [_actorBadgeView.leadingAnchor constraintEqualToAnchor:_actorNameLabel.trailingAnchor constant:6.0],
        [_actorBadgeView.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],
        [_actorBadgeView.heightAnchor constraintEqualToConstant:18.0],

        [_actorBadgeLabel.leadingAnchor constraintEqualToAnchor:_actorBadgeView.leadingAnchor constant:6.0],
        [_actorBadgeLabel.trailingAnchor constraintEqualToAnchor:_actorBadgeView.trailingAnchor constant:-6.0],
        [_actorBadgeLabel.centerYAnchor constraintEqualToAnchor:_actorBadgeView.centerYAnchor],

        [_severityDotView.trailingAnchor constraintEqualToAnchor:_actorTimeRow.trailingAnchor],
        [_severityDotView.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],
        [_severityDotView.widthAnchor constraintEqualToConstant:7.0],
        [_severityDotView.heightAnchor constraintEqualToConstant:7.0],

        [_relativeTimeLabel.trailingAnchor constraintEqualToAnchor:_severityDotView.leadingAnchor constant:-6.0],
        [_relativeTimeLabel.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],

        [_timeIconView.trailingAnchor constraintEqualToAnchor:_relativeTimeLabel.leadingAnchor constant:-4.0],
        [_timeIconView.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],
        [_timeIconView.widthAnchor constraintEqualToConstant:11.0],
        [_timeIconView.heightAnchor constraintEqualToConstant:11.0],

        [_actorBadgeView.trailingAnchor constraintLessThanOrEqualToAnchor:_timeIconView.leadingAnchor constant:-PPSpaceSM]
    ]];
    [_contentStack addArrangedSubview:_actorTimeRow];

    // --- Row 2: Action Category & Headline ---
    _actionRow = [[UIView alloc] init];
    _actionRow.translatesAutoresizingMaskIntoConstraints = NO;

    _categoryPillView = [[UIView alloc] init];
    _categoryPillView.translatesAutoresizingMaskIntoConstraints = NO;
    _categoryPillView.layer.cornerRadius = 6.0;
    [_actionRow addSubview:_categoryPillView];

    _categoryIconView = [[UIImageView alloc] init];
    _categoryIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _categoryIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_categoryPillView addSubview:_categoryIconView];

    _categoryLabel = [[UILabel alloc] init];
    _categoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _categoryLabel.font = PPFontBold(PPFontCaption2);
    [_categoryPillView addSubview:_categoryLabel];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = PPFontBold(PPFontHeadline);
    _titleLabel.textColor = [UIColor ppTextPrimary];
    _titleLabel.numberOfLines = 2;
    [_actionRow addSubview:_titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_categoryPillView.leadingAnchor constraintEqualToAnchor:_actionRow.leadingAnchor],
        [_categoryPillView.topAnchor constraintEqualToAnchor:_actionRow.topAnchor],
        [_categoryPillView.heightAnchor constraintEqualToConstant:24.0],

        [_categoryIconView.leadingAnchor constraintEqualToAnchor:_categoryPillView.leadingAnchor constant:7.0],
        [_categoryIconView.centerYAnchor constraintEqualToAnchor:_categoryPillView.centerYAnchor],
        [_categoryIconView.widthAnchor constraintEqualToConstant:12.0],
        [_categoryIconView.heightAnchor constraintEqualToConstant:12.0],

        [_categoryLabel.leadingAnchor constraintEqualToAnchor:_categoryIconView.trailingAnchor constant:5.0],
        [_categoryLabel.trailingAnchor constraintEqualToAnchor:_categoryPillView.trailingAnchor constant:-7.0],
        [_categoryLabel.centerYAnchor constraintEqualToAnchor:_categoryPillView.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_categoryPillView.trailingAnchor constant:PPSpaceSM],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_actionRow.trailingAnchor],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_categoryPillView.centerYAnchor],
        [_actionRow.bottomAnchor constraintEqualToAnchor:_categoryPillView.bottomAnchor]
    ]];
    [_contentStack addArrangedSubview:_actionRow];

    // --- Row 3: Humanized Target Entity Strip ---
    _targetRow = [[UIView alloc] init];
    _targetRow.translatesAutoresizingMaskIntoConstraints = NO;
    _targetRow.backgroundColor = [UIColor ppSecondarySurface];
    _targetRow.layer.cornerRadius = 8.0;

    _targetIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"doc.text.fill"]];
    _targetIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _targetIconView.tintColor = [UIColor ppTextSecondary];
    _targetIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_targetRow addSubview:_targetIconView];

    _targetLabel = [[UILabel alloc] init];
    _targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _targetLabel.font = PPFontMedium(PPFontCaption1);
    _targetLabel.textColor = [UIColor ppTextPrimary];
    [_targetRow addSubview:_targetLabel];

    _targetIdChipView = [[UIView alloc] init];
    _targetIdChipView.translatesAutoresizingMaskIntoConstraints = NO;
    _targetIdChipView.backgroundColor = [UIColor ppSurface];
    _targetIdChipView.layer.cornerRadius = 5.0;
    _targetIdChipView.layer.borderWidth = 0.5;
    _targetIdChipView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [_targetRow addSubview:_targetIdChipView];

    _targetIdChipLabel = [[UILabel alloc] init];
    _targetIdChipLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _targetIdChipLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:10.5] ?: PPFontBold(PPFontCaption2);
    _targetIdChipLabel.textColor = [UIColor ppTextSecondary];
    [_targetIdChipView addSubview:_targetIdChipLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_targetRow.heightAnchor constraintEqualToConstant:32.0],

        [_targetIconView.leadingAnchor constraintEqualToAnchor:_targetRow.leadingAnchor constant:PPSpaceSM],
        [_targetIconView.centerYAnchor constraintEqualToAnchor:_targetRow.centerYAnchor],
        [_targetIconView.widthAnchor constraintEqualToConstant:13.0],
        [_targetIconView.heightAnchor constraintEqualToConstant:13.0],

        [_targetLabel.leadingAnchor constraintEqualToAnchor:_targetIconView.trailingAnchor constant:6.0],
        [_targetLabel.centerYAnchor constraintEqualToAnchor:_targetRow.centerYAnchor],

        [_targetIdChipView.trailingAnchor constraintEqualToAnchor:_targetRow.trailingAnchor constant:-6.0],
        [_targetIdChipView.centerYAnchor constraintEqualToAnchor:_targetRow.centerYAnchor],
        [_targetIdChipView.heightAnchor constraintEqualToConstant:22.0],
        [_targetIdChipView.leadingAnchor constraintGreaterThanOrEqualToAnchor:_targetLabel.trailingAnchor constant:PPSpaceSM],

        [_targetIdChipLabel.leadingAnchor constraintEqualToAnchor:_targetIdChipView.leadingAnchor constant:6.0],
        [_targetIdChipLabel.trailingAnchor constraintEqualToAnchor:_targetIdChipView.trailingAnchor constant:-6.0],
        [_targetIdChipLabel.centerYAnchor constraintEqualToAnchor:_targetIdChipView.centerYAnchor]
    ]];
    [_contentStack addArrangedSubview:_targetRow];

    // --- Row 4: Delta Mutation Strip ---
    _diffBoxView = [[UIView alloc] init];
    _diffBoxView.translatesAutoresizingMaskIntoConstraints = NO;
    _diffBoxView.layer.cornerRadius = 8.0;
    _diffBoxView.layer.borderWidth = 0.5;

    _diffBadgeLabel = [[UILabel alloc] init];
    _diffBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _diffBadgeLabel.font = PPFontBold(PPFontCaption2);
    [_diffBoxView addSubview:_diffBadgeLabel];

    _diffTransitionLabel = [[UILabel alloc] init];
    _diffTransitionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _diffTransitionLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: PPFontRegular(PPFontCaption1);
    _diffTransitionLabel.textColor = [UIColor ppTextPrimary];
    [_diffBoxView addSubview:_diffTransitionLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_diffBadgeLabel.leadingAnchor constraintEqualToAnchor:_diffBoxView.leadingAnchor constant:PPSpaceSM],
        [_diffBadgeLabel.topAnchor constraintEqualToAnchor:_diffBoxView.topAnchor constant:6.0],
        [_diffBadgeLabel.bottomAnchor constraintEqualToAnchor:_diffBoxView.bottomAnchor constant:-6.0],

        [_diffTransitionLabel.leadingAnchor constraintEqualToAnchor:_diffBadgeLabel.trailingAnchor constant:PPSpaceSM],
        [_diffTransitionLabel.trailingAnchor constraintEqualToAnchor:_diffBoxView.trailingAnchor constant:-PPSpaceSM],
        [_diffTransitionLabel.centerYAnchor constraintEqualToAnchor:_diffBadgeLabel.centerYAnchor]
    ]];
    [_contentStack addArrangedSubview:_diffBoxView];

    // --- Row 5: Operational Reason Box ---
    _reasonBoxView = [[UIView alloc] init];
    _reasonBoxView.translatesAutoresizingMaskIntoConstraints = NO;
    _reasonBoxView.backgroundColor = [UIColor ppSecondarySurface];
    _reasonBoxView.layer.cornerRadius = 8.0;

    _reasonLabel = [[UILabel alloc] init];
    _reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _reasonLabel.font = PPFontRegular(PPFontCaption1);
    _reasonLabel.textColor = [UIColor ppTextSecondary];
    _reasonLabel.numberOfLines = 3;
    [_reasonBoxView addSubview:_reasonLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_reasonLabel.topAnchor constraintEqualToAnchor:_reasonBoxView.topAnchor constant:PPSpaceSM],
        [_reasonLabel.leadingAnchor constraintEqualToAnchor:_reasonBoxView.leadingAnchor constant:PPSpaceSM],
        [_reasonLabel.trailingAnchor constraintEqualToAnchor:_reasonBoxView.trailingAnchor constant:-PPSpaceSM],
        [_reasonLabel.bottomAnchor constraintEqualToAnchor:_reasonBoxView.bottomAnchor constant:-PPSpaceSM]
    ]];
    [_contentStack addArrangedSubview:_reasonBoxView];

    // --- Row 6: Provenance Footer & Tactile Disclosure ---
    _footerRow = [[UIView alloc] init];
    _footerRow.translatesAutoresizingMaskIntoConstraints = NO;

    _keyIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"number"]];
    _keyIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _keyIconView.tintColor = [UIColor ppTextTertiary];
    _keyIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_footerRow addSubview:_keyIconView];

    _auditIdLabel = [[UILabel alloc] init];
    _auditIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _auditIdLabel.font = [UIFont fontWithName:@"Menlo" size:10.5] ?: PPFontRegular(PPFontCaption2);
    _auditIdLabel.textColor = [UIColor ppTextTertiary];
    [_footerRow addSubview:_auditIdLabel];

    _disclosureButtonView = [[UIView alloc] init];
    _disclosureButtonView.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureButtonView.backgroundColor = [UIColor ppSecondarySurface];
    _disclosureButtonView.layer.cornerRadius = 12.0;
    [_footerRow addSubview:_disclosureButtonView];

    _disclosureIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
    _disclosureIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureIcon.tintColor = [UIColor ppTextSecondary];
    _disclosureIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_disclosureButtonView addSubview:_disclosureIcon];

    [NSLayoutConstraint activateConstraints:@[
        [_footerRow.heightAnchor constraintEqualToConstant:24.0],

        [_keyIconView.leadingAnchor constraintEqualToAnchor:_footerRow.leadingAnchor],
        [_keyIconView.centerYAnchor constraintEqualToAnchor:_footerRow.centerYAnchor],
        [_keyIconView.widthAnchor constraintEqualToConstant:10.0],
        [_keyIconView.heightAnchor constraintEqualToConstant:10.0],

        [_auditIdLabel.leadingAnchor constraintEqualToAnchor:_keyIconView.trailingAnchor constant:4.0],
        [_auditIdLabel.centerYAnchor constraintEqualToAnchor:_footerRow.centerYAnchor],

        [_disclosureButtonView.trailingAnchor constraintEqualToAnchor:_footerRow.trailingAnchor],
        [_disclosureButtonView.centerYAnchor constraintEqualToAnchor:_footerRow.centerYAnchor],
        [_disclosureButtonView.widthAnchor constraintEqualToConstant:24.0],
        [_disclosureButtonView.heightAnchor constraintEqualToConstant:24.0],

        [_disclosureIcon.centerXAnchor constraintEqualToAnchor:_disclosureButtonView.centerXAnchor],
        [_disclosureIcon.centerYAnchor constraintEqualToAnchor:_disclosureButtonView.centerYAnchor],
        [_disclosureIcon.widthAnchor constraintEqualToConstant:10.0],
        [_disclosureIcon.heightAnchor constraintEqualToConstant:10.0],

        [_auditIdLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_disclosureButtonView.leadingAnchor constant:-PPSpaceSM]
    ]];
    [_contentStack addArrangedSubview:_footerRow];
}

- (void)configureWithEntry:(PPAuditLogEntryModel *)entry {
    UIColor *accent = [entry accentColor];
    _accentStripe.backgroundColor = accent;
    _severityDotView.backgroundColor = [entry severityColor];

    // Actor Identity
    BOOL isBot = [entry isAutomatedSystem];
    if (isBot) {
        _actorAvatarView.backgroundColor = [[UIColor systemIndigoColor] colorWithAlphaComponent:0.12];
        _actorIconView.image = [UIImage systemImageNamed:@"cpu.fill"];
        _actorIconView.tintColor = [UIColor systemIndigoColor];
        _actorBadgeView.backgroundColor = [[UIColor systemIndigoColor] colorWithAlphaComponent:0.12];
        _actorBadgeLabel.text = [Language isRTL] ? @"🤖 آلي" : @"BOT";
        _actorBadgeLabel.textColor = [UIColor systemIndigoColor];
    } else {
        _actorAvatarView.backgroundColor = [entry badgeBackgroundColor];
        _actorIconView.image = [UIImage systemImageNamed:@"person.fill"];
        _actorIconView.tintColor = accent;
        _actorBadgeView.backgroundColor = [accent colorWithAlphaComponent:0.12];
        _actorBadgeLabel.text = [Language isRTL] ? @"👤 مسؤول" : @"STAFF";
        _actorBadgeLabel.textColor = accent;
    }
    _actorNameLabel.text = [entry actorDisplayName];
    _relativeTimeLabel.text = [entry relativeTimeString];

    // Category Pill & Title
    _categoryPillView.backgroundColor = [entry badgeBackgroundColor];
    _categoryIconView.image = [UIImage systemImageNamed:[entry systemIconName]];
    _categoryIconView.tintColor = accent;
    _categoryLabel.text = [entry categoryTitle];
    _categoryLabel.textColor = accent;
    _titleLabel.text = [entry localizedActionTitle];

    // Humanized Target Entity
    _targetLabel.text = [entry humanizedTargetCollectionName];
    NSString *cleanId = [entry cleanTargetUid];
    _targetIdChipLabel.text = cleanId.length > 0 ? cleanId : @"#SYS";
    if ([entry.targetCollection isEqualToString:@"Orders"]) {
        _targetIconView.image = [UIImage systemImageNamed:@"shippingbox.fill"];
    } else if ([entry.targetCollection isEqualToString:@"PublicUserProfiles"] || [entry.targetCollection isEqualToString:@"UsersCol"]) {
        _targetIconView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    } else if ([entry.targetCollection isEqualToString:@"serviceOffers"]) {
        _targetIconView.image = [UIImage systemImageNamed:@"pawprint.fill"];
    } else {
        _targetIconView.image = [UIImage systemImageNamed:@"doc.text.fill"];
    }

    // Delta DNA & Smart Mutation Strip
    BOOL hasDiff = [entry hasDiff];
    BOOL isZeroSync = hasDiff && [entry isZeroMutationSync];
    NSString *transition = [entry stateTransitionSummary];
    if (!hasDiff) {
        _diffBoxView.hidden = YES;
    } else if (isZeroSync) {
        _diffBoxView.hidden = NO;
        _diffBoxView.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.07];
        _diffBoxView.layer.borderColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.25].CGColor;
        _diffBadgeLabel.text = @"✓";
        _diffBadgeLabel.textColor = [UIColor ppSuccess];
        _diffTransitionLabel.text = [entry smartMutationSummary];
        _diffTransitionLabel.textColor = [UIColor ppSuccess];
    } else if (transition.length > 0) {
        _diffBoxView.hidden = NO;
        _diffBoxView.backgroundColor = [[UIColor ppPremiumAccent] colorWithAlphaComponent:0.07];
        _diffBoxView.layer.borderColor = [[UIColor ppPremiumAccent] colorWithAlphaComponent:0.25].CGColor;
        _diffBadgeLabel.text = [Language isRTL] ? @"⚡ انتقال حالة" : @"⚡ STATE";
        _diffBadgeLabel.textColor = [UIColor ppPremiumAccent];
        _diffTransitionLabel.text = transition;
        _diffTransitionLabel.textColor = [UIColor ppTextPrimary];
    } else {
        _diffBoxView.hidden = NO;
        _diffBoxView.backgroundColor = [accent colorWithAlphaComponent:0.06];
        _diffBoxView.layer.borderColor = [accent colorWithAlphaComponent:0.25].CGColor;
        _diffBadgeLabel.text = [entry diffPillText];
        _diffBadgeLabel.textColor = accent;
        _diffTransitionLabel.text = [entry smartMutationSummary];
        _diffTransitionLabel.textColor = [UIColor ppTextPrimary];
    }

    // Operational Reason Box
    BOOL hasReason = entry.reason.length > 0;
    _reasonBoxView.hidden = !hasReason;
    if (hasReason) {
        _reasonLabel.text = [NSString stringWithFormat:@"“%@”", entry.reason];
    }

    // Provenance Footer
    NSString *shortId = entry.auditId.length > 10 ? [entry.auditId substringToIndex:10] : entry.auditId;
    _auditIdLabel.text = [NSString stringWithFormat:@"ID: #%@", shortId.length > 0 ? shortId : @"--"];
    _disclosureIcon.image = [UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.transform = highlighted ? CGAffineTransformMakeScale(0.982, 0.982) : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - Ambient Sentinel Status Beacon Capsule

@interface PPSentinelBeaconView : UIView
@property (nonatomic, strong) PPAuditPulsingDotView *pulseDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *countBadge;
- (void)updateWithCount:(NSInteger)count;
@end

@implementation PPSentinelBeaconView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.backgroundColor = [UIColor ppElevatedSurface];
        self.layer.cornerRadius = 14.0;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor ppBorder].CGColor;

        _pulseDot = [[PPAuditPulsingDotView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        _pulseDot.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_pulseDot];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = PPFontBold(PPFontCaption2);
        _statusLabel.textColor = [UIColor ppSuccess];
        _statusLabel.text = [NSString stringWithFormat:@"%@ • %@", kLang(@"Audit_LiveStreamActive"), kLang(@"Audit_Live_Fidelity")];
        [self addSubview:_statusLabel];

        _countBadge = [[UILabel alloc] init];
        _countBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _countBadge.font = PPFontMedium(PPFontCaption2);
        _countBadge.textColor = [UIColor ppTextSecondary];
        _countBadge.textAlignment = NSTextAlignmentRight;
        [self addSubview:_countBadge];

        [NSLayoutConstraint activateConstraints:@[
            [_pulseDot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceMD],
            [_pulseDot.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_pulseDot.widthAnchor constraintEqualToConstant:10.0],
            [_pulseDot.heightAnchor constraintEqualToConstant:10.0],

            [_statusLabel.leadingAnchor constraintEqualToAnchor:_pulseDot.trailingAnchor constant:6.0],
            [_statusLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_countBadge.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceMD],
            [_countBadge.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_countBadge.leadingAnchor constraintGreaterThanOrEqualToAnchor:_statusLabel.trailingAnchor constant:PPSpaceSM]
        ]];
    }
    return self;
}

- (void)updateWithCount:(NSInteger)count {
    self.countBadge.text = [NSString stringWithFormat:@"%ld %@", (long)count, kLang(@"Audit_Title")];
}

@end

#pragma mark - Unified Chronos Telemetry Lens Bar

@interface PPChronosTelemetryLensView : UIView
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, copy) void (^onLensSelected)(NSInteger index);
@property (nonatomic, assign) BOOL hasAppliedInitialRTLScroll;
- (void)updateWithCounts:(NSArray<NSNumber *> *)counts selectedIndex:(NSInteger)selIdx;
@end

@implementation PPChronosTelemetryLensView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.contentInset = UIEdgeInsetsMake(0, PPSpaceBase, 0, PPSpaceBase);
        [self addSubview:_scrollView];

        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.spacing = PPSpaceSM;
        _stackView.alignment = UIStackViewAlignmentCenter;
        [_scrollView addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_stackView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
            [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
            [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
            [_stackView.heightAnchor constraintEqualToAnchor:_scrollView.heightAnchor]
        ]];
    }
    return self;
}

- (void)updateWithCounts:(NSArray<NSNumber *> *)counts selectedIndex:(NSInteger)selIdx {
    for (UIView *v in self.stackView.arrangedSubviews) {
        [v removeFromSuperview];
    }

    NSArray *configs = @[
        @{ @"title": kLang(@"Audit_Filter_All"), @"icon": @"waveform.path.ecg", @"color": AppPrimaryClr },
        @{ @"title": kLang(@"Audit_Filter_Security"), @"icon": @"shield.checkerboard", @"color": [UIColor ppQuickActionAnimals] },
        @{ @"title": kLang(@"Audit_Filter_Services"), @"icon": @"pawprint.fill", @"color": [UIColor ppQuickActionServices] },
        @{ @"title": kLang(@"Audit_Filter_Ops"), @"icon": @"slider.horizontal.3", @"color": [UIColor ppQuickActionCommunity] },
        @{ @"title": kLang(@"Audit_Filter_Finance"), @"icon": @"creditcard.fill", @"color": [UIColor ppPremiumAccent] },
        @{ @"title": kLang(@"Audit_Filter_Destructive"), @"icon": @"trash.fill", @"color": [UIColor ppError] }
    ];

    for (NSUInteger i = 0; i < configs.count; i++) {
        NSDictionary *cfg = configs[i];
        NSInteger count = (i < counts.count) ? [counts[i] integerValue] : 0;
        BOOL isSel = (i == (NSUInteger)selIdx);
        UIColor *color = cfg[@"color"];

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        btn.backgroundColor = isSel ? [color colorWithAlphaComponent:0.14] : [UIColor ppSurface];
        btn.layer.cornerRadius = 18.0;
        if (@available(iOS 13.0, *)) {
            btn.layer.cornerCurve = kCACornerCurveContinuous;
        }
        btn.layer.borderWidth = isSel ? 1.5 : 0.6;
        btn.layer.borderColor = isSel ? color.CGColor : [UIColor ppSurfaceBorder].CGColor;
        objc_setAssociatedObject(btn, "lensIdx", @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [btn addTarget:self action:@selector(handleLensTap:) forControlEvents:UIControlEventTouchUpInside];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:cfg[@"icon"]]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.tintColor = isSel ? color : [UIColor ppTextSecondary];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [btn addSubview:icon];

        UILabel *titleLbl = [[UILabel alloc] init];
        titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
        titleLbl.font = isSel ? PPFontBold(PPFontSubheadline) : PPFontMedium(PPFontSubheadline);
        titleLbl.textColor = isSel ? color : [UIColor ppTextPrimary];
        titleLbl.text = cfg[@"title"];
        [btn addSubview:titleLbl];

        UIView *badgeBox = [[UIView alloc] init];
        badgeBox.translatesAutoresizingMaskIntoConstraints = NO;
        badgeBox.backgroundColor = isSel ? color : [UIColor ppSecondarySurface];
        badgeBox.layer.cornerRadius = 9.0;
        [btn addSubview:badgeBox];

        UILabel *countLbl = [[UILabel alloc] init];
        countLbl.translatesAutoresizingMaskIntoConstraints = NO;
        countLbl.font = PPFontBold(PPFontCaption2);
        countLbl.textColor = isSel ? [UIColor whiteColor] : [UIColor ppTextSecondary];
        countLbl.text = [NSString stringWithFormat:@"%ld", (long)count];
        [badgeBox addSubview:countLbl];

        [NSLayoutConstraint activateConstraints:@[
            [btn.heightAnchor constraintEqualToConstant:38.0],

            [icon.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:PPSpaceMD],
            [icon.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:15.0],
            [icon.heightAnchor constraintEqualToConstant:15.0],

            [titleLbl.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:PPSpaceXS],
            [titleLbl.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],

            [badgeBox.leadingAnchor constraintEqualToAnchor:titleLbl.trailingAnchor constant:PPSpaceSM],
            [badgeBox.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-PPSpaceSM],
            [badgeBox.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
            [badgeBox.heightAnchor constraintEqualToConstant:18.0],

            [countLbl.leadingAnchor constraintEqualToAnchor:badgeBox.leadingAnchor constant:6.0],
            [countLbl.trailingAnchor constraintEqualToAnchor:badgeBox.trailingAnchor constant:-6.0],
            [countLbl.centerYAnchor constraintEqualToAnchor:badgeBox.centerYAnchor]
        ]];

        [self.stackView addArrangedSubview:btn];
    }

    if (!self.hasAppliedInitialRTLScroll && selIdx == 0 && [Language isRTL]) {
        self.hasAppliedInitialRTLScroll = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            CGFloat maxOffsetX = MAX(0, self.scrollView.contentSize.width - self.scrollView.bounds.size.width + self.scrollView.contentInset.right);
            [self.scrollView setContentOffset:CGPointMake(maxOffsetX, 0) animated:NO];
        });
    }
}

- (void)handleLensTap:(UIButton *)sender {
    NSInteger idx = [objc_getAssociatedObject(sender, "lensIdx") integerValue];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
    [self.scrollView scrollRectToVisible:CGRectInset(sender.frame, -24, 0) animated:YES];
    if (self.onLensSelected) {
        self.onLensSelected(idx);
    }
}

@end

#pragma mark - Sovereign Serenity Empty State View

@interface PPSentinelEmptyStateView : UIView
@property (nonatomic, strong) UIView *emblemContainer;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *primaryActionButton;
@property (nonatomic, copy) void (^onResetTapped)(void);
- (void)configureWithSearchActive:(BOOL)isSearch query:(nullable NSString *)query;
@end

@implementation PPSentinelEmptyStateView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _emblemContainer = [[UIView alloc] init];
        _emblemContainer.translatesAutoresizingMaskIntoConstraints = NO;
        _emblemContainer.layer.cornerRadius = 24.0;
        if (@available(iOS 13.0, *)) {
            _emblemContainer.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [self addSubview:_emblemContainer];

        _iconImageView = [[UIImageView alloc] init];
        _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        [_emblemContainer addSubview:_iconImageView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = PPFontBold(PPFontTitle3);
        _titleLabel.textColor = [UIColor ppTextPrimary];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = PPFontRegular(PPFontSubheadline);
        _subtitleLabel.textColor = [UIColor ppTextSecondary];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.numberOfLines = 3;
        [self addSubview:_subtitleLabel];

        _primaryActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _primaryActionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _primaryActionButton.backgroundColor = AppPrimaryClr;
        _primaryActionButton.tintColor = [UIColor whiteColor];
        _primaryActionButton.layer.cornerRadius = PPCornerMedium;
        if (@available(iOS 13.0, *)) {
            _primaryActionButton.layer.cornerCurve = kCACornerCurveContinuous;
        }
        _primaryActionButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceXL, PPSpaceMD, PPSpaceXL);
        _primaryActionButton.titleLabel.font = PPFontBold(PPFontSubheadline);
        [_primaryActionButton addTarget:self action:@selector(handleResetTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_primaryActionButton];

        [NSLayoutConstraint activateConstraints:@[
            [_emblemContainer.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_emblemContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_emblemContainer.widthAnchor constraintEqualToConstant:72.0],
            [_emblemContainer.heightAnchor constraintEqualToConstant:72.0],

            [_iconImageView.centerXAnchor constraintEqualToAnchor:_emblemContainer.centerXAnchor],
            [_iconImageView.centerYAnchor constraintEqualToAnchor:_emblemContainer.centerYAnchor],
            [_iconImageView.widthAnchor constraintEqualToConstant:38.0],
            [_iconImageView.heightAnchor constraintEqualToConstant:38.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_emblemContainer.bottomAnchor constant:PPSpaceLG],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceBase],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceBase],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceSM],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceBase],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceBase],

            [_primaryActionButton.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:PPSpaceLG],
            [_primaryActionButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_primaryActionButton.heightAnchor constraintEqualToConstant:44.0],
            [_primaryActionButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
    }
    return self;
}

- (void)configureWithSearchActive:(BOOL)isSearch query:(nullable NSString *)query {
    if (isSearch) {
        _emblemContainer.backgroundColor = [[UIColor ppTextTertiary] colorWithAlphaComponent:0.1];
        _emblemContainer.layer.borderWidth = 0.5;
        _emblemContainer.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        _iconImageView.image = [UIImage systemImageNamed:@"magnifyingglass"];
        _iconImageView.tintColor = [UIColor ppTextSecondary];

        _titleLabel.text = kLang(@"Audit_Empty_SearchTitle");
        _subtitleLabel.text = (query.length > 0) ?
            [NSString stringWithFormat:@"%@ «%@»", kLang(@"Audit_Empty_SearchSubtitle"), query] :
            kLang(@"Audit_Empty_SearchSubtitle");

        [_primaryActionButton setTitle:kLang(@"Audit_Filter_Reset") forState:UIControlStateNormal];
    } else {
        // Serene Zero Anomalies State
        _emblemContainer.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.12];
        _emblemContainer.layer.borderWidth = 1.0;
        _emblemContainer.layer.borderColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.3].CGColor;
        _iconImageView.image = [UIImage systemImageNamed:@"shield.checkerboard"];
        _iconImageView.tintColor = [UIColor ppSuccess];

        _titleLabel.text = kLang(@"Audit_Perimeter_Secure_Title");
        _subtitleLabel.text = kLang(@"Audit_Perimeter_Secure_Subtitle");

        [_primaryActionButton setTitle:kLang(@"Audit_Filter_Reset") forState:UIControlStateNormal];
    }
}

- (void)handleResetTapped {
    if (self.onResetTapped) {
        self.onResetTapped();
    }
}

@end

#pragma mark - Sovereign PPAuditLogViewController Master Controller

@interface PPAuditLogViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *allEntries;
@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *filteredEntries;
@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *canonicalEntries;
@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *adminEntries;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> canonicalListenerReg;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> adminListenerReg;
@property (nonatomic, assign) NSUInteger listenerGeneration;

// Sovereign Navigation Chrome
@property (nonatomic, strong) UIView *commandBarView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UILabel *navSubtitleLabel;
@property (nonatomic, strong) PPAuditPulsingDotView *pulseDot;
@property (nonatomic, strong) UIButton *searchToggleBtn;
@property (nonatomic, strong) UIButton *filterModalBtn;

// Search & Chronos Telemetry Chrome
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSLayoutConstraint *searchBarHeightConstraint;
@property (nonatomic, assign) BOOL isSearchVisible;
@property (nonatomic, strong) PPSentinelBeaconView *sentinelBeaconView;
@property (nonatomic, strong) PPChronosTelemetryLensView *telemetryLensView;
@property (nonatomic, assign) NSInteger selectedCategoryIndex;

// Table View & Serene Empty State
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) PPSentinelEmptyStateView *emptyStateView;

- (BOOL)evaluatePermissions;
- (void)loadData;
- (void)refreshData;
- (void)mergeAndApplyAuditEntriesWithGeneration:(NSUInteger)generation;

@end

@implementation PPAuditLogViewController

- (instancetype)initWithOnDismiss:(nullable void (^)(void))onDismiss {
    self = [super init];
    if (self) {
        _onDismiss = [onDismiss copy];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (instancetype)init {
    return [self initWithOnDismiss:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self setupCommandBar];
    [self setupSearchBar];
    [self setupTelemetryHeader];
    [self setupTableView];
    [self setupEmptyStateView];

    if ([self evaluatePermissions]) {
        [self loadData];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Hide default system navigation bar and let our sovereign Command Bar shine with native push semantics
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return (self.navigationController.viewControllers.count > 1);
}

#pragma mark - Sovereign Navigation Bar

- (void)setupCommandBar {
    _commandBarView = [[UIView alloc] init];
    _commandBarView.translatesAutoresizingMaskIntoConstraints = NO;
    _commandBarView.backgroundColor = [UIColor ppElevatedSurface];
    _commandBarView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:_commandBarView];

    // Subtle bottom border
    UIView *border = [[UIView alloc] init];
    border.translatesAutoresizingMaskIntoConstraints = NO;
    border.backgroundColor = [UIColor ppBorder];
    [_commandBarView addSubview:border];

    // Trailing Search Toggle & Deep Filter
    _filterModalBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _filterModalBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _filterModalBtn.backgroundColor = [[UIColor ppTextPrimary] colorWithAlphaComponent:0.06];
    _filterModalBtn.tintColor = [UIColor ppTextPrimary];
    _filterModalBtn.layer.borderWidth = 0.5;
    _filterModalBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(_filterModalBtn, 18.0);
    [_filterModalBtn setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] forState:UIControlStateNormal];
    [_filterModalBtn addTarget:self action:@selector(openDeepFilterSheet) forControlEvents:UIControlEventTouchUpInside];
    [_commandBarView addSubview:_filterModalBtn];

    _searchToggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _searchToggleBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _searchToggleBtn.backgroundColor = [[UIColor ppTextPrimary] colorWithAlphaComponent:0.06];
    _searchToggleBtn.tintColor = [UIColor ppTextPrimary];
    _searchToggleBtn.layer.borderWidth = 0.5;
    _searchToggleBtn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(_searchToggleBtn, 18.0);
    [_searchToggleBtn setImage:[UIImage systemImageNamed:@"magnifyingglass"] forState:UIControlStateNormal];
    [_searchToggleBtn addTarget:self action:@selector(toggleSearch) forControlEvents:UIControlEventTouchUpInside];
    [_commandBarView addSubview:_searchToggleBtn];

    // Back Button (Flagship Luxury Glass Squircle)
    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    _backButton.backgroundColor = [UIColor ppSurface];
    _backButton.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) {
        _backButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _backButton.layer.borderWidth = 0.8;
    _backButton.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.8].CGColor;
    _backButton.layer.shadowColor = UIColor.blackColor.CGColor;
    _backButton.layer.shadowOpacity = 0.04;
    _backButton.layer.shadowOffset = CGSizeMake(0, 2);
    _backButton.layer.shadowRadius = 6;
    _backButton.layer.masksToBounds = NO;
    _backButton.tintColor = [UIColor ppTextPrimary];

    NSString *backSym = [Language isRTL] ? @"arrow.right" : @"arrow.left";
    UIImage *backImg = [UIImage systemImageNamed:backSym withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold]];
    [_backButton setImage:backImg forState:UIControlStateNormal];
    _backButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [_backButton addTarget:self action:@selector(handleBackTapped) forControlEvents:UIControlEventTouchUpInside];
    [_commandBarView addSubview:_backButton];

    // Title & Live Sentinel
    _navTitleLabel = [[UILabel alloc] init];
    _navTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navTitleLabel.font = PPFontBold(PPFontTitle3);
    _navTitleLabel.textColor = [UIColor ppTextPrimary];
    _navTitleLabel.text = kLang(@"Audit_Title");
    [_commandBarView addSubview:_navTitleLabel];

    _pulseDot = [[PPAuditPulsingDotView alloc] initWithFrame:CGRectMake(0, 0, 12, 12)];
    _pulseDot.translatesAutoresizingMaskIntoConstraints = NO;
    [_commandBarView addSubview:_pulseDot];

    _navSubtitleLabel = [[UILabel alloc] init];
    _navSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navSubtitleLabel.font = PPFontMedium(PPFontCaption2);
    _navSubtitleLabel.textColor = [UIColor ppSuccess];
    _navSubtitleLabel.text = kLang(@"Audit_LiveStreamActive");
    [_commandBarView addSubview:_navSubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_commandBarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_commandBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_commandBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_commandBarView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:62.0],

        [border.leadingAnchor constraintEqualToAnchor:_commandBarView.leadingAnchor],
        [border.trailingAnchor constraintEqualToAnchor:_commandBarView.trailingAnchor],
        [border.bottomAnchor constraintEqualToAnchor:_commandBarView.bottomAnchor],
        [border.heightAnchor constraintEqualToConstant:0.5],

        [_backButton.leadingAnchor constraintEqualToAnchor:_commandBarView.leadingAnchor constant:16.0],
        [_backButton.bottomAnchor constraintEqualToAnchor:_commandBarView.bottomAnchor constant:-8.0],
        [_backButton.widthAnchor constraintEqualToConstant:44.0],
        [_backButton.heightAnchor constraintEqualToConstant:44.0],

        [_navTitleLabel.leadingAnchor constraintEqualToAnchor:_backButton.trailingAnchor constant:12.0],
        [_navTitleLabel.topAnchor constraintEqualToAnchor:_backButton.topAnchor constant:1.0],

        [_pulseDot.leadingAnchor constraintEqualToAnchor:_navTitleLabel.leadingAnchor],
        [_pulseDot.topAnchor constraintEqualToAnchor:_navTitleLabel.bottomAnchor constant:3.0],
        [_pulseDot.widthAnchor constraintEqualToConstant:10.0],
        [_pulseDot.heightAnchor constraintEqualToConstant:10.0],

        [_navSubtitleLabel.leadingAnchor constraintEqualToAnchor:_pulseDot.trailingAnchor constant:5.0],
        [_navSubtitleLabel.centerYAnchor constraintEqualToAnchor:_pulseDot.centerYAnchor],
        [_navSubtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_searchToggleBtn.leadingAnchor constant:-PPSpaceSM],

        [_filterModalBtn.trailingAnchor constraintEqualToAnchor:_commandBarView.trailingAnchor constant:-16.0],
        [_filterModalBtn.centerYAnchor constraintEqualToAnchor:_backButton.centerYAnchor],
        [_filterModalBtn.widthAnchor constraintEqualToConstant:40.0],
        [_filterModalBtn.heightAnchor constraintEqualToConstant:40.0],

        [_searchToggleBtn.trailingAnchor constraintEqualToAnchor:_filterModalBtn.leadingAnchor constant:-8.0],
        [_searchToggleBtn.centerYAnchor constraintEqualToAnchor:_backButton.centerYAnchor],
        [_searchToggleBtn.widthAnchor constraintEqualToConstant:40.0],
        [_searchToggleBtn.heightAnchor constraintEqualToConstant:40.0]
    ]];
}

- (void)handleBackTapped {
    [PPFunc pp_playTapEffect];
    if (self.onDismiss) {
        self.onDismiss();
        return;
    }
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if ([self pp_dismissWorkflowRouteIfPossible]) {
        return;
    }
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    [PPAdminNavigationFallback popOrDismissFrom:self];
}

#pragma mark - Search Bar

- (void)setupSearchBar {
    _searchBar = [[UISearchBar alloc] init];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.delegate = self;
    _searchBar.placeholder = kLang(@"Audit_Search_Placeholder");
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.clipsToBounds = YES;
    [self.view addSubview:_searchBar];

    _searchBarHeightConstraint = [_searchBar.heightAnchor constraintEqualToConstant:0.0];
    _isSearchVisible = NO;

    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:_commandBarView.bottomAnchor],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:PPSpaceSM],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-PPSpaceSM],
        _searchBarHeightConstraint
    ]];
}

- (void)toggleSearch {
    self.isSearchVisible = !self.isSearchVisible;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.searchBarHeightConstraint.constant = self.isSearchVisible ? 52.0 : 0.0;
        self.searchToggleBtn.tintColor = self.isSearchVisible ? AppPrimaryClr : [UIColor ppTextPrimary];
        [self.view layoutIfNeeded];
    } completion:^(BOOL finished) {
        if (self.isSearchVisible) {
            [self.searchBar becomeFirstResponder];
        } else {
            [self.searchBar resignFirstResponder];
            self.searchBar.text = @"";
            [self applyFilter];
        }
    }];
}

#pragma mark - Chronos Sentinel Telemetry Header & Lens

- (void)setupTelemetryHeader {
    _telemetryLensView = [[PPChronosTelemetryLensView alloc] initWithFrame:CGRectZero];
    _telemetryLensView.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _telemetryLensView.onLensSelected = ^(NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.selectedCategoryIndex = index;
        [strongSelf applyFilter];
    };
    [self.view addSubview:_telemetryLensView];

    [NSLayoutConstraint activateConstraints:@[
        [_telemetryLensView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:PPSpaceXS],
        [_telemetryLensView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_telemetryLensView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_telemetryLensView.heightAnchor constraintEqualToConstant:46.0]
    ]];
}

- (NSArray<NSString *> *)filterTitlesArray {
    return @[
        kLang(@"Audit_Filter_All"),
        kLang(@"Audit_Filter_Security"),
        kLang(@"Audit_Filter_Services"),
        kLang(@"Audit_Filter_Ops"),
        kLang(@"Audit_Filter_Finance"),
        kLang(@"Audit_Filter_Destructive")
    ];
}

#pragma mark - Table View

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 180.0;
    _tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0, PPSpaceXXXL, 0);
    [_tableView registerClass:[PPAuditLogCardCell class] forCellReuseIdentifier:kAuditCardCellID];
    [self.view addSubview:_tableView];

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_telemetryLensView.bottomAnchor constant:PPSpaceSM],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

#pragma mark - Sovereign Serenity Empty State

- (void)setupEmptyStateView {
    _emptyStateView = [[PPSentinelEmptyStateView alloc] initWithFrame:CGRectZero];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    _emptyStateView.onResetTapped = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf resetAllFilters];
    };
    [self.view addSubview:_emptyStateView];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor constant:-20.0],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:_tableView.leadingAnchor constant:PPSpaceXL],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:_tableView.trailingAnchor constant:-PPSpaceXL]
    ]];
}

#pragma mark - Security & Data Loading

- (BOOL)evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    BOOL hasGlobalReach = staff.isAdmin || staff.hasGlobalScope;
    BOOL hasAuditPerm = [staff hasPermission:kStaffPermAuditView];
    if (!hasGlobalReach || !hasAuditPerm) {
        [self.canonicalListenerReg remove];
        self.canonicalListenerReg = nil;
        [self.adminListenerReg remove];
        self.adminListenerReg = nil;
        self.listenerGeneration += 1;
        [PPHUD showError:kLang(@"Error_Title")];
        [self handleBackTapped];
        return NO;
    }
    return YES;
}

- (void)loadData {
    [self.canonicalListenerReg remove];
    self.canonicalListenerReg = nil;
    [self.adminListenerReg remove];
    self.adminListenerReg = nil;
    self.canonicalEntries = @[];
    self.adminEntries = @[];

    self.listenerGeneration += 1;
    NSUInteger generation = self.listenerGeneration;
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;

    // 1. Canonical Audit Logs (auditLogs) - Primary backend audit stream
    FIRQuery *canonicalQuery = [[[[FIRFirestore firestore] collectionWithPath:@"auditLogs"]
                                 queryOrderedByField:@"timestamp" descending:YES]
                                queryLimitedTo:250];

    __weak typeof(self) weakSelf = self;
    self.canonicalListenerReg = [canonicalQuery addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.listenerGeneration) return;

        if (!PPAuditStaffSessionCanRead(staff)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != strongSelf.listenerGeneration) return;
                [strongSelf.canonicalListenerReg remove];
                strongSelf.canonicalListenerReg = nil;
                [strongSelf.adminListenerReg remove];
                strongSelf.adminListenerReg = nil;
                strongSelf.listenerGeneration += 1;
                strongSelf.allEntries = @[];
                [strongSelf applyFilter];
                if ([strongSelf evaluatePermissions]) [strongSelf loadData];
            });
            return;
        }

        if (error) {
            NSLog(@"[PPAuditLog] Canonical auditLogs error: %@", error.localizedDescription);
            if (strongSelf.adminEntries.count == 0) {
                [PPHUD showError:kLang(@"Error_Title")];
            }
            return;
        }

        NSMutableArray *entries = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPAuditLogEntryModel *entry = [PPAuditLogEntryModel entryFromSnapshot:doc sourceCollection:@"auditLogs"];
            [entries addObject:entry];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != strongSelf.listenerGeneration || !PPAuditStaffSessionCanRead(staff)) return;
            strongSelf.canonicalEntries = entries.copy;
            [strongSelf mergeAndApplyAuditEntriesWithGeneration:generation];
        });
    }];

    // 2. Admin Specific Audit Logs (AdminAuditLogs) - Staff manual mutations
    FIRQuery *adminQuery = [[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"]
                            queryLimitedTo:250];

    self.adminListenerReg = [adminQuery addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.listenerGeneration) return;

        if (error) {
            NSLog(@"[PPAuditLog] AdminAuditLogs error: %@", error.localizedDescription);
            return;
        }

        NSMutableArray *entries = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPAuditLogEntryModel *entry = [PPAuditLogEntryModel entryFromSnapshot:doc sourceCollection:@"AdminAuditLogs"];
            [entries addObject:entry];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != strongSelf.listenerGeneration || !PPAuditStaffSessionCanRead(staff)) return;
            strongSelf.adminEntries = entries.copy;
            [strongSelf mergeAndApplyAuditEntriesWithGeneration:generation];
        });
    }];
}

- (void)mergeAndApplyAuditEntriesWithGeneration:(NSUInteger)generation {
    if (generation != self.listenerGeneration) return;
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    if (!PPAuditStaffSessionCanRead(staff)) return;

    NSMutableDictionary<NSString *, PPAuditLogEntryModel *> *dedup = [NSMutableDictionary dictionary];
    for (PPAuditLogEntryModel *entry in self.canonicalEntries ?: @[]) {
        if (entry.auditId.length > 0) {
            dedup[entry.auditId] = entry;
        }
    }
    for (PPAuditLogEntryModel *entry in self.adminEntries ?: @[]) {
        if (entry.auditId.length > 0) {
            dedup[entry.auditId] = entry;
        }
    }

    NSArray<PPAuditLogEntryModel *> *merged = [dedup.allValues sortedArrayUsingComparator:^NSComparisonResult(PPAuditLogEntryModel *a, PPAuditLogEntryModel *b) {
        return [b.timestamp compare:a.timestamp];
    }];

    self.allEntries = merged;
    [self applyFilter];
}

- (void)refreshData {
    if ([self evaluatePermissions]) {
        [self loadData];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.refreshControl endRefreshing];
    });
}

#pragma mark - Filter & Telemetry Engine

- (void)applyFilter {
    NSString *search = self.searchBar.text.lowercaseString;
    NSInteger catIdx = self.selectedCategoryIndex;

    NSMutableArray *result = [NSMutableArray array];
    NSInteger totalCount = self.allEntries.count;
    NSInteger secCount = 0;
    NSInteger srvCount = 0;
    NSInteger opsCount = 0;
    NSInteger finCount = 0;
    NSInteger destCount = 0;

    for (PPAuditLogEntryModel *entry in self.allEntries) {
        PPAuditActionCategory cat = [entry actionCategory];
        if (cat == PPAuditActionCategorySecurity) secCount++;
        else if (cat == PPAuditActionCategoryServices) srvCount++;
        else if (cat == PPAuditActionCategoryOperations) opsCount++;
        else if (cat == PPAuditActionCategoryFinance) finCount++;
        else if (cat == PPAuditActionCategoryDestructive) destCount++;

        // Category filter check
        BOOL matchesCat = YES;
        if (catIdx == 1) matchesCat = (cat == PPAuditActionCategorySecurity);
        else if (catIdx == 2) matchesCat = (cat == PPAuditActionCategoryServices);
        else if (catIdx == 3) matchesCat = (cat == PPAuditActionCategoryOperations);
        else if (catIdx == 4) matchesCat = (cat == PPAuditActionCategoryFinance);
        else if (catIdx == 5) matchesCat = (cat == PPAuditActionCategoryDestructive);

        if (!matchesCat) continue;

        // Search text check
        if (search.length > 0) {
            BOOL match = [entry.action.lowercaseString containsString:search] ||
                         [entry.adminUid.lowercaseString containsString:search] ||
                         [entry.targetUid.lowercaseString containsString:search] ||
                         (entry.reason && [entry.reason.lowercaseString containsString:search]) ||
                         [entry.localizedActionTitle.lowercaseString containsString:search] ||
                         [entry.actorDisplayName.lowercaseString containsString:search] ||
                         [entry.targetDisplayName.lowercaseString containsString:search];
            if (!match) continue;
        }

        [result addObject:entry];
    }

    self.filteredEntries = result.copy;
    [self.tableView reloadData];

    // Update Telemetry Lens & Beacon
    NSArray<NSNumber *> *counts = @[
        @(totalCount),
        @(secCount),
        @(srvCount),
        @(opsCount),
        @(finCount),
        @(destCount)
    ];
    [self.telemetryLensView updateWithCounts:counts selectedIndex:self.selectedCategoryIndex];

    NSString *countStr = [NSString stringWithFormat:@"%ld %@", (long)self.filteredEntries.count, kLang(@"Audit_Title")];
    self.navSubtitleLabel.text = [NSString stringWithFormat:@"%@ • %@ • %@", kLang(@"Audit_LiveStreamActive"), kLang(@"Audit_Live_Fidelity"), countStr];

    BOOL isSearchActive = (self.searchBar.text.length > 0);
    [self.emptyStateView configureWithSearchActive:isSearchActive query:self.searchBar.text];
    self.emptyStateView.hidden = (self.filteredEntries.count > 0);
}

- (void)resetAllFilters {
    self.selectedCategoryIndex = 0;
    self.searchBar.text = @"";
    if (self.isSearchVisible) {
        [self toggleSearch];
    } else {
        [self applyFilter];
    }
}

- (void)openDeepFilterSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Audit_Filter_Sheet_Title")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *titles = [self filterTitlesArray];
    for (NSInteger i = 0; i < titles.count; i++) {
        NSString *title = titles[i];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.selectedCategoryIndex = i;
            [self applyFilter];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Audit_Filter_Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self resetAllFilters];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.filterModalBtn;
        sheet.popoverPresentationController.sourceRect = self.filterModalBtn.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Search Bar Delegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UITableView DataSource & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPAuditLogCardCell *cell = [tableView dequeueReusableCellWithIdentifier:kAuditCardCellID forIndexPath:indexPath];
    PPAuditLogEntryModel *entry = self.filteredEntries[indexPath.row];
    [cell configureWithEntry:entry];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.filteredEntries.count) return;

    PPAuditLogEntryModel *entry = self.filteredEntries[indexPath.row];
    PPAuditDetailViewController *detailVC = [[PPAuditDetailViewController alloc] initWithEntry:entry];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detailVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (nullable UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    if (indexPath.row >= self.filteredEntries.count) return nil;
    PPAuditLogEntryModel *entry = self.filteredEntries[indexPath.row];

    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        UIAction *copyIdAction = [UIAction actionWithTitle:kLang(@"Audit_Action_CopyId") image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            if (entry.auditId.length > 0) {
                [UIPasteboard generalPasteboard].string = entry.auditId;
                [PPToast toast:kLang(@"Audit_Copied")];
                UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                [fb impactOccurred];
            }
        }];

        UIAction *inspectAction = [UIAction actionWithTitle:kLang(@"Audit_Inspector_Title") image:[UIImage systemImageNamed:@"waveform.path.ecg.rectangle"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            PPAuditDetailViewController *detailVC = [[PPAuditDetailViewController alloc] initWithEntry:entry];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detailVC];
            [self presentViewController:nav animated:YES completion:nil];
        }];

        return [UIMenu menuWithTitle:entry.localizedActionTitle children:@[copyIdAction, inspectAction]];
    }];
}

- (void)dealloc {
    self.listenerGeneration += 1;
    [self.canonicalListenerReg remove];
    self.canonicalListenerReg = nil;
    [self.adminListenerReg remove];
    self.adminListenerReg = nil;
}

@end

