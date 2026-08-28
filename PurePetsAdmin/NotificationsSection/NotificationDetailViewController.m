//
//  NotificationDetailViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationDetailViewController.m
#import "NotificationDetailViewController.h"
#import "Styling.h"
#import "Language.h"

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
    UILabel *_typeL;
    UIView *_cardView;
}

- (instancetype)initWithModel:(NotificationModel *)model userID:(NSString *)uid {
    if (self = [super init]) { _model = model; _uid = [uid copy]; }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
}

- (void)didTapBack {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *navRow = [[UIView alloc] init];
    navRow.translatesAutoresizingMaskIntoConstraints = NO;
    navRow.backgroundColor = UIColor.clearColor;
    navRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:navRow];

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    backBtn.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *chevronName = [Language isRTL] ? @"chevron.right" : @"chevron.left";
    UIImage *chevron = [UIImage systemImageNamed:chevronName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]];
    NSString *backText = [Language isRTL] ? @" رجوع" : @" Back";
    [backBtn setImage:chevron forState:UIControlStateNormal];
    [backBtn setTitle:backText forState:UIControlStateNormal];
    backBtn.tintColor = [UIColor ppPrimary];
    backBtn.titleLabel.font = [Styling fontBold:16];
    [backBtn addTarget:self action:@selector(didTapBack) forControlEvents:UIControlEventTouchUpInside];
    [navRow addSubview:backBtn];

    UILabel *eyebrow = [[UILabel alloc] init];
    eyebrow.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrow.font = [Styling fontBold:12];
    eyebrow.textColor = [UIColor ppTextSecondary];
    eyebrow.text = kLang(@"NotificationDetail_Eyebrow");
    eyebrow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [navRow addSubview:eyebrow];

    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scrollView];

    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:contentView];

    _cardView = [[UIView alloc] init];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = PPSurfaceColor();
    _cardView.layer.cornerRadius = PPCornerHero;
    _cardView.layer.cornerCurve = kCACornerCurveContinuous;
    _cardView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _cardView.layer.borderColor = PPHairlineColor().CGColor;
    PPApplyElevatedShadow(_cardView);
    _cardView.layer.shadowOpacity = 0.07;
    [contentView addSubview:_cardView];

    UIView *glyphSurface = [[UIView alloc] init];
    glyphSurface.translatesAutoresizingMaskIntoConstraints = NO;
    glyphSurface.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.12];
    glyphSurface.layer.cornerRadius = PPCornerMedium;
    glyphSurface.layer.cornerCurve = kCACornerCurveContinuous;
    [_cardView addSubview:glyphSurface];

    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bell.badge.fill"]];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    glyph.tintColor = AppPrimaryClr;
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    [glyphSurface addSubview:glyph];

    _typeL = [UILabel new]; _typeL.translatesAutoresizingMaskIntoConstraints = NO;
    _typeL.font = [Styling fontMedium:13.0];
    _typeL.textColor = PPTextSecondaryColor();
    _typeL.textAlignment = [Language alignmentForCurrentLanguage];
    _typeL.adjustsFontForContentSizeCategory = YES;
    [_cardView addSubview:_typeL];

    _titleL = [UILabel new]; _titleL.translatesAutoresizingMaskIntoConstraints = NO;
    _titleL.font = [Styling fontBold:28.0] ?: [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    _titleL.numberOfLines = 0;
    _titleL.textColor = PPTextPrimaryColor();
    _titleL.textAlignment = [Language alignmentForCurrentLanguage];
    _titleL.adjustsFontForContentSizeCategory = YES;
    [_cardView addSubview:_titleL];

    _bodyL = [UILabel new]; _bodyL.translatesAutoresizingMaskIntoConstraints = NO;
    _bodyL.font = [Styling fontRegular:19.0] ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _bodyL.numberOfLines = 0;
    _bodyL.textColor = PPTextPrimaryColor();
    _bodyL.textAlignment = [Language alignmentForCurrentLanguage];
    _bodyL.adjustsFontForContentSizeCategory = YES;
    [_cardView addSubview:_bodyL];

    _timeL = [UILabel new]; _timeL.translatesAutoresizingMaskIntoConstraints = NO;
    _timeL.font = [Styling fontMedium:13.0] ?: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _timeL.textColor = PPTextTertiaryColor();
    _timeL.textAlignment = [Language alignmentForCurrentLanguage];
    _timeL.adjustsFontForContentSizeCategory = YES;
    [_cardView addSubview:_timeL];

    [NSLayoutConstraint activateConstraints:@[
        [navRow.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [navRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [navRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        
        [backBtn.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor constant:16],
        [backBtn.topAnchor constraintEqualToAnchor:navRow.topAnchor constant:10],
        [backBtn.bottomAnchor constraintEqualToAnchor:navRow.bottomAnchor constant:-10],
        [backBtn.heightAnchor constraintGreaterThanOrEqualToConstant:44],

        [eyebrow.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor constant:16],
        [eyebrow.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:4],
        [eyebrow.trailingAnchor constraintEqualToAnchor:navRow.trailingAnchor constant:-16],
        [eyebrow.bottomAnchor constraintEqualToAnchor:navRow.bottomAnchor constant:-10],

        [scrollView.topAnchor constraintEqualToAnchor:navRow.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],

        [_cardView.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:PPSpaceXL],
        [_cardView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:PPSpaceLG],
        [_cardView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-PPSpaceLG],
        [_cardView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-PPSpaceXL],

        [glyphSurface.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:PPSpaceXL],
        [glyphSurface.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:PPSpaceXL],
        [glyphSurface.widthAnchor constraintEqualToConstant:64.0],
        [glyphSurface.heightAnchor constraintEqualToConstant:64.0],

        [glyph.centerXAnchor constraintEqualToAnchor:glyphSurface.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:glyphSurface.centerYAnchor],
        [glyph.widthAnchor constraintEqualToConstant:30.0],
        [glyph.heightAnchor constraintEqualToConstant:30.0],

        [_typeL.leadingAnchor constraintEqualToAnchor:glyphSurface.trailingAnchor constant:PPSpaceMD],
        [_typeL.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceXL],
        [_typeL.centerYAnchor constraintEqualToAnchor:glyphSurface.centerYAnchor],

        [_titleL.topAnchor constraintEqualToAnchor:glyphSurface.bottomAnchor constant:PPSpaceXL],
        [_titleL.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:PPSpaceXL],
        [_titleL.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-PPSpaceXL],

        [_bodyL.topAnchor constraintEqualToAnchor:_titleL.bottomAnchor constant:PPSpaceLG],
        [_bodyL.leadingAnchor constraintEqualToAnchor:_titleL.leadingAnchor],
        [_bodyL.trailingAnchor constraintEqualToAnchor:_titleL.trailingAnchor],

        [_timeL.topAnchor constraintEqualToAnchor:_bodyL.bottomAnchor constant:PPSpaceXL],
        [_timeL.leadingAnchor constraintEqualToAnchor:_titleL.leadingAnchor],
        [_timeL.trailingAnchor constraintEqualToAnchor:_titleL.trailingAnchor],
        [_timeL.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-PPSpaceXL],
    ]];

    _titleL.text = PPAdminNotificationDetailTitle(_model);
    _bodyL.text  = PPAdminNotificationDetailBody(_model);
    _typeL.text = kLang(@"Notification") ?: @"Notification";
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale currentLocale];
    fmt.dateStyle = NSDateFormatterMediumStyle; fmt.timeStyle = NSDateFormatterShortStyle;
    _timeL.text = [fmt stringFromDate:_model.createdAt ?: [NSDate date]];

    _cardView.isAccessibilityElement = YES;
    _cardView.accessibilityTraits = UIAccessibilityTraitStaticText;
    _cardView.accessibilityLabel = [@[_typeL.text ?: @"", _titleL.text ?: @"", _bodyL.text ?: @"", _timeL.text ?: @""] componentsJoinedByString:@", "];

    if (!_model.isRead) {
        _model.isRead = YES;
       // [[NotificationManager sharedManager] markRead:_model forUser:_uid completion:nil];
    }
}
@end
