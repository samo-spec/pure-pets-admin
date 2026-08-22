#import "PPProviderApplicationsViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPStaffAuth.h"
#import "Language.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "Styling.h"
#import "PPAlertHelper.h"
@import FirebaseFirestore;
@import FirebaseFunctions;

static NSString * const PPProviderApplicationCellID = @"PPProviderApplicationCell";

static NSString *PPProviderApplicationSafeString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *PPProviderApplicationTrimmedString(id value) {
    return [PPProviderApplicationSafeString(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSDictionary *PPProviderApplicationSafeDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSArray<NSString *> *PPProviderApplicationSafeStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        NSString *text = PPProviderApplicationTrimmedString(item);
        if (text.length) [strings addObject:text];
    }
    return strings.copy;
}

static NSNumber *PPProviderApplicationSafeNumber(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static NSString *PPProviderApplicationNumberText(NSNumber *value) {
    if (!value) return @"";
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = 2;
    return [formatter stringFromNumber:value] ?: value.stringValue;
}

static NSString *PPProviderApplicationLTRIsolate(NSString *value) {
    NSString *safe = PPProviderApplicationSafeString(value);
    return safe.length ? [NSString stringWithFormat:@"\u2066%@\u2069", safe] : @"";
}

static NSString *PPProviderApplicationIndexText(NSUInteger index) {
    return [NSNumberFormatter localizedStringFromNumber:@(index) numberStyle:NSNumberFormatterDecimalStyle];
}

static BOOL PPProviderApplicationStringsMatch(NSString *left, NSString *right) {
    NSString *safeLeft = PPProviderApplicationTrimmedString(left);
    NSString *safeRight = PPProviderApplicationTrimmedString(right);
    return safeLeft.length && safeRight.length && [safeLeft caseInsensitiveCompare:safeRight] == NSOrderedSame;
}

static NSString *PPProviderApplicationLocalizedValue(id value) {
    if ([value isKindOfClass:NSString.class]) return PPProviderApplicationTrimmedString(value);
    if ([value isKindOfClass:NSDictionary.class]) return PPProviderLocalizedText(value, @"");
    return @"";
}

static NSURL *PPProviderApplicationHTTPURL(id value) {
    NSString *text = PPProviderApplicationTrimmedString(value);
    if (text.length == 0) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithString:text];
    NSString *scheme = components.scheme.lowercaseString;
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) || components.host.length == 0) return nil;
    return components.URL;
}

static NSString *PPProviderApplicationCostTypeText(NSString *value) {
    NSString *token = PPProviderApplicationTrimmedString(value).lowercaseString;
    if ([token isEqualToString:@"price"]) return kLang(@"Providers_ApplicationDetail_CostType_Price");
    if ([token isEqualToString:@"percentage"]) return kLang(@"Providers_ApplicationDetail_CostType_Percentage");
    return value ?: @"";
}

static NSString *PPProviderApplicationPercentageBasisText(NSString *value) {
    NSString *token = PPProviderApplicationTrimmedString(value).lowercaseString;
    NSDictionary<NSString *, NSString *> *keys = @{
        @"item": @"Providers_ApplicationDetail_PercentageBasis_Item",
        @"product": @"Providers_ApplicationDetail_PercentageBasis_Product",
        @"service": @"Providers_ApplicationDetail_PercentageBasis_Service",
        @"medicine": @"Providers_ApplicationDetail_PercentageBasis_Medicine",
        @"subscription": @"Providers_ApplicationDetail_PercentageBasis_Subscription",
        @"custom": @"Providers_ApplicationDetail_PercentageBasis_Custom",
    };
    NSString *key = keys[token];
    return key ? kLang(key) : (value ?: @"");
}

static NSString *PPProviderApplicationDisplayName(PPProviderApplication *application) {
    NSDictionary *form = [application.form isKindOfClass:NSDictionary.class] ? application.form : @{};
    for (NSString *key in @[@"fullName", @"businessName", @"companyName", @"legalName"]) {
        NSString *name = PPProviderApplicationTrimmedString(form[key]);
        if (name.length) return name;
    }
    NSString *accountName = PPProviderApplicationTrimmedString(application.userSummary[@"displayName"]);
    if (accountName.length) return accountName;
    if (application.userId.length) return application.userId;
    return kLang(@"Providers_Applications_UnknownApplicant");
}

static BOOL PPProviderApplicationIsPermissionError(NSError *error) {
    if (!error) return NO;
    if ([error.domain isEqualToString:FIRFirestoreErrorDomain] && error.code == FIRFirestoreErrorCodePermissionDenied) return YES;
    if ([error.domain isEqualToString:@"com.firebase.functions"] && error.code == FIRFunctionsErrorCodePermissionDenied) return YES;
    id underlyingValue = error.userInfo[NSUnderlyingErrorKey];
    if (![underlyingValue isKindOfClass:NSError.class]) return NO;
    NSError *underlying = (NSError *)underlyingValue;
    return underlying != error && PPProviderApplicationIsPermissionError(underlying);
}

static BOOL PPProviderApplicationDecisionIsAllowed(NSString *decision, NSString *currentStatus) {
    if (![decision isEqualToString:@"under_review"] &&
        ![decision isEqualToString:@"approved"] &&
        ![decision isEqualToString:@"rejected"]) {
        return NO;
    }
    if ([decision isEqualToString:@"under_review"]) {
        return [currentStatus isEqualToString:@"pending"];
    }
    return [currentStatus isEqualToString:@"pending"] || [currentStatus isEqualToString:@"under_review"];
}

#pragma mark - Local application workspace pieces

@interface PPProviderApplicationQueueCell : UITableViewCell
- (void)configureWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                     detail:(NSString *)detail
                     status:(NSString *)status
                     symbol:(NSString *)symbol;
@end

@interface PPProviderApplicationQueueHeaderView : UIView
- (void)refreshAppearance;
- (void)updateWithVisibleCount:(NSUInteger)visibleCount
                 awaitingCount:(NSUInteger)awaitingCount
                  approvedCount:(NSUInteger)approvedCount
                  rejectedCount:(NSUInteger)rejectedCount
                  retainedText:(nullable NSString *)retainedText;
@property (nonatomic, copy, nullable) void (^retryHandler)(void);
@end

@interface PPProviderApplicationStateView : UIView
@property (nonatomic, copy, nullable) void (^retryHandler)(void);
@property (nonatomic, copy, nullable) void (^clearSearchHandler)(void);
- (void)refreshAppearance;
- (void)showLoadingWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)showEmptyWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)showFilteredEmptyWithTitle:(NSString *)title
                          subtitle:(NSString *)subtitle
                         clearTitle:(NSString *)clearTitle;
- (void)showErrorWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)showPermissionDeniedWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
@end

@interface PPProviderApplicationQueueCell ()
@property (nonatomic, strong) UIView *iconShellView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIView *statusSurface;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIView *separatorView;
@end

@implementation PPProviderApplicationQueueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.backgroundColor = PPProviderCanvasColor();
    self.contentView.backgroundColor = PPProviderSurfaceColor();
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.iconShellView = [UIView new];
    self.iconShellView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconShellView.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.09];
    PPApplyContinuousCorners(self.iconShellView, PPCornerMedium);
    [self.contentView addSubview:self.iconShellView];

    self.iconView = [UIImageView new];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.isAccessibilityElement = NO;
    [self.iconShellView addSubview:self.iconView];

    self.titleLabel = [self pp_labelWithFont:[Styling fontBold:PPFontTitle3]
                                       color:PPProviderPrimaryTextColor()
                                       lines:0];
    self.subtitleLabel = [self pp_labelWithFont:[Styling fontMedium:PPFontSubheadline]
                                          color:PPProviderSecondaryTextColor()
                                          lines:0];
    self.detailLabel = [self pp_labelWithFont:[Styling fontRegular:PPFontFootnote]
                                        color:PPProviderSecondaryTextColor()
                                        lines:0];
    [self.contentView addSubview:self.titleLabel];
    [self.contentView addSubview:self.subtitleLabel];
    [self.contentView addSubview:self.detailLabel];

    self.statusSurface = [UIView new];
    self.statusSurface.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(self.statusSurface, PPCornerSmall);
    [self.contentView addSubview:self.statusSurface];

    self.statusLabel = [self pp_labelWithFont:[Styling fontBold:PPFontFootnote]
                                        color:PPProviderBrandColor()
                                        lines:0];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.statusSurface addSubview:self.statusLabel];

    self.chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"
                                                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold]]];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.tintColor = [UIColor ppTextTertiary];
    self.chevronView.isAccessibilityElement = NO;
    [self.contentView addSubview:self.chevronView];

    self.separatorView = [UIView new];
    self.separatorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.separatorView.backgroundColor = [UIColor ppSurfaceBorder];
    [self.contentView addSubview:self.separatorView];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconShellView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
        [self.iconShellView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceBase],
        [self.iconShellView.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.iconShellView.heightAnchor constraintEqualToConstant:PPTouchTargetMin],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.iconShellView.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.iconShellView.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:PPSpaceXL],
        [self.iconView.heightAnchor constraintEqualToConstant:PPSpaceXL],

        [self.chevronView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
        [self.chevronView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronView.widthAnchor constraintEqualToConstant:PPSpaceMD],
        [self.chevronView.heightAnchor constraintEqualToConstant:PPSpaceMD],

        [self.statusSurface.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceBase],
        [self.statusSurface.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-PPSpaceSM],
        [self.statusSurface.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor constant:PPSpaceSM],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusSurface.topAnchor constant:PPSpaceXS],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusSurface.leadingAnchor constant:PPSpaceSM],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusSurface.trailingAnchor constant:-PPSpaceSM],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.statusSurface.bottomAnchor constant:-PPSpaceXS],
        [self.statusSurface.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconShellView.trailingAnchor constant:PPSpaceMD],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusSurface.leadingAnchor constant:-PPSpaceSM],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceBase],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusSurface.leadingAnchor constant:-PPSpaceSM],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:PPSpaceXS],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusSurface.leadingAnchor constant:-PPSpaceSM],
        [self.detailLabel.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:PPSpaceXS],
        [self.detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceBase],

        [self.separatorView.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.separatorView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
        [self.separatorView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.separatorView.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    ]];
    return self;
}

- (UILabel *)pp_labelWithFont:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:font];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = Language.alignmentForCurrentLanguage;
    label.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    return label;
}

- (void)configureWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                     detail:(NSString *)detail
                     status:(NSString *)status
                     symbol:(NSString *)symbol {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.detailLabel.text = detail;

    NSString *statusText = PPProviderLocalizedStatus(status);
    UIColor *statusColor = PPProviderStatusColor(status);
    self.statusLabel.text = statusText;
    self.statusLabel.textColor = statusColor;
    self.statusSurface.backgroundColor = [statusColor colorWithAlphaComponent:0.11];
    self.iconShellView.backgroundColor = [statusColor colorWithAlphaComponent:0.09];
    self.iconView.tintColor = statusColor;
    self.iconView.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22.0 weight:UIImageSymbolWeightSemibold]];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = [@[title ?: @"", subtitle ?: @"", detail ?: @"", statusText ?: @""] componentsJoinedByString:@", "];
    self.accessibilityHint = kLang(@"Providers_OpenActions_Hint");
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.contentView.alpha = highlighted ? 0.88 : 1.0;
        return;
    }
    [UIView animateWithDuration:PPAnimDurationFast animations:^{
        self.contentView.alpha = highlighted ? 0.90 : 1.0;
    }];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
}

@end

@interface PPProviderApplicationQueueHeaderView ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *awaitingValueLabel;
@property (nonatomic, strong) UILabel *approvedValueLabel;
@property (nonatomic, strong) UILabel *rejectedValueLabel;
@property (nonatomic, strong) UIStackView *healthStack;
@property (nonatomic, strong) UIStackView *awaitingMetricStack;
@property (nonatomic, strong) UIStackView *approvedMetricStack;
@property (nonatomic, strong) UIStackView *rejectedMetricStack;
@property (nonatomic, strong) UIStackView *retainedSignalView;
@property (nonatomic, strong) UILabel *retainedSignalLabel;
@property (nonatomic, strong) UIButton *retainedRetryButton;
@end

@implementation PPProviderApplicationQueueHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.surfaceView = [UIView new];
    self.surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    self.surfaceView.backgroundColor = PPProviderSurfaceColor();
    self.surfaceView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceLG, PPSpaceLG, PPSpaceLG, PPSpaceLG);
    self.surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.surfaceView.layer.borderColor = PPProviderSeparatorColor().CGColor;
    PPApplyContinuousCorners(self.surfaceView, PPCornerCard);
    [self addSubview:self.surfaceView];

    UIView *rail = [UIView new];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    rail.backgroundColor = PPProviderBrandColor();
    PPApplyContinuousCorners(rail, PPSpaceXXS);
    rail.isAccessibilityElement = NO;
    [self.surfaceView addSubview:rail];

    UIStackView *contentStack = [UIStackView new];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.alignment = UIStackViewAlignmentFill;
    contentStack.spacing = PPSpaceMD;
    contentStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.surfaceView addSubview:contentStack];

    self.titleLabel = [self pp_labelWithText:kLang(@"Providers_Applications_HeroTitle")
                                        font:[Styling fontBold:PPFontTitle1]
                                       color:PPProviderPrimaryTextColor()
                                       lines:0];
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    self.subtitleLabel = [self pp_labelWithText:kLang(@"Providers_Applications_HeroSubtitle")
                                           font:[Styling fontRegular:PPFontBody]
                                          color:PPProviderSecondaryTextColor()
                                          lines:0];
    self.summaryLabel = [self pp_labelWithText:@""
                                          font:[Styling fontBold:PPFontHeadline]
                                         color:PPProviderBrandColor()
                                         lines:0];
    [contentStack addArrangedSubview:self.titleLabel];
    [contentStack addArrangedSubview:self.subtitleLabel];
    [contentStack addArrangedSubview:self.summaryLabel];

    self.healthStack = [UIStackView new];
    self.healthStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.healthStack.axis = UILayoutConstraintAxisHorizontal;
    self.healthStack.alignment = UIStackViewAlignmentTop;
    self.healthStack.distribution = UIStackViewDistributionFillEqually;
    self.healthStack.spacing = PPSpaceSM;
    self.healthStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [contentStack addArrangedSubview:self.healthStack];

    self.awaitingValueLabel = [self pp_metricValueLabelWithColor:[UIColor ppWarning]];
    self.approvedValueLabel = [self pp_metricValueLabelWithColor:[UIColor ppSuccess]];
    self.rejectedValueLabel = [self pp_metricValueLabelWithColor:[UIColor ppError]];
    self.awaitingMetricStack = [self pp_metricStackWithValue:self.awaitingValueLabel titleKey:@"Providers_Pending"];
    self.approvedMetricStack = [self pp_metricStackWithValue:self.approvedValueLabel titleKey:@"Providers_Approved"];
    self.rejectedMetricStack = [self pp_metricStackWithValue:self.rejectedValueLabel titleKey:@"Providers_Rejected"];
    [self.healthStack addArrangedSubview:self.awaitingMetricStack];
    [self.healthStack addArrangedSubview:self.approvedMetricStack];
    [self.healthStack addArrangedSubview:self.rejectedMetricStack];

    self.retainedSignalView = [UIStackView new];
    self.retainedSignalView.translatesAutoresizingMaskIntoConstraints = NO;
    self.retainedSignalView.axis = UILayoutConstraintAxisHorizontal;
    self.retainedSignalView.alignment = UIStackViewAlignmentCenter;
    self.retainedSignalView.spacing = PPSpaceSM;
    self.retainedSignalView.distribution = UIStackViewDistributionFill;
    self.retainedSignalView.layoutMarginsRelativeArrangement = YES;
    self.retainedSignalView.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.10];
    self.retainedSignalView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceSM, PPSpaceSM, PPSpaceSM, PPSpaceSM);
    PPApplyContinuousCorners(self.retainedSignalView, PPCornerSmall);
    self.retainedSignalView.hidden = YES;
    [contentStack addArrangedSubview:self.retainedSignalView];

    UIImageView *signalIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"wifi.exclamationmark"]];
    signalIcon.translatesAutoresizingMaskIntoConstraints = NO;
    signalIcon.tintColor = [UIColor ppWarning];
    signalIcon.isAccessibilityElement = NO;
    [self.retainedSignalView addArrangedSubview:signalIcon];

    self.retainedSignalLabel = [self pp_labelWithText:@""
                                                 font:[Styling fontMedium:PPFontFootnote]
                                                color:PPProviderPrimaryTextColor()
                                                lines:0];
    [self.retainedSignalView addArrangedSubview:self.retainedSignalLabel];

    self.retainedRetryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.retainedRetryButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.retainedRetryButton.tintColor = PPProviderBrandColor();
    self.retainedRetryButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontFootnote]];
    self.retainedRetryButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.retainedRetryButton setTitle:kLang(@"Providers_TryAgain") forState:UIControlStateNormal];
    [self.retainedRetryButton addTarget:self action:@selector(pp_retryTapped) forControlEvents:UIControlEventTouchUpInside];
    self.retainedRetryButton.accessibilityLabel = kLang(@"Providers_TryAgain");
    self.retainedRetryButton.accessibilityHint = kLang(@"Providers_Applications_ErrorSubtitle");
    [self.retainedSignalView addArrangedSubview:self.retainedRetryButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.surfaceView.topAnchor constraintEqualToAnchor:self.topAnchor constant:PPSpaceMD],
        [self.surfaceView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPScreenMargin],
        [self.surfaceView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPScreenMargin],
        [self.surfaceView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PPSpaceSM],
        [rail.leadingAnchor constraintEqualToAnchor:self.surfaceView.leadingAnchor],
        [rail.topAnchor constraintEqualToAnchor:self.surfaceView.topAnchor constant:PPSpaceLG],
        [rail.bottomAnchor constraintEqualToAnchor:self.surfaceView.bottomAnchor constant:-PPSpaceLG],
        [rail.widthAnchor constraintEqualToConstant:PPSpaceXS],
        [contentStack.topAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.topAnchor],
        [contentStack.leadingAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.leadingAnchor],
        [contentStack.trailingAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.trailingAnchor],
        [contentStack.bottomAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.bottomAnchor],
        [signalIcon.widthAnchor constraintEqualToConstant:PPSpaceLG],
        [signalIcon.heightAnchor constraintEqualToConstant:PPSpaceLG],
        [self.retainedRetryButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
    ]];
    return self;
}

- (UILabel *)pp_labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:font];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = Language.alignmentForCurrentLanguage;
    label.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    return label;
}

- (UILabel *)pp_metricValueLabelWithColor:(UIColor *)color {
    UILabel *label = [self pp_labelWithText:@"0"
                                        font:[Styling fontBold:PPFontTitle3]
                                       color:color
                                       lines:1];
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

- (UIStackView *)pp_metricStackWithValue:(UILabel *)valueLabel titleKey:(NSString *)titleKey {
    UILabel *titleLabel = [self pp_labelWithText:kLang(titleKey)
                                             font:[Styling fontBold:PPFontFootnote]
                                            color:PPProviderSecondaryTextColor()
                                            lines:0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = PPSpaceXS;
    stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [stack addArrangedSubview:valueLabel];
    [stack addArrangedSubview:titleLabel];
    stack.isAccessibilityElement = YES;
    stack.accessibilityTraits = UIAccessibilityTraitStaticText;
    stack.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", titleLabel.text ?: @"", valueLabel.text ?: @""];
    return stack;
}

- (void)refreshAppearance {
    self.surfaceView.backgroundColor = PPProviderSurfaceColor();
    self.surfaceView.layer.borderColor = PPProviderSeparatorColor().CGColor;
    self.retainedSignalView.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.10];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL useVerticalHealth = self.bounds.size.width < 420.0 || UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    UILayoutConstraintAxis axis = useVerticalHealth ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    if (self.healthStack.axis != axis) self.healthStack.axis = axis;
}

- (void)updateWithVisibleCount:(NSUInteger)visibleCount
                 awaitingCount:(NSUInteger)awaitingCount
                  approvedCount:(NSUInteger)approvedCount
                  rejectedCount:(NSUInteger)rejectedCount
                  retainedText:(NSString *)retainedText {
    NSString *format = kLang(@"Providers_Applications_Summary_Format");
    self.summaryLabel.text = [NSString stringWithFormat:format,
                              (unsigned long)visibleCount,
                              (unsigned long)awaitingCount];
    self.awaitingValueLabel.text = PPProviderApplicationIndexText(awaitingCount);
    self.approvedValueLabel.text = PPProviderApplicationIndexText(approvedCount);
    self.rejectedValueLabel.text = PPProviderApplicationIndexText(rejectedCount);
    self.awaitingMetricStack.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", kLang(@"Providers_Pending"), self.awaitingValueLabel.text ?: @""];
    self.approvedMetricStack.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", kLang(@"Providers_Approved"), self.approvedValueLabel.text ?: @""];
    self.rejectedMetricStack.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", kLang(@"Providers_Rejected"), self.rejectedValueLabel.text ?: @""];
    self.retainedSignalLabel.text = retainedText ?: @"";
    self.retainedSignalView.hidden = retainedText.length == 0;
    self.retainedSignalView.isAccessibilityElement = NO;
    self.retainedSignalLabel.isAccessibilityElement = retainedText.length > 0;
    self.retainedSignalLabel.accessibilityLabel = kLang(@"Fulfillment_Connection_Retained");
    self.retainedSignalLabel.accessibilityValue = retainedText ?: @"";
}

- (void)pp_retryTapped {
    if (self.retryHandler) self.retryHandler();
}

@end

@interface PPProviderApplicationStateView ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIButton *clearSearchButton;
@end

@implementation PPProviderApplicationStateView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.surfaceView = [UIView new];
    self.surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    self.surfaceView.backgroundColor = PPProviderSurfaceColor();
    self.surfaceView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceXL, PPSpaceXL, PPSpaceXL, PPSpaceXL);
    self.surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.surfaceView.layer.borderColor = PPProviderSeparatorColor().CGColor;
    PPApplyContinuousCorners(self.surfaceView, PPCornerCard);
    [self addSubview:self.surfaceView];

    self.symbolView = [UIImageView new];
    self.symbolView.translatesAutoresizingMaskIntoConstraints = NO;
    self.symbolView.contentMode = UIViewContentModeScaleAspectFit;
    self.symbolView.tintColor = PPProviderBrandColor();
    self.symbolView.isAccessibilityElement = NO;
    [self.surfaceView addSubview:self.symbolView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = PPProviderBrandColor();
    self.spinner.hidesWhenStopped = YES;
    [self.surfaceView addSubview:self.spinner];

    self.titleLabel = [self pp_labelWithFont:[Styling fontBold:PPFontTitle2]
                                       color:PPProviderPrimaryTextColor()
                                       lines:0];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.surfaceView addSubview:self.titleLabel];

    self.subtitleLabel = [self pp_labelWithFont:[Styling fontRegular:PPFontBody]
                                          color:PPProviderSecondaryTextColor()
                                          lines:0];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.surfaceView addSubview:self.subtitleLabel];

    self.retryButton = [self pp_buttonWithTitle:kLang(@"Providers_TryAgain") filled:YES];
    [self.retryButton addTarget:self action:@selector(pp_retryTapped) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.accessibilityLabel = kLang(@"Providers_TryAgain");

    self.clearSearchButton = [self pp_buttonWithTitle:kLang(@"Fulfillment_ClearSearch") filled:NO];
    [self.clearSearchButton addTarget:self action:@selector(pp_clearSearchTapped) forControlEvents:UIControlEventTouchUpInside];
    self.clearSearchButton.accessibilityLabel = kLang(@"Fulfillment_ClearSearch");

    UIStackView *actionStack = [UIStackView new];
    actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    actionStack.axis = UILayoutConstraintAxisVertical;
    actionStack.alignment = UIStackViewAlignmentCenter;
    actionStack.spacing = PPSpaceSM;
    [actionStack addArrangedSubview:self.retryButton];
    [actionStack addArrangedSubview:self.clearSearchButton];
    [self.surfaceView addSubview:actionStack];

    NSLayoutConstraint *responsiveWidth = [self.surfaceView.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-(PPScreenMargin * 2.0)];
    responsiveWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.surfaceView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.surfaceView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.surfaceView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:PPScreenMargin],
        [self.surfaceView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-PPScreenMargin],
        [self.surfaceView.widthAnchor constraintLessThanOrEqualToConstant:620.0],
        responsiveWidth,
        [self.symbolView.topAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.topAnchor],
        [self.symbolView.centerXAnchor constraintEqualToAnchor:self.surfaceView.centerXAnchor],
        [self.symbolView.widthAnchor constraintEqualToConstant:PPSpaceXL],
        [self.symbolView.heightAnchor constraintEqualToConstant:PPSpaceXL],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.symbolView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.symbolView.centerYAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.symbolView.bottomAnchor constant:PPSpaceMD],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.trailingAnchor],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:PPSpaceSM],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [actionStack.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:PPSpaceLG],
        [actionStack.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [actionStack.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [actionStack.bottomAnchor constraintEqualToAnchor:self.surfaceView.layoutMarginsGuide.bottomAnchor],
        [self.retryButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
        [self.retryButton.widthAnchor constraintGreaterThanOrEqualToConstant:132.0],
        [self.clearSearchButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
    ]];
    return self;
}

- (UILabel *)pp_labelWithFont:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:font];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = Language.alignmentForCurrentLanguage;
    label.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    return label;
}

- (UIButton *)pp_buttonWithTitle:(NSString *)title filled:(BOOL)filled {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontSubheadline]];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 0;
    button.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceMD, PPSpaceSM, PPSpaceMD);
    button.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPApplyContinuousCorners(button, PPCornerSmall);
    if (filled) {
        button.backgroundColor = PPProviderBrandColor();
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        button.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.08];
        [button setTitleColor:PPProviderBrandColor() forState:UIControlStateNormal];
    }
    [button setTitle:title forState:UIControlStateNormal];
    return button;
}

- (void)refreshAppearance {
    self.surfaceView.backgroundColor = PPProviderSurfaceColor();
    self.surfaceView.layer.borderColor = PPProviderSeparatorColor().CGColor;
}

- (void)pp_prepareForStateWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol tintColor:(UIColor *)tintColor {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.symbolView.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightSemibold]];
    self.symbolView.tintColor = tintColor ?: PPProviderBrandColor();
    self.symbolView.hidden = NO;
    [self.spinner stopAnimating];
    self.retryButton.hidden = YES;
    self.clearSearchButton.hidden = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", title ?: @"", subtitle ?: @""];
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
}

- (void)showLoadingWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    [self pp_prepareForStateWithTitle:title subtitle:subtitle symbol:@"arrow.clockwise" tintColor:PPProviderBrandColor()];
    self.symbolView.hidden = YES;
    [self.spinner startAnimating];
    self.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
}

- (void)showEmptyWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    [self pp_prepareForStateWithTitle:title subtitle:subtitle symbol:@"person.crop.circle.badge.plus" tintColor:PPProviderBrandColor()];
}

- (void)showFilteredEmptyWithTitle:(NSString *)title
                          subtitle:(NSString *)subtitle
                         clearTitle:(NSString *)clearTitle {
    [self pp_prepareForStateWithTitle:title subtitle:subtitle symbol:@"line.3.horizontal.decrease.circle" tintColor:PPProviderBrandColor()];
    [self.clearSearchButton setTitle:clearTitle forState:UIControlStateNormal];
    self.clearSearchButton.hidden = NO;
}

- (void)showErrorWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    [self pp_prepareForStateWithTitle:title subtitle:subtitle symbol:@"exclamationmark.triangle.fill" tintColor:[UIColor ppError]];
    self.retryButton.hidden = NO;
}

- (void)showPermissionDeniedWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    [self pp_prepareForStateWithTitle:title subtitle:subtitle symbol:@"lock.fill" tintColor:[UIColor ppWarning]];
}

- (void)pp_retryTapped {
    if (self.retryHandler) self.retryHandler();
}

- (void)pp_clearSearchTapped {
    if (self.clearSearchHandler) self.clearSearchHandler();
}

@end

@interface PPProviderApplicationDetailViewController : UIViewController
@property (nonatomic, copy) void (^applicationDidMutate)(void);
- (instancetype)initWithApplication:(PPProviderApplication *)application canManage:(BOOL)canManage;
- (void)updateWithApplication:(PPProviderApplication *)application;
@end

@interface PPProviderApplicationDetailViewController ()
@property (nonatomic, strong) PPProviderApplication *application;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL isReviewing;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIButton *reviewButton;
@property (nonatomic, strong) UIActivityIndicatorView *reviewSpinner;
@property (nonatomic, strong) NSMutableArray<NSURL *> *linkURLs;
@property (nonatomic, strong) NSMutableArray<UIView *> *borderedSurfaces;
@property (nonatomic, weak) UIView *decisionSurface;
@end

@implementation PPProviderApplicationDetailViewController

#pragma mark - Lifecycle

- (instancetype)initWithApplication:(PPProviderApplication *)application canManage:(BOOL)canManage {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _application = application;
        _canManage = canManage;
        _linkURLs = [NSMutableArray array];
        _borderedSurfaces = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Providers_ApplicationDetail_Title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = PPProviderCanvasColor();
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self pp_buildView];
    [self pp_rebuildContent];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self pp_refreshBorderColors];
    }
}

- (void)updateWithApplication:(PPProviderApplication *)application {
    if (!application || ![application.applicationID isEqualToString:self.application.applicationID]) return;
    self.application = application;
    if (self.isViewLoaded) [self pp_rebuildContent];
}

#pragma mark - Setup

- (void)pp_buildView {
    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.backgroundColor = PPProviderCanvasColor();
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.contentStack = [UIStackView new];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = PPSpaceMD;
    [self.scrollView addSubview:self.contentStack];

    NSLayoutConstraint *responsiveWidth = [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-(PPScreenMargin * 2.0)];
    responsiveWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:PPSpaceMD],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-PPSpaceXXL],
        [self.contentStack.centerXAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.centerXAnchor],
        [self.contentStack.widthAnchor constraintLessThanOrEqualToConstant:760.0],
        responsiveWidth,
    ]];
}

- (void)pp_rebuildContent {
    for (UIView *view in self.contentStack.arrangedSubviews.copy) {
        [self.contentStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    self.reviewButton = nil;
    self.reviewSpinner = nil;
    [self.linkURLs removeAllObjects];
    [self.borderedSurfaces removeAllObjects];

    [self.contentStack addArrangedSubview:[self pp_briefingView]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitleKey:@"Providers_ApplicationDetail_Section_Overview"
                                                               symbol:@"doc.text"
                                                                 rows:[self pp_overviewRows]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitleKey:@"Providers_ApplicationDetail_Section_ApplicantBusinessContact"
                                                               symbol:@"person.crop.circle"
                                                                 rows:[self pp_applicantRows]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitleKey:@"Providers_ApplicationDetail_Section_DocumentsImages"
                                                               symbol:@"paperclip"
                                                                 rows:[self pp_documentRows]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitleKey:@"Providers_ApplicationDetail_Section_PlanCoverage"
                                                               symbol:@"list.bullet.rectangle"
                                                                 rows:[self pp_planRows]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitleKey:@"Providers_ApplicationDetail_Section_ReviewHistory"
                                                               symbol:@"clock"
                                                                 rows:[self pp_reviewHistoryRows]]];
    if (self.canManage && [self pp_isTransitionable]) {
        [self.contentStack addArrangedSubview:[self pp_sectionWithTitleKey:@"Providers_ApplicationDetail_Section_Decision"
                                                                   symbol:@"checkmark.seal"
                                                                     rows:@[[self pp_reviewActionRow]]]];
    }
    [self pp_refreshBorderColors];
}

#pragma mark - Briefing

- (UIView *)pp_briefingView {
    NSString *status = [self pp_normalizedStatus];
    UIColor *statusColor = PPProviderStatusColor(status);

    UIView *surface = [UIView new];
    surface.translatesAutoresizingMaskIntoConstraints = NO;
    surface.backgroundColor = [UIColor ppElevatedSurface];
    surface.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    surface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    PPApplyContinuousCorners(surface, PPCornerCard);
    [self.borderedSurfaces addObject:surface];

    UIView *rail = [UIView new];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    rail.backgroundColor = statusColor;
    rail.userInteractionEnabled = NO;
    PPApplyContinuousCorners(rail, PPSpaceXXS);
    [surface addSubview:rail];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = PPSpaceSM;
    [surface addSubview:stack];

    UIStackView *identity = [UIStackView new];
    identity.axis = UILayoutConstraintAxisHorizontal;
    identity.alignment = UIStackViewAlignmentCenter;
    identity.spacing = PPSpaceMD;
    identity.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *symbolShell = [UIView new];
    symbolShell.translatesAutoresizingMaskIntoConstraints = NO;
    symbolShell.backgroundColor = [statusColor colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(symbolShell, PPCornerSmall);
    [NSLayoutConstraint activateConstraints:@[
        [symbolShell.widthAnchor constraintEqualToConstant:PPTouchTargetMin],
        [symbolShell.heightAnchor constraintEqualToConstant:PPTouchTargetMin],
    ]];

    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.badge.checkmark"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21.0 weight:UIImageSymbolWeightSemibold]]];
    symbol.translatesAutoresizingMaskIntoConstraints = NO;
    symbol.tintColor = statusColor;
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.isAccessibilityElement = NO;
    [symbolShell addSubview:symbol];
    [NSLayoutConstraint activateConstraints:@[
        [symbol.centerXAnchor constraintEqualToAnchor:symbolShell.centerXAnchor],
        [symbol.centerYAnchor constraintEqualToAnchor:symbolShell.centerYAnchor],
        [symbol.widthAnchor constraintEqualToConstant:24.0],
        [symbol.heightAnchor constraintEqualToConstant:24.0],
    ]];

    UIStackView *identityText = [UIStackView new];
    identityText.axis = UILayoutConstraintAxisVertical;
    identityText.spacing = PPSpaceXXS;
    UILabel *contextLabel = [self pp_labelWithText:kLang(@"Providers_ApplicationDetail_Context")
                                              font:[Styling fontBold:PPFontFootnote]
                                             color:PPProviderSecondaryTextColor()
                                              lines:0];
    UILabel *titleLabel = [self pp_labelWithText:PPProviderApplicationDisplayName(self.application)
                                            font:[Styling fontBold:PPFontTitle2]
                                           color:PPProviderPrimaryTextColor()
                                           lines:0];
    UILabel *typeLabel = [self pp_labelWithText:PPProviderLocalizedType(self.application.providerType)
                                           font:[Styling fontMedium:PPFontSubheadline]
                                          color:PPProviderSecondaryTextColor()
                                          lines:0];
    [identityText addArrangedSubview:contextLabel];
    [identityText addArrangedSubview:titleLabel];
    [identityText addArrangedSubview:typeLabel];
    [identity addArrangedSubview:symbolShell];
    [identity addArrangedSubview:identityText];
    [stack addArrangedSubview:identity];
    [stack addArrangedSubview:[self pp_statusBadgeWithText:PPProviderLocalizedStatus(status) color:statusColor]];

    UIView *divider = [UIView new];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [UIColor ppSurfaceBorder];
    [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    [stack addArrangedSubview:divider];

    UIStackView *nextActionStack = [UIStackView new];
    nextActionStack.axis = UILayoutConstraintAxisVertical;
    nextActionStack.spacing = PPSpaceXXS;
    nextActionStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UILabel *nextLabel = [self pp_labelWithText:kLang(@"Providers_ApplicationDetail_NextMove")
                                           font:[Styling fontBold:PPFontFootnote]
                                          color:PPProviderSecondaryTextColor()
                                          lines:1];
    UILabel *nextValue = [self pp_labelWithText:[self pp_nextMoveText]
                                           font:[Styling fontMedium:PPFontBody]
                                          color:PPProviderPrimaryTextColor()
                                          lines:0];
    [nextActionStack addArrangedSubview:nextLabel];
    [nextActionStack addArrangedSubview:nextValue];
    [stack addArrangedSubview:nextActionStack];

    [NSLayoutConstraint activateConstraints:@[
        [rail.topAnchor constraintEqualToAnchor:surface.topAnchor constant:PPSpaceMD],
        [rail.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-PPSpaceMD],
        [rail.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
        [rail.widthAnchor constraintEqualToConstant:PPSpaceXS],
        [stack.topAnchor constraintEqualToAnchor:surface.topAnchor constant:PPSpaceMD],
        [stack.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:PPSpaceLG],
        [stack.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-PPSpaceMD],
        [stack.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-PPSpaceMD],
    ]];
    return surface;
}

- (UIView *)pp_statusBadgeWithText:(NSString *)text color:(UIColor *)color {
    UIView *badge = [UIView new];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = [color colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(badge, PPCornerSmall);
    UILabel *label = [self pp_labelWithText:text font:[Styling fontBold:PPFontSubheadline] color:color lines:0];
    [badge addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:badge.topAnchor constant:PPSpaceSM],
        [label.leadingAnchor constraintEqualToAnchor:badge.leadingAnchor constant:PPSpaceMD],
        [label.trailingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:-PPSpaceMD],
        [label.bottomAnchor constraintEqualToAnchor:badge.bottomAnchor constant:-PPSpaceSM],
        [badge.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
    ]];
    badge.isAccessibilityElement = YES;
    badge.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", kLang(@"Providers_ApplicationDetail_Field_Status"), text ?: @""];
    label.isAccessibilityElement = NO;
    return badge;
}

- (NSString *)pp_normalizedStatus {
    NSString *status = PPProviderApplicationTrimmedString(self.application.status).lowercaseString;
    return status.length ? status : @"pending";
}

- (BOOL)pp_isTransitionable {
    NSString *status = [self pp_normalizedStatus];
    return [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"];
}

- (NSString *)pp_nextMoveText {
    NSString *status = [self pp_normalizedStatus];
    if ([self pp_isTransitionable] && !self.canManage) {
        return kLang(@"Providers_ApplicationDetail_NextMove_AwaitingManager");
    }
    if ([status isEqualToString:@"pending"]) return kLang(@"Providers_ApplicationDetail_NextMove_StartReview");
    if ([status isEqualToString:@"under_review"]) return kLang(@"Providers_ApplicationDetail_NextMove_CompleteReview");
    if ([status isEqualToString:@"approved"]) return kLang(@"Providers_ApplicationDetail_NextMove_Approved");
    if ([status isEqualToString:@"rejected"]) return kLang(@"Providers_ApplicationDetail_NextMove_Rejected");
    if ([status isEqualToString:@"archived"]) return kLang(@"Providers_ApplicationDetail_NextMove_Archived");
    return kLang(@"Providers_ApplicationDetail_NextMove_VerifyStatus");
}

#pragma mark - Sections

- (UIView *)pp_sectionWithTitleKey:(NSString *)titleKey symbol:(NSString *)symbolName rows:(NSArray<UIView *> *)rows {
    UIView *surface = [UIView new];
    surface.translatesAutoresizingMaskIntoConstraints = NO;
    surface.backgroundColor = [UIColor ppSurface];
    surface.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    surface.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceMD, PPSpaceMD, PPSpaceSM, PPSpaceMD);
    surface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    PPApplyContinuousCorners(surface, PPCornerCard);
    [self.borderedSurfaces addObject:surface];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0.0;
    [surface addSubview:stack];

    UIStackView *heading = [UIStackView new];
    heading.axis = UILayoutConstraintAxisHorizontal;
    heading.alignment = UIStackViewAlignmentCenter;
    heading.spacing = PPSpaceSM;
    heading.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbolName
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold]]];
    symbol.translatesAutoresizingMaskIntoConstraints = NO;
    symbol.tintColor = PPProviderBrandColor();
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.isAccessibilityElement = NO;
    [NSLayoutConstraint activateConstraints:@[
        [symbol.widthAnchor constraintEqualToConstant:22.0],
        [symbol.heightAnchor constraintEqualToConstant:22.0],
    ]];
    UILabel *title = [self pp_labelWithText:kLang(titleKey)
                                        font:[Styling fontBold:PPFontTitle3]
                                       color:PPProviderPrimaryTextColor()
                                       lines:0];
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    [heading addArrangedSubview:symbol];
    [heading addArrangedSubview:title];
    [stack addArrangedSubview:heading];
    [stack setCustomSpacing:PPSpaceSM afterView:heading];

    for (NSUInteger index = 0; index < rows.count; index++) {
        if (index > 0) {
            UIView *separator = [UIView new];
            separator.translatesAutoresizingMaskIntoConstraints = NO;
            separator.backgroundColor = [UIColor ppSurfaceBorder];
            [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
            [stack addArrangedSubview:separator];
        }
        [stack addArrangedSubview:rows[index]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:surface.layoutMarginsGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:surface.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:surface.layoutMarginsGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:surface.layoutMarginsGuide.bottomAnchor],
    ]];
    surface.accessibilityContainerType = UIAccessibilityContainerTypeSemanticGroup;
    return surface;
}

- (NSArray<UIView *> *)pp_overviewRows {
    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Status"
                             value:PPProviderLocalizedStatus([self pp_normalizedStatus])
                         technical:NO
                                URL:nil
                             toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_ProviderType"
                             value:PPProviderLocalizedType(self.application.providerType)
                         technical:NO
                                URL:nil
                             toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_ApplicationID"
                             value:self.application.applicationID
                         technical:YES
                                URL:nil
                             toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_UserID"
                             value:self.application.userId
                         technical:YES
                                URL:nil
                             toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_ProfileID"
                             value:self.application.profileId
                         technical:YES
                                URL:nil
                             toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_DeliveryCompanyID"
                             value:self.application.deliveryCompanyId
                         technical:YES
                                URL:nil
                             toRows:rows];
    return rows.copy;
}

- (NSArray<UIView *> *)pp_applicantRows {
    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    NSDictionary *form = PPProviderApplicationSafeDictionary(self.application.form);
    NSDictionary *summary = PPProviderApplicationSafeDictionary(self.application.userSummary);
    NSString *fullName = PPProviderApplicationTrimmedString(form[@"fullName"]);
    NSString *summaryName = PPProviderApplicationTrimmedString(summary[@"displayName"]);
    NSString *phone = PPProviderApplicationTrimmedString(form[@"phone"]);
    NSString *summaryPhone = PPProviderApplicationTrimmedString(summary[@"phone"]);
    NSString *email = PPProviderApplicationTrimmedString(form[@"email"]);
    NSString *summaryEmail = PPProviderApplicationTrimmedString(summary[@"email"]);

    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_FullName" value:fullName technical:NO URL:nil toRows:rows];
    if (!PPProviderApplicationStringsMatch(fullName, summaryName)) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_AccountDisplayName" value:summaryName technical:NO URL:nil toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_BusinessName" value:PPProviderApplicationTrimmedString(form[@"businessName"]) technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_CompanyName" value:PPProviderApplicationTrimmedString(form[@"companyName"]) technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_LegalName" value:PPProviderApplicationTrimmedString(form[@"legalName"]) technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Phone" value:phone technical:YES URL:nil toRows:rows];
    if (!PPProviderApplicationStringsMatch(phone, summaryPhone)) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_AccountPhone" value:summaryPhone technical:YES URL:nil toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Email" value:email technical:YES URL:nil toRows:rows];
    if (!PPProviderApplicationStringsMatch(email, summaryEmail)) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_AccountEmail" value:summaryEmail technical:YES URL:nil toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_City" value:PPProviderApplicationTrimmedString(form[@"city"]) technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Address" value:PPProviderApplicationTrimmedString(form[@"address"]) technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_LicenseNumber" value:PPProviderApplicationTrimmedString(form[@"licenseNumber"]) technical:YES URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_CommercialRegistrationNumber" value:PPProviderApplicationTrimmedString(form[@"commercialRegistrationNumber"]) technical:YES URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_ApplicationNotes" value:PPProviderApplicationTrimmedString(form[@"notes"]) technical:NO URL:nil toRows:rows];
    return rows.copy;
}

- (NSArray<UIView *> *)pp_planRows {
    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    NSDictionary *snapshot = PPProviderApplicationSafeDictionary(self.application.planSnapshot);
    NSString *costType = PPProviderApplicationTrimmedString(snapshot[@"costType"]);
    NSString *currency = PPProviderApplicationTrimmedString(snapshot[@"currency"]);
    NSString *planProviderType = PPProviderApplicationTrimmedString(snapshot[@"providerType"]);
    NSString *billingInterval = PPProviderApplicationTrimmedString(snapshot[@"billingInterval"]);
    NSNumber *costValue = PPProviderApplicationSafeNumber(snapshot[@"costValue"]);
    NSNumber *priceAmount = PPProviderApplicationSafeNumber(snapshot[@"priceAmount"]);

    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlanID" value:self.application.planId technical:YES URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlanSnapshotID" value:PPProviderApplicationTrimmedString(snapshot[@"id"]) technical:YES URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlanCode" value:PPProviderApplicationTrimmedString(snapshot[@"code"]) technical:YES URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlanName" value:PPProviderApplicationLocalizedValue(snapshot[@"name"]) technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlanDescription" value:PPProviderApplicationLocalizedValue(snapshot[@"description"]) technical:NO URL:nil toRows:rows];
    if (planProviderType.length) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlanProviderType" value:PPProviderLocalizedType(planProviderType) technical:NO URL:nil toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_CostType" value:PPProviderApplicationCostTypeText(costType) technical:NO URL:nil toRows:rows];
    if (costValue) {
        NSString *costText = [costType.lowercaseString isEqualToString:@"percentage"]
            ? [NSString stringWithFormat:kLang(@"Providers_ApplicationDetail_Percent_Format"), PPProviderApplicationNumberText(costValue)]
            : PPProviderMoneyText(costValue.doubleValue, currency);
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlanCost" value:costText technical:YES URL:nil toRows:rows];
    }
    if (priceAmount && (!costValue || [priceAmount compare:costValue] != NSOrderedSame)) {
        NSString *priceText = [costType.lowercaseString isEqualToString:@"percentage"]
            ? [NSString stringWithFormat:kLang(@"Providers_ApplicationDetail_Percent_Format"), PPProviderApplicationNumberText(priceAmount)]
            : PPProviderMoneyText(priceAmount.doubleValue, currency);
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PriceAmount" value:priceText technical:YES URL:nil toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Currency" value:currency technical:YES URL:nil toRows:rows];
    if (billingInterval.length) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_BillingInterval" value:PPProviderLocalizedBillingInterval(billingInterval) technical:NO URL:nil toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PercentageBasis" value:PPProviderApplicationPercentageBasisText(PPProviderApplicationTrimmedString(snapshot[@"percentageBasis"])) technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PercentageCustomLabel" value:PPProviderApplicationTrimmedString(snapshot[@"percentageCustomLabel"]) technical:NO URL:nil toRows:rows];

    NSNumber *commission = PPProviderApplicationSafeNumber(snapshot[@"platformCommissionRate"]);
    if (commission) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_PlatformCommission"
                                 value:[NSString stringWithFormat:kLang(@"Providers_ApplicationDetail_Percent_Format"), PPProviderApplicationNumberText(commission)]
                             technical:YES
                                    URL:nil
                                 toRows:rows];
    }
    NSNumber *trialDays = PPProviderApplicationSafeNumber(snapshot[@"trialDays"]);
    if (trialDays) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_TrialDays"
                                 value:PPProviderApplicationNumberText(trialDays)
                             technical:NO
                                    URL:nil
                                 toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Rank" value:PPProviderApplicationNumberText(PPProviderApplicationSafeNumber(snapshot[@"rank"])) technical:YES URL:nil toRows:rows];
    NSNumber *recommended = PPProviderApplicationSafeNumber(snapshot[@"recommended"]);
    if (recommended) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Recommended"
                                 value:kLang(recommended.boolValue ? @"Providers_ApplicationDetail_Yes" : @"Providers_ApplicationDetail_No")
                             technical:NO
                                    URL:nil
                                 toRows:rows];
    }
    NSArray<NSString *> *features = PPProviderApplicationSafeStringArray(snapshot[@"features"]);
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_Features" value:[features componentsJoinedByString:@"\n"] technical:YES URL:nil toRows:rows];
    NSArray<NSString *> *coverage = PPProviderApplicationSafeStringArray(self.application.form[@"coverageAreas"]);
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_CoverageAreas" value:[coverage componentsJoinedByString:@"\n"] technical:NO URL:nil toRows:rows];
    return rows.copy;
}

- (NSArray<UIView *> *)pp_reviewHistoryRows {
    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    if (self.application.submittedAt) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_SubmittedAt" value:PPProviderDateText(self.application.submittedAt) technical:NO URL:nil toRows:rows];
    }
    if (self.application.createdAt) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_CreatedAt" value:PPProviderDateText(self.application.createdAt) technical:NO URL:nil toRows:rows];
    }
    if (self.application.updatedAt) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_UpdatedAt" value:PPProviderDateText(self.application.updatedAt) technical:NO URL:nil toRows:rows];
    }
    if (self.application.reviewedAt) {
        [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_ReviewedAt" value:PPProviderDateText(self.application.reviewedAt) technical:NO URL:nil toRows:rows];
    }
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_ReviewedBy" value:self.application.reviewedBy technical:YES URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_ReviewNotes" value:self.application.reviewNotes technical:NO URL:nil toRows:rows];
    [self pp_appendRowWithLabelKey:@"Providers_ApplicationDetail_Field_RejectionReason" value:self.application.rejectionReason technical:NO URL:nil toRows:rows];
    return rows.copy;
}

- (NSArray<UIView *> *)pp_documentRows {
    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    NSDictionary *form = PPProviderApplicationSafeDictionary(self.application.form);
    NSDictionary *summary = PPProviderApplicationSafeDictionary(self.application.userSummary);
    [self pp_appendDocumentRowWithLabelKey:@"Providers_ApplicationDetail_Field_LicenseDocument" value:form[@"licenseDocumentURL"] toRows:rows];
    [self pp_appendDocumentRowWithLabelKey:@"Providers_ApplicationDetail_Field_CommercialRegistrationDocument" value:form[@"commercialRegistrationDocumentURL"] toRows:rows];

    NSArray<NSString *> *documents = PPProviderApplicationSafeStringArray(form[@"documentRefs"]);
    for (NSUInteger index = 0; index < documents.count; index++) {
        NSString *label = [NSString stringWithFormat:kLang(@"Providers_ApplicationDetail_Document_Format"), PPProviderApplicationIndexText(index + 1)];
        [self pp_appendRowWithLabel:label value:documents[index] technical:YES URL:PPProviderApplicationHTTPURL(documents[index]) toRows:rows];
    }
    NSArray<NSString *> *images = PPProviderApplicationSafeStringArray(form[@"imageRefs"]);
    for (NSUInteger index = 0; index < images.count; index++) {
        NSString *label = [NSString stringWithFormat:kLang(@"Providers_ApplicationDetail_Image_Format"), PPProviderApplicationIndexText(index + 1)];
        [self pp_appendRowWithLabel:label value:images[index] technical:YES URL:PPProviderApplicationHTTPURL(images[index]) toRows:rows];
    }
    [self pp_appendDocumentRowWithLabelKey:@"Providers_ApplicationDetail_Field_ProfileImage" value:summary[@"photoURL"] toRows:rows];
    if (rows.count == 0) {
        [rows addObject:[self pp_messageRowWithText:kLang(@"Providers_ApplicationDetail_NoDocuments")]];
    }
    return rows.copy;
}

#pragma mark - Rows

- (void)pp_appendDocumentRowWithLabelKey:(NSString *)labelKey value:(id)value toRows:(NSMutableArray<UIView *> *)rows {
    NSString *text = PPProviderApplicationTrimmedString(value);
    [self pp_appendRowWithLabelKey:labelKey value:text technical:YES URL:PPProviderApplicationHTTPURL(text) toRows:rows];
}

- (void)pp_appendRowWithLabelKey:(NSString *)labelKey
                           value:(NSString *)value
                       technical:(BOOL)technical
                              URL:(NSURL *)URL
                           toRows:(NSMutableArray<UIView *> *)rows {
    [self pp_appendRowWithLabel:kLang(labelKey) value:value technical:technical URL:URL toRows:rows];
}

- (void)pp_appendRowWithLabel:(NSString *)label
                        value:(NSString *)value
                    technical:(BOOL)technical
                           URL:(NSURL *)URL
                        toRows:(NSMutableArray<UIView *> *)rows {
    NSString *safeValue = PPProviderApplicationTrimmedString(value);
    if (safeValue.length == 0) return;
    [rows addObject:[self pp_fieldRowWithLabel:label value:safeValue technical:technical URL:URL]];
}

- (UIView *)pp_fieldRowWithLabel:(NSString *)labelText value:(NSString *)valueText technical:(BOOL)technical URL:(NSURL *)URL {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = PPSpaceXXS;
    [row addSubview:stack];

    UILabel *label = [self pp_labelWithText:labelText
                                        font:[Styling fontBold:PPFontFootnote]
                                       color:PPProviderSecondaryTextColor()
                                       lines:0];
    UILabel *value = [self pp_labelWithText:valueText
                                        font:[Styling fontMedium:PPFontBody]
                                       color:PPProviderPrimaryTextColor()
                                       lines:0];
    if (technical) {
        value.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        value.textAlignment = NSTextAlignmentNatural;
        value.lineBreakMode = NSLineBreakByCharWrapping;
    }
    [stack addArrangedSubview:label];
    [stack addArrangedSubview:value];

    if (URL) {
        UIButton *openButton = [UIButton buttonWithType:UIButtonTypeSystem];
        openButton.translatesAutoresizingMaskIntoConstraints = NO;
        openButton.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        openButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        openButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceMD, PPSpaceSM, PPSpaceMD);
        openButton.tintColor = PPProviderBrandColor();
        openButton.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.08];
        openButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontSubheadline]];
        openButton.titleLabel.adjustsFontForContentSizeCategory = YES;
        openButton.titleLabel.numberOfLines = 0;
        [openButton setTitle:kLang(@"Providers_ApplicationDetail_Open") forState:UIControlStateNormal];
        [openButton setImage:[UIImage systemImageNamed:@"arrow.up.right.square"] forState:UIControlStateNormal];
        PPApplyContinuousCorners(openButton, PPCornerSmall);
        openButton.tag = (NSInteger)self.linkURLs.count;
        [self.linkURLs addObject:URL];
        [openButton addTarget:self action:@selector(pp_openURL:) forControlEvents:UIControlEventTouchUpInside];
        openButton.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", kLang(@"Providers_ApplicationDetail_Open"), labelText ?: @""];
        openButton.accessibilityHint = kLang(@"Providers_ApplicationDetail_OpenURLHint");
        openButton.accessibilityTraits |= UIAccessibilityTraitLink;
        [openButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;
        [stack addArrangedSubview:openButton];
    } else {
        row.isAccessibilityElement = YES;
        NSString *accessibleValue = technical ? PPProviderApplicationLTRIsolate(valueText) : (valueText ?: @"");
        row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", labelText ?: @"", accessibleValue];
        label.isAccessibilityElement = NO;
        value.isAccessibilityElement = NO;
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:row.topAnchor constant:PPSpaceSM],
        [stack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-PPSpaceSM],
    ]];
    return row;
}

- (UIView *)pp_messageRowWithText:(NSString *)text {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *label = [self pp_labelWithText:text font:[Styling fontRegular:PPFontBody] color:PPProviderSecondaryTextColor() lines:0];
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:PPSpaceSM],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-PPSpaceSM],
    ]];
    return row;
}

- (UILabel *)pp_labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:font];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = lines;
    label.textColor = color;
    label.textAlignment = Language.alignmentForCurrentLanguage;
    label.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    return label;
}

#pragma mark - Documents

- (void)pp_openURL:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.linkURLs.count) return;
    NSURL *URL = self.linkURLs[(NSUInteger)sender.tag];
    [[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [AlertHelper showAlertIn:self
                               title:kLang(@"Error_Title")
                            subtitle:kLang(@"Providers_ApplicationDetail_OpenURLFailed")];
        });
    }];
}

#pragma mark - Review

- (UIView *)pp_reviewActionRow {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [PPProviderBrandColor() colorWithAlphaComponent:0.055];
    row.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(PPSpaceSM, PPSpaceSM, PPSpaceSM, PPSpaceSM);
    row.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    row.layer.borderColor = [PPProviderBrandColor() colorWithAlphaComponent:0.15].CGColor;
    PPApplyContinuousCorners(row, PPCornerMedium);
    self.decisionSurface = row;

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = PPSpaceMD;
    [row addSubview:stack];

    UILabel *subtitle = [self pp_labelWithText:kLang(@"Providers_ApplicationDetail_DecisionSubtitle")
                                           font:[Styling fontRegular:PPFontBody]
                                          color:PPProviderSecondaryTextColor()
                                          lines:0];
    [stack addArrangedSubview:subtitle];

    self.reviewButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.reviewButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.reviewButton.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.reviewButton.backgroundColor = PPProviderBrandColor();
    self.reviewButton.tintColor = UIColor.whiteColor;
    [self.reviewButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.reviewButton setTitleColor:[UIColor.whiteColor colorWithAlphaComponent:0.65] forState:UIControlStateDisabled];
    [self.reviewButton setTitle:kLang(@"Providers_ApplicationDetail_ReviewApplication") forState:UIControlStateNormal];
    [self.reviewButton setImage:[UIImage systemImageNamed:@"checkmark.seal"] forState:UIControlStateNormal];
    self.reviewButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontHeadline]];
    self.reviewButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.reviewButton.titleLabel.numberOfLines = 0;
    self.reviewButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceBase, PPSpaceMD, PPSpaceBase);
    PPApplyContinuousCorners(self.reviewButton, PPCornerSmall);
    [self.reviewButton addTarget:self action:@selector(pp_reviewTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.reviewButton.accessibilityHint = kLang(@"Providers_ApplicationDetail_ReviewHint");
    [self.reviewButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightLG].active = YES;
    [stack addArrangedSubview:self.reviewButton];

    self.reviewSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.reviewSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.reviewSpinner.color = UIColor.whiteColor;
    self.reviewSpinner.hidesWhenStopped = YES;
    [self.reviewButton addSubview:self.reviewSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.reviewSpinner.centerXAnchor constraintEqualToAnchor:self.reviewButton.centerXAnchor],
        [self.reviewSpinner.centerYAnchor constraintEqualToAnchor:self.reviewButton.centerYAnchor],
        [stack.topAnchor constraintEqualToAnchor:row.layoutMarginsGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:row.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:row.layoutMarginsGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:row.layoutMarginsGuide.bottomAnchor],
    ]];
    return row;
}

- (void)pp_reviewTapped:(UIButton *)sender {
    if (!self.canManage || self.isReviewing || ![self pp_isTransitionable] || self.presentedViewController) return;
    NSString *status = [self pp_normalizedStatus];
    UIAlertController *actions = [UIAlertController alertControllerWithTitle:PPProviderApplicationDisplayName(self.application)
                                                                      message:PPProviderLocalizedStatus(status)
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    if ([status isEqualToString:@"pending"]) {
        [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_MarkUnderReview") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf pp_requestReviewDecision:@"under_review"];
        }]];
    }
    [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Approve") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf pp_requestReviewDecision:@"approved"];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Providers_Reject") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [weakSelf pp_requestReviewDecision:@"rejected"];
    }]];
    [actions addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = actions.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender;
        popover.sourceRect = sender.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [self presentViewController:actions animated:YES completion:nil];
}

- (void)pp_requestReviewDecision:(NSString *)decision {
    if (!self.canManage || self.isReviewing || ![self pp_isTransitionable]) return;
    if (!PPProviderApplicationDecisionIsAllowed(decision, [self pp_normalizedStatus])) return;
    UIAlertController *notes = [UIAlertController alertControllerWithTitle:kLang(@"Providers_ReviewNotes")
                                                                   message:kLang(@"Providers_ReviewNotes_Context")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [notes addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = kLang(@"Providers_ReviewNotesPlaceholder");
        textField.textAlignment = Language.alignmentForCurrentLanguage;
        textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        textField.accessibilityLabel = kLang(@"Providers_ReviewNotes");
    }];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakNotes = notes;
    [notes addAction:[UIAlertAction actionWithTitle:kLang(@"Confirm") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf pp_submitReviewDecision:decision notes:weakNotes.textFields.firstObject.text];
    }]];
    [notes addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:notes animated:YES completion:nil];
}

- (void)pp_submitReviewDecision:(NSString *)decision notes:(NSString *)notes {
    if (!self.canManage || self.isReviewing || ![self pp_isTransitionable]) return;
    if (!PPProviderApplicationDecisionIsAllowed(decision, [self pp_normalizedStatus])) return;
    self.isReviewing = YES;
    [self pp_setReviewing:YES];
    NSString *safeNotes = PPProviderApplicationTrimmedString(notes);
    void (^mutationHandler)(void) = self.applicationDidMutate;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] reviewApplication:self.application.applicationID status:decision notes:safeNotes completion:^(NSDictionary *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                if (!error && mutationHandler) mutationHandler();
                return;
            }
            self.isReviewing = NO;
            [self pp_setReviewing:NO];
            if (error) {
                if (PPProviderApplicationIsPermissionError(error)) {
                    [AlertHelper showAlertIn:self
                                       title:kLang(@"CommandCenter_Permission_Denied_Title")
                                    subtitle:kLang(@"CommandCenter_Permission_Denied_Message")];
                } else {
                    [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                }
                return;
            }
            self.application.status = decision;
            self.application.reviewNotes = safeNotes;
            NSString *deliveryCompanyId = PPProviderApplicationTrimmedString(result[@"deliveryCompanyId"]);
            if (deliveryCompanyId.length) self.application.deliveryCompanyId = deliveryCompanyId;
            if ([decision isEqualToString:@"rejected"] && [self.application.providerType.lowercaseString isEqualToString:@"delivery_company"]) {
                self.application.rejectionReason = safeNotes;
            }
            [PPFunc pp_playSuccessEffect];
            [self pp_rebuildContent];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, kLang(@"Providers_ApplicationDetail_ReviewSucceeded"));
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.view);
            if (mutationHandler) mutationHandler();
        });
    }];
}

- (void)pp_setReviewing:(BOOL)reviewing {
    self.reviewButton.enabled = !reviewing;
    if (reviewing) {
        [self.reviewButton setTitle:@"" forState:UIControlStateNormal];
        [self.reviewButton setImage:nil forState:UIControlStateNormal];
        self.reviewButton.accessibilityLabel = kLang(@"Providers_ApplicationDetail_Saving");
        [self.reviewSpinner startAnimating];
    } else {
        [self.reviewSpinner stopAnimating];
        [self.reviewButton setTitle:kLang(@"Providers_ApplicationDetail_ReviewApplication") forState:UIControlStateNormal];
        [self.reviewButton setImage:[UIImage systemImageNamed:@"checkmark.seal"] forState:UIControlStateNormal];
        self.reviewButton.accessibilityLabel = kLang(@"Providers_ApplicationDetail_ReviewApplication");
    }
}

#pragma mark - Appearance

- (void)pp_refreshBorderColors {
    UIColor *borderColor = [[UIColor ppSurfaceBorder] resolvedColorWithTraitCollection:self.traitCollection];
    for (UIView *surface in self.borderedSurfaces) {
        surface.layer.borderColor = borderColor.CGColor;
    }
    self.decisionSurface.layer.borderColor = [PPProviderBrandColor() colorWithAlphaComponent:0.15].CGColor;
}

@end

@interface PPProviderApplicationsViewController () <UISearchBarDelegate>
@property (nonatomic, strong) NSArray<PPProviderApplication *> *applications;
@property (nonatomic, copy) NSString *statusFilter;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) PPProviderApplicationQueueHeaderView *queueHeader;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPProviderApplicationStateView *stateView;
@property (nonatomic, strong) NSError *currentError;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedApplicationIDs;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL canView;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL permissionDenied;
@property (nonatomic, assign) BOOL reloadAfterCurrentLoad;
@property (nonatomic, copy) void (^queuedLoadCompletion)(NSArray<PPProviderApplication *> *applications, NSError *error);
- (void)pp_loadDataWithCompletion:(void(^)(NSArray<PPProviderApplication *> *applications, NSError *error))completion;
- (void)pp_refreshFilterAppearance;
@end

@implementation PPProviderApplicationsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.applications = @[];
    self.statusFilter = @"all";
    self.searchQuery = @"";
    self.animatedApplicationIDs = [NSMutableSet set];
    [self pp_configureNavigation];
    [self pp_configureTableView];
    [self pp_buildHeader];
    [self pp_evaluatePermissions];
    if (!self.permissionDenied) {
        [self loadData];
    } else {
        [self pp_updateState];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_fitTableHeader];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    BOOL colorChanged = !previousTraitCollection || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection];
    BOOL contentSizeChanged = !previousTraitCollection || ![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory];
    if (colorChanged || contentSizeChanged) {
        [self.queueHeader refreshAppearance];
        [self.stateView refreshAppearance];
        [self pp_refreshFilterAppearance];
    }
}

#pragma mark - Setup

- (void)pp_evaluatePermissions {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    self.canView = [staff hasPermission:kStaffPermProvidersView];
    self.canManage = [staff hasPermission:kStaffPermProvidersManage];
    self.permissionDenied = !self.canView && !self.canManage;
    if (self.permissionDenied) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
    }
}

- (void)pp_configureNavigation {
    self.title = kLang(@"Providers_Applications_Title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(loadData)];
    refresh.accessibilityLabel = kLang(@"DC_Refresh");
    self.navigationItem.rightBarButtonItem = refresh;
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPProviderCanvasColor();
    self.tableView.backgroundColor = PPProviderCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 112.0;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0.0, PPSpaceXXL, 0.0);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:PPProviderApplicationQueueCell.class forCellReuseIdentifier:PPProviderApplicationCellID];
    if (@available(iOS 15.0, *)) self.tableView.sectionHeaderTopPadding = 0.0;

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = PPProviderBrandColor();
    [refresh addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.stateView = [PPProviderApplicationStateView new];
    __weak typeof(self) weakSelf = self;
    self.stateView.retryHandler = ^{ [weakSelf loadData]; };
    self.stateView.clearSearchHandler = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        BOOL hadSearch = PPProviderApplicationTrimmedString(self.searchQuery).length > 0;
        self.searchBar.text = @"";
        self.searchQuery = @"";
        if (!hadSearch) {
            self.statusFilter = @"all";
            self.filterControl.selectedSegmentIndex = 0;
        }
        [self pp_refreshHeaderMetric];
        [self pp_updateState];
        [self.tableView reloadData];
        [self.searchBar resignFirstResponder];
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.tableView);
    };
    self.tableView.backgroundView = self.stateView;
}

- (void)pp_buildHeader {
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.clearColor;
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.queueHeader = [PPProviderApplicationQueueHeaderView new];
    self.queueHeader.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.queueHeader.retryHandler = ^{
        [weakSelf loadData];
    };
    [container addSubview:self.queueHeader];

    self.searchBar = [UISearchBar new];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.tintColor = PPProviderBrandColor();
    self.searchBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.searchBar.placeholder = kLang(@"MissionControl_Customers_Search_Placeholder");
    self.searchBar.accessibilityLabel = self.searchBar.placeholder;
    self.searchBar.delegate = self;
    if (@available(iOS 13.0, *)) {
        self.searchBar.searchTextField.backgroundColor = PPProviderSurfaceColor();
        self.searchBar.searchTextField.textColor = PPProviderPrimaryTextColor();
        self.searchBar.searchTextField.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:PPFontBody]];
        self.searchBar.searchTextField.adjustsFontForContentSizeCategory = YES;
        self.searchBar.searchTextField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    }
    [container addSubview:self.searchBar];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[
        kLang(@"Providers_All"), kLang(@"Providers_Pending"),
        kLang(@"Providers_Approved"), kLang(@"Providers_Rejected")
    ]];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterControl.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.selectedSegmentTintColor = PPProviderBrandColor();
    [self pp_refreshFilterAppearance];
    self.filterControl.accessibilityLabel = kLang(@"Providers_Applications_Title");
    [self.filterControl addTarget:self action:@selector(pp_filterChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:self.filterControl];

    [NSLayoutConstraint activateConstraints:@[
        [self.queueHeader.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.queueHeader.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.queueHeader.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.queueHeader.bottomAnchor constant:PPSpaceXS],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],
        [self.searchBar.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
        [self.filterControl.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:PPSpaceXS],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],
        [self.filterControl.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
        [self.filterControl.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-PPSpaceSM],
    ]];
    self.headerContainer = container;
    self.tableView.tableHeaderView = container;
    [self pp_refreshHeaderMetric];
}

- (void)pp_refreshFilterAppearance {
    UIFont *font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontSubheadline]];
    [self.filterControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: PPProviderPrimaryTextColor(),
        NSFontAttributeName: font
    } forState:UIControlStateNormal];
    [self.filterControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: font
    } forState:UIControlStateSelected];
}

- (void)pp_fitTableHeader {
    UIView *header = self.headerContainer;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (!header || width <= 0.0) return;
    header.frame = CGRectMake(0.0, 0.0, width, MAX(header.frame.size.height, 1.0));
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat height = ceil(size.height);
    if (fabs(CGRectGetHeight(header.frame) - height) > 0.5) {
        header.frame = CGRectMake(0.0, 0.0, width, height);
        self.tableView.tableHeaderView = header;
    }
}

#pragma mark - Data and State

- (void)loadData {
    if (self.permissionDenied) return;
    [self pp_loadDataWithCompletion:nil];
}

- (void)pp_loadDataWithCompletion:(void(^)(NSArray<PPProviderApplication *> *, NSError *))completion {
    if (self.isLoading) {
        self.reloadAfterCurrentLoad = YES;
        if (completion) {
            void (^previousCompletion)(NSArray<PPProviderApplication *> *, NSError *) = self.queuedLoadCompletion;
            self.queuedLoadCompletion = ^(NSArray<PPProviderApplication *> *applications, NSError *error) {
                if (previousCompletion) previousCompletion(applications, error);
                completion(applications, error);
            };
        }
        return;
    }
    self.isLoading = YES;
    self.currentError = nil;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self pp_updateState];

    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchApplicationsWithCompletion:^(NSArray<PPProviderApplication *> *apps, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            self.navigationItem.rightBarButtonItem.enabled = YES;
            [self.refreshControl endRefreshing];
            self.currentError = error;
            if (!error) self.applications = apps ?: @[];
            [self pp_refreshHeaderMetric];
            [self pp_updateState];
            [self.tableView reloadData];
            if (error && self.applications.count > 0) {
                if (PPProviderApplicationIsPermissionError(error)) {
                    [AlertHelper showAlertIn:self
                                       title:kLang(@"CommandCenter_Permission_Denied_Title")
                                    subtitle:kLang(@"CommandCenter_Permission_Denied_Message")];
                } else {
                    [AlertHelper showAlertIn:self title:kLang(@"Providers_Applications_LoadFailed") subtitle:kLang(@"Providers_Applications_ErrorSubtitle")];
                }
            }
            if (completion) completion(self.applications ?: @[], error);
            BOOL shouldReload = self.reloadAfterCurrentLoad;
            void (^queuedCompletion)(NSArray<PPProviderApplication *> *, NSError *) = self.queuedLoadCompletion;
            self.reloadAfterCurrentLoad = NO;
            self.queuedLoadCompletion = nil;
            if (shouldReload) [self pp_loadDataWithCompletion:queuedCompletion];
        });
    }];
}

- (NSArray<PPProviderApplication *> *)pp_filteredApplications {
    NSArray<PPProviderApplication *> *source = self.applications ?: @[];
    NSArray<PPProviderApplication *> *statusFiltered = source;
    if (![self.statusFilter isEqualToString:@"all"]) {
        statusFiltered = [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PPProviderApplication *application, NSDictionary *bindings) {
            (void)bindings;
            NSString *status = PPProviderApplicationSafeString(application.status).lowercaseString;
            if ([self.statusFilter isEqualToString:@"pending"]) {
                return status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"];
            }
            return [status isEqualToString:self.statusFilter];
        }]];
    }

    NSString *query = PPProviderApplicationTrimmedString(self.searchQuery).lowercaseString;
    if (query.length == 0) return statusFiltered;
    return [statusFiltered filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PPProviderApplication *application, NSDictionary *bindings) {
        (void)bindings;
        NSMutableArray<NSString *> *searchValues = [NSMutableArray arrayWithObjects:
            PPProviderApplicationDisplayName(application),
            PPProviderApplicationSafeString(application.applicationID),
            PPProviderApplicationSafeString(application.userId),
            PPProviderApplicationSafeString(application.profileId),
            PPProviderApplicationSafeString(application.deliveryCompanyId),
            PPProviderLocalizedType(application.providerType),
            PPProviderLocalizedStatus(application.status),
            nil
        ];
        NSDictionary *form = PPProviderApplicationSafeDictionary(application.form);
        NSDictionary *summary = PPProviderApplicationSafeDictionary(application.userSummary);
        NSDictionary *planSnapshot = PPProviderApplicationSafeDictionary(application.planSnapshot);
        for (NSString *key in @[
            @"fullName", @"businessName", @"companyName", @"legalName", @"phone", @"email",
            @"city", @"address", @"licenseNumber", @"commercialRegistrationNumber"
        ]) {
            NSString *value = PPProviderApplicationTrimmedString(form[key]);
            if (value.length) [searchValues addObject:value];
        }
        for (NSString *key in @[@"displayName", @"phone", @"email"]) {
            NSString *value = PPProviderApplicationTrimmedString(summary[key]);
            if (value.length) [searchValues addObject:value];
        }
        [searchValues addObject:PPProviderApplicationLocalizedValue(planSnapshot[@"name"])];
        [searchValues addObject:PPProviderApplicationLocalizedValue(planSnapshot[@"description"])];
        NSString *haystack = [[searchValues componentsJoinedByString:@" "] lowercaseString];
        return [haystack localizedCaseInsensitiveContainsString:query];
    }]];
}

- (BOOL)pp_isFiltering {
    return ![self.statusFilter isEqualToString:@"all"] || PPProviderApplicationTrimmedString(self.searchQuery).length > 0;
}

- (void)pp_refreshHeaderMetric {
    NSUInteger reviewQueue = 0;
    NSUInteger approvedCount = 0;
    NSUInteger rejectedCount = 0;
    for (PPProviderApplication *application in self.applications) {
        NSString *status = PPProviderApplicationSafeString(application.status).lowercaseString;
        if (status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"]) reviewQueue++;
        if ([status isEqualToString:@"approved"]) approvedCount++;
        if ([status isEqualToString:@"rejected"]) rejectedCount++;
    }
    NSString *retainedText = self.currentError && self.applications.count > 0
        ? kLang(@"Providers_Load_Error_Subtitle")
        : nil;
    [self.queueHeader updateWithVisibleCount:self.pp_filteredApplications.count
                               awaitingCount:reviewQueue
                                approvedCount:approvedCount
                                rejectedCount:rejectedCount
                                retainedText:retainedText];
}

- (void)pp_updateState {
    if (self.permissionDenied) {
        self.stateView.hidden = NO;
        [self.stateView showPermissionDeniedWithTitle:kLang(@"CommandCenter_Permission_Denied_Title")
                                             subtitle:kLang(@"CommandCenter_Permission_Denied_Message")];
        return;
    }
    BOOL hasRows = self.pp_filteredApplications.count > 0;
    self.stateView.hidden = hasRows;
    if (hasRows) return;
    if (self.isLoading && self.applications.count == 0) {
        [self.stateView showLoadingWithTitle:kLang(@"Providers_Applications_Loading") subtitle:kLang(@"Providers_Applications_Subtitle")];
    } else if (self.currentError && self.applications.count == 0) {
        if (PPProviderApplicationIsPermissionError(self.currentError)) {
            [self.stateView showPermissionDeniedWithTitle:kLang(@"CommandCenter_Permission_Denied_Title")
                                                 subtitle:kLang(@"CommandCenter_Permission_Denied_Message")];
        } else {
            [self.stateView showErrorWithTitle:kLang(@"Providers_Applications_LoadFailed") subtitle:kLang(@"Providers_Applications_ErrorSubtitle")];
        }
    } else if (self.applications.count > 0 && [self pp_isFiltering]) {
        NSString *clearTitle = PPProviderApplicationTrimmedString(self.searchQuery).length > 0
            ? kLang(@"Fulfillment_ClearSearch")
            : kLang(@"Providers_All");
        [self.stateView showFilteredEmptyWithTitle:kLang(@"Providers_Applications_Empty")
                                          subtitle:kLang(@"Fulfillment_EmptyFiltered_Subtitle")
                                         clearTitle:clearTitle];
    } else {
        [self.stateView showEmptyWithTitle:kLang(@"Providers_Applications_Empty")
                                  subtitle:kLang(@"Providers_Applications_EmptySubtitle")];
    }
}

- (void)pp_filterChanged:(UISegmentedControl *)sender {
    NSArray<NSString *> *filters = @[@"all", @"pending", @"approved", @"rejected"];
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)filters.count) return;
    self.statusFilter = filters[(NSUInteger)sender.selectedSegmentIndex];
    [self pp_refreshHeaderMetric];
    [self pp_updateState];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self.tableView reloadData];
    } else {
        [UIView transitionWithView:self.tableView duration:PPAnimDurationNormal
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ [self.tableView reloadData]; } completion:nil];
    }
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.tableView);
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchQuery = PPProviderApplicationTrimmedString(searchText);
    [self pp_refreshHeaderMetric];
    [self pp_updateState];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [self.tableView reloadData];
    } else {
        [UIView transitionWithView:self.tableView duration:PPAnimDurationNormal
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ [self.tableView reloadData]; } completion:nil];
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.tableView);
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.pp_filteredApplications.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPProviderApplicationQueueCell *cell = [tableView dequeueReusableCellWithIdentifier:PPProviderApplicationCellID forIndexPath:indexPath];
    PPProviderApplication *application = self.pp_filteredApplications[(NSUInteger)indexPath.row];
    NSString *status = PPProviderApplicationSafeString(application.status).lowercaseString;
    NSString *reference = application.applicationID.length ? application.applicationID : application.userId;
    NSDate *displayDate = application.submittedAt ?: application.createdAt ?: application.updatedAt;
    [cell configureWithTitle:PPProviderApplicationDisplayName(application)
                     subtitle:PPProviderLocalizedType(application.providerType)
                       detail:[NSString stringWithFormat:@"%@ · %@", PPProviderDateText(displayDate), PPProviderApplicationLTRIsolate(reference)]
                       status:status
                       symbol:@"person.crop.circle.badge.checkmark"];
    cell.accessibilityHint = kLang(@"Providers_ApplicationDetail_OpenHint");
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    PPProviderApplication *application = self.pp_filteredApplications[(NSUInteger)indexPath.row];
    NSString *identifier = application.applicationID.length ? application.applicationID : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedApplicationIDs containsObject:identifier]) return;
    [self.animatedApplicationIDs addObject:identifier];
    cell.contentView.alpha = 0.0;
    cell.contentView.transform = CGAffineTransformMakeTranslation(0.0, PPSpaceMD);
    [UIView animateWithDuration:PPAnimDurationNormal delay:MIN(indexPath.row, 6) * 0.025
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.contentView.alpha = 1.0;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<PPProviderApplication *> *applications = self.pp_filteredApplications;
    if (indexPath.row >= (NSInteger)applications.count) return;
    PPProviderApplication *application = applications[(NSUInteger)indexPath.row];
    PPProviderApplicationDetailViewController *detail = [[PPProviderApplicationDetailViewController alloc] initWithApplication:application
                                                                                                                    canManage:self.canManage];
    __weak typeof(self) weakSelf = self;
    __weak PPProviderApplicationDetailViewController *weakDetail = detail;
    detail.applicationDidMutate = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self pp_loadDataWithCompletion:^(NSArray<PPProviderApplication *> *applications, NSError *error) {
            if (error) return;
            for (PPProviderApplication *updatedApplication in applications) {
                if ([updatedApplication.applicationID isEqualToString:application.applicationID]) {
                    [weakDetail updateWithApplication:updatedApplication];
                    break;
                }
            }
        }];
    };
    [self.navigationController pushViewController:detail animated:YES];
}

@end
