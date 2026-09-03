//
//  NotificationDetailViewController.m
//  PurePetsAdmin
//
//  Category-defining administrative notification inspector & action hub.
//

#import "NotificationDetailViewController.h"
#import "NotificationManager.h"
#import "Styling.h"
#import "Language.h"
#import "PPDesignTokens.h"
#import "UIViewController+PPNavBar.h"
#import "PPFunc.h"
#import "PPHUD.h"
#import "PPToast.h"
#import "SceneDelegate.h"
#import "PurePetsAdmin-Swift.h"

@interface NotificationDetailViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NotificationModel *model;
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, strong) UIView *dossierNavBarView;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *navEyebrowLabel;
@property (nonatomic, strong) UILabel *navTitleLabel;
@property (nonatomic, strong) UIButton *readStatusNavButton;
@property (nonatomic, strong) UIButton *shareNavButton;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@end

@implementation NotificationDetailViewController

- (instancetype)initWithModel:(NotificationModel *)model userID:(NSString *)uid onDismiss:(nullable void (^)(void))onDismiss {
    self = [super init];
    if (self) {
        _model = model;
        _uid = [uid copy];
        _onDismiss = [onDismiss copy];
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (instancetype)initWithModel:(NotificationModel *)model userID:(NSString *)uid {
    return [self initWithModel:model userID:uid onDismiss:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self setupNavigation];
    [self setupScrollView];
    [self buildHeroCard];
    [self buildBodyCard];
    [self buildActionCardIfNeeded];
    [self buildMetadataCard];
    
    // Mark as read immediately on open
    if (!self.model.isRead) {
        self.model.isRead = YES;
        [[NotificationManager shared] markRead:self.model forUser:self.uid completion:nil];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    self.navigationController.interactivePopGestureRecognizer.delegate = self;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return (self.navigationController.viewControllers.count > 1);
}

- (void)setupNavigation {
    _dossierNavBarView = [[UIView alloc] init];
    _dossierNavBarView.translatesAutoresizingMaskIntoConstraints = NO;
    _dossierNavBarView.backgroundColor = [UIColor ppElevatedSurface];
    _dossierNavBarView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:_dossierNavBarView];

    UIView *hairline = [[UIView alloc] init];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = [UIColor ppBorder];
    [_dossierNavBarView addSubview:hairline];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = UIColor.clearColor;
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [_dossierNavBarView addSubview:container];

    // 1. Back Squircle Button
    _backButton = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(handleBackAction)];
    [container addSubview:_backButton];

    // 2. Title Stack
    UIStackView *titleStack = [[UIStackView alloc] init];
    titleStack.translatesAutoresizingMaskIntoConstraints = NO;
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.alignment = UIStackViewAlignmentCenter;
    titleStack.spacing = 1;
    titleStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [container addSubview:titleStack];

    _navEyebrowLabel = [[UILabel alloc] init];
    _navEyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navEyebrowLabel.text = [Language isRTL] ? @"مركز الإشعارات" : @"Notification Center";
    _navEyebrowLabel.font = [Styling fontBold:10.5];
    _navEyebrowLabel.textColor = [UIColor ppTextTertiary];
    _navEyebrowLabel.textAlignment = NSTextAlignmentCenter;
    [titleStack addArrangedSubview:_navEyebrowLabel];

    _navTitleLabel = [[UILabel alloc] init];
    _navTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _navTitleLabel.text = [Language isRTL] ? @"تفاصيل التنبيه" : @"Notification Details";
    _navTitleLabel.font = [Styling fontBold:16.5];
    _navTitleLabel.textColor = [UIColor ppTextPrimary];
    _navTitleLabel.textAlignment = NSTextAlignmentCenter;
    [titleStack addArrangedSubview:_navTitleLabel];

    // 3. Trailing Action Buttons Stack
    UIStackView *actionsStack = [[UIStackView alloc] init];
    actionsStack.translatesAutoresizingMaskIntoConstraints = NO;
    actionsStack.axis = UILayoutConstraintAxisHorizontal;
    actionsStack.alignment = UIStackViewAlignmentCenter;
    actionsStack.spacing = 8;
    actionsStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [container addSubview:actionsStack];

    _readStatusNavButton = [self makeNavCircleButtonWithIcon:(self.model.isRead ? @"envelope.fill" : @"envelope.open.fill")
                                                       color:[UIColor ppPrimary]
                                                      action:@selector(toggleReadStatus)];
    _readStatusNavButton.accessibilityLabel = [Language isRTL] ? @"تبديل حالة القراءة" : @"Toggle read status";
    [actionsStack addArrangedSubview:_readStatusNavButton];

    _shareNavButton = [self makeNavCircleButtonWithIcon:@"square.and.arrow.up"
                                                  color:[UIColor ppPrimary]
                                                 action:@selector(shareNotification)];
    _shareNavButton.accessibilityLabel = [Language isRTL] ? @"مشاركة التنبيه" : @"Share notification";
    [actionsStack addArrangedSubview:_shareNavButton];

    [NSLayoutConstraint activateConstraints:@[
        [_dossierNavBarView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_dossierNavBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_dossierNavBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_dossierNavBarView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:56],

        [hairline.leadingAnchor constraintEqualToAnchor:_dossierNavBarView.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:_dossierNavBarView.trailingAnchor],
        [hairline.bottomAnchor constraintEqualToAnchor:_dossierNavBarView.bottomAnchor],
        [hairline.heightAnchor constraintEqualToConstant:0.5],

        [container.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [container.bottomAnchor constraintEqualToAnchor:_dossierNavBarView.bottomAnchor constant:-4],
        [container.leadingAnchor constraintEqualToAnchor:_dossierNavBarView.leadingAnchor constant:14],
        [container.trailingAnchor constraintEqualToAnchor:_dossierNavBarView.trailingAnchor constant:-14],

        [_backButton.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_backButton.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [_backButton.widthAnchor constraintEqualToConstant:44],
        [_backButton.heightAnchor constraintEqualToConstant:44],

        [titleStack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [titleStack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [titleStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_backButton.trailingAnchor constant:8],
        [titleStack.trailingAnchor constraintLessThanOrEqualToAnchor:actionsStack.leadingAnchor constant:-8],

        [actionsStack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [actionsStack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor]
    ]];
}

- (UIButton *)makeNavCircleButtonWithIcon:(NSString *)iconName color:(UIColor *)color action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *img = [UIImage systemImageNamed:iconName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]];
    [btn setImage:img forState:UIControlStateNormal];
    btn.tintColor = color;
    btn.backgroundColor = [color colorWithAlphaComponent:0.08];
    btn.layer.borderWidth = 0.5;
    btn.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(btn, 18.0);
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor constraintEqualToConstant:36],
        [btn.heightAnchor constraintEqualToConstant:36]
    ]];
    return btn;
}

- (void)handleBackAction {
    [PPFunc pp_playTapEffect];
    if (self.onDismiss) {
        self.onDismiss();
        return;
    }
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    if ([self pp_dismissWorkflowRouteIfPossible]) {
        return;
    }
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    [PPAdminNavigationFallback popOrDismissFrom:self];
}

- (void)updateReadButtonIcon {
    NSString *iconName = self.model.isRead ? @"envelope.fill" : @"envelope.open.fill";
    UIImage *img = [UIImage systemImageNamed:iconName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]];
    [_readStatusNavButton setImage:img forState:UIControlStateNormal];
}

- (void)toggleReadStatus {
    [PPFunc pp_playTapEffect];
    self.model.isRead = !self.model.isRead;
    [self updateReadButtonIcon];
    [[NotificationManager shared] markRead:self.model forUser:self.uid completion:nil];
    
    NSString *msg = self.model.isRead
        ? ([Language isRTL] ? @"تم تحديد التنبيه كمقروء" : @"Marked as read")
        : ([Language isRTL] ? @"تم تحديد التنبيه كغير مقروء" : @"Marked as unread");
    [PPHUD showSuccess:msg];
}

- (void)shareNotification {
    [PPFunc pp_playTapEffect];
    NSString *title = self.model.title ?: @"";
    NSString *body = self.model.body ?: @"";
    NSString *text = [NSString stringWithFormat:@"%@\n\n%@", title, body];
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    [self presentViewController:act animated:YES completion:nil];
}

- (void)setupScrollView {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.contentInset = UIEdgeInsetsMake(16, 0, 40, 0);
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scrollView];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 16;
    _contentStack.alignment = UIStackViewAlignmentFill;
    [_scrollView addSubview:_contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.dossierNavBarView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_contentStack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor constant:16],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor constant:-16],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
        [_contentStack.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor constant:-32]
    ]];
}

- (void)buildHeroCard {
    UIView *card = [self makeSectionCard];
    
    NSDictionary *meta = [self.model.meta isKindOfClass:NSDictionary.class] ? self.model.meta : @{};
    NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];
    
    UIColor *accent = [UIColor ppPrimary];
    NSString *symbol = @"bell.badge.fill";
    NSString *categoryText = [Language isRTL] ? @"إشعار عام" : @"Notification";
    
    if (self.model.type == PPNotificationTypeOrder || orderID.length > 0) {
        accent = [UIColor ppQuickActionShopping] ?: [UIColor systemOrangeColor];
        symbol = @"bag.fill";
        categoryText = [Language isRTL] ? @"طلب متجر" : @"Store Order";
    } else if (self.model.type == PPNotificationTypeWarning) {
        accent = [UIColor ppWarning];
        symbol = @"exclamationmark.triangle.fill";
        categoryText = [Language isRTL] ? @"تنبيه نظام" : @"System Alert";
    } else if ([self.model.title containsString:@"support"] || [self.model.title containsString:@"دعم"]) {
        accent = [UIColor ppQuickActionServices] ?: [UIColor systemGreenColor];
        symbol = @"bubble.left.and.bubble.right.fill";
        categoryText = [Language isRTL] ? @"رسالة دعم" : @"Support Message";
    }
    
    UIView *iconSurface = [[UIView alloc] init];
    iconSurface.translatesAutoresizingMaskIntoConstraints = NO;
    iconSurface.backgroundColor = [accent colorWithAlphaComponent:0.12];
    PPApplyContinuousCorners(iconSurface, 18.0);
    [card addSubview:iconSurface];
    
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = accent;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconSurface addSubview:iconView];
    
    UIView *categoryPill = [[UIView alloc] init];
    categoryPill.translatesAutoresizingMaskIntoConstraints = NO;
    categoryPill.backgroundColor = [accent colorWithAlphaComponent:0.10];
    PPApplyContinuousCorners(categoryPill, PPCornerPill);
    [card addSubview:categoryPill];
    
    UILabel *catLabel = [[UILabel alloc] init];
    catLabel.translatesAutoresizingMaskIntoConstraints = NO;
    catLabel.font = [Styling fontBold:12.0];
    catLabel.textColor = accent;
    catLabel.text = categoryText;
    [categoryPill addSubview:catLabel];
    
    UILabel *timeLabel = [[UILabel alloc] init];
    timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    timeLabel.font = [Styling fontMedium:13.0];
    timeLabel.textColor = [UIColor ppTextSecondary];
    timeLabel.textAlignment = Language.alignmentForCurrentLanguage;
    
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateStyle = NSDateFormatterMediumStyle;
    fmt.timeStyle = NSDateFormatterShortStyle;
    timeLabel.text = [fmt stringFromDate:self.model.createdAt ?: [NSDate date]];
    [card addSubview:timeLabel];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:22.0];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.numberOfLines = 0;
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    
    NSString *titleKey = meta[@"titleLocalizationKey"];
    titleLabel.text = (titleKey.length > 0) ? kLang(titleKey) : self.model.title;
    [card addSubview:titleLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [iconSurface.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [iconSurface.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [iconSurface.widthAnchor constraintEqualToConstant:56],
        [iconSurface.heightAnchor constraintEqualToConstant:56],
        
        [iconView.centerXAnchor constraintEqualToAnchor:iconSurface.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconSurface.centerYAnchor],
        [iconView.widthAnchor constraintEqualToConstant:30],
        [iconView.heightAnchor constraintEqualToConstant:30],
        
        [categoryPill.centerYAnchor constraintEqualToAnchor:iconSurface.centerYAnchor],
        [categoryPill.leadingAnchor constraintEqualToAnchor:iconSurface.trailingAnchor constant:14],
        [categoryPill.heightAnchor constraintEqualToConstant:26],
        
        [catLabel.leadingAnchor constraintEqualToAnchor:categoryPill.leadingAnchor constant:10],
        [catLabel.trailingAnchor constraintEqualToAnchor:categoryPill.trailingAnchor constant:-10],
        [catLabel.centerYAnchor constraintEqualToAnchor:categoryPill.centerYAnchor],
        
        [timeLabel.centerYAnchor constraintEqualToAnchor:categoryPill.centerYAnchor],
        [timeLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [timeLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:categoryPill.trailingAnchor constant:8],
        
        [titleLabel.topAnchor constraintEqualToAnchor:iconSurface.bottomAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [titleLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]
    ]];
    
    [_contentStack addArrangedSubview:card];
}

- (void)buildBodyCard {
    UIView *card = [self makeSectionCard];
    
    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.text = [Language isRTL] ? @"نص الإشعار" : @"Notification Message";
    header.font = [Styling fontBold:15.0];
    header.textColor = [UIColor ppTextSecondary];
    header.textAlignment = Language.alignmentForCurrentLanguage;
    [card addSubview:header];
    
    NSDictionary *meta = [self.model.meta isKindOfClass:NSDictionary.class] ? self.model.meta : @{};
    NSString *bodyKey = meta[@"bodyLocalizationKey"];
    NSString *displayBody = @"";
    if (bodyKey.length > 0) {
        NSString *format = kLang(bodyKey);
        NSString *ref = meta[@"orderReference"] ?: @"";
        displayBody = (ref.length > 0) ? [NSString stringWithFormat:format, ref] : format;
    } else {
        displayBody = self.model.body ?: @"";
    }
    
    UILabel *bodyLabel = [[UILabel alloc] init];
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bodyLabel.font = [Styling fontRegular:16.0];
    bodyLabel.textColor = [UIColor ppTextPrimary];
    bodyLabel.numberOfLines = 0;
    bodyLabel.textAlignment = Language.alignmentForCurrentLanguage;
    bodyLabel.text = displayBody;
    [card addSubview:bodyLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [header.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        
        [bodyLabel.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:10],
        [bodyLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [bodyLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [bodyLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]
    ]];
    
    [_contentStack addArrangedSubview:card];
}

- (void)buildActionCardIfNeeded {
    NSDictionary *meta = [self.model.meta isKindOfClass:NSDictionary.class] ? self.model.meta : @{};
    NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];
    
    if (orderID.length == 0) return;
    
    UIView *card = [self makeSectionCard];
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.backgroundColor = [UIColor ppPrimary];
    NSString *btnTitle = [Language isRTL]
        ? [NSString stringWithFormat:@"🛍️ الانتقال إلى تفاصيل الطلب #%@ ➔", orderID]
        : [NSString stringWithFormat:@"🛍️ View Full Order Details #%@ ➔", orderID];
    [btn setTitle:btnTitle forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [Styling fontBold:16.0];
    PPApplyContinuousCorners(btn, PPCornerMedium);
    PPApplyButtonShadow(btn);
    [btn addTarget:self action:@selector(openRelatedOrder) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:btn];
    
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [btn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [btn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [btn.heightAnchor constraintEqualToConstant:50],
        [btn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14]
    ]];
    
    [_contentStack addArrangedSubview:card];
}

- (void)openRelatedOrder {
    [PPFunc pp_playTapEffect];
    NSDictionary *meta = [self.model.meta isKindOfClass:NSDictionary.class] ? self.model.meta : @{};
    NSString *orderID = meta[@"orderId"] ?: meta[@"orderID"];
    if (orderID.length > 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:PPAdminRouteToPaymentOrderNotification
                                                            object:nil
                                                          userInfo:@{ PPAdminRouteToPaymentOrderIDUserInfoKey: orderID }];
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)buildMetadataCard {
    UIView *card = [self makeSectionCard];
    
    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.text = [Language isRTL] ? @"البيانات الإدارية (Metadata)" : @"Administrative Metadata";
    header.font = [Styling fontBold:15.0];
    header.textColor = [UIColor ppTextSecondary];
    header.textAlignment = Language.alignmentForCurrentLanguage;
    [card addSubview:header];
    
    UIStackView *rowsStack = [[UIStackView alloc] init];
    rowsStack.translatesAutoresizingMaskIntoConstraints = NO;
    rowsStack.axis = UILayoutConstraintAxisVertical;
    rowsStack.spacing = 10;
    [card addSubview:rowsStack];
    
    [rowsStack addArrangedSubview:[self makeMetaRow:[Language isRTL] ? @"معرف الإشعار" : @"Notification ID" value:self.model.nid ?: @"-"]];
    if (self.model.targetUserID.length > 0) {
        [rowsStack addArrangedSubview:[self makeMetaRow:[Language isRTL] ? @"المستخدم المستهدف" : @"Target User" value:self.model.targetUserID]];
    }
    
    NSDictionary *meta = [self.model.meta isKindOfClass:NSDictionary.class] ? self.model.meta : @{};
    if (meta[@"route"]) {
        [rowsStack addArrangedSubview:[self makeMetaRow:[Language isRTL] ? @"المسار الداخلي" : @"Route" value:[NSString stringWithFormat:@"%@", meta[@"route"]]]];
    }
    if (self.model.sourcePath.length > 0) {
        [rowsStack addArrangedSubview:[self makeMetaRow:[Language isRTL] ? @"المصدر" : @"Source Path" value:self.model.sourcePath]];
    }
    
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [header.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        
        [rowsStack.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],
        [rowsStack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [rowsStack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [rowsStack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18]
    ]];
    
    [_contentStack addArrangedSubview:card];
}

- (UIView *)makeMetaRow:(NSString *)key value:(NSString *)val {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor ppSurface];
    PPApplyContinuousCorners(row, PPCornerSmall);
    
    UILabel *keyL = [[UILabel alloc] init];
    keyL.translatesAutoresizingMaskIntoConstraints = NO;
    keyL.font = [Styling fontMedium:13.0];
    keyL.textColor = [UIColor ppTextSecondary];
    keyL.text = key;
    keyL.textAlignment = Language.alignmentForCurrentLanguage;
    [row addSubview:keyL];
    
    UILabel *valL = [[UILabel alloc] init];
    valL.translatesAutoresizingMaskIntoConstraints = NO;
    valL.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular];
    valL.textColor = [UIColor ppTextPrimary];
    valL.text = val;
    valL.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;
    [row addSubview:valL];
    
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:36],
        [keyL.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:10],
        [keyL.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        
        [valL.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-10],
        [valL.leadingAnchor constraintGreaterThanOrEqualToAnchor:keyL.trailingAnchor constant:12],
        [valL.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];
    return row;
}

- (UIView *)makeSectionCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor ppSurfaceElevated];
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    PPApplyContinuousCorners(card, PPCornerCard);
    PPApplyCardShadow(card);
    return card;
}

@end
