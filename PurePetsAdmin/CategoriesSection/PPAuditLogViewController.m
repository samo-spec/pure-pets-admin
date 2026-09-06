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

#pragma mark - Flagship Narrative Audit Log Card Cell

@interface PPAuditLogCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *accentStripe;
@property (nonatomic, strong) UIStackView *contentStack;

// Row 1: Actor & Time
@property (nonatomic, strong) UIView *actorTimeRow;
@property (nonatomic, strong) UIView *actorAvatarView;
@property (nonatomic, strong) UIImageView *actorIconView;
@property (nonatomic, strong) UILabel *actorNameLabel;
@property (nonatomic, strong) UIImageView *timeIconView;
@property (nonatomic, strong) UILabel *relativeTimeLabel;

// Row 2: Category Pill & Localized Headline
@property (nonatomic, strong) UIView *actionRow;
@property (nonatomic, strong) UIView *categoryPillView;
@property (nonatomic, strong) UIImageView *categoryIconView;
@property (nonatomic, strong) UILabel *categoryLabel;
@property (nonatomic, strong) UILabel *titleLabel;

// Row 3: Target Entity
@property (nonatomic, strong) UIView *targetRow;
@property (nonatomic, strong) UIImageView *targetIconView;
@property (nonatomic, strong) UILabel *targetLabel;

// Row 4: Delta DNA Strip
@property (nonatomic, strong) UIView *diffBoxView;
@property (nonatomic, strong) UILabel *diffBadgeLabel;
@property (nonatomic, strong) UILabel *diffTransitionLabel;

// Row 5: Operational Reason Box
@property (nonatomic, strong) UIView *reasonBoxView;
@property (nonatomic, strong) UILabel *reasonLabel;

// Row 6: Provenance Footer & Chevron
@property (nonatomic, strong) UIView *footerRow;
@property (nonatomic, strong) UILabel *auditIdLabel;
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
    PPApplyContinuousCorners(_cardView, PPCornerCard);
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

    // --- Row 1: Actor & Time ---
    _actorTimeRow = [[UIView alloc] init];
    _actorTimeRow.translatesAutoresizingMaskIntoConstraints = NO;

    _actorAvatarView = [[UIView alloc] init];
    _actorAvatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _actorAvatarView.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) {
        _actorAvatarView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [_actorTimeRow addSubview:_actorAvatarView];

    _actorIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.fill"]];
    _actorIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _actorIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_actorAvatarView addSubview:_actorIconView];

    _actorNameLabel = [[UILabel alloc] init];
    _actorNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _actorNameLabel.font = PPFontBold(PPFontSubheadline);
    _actorNameLabel.textColor = [UIColor ppTextPrimary];
    [_actorTimeRow addSubview:_actorNameLabel];

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
        [_actorAvatarView.widthAnchor constraintEqualToConstant:28.0],
        [_actorAvatarView.heightAnchor constraintEqualToConstant:28.0],

        [_actorIconView.centerXAnchor constraintEqualToAnchor:_actorAvatarView.centerXAnchor],
        [_actorIconView.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],
        [_actorIconView.widthAnchor constraintEqualToConstant:14.0],
        [_actorIconView.heightAnchor constraintEqualToConstant:14.0],

        [_actorNameLabel.leadingAnchor constraintEqualToAnchor:_actorAvatarView.trailingAnchor constant:PPSpaceSM],
        [_actorNameLabel.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],

        [_relativeTimeLabel.trailingAnchor constraintEqualToAnchor:_actorTimeRow.trailingAnchor],
        [_relativeTimeLabel.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],

        [_timeIconView.trailingAnchor constraintEqualToAnchor:_relativeTimeLabel.leadingAnchor constant:-PPSpaceXS],
        [_timeIconView.centerYAnchor constraintEqualToAnchor:_actorAvatarView.centerYAnchor],
        [_timeIconView.widthAnchor constraintEqualToConstant:12.0],
        [_timeIconView.heightAnchor constraintEqualToConstant:12.0],

        [_actorNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeIconView.leadingAnchor constant:-PPSpaceSM]
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
        [_categoryPillView.heightAnchor constraintEqualToConstant:22.0],

        [_categoryIconView.leadingAnchor constraintEqualToAnchor:_categoryPillView.leadingAnchor constant:6.0],
        [_categoryIconView.centerYAnchor constraintEqualToAnchor:_categoryPillView.centerYAnchor],
        [_categoryIconView.widthAnchor constraintEqualToConstant:12.0],
        [_categoryIconView.heightAnchor constraintEqualToConstant:12.0],

        [_categoryLabel.leadingAnchor constraintEqualToAnchor:_categoryIconView.trailingAnchor constant:4.0],
        [_categoryLabel.trailingAnchor constraintEqualToAnchor:_categoryPillView.trailingAnchor constant:-6.0],
        [_categoryLabel.centerYAnchor constraintEqualToAnchor:_categoryPillView.centerYAnchor],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_categoryPillView.trailingAnchor constant:PPSpaceSM],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_actionRow.trailingAnchor],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_categoryPillView.centerYAnchor],
        [_actionRow.bottomAnchor constraintEqualToAnchor:_categoryPillView.bottomAnchor]
    ]];
    [_contentStack addArrangedSubview:_actionRow];

    // --- Row 3: Target Entity ---
    _targetRow = [[UIView alloc] init];
    _targetRow.translatesAutoresizingMaskIntoConstraints = NO;

    _targetIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.turn.down.right"]];
    _targetIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _targetIconView.tintColor = [UIColor ppTextTertiary];
    _targetIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_targetRow addSubview:_targetIconView];

    _targetLabel = [[UILabel alloc] init];
    _targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _targetLabel.font = [UIFont fontWithName:@"Menlo" size:11] ?: PPFontRegular(PPFontCaption1);
    _targetLabel.textColor = [UIColor ppTextSecondary];
    [_targetRow addSubview:_targetLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_targetIconView.leadingAnchor constraintEqualToAnchor:_targetRow.leadingAnchor],
        [_targetIconView.centerYAnchor constraintEqualToAnchor:_targetRow.centerYAnchor],
        [_targetIconView.widthAnchor constraintEqualToConstant:12.0],
        [_targetIconView.heightAnchor constraintEqualToConstant:12.0],

        [_targetLabel.leadingAnchor constraintEqualToAnchor:_targetIconView.trailingAnchor constant:6.0],
        [_targetLabel.trailingAnchor constraintEqualToAnchor:_targetRow.trailingAnchor],
        [_targetLabel.topAnchor constraintEqualToAnchor:_targetRow.topAnchor],
        [_targetLabel.bottomAnchor constraintEqualToAnchor:_targetRow.bottomAnchor]
    ]];
    [_contentStack addArrangedSubview:_targetRow];

    // --- Row 4: Delta DNA Strip ---
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

    // --- Row 6: Provenance Footer ---
    _footerRow = [[UIView alloc] init];
    _footerRow.translatesAutoresizingMaskIntoConstraints = NO;

    _auditIdLabel = [[UILabel alloc] init];
    _auditIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _auditIdLabel.font = [UIFont fontWithName:@"Menlo" size:10] ?: PPFontRegular(PPFontCaption2);
    _auditIdLabel.textColor = [UIColor ppTextTertiary];
    [_footerRow addSubview:_auditIdLabel];

    _disclosureIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:[Language isRTL] ? @"chevron.left" : @"chevron.right"]];
    _disclosureIcon.translatesAutoresizingMaskIntoConstraints = NO;
    _disclosureIcon.tintColor = [UIColor ppTextTertiary];
    [_footerRow addSubview:_disclosureIcon];

    [NSLayoutConstraint activateConstraints:@[
        [_auditIdLabel.leadingAnchor constraintEqualToAnchor:_footerRow.leadingAnchor],
        [_auditIdLabel.centerYAnchor constraintEqualToAnchor:_footerRow.centerYAnchor],
        [_auditIdLabel.topAnchor constraintEqualToAnchor:_footerRow.topAnchor],
        [_auditIdLabel.bottomAnchor constraintEqualToAnchor:_footerRow.bottomAnchor],

        [_disclosureIcon.trailingAnchor constraintEqualToAnchor:_footerRow.trailingAnchor],
        [_disclosureIcon.centerYAnchor constraintEqualToAnchor:_footerRow.centerYAnchor],
        [_disclosureIcon.widthAnchor constraintEqualToConstant:12.0],
        [_disclosureIcon.heightAnchor constraintEqualToConstant:12.0],

        [_auditIdLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_disclosureIcon.leadingAnchor constant:-PPSpaceSM]
    ]];
    [_contentStack addArrangedSubview:_footerRow];
}

- (void)configureWithEntry:(PPAuditLogEntryModel *)entry {
    UIColor *accent = [entry accentColor];
    _accentStripe.backgroundColor = accent;

    // Actor
    _actorAvatarView.backgroundColor = [entry badgeBackgroundColor];
    _actorIconView.tintColor = accent;
    _actorNameLabel.text = [entry actorDisplayName];
    _relativeTimeLabel.text = [entry relativeTimeString];

    // Category Pill & Title
    _categoryPillView.backgroundColor = [entry badgeBackgroundColor];
    _categoryIconView.image = [UIImage systemImageNamed:[entry systemIconName]];
    _categoryIconView.tintColor = accent;
    _categoryLabel.text = [entry categoryTitle];
    _categoryLabel.textColor = accent;
    _titleLabel.text = [entry localizedActionTitle];

    // Target
    _targetLabel.text = [NSString stringWithFormat:@"%@: %@", kLang(@"Audit_Target"), [entry targetDisplayName]];

    // Delta DNA
    BOOL hasDiff = [entry hasDiff];
    NSString *transition = [entry stateTransitionSummary];
    if (hasDiff || transition.length > 0) {
        _diffBoxView.hidden = NO;
        _diffBoxView.backgroundColor = [accent colorWithAlphaComponent:0.06];
        _diffBoxView.layer.borderColor = [accent colorWithAlphaComponent:0.25].CGColor;
        _diffBadgeLabel.text = [entry diffPillText];
        _diffBadgeLabel.textColor = accent;
        _diffTransitionLabel.text = transition.length > 0 ? transition : [NSString stringWithFormat:@"%ld fields", (long)([entry addedKeysCount] + [entry modifiedKeysCount] + [entry removedKeysCount])];
    } else {
        _diffBoxView.hidden = YES;
    }

    // Reason
    BOOL hasReason = entry.reason.length > 0;
    _reasonBoxView.hidden = !hasReason;
    if (hasReason) {
        _reasonLabel.text = [NSString stringWithFormat:@"“%@”", entry.reason];
    }

    // Provenance Footer
    NSString *shortId = entry.auditId.length > 10 ? [entry.auditId substringToIndex:10] : entry.auditId;
    _auditIdLabel.text = [NSString stringWithFormat:@"ID: #%@", shortId.length > 0 ? shortId : @"--"];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.transform = highlighted ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
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
        btn.backgroundColor = isSel ? [color colorWithAlphaComponent:0.12] : [UIColor ppSurface];
        btn.layer.cornerRadius = 16.0;
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
            [btn.heightAnchor constraintEqualToConstant:36.0],

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
}

- (void)handleLensTap:(UIButton *)sender {
    NSInteger idx = [objc_getAssociatedObject(sender, "lensIdx") integerValue];
    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [fb impactOccurred];
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
    _sentinelBeaconView = [[PPSentinelBeaconView alloc] initWithFrame:CGRectZero];
    _sentinelBeaconView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_sentinelBeaconView];

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
        [_sentinelBeaconView.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:PPSpaceXS],
        [_sentinelBeaconView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:PPSpaceBase],
        [_sentinelBeaconView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-PPSpaceBase],
        [_sentinelBeaconView.heightAnchor constraintEqualToConstant:36.0],

        [_telemetryLensView.topAnchor constraintEqualToAnchor:_sentinelBeaconView.bottomAnchor constant:PPSpaceSM],
        [_telemetryLensView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_telemetryLensView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_telemetryLensView.heightAnchor constraintEqualToConstant:44.0]
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
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.listenerGeneration) return;

        if (!PPAuditStaffSessionCanRead(staff)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != strongSelf.listenerGeneration) return;
                [strongSelf.listenerReg remove];
                strongSelf.listenerReg = nil;
                strongSelf.listenerGeneration += 1;
                strongSelf.allEntries = @[];
                [strongSelf applyFilter];
                if ([strongSelf evaluatePermissions]) [strongSelf loadData];
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
            if (generation != strongSelf.listenerGeneration || !PPAuditStaffSessionCanRead(staff)) return;
            strongSelf.allEntries = entries.copy;
            [strongSelf applyFilter];
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
    [self.sentinelBeaconView updateWithCount:self.filteredEntries.count];

    NSString *countStr = [NSString stringWithFormat:@"(%ld %@)", (long)self.filteredEntries.count, kLang(@"Audit_Title")];
    self.navSubtitleLabel.text = [NSString stringWithFormat:@"%@ • %@", kLang(@"Audit_LiveStreamActive"), countStr];

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
    [self.listenerReg remove];
}

@end

