//
//  PPAlertHelper.m
//  PurePetsPro
//
//  Reinvented from absolute first principles for iPhone & iPad.
//  Category-defining Apple modal architecture, unified reading axis,
//  zero geometric clipping flaws, hardware keyboard & pointer support.
//

#import "PPAlertHelper.h"
#import "Language.h"
#import "Styling.h"
#import <AudioToolbox/AudioToolbox.h>

#ifndef PrimaryTextClr
#define PrimaryTextClr (AppPrimaryTextClr ?: UIColor.labelColor)
#endif

#ifndef SeconderyTextClr
#define SeconderyTextClr (AppSecondaryTextClr ?: UIColor.secondaryLabelColor)
#endif

#ifndef PPFontBold
#define PPFontBold(size) ([Styling fontBold:(size)] ?: [UIFont systemFontOfSize:(size) weight:UIFontWeightBold])
#endif

#ifndef PPFontMedium
#define PPFontMedium(size) ([Styling fontMedium:(size)] ?: [UIFont systemFontOfSize:(size) weight:UIFontWeightMedium])
#endif

#ifndef PPFontRegular
#define PPFontRegular(size) ([Styling fontRegular:(size)] ?: [UIFont systemFontOfSize:(size) weight:UIFontWeightRegular])
#endif

static UIWindow *ppAlertOverlayWindow = nil;
static UIViewController *ppAlertRootViewController = nil;

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

// MARK: - Action Item Model

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

// MARK: - Semantic Appearance Profile

@interface PPAlertAppearance : NSObject
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, copy) NSString *iconSystemName;
@property (nonatomic, strong) UIColor *badgeBackgroundColor;
@property (nonatomic, strong) UIColor *badgeForegroundColor;
@property (nonatomic, copy) NSString *eyebrowText;

+ (instancetype)appearanceForType:(PPAlertType)type;
@end

@implementation PPAlertAppearance

+ (instancetype)appearanceForType:(PPAlertType)type {
    PPAlertAppearance *appearance = [[self alloc] init];
    switch (type) {
        case PPAlertTypeSuccess:
            appearance.accentColor = [UIColor ppSuccess];
            appearance.iconSystemName = @"checkmark.seal.fill";
            appearance.eyebrowText = kLang(@"Alert_Eyebrow_Success") ?: (kLang(@"alert_eyebrow_success") ?: @"SUCCESS");
            break;
        case PPAlertTypeError:
            appearance.accentColor = [UIColor ppError];
            appearance.iconSystemName = @"xmark.seal.fill";
            appearance.eyebrowText = kLang(@"Alert_Eyebrow_Error") ?: (kLang(@"alert_eyebrow_error") ?: @"ACTION REQUIRED");
            break;
        case PPAlertTypeWarning:
            appearance.accentColor = [UIColor ppWarning];
            appearance.iconSystemName = @"exclamationmark.triangle.fill";
            appearance.eyebrowText = kLang(@"Alert_Eyebrow_Warning") ?: (kLang(@"alert_eyebrow_warning") ?: @"PLEASE REVIEW");
            break;
        case PPAlertTypeInfo:
            appearance.accentColor = AppPrimaryClr;
            appearance.iconSystemName = @"info.circle.fill";
            appearance.eyebrowText = kLang(@"Alert_Eyebrow_Info") ?: (kLang(@"alert_eyebrow_info") ?: @"DETAILS");
            break;
        case PPAlertTypeConfirmation:
            appearance.accentColor = AppPrimaryClr;
            appearance.iconSystemName = @"questionmark.circle.fill";
            appearance.eyebrowText = kLang(@"Alert_Eyebrow_Confirmation") ?: (kLang(@"alert_eyebrow_confirmation") ?: @"CONFIRMATION");
            break;
        case PPAlertTypeTextInput:
            appearance.accentColor = AppPrimaryClr;
            appearance.iconSystemName = @"square.and.pencil.circle.fill";
            appearance.eyebrowText = kLang(@"Alert_Eyebrow_TextInput") ?: (kLang(@"alert_eyebrow_input") ?: @"INPUT");
            break;
    }
    appearance.badgeBackgroundColor = [appearance.accentColor colorWithAlphaComponent:0.12];
    appearance.badgeForegroundColor = appearance.accentColor;
    return appearance;
}

@end

// MARK: - PPAlert View

@interface PPAlert () <UITextFieldDelegate, UIPointerInteractionDelegate>

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
@property (nonatomic, strong) UIView *cardContainerView;
@property (nonatomic, strong) UIView *cardInnerAuraView;
@property (nonatomic, strong) UIView *badgeView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIView *eyebrowCapsule;
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *inputContainerView;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, strong) UILabel *footnoteLabel;
@property (nonatomic, strong) UIStackView *buttonStackView;
@property (nonatomic, strong) NSLayoutConstraint *cardCenterYConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardWidthConstraint;

@property (nonatomic, strong) PPAlertAppearance *appearance;
@property (nonatomic, assign) BOOL didPreparePresentation;
@property (nonatomic, assign) BOOL didRunPresentation;
@property (nonatomic, assign) BOOL isPresentingAlert;

@end

@implementation PPAlert

#pragma mark - Initializers

- (instancetype)initWithType:(PPAlertType)type
                       title:(NSString *)title
                    subtitle:(NSString *)subtitle
                        icon:(UIImage *)icon
                confirmTitle:(NSString * _Nullable)confirmTitle
                 cancelTitle:(NSString * _Nullable)cancelTitle
               confirmAction:(AlertCompletionBlock _Nullable)confirmAction
                cancelAction:(void(^ _Nullable)(void))cancelAction {
    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];
    NSString *safeConfirmTitle = confirmTitle.length ? confirmTitle : (kLang(@"OK") ?: @"OK");
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
    _alertTitle = title ?: @"";
    _alertSubtitle = subtitle ?: @"";
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

#pragma mark - First-Principles Hierarchy Construction

- (void)buildHierarchy {
    // 1. Ambient Blur Backdrop
    UIBlurEffect *backdropEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    self.backdropView = [[UIVisualEffectView alloc] initWithEffect:backdropEffect];
    self.backdropView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backdropView.userInteractionEnabled = YES;
    [self addSubview:self.backdropView];

    // 2. Soft Dimming
    self.dimmingView = [[UIView alloc] init];
    self.dimmingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimmingView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    [self addSubview:self.dimmingView];

    // 3. Background Dismiss Trigger
    UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
    dismissButton.backgroundColor = UIColor.clearColor;
    [dismissButton addTarget:self action:@selector(backgroundTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:dismissButton];

    // 4. Elevated Continuous Card Container
    self.cardContainerView = [[UIView alloc] init];
    self.cardContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardContainerView.backgroundColor = AppForgroundColr;
    self.cardContainerView.layer.cornerRadius = 28.0;
    self.cardContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardContainerView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.cardContainerView.layer.borderColor = [PrimaryTextClr colorWithAlphaComponent:0.08].CGColor;
    self.cardContainerView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.cardContainerView.layer.shadowOpacity = 0.16;
    self.cardContainerView.layer.shadowRadius = 32.0;
    self.cardContainerView.layer.shadowOffset = CGSizeMake(0.0, 16.0);
    self.cardContainerView.clipsToBounds = NO;
    self.cardContainerView.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    [self addSubview:self.cardContainerView];

    // 5. Contained Inner Aura (Replaces the broken clipped-moon heroGlowView)
    self.cardInnerAuraView = [[UIView alloc] init];
    self.cardInnerAuraView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardInnerAuraView.backgroundColor = [self.appearance.accentColor colorWithAlphaComponent:0.07];
    self.cardInnerAuraView.layer.cornerRadius = 140.0;
    self.cardInnerAuraView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardInnerAuraView.layer.masksToBounds = YES;
    self.cardInnerAuraView.userInteractionEnabled = NO;
    [self.cardContainerView addSubview:self.cardInnerAuraView];

    // 6. Tactile Icon Badge
    self.badgeView = [[UIView alloc] init];
    self.badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeView.layer.cornerRadius = 28.0;
    self.badgeView.layer.cornerCurve = kCACornerCurveContinuous;
    self.badgeView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.badgeView.layer.borderColor = [self.appearance.accentColor colorWithAlphaComponent:0.20].CGColor;
    [self.cardContainerView addSubview:self.badgeView];

    self.iconView = [[UIImageView alloc] initWithImage:self.iconImage];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.isAccessibilityElement = NO;
    [self.badgeView addSubview:self.iconView];

    // 7. Eyebrow Semantic Pill
    self.eyebrowCapsule = [[UIView alloc] init];
    self.eyebrowCapsule.translatesAutoresizingMaskIntoConstraints = NO;
    self.eyebrowCapsule.backgroundColor = [self.appearance.accentColor colorWithAlphaComponent:0.10];
    self.eyebrowCapsule.layer.cornerRadius = 11.0;
    self.eyebrowCapsule.layer.cornerCurve = kCACornerCurveContinuous;
    [self.cardContainerView addSubview:self.eyebrowCapsule];

    self.eyebrowLabel = [[UILabel alloc] init];
    self.eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.eyebrowLabel.font = PPFontBold(10.5);
    self.eyebrowLabel.textColor = self.appearance.accentColor;
    self.eyebrowLabel.textAlignment = NSTextAlignmentCenter;
    self.eyebrowLabel.numberOfLines = 1;
    self.eyebrowLabel.text = [self.appearance.eyebrowText uppercaseString];
    self.eyebrowLabel.adjustsFontForContentSizeCategory = YES;
    [self.eyebrowCapsule addSubview:self.eyebrowLabel];

    // 8. Title Label (Centered Harmonic Axis)
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = PPFontBold(23.0);
    self.titleLabel.textColor = PrimaryTextClr;
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.text = self.alertTitle;
    [self.cardContainerView addSubview:self.titleLabel];

    // 9. Subtitle Label
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = PPFontRegular(14.5);
    self.subtitleLabel.textColor = [SeconderyTextClr colorWithAlphaComponent:0.86];
    self.subtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.text = self.alertSubtitle;
    [self.cardContainerView addSubview:self.subtitleLabel];

    // 10. Optional Text Input Container
    self.inputContainerView = [[UIView alloc] init];
    self.inputContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputContainerView.backgroundColor = [AppBackgroundClr colorWithAlphaComponent:0.85];
    self.inputContainerView.layer.cornerRadius = 16.0;
    self.inputContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.inputContainerView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.inputContainerView.layer.borderColor = [SeconderyTextClr colorWithAlphaComponent:0.12].CGColor;
    self.inputContainerView.hidden = (self.type != PPAlertTypeTextInput);
    [self.cardContainerView addSubview:self.inputContainerView];

    self.textField = [[UITextField alloc] init];
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    self.textField.font = PPFontMedium(16.0);
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
    self.textField.delegate = self;
    [self.textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [self.inputContainerView addSubview:self.textField];

    self.footnoteLabel = [[UILabel alloc] init];
    self.footnoteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.footnoteLabel.font = PPFontRegular(12.0);
    self.footnoteLabel.textColor = SeconderyTextClr;
    self.footnoteLabel.adjustsFontForContentSizeCategory = YES;
    self.footnoteLabel.numberOfLines = 0;
    self.footnoteLabel.textAlignment = NSTextAlignmentCenter;
    self.footnoteLabel.hidden = YES;
    [self.cardContainerView addSubview:self.footnoteLabel];

    // 11. Button Stack View
    self.buttonStackView = [[UIStackView alloc] init];
    self.buttonStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttonStackView.spacing = 10.0;
    self.buttonStackView.distribution = UIStackViewDistributionFillEqually;
    self.buttonStackView.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    [self.cardContainerView addSubview:self.buttonStackView];

    // Constraints Architecture
    self.cardCenterYConstraint = [self.cardContainerView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];

    BOOL isIPad = (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad);
    CGFloat maxCardWidth = isIPad ? 460.0 : 380.0;
    NSLayoutConstraint *cardWidthConstraint = [self.cardContainerView.widthAnchor constraintEqualToConstant:maxCardWidth];
    cardWidthConstraint.priority = 999.0f;

    [NSLayoutConstraint activateConstraints:@[
        // Backdrop
        [self.backdropView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.backdropView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.backdropView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.backdropView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        // Dimming
        [self.dimmingView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.dimmingView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.dimmingView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.dimmingView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        // Dismiss trigger
        [dismissButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [dismissButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [dismissButton.topAnchor constraintEqualToAnchor:self.topAnchor],
        [dismissButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        // Card Container Position & Proportions
        self.cardCenterYConstraint,
        [self.cardContainerView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.cardContainerView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [self.cardContainerView.trailingAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
        cardWidthConstraint,

        // Contained Top Ambient Glow (Zero clipping artifacts)
        [self.cardInnerAuraView.centerXAnchor constraintEqualToAnchor:self.cardContainerView.centerXAnchor],
        [self.cardInnerAuraView.centerYAnchor constraintEqualToAnchor:self.cardContainerView.topAnchor constant:40.0],
        [self.cardInnerAuraView.widthAnchor constraintEqualToConstant:280.0],
        [self.cardInnerAuraView.heightAnchor constraintEqualToConstant:180.0],

        // Centered Badge View
        [self.badgeView.topAnchor constraintEqualToAnchor:self.cardContainerView.topAnchor constant:26.0],
        [self.badgeView.centerXAnchor constraintEqualToAnchor:self.cardContainerView.centerXAnchor],
        [self.badgeView.widthAnchor constraintEqualToConstant:56.0],
        [self.badgeView.heightAnchor constraintEqualToConstant:56.0],

        [self.iconView.centerXAnchor constraintEqualToAnchor:self.badgeView.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.badgeView.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:28.0],
        [self.iconView.heightAnchor constraintEqualToConstant:28.0],

        // Eyebrow Capsule
        [self.eyebrowCapsule.topAnchor constraintEqualToAnchor:self.badgeView.bottomAnchor constant:14.0],
        [self.eyebrowCapsule.centerXAnchor constraintEqualToAnchor:self.cardContainerView.centerXAnchor],
        [self.eyebrowCapsule.heightAnchor constraintEqualToConstant:22.0],

        [self.eyebrowLabel.leadingAnchor constraintEqualToAnchor:self.eyebrowCapsule.leadingAnchor constant:10.0],
        [self.eyebrowLabel.trailingAnchor constraintEqualToAnchor:self.eyebrowCapsule.trailingAnchor constant:-10.0],
        [self.eyebrowLabel.centerYAnchor constraintEqualToAnchor:self.eyebrowCapsule.centerYAnchor],

        // Title
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.eyebrowCapsule.bottomAnchor constant:10.0],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor constant:22.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor constant:-22.0],

        // Subtitle
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor constant:22.0],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor constant:-22.0],

        // Text Input
        [self.inputContainerView.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:16.0],
        [self.inputContainerView.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor constant:22.0],
        [self.inputContainerView.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor constant:-22.0],

        [self.textField.topAnchor constraintEqualToAnchor:self.inputContainerView.topAnchor constant:12.0],
        [self.textField.leadingAnchor constraintEqualToAnchor:self.inputContainerView.leadingAnchor constant:14.0],
        [self.textField.trailingAnchor constraintEqualToAnchor:self.inputContainerView.trailingAnchor constant:-14.0],
        [self.textField.bottomAnchor constraintEqualToAnchor:self.inputContainerView.bottomAnchor constant:-12.0],

        // Footnote
        [self.footnoteLabel.topAnchor constraintEqualToAnchor:self.inputContainerView.bottomAnchor constant:8.0],
        [self.footnoteLabel.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor constant:22.0],
        [self.footnoteLabel.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor constant:-22.0],

        // Action Buttons
        [self.buttonStackView.topAnchor constraintEqualToAnchor:(self.type == PPAlertTypeTextInput ? self.footnoteLabel.bottomAnchor : self.subtitleLabel.bottomAnchor) constant:22.0],
        [self.buttonStackView.leadingAnchor constraintEqualToAnchor:self.cardContainerView.leadingAnchor constant:20.0],
        [self.buttonStackView.trailingAnchor constraintEqualToAnchor:self.cardContainerView.trailingAnchor constant:-20.0],
        [self.buttonStackView.bottomAnchor constraintEqualToAnchor:self.cardContainerView.bottomAnchor constant:-22.0]
    ]];
}

- (void)applyStyling {
    self.badgeView.backgroundColor = self.appearance.badgeBackgroundColor;
    self.iconView.tintColor = self.appearance.badgeForegroundColor;
}

#pragma mark - Action Buttons & iPad Pointer Interactions

- (void)buildActions {
    self.buttonStackView.axis = (self.actionItems.count >= 3) ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.buttonStackView.spacing = 10.0;

    for (NSInteger idx = 0; idx < self.actionItems.count; idx += 1) {
        PPAlertActionItem *item = self.actionItems[idx];
        UIButton *button = [self actionButtonForItem:item];
        button.tag = idx;
        [button addTarget:self action:@selector(actionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.buttonStackView addArrangedSubview:button];
        [button.heightAnchor constraintEqualToConstant:50.0].active = YES;

        // iPad Pointer Hover Integration
        if (@available(iOS 13.4, *)) {
            UIPointerInteraction *pointer = [[UIPointerInteraction alloc] initWithDelegate:self];
            [button addInteraction:pointer];
        }
    }
}

- (UIButton *)actionButtonForItem:(PPAlertActionItem *)item {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 18.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.titleLabel.font = (item.style == PPAlertActionStylePrimary || item.style == PPAlertActionStyleDestructive) ? PPFontBold(16.0) : PPFontMedium(15.5);
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button setTitle:item.title forState:UIControlStateNormal];

    switch (item.style) {
        case PPAlertActionStylePrimary:
            button.backgroundColor = self.appearance.accentColor;
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.layer.shadowColor = self.appearance.accentColor.CGColor;
            button.layer.shadowOpacity = 0.28;
            button.layer.shadowRadius = 8.0;
            button.layer.shadowOffset = CGSizeMake(0.0, 4.0);
            break;

        case PPAlertActionStyleDestructive:
            button.backgroundColor = [UIColor ppError];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.layer.shadowColor = [UIColor ppError].CGColor;
            button.layer.shadowOpacity = 0.28;
            button.layer.shadowRadius = 8.0;
            button.layer.shadowOffset = CGSizeMake(0.0, 4.0);
            break;

        case PPAlertActionStyleCancel:
        case PPAlertActionStyleSecondary:
        default:
            button.backgroundColor = [AppBackgroundClr colorWithAlphaComponent:0.92];
            [button setTitleColor:PrimaryTextClr forState:UIControlStateNormal];
            button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
            button.layer.borderColor = [SeconderyTextClr colorWithAlphaComponent:0.12].CGColor;
            break;
    }

    return button;
}

#pragma mark - Hardware Keyboard Support (iPad & Simulators)

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands {
    return @[
        [UIKeyCommand keyCommandWithInput:@"\r"
                            modifierFlags:0
                                   action:@selector(pp_keyboardConfirmAction)],
        [UIKeyCommand keyCommandWithInput:UIKeyInputEscape
                            modifierFlags:0
                                   action:@selector(pp_keyboardCancelAction)]
    ];
}

- (void)pp_keyboardConfirmAction {
    for (NSInteger i = (NSInteger)self.actionItems.count - 1; i >= 0; i--) {
        PPAlertActionItem *item = self.actionItems[i];
        if (item.style == PPAlertActionStylePrimary || item.style == PPAlertActionStyleDestructive) {
            [self handleActionIndex:i];
            return;
        }
    }
}

- (void)pp_keyboardCancelAction {
    [self backgroundTapped];
}

#pragma mark - UIPointerInteractionDelegate (iPad)

- (nullable UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction
                               styleForRegion:(UIPointerRegion *)region API_AVAILABLE(ios(13.4)) {
    if ([interaction.view isKindOfClass:[UIButton class]]) {
        UITargetedPreview *preview = [[UITargetedPreview alloc] initWithView:interaction.view];
        return [UIPointerStyle styleWithEffect:[UIPointerHighlightEffect effectWithPreview:preview] shape:nil];
    }
    return nil;
}

#pragma mark - Keyboard Management

- (void)registerForKeyboard {
    if (self.type != PPAlertTypeTextInput) return;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;

    CGRect localFrame = [self convertRect:keyboardFrame fromView:nil];
    CGRect overlap = CGRectIntersection(self.bounds, localFrame);
    CGFloat keyboardHeight = CGRectIsNull(overlap) ? 0.0 : CGRectGetHeight(overlap);
    self.cardCenterYConstraint.constant = -keyboardHeight * 0.42;

    [UIView animateWithDuration:duration delay:0.0 options:curve animations:^{
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;

    self.cardCenterYConstraint.constant = 0.0;
    [UIView animateWithDuration:duration delay:0.0 options:curve animations:^{
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)textFieldDidChange:(UITextField *)textField {
    // Dynamic validation hook if needed
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self pp_keyboardConfirmAction];
    return YES;
}

#pragma mark - Presentation & Dismissal Lifecycle

- (void)preparePresentationState {
    if (self.didPreparePresentation) return;
    self.didPreparePresentation = YES;

    self.backdropView.alpha = 0.0;
    self.dimmingView.alpha = 0.0;
    self.cardContainerView.alpha = 0.0;

    if (!UIAccessibilityIsReduceMotionEnabled()) {
        self.cardContainerView.transform = CGAffineTransformMakeScale(0.92, 0.92);
    }
}

- (void)showInViewController:(UIViewController *)vc {
    UIWindow *window = vc.view.window ?: [UIApplication sharedApplication].keyWindow;
    if (!window) {
        window = [UIApplication sharedApplication].windows.firstObject;
    }
    if (!window) return;

    self.isPresentingAlert = YES;
    [window addSubview:self];
    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:window.leadingAnchor],
        [self.trailingAnchor constraintEqualToAnchor:window.trailingAnchor],
        [self.topAnchor constraintEqualToAnchor:window.topAnchor],
        [self.bottomAnchor constraintEqualToAnchor:window.bottomAnchor]
    ]];

    [self layoutIfNeeded];
    [self becomeFirstResponder];

    // Trigger Authentic Apple Semantic Haptic Feedback
    if (@available(iOS 10.0, *)) {
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        switch (self.type) {
            case PPAlertTypeSuccess:
                [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
                break;
            case PPAlertTypeError:
                [feedback notificationOccurred:UINotificationFeedbackTypeError];
                break;
            case PPAlertTypeWarning:
            case PPAlertTypeConfirmation:
                [feedback notificationOccurred:UINotificationFeedbackTypeWarning];
                break;
            default:
                break;
        }
    }

    // Spring Animation Presentation
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.18 animations:^{
            self.backdropView.alpha = 1.0;
            self.dimmingView.alpha = 1.0;
            self.cardContainerView.alpha = 1.0;
        } completion:^(BOOL finished) {
            if (self.type == PPAlertTypeTextInput) {
                [self.textField becomeFirstResponder];
            }
        }];
    } else {
        [UIView animateWithDuration:0.38
                              delay:0.0
             usingSpringWithDamping:0.82
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.backdropView.alpha = 1.0;
            self.dimmingView.alpha = 1.0;
            self.cardContainerView.alpha = 1.0;
            self.cardContainerView.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            if (self.type == PPAlertTypeTextInput) {
                [self.textField becomeFirstResponder];
            }
        }];
    }
}

- (void)dismissWithCompletion:(void(^ _Nullable)(void))completion {
    self.isPresentingAlert = NO;
    [self endEditing:YES];
    [self resignFirstResponder];

    if (UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.15 animations:^{
            self.backdropView.alpha = 0.0;
            self.dimmingView.alpha = 0.0;
            self.cardContainerView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self removeFromSuperview];
            if (completion) completion();
        }];
    } else {
        [UIView animateWithDuration:0.22
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            self.backdropView.alpha = 0.0;
            self.dimmingView.alpha = 0.0;
            self.cardContainerView.alpha = 0.0;
            self.cardContainerView.transform = CGAffineTransformMakeScale(0.94, 0.94);
        } completion:^(BOOL finished) {
            [self removeFromSuperview];
            if (completion) completion();
        }];
    }
}

- (void)backgroundTapped {
    if (!self.shouldDismissOnBackgroundTap) return;
    if (!self.isPresentingAlert) return;

    for (NSInteger idx = 0; idx < self.actionItems.count; idx += 1) {
        if (self.actionItems[idx].style == PPAlertActionStyleCancel) {
            [self handleActionIndex:idx];
            return;
        }
    }
    [self dismissWithCompletion:nil];
}

- (void)actionButtonTapped:(UIButton *)sender {
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [impact impactOccurred];
    }
    [self handleActionIndex:sender.tag];
}

- (void)handleActionIndex:(NSInteger)idx {
    if (!self.isPresentingAlert) return;
    self.isPresentingAlert = NO;
    if (idx < 0 || idx >= self.actionItems.count) return;
    PPAlertActionItem *item = self.actionItems[idx];
    NSString *inputText = PPAlertTrimmedText(self.textField.text);

    [self dismissWithCompletion:^{
        if (item.completion) {
            item.completion(inputText, (item.style != PPAlertActionStyleCancel));
        } else if (item.simpleCompletion) {
            item.simpleCompletion();
        }
    }];
}

@end

// MARK: - PPAlertHelper Facade Implementation

@implementation PPAlertHelper

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle {
    [self showSuccessIn:vc title:title subtitle:subtitle OKAction:nil];
}

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
             OKAction:(AlertCompletionBlock _Nullable)okAction {
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeSuccess
                                             title:title
                                          subtitle:subtitle
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:okAction
                                      cancelAction:nil];
    [alert showInViewController:vc];
}

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
        confirmAction:(AlertCompletionBlock _Nullable)confirmAction
         cancelAction:(void (^)(void))cancelAction {
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeSuccess
                                             title:title
                                          subtitle:subtitle
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:kLang(@"Cancel") ?: @"Cancel"
                                     confirmAction:confirmAction
                                      cancelAction:cancelAction];
    [alert showInViewController:vc];
}

+ (void)showFailIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion {
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeError
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion();
    } cancelAction:completion];
    [alert showInViewController:vc];
}

+ (void)showErrorIn:(UIViewController *)vc
              title:(NSString *)title
           subtitle:(NSString * _Nullable)subtitle {
    [self showFailIn:vc title:title subtitle:subtitle completion:nil];
}

+ (void)showWarningIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString * _Nullable)subtitle {
    [self showWarningIn:vc title:title subtitle:subtitle completion:nil];
}

+ (void)showWarningIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString * _Nullable)subtitle
           completion:(void (^ _Nullable)(void))completion {
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeWarning
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion();
    } cancelAction:completion];
    [alert showInViewController:vc];
}

+ (void)showInfoIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle {
    [self showInfoIn:vc title:title subtitle:subtitle completion:nil];
}

+ (void)showInfoIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion {
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeInfo
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion();
    } cancelAction:completion];
    [alert showInViewController:vc];
}

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString *)cancelTitle
                      icon:(UIImage * _Nullable)icon
               confirmBlock:(AlertCompletionBlock _Nullable)confirmBlock
                cancelBlock:(void(^ _Nullable)(void))cancelBlock {
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle
                                              icon:icon
                                      confirmTitle:confirmTitle
                                       cancelTitle:cancelTitle
                                     confirmAction:confirmBlock
                                      cancelAction:cancelBlock];
    [alert showInViewController:vc];
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
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle
                                              icon:icon
                                      confirmTitle:confirmTitle
                                       cancelTitle:cancelTitle
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (confirmBlock) confirmBlock();
    } cancelAction:cancelBlock];
    [alert showInViewController:vc];
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

    PPAlertActionStyle pStyle = (primaryStyle == UIAlertActionStyleDestructive) ? PPAlertActionStyleDestructive : PPAlertActionStylePrimary;
    PPAlertActionStyle sStyle = (secondaryStyle == UIAlertActionStyleDestructive) ? PPAlertActionStyleDestructive : PPAlertActionStyleSecondary;
    PPAlertActionStyle tStyle = (tertiaryStyle == UIAlertActionStyleCancel) ? PPAlertActionStyleCancel : PPAlertActionStyleSecondary;

    if (primaryTitle.length) {
        [actions addObject:[PPAlertActionItem itemWithTitle:primaryTitle style:pStyle completion:nil simpleCompletion:primaryBlock]];
    }
    if (secondaryTitle.length) {
        [actions addObject:[PPAlertActionItem itemWithTitle:secondaryTitle style:sStyle completion:nil simpleCompletion:secondaryBlock]];
    }
    if (tertiaryTitle.length) {
        [actions addObject:[PPAlertActionItem itemWithTitle:tertiaryTitle style:tStyle completion:nil simpleCompletion:tertiaryBlock]];
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                           actions:actions
                                       placeholder:nil
                                       initialText:nil
                                       secureEntry:NO
                                      keyboardType:UIKeyboardTypeDefault
                      shouldDismissOnBackgroundTap:(tStyle == PPAlertActionStyleCancel)];
    [alert showInViewController:vc];
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
        if (completion) completion(text, (text != nil));
    }];
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
    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];

    if (cancelText.length > 0) {
        [actions addObject:[PPAlertActionItem itemWithTitle:cancelText
                                                      style:PPAlertActionStyleCancel
                                                 completion:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
            if (completion) completion(nil);
        } simpleCompletion:nil]];
    }

    NSString *safeConfirmText = confirmText.length ? confirmText : (kLang(@"OK") ?: @"OK");
    [actions addObject:[PPAlertActionItem itemWithTitle:safeConfirmText
                                                  style:PPAlertActionStylePrimary
                                             completion:^(NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion(text);
    } simpleCompletion:nil]];

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeTextInput
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                           actions:actions
                                       placeholder:placeholder
                                       initialText:initialText
                                       secureEntry:secureEntry
                                      keyboardType:keyboardType
                      shouldDismissOnBackgroundTap:(cancelText.length > 0)];
    [alert showInViewController:vc];
}

@end
