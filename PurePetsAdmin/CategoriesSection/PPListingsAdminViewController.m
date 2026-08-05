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

/// Gold-ink for stats and needs-review signals (matches the Console gold ops language).
static UIColor *PPListingsOpsGold(void) {
    return PPDynamicColor(0x8A5F14, 0xE3B878, 1.0, 1.0);
}

/// Needs-review hairline (gold at a quiet alpha).
static UIColor *PPListingsNeedsReviewStroke(void) {
    return PPDynamicColor(0xD7A45C, 0xD7A45C, 0.55, 0.50);
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

#pragma mark - Status Style

typedef struct {
    UIColor *__unsafe_unretained background;
    UIColor *__unsafe_unretained foreground;
} PPListingsStatusStyle;

static PPListingsStatusStyle PPListingsStatusStyleForStatus(NSInteger status, BOOL blocked) {
    PPListingsStatusStyle style;
    if (blocked || status == 5) {
        style.background = PPDynamicColor(0xFBEAEA, 0x3A1C1C, 1.0, 1.0);
        style.foreground = PPDynamicColor(0xC62828, 0xF0A3A3, 1.0, 1.0);
    } else if (status == 1) {
        style.background = PPDynamicColor(0xE7F3EA, 0x16301E, 1.0, 1.0);
        style.foreground = PPDynamicColor(0x1E7A34, 0x8FD6A5, 1.0, 1.0);
    } else if (status == 4) {
        style.background = PPDynamicColor(0xFFEFD9, 0x382A14, 1.0, 1.0);
        style.foreground = PPDynamicColor(0xB35C00, 0xF5B158, 1.0, 1.0);
    } else if (status == 0) {
        style.background = PPDynamicColor(0xF7EDDC, 0x33291A, 1.0, 1.0);
        style.foreground = PPListingsOpsGold();
    } else {
        style.background = PPDynamicColor(0xEEEEEF, 0x2C2C2E, 1.0, 1.0);
        style.foreground = PPDynamicColor(0x5A5A5E, 0xBDBDC2, 1.0, 1.0);
    }
    return style;
}

#pragma mark - State

typedef NS_ENUM(NSInteger, PPListingsState) {
    PPListingsStateLoading = 0,
    PPListingsStateReady,
    PPListingsStateEmpty,
    PPListingsStateNoResults,
    PPListingsStateError,
};

typedef NS_ENUM(NSInteger, PPListingsRailFilter) {
    PPListingsRailFilterAll = 0,
    PPListingsRailFilterPending,
    PPListingsRailFilterActive,
    PPListingsRailFilterArchived,
    PPListingsRailFilterRejected,
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
- (BOOL)matchesRailFilter:(PPListingsRailFilter)filter;
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
- (BOOL)matchesRailFilter:(PPListingsRailFilter)filter {
    switch (filter) {
        case PPListingsRailFilterAll:      return YES;
        case PPListingsRailFilterPending:  return self.status == 0;
        case PPListingsRailFilterActive:   return self.status == 1;
        case PPListingsRailFilterArchived: return self.status == 4;
        case PPListingsRailFilterRejected: return self.status == 5;
    }
    return YES;
}
@end

#pragma mark - PPListingsSummaryBar

@interface PPListingsSummaryBar : UIView
@property (nonatomic, strong) UILabel *totalValueLabel;
@property (nonatomic, strong) UILabel *pendingValueLabel;
@property (nonatomic, strong) UILabel *activeValueLabel;
@property (nonatomic, strong) UILabel *adoptionValueLabel;
- (void)configureWithTotal:(NSInteger)total marketplace:(NSInteger)marketplace active:(NSInteger)active pending:(NSInteger)pending adoption:(NSInteger)adoption;
@end

@implementation PPListingsSummaryBar {
    NSInteger _lastPendingValue;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = PPSurfaceColor();
        self.layer.cornerRadius = PPCornerCard;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = PPListingsSurfaceStrokeColor().CGColor;
        _lastPendingValue = NSNotFound;

        // Maroon leading accent stripe
        UIView *accentStripe = [[UIView alloc] init];
        accentStripe.backgroundColor = PPMaroon600Color();
        accentStripe.layer.cornerRadius = 2.0;
        accentStripe.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:accentStripe];

        // Horizontal stack for stat columns
        UIStackView *hStack = [[UIStackView alloc] init];
        hStack.axis = UILayoutConstraintAxisHorizontal;
        hStack.distribution = UIStackViewDistributionFillEqually;
        hStack.alignment = UIStackViewAlignmentFill;
        hStack.spacing = 0;
        hStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        hStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:hStack];

        [NSLayoutConstraint activateConstraints:@[
            [accentStripe.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceXS],
            [accentStripe.topAnchor constraintEqualToAnchor:self.topAnchor constant:PPSpaceSM],
            [accentStripe.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PPSpaceSM],
            [accentStripe.widthAnchor constraintEqualToConstant:4.0],

            [hStack.leadingAnchor constraintEqualToAnchor:accentStripe.trailingAnchor constant:PPSpaceSM],
            [hStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-PPSpaceSM],
            [hStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:PPSpaceMD],
            [hStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PPSpaceMD],
        ]];

        NSArray *configs = @[
            @{@"label": kLang(@"ListingsAdmin_Total"), @"style": @"ink"},
            @{@"label": kLang(@"ListingsAdmin_Pending"), @"style": @"gold"},
            @{@"label": kLang(@"ListingsAdmin_Active") ?: @"Active", @"style": @"green"},
            @{@"label": kLang(@"ListingsAdmin_Adoption"), @"style": @"ink"},
        ];

        for (NSInteger i = 0; i < configs.count; i++) {
            NSDictionary *config = configs[i];

            UIView *column = [[UIView alloc] init];
            column.translatesAutoresizingMaskIntoConstraints = NO;

            UILabel *valueLabel = [[UILabel alloc] init];
            valueLabel.font = PPListingBold(PPFontHeadline, UIFontTextStyleHeadline);
            if ([config[@"style"] isEqualToString:@"gold"]) {
                valueLabel.textColor = PPListingsOpsGold();
            } else if ([config[@"style"] isEqualToString:@"green"]) {
                valueLabel.textColor = PPDynamicColor(0x1E7A34, 0x8FD6A5, 1.0, 1.0);
            } else {
                valueLabel.textColor = PPTextPrimaryColor();
            }
            valueLabel.textAlignment = NSTextAlignmentCenter;
            valueLabel.adjustsFontForContentSizeCategory = YES;
            valueLabel.numberOfLines = 1;
            valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [column addSubview:valueLabel];

            UILabel *label = [[UILabel alloc] init];
            label.font = PPListingRegular(PPFontCaption2, UIFontTextStyleCaption2);
            label.textColor = PPTextTertiaryColor();
            label.textAlignment = NSTextAlignmentCenter;
            label.adjustsFontForContentSizeCategory = YES;
            label.numberOfLines = 1;
            label.text = config[@"label"];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [column addSubview:label];

            [NSLayoutConstraint activateConstraints:@[
                [valueLabel.topAnchor constraintEqualToAnchor:column.topAnchor],
                [valueLabel.leadingAnchor constraintEqualToAnchor:column.leadingAnchor constant:PPSpaceXXS],
                [valueLabel.trailingAnchor constraintEqualToAnchor:column.trailingAnchor constant:-PPSpaceXXS],

                [label.topAnchor constraintEqualToAnchor:valueLabel.bottomAnchor constant:PPSpaceXXS],
                [label.leadingAnchor constraintEqualToAnchor:column.leadingAnchor constant:PPSpaceXXS],
                [label.trailingAnchor constraintEqualToAnchor:column.trailingAnchor constant:-PPSpaceXXS],
                [label.bottomAnchor constraintEqualToAnchor:column.bottomAnchor],
            ]];

            [hStack addArrangedSubview:column];

            // Dividers between columns
            if (i > 0) {
                UIView *divider = [[UIView alloc] init];
                divider.backgroundColor = PPHairlineColor();
                divider.translatesAutoresizingMaskIntoConstraints = NO;
                [self addSubview:divider];
                [NSLayoutConstraint activateConstraints:@[
                    [divider.centerXAnchor constraintEqualToAnchor:column.leadingAnchor],
                    [divider.topAnchor constraintEqualToAnchor:self.topAnchor constant:PPSpaceMD],
                    [divider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PPSpaceMD],
                    [divider.widthAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
                ]];
            }

            if (i == 0) self.totalValueLabel = valueLabel;
            if (i == 1) self.pendingValueLabel = valueLabel;
            if (i == 2) self.activeValueLabel = valueLabel;
            if (i == 3) self.adoptionValueLabel = valueLabel;
        }

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitHeader;
    }
    return self;
}

- (void)configureWithTotal:(NSInteger)total marketplace:(NSInteger)marketplace active:(NSInteger)active pending:(NSInteger)pending adoption:(NSInteger)adoption {
    (void)marketplace;
    self.totalValueLabel.text = PPListingsLocalizedInteger(total);
    self.activeValueLabel.text = PPListingsLocalizedInteger(active);
    self.adoptionValueLabel.text = PPListingsLocalizedInteger(adoption);
    self.pendingValueLabel.text = PPListingsLocalizedInteger(pending);

    // Animate pending value change
    if (_lastPendingValue != NSNotFound && _lastPendingValue != pending && !PPListingsReduceMotionEnabled() && self.pendingValueLabel) {
        self.pendingValueLabel.transform = CGAffineTransformMakeScale(1.18, 1.18);
        self.pendingValueLabel.alpha = 0.4;
        [UIView animateWithDuration:0.45 delay:0.05
             usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.pendingValueLabel.transform = CGAffineTransformIdentity;
            self.pendingValueLabel.alpha = 1.0;
        } completion:nil];
    }
    _lastPendingValue = pending;

    self.accessibilityLabel = [NSString stringWithFormat:@"%@: %@, %@: %@, %@: %@, %@: %@",
                               kLang(@"ListingsAdmin_Total"), PPListingsLocalizedInteger(total),
                               kLang(@"ListingsAdmin_Pending"), PPListingsLocalizedInteger(pending),
                               kLang(@"ListingsAdmin_Active") ?: @"Active", PPListingsLocalizedInteger(active),
                               kLang(@"ListingsAdmin_Adoption"), PPListingsLocalizedInteger(adoption)];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    self.layer.borderColor = PPListingsSurfaceStrokeColor().CGColor;
}

@end

#pragma mark - PPListingsRailView

@interface PPListingsRailView : UIView
@property (nonatomic, copy) void (^onSelectFilter)(PPListingsRailFilter filter);
@property (nonatomic, assign) PPListingsRailFilter selectedFilter;
- (void)setCountsForAll:(NSInteger)all pending:(NSInteger)pending active:(NSInteger)active archived:(NSInteger)archived rejected:(NSInteger)rejected;
@end

@implementation PPListingsRailView {
    UIScrollView *_scrollView;
    UIStackView *_stackView;
    NSMutableArray<UIButton *> *_chips;
    NSArray<NSNumber *> *_counts;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _chips = [NSMutableArray array];
        _counts = @[@0, @0, @0, @0, @0];
        self.accessibilityLabel = kLang(@"ListingsAdmin_RailHint");

        _scrollView = [[UIScrollView alloc] init];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_scrollView];

        _stackView = [[UIStackView alloc] init];
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.alignment = UIStackViewAlignmentCenter;
        _stackView.spacing = PPSpaceSM;
        _stackView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        [_scrollView addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor constant:PPSpaceBase],
            [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor constant:-PPSpaceBase],
            [_stackView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
            [_stackView.heightAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.heightAnchor],
        ]];

        NSArray *labels = @[
            kLang(@"ListingsAdmin_RailAll"),
            kLang(@"ListingsAdmin_Pending"),
            kLang(@"ListingsAdmin_Active"),
            kLang(@"ListingsAdmin_StatusArchived"),
            kLang(@"ListingsAdmin_StatusRejected"),
        ];

        for (NSInteger i = 0; i < labels.count; i++) {
            UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
            chip.tag = i;
            chip.titleLabel.adjustsFontForContentSizeCategory = YES;
            chip.accessibilityTraits = UIAccessibilityTraitButton;
            [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
            [chip.heightAnchor constraintEqualToConstant:40.0].active = YES;
            chip.contentEdgeInsets = UIEdgeInsetsMake(0, PPSpaceMD, 0, PPSpaceMD);
            [_stackView addArrangedSubview:chip];
            [_chips addObject:chip];
        }

        self.selectedFilter = PPListingsRailFilterAll;
        [self rebuildChips];
    }
    return self;
}

- (void)chipTapped:(UIButton *)chip {
    self.selectedFilter = (PPListingsRailFilter)chip.tag;
    [self rebuildChips];
    if (self.onSelectFilter) self.onSelectFilter(self.selectedFilter);
}

- (void)setCountsForAll:(NSInteger)all pending:(NSInteger)pending active:(NSInteger)active archived:(NSInteger)archived rejected:(NSInteger)rejected {
    _counts = @[@(all), @(pending), @(active), @(archived), @(rejected)];
    [self rebuildChips];
}

- (void)rebuildChips {
    NSArray *labels = @[
        kLang(@"ListingsAdmin_RailAll"),
        kLang(@"ListingsAdmin_Pending"),
        kLang(@"ListingsAdmin_Active"),
        kLang(@"ListingsAdmin_StatusArchived"),
        kLang(@"ListingsAdmin_StatusRejected"),
    ];

    for (NSInteger i = 0; i < _chips.count; i++) {
        UIButton *chip = _chips[i];
        BOOL selected = (i == self.selectedFilter);
        NSInteger count = [_counts[i] integerValue];
        NSString *label = labels[i];
        NSString *countText = PPListingsLocalizedInteger(count);

        NSString *chipTitle = [NSString stringWithFormat:@"%@ · %@", label, countText];
        [chip setTitle:chipTitle forState:UIControlStateNormal];
        chip.titleLabel.font = PPListingMedium(PPFontCaption1, UIFontTextStyleCaption1);
        [chip setTitleColor:(selected ? [UIColor whiteColor] : [UIColor labelColor]) forState:UIControlStateNormal];

        chip.backgroundColor = selected ? PPMaroon600Color() : PPSurfaceColor();
        chip.layer.cornerRadius = 20.0;
        chip.layer.cornerCurve = kCACornerCurveContinuous;
        chip.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        chip.layer.borderColor = selected ? PPMaroon600Color().CGColor : PPListingsSurfaceStrokeColor().CGColor;
        chip.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", label, countText];
        chip.accessibilityTraits = selected ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    }
}

@end

#pragma mark - PPListingCell

typedef NS_ENUM(NSInteger, PPListingDecision) {
    PPListingDecisionNone = 0,
    PPListingDecisionApprove,
    PPListingDecisionReject,
    PPListingDecisionArchive,
};

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
@property (nonatomic, strong) UIView *needsReviewDot;
@property (nonatomic, assign) BOOL canModerate;
@property (nonatomic, copy) void (^decisionHandler)(PPListingDecision decision);
- (void)configureWithItem:(PPListingItem *)item canManage:(BOOL)canManage canModerate:(BOOL)canModerate;
@end

@implementation PPListingCell {
    NSInteger _lastStatus;
    BOOL _lastBlocked;
    BOOL _hasConfigured;
    NSLayoutConstraint *_dotWidthConstraint;
}

static const CGFloat kIconTileSize = 88.0;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.contentView.layoutMargins = UIEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);
        _lastStatus = NSNotFound;
        _lastBlocked = NO;
        _hasConfigured = NO;

        _surfaceView = [[UIView alloc] init];
        _surfaceView.backgroundColor = PPSurfaceColor();
        _surfaceView.layer.cornerRadius = PPCornerCard;
        _surfaceView.layer.cornerCurve = kCACornerCurveContinuous;
        _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _surfaceView.layer.borderColor = PPListingsSurfaceStrokeColor().CGColor;
        PPApplyCardShadow(_surfaceView);
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
        [_iconTile addSubview:_sourceBadge];

        _needsReviewDot = [[UIView alloc] init];
        _needsReviewDot.layer.cornerRadius = 4.0;
        _needsReviewDot.backgroundColor = PPListingsOpsGold();
        _needsReviewDot.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_needsReviewDot];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPListingMedium(PPFontHeadline, UIFontTextStyleHeadline);
        _titleLabel.textColor = PPTextPrimaryColor();
        _titleLabel.numberOfLines = 2;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_titleLabel];

        _metaLabel = [[UILabel alloc] init];
        _metaLabel.font = PPListingRegular(PPFontSubheadline, UIFontTextStyleSubheadline);
        _metaLabel.textColor = PPTextSecondaryColor();
        _metaLabel.numberOfLines = 2;
        _metaLabel.adjustsFontForContentSizeCategory = YES;
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_metaLabel];

        _priceLabel = [[UILabel alloc] init];
        _priceLabel.font = PPListingBold(PPFontCallout, UIFontTextStyleCallout);
        _priceLabel.textColor = PPPrimaryColor();
        _priceLabel.numberOfLines = 1;
        _priceLabel.textAlignment = NSTextAlignmentNatural;
        _priceLabel.adjustsFontForContentSizeCategory = YES;
        _priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_priceLabel];

        _dateLabel = [[UILabel alloc] init];
        _dateLabel.font = PPListingRegular(PPFontCaption1, UIFontTextStyleCaption1);
        _dateLabel.textColor = PPTextTertiaryColor();
        _dateLabel.numberOfLines = 1;
        _dateLabel.textAlignment = NSTextAlignmentNatural;
        _dateLabel.adjustsFontForContentSizeCategory = YES;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_dateLabel];

        _statusBadge = [[UILabel alloc] init];
        _statusBadge.font = PPListingMedium(PPFontCaption2, UIFontTextStyleCaption2);
        _statusBadge.textAlignment = NSTextAlignmentCenter;
        _statusBadge.layer.cornerRadius = PPSpaceXS + 2;
        _statusBadge.layer.masksToBounds = YES;
        _statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [_surfaceView addSubview:_statusBadge];

        UIView *selectedBg = [[UIView alloc] init];
        selectedBg.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.10];
        selectedBg.layer.cornerRadius = PPCornerCard;
        selectedBg.layer.masksToBounds = YES;
        self.selectedBackgroundView = selectedBg;

        UILayoutGuide *contentGuide = self.contentView.layoutMarginsGuide;
        self.surfaceView.layoutMargins = UIEdgeInsetsMake(PPSpaceMD, PPSpaceMD, PPSpaceMD, PPSpaceMD);
        UILayoutGuide *guide = self.surfaceView.layoutMarginsGuide;

        [NSLayoutConstraint activateConstraints:@[
            // Surface within content view margins
            [_surfaceView.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:contentGuide.bottomAnchor],

            // Icon tile — 88pt, leading+top of surface margins
            [_iconTile.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_iconTile.topAnchor constraintEqualToAnchor:guide.topAnchor],
            [_iconTile.widthAnchor constraintEqualToConstant:kIconTileSize],
            [_iconTile.heightAnchor constraintEqualToConstant:kIconTileSize],

            // Icon image fills the tile
            [_iconView.leadingAnchor constraintEqualToAnchor:_iconTile.leadingAnchor],
            [_iconView.trailingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor],
            [_iconView.topAnchor constraintEqualToAnchor:_iconTile.topAnchor],
            [_iconView.bottomAnchor constraintEqualToAnchor:_iconTile.bottomAnchor],

            // Gradient overlay fills tile
            [_mediaGradientOverlay.leadingAnchor constraintEqualToAnchor:_iconTile.leadingAnchor],
            [_mediaGradientOverlay.trailingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor],
            [_mediaGradientOverlay.topAnchor constraintEqualToAnchor:_iconTile.topAnchor],
            [_mediaGradientOverlay.bottomAnchor constraintEqualToAnchor:_iconTile.bottomAnchor],

            // Source badge pinned to bottom of icon tile
            [_sourceBadge.centerXAnchor constraintEqualToAnchor:_iconTile.centerXAnchor],
            [_sourceBadge.bottomAnchor constraintEqualToAnchor:_iconTile.bottomAnchor constant:-PPSpaceXXS],
            [_sourceBadge.heightAnchor constraintEqualToConstant:PPSpaceLG],
            [_sourceBadge.widthAnchor constraintLessThanOrEqualToAnchor:_iconTile.widthAnchor constant:-PPSpaceSM],

            // Title — top-aligned with icon, starts after icon+spacing
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor constant:PPSpaceMD],
            [_titleLabel.topAnchor constraintEqualToAnchor:guide.topAnchor],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],

            // Meta — below title with proper spacing
            [_metaLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [_metaLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],

            // Price + Date row — below meta
            [_priceLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_priceLabel.topAnchor constraintEqualToAnchor:_metaLabel.bottomAnchor constant:PPSpaceSM],

            [_dateLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [_dateLabel.centerYAnchor constraintEqualToAnchor:_priceLabel.centerYAnchor],
            [_dateLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_priceLabel.trailingAnchor constant:PPSpaceSM],

            // Status badge row — below price row
            [_statusBadge.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_statusBadge.topAnchor constraintEqualToAnchor:_priceLabel.bottomAnchor constant:PPSpaceSM],
            [_statusBadge.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
            [_statusBadge.heightAnchor constraintEqualToConstant:PPSpaceLG + 2],

            // Needs-review dot next to status badge
            [_needsReviewDot.leadingAnchor constraintEqualToAnchor:_statusBadge.trailingAnchor constant:PPSpaceSM],
            [_needsReviewDot.centerYAnchor constraintEqualToAnchor:_statusBadge.centerYAnchor],

            // Ensure icon tile doesn't exceed bottom
            [_iconTile.bottomAnchor constraintLessThanOrEqualToAnchor:guide.bottomAnchor],
        ]];

        _dotWidthConstraint = [_needsReviewDot.widthAnchor constraintEqualToConstant:8.0];
        _dotWidthConstraint.active = YES;
        [_needsReviewDot.heightAnchor constraintEqualToConstant:8.0].active = YES;

        [_priceLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                                    forAxis:UILayoutConstraintAxisHorizontal];
        [_dateLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                    forAxis:UILayoutConstraintAxisHorizontal];
    }
    return self;
}

- (void)configureWithItem:(PPListingItem *)item canManage:(BOOL)canManage canModerate:(BOOL)canModerate {
    self.canModerate = canModerate;
    self.titleLabel.text = item.title ?: kLang(@"Unknown");
    self.titleLabel.textColor = item.isBlocked ? PPDisabledContentColor() : PPTextPrimaryColor();
    self.surfaceView.backgroundColor = item.isBlocked ? [PPSurfaceColor() colorWithAlphaComponent:0.72] : PPSurfaceColor();

    UIColor *sourceColor = item.isMarketplace ? PPMaroon600Color() : [UIColor colorWithRed:0.184 green:0.365 blue:0.290 alpha:1.0];
    self.sourceBadge.text = item.isMarketplace ? kLang(@"ListingsAdmin_Marketplace") : kLang(@"ListingsAdmin_Adoption");
    self.sourceBadge.backgroundColor = sourceColor;
    self.sourceBadge.textColor = UIColor.whiteColor;

    self.iconTile.backgroundColor = [PPPrimaryColor() colorWithAlphaComponent:0.12];
    UIImage *placeholder = [UIImage systemImageNamed:item.isMarketplace ? @"bag" : @"heart"];
    self.iconView.image = placeholder;
    self.iconView.tintColor = item.isMarketplace ? PPPrimaryColor() : PPSecondaryAccentColor();
    self.iconView.contentMode = UIViewContentModeCenter;
    self.mediaGradientOverlay.hidden = YES;

    if (item.imageUrl.length > 0) {
        __weak typeof(self) weakSelf = self;
        [self.iconView setImageFromUrl:item.imageUrl completion:^(UIImage *image) {
            if (!image) {
                weakSelf.iconView.image = placeholder;
                weakSelf.iconView.tintColor = item.isMarketplace ? PPPrimaryColor() : PPSecondaryAccentColor();
                weakSelf.iconView.contentMode = UIViewContentModeCenter;
                weakSelf.mediaGradientOverlay.hidden = YES;
            } else {
                weakSelf.iconView.contentMode = UIViewContentModeScaleAspectFill;
                weakSelf.mediaGradientOverlay.hidden = NO;
            }
        }];
    }

    NSString *owner = item.ownerName ?: item.ownerID ?: kLang(@"Unknown");
    NSString *location = item.location.length > 0 ? item.location : nil;
    self.metaLabel.text = location.length > 0 ? [NSString stringWithFormat:@"%@ · %@", owner, location] : owner;

    self.priceLabel.text = PPListingsPriceText(item.price);
    self.dateLabel.text = PPListingsFormattedDate(item.updatedAt ?: item.createdAt);

    BOOL needsReview = item.isPending;
    PPListingsStatusStyle statusStyle = PPListingsStatusStyleForStatus(item.status, item.isBlocked);
    self.statusBadge.text = item.isBlocked ? kLang(@"Blocked") : item.statusString;
    //self.statusBadge.backgroundColor = statusStyle.background;
    //self.statusBadge.textColor = statusStyle.foreground;

    self.surfaceView.layer.borderColor = (item.isBlocked
        ? [PPCriticalColor() colorWithAlphaComponent:0.28]
        : (needsReview ? PPListingsNeedsReviewStroke() : PPListingsSurfaceStrokeColor())).CGColor;
    self.needsReviewDot.hidden = !needsReview;
    _dotWidthConstraint.constant = needsReview ? 8.0 : 0.0;
    self.needsReviewDot.accessibilityLabel = kLang(@"ListingsAdmin_Pending");

    // Animate status badge on change
    if (!_hasConfigured || _lastStatus != item.status || _lastBlocked != item.isBlocked) {
        if (_hasConfigured && !PPListingsReduceMotionEnabled()) {
            self.statusBadge.transform = CGAffineTransformMakeScale(0.55, 0.55);
            self.statusBadge.alpha = 0.0;
            [UIView animateWithDuration:0.42 delay:0.02
                 usingSpringWithDamping:0.6 initialSpringVelocity:0.9
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                self.statusBadge.transform = CGAffineTransformIdentity;
                self.statusBadge.alpha = 1.0;
            } completion:nil];
        } else {
            self.statusBadge.transform = CGAffineTransformIdentity;
            self.statusBadge.alpha = 1.0;
        }
    }
    _lastStatus = item.status;
    _lastBlocked = item.isBlocked;
    _hasConfigured = YES;

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

    NSMutableArray<UIAccessibilityCustomAction *> *actions = [NSMutableArray array];
    if (item.isMarketplace) {
        if (canModerate && item.status != 1) {
            [actions addObject:[[UIAccessibilityCustomAction alloc] initWithName:kLang(@"ListingsAdmin_Approve")
                                                                          target:self
                                                                        selector:@selector(_ppAccessibilityApprove)]];
        }
        if (canModerate && item.status != 5 && !item.isBlocked) {
            [actions addObject:[[UIAccessibilityCustomAction alloc] initWithName:kLang(@"ListingsAdmin_Reject")
                                                                          target:self
                                                                        selector:@selector(_ppAccessibilityReject)]];
        }
        if (canManage && item.status != 4 && !item.isBlocked) {
            [actions addObject:[[UIAccessibilityCustomAction alloc] initWithName:kLang(@"ListingsAdmin_Archive")
                                                                          target:self
                                                                        selector:@selector(_ppAccessibilityArchive)]];
        }
    }
    self.accessibilityCustomActions = actions.count > 0 ? actions.copy : nil;
}

- (BOOL)_ppAccessibilityApprove {
    if (self.decisionHandler) self.decisionHandler(PPListingDecisionApprove);
    return YES;
}

- (BOOL)_ppAccessibilityReject {
    if (self.decisionHandler) self.decisionHandler(PPListingDecisionReject);
    return YES;
}

- (BOOL)_ppAccessibilityArchive {
    if (self.decisionHandler) self.decisionHandler(PPListingDecisionArchive);
    return YES;
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

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
    self.iconView.contentMode = UIViewContentModeCenter;
    self.mediaGradientOverlay.hidden = YES;
    self.surfaceView.transform = CGAffineTransformIdentity;
    _hasConfigured = NO;
    _lastStatus = NSNotFound;
    _lastBlocked = NO;
}

@end

#pragma mark - PPListingsAdminViewController

static NSString *const kListingCellID = @"PPListingCell";

@interface PPListingsAdminViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<PPListingItem *> *listings;
@property (nonatomic, strong) NSArray<PPListingItem *> *filteredListings;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL canView;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL canModerate;
@property (nonatomic, assign) PPListingsState state;
@property (nonatomic, assign) PPListingsRailFilter railFilter;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) id marketplaceListener;
@property (nonatomic, strong) id adoptionListener;
@property (nonatomic, assign) BOOL marketplaceLoaded;
@property (nonatomic, assign) BOOL adoptionLoaded;
@property (nonatomic, strong) PPListingsSummaryBar *summaryBar;
@property (nonatomic, strong) PPListingsRailView *railView;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIView *stateOverlay;
@property (nonatomic, strong) UIView *loadingView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIView *noResultsView;
@property (nonatomic, strong) UIView *errorView;
@property (nonatomic, strong) UILabel *noResultsSubtitleLabel;
@end

@implementation PPListingsAdminViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    [self setupNavigation];
    [self setupTableView];
    [self setupTableHeader];
    [self setupStateOverlay];
    [self evaluatePermissions];
    [self startListening];
}

#pragma mark - Setup

- (void)setupNavigation {
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.title = kLang(@"ListingsAdmin_Title");
}

- (void)setupTableView {
    [self.tableView registerClass:[PPListingCell class] forCellReuseIdentifier:kListingCellID];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = kIconTileSize + PPSpaceXL;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.accessibilityIdentifier = @"ListingsTable";
    self.tableView.backgroundColor = UIColor.clearColor;

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
    self.definesPresentationContext = YES;
}

- (void)setupTableHeader {
    // Container that becomes tableView.tableHeaderView
    _headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 1)];
    _headerContainer.backgroundColor = UIColor.clearColor;

    _summaryBar = [[PPListingsSummaryBar alloc] initWithFrame:CGRectZero];
    _summaryBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerContainer addSubview:_summaryBar];

    _railView = [[PPListingsRailView alloc] initWithFrame:CGRectZero];
    _railView.translatesAutoresizingMaskIntoConstraints = NO;
    PPweakify(self);
    _railView.onSelectFilter = ^(PPListingsRailFilter filter) {
        PPstrongify(self);
        if (!self) return;
        self.railFilter = filter;
        [self applyFilter];
    };
    [_headerContainer addSubview:_railView];

    [NSLayoutConstraint activateConstraints:@[
        [_summaryBar.topAnchor constraintEqualToAnchor:_headerContainer.topAnchor constant:PPSpaceSM],
        [_summaryBar.leadingAnchor constraintEqualToAnchor:_headerContainer.leadingAnchor constant:PPSpaceBase],
        [_summaryBar.trailingAnchor constraintEqualToAnchor:_headerContainer.trailingAnchor constant:-PPSpaceBase],

        [_railView.topAnchor constraintEqualToAnchor:_summaryBar.bottomAnchor constant:PPSpaceSM],
        [_railView.leadingAnchor constraintEqualToAnchor:_headerContainer.leadingAnchor],
        [_railView.trailingAnchor constraintEqualToAnchor:_headerContainer.trailingAnchor],
        [_railView.heightAnchor constraintEqualToConstant:48.0],
        [_railView.bottomAnchor constraintEqualToAnchor:_headerContainer.bottomAnchor constant:-PPSpaceSM],
    ]];

    self.tableView.tableHeaderView = _headerContainer;
}

- (void)layoutTableHeader {
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;

    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) return;

    // Size the header using Auto Layout
    CGSize targetSize = CGSizeMake(width, UILayoutFittingCompressedSize.height);
    header.frame = CGRectMake(0, 0, width, header.frame.size.height ?: 1);
    [header setNeedsLayout];
    [header layoutIfNeeded];

    CGFloat height = [header systemLayoutSizeFittingSize:targetSize
                           withHorizontalFittingPriority:UILayoutPriorityRequired
                                 verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    height = MAX(height, 1.0);

    // Only reassign tableHeaderView if height actually changed (prevents layout loop)
    if (fabs(header.frame.size.height - height) > 0.5) {
        CGRect frame = header.frame;
        frame.size.height = height;
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
}

- (void)setupStateOverlay {
    _stateOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    _stateOverlay.autoresizingMask = UIViewAutoresizingNone;
    _stateOverlay.hidden = YES;
    _stateOverlay.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    [self.view addSubview:_stateOverlay];

    [self buildLoadingView];
    [self buildEmptyView];
    [self buildNoResultsView];
    [self buildErrorView];
}

- (void)buildLoadingView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [_stateOverlay addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:_stateOverlay.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:_stateOverlay.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:_stateOverlay.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:_stateOverlay.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = AppPrimaryClr;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [container addSubview:spinner];

    UILabel *label = [[UILabel alloc] init];
    label.font = PPListingMedium(PPFontSubheadline, UIFontTextStyleSubheadline);
    label.textColor = PPTextSecondaryColor();
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
    [_stateOverlay addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:_stateOverlay.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:_stateOverlay.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:_stateOverlay.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:_stateOverlay.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"list.bullet.clipboard" tint:[AppPrimaryClr colorWithAlphaComponent:0.16] glyphTint:AppPrimaryClr];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"ListingsAdmin_NoListings");
    [container addSubview:title];

    UILabel *subtitle = [self stateSubtitleLabel];
    subtitle.text = kLang(@"ListingsAdmin_EmptySubtitle");
    [container addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceXS],
        [subtitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    self.emptyView = container;
}

- (void)buildNoResultsView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [_stateOverlay addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:_stateOverlay.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:_stateOverlay.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:_stateOverlay.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:_stateOverlay.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"magnifyingglass" tint:[PPTextTertiaryColor() colorWithAlphaComponent:0.16] glyphTint:PPTextTertiaryColor()];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"ListingsAdmin_NoResultsTitle");
    [container addSubview:title];

    UILabel *subtitle = [self stateSubtitleLabel];
    subtitle.accessibilityIdentifier = @"ListingsNoResultsSubtitle";
    self.noResultsSubtitleLabel = subtitle;
    [container addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceXS],
        [subtitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    self.noResultsView = container;
}

- (void)buildErrorView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [_stateOverlay addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:_stateOverlay.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:_stateOverlay.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:_stateOverlay.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:_stateOverlay.trailingAnchor constant:-PPSpaceXL],
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
    label.textColor = PPTextPrimaryColor();
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontForContentSizeCategory = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UILabel *)stateSubtitleLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = PPListingRegular(PPFontSubheadline, UIFontTextStyleSubheadline);
    label.textColor = PPTextSecondaryColor();
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
    self.marketplaceLoaded = NO;
    self.adoptionLoaded = NO;
    self.listings = @[];
    self.filteredListings = @[];
    [self refreshStateVisibility];
    [self startMarketplaceListener];
    [self startAdoptionListener];
}

- (void)startMarketplaceListener {
    PPweakify(self);
    FIRQuery *query = [[[[FIRFirestore firestore] collectionWithPath:PPListingSourceMarketplace]
                         queryOrderedByField:@"createdAt" descending:YES]
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
        self.marketplaceLoaded = YES;
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
            self.state = PPListingsStateError;
            [self refreshStateVisibility];
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPListingItem *item = [self adoptionItemFromDoc:doc];
            if (item) [items addObject:item];
        }
        self.adoptionLoaded = YES;
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
    NSMutableArray *filtered = [NSMutableArray array];
    for (PPListingItem *item in self.listings) {
        if (![item matchesRailFilter:self.railFilter]) continue;
        if (query.length > 0) {
            NSString *q = query.lowercaseString;
            NSString *title = item.title.lowercaseString ?: @"";
            NSString *owner = item.ownerName.lowercaseString ?: item.ownerID.lowercaseString ?: @"";
            NSString *category = item.category.lowercaseString ?: @"";
            if (![title containsString:q] && ![owner containsString:q] && ![category containsString:q]) {
                continue;
            }
        }
        [filtered addObject:item];
    }
    self.filteredListings = filtered.copy;
    [self updateSummary];
    [self refreshStateVisibility];
    [self.tableView reloadData];
}

- (void)updateSummary {
    NSInteger total = self.listings.count;
    NSInteger marketplace = 0;
    NSInteger active = 0;
    NSInteger pending = 0;
    NSInteger adoption = 0;
    for (PPListingItem *item in self.listings) {
        if (item.isMarketplace) marketplace++;
        else adoption++;
        if (item.isActive) active++;
        if (item.isPending) pending++;
    }
    [self.summaryBar configureWithTotal:total marketplace:marketplace active:active pending:pending adoption:adoption];

    NSInteger railAll = self.listings.count;
    NSInteger railPending = 0;
    NSInteger railActive = 0;
    NSInteger railArchived = 0;
    NSInteger railRejected = 0;
    for (PPListingItem *item in self.listings) {
        switch (item.status) {
            case 0: railPending++; break;
            case 1: railActive++; break;
            case 4: railArchived++; break;
            case 5: railRejected++; break;
            default: break;
        }
    }
    [self.railView setCountsForAll:railAll pending:railPending active:railActive archived:railArchived rejected:railRejected];
}

- (void)refreshStateVisibility {
    if (self.state == PPListingsStateError) {
        // Keep the error state until the user explicitly retries.
    } else if (!self.marketplaceLoaded || !self.adoptionLoaded) {
        self.state = PPListingsStateLoading;
    } else if (self.listings.count == 0) {
        self.state = PPListingsStateEmpty;
    } else if (self.filteredListings.count == 0) {
        self.state = PPListingsStateNoResults;
    } else {
        self.state = PPListingsStateReady;
    }

    BOOL ready = (self.state == PPListingsStateReady);
    self.stateOverlay.hidden = ready;
    self.tableView.scrollEnabled = ready;
    if (!ready) [self repositionStateOverlay];
    self.loadingView.hidden = (self.state != PPListingsStateLoading);
    self.emptyView.hidden = (self.state != PPListingsStateEmpty);
    self.noResultsView.hidden = (self.state != PPListingsStateNoResults);
    self.errorView.hidden = (self.state != PPListingsStateError);

    if (self.state == PPListingsStateNoResults) {
        NSString *query = self.searchController.searchBar.text;
        if (self.noResultsSubtitleLabel) {
            if (query.length > 0) {
                self.noResultsSubtitleLabel.text = [NSString stringWithFormat:kLang(@"ListingsAdmin_NoResultsSubtitle"), query];
            } else {
                self.noResultsSubtitleLabel.text = kLang(@"ListingsAdmin_NoResultsFilter");
            }
        }
    }
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
    PPweakify(self);
    cell.decisionHandler = ^(PPListingDecision decision) {
        PPstrongify(self);
        if (!self) return;
        if (decision == PPListingDecisionApprove) {
            [self approveListing:item];
        } else if (decision == PPListingDecisionReject) {
            [self rejectListing:item];
        } else if (decision == PPListingDecisionArchive) {
            [self archiveListing:item];
        }
    };
    [cell configureWithItem:item canManage:self.canManage canModerate:self.canModerate];
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
        self.headerContainer.alpha = 1.0;
        self.headerContainer.transform = CGAffineTransformIdentity;
        return;
    }

    self.headerContainer.alpha = 0;
    self.headerContainer.transform = CGAffineTransformMakeTranslation(0, 14);

    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.headerContainer.alpha = 1;
        self.headerContainer.transform = CGAffineTransformIdentity;
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
    [self layoutTableHeader];
    [self repositionStateOverlay];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self repositionStateOverlay];
}

- (void)repositionStateOverlay {
    if (!_stateOverlay || _stateOverlay.hidden) return;
    // Pin overlay to the visible portion of the table view
    CGRect visibleFrame = self.tableView.bounds;
    UIEdgeInsets safeInsets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        safeInsets = self.tableView.safeAreaInsets;
    }
    _stateOverlay.frame = CGRectMake(0,
                                     self.tableView.contentOffset.y + safeInsets.top,
                                     visibleFrame.size.width,
                                     visibleFrame.size.height - safeInsets.top);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self.tableView reloadData];
    [self layoutTableHeader];
}

#pragma mark - Cleanup

- (void)dealloc {
    [self.marketplaceListener remove];
    [self.adoptionListener remove];
}

@end
