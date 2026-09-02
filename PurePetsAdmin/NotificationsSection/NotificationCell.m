//
//  NotificationCell.m
//  PurePetsAdmin
//
//  Category-defining administrative notification card cell.
//

#import "NotificationCell.h"
#import "Styling.h"
#import "Language.h"
#import "PPDesignTokens.h"
#import "PPFunc.h"

typedef NS_ENUM(NSInteger, PPAdminNotificationCategory) {
    PPAdminNotificationCategoryGeneral = 0,
    PPAdminNotificationCategoryOrder,
    PPAdminNotificationCategoryDelivery,
    PPAdminNotificationCategorySupport,
    PPAdminNotificationCategoryWarning
};

@interface NotificationCell ()
@property (nonatomic, strong) UIView *cardSurface;
@property (nonatomic, strong) UIView *iconSurface;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UIView *unreadDot;

@property (nonatomic, strong) UILabel *categoryLabel;
@property (nonatomic, strong) UIView *categoryPill;
@property (nonatomic, strong) UILabel *orderPillLabel;
@property (nonatomic, strong) UIView *orderPill;

@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *bodyLabel;

@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong, nullable) NotificationModel *currentModel;
@property (nonatomic, strong) NSLayoutConstraint *actionButtonHeightConstraint;
@end

@implementation NotificationCell

+ (NSString *)reuseId {
    return @"PPAdminNotificationCardCell";
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    _cardSurface = [[UIView alloc] init];
    _cardSurface.translatesAutoresizingMaskIntoConstraints = NO;
    _cardSurface.backgroundColor = [UIColor ppSurfaceElevated];
    _cardSurface.layer.borderWidth = 1.0;
    _cardSurface.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(_cardSurface, PPCornerCard);
    PPApplyCardShadow(_cardSurface);
    _cardSurface.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.contentView addSubview:_cardSurface];

    // Icon Container
    _iconSurface = [[UIView alloc] init];
    _iconSurface.translatesAutoresizingMaskIntoConstraints = NO;
    _iconSurface.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(_iconSurface, 14.0);
    [_cardSurface addSubview:_iconSurface];

    _iconImageView = [[UIImageView alloc] init];
    _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    _iconImageView.tintColor = [UIColor ppPrimary];
    [_iconSurface addSubview:_iconImageView];

    // Unread Glowing Dot
    _unreadDot = [[UIView alloc] init];
    _unreadDot.translatesAutoresizingMaskIntoConstraints = NO;
    _unreadDot.backgroundColor = [UIColor ppPrimary];
    _unreadDot.layer.cornerRadius = 4.0;
    _unreadDot.layer.masksToBounds = YES;
    [_cardSurface addSubview:_unreadDot];

    // Category Pill
    _categoryPill = [[UIView alloc] init];
    _categoryPill.translatesAutoresizingMaskIntoConstraints = NO;
    _categoryPill.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    PPApplyContinuousCorners(_categoryPill, PPCornerPill);
    [_cardSurface addSubview:_categoryPill];

    _categoryLabel = [[UILabel alloc] init];
    _categoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _categoryLabel.font = [Styling fontBold:11.0];
    _categoryLabel.textColor = [UIColor ppPrimary];
    _categoryLabel.textAlignment = NSTextAlignmentCenter;
    [_categoryPill addSubview:_categoryLabel];

    // Order ID Pill
    _orderPill = [[UIView alloc] init];
    _orderPill.translatesAutoresizingMaskIntoConstraints = NO;
    _orderPill.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.6];
    PPApplyContinuousCorners(_orderPill, PPCornerPill);
    _orderPill.hidden = YES;
    [_cardSurface addSubview:_orderPill];

    _orderPillLabel = [[UILabel alloc] init];
    _orderPillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _orderPillLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium];
    _orderPillLabel.textColor = [UIColor ppTextSecondary];
    _orderPillLabel.textAlignment = NSTextAlignmentCenter;
    [_orderPill addSubview:_orderPillLabel];

    // Timestamp
    _timeLabel = [[UILabel alloc] init];
    _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _timeLabel.font = [Styling fontRegular:12.0];
    _timeLabel.textColor = [UIColor ppTextTertiary];
    _timeLabel.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    [_cardSurface addSubview:_timeLabel];

    // Title
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [Styling fontBold:15.5];
    _titleLabel.textColor = [UIColor ppTextPrimary];
    _titleLabel.numberOfLines = 2;
    _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [_cardSurface addSubview:_titleLabel];

    // Body
    _bodyLabel = [[UILabel alloc] init];
    _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bodyLabel.font = [Styling fontRegular:13.5];
    _bodyLabel.textColor = [UIColor ppTextSecondary];
    _bodyLabel.numberOfLines = 2;
    _bodyLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [_cardSurface addSubview:_bodyLabel];

    // Direct Action Button
    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.titleLabel.font = [Styling fontBold:12.5];
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    PPApplyContinuousCorners(_actionButton, PPCornerSmall);
    [_actionButton addTarget:self action:@selector(actionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_cardSurface addSubview:_actionButton];

    _actionButtonHeightConstraint = [_actionButton.heightAnchor constraintEqualToConstant:32.0];

    [NSLayoutConstraint activateConstraints:@[
        [_cardSurface.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        [_cardSurface.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_cardSurface.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_cardSurface.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

        // Icon Surface
        [_iconSurface.topAnchor constraintEqualToAnchor:_cardSurface.topAnchor constant:14],
        [_iconSurface.leadingAnchor constraintEqualToAnchor:_cardSurface.leadingAnchor constant:14],
        [_iconSurface.widthAnchor constraintEqualToConstant:46],
        [_iconSurface.heightAnchor constraintEqualToConstant:46],

        [_iconImageView.centerXAnchor constraintEqualToAnchor:_iconSurface.centerXAnchor],
        [_iconImageView.centerYAnchor constraintEqualToAnchor:_iconSurface.centerYAnchor],
        [_iconImageView.widthAnchor constraintEqualToConstant:24],
        [_iconImageView.heightAnchor constraintEqualToConstant:24],

        // Unread Dot
        [_unreadDot.widthAnchor constraintEqualToConstant:8],
        [_unreadDot.heightAnchor constraintEqualToConstant:8],
        [_unreadDot.topAnchor constraintEqualToAnchor:_iconSurface.topAnchor constant:-2],
        [_unreadDot.trailingAnchor constraintEqualToAnchor:_iconSurface.trailingAnchor constant:2],

        // Top Metadata Row: Category Pill + Order Pill + Time Label
        [_categoryPill.centerYAnchor constraintEqualToAnchor:_timeLabel.centerYAnchor],
        [_categoryPill.leadingAnchor constraintEqualToAnchor:_iconSurface.trailingAnchor constant:12],
        [_categoryPill.heightAnchor constraintEqualToConstant:22],

        [_categoryLabel.leadingAnchor constraintEqualToAnchor:_categoryPill.leadingAnchor constant:8],
        [_categoryLabel.trailingAnchor constraintEqualToAnchor:_categoryPill.trailingAnchor constant:-8],
        [_categoryLabel.centerYAnchor constraintEqualToAnchor:_categoryPill.centerYAnchor],

        [_orderPill.centerYAnchor constraintEqualToAnchor:_categoryPill.centerYAnchor],
        [_orderPill.leadingAnchor constraintEqualToAnchor:_categoryPill.trailingAnchor constant:6],
        [_orderPill.heightAnchor constraintEqualToConstant:22],

        [_orderPillLabel.leadingAnchor constraintEqualToAnchor:_orderPill.leadingAnchor constant:8],
        [_orderPillLabel.trailingAnchor constraintEqualToAnchor:_orderPill.trailingAnchor constant:-8],
        [_orderPillLabel.centerYAnchor constraintEqualToAnchor:_orderPill.centerYAnchor],

        [_timeLabel.topAnchor constraintEqualToAnchor:_cardSurface.topAnchor constant:14],
        [_timeLabel.trailingAnchor constraintEqualToAnchor:_cardSurface.trailingAnchor constant:-14],
        [_timeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_orderPill.trailingAnchor constant:8],

        // Title
        [_titleLabel.topAnchor constraintEqualToAnchor:_categoryPill.bottomAnchor constant:8],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconSurface.trailingAnchor constant:12],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardSurface.trailingAnchor constant:-14],

        // Body
        [_bodyLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_bodyLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_bodyLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

        // Action Button
        [_actionButton.topAnchor constraintEqualToAnchor:_bodyLabel.bottomAnchor constant:10],
        [_actionButton.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        _actionButtonHeightConstraint,
        [_actionButton.bottomAnchor constraintEqualToAnchor:_cardSurface.bottomAnchor constant:-14]
    ]];
}

- (void)actionButtonTapped {
    [PPFunc pp_playTapEffect];
    if (self.onDirectActionTapped && self.currentModel) {
        self.onDirectActionTapped(self.currentModel);
    }
}

- (PPAdminNotificationCategory)categoryForModel:(NotificationModel *)m {
    NSDictionary *meta = [m.meta isKindOfClass:NSDictionary.class] ? m.meta : @{};
    NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];
    if (m.type == PPNotificationTypeOrder || orderID.length > 0) {
        return PPAdminNotificationCategoryOrder;
    }
    
    NSString *type = [meta[@"type"] lowercaseString] ?: @"";
    NSString *title = [m.title lowercaseString] ?: @"";
    
    if ([type containsString:@"delivery"] || [title containsString:@"delivery"] || [title containsString:@"توصيل"] || meta[@"requestId"]) {
        return PPAdminNotificationCategoryDelivery;
    }
    
    if ([type containsString:@"chat"] || [type containsString:@"support"] || [title containsString:@"support"] || [title containsString:@"محادثة"] || meta[@"threadId"] || meta[@"conversationId"]) {
        return PPAdminNotificationCategorySupport;
    }
    
    if (m.type == PPNotificationTypeWarning || [type containsString:@"warn"] || [title containsString:@"warning"] || [title containsString:@"تحذير"]) {
        return PPAdminNotificationCategoryWarning;
    }
    
    return PPAdminNotificationCategoryGeneral;
}

- (void)configure:(NotificationModel *)m {
    _currentModel = m;
    
    // Read state
    _unreadDot.hidden = m.isRead;
    _cardSurface.backgroundColor = m.isRead ? [UIColor ppSurface] : [UIColor ppSurfaceElevated];
    if (!m.isRead) {
        _cardSurface.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.35].CGColor;
    } else {
        _cardSurface.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    }
    
    PPAdminNotificationCategory cat = [self categoryForModel:m];
    
    // Icon & Accent
    UIColor *accent = [UIColor ppPrimary];
    NSString *symbolName = @"bell.badge.fill";
    NSString *categoryText = [Language isRTL] ? @"إشعار عام" : @"Notification";
    
    switch (cat) {
        case PPAdminNotificationCategoryOrder:
            accent = [UIColor ppQuickActionShopping] ?: [UIColor systemOrangeColor];
            symbolName = @"bag.fill";
            categoryText = [Language isRTL] ? @"طلب متجر" : @"Order";
            break;
        case PPAdminNotificationCategoryDelivery:
            accent = [UIColor ppInfo] ?: [UIColor systemTealColor];
            symbolName = @"truck.box.fill";
            categoryText = [Language isRTL] ? @"شحنة وتوصيل" : @"Delivery";
            break;
        case PPAdminNotificationCategorySupport:
            accent = [UIColor ppQuickActionServices] ?: [UIColor systemGreenColor];
            symbolName = @"bubble.left.and.bubble.right.fill";
            categoryText = [Language isRTL] ? @"رسالة دعم" : @"Support";
            break;
        case PPAdminNotificationCategoryWarning:
            accent = [UIColor ppWarning];
            symbolName = @"exclamationmark.triangle.fill";
            categoryText = [Language isRTL] ? @"تنبيه حرج" : @"Alert";
            break;
        case PPAdminNotificationCategoryGeneral:
        default:
            accent = [UIColor ppPrimary];
            symbolName = @"bell.badge.fill";
            categoryText = [Language isRTL] ? @"إشعار نظام" : @"System";
            break;
    }
    
    _iconSurface.backgroundColor = [accent colorWithAlphaComponent:0.12];
    _iconImageView.tintColor = accent;
    _iconImageView.image = [UIImage systemImageNamed:symbolName];
    
    _categoryPill.backgroundColor = [accent colorWithAlphaComponent:0.10];
    _categoryLabel.textColor = accent;
    _categoryLabel.text = categoryText;
    
    // Order ID Pill
    NSDictionary *meta = [m.meta isKindOfClass:NSDictionary.class] ? m.meta : @{};
    NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];
    if (orderID.length > 0) {
        _orderPill.hidden = NO;
        _orderPillLabel.text = [NSString stringWithFormat:@"#%@", orderID];
    } else {
        _orderPill.hidden = YES;
    }
    
    // Title
    NSString *titleKey = meta[@"titleLocalizationKey"];
    NSString *displayTitle = (titleKey.length > 0) ? kLang(titleKey) : m.title;
    _titleLabel.text = displayTitle ?: @"";
    
    // Body
    NSString *bodyKey = meta[@"bodyLocalizationKey"];
    NSString *displayBody = @"";
    if (bodyKey.length > 0) {
        NSString *format = kLang(bodyKey);
        NSString *ref = meta[@"orderReference"] ?: @"";
        displayBody = (ref.length > 0) ? [NSString stringWithFormat:format, ref] : format;
    } else {
        displayBody = m.body ?: @"";
    }
    _bodyLabel.text = displayBody;
    
    // Relative Timestamp
    _timeLabel.text = [self relativeDateStringForDate:m.createdAt];
    
    // Direct Action Button
    if (cat == PPAdminNotificationCategoryOrder && orderID.length > 0) {
        _actionButton.hidden = NO;
        _actionButtonHeightConstraint.constant = 32.0;
        _actionButton.backgroundColor = [accent colorWithAlphaComponent:0.12];
        [_actionButton setTitleColor:accent forState:UIControlStateNormal];
        NSString *btnTitle = [Language isRTL] ? @"عرض الطلب ➔" : @"View Order ➔";
        [_actionButton setTitle:btnTitle forState:UIControlStateNormal];
    } else if (cat == PPAdminNotificationCategorySupport) {
        _actionButton.hidden = NO;
        _actionButtonHeightConstraint.constant = 32.0;
        _actionButton.backgroundColor = [accent colorWithAlphaComponent:0.12];
        [_actionButton setTitleColor:accent forState:UIControlStateNormal];
        NSString *btnTitle = [Language isRTL] ? @"فتح المحادثة ➔" : @"Open Chat ➔";
        [_actionButton setTitle:btnTitle forState:UIControlStateNormal];
    } else {
        _actionButton.hidden = YES;
        _actionButtonHeightConstraint.constant = 0.0;
    }
}

- (NSString *)relativeDateStringForDate:(NSDate *)date {
    if (!date) return @"";
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:date];
    if (interval < 60) {
        return [Language isRTL] ? @"الآن" : @"Just now";
    } else if (interval < 3600) {
        NSInteger mins = (NSInteger)(interval / 60);
        return [Language isRTL] ? [NSString stringWithFormat:@"منذ %ld د", (long)mins]
                                : [NSString stringWithFormat:@"%ldm ago", (long)mins];
    } else if (interval < 86400) {
        NSInteger hours = (NSInteger)(interval / 3600);
        return [Language isRTL] ? [NSString stringWithFormat:@"منذ %ld س", (long)hours]
                                : [NSString stringWithFormat:@"%ldh ago", (long)hours];
    } else {
        static NSDateFormatter *fmt = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            fmt = [[NSDateFormatter alloc] init];
            fmt.dateStyle = NSDateFormatterShortStyle;
            fmt.timeStyle = NSDateFormatterNoStyle;
        });
        return [fmt stringFromDate:date];
    }
}

@end
