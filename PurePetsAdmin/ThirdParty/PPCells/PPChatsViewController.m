//
//  PPChatsViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 2026-07-13.
//

#import "PPChatsViewController.h"
#import "PPHero.h"
#import "PPStaffAuth.h"
#import "Styling.h"
#import "Language.h"
#import "AlertHelper.h"
@import FirebaseAuth;
@import FirebaseFirestore;
@import FirebaseFunctions;

static NSString * const PPChatsSupportConversationType = @"user_support";
static NSString * const PPChatsSupportContextType = @"support";
static NSString * const PPChatsOfficialSupportActorKey = @"support:official";
static NSString * const PPChatsOfficialSupportUserID = @"PUIDPOFFICILAL20262214";
static NSString * const PPChatsCustomerChatScope = @"customer.chat";
static NSString * const PPChatsUserIOSTargetApp = @"user_ios";
static NSInteger const PPChatsSchemaVersion = 2;

static NSString *PPChatsSafeString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [[(id)value stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return @"";
}

static NSDictionary *PPChatsSafeDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? (NSDictionary *)value : @{};
}

static NSArray<NSString *> *PPChatsStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    for (id item in (NSArray *)value) {
        NSString *text = PPChatsSafeString(item);
        if (text.length > 0) [set addObject:text];
    }
    return set.array ?: @[];
}

static NSString *PPChatsL(NSString *key) {
    NSString *value = kLang(key);
    if (![value isKindOfClass:NSString.class] || value.length == 0 || [value isEqualToString:key]) {
        return key;
    }
    return value;
}

static UIFont *PPChatsFont(UIFont *baseFont, UIFontTextStyle style) {
    if (!baseFont) return [UIFont preferredFontForTextStyle:style];
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:baseFont];
    }
    return baseFont;
}

static UIColor *PPChatsAccentColor(void) {
    return [UIColor ppPrimary];
}

static UIColor *PPChatsCanvasColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPChatsSurfaceColor(void) {
    return [UIColor ppElevatedSurface];
}

static UIColor *PPChatsPrimaryTextColor(void) {
    return [UIColor ppTextPrimary];
}

static UIColor *PPChatsSecondaryTextColor(void) {
    return [UIColor ppTextSecondary];
}

static void PPChatsApplyContinuousCorners(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) {
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static void PPChatsApplySoftCardChrome(UIView *view, CGFloat radius) {
    PPChatsApplyContinuousCorners(view, radius);
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.055;
    view.layer.shadowRadius = 18.0;
    view.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.58].CGColor;
}

static NSDate *PPChatsDateFromValue(id value) {
    if ([value isKindOfClass:NSDate.class]) return (NSDate *)value;
    if ([value respondsToSelector:@selector(dateValue)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id date = [value performSelector:@selector(dateValue)];
#pragma clang diagnostic pop
        if ([date isKindOfClass:NSDate.class]) return date;
    }
    return nil;
}

static NSString *PPChatsRelativeDateString(id value) {
    NSDate *date = PPChatsDateFromValue(value);
    if (!date) return @"";
    if (@available(iOS 13.0, *)) {
        NSRelativeDateTimeFormatter *formatter = [NSRelativeDateTimeFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
        formatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleShort;
        return [formatter localizedStringForDate:date relativeToDate:NSDate.date];
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.doesRelativeDateFormatting = YES;
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

static NSString *PPChatsActorKey(NSString *prefix, NSString *uid) {
    NSString *safeUID = PPChatsSafeString(uid);
    if (safeUID.length == 0) return @"";
    return [NSString stringWithFormat:@"%@:%@", prefix, safeUID];
}

static BOOL PPChatsIsSupportOfficialSender(NSDictionary *data) {
    NSString *actorKey = PPChatsSafeString(data[@"lastMessageSenderActorKey"]);
    if (actorKey.length == 0) actorKey = PPChatsSafeString(data[@"senderActorKey"]);
    if (actorKey.length == 0) actorKey = PPChatsSafeString(data[@"visibleSenderActorKey"]);
    if ([actorKey isEqualToString:PPChatsOfficialSupportActorKey]) return YES;

    NSString *senderID = PPChatsSafeString(data[@"senderID"]);
    if (senderID.length == 0) senderID = PPChatsSafeString(data[@"senderId"]);
    return [senderID isEqualToString:PPChatsOfficialSupportUserID];
}

static BOOL PPChatsTargetsSupportOfficial(NSDictionary *data) {
    NSArray<NSString *> *receiverActorKeys = PPChatsStringArray(data[@"receiverActorKeys"]);
    if ([receiverActorKeys containsObject:PPChatsOfficialSupportActorKey]) return YES;
    NSString *targetActorKey = PPChatsSafeString(data[@"targetActorKey"]);
    if ([targetActorKey isEqualToString:PPChatsOfficialSupportActorKey]) return YES;
    NSString *receiverID = PPChatsSafeString(data[@"receiverID"]);
    if (receiverID.length == 0) receiverID = PPChatsSafeString(data[@"receiverId"]);
    return [receiverID isEqualToString:PPChatsOfficialSupportUserID];
}

static NSString *PPChatsFindCustomerUID(NSArray<NSString *> *values, NSString *currentStaffUID) {
    NSString *staffUID = PPChatsSafeString(currentStaffUID);
    for (NSString *uid in values) {
        NSString *candidate = PPChatsSafeString(uid);
        if (candidate.length == 0) continue;
        if ([candidate isEqualToString:PPChatsOfficialSupportUserID]) continue;
        if (staffUID.length > 0 && [candidate isEqualToString:staffUID]) continue;
        return candidate;
    }
    return @"";
}

static NSString *PPChatsResolveCustomerID(NSDictionary *data, NSString *currentStaffUID) {
    NSString *direct = PPChatsSafeString(data[@"customerId"]);
    if (direct.length == 0) direct = PPChatsSafeString(data[@"customerID"]);
    if (direct.length == 0) direct = PPChatsSafeString(data[@"userId"]);
    if (direct.length == 0) direct = PPChatsSafeString(data[@"userID"]);
    if (direct.length > 0 && ![direct isEqualToString:PPChatsOfficialSupportUserID] && ![direct isEqualToString:PPChatsSafeString(currentStaffUID)]) return direct;

    NSString *targetUID = PPChatsSafeString(data[@"targetUid"]);
    if (targetUID.length > 0 && ![targetUID isEqualToString:PPChatsOfficialSupportUserID] && ![targetUID isEqualToString:PPChatsSafeString(currentStaffUID)]) return targetUID;

    NSString *participantUID = PPChatsFindCustomerUID(PPChatsStringArray(data[@"participantUids"]), currentStaffUID);
    if (participantUID.length > 0) return participantUID;

    NSString *memberUID = PPChatsFindCustomerUID(PPChatsStringArray(data[@"members"]), currentStaffUID);
    if (memberUID.length > 0) return memberUID;

    NSString *senderID = PPChatsSafeString(data[@"senderID"]);
    if (senderID.length == 0) senderID = PPChatsSafeString(data[@"senderId"]);
    if (senderID.length > 0 && ![senderID isEqualToString:PPChatsOfficialSupportUserID] && ![senderID isEqualToString:PPChatsSafeString(currentStaffUID)]) return senderID;

    NSString *receiverID = PPChatsSafeString(data[@"receiverID"]);
    if (receiverID.length == 0) receiverID = PPChatsSafeString(data[@"receiverId"]);
    if (receiverID.length > 0 && ![receiverID isEqualToString:PPChatsOfficialSupportUserID] && ![receiverID isEqualToString:PPChatsSafeString(currentStaffUID)]) return receiverID;

    return @"";
}

static NSString *PPChatsCustomerDisplayName(NSDictionary *thread, NSString *currentStaffUID) {
    NSString *customerID = PPChatsResolveCustomerID(thread, currentStaffUID);
    NSDictionary *memberNames = PPChatsSafeDictionary(thread[@"memberNames"]);
    NSString *name = PPChatsSafeString(memberNames[customerID]);
    if (name.length == 0) name = PPChatsSafeString(thread[@"customerName"]);
    if (name.length == 0) name = PPChatsSafeString(thread[@"displayName"]);
    if (name.length == 0) name = PPChatsSafeString(thread[@"name"]);
    if (name.length == 0 && customerID.length >= 8) name = [customerID substringToIndex:8];
    if (name.length == 0) name = PPChatsL(@"SupportChats_CustomerFallback");
    return name;
}

static NSString *PPChatsStatusKey(NSString *status) {
    NSString *safe = PPChatsSafeString(status).lowercaseString;
    if ([safe isEqualToString:@"active"]) return @"SupportChats_Status_Active";
    if ([safe isEqualToString:@"resolved"]) return @"SupportChats_Status_Resolved";
    if ([safe isEqualToString:@"closed"]) return @"SupportChats_Status_Closed";
    if ([safe isEqualToString:@"waiting_for_agent"] || safe.length == 0) return @"SupportChats_Status_Waiting";
    return @"SupportChats_Status_Support";
}

static NSString *PPChatsStatusText(NSString *status) {
    return PPChatsL(PPChatsStatusKey(status));
}

static UIColor *PPChatsStatusColor(NSString *status) {
    NSString *safe = PPChatsSafeString(status).lowercaseString;
    if ([safe isEqualToString:@"resolved"]) return [UIColor ppSuccess];
    if ([safe isEqualToString:@"closed"]) return [UIColor ppTextSecondary];
    if ([safe isEqualToString:@"active"]) return [UIColor ppInfo];
    return PPChatsAccentColor();
}

static BOOL PPChatsThreadIsUnread(NSDictionary *thread, NSString *currentStaffUID) {
    NSString *lastMessage = PPChatsSafeString(thread[@"lastMessage"]);
    if (lastMessage.length == 0) return NO;
    if (PPChatsIsSupportOfficialSender(thread)) return NO;
    NSString *lastReadActorKey = PPChatsSafeString(thread[@"lastReadActorKey"]);
    if ([lastReadActorKey isEqualToString:PPChatsOfficialSupportActorKey]) return NO;
    NSString *lastReadBy = PPChatsSafeString(thread[@"lastReadBy"]);
    return ![lastReadBy isEqualToString:PPChatsSafeString(currentStaffUID)];
}

static BOOL PPChatsThreadIsOpen(NSDictionary *thread) {
    NSString *status = PPChatsSafeString(thread[@"supportStatus"]).lowercaseString;
    return status.length == 0 || [status isEqualToString:@"waiting_for_agent"] || [status isEqualToString:@"active"];
}

static NSMutableDictionary *PPChatsSupportBaseFields(NSString *threadID, NSString *customerUID, NSString *staffUID) {
    NSString *safeThreadID = PPChatsSafeString(threadID);
    NSString *safeCustomerUID = PPChatsSafeString(customerUID);
    NSString *safeStaffUID = PPChatsSafeString(staffUID);
    NSString *customerActorKey = PPChatsActorKey(@"user", safeCustomerUID);
    NSString *staffActorKey = PPChatsActorKey(@"support_agent", safeStaffUID);

    NSMutableDictionary *payload = [@{
        @"schemaVersion": @(PPChatsSchemaVersion),
        @"conversationId": safeThreadID,
        @"conversationType": PPChatsSupportConversationType,
        @"contextType": PPChatsSupportContextType,
        @"contextId": safeThreadID,
        @"threadId": safeThreadID,
        @"threadID": safeThreadID,
        @"supportActorKey": PPChatsOfficialSupportActorKey,
        @"supportUserId": PPChatsOfficialSupportUserID,
        @"customerId": safeCustomerUID,
        @"customerActorKey": customerActorKey,
        @"participantKeys": @[PPChatsOfficialSupportActorKey, customerActorKey],
        @"participantUids": @[PPChatsOfficialSupportUserID, safeCustomerUID],
        @"targetUid": safeCustomerUID,
        @"targetActorKey": customerActorKey,
        @"targetApp": PPChatsUserIOSTargetApp,
        @"scope": PPChatsCustomerChatScope,
        @"route": @"chat",
        @"notificationType": @"chat",
        @"updatedByActorKey": staffActorKey,
        @"updatedByUid": safeStaffUID
    } mutableCopy];
    return payload;
}

static NSMutableDictionary *PPChatsSupportOutgoingThreadFields(NSString *threadID, NSString *customerUID, NSString *staffUID) {
    NSMutableDictionary *payload = PPChatsSupportBaseFields(threadID, customerUID, staffUID);
    NSString *customerActorKey = PPChatsActorKey(@"user", customerUID);
    NSString *staffActorKey = PPChatsActorKey(@"support_agent", staffUID);
    payload[@"lastMessageSenderActorKey"] = PPChatsOfficialSupportActorKey;
    payload[@"lastMessageSenderAuditUid"] = PPChatsSafeString(staffUID);
    payload[@"lastMessageSenderAuditActorKey"] = staffActorKey;
    payload[@"lastMessageReceiverActorKeys"] = customerActorKey.length > 0 ? @[customerActorKey] : @[];
    return payload;
}

static NSMutableDictionary *PPChatsSupportOutgoingMessageFields(NSString *threadID, NSString *messageID, NSString *customerUID, NSString *staffUID) {
    NSMutableDictionary *payload = PPChatsSupportBaseFields(threadID, customerUID, staffUID);
    NSString *safeMessageID = PPChatsSafeString(messageID);
    NSString *customerActorKey = PPChatsActorKey(@"user", customerUID);
    NSString *staffActorKey = PPChatsActorKey(@"support_agent", staffUID);
    payload[@"ID"] = safeMessageID;
    payload[@"id"] = safeMessageID;
    payload[@"messageId"] = safeMessageID;
    payload[@"senderActorKey"] = PPChatsOfficialSupportActorKey;
    payload[@"visibleSenderActorKey"] = PPChatsOfficialSupportActorKey;
    payload[@"senderAuditUid"] = PPChatsSafeString(staffUID);
    payload[@"senderAuditActorKey"] = staffActorKey;
    payload[@"receiverActorKeys"] = customerActorKey.length > 0 ? @[customerActorKey] : @[];
    return payload;
}

static NSDictionary *PPChatsReadV2Fields(NSString *staffUID) {
    NSString *safeStaffUID = PPChatsSafeString(staffUID);
    return @{
        @"lastReadActorKey": PPChatsOfficialSupportActorKey,
        @"lastReadByActorKey": PPChatsActorKey(@"support_agent", safeStaffUID),
        @"lastReadByUid": safeStaffUID
    };
}

static NSDictionary *PPChatsMessageReadV2Fields(NSString *staffUID) {
    NSString *safeStaffUID = PPChatsSafeString(staffUID);
    return @{
        @"readByActorKey": PPChatsOfficialSupportActorKey,
        @"readByAuditUid": safeStaffUID,
        @"readByAuditActorKey": PPChatsActorKey(@"support_agent", safeStaffUID)
    };
}

#pragma mark - Cells

@interface PPSupportChatCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconPlate;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *unreadDot;
- (void)configureWithName:(NSString *)name
                  message:(NSString *)message
                     time:(NSString *)time
                   status:(NSString *)status
              statusColor:(UIColor *)statusColor
                   unread:(BOOL)unread;
@end

@implementation PPSupportChatCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPChatsSurfaceColor();
        PPChatsApplySoftCardChrome(_cardView, 22.0);
        [self.contentView addSubview:_cardView];

        _iconPlate = [UIView new];
        _iconPlate.translatesAutoresizingMaskIntoConstraints = NO;
        _iconPlate.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
        PPChatsApplyContinuousCorners(_iconPlate, 18.0);
        _iconPlate.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _iconPlate.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.25].CGColor;
        [_cardView addSubview:_iconPlate];

        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = [UIColor ppPrimary];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconPlate addSubview:_iconView];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = PPChatsFont([Styling fontBold:16.0], UIFontTextStyleHeadline);
        _nameLabel.adjustsFontForContentSizeCategory = YES;
        _nameLabel.textColor = PPChatsPrimaryTextColor();
        _nameLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _nameLabel.numberOfLines = 1;
        [_cardView addSubview:_nameLabel];

        _messageLabel = [UILabel new];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.font = PPChatsFont([Styling fontRegular:13.0], UIFontTextStyleSubheadline);
        _messageLabel.adjustsFontForContentSizeCategory = YES;
        _messageLabel.textColor = PPChatsSecondaryTextColor();
        _messageLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _messageLabel.numberOfLines = 2;
        [_cardView addSubview:_messageLabel];

        _timeLabel = [UILabel new];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.font = PPChatsFont([Styling fontRegular:11.0], UIFontTextStyleCaption1);
        _timeLabel.adjustsFontForContentSizeCategory = YES;
        _timeLabel.textColor = PPChatsSecondaryTextColor();
        _timeLabel.textAlignment = NSTextAlignmentNatural;
        [_cardView addSubview:_timeLabel];

        _statusLabel = [UILabel new];
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel.font = PPChatsFont([Styling fontBold:11.0], UIFontTextStyleCaption1);
        _statusLabel.adjustsFontForContentSizeCategory = YES;
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.numberOfLines = 1;
        PPChatsApplyContinuousCorners(_statusLabel, 12.0);
        _statusLabel.layer.masksToBounds = YES;
        _statusLabel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        [_cardView addSubview:_statusLabel];

        _unreadDot = [UIView new];
        _unreadDot.translatesAutoresizingMaskIntoConstraints = NO;
        _unreadDot.backgroundColor = PPChatsAccentColor();
        PPChatsApplyContinuousCorners(_unreadDot, 5.0);
        [_cardView addSubview:_unreadDot];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            [_iconPlate.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14.0],
            [_iconPlate.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_iconPlate.widthAnchor constraintEqualToConstant:44.0],
            [_iconPlate.heightAnchor constraintEqualToConstant:44.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconPlate.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconPlate.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:24.0],
            [_iconView.heightAnchor constraintEqualToConstant:24.0],

            [_timeLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_timeLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],

            [_nameLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconPlate.trailingAnchor constant:12.0],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-10.0],

            [_statusLabel.topAnchor constraintEqualToAnchor:_timeLabel.bottomAnchor constant:8.0],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:_timeLabel.trailingAnchor],
            [_statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:76.0],
            [_statusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:24.0],

            [_messageLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:5.0],
            [_messageLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_messageLabel.trailingAnchor constraintEqualToAnchor:_statusLabel.leadingAnchor constant:-12.0],
            [_messageLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-15.0],

            [_unreadDot.leadingAnchor constraintEqualToAnchor:_iconPlate.leadingAnchor constant:-1.0],
            [_unreadDot.bottomAnchor constraintEqualToAnchor:_iconPlate.bottomAnchor constant:1.0],
            [_unreadDot.widthAnchor constraintEqualToConstant:10.0],
            [_unreadDot.heightAnchor constraintEqualToConstant:10.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.cardView.transform = CGAffineTransformIdentity;
    self.cardView.alpha = 1.0;
    self.nameLabel.text = nil;
    self.messageLabel.text = nil;
    self.timeLabel.text = nil;
    self.statusLabel.text = nil;
    self.unreadDot.hidden = YES;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CGFloat scale = highlighted ? 0.985 : 1.0;
    NSTimeInterval duration = highlighted ? 0.08 : 0.16;
    [UIView animateWithDuration:duration delay:0.0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.cardView.transform = CGAffineTransformMakeScale(scale, scale);
        self.cardView.alpha = highlighted ? 0.94 : 1.0;
    } completion:nil];
}

- (void)configureWithName:(NSString *)name
                  message:(NSString *)message
                     time:(NSString *)time
                   status:(NSString *)status
              statusColor:(UIColor *)statusColor
                   unread:(BOOL)unread {
    UIColor *accent = statusColor ?: PPChatsAccentColor();
    self.nameLabel.text = name;
    self.messageLabel.text = message.length > 0 ? message : PPChatsL(@"SupportChats_MessageFallback");
    self.timeLabel.text = time;
    self.statusLabel.text = status;
    self.statusLabel.textColor = accent;
    self.statusLabel.backgroundColor = [accent colorWithAlphaComponent:0.12];
    self.statusLabel.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;
    self.unreadDot.hidden = !unread;
    self.iconView.image = [UIImage systemImageNamed:unread ? @"exclamationmark.bubble.fill" : @"person.crop.circle.fill"];
    self.iconView.tintColor = accent;
    self.iconPlate.backgroundColor = [accent colorWithAlphaComponent:0.11];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@, %@", name ?: @"", status ?: @"", message ?: @"", time ?: @""];
    self.accessibilityTraits = UIAccessibilityTraitButton;
}

@end

@interface PPSupportStateCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)configureWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle;
@end

@implementation PPSupportStateCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lifepreserver.fill"]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = PPChatsAccentColor();
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = PPChatsFont([Styling fontBold:18.0], UIFontTextStyleHeadline);
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.textColor = PPChatsPrimaryTextColor();
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 0;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = PPChatsFont([Styling fontRegular:14.0], UIFontTextStyleSubheadline);
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        _subtitleLabel.textColor = PPChatsSecondaryTextColor();
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.numberOfLines = 0;
        [self.contentView addSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:56.0],
            [_iconView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:36.0],
            [_iconView.heightAnchor constraintEqualToConstant:36.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:14.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:34.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-34.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-54.0],
        ]];
    }
    return self;
}

- (void)configureWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle {
    self.iconView.image = [UIImage systemImageNamed:symbol];
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", title ?: @"", subtitle ?: @""];
}

@end

@interface PPSupportMessageCell : UITableViewCell
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) NSLayoutConstraint *leadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *trailingConstraint;
- (void)configureWithText:(NSString *)text meta:(NSString *)meta outgoing:(BOOL)outgoing;
@end

@implementation PPSupportMessageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _bubbleView = [UIView new];
        _bubbleView.translatesAutoresizingMaskIntoConstraints = NO;
        PPChatsApplyContinuousCorners(_bubbleView, 20.0);
        [self.contentView addSubview:_bubbleView];

        _messageLabel = [UILabel new];
        _messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _messageLabel.font = PPChatsFont([Styling fontRegular:15.0], UIFontTextStyleBody);
        _messageLabel.adjustsFontForContentSizeCategory = YES;
        _messageLabel.numberOfLines = 0;
        _messageLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_bubbleView addSubview:_messageLabel];

        _metaLabel = [UILabel new];
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel.font = PPChatsFont([Styling fontRegular:11.0], UIFontTextStyleCaption1);
        _metaLabel.adjustsFontForContentSizeCategory = YES;
        _metaLabel.textColor = PPChatsSecondaryTextColor();
        _metaLabel.textAlignment = NSTextAlignmentNatural;
        [_bubbleView addSubview:_metaLabel];

        _leadingConstraint = [_bubbleView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0];
        _trailingConstraint = [_bubbleView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0];

        [NSLayoutConstraint activateConstraints:@[
            [_bubbleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [_bubbleView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.78],
            [_bubbleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],

            [_messageLabel.topAnchor constraintEqualToAnchor:_bubbleView.topAnchor constant:12.0],
            [_messageLabel.leadingAnchor constraintEqualToAnchor:_bubbleView.leadingAnchor constant:14.0],
            [_messageLabel.trailingAnchor constraintEqualToAnchor:_bubbleView.trailingAnchor constant:-14.0],

            [_metaLabel.topAnchor constraintEqualToAnchor:_messageLabel.bottomAnchor constant:6.0],
            [_metaLabel.leadingAnchor constraintEqualToAnchor:_messageLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:_messageLabel.trailingAnchor],
            [_metaLabel.bottomAnchor constraintEqualToAnchor:_bubbleView.bottomAnchor constant:-10.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.bubbleView.transform = CGAffineTransformIdentity;
    self.messageLabel.text = nil;
    self.metaLabel.text = nil;
}

- (void)configureWithText:(NSString *)text meta:(NSString *)meta outgoing:(BOOL)outgoing {
    self.leadingConstraint.active = !outgoing;
    self.trailingConstraint.active = outgoing;
    self.bubbleView.backgroundColor = outgoing ? [PPChatsAccentColor() colorWithAlphaComponent:0.14] : PPChatsSurfaceColor();
    self.messageLabel.textColor = PPChatsPrimaryTextColor();
    self.messageLabel.text = text.length > 0 ? text : PPChatsL(@"SupportChats_MessageFallback");
    self.metaLabel.text = meta;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", self.messageLabel.text ?: @"", meta ?: @""];
}

@end

#pragma mark - Thread Detail

@interface PPSupportThreadViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, copy) NSDictionary *thread;
@property (nonatomic, copy) NSString *currentUID;
@property (nonatomic, assign) BOOL canManageSupport;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputContainer;
@property (nonatomic, strong) UITextField *messageField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UISegmentedControl *statusControl;
@property (nonatomic, strong) NSArray<NSDictionary *> *messages;
@property (nonatomic, strong) id<FIRListenerRegistration> messagesListener;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL isSending;
@property (nonatomic, assign) BOOL didCaptureNavigationBarHiddenState;
@property (nonatomic, assign) BOOL previousNavigationBarHiddenState;
- (instancetype)initWithThread:(NSDictionary *)thread currentUID:(NSString *)currentUID canManageSupport:(BOOL)canManageSupport;
@end

@implementation PPSupportThreadViewController

- (instancetype)initWithThread:(NSDictionary *)thread currentUID:(NSString *)currentUID canManageSupport:(BOOL)canManageSupport {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _thread = [thread copy] ?: @{};
        _currentUID = [currentUID copy] ?: @"";
        _canManageSupport = canManageSupport;
        _messages = @[];
    }
    return self;
}

- (void)dealloc {
    [self.messagesListener remove];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PPChatsCanvasColor();
    self.title = PPChatsCustomerDisplayName(self.thread, self.currentUID);
    [self setupTableView];
    [self setupInputBar];
    [self setupThreadHeader];
    [self listenMessages];
    [self markThreadRead];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_applyNoNavigationBarAnimated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self pp_restoreNavigationBarIfNeededAnimated:animated];
}

- (void)pp_applyNoNavigationBarAnimated:(BOOL)animated {
    if (!self.navigationController) return;
    if (!self.didCaptureNavigationBarHiddenState) {
        self.previousNavigationBarHiddenState = self.navigationController.navigationBarHidden;
        self.didCaptureNavigationBarHiddenState = YES;
    }
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)pp_restoreNavigationBarIfNeededAnimated:(BOOL)animated {
    if (!self.navigationController || !self.didCaptureNavigationBarHiddenState) return;
    [self.navigationController setNavigationBarHidden:self.previousNavigationBarHiddenState animated:animated];
    self.didCaptureNavigationBarHiddenState = NO;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 92.0;
    [self.tableView registerClass:PPSupportMessageCell.class forCellReuseIdentifier:@"MessageCell"];
    [self.tableView registerClass:PPSupportStateCell.class forCellReuseIdentifier:@"StateCell"];
    [self.view addSubview:self.tableView];
}

- (void)setupInputBar {
    self.inputContainer = [UIView new];
    self.inputContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputContainer.backgroundColor = [PPChatsSurfaceColor() colorWithAlphaComponent:0.96];
    self.inputContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.inputContainer.layer.borderColor = [PPChatsSecondaryTextColor() colorWithAlphaComponent:0.10].CGColor;
    [self.view addSubview:self.inputContainer];

    self.messageField = [UITextField new];
    self.messageField.translatesAutoresizingMaskIntoConstraints = NO;
    self.messageField.placeholder = self.canManageSupport ? PPChatsL(@"SupportChats_MessagePlaceholder") : PPChatsL(@"SupportChats_ManageDenied");
    self.messageField.enabled = self.canManageSupport;
    self.messageField.delegate = self;
    self.messageField.font = PPChatsFont([Styling fontRegular:15.0], UIFontTextStyleBody);
    self.messageField.textAlignment = [Language alignmentForCurrentLanguage];
    self.messageField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    if (@available(iOS 13.0, *)) {
        self.messageField.backgroundColor = [UIColor ppSurfaceOverlay];
    } else {
        self.messageField.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    }
    PPChatsApplyContinuousCorners(self.messageField, 20.0);
    UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14.0, 1.0)];
    self.messageField.leftView = padding;
    self.messageField.leftViewMode = UITextFieldViewModeAlways;
    self.messageField.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14.0, 1.0)];
    self.messageField.rightViewMode = UITextFieldViewModeAlways;
    [self.inputContainer addSubview:self.messageField];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *sendImage = [UIImage systemImageNamed:Language.isRTL ? @"arrow.left.circle.fill" : @"arrow.right.circle.fill"];
    [self.sendButton setImage:sendImage forState:UIControlStateNormal];
    self.sendButton.tintColor = PPChatsAccentColor();
    self.sendButton.enabled = self.canManageSupport;
    self.sendButton.accessibilityLabel = PPChatsL(@"SupportChats_Send");
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputContainer addSubview:self.sendButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.inputContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.inputContainer.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.inputContainer.heightAnchor constraintGreaterThanOrEqualToConstant:78.0],

        [self.messageField.leadingAnchor constraintEqualToAnchor:self.inputContainer.leadingAnchor constant:16.0],
        [self.messageField.topAnchor constraintEqualToAnchor:self.inputContainer.topAnchor constant:12.0],
        [self.messageField.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-10.0],
        [self.messageField.heightAnchor constraintEqualToConstant:44.0],
        [self.messageField.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],

        [self.sendButton.trailingAnchor constraintEqualToAnchor:self.inputContainer.trailingAnchor constant:-16.0],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.messageField.centerYAnchor],
        [self.sendButton.widthAnchor constraintEqualToConstant:44.0],
        [self.sendButton.heightAnchor constraintEqualToConstant:44.0],

        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputContainer.topAnchor],
    ]];
}

- (void)setupThreadHeader {
    CGFloat width = MAX(CGRectGetWidth(self.view.bounds), UIScreen.mainScreen.bounds.size.width);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 126.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    [header addSubview:card];

    PPHero *glassBG = [PPHero new];
    glassBG.translatesAutoresizingMaskIntoConstraints = NO;
    glassBG.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    glassBG.cornerGlowOpacityMultiplier = 0.55;
    glassBG.accentColorOverride = [UIColor ppPrimary];
    [card addSubview:glassBG];

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *backSymbol = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    NSString *backSymbolName = Language.isRTL ? @"chevron.right" : @"chevron.left";
    [backButton setImage:[UIImage systemImageNamed:backSymbolName withConfiguration:backSymbol] forState:UIControlStateNormal];
    backButton.tintColor = [UIColor ppPrimary];
    backButton.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    PPChatsApplyContinuousCorners(backButton, 22.0);
    backButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    backButton.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.30].CGColor;
    backButton.accessibilityLabel = PPChatsL(@"Back");
    [backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:backButton];

    UILabel *name = [UILabel new];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.font = PPChatsFont([Styling fontBold:19.0], UIFontTextStyleTitle3);
    name.adjustsFontForContentSizeCategory = YES;
    name.textColor = PPChatsPrimaryTextColor();
    name.textAlignment = [Language alignmentForCurrentLanguage];
    name.text = PPChatsCustomerDisplayName(self.thread, self.currentUID);
    [card addSubview:name];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.font = PPChatsFont([Styling fontBold:12.0], UIFontTextStyleCaption1);
    subtitle.adjustsFontForContentSizeCategory = YES;
    subtitle.textColor = [UIColor ppPrimary];
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.text = self.canManageSupport ? PPChatsL(@"SupportChats_SupportReady") : PPChatsL(@"SupportChats_ReadOnly");
    [card addSubview:subtitle];

    self.statusControl = [[UISegmentedControl alloc] initWithItems:@[
        PPChatsL(@"SupportChats_Status_Waiting"),
        PPChatsL(@"SupportChats_Status_Active"),
        PPChatsL(@"SupportChats_Status_Resolved"),
        PPChatsL(@"SupportChats_Status_Closed")
    ]];
    self.statusControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusControl.enabled = self.canManageSupport;
    if (@available(iOS 13.0, *)) {
        self.statusControl.selectedSegmentTintColor = [UIColor ppPrimary];
        [self.statusControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [Styling fontBold:13.0]} forState:UIControlStateSelected];
        [self.statusControl setTitleTextAttributes:@{NSForegroundColorAttributeName: PPChatsSecondaryTextColor(), NSFontAttributeName: [Styling fontRegular:13.0]} forState:UIControlStateNormal];
    }
    [self.statusControl addTarget:self action:@selector(statusChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:self.statusControl];
    [self refreshStatusControl];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:12.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-10.0],

        [glassBG.topAnchor constraintEqualToAnchor:card.topAnchor],
        [glassBG.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [glassBG.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [glassBG.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [name.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [name.leadingAnchor constraintEqualToAnchor:backButton.trailingAnchor constant:10.0],
        [name.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],

        [subtitle.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],

        [backButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [backButton.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [backButton.widthAnchor constraintEqualToConstant:44.0],
        [backButton.heightAnchor constraintEqualToConstant:44.0],

        [self.statusControl.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:12.0],
        [self.statusControl.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [self.statusControl.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [self.statusControl.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],
    ]];

    self.tableView.tableHeaderView = header;
}

- (void)backTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)refreshStatusControl {
    NSString *status = PPChatsSafeString(self.thread[@"supportStatus"]).lowercaseString;
    if ([status isEqualToString:@"active"]) self.statusControl.selectedSegmentIndex = 1;
    else if ([status isEqualToString:@"resolved"]) self.statusControl.selectedSegmentIndex = 2;
    else if ([status isEqualToString:@"closed"]) self.statusControl.selectedSegmentIndex = 3;
    else self.statusControl.selectedSegmentIndex = 0;
}

- (NSString *)threadID {
    return PPChatsSafeString(self.thread[@"id"]);
}

- (NSString *)customerID {
    return PPChatsResolveCustomerID(self.thread, self.currentUID);
}

- (void)listenMessages {
    NSString *threadID = [self threadID];
    if (threadID.length == 0) return;
    self.isLoading = YES;
    [self.tableView reloadData];

    FIRCollectionReference *messagesRef = [[[[FIRFirestore firestore] collectionWithPath:@"Chats"] documentWithPath:threadID] collectionWithPath:@"Messages"];
    FIRQuery *query = [[messagesRef queryOrderedByField:@"timestamp" descending:NO] queryLimitedTo:200];
    __weak typeof(self) weakSelf = self;
    self.messagesListener = [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            if (error) {
                self.messages = @[];
                [self.tableView reloadData];
                return;
            }
            NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
            for (FIRDocumentSnapshot *document in snapshot.documents) {
                NSMutableDictionary *data = [(document.data ?: @{}) mutableCopy];
                data[@"id"] = document.documentID ?: @"";
                [items addObject:data.copy];
            }
            self.messages = items.copy;
            [self.tableView reloadData];
            [self scrollToBottomAnimated:YES];
            [self markMessagesReadIfNeeded];
        });
    }];
}

- (void)markThreadRead {
    NSString *threadID = [self threadID];
    if (threadID.length == 0 || self.currentUID.length == 0) return;
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"supportChatCommand"];
    callable.timeoutInterval = 30.0;
    [callable callWithObject:@{
        @"action": @"mark_read",
        @"threadId": threadID,
        @"expectedLastMessageId": PPChatsSafeString(self.thread[@"lastMessageId"] ?: self.thread[@"lastProjectedMessageId"])
    } completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {}];
}

- (void)markMessagesReadIfNeeded {
    [self markThreadRead];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count == 0) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (void)statusChanged:(UISegmentedControl *)sender {
    if (!self.canManageSupport) return;
    NSArray<NSString *> *statuses = @[@"waiting_for_agent", @"active", @"resolved", @"closed"];
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)statuses.count) return;
    NSString *nextStatus = statuses[sender.selectedSegmentIndex];
    NSString *threadID = [self threadID];
    if (threadID.length == 0 || self.currentUID.length == 0) return;
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"supportChatCommand"];
    callable.timeoutInterval = 30.0;
    [callable callWithObject:@{
        @"action": @"transition",
        @"threadId": threadID,
        @"toStatus": nextStatus,
        @"expectedVersion": self.thread[@"supportLifecycleVersion"] ?: @0,
        @"reason": @"admin_status_change"
    } completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [self refreshStatusControl];
                [AlertHelper showAlertIn:self title:PPChatsL(@"Error_Title") subtitle:PPChatsL(@"SupportChats_ReplyError")];
                return;
            }
            NSMutableDictionary *nextThread = [self.thread mutableCopy];
            nextThread[@"supportStatus"] = nextStatus;
            NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : @{};
            nextThread[@"supportLifecycleVersion"] = response[@"supportLifecycleVersion"] ?: nextThread[@"supportLifecycleVersion"];
            self.thread = nextThread.copy;
        });
    }];
}

- (void)sendTapped {
    [self sendCurrentMessage];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendCurrentMessage];
    return YES;
}

- (void)sendCurrentMessage {
    if (!self.canManageSupport || self.isSending) return;
    NSString *text = PPChatsSafeString(self.messageField.text);
    NSString *threadID = [self threadID];
    NSString *customerID = [self customerID];
    if (text.length == 0 || threadID.length == 0 || customerID.length == 0 || self.currentUID.length == 0) return;

    self.isSending = YES;
    self.sendButton.enabled = NO;
    self.messageField.text = @"";
    __weak typeof(self) weakSelf = self;
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"supportChatCommand"];
    callable.timeoutInterval = 30.0;
    [callable callWithObject:@{
        @"action": @"send_staff_reply",
        @"threadId": threadID,
        @"messageId": [NSUUID UUID].UUIDString,
        @"expectedVersion": self.thread[@"supportLifecycleVersion"] ?: @0,
        @"sourceApp": @"admin_ios",
        @"sourcePlatform": @"ios",
        @"message": @{ @"text": text, @"type": @0 }
    } completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error) {
                self.isSending = NO;
                self.sendButton.enabled = self.canManageSupport;
                self.messageField.text = text;
                [AlertHelper showAlertIn:self title:PPChatsL(@"Error_Title") subtitle:PPChatsL(@"SupportChats_ReplyError")];
                return;
            }
            self.isSending = NO;
            self.sendButton.enabled = self.canManageSupport;
            NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : @{};
            NSMutableDictionary *nextThread = [self.thread mutableCopy];
            nextThread[@"supportStatus"] = response[@"supportStatus"] ?: @"active";
            nextThread[@"supportLifecycleVersion"] = response[@"supportLifecycleVersion"] ?: nextThread[@"supportLifecycleVersion"];
            self.thread = nextThread.copy;
        });
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count > 0 ? self.messages.count : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.messages.count == 0) {
        PPSupportStateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StateCell" forIndexPath:indexPath];
        if (self.isLoading) {
            [cell configureWithSymbol:@"ellipsis.message.fill" title:PPChatsL(@"SupportChats_MessagesLoading") subtitle:@""];
        } else {
            [cell configureWithSymbol:@"bubble.left.and.bubble.right.fill" title:PPChatsL(@"SupportChats_MessagesEmpty") subtitle:@""];
        }
        return cell;
    }

    NSDictionary *message = self.messages[indexPath.row];
    BOOL outgoing = PPChatsIsSupportOfficialSender(message);
    NSString *text = PPChatsSafeString(message[@"text"]);
    if (text.length == 0) text = PPChatsSafeString(message[@"message"]);
    NSString *meta = PPChatsRelativeDateString(message[@"timestamp"]);
    if (meta.length == 0) meta = PPChatsRelativeDateString(message[@"createdAt"]);
    PPSupportMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MessageCell" forIndexPath:indexPath];
    [cell configureWithText:text meta:meta outgoing:outgoing];
    return cell;
}

@end

#pragma mark - Chat List

@interface PPChatsViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPHero *heroGlassBG;
@property (nonatomic, strong) UILabel *heroUnreadCountLabel;
@property (nonatomic, strong) UILabel *heroActiveCountLabel;
@property (nonatomic, strong) UILabel *heroSubtitleLabel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSArray<NSDictionary *> *allChats;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredChats;
@property (nonatomic, strong) id<FIRListenerRegistration> supportListener;
@property (nonatomic, copy) NSString *currentUID;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, copy) NSString *stateTitle;
@property (nonatomic, copy) NSString *stateSubtitle;
@property (nonatomic, copy) NSString *stateSymbol;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) BOOL hasViewPermission;
@property (nonatomic, assign) BOOL hasManagePermission;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL didRunEntrance;
@property (nonatomic, assign) BOOL didCaptureNavigationBarHiddenState;
@property (nonatomic, assign) BOOL previousNavigationBarHiddenState;

@end

@implementation PPChatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PPChatsCanvasColor();
    self.title = PPChatsL(@"SupportChats_Title");
    self.allChats = @[];
    self.filteredChats = @[];
    self.stateSymbol = @"ellipsis.message.fill";
    self.stateTitle = PPChatsL(@"SupportChats_Loading");
    self.stateSubtitle = @"";
    [self setupTableView];
    [self setupHeaderUI];
    [self prepareEntranceState];
    [self refreshStaffAndStartListener];
}

- (void)dealloc {
    [self.supportListener remove];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_applyNoNavigationBarAnimated:animated];
    [self prepareEntranceState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self sizeHeaderToFit];
    if (!self.didPrepareEntrance) {
        [self prepareEntranceState];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroGlassBG startAnimations];
    [self runEntranceIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.heroGlassBG stopAnimations];
    if (![self.navigationController.topViewController isKindOfClass:PPSupportThreadViewController.class]) {
        [self pp_restoreNavigationBarIfNeededAnimated:animated];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.heroGlassBG reapplyPalette];
        [self.tableView reloadData];
    }
}

#pragma mark - UI Setup

- (void)pp_applyNoNavigationBarAnimated:(BOOL)animated {
    if (!self.navigationController) return;
    if (!self.didCaptureNavigationBarHiddenState) {
        self.previousNavigationBarHiddenState = self.navigationController.navigationBarHidden;
        self.didCaptureNavigationBarHiddenState = YES;
    }
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)pp_restoreNavigationBarIfNeededAnimated:(BOOL)animated {
    if (!self.navigationController || !self.didCaptureNavigationBarHiddenState) return;
    [self.navigationController setNavigationBarHidden:self.previousNavigationBarHiddenState animated:animated];
    self.didCaptureNavigationBarHiddenState = NO;
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 92.0;
    [self.tableView registerClass:PPSupportChatCell.class forCellReuseIdentifier:@"ChatCell"];
    [self.tableView registerClass:PPSupportStateCell.class forCellReuseIdentifier:@"StateCell"];

    self.refreshControl = [UIRefreshControl new];
    self.refreshControl.tintColor = PPChatsAccentColor();
    [self.refreshControl addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventValueChanged];
    if (@available(iOS 10.0, *)) {
        self.tableView.refreshControl = self.refreshControl;
    } else {
        [self.tableView addSubview:self.refreshControl];
    }

    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupHeaderUI {
    CGFloat width = MAX(CGRectGetWidth(self.view.bounds), UIScreen.mainScreen.bounds.size.width);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 248.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    [header addSubview:card];

    PPHero *glassBG = [PPHero new];
    glassBG.translatesAutoresizingMaskIntoConstraints = NO;
    glassBG.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    glassBG.cornerGlowOpacityMultiplier = 0.65;
    glassBG.accentColorOverride = [UIColor ppPrimary];
    [card addSubview:glassBG];
    self.heroGlassBG = glassBG;

    UIView *identityPlate = [UIView new];
    identityPlate.translatesAutoresizingMaskIntoConstraints = NO;
    identityPlate.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.16];
    PPChatsApplyContinuousCorners(identityPlate, 20.0);
    identityPlate.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    identityPlate.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.35].CGColor;
    [card addSubview:identityPlate];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.checkered"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [UIColor ppPrimary];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [identityPlate addSubview:iconView];

    UILabel *kickerLabel = [UILabel new];
    kickerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    kickerLabel.font = PPChatsFont([Styling fontBold:12.0], UIFontTextStyleCaption1);
    kickerLabel.adjustsFontForContentSizeCategory = YES;
    kickerLabel.textColor = [UIColor ppPrimary];
    kickerLabel.textAlignment = [Language alignmentForCurrentLanguage];
    kickerLabel.text = PPChatsL(@"SupportChats_HeroKicker");
    [card addSubview:kickerLabel];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = PPChatsFont([Styling fontBold:24.0], UIFontTextStyleTitle2);
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textColor = PPChatsPrimaryTextColor();
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    titleLabel.text = PPChatsL(@"SupportChats_OfficialName");
    titleLabel.numberOfLines = 1;
    [card addSubview:titleLabel];

    self.heroSubtitleLabel = [UILabel new];
    self.heroSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroSubtitleLabel.font = PPChatsFont([Styling fontRegular:14.0], UIFontTextStyleSubheadline);
    self.heroSubtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.heroSubtitleLabel.textColor = PPChatsSecondaryTextColor();
    self.heroSubtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.heroSubtitleLabel.numberOfLines = 2;
    [card addSubview:self.heroSubtitleLabel];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 10.0;
    [card addSubview:stack];

    UILabel *unreadCountLabel = nil;
    UIView *unreadMetric = [self metricViewWithTitle:PPChatsL(@"SupportChats_HeroMetricUnread") valueLabel:&unreadCountLabel];
    _heroUnreadCountLabel = unreadCountLabel;

    UILabel *activeCountLabel = nil;
    UIView *activeMetric = [self metricViewWithTitle:PPChatsL(@"SupportChats_HeroMetricActive") valueLabel:&activeCountLabel];
    _heroActiveCountLabel = activeCountLabel;
    [stack addArrangedSubview:unreadMetric];
    [stack addArrangedSubview:activeMetric];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = PPChatsL(@"SupportChats_SearchPlaceholder");
    self.searchBar.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [card addSubview:self.searchBar];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:12.0],
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],

        [glassBG.topAnchor constraintEqualToAnchor:card.topAnchor],
        [glassBG.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [glassBG.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [glassBG.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [identityPlate.topAnchor constraintEqualToAnchor:card.topAnchor constant:22.0],
        [identityPlate.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [identityPlate.widthAnchor constraintEqualToConstant:52.0],
        [identityPlate.heightAnchor constraintEqualToConstant:52.0],

        [iconView.centerXAnchor constraintEqualToAnchor:identityPlate.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:identityPlate.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:27.0],
        [iconView.heightAnchor constraintEqualToConstant:27.0],

        [kickerLabel.topAnchor constraintEqualToAnchor:identityPlate.topAnchor constant:1.0],
        [kickerLabel.leadingAnchor constraintEqualToAnchor:identityPlate.trailingAnchor constant:14.0],
        [kickerLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],

        [titleLabel.topAnchor constraintEqualToAnchor:kickerLabel.bottomAnchor constant:3.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:kickerLabel.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:kickerLabel.trailingAnchor],

        [self.heroSubtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:5.0],
        [self.heroSubtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.heroSubtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [stack.topAnchor constraintEqualToAnchor:identityPlate.bottomAnchor constant:22.0],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0],
        [stack.heightAnchor constraintEqualToConstant:54.0],

        [self.searchBar.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:14.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [self.searchBar.heightAnchor constraintEqualToConstant:48.0],
        [self.searchBar.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],
    ]];

    self.tableView.tableHeaderView = header;
    [self updateHeroMetrics];
    [self sizeHeaderToFit];
}

- (UIView *)metricViewWithTitle:(NSString *)title valueLabel:(UILabel * __strong *)valueLabel {
    UIView *view = [UIView new];
    view.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.42];
    PPChatsApplyContinuousCorners(view, 17.0);
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.70].CGColor;

    UILabel *value = [UILabel new];
    value.translatesAutoresizingMaskIntoConstraints = NO;
    value.font = [UIFont monospacedDigitSystemFontOfSize:20.0 weight:UIFontWeightBold];
    value.adjustsFontForContentSizeCategory = YES;
    value.textColor = PPChatsPrimaryTextColor();
    value.textAlignment = NSTextAlignmentCenter;
    [view addSubview:value];

    UILabel *caption = [UILabel new];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    caption.font = PPChatsFont([Styling fontRegular:11.0], UIFontTextStyleCaption1);
    caption.adjustsFontForContentSizeCategory = YES;
    caption.textColor = PPChatsSecondaryTextColor();
    caption.textAlignment = NSTextAlignmentCenter;
    caption.text = title;
    [view addSubview:caption];

    [NSLayoutConstraint activateConstraints:@[
        [value.topAnchor constraintEqualToAnchor:view.topAnchor constant:8.0],
        [value.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:8.0],
        [value.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-8.0],
        [caption.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:1.0],
        [caption.leadingAnchor constraintEqualToAnchor:value.leadingAnchor],
        [caption.trailingAnchor constraintEqualToAnchor:value.trailingAnchor],
        [caption.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-7.0],
    ]];
    if (valueLabel) {
        *valueLabel = value;
    }
    return view;
}

- (void)sizeHeaderToFit {
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;
    CGRect frame = header.frame;
    frame.size.width = width;
    header.frame = frame;
    [header setNeedsLayout];
    [header layoutIfNeeded];
    CGFloat height = [header systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    frame.size.height = ceil(MAX(1.0, height));
    header.frame = frame;
    self.tableView.tableHeaderView = header;
}

- (void)prepareEntranceState {
    if (self.didRunEntrance) return;
    self.didPrepareEntrance = YES;
    self.tableView.alpha = 0.0;
    self.tableView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
}

- (void)runEntranceIfNeeded {
    if (self.didRunEntrance) return;
    self.didRunEntrance = YES;
    [self.view layoutIfNeeded];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.tableView.alpha = 1.0;
        self.tableView.transform = CGAffineTransformIdentity;
        return;
    }
    [UIView animateWithDuration:0.48 delay:0.02 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.tableView.alpha = 1.0;
        self.tableView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Backend

- (void)onRefresh {
    [self refreshStaffAndStartListener];
}

- (void)refreshStaffAndStartListener {
    self.isLoading = YES;
    self.stateSymbol = @"ellipsis.message.fill";
    self.stateTitle = PPChatsL(@"SupportChats_Loading");
    self.stateSubtitle = @"";
    [self.tableView reloadData];

    PPStaffDoc *cached = [PPStaffAuth shared].cachedCurrentStaff;
    if (cached) {
        [self applyStaffDoc:cached];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[PPStaffAuth shared] refreshCurrentStaff:^(PPStaffDoc * _Nullable doc, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self applyStaffDoc:doc];
        });
    }];
}

- (void)applyStaffDoc:(PPStaffDoc *)staffDoc {
    NSString *authUID = [FIRAuth auth].currentUser.uid ?: @"";
    self.currentUID = authUID.length > 0 ? authUID : (staffDoc.uid ?: @"");
    self.hasViewPermission = [staffDoc hasAnyPermission:@[kStaffPermSupportView, kStaffPermSupportManage]];
    self.hasManagePermission = [staffDoc hasPermission:kStaffPermSupportManage];
    [self updateHeroMetrics];

    if (!self.hasViewPermission || self.currentUID.length == 0) {
        [self.supportListener remove];
        self.supportListener = nil;
        self.isLoading = NO;
        self.allChats = @[];
        self.filteredChats = @[];
        self.stateSymbol = @"lock.shield.fill";
        self.stateTitle = PPChatsL(@"SupportChats_NoAccess");
        self.stateSubtitle = PPChatsL(@"SupportChats_NoAccess_Subtitle");
        [self.refreshControl endRefreshing];
        [self.tableView reloadData];
        return;
    }

    [self startSupportListener];
}

- (void)startSupportListener {
    [self.supportListener remove];
    self.supportListener = nil;
    self.isLoading = YES;
    self.stateSymbol = @"ellipsis.message.fill";
    self.stateTitle = PPChatsL(@"SupportChats_Loading");
    self.stateSubtitle = @"";
    [self.tableView reloadData];

    FIRQuery *query = [[[[[FIRFirestore firestore] collectionWithPath:@"Chats"]
                         queryWhereField:@"conversationType" in:@[PPChatsSupportConversationType, PPChatsSupportContextType]]
                        queryOrderedByField:@"lastMessageAt" descending:YES]
                       queryLimitedTo:100];
    __weak typeof(self) weakSelf = self;
    self.supportListener = [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoading = NO;
            [self.refreshControl endRefreshing];
            if (error) {
                self.allChats = @[];
                self.filteredChats = @[];
                self.stateSymbol = @"wifi.exclamationmark";
                self.stateTitle = PPChatsL(@"SupportChats_Error");
                self.stateSubtitle = PPChatsL(@"SupportChats_Retry");
                [self updateHeroMetrics];
                [self.tableView reloadData];
                return;
            }

            NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
            for (FIRDocumentSnapshot *document in snapshot.documents) {
                NSMutableDictionary *data = [(document.data ?: @{}) mutableCopy];
                data[@"id"] = document.documentID ?: @"";
                [items addObject:data.copy];
            }
            self.allChats = items.copy;
            [self applySearchAndReload];
        });
    }];
}

- (void)applySearchAndReload {
    NSString *query = PPChatsSafeString(self.searchText);
    if (query.length == 0) {
        self.filteredChats = self.allChats;
    } else {
        NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
        for (NSDictionary *chat in self.allChats) {
            NSString *blob = [self searchableStringForThread:chat];
            if ([blob localizedCaseInsensitiveContainsString:query]) {
                [results addObject:chat];
            }
        }
        self.filteredChats = results.copy;
    }

    if (self.filteredChats.count == 0) {
        if (query.length > 0) {
            self.stateSymbol = @"magnifyingglass";
            self.stateTitle = PPChatsL(@"SupportChats_NoResults");
            self.stateSubtitle = @"";
        } else {
            self.stateSymbol = @"lifepreserver.fill";
            self.stateTitle = PPChatsL(@"SupportChats_Empty");
            self.stateSubtitle = PPChatsL(@"SupportChats_Empty_Subtitle");
        }
    }
    [self updateHeroMetrics];
    [self.tableView reloadData];
}

- (NSString *)searchableStringForThread:(NSDictionary *)thread {
    NSString *name = PPChatsCustomerDisplayName(thread, self.currentUID);
    NSString *message = PPChatsSafeString(thread[@"lastMessage"]);
    NSString *status = PPChatsStatusText(thread[@"supportStatus"]);
    NSString *source = PPChatsSafeString(thread[@"sourcePlatform"]);
    NSString *threadID = PPChatsSafeString(thread[@"id"]);
    return [@[name, message, status, source, threadID] componentsJoinedByString:@" "];
}

- (void)updateHeroMetrics {
    NSInteger unread = 0;
    NSInteger active = 0;
    for (NSDictionary *thread in self.allChats) {
        if (PPChatsThreadIsUnread(thread, self.currentUID)) unread += 1;
        if (PPChatsThreadIsOpen(thread)) active += 1;
    }
    self.heroUnreadCountLabel.text = [NSString stringWithFormat:@"%ld", (long)unread];
    self.heroActiveCountLabel.text = [NSString stringWithFormat:@"%ld", (long)active];
    self.heroSubtitleLabel.text = self.hasManagePermission ? PPChatsL(@"SupportChats_HeroSubtitleManage") : PPChatsL(@"SupportChats_HeroSubtitleView");
}

- (void)markThreadRead:(NSDictionary *)thread {
    NSString *threadID = PPChatsSafeString(thread[@"id"]);
    if (threadID.length == 0 || self.currentUID.length == 0) return;
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:@"supportChatCommand"];
    callable.timeoutInterval = 30.0;
    [callable callWithObject:@{
        @"action": @"mark_read",
        @"threadId": threadID,
        @"expectedLastMessageId": PPChatsSafeString(thread[@"lastMessageId"] ?: thread[@"lastProjectedMessageId"])
    } completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {}];
}

#pragma mark - Search Bar Delegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText ?: @"";
    [self applySearchAndReload];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UITableView Delegate & DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredChats.count > 0 ? self.filteredChats.count : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.filteredChats.count == 0) {
        PPSupportStateCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StateCell" forIndexPath:indexPath];
        [cell configureWithSymbol:self.stateSymbol ?: @"lifepreserver.fill" title:self.stateTitle ?: @"" subtitle:self.stateSubtitle ?: @""];
        return cell;
    }

    NSDictionary *chat = self.filteredChats[indexPath.row];
    NSString *name = PPChatsCustomerDisplayName(chat, self.currentUID);
    NSString *message = PPChatsSafeString(chat[@"lastMessage"]);
    NSString *time = PPChatsRelativeDateString(chat[@"lastMessageAt"]);
    if (time.length == 0) time = PPChatsRelativeDateString(chat[@"timestamp"]);
    NSString *status = PPChatsStatusText(chat[@"supportStatus"]);
    UIColor *statusColor = PPChatsStatusColor(chat[@"supportStatus"]);
    BOOL unread = PPChatsThreadIsUnread(chat, self.currentUID);

    PPSupportChatCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ChatCell" forIndexPath:indexPath];
    [cell configureWithName:name message:message time:time status:status statusColor:statusColor unread:unread];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.filteredChats.count == 0 || indexPath.row >= self.filteredChats.count) return;
    NSDictionary *thread = self.filteredChats[indexPath.row];
    [self markThreadRead:thread];
    PPSupportThreadViewController *detail = [[PPSupportThreadViewController alloc] initWithThread:thread currentUID:self.currentUID canManageSupport:self.hasManagePermission];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
