//
//  NotificationDetailViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationDetailViewController.m
#import "NotificationDetailViewController.h"

static NSString *PPAdminNotificationDetailTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSDictionary *PPAdminNotificationDetailMeta(NotificationModel *model)
{
    return [model.meta isKindOfClass:NSDictionary.class] ? model.meta : @{};
}

static NSString *PPAdminNotificationDetailTitle(NotificationModel *model)
{
    NSDictionary *meta = PPAdminNotificationDetailMeta(model);
    NSString *titleKey = PPAdminNotificationDetailTrimmedString(meta[@"titleLocalizationKey"]);
    if (titleKey.length > 0) return kLang(titleKey);
    return PPAdminNotificationDetailTrimmedString(model.title);
}

static NSString *PPAdminNotificationDetailBody(NotificationModel *model)
{
    NSDictionary *meta = PPAdminNotificationDetailMeta(model);
    NSString *bodyKey = PPAdminNotificationDetailTrimmedString(meta[@"bodyLocalizationKey"]);
    NSString *orderReference = PPAdminNotificationDetailTrimmedString(meta[@"orderReference"]);
    if (bodyKey.length > 0) {
        NSString *format = kLang(bodyKey);
        return orderReference.length > 0 ? [NSString stringWithFormat:format, orderReference] : format;
    }
    return PPAdminNotificationDetailTrimmedString(model.body);
}

@implementation NotificationDetailViewController {
    NotificationModel *_model;
    NSString *_uid;
    UILabel *_titleL;
    UILabel *_bodyL;
    UILabel *_timeL;
}

- (instancetype)initWithModel:(NotificationModel *)model userID:(NSString *)uid {
    if (self = [super init]) { _model = model; _uid = [uid copy]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = kLang(@"Notification");

    _titleL = [UILabel new]; _titleL.translatesAutoresizingMaskIntoConstraints = NO;
    _titleL.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    _titleL.numberOfLines = 0;

    _bodyL = [UILabel new]; _bodyL.translatesAutoresizingMaskIntoConstraints = NO;
    _bodyL.font = [UIFont systemFontOfSize:16];
    _bodyL.numberOfLines = 0;

    _timeL = [UILabel new]; _timeL.translatesAutoresizingMaskIntoConstraints = NO;
    _timeL.font = [UIFont systemFontOfSize:12];
    _timeL.textColor = UIColor.secondaryLabelColor;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleL, _bodyL, _timeL]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 8;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    ]];

    _titleL.text = PPAdminNotificationDetailTitle(_model);
    _bodyL.text  = PPAdminNotificationDetailBody(_model);
    NSDateFormatter *fmt = [NSDateFormatter new]; fmt.dateStyle = NSDateFormatterMediumStyle; fmt.timeStyle = NSDateFormatterShortStyle;
    _timeL.text = [fmt stringFromDate:_model.createdAt ?: [NSDate date]];

    if (!_model.isRead) {
        _model.isRead = YES;
       // [[NotificationManager sharedManager] markRead:_model forUser:_uid completion:nil];
    }
}
@end
