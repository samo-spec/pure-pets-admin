#import "PPProviderUI.h"
#import "Language.h"
#import "Styling.h"

UIColor *PPProviderCanvasColor(void) {
    return AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
}

UIColor *PPProviderSurfaceColor(void) {
    return AppForgroundColr ?: UIColor.secondarySystemGroupedBackgroundColor;
}

UIColor *PPProviderRaisedSurfaceColor(void) {
    return UIColor.tertiarySystemGroupedBackgroundColor;
}

UIColor *PPProviderBrandColor(void) {
    return AppPrimaryClr ?: UIColor.systemPinkColor;
}

UIColor *PPProviderPrimaryTextColor(void) {
    return PrimaryTextClr ?: UIColor.labelColor;
}

UIColor *PPProviderSecondaryTextColor(void) {
    return SeconderyTextClr ?: UIColor.secondaryLabelColor;
}

UIColor *PPProviderSeparatorColor(void) {
    return [PPProviderBrandColor() colorWithAlphaComponent:0.10];
}

static NSString *PPProviderSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

NSString *PPProviderLocalizedType(NSString *providerType) {
    NSString *token = PPProviderSafeString(providerType).lowercaseString;
    NSDictionary *aliases = @{
        @"service_provider": @"service",
        @"veterinarians": @"vet"
    };
    token = aliases[token] ?: token;
    if (token.length == 0) return kLang(@"Providers_Type_Unknown");
    NSString *key = [@"Providers_Type_" stringByAppendingString:token];
    NSString *localized = kLang(key);
    return localized.length > 0 && ![localized isEqualToString:key] ? localized : providerType;
}

NSString *PPProviderLocalizedStatus(NSString *status) {
    NSString *token = PPProviderSafeString(status).lowercaseString;
    NSDictionary *keys = @{
        @"pending": @"Providers_Status_Pending",
        @"under_review": @"Providers_Status_UnderReview",
        @"approved": @"Providers_Status_Approved",
        @"rejected": @"Providers_Status_Rejected",
        @"archived": @"Providers_Status_Archived",
        @"active": @"Providers_Status_Active",
        @"inactive": @"Providers_Status_Inactive",
        @"settled": @"Providers_Status_Settled",
        @"voided": @"Providers_Status_Voided"
    };
    NSString *key = keys[token] ?: @"Providers_Status_Pending";
    return kLang(key);
}

NSString *PPProviderLocalizedBillingInterval(NSString *interval) {
    NSString *token = PPProviderSafeString(interval).lowercaseString;
    NSDictionary *keys = @{
        @"monthly": @"Providers_Billing_Monthly",
        @"yearly": @"Providers_Billing_Yearly",
        @"one_time": @"Providers_Billing_OneTime"
    };
    NSString *key = keys[token];
    return key ? kLang(key) : kLang(@"Providers_NotAvailable");
}

UIColor *PPProviderStatusColor(NSString *status) {
    NSString *token = PPProviderSafeString(status).lowercaseString;
    if ([token isEqualToString:@"approved"] || [token isEqualToString:@"active"] || [token isEqualToString:@"settled"]) {
        return UIColor.systemGreenColor;
    }
    if ([token isEqualToString:@"rejected"] || [token isEqualToString:@"voided"]) {
        return UIColor.systemRedColor;
    }
    if ([token isEqualToString:@"under_review"] || [token isEqualToString:@"pending"]) {
        return UIColor.systemOrangeColor;
    }
    return UIColor.systemGrayColor;
}

NSString *PPProviderLocalizedText(NSDictionary *value, NSString *fallback) {
    NSDictionary *safe = [value isKindOfClass:NSDictionary.class] ? value : @{};
    NSString *preferredKey = [[Language currentLanguageCode] isEqualToString:@"ar"] ? @"ar" : @"en";
    NSString *preferred = PPProviderSafeString(safe[preferredKey]);
    NSString *english = PPProviderSafeString(safe[@"en"]);
    NSString *arabic = PPProviderSafeString(safe[@"ar"]);
    if (preferred.length) return preferred;
    if (english.length) return english;
    if (arabic.length) return arabic;
    return fallback ?: @"";
}

NSString *PPProviderDateText(NSDate *date) {
    if (!date) return kLang(@"Providers_NotAvailable");
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

NSString *PPProviderMoneyText(double amount, NSString *currency) {
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 2;
    formatter.maximumFractionDigits = 2;
    NSString *number = [formatter stringFromNumber:@(amount)] ?: [NSString stringWithFormat:@"%.2f", amount];
    NSString *code = PPProviderSafeString(currency);
    if (code.length == 0) code = @"QAR";
    return [NSString stringWithFormat:@"%@ %@", number, code];
}

@interface PPProviderContextHeaderView ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *symbolShellView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong, readwrite) UILabel *metricLabel;
@end

@implementation PPProviderContextHeaderView

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceMD, PPScreenMargin, PPSpaceSM, PPScreenMargin);
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    _surfaceView = [UIView new];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(_surfaceView, PPCornerHero);
    _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _surfaceView.layer.borderColor = PPProviderSeparatorColor().CGColor;
    PPApplyCardShadow(_surfaceView);
    [self addSubview:_surfaceView];

    UIView *ambient = [UIView new];
    ambient.translatesAutoresizingMaskIntoConstraints = NO;
    ambient.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.055];
    PPApplyContinuousCorners(ambient, PPCornerHero);
    ambient.userInteractionEnabled = NO;
    [_surfaceView addSubview:ambient];

    UIView *rail = [UIView new];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    rail.backgroundColor = PPProviderBrandColor();
    PPApplyContinuousCorners(rail, 2.0);
    [_surfaceView addSubview:rail];

    _symbolShellView = [UIView new];
    _symbolShellView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolShellView.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.11];
    PPApplyContinuousCorners(_symbolShellView, PPCornerMedium);
    [_surfaceView addSubview:_symbolShellView];

    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightSemibold];
    _symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
    _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolView.tintColor = PPProviderBrandColor();
    _symbolView.contentMode = UIViewContentModeScaleAspectFit;
    [_symbolShellView addSubview:_symbolView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = title;
    _titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:25.0]];
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.numberOfLines = 0;
    _titleLabel.textColor = PPProviderPrimaryTextColor();
    _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [_surfaceView addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.text = subtitle;
    _subtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:15.0]];
    _subtitleLabel.adjustsFontForContentSizeCategory = YES;
    _subtitleLabel.numberOfLines = 0;
    _subtitleLabel.textColor = PPProviderSecondaryTextColor();
    _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [_surfaceView addSubview:_subtitleLabel];

    _metricLabel = [UILabel new];
    _metricLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _metricLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:13.0]];
    _metricLabel.adjustsFontForContentSizeCategory = YES;
    _metricLabel.numberOfLines = 0;
    _metricLabel.textColor = PPProviderBrandColor();
    _metricLabel.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.09];
    _metricLabel.textAlignment = Language.alignmentForCurrentLanguage;
    _metricLabel.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceSM, PPSpaceMD, PPSpaceSM, PPSpaceMD);
    PPApplyContinuousCorners(_metricLabel, PPCornerSmall);
    _metricLabel.layer.masksToBounds = YES;
    [_surfaceView addSubview:_metricLabel];

    UILayoutGuide *margins = _surfaceView.layoutMarginsGuide;
    _surfaceView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceLG, PPSpaceLG, PPSpaceLG, PPSpaceLG);
    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.layoutMarginsGuide.topAnchor],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.trailingAnchor],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.layoutMarginsGuide.bottomAnchor],
        [ambient.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor],
        [ambient.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor],
        [ambient.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor],
        [ambient.heightAnchor constraintEqualToAnchor:_surfaceView.heightAnchor multiplier:0.58],
        [rail.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:PPSpaceXL],
        [rail.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceLG],
        [rail.widthAnchor constraintEqualToConstant:PPSpaceXS],
        [rail.heightAnchor constraintEqualToConstant:PPSpaceXXL],
        [_symbolShellView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_symbolShellView.topAnchor constraintEqualToAnchor:margins.topAnchor constant:PPSpaceXL],
        [_symbolShellView.widthAnchor constraintEqualToConstant:56.0],
        [_symbolShellView.heightAnchor constraintEqualToConstant:56.0],
        [_symbolView.centerXAnchor constraintEqualToAnchor:_symbolShellView.centerXAnchor],
        [_symbolView.centerYAnchor constraintEqualToAnchor:_symbolShellView.centerYAnchor],
        [_symbolView.widthAnchor constraintEqualToConstant:28.0],
        [_symbolView.heightAnchor constraintEqualToConstant:28.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_symbolShellView.trailingAnchor constant:PPSpaceBase],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:margins.topAnchor constant:PPSpaceLG],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],
        [_metricLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_metricLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_metricLabel.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:PPSpaceBase],
        [_metricLabel.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
        [_metricLabel.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
    ]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitHeader;
    [self pp_updateAccessibilityLabel];
    return self;
}

- (void)setMetricText:(NSString *)text {
    self.metricLabel.text = text;
    [self pp_updateAccessibilityLabel];
}

- (void)pp_updateAccessibilityLabel {
    self.accessibilityLabel = [@[self.titleLabel.text ?: @"", self.subtitleLabel.text ?: @"", self.metricLabel.text ?: @""] componentsJoinedByString:@", "];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.surfaceView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.surfaceView.bounds cornerRadius:PPCornerHero].CGPath;
}

@end

@interface PPProviderStateView ()
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *symbolShellView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *retryButton;
@end

@implementation PPProviderStateView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    _contentView = [UIView new];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentView.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(_contentView, PPCornerCard);
    [self addSubview:_contentView];

    _symbolShellView = [UIView new];
    _symbolShellView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolShellView.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(_symbolShellView, 30.0);
    [_contentView addSubview:_symbolShellView];

    _symbolView = [UIImageView new];
    _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolView.tintColor = PPProviderBrandColor();
    _symbolView.contentMode = UIViewContentModeScaleAspectFit;
    [_symbolShellView addSubview:_symbolView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.color = PPProviderBrandColor();
    [_symbolShellView addSubview:_spinner];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:19.0]];
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.numberOfLines = 0;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.textColor = PPProviderPrimaryTextColor();
    [_contentView addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:15.0]];
    _subtitleLabel.adjustsFontForContentSizeCategory = YES;
    _subtitleLabel.numberOfLines = 0;
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    _subtitleLabel.textColor = PPProviderSecondaryTextColor();
    [_contentView addSubview:_subtitleLabel];

    _retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_retryButton setTitle:kLang(@"Providers_TryAgain") forState:UIControlStateNormal];
    _retryButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:15.0]];
    _retryButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    _retryButton.backgroundColor = PPProviderBrandColor();
    [_retryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    PPApplyContinuousCorners(_retryButton, PPCornerSmall);
    [_retryButton addTarget:self action:@selector(pp_retryTapped) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_retryButton];

    [NSLayoutConstraint activateConstraints:@[
        [_contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_contentView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPScreenMargin],
        [_contentView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPScreenMargin],
        [_symbolShellView.topAnchor constraintEqualToAnchor:_contentView.topAnchor constant:PPSpaceXL],
        [_symbolShellView.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor],
        [_symbolShellView.widthAnchor constraintEqualToConstant:60.0],
        [_symbolShellView.heightAnchor constraintEqualToConstant:60.0],
        [_symbolView.centerXAnchor constraintEqualToAnchor:_symbolShellView.centerXAnchor],
        [_symbolView.centerYAnchor constraintEqualToAnchor:_symbolShellView.centerYAnchor],
        [_symbolView.widthAnchor constraintEqualToConstant:26.0],
        [_symbolView.heightAnchor constraintEqualToConstant:26.0],
        [_spinner.centerXAnchor constraintEqualToAnchor:_symbolShellView.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_symbolShellView.centerYAnchor],
        [_titleLabel.topAnchor constraintEqualToAnchor:_symbolShellView.bottomAnchor constant:PPSpaceBase],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:PPSpaceXL],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-PPSpaceXL],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceSM],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_retryButton.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:PPSpaceBase],
        [_retryButton.centerXAnchor constraintEqualToAnchor:_contentView.centerXAnchor],
        [_retryButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
        [_retryButton.widthAnchor constraintGreaterThanOrEqualToConstant:132.0],
        [_retryButton.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor constant:-PPSpaceXL],
    ]];
    return self;
}

- (void)showLoadingWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.symbolView.hidden = YES;
    self.retryButton.hidden = YES;
    [self.spinner startAnimating];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title, subtitle];
    self.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
}

- (void)showEmptyWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.symbolView.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightSemibold]];
    self.symbolView.hidden = NO;
    self.retryButton.hidden = YES;
    [self.spinner stopAnimating];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title, subtitle];
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
}

- (void)showErrorWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.symbolView.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightSemibold]];
    self.symbolView.tintColor = UIColor.systemRedColor;
    self.symbolView.hidden = NO;
    self.retryButton.hidden = NO;
    [self.spinner stopAnimating];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title, subtitle];
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
}

- (void)pp_retryTapped {
    if (self.retryHandler) self.retryHandler();
}

@end

@interface PPProviderRecordCell ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *symbolShellView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *titleValueLabel;
@property (nonatomic, strong) UILabel *subtitleValueLabel;
@property (nonatomic, strong) UILabel *detailValueLabel;
@property (nonatomic, strong) UILabel *statusValueLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation PPProviderRecordCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    _surfaceView = [UIView new];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.backgroundColor = PPProviderSurfaceColor();
    PPApplyContinuousCorners(_surfaceView, PPCornerCard);
    _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _surfaceView.layer.borderColor = PPProviderSeparatorColor().CGColor;
    [self.contentView addSubview:_surfaceView];

    _symbolShellView = [UIView new];
    _symbolShellView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolShellView.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.09];
    PPApplyContinuousCorners(_symbolShellView, PPCornerMedium);
    [_surfaceView addSubview:_symbolShellView];

    _symbolView = [UIImageView new];
    _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    _symbolView.tintColor = PPProviderBrandColor();
    _symbolView.contentMode = UIViewContentModeScaleAspectFit;
    [_symbolShellView addSubview:_symbolView];

    _titleValueLabel = [self pp_labelWithFont:[Styling fontBold:18.0] color:PPProviderPrimaryTextColor() lines:0];
    _subtitleValueLabel = [self pp_labelWithFont:[Styling fontMedium:14.0] color:PPProviderSecondaryTextColor() lines:0];
    _detailValueLabel = [self pp_labelWithFont:[Styling fontRegular:13.0] color:PPProviderSecondaryTextColor() lines:0];
    [_surfaceView addSubview:_titleValueLabel];
    [_surfaceView addSubview:_subtitleValueLabel];
    [_surfaceView addSubview:_detailValueLabel];

    _statusValueLabel = [self pp_labelWithFont:[Styling fontBold:12.0] color:PPProviderBrandColor() lines:1];
    _statusValueLabel.textAlignment = NSTextAlignmentCenter;
    _statusValueLabel.layer.masksToBounds = YES;
    [_statusValueLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [_statusValueLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    PPApplyContinuousCorners(_statusValueLabel, PPCornerSmall);
    [_surfaceView addSubview:_statusValueLabel];

    _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold]]];
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.tintColor = UIColor.tertiaryLabelColor;
    [_chevronView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_surfaceView addSubview:_chevronView];

    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],
        [_symbolShellView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:PPSpaceBase],
        [_symbolShellView.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceBase],
        [_symbolShellView.widthAnchor constraintEqualToConstant:52.0],
        [_symbolShellView.heightAnchor constraintEqualToConstant:52.0],
        [_symbolView.centerXAnchor constraintEqualToAnchor:_symbolShellView.centerXAnchor],
        [_symbolView.centerYAnchor constraintEqualToAnchor:_symbolShellView.centerYAnchor],
        [_symbolView.widthAnchor constraintEqualToConstant:25.0],
        [_symbolView.heightAnchor constraintEqualToConstant:25.0],
        [_statusValueLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceBase],
        [_statusValueLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-PPSpaceSM],
        [_statusValueLabel.heightAnchor constraintGreaterThanOrEqualToConstant:28.0],
        [_statusValueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:64.0],
        [_chevronView.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-PPSpaceBase],
        [_chevronView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
        [_chevronView.widthAnchor constraintEqualToConstant:14.0],
        [_titleValueLabel.leadingAnchor constraintEqualToAnchor:_symbolShellView.trailingAnchor constant:PPSpaceMD],
        [_titleValueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusValueLabel.leadingAnchor constant:-PPSpaceSM],
        [_titleValueLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceBase],
        [_subtitleValueLabel.leadingAnchor constraintEqualToAnchor:_titleValueLabel.leadingAnchor],
        [_subtitleValueLabel.trailingAnchor constraintEqualToAnchor:_statusValueLabel.trailingAnchor],
        [_subtitleValueLabel.topAnchor constraintEqualToAnchor:_titleValueLabel.bottomAnchor constant:PPSpaceXS],
        [_detailValueLabel.leadingAnchor constraintEqualToAnchor:_titleValueLabel.leadingAnchor],
        [_detailValueLabel.trailingAnchor constraintEqualToAnchor:_statusValueLabel.trailingAnchor],
        [_detailValueLabel.topAnchor constraintEqualToAnchor:_subtitleValueLabel.bottomAnchor constant:PPSpaceXS],
        [_detailValueLabel.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceBase],
    ]];
    return self;
}

- (UILabel *)pp_labelWithFont:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:font];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.textAlignment = Language.alignmentForCurrentLanguage;
    label.numberOfLines = lines;
    return label;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle detail:(NSString *)detail status:(NSString *)status symbol:(NSString *)symbol actionable:(BOOL)actionable {
    self.titleValueLabel.text = title;
    self.subtitleValueLabel.text = subtitle;
    self.detailValueLabel.text = detail;
    NSString *statusText = PPProviderLocalizedStatus(status);
    UIColor *statusColor = PPProviderStatusColor(status);
    self.statusValueLabel.text = statusText;
    self.statusValueLabel.textColor = statusColor;
    self.statusValueLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.11];
    self.symbolShellView.backgroundColor = [statusColor colorWithAlphaComponent:0.09];
    self.symbolView.tintColor = statusColor;
    self.symbolView.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightSemibold]];
    self.chevronView.hidden = !actionable;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = actionable ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    self.accessibilityLabel = [@[title ?: @"", subtitle ?: @"", detail ?: @"", statusText ?: @""] componentsJoinedByString:@", "];
    self.accessibilityHint = actionable ? kLang(@"Providers_OpenActions_Hint") : nil;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.surfaceView.alpha = highlighted ? 0.88 : 1.0;
        return;
    }
    [UIView animateWithDuration:PPAnimDurationFast animations:^{
        self.surfaceView.transform = highlighted ? CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown) : CGAffineTransformIdentity;
        self.surfaceView.alpha = highlighted ? 0.94 : 1.0;
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.surfaceView.transform = CGAffineTransformIdentity;
    self.surfaceView.alpha = 1.0;
}

@end