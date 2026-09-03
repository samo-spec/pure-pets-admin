//
//  NotificationSettingsViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationSettingsViewController.m
#import "NotificationSettingsViewController.h"
#import "Language.h"
#import "Styling.h"
#import "UIViewController+PPNavBar.h"
#import "PPDesignTokens.h"
#import "XLFormBaseCell.h"
#import "XLFormRowDescriptor+Extras.h"

static NSString * const PPNotificationCategoryGeneralTag = @"cat_general";
static NSString * const PPNotificationCategoryOrderTag = @"cat_order";
static NSString * const PPNotificationCategoryReviewTag = @"cat_review";
static NSString * const PPNotificationCategoryWarningTag = @"cat_warning";

static NSString * const PPNotificationCategorySubtitleKey = @"subtitle";
static NSString * const PPNotificationCategorySymbolKey = @"symbol";
static NSString * const PPNotificationCategoryAccentKey = @"accent";
static NSString * const PPNotificationCategoryFirstKey = @"first";
static NSString * const PPNotificationCategoryLastKey = @"last";

@interface PPNotificationCategorySwitch : UISwitch
@end

@implementation PPNotificationCategorySwitch

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    CGFloat horizontalInset = MAX((PPTouchTargetMin - CGRectGetWidth(self.bounds)) * 0.5, 0.0);
    CGFloat verticalInset = MAX((PPTouchTargetMin - CGRectGetHeight(self.bounds)) * 0.5, 0.0);
    return CGRectContainsPoint(CGRectInset(self.bounds, -horizontalInset, -verticalInset), point);
}

@end

@interface PPNotificationCategoryCell : XLFormBaseCell

@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *iconSurfaceView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIView *separatorView;

- (void)pp_switchChanged:(UISwitch *)sender;

@end

@implementation PPNotificationCategoryCell

- (void)configure {
    [super configure];

    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.surfaceView = [UIView new];
    self.surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    self.surfaceView.backgroundColor = [UIColor ppSurface];
    self.surfaceView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.contentView addSubview:self.surfaceView];

    self.iconSurfaceView = [UIView new];
    self.iconSurfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconSurfaceView.isAccessibilityElement = NO;
    PPApplyContinuousCorners(self.iconSurfaceView, PPCornerSmall);
    [self.surfaceView addSubview:self.iconSurfaceView];

    self.symbolView = [UIImageView new];
    self.symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    self.symbolView.contentMode = UIViewContentModeCenter;
    self.symbolView.isAccessibilityElement = NO;
    [self.iconSurfaceView addSubview:self.symbolView];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
                            scaledFontForFont:[Styling fontBold:PPFontHeadline]];
    self.titleLabel.textColor = [UIColor ppTextPrimary];
    self.titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.titleLabel.isAccessibilityElement = NO;
    [self.surfaceView addSubview:self.titleLabel];

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.subtitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
                               scaledFontForFont:[Styling fontRegular:PPFontSubheadline]];
    self.subtitleLabel.textColor = [UIColor ppTextSecondary];
    self.subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.subtitleLabel.isAccessibilityElement = NO;
    [self.surfaceView addSubview:self.subtitleLabel];

    self.toggleSwitch = [PPNotificationCategorySwitch new];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.toggleSwitch.onTintColor = [UIColor ppPrimary];
    [self.toggleSwitch addTarget:self action:@selector(pp_switchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.surfaceView addSubview:self.toggleSwitch];

    self.separatorView = [UIView new];
    self.separatorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.separatorView.backgroundColor = [UIColor ppSeparator];
    self.separatorView.isAccessibilityElement = NO;
    [self.surfaceView addSubview:self.separatorView];

    [NSLayoutConstraint activateConstraints:@[
        [self.surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.iconSurfaceView.topAnchor constraintEqualToAnchor:self.surfaceView.topAnchor constant:PPSpaceLG],
        [self.iconSurfaceView.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.iconSurfaceView.heightAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.symbolView.centerXAnchor constraintEqualToAnchor:self.iconSurfaceView.centerXAnchor],
        [self.symbolView.centerYAnchor constraintEqualToAnchor:self.iconSurfaceView.centerYAnchor],

        [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.surfaceView.centerYAnchor],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.surfaceView.topAnchor constant:PPSpaceBase],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:PPSpaceXS],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.surfaceView.bottomAnchor constant:-PPSpaceBase],

        [self.separatorView.bottomAnchor constraintEqualToAnchor:self.surfaceView.bottomAnchor],
        [self.separatorView.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [self.surfaceView.heightAnchor constraintGreaterThanOrEqualToConstant:88.0],
    ]];

    NSArray<NSLayoutConstraint *> *directionalConstraints = nil;
    if (Language.isRTL) {
        directionalConstraints = @[
            [self.iconSurfaceView.trailingAnchor constraintEqualToAnchor:self.surfaceView.trailingAnchor constant:-PPSpaceBase],
            [self.toggleSwitch.leadingAnchor constraintEqualToAnchor:self.surfaceView.leadingAnchor constant:PPSpaceBase],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.iconSurfaceView.leadingAnchor constant:-PPSpaceMD],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.toggleSwitch.trailingAnchor constant:PPSpaceMD],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.toggleSwitch.trailingAnchor constant:PPSpaceMD],
            [self.separatorView.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.separatorView.leadingAnchor constraintEqualToAnchor:self.surfaceView.leadingAnchor constant:PPSpaceBase],
        ];
    } else {
        directionalConstraints = @[
            [self.iconSurfaceView.leadingAnchor constraintEqualToAnchor:self.surfaceView.leadingAnchor constant:PPSpaceBase],
            [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.surfaceView.trailingAnchor constant:-PPSpaceBase],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconSurfaceView.trailingAnchor constant:PPSpaceMD],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor constant:-PPSpaceMD],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor constant:-PPSpaceMD],
            [self.separatorView.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.separatorView.trailingAnchor constraintEqualToAnchor:self.surfaceView.trailingAnchor constant:-PPSpaceBase],
        ];
    }
    [NSLayoutConstraint activateConstraints:directionalConstraints];
}

- (void)update {
    [super update];

    NSDictionary *metadata = self.rowDescriptor.extraInfo ?: @{};
    NSString *subtitle = [metadata[PPNotificationCategorySubtitleKey] isKindOfClass:NSString.class]
        ? metadata[PPNotificationCategorySubtitleKey]
        : @"";
    NSString *symbolName = [metadata[PPNotificationCategorySymbolKey] isKindOfClass:NSString.class]
        ? metadata[PPNotificationCategorySymbolKey]
        : @"bell.fill";
    UIColor *accent = [metadata[PPNotificationCategoryAccentKey] isKindOfClass:UIColor.class]
        ? metadata[PPNotificationCategoryAccentKey]
        : [UIColor ppPrimary];
    BOOL isFirst = [metadata[PPNotificationCategoryFirstKey] boolValue];
    BOOL isLast = [metadata[PPNotificationCategoryLastKey] boolValue];
    BOOL isDisabled = self.rowDescriptor.isDisabled;

    self.titleLabel.text = self.rowDescriptor.title ?: @"";
    self.subtitleLabel.text = subtitle;
    self.symbolView.image = [UIImage systemImageNamed:symbolName
                                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                                                                           weight:UIImageSymbolWeightSemibold]];
    self.symbolView.tintColor = accent;
    self.iconSurfaceView.backgroundColor = [accent colorWithAlphaComponent:0.12];
    self.toggleSwitch.on = [self.rowDescriptor.value boolValue];
    self.toggleSwitch.enabled = !isDisabled;
    self.toggleSwitch.accessibilityIdentifier = self.rowDescriptor.tag;
    self.toggleSwitch.accessibilityLabel = self.titleLabel.text;
    self.toggleSwitch.accessibilityHint = subtitle;
    self.separatorView.hidden = isLast;
    self.contentView.accessibilityIdentifier = self.rowDescriptor.tag;

    self.surfaceView.layer.cornerRadius = PPCornerCard;
    self.surfaceView.layer.maskedCorners = 0;
    if (isFirst) {
        self.surfaceView.layer.maskedCorners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    if (isLast) {
        self.surfaceView.layer.maskedCorners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    if (@available(iOS 13.0, *)) {
        self.surfaceView.layer.cornerCurve = kCACornerCurveContinuous;
    }

    self.titleLabel.textColor = isDisabled ? [UIColor ppTextTertiary] : [UIColor ppTextPrimary];
    self.subtitleLabel.textColor = isDisabled ? [UIColor ppTextTertiary] : [UIColor ppTextSecondary];
    self.iconSurfaceView.alpha = isDisabled ? 0.55 : 1.0;
    self.contentView.alpha = isDisabled ? 0.72 : 1.0;
}

- (void)pp_switchChanged:(UISwitch *)sender {
    self.rowDescriptor.value = @(sender.isOn);
}

- (void)formDescriptorCellDidSelectedWithFormController:(XLFormViewController *)controller {
    (void)controller;
    if (self.rowDescriptor.isDisabled) return;
    [self.toggleSwitch setOn:!self.toggleSwitch.isOn animated:!UIAccessibilityIsReduceMotionEnabled()];
    [self pp_switchChanged:self.toggleSwitch];
}

@end

@interface NotificationSettingsViewController ()

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIImageView *summaryIconView;
@property (nonatomic, strong) UIView *summarySurfaceView;
@property (nonatomic, assign) BOOL isSizingHeader;
@property (nonatomic, strong) UIView *v6NavRow;

- (void)pp_buildForm;
- (void)pp_buildHeader;
- (void)pp_sizeHeaderToFit;
- (void)pp_updateSummary;

@end

@implementation NotificationSettingsViewController

@synthesize rowDescriptor;

#pragma mark - Lifecycle

- (instancetype)init {
    self = [super initWithForm:[XLFormDescriptor formDescriptor] style:UITableViewStyleInsetGrouped];
    if (self) {
        [self pp_buildForm];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 104.0;
    self.tableView.sectionFooterHeight = PPSpaceXL;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, PPSpaceXL, 0.0);

    [self pp_buildHeader];
    [self pp_updateSummary];
    [self pp_setupV6NavRow];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
}

- (void)didTapBack {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)pp_setupV6NavRow {
    if (self.v6NavRow) return;

    UIView *navRow = [[UIView alloc] init];
    navRow.translatesAutoresizingMaskIntoConstraints = NO;
    navRow.backgroundColor = UIColor.clearColor;
    navRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    UIButton *backBtn = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(didTapBack)];
    [navRow addSubview:backBtn];
    
    [self.view addSubview:navRow];
    
    [NSLayoutConstraint activateConstraints:@[
        [navRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [navRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [navRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        
        [backBtn.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor constant:16],
        [backBtn.topAnchor constraintEqualToAnchor:navRow.topAnchor constant:10],
        [backBtn.bottomAnchor constraintEqualToAnchor:navRow.bottomAnchor constant:-10],
        [backBtn.widthAnchor constraintEqualToConstant:44],
        [backBtn.heightAnchor constraintEqualToConstant:44]
    ]];
    
    self.v6NavRow = navRow;
    
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_sizeHeaderToFit];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.summarySurfaceView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        [self.tableView reloadData];
    }
}

#pragma mark - Form

- (void)pp_buildForm {
    self.title = kLang(@"Notification Settings");

    XLFormSectionDescriptor *section = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Categories")];
    [self.form addFormSection:section];

    [section addFormRow:[self pp_categoryRowWithTag:PPNotificationCategoryGeneralTag
                                               title:kLang(@"General")
                                            subtitle:kLang(@"NotificationSettings_CategoryGeneralSubtitle")
                                          symbolName:@"bell.badge.fill"
                                               color:[UIColor ppInfo]
                                               first:YES
                                                last:NO]];
    [section addFormRow:[self pp_categoryRowWithTag:PPNotificationCategoryOrderTag
                                               title:kLang(@"Orders")
                                            subtitle:kLang(@"NotificationSettings_CategoryOrdersSubtitle")
                                          symbolName:@"shippingbox.fill"
                                               color:[UIColor ppPrimary]
                                               first:NO
                                                last:NO]];
    [section addFormRow:[self pp_categoryRowWithTag:PPNotificationCategoryReviewTag
                                               title:kLang(@"Ad Review")
                                            subtitle:kLang(@"NotificationSettings_CategoryReviewSubtitle")
                                          symbolName:@"doc.text.magnifyingglass"
                                               color:[UIColor ppQuickActionServices]
                                               first:NO
                                                last:NO]];
    [section addFormRow:[self pp_categoryRowWithTag:PPNotificationCategoryWarningTag
                                               title:kLang(@"Warnings")
                                            subtitle:kLang(@"NotificationSettings_CategoryWarningSubtitle")
                                          symbolName:@"exclamationmark.shield.fill"
                                               color:[UIColor ppWarning]
                                               first:NO
                                                last:YES]];
}

- (XLFormRowDescriptor *)pp_categoryRowWithTag:(NSString *)tag
                                         title:(NSString *)title
                                      subtitle:(NSString *)subtitle
                                    symbolName:(NSString *)symbolName
                                         color:(UIColor *)color
                                         first:(BOOL)first
                                          last:(BOOL)last {
    XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:tag
                                                                    rowType:XLFormRowDescriptorTypeBooleanSwitch
                                                                      title:title];
    row.value = @YES;
    row.cellClass = PPNotificationCategoryCell.class;
    row.extraInfo = @{
        PPNotificationCategorySubtitleKey: subtitle ?: @"",
        PPNotificationCategorySymbolKey: symbolName ?: @"bell.fill",
        PPNotificationCategoryAccentKey: color ?: [UIColor ppPrimary],
        PPNotificationCategoryFirstKey: @(first),
        PPNotificationCategoryLastKey: @(last),
    };

    __weak typeof(self) weakSelf = self;
    row.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *changedRow) {
        (void)oldValue;
        (void)newValue;
        (void)changedRow;
        [weakSelf pp_updateSummary];
    };
    return row;
}

#pragma mark - Header

- (void)pp_buildHeader {
    UIView *header = [UIView new];
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    header.layoutMargins = UIEdgeInsetsMake(PPSpaceXL, PPScreenMargin, PPSpaceLG, PPScreenMargin);
    self.headerView = header;

    UIView *iconSurface = [UIView new];
    iconSurface.translatesAutoresizingMaskIntoConstraints = NO;
    iconSurface.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(iconSurface, PPCornerMedium);
    [header addSubview:iconSurface];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bell.and.waves.left.and.right.fill"
                                                                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20.0
                                                                                                                                      weight:UIImageSymbolWeightSemibold]]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor ppPrimary];
    icon.isAccessibilityElement = NO;
    [iconSurface addSubview:icon];

    UILabel *eyebrow = [self pp_labelWithText:kLang(@"NotificationSettings_Eyebrow")
                                    textStyle:UIFontTextStyleCaption1
                                     baseFont:[Styling fontBold:PPFontCaption1]
                                        color:[UIColor ppPrimary]
                                        lines:0];
    [header addSubview:eyebrow];

    UILabel *title = [self pp_labelWithText:kLang(@"NotificationSettings_HeroTitle")
                                  textStyle:UIFontTextStyleTitle1
                                   baseFont:[Styling fontBold:PPFontTitle1]
                                      color:[UIColor ppTextPrimary]
                                      lines:0];
    [header addSubview:title];

    UILabel *subtitle = [self pp_labelWithText:kLang(@"NotificationSettings_HeroSubtitle")
                                     textStyle:UIFontTextStyleBody
                                      baseFont:[Styling fontRegular:PPFontBody]
                                         color:[UIColor ppTextSecondary]
                                         lines:0];
    [header addSubview:subtitle];

    UIView *summarySurface = [UIView new];
    summarySurface.translatesAutoresizingMaskIntoConstraints = NO;
    summarySurface.backgroundColor = [UIColor ppSurface];
    summarySurface.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    summarySurface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    PPApplyContinuousCorners(summarySurface, PPCorner16);
    [header addSubview:summarySurface];
    self.summarySurfaceView = summarySurface;

    self.summaryIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    self.summaryIconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.summaryIconView.tintColor = [UIColor ppSuccess];
    self.summaryIconView.isAccessibilityElement = NO;
    [summarySurface addSubview:self.summaryIconView];

    self.summaryLabel = [self pp_labelWithText:@""
                                     textStyle:UIFontTextStyleSubheadline
                                      baseFont:[Styling fontMedium:PPFontSubheadline]
                                         color:[UIColor ppTextPrimary]
                                         lines:0];
    [summarySurface addSubview:self.summaryLabel];

    UILabel *note = [self pp_labelWithText:kLang(@"NotificationSettings_SessionNote")
                                 textStyle:UIFontTextStyleFootnote
                                  baseFont:[Styling fontRegular:PPFontFootnote]
                                     color:[UIColor ppTextTertiary]
                                     lines:0];
    [header addSubview:note];

    UILayoutGuide *readable = header.readableContentGuide;
    [NSLayoutConstraint activateConstraints:@[
        [iconSurface.topAnchor constraintEqualToAnchor:header.layoutMarginsGuide.topAnchor],
        [iconSurface.widthAnchor constraintEqualToConstant:48.0],
        [iconSurface.heightAnchor constraintEqualToConstant:48.0],
        [icon.centerXAnchor constraintEqualToAnchor:iconSurface.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconSurface.centerYAnchor],

        [eyebrow.topAnchor constraintEqualToAnchor:iconSurface.topAnchor constant:PPSpaceXS],

        [title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:PPSpaceXS],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceMD],
        [subtitle.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],

        [summarySurface.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:PPSpaceBase],
        [summarySurface.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
        [summarySurface.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
        [summarySurface.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],

        [self.summaryIconView.centerYAnchor constraintEqualToAnchor:summarySurface.centerYAnchor],
        [self.summaryIconView.widthAnchor constraintEqualToConstant:PPSpaceLG],
        [self.summaryIconView.heightAnchor constraintEqualToConstant:PPSpaceLG],

        [self.summaryLabel.topAnchor constraintEqualToAnchor:summarySurface.topAnchor constant:PPSpaceSM],
        [self.summaryLabel.bottomAnchor constraintEqualToAnchor:summarySurface.bottomAnchor constant:-PPSpaceSM],

        [note.topAnchor constraintEqualToAnchor:summarySurface.bottomAnchor constant:PPSpaceMD],
        [note.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
        [note.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
        [note.bottomAnchor constraintEqualToAnchor:header.layoutMarginsGuide.bottomAnchor],
    ]];

    NSArray<NSLayoutConstraint *> *directionalConstraints = nil;
    if (Language.isRTL) {
        directionalConstraints = @[
            [iconSurface.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
            [eyebrow.trailingAnchor constraintEqualToAnchor:iconSurface.leadingAnchor constant:-PPSpaceMD],
            [eyebrow.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
            [title.trailingAnchor constraintEqualToAnchor:eyebrow.trailingAnchor],
            [title.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
            [self.summaryIconView.trailingAnchor constraintEqualToAnchor:summarySurface.trailingAnchor constant:-PPSpaceMD],
            [self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.summaryIconView.leadingAnchor constant:-PPSpaceSM],
            [self.summaryLabel.leadingAnchor constraintEqualToAnchor:summarySurface.leadingAnchor constant:PPSpaceMD],
        ];
    } else {
        directionalConstraints = @[
            [iconSurface.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
            [eyebrow.leadingAnchor constraintEqualToAnchor:iconSurface.trailingAnchor constant:PPSpaceMD],
            [eyebrow.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
            [title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
            [title.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
            [self.summaryIconView.leadingAnchor constraintEqualToAnchor:summarySurface.leadingAnchor constant:PPSpaceMD],
            [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.summaryIconView.trailingAnchor constant:PPSpaceSM],
            [self.summaryLabel.trailingAnchor constraintEqualToAnchor:summarySurface.trailingAnchor constant:-PPSpaceMD],
        ];
    }
    [NSLayoutConstraint activateConstraints:directionalConstraints];

    self.tableView.tableHeaderView = header;
}

- (UILabel *)pp_labelWithText:(NSString *)text
                    textStyle:(UIFontTextStyle)textStyle
                     baseFont:(UIFont *)baseFont
                        color:(UIColor *)color
                        lines:(NSInteger)lines {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.textAlignment = [Language alignmentForCurrentLanguage];
    label.numberOfLines = lines;
    return label;
}

- (void)pp_sizeHeaderToFit {
    if (self.isSizingHeader || !self.headerView || self.tableView.bounds.size.width <= 0.0) return;
    self.isSizingHeader = YES;

    CGRect frame = self.headerView.frame;
    frame.size.width = self.tableView.bounds.size.width;
    self.headerView.frame = frame;
    CGSize targetSize = CGSizeMake(frame.size.width, UILayoutFittingCompressedSize.height);
    CGFloat height = [self.headerView systemLayoutSizeFittingSize:targetSize
                                  withHorizontalFittingPriority:UILayoutPriorityRequired
                                        verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (fabs(frame.size.height - height) > 0.5) {
        frame.size.height = height;
        self.headerView.frame = frame;
        self.tableView.tableHeaderView = self.headerView;
    }

    self.isSizingHeader = NO;
}

- (void)pp_updateSummary {
    NSArray<NSString *> *tags = @[
        PPNotificationCategoryGeneralTag,
        PPNotificationCategoryOrderTag,
        PPNotificationCategoryReviewTag,
        PPNotificationCategoryWarningTag,
    ];
    NSInteger enabledCount = 0;
    for (NSString *tag in tags) {
        enabledCount += [[self.form formRowWithTag:tag].value boolValue] ? 1 : 0;
    }

    self.summaryLabel.text = [NSString stringWithFormat:kLang(@"NotificationSettings_EnabledCount_Format"),
                              (long)enabledCount,
                              (long)tags.count];
    BOOL hasEnabledCategories = enabledCount > 0;
    self.summaryIconView.image = [UIImage systemImageNamed:hasEnabledCategories ? @"checkmark.circle.fill" : @"bell.slash.fill"];
    self.summaryIconView.tintColor = hasEnabledCategories ? [UIColor ppSuccess] : [UIColor ppTextTertiary];
    self.summaryLabel.accessibilityLabel = self.summaryLabel.text;
    [self pp_sizeHeaderToFit];
}

#pragma mark - Table Styling

- (void)tableView:(UITableView *)tableView
 willDisplayHeaderView:(UIView *)view
        forSection:(NSInteger)section {
    [super tableView:tableView willDisplayHeaderView:view forSection:section];
    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;

    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    header.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]
                             scaledFontForFont:[Styling fontBold:PPFontSubheadline]];
    header.textLabel.adjustsFontForContentSizeCategory = YES;
    header.textLabel.textColor = [UIColor ppTextSecondary];
    header.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
}

@end
