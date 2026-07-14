#import "PPProviderApplicationsViewController.h"
#import "PPProviderService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "PPHero.h"

static NSString * const PPProviderApplicationCellID = @"PPProviderApplicationCell";
static CGFloat const PPProviderApplicationsHorizontalInset = 18.0;

static UIColor *PPProviderApplicationsBackgroundColor(void) {
    return AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
}

static UIColor *PPProviderApplicationsSurfaceColor(void) {
    return AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
}

static UIColor *PPProviderApplicationsPrimaryColor(void) {
    return AppPrimaryClr ?: UIColor.systemBlueColor;
}

static UIColor *PPProviderApplicationsPrimaryTextColor(void) {
    return PrimaryTextClr ?: UIColor.labelColor;
}

static UIColor *PPProviderApplicationsSecondaryTextColor(void) {
    return SeconderyTextClr ?: UIColor.secondaryLabelColor;
}

static UIColor *PPProviderApplicationsBorderColor(void) {
    return [PPProviderApplicationsPrimaryColor() colorWithAlphaComponent:0.09];
}

static NSString *PPProviderApplicationsSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSString *PPProviderApplicationsDisplayName(PPProviderApplication *app) {
    NSDictionary *form = [app.form isKindOfClass:NSDictionary.class] ? app.form : @{};
    NSString *name = PPProviderApplicationsSafeString(form[@"fullName"]);
    if (name.length == 0) name = PPProviderApplicationsSafeString(form[@"businessName"]);
    if (name.length == 0) name = PPProviderApplicationsSafeString(form[@"companyName"]);
    if (name.length == 0) name = PPProviderApplicationsSafeString(form[@"legalName"]);
    if (name.length == 0) name = PPProviderApplicationsSafeString(app.userId);
    return name.length ? name : kLang(@"Providers_Applications_UnknownApplicant");
}

static UIColor *PPProviderApplicationsStatusColor(NSString *status) {
    NSString *normalized = PPProviderApplicationsSafeString(status).lowercaseString;
    if ([normalized isEqualToString:@"approved"]) return UIColor.systemGreenColor;
    if ([normalized isEqualToString:@"rejected"]) return UIColor.systemRedColor;
    if ([normalized isEqualToString:@"under_review"]) return UIColor.systemOrangeColor;
    return UIColor.systemOrangeColor;
}

static NSString *PPProviderApplicationsLocalizedStatus(NSString *status) {
    NSString *normalized = PPProviderApplicationsSafeString(status).lowercaseString;
    if ([normalized isEqualToString:@"approved"]) return kLang(@"Providers_Status_Approved");
    if ([normalized isEqualToString:@"rejected"]) return kLang(@"Providers_Status_Rejected");
    if ([normalized isEqualToString:@"under_review"]) return kLang(@"Providers_Status_UnderReview");
    return kLang(@"Providers_Status_Pending");
}

static NSString *PPProviderApplicationsLocalizedProviderType(NSString *providerType) {
    NSString *token = [[PPProviderApplicationsSafeString(providerType) stringByReplacingOccurrencesOfString:@"-" withString:@"_"] lowercaseString];
    if (token.length == 0) return kLang(@"Providers_Type_Unknown");
    NSString *key = [@"Providers_Type_" stringByAppendingString:token];
    NSString *localized = kLang(key);
    if ([localized isKindOfClass:NSString.class] && localized.length > 0 && ![localized isEqualToString:key]) {
        return localized;
    }
    return providerType ?: @"";
}

static NSString *PPProviderApplicationsDateText(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

@interface PPProviderApplicationCell : UITableViewCell
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *iconShellView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *idLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *chevronView;
- (void)configureWithApplication:(PPProviderApplication *)application;
@end

@implementation PPProviderApplicationCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _surfaceView = [UIView new];
        _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
        _surfaceView.backgroundColor = PPProviderApplicationsSurfaceColor();
        _surfaceView.layer.cornerRadius = 22.0;
        _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _surfaceView.layer.borderColor = PPProviderApplicationsBorderColor().CGColor;
        _surfaceView.layer.shadowColor = UIColor.blackColor.CGColor;
        _surfaceView.layer.shadowOpacity = 0.055;
        _surfaceView.layer.shadowRadius = 16.0;
        _surfaceView.layer.shadowOffset = CGSizeMake(0.0, 9.0);
        [self.contentView addSubview:_surfaceView];

        _iconShellView = [UIView new];
        _iconShellView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconShellView.backgroundColor = [PPProviderApplicationsPrimaryColor() colorWithAlphaComponent:0.11];
        _iconShellView.layer.cornerRadius = 20.0;
        [_surfaceView addSubview:_iconShellView];

        UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightSemibold];
        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"building.2.crop.circle.fill" withConfiguration:iconConfig]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = PPProviderApplicationsPrimaryColor();
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconShellView addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:16.5];
        _titleLabel.textColor = PPProviderApplicationsPrimaryTextColor();
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_surfaceView addSubview:_titleLabel];

        _metaLabel = [UILabel new];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel.font = [Styling fontMedium:13.0];
        _metaLabel.textColor = [PPProviderApplicationsSecondaryTextColor() colorWithAlphaComponent:0.94];
        _metaLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _metaLabel.numberOfLines = 1;
        [_surfaceView addSubview:_metaLabel];

        _idLabel = [UILabel new];
        _idLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _idLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightMedium];
        _idLabel.textColor = [PPProviderApplicationsSecondaryTextColor() colorWithAlphaComponent:0.72];
        _idLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _idLabel.numberOfLines = 1;
        _idLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [_surfaceView addSubview:_idLabel];

        _statusLabel = [UILabel new];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = [Styling fontMedium:11.5];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.layer.cornerRadius = 12.0;
        _statusLabel.layer.masksToBounds = YES;
        _statusLabel.adjustsFontSizeToFitWidth = YES;
        _statusLabel.minimumScaleFactor = 0.82;
        [_surfaceView addSubview:_statusLabel];

        UIImageSymbolConfiguration *chevronConfig = [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold];
        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:chevronConfig]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.tintColor = [PPProviderApplicationsSecondaryTextColor() colorWithAlphaComponent:0.6];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;
        [_surfaceView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPProviderApplicationsHorizontalInset],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPProviderApplicationsHorizontalInset],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [_surfaceView.heightAnchor constraintGreaterThanOrEqualToConstant:96.0],

            [_iconShellView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:16.0],
            [_iconShellView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_iconShellView.widthAnchor constraintEqualToConstant:42.0],
            [_iconShellView.heightAnchor constraintEqualToConstant:42.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconShellView.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconShellView.centerYAnchor],

            [_chevronView.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-16.0],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:14.0],
            [_chevronView.heightAnchor constraintEqualToConstant:14.0],

            [_statusLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-10.0],
            [_statusLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:16.0],
            [_statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:82.0],
            [_statusLabel.heightAnchor constraintEqualToConstant:25.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconShellView.trailingAnchor constant:13.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-12.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:17.0],

            [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-12.0],
            [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],

            [_idLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_idLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-12.0],
            [_idLabel.topAnchor constraintEqualToAnchor:_metaLabel.bottomAnchor constant:6.0],
            [_idLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_surfaceView.bottomAnchor constant:-16.0],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.surfaceView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.surfaceView.bounds
                                                                   cornerRadius:self.surfaceView.layer.cornerRadius].CGPath;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
    self.surfaceView.transform = CGAffineTransformIdentity;
    self.surfaceView.alpha = 1.0;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CGFloat scale = highlighted ? 0.985 : 1.0;
    [UIView animateWithDuration:0.16
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.surfaceView.transform = CGAffineTransformMakeScale(scale, scale);
        self.surfaceView.alpha = highlighted ? 0.96 : 1.0;
    } completion:nil];
}

- (void)configureWithApplication:(PPProviderApplication *)application {
    NSString *name = PPProviderApplicationsDisplayName(application);
    NSString *type = PPProviderApplicationsLocalizedProviderType(application.providerType);
    NSString *dateText = PPProviderApplicationsDateText(application.createdAt);
    NSString *statusText = PPProviderApplicationsLocalizedStatus(application.status);
    UIColor *statusColor = PPProviderApplicationsStatusColor(application.status);

    self.titleLabel.text = name;
    self.metaLabel.text = dateText.length ? [NSString stringWithFormat:@"%@ • %@", type, dateText] : type;
    self.idLabel.text = application.applicationID.length ? application.applicationID : application.userId;
    self.statusLabel.text = statusText;
    self.statusLabel.textColor = statusColor;
    self.statusLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.12];
    self.iconShellView.backgroundColor = [statusColor colorWithAlphaComponent:0.10];
    self.iconView.tintColor = statusColor;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@",
                               name ?: @"",
                               type ?: @"",
                               statusText ?: @""];
}

@end

@interface PPProviderApplicationsViewController ()
@property (nonatomic, strong) NSArray<PPProviderApplication *> *applications;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, copy) NSString *statusFilter;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UILabel *stateTitleLabel;
@property (nonatomic, strong) UILabel *stateSubtitleLabel;
@property (nonatomic, strong) UIActivityIndicatorView *stateSpinner;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedApplicationIDs;
@property (nonatomic, assign) CGFloat headerWidth;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *heroCountLabel;
@end

@implementation PPProviderApplicationsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.applications = @[];
    self.animatedApplicationIDs = [NSMutableSet set];
    self.statusFilter = @"all";
    self.view.backgroundColor = PPProviderApplicationsBackgroundColor();
    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_installHeaderForCurrentWidthForce:YES];
    [self loadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroBackground startAnimations];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.heroBackground stopAnimations];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (fabs(width - self.headerWidth) > 1.0) {
        [self pp_installHeaderForCurrentWidthForce:YES];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.heroBackground reapplyPalette];
    }
}

#pragma mark - Setup

- (void)pp_configureNavigation {
    self.title = kLang(@"Providers_Applications_Title");
    self.navigationItem.titleView = nil;
    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(loadData)];
    self.navigationItem.rightBarButtonItem = refreshBtn;
}

- (void)pp_configureTableView {
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.backgroundColor = PPProviderApplicationsBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 108.0;
    self.tableView.contentInset = UIEdgeInsetsMake(4.0, 0.0, 34.0, 0.0);
    [self.tableView registerClass:PPProviderApplicationCell.class forCellReuseIdentifier:PPProviderApplicationCellID];
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = PPProviderApplicationsPrimaryColor();
    [refresh addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.stateView = [self pp_buildStateView];
    self.tableView.backgroundView = self.stateView;
    [self pp_updateStateView];
}

- (UIView *)pp_buildStateView {
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.clearColor;

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:content];

    self.stateSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.stateSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateSpinner.color = PPProviderApplicationsPrimaryColor();
    [content addSubview:self.stateSpinner];

    UIView *iconShell = [UIView new];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPProviderApplicationsPrimaryColor() colorWithAlphaComponent:0.09];
    iconShell.layer.cornerRadius = 28.0;
    [content addSubview:iconShell];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"tray.fill"
                                                                   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightSemibold]]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = PPProviderApplicationsPrimaryColor();
    [iconShell addSubview:icon];

    self.stateTitleLabel = [UILabel new];
    self.stateTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateTitleLabel.font = [Styling fontBold:18.0];
    self.stateTitleLabel.textColor = PPProviderApplicationsPrimaryTextColor();
    self.stateTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateTitleLabel.numberOfLines = 2;
    [content addSubview:self.stateTitleLabel];

    self.stateSubtitleLabel = [UILabel new];
    self.stateSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateSubtitleLabel.font = [Styling fontRegular:14.0];
    self.stateSubtitleLabel.textColor = [PPProviderApplicationsSecondaryTextColor() colorWithAlphaComponent:0.9];
    self.stateSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.stateSubtitleLabel.numberOfLines = 3;
    [content addSubview:self.stateSubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:-22.0],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:28.0],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-28.0],

        [iconShell.topAnchor constraintEqualToAnchor:content.topAnchor],
        [iconShell.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [iconShell.widthAnchor constraintEqualToConstant:56.0],
        [iconShell.heightAnchor constraintEqualToConstant:56.0],

        [icon.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [self.stateSpinner.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [self.stateSpinner.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [self.stateTitleLabel.topAnchor constraintEqualToAnchor:iconShell.bottomAnchor constant:18.0],
        [self.stateTitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.stateTitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],

        [self.stateSubtitleLabel.topAnchor constraintEqualToAnchor:self.stateTitleLabel.bottomAnchor constant:8.0],
        [self.stateSubtitleLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.stateSubtitleLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.stateSubtitleLabel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    return container;
}

#pragma mark - Header

- (void)pp_installHeaderForCurrentWidthForce:(BOOL)force {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;
    if (!force && fabs(width - self.headerWidth) <= 1.0) return;
    self.headerWidth = width;
    self.tableView.tableHeaderView = [self pp_buildHeaderWithWidth:width];
    [self pp_refreshHeroCount];
}

- (UIView *)pp_buildHeaderWithWidth:(CGFloat)width {
    CGFloat inset = width > 800.0 ? 28.0 : PPProviderApplicationsHorizontalInset;
    CGFloat heroHeight = 166.0;
    CGFloat filterHeight = 46.0;
    CGFloat headerHeight = heroHeight + filterHeight + 42.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, headerHeight)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *heroCard = [[UIView alloc] initWithFrame:CGRectMake(inset, 14.0, width - (inset * 2.0), heroHeight)];
    heroCard.backgroundColor = UIColor.clearColor;
    heroCard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:heroCard];

    PPHero *hero = [PPHero new];
    hero.frame = heroCard.bounds;
    hero.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    hero.accentColorOverride = PPProviderApplicationsPrimaryColor();
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.54;
    [heroCard addSubview:hero];
    self.heroBackground = hero;
    [self.heroBackground startAnimations];

    BOOL isRTL = [Language isRTL];
    CGFloat heroWidth = CGRectGetWidth(heroCard.bounds);
    CGFloat iconX = isRTL ? (heroWidth - 22.0 - 54.0) : 22.0;
    UIView *iconShell = [[UIView alloc] initWithFrame:CGRectMake(iconX, 24.0, 54.0, 54.0)];
    iconShell.autoresizingMask = isRTL ? UIViewAutoresizingFlexibleLeftMargin : UIViewAutoresizingFlexibleRightMargin;
    iconShell.backgroundColor = [PPProviderApplicationsPrimaryColor() colorWithAlphaComponent:0.12];
    iconShell.layer.cornerRadius = 19.0;
    [heroCard addSubview:iconShell];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.rectangle.stack.fill"
                                                                   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:23.0 weight:UIImageSymbolWeightSemibold]]];
    icon.frame = CGRectMake(15.0, 15.0, 24.0, 24.0);
    icon.tintColor = PPProviderApplicationsPrimaryColor();
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:icon];

    CGFloat titleX = isRTL ? 22.0 : CGRectGetMaxX(iconShell.frame) + 14.0;
    CGFloat titleMaxX = isRTL ? CGRectGetMinX(iconShell.frame) - 14.0 : heroWidth - 24.0;
    CGFloat titleWidth = MAX(titleMaxX - titleX, 120.0);
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(titleX, 25.0, titleWidth, 31.0)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = kLang(@"Providers_Applications_HeroTitle");
    title.font = [Styling fontBold:24.0];
    title.textColor = PPProviderApplicationsPrimaryTextColor();
    title.textAlignment = Language.alignmentForCurrentLanguage;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.82;
    [heroCard addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(titleX, CGRectGetMaxY(title.frame) + 8.0, titleWidth, 42.0)];
    subtitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitle.text = kLang(@"Providers_Applications_HeroSubtitle");
    subtitle.font = [Styling fontRegular:14.0];
    subtitle.textColor = [PPProviderApplicationsSecondaryTextColor() colorWithAlphaComponent:0.92];
    subtitle.textAlignment = Language.alignmentForCurrentLanguage;
    subtitle.numberOfLines = 2;
    [heroCard addSubview:subtitle];

    UILabel *count = [[UILabel alloc] initWithFrame:CGRectMake(22.0, CGRectGetHeight(heroCard.bounds) - 48.0, CGRectGetWidth(heroCard.bounds) - 44.0, 30.0)];
    count.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    count.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
    count.textColor = PPProviderApplicationsPrimaryColor();
    count.textAlignment = Language.alignmentForCurrentLanguage;
    count.backgroundColor = [PPProviderApplicationsPrimaryColor() colorWithAlphaComponent:0.09];
    count.layer.cornerRadius = 15.0;
    count.layer.masksToBounds = YES;
    [heroCard addSubview:count];
    self.heroCountLabel = count;

    UISegmentedControl *segment = [[UISegmentedControl alloc] initWithItems:@[
        kLang(@"Providers_All"),
        kLang(@"Providers_Pending"),
        kLang(@"Providers_Approved"),
        kLang(@"Providers_Rejected")
    ]];
    segment.frame = CGRectMake(inset, CGRectGetMaxY(heroCard.frame) + 16.0, width - (inset * 2.0), filterHeight);
    segment.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    segment.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    segment.selectedSegmentIndex = [self pp_selectedFilterIndex];
    segment.backgroundColor = [PPProviderApplicationsSurfaceColor() colorWithAlphaComponent:0.86];
    segment.selectedSegmentTintColor = PPProviderApplicationsPrimaryColor();
    [segment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: PPProviderApplicationsPrimaryTextColor(),
        NSFontAttributeName: [Styling fontMedium:13.0]
    } forState:UIControlStateNormal];
    [segment setTitleTextAttributes:@{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [Styling fontBold:13.0]
    } forState:UIControlStateSelected];
    [segment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:segment];
    self.filterSegment = segment;

    return header;
}

- (NSUInteger)pp_selectedFilterIndex {
    NSArray<NSString *> *statuses = @[@"all", @"pending", @"approved", @"rejected"];
    NSUInteger index = [statuses indexOfObject:self.statusFilter ?: @"all"];
    return index == NSNotFound ? 0 : index;
}

- (void)pp_refreshHeroCount {
    NSUInteger filteredCount = [self filteredApps].count;
    NSString *format = kLang(@"Providers_Applications_Count_Format");
    if (![format isKindOfClass:NSString.class] || format.length == 0) {
        format = @"%lu applications";
    }
    self.heroCountLabel.text = [NSString stringWithFormat:format, (unsigned long)filteredCount];
}

#pragma mark - Data

- (void)filterChanged:(UISegmentedControl *)sender {
    NSArray<NSString *> *statuses = @[@"all", @"pending", @"approved", @"rejected"];
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)statuses.count) return;
    self.statusFilter = statuses[(NSUInteger)sender.selectedSegmentIndex];
    [self pp_refreshHeroCount];
    [self pp_updateStateView];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self.tableView reloadData];
        return;
    }

    [UIView transitionWithView:self.tableView
                      duration:0.20
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{
        [self.tableView reloadData];
    } completion:nil];
}

- (void)loadData {
    self.isLoading = YES;
    self.currentError = nil;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self pp_updateStateView];
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchApplicationsWithCompletion:^(NSArray<PPProviderApplication *> *apps, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            weakSelf.navigationItem.rightBarButtonItem.enabled = YES;
            [weakSelf.refreshControl endRefreshing];
            if (error) {
                weakSelf.currentError = error;
            } else {
                weakSelf.currentError = nil;
                weakSelf.applications = apps ?: @[];
            }
            [weakSelf pp_refreshHeroCount];
            [weakSelf pp_updateStateView];
            [weakSelf.tableView reloadData];
        });
    }];
}

- (NSArray<PPProviderApplication *> *)filteredApps {
    NSArray<PPProviderApplication *> *source = self.applications ?: @[];
    NSString *filter = self.statusFilter ?: @"all";
    if ([filter isEqualToString:@"all"]) return source;
    if ([filter isEqualToString:@"pending"]) {
        return [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PPProviderApplication *app, NSDictionary *bindings) {
            (void)bindings;
            NSString *status = PPProviderApplicationsSafeString(app.status).lowercaseString;
            return [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"] || status.length == 0;
        }]];
    }
    return [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PPProviderApplication *app, NSDictionary *bindings) {
        (void)bindings;
        return [PPProviderApplicationsSafeString(app.status).lowercaseString isEqualToString:filter];
    }]];
}

- (void)pp_updateStateView {
    BOOL hasRows = [self filteredApps].count > 0;
    self.stateView.hidden = hasRows;
    if (hasRows) {
        [self.stateSpinner stopAnimating];
        return;
    }

    if (self.isLoading) {
        self.stateTitleLabel.text = kLang(@"Providers_Applications_Loading");
        self.stateSubtitleLabel.text = kLang(@"Providers_Applications_Subtitle");
        [self.stateSpinner startAnimating];
        return;
    }

    [self.stateSpinner stopAnimating];
    if (self.currentError) {
        self.stateTitleLabel.text = kLang(@"Providers_Applications_LoadFailed");
        self.stateSubtitleLabel.text = kLang(@"Providers_Applications_ErrorSubtitle");
    } else {
        self.stateTitleLabel.text = kLang(@"Providers_Applications_Empty");
        self.stateSubtitleLabel.text = kLang(@"Providers_Applications_EmptySubtitle");
    }
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [self filteredApps].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPProviderApplicationCell *cell = [tableView dequeueReusableCellWithIdentifier:PPProviderApplicationCellID forIndexPath:indexPath];
    PPProviderApplication *app = [self filteredApps][(NSUInteger)indexPath.row];
    [cell configureWithApplication:app];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<PPProviderApplication *> *apps = [self filteredApps];
    if (indexPath.row >= (NSInteger)apps.count || UIAccessibilityIsReduceMotionEnabled()) return;
    PPProviderApplication *app = apps[(NSUInteger)indexPath.row];
    NSString *identifier = app.applicationID.length ? app.applicationID : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedApplicationIDs containsObject:identifier]) return;
    [self.animatedApplicationIDs addObject:identifier];

    cell.contentView.alpha = 0.0;
    cell.contentView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    NSTimeInterval delay = MIN(indexPath.row, 8) * 0.025;
    [UIView animateWithDuration:0.32
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.contentView.alpha = 1.0;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<PPProviderApplication *> *filtered = [self filteredApps];
    if (indexPath.row >= (NSInteger)filtered.count) return;

    PPProviderApplication *app = filtered[(NSUInteger)indexPath.row];
    NSString *name = PPProviderApplicationsDisplayName(app);
    NSString *message = [NSString stringWithFormat:@"%@\n%@",
                         PPProviderApplicationsLocalizedProviderType(app.providerType),
                         PPProviderApplicationsLocalizedStatus(app.status)];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *status = PPProviderApplicationsSafeString(app.status).lowercaseString;
    if ([status isEqualToString:@"pending"] || status.length == 0) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_MarkUnderReview")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self reviewApp:app status:@"under_review"];
        }]];
    }
    if ([status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"] || status.length == 0) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Approve")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self reviewApp:app status:@"approved"];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Reject")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            [self reviewApp:app status:@"rejected"];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        popover.sourceView = cell ?: self.view;
        popover.sourceRect = cell ? cell.bounds : self.view.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reviewApp:(PPProviderApplication *)app status:(NSString *)status {
    UIAlertController *notesAlert = [UIAlertController alertControllerWithTitle:kLang(@"Providers_ReviewNotes")
                                                                        message:nil
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    [notesAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = kLang(@"Providers_ReviewNotesPlaceholder");
        tf.textAlignment = Language.alignmentForCurrentLanguage;
        tf.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    }];
    [notesAlert addAction:[UIAlertAction actionWithTitle:kLang(@"Confirm")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *action) {
        NSString *notes = notesAlert.textFields.firstObject.text;
        self.navigationItem.rightBarButtonItem.enabled = NO;
        [[PPProviderService shared] reviewApplication:app.applicationID status:status notes:notes completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.navigationItem.rightBarButtonItem.enabled = YES;
                if (error) {
                    [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                } else {
                    [PPFunc pp_playSuccessEffect];
                    [self loadData];
                }
            });
        }];
    }]];
    [notesAlert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:notesAlert animated:YES completion:nil];
}

@end
