#import "AlertHelper.h"

#ifndef PrimaryTextClr
#define PrimaryTextClr (AppPrimaryTextClr ?: UIColor.labelColor)
#endif

#ifndef SeconderyTextClr
#define SeconderyTextClr (AppSecondaryTextClr ?: UIColor.secondaryLabelColor)
#endif

static UIWindow *ppAlertOverlayWindow = nil;
static UIViewController *ppAlertRootViewController = nil;

static NSString *PPAlertSanitizedText(NSString *text, NSString *fallbackKey) {
    if (text.length == 0) return text ?: @"";
    return text;
}

static NSString *PPAlertTrimmedText(NSString *value) {
    return [value isKindOfClass:NSString.class]
        ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
}

typedef NS_ENUM(NSInteger, PPAlertActionStyle) {
    PPAlertActionStylePrimary = 0,
    PPAlertActionStyleSecondary,
    PPAlertActionStyleDestructive,
    PPAlertActionStyleCancel
};

@interface PPAlertActionItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) PPAlertActionStyle style;
@property (nonatomic, copy, nullable) AlertCompletionBlock completion;
@property (nonatomic, copy, nullable) PPAlertSimpleActionBlock simpleCompletion;
+ (instancetype)itemWithTitle:(NSString *)title
                        style:(PPAlertActionStyle)style
                   completion:(AlertCompletionBlock _Nullable)completion
             simpleCompletion:(PPAlertSimpleActionBlock _Nullable)simpleCompletion;
@end

@implementation PPAlertActionItem

+ (instancetype)itemWithTitle:(NSString *)title
                        style:(PPAlertActionStyle)style
                   completion:(AlertCompletionBlock _Nullable)completion
             simpleCompletion:(PPAlertSimpleActionBlock _Nullable)simpleCompletion {
    PPAlertActionItem *item = [[self alloc] init];
    item.title = title ?: @"";
    item.style = style;
    item.completion = completion;
    item.simpleCompletion = simpleCompletion;
    return item;
}

@end

@interface PPAlertAppearance : NSObject
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, copy) NSString *iconSystemName;
@property (nonatomic, strong) UIColor *badgeBackgroundColor;
@property (nonatomic, strong) UIColor *badgeForegroundColor;
+ (instancetype)appearanceForType:(PPAlertType)type;
@end

@implementation PPAlertAppearance

+ (instancetype)appearanceForType:(PPAlertType)type {
    PPAlertAppearance *appearance = [[self alloc] init];
    switch (type) {
        case PPAlertTypeSuccess:
            appearance.accentColor = UIColor.systemGreenColor;
            appearance.iconSystemName = @"checkmark.seal.fill";
            break;
        case PPAlertTypeError:
            appearance.accentColor = UIColor.systemRedColor;
            appearance.iconSystemName = @"xmark.seal.fill";
            break;
        case PPAlertTypeWarning:
            appearance.accentColor = UIColor.systemOrangeColor;
            appearance.iconSystemName = @"exclamationmark.triangle.fill";
            break;
        case PPAlertTypeInfo:
            appearance.accentColor = AppPrimaryClr ?: UIColor.systemBlueColor;
            appearance.iconSystemName = @"info.circle.fill";
            break;
        case PPAlertTypeConfirmation:
            appearance.accentColor = AppPrimaryClr ?: UIColor.systemBlueColor;
            appearance.iconSystemName = @"questionmark.circle.fill";
            break;
        case PPAlertTypeTextInput:
            appearance.accentColor = AppPrimaryClr ?: UIColor.systemBlueColor;
            appearance.iconSystemName = @"square.and.pencil.circle.fill";
            break;
    }
    appearance.badgeBackgroundColor = [appearance.accentColor colorWithAlphaComponent:0.13];
    appearance.badgeForegroundColor = appearance.accentColor;
    return appearance;
}

@end

@interface PPAlert ()
@property (nonatomic, assign) PPAlertType type;
@property (nonatomic, copy) NSString *alertTitle;
@property (nonatomic, copy) NSString *alertSubtitle;
@property (nonatomic, strong) UIImage *iconImage;
@property (nonatomic, copy) NSArray<PPAlertActionItem *> *actionItems;
@property (nonatomic, copy, nullable) NSString *textPlaceholder;
@property (nonatomic, copy, nullable) NSString *initialText;
@property (nonatomic, assign) BOOL secureEntry;
@property (nonatomic, assign) UIKeyboardType keyboardType;
@property (nonatomic, assign) BOOL shouldDismissOnBackgroundTap;
@property (nonatomic, strong) UIVisualEffectView *backdropView;
@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *heroGlowView;
@property (nonatomic, strong) UIView *badgeView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *inputContainerView;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, strong) UILabel *footnoteLabel;
@property (nonatomic, strong) UIStackView *buttonStackView;
@property (nonatomic, strong) NSLayoutConstraint *cardCenterYConstraint;
@property (nonatomic, assign) BOOL isPresentingAlert;
@property (nonatomic, strong) PPAlertAppearance *appearance;
@property (nonatomic, assign) BOOL didPreparePresentation;
@property (nonatomic, assign) BOOL didRunPresentation;
@end

@implementation PPAlert

- (instancetype)initWithType:(PPAlertType)type
                       title:(NSString *)title
                    subtitle:(NSString *)subtitle
                        icon:(UIImage *)icon
                confirmTitle:(NSString * _Nullable)confirmTitle
                 cancelTitle:(NSString * _Nullable)cancelTitle
               confirmAction:(AlertCompletionBlock _Nullable)confirmAction
                cancelAction:(void(^ _Nullable)(void))cancelAction {
    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];
    NSString *safeConfirmTitle = confirmTitle.length ? confirmTitle : kLang(@"OK");
    if (cancelTitle.length > 0) {
        [actions addObject:[PPAlertActionItem itemWithTitle:cancelTitle
                                                      style:PPAlertActionStyleCancel
                                                 completion:nil
                                           simpleCompletion:cancelAction]];
    }
    [actions addObject:[PPAlertActionItem itemWithTitle:safeConfirmTitle
                                                  style:(type == PPAlertTypeError ? PPAlertActionStyleDestructive : PPAlertActionStylePrimary)
                                             completion:confirmAction
                                       simpleCompletion:nil]];

    return [self initWithType:type
                        title:title
                     subtitle:subtitle
                         icon:icon
                      actions:actions
                  placeholder:nil
                  initialText:nil
                  secureEntry:NO
                 keyboardType:UIKeyboardTypeDefault
  shouldDismissOnBackgroundTap:(cancelTitle.length > 0)];
}

- (instancetype)initWithType:(PPAlertType)type
                       title:(NSString *)title
                    subtitle:(NSString *)subtitle
                        icon:(UIImage * _Nullable)icon
                     actions:(NSArray<PPAlertActionItem *> *)actions
                 placeholder:(NSString * _Nullable)placeholder
                 initialText:(NSString * _Nullable)initialText
                 secureEntry:(BOOL)secureEntry
                keyboardType:(UIKeyboardType)keyboardType
shouldDismissOnBackgroundTap:(BOOL)shouldDismissOnBackgroundTap {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _type = type;
    NSString *titleFallbackKey = type == PPAlertTypeError ? @"Error" :
        (type == PPAlertTypeWarning ? @"alert_eyebrow_warning" : @"Info");
    _alertTitle = PPAlertSanitizedText(title, titleFallbackKey);
    _alertSubtitle = PPAlertSanitizedText(subtitle, @"SomethingWentWrong");
    _appearance = [PPAlertAppearance appearanceForType:type];
    _iconImage = icon ?: [UIImage systemImageNamed:_appearance.iconSystemName];
    _actionItems = actions ?: @[];
    _textPlaceholder = placeholder;
    _initialText = initialText;
    _secureEntry = secureEntry;
    _keyboardType = keyboardType;
    _shouldDismissOnBackgroundTap = shouldDismissOnBackgroundTap;
    self.backgroundColor = UIColor.clearColor;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;

    [self buildHierarchy];
    [self applyStyling];
    [self buildActions];
    [self registerForKeyboard];
    [self preparePresentationState];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)buildHierarchy {
    UIBlurEffect *backdropEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.backdropView = [[UIVisualEffectView alloc] initWithEffect:backdropEffect];
    self.backdropView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backdropView.userInteractionEnabled = YES;
    [self addSubview:self.backdropView];

    self.dimmingView = [[UIView alloc] init];
    self.dimmingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimmingView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.30];
    [self addSubview:self.dimmingView];

    UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
    dismissButton.backgroundColor = UIColor.clearColor;
    [dismissButton addTarget:self action:@selector(backgroundTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:dismissButton];

    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [AppForgroundColr colorWithAlphaComponent:0.94];
    self.cardView.layer.cornerRadius = 30.0;
    self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.cardView.layer.borderColor = [SeconderyTextClr colorWithAlphaComponent:0.08].CGColor;
    self.cardView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.cardView.layer.shadowOpacity = 0.18;
    self.cardView.layer.shadowRadius = 26.0;
    self.cardView.layer.shadowOffset = CGSizeMake(0.0, 18.0);
    [self addSubview:self.cardView];

    self.heroGlowView = [[UIView alloc] init];
    self.heroGlowView.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroGlowView.layer.cornerRadius = 112.0;
    self.heroGlowView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.cardView addSubview:self.heroGlowView];

    self.badgeView = [[UIView alloc] init];
    self.badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeView.layer.cornerRadius = 30.0;
    self.badgeView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.cardView addSubview:self.badgeView];

    self.iconView = [[UIImageView alloc] initWithImage:self.iconImage];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    [self.badgeView addSubview:self.iconView];

    self.eyebrowLabel = [[UILabel alloc] init];
    self.eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.eyebrowLabel.font = PPFontBold(11);
    self.eyebrowLabel.textColor = self.appearance.accentColor;
    self.eyebrowLabel.adjustsFontForContentSizeCategory = YES;
    self.eyebrowLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.eyebrowLabel.numberOfLines = 1;
    self.eyebrowLabel.text = [self eyebrowTextForType:self.type];
    [self.cardView addSubview:self.eyebrowLabel];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = PPFontBold(26);
    self.titleLabel.textColor = PrimaryTextClr;
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.titleLabel.text = self.alertTitle;
    [self.cardView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = PPFontRegular(15);
    self.subtitleLabel.textColor = SeconderyTextClr;
    self.subtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.subtitleLabel.text = self.alertSubtitle;
    [self.cardView addSubview:self.subtitleLabel];

    self.inputContainerView = [[UIView alloc] init];
    self.inputContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputContainerView.backgroundColor = [AppBackgroundClr colorWithAlphaComponent:0.78];
    self.inputContainerView.layer.cornerRadius = 22.0;
    self.inputContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.inputContainerView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.inputContainerView.layer.borderColor = [SeconderyTextClr colorWithAlphaComponent:0.06].CGColor;
    self.inputContainerView.hidden = self.type != PPAlertTypeTextInput;
    [self.cardView addSubview:self.inputContainerView];

    self.textField = [[UITextField alloc] init];
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    self.textField.font = PPFontMedium(17);
    self.textField.textColor = PrimaryTextClr;
    self.textField.tintColor = AppPrimaryClr;
    self.textField.placeholder = self.textPlaceholder ?: @"";
    self.textField.text = self.initialText ?: @"";
    self.textField.secureTextEntry = self.secureEntry;
    self.textField.keyboardType = self.keyboardType;
    self.textField.returnKeyType = UIReturnKeyDone;
    self.textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.textField.borderStyle = UITextBorderStyleNone;
    self.textField.textAlignment = Language.alignmentForCurrentLanguage;
    self.textField.adjustsFontForContentSizeCategory = YES;
    [self.textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [self.textField addTarget:self action:@selector(textFieldEditingDidBegin:) forControlEvents:UIControlEventEditingDidBegin];
    [self.textField addTarget:self action:@selector(textFieldEditingDidEnd:) forControlEvents:UIControlEventEditingDidEnd];
    [self.inputContainerView addSubview:self.textField];

    self.footnoteLabel = [[UILabel alloc] init];

    self.footnoteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.footnoteLabel.font = PPFontRegular(12);
    self.footnoteLabel.textColor = SeconderyTextClr;
    self.footnoteLabel.adjustsFontForContentSizeCategory = YES;
    self.footnoteLabel.numberOfLines = 0;
    self.footnoteLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.footnoteLabel.hidden = YES;
    self.footnoteLabel.text = @"";
    [self.cardView addSubview:self.footnoteLabel];

    self.buttonStackView = [[UIStackView alloc] init];
    self.buttonStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttonStackView.spacing = 10.0;
    self.buttonStackView.distribution = UIStackViewDistributionFillEqually;
    [self.cardView addSubview:self.buttonStackView];

    self.cardCenterYConstraint = [self.cardView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];

    [NSLayoutConstraint activateConstraints:@[

        [self.backdropView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.backdropView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.backdropView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.backdropView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [self.dimmingView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.dimmingView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.dimmingView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.dimmingView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [dismissButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [dismissButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [dismissButton.topAnchor constraintEqualToAnchor:self.topAnchor],
        [dismissButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        self.cardCenterYConstraint,

        [self.cardView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:20.0],
        [self.cardView.trailingAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-20.0],
        [self.cardView.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:20.0],
        [self.cardView.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-20.0],
        [self.cardView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.cardView.widthAnchor constraintLessThanOrEqualToConstant:420.0],
        [self.cardView.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.86],

        [self.heroGlowView.widthAnchor constraintEqualToConstant:224.0],
        [self.heroGlowView.heightAnchor constraintEqualToConstant:224.0],
        [self.heroGlowView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:-84.0],
        [self.heroGlowView.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:78.0],

        [self.badgeView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:20.0],
        [self.badgeView.centerXAnchor constraintEqualToAnchor:self.cardView.centerXAnchor],
        [self.badgeView.widthAnchor constraintEqualToConstant:60.0],
        [self.badgeView.heightAnchor constraintEqualToConstant:60.0],

        [self.iconView.centerXAnchor constraintEqualToAnchor:self.badgeView.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.badgeView.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:32.0],
        [self.iconView.heightAnchor constraintEqualToConstant:32.0],

        [self.eyebrowLabel.topAnchor constraintEqualToAnchor:self.badgeView.bottomAnchor constant:16.0],
        [self.eyebrowLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20.0],
        [self.eyebrowLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20.0],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.eyebrowLabel.bottomAnchor constant:8.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.eyebrowLabel.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.eyebrowLabel.trailingAnchor],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],

        [self.inputContainerView.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:16.0],
        [self.inputContainerView.leadingAnchor constraintEqualToAnchor:self.subtitleLabel.leadingAnchor],
        [self.inputContainerView.trailingAnchor constraintEqualToAnchor:self.subtitleLabel.trailingAnchor],

        [self.textField.topAnchor constraintEqualToAnchor:self.inputContainerView.topAnchor constant:14.0],
        [self.textField.leadingAnchor constraintEqualToAnchor:self.inputContainerView.leadingAnchor constant:16.0],
        [self.textField.trailingAnchor constraintEqualToAnchor:self.inputContainerView.trailingAnchor constant:-16.0],
        [self.textField.bottomAnchor constraintEqualToAnchor:self.inputContainerView.bottomAnchor constant:-14.0],
        [self.textField.heightAnchor constraintGreaterThanOrEqualToConstant:24.0],

        [self.footnoteLabel.topAnchor constraintEqualToAnchor:self.inputContainerView.bottomAnchor constant:10.0],
        [self.footnoteLabel.leadingAnchor constraintEqualToAnchor:self.subtitleLabel.leadingAnchor constant:2.0],
        [self.footnoteLabel.trailingAnchor constraintEqualToAnchor:self.subtitleLabel.trailingAnchor constant:-2.0],

        [self.buttonStackView.topAnchor constraintEqualToAnchor:(self.type == PPAlertTypeTextInput ? self.footnoteLabel.bottomAnchor : self.subtitleLabel.bottomAnchor) constant:(self.type == PPAlertTypeTextInput ? 18.0 : 20.0)],
        [self.buttonStackView.leadingAnchor constraintEqualToAnchor:self.subtitleLabel.leadingAnchor],
        [self.buttonStackView.trailingAnchor constraintEqualToAnchor:self.subtitleLabel.trailingAnchor],
        [self.buttonStackView.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-20.0]
    ]];
}

- (void)applyStyling {
    self.heroGlowView.backgroundColor = [self.appearance.accentColor colorWithAlphaComponent:0.08];
    self.badgeView.backgroundColor = self.appearance.badgeBackgroundColor;
    self.iconView.tintColor = self.appearance.badgeForegroundColor;
    self.inputContainerView.backgroundColor = [AppForgroundColr colorWithAlphaComponent:0.98];
    self.inputContainerView.layer.borderColor = [PrimaryTextClr colorWithAlphaComponent:0.10].CGColor;
    self.textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.textPlaceholder ?: @""
                                                                            attributes:@{
        NSForegroundColorAttributeName: [SeconderyTextClr colorWithAlphaComponent:0.72],
        NSFontAttributeName: self.textField.font ?: PPFontMedium(17)
    }];
    [self pp_updateInputFieldAppearanceFocused:NO hasText:PPAlertTrimmedText(self.textField.text).length > 0];
}

- (void)buildActions {
    self.buttonStackView.axis = self.actionItems.count >= 3 ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.buttonStackView.spacing = self.actionItems.count >= 3 ? 10.0 : 12.0;
    self.buttonStackView.distribution = UIStackViewDistributionFillEqually;

    for (NSInteger idx = 0; idx < self.actionItems.count; idx += 1) {
        PPAlertActionItem *item = self.actionItems[idx];
        UIButton *button = [self actionButtonForItem:item];
        button.tag = idx;
        [button addTarget:self action:@selector(actionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.buttonStackView addArrangedSubview:button];
        [button.heightAnchor constraintEqualToConstant:54.0].active = YES;
    }
}

- (UIButton *)actionButtonForItem:(PPAlertActionItem *)item {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 20.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.titleLabel.font = (item.style == PPAlertActionStylePrimary || item.style == PPAlertActionStyleCancel) ? PPFontBold(16) : PPFontMedium(16);
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button setTitle:item.title forState:UIControlStateNormal];

    UIColor *backgroundColor = AppForgroundColr;
    UIColor *titleColor = PrimaryTextClr;
    UIColor *borderColor = [SeconderyTextClr colorWithAlphaComponent:0.08];

    switch (item.style) {
        case PPAlertActionStylePrimary:
            backgroundColor = self.appearance.accentColor;
            titleColor = UIColor.whiteColor;
            borderColor = UIColor.clearColor;
            break;
        case PPAlertActionStyleDestructive:
            backgroundColor = UIColor.systemRedColor;
            titleColor = UIColor.whiteColor;
            borderColor = UIColor.clearColor;
            break;
        case PPAlertActionStyleSecondary:
            backgroundColor = [AppBackgroundClr colorWithAlphaComponent:0.82];
            titleColor = PrimaryTextClr;
            borderColor = [SeconderyTextClr colorWithAlphaComponent:0.08];
            break;
        case PPAlertActionStyleCancel:
            backgroundColor = [AppForgroundColr colorWithAlphaComponent:0.98];
            titleColor = [PrimaryTextClr colorWithAlphaComponent:0.92];
            borderColor = [PrimaryTextClr colorWithAlphaComponent:0.14];
            break;
    }

    button.backgroundColor = backgroundColor;
    button.layer.borderWidth = borderColor == UIColor.clearColor ? 0.0 : (1.0 / UIScreen.mainScreen.scale);
    button.layer.borderColor = borderColor.CGColor;
    [button setTitleColor:titleColor forState:UIControlStateNormal];
    if (item.style == PPAlertActionStyleCancel) {
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.05;
        button.layer.shadowRadius = 10.0;
        button.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    }

    return button;
}

- (NSString *)eyebrowTextForType:(PPAlertType)type {
    switch (type) {
        case PPAlertTypeSuccess: return kLang(@"alert_eyebrow_success") ?: @"Success";
        case PPAlertTypeError: return kLang(@"alert_eyebrow_error") ?: @"Action required";
        case PPAlertTypeWarning: return kLang(@"alert_eyebrow_warning") ?: @"Please review";
        case PPAlertTypeInfo: return kLang(@"alert_eyebrow_info") ?: @"Details";
        case PPAlertTypeConfirmation: return kLang(@"alert_eyebrow_confirmation") ?: @"Confirmation";
        case PPAlertTypeTextInput: return kLang(@"alert_eyebrow_input") ?: @"Input";
    }
}

- (void)registerForKeyboard {
    if (self.type != PPAlertTypeTextInput) return;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)preparePresentationState {
    if (self.didPreparePresentation) return;
    self.didPreparePresentation = YES;
    self.backdropView.alpha = 0.0;
    self.dimmingView.alpha = 0.0;
    self.cardView.alpha = 0.0;
    self.cardView.transform = CGAffineTransformMakeScale(1.04, 1.04);
    self.titleLabel.alpha = 0.0;
    self.titleLabel.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
    self.subtitleLabel.alpha = 0.0;
    self.subtitleLabel.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    self.buttonStackView.alpha = 0.0;
    self.buttonStackView.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
    self.inputContainerView.alpha = self.type == PPAlertTypeTextInput ? 0.0 : 1.0;
    if (self.type == PPAlertTypeTextInput) {
        self.inputContainerView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
        self.footnoteLabel.alpha = 0.0;
        self.footnoteLabel.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
    }
}

- (void)showInViewController:(UIViewController *)vc {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self prepareOverlayWindowForViewController:vc];
        [ppAlertRootViewController.view addSubview:self];
        [NSLayoutConstraint activateConstraints:@[
            [self.leadingAnchor constraintEqualToAnchor:ppAlertRootViewController.view.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:ppAlertRootViewController.view.trailingAnchor],
            [self.topAnchor constraintEqualToAnchor:ppAlertRootViewController.view.topAnchor],
            [self.bottomAnchor constraintEqualToAnchor:ppAlertRootViewController.view.bottomAnchor]
        ]];
        [ppAlertRootViewController.view layoutIfNeeded];
        [self runPresentationIfNeeded];
    });
}

- (void)prepareOverlayWindowForViewController:(UIViewController *)vc {
    if (ppAlertOverlayWindow) return;

    UIWindowScene *scene = vc.view.window.windowScene;
    if (!scene) {
        for (UIScene *connectedScene in UIApplication.sharedApplication.connectedScenes) {
            if ([connectedScene isKindOfClass:[UIWindowScene class]] &&
                connectedScene.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)connectedScene;
                break;
            }
        }
    }

    if (scene) {
        ppAlertOverlayWindow = [[UIWindow alloc] initWithWindowScene:scene];
    } else {
        ppAlertOverlayWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }
    ppAlertOverlayWindow.backgroundColor = UIColor.clearColor;
    ppAlertOverlayWindow.windowLevel = UIWindowLevelAlert + 1;
    ppAlertRootViewController = [[UIViewController alloc] init];
    ppAlertRootViewController.view.backgroundColor = UIColor.clearColor;
    ppAlertOverlayWindow.rootViewController = ppAlertRootViewController;
    ppAlertOverlayWindow.hidden = NO;
}

- (void)runPresentationIfNeeded {
    if (self.didRunPresentation) return;
    self.didRunPresentation = YES;

    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    if (reduceMotion) {
        self.backdropView.alpha = 1.0;
        self.dimmingView.alpha = 1.0;
        self.cardView.alpha = 1.0;
        self.cardView.transform = CGAffineTransformIdentity;
        self.titleLabel.alpha = 1.0;
        self.titleLabel.transform = CGAffineTransformIdentity;
        self.subtitleLabel.alpha = 1.0;
        self.subtitleLabel.transform = CGAffineTransformIdentity;
        self.buttonStackView.alpha = 1.0;
        self.buttonStackView.transform = CGAffineTransformIdentity;
        self.inputContainerView.alpha = 1.0;
        self.inputContainerView.transform = CGAffineTransformIdentity;
        self.footnoteLabel.alpha = 1.0;
        self.footnoteLabel.transform = CGAffineTransformIdentity;
        if (self.type == PPAlertTypeTextInput) {
            [self.textField becomeFirstResponder];
        }
        return;
    }

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft];
    [feedback prepare];

    [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.backdropView.alpha = 1.0;
        self.dimmingView.alpha = 1.0;
    } completion:nil];

    [UIView animateWithDuration:0.46
                          delay:0.0
         usingSpringWithDamping:0.88
          initialSpringVelocity:0.28
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.cardView.alpha = 1.0;
        self.cardView.transform = CGAffineTransformIdentity;
    } completion:^(__unused BOOL finished) {
        [feedback impactOccurred];
        if (self.type == PPAlertTypeTextInput) {
            [self.textField becomeFirstResponder];
        }
    }];

    [UIView animateWithDuration:0.30 delay:0.06 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.titleLabel.alpha = 1.0;
        self.titleLabel.transform = CGAffineTransformIdentity;
    } completion:nil];
    [UIView animateWithDuration:0.30 delay:0.10 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.subtitleLabel.alpha = 1.0;
        self.subtitleLabel.transform = CGAffineTransformIdentity;
    } completion:nil];
    [UIView animateWithDuration:0.32 delay:0.14 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.inputContainerView.alpha = 1.0;
        self.inputContainerView.transform = CGAffineTransformIdentity;
        self.footnoteLabel.alpha = 1.0;
        self.footnoteLabel.transform = CGAffineTransformIdentity;
    } completion:nil];
    [UIView animateWithDuration:0.34 delay:0.18 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.buttonStackView.alpha = 1.0;
        self.buttonStackView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)backgroundTapped {
    if (!self.shouldDismissOnBackgroundTap) return;
    PPAlertActionItem *cancelItem = nil;
    for (PPAlertActionItem *item in self.actionItems) {
        if (item.style == PPAlertActionStyleCancel) {
            cancelItem = item;
            break;
        }
    }
    [self dismissWithSelectedAction:cancelItem didConfirm:NO];
}

- (void)actionButtonTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= self.actionItems.count) return;
    [self dismissWithSelectedAction:self.actionItems[idx] didConfirm:(self.actionItems[idx].style != PPAlertActionStyleCancel)];
}

- (void)dismissWithSelectedAction:(PPAlertActionItem * _Nullable)selectedAction didConfirm:(BOOL)didConfirm {
    if (!self.superview || self.isPresentingAlert) return;
    self.isPresentingAlert = YES;

    if (selectedAction.style == PPAlertActionStylePrimary || selectedAction.style == PPAlertActionStyleDestructive) {
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:(selectedAction.style == PPAlertActionStyleDestructive ? UINotificationFeedbackTypeWarning : UINotificationFeedbackTypeSuccess)];
    }

    [self endEditing:YES];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    NSTimeInterval duration = reduceMotion ? 0.12 : 0.22;
    [UIView animateWithDuration:duration
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.backdropView.alpha = 0.0;
        self.dimmingView.alpha = 0.0;
        self.cardView.alpha = 0.0;
        self.cardView.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformConcat(CGAffineTransformMakeTranslation(0.0, 12.0), CGAffineTransformMakeScale(0.96, 0.96));
    } completion:^(__unused BOOL finished) {
        [self removeFromSuperview];
        [self cleanupOverlayWindowIfPossible];
        if (selectedAction.completion) {
            selectedAction.completion(self.textField.text, didConfirm);
        }
        if (selectedAction.simpleCompletion) {
            selectedAction.simpleCompletion();
        }
        self.isPresentingAlert = NO;
    }];
}

- (void)cleanupOverlayWindowIfPossible {
    if (ppAlertRootViewController.view.subviews.count > 0) return;
    ppAlertOverlayWindow.hidden = YES;
    ppAlertOverlayWindow.rootViewController = nil;
    ppAlertOverlayWindow = nil;
    ppAlertRootViewController = nil;
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    if (self.type != PPAlertTypeTextInput) return;
    NSDictionary *info = notification.userInfo ?: @{};
    CGRect keyboardFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    CGRect keyboardFrameInSelf = [self convertRect:keyboardFrame fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.cardView.frame) - keyboardFrameInSelf.origin.y + 20.0;
    self.cardCenterYConstraint.constant = overlap > 0.0 ? -MIN(overlap * 0.5, 120.0) : 0.0;
    [UIView animateWithDuration:duration
                          delay:0.0
                        options:(curve << 16) | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo ?: @{};
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    self.cardCenterYConstraint.constant = 0.0;
    [UIView animateWithDuration:duration
                          delay:0.0
                        options:(curve << 16) | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)textFieldEditingDidBegin:(UITextField *)textField {
    if (self.type != PPAlertTypeTextInput) return;
    [self pp_updateInputFieldAppearanceFocused:YES hasText:PPAlertTrimmedText(textField.text).length > 0];
}

- (void)textFieldEditingDidEnd:(UITextField *)textField {
    if (self.type != PPAlertTypeTextInput) return;
    [self pp_updateInputFieldAppearanceFocused:NO hasText:PPAlertTrimmedText(textField.text).length > 0];
}

- (void)textFieldDidChange:(UITextField *)textField {
    if (self.type != PPAlertTypeTextInput) return;
    BOOL hasText = PPAlertTrimmedText(textField.text).length > 0;
    [self pp_updateInputFieldAppearanceFocused:textField.isEditing hasText:hasText];
}

- (void)pp_updateInputFieldAppearanceFocused:(BOOL)focused hasText:(BOOL)hasText {
    UIColor *borderColor = focused
        ? [self.appearance.accentColor colorWithAlphaComponent:0.28]
        : (hasText ? [PrimaryTextClr colorWithAlphaComponent:0.16] : [PrimaryTextClr colorWithAlphaComponent:0.10]);
    UIColor *backgroundColor = focused
        ? [self.appearance.accentColor colorWithAlphaComponent:0.05]
        : [AppForgroundColr colorWithAlphaComponent:0.98];

    self.inputContainerView.backgroundColor = backgroundColor;
    self.inputContainerView.layer.borderColor = borderColor.CGColor;
}

@end

@implementation AlertHelper

+ (UIViewController *)presenterForViewController:(UIViewController *)vc {
    UIViewController *presenter = vc;
    if (!presenter) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow && window.rootViewController) {
                    presenter = window.rootViewController;
                    break;
                }
            }
            if (presenter) break;
        }
    }
    if (!presenter) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.rootViewController) {
                    presenter = window.rootViewController;
                    break;
                }
            }
            if (presenter) break;
        }
    }
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    return presenter;
}

+ (UIImage *)symbolImageNamed:(NSString *)systemName fallbackType:(PPAlertType)type {
    UIImage *image = [UIImage systemImageNamed:systemName];
    if (image) return image;
    PPAlertAppearance *appearance = [PPAlertAppearance appearanceForType:type];
    return [UIImage systemImageNamed:appearance.iconSystemName];
}

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
        confirmAction:(AlertCompletionBlock _Nullable)confirmAction
         cancelAction:(void (^)(void))cancelAction {
    UIImage *icon = [self symbolImageNamed:@"checkmark.seal.fill" fallbackType:PPAlertTypeSuccess];
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeSuccess
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon
                                       confirmTitle:kLang(@"OK")
                                        cancelTitle:nil
                                      confirmAction:confirmAction
                                       cancelAction:cancelAction];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
             OKAction:(AlertCompletionBlock _Nullable)okAction {
    [self showSuccessIn:vc title:title subtitle:subtitle confirmAction:okAction cancelAction:nil];
}

+ (void)showSuccessIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle {
    [self showSuccessIn:vc title:title subtitle:subtitle ?: @"" confirmAction:nil cancelAction:nil];
}

+ (void)showErrorIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle {
    UIImage *icon = [self symbolImageNamed:@"xmark.seal.fill" fallbackType:PPAlertTypeError];
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeError
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon
                                       confirmTitle:kLang(@"OK")
                                        cancelTitle:nil
                                      confirmAction:nil
                                       cancelAction:nil];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showWarningIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle {
    UIImage *icon = [self symbolImageNamed:@"exclamationmark.triangle.fill" fallbackType:PPAlertTypeWarning];
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeWarning
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon
                                       confirmTitle:kLang(@"OK")
                                        cancelTitle:nil
                                      confirmAction:nil
                                       cancelAction:nil];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showInfoIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle {
    UIImage *icon = [self symbolImageNamed:@"info.circle.fill" fallbackType:PPAlertTypeInfo];
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeInfo
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon
                                       confirmTitle:kLang(@"OK")
                                        cancelTitle:nil
                                      confirmAction:nil
                                       cancelAction:nil];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showWarningIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString * _Nullable)subtitle
           completion:(void (^ _Nullable)(void))completion {
    UIImage *icon = [self symbolImageNamed:@"exclamationmark.triangle.fill" fallbackType:PPAlertTypeWarning];
    AlertCompletionBlock wrapped = completion ? ^(__unused NSString * _Nullable text, __unused BOOL didConfirm) { completion(); } : nil;
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeWarning
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon
                                       confirmTitle:kLang(@"OK")
                                        cancelTitle:nil
                                      confirmAction:wrapped
                                       cancelAction:nil];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showInfoIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion {
    UIImage *icon = [self symbolImageNamed:@"info.circle.fill" fallbackType:PPAlertTypeInfo];
    AlertCompletionBlock wrapped = completion ? ^(__unused NSString * _Nullable text, __unused BOOL didConfirm) { completion(); } : nil;
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeInfo
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon
                                       confirmTitle:kLang(@"OK")
                                        cancelTitle:nil
                                      confirmAction:wrapped
                                       cancelAction:nil];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString *)cancelTitle
                      icon:(UIImage * _Nullable)icon
              confirmBlock:(AlertCompletionBlock _Nullable)confirmBlock
               cancelBlock:(void(^ _Nullable)(void))cancelBlock {
    UIImage *iconImage = icon ?: [self symbolImageNamed:@"questionmark.circle.fill" fallbackType:PPAlertTypeConfirmation];
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:iconImage
                                       confirmTitle:confirmTitle.length ? confirmTitle : kLang(@"Confirm")
                                        cancelTitle:cancelTitle.length ? cancelTitle : kLang(@"Cancel")
                                      confirmAction:confirmBlock
                                       cancelAction:cancelBlock];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showThreeActionConfirmationIn:(UIViewController *)vc
                                title:(NSString *)title
                             subtitle:(NSString * _Nullable)subtitle
                        primaryButton:(NSString *)primaryTitle
                         primaryStyle:(UIAlertActionStyle)primaryStyle
                      secondaryButton:(NSString *)secondaryTitle
                       secondaryStyle:(UIAlertActionStyle)secondaryStyle
                       tertiaryButton:(NSString *)tertiaryTitle
                        tertiaryStyle:(UIAlertActionStyle)tertiaryStyle
                         primaryBlock:(PPAlertSimpleActionBlock _Nullable)primaryBlock
                       secondaryBlock:(PPAlertSimpleActionBlock _Nullable)secondaryBlock
                        tertiaryBlock:(PPAlertSimpleActionBlock _Nullable)tertiaryBlock {
    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];
    [actions addObject:[PPAlertActionItem itemWithTitle:primaryTitle
                                                  style:(primaryStyle == UIAlertActionStyleDestructive ? PPAlertActionStyleDestructive : PPAlertActionStylePrimary)
                                             completion:nil
                                       simpleCompletion:primaryBlock]];
    [actions addObject:[PPAlertActionItem itemWithTitle:secondaryTitle
                                                  style:(secondaryStyle == UIAlertActionStyleCancel ? PPAlertActionStyleCancel : (secondaryStyle == UIAlertActionStyleDestructive ? PPAlertActionStyleDestructive : PPAlertActionStyleSecondary))
                                             completion:nil
                                       simpleCompletion:secondaryBlock]];
    [actions addObject:[PPAlertActionItem itemWithTitle:tertiaryTitle
                                                  style:(tertiaryStyle == UIAlertActionStyleCancel ? PPAlertActionStyleCancel : (tertiaryStyle == UIAlertActionStyleDestructive ? PPAlertActionStyleDestructive : PPAlertActionStyleSecondary))
                                             completion:nil
                                       simpleCompletion:tertiaryBlock]];

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:[self symbolImageNamed:@"sparkles" fallbackType:PPAlertTypeConfirmation]
                                           actions:actions
                                       placeholder:nil
                                       initialText:nil
                                       secureEntry:NO
                                      keyboardType:UIKeyboardTypeDefault
                       shouldDismissOnBackgroundTap:YES];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showFailIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion {
    UIImage *icon = [self symbolImageNamed:@"xmark.octagon.fill" fallbackType:PPAlertTypeError];
    AlertCompletionBlock wrapped = completion ? ^(__unused NSString * _Nullable text, __unused BOOL didConfirm) { completion(); } : nil;
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeError
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon
                                       confirmTitle:kLang(@"OK")
                                        cancelTitle:nil
                                      confirmAction:wrapped
                                       cancelAction:nil];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showTextFieldAlertIn:(UIViewController *)vc
                       title:(NSString *)title
                    subtitle:(NSString * _Nullable)subtitle
                 placeholder:(NSString * _Nullable)placeholder
                 initialText:(NSString * _Nullable)initialText
                 confirmText:(NSString * _Nullable)confirmText
                  cancelText:(NSString * _Nullable)cancelText
                 completion:(AlertCompletionBlock)completion {
    [self showTextPromptIn:vc
                     title:title
                  subtitle:subtitle
               placeholder:placeholder
               initialText:initialText
               confirmText:confirmText
                cancelText:cancelText
               secureEntry:NO
              keyboardType:UIKeyboardTypeDefault
                completion:^(NSString * _Nullable text) {
        if (completion) {
            completion(text, text != nil);
        }
    }];
}

#pragma mark - Backward-compatible (old AlertHelper API)

+ (void)showAlertIn:(UIViewController *)vc
              title:(NSString *)title
           subtitle:(NSString *)subtitle {
    [self showAlertIn:vc title:title subtitle:subtitle placeholder:nil withType:@"error"];
}

+ (void)showAlertIn:(UIViewController *)vc
              title:(NSString *)title
           subtitle:(NSString *)subtitle
        placeholder:(NSString *)placeholder
           withType:(NSString *)type {
    if (!vc) return;
    if ([type isEqualToString:@"success"]) {
        [self showSuccessIn:vc title:title subtitle:subtitle];
    } else if ([type isEqualToString:@"error"]) {
        [self showErrorIn:vc title:title subtitle:subtitle];
    } else if ([type isEqualToString:@"warning"]) {
        [self showWarningIn:vc title:title subtitle:subtitle];
    } else if ([type isEqualToString:@"info"]) {
        [self showInfoIn:vc title:title subtitle:subtitle];
    } else {
        [self showInfoIn:vc title:title subtitle:subtitle];
    }
}

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
               placeholder:(NSString * _Nullable)placeholder
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString * _Nullable)cancelTitle
              confirmBlock:(void(^_Nullable)(void))confirmBlock
               cancelBlock:(void(^_Nullable)(void))cancelBlock {
    [self showConfirmationIn:vc
                       title:title
                    subtitle:subtitle
                 placeholder:placeholder
               confirmButton:confirmTitle
                cancelButton:cancelTitle
                        icon:nil
                confirmBlock:confirmBlock
                 cancelBlock:cancelBlock];
}

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
               placeholder:(NSString * _Nullable)placeholder
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString * _Nullable)cancelTitle
                      icon:(UIImage * _Nullable)icon
              confirmBlock:(void(^_Nullable)(void))confirmBlock
               cancelBlock:(void(^_Nullable)(void))cancelBlock {
    AlertCompletionBlock wrappedConfirm = nil;
    if (confirmBlock) {
        wrappedConfirm = ^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
            confirmBlock();
        };
    }
    [self showConfirmationIn:vc
                       title:title
                    subtitle:subtitle
               confirmButton:confirmTitle
                cancelButton:cancelTitle
                        icon:icon
                confirmBlock:wrappedConfirm
                 cancelBlock:cancelBlock];
}

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
                subtitle:(NSString * _Nullable)subtitle
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
             confirmText:(NSString * _Nullable)confirmText
              cancelText:(NSString * _Nullable)cancelText
              completion:(void(^)(NSString * _Nullable text))completion {
    [self showTextPromptIn:vc
                     title:title
                  subtitle:subtitle
               placeholder:placeholder
               initialText:initialText
               confirmText:confirmText
                cancelText:cancelText
               secureEntry:NO
              keyboardType:UIKeyboardTypeDefault
                completion:completion];
}

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
                subtitle:(NSString * _Nullable)subtitle
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
             confirmText:(NSString * _Nullable)confirmText
              cancelText:(NSString * _Nullable)cancelText
             secureEntry:(BOOL)secureEntry
            keyboardType:(UIKeyboardType)keyboardType
              completion:(void(^)(NSString * _Nullable text))completion {
    NSString *safeConfirm = confirmText.length ? confirmText : kLang(@"OK");
    NSString *safeCancel = cancelText.length ? cancelText : kLang(@"Cancel");
    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];
    [actions addObject:[PPAlertActionItem itemWithTitle:safeCancel
                                                  style:PPAlertActionStyleCancel
                                             completion:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion(nil);
    }
                                       simpleCompletion:nil]];
    [actions addObject:[PPAlertActionItem itemWithTitle:safeConfirm
                                                  style:PPAlertActionStylePrimary
                                             completion:^(NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion(text);
    }
                                       simpleCompletion:nil]];

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeTextInput
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:[self symbolImageNamed:@"square.and.pencil.circle.fill" fallbackType:PPAlertTypeTextInput]
                                           actions:actions
                                       placeholder:placeholder
                                       initialText:initialText
                                       secureEntry:secureEntry
                                      keyboardType:keyboardType
                       shouldDismissOnBackgroundTap:YES];
    [alert showInViewController:[self presenterForViewController:vc]];
}

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
              completion:(void(^)(NSString * _Nullable text))completion {
    [self showTextPromptIn:vc
                     title:title
                  subtitle:nil
               placeholder:placeholder
               initialText:initialText
               confirmText:nil
                cancelText:nil
               secureEntry:NO
              keyboardType:UIKeyboardTypeDefault
                completion:completion];
}

@end
