//
//  PPFlagshipBannerCardCell.m
//  PurePetsAdmin
//
//  Flagship Beyond-FAANG Apple-grade Banner Card Interface
//

#import "PPFlagshipBannerCardCell.h"
#import "PPDesignTokens.h"
#import "Language.h"
#import "Styling.h"
#import "PPImageManager.h"

@interface PPFlagshipBannerCardCell ()

@property (nonatomic, strong) UIView *cardContainer;
@property (nonatomic, strong) UIView *bannerCanvas;
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) CAGradientLayer *canvasGradientLayer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UIView *timePill;
@property (nonatomic, strong) UIImageView *timeIconView;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIImageView *sampleImageView;
@property (nonatomic, strong) UIImageView *badgeImageView;

// Metadata Telemetry Strip
@property (nonatomic, strong) UIView *telemetryStrip;
@property (nonatomic, strong) UILabel *placementBadgeLabel;
@property (nonatomic, strong) UILabel *tapActionBadgeLabel;
@property (nonatomic, strong) UILabel *tapsCountBadgeLabel;

// Quick Action Bar
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) UIButton *statusToggleButton;
@property (nonatomic, strong) UIButton *previewButton;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) UIButton *moreButton;

@property (nonatomic, strong) MainBannerModel *groupModel;
@property (nonatomic, strong) PPBannerViewModel *bannerModel;
@property (nonatomic, strong) NSIndexPath *indexPath;

@end

@implementation PPFlagshipBannerCardCell

+ (NSString *)reuseIdentifier {
    return @"PPFlagshipBannerCardCell";
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupCellUI];
    }
    return self;
}

- (void)setupCellUI {
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    // Card Container
    _cardContainer = [[UIView alloc] init];
    _cardContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _cardContainer.backgroundColor = [UIColor ppElevatedSurface];
    _cardContainer.layer.cornerRadius = 24.0;
    if (@available(iOS 13.0, *)) {
        _cardContainer.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _cardContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _cardContainer.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.85].CGColor;
    _cardContainer.layer.shadowColor = [UIColor ppShadow].CGColor;
    _cardContainer.layer.shadowOffset = CGSizeMake(0.0, 6.0);
    _cardContainer.layer.shadowRadius = 16.0;
    _cardContainer.layer.shadowOpacity = 0.05;
    [self.contentView addSubview:_cardContainer];

    // Top Banner Canvas (Live Aspect-Ratio Preview)
    _bannerCanvas = [[UIView alloc] init];
    _bannerCanvas.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerCanvas.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    _bannerCanvas.layer.cornerRadius = 18.0;
    if (@available(iOS 13.0, *)) {
        _bannerCanvas.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _bannerCanvas.clipsToBounds = YES;
    [_cardContainer addSubview:_bannerCanvas];

    // Background Image
    _backgroundImageView = [[UIImageView alloc] init];
    _backgroundImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    _backgroundImageView.clipsToBounds = YES;
    [_bannerCanvas addSubview:_backgroundImageView];

    // Ambient Gradient Overlay
    _canvasGradientLayer = [CAGradientLayer layer];
    _canvasGradientLayer.colors = @[
        (id)[UIColor colorWithWhite:0.0 alpha:0.75].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.40].CGColor,
        (id)[UIColor colorWithWhite:0.0 alpha:0.70].CGColor
    ];
    _canvasGradientLayer.startPoint = CGPointMake(0.0, 0.5);
    _canvasGradientLayer.endPoint = CGPointMake(1.0, 0.5);
    [_bannerCanvas.layer addSublayer:_canvasGradientLayer];

    // Sample Product/Pet Image (Trailing)
    _sampleImageView = [[UIImageView alloc] init];
    _sampleImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _sampleImageView.contentMode = UIViewContentModeScaleAspectFill;
    _sampleImageView.clipsToBounds = YES;
    _sampleImageView.layer.cornerRadius = 16.0;
    if (@available(iOS 13.0, *)) {
        _sampleImageView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _sampleImageView.layer.borderWidth = 1.5;
    _sampleImageView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    _sampleImageView.backgroundColor = [[UIColor ppWarmPorcelain] colorWithAlphaComponent:0.4];
    [_bannerCanvas addSubview:_sampleImageView];

    // Badge Image (Top-Trailing over sample)
    _badgeImageView = [[UIImageView alloc] init];
    _badgeImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _badgeImageView.contentMode = UIViewContentModeScaleAspectFit;
    _badgeImageView.clipsToBounds = YES;
    _badgeImageView.hidden = YES;
    [_bannerCanvas addSubview:_badgeImageView];

    // Text Stack Container (Leading)
    UIStackView *textStack = [[UIStackView alloc] init];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 4.0;
    [_bannerCanvas addSubview:textStack];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:16]];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.numberOfLines = 2;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [textStack addArrangedSubview:_titleLabel];

    _descLabel = [[UILabel alloc] init];
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _descLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontMedium:13]];
    _descLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    _descLabel.numberOfLines = 2;
    _descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _descLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [textStack addArrangedSubview:_descLabel];

    // Time/Date Pill
    _timePill = [[UIView alloc] init];
    _timePill.translatesAutoresizingMaskIntoConstraints = NO;
    _timePill.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.38];
    _timePill.layer.cornerRadius = 10.0;
    if (@available(iOS 13.0, *)) {
        _timePill.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _timePill.clipsToBounds = YES;
    [textStack addArrangedSubview:_timePill];

    _timeIconView = [[UIImageView alloc] init];
    _timeIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _timeIconView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    _timeIconView.image = [UIImage systemImageNamed:@"calendar"];
    _timeIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_timePill addSubview:_timeIconView];

    _timeLabel = [[UILabel alloc] init];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timeLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[Styling fontRegular:11]];
    _timeLabel.textColor = UIColor.whiteColor;
    [_timePill addSubview:_timeLabel];

    // Metadata Telemetry Strip
    _telemetryStrip = [[UIView alloc] init];
    _telemetryStrip.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardContainer addSubview:_telemetryStrip];

    UIStackView *telemetryStack = [[UIStackView alloc] init];
    telemetryStack.translatesAutoresizingMaskIntoConstraints = NO;
    telemetryStack.axis = UILayoutConstraintAxisHorizontal;
    telemetryStack.spacing = 6.0;
    telemetryStack.alignment = UIStackViewAlignmentCenter;
    [_telemetryStrip addSubview:telemetryStack];

    _placementBadgeLabel = [self createCapsuleLabelWithBg:[[UIColor ppPrimary] colorWithAlphaComponent:0.10]
                                                textColor:[UIColor ppPrimary]];
    [telemetryStack addArrangedSubview:_placementBadgeLabel];

    _tapActionBadgeLabel = [self createCapsuleLabelWithBg:[[UIColor ppInfo] colorWithAlphaComponent:0.10]
                                                textColor:[UIColor ppInfo]];
    [telemetryStack addArrangedSubview:_tapActionBadgeLabel];

    _tapsCountBadgeLabel = [self createCapsuleLabelWithBg:[[UIColor ppWarmPorcelain] colorWithAlphaComponent:0.85]
                                                textColor:[UIColor ppTextSecondary]];
    [telemetryStack addArrangedSubview:_tapsCountBadgeLabel];

    // Separator
    UIView *divider = [[UIView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.5];
    [_cardContainer addSubview:divider];

    // Action Bar
    _actionBar = [[UIView alloc] init];
    _actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_cardContainer addSubview:_actionBar];

    // Status toggle pill button
    _statusToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _statusToggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    _statusToggleButton.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) {
        _statusToggleButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _statusToggleButton.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[Styling fontBold:12]];
    _statusToggleButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    [_statusToggleButton addTarget:self action:@selector(onStatusToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_actionBar addSubview:_statusToggleButton];

    // Action buttons container (Preview, Edit, More)
    UIStackView *rightActionsStack = [[UIStackView alloc] init];
    rightActionsStack.translatesAutoresizingMaskIntoConstraints = NO;
    rightActionsStack.axis = UILayoutConstraintAxisHorizontal;
    rightActionsStack.spacing = 8.0;
    rightActionsStack.alignment = UIStackViewAlignmentCenter;
    [_actionBar addSubview:rightActionsStack];

    _previewButton = [self createActionButtonWithIcon:@"eye"
                                                title:kLang(@"Banners_Action_Preview")
                                               action:@selector(onPreviewTapped)];
    [rightActionsStack addArrangedSubview:_previewButton];

    _editButton = [self createActionButtonWithIcon:@"pencil"
                                             title:kLang(@"Banners_Action_Edit")
                                            action:@selector(onEditTapped)];
    [rightActionsStack addArrangedSubview:_editButton];

    _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    _moreButton.tintColor = [UIColor ppTextSecondary];
    _moreButton.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.35];
    _moreButton.layer.cornerRadius = 16.0;
    [_moreButton addTarget:self action:@selector(onMoreTapped:) forControlEvents:UIControlEventTouchUpInside];
    [rightActionsStack addArrangedSubview:_moreButton];

    // Layout Constraints
    [NSLayoutConstraint activateConstraints:@[
        // Card Container
        [_cardContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
        [_cardContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [_cardContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [_cardContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0],

        // Banner Canvas
        [_bannerCanvas.topAnchor constraintEqualToAnchor:_cardContainer.topAnchor constant:12.0],
        [_bannerCanvas.leadingAnchor constraintEqualToAnchor:_cardContainer.leadingAnchor constant:12.0],
        [_bannerCanvas.trailingAnchor constraintEqualToAnchor:_cardContainer.trailingAnchor constant:-12.0],
        [_bannerCanvas.heightAnchor constraintGreaterThanOrEqualToConstant:128.0],

        // Background Image
        [_backgroundImageView.topAnchor constraintEqualToAnchor:_bannerCanvas.topAnchor],
        [_backgroundImageView.leadingAnchor constraintEqualToAnchor:_bannerCanvas.leadingAnchor],
        [_backgroundImageView.trailingAnchor constraintEqualToAnchor:_bannerCanvas.trailingAnchor],
        [_backgroundImageView.bottomAnchor constraintEqualToAnchor:_bannerCanvas.bottomAnchor],

        // Trailing Sample Image
        [_sampleImageView.trailingAnchor constraintEqualToAnchor:_bannerCanvas.trailingAnchor constant:-12.0],
        [_sampleImageView.centerYAnchor constraintEqualToAnchor:_bannerCanvas.centerYAnchor],
        [_sampleImageView.widthAnchor constraintEqualToConstant:84.0],
        [_sampleImageView.heightAnchor constraintEqualToConstant:84.0],

        // Badge Image
        [_badgeImageView.topAnchor constraintEqualToAnchor:_sampleImageView.topAnchor constant:-6.0],
        [_badgeImageView.trailingAnchor constraintEqualToAnchor:_sampleImageView.trailingAnchor constant:6.0],
        [_badgeImageView.widthAnchor constraintEqualToConstant:24.0],
        [_badgeImageView.heightAnchor constraintEqualToConstant:24.0],

        // Text Stack
        [textStack.topAnchor constraintEqualToAnchor:_bannerCanvas.topAnchor constant:12.0],
        [textStack.leadingAnchor constraintEqualToAnchor:_bannerCanvas.leadingAnchor constant:14.0],
        [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_sampleImageView.leadingAnchor constant:-12.0],
        [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:_bannerCanvas.bottomAnchor constant:-12.0],

        // Time Pill
        [_timeIconView.leadingAnchor constraintEqualToAnchor:_timePill.leadingAnchor constant:6.0],
        [_timeIconView.centerYAnchor constraintEqualToAnchor:_timePill.centerYAnchor],
        [_timeIconView.widthAnchor constraintEqualToConstant:12.0],
        [_timeIconView.heightAnchor constraintEqualToConstant:12.0],
        [_timeLabel.leadingAnchor constraintEqualToAnchor:_timeIconView.trailingAnchor constant:4.0],
        [_timeLabel.trailingAnchor constraintEqualToAnchor:_timePill.trailingAnchor constant:-8.0],
        [_timeLabel.topAnchor constraintEqualToAnchor:_timePill.topAnchor constant:3.0],
        [_timeLabel.bottomAnchor constraintEqualToAnchor:_timePill.bottomAnchor constant:-3.0],

        // Telemetry Strip
        [_telemetryStrip.topAnchor constraintEqualToAnchor:_bannerCanvas.bottomAnchor constant:10.0],
        [_telemetryStrip.leadingAnchor constraintEqualToAnchor:_cardContainer.leadingAnchor constant:14.0],
        [_telemetryStrip.trailingAnchor constraintEqualToAnchor:_cardContainer.trailingAnchor constant:-14.0],
        [_telemetryStrip.heightAnchor constraintEqualToConstant:26.0],

        [telemetryStack.leadingAnchor constraintEqualToAnchor:_telemetryStrip.leadingAnchor],
        [telemetryStack.centerYAnchor constraintEqualToAnchor:_telemetryStrip.centerYAnchor],
        [telemetryStack.trailingAnchor constraintLessThanOrEqualToAnchor:_telemetryStrip.trailingAnchor],

        // Divider
        [divider.topAnchor constraintEqualToAnchor:_telemetryStrip.bottomAnchor constant:10.0],
        [divider.leadingAnchor constraintEqualToAnchor:_cardContainer.leadingAnchor constant:14.0],
        [divider.trailingAnchor constraintEqualToAnchor:_cardContainer.trailingAnchor constant:-14.0],
        [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],

        // Action Bar
        [_actionBar.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:8.0],
        [_actionBar.leadingAnchor constraintEqualToAnchor:_cardContainer.leadingAnchor constant:12.0],
        [_actionBar.trailingAnchor constraintEqualToAnchor:_cardContainer.trailingAnchor constant:-12.0],
        [_actionBar.bottomAnchor constraintEqualToAnchor:_cardContainer.bottomAnchor constant:-10.0],
        [_actionBar.heightAnchor constraintEqualToConstant:36.0],

        [_statusToggleButton.leadingAnchor constraintEqualToAnchor:_actionBar.leadingAnchor],
        [_statusToggleButton.centerYAnchor constraintEqualToAnchor:_actionBar.centerYAnchor],

        [rightActionsStack.trailingAnchor constraintEqualToAnchor:_actionBar.trailingAnchor],
        [rightActionsStack.centerYAnchor constraintEqualToAnchor:_actionBar.centerYAnchor],

        [_moreButton.widthAnchor constraintEqualToConstant:32.0],
        [_moreButton.heightAnchor constraintEqualToConstant:32.0],
    ]];
}

- (UILabel *)createCapsuleLabelWithBg:(UIColor *)bg textColor:(UIColor *)textColor {
    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption2] scaledFontForFont:[Styling fontMedium:11]];
    lbl.textColor = textColor;
    lbl.backgroundColor = bg;
    lbl.layer.cornerRadius = 8.0;
    if (@available(iOS 13.0, *)) {
        lbl.layer.cornerCurve = kCACornerCurveContinuous;
    }
    lbl.clipsToBounds = YES;
    lbl.textAlignment = NSTextAlignmentCenter;
    [lbl.heightAnchor constraintEqualToConstant:22.0].active = YES;
    return lbl;
}

- (UIButton *)createActionButtonWithIcon:(NSString *)iconName title:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.35];
    btn.tintColor = [UIColor ppTextPrimary];
    btn.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[Styling fontMedium:12]];
    btn.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) {
        btn.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [btn setImage:[UIImage systemImageNamed:iconName] forState:UIControlStateNormal];
    [btn setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];
    btn.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.canvasGradientLayer.frame = self.bannerCanvas.bounds;
}

#pragma mark - Configuration

- (void)configureWithBanner:(PPBannerViewModel *)banner
                      group:(MainBannerModel *)group
                  indexPath:(NSIndexPath *)indexPath {
    _bannerModel = banner;
    _groupModel = group;
    _indexPath = indexPath;

    // Title & Description
    NSString *title = [banner localizedTitleText];
    self.titleLabel.text = title.length > 0 ? title : kLang(@"No Title");

    NSString *desc = [banner localizedDescText];
    self.descLabel.text = desc.length > 0 ? desc : @"";
    self.descLabel.hidden = desc.length == 0;

    // Text Style (White vs Dark)
    if (banner.pannerTextStyle == PPBannerTextStyleBlack) {
        self.titleLabel.textColor = [UIColor ppTextPrimary];
        self.descLabel.textColor = [UIColor ppTextSecondary];
        self.canvasGradientLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.85].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.45].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.75].CGColor
        ];
    } else {
        self.titleLabel.textColor = UIColor.whiteColor;
        self.descLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        self.canvasGradientLayer.colors = @[
            (id)[UIColor colorWithWhite:0.0 alpha:0.75].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.40].CGColor,
            (id)[UIColor colorWithWhite:0.0 alpha:0.70].CGColor
        ];
    }

    // Time / Validity / Post Date
    if (banner.validityDuration && banner.countdownTimeRemaining.length > 0) {
        self.timeLabel.text = [NSString stringWithFormat:@"⏳ %@", banner.countdownTimeRemaining];
        self.timeIconView.image = [UIImage systemImageNamed:@"hourglass"];
    } else if (banner.postDateText.length > 0) {
        self.timeLabel.text = banner.postDateText;
        self.timeIconView.image = [UIImage systemImageNamed:@"calendar"];
    } else {
        self.timeLabel.text = @"-";
    }

    // Background Image
    if (banner.backgroundImageURL) {
        [[PPImageManager sharedManager] setImageFromUrl:banner.backgroundImageURL.absoluteString
                                            toImageView:self.backgroundImageView
                                               fadeType:PPImageFadeTypeCrossDissolve
                                               duration:0.3
                                             completion:nil];
    } else {
        self.backgroundImageView.image = nil;
    }

    // Sample Image
    if (banner.sampleImageURL) {
        self.sampleImageView.hidden = NO;
        [[PPImageManager sharedManager] setImageFromUrl:banner.sampleImageURL.absoluteString
                                            toImageView:self.sampleImageView
                                               fadeType:PPImageFadeTypeCrossDissolve
                                               duration:0.3
                                             completion:nil];
    } else {
        self.sampleImageView.image = nil;
        self.sampleImageView.hidden = YES;
    }

    // Badge Image
    if (banner.badgeImageURL) {
        self.badgeImageView.hidden = NO;
        [[PPImageManager sharedManager] setImageFromUrl:banner.badgeImageURL.absoluteString
                                            toImageView:self.badgeImageView
                                               fadeType:PPImageFadeTypeCrossDissolve
                                               duration:0.3
                                             completion:nil];
    } else {
        self.badgeImageView.image = nil;
        self.badgeImageView.hidden = YES;
    }

    // Placement Capsule
    NSString *holderName = [self holderNameString:group.bannerViewHolder];
    NSString *posName = [self positionNameString:group.bannerViewPosition];
    self.placementBadgeLabel.text = [NSString stringWithFormat:@"  %@ • %@  ", holderName, posName];

    // Tap Action Capsule
    NSString *actionText = [self tapActionString:banner.onTapAction value:banner.onTapValue];
    self.tapActionBadgeLabel.text = [NSString stringWithFormat:@"  %@  ", actionText];

    // Taps Count
    self.tapsCountBadgeLabel.text = [NSString stringWithFormat:@"  %@  ", [NSString stringWithFormat:kLang(@"Banners_Taps_Count_Format"), (unsigned long)banner.tapCount]];

    // Active Toggle Button
    BOOL isGroupVisible = group.bannerViewVisible;
    if (isGroupVisible) {
        [self.statusToggleButton setTitle:[NSString stringWithFormat:@" ● %@ ", kLang(@"Banners_Status_Active")] forState:UIControlStateNormal];
        self.statusToggleButton.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.15];
        self.statusToggleButton.tintColor = [UIColor ppSuccess];
    } else {
        [self.statusToggleButton setTitle:[NSString stringWithFormat:@" ○ %@ ", kLang(@"Banners_Status_Hidden")] forState:UIControlStateNormal];
        self.statusToggleButton.backgroundColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.12];
        self.statusToggleButton.tintColor = [UIColor ppTextSecondary];
    }
}

#pragma mark - Helpers

- (NSString *)holderNameString:(PPBannerHolder)holder {
    switch (holder) {
        case PPBannerHolderMainView:        return kLang(@"Main");
        case PPBannerHolderAccessoriesView: return kLang(@"Accessories");
        case PPBannerHolderAdsView:         return kLang(@"Ads");
        case PPBannerHolderFoodView:        return kLang(@"Food");
        case PPBannerHolderVetsView:        return kLang(@"Vets");
    }
    return kLang(@"Main");
}

- (NSString *)positionNameString:(PPBannerPosition)pos {
    switch (pos) {
        case PPBannerPositionTop:    return kLang(@"Top");
        case PPBannerPositionCenter: return kLang(@"Center");
        case PPBannerPositionBottom: return kLang(@"Bottom");
    }
    return kLang(@"Top");
}

- (NSString *)tapActionString:(PPBannerOnTapAction)action value:(NSString *)val {
    NSString *valPreview = val.length > 0 ? [NSString stringWithFormat:@": %@", val] : @"";
    switch (action) {
        case PPBannerOnTapViewAccessory:     return [NSString stringWithFormat:@"🛍️ %@%@", kLang(@"Banners_TapAction_Accessory"), valPreview];
        case PPBannerOnTapViewAd:            return [NSString stringWithFormat:@"📢 %@%@", kLang(@"Banners_TapAction_Ad"), valPreview];
        case PPBannerOnTapOpenUrl:           return [NSString stringWithFormat:@"🌐 %@%@", kLang(@"Banners_TapAction_URL"), valPreview];
        case PPBannerOnTapCallPhoneNumber:   return [NSString stringWithFormat:@"📞 %@%@", kLang(@"Banners_TapAction_Call"), valPreview];
        case PPBannerOnTapWhatsApp:          return [NSString stringWithFormat:@"💬 %@%@", kLang(@"Banners_TapAction_WhatsApp"), valPreview];
    }
    return kLang(@"Banners_TapAction_Accessory");
}

#pragma mark - Actions

- (void)onPreviewTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    if ([self.delegate respondsToSelector:@selector(bannerCardCell:didTapPreviewForBanner:inGroup:)]) {
        [self.delegate bannerCardCell:self didTapPreviewForBanner:self.bannerModel inGroup:self.groupModel];
    }
}

- (void)onEditTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    if ([self.delegate respondsToSelector:@selector(bannerCardCell:didTapEditForBanner:inGroup:)]) {
        [self.delegate bannerCardCell:self didTapEditForBanner:self.bannerModel inGroup:self.groupModel];
    }
}

- (void)onStatusToggleTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    BOOL newStatus = !self.groupModel.bannerViewVisible;
    if ([self.delegate respondsToSelector:@selector(bannerCardCell:didToggleActive:forBanner:inGroup:)]) {
        [self.delegate bannerCardCell:self didToggleActive:newStatus forBanner:self.bannerModel inGroup:self.groupModel];
    }
}

- (void)onMoreTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    if ([self.delegate respondsToSelector:@selector(bannerCardCell:didTapMoreOptionsForBanner:inGroup:sourceView:)]) {
        [self.delegate bannerCardCell:self didTapMoreOptionsForBanner:self.bannerModel inGroup:self.groupModel sourceView:sender];
    }
}

@end
