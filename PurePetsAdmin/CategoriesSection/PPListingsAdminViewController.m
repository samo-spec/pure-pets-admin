#import "PPListingsAdminViewController.h"
#import "PPStaffAuth.h"
#import "PPHUD.h"
#import "Language.h"
#import "Styling.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;

#pragma mark - Font Helpers

static UIFont *PPListingScaled(UIFont *base, UIFontTextStyle style) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
    }
    return base;
}

static UIFont *PPListingMedium(CGFloat size, UIFontTextStyle style) {
    return PPListingScaled(PPFontMedium(size), style);
}

static UIFont *PPListingRegular(CGFloat size, UIFontTextStyle style) {
    return PPListingScaled(PPFontRegular(size), style);
}

static UIFont *PPListingBold(CGFloat size, UIFontTextStyle style) {
    return PPListingScaled(PPFontBold(size), style);
}

static BOOL PPListingsReduceMotionEnabled(void) {
    return UIAccessibilityIsReduceMotionEnabled();
}

static UIColor *PPListingsSurfaceStrokeColor(void) {
    return [PPHairlineColor() colorWithAlphaComponent:0.72];
}

static NSString *PPListingsLocalizedInteger(NSInteger value) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.locale = [NSLocale currentLocale];
    return [formatter stringFromNumber:@(value)] ?: [NSString stringWithFormat:@"%ld", (long)value];
}

static NSString *PPListingsFormattedDate(NSDate *date) {
    if (!date) { return @"—"; }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale currentLocale];
    df.dateStyle = NSDateFormatterMediumStyle;
    df.timeStyle = NSDateFormatterNoStyle;
    return [df stringFromDate:date] ?: @"—";
}

static NSString *PPListingStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if ([value isKindOfClass:NSNumber.class]) {
        return ((NSNumber *)value).stringValue ?: @"";
    }
    if ([value isKindOfClass:NSURL.class]) {
        return ((NSURL *)value).absoluteString ?: @"";
    }
    return @"";
}

static NSString *PPListingFirstString(NSDictionary *dictionary, NSArray<NSString *> *keys) {
    if (![dictionary isKindOfClass:NSDictionary.class]) { return @""; }
    for (NSString *key in keys) {
        NSString *value = PPListingStringValue(dictionary[key]);
        if (value.length > 0) { return value; }
    }
    return @"";
}

static NSString *PPListingLocationText(NSDictionary *dictionary) {
    NSString *namedLocation = PPListingFirstString(dictionary, @[@"locationName", @"cityName", @"city", @"address", @"area"]);
    if (namedLocation.length > 0) { return namedLocation; }

    id rawLocation = dictionary[@"location"];
    NSString *stringLocation = PPListingStringValue(rawLocation);
    if (stringLocation.length > 0) { return stringLocation; }

    if ([rawLocation isKindOfClass:FIRGeoPoint.class]) {
        FIRGeoPoint *point = (FIRGeoPoint *)rawLocation;
        return [NSString stringWithFormat:@"%.4f, %.4f", point.latitude, point.longitude];
    }
    return @"";
}

static NSString *PPListingsPriceText(NSString *rawPrice) {
    NSString *trimmed = [rawPrice isKindOfClass:NSString.class]
        ? [rawPrice stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
    if (trimmed.length == 0 || [trimmed isEqualToString:@"(null)"]) { return @"—"; }
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    numberFormatter.locale = [NSLocale currentLocale];
    NSNumber *number = [numberFormatter numberFromString:trimmed];
    if (!number) {
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        double scannedValue = 0.0;
        if ([scanner scanDouble:&scannedValue] && scanner.isAtEnd) {
            number = @(scannedValue);
        }
    }
    NSString *formatted = number ? ([numberFormatter stringFromNumber:number] ?: trimmed) : trimmed;
    return [NSString stringWithFormat:@"%@ %@", formatted, kLang(@"EGP") ?: @"EGP"];
}

#pragma mark - State

typedef NS_ENUM(NSInteger, PPListingsState) {
    PPListingsStateLoading = 0,
    PPListingsStateReady,
    PPListingsStateEmpty,
    PPListingsStateNoResults,
    PPListingsStateError,
};

#pragma mark - PPListingItem

typedef NSString * PPListingSource NS_TYPED_ENUM;
PPListingSource const PPListingSourceMarketplace = @"pet_ads";
PPListingSource const PPListingSourceAdoption = @"adopt_pets";

@interface PPListingItem : NSObject
@property (nonatomic, copy) NSString *documentID;
@property (nonatomic, copy) PPListingSource source;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *listingDescription;
@property (nonatomic, copy, nullable) NSString *price;
@property (nonatomic, copy, nullable) NSString *category;
@property (nonatomic, copy, nullable) NSString *subcategory;
@property (nonatomic, copy, nullable) NSString *ownerID;
@property (nonatomic, copy, nullable) NSString *ownerName;
@property (nonatomic, copy, nullable) NSString *imageUrl;
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) BOOL visibility;
@property (nonatomic, assign) BOOL isApproved;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) NSInteger viewsCount;
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
@property (nonatomic, copy, nullable) NSString *location;
@property (nonatomic, copy, nullable) NSString *petAge;

- (NSString *)statusString;
- (BOOL)isMarketplace;
- (BOOL)isActive;
- (BOOL)isPending;
@end

@implementation PPListingItem
- (BOOL)isMarketplace { return [self.source isEqualToString:PPListingSourceMarketplace]; }
- (BOOL)isActive { return self.status == 1 && self.visibility && self.isApproved; }
- (BOOL)isPending { return self.status == 0 && self.visibility == 0 && !self.isApproved; }
- (NSString *)statusString {
    switch (self.status) {
        case 0: return kLang(@"ListingsAdmin_StatusDraft");
        case 1: return kLang(@"ListingsAdmin_StatusActive");
        case 4: return kLang(@"ListingsAdmin_StatusArchived");
        case 5: return kLang(@"ListingsAdmin_StatusRejected");
        default: return kLang(@"Unknown");
    }
}
@end

#pragma mark - PPListingsHeroView

@interface PPListingsHeroView : UIView
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) UIImageView *glyphView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *statsStack;
@property (nonatomic, strong) NSArray<UILabel *> *statValueLabels;
- (void)configureWithTotal:(NSInteger)total marketplace:(NSInteger)marketplace active:(NSInteger)active pending:(NSInteger)pending adoption:(NSInteger)adoption;
@end

@implementation PPListingsHeroView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[(__bridge id)PPMaroon900Color().CGColor,
                             (__bridge id)PPMaroon600Color().CGColor,
                             (__bridge id)PPMaroon200Color().CGColor];
        _gradient.locations = @[@0.0, @0.58, @1.0];
        _gradient.startPoint = CGPointMake(0.08, 0.08);
        _gradient.endPoint = CGPointMake(0.94, 1.0);
        _gradient.cornerRadius = PPCornerHero;
        [self.layer addSublayer:_gradient];

        self.layer.shadowColor = PPDeepCharcoalColor().CGColor;
        self.layer.shadowOpacity = 0.14;
        self.layer.shadowRadius = 24.0;
        self.layer.shadowOffset = CGSizeMake(0, 14.0);

        _glyphView = [[UIImageView alloc] init];
        _glyphView.contentMode = UIViewContentModeScaleAspectFit;
        _glyphView.tintColor = [UIColor whiteColor];
        _glyphView.layer.cornerRadius = PPCornerMedium;
        _glyphView.layer.masksToBounds = YES;
        _glyphView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
        _glyphView.image = [UIImage pp_symbolNamed:@"list.bullet.clipboard"
                                          pointSize:26
                                             weight:UIImageSymbolWeightSemibold
                                              scale:UIImageSymbolScaleMedium
                                            palette:@[[UIColor whiteColor]]
                                      makeTemplate:YES];
        _glyphView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glyphView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPListingBold(PPFontTitle2, UIFontTextStyleTitle2);
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = PPListingRegular(PPFontSubheadline, UIFontTextStyleSubheadline);
        _subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.86];
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        _subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_subtitleLabel];

        _statsStack = [[UIView alloc] init];
        _statsStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_statsStack];

        [NSLayoutConstraint activateConstraints:@[
            [_glyphView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceLG],
            [_glyphView.topAnchor constraintEqualToAnchor:self.topAnchor constant:PPSpaceLG],
            [_glyphView.widthAnchor constraintEqualToConstant:PPSpace4XL],
            [_glyphView.heightAnchor constraintEqualToConstant:PPSpace4XL],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_glyphView.trailingAnchor constant:PPSpaceMD],
            [_titleLabel.topAnchor constraintEqualToAnchor:_glyphView.topAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],

            [_statsStack.leadingAnchor constraintEqualToAnchor:_glyphView.leadingAnchor],
            [_statsStack.topAnchor constraintEqualToAnchor:_glyphView.bottomAnchor constant:PPSpaceMD],
            [_statsStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],
            [_statsStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PPSpaceLG],
        ]];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitHeader;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradient.frame = self.bounds;
}

- (void)configureWithTotal:(NSInteger)total marketplace:(NSInteger)marketplace active:(NSInteger)active pending:(NSInteger)pending adoption:(NSInteger)adoption {
    [self.statsStack.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSArray *statConfigs = @[
        @{@"label": kLang(@"ListingsAdmin_Total"), @"value": PPListingsLocalizedInteger(total)},
        @{@"label": kLang(@"ListingsAdmin_Marketplace"), @"value": PPListingsLocalizedInteger(marketplace)},
        @{@"label": kLang(@"ListingsAdmin_Active"), @"value": PPListingsLocalizedInteger(active)},
        @{@"label": kLang(@"ListingsAdmin_Pending"), @"value": PPListingsLocalizedInteger(pending)},
        @{@"label": kLang(@"ListingsAdmin_Adoption"), @"value": PPListingsLocalizedInteger(adoption)},
    ];

    UIStackView *hStack = [[UIStackView alloc] init];
    hStack.axis = UILayoutConstraintAxisHorizontal;
    hStack.distribution = UIStackViewDistributionFillEqually;
    hStack.spacing = PPSpaceSM;
    hStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statsStack addSubview:hStack];

    [NSLayoutConstraint activateConstraints:@[
        [hStack.leadingAnchor constraintEqualToAnchor:self.statsStack.leadingAnchor],
        [hStack.trailingAnchor constraintEqualToAnchor:self.statsStack.trailingAnchor],
        [hStack.topAnchor constraintEqualToAnchor:self.statsStack.topAnchor],
        [hStack.bottomAnchor constraintEqualToAnchor:self.statsStack.bottomAnchor],
    ]];

    NSMutableArray *valueLabels = [NSMutableArray array];
    for (NSDictionary *config in statConfigs) {
        UIView *pill = [[UIView alloc] init];
        pill.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14];
        pill.layer.cornerRadius = PPCornerMedium;
        pill.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        pill.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22].CGColor;
        pill.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *valLabel = [[UILabel alloc] init];
        valLabel.font = PPListingBold(PPFontFootnote, UIFontTextStyleFootnote);
        valLabel.textColor = [UIColor whiteColor];
        valLabel.textAlignment = NSTextAlignmentCenter;
        valLabel.text = config[@"value"];
        valLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [pill addSubview:valLabel];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.font = PPListingRegular(PPFontCaption2, UIFontTextStyleCaption2);
        titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.text = config[@"label"];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [pill addSubview:titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [valLabel.topAnchor constraintEqualToAnchor:pill.topAnchor constant:PPSpaceXS],
            [valLabel.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:PPSpaceSM],
            [valLabel.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-PPSpaceSM],

            [titleLabel.topAnchor constraintEqualToAnchor:valLabel.bottomAnchor constant:PPSpaceXXS],
            [titleLabel.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:PPSpaceSM],
            [titleLabel.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-PPSpaceSM],
            [titleLabel.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-PPSpaceXS],
        ]];

        [hStack addArrangedSubview:pill];
        [valueLabels addObject:valLabel];
    }
    self.statValueLabels = valueLabels;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", self.titleLabel.text ?: @"", self.subtitleLabel.text ?: @""];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
}

@end

#pragma mark - PPListingCell

@interface PPListingCell : UITableViewCell
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *iconTile;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIView *mediaGradientOverlay;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UILabel *sourceBadge;
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UILabel *dateLabel;
- (void)configureWithItem:(PPListingItem *)item canManage:(BOOL)canManage;
@end

@implementation PPListingCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.contentView.layoutMargins = UIEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);

        _surfaceView = [[UIView alloc] init];
        _surfaceView.backgroundColor = PPSurfaceColor();
        _surfaceView.layer.cornerRadius = PPCornerCard;
        _surfaceView.layer.cornerCurve = kCACornerCurveContinuous;
        _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _surfaceView.layer.borderColor = PPListingsSurfaceStrokeColor().CGColor;
        _surfaceView.layer.shadowColor = PPDeepCharcoalColor().CGColor;
        _surfaceView.layer.shadowOpacity = 0.045;
        _surfaceView.layer.shadowRadius = 16.0;
        _surfaceView.layer.shadowOffset = CGSizeMake(0, 8.0);
        _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_surfaceView];

        _iconTile = [[UIView alloc] init];
        _iconTile.layer.cornerRadius = PPCornerMedium;
        _iconTile.layer.masksToBounds = YES;
        _iconTile.layer.cornerCurve = kCACornerCurveContinuous;
        _iconTile.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_iconTile];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeScaleAspectFill;
        _iconView.clipsToBounds = YES;
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconTile addSubview:_iconView];

        _mediaGradientOverlay = [[UIView alloc] init];
        _mediaGradientOverlay.userInteractionEnabled = NO;
        _mediaGradientOverlay.backgroundColor = [PPDeepCharcoalColor() colorWithAlphaComponent:0.08];
        _mediaGradientOverlay.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconTile addSubview:_mediaGradientOverlay];

        _sourceBadge = [[UILabel alloc] init];
        _sourceBadge.font = PPListingMedium(PPFontCaption2, UIFontTextStyleCaption2);
        _sourceBadge.textColor = [UIColor whiteColor];
        _sourceBadge.textAlignment = NSTextAlignmentCenter;
        _sourceBadge.layer.cornerRadius = PPSpaceXS;
        _sourceBadge.layer.masksToBounds = YES;
        _sourceBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_sourceBadge];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPListingMedium(PPFontHeadline, UIFontTextStyleHeadline);
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.numberOfLines = 2;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_titleLabel];

        _metaLabel = [[UILabel alloc] init];
        _metaLabel.font = PPListingRegular(PPFontSubheadline, UIFontTextStyleSubheadline);
        _metaLabel.textColor = UIColor.secondaryLabelColor;
        _metaLabel.numberOfLines = 2;
        _metaLabel.adjustsFontForContentSizeCategory = YES;
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_metaLabel];

        _priceLabel = [[UILabel alloc] init];
        _priceLabel.font = PPListingMedium(PPFontCallout, UIFontTextStyleCallout);
        _priceLabel.textColor = AppPrimaryClr;
        _priceLabel.numberOfLines = 1;
        _priceLabel.textAlignment = NSTextAlignmentNatural;
        _priceLabel.adjustsFontForContentSizeCategory = YES;
        _priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_priceLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = PPListingRegular(PPFontCaption1, UIFontTextStyleCaption1);
        _dateLabel.textColor = UIColor.tertiaryLabelColor;
        _dateLabel.numberOfLines = 1;
        _dateLabel.textAlignment = NSTextAlignmentNatural;
        _dateLabel.adjustsFontForContentSizeCategory = YES;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_dateLabel];

        _statusBadge = [[UILabel alloc] init];
        _statusBadge.font = PPListingMedium(PPFontCaption2, UIFontTextStyleCaption2);
        _statusBadge.textColor = [UIColor whiteColor];
        _statusBadge.textAlignment = NSTextAlignmentCenter;
        _statusBadge.layer.cornerRadius = PPSpaceXS + 2;
        _statusBadge.layer.masksToBounds = YES;
        _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_statusBadge];

        UIView *selectedBg = [[UIView alloc] init];
        selectedBg.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.10];
        selectedBg.layer.cornerRadius = PPCornerSmall;
        selectedBg.layer.masksToBounds = YES;
        self.selectedBackgroundView = selectedBg;

        UILayoutGuide *contentGuide = self.contentView.layoutMarginsGuide;
        UILayoutGuide *guide = self.surfaceView.layoutMarginsGuide;
        self.surfaceView.layoutMargins = UIEdgeInsetsMake(PPSpaceMD, PPSpaceMD, PPSpaceMD, PPSpaceMD);

        [NSLayoutConstraint activateConstraints:@[
            [_surfaceView.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:contentGuide.bottomAnchor],

            [_iconTile.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_iconTile.topAnchor constraintEqualToAnchor:guide.topAnchor],
            [_iconTile.widthAnchor constraintEqualToConstant:74.0],
            [_iconTile.heightAnchor constraintEqualToConstant:74.0],
            [_iconTile.bottomAnchor constraintLessThanOrEqualToAnchor:guide.bottomAnchor],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconTile.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconTile.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToAnchor:_iconTile.widthAnchor],
            [_iconView.heightAnchor constraintEqualToAnchor:_iconTile.heightAnchor],

            [_mediaGradientOverlay.leadingAnchor constraintEqualToAnchor:_iconTile.leadingAnchor],
            [_mediaGradientOverlay.trailingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor],
            [_mediaGradientOverlay.topAnchor constraintEqualToAnchor:_iconTile.topAnchor],
            [_mediaGradientOverlay.bottomAnchor constraintEqualToAnchor:_iconTile.bottomAnchor],

            [_sourceBadge.centerXAnchor constraintEqualToAnchor:_iconTile.centerXAnchor],
            [_sourceBadge.bottomAnchor constraintEqualToAnchor:_iconTile.bottomAnchor constant:-PPSpaceXS],
            [_sourceBadge.heightAnchor constraintEqualToConstant:PPSpaceLG],
            [_sourceBadge.widthAnchor constraintLessThanOrEqualToAnchor:_iconTile.widthAnchor constant:-PPSpaceSM],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor constant:PPSpaceMD],
            [_titleLabel.topAnchor constraintEqualToAnchor:_iconTile.topAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_priceLabel.leadingAnchor constant:-PPSpaceSM],

            [_priceLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [_priceLabel.topAnchor constraintEqualToAnchor:_titleLabel.topAnchor],
            [_priceLabel.widthAnchor constraintGreaterThanOrEqualToConstant:60],

            [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:_dateLabel.leadingAnchor constant:-PPSpaceSM],
            [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXXS],

            [_dateLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [_dateLabel.topAnchor constraintEqualToAnchor:_metaLabel.topAnchor],

            [_statusBadge.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_statusBadge.topAnchor constraintGreaterThanOrEqualToAnchor:_metaLabel.bottomAnchor constant:PPSpaceXS],
            [_statusBadge.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
            [_statusBadge.heightAnchor constraintEqualToConstant:PPSpaceLG + 2],
        ]];

        [_priceLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                      forAxis:UILayoutConstraintAxisHorizontal];
        [_dateLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                     forAxis:UILayoutConstraintAxisHorizontal];
        [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                      forAxis:UILayoutConstraintAxisHorizontal];
    }
    return self;
}

- (void)configureWithItem:(PPListingItem *)item canManage:(BOOL)canManage {
    self.titleLabel.text = item.title ?: kLang(@"Unknown");
    self.titleLabel.textColor = item.isBlocked ? PPDisabledContentColor() : PPTextPrimaryColor();
    self.surfaceView.backgroundColor = item.isBlocked ? [PPSurfaceColor() colorWithAlphaComponent:0.72] : PPSurfaceColor();
    self.surfaceView.layer.borderColor = (item.isBlocked ? [PPCriticalColor() colorWithAlphaComponent:0.28] : PPListingsSurfaceStrokeColor()).CGColor;

    UIColor *sourceColor = item.isMarketplace ? PPPrimaryColor() : PPSecondaryAccentColor();
    self.sourceBadge.text = item.isMarketplace ? kLang(@"ListingsAdmin_Marketplace") : kLang(@"ListingsAdmin_Adoption");
    self.sourceBadge.backgroundColor = [sourceColor colorWithAlphaComponent:0.92];
    self.sourceBadge.textColor = UIColor.whiteColor;

    self.iconTile.backgroundColor = [sourceColor colorWithAlphaComponent:0.12];
    UIImage *placeholder = [UIImage systemImageNamed:item.isMarketplace ? @"bag" : @"heart"];
    self.iconView.image = placeholder;
    self.iconView.tintColor = sourceColor;
    self.iconView.contentMode = UIViewContentModeCenter;
    self.mediaGradientOverlay.hidden = YES;

    if (item.imageUrl.length > 0) {
        [self.iconView setImageFromUrl:item.imageUrl placeholderImage:nil completion:nil];
        self.iconView.contentMode = UIViewContentModeScaleAspectFill;
        self.mediaGradientOverlay.hidden = NO;
    }

    NSString *owner = item.ownerName ?: item.ownerID ?: kLang(@"Unknown");
    NSString *location = item.location.length > 0 ? item.location : nil;
    self.metaLabel.text = location.length > 0 ? [NSString stringWithFormat:@"%@ · %@", owner, location] : owner;

    self.priceLabel.text = PPListingsPriceText(item.price);

    self.dateLabel.text = PPListingsFormattedDate(item.updatedAt ?: item.createdAt);

    UIColor *statusColor = UIColor.systemGrayColor;
    NSString *statusText = item.statusString;
    if (item.status == 1 && item.isApproved) {
        statusColor = UIColor.systemGreenColor;
    } else if (item.status == 5) {
        statusColor = UIColor.systemRedColor;
    } else if (item.status == 4) {
        statusColor = UIColor.systemOrangeColor;
    } else if (item.status == 0) {
        statusColor = UIColor.systemYellowColor;
    }
    if (item.isBlocked) {
        statusColor = UIColor.systemRedColor;
        statusText = kLang(@"Blocked");
    }
    self.statusBadge.text = statusText;
    self.statusBadge.textColor = statusColor;
    self.statusBadge.backgroundColor = [statusColor colorWithAlphaComponent:0.14];

    self.accessoryType = canManage ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    self.titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.metaLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.priceLabel.textAlignment = NSTextAlignmentNatural;
    self.dateLabel.textAlignment = NSTextAlignmentNatural;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = canManage ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    self.accessibilityLabel = [@[self.titleLabel.text ?: @"",
                                 self.priceLabel.text ?: @"",
                                 self.metaLabel.text ?: @"",
                                 self.statusBadge.text ?: @"",
                                 self.dateLabel.text ?: @""] componentsJoinedByString:@", "];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (PPListingsReduceMotionEnabled()) { return; }
    [UIView animateWithDuration:PPAnimDurationFast delay:0
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.surfaceView.transform = highlighted ? CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown)
                                             : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - PPListingsAdminViewController

static NSString *const kListingCellID = @"PPListingCell";

@interface PPListingsAdminViewController ()
@property (nonatomic, strong) NSArray<PPListingItem *> *listings;
@property (nonatomic, strong) NSArray<PPListingItem *> *filteredListings;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL canView;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL canModerate;
@property (nonatomic, assign) PPListingsState state;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) id marketplaceListener;
@property (nonatomic, strong) id adoptionListener;
@property (nonatomic, strong) PPListingsHeroView *heroView;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UIView *loadingView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIView *noResultsView;
@property (nonatomic, strong) UIView *errorView;
@end

@implementation PPListingsAdminViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    [self setupNavigation];
    [self setupTableView];
    [self setupHero];
    [self setupStateViews];
    [self evaluatePermissions];
    [self startListening];
}

#pragma mark - Setup

- (void)setupNavigation {
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.title = kLang(@"ListingsAdmin_Title");
}

- (void)setupTableView {
    [self.tableView registerClass:[PPListingCell class] forCellReuseIdentifier:kListingCellID];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL + PPSpaceLG;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.accessibilityIdentifier = @"ListingsTable";
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceSM, 0, PPSpace4XL, 0);

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = kLang(@"SearchHere");
    self.searchController.searchBar.tintColor = AppPrimaryClr;
    if (@available(iOS 13.0, *)) {
        self.searchController.searchBar.searchTextField.font = PPListingRegular(PPFontBody, UIFontTextStyleBody);
        self.searchController.searchBar.searchTextField.adjustsFontForContentSizeCategory = YES;
    }
    self.searchController.searchBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)setupHero {
    self.heroView = [[PPListingsHeroView alloc] initWithFrame:CGRectMake(PPSpaceBase, PPSpaceMD, self.view.bounds.size.width - (PPSpaceBase * 2.0), 220)];
    self.heroView.titleLabel.text = kLang(@"ListingsAdmin_Title");
    self.heroView.subtitleLabel.text = kLang(@"ListingsAdmin_HeroSubtitle") ?: kLang(@"ListingsAdmin_Source");
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 244.0)];
    header.backgroundColor = UIColor.clearColor;
    self.heroView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.heroView];
    self.tableView.tableHeaderView = header;
    [self updateHero];
}

- (void)setupStateViews {
    self.stateView = [[UIView alloc] init];
    self.stateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateView.hidden = YES;
    [self.view addSubview:self.stateView];

    [NSLayoutConstraint activateConstraints:@[
        [self.stateView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.stateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stateView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self buildLoadingView];
    [self buildEmptyView];
    [self buildNoResultsView];
    [self buildErrorView];
}

- (void)buildLoadingView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = AppPrimaryClr;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [container addSubview:spinner];

    UILabel *label = [[UILabel alloc] init];
    label.font = PPListingMedium(PPFontSubheadline, UIFontTextStyleSubheadline);
    label.textColor = UIColor.secondaryLabelColor;
    label.text = kLang(@"Loading");
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontForContentSizeCategory = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [spinner.topAnchor constraintEqualToAnchor:container.topAnchor],
        [spinner.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:PPSpaceMD],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    self.loadingView = container;
}

- (void)buildEmptyView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"list.bullet.clipboard" tint:[AppPrimaryClr colorWithAlphaComponent:0.16] glyphTint:AppPrimaryClr];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"ListingsAdmin_NoListings");
    [container addSubview:title];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [title.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    self.emptyView = container;
}

- (void)buildNoResultsView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"magnifyingglass" tint:[[UIColor tertiaryLabelColor] colorWithAlphaComponent:0.16] glyphTint:UIColor.tertiaryLabelColor];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"ListingsAdmin_NoListings");
    [container addSubview:title];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [title.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    self.noResultsView = container;
}

- (void)buildErrorView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"exclamationmark.triangle" tint:[[UIColor systemRedColor] colorWithAlphaComponent:0.14] glyphTint:[UIColor systemRedColor]];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"Error_Title");
    [container addSubview:title];

    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    retry.translatesAutoresizingMaskIntoConstraints = NO;
    retry.backgroundColor = AppPrimaryClr;
    retry.tintColor = [UIColor whiteColor];
    retry.titleLabel.font = PPListingMedium(PPFontHeadline, UIFontTextStyleHeadline);
    [retry setTitle:kLang(@"TryAgain") forState:UIControlStateNormal];
    retry.layer.cornerRadius = PPCornerMedium;
    retry.layer.masksToBounds = YES;
    retry.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceXL, PPSpaceMD, PPSpaceXL);
    [retry addTarget:self action:@selector(didTapRetry) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:retry];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [retry.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceLG],
        [retry.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [retry.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    self.errorView = container;
}

- (UIView *)stateGlyphWithName:(NSString *)name tint:(UIColor *)tint glyphTint:(UIColor *)glyphTint {
    UIView *circle = [[UIView alloc] init];
    circle.translatesAutoresizingMaskIntoConstraints = NO;
    circle.backgroundColor = tint;
    circle.layer.cornerRadius = (PPSpace4XL + PPSpaceXL) / 2.0;
    circle.layer.masksToBounds = YES;

    UIImageView *iv = [[UIImageView alloc] init];
    iv.contentMode = UIViewContentModeCenter;
    iv.tintColor = glyphTint;
    iv.image = [UIImage pp_symbolNamed:name
                              pointSize:34
                                 weight:UIImageSymbolWeightSemibold
                                  scale:UIImageSymbolScaleMedium
                                palette:@[glyphTint]
                          makeTemplate:YES];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [circle addSubview:iv];

    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:40],
        [iv.heightAnchor constraintEqualToConstant:40],
    ]];
    return circle;
}

- (UILabel *)stateTitleLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = PPListingBold(PPFontTitle3, UIFontTextStyleTitle3);
    label.textColor = UIColor.labelColor;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontForContentSizeCategory = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

#pragma mark - Permissions

- (void)evaluatePermissions {
    self.canView = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermListingsView];
    self.canManage = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermListingsManage];
    self.canModerate = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermListingsModerate];
    if (!self.canView && !self.canManage && !self.canModerate) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - Listeners

- (void)startListening {
    self.state = PPListingsStateLoading;
    [self refreshStateVisibility];
    [self startMarketplaceListener];
    [self startAdoptionListener];
}

- (void)startMarketplaceListener {
    PPweakify(self);
    FIRQuery *query = [[[[FIRFirestore firestore] collectionWithPath:PPListingSourceMarketplace]
                         queryOrderedByField:@"updatedAt" descending:YES]
                        queryLimitedTo:350];
    self.marketplaceListener = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        PPstrongify(self);
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
            self.state = PPListingsStateError;
            [self refreshStateVisibility];
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPListingItem *item = [self marketplaceItemFromDoc:doc];
            if (item) [items addObject:item];
        }
        [self mergeAndReloadWithMarketplace:items.copy adoption:self.filteredListingsForAdoptionOnly];
    }];
}

- (void)startAdoptionListener {
    PPweakify(self);
    FIRQuery *query = [[[[FIRFirestore firestore] collectionWithPath:PPListingSourceAdoption]
                         queryOrderedByField:@"createdAt" descending:YES]
                        queryLimitedTo:350];
    self.adoptionListener = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        PPstrongify(self);
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPListingItem *item = [self adoptionItemFromDoc:doc];
            if (item) [items addObject:item];
        }
        [self mergeAndReloadWithMarketplace:self.filteredListingsForMarketplaceOnly adoption:items.copy];
    }];
}

- (NSArray<PPListingItem *> *)filteredListingsForMarketplaceOnly {
    NSMutableArray *result = [NSMutableArray array];
    for (PPListingItem *item in self.listings) {
        if (item.isMarketplace) [result addObject:item];
    }
    return result.copy;
}

- (NSArray<PPListingItem *> *)filteredListingsForAdoptionOnly {
    NSMutableArray *result = [NSMutableArray array];
    for (PPListingItem *item in self.listings) {
        if (!item.isMarketplace) [result addObject:item];
    }
    return result.copy;
}

- (void)mergeAndReloadWithMarketplace:(NSArray<PPListingItem *> *)marketplace adoption:(NSArray<PPListingItem *> *)adoption {
    NSMutableArray *merged = [NSMutableArray array];
    [merged addObjectsFromArray:marketplace];
    [merged addObjectsFromArray:adoption];
    [merged sortUsingComparator:^NSComparisonResult(PPListingItem *a, PPListingItem *b) {
        NSDate *dateA = a.updatedAt ?: a.createdAt ?: [NSDate distantPast];
        NSDate *dateB = b.updatedAt ?: b.createdAt ?: [NSDate distantPast];
        return [dateB compare:dateA];
    }];
    self.listings = merged.copy;
    [self applyFilter];
}

- (PPListingItem *)marketplaceItemFromDoc:(FIRDocumentSnapshot *)doc {
    NSDictionary *data = doc.data;
    if (!data) return nil;
    PPListingItem *item = [[PPListingItem alloc] init];
    item.documentID = PPListingStringValue(doc.documentID);
    item.source = PPListingSourceMarketplace;
    item.title = PPListingFirstString(data, @[@"adTitle", @"title", @"name"]);
    item.listingDescription = PPListingStringValue(data[@"desc"]);
    item.price = PPListingStringValue(data[@"price"]);
    item.category = PPListingStringValue(data[@"category"]);
    item.subcategory = PPListingStringValue(data[@"subcategory"]);
    item.ownerID = PPListingStringValue(data[@"ownerID"]);
    item.ownerName = PPListingStringValue(data[@"ownerName"]);
    item.imageUrl = PPListingFirstString(data, @[@"imageUrl", @"imageURL"]);
    item.status = [data[@"status"] integerValue];
    item.visibility = [data[@"visibility"] boolValue];
    item.isApproved = [data[@"isApproved"] boolValue];
    item.isBlocked = [data[@"isBlocked"] boolValue];
    item.viewsCount = [data[@"viewsCount"] integerValue];
    item.location = PPListingLocationText(data);
    item.petAge = PPListingStringValue(data[@"petAge"]);
    item.createdAt = [data[@"createdAt"] isKindOfClass:[FIRTimestamp class]] ? [(FIRTimestamp *)data[@"createdAt"] dateValue] : nil;
    item.updatedAt = [data[@"updatedAt"] isKindOfClass:[FIRTimestamp class]] ? [(FIRTimestamp *)data[@"updatedAt"] dateValue] : nil;
    return item;
}

- (PPListingItem *)adoptionItemFromDoc:(FIRDocumentSnapshot *)doc {
    NSDictionary *data = doc.data;
    if (!data) return nil;
    PPListingItem *item = [[PPListingItem alloc] init];
    item.documentID = PPListingStringValue(doc.documentID);
    item.source = PPListingSourceAdoption;
    item.title = PPListingFirstString(data, @[@"name", @"title"]);
    item.listingDescription = PPListingStringValue(data[@"details"]);
    item.price = PPListingStringValue(data[@"price"]);
    item.category = PPListingStringValue(data[@"kindID"]);
    item.ownerID = PPListingStringValue(data[@"ownerID"]);
    item.ownerName = PPListingStringValue(data[@"ownerName"]);
    item.location = PPListingLocationText(data);
    NSArray *imageURLs = [data[@"imageURLsArray"] isKindOfClass:NSArray.class] ? data[@"imageURLsArray"] : @[];
    item.imageUrl = PPListingStringValue(imageURLs.firstObject);
    item.isBlocked = [data[@"isBlocked"] boolValue];
    item.createdAt = [data[@"createdAt"] isKindOfClass:[FIRTimestamp class]] ? [(FIRTimestamp *)data[@"createdAt"] dateValue] : nil;
    item.updatedAt = item.createdAt;
    item.status = 1;
    item.visibility = YES;
    item.isApproved = YES;
    return item;
}

- (void)didTapRetry {
    [self.marketplaceListener remove]; self.marketplaceListener = nil;
    [self.adoptionListener remove]; self.adoptionListener = nil;
    [self startListening];
}

#pragma mark - Filtering

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text;
    if (query.length == 0) {
        self.filteredListings = self.listings;
    } else {
        NSString *q = query.lowercaseString;
        NSMutableArray *filtered = [NSMutableArray array];
        for (PPListingItem *item in self.listings) {
            NSString *title = item.title.lowercaseString ?: @"";
            NSString *owner = item.ownerName.lowercaseString ?: item.ownerID.lowercaseString ?: @"";
            NSString *category = item.category.lowercaseString ?: @"";
            if ([title containsString:q] || [owner containsString:q] || [category containsString:q]) {
                [filtered addObject:item];
            }
        }
        self.filteredListings = filtered.copy;
    }
    [self updateHero];
    [self refreshStateVisibility];
    [self.tableView reloadData];
}

- (void)updateHero {
    NSInteger total = self.listings.count;
    NSInteger marketplace = 0;
    NSInteger active = 0;
    NSInteger pending = 0;
    NSInteger adoption = 0;
    for (PPListingItem *item in self.filteredListings) {
        if (item.isMarketplace) marketplace++;
        else adoption++;
        if (item.isActive) active++;
        if (item.isPending) pending++;
    }
    [self.heroView configureWithTotal:total marketplace:marketplace active:active pending:pending adoption:adoption];
}

- (void)refreshStateVisibility {
    if (self.listings.count == 0) {
        self.state = PPListingsStateEmpty;
    } else if (self.filteredListings.count == 0) {
        self.state = PPListingsStateNoResults;
    } else {
        self.state = PPListingsStateReady;
    }
    BOOL ready = (self.state == PPListingsStateReady);
    self.tableView.hidden = !ready;
    self.stateView.hidden = ready;
    self.loadingView.hidden = (self.state != PPListingsStateLoading);
    self.emptyView.hidden = (self.state != PPListingsStateEmpty);
    self.noResultsView.hidden = (self.state != PPListingsStateNoResults);
    self.errorView.hidden = (self.state != PPListingsStateError);
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredListings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPListingCell *cell = [tableView dequeueReusableCellWithIdentifier:kListingCellID forIndexPath:indexPath];
    PPListingItem *item = self.filteredListings[indexPath.row];
    [cell configureWithItem:item canManage:self.canManage];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.canManage || self.canModerate;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPListingItem *item = self.filteredListings[indexPath.row];
    if (!self.canManage && !self.canModerate) return nil;
    if (!item.isMarketplace) return nil;

    NSMutableArray *actions = [NSMutableArray array];

    if (self.canModerate && item.status != 1) {
        UIContextualAction *approve = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                              title:kLang(@"ListingsAdmin_Approve")
                                                                            handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self approveListing:item];
            completionHandler(YES);
        }];
        approve.backgroundColor = [UIColor systemGreenColor];
        [actions addObject:approve];
    }

    if (self.canModerate && item.status != 5) {
        UIContextualAction *reject = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                             title:kLang(@"ListingsAdmin_Reject")
                                                                           handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self rejectListing:item];
            completionHandler(YES);
        }];
        reject.backgroundColor = [UIColor systemRedColor];
        [actions addObject:reject];
    }

    if (self.canManage && item.status != 4) {
        UIContextualAction *archive = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                              title:kLang(@"ListingsAdmin_Archive")
                                                                            handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
            [self archiveListing:item];
            completionHandler(YES);
        }];
        archive.backgroundColor = [UIColor systemOrangeColor];
        [actions addObject:archive];
    }

    if (actions.count == 0) return nil;
    return [UISwipeActionsConfiguration configurationWithActions:actions.copy];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PPListingItem *item = self.filteredListings[indexPath.row];
    [self showDetailForItem:item];
}

#pragma mark - Actions

- (void)approveListing:(PPListingItem *)item {
    if (!item.isMarketplace) return;
    [[[[FIRFirestore firestore] collectionWithPath:PPListingSourceMarketplace] documentWithPath:item.documentID]
     updateData:@{
        @"status": @1,
        @"visibility": @1,
        @"isApproved": @YES,
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"ListingsAdmin_Approve")];
            [self writeAuditLog:@"approve_listing" item:item];
        }
    }];
}

- (void)rejectListing:(PPListingItem *)item {
    if (!item.isMarketplace) return;
    [[[[FIRFirestore firestore] collectionWithPath:PPListingSourceMarketplace] documentWithPath:item.documentID]
     updateData:@{
        @"status": @5,
        @"isApproved": @NO,
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"ListingsAdmin_Reject")];
            [self writeAuditLog:@"reject_listing" item:item];
        }
    }];
}

- (void)archiveListing:(PPListingItem *)item {
    if (!item.isMarketplace) return;
    [[[[FIRFirestore firestore] collectionWithPath:PPListingSourceMarketplace] documentWithPath:item.documentID]
     updateData:@{
        @"status": @4,
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"ListingsAdmin_Archive")];
            [self writeAuditLog:@"archive_listing" item:item];
        }
    }];
}

- (void)showDetailForItem:(PPListingItem *)item {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:item.title
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *detailMessage = [NSString stringWithFormat:kLang(@"ListingsAdmin_Source"), item.isMarketplace ? kLang(@"ListingsAdmin_Marketplace") : kLang(@"ListingsAdmin_Adoption")];
    if (item.ownerName.length > 0) {
        detailMessage = [detailMessage stringByAppendingFormat:@"\n%@: %@", kLang(@"User"), item.ownerName];
    }
    if (item.price.length > 0) {
        detailMessage = [detailMessage stringByAppendingFormat:@"\n%@: %@ %@", kLang(@"Price"), item.price, kLang(@"EGP")];
    }
    if (item.category.length > 0) {
        detailMessage = [detailMessage stringByAppendingFormat:@"\n%@: %@", kLang(@"PaymentMgmt_Field_Category"), item.category];
    }
    if (item.location.length > 0) {
        detailMessage = [detailMessage stringByAppendingFormat:@"\n%@: %@", kLang(@"Branches_Address"), item.location];
    }
    detailMessage = [detailMessage stringByAppendingFormat:@"\n%@: %@", kLang(@"Account_Status"), item.statusString];
    if (item.viewsCount > 0) {
        detailMessage = [detailMessage stringByAppendingFormat:@"\n%@: %ld", kLang(@"ListingsAdmin_Views"), (long)item.viewsCount];
    }
    alert.message = detailMessage;

    if (self.canModerate && item.isMarketplace && item.status != 1) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"ListingsAdmin_Approve") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self approveListing:item];
        }]];
    }
    if (self.canModerate && item.isMarketplace && item.status != 5) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"ListingsAdmin_Reject") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self rejectListing:item];
        }]];
    }
    if (self.canManage && item.isMarketplace && item.status != 4) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"ListingsAdmin_Archive") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self archiveListing:item];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.tableView;
        alert.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[self.tableView indexPathForSelectedRow] ?: [NSIndexPath indexPathForRow:0 inSection:0]];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)writeAuditLog:(NSString *)action item:(PPListingItem *)item {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
     setData:@{
        @"action": action ?: @"",
        @"targetCollection": item.source ?: @"",
        @"targetId": item.documentID ?: @"",
        @"adminUid": uid,
        @"details": @{
            @"title": item.title ?: @"",
            @"source": item.source ?: @"",
        },
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter];
}

#pragma mark - Entrance Animation

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self runEntranceIfNeeded];
}

- (void)runEntranceIfNeeded {
    if (self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;

    if (PPListingsReduceMotionEnabled()) {
        self.heroView.alpha = 1.0;
        self.heroView.transform = CGAffineTransformIdentity;
        return;
    }

    self.heroView.alpha = 0;
    self.heroView.transform = CGAffineTransformMakeTranslation(0, 16);

    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.heroView.alpha = 1;
        self.heroView.transform = CGAffineTransformIdentity;
    } completion:nil];

    [self.tableView.visibleCells enumerateObjectsUsingBlock:^(UITableViewCell *cell, NSUInteger idx, BOOL *stop) {
        cell.alpha = 0;
        cell.transform = CGAffineTransformMakeTranslation(0, 12);
        [UIView animateWithDuration:0.36 delay:0.06 + idx * 0.045 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.heroView) {
        CGFloat width = MAX(0.0, self.tableView.bounds.size.width - (PPSpaceBase * 2.0));
        CGSize size = [self.heroView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                    withHorizontalFittingPriority:UILayoutPriorityRequired
                                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        CGFloat targetHeight = MAX(220.0, size.height);
        UIView *header = self.tableView.tableHeaderView;
        if (fabs(self.heroView.frame.size.width - width) > 0.5 || fabs(self.heroView.frame.size.height - targetHeight) > 0.5) {
            self.heroView.frame = CGRectMake(PPSpaceBase, PPSpaceMD, width, targetHeight);
            header.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, targetHeight + (PPSpaceMD * 2.0));
            self.tableView.tableHeaderView = header;
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self.tableView reloadData];
}

#pragma mark - Cleanup

- (void)dealloc {
    [self.marketplaceListener remove];
    [self.adoptionListener remove];
}

@end
