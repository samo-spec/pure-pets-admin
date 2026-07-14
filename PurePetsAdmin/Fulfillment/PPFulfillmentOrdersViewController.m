#import "PPFulfillmentOrdersViewController.h"
#import "PPFulfillmentService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "PPHero.h"
#import "PPDesignTokens.h"
@import FirebaseFirestore;

#pragma mark - Colors & Constants

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
    if ([status isEqualToString:@"completed"] || [status isEqualToString:@"accepted"]) return UIColor.systemGreenColor;
    if ([status isEqualToString:@"rejected"] || [status isEqualToString:@"cancelled"]) return UIColor.systemRedColor;
    if ([status isEqualToString:@"delivery_requested"] || [status isEqualToString:@"in_progress"]) return UIColor.systemBlueColor;
    if ([status isEqualToString:@"preparing"]) return UIColor.systemOrangeColor;
    return PPF_AccentColor();
}

static inline NSString *PPF_StatusKey(NSString *status) {
    NSString *s = status ?: @"";
    if ([s isEqualToString:@"new_request"]) return @"Fulfillment_Status_NewRequest";
    if ([s isEqualToString:@"preparing"]) return @"Fulfillment_Status_Preparing";
    if ([s isEqualToString:@"delivery_requested"]) return @"Fulfillment_Status_DeliveryRequested";
    if ([s isEqualToString:@"accepted"]) return @"Fulfillment_Status_Accepted";
    if ([s isEqualToString:@"rejected"]) return @"Fulfillment_Status_Rejected";
    if ([s isEqualToString:@"completed"]) return @"Fulfillment_Status_Completed";
    if ([s isEqualToString:@"cancelled"]) return @"Fulfillment_Status_Cancelled";
    if ([s isEqualToString:@"pending"]) return @"Fulfillment_Status_Pending";
    if ([s isEqualToString:@"in_progress"]) return @"Fulfillment_Status_InProgress";
    return @"Fulfillment_Status_Unknown";
}

static inline NSString *PPF_StatusText(NSString *status) {
    if (!status || status.length == 0) return kLang(@"Fulfillment_Status_Unknown");
    NSString *key = PPF_StatusKey(status);
    NSString *localized = kLang(key);
    if (localized.length > 0 && ![localized isEqualToString:key]) return localized;
    return status;
}

static inline NSString *PPF_DateString(NSDate *date) {
    if (!date) return kLang(@"Fulfillment_Date_Unknown");
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    return [f stringFromDate:date];
}

static inline NSString *PPF_SafeString(id v) {
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v respondsToSelector:@selector(stringValue)]) return [v stringValue];
    return @"";
}

static inline void PPF_ApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    view.layer.shadowRadius = 22.0;
    view.layer.shadowOpacity = 0.052;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.62].CGColor;
}

#pragma mark - Cells

@interface PPF_OrderCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *orderLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, assign) BOOL hasAnimatedEntrance;
- (void)configureWithRecord:(PPFulfillmentRecord *)record animated:(BOOL)animated;
- (void)prepareForEntrance;
- (void)runEntrance;
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

        _symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shippingbox.fill"]];
        _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolView.contentMode = UIViewContentModeCenter;
        _symbolView.tintColor = PPF_AccentColor();
        _symbolView.backgroundColor = [PPF_AccentColor() colorWithAlphaComponent:0.11];
        _symbolView.layer.cornerRadius = 18.0;
        if (@available(iOS 13.0, *)) _symbolView.layer.cornerCurve = kCACornerCurveContinuous;
        _symbolView.clipsToBounds = YES;
        [_cardView addSubview:_symbolView];

        _orderLabel = [UILabel new];
        _orderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _orderLabel.font = [Styling fontBold:PPFontBody];
        _orderLabel.textColor = PPF_InkColor();
        _orderLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _orderLabel.numberOfLines = 1;
        _orderLabel.adjustsFontForContentSizeCategory = YES;
        _orderLabel.adjustsFontSizeToFitWidth = YES;
        _orderLabel.minimumScaleFactor = 0.76;
        [_cardView addSubview:_orderLabel];

        _detailLabel = [UILabel new];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [Styling fontRegular:PPFontFootnote];
        _detailLabel.textColor = PPF_SubInkColor();
        _detailLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _detailLabel.numberOfLines = 2;
        _detailLabel.adjustsFontForContentSizeCategory = YES;
        [_cardView addSubview:_detailLabel];

        _statusLabel = [UILabel new];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = [Styling fontBold:PPFontCaption2];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.layer.cornerRadius = 12.0;
        _statusLabel.layer.masksToBounds = YES;
        _statusLabel.adjustsFontSizeToFitWidth = YES;
        _statusLabel.minimumScaleFactor = 0.72;
        _statusLabel.adjustsFontForContentSizeCategory = YES;
        [_cardView addSubview:_statusLabel];

        UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward"]];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        chevron.tintColor = [PPF_TertiaryInkColor() colorWithAlphaComponent:0.55];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        [_cardView addSubview:chevron];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0],
            [_cardView.heightAnchor constraintGreaterThanOrEqualToConstant:88.0],

            [_symbolView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_symbolView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_symbolView.widthAnchor constraintEqualToConstant:46.0],
            [_symbolView.heightAnchor constraintEqualToConstant:46.0],

            [chevron.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],
            [chevron.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [chevron.widthAnchor constraintEqualToConstant:10.0],
            [chevron.heightAnchor constraintEqualToConstant:16.0],

            [_statusLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-12.0],
            [_statusLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:18.0],
            [_statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:92.0],
            [_statusLabel.heightAnchor constraintEqualToConstant:26.0],

            [_orderLabel.leadingAnchor constraintEqualToAnchor:_symbolView.trailingAnchor constant:14.0],
            [_orderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-12.0],
            [_orderLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:17.0],

            [_detailLabel.leadingAnchor constraintEqualToAnchor:_orderLabel.leadingAnchor],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-22.0],
            [_detailLabel.topAnchor constraintEqualToAnchor:_orderLabel.bottomAnchor constant:6.0],
            [_detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-17.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _hasAnimatedEntrance = NO;
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
    _orderLabel.text = nil;
    _detailLabel.text = nil;
    _statusLabel.text = nil;
    _statusLabel.backgroundColor = UIColor.clearColor;
    _symbolView.image = [UIImage systemImageNamed:@"shippingbox.fill"];
    _symbolView.tintColor = PPF_AccentColor();
    _symbolView.backgroundColor = [PPF_AccentColor() colorWithAlphaComponent:0.11];
}

- (void)prepareForEntrance {
    self.contentView.alpha = 0.0;
    self.contentView.transform = CGAffineTransformMakeTranslation(0.0, 14.0);
}

- (void)runEntrance {
    _hasAnimatedEntrance = YES;
    [UIView animateWithDuration:0.38
                          delay:0
         usingSpringWithDamping:0.88
          initialSpringVelocity:0.4
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.contentView.alpha = 1.0;
        self.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)configureWithRecord:(PPFulfillmentRecord *)record animated:(BOOL)animated {
    NSString *orderNumber = record.parentOrderNumber.length ? record.parentOrderNumber : record.fulfillmentID;
    self.orderLabel.text = [NSString stringWithFormat:@"#%@", orderNumber ?: @"-"];

    NSString *itemsFormat = kLang(@"Fulfillment_ItemsCount_Format");
    NSString *items = [NSString stringWithFormat:itemsFormat, @(record.items.count)];
    self.detailLabel.text = [NSString stringWithFormat:@"%@ - %@ - %@",
                             record.customerName.length ? record.customerName : kLang(@"Fulfillment_UnknownCustomer"),
                             record.fulfillmentMode.length ? record.fulfillmentMode : kLang(@"Fulfillment_UnknownMode"),
                             items];

    UIColor *statusColor = PPF_StatusColor(record.status);
    self.statusLabel.text = PPF_StatusText(record.status);
    self.statusLabel.textColor = statusColor;
    self.statusLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.12];
    self.symbolView.tintColor = statusColor;
    self.symbolView.backgroundColor = [statusColor colorWithAlphaComponent:0.12];

    if (animated && !_hasAnimatedEntrance) {
        [self prepareForEntrance];
        [self runEntrance];
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    if (highlighted) {
        [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.contentView.transform = CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown);
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            self.contentView.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

@end

#pragma mark - Info Cell (Premium)

@interface PPFulfillmentInfoCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
- (void)configureTitle:(NSString *)title value:(NSString *)value symbolName:(NSString *)symbolName tint:(UIColor *)tint;
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
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        [_cardView addSubview:_titleLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:PPFontBody];
        _valueLabel.textColor = PPF_InkColor();
        _valueLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _valueLabel.numberOfLines = 0;
        _valueLabel.adjustsFontForContentSizeCategory = YES;
        [_cardView addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [_cardView.heightAnchor constraintGreaterThanOrEqualToConstant:60.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],

            [_valueLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_valueLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _titleLabel.text = nil;
    _valueLabel.text = nil;
}

- (void)configureTitle:(NSString *)title value:(NSString *)value symbolName:(NSString *)symbolName tint:(UIColor *)tint {
    (void)symbolName; (void)tint;
    self.titleLabel.text = title ?: @"";
    self.valueLabel.text = value.length ? value : @"-";
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
        self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _messageLabel = [UILabel new];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.font = [Styling fontMedium:PPFontCallout];
        _messageLabel.textColor = PPF_SubInkColor();
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 0;
        _messageLabel.adjustsFontForContentSizeCategory = YES;
        [self.contentView addSubview:_messageLabel];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        _spinner.color = PPF_AccentColor();
        [self.contentView addSubview:_spinner];

        [NSLayoutConstraint activateConstraints:@[
            [_messageLabel.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_messageLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_messageLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:PPSpaceXL],
            [_messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-PPSpaceXL],

            [_spinner.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_spinner.topAnchor constraintEqualToAnchor:_messageLabel.bottomAnchor constant:PPSpaceMD],
            [_spinner.heightAnchor constraintEqualToConstant:24],
            [_spinner.widthAnchor constraintEqualToConstant:24],

            [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:200],
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
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL didRunEntrance;
@property (nonatomic, assign) BOOL isAdjustingHeaderSize;
@property (nonatomic, assign) CGFloat lastHeaderWidth;
@property (nonatomic, assign) CGFloat lastHeaderHeight;
@end

@implementation PPFulfillmentDetailViewController

- (instancetype)initWithRecord:(PPFulfillmentRecord *)record {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _seedRecord = record;
        _detailRecord = record;
        _events = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.seedRecord.parentOrderNumber.length ? self.seedRecord.parentOrderNumber : self.seedRecord.fulfillmentID;
    self.view.backgroundColor = PPF_CanvasColor();
    self.tableView.backgroundColor = PPF_CanvasColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.showsVerticalScrollIndicator = NO;
    [self.tableView registerClass:[PPFulfillmentInfoCell class] forCellReuseIdentifier:@"Info"];
    [self.tableView registerClass:[PPF_StateCell class] forCellReuseIdentifier:@"State"];
    [self pp_buildHeader];
    [self loadDetail];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self prepareEntranceState];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroBackground startAnimations];
    [self runEntranceIfNeeded];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.heroBackground stopAnimations];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_updateInsets];
    [self pp_sizeHeaderToFit];
    if (!_didPrepareEntrance) {
        [self prepareEntranceState];
    }
}

- (void)prepareEntranceState {
    if (_didRunEntrance) return;
    _didPrepareEntrance = YES;
    self.heroBackground.alpha = 0;
    self.heroBackground.transform = CGAffineTransformMakeScale(1.04, 1.04);
    UILabel *title = [self.headerContainer viewWithTag:3001];
    UILabel *subtitle = [self.headerContainer viewWithTag:3002];
    UILabel *status = [self.headerContainer viewWithTag:3003];
    if (title) { title.alpha = 0; title.transform = CGAffineTransformMakeTranslation(0, 14); }
    if (subtitle) { subtitle.alpha = 0; subtitle.transform = CGAffineTransformMakeTranslation(0, 10); }
    if (status) { status.alpha = 0; status.transform = CGAffineTransformMakeTranslation(0, 10); }
}

- (void)runEntranceIfNeeded {
    if (_didRunEntrance) return;
    _didRunEntrance = YES;
    [self.view layoutIfNeeded];

    [UIView animateWithDuration:0.48 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.heroBackground.alpha = 1;
        self.heroBackground.transform = CGAffineTransformIdentity;
    } completion:nil];

    UILabel *title = [self.headerContainer viewWithTag:3001];
    UILabel *subtitle = [self.headerContainer viewWithTag:3002];
    UILabel *status = [self.headerContainer viewWithTag:3003];

    [UIView animateWithDuration:0.42 delay:0.08 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (title) { title.alpha = 1; title.transform = CGAffineTransformIdentity; }
    } completion:nil];

    [UIView animateWithDuration:0.42 delay:0.16 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (subtitle) { subtitle.alpha = 1; subtitle.transform = CGAffineTransformIdentity; }
    } completion:nil];

    [UIView animateWithDuration:0.48 delay:0.22 usingSpringWithDamping:0.86 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        if (status) { status.alpha = 1; status.transform = CGAffineTransformIdentity; }
    } completion:nil];
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:card];

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.72;
    hero.accentColorOverride = PPF_StatusColor(self.detailRecord.status);
    [card addSubview:hero];
    self.heroBackground = hero;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [Styling fontBold:PPFontTitle1];
    title.textColor = PPF_InkColor();
    title.textAlignment = [Language alignmentForCurrentLanguage];
    title.numberOfLines = 2;
    title.tag = 3001;
    [card addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.font = [Styling fontRegular:PPFontSubheadline];
    subtitle.textColor = PPF_SubInkColor();
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.numberOfLines = 2;
    subtitle.tag = 3002;
    [card addSubview:subtitle];

    UILabel *status = [UILabel new];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [Styling fontBold:PPFontFootnote];
    status.textAlignment = NSTextAlignmentCenter;
    status.layer.cornerRadius = 14.0;
    status.layer.masksToBounds = YES;
    status.tag = 3003;
    [card addSubview:status];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:18.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14.0],
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:168.0],

        [hero.topAnchor constraintEqualToAnchor:card.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [status.topAnchor constraintEqualToAnchor:card.topAnchor constant:24.0],
        [status.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [status.widthAnchor constraintGreaterThanOrEqualToConstant:104.0],
        [status.heightAnchor constraintEqualToConstant:30.0],

        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:status.leadingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:28.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12.0],
        [subtitle.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-24.0],
    ]];
    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_refreshHeaderText];
    [self pp_sizeHeaderToFit];
}

- (void)pp_refreshHeaderText {
    UILabel *title = [self.headerContainer viewWithTag:3001];
    UILabel *subtitle = [self.headerContainer viewWithTag:3002];
    UILabel *status = [self.headerContainer viewWithTag:3003];
    PPFulfillmentRecord *record = self.detailRecord ?: self.seedRecord;
    NSString *order = record.parentOrderNumber.length ? record.parentOrderNumber : record.fulfillmentID;
    title.text = [NSString stringWithFormat:@"#%@", order ?: @"-"];
    NSString *itemsFormat = kLang(@"Fulfillment_ItemsCount_Format");
    subtitle.text = [NSString stringWithFormat:@"%@ - %@ - %@",
                     record.customerName.length ? record.customerName : kLang(@"Fulfillment_UnknownCustomer"),
                     record.fulfillmentMode.length ? record.fulfillmentMode : kLang(@"Fulfillment_UnknownMode"),
                     [NSString stringWithFormat:itemsFormat, @(record.items.count)]];
    UIColor *color = PPF_StatusColor(record.status);
    status.text = PPF_StatusText(record.status);
    status.textColor = color;
    status.backgroundColor = [color colorWithAlphaComponent:0.12];
    self.heroBackground.accentColorOverride = color;
    [self.heroBackground reapplyPalette];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer || self.isAdjustingHeaderSize) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGRect frame = self.headerContainer.frame;
    BOOL widthChanged = fabs(frame.size.width - width) > 0.5;
    if (widthChanged) {
        frame.size.width = width;
        self.headerContainer.frame = frame;
    }
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat targetHeight = ceil(MAX(1.0, height));
    BOOL heightChanged = fabs(frame.size.height - targetHeight) > 0.5;
    if (!widthChanged && !heightChanged &&
        fabs(self.lastHeaderWidth - width) <= 0.5 &&
        fabs(self.lastHeaderHeight - targetHeight) <= 0.5) {
        return;
    }
    frame.size.width = width;
    frame.size.height = targetHeight;
    self.isAdjustingHeaderSize = YES;
    self.headerContainer.frame = frame;
    self.tableView.tableHeaderView = self.headerContainer;
    self.lastHeaderWidth = width;
    self.lastHeaderHeight = targetHeight;
    self.isAdjustingHeaderSize = NO;
}

- (void)pp_updateInsets {
    CGFloat tabHeight = self.tabBarController ? CGRectGetHeight(self.tabBarController.tabBar.bounds) : 0.0;
    UIEdgeInsets inset = self.tableView.contentInset;
    inset.bottom = MAX(28.0, tabHeight + 34.0);
    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.contentInset, inset)) {
        self.tableView.contentInset = inset;
    }
    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.scrollIndicatorInsets, inset)) {
        self.tableView.scrollIndicatorInsets = inset;
    }
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
                [weakSelf pp_refreshHeaderText];
            }
            [weakSelf.tableView reloadData];
        });
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isLoading) return section == 0 ? 1 : 0;
    if (section == 0) return 6;
    if (section == 1) return MAX(self.detailRecord.items.count, 1);
    return MAX(self.events.count, 1);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 42.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [Styling fontBold:PPFontTitle3];
    label.textColor = PPF_InkColor();
    label.textAlignment = [Language alignmentForCurrentLanguage];
    if (section == 0) label.text = kLang(@"Fulfillment_DetailOverview");
    else if (section == 1) label.text = kLang(@"Fulfillment_DetailItems");
    else label.text = kLang(@"Fulfillment_DetailTimeline");
    [view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:PPScreenMargin],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-PPScreenMargin],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-6.0]
    ]];
    return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isLoading) {
        PPF_StateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"State" forIndexPath:indexPath];
        [cell configureWithText:kLang(@"Loading") loading:YES];
        return cell;
    }

    PPFulfillmentRecord *record = self.detailRecord ?: self.seedRecord;
    if (indexPath.section == 0) {
        PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
        NSArray *titles = @[kLang(@"Fulfillment_DetailOrder"), kLang(@"Fulfillment_DetailCustomer"), kLang(@"Fulfillment_DetailMode"), kLang(@"Fulfillment_DetailOwner"), kLang(@"Fulfillment_DetailCreated"), kLang(@"Fulfillment_DetailUpdated")];
        NSArray *values = @[
            record.parentOrderNumber.length ? record.parentOrderNumber : record.parentOrderID ?: @"-",
            record.customerName.length ? record.customerName : kLang(@"Fulfillment_UnknownCustomer"),
            record.fulfillmentMode.length ? record.fulfillmentMode : kLang(@"Fulfillment_UnknownMode"),
            record.ownerID.length ? record.ownerID : @"-",
            PPF_DateString(record.createdAt),
            PPF_DateString(record.updatedAt)
        ];
        [cell configureTitle:titles[indexPath.row] value:values[indexPath.row] symbolName:nil tint:nil];
        return cell;
    }

    if (indexPath.section == 1) {
        PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
        if (record.items.count == 0) {
            [cell configureTitle:kLang(@"Fulfillment_Item") value:kLang(@"Fulfillment_NoItems") symbolName:nil tint:nil];
            return cell;
        }
        NSDictionary *item = [record.items[indexPath.row] isKindOfClass:NSDictionary.class] ? record.items[indexPath.row] : @{};
        NSString *name = PPF_SafeString(item[@"title"]);
        if (!name.length) name = PPF_SafeString(item[@"name"]);
        if (!name.length) name = PPF_SafeString(item[@"productName"]);
        if (!name.length) name = PPF_SafeString(item[@"id"]);
        NSString *quantity = PPF_SafeString(item[@"quantity"]);
        if (!quantity.length) quantity = PPF_SafeString(item[@"qty"]);
        NSString *value = quantity.length ? [NSString stringWithFormat:@"%@ x %@", quantity, name.length ? name : kLang(@"Fulfillment_Item")] : (name.length ? name : kLang(@"Fulfillment_Item"));
        [cell configureTitle:kLang(@"Fulfillment_Item") value:value symbolName:nil tint:nil];
        return cell;
    }

    PPFulfillmentInfoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Info" forIndexPath:indexPath];
    if (self.events.count == 0) {
        [cell configureTitle:kLang(@"Fulfillment_Event") value:kLang(@"Fulfillment_NoEvents") symbolName:nil tint:nil];
        return cell;
    }
    NSDictionary *event = [self.events[indexPath.row] isKindOfClass:NSDictionary.class] ? self.events[indexPath.row] : @{};
    NSString *eventStatus = PPF_SafeString(event[@"status"]);
    if (!eventStatus.length) eventStatus = PPF_SafeString(event[@"type"]);
    NSString *note = PPF_SafeString(event[@"note"]);
    if (!note.length) note = PPF_SafeString(event[@"reason"]);
    id createdAt = event[@"createdAt"];
    NSDate *date = [createdAt isKindOfClass:FIRTimestamp.class] ? [(FIRTimestamp *)createdAt dateValue] : nil;
    NSString *value = note.length ? note : PPF_DateString(date);
    [cell configureTitle:eventStatus.length ? PPF_StatusText(eventStatus) : kLang(@"Fulfillment_Event") value:value symbolName:nil tint:nil];
    return cell;
}

@end

#pragma mark - Main List View Controller

@interface PPFulfillmentOrdersViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<PPFulfillmentRecord *> *records;
@property (nonatomic, strong) NSArray<PPFulfillmentRecord *> *visibleRecords;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, copy) NSString *filterStatus;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL didRunEntrance;
@property (nonatomic, assign) BOOL didRunInitialListAnimation;
@property (nonatomic, assign) BOOL isAdjustingHeaderSize;
@property (nonatomic, assign) CGFloat lastHeaderWidth;
@property (nonatomic, assign) CGFloat lastHeaderHeight;
@end

@implementation PPFulfillmentOrdersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Fulfillment_Title");
    self.records = @[];
    self.visibleRecords = @[];
    [self pp_configureTableView];
    [self pp_configureSearch];
    [self pp_buildHeader];

    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadData)];
    refreshBtn.accessibilityLabel = kLang(@"Fulfillment_Refresh");
    self.navigationItem.rightBarButtonItem = refreshBtn;
    [self loadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self prepareEntranceState];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroBackground startAnimations];
    [self runEntranceIfNeeded];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.heroBackground stopAnimations];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_updateInsets];
    [self pp_sizeHeaderToFit];
    if (!_didPrepareEntrance) {
        [self prepareEntranceState];
    }
}

- (void)prepareEntranceState {
    if (_didRunEntrance) return;
    _didPrepareEntrance = YES;
    self.heroBackground.alpha = 0;
    self.heroBackground.transform = CGAffineTransformMakeScale(1.04, 1.04);
    UILabel *title = [self.headerContainer viewWithTag:1001];
    UILabel *subtitle = [self.headerContainer viewWithTag:1002];
    UILabel *count = [self.headerContainer viewWithTag:1003];
    if (title) { title.alpha = 0; title.transform = CGAffineTransformMakeTranslation(0, 14); }
    if (subtitle) { subtitle.alpha = 0; subtitle.transform = CGAffineTransformMakeTranslation(0, 10); }
    if (count) { count.alpha = 0; count.transform = CGAffineTransformMakeScale(0.85, 0.85); }
}

- (void)runEntranceIfNeeded {
    if (_didRunEntrance) return;
    _didRunEntrance = YES;
    [self.view layoutIfNeeded];

    [UIView animateWithDuration:0.48 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.heroBackground.alpha = 1;
        self.heroBackground.transform = CGAffineTransformIdentity;
    } completion:nil];

    UILabel *title = [self.headerContainer viewWithTag:1001];
    UILabel *subtitle = [self.headerContainer viewWithTag:1002];
    UILabel *count = [self.headerContainer viewWithTag:1003];

    [UIView animateWithDuration:0.42 delay:0.08 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (title) { title.alpha = 1; title.transform = CGAffineTransformIdentity; }
    } completion:nil];

    [UIView animateWithDuration:0.42 delay:0.16 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (subtitle) { subtitle.alpha = 1; subtitle.transform = CGAffineTransformIdentity; }
    } completion:nil];

    [UIView animateWithDuration:0.48 delay:0.22 usingSpringWithDamping:0.86 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        if (count) { count.alpha = 1; count.transform = CGAffineTransformIdentity; }
    } completion:nil];
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPF_CanvasColor();
    self.tableView.backgroundColor = PPF_CanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 92.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.tableView registerClass:[PPF_OrderCell class] forCellReuseIdentifier:@"Order"];
    [self.tableView registerClass:[PPF_StateCell class] forCellReuseIdentifier:@"State"];

    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = PPF_AccentColor();
    [refresh addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
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
    title.textAlignment = [Language alignmentForCurrentLanguage];
    title.numberOfLines = 2;
    title.tag = 1001;

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = kLang(@"Fulfillment_Subtitle");
    subtitle.font = [Styling fontRegular:PPFontSubheadline];
    subtitle.textColor = PPF_SubInkColor();
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.numberOfLines = 2;
    subtitle.tag = 1002;

    UILabel *count = [UILabel new];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    count.font = [Styling fontBold:PPFontFootnote];
    count.textColor = PPF_AccentColor();
    count.backgroundColor = [PPF_AccentColor() colorWithAlphaComponent:0.11];
    count.textAlignment = NSTextAlignmentCenter;
    count.layer.cornerRadius = 16.0;
    count.layer.masksToBounds = YES;
    count.adjustsFontSizeToFitWidth = YES;
    count.minimumScaleFactor = 0.72;
    count.adjustsFontForContentSizeCategory = YES;
    count.tag = 1003;
    self.heroCountLabel = count;

    UIView *textColumn = [UIView new];
    textColumn.translatesAutoresizingMaskIntoConstraints = NO;
    textColumn.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:textColumn];

    [textColumn addSubview:title];
    [textColumn addSubview:subtitle];
    [card addSubview:count];

    [title setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [count setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [count setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:18.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14.0],
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:168.0],

        [hero.topAnchor constraintEqualToAnchor:card.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [textColumn.topAnchor constraintEqualToAnchor:card.topAnchor constant:26.0],
        [textColumn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24.0],
        [textColumn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24.0],
        [textColumn.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-24.0],

        [count.topAnchor constraintEqualToAnchor:card.topAnchor constant:24.0],
        [count.leadingAnchor constraintGreaterThanOrEqualToAnchor:textColumn.leadingAnchor],
        [count.trailingAnchor constraintEqualToAnchor:textColumn.trailingAnchor],
        [count.widthAnchor constraintGreaterThanOrEqualToConstant:86.0],
        [count.heightAnchor constraintEqualToConstant:34.0],

        [title.topAnchor constraintEqualToAnchor:textColumn.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:textColumn.leadingAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:count.leadingAnchor constant:-14.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:textColumn.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:textColumn.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10.0],
        [subtitle.bottomAnchor constraintEqualToAnchor:textColumn.bottomAnchor],
    ]];
    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_updateHeroCount];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer || self.isAdjustingHeaderSize) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGRect frame = self.headerContainer.frame;
    BOOL widthChanged = fabs(frame.size.width - width) > 0.5;
    if (widthChanged) {
        frame.size.width = width;
        self.headerContainer.frame = frame;
    }
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                     withHorizontalFittingPriority:UILayoutPriorityRequired
                                           verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat targetHeight = ceil(MAX(1.0, height));
    BOOL heightChanged = fabs(frame.size.height - targetHeight) > 0.5;
    if (!widthChanged && !heightChanged &&
        fabs(self.lastHeaderWidth - width) <= 0.5 &&
        fabs(self.lastHeaderHeight - targetHeight) <= 0.5) {
        return;
    }
    frame.size.width = width;
    frame.size.height = targetHeight;
    self.isAdjustingHeaderSize = YES;
    self.headerContainer.frame = frame;
    self.tableView.tableHeaderView = self.headerContainer;
    self.lastHeaderWidth = width;
    self.lastHeaderHeight = targetHeight;
    self.isAdjustingHeaderSize = NO;
}

- (void)pp_updateInsets {
    CGFloat tabHeight = self.tabBarController ? CGRectGetHeight(self.tabBarController.tabBar.bounds) : 0.0;
    UIEdgeInsets inset = self.tableView.contentInset;
    inset.bottom = MAX(28.0, tabHeight + 34.0);
    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.contentInset, inset)) {
        self.tableView.contentInset = inset;
    }
    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.scrollIndicatorInsets, inset)) {
        self.tableView.scrollIndicatorInsets = inset;
    }
}

- (void)pp_updateHeroCount {
    NSString *format = kLang(@"Fulfillment_Count_Format");
    self.heroCountLabel.text = [NSString stringWithFormat:format, @(self.visibleRecords.count)];
}

- (void)loadData {
    self.isLoading = YES;
    self.errorMessage = nil;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[PPFulfillmentService shared] fetchFulfillmentsWithCompletion:^(NSArray<PPFulfillmentRecord *> *records, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.isLoading = NO;
            [weakSelf.refreshControl endRefreshing];
            if (error) {
                weakSelf.errorMessage = error.localizedDescription;
                [AlertHelper showAlertIn:weakSelf title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                weakSelf.records = records ?: @[];
                weakSelf.errorMessage = nil;
            }
            [weakSelf pp_applySearchFilter];
        });
    }];
}

- (void)pp_applySearchFilter {
    NSString *query = [self.searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (query.length == 0) {
        self.visibleRecords = self.records ?: @[];
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PPFulfillmentRecord *record, NSDictionary<NSString *,id> *bindings) {
            (void)bindings;
            NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@", record.parentOrderNumber ?: @"", record.fulfillmentID ?: @"", record.customerName ?: @"", record.status ?: @"", record.fulfillmentMode ?: @""] lowercaseString];
            return [haystack containsString:query];
        }];
        self.visibleRecords = [self.records filteredArrayUsingPredicate:predicate];
    }
    [self pp_updateHeroCount];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self pp_applySearchFilter];
}

#pragma mark - Table View

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
    BOOL animateEntrance = !_didRunInitialListAnimation && indexPath.row < 12;
    [cell configureWithRecord:record animated:animateEntrance];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    if (!_didRunInitialListAnimation && indexPath.row < 12) {
        cell.alpha = 0.0;
        cell.transform = CGAffineTransformMakeTranslation(0.0, 14.0);
        CGFloat delay = MIN(indexPath.row * 0.055, 0.35);
        [UIView animateWithDuration:0.38 delay:delay usingSpringWithDamping:0.88 initialSpringVelocity:0.4 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == MIN(11, (NSInteger)self.visibleRecords.count - 1)) {
        _didRunInitialListAnimation = YES;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.visibleRecords.count) return;

    PPFulfillmentRecord *record = self.visibleRecords[indexPath.row];

    UIViewController *detail = [[PPFulfillmentDetailViewController alloc] initWithRecord:record];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
