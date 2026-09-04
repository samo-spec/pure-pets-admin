#import "PPDeliveryManagementViewController.h"
#import "PPDeliveryService.h"
#import "Language.h"
#import "Styling.h"

#import "PPFunc+Haptics.h"
#import "PPDesignTokens.h"
#import "UIViewController+PPNavBar.h"
#import "PPStaffAuth.h"
#import "PPAlertHelper.h"

static UIFont *PPDeliveryScaledFont(UIFont *baseFont, UIFontTextStyle textStyle) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
    }
    return baseFont;
}

static UIColor *PPDeliveryAccentColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPDeliveryCanvasColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPDeliverySurfaceColor(void) {
    return [UIColor ppElevatedSurface];
}

static UIColor *PPDeliveryInkColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPDeliverySubInkColor(void) {
    return [UIColor ppTextSecondary];
}

static void PPDeliveryApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = [UIColor ppShadow].CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, PPShadowCardOffsetY);
    view.layer.shadowRadius = PPShadowCardRadius;
    view.layer.shadowOpacity = PPShadowCardOpacity;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.62].CGColor;
}

static NSString *PPDeliveryDateString(NSDate *date) {
    if (!date) return @"-";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

static NSString *PPDeliveryLTRIsolate(NSString *value) {
    NSString *safe = value ?: @"";
    return safe.length ? [NSString stringWithFormat:@"\u2066%@\u2069", safe] : @"";
}

static NSString *PPDeliveryNormalizedStatus(NSString *status) {
    return [[status ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

static NSString *PPDeliveryCanonicalStatus(NSString *status) {
    NSString *normalized = PPDeliveryNormalizedStatus(status);
    if ([normalized isEqualToString:@"accepted"]) return @"accepted_by_company";
    if ([normalized isEqualToString:@"assigned"]) return @"assigned_to_driver";
    return normalized;
}

static NSString *PPDeliveryStatusKey(NSString *status) {
    NSString *normalized = PPDeliveryNormalizedStatus(status);
    if ([normalized isEqualToString:@"pending"]) return @"Delivery_Status_Pending";

    NSString *canonical = PPDeliveryCanonicalStatus(normalized);
    if ([canonical isEqualToString:@"offered"]) return @"Fulfillment_Status_DeliveryRequested";
    if ([canonical isEqualToString:@"accepted_by_company"]) return @"Fulfillment_Status_Accepted";
    if ([canonical isEqualToString:@"assigned_to_driver"]) return @"Fulfillment_Status_DeliveryAssigned";
    if ([canonical isEqualToString:@"picked_up"]) return @"Fulfillment_Status_PickedUp";
    if ([canonical isEqualToString:@"in_transit"]) return @"Fulfillment_Status_InTransit";
    if ([canonical isEqualToString:@"delivered"]) return @"Fulfillment_Status_Delivered";
    if ([canonical isEqualToString:@"completed"]) return @"Fulfillment_Status_Completed";
    if ([canonical isEqualToString:@"rejected"]) return @"Fulfillment_Status_Rejected";
    if ([canonical isEqualToString:@"cancelled"]) return @"Fulfillment_Status_Cancelled";
    if ([canonical isEqualToString:@"failed"]) return @"Fulfillment_Status_Failed";
    return @"Fulfillment_Status_Unknown";
}

static NSString *PPDeliveryStatusText(NSString *status) {
    NSString *key = PPDeliveryStatusKey(status);
    NSString *localized = kLang(key);
    if ([localized isKindOfClass:NSString.class] && localized.length > 0 && ![localized isEqualToString:key]) {
        return localized;
    }
    return kLang(@"Delivery_Status_Unknown");
}

static UIColor *PPDeliveryStatusColor(NSString *status) {
    NSString *normalized = PPDeliveryNormalizedStatus(status);
    NSString *canonical = PPDeliveryCanonicalStatus(normalized);
    if ([canonical isEqualToString:@"delivered"] || [canonical isEqualToString:@"completed"] || [canonical isEqualToString:@"accepted_by_company"]) {
        return [UIColor ppSuccess];
    }
    if ([canonical isEqualToString:@"cancelled"] || [canonical isEqualToString:@"rejected"] || [canonical isEqualToString:@"failed"] || [canonical isEqualToString:@"expired"]) {
        return [UIColor ppError];
    }
    if ([canonical isEqualToString:@"assigned_to_driver"] || [canonical isEqualToString:@"picked_up"] || [canonical isEqualToString:@"in_transit"]) {
        return [UIColor ppInfo];
    }
    if ([canonical isEqualToString:@"offered"] || [normalized isEqualToString:@"pending"]) {
        return [UIColor ppWarning];
    }
    return PPDeliveryAccentColor();
}

static BOOL PPDeliveryIsActiveStatus(NSString *status) {
    NSString *normalized = PPDeliveryNormalizedStatus(status);
    NSString *canonical = PPDeliveryCanonicalStatus(normalized);
    return [canonical isEqualToString:@"offered"] ||
           [canonical isEqualToString:@"accepted_by_company"] ||
           [canonical isEqualToString:@"assigned_to_driver"] ||
           [canonical isEqualToString:@"picked_up"] ||
           [canonical isEqualToString:@"in_transit"] ||
           [normalized isEqualToString:@"pending"];
}

static BOOL PPDeliveryIsCompletedStatus(NSString *status) {
    NSString *canonical = PPDeliveryCanonicalStatus(status);
    return [canonical isEqualToString:@"delivered"] || [canonical isEqualToString:@"completed"];
}

static BOOL PPDeliveryRecordHasAction(PPDeliveryRequestRecord *record) {
    return [record allowedActionNamed:@"ASSIGN"] != nil ||
           [record allowedActionNamed:@"REASSIGN"] != nil ||
           [record allowedActionNamed:@"COMPLETE"] != nil ||
           [record allowedActionNamed:@"CANCEL"] != nil;
}

static NSString *PPDeliveryOrderReference(PPDeliveryRequestRecord *record) {
    NSString *orderRef = record.orderNumber.length > 0 ? record.orderNumber : record.orderID;
    if (orderRef.length == 0) orderRef = record.requestID;
    return orderRef.length > 0 ? PPDeliveryLTRIsolate([NSString stringWithFormat:@"#%@", orderRef]) : @"-";
}

static BOOL PPDeliveryIsPermissionError(NSError *error) {
    return [PPDeliveryService isPermissionError:error];
}

static NSString *PPDeliveryErrorText(NSError *error) {
    NSString *code = [PPDeliveryService domainCodeForError:error];
    NSDictionary<NSString *, NSArray<NSString *> *> *copyByCode = @{
        @"DELIVERY_COMPANY_NOT_CONFIGURED": @[@"Delivery_Error_State_Configuration", @"Delivery_Error_Cause_Company_Not_Configured", @"Delivery_Error_Impact_Dispatch_Blocked", @"Delivery_Error_Recovery_Configure_Carrier"],
        @"DELIVERY_COMPANY_NOT_FOUND": @[@"Delivery_Error_State_Carrier_Missing", @"Delivery_Error_Cause_Company_Not_Found", @"Delivery_Error_Impact_Carrier_Unavailable", @"Delivery_Error_Recovery_Refresh_Carrier"],
        @"DELIVERY_REQUEST_NOT_FOUND": @[@"Delivery_Error_State_Request_Missing", @"Delivery_Error_Cause_Request_Not_Found", @"Delivery_Error_Impact_Command_Not_Applied", @"Delivery_Error_Recovery_Return_Queue"],
        @"DELIVERY_PERMISSION_DENIED": @[@"Delivery_Error_State_Access_Denied", @"Delivery_Error_Cause_Permission", @"Delivery_Error_Impact_Action_Unavailable", @"Delivery_Error_Recovery_Request_Access"],
        @"DELIVERY_STATE_CONFLICT": @[@"Delivery_Error_State_Changed", @"Delivery_Error_Cause_Stale_Action", @"Delivery_Error_Impact_Command_Not_Applied", @"Delivery_Error_Recovery_Refresh_Dossier"],
        @"DELIVERY_AUTHORITY_MISMATCH": @[@"Delivery_Error_State_Authority_Mismatch", @"Delivery_Error_Cause_Fulfillment_Authority", @"Delivery_Error_Impact_Command_Not_Applied", @"Delivery_Error_Recovery_Open_Fulfillment"],
        @"DELIVERY_COD_MISMATCH": @[@"Delivery_Error_State_COD_Attention", @"Delivery_Error_Cause_COD_Mismatch", @"Delivery_Error_Impact_Reconciliation_Blocked", @"Delivery_Error_Recovery_Verify_Custody"],
        @"DELIVERY_POD_REQUIRED": @[@"Delivery_Error_State_POD_Incomplete", @"Delivery_Error_Cause_POD_Required", @"Delivery_Error_Impact_Completion_Blocked", @"Delivery_Error_Recovery_Collect_POD"],
    };
    NSArray<NSString *> *keys = copyByCode[code] ?: @[@"Delivery_Error_State_Service_Unavailable", @"Delivery_Error_Cause_Service", @"Delivery_Error_Impact_Data_Unavailable", @"Delivery_Error_Recovery_Retry"];
    return [NSString stringWithFormat:@"%@: %@\n%@: %@\n%@: %@\n%@: %@\n%@",
            kLang(@"Delivery_Error_Label_State"), kLang(keys[0]),
            kLang(@"Delivery_Error_Label_Cause"), kLang(keys[1]),
            kLang(@"Delivery_Error_Label_Impact"), kLang(keys[2]),
            kLang(@"Delivery_Error_Label_Recovery"), kLang(keys[3]),
            code];
}

@interface PPDeliveryBadgeLabel : UILabel
@end

@implementation PPDeliveryBadgeLabel

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + PPSpaceMD, size.height + PPSpaceXS);
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:CGRectInset(rect, PPSpaceMDHalf, PPSpaceXS * 0.5)];
}

@end

@interface PPDeliveryRequestCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *statusRail;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *orderLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) PPDeliveryBadgeLabel *statusLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, copy) NSString *representedRequestID;
- (void)configureWithRecord:(PPDeliveryRequestRecord *)record;
@end

@implementation PPDeliveryRequestCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitStaticText;

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPDeliverySurfaceColor();
        PPDeliveryApplyCardChrome(_cardView, PPCornerMedium);
        [self.contentView addSubview:_cardView];

        _statusRail = [UIView new];
        _statusRail.translatesAutoresizingMaskIntoConstraints = NO;
        _statusRail.layer.cornerRadius = 2.0;
        _statusRail.accessibilityElementsHidden = YES;
        [_cardView addSubview:_statusRail];

         _symbolView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shippingbox.fill"]];
        _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolView.contentMode = UIViewContentModeCenter;
        _symbolView.layer.cornerRadius = PPCornerMedium;
        _symbolView.layer.masksToBounds = YES;
        _symbolView.accessibilityElementsHidden = YES;
        if (@available(iOS 13.0, *)) _symbolView.layer.cornerCurve = kCACornerCurveContinuous;
        [_cardView addSubview:_symbolView];

        _orderLabel = [UILabel new];
        _orderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _orderLabel.font = PPDeliveryScaledFont([Styling fontBold:PPFontHeadline], UIFontTextStyleHeadline);
        _orderLabel.textColor = PPDeliveryInkColor();
        _orderLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _orderLabel.adjustsFontForContentSizeCategory = YES;
        _orderLabel.numberOfLines = 0;
        [_cardView addSubview:_orderLabel];

        _detailLabel = [UILabel new];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = PPDeliveryScaledFont([Styling fontRegular:PPFontSubheadline], UIFontTextStyleSubheadline);
        _detailLabel.textColor = PPDeliverySubInkColor();
        _detailLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _detailLabel.adjustsFontForContentSizeCategory = YES;
        _detailLabel.numberOfLines = 0;
        [_cardView addSubview:_detailLabel];

        _statusLabel = [PPDeliveryBadgeLabel new];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = PPDeliveryScaledFont([Styling fontBold:PPFontCaption1], UIFontTextStyleCaption1);
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.layer.cornerRadius = PPCornerPill;
        _statusLabel.layer.masksToBounds = YES;
        _statusLabel.adjustsFontForContentSizeCategory = YES;
        _statusLabel.numberOfLines = 0;
        [_cardView addSubview:_statusLabel];

        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle.fill"]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.accessibilityElementsHidden = YES;
        [_cardView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],

            [_statusRail.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
            [_statusRail.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],
            [_statusRail.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD],
            [_statusRail.widthAnchor constraintEqualToConstant:PPSpaceXS],

            [_symbolView.leadingAnchor constraintEqualToAnchor:_statusRail.trailingAnchor constant:PPSpaceMD],
            [_symbolView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceBase],
            [_symbolView.widthAnchor constraintEqualToConstant:PPButtonHeightSM],
            [_symbolView.heightAnchor constraintEqualToConstant:PPButtonHeightSM],

            [_chevronView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceMD],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:PPSpaceLG],
            [_chevronView.heightAnchor constraintEqualToConstant:PPSpaceLG],

            [_statusLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-PPSpaceSM],
            [_statusLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],
            [_statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:76.0],

            [_orderLabel.leadingAnchor constraintEqualToAnchor:_symbolView.trailingAnchor constant:PPSpaceMD],
            [_orderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-PPSpaceSM],
            [_orderLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceMD],

            [_detailLabel.leadingAnchor constraintEqualToAnchor:_orderLabel.leadingAnchor],
            [_detailLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceMD],
            [_detailLabel.topAnchor constraintEqualToAnchor:_orderLabel.bottomAnchor constant:PPSpaceXS],
            [_detailLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceMD]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedRequestID = nil;
    self.alpha = 1.0;
    self.transform = CGAffineTransformIdentity;
    self.accessibilityLabel = nil;
    self.accessibilityHint = nil;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.cardView.alpha = highlighted ? 0.94 : 1.0;
        return;
    }
    [UIView animateWithDuration:PPAnimDurationFast
                          delay:0.0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.cardView.transform = highlighted ? CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown) : CGAffineTransformIdentity;
        self.cardView.alpha = highlighted ? 0.94 : 1.0;
    } completion:nil];
}

- (void)configureWithRecord:(PPDeliveryRequestRecord *)record {
    self.representedRequestID = record.requestID ?: @"";
    BOOL actionable = PPDeliveryRecordHasAction(record);
    self.accessibilityTraits = actionable ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    self.accessibilityHint = actionable ? kLang(@"Delivery_Actions") : nil;

    self.orderLabel.text = PPDeliveryOrderReference(record);
    NSString *customer = record.customerName.length ? record.customerName : kLang(@"Delivery_UnknownCustomer");
    NSString *fee = record.deliveryFee ? [NSString stringWithFormat:@"%.2f %@", record.deliveryFee.doubleValue, kLang(@"Accounting_QAR")] : @"-";
    NSString *driver = record.assignedDriverName.length ? record.assignedDriverName : kLang(@"Delivery_DriverUnassigned");
    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@\n%@ · %@", customer, fee, driver, PPDeliveryDateString(record.createdAt)];

    UIColor *statusColor = PPDeliveryStatusColor(record.status);
    self.statusLabel.text = PPDeliveryStatusText(record.status);
    self.statusLabel.textColor = statusColor;
    self.statusLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.14];
    self.statusRail.backgroundColor = statusColor;
    self.symbolView.tintColor = statusColor;
    self.symbolView.backgroundColor = [statusColor colorWithAlphaComponent:0.14];
    self.chevronView.hidden = !actionable;
    self.chevronView.tintColor = actionable ? [statusColor colorWithAlphaComponent:0.84] : [PPDeliverySubInkColor() colorWithAlphaComponent:0.42];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@", self.orderLabel.text ?: @"", self.statusLabel.text ?: @"", self.detailLabel.text ?: @""];
}

@end

#pragma mark - Delivery State

@interface PPDeliveryStateCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) NSLayoutConstraint *actionButtonHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *actionButtonCollapsedConstraint;
@property (nonatomic, copy) dispatch_block_t action;
- (void)configureWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                symbolName:(NSString *)symbolName
                      color:(UIColor *)color
                actionTitle:(NSString *)actionTitle
                     action:(dispatch_block_t)action;
@end

@implementation PPDeliveryStateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPDeliverySurfaceColor();
        PPDeliveryApplyCardChrome(_cardView, PPCornerCard);
        [self.contentView addSubview:_cardView];

        _symbolView = [UIImageView new];
        _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolView.contentMode = UIViewContentModeCenter;
        _symbolView.layer.cornerRadius = PPCornerMedium;
        _symbolView.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) _symbolView.layer.cornerCurve = kCACornerCurveContinuous;
        _symbolView.accessibilityElementsHidden = YES;
        [_cardView addSubview:_symbolView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = PPDeliveryScaledFont([Styling fontBold:PPFontTitle3], UIFontTextStyleTitle3);
        _titleLabel.textColor = PPDeliveryInkColor();
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _titleLabel.numberOfLines = 0;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
        [_cardView addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = PPDeliveryScaledFont([Styling fontRegular:PPFontCallout], UIFontTextStyleCallout);
        _subtitleLabel.textColor = PPDeliverySubInkColor();
        _subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _subtitleLabel.numberOfLines = 0;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        [_cardView addSubview:_subtitleLabel];

        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _actionButton.backgroundColor = [UIColor ppSecondarySurface];
        _actionButton.layer.cornerRadius = PPCornerPill;
        if (@available(iOS 13.0, *)) _actionButton.layer.cornerCurve = kCACornerCurveContinuous;
        _actionButton.titleLabel.font = PPDeliveryScaledFont([Styling fontBold:PPFontCallout], UIFontTextStyleCallout);
        _actionButton.titleLabel.adjustsFontForContentSizeCategory = YES;
        _actionButton.titleLabel.numberOfLines = 0;
        _actionButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceLG, PPSpaceSM, PPSpaceLG);
        [_actionButton setTitleColor:PPDeliveryInkColor() forState:UIControlStateNormal];
        [_actionButton addTarget:self action:@selector(pp_actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:_actionButton];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:PPScreenMargin],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-PPScreenMargin],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],

            [_symbolView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceXL],
            [_symbolView.centerXAnchor constraintEqualToAnchor:_cardView.centerXAnchor],
            [_symbolView.widthAnchor constraintEqualToConstant:PPButtonHeightSM],
            [_symbolView.heightAnchor constraintEqualToConstant:PPButtonHeightSM],

            [_titleLabel.topAnchor constraintEqualToAnchor:_symbolView.bottomAnchor constant:PPSpaceMD],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:PPSpaceXL],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceXL],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

            [_actionButton.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:PPSpaceLG],
            [_actionButton.centerXAnchor constraintEqualToAnchor:_cardView.centerXAnchor],
            [_actionButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_cardView.leadingAnchor constant:PPSpaceXL],
            [_actionButton.trailingAnchor constraintLessThanOrEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceXL],
            [_actionButton.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceXL]
        ]];
        _actionButtonHeightConstraint = [_actionButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightMD];
        _actionButtonCollapsedConstraint = [_actionButton.heightAnchor constraintEqualToConstant:0.0];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.action = nil;
    self.actionButton.hidden = YES;
    self.actionButtonHeightConstraint.active = NO;
    self.actionButtonCollapsedConstraint.active = YES;
}

- (void)configureWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                symbolName:(NSString *)symbolName
                      color:(UIColor *)color
                actionTitle:(NSString *)actionTitle
                     action:(dispatch_block_t)action {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.subtitleLabel.hidden = subtitle.length == 0;
    self.symbolView.image = [UIImage systemImageNamed:symbolName ?: @"info.circle.fill"];
    self.symbolView.tintColor = color ?: PPDeliveryAccentColor();
    self.symbolView.backgroundColor = [(color ?: PPDeliveryAccentColor()) colorWithAlphaComponent:0.14];
    self.action = [action copy];
    self.actionButton.hidden = actionTitle.length == 0 || !action;
    self.actionButtonHeightConstraint.active = !self.actionButton.hidden;
    self.actionButtonCollapsedConstraint.active = self.actionButton.hidden;
    [self.actionButton setTitle:actionTitle ?: @"" forState:UIControlStateNormal];
    self.actionButton.accessibilityLabel = actionTitle ?: @"";
    self.isAccessibilityElement = NO;
}

- (void)pp_actionTapped {
    if (self.action) self.action();
}

@end

#pragma mark - Action Sheet

@interface PPDeliveryActionsViewController : UIViewController
@property (nonatomic, copy) NSString *requestSummary;
@property (nonatomic, copy) NSString *assignTitle;
@property (nonatomic, copy) NSString *completeTitle;
@property (nonatomic, copy) NSString *cancelTitle;
@property (nonatomic, copy, nullable) dispatch_block_t assignAction;
@property (nonatomic, copy, nullable) dispatch_block_t completeAction;
@property (nonatomic, copy, nullable) dispatch_block_t cancelAction;
@end

@interface PPDeliveryActionsViewController ()
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIStackView *actionStack;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSLayoutConstraint *cardHeightConstraint;
@property (nonatomic, assign) BOOL isSizingCard;
@end

@implementation PPDeliveryActionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.view.accessibilityViewIsModal = YES;

    UIView *scrim = [UIView new];
    scrim.translatesAutoresizingMaskIntoConstraints = NO;
    scrim.backgroundColor = [[UIColor ppShadow] colorWithAlphaComponent:0.48];
    scrim.accessibilityElementsHidden = YES;
    [self.view addSubview:scrim];
    [NSLayoutConstraint activateConstraints:@[
        [scrim.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrim.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrim.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrim.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
    dismissButton.accessibilityLabel = kLang(@"Cancel");
    dismissButton.accessibilityTraits = UIAccessibilityTraitButton;
    [dismissButton addTarget:self action:@selector(pp_dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:dismissButton];
    [NSLayoutConstraint activateConstraints:@[
        [dismissButton.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [dismissButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dismissButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [dismissButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.cardView = [UIView new];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = PPDeliverySurfaceColor();
    self.cardView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    PPDeliveryApplyCardChrome(self.cardView, PPCornerHero);
    self.cardView.layer.shadowOffset = CGSizeMake(0.0, PPShadowElevatedOffsetY);
    self.cardView.layer.shadowRadius = PPShadowElevatedRadius;
    self.cardView.layer.shadowOpacity = PPShadowElevatedOpacity;
    [self.view addSubview:self.cardView];

    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = NO;
    self.scrollView.showsVerticalScrollIndicator = YES;
    self.scrollView.directionalLockEnabled = YES;
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.scrollView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.cardView addSubview:self.scrollView];

    self.actionStack = [UIStackView new];
    self.actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionStack.axis = UILayoutConstraintAxisVertical;
    self.actionStack.alignment = UIStackViewAlignmentFill;
    self.actionStack.spacing = PPSpaceSM;
    self.actionStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.scrollView addSubview:self.actionStack];

    UILabel *titleLabel = [UILabel new];
    titleLabel.font = PPDeliveryScaledFont([Styling fontBold:PPFontTitle2], UIFontTextStyleTitle2);
    titleLabel.textColor = PPDeliveryInkColor();
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    titleLabel.numberOfLines = 0;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.text = kLang(@"Delivery_Actions");
    titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.actionStack addArrangedSubview:titleLabel];

    UILabel *summaryLabel = [UILabel new];
    summaryLabel.font = PPDeliveryScaledFont([Styling fontRegular:PPFontCallout], UIFontTextStyleCallout);
    summaryLabel.textColor = PPDeliverySubInkColor();
    summaryLabel.textAlignment = [Language alignmentForCurrentLanguage];
    summaryLabel.numberOfLines = 0;
    summaryLabel.adjustsFontForContentSizeCategory = YES;
    summaryLabel.text = self.requestSummary ?: @"";
    [self.actionStack addArrangedSubview:summaryLabel];

    UIView *separator = [UIView new];
    separator.backgroundColor = [UIColor ppSurfaceBorder];
    [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    [self.actionStack addArrangedSubview:separator];

    if (self.assignAction) {
        [self pp_addActionButtonWithTitle:self.assignTitle destructive:NO action:self.assignAction];
    }
    if (self.completeAction) {
        [self pp_addActionButtonWithTitle:self.completeTitle destructive:NO action:self.completeAction];
    }
    if (self.cancelAction) {
        [self pp_addActionButtonWithTitle:self.cancelTitle destructive:YES action:self.cancelAction];
    }

    NSLayoutConstraint *widthConstraint = [self.cardView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.90];
    widthConstraint.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        widthConstraint,
        [self.cardView.widthAnchor constraintLessThanOrEqualToConstant:420.0],
        [self.cardView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:PPSpaceLG],
        [self.cardView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-PPSpaceLG],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.cardView.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.topAnchor],

        [self.scrollView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:PPSpaceXL],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:PPSpaceXL],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-PPSpaceXL],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-PPSpaceXL],

        [self.actionStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.actionStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.actionStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.actionStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.actionStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor]
    ]];

    self.cardHeightConstraint = [self.cardView.heightAnchor constraintEqualToConstant:280.0];
    self.cardHeightConstraint.active = YES;
}

- (void)pp_addActionButtonWithTitle:(NSString *)title destructive:(BOOL)destructive action:(dispatch_block_t)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor ppSecondarySurface];
    button.layer.cornerRadius = PPCornerPill;
    if (@available(iOS 13.0, *)) button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceMD, PPSpaceSM, PPSpaceMD);
    button.titleLabel.font = PPDeliveryScaledFont([Styling fontBold:PPFontCallout], UIFontTextStyleCallout);
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button setTitle:title ?: @"" forState:UIControlStateNormal];
    [button setTitleColor:destructive ? [UIColor ppError] : PPDeliveryInkColor() forState:UIControlStateNormal];
    button.accessibilityLabel = title ?: @"";
    button.accessibilityTraits = UIAccessibilityTraitButton;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightMD].active = YES;
    __weak typeof(self) weakSelf = self;
    [button addAction:[UIAction actionWithHandler:^(__unused UIAction *sender) {
        [weakSelf dismissViewControllerAnimated:YES completion:action];
    }] forControlEvents:UIControlEventTouchUpInside];
    [self.actionStack addArrangedSubview:button];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.isSizingCard || CGRectGetWidth(self.actionStack.bounds) <= 0.0) return;
    self.isSizingCard = YES;
    [self.actionStack layoutIfNeeded];
    CGFloat contentWidth = CGRectGetWidth(self.actionStack.bounds);
    CGFloat contentHeight = [self.actionStack systemLayoutSizeFittingSize:CGSizeMake(contentWidth, UILayoutFittingCompressedSize.height)
                                              withHorizontalFittingPriority:UILayoutPriorityRequired
                                                    verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat safeHeight = CGRectGetHeight(self.view.safeAreaLayoutGuide.layoutFrame);
    CGFloat maxHeight = MAX(160.0, safeHeight - (PPSpaceSM * 2.0));
    CGFloat minimumHeight = MIN(220.0, maxHeight);
    CGFloat targetHeight = MIN(MAX(contentHeight + PPSpaceXL * 2.0, minimumHeight), maxHeight);
    if (fabs(self.cardHeightConstraint.constant - targetHeight) > 0.5) {
        self.cardHeightConstraint.constant = targetHeight;
        [self.view layoutIfNeeded];
    }
    self.isSizingCard = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    self.view.alpha = 0.0;
    self.cardView.transform = CGAffineTransformMakeTranslation(0.0, PPSpaceLG);
    [UIView animateWithDuration:PPAnimDurationNormal
                          delay:0.0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.view.alpha = 1.0;
        self.cardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)pp_dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface PPDeliveryManagementViewController ()
@property (nonatomic, strong) NSArray<PPDeliveryRequestRecord *> *records;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, copy) NSString *statusFilter;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UIBarButtonItem *globalRefreshItem;
@property (nonatomic, strong) UIView *headerStatusView;
@property (nonatomic, strong) UIActivityIndicatorView *headerStatusIndicator;
@property (nonatomic, strong) UILabel *headerStatusLabel;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, copy) NSString *successMessage;
@property (nonatomic, assign) BOOL permissionDenied;
@property (nonatomic, assign) BOOL isSubmitting;
@property (nonatomic, assign) BOOL showSuccessAfterLoad;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, strong) UIAlertAction *pendingDriverConfirmAction;
@property (nonatomic, assign) BOOL isSizingHeader;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedRequestIDs;
@end

@implementation PPDeliveryManagementViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Delivery_Title");
    self.statusFilter = @"all";
    self.records = @[];
    self.animatedRequestIDs = [NSMutableSet set];
    [self pp_configureTableView];
    [self pp_configureGlobalNavigationRefresh];
    [self pp_buildHeader];
    [self pp_updatePermissionState];
    if (!self.permissionDenied) {
        [self loadData];
    } else {
        [self.tableView reloadData];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto
                       button:nil
                        title:kLang(@"Delivery_Title")
                     showBack:YES];
    [self pp_updatePermissionState];
    if (self.permissionDenied) [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_updateInsets];
    [self pp_sizeHeaderToFit];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self pp_applyFilterStyle];
    [self pp_sizeHeaderToFit];
}

- (void)pp_configureGlobalNavigationRefresh {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:PPFontHeadline
                                                                                                weight:UIImageSymbolWeightMedium];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"
                                                                       withConfiguration:configuration]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(loadData)];
    item.accessibilityIdentifier = @"admin-delivery-refresh";
    item.accessibilityLabel = kLang(@"CommandCenter_Refresh");
    item.accessibilityHint = kLang(@"Delivery_Retry_Hint");
    self.globalRefreshItem = item;
    self.navigationItem.rightBarButtonItem = item;
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPDeliveryCanvasColor();
    self.tableView.backgroundColor = PPDeliveryCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 128.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    [self.tableView registerClass:PPDeliveryRequestCell.class forCellReuseIdentifier:@"DeliveryCell"];
    [self.tableView registerClass:PPDeliveryStateCell.class forCellReuseIdentifier:@"StateCell"];

    UIRefreshControl *refresh = [UIRefreshControl new];
    [refresh addTarget:self action:@selector(loadData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)pp_onBackTapped {
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = PPSpaceXS;
    stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:stack];

    // 1. Navigation Top Bar (Back Button + Refresh Button)
    UIView *navRow = [UIView new];
    navRow.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *backBtn = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(pp_onBackTapped)];
    [navRow addSubview:backBtn];

    UIButton *refreshBtn = [self pp_ButtonWithSystemName:@"arrow.clockwise" action:@selector(loadData)];
    [navRow addSubview:refreshBtn];

    [NSLayoutConstraint activateConstraints:@[
        [backBtn.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor],
        [backBtn.topAnchor constraintEqualToAnchor:navRow.topAnchor],
        [backBtn.bottomAnchor constraintEqualToAnchor:navRow.bottomAnchor],
        [backBtn.widthAnchor constraintEqualToConstant:44],
        [backBtn.heightAnchor constraintEqualToConstant:44],

        [refreshBtn.trailingAnchor constraintEqualToAnchor:navRow.trailingAnchor],
        [refreshBtn.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
        [refreshBtn.widthAnchor constraintEqualToConstant:44],
        [refreshBtn.heightAnchor constraintEqualToConstant:44]
    ]];
    [stack addArrangedSubview:navRow];

    // 2. Eyebrow Category Breadcrumb
    UILabel *eyebrowLabel = [UILabel new];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [Styling fontRegular:12];
    eyebrowLabel.textColor = [UIColor ppTextSecondary];
    eyebrowLabel.text = [NSString stringWithFormat:@"%@ / %@", kLang(@"CommandCenter_Work_Workspace"), kLang(@"Delivery_Title")];
    eyebrowLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [stack addArrangedSubview:eyebrowLabel];

    // 3. Dossier Large Title
    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:22];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = kLang(@"Delivery_Title");
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [stack addArrangedSubview:titleLabel];

    self.headerStatusView = [UIView new];
    self.headerStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerStatusView.backgroundColor = [UIColor ppSecondarySurface];
    self.headerStatusView.layer.cornerRadius = PPCornerSmall;
    if (@available(iOS 13.0, *)) self.headerStatusView.layer.cornerCurve = kCACornerCurveContinuous;
    self.headerStatusView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.headerStatusView.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.68].CGColor;
    self.headerStatusView.hidden = YES;
    [stack addArrangedSubview:self.headerStatusView];
    [self.headerStatusView.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightSM].active = YES;

    self.headerStatusIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.headerStatusIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerStatusIndicator.color = PPDeliveryAccentColor();
    self.headerStatusIndicator.hidesWhenStopped = YES;
    [self.headerStatusView addSubview:self.headerStatusIndicator];

    self.headerStatusLabel = [UILabel new];
    self.headerStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerStatusLabel.font = PPDeliveryScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote);
    self.headerStatusLabel.textColor = PPDeliverySubInkColor();
    self.headerStatusLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.headerStatusLabel.numberOfLines = 0;
    self.headerStatusLabel.adjustsFontForContentSizeCategory = YES;
    [self.headerStatusView addSubview:self.headerStatusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerStatusIndicator.leadingAnchor constraintEqualToAnchor:self.headerStatusView.leadingAnchor constant:PPSpaceMD],
        [self.headerStatusIndicator.centerYAnchor constraintEqualToAnchor:self.headerStatusView.centerYAnchor],
        [self.headerStatusIndicator.widthAnchor constraintEqualToConstant:PPSpaceLG],
        [self.headerStatusIndicator.heightAnchor constraintEqualToConstant:PPSpaceLG],
        [self.headerStatusLabel.leadingAnchor constraintEqualToAnchor:self.headerStatusIndicator.trailingAnchor constant:PPSpaceSM],
        [self.headerStatusLabel.trailingAnchor constraintEqualToAnchor:self.headerStatusView.trailingAnchor constant:-PPSpaceMD],
        [self.headerStatusLabel.topAnchor constraintEqualToAnchor:self.headerStatusView.topAnchor constant:PPSpaceSM],
        [self.headerStatusLabel.bottomAnchor constraintEqualToAnchor:self.headerStatusView.bottomAnchor constant:-PPSpaceSM]
    ]];

    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[
        kLang(@"Delivery_All"),
        kLang(@"Delivery_Active"),
        kLang(@"Delivery_Completed"),
        kLang(@"Delivery_Cancelled")
    ]];
    self.filterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterSegment.selectedSegmentIndex = 0;
    self.filterSegment.selectedSegmentTintColor = PPDeliveryAccentColor();
    self.filterSegment.backgroundColor = [UIColor ppSecondarySurface];
    self.filterSegment.layer.cornerRadius = PPCornerCard;
    if (@available(iOS 13.0, *)) self.filterSegment.layer.cornerCurve = kCACornerCurveContinuous;
    self.filterSegment.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.filterSegment.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.82].CGColor;
    self.filterSegment.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.filterSegment.apportionsSegmentWidthsByContent = YES;
    self.filterSegment.accessibilityLabel = kLang(@"Delivery_Title");
    [self.filterSegment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.filterSegment];
    [self.filterSegment.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightMD].active = YES;
    [self pp_applyFilterStyle];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceLG],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceMD]
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_updateHeaderState];
}

- (void)pp_applyFilterStyle {
    if (!self.filterSegment) return;
    [self.filterSegment setTitleTextAttributes:@{
        NSFontAttributeName: PPDeliveryScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote),
        NSForegroundColorAttributeName: PPDeliveryInkColor()
    } forState:UIControlStateNormal];
    [self.filterSegment setTitleTextAttributes:@{
        NSFontAttributeName: PPDeliveryScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote),
        NSForegroundColorAttributeName: PPOnPrimaryColor()
    } forState:UIControlStateSelected];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer || self.isSizingHeader) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;

    self.isSizingHeader = YES;
    CGRect frame = self.headerContainer.frame;
    BOOL widthChanged = fabs(CGRectGetWidth(frame) - width) > 0.5;
    if (widthChanged) {
        frame.size.width = width;
        self.headerContainer.frame = frame;
    }
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat targetHeight = ceil(MAX(1.0, height));
    BOOL heightChanged = fabs(CGRectGetHeight(self.headerContainer.frame) - targetHeight) > 0.5;
    if (widthChanged || heightChanged) {
        frame = self.headerContainer.frame;
        frame.size.width = width;
        frame.size.height = targetHeight;
        self.headerContainer.frame = frame;
        self.tableView.tableHeaderView = self.headerContainer;
    }
    self.isSizingHeader = NO;
}

- (void)pp_updateInsets {
    CGFloat tabHeight = self.tabBarController ? CGRectGetHeight(self.tabBarController.tabBar.bounds) : 0.0;
    UIEdgeInsets inset = self.tableView.contentInset;
    CGFloat targetBottom = MAX(PPSpaceXXL, tabHeight + PPSpaceXXL);
    if (fabs(inset.bottom - targetBottom) > 0.5) {
        inset.bottom = targetBottom;
        self.tableView.contentInset = inset;
        self.tableView.scrollIndicatorInsets = inset;
    }
}

- (void)pp_updatePermissionState {
    BOOL wasDenied = self.permissionDenied;
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    // The canonical staff document is the only local permission authority.
    // Route guards and callable enforcement remain the final access boundary.
    if (!staff) return;

    BOOL allowed = [staff hasAnyPermission:@[kStaffPermDeliveryView, kStaffPermDeliveryDispatch, kStaffPermDeliveryOverride, kStaffPermDeliveryCODReconcile, kStaffPermPaymentsManage]];
    self.permissionDenied = !allowed;
    if (self.permissionDenied) {
        if (!wasDenied) self.loadGeneration += 1;
        self.records = @[];
        self.errorMessage = nil;
        self.successMessage = nil;
        self.showSuccessAfterLoad = NO;
        self.isLoading = NO;
        self.isSubmitting = NO;
        self.tableView.userInteractionEnabled = YES;
        [self.refreshControl endRefreshing];
    }
    [self pp_updateHeaderState];
    if (wasDenied && !self.permissionDenied && !self.isLoading && self.records.count == 0) {
        [self loadData];
    }
}

#pragma mark - Data

- (void)filterChanged:(UISegmentedControl *)sender {
    NSArray<NSString *> *statuses = @[@"all", @"active", @"completed", @"cancelled"];
    NSInteger index = sender.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)statuses.count) index = 0;
    self.statusFilter = statuses[(NSUInteger)index];
    [self.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.filterSegment);
}

- (void)loadData {
    if (self.permissionDenied) {
        [self.refreshControl endRefreshing];
        return;
    }
    if (self.isLoading || self.isSubmitting) {
        [self.refreshControl endRefreshing];
        return;
    }

    self.isLoading = YES;
    self.errorMessage = nil;
    self.successMessage = nil;
    BOOL shouldShowSuccessAfterLoad = self.showSuccessAfterLoad;
    self.showSuccessAfterLoad = NO;
    NSUInteger generation = ++self.loadGeneration;
    [self pp_updateHeaderState];
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[PPDeliveryService shared] fetchCommandCenterWithCompletion:^(PPDeliveryCommandCenterSnapshot *snapshot, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.loadGeneration) return;

            self.isLoading = NO;
            [self.refreshControl endRefreshing];

            if (error) {
                self.errorMessage = PPDeliveryErrorText(error);
                self.showSuccessAfterLoad = NO;
                if (PPDeliveryIsPermissionError(error)) {
                    self.permissionDenied = YES;
                    self.records = @[];
                    self.errorMessage = kLang(@"StatusNoAccess");
                }
                [PPAlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:self.errorMessage];
            } else {
                self.records = snapshot.records ?: @[];
                if (shouldShowSuccessAfterLoad) {
                    self.successMessage = kLang(@"Success");
                    NSUInteger successGeneration = generation;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (self.loadGeneration == successGeneration) {
                            self.successMessage = nil;
                            [self pp_updateHeaderState];
                        }
                    });
                }
            }
            [self pp_updateHeaderState];
            [self.tableView reloadData];
        });
    }];
}

- (NSArray<PPDeliveryRequestRecord *> *)filteredRecords {
    if ([self.statusFilter isEqualToString:@"all"]) return self.records ?: @[];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PPDeliveryRequestRecord *record, NSDictionary<NSString *, id> *bindings) {
        (void)bindings;
        if ([self.statusFilter isEqualToString:@"active"]) return PPDeliveryIsActiveStatus(record.status);
        if ([self.statusFilter isEqualToString:@"completed"]) return PPDeliveryIsCompletedStatus(record.status);
        return [PPDeliveryCanonicalStatus(record.status) isEqualToString:@"cancelled"];
    }];
    return [self.records filteredArrayUsingPredicate:predicate];
}

- (void)pp_updateHeaderState {
    if (!self.headerStatusView) return;

    NSString *message = nil;
    BOOL spinning = NO;
    if (!self.permissionDenied && self.isLoading) {
        message = kLang(@"Loading");
        spinning = YES;
    } else if (!self.permissionDenied && self.successMessage.length > 0) {
        message = self.successMessage;
    } else if (!self.permissionDenied && self.errorMessage.length > 0 && self.records.count > 0) {
        message = self.errorMessage;
    }

    self.headerStatusView.hidden = message.length == 0;
    self.headerStatusLabel.text = message ?: @"";
    self.headerStatusIndicator.hidden = !spinning;
    if (spinning) [self.headerStatusIndicator startAnimating];
    else [self.headerStatusIndicator stopAnimating];

    BOOL refreshEnabled = !self.permissionDenied && !self.isLoading && !self.isSubmitting;
    self.globalRefreshItem.enabled = refreshEnabled;
    self.globalRefreshItem.accessibilityValue = self.isLoading ? kLang(@"Loading") : nil;
    if (self.globalNavigationStateDidChange) self.globalNavigationStateDidChange();
    [self.headerContainer setNeedsLayout];
    [self.headerContainer layoutIfNeeded];
    [self pp_sizeHeaderToFit];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX([self filteredRecords].count, 1);
}

- (UITableViewCell *)pp_stateCellWithTitle:(NSString *)title
                                  subtitle:(NSString *)subtitle
                               symbolName:(NSString *)symbolName
                                     color:(UIColor *)color
                               actionTitle:(NSString *)actionTitle
                                    action:(dispatch_block_t)action {
    PPDeliveryStateCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"StateCell"];
    [cell configureWithTitle:title
                    subtitle:subtitle
                 symbolName:symbolName
                       color:color
                 actionTitle:actionTitle
                      action:action];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<PPDeliveryRequestRecord *> *filtered = [self filteredRecords];
    if (self.permissionDenied) {
        return [self pp_stateCellWithTitle:kLang(@"CommandCenter_Permission_Denied_Title")
                                  subtitle:kLang(@"CommandCenter_Permission_Denied_Message")
                               symbolName:@"lock.shield.fill"
                                     color:[UIColor ppError]
                               actionTitle:nil
                                    action:nil];
    }
    if (filtered.count == 0) {
        if (self.isLoading) {
            return [self pp_stateCellWithTitle:kLang(@"Loading")
                                      subtitle:nil
                                   symbolName:@"arrow.triangle.2.circlepath"
                                         color:PPDeliveryAccentColor()
                                   actionTitle:nil
                                        action:nil];
        }
        if (self.errorMessage.length > 0 && self.records.count == 0) {
            __weak typeof(self) weakSelf = self;
            return [self pp_stateCellWithTitle:kLang(@"Error_Title")
                                      subtitle:self.errorMessage
                                   symbolName:@"exclamationmark.triangle.fill"
                                         color:[UIColor ppError]
                                   actionTitle:kLang(@"Retry")
                                        action:^{ [weakSelf loadData]; }];
        }
        return [self pp_stateCellWithTitle:kLang(@"Delivery_Empty")
                                  subtitle:nil
                               symbolName:@"shippingbox.fill"
                                     color:PPDeliverySubInkColor()
                               actionTitle:nil
                                    action:nil];
    }

    PPDeliveryRequestRecord *record = filtered[(NSUInteger)indexPath.row];
    PPDeliveryRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeliveryCell" forIndexPath:indexPath];
    [cell configureWithRecord:record];
    cell.userInteractionEnabled = !self.isLoading && !self.isSubmitting;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.isLoading || self.isSubmitting || self.permissionDenied) return;
    NSArray<PPDeliveryRequestRecord *> *filtered = [self filteredRecords];
    if (indexPath.row >= (NSInteger)filtered.count) return;

    PPDeliveryRequestRecord *record = filtered[(NSUInteger)indexPath.row];
    if (PPDeliveryRecordHasAction(record)) [self showActionsForRecord:record];
}

#pragma mark - Actions

- (void)showActionsForRecord:(PPDeliveryRequestRecord *)record {
    if (!PPDeliveryRecordHasAction(record) || self.isLoading || self.isSubmitting) return;

    PPDeliveryActionsViewController *actions = [PPDeliveryActionsViewController new];
    actions.requestSummary = [NSString stringWithFormat:@"%@ - %@", PPDeliveryOrderReference(record), PPDeliveryStatusText(record.status)];
    actions.assignTitle = kLang(@"Delivery_AssignDriver");
    actions.completeTitle = kLang(@"Delivery_MarkCompleted");
    actions.cancelTitle = kLang(@"Delivery_CancelRequest");

    __weak typeof(self) weakSelf = self;
    if ([record allowedActionNamed:@"ASSIGN"] || [record allowedActionNamed:@"REASSIGN"]) {
        actions.assignAction = ^{ [weakSelf promptAssignDriver:record]; };
    }
    if ([record allowedActionNamed:@"CANCEL"]) {
        actions.cancelAction = ^{ [weakSelf cancelRecord:record]; };
    }
    if ([record allowedActionNamed:@"COMPLETE"]) {
        actions.completeAction = ^{ [weakSelf completeRecord:record]; };
    }

    actions.modalPresentationStyle = UIModalPresentationOverFullScreen;
    actions.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:actions animated:NO completion:^{
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, actions.view);
    }];
}

- (void)promptAssignDriver:(PPDeliveryRequestRecord *)record {
    if (self.isSubmitting) return;
    [PPAlertHelper showTextPromptIn:self title:kLang(@"Delivery_AssignDriver") subtitle:kLang(@"Delivery_EnterDriverUID") placeholder:kLang(@"Delivery_DriverUIDPlaceholder") initialText:nil confirmText:kLang(@"Confirm") cancelText:kLang(@"Cancel") secureEntry:NO keyboardType:UIKeyboardTypeDefault completion:^(NSString * _Nullable text) {
        NSString *driverUID = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (driverUID.length == 0) return;
        PPDeliveryAllowedAction *action = [record allowedActionNamed:@"ASSIGN"] ?: [record allowedActionNamed:@"REASSIGN"];
        if (!action) return;
        [self pp_beginSubmitting];
        NSString *commandID = [NSString stringWithFormat:@"admin-ios-%@-%@", action.action.lowercaseString, NSUUID.UUID.UUIDString];
        [[PPDeliveryService shared] executeAllowedAction:action
                                              requestID:record.requestID
                                              commandID:commandID
                                              driverUID:driverUID
                                      handoverConfirmed:NO
                                                 reason:nil
                                             completion:^(__unused PPDeliveryCommandResult *result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self pp_handleActionError:error];
            });
        }];
    }];
}

- (void)completeRecord:(PPDeliveryRequestRecord *)record {
    [self pp_confirmRecord:record
                    title:kLang(@"Delivery_MarkCompleted")
                destructive:NO
                    handler:^{
        PPDeliveryAllowedAction *action = [record allowedActionNamed:@"COMPLETE"];
        if (!action) return;
        [self pp_beginSubmitting];
        NSString *commandID = [NSString stringWithFormat:@"admin-ios-complete-%@", NSUUID.UUID.UUIDString];
        [[PPDeliveryService shared] executeAllowedAction:action
                                              requestID:record.requestID
                                              commandID:commandID
                                              driverUID:nil
                                      handoverConfirmed:NO
                                                 reason:nil
                                             completion:^(__unused PPDeliveryCommandResult *result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self pp_handleActionError:error];
            });
        }];
    }];
}

- (void)cancelRecord:(PPDeliveryRequestRecord *)record {
    [self pp_confirmRecord:record
                     title:kLang(@"Delivery_CancelRequest")
                destructive:YES
                    handler:^{
        PPDeliveryAllowedAction *action = [record allowedActionNamed:@"CANCEL"];
        if (!action) return;
        [self pp_beginSubmitting];
        NSString *commandID = [NSString stringWithFormat:@"admin-ios-cancel-%@", NSUUID.UUID.UUIDString];
        [[PPDeliveryService shared] executeAllowedAction:action
                                              requestID:record.requestID
                                              commandID:commandID
                                              driverUID:nil
                                      handoverConfirmed:NO
                                                 reason:@"ADMIN_CANCELLED"
                                             completion:^(__unused PPDeliveryCommandResult *result, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self pp_handleActionError:error];
            });
        }];
    }];
}

- (void)pp_confirmRecord:(PPDeliveryRequestRecord *)record
                   title:(NSString *)title
              destructive:(BOOL)destructive
                  handler:(dispatch_block_t)handler {
    [PPAlertHelper showConfirmationIn:self title:title subtitle:[NSString stringWithFormat:@"%@ - %@", PPDeliveryOrderReference(record), PPDeliveryStatusText(record.status)] confirmButton:kLang(@"Confirm") cancelButton:kLang(@"Cancel") icon:nil confirmBlock:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (handler) handler();
    } cancelBlock:nil];
}

- (void)pp_beginSubmitting {
    self.isSubmitting = YES;
    [self pp_updateHeaderState];
    self.tableView.userInteractionEnabled = NO;
}

- (void)pp_handleActionError:(NSError *)error {
    self.isSubmitting = NO;
    self.tableView.userInteractionEnabled = YES;
    self.pendingDriverConfirmAction = nil;
    if (error) {
        self.errorMessage = PPDeliveryErrorText(error);
        if (PPDeliveryIsPermissionError(error)) {
            self.permissionDenied = YES;
            self.records = @[];
            self.errorMessage = kLang(@"StatusNoAccess");
        }
        self.showSuccessAfterLoad = NO;
            [self pp_updateHeaderState];
        [self.tableView reloadData];
        NSString *message = self.permissionDenied ? kLang(@"StatusNoAccess") : PPDeliveryErrorText(error);
        [PPAlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:message];
        return;
    }

    self.showSuccessAfterLoad = YES;
    [PPFunc pp_playSuccessEffect];
    [self loadData];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<PPDeliveryRequestRecord *> *filtered = [self filteredRecords];
    if (indexPath.row >= (NSInteger)filtered.count || UIAccessibilityIsReduceMotionEnabled() || self.isLoading) return;
    NSString *identifier = filtered[(NSUInteger)indexPath.row].requestID.length ? filtered[(NSUInteger)indexPath.row].requestID : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedRequestIDs containsObject:identifier]) return;
    [self.animatedRequestIDs addObject:identifier];
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0.0, PPSpaceSM);
    [UIView animateWithDuration:PPAnimDurationSlow
                          delay:MIN(indexPath.row * 0.026, 0.20)
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.3
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
