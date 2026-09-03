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

#pragma mark - Forensic Inspector & Visual State Diff Studio

@interface PPAuditDetailViewController : UIViewController
@property (nonatomic, strong) PPAuditLogEntryModel *entry;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UISegmentedControl *diffSegmentedControl;
@property (nonatomic, strong) UIView *diffContentView;
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
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                               target:self
                                                                               action:@selector(handleClose)];
    self.navigationItem.rightBarButtonItem = closeItem;

    UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                                  style:UIBarButtonItemStylePlain
                                                                 target:self
                                                                 action:@selector(handleShareReport)];
    self.navigationItem.leftBarButtonItem = shareItem;
}

- (void)handleClose {
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)handleShareReport {
    NSString *report = [NSString stringWithFormat:@"PurePets Audit Forensic Report\n"
                        "--------------------------------\n"
                        "Action: %@ (%@)\n"
                        "Actor Admin: %@\n"
                        "Target: %@\n"
                        "Timestamp: %@\n"
                        "Reason: %@\n"
                        "Audit ID: %@\n",
                        self.entry.localizedActionTitle, self.entry.action,
                        self.entry.adminUid, self.entry.targetUid,
                        self.entry.formattedTimestamp,
                        self.entry.reason ?: @"N/A",
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
    // 1. Forensic Header Card
    UIView *headerCard = [self buildHeaderCard];
    [_contentStack addArrangedSubview:headerCard];

    // 2. Participants Dossier (Actor & Target)
    UIView *participantsCard = [self buildParticipantsCard];
    [_contentStack addArrangedSubview:participantsCard];

    // 3. Operational Justification (Reason)
    UIView *reasonCard = [self buildReasonCard];
    [_contentStack addArrangedSubview:reasonCard];

    // 4. State Diff Section Header & Segmented Control
    UIView *diffContainer = [self buildDiffContainer];
    [_contentStack addArrangedSubview:diffContainer];
}

- (UIView *)buildHeaderCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);

    // Accent line at leading edge
    UIView *accentLine = [[UIView alloc] init];
    accentLine.translatesAutoresizingMaskIntoConstraints = NO;
    accentLine.backgroundColor = [self.entry accentColor];
    accentLine.layer.cornerRadius = 2.5;
    [card addSubview:accentLine];

    // Icon Circle
    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [self.entry badgeBackgroundColor];
    iconCircle.layer.cornerRadius = 22.0;
    [card addSubview:iconCircle];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[self.entry systemIconName]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [self.entry accentColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconCircle addSubview:iconView];

    // Titles
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPFontBold(PPFontTitle3);
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = [self.entry localizedActionTitle];
    titleLabel.numberOfLines = 2;
    [card addSubview:titleLabel];

    UILabel *techActionLabel = [[UILabel alloc] init];
    techActionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    techActionLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: PPFontRegular(PPFontCaption1);
    techActionLabel.textColor = [UIColor ppTextSecondary];
    techActionLabel.text = self.entry.action;
    [card addSubview:techActionLabel];

    // Timestamp & relative pill
    UIView *timePill = [[UIView alloc] init];
    timePill.translatesAutoresizingMaskIntoConstraints = NO;
    timePill.backgroundColor = [UIColor ppSecondarySurface];
    timePill.layer.cornerRadius = PPCornerSmall;
    [card addSubview:timePill];

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

    // Audit ID Copy Row
    UIButton *copyIdBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyIdBtn.translatesAutoresizingMaskIntoConstraints = NO;
    copyIdBtn.backgroundColor = [UIColor ppSecondarySurface];
    copyIdBtn.layer.cornerRadius = PPCornerSmall;
    copyIdBtn.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceXS, PPSpaceSM, PPSpaceXS, PPSpaceSM);
    NSString *idSnippet = self.entry.auditId.length > 16 ? [self.entry.auditId substringToIndex:16] : (self.entry.auditId ?: @"--");
    [copyIdBtn setTitle:[NSString stringWithFormat:@"ID: %@... 📋", idSnippet] forState:UIControlStateNormal];
    [copyIdBtn setTitleColor:[UIColor ppTextSecondary] forState:UIControlStateNormal];
    copyIdBtn.titleLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: PPFontRegular(PPFontCaption1);
    [copyIdBtn addTarget:self action:@selector(copyAuditId) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:copyIdBtn];

    [NSLayoutConstraint activateConstraints:@[
        [accentLine.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceSM],
        [accentLine.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceMD],
        [accentLine.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceMD],
        [accentLine.widthAnchor constraintEqualToConstant:4.0],

        [iconCircle.leadingAnchor constraintEqualToAnchor:accentLine.trailingAnchor constant:PPSpaceMD],
        [iconCircle.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceMD],
        [iconCircle.widthAnchor constraintEqualToConstant:44.0],
        [iconCircle.heightAnchor constraintEqualToConstant:44.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:22.0],
        [iconView.heightAnchor constraintEqualToConstant:22.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconCircle.trailingAnchor constant:PPSpaceMD],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [titleLabel.topAnchor constraintEqualToAnchor:iconCircle.topAnchor],

        [techActionLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [techActionLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [techActionLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:PPSpaceXXS],

        [timePill.leadingAnchor constraintEqualToAnchor:iconCircle.leadingAnchor],
        [timePill.topAnchor constraintEqualToAnchor:techActionLabel.bottomAnchor constant:PPSpaceMD],
        [timePill.heightAnchor constraintEqualToConstant:26.0],

        [timeIcon.leadingAnchor constraintEqualToAnchor:timePill.leadingAnchor constant:PPSpaceSM],
        [timeIcon.centerYAnchor constraintEqualToAnchor:timePill.centerYAnchor],
        [timeIcon.widthAnchor constraintEqualToConstant:12.0],
        [timeIcon.heightAnchor constraintEqualToConstant:12.0],

        [timeLabel.leadingAnchor constraintEqualToAnchor:timeIcon.trailingAnchor constant:PPSpaceXS],
        [timeLabel.trailingAnchor constraintEqualToAnchor:timePill.trailingAnchor constant:-PPSpaceSM],
        [timeLabel.centerYAnchor constraintEqualToAnchor:timePill.centerYAnchor],

        [copyIdBtn.leadingAnchor constraintEqualToAnchor:iconCircle.leadingAnchor],
        [copyIdBtn.topAnchor constraintEqualToAnchor:timePill.bottomAnchor constant:PPSpaceSM],
        [copyIdBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceMD]
    ]];

    return card;
}

- (UIView *)buildParticipantsCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);

    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.font = PPFontBold(PPFontCallout);
    headerLabel.textColor = [UIColor ppTextSecondary];
    headerLabel.text = [Language isRTL] ? @"أطراف العملية والمعرّفات" : @"Operation Parties & Identifiers";
    [card addSubview:headerLabel];

    // Actor Admin Row
    UIView *actorRow = [self buildPartyRowWithTitle:kLang(@"Audit_Inspector_Actor")
                                              value:self.entry.adminUid
                                           iconName:@"person.badge.shield.checkmark.fill"
                                         badgeColor:[UIColor ppQuickActionAnimals]
                                           isCopier:YES];
    [card addSubview:actorRow];

    // Target Entity Row
    UIView *targetRow = [self buildPartyRowWithTitle:kLang(@"Audit_Inspector_Target")
                                               value:self.entry.targetUid
                                            iconName:@"target"
                                          badgeColor:[UIColor ppQuickActionServices]
                                            isCopier:YES];
    [card addSubview:targetRow];

    [NSLayoutConstraint activateConstraints:@[
        [headerLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [headerLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [headerLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],

        [actorRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [actorRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [actorRow.topAnchor constraintEqualToAnchor:headerLabel.bottomAnchor constant:PPSpaceMD],

        [targetRow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [targetRow.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [targetRow.topAnchor constraintEqualToAnchor:actorRow.bottomAnchor constant:PPSpaceSM],
        [targetRow.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase]
    ]];

    return card;
}

- (UIView *)buildPartyRowWithTitle:(NSString *)title
                             value:(NSString *)value
                          iconName:(NSString *)iconName
                        badgeColor:(UIColor *)color
                          isCopier:(BOOL)canCopy {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor ppSecondarySurface];
    row.layer.cornerRadius = PPCornerSmall;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = color;
    [row addSubview:icon];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.font = PPFontRegular(PPFontCaption1);
    titleLbl.textColor = [UIColor ppTextSecondary];
    titleLbl.text = title;
    [row addSubview:titleLbl];

    UILabel *valLbl = [[UILabel alloc] init];
    valLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valLbl.font = [UIFont fontWithName:@"Menlo" size:12] ?: PPFontMedium(PPFontSubheadline);
    valLbl.textColor = [UIColor ppTextPrimary];
    valLbl.text = value.length > 0 ? value : @"--";
    valLbl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [row addSubview:valLbl];

    if (canCopy && value.length > 0) {
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
        copyBtn.tintColor = [UIColor ppTextTertiary];
        objc_setAssociatedObject(copyBtn, "copyVal", value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [copyBtn addTarget:self action:@selector(handleRowCopyTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:copyBtn];

        [NSLayoutConstraint activateConstraints:@[
            [copyBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-PPSpaceSM],
            [copyBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [copyBtn.widthAnchor constraintEqualToConstant:32.0],
            [copyBtn.heightAnchor constraintEqualToConstant:32.0],
            [valLbl.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-PPSpaceSM]
        ]];
    } else {
        [valLbl.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-PPSpaceBase].active = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:48.0],
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:PPSpaceMD],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:20.0],
        [icon.heightAnchor constraintEqualToConstant:20.0],

        [titleLbl.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:PPSpaceMD],
        [titleLbl.topAnchor constraintEqualToAnchor:row.topAnchor constant:PPSpaceXS],

        [valLbl.leadingAnchor constraintEqualToAnchor:titleLbl.leadingAnchor],
        [valLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:PPSpaceXXS],
        [valLbl.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-PPSpaceXS]
    ]];

    return row;
}

- (void)handleRowCopyTapped:(UIButton *)sender {
    NSString *val = objc_getAssociatedObject(sender, "copyVal");
    if (val.length > 0) {
        [UIPasteboard generalPasteboard].string = val;
        [PPToast toast:kLang(@"Audit_Copied")];
        UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [fb impactOccurred];
    }
}

- (UIView *)buildReasonCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);

    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.font = PPFontBold(PPFontCallout);
    headerLabel.textColor = [UIColor ppTextSecondary];
    headerLabel.text = kLang(@"Audit_Inspector_Reason");
    [card addSubview:headerLabel];

    UIView *quoteBox = [[UIView alloc] init];
    quoteBox.translatesAutoresizingMaskIntoConstraints = NO;
    quoteBox.backgroundColor = [UIColor ppSecondarySurface];
    quoteBox.layer.cornerRadius = PPCornerSmall;
    [card addSubview:quoteBox];

    UILabel *reasonLabel = [[UILabel alloc] init];
    reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
    reasonLabel.font = PPFontRegular(PPFontBody);
    reasonLabel.textColor = self.entry.reason.length > 0 ? [UIColor ppTextPrimary] : [UIColor ppTextTertiary];
    reasonLabel.numberOfLines = 0;
    reasonLabel.text = self.entry.reason.length > 0 ? self.entry.reason : kLang(@"Audit_Inspector_NoReason");
    [quoteBox addSubview:reasonLabel];

    [NSLayoutConstraint activateConstraints:@[
        [headerLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [headerLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [headerLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceBase],

        [quoteBox.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceBase],
        [quoteBox.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceBase],
        [quoteBox.topAnchor constraintEqualToAnchor:headerLabel.bottomAnchor constant:PPSpaceSM],
        [quoteBox.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceBase],

        [reasonLabel.leadingAnchor constraintEqualToAnchor:quoteBox.leadingAnchor constant:PPSpaceMD],
        [reasonLabel.trailingAnchor constraintEqualToAnchor:quoteBox.trailingAnchor constant:-PPSpaceMD],
        [reasonLabel.topAnchor constraintEqualToAnchor:quoteBox.topAnchor constant:PPSpaceMD],
        [reasonLabel.bottomAnchor constraintEqualToAnchor:quoteBox.bottomAnchor constant:-PPSpaceMD]
    ]];

    return card;
}

- (UIView *)buildDiffContainer {
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(container, PPCornerCard);
    PPApplyCardShadow(container);

    UILabel *headerLabel = [[UILabel alloc] init];
    headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    headerLabel.font = PPFontBold(PPFontCallout);
    headerLabel.textColor = [UIColor ppTextSecondary];
    headerLabel.text = [Language isRTL] ? @"محرك التدقيق وفحص التغييرات" : @"Audit Engine & State Diff";
    [container addSubview:headerLabel];

    NSArray *items = @[
        kLang(@"Audit_Inspector_VisualDiff"),
        kLang(@"Audit_Inspector_After"),
        kLang(@"Audit_Inspector_Before"),
        kLang(@"Audit_Inspector_Raw")
    ];
    _diffSegmentedControl = [[UISegmentedControl alloc] initWithItems:items];
    _diffSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    _diffSegmentedControl.selectedSegmentIndex = 0;
    [_diffSegmentedControl addTarget:self action:@selector(diffSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:_diffSegmentedControl];

    _diffContentView = [[UIView alloc] init];
    _diffContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:_diffContentView];

    [NSLayoutConstraint activateConstraints:@[
        [headerLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceBase],
        [headerLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceBase],
        [headerLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:PPSpaceBase],

        [_diffSegmentedControl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceBase],
        [_diffSegmentedControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceBase],
        [_diffSegmentedControl.topAnchor constraintEqualToAnchor:headerLabel.bottomAnchor constant:PPSpaceMD],

        [_diffContentView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPSpaceBase],
        [_diffContentView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPSpaceBase],
        [_diffContentView.topAnchor constraintEqualToAnchor:_diffSegmentedControl.bottomAnchor constant:PPSpaceMD],
        [_diffContentView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceBase]
    ]];

    return container;
}

- (void)diffSegmentChanged:(UISegmentedControl *)sender {
    [self updateDiffSectionContent];
}

- (void)updateDiffSectionContent {
    for (UIView *sub in self.diffContentView.subviews) {
        [sub removeFromSuperview];
    }

    NSInteger idx = self.diffSegmentedControl.selectedSegmentIndex;
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
        // Raw JSON
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
    stack.spacing = PPSpaceSM;
    stack.alignment = UIStackViewAlignmentFill;
    [hostView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor]
    ]];

    for (PPAuditDiffItem *item in diffItems) {
        UIView *row = [self buildVisualDiffRowForItem:item];
        [stack addArrangedSubview:row];
    }
}

- (UIView *)buildVisualDiffRowForItem:(PPAuditDiffItem *)item {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = PPCornerSmall;

    UIColor *badgeColor = [UIColor ppTextTertiary];
    NSString *symbolText = @"•";
    if (item.diffType == PPAuditDiffTypeAdded) {
        card.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.08];
        badgeColor = [UIColor ppSuccess];
        symbolText = @"+";
    } else if (item.diffType == PPAuditDiffTypeRemoved) {
        card.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.08];
        badgeColor = [UIColor ppError];
        symbolText = @"-";
    } else if (item.diffType == PPAuditDiffTypeModified) {
        card.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.08];
        badgeColor = [UIColor ppWarning];
        symbolText = @"Δ";
    } else {
        card.backgroundColor = [UIColor ppSecondarySurface];
    }

    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [badgeColor colorWithAlphaComponent:0.18];
    pill.layer.cornerRadius = 6.0;
    [card addSubview:pill];

    UILabel *symLbl = [[UILabel alloc] init];
    symLbl.translatesAutoresizingMaskIntoConstraints = NO;
    symLbl.font = PPFontBold(PPFontCaption1);
    symLbl.textColor = badgeColor;
    symLbl.text = symbolText;
    [pill addSubview:symLbl];

    UILabel *keyLbl = [[UILabel alloc] init];
    keyLbl.translatesAutoresizingMaskIntoConstraints = NO;
    keyLbl.font = PPFontBold(PPFontCaption1);
    keyLbl.textColor = [UIColor ppTextPrimary];
    keyLbl.text = item.key;
    [card addSubview:keyLbl];

    UILabel *valLbl = [[UILabel alloc] init];
    valLbl.translatesAutoresizingMaskIntoConstraints = NO;
    valLbl.font = [UIFont fontWithName:@"Menlo" size:11] ?: PPFontRegular(PPFontCaption1);
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

    [NSLayoutConstraint activateConstraints:@[
        [pill.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceSM],
        [pill.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceSM],
        [pill.widthAnchor constraintEqualToConstant:18.0],
        [pill.heightAnchor constraintEqualToConstant:18.0],

        [symLbl.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
        [symLbl.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],

        [keyLbl.leadingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:PPSpaceSM],
        [keyLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceSM],
        [keyLbl.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],

        [valLbl.leadingAnchor constraintEqualToAnchor:keyLbl.leadingAnchor],
        [valLbl.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceSM],
        [valLbl.topAnchor constraintEqualToAnchor:keyLbl.bottomAnchor constant:PPSpaceXXS],
        [valLbl.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-PPSpaceSM]
    ]];

    return card;
}

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
    box.layer.cornerRadius = PPCornerSmall;
    [hostView addSubview:box];

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.scrollEnabled = NO;
    tv.font = [UIFont fontWithName:@"Menlo" size:11] ?: PPFontRegular(PPFontCaption1);
    tv.textColor = [UIColor ppTextPrimary];
    tv.backgroundColor = UIColor.clearColor;
    tv.text = jsonStr;
    [box addSubview:tv];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [copyBtn setTitle:[Language isRTL] ? @"نسخ JSON" : @"Copy JSON" forState:UIControlStateNormal];
    copyBtn.titleLabel.font = PPFontMedium(PPFontCaption1);
    copyBtn.tintColor = AppPrimaryClr;
    objc_setAssociatedObject(copyBtn, "jsonText", jsonStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [copyBtn addTarget:self action:@selector(handleCopyJsonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:copyBtn];

    [NSLayoutConstraint activateConstraints:@[
        [box.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [box.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        [box.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],

        [copyBtn.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-PPSpaceSM],
        [copyBtn.topAnchor constraintEqualToAnchor:box.topAnchor constant:PPSpaceXS],

        [tv.topAnchor constraintEqualToAnchor:copyBtn.bottomAnchor constant:PPSpaceXXS],
        [tv.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:PPSpaceSM],
        [tv.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-PPSpaceSM],
        [tv.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-PPSpaceSM]
    ]];
}

- (void)handleCopyJsonTapped:(UIButton *)sender {
    NSString *json = objc_getAssociatedObject(sender, "jsonText");
    if (json.length > 0) {
        [UIPasteboard generalPasteboard].string = json;
        [PPToast toast:kLang(@"Audit_Copied")];
        UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [fb impactOccurred];
    }
}

- (void)copyAuditId {
    if (self.entry.auditId.length > 0) {
        [UIPasteboard generalPasteboard].string = self.entry.auditId;
        [PPToast toast:kLang(@"Audit_Copied")];
        UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [fb impactOccurred];
    }
}

@end

#pragma mark - Flagship Audit Log Card Cell

@interface PPAuditLogCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *accentStripe;
@property (nonatomic, strong) UIView *iconCircle;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *techActionPill;
@property (nonatomic, strong) UILabel *relativeTimeLabel;
@property (nonatomic, strong) UILabel *adminLabel;
@property (nonatomic, strong) UILabel *targetLabel;
@property (nonatomic, strong) UIView *reasonBox;
@property (nonatomic, strong) UILabel *reasonLabel;
@property (nonatomic, strong) UIView *diffBadge;
@property (nonatomic, strong) UILabel *diffBadgeLabel;
@property (nonatomic, strong) UIImageView *disclosureIcon;
@property (nonatomic, strong) NSLayoutConstraint *reasonTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *reasonBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *diffBottomConstraint;
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
    _cardView = [[UIView alloc] init];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(_cardView, PPCornerCard);
    PPApplyCardShadow(_cardView);
    [self.contentView addSubview:_cardView];

    _accentStripe = [[UIView alloc] init];
    _accentStripe.translatesAutoresizingMaskIntoConstraints = NO;
    _accentStripe.layer.cornerRadius = 2.0;
    [_cardView addSubview:_accentStripe];

    _iconCircle = [[UIView alloc] init];
    _iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    _iconCircle.layer.cornerRadius = 18.0;
    [_cardView addSubview:_iconCircle];

    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    [_iconCircle addSubview:_iconImageView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = PPFontBold(PPFontHeadline);
    _titleLabel.textColor = [UIColor ppTextPrimary];
    _titleLabel.numberOfLines = 1;
    [_cardView addSubview:_titleLabel];

    _techActionPill = [[UILabel alloc] init];
    _techActionPill.translatesAutoresizingMaskIntoConstraints = NO;
    _techActionPill.font = [UIFont fontWithName:@"Menlo" size:10] ?: PPFontRegular(PPFontCaption2);
    _techActionPill.textColor = [UIColor ppTextSecondary];
    _techActionPill.backgroundColor = [UIColor ppSecondarySurface];
    _techActionPill.layer.cornerRadius = 4.0;
    _techActionPill.clipsToBounds = YES;
    [_cardView addSubview:_techActionPill];

    _relativeTimeLabel = [[UILabel alloc] init];
    _relativeTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _relativeTimeLabel.font = PPFontRegular(PPFontCaption1);
    _relativeTimeLabel.textColor = [UIColor ppTextTertiary];
    [_cardView addSubview:_relativeTimeLabel];

    _adminLabel = [[UILabel alloc] init];
    _adminLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _adminLabel.font = PPFontMedium(PPFontCaption1);
    _adminLabel.textColor = [UIColor ppTextSecondary];
    [_cardView addSubview:_adminLabel];

    _targetLabel = [[UILabel alloc] init];
    _targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _targetLabel.font = PPFontRegular(PPFontCaption1);
    _targetLabel.textColor = [UIColor ppTextTertiary];
    [_cardView addSubview:_targetLabel];

    _reasonBox = [[UIView alloc] init];
    _reasonBox.translatesAutoresizingMaskIntoConstraints = NO;
    _reasonBox.backgroundColor = [UIColor ppSecondarySurface];
    _reasonBox.layer.cornerRadius = 8.0;
    [_cardView addSubview:_reasonBox];

    _reasonLabel = [[UILabel alloc] init];
    _reasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _reasonLabel.font = PPFontRegular(PPFontCaption1);
    _reasonLabel.textColor = [UIColor ppTextSecondary];
    _reasonLabel.numberOfLines = 2;
    [_reasonBox addSubview:_reasonLabel];

    _diffBadge = [[UIView alloc] init];
    _diffBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _diffBadge.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.12];
    _diffBadge.layer.cornerRadius = 6.0;
    [_cardView addSubview:_diffBadge];

    _diffBadgeLabel = [[UILabel alloc] init];
    _diffBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _diffBadgeLabel.font = PPFontBold(PPFontCaption2);
    _diffBadgeLabel.textColor = [UIColor ppWarning];
    [_diffBadge addSubview:_diffBadgeLabel];

    _disclosureIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
    _disclosureIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureIcon.tintColor = [UIColor ppTextTertiary];
    [_cardView addSubview:_disclosureIcon];

    [NSLayoutConstraint activateConstraints:@[
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceBase],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceBase],
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceXS],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceXS],

        [_accentStripe.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:PPSpaceSM],
        [_accentStripe.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],
        [_accentStripe.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD],
        [_accentStripe.widthAnchor constraintEqualToConstant:4.0],

        [_iconCircle.leadingAnchor constraintEqualToAnchor:_accentStripe.trailingAnchor constant:PPSpaceMD],
        [_iconCircle.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],
        [_iconCircle.widthAnchor constraintEqualToConstant:36.0],
        [_iconCircle.heightAnchor constraintEqualToConstant:36.0],

        [_iconImageView.centerXAnchor constraintEqualToAnchor:_iconCircle.centerXAnchor],
        [_iconImageView.centerYAnchor constraintEqualToAnchor:_iconCircle.centerYAnchor],
        [_iconImageView.widthAnchor constraintEqualToConstant:18.0],
        [_iconImageView.heightAnchor constraintEqualToConstant:18.0],

        [_disclosureIcon.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceBase],
        [_disclosureIcon.centerYAnchor constraintEqualToAnchor:_iconCircle.centerYAnchor],
        [_disclosureIcon.widthAnchor constraintEqualToConstant:12.0],
        [_disclosureIcon.heightAnchor constraintEqualToConstant:12.0],

        [_relativeTimeLabel.trailingAnchor constraintEqualToAnchor:_disclosureIcon.leadingAnchor constant:-PPSpaceSM],
        [_relativeTimeLabel.centerYAnchor constraintEqualToAnchor:_iconCircle.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconCircle.trailingAnchor constant:PPSpaceMD],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_relativeTimeLabel.leadingAnchor constant:-PPSpaceSM],
        [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],

        [_techActionPill.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_techActionPill.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXXS],
        [_techActionPill.trailingAnchor constraintLessThanOrEqualToAnchor:_relativeTimeLabel.leadingAnchor constant:-PPSpaceSM],

        [_adminLabel.leadingAnchor constraintEqualToAnchor:_iconCircle.leadingAnchor],
        [_adminLabel.topAnchor constraintEqualToAnchor:_techActionPill.bottomAnchor constant:PPSpaceSM],
        [_adminLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceBase],

        [_targetLabel.leadingAnchor constraintEqualToAnchor:_iconCircle.leadingAnchor],
        [_targetLabel.topAnchor constraintEqualToAnchor:_adminLabel.bottomAnchor constant:PPSpaceXXS],
        [_targetLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceBase],

        [_reasonBox.leadingAnchor constraintEqualToAnchor:_iconCircle.leadingAnchor],
        [_reasonBox.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceBase],
        [_reasonLabel.topAnchor constraintEqualToAnchor:_reasonBox.topAnchor constant:PPSpaceXS],
        [_reasonLabel.leadingAnchor constraintEqualToAnchor:_reasonBox.leadingAnchor constant:PPSpaceSM],
        [_reasonLabel.trailingAnchor constraintEqualToAnchor:_reasonBox.trailingAnchor constant:-PPSpaceSM],
        [_reasonLabel.bottomAnchor constraintEqualToAnchor:_reasonBox.bottomAnchor constant:-PPSpaceXS],

        [_diffBadge.leadingAnchor constraintEqualToAnchor:_iconCircle.leadingAnchor],
        [_diffBadge.heightAnchor constraintEqualToConstant:20.0],
        [_diffBadgeLabel.leadingAnchor constraintEqualToAnchor:_diffBadge.leadingAnchor constant:PPSpaceSM],
        [_diffBadgeLabel.trailingAnchor constraintEqualToAnchor:_diffBadge.trailingAnchor constant:-PPSpaceSM],
        [_diffBadgeLabel.centerYAnchor constraintEqualToAnchor:_diffBadge.centerYAnchor]
    ]];

    _reasonTopConstraint = [_reasonBox.topAnchor constraintEqualToAnchor:_targetLabel.bottomAnchor constant:PPSpaceSM];
    _reasonBottomConstraint = [_reasonBox.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD];
    _diffBottomConstraint = [_diffBadge.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD];
}

- (void)configureWithEntry:(PPAuditLogEntryModel *)entry {
    UIColor *accent = [entry accentColor];
    _accentStripe.backgroundColor = accent;
    _iconCircle.backgroundColor = [entry badgeBackgroundColor];
    _iconImageView.image = [UIImage systemImageNamed:[entry systemIconName]];
    _iconImageView.tintColor = accent;

    _titleLabel.text = [entry localizedActionTitle];
    _techActionPill.text = [NSString stringWithFormat:@" %@ ", entry.action];
    _relativeTimeLabel.text = [entry relativeTimeString];

    _adminLabel.text = [NSString stringWithFormat:@"%@: %@", kLang(@"Audit_Admin"), entry.adminUid.length > 0 ? entry.adminUid : @"--"];
    _targetLabel.text = [NSString stringWithFormat:@"%@: %@", kLang(@"Audit_Target"), entry.targetUid.length > 0 ? entry.targetUid : @"--"];

    BOOL hasReason = entry.reason.length > 0;
    _reasonBox.hidden = !hasReason;
    if (hasReason) {
        _reasonLabel.text = entry.reason;
    }

    BOOL hasDiff = [entry hasDiff];
    _diffBadge.hidden = !hasDiff;
    if (hasDiff) {
        NSInteger added = [entry addedKeysCount];
        NSInteger mod = [entry modifiedKeysCount];
        NSInteger rem = [entry removedKeysCount];
        _diffBadgeLabel.text = [NSString stringWithFormat:@"Δ +%ld ~%ld -%ld", (long)added, (long)mod, (long)rem];
    }

    // Dynamic constraints layout
    _reasonTopConstraint.active = hasReason;
    if (hasReason && !hasDiff) {
        _reasonBottomConstraint.active = YES;
        _diffBottomConstraint.active = NO;
    } else if (hasDiff) {
        _reasonBottomConstraint.active = NO;
        _diffBottomConstraint.active = YES;
        [_diffBadge.topAnchor constraintEqualToAnchor:(hasReason ? _reasonBox.bottomAnchor : _targetLabel.bottomAnchor) constant:PPSpaceSM].active = YES;
    } else {
        _reasonBottomConstraint.active = NO;
        _diffBottomConstraint.active = NO;
        [_targetLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD].active = YES;
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - Telemetry Pulse Strip View

@interface PPAuditTelemetryPulseView : UIView
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, copy) void (^onCardTapped)(NSInteger filterIndex);
- (void)updateWithTotal:(NSInteger)total
               security:(NSInteger)sec
                    ops:(NSInteger)ops
            destructive:(NSInteger)dest
          selectedIndex:(NSInteger)selectedIdx;
@end

@implementation PPAuditTelemetryPulseView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        scroll.showsHorizontalScrollIndicator = NO;
        [self addSubview:scroll];

        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.spacing = PPSpaceSM;
        _stackView.alignment = UIStackViewAlignmentFill;
        _stackView.distribution = UIStackViewDistributionFillEqually;
        [scroll addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_stackView.topAnchor constraintEqualToAnchor:scroll.topAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
            [_stackView.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:PPSpaceBase],
            [_stackView.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-PPSpaceBase],
            [_stackView.heightAnchor constraintEqualToAnchor:scroll.heightAnchor]
        ]];
    }
    return self;
}

- (void)updateWithTotal:(NSInteger)total
               security:(NSInteger)sec
                    ops:(NSInteger)ops
            destructive:(NSInteger)dest
          selectedIndex:(NSInteger)selectedIdx {
    for (UIView *v in self.stackView.arrangedSubviews) {
        [v removeFromSuperview];
    }

    NSArray *configs = @[
        @{ @"title": kLang(@"Audit_Metric_Total"), @"count": @(total), @"icon": @"waveform.path.ecg", @"color": AppPrimaryClr, @"idx": @(0) },
        @{ @"title": kLang(@"Audit_Metric_Security"), @"count": @(sec), @"icon": @"shield.checkerboard", @"color": [UIColor ppQuickActionAnimals], @"idx": @(1) },
        @{ @"title": kLang(@"Audit_Metric_Ops"), @"count": @(ops), @"icon": @"slider.horizontal.3", @"color": [UIColor ppQuickActionServices], @"idx": @(2) },
        @{ @"title": kLang(@"Audit_Metric_Destructive"), @"count": @(dest), @"icon": @"trash.fill", @"color": [UIColor ppError], @"idx": @(5) }
    ];

    for (NSDictionary *cfg in configs) {
        NSInteger idx = [cfg[@"idx"] integerValue];
        BOOL isSel = (selectedIdx == idx);
        UIView *card = [self buildMetricCardWithTitle:cfg[@"title"]
                                                count:[cfg[@"count"] integerValue]
                                             iconName:cfg[@"icon"]
                                                color:cfg[@"color"]
                                           isSelected:isSel
                                                index:idx];
        [self.stackView addArrangedSubview:card];
    }
}

- (UIView *)buildMetricCardWithTitle:(NSString *)title
                               count:(NSInteger)count
                            iconName:(NSString *)iconName
                               color:(UIColor *)color
                          isSelected:(BOOL)isSel
                               index:(NSInteger)idx {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = isSel ? [color colorWithAlphaComponent:0.12] : [UIColor ppSurface];
    PPApplyContinuousCorners(btn, PPCornerMedium);
    btn.layer.borderWidth = isSel ? 1.5 : 0.5;
    btn.layer.borderColor = isSel ? color.CGColor : [UIColor ppBorder].CGColor;
    objc_setAssociatedObject(btn, "cardIdx", @(idx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [btn addTarget:self action:@selector(handleCardTap:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = color;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [btn addSubview:icon];

    UILabel *countLbl = [[UILabel alloc] init];
    countLbl.translatesAutoresizingMaskIntoConstraints = NO;
    countLbl.font = PPFontBold(PPFontTitle3);
    countLbl.textColor = isSel ? color : [UIColor ppTextPrimary];
    countLbl.text = [NSString stringWithFormat:@"%ld", (long)count];
    [btn addSubview:countLbl];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.font = PPFontMedium(PPFontCaption2);
    titleLbl.textColor = [UIColor ppTextSecondary];
    titleLbl.text = title;
    titleLbl.numberOfLines = 1;
    [btn addSubview:titleLbl];

    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor constraintGreaterThanOrEqualToConstant:108.0],
        [icon.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:PPSpaceMD],
        [icon.topAnchor constraintEqualToAnchor:btn.topAnchor constant:PPSpaceSM],
        [icon.widthAnchor constraintEqualToConstant:18.0],
        [icon.heightAnchor constraintEqualToConstant:18.0],

        [countLbl.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [countLbl.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceXXS],

        [titleLbl.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [titleLbl.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-PPSpaceSM],
        [titleLbl.topAnchor constraintEqualToAnchor:countLbl.bottomAnchor constant:PPSpaceXXS],
        [titleLbl.bottomAnchor constraintEqualToAnchor:btn.bottomAnchor constant:-PPSpaceSM]
    ]];

    return btn;
}

- (void)handleCardTap:(UIButton *)sender {
    NSInteger idx = [objc_getAssociatedObject(sender, "cardIdx") integerValue];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
    if (self.onCardTapped) {
        self.onCardTapped(idx);
    }
}

@end

#pragma mark - Filter Scrubber View

@interface PPAuditScrubberView : UIView
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, copy) void (^onPillSelected)(NSInteger index);
- (void)setFilterTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selIdx;
@end

@implementation PPAuditScrubberView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.bounds];
        scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        scroll.showsHorizontalScrollIndicator = NO;
        [self addSubview:scroll];

        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.spacing = PPSpaceSM;
        _stackView.alignment = UIStackViewAlignmentCenter;
        [scroll addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_stackView.topAnchor constraintEqualToAnchor:scroll.topAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
            [_stackView.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:PPSpaceBase],
            [_stackView.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-PPSpaceBase],
            [_stackView.heightAnchor constraintEqualToAnchor:scroll.heightAnchor]
        ]];
    }
    return self;
}

- (void)setFilterTitles:(NSArray<NSString *> *)titles selectedIndex:(NSInteger)selIdx {
    for (UIView *v in self.stackView.arrangedSubviews) {
        [v removeFromSuperview];
    }

    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        BOOL isSel = (idx == selIdx);
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        btn.layer.cornerRadius = PPCornerPill;
        btn.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceLG, PPSpaceSM, PPSpaceLG);
        btn.titleLabel.font = isSel ? PPFontBold(PPFontSubheadline) : PPFontMedium(PPFontSubheadline);

        if (isSel) {
            btn.backgroundColor = AppPrimaryClr;
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        } else {
            btn.backgroundColor = [UIColor ppSecondarySurface];
            [btn setTitleColor:[UIColor ppTextSecondary] forState:UIControlStateNormal];
        }
        [btn setTitle:title forState:UIControlStateNormal];
        objc_setAssociatedObject(btn, "pillIdx", @(idx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [btn addTarget:self action:@selector(handlePillTap:) forControlEvents:UIControlEventTouchUpInside];
        [self.stackView addArrangedSubview:btn];
    }];
}

- (void)handlePillTap:(UIButton *)sender {
    NSInteger idx = [objc_getAssociatedObject(sender, "pillIdx") integerValue];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
    if (self.onPillSelected) {
        self.onPillSelected(idx);
    }
}

@end

#pragma mark - Sovereign PPAuditLogViewController Master Controller

@interface PPAuditLogViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *allEntries;
@property (nonatomic, strong) NSArray<PPAuditLogEntryModel *> *filteredEntries;
@property (nonatomic, strong) id<FIRListenerRegistration> listenerReg;
@property (nonatomic, assign) NSUInteger listenerGeneration;

// Sovereign Navigation Chrome
@property (nonatomic, strong) UIView *commandBarView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UILabel *navSubtitleLabel;
@property (nonatomic, strong) PPAuditPulsingDotView *pulseDot;
@property (nonatomic, strong) UIButton *searchToggleBtn;
@property (nonatomic, strong) UIButton *filterModalBtn;

// Search & Telemetry Chrome
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSLayoutConstraint *searchBarHeightConstraint;
@property (nonatomic, assign) BOOL isSearchVisible;
@property (nonatomic, strong) PPAuditTelemetryPulseView *telemetryPulseView;
@property (nonatomic, strong) PPAuditScrubberView *scrubberView;
@property (nonatomic, assign) NSInteger selectedCategoryIndex;

// Table View
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *emptyStateView;

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

#pragma mark - Telemetry Header & Scrubber

- (void)setupTelemetryHeader {
    _telemetryPulseView = [[PPAuditTelemetryPulseView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 92.0)];
    _telemetryPulseView.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _telemetryPulseView.onCardTapped = ^(NSInteger filterIndex) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.selectedCategoryIndex = filterIndex;
        [strongSelf.scrubberView setFilterTitles:[strongSelf filterTitlesArray] selectedIndex:strongSelf.selectedCategoryIndex];
        [strongSelf applyFilter];
    };
    [self.view addSubview:_telemetryPulseView];

    _scrubberView = [[PPAuditScrubberView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 48.0)];
    _scrubberView.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrubberView setFilterTitles:[self filterTitlesArray] selectedIndex:0];
    _scrubberView.onPillSelected = ^(NSInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.selectedCategoryIndex = index;
        [strongSelf.scrubberView setFilterTitles:[strongSelf filterTitlesArray] selectedIndex:index];
        [strongSelf applyFilter];
    };
    [self.view addSubview:_scrubberView];

    [NSLayoutConstraint activateConstraints:@[
        [_telemetryPulseView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:PPSpaceSM],
        [_telemetryPulseView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_telemetryPulseView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_telemetryPulseView.heightAnchor constraintEqualToConstant:92.0],

        [_scrubberView.topAnchor constraintEqualToAnchor:_telemetryPulseView.bottomAnchor constant:PPSpaceSM],
        [_scrubberView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrubberView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrubberView.heightAnchor constraintEqualToConstant:48.0]
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
    _tableView.estimatedRowHeight = 160.0;
    _tableView.contentInset = UIEdgeInsetsMake(PPSpaceSM, 0, PPSpaceXXXL, 0);
    [_tableView registerClass:[PPAuditLogCardCell class] forCellReuseIdentifier:kAuditCardCellID];
    [self.view addSubview:_tableView];

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:_scrubberView.bottomAnchor constant:PPSpaceSM],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupEmptyStateView {
    _emptyStateView = [[UIView alloc] init];
    _emptyStateView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyStateView.hidden = YES;
    [self.view addSubview:_emptyStateView];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.slash"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor ppTextTertiary];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [_emptyStateView addSubview:icon];

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.font = PPFontBold(PPFontHeadline);
    titleLbl.textColor = [UIColor ppTextPrimary];
    titleLbl.text = kLang(@"Audit_Empty_SearchTitle");
    titleLbl.textAlignment = NSTextAlignmentCenter;
    [_emptyStateView addSubview:titleLbl];

    UILabel *subLbl = [[UILabel alloc] init];
    subLbl.translatesAutoresizingMaskIntoConstraints = NO;
    subLbl.font = PPFontRegular(PPFontSubheadline);
    subLbl.textColor = [UIColor ppTextSecondary];
    subLbl.text = kLang(@"Audit_Empty_SearchSubtitle");
    subLbl.textAlignment = NSTextAlignmentCenter;
    subLbl.numberOfLines = 2;
    [_emptyStateView addSubview:subLbl];

    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.translatesAutoresizingMaskIntoConstraints = NO;
    resetBtn.backgroundColor = [UIColor ppSecondarySurface];
    resetBtn.tintColor = AppPrimaryClr;
    resetBtn.layer.cornerRadius = PPCornerMedium;
    resetBtn.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceLG, PPSpaceSM, PPSpaceLG);
    resetBtn.titleLabel.font = PPFontMedium(PPFontSubheadline);
    [resetBtn setTitle:kLang(@"Audit_Filter_Reset") forState:UIControlStateNormal];
    [resetBtn addTarget:self action:@selector(resetAllFilters) forControlEvents:UIControlEventTouchUpInside];
    [_emptyStateView addSubview:resetBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyStateView.centerXAnchor constraintEqualToAnchor:_tableView.centerXAnchor],
        [_emptyStateView.centerYAnchor constraintEqualToAnchor:_tableView.centerYAnchor constant:-40.0],
        [_emptyStateView.leadingAnchor constraintEqualToAnchor:_tableView.leadingAnchor constant:PPSpaceXL],
        [_emptyStateView.trailingAnchor constraintEqualToAnchor:_tableView.trailingAnchor constant:-PPSpaceXL],

        [icon.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [icon.topAnchor constraintEqualToAnchor:_emptyStateView.topAnchor],
        [icon.widthAnchor constraintEqualToConstant:56.0],
        [icon.heightAnchor constraintEqualToConstant:56.0],

        [titleLbl.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceMD],
        [titleLbl.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [titleLbl.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

        [subLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:PPSpaceXS],
        [subLbl.leadingAnchor constraintEqualToAnchor:_emptyStateView.leadingAnchor],
        [subLbl.trailingAnchor constraintEqualToAnchor:_emptyStateView.trailingAnchor],

        [resetBtn.topAnchor constraintEqualToAnchor:subLbl.bottomAnchor constant:PPSpaceMD],
        [resetBtn.centerXAnchor constraintEqualToAnchor:_emptyStateView.centerXAnchor],
        [resetBtn.bottomAnchor constraintEqualToAnchor:_emptyStateView.bottomAnchor]
    ]];
}

#pragma mark - Security & Data Loading

- (BOOL)evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    BOOL hasGlobalReach = staff.isAdmin || staff.hasGlobalScope;
    BOOL hasAuditPerm = [staff hasPermission:kStaffPermAuditView];
    if (!hasGlobalReach || !hasAuditPerm) {
        [self.listenerReg remove];
        self.listenerReg = nil;
        self.listenerGeneration += 1;
        [PPHUD showError:kLang(@"Error_Title")];
        [self handleBackTapped];
        return NO;
    }
    return YES;
}

- (void)loadData {
    [self.listenerReg remove];
    self.listenerReg = nil;
    self.listenerGeneration += 1;
    NSUInteger generation = self.listenerGeneration;
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;

    FIRQuery *query = [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"]
                        queryOrderedByField:@"timestamp" descending:YES]
                       queryLimitedTo:500];

    __weak typeof(self) weakSelf = self;
    self.listenerReg = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.listenerGeneration) return;

        if (!PPAuditStaffSessionCanRead(staff)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.listenerGeneration) return;
                [self.listenerReg remove];
                self.listenerReg = nil;
                self.listenerGeneration += 1;
                self.allEntries = @[];
                [self applyFilter];
                if ([self evaluatePermissions]) [self loadData];
            });
            return;
        }

        if (error) {
            [PPHUD showError:kLang(@"Error_Title")];
            return;
        }

        NSMutableArray *entries = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPAuditLogEntryModel *entry = [PPAuditLogEntryModel entryFromSnapshot:doc];
            [entries addObject:entry];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.listenerGeneration || !PPAuditStaffSessionCanRead(staff)) return;
            self.allEntries = entries.copy;
            [self applyFilter];
        });
    }];
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
    NSInteger opsCount = 0;
    NSInteger destCount = 0;

    for (PPAuditLogEntryModel *entry in self.allEntries) {
        PPAuditActionCategory cat = [entry actionCategory];
        if (cat == PPAuditActionCategorySecurity) secCount++;
        if (cat == PPAuditActionCategoryServices || cat == PPAuditActionCategoryOperations) opsCount++;
        if (cat == PPAuditActionCategoryDestructive) destCount++;

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
                         [entry.localizedActionTitle.lowercaseString containsString:search];
            if (!match) continue;
        }

        [result addObject:entry];
    }

    self.filteredEntries = result.copy;
    [self.tableView reloadData];

    // Update Telemetry Header & Subtitle
    [self.telemetryPulseView updateWithTotal:totalCount
                                   security:secCount
                                        ops:opsCount
                                destructive:destCount
                              selectedIndex:self.selectedCategoryIndex];

    NSString *countStr = [NSString stringWithFormat:@"(%ld %@)", (long)self.filteredEntries.count, kLang(@"Audit_Title")];
    self.navSubtitleLabel.text = [NSString stringWithFormat:@"%@ • %@", kLang(@"Audit_LiveStreamActive"), countStr];

    self.emptyStateView.hidden = (self.filteredEntries.count > 0);
}

- (void)resetAllFilters {
    self.selectedCategoryIndex = 0;
    [self.scrubberView setFilterTitles:[self filterTitlesArray] selectedIndex:0];
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
            [self.scrubberView setFilterTitles:[self filterTitlesArray] selectedIndex:i];
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

- (void)dealloc {
    self.listenerGeneration += 1;
    [self.listenerReg remove];
}

@end

