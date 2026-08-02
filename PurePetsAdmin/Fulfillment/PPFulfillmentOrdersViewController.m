#import "PPFulfillmentOrdersViewController.h"
#import "PPFulfillmentService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "PPHero.h"
#import "PPDesignTokens.h"
@import FirebaseFirestore;

#pragma mark - Haptic Helpers
/*
 
 static inline void PPHapticTouch(void) {
     [PPFunc pp_playTapEffect];
 }

 static inline void PPHapticSuccess(void) {
     [PPFunc pp_playSuccessEffect];
 }

 static inline void PPHapticError(void) {
     [PPFunc pp_playErrorEffect];
 }

 */
#pragma mark - Colors & Helpers

static inline UIColor *PPF_AccentColor(void) {
    return AppPrimaryClr ?: UIColor.systemPinkColor;
}

static inline UIColor *PPF_CanvasColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGroupedBackgroundColor;
    return [UIColor colorWithWhite:0.96 alpha:1.0];
}

static inline UIColor *PPF_SurfaceColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondarySystemGroupedBackgroundColor;
    return UIColor.whiteColor;
}

static inline UIColor *PPF_InkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.labelColor;
    return UIColor.blackColor;
}

static inline UIColor *PPF_SubInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondaryLabelColor;
    return [UIColor colorWithWhite:0.40 alpha:1.0];
}

static inline UIColor *PPF_TertiaryInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.tertiaryLabelColor;
    return [UIColor colorWithWhite:0.55 alpha:1.0];
}

static inline UIColor *PPF_StatusColor(NSString *status) {
    NSString *s = [status.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s isEqualToString:@"completed"] || [s isEqualToString:@"ready_for_pickup"] || [s isEqualToString:@"accepted"]) {
        return UIColor.systemGreenColor;
    }
    if ([s isEqualToString:@"rejected"] || [s isEqualToString:@"cancelled"] || [s isEqualToString:@"failed"] || [s isEqualToString:@"returned"]) {
        return UIColor.systemRedColor;
    }
    if ([s isEqualToString:@"new_request"] || [s isEqualToString:@"preparing"] || [s isEqualToString:@"delivery_requested"] ||
        [s isEqualToString:@"delivery_assigned"] || [s isEqualToString:@"awaiting_handover"] || [s isEqualToString:@"handed_over"] ||
        [s isEqualToString:@"picked_up"] || [s isEqualToString:@"in_transit"] || [s isEqualToString:@"in_progress"]) {
        return PPF_AccentColor();
    }
    return UIColor.systemGrayColor;
}

static inline NSString *PPF_StatusKey(NSString *status) {
    NSString *s = status ?: @"";
    if ([s isEqualToString:@"new_request"]) return @"Fulfillment_Status_NewRequest";
    if ([s isEqualToString:@"preparing"]) return @"Fulfillment_Status_Preparing";
    if ([s isEqualToString:@"ready_for_pickup"]) return @"Fulfillment_Status_ReadyForPickup";
    if ([s isEqualToString:@"delivery_requested"]) return @"Fulfillment_Status_DeliveryRequested";
    if ([s isEqualToString:@"delivery_assigned"]) return @"Fulfillment_Status_DeliveryAssigned";
    if ([s isEqualToString:@"awaiting_handover"]) return @"Fulfillment_Status_AwaitingHandover";
    if ([s isEqualToString:@"handed_over"]) return @"Fulfillment_Status_HandedOver";
    if ([s isEqualToString:@"picked_up"]) return @"Fulfillment_Status_PickedUp";
    if ([s isEqualToString:@"in_transit"]) return @"Fulfillment_Status_InTransit";
    if ([s isEqualToString:@"accepted"]) return @"Fulfillment_Status_Accepted";
    if ([s isEqualToString:@"rejected"]) return @"Fulfillment_Status_Rejected";
    if ([s isEqualToString:@"completed"]) return @"Fulfillment_Status_Completed";
    if ([s isEqualToString:@"cancelled"]) return @"Fulfillment_Status_Cancelled";
    if ([s isEqualToString:@"failed"]) return @"Fulfillment_Status_Failed";
    if ([s isEqualToString:@"returned"]) return @"Fulfillment_Status_Returned";
    if ([s isEqualToString:@"pending"]) return @"Fulfillment_Status_Pending";
    if ([s isEqualToString:@"in_progress"]) return @"Fulfillment_Status_InProgress";
    return @"Fulfillment_Status_Unknown";
}

static inline NSString *PPF_StatusText(NSString *status) {
    if (!status || status.length == 0) return kLang(@"Fulfillment_Status_Unknown");
    NSString *key = PPF_StatusKey(status);
    NSString *localized = kLang(key);
    if (localized.length > 0 && ![localized isEqualToString:key]) return localized;
    return [status stringByReplacingOccurrencesOfString:@"_" withString:@" "].capitalizedString;
}

static inline NSString *PPF_DateString(NSDate *date) {
    if (!date) return @"—";
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    return [f stringFromDate:date];
}

static inline NSString *PPF_MoneyString(NSNumber *amount, NSString *currency) {
    double val = amount ? amount.doubleValue : 0.0;
    NSString *curr = currency.length ? currency : @"QAR";
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterCurrencyStyle;
    f.currencyCode = curr;
    f.maximumFractionDigits = 0;
    f.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    return [f stringFromNumber:@(val)] ?: [NSString stringWithFormat:@"%.0f %@", val, curr];
}

static inline NSString *PPF_ShortId(NSString *value, NSUInteger length) {
    if (!value || value.length == 0) return @"—";
    if (value.length > length) {
        return [NSString stringWithFormat:@"%@…", [value substringToIndex:length]];
    }
    return value;
}

static inline NSString *PPF_Initials(NSString *name) {
    if (!name || name.length == 0) return @"PP";
    NSArray *parts = [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length > 0) [clean addObject:p];
    }
    if (clean.count == 0) return @"PP";
    if (clean.count == 1) return [[[clean[0] substringToIndex:1] uppercaseString] copy];
    NSString *first = [clean[0] substringToIndex:1];
    NSString *second = [clean[1] substringToIndex:1];
    return [[NSString stringWithFormat:@"%@%@", first, second] uppercaseString];
}

static inline void PPF_ApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    view.layer.shadowRadius = 18.0;
    view.layer.shadowOpacity = 0.048;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.62].CGColor;
}

#pragma mark - Custom UI Avatar View

@interface PPF_AvatarView : UIView
@property (nonatomic, strong) UILabel *initialsLabel;
- (void)setName:(NSString *)name isLarge:(BOOL)isLarge;
@end

@implementation PPF_AvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [PPF_AccentColor() colorWithAlphaComponent:0.12];
        self.clipsToBounds = YES;
        
        _initialsLabel = [UILabel new];
        _initialsLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _initialsLabel.font = [Styling fontBold:PPFontCaption1];
        _initialsLabel.textColor = PPF_AccentColor();
        _initialsLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_initialsLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_initialsLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_initialsLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) / 2.0;
}

- (void)setName:(NSString *)name isLarge:(BOOL)isLarge {
    self.initialsLabel.text = PPF_Initials(name);
    self.initialsLabel.font = isLarge ? [Styling fontBold:PPFontSubheadline] : [Styling fontBold:PPFontCaption1];
}

@end

#pragma mark - Custom Metrics Card View

@interface PPF_MetricsCardView : UIView
@property (nonatomic, strong) UILabel *activeCountLabel;
@property (nonatomic, strong) UILabel *waitingCountLabel;
@property (nonatomic, strong) UILabel *completedCountLabel;
@property (nonatomic, strong) UILabel *providerNetLabel;
- (void)updateWithActive:(NSInteger)active waiting:(NSInteger)waiting completed:(NSInteger)completed providerNet:(double)net currency:(NSString *)currency;
@end

@implementation PPF_MetricsCardView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(self, PPCornerCard);
        
        UIStackView *stack = [UIStackView new];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionFillEqually;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8.0;
        stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [self addSubview:stack];
        
        _activeCountLabel = [UILabel new];
        _waitingCountLabel = [UILabel new];
        _completedCountLabel = [UILabel new];
        _providerNetLabel = [UILabel new];
        
        [stack addArrangedSubview:[self buildBlockWithTitle:kLang(@"Fulfillment_Metric_Active") label:_activeCountLabel color:UIColor.systemBlueColor]];
        [stack addArrangedSubview:[self buildBlockWithTitle:kLang(@"Fulfillment_Metric_Waiting") label:_waitingCountLabel color:UIColor.systemOrangeColor]];
        [stack addArrangedSubview:[self buildBlockWithTitle:kLang(@"Fulfillment_Metric_Completed") label:_completedCountLabel color:UIColor.systemGreenColor]];
        [stack addArrangedSubview:[self buildBlockWithTitle:kLang(@"Fulfillment_Metric_NetValue") label:_providerNetLabel color:PPF_AccentColor()]];
        
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12.0],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (UIView *)buildBlockWithTitle:(NSString *)title label:(UILabel *)label color:(UIColor *)color {
    UIView *container = [UIView new];
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    UILabel *tLabel = [UILabel new];
    tLabel.translatesAutoresizingMaskIntoConstraints = NO;
    tLabel.text = title;
    tLabel.font = [Styling fontMedium:PPFontCaption2];
    tLabel.textColor = PPF_SubInkColor();
    tLabel.textAlignment = NSTextAlignmentCenter;
    tLabel.adjustsFontSizeToFitWidth = YES;
    tLabel.minimumScaleFactor = 0.75;
    [container addSubview:tLabel];
    
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [Styling fontBold:PPFontFootnote];
    label.textColor = color;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.70;
    [container addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [tLabel.topAnchor constraintEqualToAnchor:container.topAnchor],
        [tLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [tLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        
        [label.topAnchor constraintEqualToAnchor:tLabel.bottomAnchor constant:4.0],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];
    return container;
}

- (void)updateWithActive:(NSInteger)active waiting:(NSInteger)waiting completed:(NSInteger)completed providerNet:(double)net currency:(NSString *)currency {
    self.activeCountLabel.text = [NSString stringWithFormat:@"%ld", (long)active];
    self.waitingCountLabel.text = [NSString stringWithFormat:@"%ld", (long)waiting];
    self.completedCountLabel.text = [NSString stringWithFormat:@"%ld", (long)completed];
    self.providerNetLabel.text = PPF_MoneyString(@(net), currency);
}

@end

#pragma mark - Cells

@interface PPF_OrderCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) PPF_AvatarView *customerAvatar;
@property (nonatomic, strong) UILabel *customerNameLabel;
@property (nonatomic, strong) UILabel *customerIdLabel;
@property (nonatomic, strong) UIImageView *routeArrow;
@property (nonatomic, strong) PPF_AvatarView *ownerAvatar;
@property (nonatomic, strong) UILabel *ownerNameLabel;
@property (nonatomic, strong) UILabel *ownerIdLabel;

@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *subtotalLabel;
@property (nonatomic, strong) UILabel *itemCountLabel;
@property (nonatomic, strong) UILabel *orderRefLabel;
@property (nonatomic, strong) UILabel *updatedAtLabel;

@property (nonatomic, assign) BOOL hasAnimatedEntrance;
- (void)configureWithRecord:(PPFulfillmentRecord *)record
               customerName:(nullable NSString *)customerName
                  ownerName:(nullable NSString *)ownerName
                   animated:(BOOL)animated;
@end

@implementation PPF_OrderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerCard);
        [self.contentView addSubview:_cardView];

        // Customer Person
        _customerAvatar = [PPF_AvatarView new];
        _customerAvatar.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_customerAvatar];

        _customerNameLabel = [UILabel new];
        _customerNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _customerNameLabel.font = [Styling fontBold:PPFontSubheadline];
        _customerNameLabel.textColor = PPF_InkColor();
        _customerNameLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _customerNameLabel.adjustsFontSizeToFitWidth = YES;
        _customerNameLabel.minimumScaleFactor = 0.8;
        [_cardView addSubview:_customerNameLabel];

        _customerIdLabel = [UILabel new];
        _customerIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _customerIdLabel.font = [Styling fontRegular:PPFontCaption2];
        _customerIdLabel.textColor = PPF_TertiaryInkColor();
        _customerIdLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_customerIdLabel];

        // Route arrow icon
        _routeArrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right"]];
        _routeArrow.translatesAutoresizingMaskIntoConstraints = NO;
        _routeArrow.tintColor = PPF_TertiaryInkColor();
        _routeArrow.contentMode = UIViewContentModeScaleAspectFit;
        if ([Language isRTL]) {
            _routeArrow.transform = CGAffineTransformMakeScale(-1.0, 1.0);
        }
        [_cardView addSubview:_routeArrow];

        // Owner Person
        _ownerAvatar = [PPF_AvatarView new];
        _ownerAvatar.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_ownerAvatar];

        _ownerNameLabel = [UILabel new];
        _ownerNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _ownerNameLabel.font = [Styling fontBold:PPFontSubheadline];
        _ownerNameLabel.textColor = PPF_InkColor();
        _ownerNameLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _ownerNameLabel.adjustsFontSizeToFitWidth = YES;
        _ownerNameLabel.minimumScaleFactor = 0.8;
        [_cardView addSubview:_ownerNameLabel];

        _ownerIdLabel = [UILabel new];
        _ownerIdLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _ownerIdLabel.font = [Styling fontRegular:PPFontCaption2];
        _ownerIdLabel.textColor = PPF_TertiaryInkColor();
        _ownerIdLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_ownerIdLabel];

        // Status pill
        _statusDot = [UIView new];
        _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
        _statusDot.layer.cornerRadius = 3.5;
        _statusDot.clipsToBounds = YES;
        
        _statusLabel = [UILabel new];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = [Styling fontBold:PPFontCaption1];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.layer.cornerRadius = 10.0;
        _statusLabel.layer.masksToBounds = YES;
        [_cardView addSubview:_statusLabel];
        [_statusLabel addSubview:_statusDot];

        // Subtotal & Items
        _subtotalLabel = [UILabel new];
        _subtotalLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtotalLabel.font = [Styling fontBold:PPFontCallout];
        _subtotalLabel.textColor = PPF_InkColor();
        _subtotalLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_subtotalLabel];

        _itemCountLabel = [UILabel new];
        _itemCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _itemCountLabel.font = [Styling fontMedium:PPFontCaption1];
        _itemCountLabel.textColor = PPF_SubInkColor();
        _itemCountLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_itemCountLabel];

        // Order Ref & Updated At
        _orderRefLabel = [UILabel new];
        _orderRefLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _orderRefLabel.font = [Styling fontRegular:PPFontFootnote];
        _orderRefLabel.textColor = PPF_SubInkColor();
        _orderRefLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_orderRefLabel];

        _updatedAtLabel = [UILabel new];
        _updatedAtLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _updatedAtLabel.font = [Styling fontRegular:PPFontCaption1];
        _updatedAtLabel.textColor = PPF_TertiaryInkColor();
        _updatedAtLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_updatedAtLabel];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"]];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        chevron.tintColor = [PPF_TertiaryInkColor() colorWithAlphaComponent:0.55];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        if ([Language isRTL]) {
            chevron.transform = CGAffineTransformMakeScale(-1.0, 1.0);
        }
        [_cardView addSubview:chevron];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            // Customer Identity Row
            [_customerAvatar.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14.0],
            [_customerAvatar.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_customerAvatar.widthAnchor constraintEqualToConstant:32.0],
            [_customerAvatar.heightAnchor constraintEqualToConstant:32.0],

            [_customerNameLabel.leadingAnchor constraintEqualToAnchor:_customerAvatar.trailingAnchor constant:10.0],
            [_customerNameLabel.topAnchor constraintEqualToAnchor:_customerAvatar.topAnchor],
            [_customerNameLabel.widthAnchor constraintLessThanOrEqualToConstant:110.0],

            [_customerIdLabel.leadingAnchor constraintEqualToAnchor:_customerNameLabel.leadingAnchor],
            [_customerIdLabel.topAnchor constraintEqualToAnchor:_customerNameLabel.bottomAnchor constant:2.0],

            // Route arrow
            [_routeArrow.leadingAnchor constraintEqualToAnchor:_customerNameLabel.trailingAnchor constant:6.0],
            [_routeArrow.centerYAnchor constraintEqualToAnchor:_customerAvatar.centerYAnchor],
            [_routeArrow.widthAnchor constraintEqualToConstant:14.0],
            [_routeArrow.heightAnchor constraintEqualToConstant:14.0],

            // Owner Identity
            [_ownerAvatar.leadingAnchor constraintEqualToAnchor:_routeArrow.trailingAnchor constant:6.0],
            [_ownerAvatar.topAnchor constraintEqualToAnchor:_customerAvatar.topAnchor],
            [_ownerAvatar.widthAnchor constraintEqualToConstant:32.0],
            [_ownerAvatar.heightAnchor constraintEqualToConstant:32.0],

            [_ownerNameLabel.leadingAnchor constraintEqualToAnchor:_ownerAvatar.trailingAnchor constant:10.0],
            [_ownerNameLabel.topAnchor constraintEqualToAnchor:_ownerAvatar.topAnchor],
            [_ownerNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-8.0],

            [_ownerIdLabel.leadingAnchor constraintEqualToAnchor:_ownerNameLabel.leadingAnchor],
            [_ownerIdLabel.topAnchor constraintEqualToAnchor:_ownerNameLabel.bottomAnchor constant:2.0],

            // Status label top-right
            [_statusLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8.0],
            [_statusLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_statusLabel.heightAnchor constraintEqualToConstant:24.0],

            [chevron.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14.0],
            [chevron.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:10.0],
            [chevron.heightAnchor constraintEqualToConstant:16.0],

            // Divider / Subtotal Row
            [_subtotalLabel.leadingAnchor constraintEqualToAnchor:_customerAvatar.leadingAnchor],
            [_subtotalLabel.topAnchor constraintEqualToAnchor:_customerAvatar.bottomAnchor constant:14.0],

            [_itemCountLabel.leadingAnchor constraintEqualToAnchor:_subtotalLabel.trailingAnchor constant:8.0],
            [_itemCountLabel.firstBaselineAnchor constraintEqualToAnchor:_subtotalLabel.firstBaselineAnchor],

            [_orderRefLabel.leadingAnchor constraintEqualToAnchor:_customerAvatar.leadingAnchor],
            [_orderRefLabel.topAnchor constraintEqualToAnchor:_subtotalLabel.bottomAnchor constant:6.0],
            [_orderRefLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-14.0],

            [_updatedAtLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8.0],
            [_updatedAtLabel.centerYAnchor constraintEqualToAnchor:_orderRefLabel.centerYAnchor],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _hasAnimatedEntrance = NO;
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
    _customerNameLabel.text = nil;
    _customerIdLabel.text = nil;
    _ownerNameLabel.text = nil;
    _ownerIdLabel.text = nil;
    _statusLabel.text = nil;
    _subtotalLabel.text = nil;
    _itemCountLabel.text = nil;
    _orderRefLabel.text = nil;
    _updatedAtLabel.text = nil;
}

- (void)configureWithRecord:(PPFulfillmentRecord *)record
               customerName:(nullable NSString *)customerName
                  ownerName:(nullable NSString *)ownerName
                   animated:(BOOL)animated {
    
    NSString *cName = customerName.length ? customerName : kLang(@"Fulfillment_UnknownCustomer");
    [self.customerAvatar setName:cName isLarge:NO];
    self.customerNameLabel.text = cName;
    self.customerIdLabel.text = PPF_ShortId(record.customerID, 8);

    BOOL isPlatform = [record.ownerType isEqualToString:@"platform"] || !record.ownerID.length;
    NSString *oName = isPlatform ? kLang(@"Fulfillment_Filter_Platform") : (ownerName.length ? ownerName : kLang(@"Fulfillment_UnknownCustomer"));
    [self.ownerAvatar setName:oName isLarge:NO];
    self.ownerNameLabel.text = oName;
    self.ownerIdLabel.text = isPlatform ? kLang(@"Fulfillment_Filter_Platform") : PPF_ShortId(record.ownerID, 8);

    UIColor *sColor = PPF_StatusColor(record.status);
    self.statusLabel.text = [NSString stringWithFormat:@"  %@  ", PPF_StatusText(record.status)];
    self.statusLabel.textColor = sColor;
    self.statusLabel.backgroundColor = [sColor colorWithAlphaComponent:0.12];

    NSNumber *subtotal = record.money[@"subtotal"];
    NSString *currency = record.money[@"currency"];
    self.subtotalLabel.text = PPF_MoneyString(subtotal, currency);

    NSString *itemsFormat = kLang(@"Fulfillment_ItemsCount_Format");
    self.itemCountLabel.text = [NSString stringWithFormat:itemsFormat, @(record.items.count)];

    NSString *orderRef = record.parentOrderNumber.length ? record.parentOrderNumber : PPF_ShortId(record.parentOrderID, 12);
    self.orderRefLabel.text = [NSString stringWithFormat:@"#%@", orderRef];

    self.updatedAtLabel.text = PPF_DateString(record.updatedAt);

    if (animated && !_hasAnimatedEntrance) {
        _hasAnimatedEntrance = YES;
        self.contentView.alpha = 0.0;
        self.contentView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
        [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.contentView.alpha = 1.0;
            self.contentView.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    if (highlighted) {
        [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.contentView.transform = CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown);
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.20 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            self.contentView.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

@end

#pragma mark - Info Cell (Detail)

@interface PPFulfillmentInfoCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
- (void)configureTitle:(NSString *)title value:(NSString *)value isEmphasized:(BOOL)isEmphasized;
@end

@implementation PPFulfillmentInfoCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPF_SurfaceColor();
        PPF_ApplyCardChrome(_cardView, PPCornerMedium);
        [self.contentView addSubview:_cardView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontMedium:PPFontFootnote];
        _titleLabel.textColor = PPF_SubInkColor();
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_titleLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:PPFontBody];
        _valueLabel.textColor = PPF_InkColor();
        _valueLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _valueLabel.numberOfLines = 0;
        [_cardView addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],

            [_valueLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_valueLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _titleLabel.text = nil;
    _valueLabel.text = nil;
    _valueLabel.textColor = PPF_InkColor();
}

- (void)configureTitle:(NSString *)title value:(NSString *)value isEmphasized:(BOOL)isEmphasized {
    self.titleLabel.text = title ?: @"";
    self.valueLabel.text = value.length ? value : @"-";
    if (isEmphasized) {
        self.valueLabel.textColor = PPF_AccentColor();
        self.valueLabel.font = [Styling fontBold:PPFontTitle3];
    } else {
        self.valueLabel.textColor = PPF_InkColor();
        self.valueLabel.font = [Styling fontBold:PPFontBody];
    }
}

@end

#pragma mark - State Cell

@interface PPF_StateCell : UITableViewCell
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (void)configureWithText:(NSString *)text loading:(BOOL)loading;
@end

@implementation PPF_StateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _messageLabel = [UILabel new];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.font = [Styling fontMedium:PPFontCallout];
        _messageLabel.textColor = PPF_SubInkColor();
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 0;
        [self.contentView addSubview:_messageLabel];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        _spinner.color = PPF_AccentColor();
        [self.contentView addSubview:_spinner];

        [NSLayoutConstraint activateConstraints:@[
            [_messageLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_messageLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-12.0],
            [_messageLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceXL],
            [_messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceXL],

            [_spinner.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_spinner.topAnchor constraintEqualToAnchor:_messageLabel.bottomAnchor constant:PPSpaceMD],
            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:180.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _messageLabel.text = nil;
    [_spinner stopAnimating];
}

- (void)configureWithText:(NSString *)text loading:(BOOL)loading {
    _messageLabel.text = text;
    if (loading) {
        [_spinner startAnimating];
        _messageLabel.alpha = 0.7;
    } else {
        [_spinner stopAnimating];
        _messageLabel.alpha = 1.0;
    }
}

@end

#pragma mark - Detail View Controller

@interface PPFulfillmentDetailViewController ()
@property (nonatomic, strong) PPFulfillmentRecord *seedRecord;
@property (nonatomic, strong) PPFulfillmentRecord *detailRecord;
@property (nonatomic, copy) NSArray *events;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *userNames;
@property (nonatomic, strong) id<FIRListenerRegistration> eventsListener;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation PPFulfillmentDetailViewController

- (instancetype)initWithRecord:(PPFulfillmentRecord *)record {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _seedRecord = record;
        _detailRecord = record;
        _events = @[];
        _userNames = @{};
    }
    return self;
}

- (void)dealloc {
    [_eventsListener remove];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.seedRecord.parentOrderNumber.length ? [NSString stringWithFormat:@"#%@", self.seedRecord.parentOrderNumber] : self.seedRecord.fulfillmentID;
    self.view.backgroundColor = PPF_CanvasColor();
    self.tableView.backgroundColor = PPF_CanvasColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    [self.tableView registerClass:[PPFulfillmentInfoCell class] forCellReuseIdentifier:@"Info"];
    [self.tableView registerClass:[PPF_StateCell class] forCellReuseIdentifier:@"State"];
    
    [self pp_buildHeader];
    [self pp_setupActionBar];
    [self loadDetail];
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = PPF_SurfaceColor();
    PPF_ApplyCardChrome(card, PPCornerCard);
    [header addSubview:card];
    
    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.72;
    hero.accentColorOverride = PPF_StatusColor(self.detailRecord.status);
    [card addSubview:hero];
    self.heroBackground = hero;

    PPF_AvatarView *cAvatar = [PPF_AvatarView new];
    cAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:cAvatar];

    UILabel *cName = [UILabel new];
    cName.translatesAutoresizingMaskIntoConstraints = NO;
    cName.font = [Styling fontBold:PPFontHeadline];
    cName.textColor = PPF_InkColor();
    [card addSubview:cName];

    UIImageView *routeArrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right"]];
    routeArrow.translatesAutoresizingMaskIntoConstraints = NO;
    routeArrow.tintColor = PPF_TertiaryInkColor();
    if ([Language isRTL]) routeArrow.transform = CGAffineTransformMakeScale(-1.0, 1.0);
    [card addSubview:routeArrow];

    PPF_AvatarView *oAvatar = [PPF_AvatarView new];
    oAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:oAvatar];

    UILabel *oName = [UILabel new];
    oName.translatesAutoresizingMaskIntoConstraints = NO;
    oName.font = [Styling fontBold:PPFontHeadline];
    oName.textColor = PPF_InkColor();
    [card addSubview:oName];

    UILabel *statusPill = [UILabel new];
    statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    statusPill.font = [Styling fontBold:PPFontFootnote];
    statusPill.textAlignment = NSTextAlignmentCenter;
    statusPill.layer.cornerRadius = 12.0;
    statusPill.layer.masksToBounds = YES;
    statusPill.tag = 5001;
    [card addSubview:statusPill];

    UILabel *modePill = [UILabel new];
    modePill.translatesAutoresizingMaskIntoConstraints = NO;
    modePill.font = [Styling fontMedium:PPFontCaption1];
    modePill.textColor = PPF_SubInkColor();
    modePill.tag = 5002;
    [card addSubview:modePill];

    NSString *custName = self.userNames[self.detailRecord.customerID] ?: self.detailRecord.customerName;
    if (!custName.length) custName = kLang(@"Fulfillment_UnknownCustomer");
    [cAvatar setName:custName isLarge:YES];
    cName.text = custName;

    BOOL isPlatform = [self.detailRecord.ownerType isEqualToString:@"platform"] || !self.detailRecord.ownerID.length;
    NSString *ownName = isPlatform ? kLang(@"Fulfillment_Filter_Platform") : (self.userNames[self.detailRecord.ownerID] ?: kLang(@"Fulfillment_UnknownCustomer"));
    [oAvatar setName:ownName isLarge:YES];
    oName.text = ownName;

    UIColor *sColor = PPF_StatusColor(self.detailRecord.status);
    statusPill.text = [NSString stringWithFormat:@"  %@  ", PPF_StatusText(self.detailRecord.status)];
    statusPill.textColor = sColor;
    statusPill.backgroundColor = [sColor colorWithAlphaComponent:0.12];
    modePill.text = [self.detailRecord.fulfillmentMode isEqualToString:@"partner_managed"] ? kLang(@"Fulfillment_Filter_Partner") : kLang(@"Fulfillment_Filter_Platform");

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:16.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],

        [hero.topAnchor constraintEqualToAnchor:card.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [cAvatar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [cAvatar.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],
        [cAvatar.widthAnchor constraintEqualToConstant:40.0],
        [cAvatar.heightAnchor constraintEqualToConstant:40.0],

        [cName.leadingAnchor constraintEqualToAnchor:cAvatar.trailingAnchor constant:10.0],
        [cName.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],

        [routeArrow.leadingAnchor constraintEqualToAnchor:cName.trailingAnchor constant:8.0],
        [routeArrow.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],
        [routeArrow.widthAnchor constraintEqualToConstant:16.0],
        [routeArrow.heightAnchor constraintEqualToConstant:16.0],

        [oAvatar.leadingAnchor constraintEqualToAnchor:routeArrow.trailingAnchor constant:8.0],
        [oAvatar.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],
        [oAvatar.widthAnchor constraintEqualToConstant:40.0],
        [oAvatar.heightAnchor constraintEqualToConstant:40.0],

        [oName.leadingAnchor constraintEqualToAnchor:oAvatar.trailingAnchor constant:10.0],
        [oName.centerYAnchor constraintEqualToAnchor:cAvatar.centerYAnchor],
        [oName.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16.0],

        [statusPill.leadingAnchor constraintEqualToAnchor:cAvatar.leadingAnchor],
        [statusPill.topAnchor constraintEqualToAnchor:cAvatar.bottomAnchor constant:16.0],
        [statusPill.heightAnchor constraintEqualToConstant:28.0],
        [statusPill.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18.0],

        [modePill.leadingAnchor constraintEqualToAnchor:statusPill.trailingAnchor constant:12.0],
        [modePill.centerYAnchor constraintEqualToAnchor:statusPill.centerYAnchor],
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_sizeHeaderToFit];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGRect frame = self.headerContainer.frame;
    frame.size.width = width;
    self.headerContainer.frame = frame;
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    frame.size.height = ceil(MAX(1.0, height));
    self.headerContainer.frame = frame;
    self.tableView.tableHeaderView = self.headerContainer;
}

- (void)pp_setupActionBar {
    UIBarButtonItem *overrideItem = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Fulfillment_AdminOverride") style:UIBarButtonItemStylePlain target:self action:@selector(presentAdminOverrideSheet)];
    overrideItem.tintColor = UIColor.systemRedColor;
    self.navigationItem.rightBarButtonItem = overrideItem;
}

- (void)loadDetail {
    self.isLoading = YES;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    
    [[PPFulfillmentService shared] fetchFulfillmentDetail:self.seedRecord.fulfillmentID completion:^(PPFulfillmentRecord *detail, NSArray *events, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            if (error) {
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                weakSelf.detailRecord = detail ?: weakSelf.seedRecord;
                weakSelf.events = events ?: @[];
                [weakSelf pp_buildHeader];
            }
            [weakSelf.tableView reloadData];
        });
    }];

    // Live event timeline
    self.eventsListener = [[PPFulfillmentService shared] observeFulfillmentEvents:self.seedRecord.fulfillmentID completion:^(NSArray<NSDictionary *> *events, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!error && events.count > 0) {
                weakSelf.events = events;
                [weakSelf.tableView reloadData];
            }
        });
    }];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5; // Overview, Composition, Settlement, Audit (if present), Timeline
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isLoading) return section == 0 ? 1 : 0;
    PPFulfillmentRecord *r = self.detailRecord ?: self.seedRecord;
    
    if (section == 0) return 4; // Order, Fulfillment Ref, Created, Updated
    if (section == 1) return MAX(r.items.count, 1);
    if (section == 2) return 3; // Subtotal, Platform Commission, Provider Net
    if (section == 3) return r.adminOverrideAt ? 1 : 0;
    return MAX(self.events.count, 1);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 3 && !self.detailRecord.adminOverrideAt) return 0.01;
    return 38.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 3 && !self.detailRecord.adminOverrideAt) return [UIView new];
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [Styling fontBold:PPFontTitle3];
    label.textColor = PPF_InkColor();
    label.textAlignment = [Language alignmentForCurrentLanguage];
    
    if (section == 0) label.text = kLang(@"Fulfillment_DetailOverview");
    else if (section == 1) label.text = kLang(@"Fulfillment_DetailItems");
    else if (section == 2) label.text = kLang(@"Fulfillment_DetailSettlement");
    else if (section == 3) label.text = kLang(@"Fulfillment_AdminOverride");
    else label.text = kLang(@"Fulfillment_DetailTimeline");
    
    [view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:PPScreenMargin],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-PPScreenMargin],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-4.0]
    ]];
    return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isLoading) {
        PPF_StateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"State" forIndexPath:indexPath];
        [cell configureWithText:kLang(@"Loading") loading:YES];
        return cell;
    }

    PPFulfillmentRecord *r = self.detailRecord ?: self.seedRecord;
    
    // Overview Section
    if (indexPath.section == 0) {
        PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
        NSArray *titles = @[kLang(@"Fulfillment_DetailOrder"), kLang(@"Fulfillment_DetailOverview"), kLang(@"Fulfillment_DetailCreated"), kLang(@"Fulfillment_DetailUpdated")];
        NSString *orderNum = r.parentOrderNumber.length ? r.parentOrderNumber : r.parentOrderID;
        NSArray *values = @[
            orderNum.length ? [NSString stringWithFormat:@"#%@", orderNum] : @"-",
            r.fulfillmentID ?: @"-",
            PPF_DateString(r.createdAt),
            PPF_DateString(r.updatedAt)
        ];
        [cell configureTitle:titles[indexPath.row] value:values[indexPath.row] isEmphasized:NO];
        return cell;
    }

    // Items Section
    if (indexPath.section == 1) {
        PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
        if (r.items.count == 0) {
            [cell configureTitle:kLang(@"Fulfillment_Item") value:kLang(@"Fulfillment_NoItems") isEmphasized:NO];
            return cell;
        }
        NSDictionary *item = [r.items[indexPath.row] isKindOfClass:NSDictionary.class] ? r.items[indexPath.row] : @{};
        NSString *name = PPSafeString(item[@"name"]);
        if (!name.length) name = PPSafeString(item[@"title"]);
        if (!name.length) name = PPSafeString(item[@"itemName"]);
        if (!name.length) name = PPSafeString(item[@"itemId"]);
        NSNumber *qty = item[@"quantity"] ?: item[@"qty"] ?: @(1);
        NSNumber *price = item[@"price"];
        NSString *currency = r.money[@"currency"];
        
        NSString *title = [NSString stringWithFormat:@"%02ld. %@", (long)(indexPath.row + 1), name.length ? name : kLang(@"Fulfillment_Item")];
        NSString *value = [NSString stringWithFormat:@"×%@  •  %@", qty, PPF_MoneyString(price, currency)];
        [cell configureTitle:title value:value isEmphasized:NO];
        return cell;
    }

    // Settlement Section
    if (indexPath.section == 2) {
        PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
        NSDictionary *m = r.money ?: @{};
        NSString *currency = m[@"currency"];
        if (indexPath.row == 0) {
            [cell configureTitle:kLang(@"Fulfillment_Subtotal") value:PPF_MoneyString(m[@"subtotal"], currency) isEmphasized:NO];
        } else if (indexPath.row == 1) {
            [cell configureTitle:kLang(@"Fulfillment_PlatformCommission") value:PPF_MoneyString(m[@"platformCommission"], currency) isEmphasized:NO];
        } else {
            [cell configureTitle:kLang(@"Fulfillment_ProviderNet") value:PPF_MoneyString(m[@"providerNet"], currency) isEmphasized:YES];
        }
        return cell;
    }

    // Admin Audit Section
    if (indexPath.section == 3) {
        PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
        NSString *date = PPF_DateString(r.adminOverrideAt);
        NSString *by = r.adminOverrideBy.length ? r.adminOverrideBy : kLang(@"Fulfillment_Event");
        NSString *reason = r.adminOverrideReason.length ? r.adminOverrideReason : @"-";
        NSString *val = [NSString stringWithFormat:@"%@ - %@\n%@", date, by, reason];
        [cell configureTitle:kLang(@"Fulfillment_AdminOverride") value:val isEmphasized:NO];
        return cell;
    }

    // Timeline Section
    PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
    if (self.events.count == 0) {
        [cell configureTitle:kLang(@"Fulfillment_Event") value:kLang(@"Fulfillment_NoEvents") isEmphasized:NO];
        return cell;
    }
    NSDictionary *event = [self.events[indexPath.row] isKindOfClass:NSDictionary.class] ? self.events[indexPath.row] : @{};
    NSString *action = PPSafeString(event[@"action"]);
    if (!action.length) action = PPSafeString(event[@"type"]);
    NSString *fromS = PPF_StatusText(event[@"fromStatus"]);
    NSString *toS = PPF_StatusText(event[@"toStatus"]);
    id createdAt = event[@"createdAt"];
    NSDate *date = [createdAt isKindOfClass:FIRTimestamp.class] ? [(FIRTimestamp *)createdAt dateValue] : nil;
    
    NSString *title = [action stringByReplacingOccurrencesOfString:@"_" withString:@" "].capitalizedString;
    NSString *value = [NSString stringWithFormat:@"%@ → %@\n%@", fromS, toS, PPF_DateString(date)];
    [cell configureTitle:title value:value isEmphasized:NO];
    return cell;
}

#pragma mark - Admin Override Action

- (void)presentAdminOverrideSheet {
    PPHapticTouch();
    PPFulfillmentRecord *r = self.detailRecord ?: self.seedRecord;
    NSArray *allowedTargets = [PPFulfillmentService allowedOverrideTargetsForStatus:r.status];
    
    if (allowedTargets.count == 0) {
        [AlertHelper showAlertIn:self title:kLang(@"Fulfillment_AdminOverride") subtitle:kLang(@"Fulfillment_OverrideSkipped")];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Fulfillment_AdminOverride")
                                                                   message:kLang(@"Fulfillment_ReasonPlaceholder")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *targetStatus in allowedTargets) {
        NSString *title = PPF_StatusText(targetStatus);
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self promptReasonAndSubmitOverrideForTargetStatus:targetStatus];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptReasonAndSubmitOverrideForTargetStatus:(NSString *)targetStatus {
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ → %@", kLang(@"Fulfillment_TargetStatus"), PPF_StatusText(targetStatus)]
                                                                    message:kLang(@"Fulfillment_Reason")
                                                             preferredStyle:UIAlertControllerStyleAlert];
    
    [prompt addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Fulfillment_ReasonPlaceholder");
    }];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Fulfillment_NotePlaceholder");
    }];

    __weak typeof(self) weakSelf = self;
    [prompt addAction:[UIAlertAction actionWithTitle:kLang(@"Fulfillment_ConfirmOverride") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSString *reason = prompt.textFields.firstObject.text;
        NSString *note = prompt.textFields.count > 1 ? prompt.textFields[1].text : @"";
        
        if (!reason.length) {
            PPHapticError();
            [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:kLang(@"Fulfillment_Reason")];
            return;
        }
        
        PPHapticTouch();
        [[PPFulfillmentService shared] adminOverrideFulfillment:weakSelf.seedRecord.fulfillmentID
                                                   targetStatus:targetStatus
                                                         reason:reason
                                                           note:note
                                                         notify:YES
                                                     completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    PPHapticError();
                    [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                } else {
                    PPHapticSuccess();
                    [AlertHelper showAlertIn:weakSelf title:kLang(@"Success") subtitle:kLang(@"Fulfillment_OverrideSuccess")];
                    [weakSelf loadDetail];
                }
            });
        }];
    }]];
    
    [prompt addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:prompt animated:YES completion:nil];
}

@end

#pragma mark - Main List View Controller

@interface PPFulfillmentOrdersViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<PPFulfillmentRecord *> *records;
@property (nonatomic, strong) NSArray<PPFulfillmentRecord *> *visibleRecords;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *userNames;
@property (nonatomic, strong) id<FIRListenerRegistration> fulfillmentsListener;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) PPF_MetricsCardView *metricsView;

@property (nonatomic, copy) NSString *filterStatus;
@property (nonatomic, copy) NSString *filterOwnerType;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@end

@implementation PPFulfillmentOrdersViewController

- (void)dealloc {
    [_fulfillmentsListener remove];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Fulfillment_Title");
    self.records = @[];
    self.visibleRecords = @[];
    self.userNames = @{};
    self.filterStatus = @"";
    self.filterOwnerType = @"";

    [self pp_configureTableView];
    [self pp_configureSearch];
    [self pp_buildHeader];
    [self pp_setupNavigationItems];

    [self startLiveSubscription];
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPF_CanvasColor();
    self.tableView.backgroundColor = PPF_CanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 110.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    
    [self.tableView registerClass:[PPF_OrderCell class] forCellReuseIdentifier:@"Order"];
    [self.tableView registerClass:[PPF_StateCell class] forCellReuseIdentifier:@"State"];

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = PPF_AccentColor();
    [refresh addTarget:self action:@selector(startLiveSubscription) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)pp_configureSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = kLang(@"Fulfillment_SearchPlaceholder");
    self.searchController.searchBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.searchController.searchBar.tintColor = PPF_AccentColor();
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)pp_setupNavigationItems {
    UIBarButtonItem *filterItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(presentFilterOptionsSheet)];
    filterItem.tintColor = PPF_AccentColor();

    UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(startLiveSubscription)];
    refreshItem.tintColor = PPF_AccentColor();

    self.navigationItem.rightBarButtonItems = @[refreshItem, filterItem];
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:card];

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.72;
    hero.accentColorOverride = PPF_AccentColor();
    [card addSubview:hero];
    self.heroBackground = hero;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = kLang(@"Fulfillment_Title");
    title.font = [Styling fontBold:PPFontTitle1];
    title.textColor = PPF_InkColor();

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = kLang(@"Fulfillment_Subtitle");
    subtitle.font = [Styling fontRegular:PPFontSubheadline];
    subtitle.textColor = PPF_SubInkColor();
    subtitle.numberOfLines = 2;

    _metricsView = [PPF_MetricsCardView new];
    _metricsView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:_metricsView];
    [card addSubview:title];
    [card addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:16.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],

        [hero.topAnchor constraintEqualToAnchor:card.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:20.0],
        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],

        [_metricsView.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:16.0],
        [_metricsView.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_metricsView.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [_metricsView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20.0],
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_sizeHeaderToFit];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGRect frame = self.headerContainer.frame;
    frame.size.width = width;
    self.headerContainer.frame = frame;
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    frame.size.height = ceil(MAX(1.0, height));
    self.headerContainer.frame = frame;
    self.tableView.tableHeaderView = self.headerContainer;
}

- (void)startLiveSubscription {
    self.isLoading = YES;
    self.errorMessage = nil;
    [self.tableView reloadData];

    [_fulfillmentsListener remove];
    __weak typeof(self) weakSelf = self;

    self.fulfillmentsListener = [[PPFulfillmentService shared] observeFulfillmentsWithCompletion:^(NSArray<PPFulfillmentRecord *> *records, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            [weakSelf.refreshControl endRefreshing];
            if (error) {
                weakSelf.errorMessage = error.localizedDescription;
            } else {
                weakSelf.records = records ?: @[];
                weakSelf.errorMessage = nil;
                [weakSelf fetchUserNamesForRecords:weakSelf.records];
            }
            [weakSelf pp_applySearchAndFilters];
        });
    }];
}

- (void)fetchUserNamesForRecords:(NSArray<PPFulfillmentRecord *> *)records {
    NSMutableSet *uids = [NSMutableSet set];
    for (PPFulfillmentRecord *r in records) {
        if (r.customerID.length) [uids addObject:r.customerID];
        if (r.ownerID.length) [uids addObject:r.ownerID];
    }
    
    __weak typeof(self) weakSelf = self;
    [[PPFulfillmentService shared] resolveUserProfilesForIDs:uids.allObjects completion:^(NSDictionary<NSString *,NSString *> *names) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (names.count > 0) {
                NSMutableDictionary *next = [NSMutableDictionary dictionaryWithDictionary:weakSelf.userNames];
                [next addEntriesFromDictionary:names];
                weakSelf.userNames = next;
                [weakSelf pp_applySearchAndFilters];
            }
        });
    }];
}

- (void)pp_applySearchAndFilters {
    // 1. Calculate metrics
    NSInteger active = 0;
    NSInteger waiting = 0;
    NSInteger completed = 0;
    double providerNet = 0.0;
    NSString *curr = @"QAR";

    NSSet *terminalStatuses = [NSSet setWithArray:@[@"completed", @"cancelled", @"rejected", @"failed", @"returned"]];
    NSSet *waitingStatuses = [NSSet setWithArray:@[@"new_request", @"delivery_requested", @"awaiting_handover"]];

    for (PPFulfillmentRecord *r in self.records) {
        NSString *s = r.status.lowercaseString;
        if (![terminalStatuses containsObject:s]) active++;
        if ([waitingStatuses containsObject:s]) waiting++;
        if ([s isEqualToString:@"completed"]) completed++;
        
        NSNumber *net = r.money[@"providerNet"];
        if (net) providerNet += net.doubleValue;
        if (r.money[@"currency"]) curr = r.money[@"currency"];
    }

    [self.metricsView updateWithActive:active waiting:waiting completed:completed providerNet:providerNet currency:curr];

    // 2. Filter records
    NSString *query = [self.searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    
    NSMutableArray *filtered = [NSMutableArray array];
    for (PPFulfillmentRecord *r in self.records) {
        if (self.filterStatus.length > 0 && ![r.status isEqualToString:self.filterStatus]) {
            continue;
        }
        if (self.filterOwnerType.length > 0 && ![r.ownerType isEqualToString:self.filterOwnerType]) {
            continue;
        }
        if (query.length > 0) {
            NSString *custName = self.userNames[r.customerID] ?: r.customerName;
            NSString *ownName = self.userNames[r.ownerID] ?: @"";
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@",
                                  r.fulfillmentID ?: @"",
                                  r.parentOrderID ?: @"",
                                  r.parentOrderNumber ?: @"",
                                  r.customerID ?: @"",
                                  r.ownerID ?: @"",
                                  custName ?: @"",
                                  ownName ?: @""];
            if (![haystack.lowercaseString containsString:query]) {
                continue;
            }
        }
        [filtered addObject:r];
    }
    
    self.visibleRecords = filtered;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self pp_applySearchAndFilters];
}

#pragma mark - Filter Action Sheet

- (void)presentFilterOptionsSheet {
    PPHapticTouch();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"Fulfillment_Filter_AllStatuses")
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Fulfillment_Filter_AllStatuses") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.filterStatus = @"";
        [weakSelf pp_applySearchAndFilters];
    }]];

    // Unique statuses in records
    NSMutableSet *statuses = [NSMutableSet set];
    for (PPFulfillmentRecord *r in self.records) {
        if (r.status.length) [statuses addObject:r.status];
    }

    for (NSString *st in statuses.allObjects) {
        [sheet addAction:[UIAlertAction actionWithTitle:PPF_StatusText(st) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            weakSelf.filterStatus = st;
            [weakSelf pp_applySearchAndFilters];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Fulfillment_Filter_Clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        weakSelf.filterStatus = @"";
        weakSelf.filterOwnerType = @"";
        [weakSelf pp_applySearchAndFilters];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.visibleRecords.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.visibleRecords.count == 0) {
        PPF_StateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"State" forIndexPath:indexPath];
        NSString *text = self.isLoading ? kLang(@"Loading") : (self.errorMessage.length ? self.errorMessage : kLang(@"Fulfillment_Empty"));
        [cell configureWithText:text loading:self.isLoading];
        return cell;
    }

    PPFulfillmentRecord *record = self.visibleRecords[indexPath.row];
    PPF_OrderCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Order" forIndexPath:indexPath];
    
    NSString *cName = self.userNames[record.customerID] ?: record.customerName;
    NSString *oName = self.userNames[record.ownerID];
    
    [cell configureWithRecord:record customerName:cName ownerName:oName animated:YES];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.visibleRecords.count) return;

    PPHapticTouch();
    PPFulfillmentRecord *record = self.visibleRecords[indexPath.row];
    PPFulfillmentDetailViewController *detail = [[PPFulfillmentDetailViewController alloc] initWithRecord:record];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
