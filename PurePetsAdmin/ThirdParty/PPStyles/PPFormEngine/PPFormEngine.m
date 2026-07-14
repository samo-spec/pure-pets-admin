//
//  PPFormEngine.m
//
//  Reusable UIKit form engine + pixel-perfect row UI.
//  No third-party dependencies.
//

#import "PPFormEngine.h"

static CGFloat PPFormPixel(void) {
    return 1.0 / UIScreen.mainScreen.scale;
}

static NSString *PPFormEngineLocalizedString(NSString *key, NSString *fallback) {
    if (key.length == 0) return fallback ?: @"";
    NSString *value = kLang(key);
    if (![value isKindOfClass:NSString.class] || value.length == 0 || [value isEqualToString:key]) {
        return fallback ?: @"";
    }
    return value;
}

static UISemanticContentAttribute PPFormEngineSemanticAttribute(void) {
    return Language.isRTL ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
}

static NSTextAlignment PPFormEngineTextAlignment(void) {
    return Language.isRTL ? NSTextAlignmentRight : NSTextAlignmentLeft;
}

@implementation PPFormStyle

+ (instancetype)defaultStyle {
    PPFormStyle *style = [[PPFormStyle alloc] init];

    style.cardBackgroundColor = UIColor.whiteColor;
    style.fieldBackgroundColor = [[UIColor colorWithWhite:0.96 alpha:1.0] colorWithAlphaComponent:0.42];
    style.accentColor = AppPrimaryClr;
    style.primaryTextColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    style.secondaryTextColor = [UIColor colorWithWhite:0.43 alpha:1.0];
    style.errorColor = UIColor.systemRedColor;
    style.cardBorderColor = [[UIColor colorWithWhite:0.43 alpha:1.0] colorWithAlphaComponent:0.075];
    style.fieldBorderColor = [UIColor.systemTealColor colorWithAlphaComponent:0.09];
    style.shadowColor = UIColor.blackColor;

    style.titleFont = [Styling fontBold:12.5];
    style.inputFont = [Styling fontMedium:12.5];
    style.placeholderFont = [Styling fontRegular:14];
    style.errorFont =  [Styling fontMedium:11.5];
    style.attachmentTitleFont = [Styling fontBold:12.5];
    style.attachmentSubtitleFont =  [Styling fontMedium:11.5];

    style.stackSpacing = 8.0;
    style.cardCornerRadius = 18.0;
    style.fieldCornerRadius = 16.0;
    style.attachmentThumbCornerRadius = 14.0;
    style.cardBorderWidth = PPFormPixel();
    style.fieldBorderWidth = PPFormPixel();
    style.shadowOpacity = 0.035;
    style.shadowRadius = 18.0;
    style.shadowOffset = CGSizeMake(0.0, 8.0);

    style.accentLeading = 14.0;
    style.accentTop = 16.0;
    style.accentWidth = 3.0;
    style.accentHeight = 22.0;
    style.titleLeadingFromAccent = 9.0;
    style.titleTrailing = 14.0;
    style.titleToFieldSpacing = 10.0;

    style.fieldLeading = 12.0;
    style.fieldTrailing = 12.0;
    style.fieldTopInset = 11.0;
    style.fieldHorizontalInset = 12.0;
    style.fieldBottomInset = 11.0;

    style.rowBottomInset = 12.0;
    style.errorTopSpacing = 6.0;
    style.attachmentDividerTopSpacing = 10.0;
    style.attachmentZoneTopSpacing = 8.0;
    style.attachmentZoneBottomInset = 10.0;

    style.minimumSingleLineFieldHeight = 46.0;
    style.minimumTextViewFieldHeight = 116.0;
    style.attachmentThumbSize = 44.0;

    return style;
}

- (id)copyWithZone:(NSZone *)zone {
    PPFormStyle *copy = [[[self class] allocWithZone:zone] init];
    copy.cardBackgroundColor = self.cardBackgroundColor;
    copy.fieldBackgroundColor = self.fieldBackgroundColor;
    copy.accentColor = self.accentColor;
    copy.primaryTextColor = self.primaryTextColor;
    copy.secondaryTextColor = self.secondaryTextColor;
    copy.errorColor = self.errorColor;
    copy.cardBorderColor = self.cardBorderColor;
    copy.fieldBorderColor = self.fieldBorderColor;
    copy.shadowColor = self.shadowColor;

    copy.titleFont = self.titleFont;
    copy.inputFont = self.inputFont;
    copy.placeholderFont = self.placeholderFont;
    copy.errorFont = self.errorFont;
    copy.attachmentTitleFont = self.attachmentTitleFont;
    copy.attachmentSubtitleFont = self.attachmentSubtitleFont;

    copy.stackSpacing = self.stackSpacing;
    copy.cardCornerRadius = self.cardCornerRadius;
    copy.fieldCornerRadius = self.fieldCornerRadius;
    copy.attachmentThumbCornerRadius = self.attachmentThumbCornerRadius;
    copy.cardBorderWidth = self.cardBorderWidth;
    copy.fieldBorderWidth = self.fieldBorderWidth;
    copy.shadowOpacity = self.shadowOpacity;
    copy.shadowRadius = self.shadowRadius;
    copy.shadowOffset = self.shadowOffset;

    copy.accentLeading = self.accentLeading;
    copy.accentTop = self.accentTop;
    copy.accentWidth = self.accentWidth;
    copy.accentHeight = self.accentHeight;
    copy.titleLeadingFromAccent = self.titleLeadingFromAccent;
    copy.titleTrailing = self.titleTrailing;
    copy.titleToFieldSpacing = self.titleToFieldSpacing;

    copy.fieldLeading = self.fieldLeading;
    copy.fieldTrailing = self.fieldTrailing;
    copy.fieldTopInset = self.fieldTopInset;
    copy.fieldHorizontalInset = self.fieldHorizontalInset;
    copy.fieldBottomInset = self.fieldBottomInset;

    copy.rowBottomInset = self.rowBottomInset;
    copy.errorTopSpacing = self.errorTopSpacing;
    copy.attachmentDividerTopSpacing = self.attachmentDividerTopSpacing;
    copy.attachmentZoneTopSpacing = self.attachmentZoneTopSpacing;
    copy.attachmentZoneBottomInset = self.attachmentZoneBottomInset;

    copy.minimumSingleLineFieldHeight = self.minimumSingleLineFieldHeight;
    copy.minimumTextViewFieldHeight = self.minimumTextViewFieldHeight;
    copy.attachmentThumbSize = self.attachmentThumbSize;
    return copy;
}

@end

@implementation PPFormFieldConfig

+ (instancetype)fieldWithIdentifier:(NSString *)identifier
                              title:(NSString *)title
                        placeholder:(NSString *)placeholder
                          inputType:(PPFormInputType)inputType {
    PPFormFieldConfig *config = [[PPFormFieldConfig alloc] init];
    config.identifier = identifier ?: @"";
    config.title = title ?: @"";
    config.placeholder = placeholder ?: @"";
    config.inputType = inputType;
    config.keyboardType = UIKeyboardTypeDefault;
    config.value = @"";
    config.required = NO;
    config.enabled = YES;
    config.hidden = NO;
    config.attachmentTitle = PPFormEngineLocalizedString(@"form_attachment_add_title", @"Attach document");
    config.attachmentSubtitle = PPFormEngineLocalizedString(@"form_attachment_add_subtitle", @"Upload from camera, photos, scan, or files");
    config.attachmentLoading = NO;
    config.attachmentRemoveHidden = YES;

    if (inputType == PPFormInputTypePhone) {
        config.keyboardType = UIKeyboardTypePhonePad;
    } else if (inputType == PPFormInputTypeNumber) {
        config.keyboardType = UIKeyboardTypeNumberPad;
    }

    return config;
}

- (id)copyWithZone:(NSZone *)zone {
    PPFormFieldConfig *copy = [[[self class] allocWithZone:zone] init];
    copy.identifier = self.identifier;
    copy.title = self.title;
    copy.placeholder = self.placeholder;
    copy.inputType = self.inputType;
    copy.keyboardType = self.keyboardType;
    copy.value = self.value;
    copy.required = self.required;
    copy.enabled = self.enabled;
    copy.hidden = self.hidden;
    copy.optionTitles = self.optionTitles;
    copy.optionValues = self.optionValues;
    copy.attachmentTitle = self.attachmentTitle;
    copy.attachmentSubtitle = self.attachmentSubtitle;
    copy.attachmentImage = self.attachmentImage;
    copy.attachmentLoading = self.attachmentLoading;
    copy.attachmentRemoveHidden = self.attachmentRemoveHidden;
    copy.validationBlock = self.validationBlock;
    copy.textChangeBlock = self.textChangeBlock;
    copy.pickerTapBlock = self.pickerTapBlock;
    copy.attachmentTapBlock = self.attachmentTapBlock;
    copy.attachmentRemoveBlock = self.attachmentRemoveBlock;
    return copy;
}

@end

@interface PPFormFieldRowView ()
@property (nonatomic, assign, readwrite) PPFormInputType inputType;
@property (nonatomic, strong, readwrite) UILabel *titleLabel;
@property (nonatomic, strong, readwrite, nullable) UITextField *textField;
@property (nonatomic, strong, readwrite, nullable) UITextView *textView;
@property (nonatomic, strong, readwrite, nullable) UIButton *pickerButton;
@property (nonatomic, strong, readwrite, nullable) UISwitch *toggleSwitch;
@property (nonatomic, strong, readwrite, nullable) UISegmentedControl *segmentedControl;
@property (nonatomic, strong, readwrite, nullable) UIStackView *attachmentZone;
@property (nonatomic, strong, readwrite, nullable) UIImageView *attachmentImageView;
@property (nonatomic, strong, readwrite, nullable) UILabel *attachmentTitleLabel;
@property (nonatomic, strong, readwrite, nullable) UILabel *attachmentSubtitleLabel;
@property (nonatomic, strong, readwrite, nullable) UIActivityIndicatorView *attachmentActivityView;
@property (nonatomic, strong, readwrite, nullable) UIButton *attachmentRemoveButton;

@property (nonatomic, strong) PPFormStyle *style;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *fieldSurface;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIImageView *pickerIconView;
@property (nonatomic, strong) UILabel *textViewPlaceholderLabel;
@property (nonatomic, strong) UIView *accentView;
@property (nonatomic, strong) UIView *inputContentView;
@property (nonatomic, strong) PPFormFieldConfig *config;
@property (nonatomic, assign) BOOL enabled;
@end

@implementation PPFormFieldRowView

@synthesize enabled = _enabled;

- (instancetype)initWithConfig:(PPFormFieldConfig *)config style:(PPFormStyle *)style {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _config = [config copy];
        _inputType = config.inputType;
        _style = [style ?: [PPFormStyle defaultStyle] copy];

        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.semanticContentAttribute = PPFormEngineSemanticAttribute();

        [self pp_build];
        [self applyConfig:config];
    }
    return self;
}

- (void)pp_build {
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.semanticContentAttribute = PPFormEngineSemanticAttribute();
    self.cardView.backgroundColor = self.style.cardBackgroundColor;
    self.cardView.layer.cornerRadius = self.style.cardCornerRadius;
    if (@available(iOS 13.0, *)) self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardView.layer.borderWidth = self.style.cardBorderWidth;
    self.cardView.layer.borderColor = self.style.cardBorderColor.CGColor;
    self.cardView.layer.shadowColor = self.style.shadowColor.CGColor;
    self.cardView.layer.shadowOffset = self.style.shadowOffset;
    self.cardView.layer.shadowRadius = self.style.shadowRadius;
    self.cardView.layer.shadowOpacity = self.style.shadowOpacity;
    [self addSubview:self.cardView];

    self.accentView = [[UIView alloc] init];
    self.accentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.accentView.backgroundColor = [self.style.accentColor colorWithAlphaComponent:0.72];
    self.accentView.layer.cornerRadius = 1.5;
    if (@available(iOS 13.0, *)) self.accentView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.cardView addSubview:self.accentView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = self.style.titleFont;
    self.titleLabel.textColor = [self.style.primaryTextColor colorWithAlphaComponent:0.82];
    self.titleLabel.semanticContentAttribute = PPFormEngineSemanticAttribute();
    self.titleLabel.textAlignment = PPFormEngineTextAlignment();
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.88;
    [self.cardView addSubview:self.titleLabel];

    self.fieldSurface = [[UIView alloc] init];
    self.fieldSurface.translatesAutoresizingMaskIntoConstraints = NO;
    self.fieldSurface.semanticContentAttribute = PPFormEngineSemanticAttribute();
    self.fieldSurface.backgroundColor = self.style.fieldBackgroundColor;
    self.fieldSurface.layer.cornerRadius = self.style.fieldCornerRadius;
    if (@available(iOS 13.0, *)) self.fieldSurface.layer.cornerCurve = kCACornerCurveContinuous;
    self.fieldSurface.layer.borderWidth = self.style.fieldBorderWidth;
    self.fieldSurface.layer.borderColor = self.style.fieldBorderColor.CGColor;
    [self.cardView addSubview:self.fieldSurface];

    self.inputContentView = [self pp_makeInputView];
    [self.fieldSurface addSubview:self.inputContentView];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = self.style.errorFont;
    self.errorLabel.textColor = self.style.errorColor;
    self.errorLabel.semanticContentAttribute = PPFormEngineSemanticAttribute();
    self.errorLabel.textAlignment = PPFormEngineTextAlignment();
    self.errorLabel.numberOfLines = 2;
    self.errorLabel.hidden = YES;
    [self.cardView addSubview:self.errorLabel];

    CGFloat minimumFieldHeight = self.inputType == PPFormInputTypeTextView ? self.style.minimumTextViewFieldHeight : self.style.minimumSingleLineFieldHeight;
    BOOL compactToggleRow = (self.inputType == PPFormInputTypeToggle);
    BOOL compactSegmentedRow = (self.inputType == PPFormInputTypeSegmented && self.config.title.length == 0);

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [self.cardView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    if (compactToggleRow) {
        self.fieldSurface.backgroundColor = UIColor.clearColor;
        self.fieldSurface.layer.borderWidth = 0.0;

        [constraints addObjectsFromArray:@[
            [self.accentView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:14.0],
            [self.accentView.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
            [self.accentView.widthAnchor constraintEqualToConstant:4.0],
            [self.accentView.heightAnchor constraintEqualToConstant:30.0],

            [self.titleLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:16.0],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.accentView.trailingAnchor constant:12.0],
            [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-16.0],

            [self.fieldSurface.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.titleLabel.trailingAnchor constant:14.0],
            [self.fieldSurface.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16.0],
            [self.fieldSurface.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
            [self.fieldSurface.widthAnchor constraintGreaterThanOrEqualToConstant:51.0],
            [self.fieldSurface.heightAnchor constraintGreaterThanOrEqualToConstant:31.0],

            [self.inputContentView.topAnchor constraintEqualToAnchor:self.fieldSurface.topAnchor],
            [self.inputContentView.leadingAnchor constraintEqualToAnchor:self.fieldSurface.leadingAnchor],
            [self.inputContentView.trailingAnchor constraintEqualToAnchor:self.fieldSurface.trailingAnchor],
            [self.inputContentView.bottomAnchor constraintEqualToAnchor:self.fieldSurface.bottomAnchor],

            [self.errorLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
            [self.errorLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.errorLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16.0],
            [self.errorLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.cardView.bottomAnchor constant:-10.0],
        ]];
    } else if (compactSegmentedRow) {
        self.accentView.hidden = YES;
        self.titleLabel.hidden = YES;

        [constraints addObjectsFromArray:@[
            [self.fieldSurface.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:12.0],
            [self.fieldSurface.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:12.0],
            [self.fieldSurface.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-12.0],
            [self.fieldSurface.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-12.0],
            [self.fieldSurface.heightAnchor constraintGreaterThanOrEqualToConstant:50.0],

            [self.inputContentView.topAnchor constraintEqualToAnchor:self.fieldSurface.topAnchor],
            [self.inputContentView.leadingAnchor constraintEqualToAnchor:self.fieldSurface.leadingAnchor],
            [self.inputContentView.trailingAnchor constraintEqualToAnchor:self.fieldSurface.trailingAnchor],
            [self.inputContentView.bottomAnchor constraintEqualToAnchor:self.fieldSurface.bottomAnchor],

            [self.errorLabel.topAnchor constraintEqualToAnchor:self.fieldSurface.bottomAnchor constant:self.style.errorTopSpacing],
            [self.errorLabel.leadingAnchor constraintEqualToAnchor:self.fieldSurface.leadingAnchor],
            [self.errorLabel.trailingAnchor constraintEqualToAnchor:self.fieldSurface.trailingAnchor],
        ]];
    } else {
        [constraints addObjectsFromArray:@[
            [self.accentView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:self.style.accentLeading],
            [self.accentView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:self.style.accentTop],
            [self.accentView.widthAnchor constraintEqualToConstant:self.style.accentWidth],
            [self.accentView.heightAnchor constraintEqualToConstant:self.style.accentHeight],

            [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.accentView.centerYAnchor],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.accentView.trailingAnchor constant:self.style.titleLeadingFromAccent],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-self.style.titleTrailing],

            [self.fieldSurface.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:self.style.titleToFieldSpacing],
            [self.fieldSurface.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:self.style.fieldLeading],
            [self.fieldSurface.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-self.style.fieldTrailing],
            [self.fieldSurface.heightAnchor constraintGreaterThanOrEqualToConstant:minimumFieldHeight],

            [self.inputContentView.topAnchor constraintEqualToAnchor:self.fieldSurface.topAnchor constant:self.style.fieldTopInset],
            [self.inputContentView.leadingAnchor constraintEqualToAnchor:self.fieldSurface.leadingAnchor constant:self.style.fieldHorizontalInset],
            [self.inputContentView.trailingAnchor constraintEqualToAnchor:self.fieldSurface.trailingAnchor constant:-self.style.fieldHorizontalInset],
            [self.inputContentView.bottomAnchor constraintEqualToAnchor:self.fieldSurface.bottomAnchor constant:-self.style.fieldBottomInset],

            [self.errorLabel.topAnchor constraintEqualToAnchor:self.fieldSurface.bottomAnchor constant:self.style.errorTopSpacing],
            [self.errorLabel.leadingAnchor constraintEqualToAnchor:self.fieldSurface.leadingAnchor],
            [self.errorLabel.trailingAnchor constraintEqualToAnchor:self.fieldSurface.trailingAnchor],
        ]];
    }

    if (self.inputType == PPFormInputTypeAttachment) {
        UIView *divider = [[UIView alloc] init];
        divider.translatesAutoresizingMaskIntoConstraints = NO;
        divider.backgroundColor = [self.style.accentColor colorWithAlphaComponent:0.08];
        [self.cardView addSubview:divider];

        self.attachmentZone = [self pp_makeAttachmentZone];
        [self.cardView addSubview:self.attachmentZone];

        [constraints addObjectsFromArray:@[
            [divider.topAnchor constraintEqualToAnchor:self.errorLabel.bottomAnchor constant:self.style.attachmentDividerTopSpacing],
            [divider.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:14.0],
            [divider.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-14.0],
            [divider.heightAnchor constraintEqualToConstant:PPFormPixel()],

            [self.attachmentZone.topAnchor constraintEqualToAnchor:divider.bottomAnchor constant:self.style.attachmentZoneTopSpacing],
            [self.attachmentZone.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:14.0],
            [self.attachmentZone.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-14.0],
            [self.attachmentZone.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-self.style.attachmentZoneBottomInset],
        ]];
    } else {
        [constraints addObject:[self.errorLabel.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-self.style.rowBottomInset]];
    }

    [NSLayoutConstraint activateConstraints:constraints];
}

- (UIView *)pp_makeInputView {
    if (self.inputType == PPFormInputTypeTextView) {
        self.textView = [[UITextView alloc] init];
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        self.textView.backgroundColor = UIColor.clearColor;
        self.textView.textColor = self.style.primaryTextColor;
        self.textView.font = self.style.inputFont;
        self.textView.delegate = self;
        self.textView.semanticContentAttribute = PPFormEngineSemanticAttribute();
        self.textView.textAlignment = PPFormEngineTextAlignment();
        self.textView.textContainerInset = UIEdgeInsetsZero;
        self.textView.textContainer.lineFragmentPadding = 0.0;

        self.textViewPlaceholderLabel = [[UILabel alloc] init];
        self.textViewPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.textViewPlaceholderLabel.font = self.style.placeholderFont;
        self.textViewPlaceholderLabel.textColor = [self.style.secondaryTextColor colorWithAlphaComponent:0.66];
        self.textViewPlaceholderLabel.semanticContentAttribute = PPFormEngineSemanticAttribute();
        self.textViewPlaceholderLabel.textAlignment = PPFormEngineTextAlignment();
        self.textViewPlaceholderLabel.numberOfLines = 0;
        [self.textView addSubview:self.textViewPlaceholderLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.textViewPlaceholderLabel.topAnchor constraintEqualToAnchor:self.textView.topAnchor],
            [self.textViewPlaceholderLabel.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor],
            [self.textViewPlaceholderLabel.trailingAnchor constraintEqualToAnchor:self.textView.trailingAnchor]
        ]];
        return self.textView;
    }

    if (self.inputType == PPFormInputTypeToggle) {
        UIView *container = [[UIView alloc] init];
        container.translatesAutoresizingMaskIntoConstraints = NO;

        self.toggleSwitch = [[UISwitch alloc] init];
        self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        self.toggleSwitch.onTintColor = self.style.accentColor;
        [self.toggleSwitch addTarget:self action:@selector(pp_toggleValueChanged:) forControlEvents:UIControlEventValueChanged];
        [container addSubview:self.toggleSwitch];

        [NSLayoutConstraint activateConstraints:@[
            [self.toggleSwitch.topAnchor constraintEqualToAnchor:container.topAnchor],
            [self.toggleSwitch.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [self.toggleSwitch.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        ]];
        return container;
    }

    if (self.inputType == PPFormInputTypeSegmented) {
        self.segmentedControl = [[UISegmentedControl alloc] initWithItems:self.config.optionTitles ?: @[]];
        self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
        self.segmentedControl.selectedSegmentTintColor = self.style.accentColor;
        self.segmentedControl.backgroundColor = [self.style.accentColor colorWithAlphaComponent:0.08];
        self.segmentedControl.layer.cornerRadius = self.style.fieldCornerRadius;
        if (@available(iOS 13.0, *)) self.segmentedControl.layer.cornerCurve = kCACornerCurveContinuous;
        self.segmentedControl.layer.borderWidth = self.style.fieldBorderWidth;
        self.segmentedControl.layer.borderColor = [self.style.accentColor colorWithAlphaComponent:0.12].CGColor;
        [self.segmentedControl addTarget:self action:@selector(pp_segmentedValueChanged:) forControlEvents:UIControlEventValueChanged];
        NSDictionary *normalAttributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: self.style.primaryTextColor
        };
        NSDictionary *selectedAttributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: UIColor.whiteColor
        };
        [self.segmentedControl setTitleTextAttributes:normalAttributes forState:UIControlStateNormal];
        [self.segmentedControl setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
        return self.segmentedControl;
    }

    self.textField = [[UITextField alloc] init];
    self.textField.translatesAutoresizingMaskIntoConstraints = NO;
    self.textField.backgroundColor = UIColor.clearColor;
    self.textField.textColor = self.style.primaryTextColor;
    self.textField.tintColor = self.style.accentColor;
    self.textField.font = self.style.inputFont;
    self.textField.semanticContentAttribute = PPFormEngineSemanticAttribute();
    self.textField.textAlignment = PPFormEngineTextAlignment();
    self.textField.delegate = self;
    [self.textField addTarget:self action:@selector(pp_textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    if (self.inputType == PPFormInputTypePicker) {
        self.textField.enabled = NO;
        self.textField.tintColor = UIColor.clearColor;

        self.pickerButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.pickerButton.translatesAutoresizingMaskIntoConstraints = NO;
        self.pickerButton.backgroundColor = UIColor.clearColor;
        self.pickerButton.semanticContentAttribute = PPFormEngineSemanticAttribute();
        [self.pickerButton addTarget:self action:@selector(pp_pickerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.fieldSurface addSubview:self.pickerButton];

        UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightSemibold];
        self.pickerIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:iconConfig]];
        self.pickerIconView.translatesAutoresizingMaskIntoConstraints = NO;
        self.pickerIconView.tintColor = [self.style.secondaryTextColor colorWithAlphaComponent:0.86];
        [self.fieldSurface addSubview:self.pickerIconView];

        [NSLayoutConstraint activateConstraints:@[
            [self.pickerButton.topAnchor constraintEqualToAnchor:self.fieldSurface.topAnchor],
            [self.pickerButton.leadingAnchor constraintEqualToAnchor:self.fieldSurface.leadingAnchor],
            [self.pickerButton.trailingAnchor constraintEqualToAnchor:self.fieldSurface.trailingAnchor],
            [self.pickerButton.bottomAnchor constraintEqualToAnchor:self.fieldSurface.bottomAnchor],

            [self.pickerIconView.centerYAnchor constraintEqualToAnchor:self.fieldSurface.centerYAnchor],
            [self.pickerIconView.trailingAnchor constraintEqualToAnchor:self.fieldSurface.trailingAnchor constant:-12.0],
        ]];
    }

    return self.textField;
}

- (UIStackView *)pp_makeAttachmentZone {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10.0;
    stack.distribution = UIStackViewDistributionFill;
    stack.userInteractionEnabled = YES;

    self.attachmentImageView = [[UIImageView alloc] init];
    self.attachmentImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentImageView.contentMode = UIViewContentModeCenter;
    self.attachmentImageView.clipsToBounds = YES;
    self.attachmentImageView.backgroundColor = [self.style.fieldBackgroundColor colorWithAlphaComponent:0.64];
    self.attachmentImageView.tintColor = self.style.accentColor;
    self.attachmentImageView.layer.cornerRadius = self.style.attachmentThumbCornerRadius;
    if (@available(iOS 13.0, *)) self.attachmentImageView.layer.cornerCurve = kCACornerCurveContinuous;
    self.attachmentImageView.image = [UIImage systemImageNamed:@"doc.badge.plus"];
    [stack addArrangedSubview:self.attachmentImageView];
    [self.attachmentImageView.widthAnchor constraintEqualToConstant:self.style.attachmentThumbSize].active = YES;
    [self.attachmentImageView.heightAnchor constraintEqualToConstant:self.style.attachmentThumbSize].active = YES;

    UIStackView *textStack = [[UIStackView alloc] init];
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 3.0;
    textStack.alignment = UIStackViewAlignmentFill;
    [stack addArrangedSubview:textStack];

    self.attachmentTitleLabel = [[UILabel alloc] init];
    self.attachmentTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentTitleLabel.font = self.style.attachmentTitleFont;
    self.attachmentTitleLabel.textColor = self.style.primaryTextColor;
    self.attachmentTitleLabel.textAlignment = NSTextAlignmentNatural;
    self.attachmentTitleLabel.numberOfLines = 1;
    [textStack addArrangedSubview:self.attachmentTitleLabel];

    self.attachmentSubtitleLabel = [[UILabel alloc] init];
    self.attachmentSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentSubtitleLabel.font = self.style.attachmentSubtitleFont;
    self.attachmentSubtitleLabel.textColor = [self.style.secondaryTextColor colorWithAlphaComponent:0.82];
    self.attachmentSubtitleLabel.textAlignment = NSTextAlignmentNatural;
    self.attachmentSubtitleLabel.numberOfLines = 2;
    [textStack addArrangedSubview:self.attachmentSubtitleLabel];

    self.attachmentActivityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.attachmentActivityView.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentActivityView.hidesWhenStopped = YES;
    [stack addArrangedSubview:self.attachmentActivityView];

    self.attachmentRemoveButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.attachmentRemoveButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.attachmentRemoveButton.hidden = YES;
    [self.attachmentRemoveButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.attachmentRemoveButton.tintColor = [UIColor.systemRedColor colorWithAlphaComponent:0.72];
    [self.attachmentRemoveButton addTarget:self action:@selector(pp_removeAttachmentTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.attachmentRemoveButton];
    [self.attachmentRemoveButton.widthAnchor constraintEqualToConstant:28.0].active = YES;
    [self.attachmentRemoveButton.heightAnchor constraintEqualToConstant:28.0].active = YES;

    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightSemibold];
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:iconConfig]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = [self.style.secondaryTextColor colorWithAlphaComponent:0.72];
    [stack addArrangedSubview:chevron];
    [chevron.widthAnchor constraintEqualToConstant:14.0].active = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pp_attachmentTapped)];
    [stack addGestureRecognizer:tap];

    return stack;
}

- (void)applyConfig:(PPFormFieldConfig *)config {
    self.config = [config copy];
    self.titleLabel.text = config.title ?: @"";

    UIColor *placeholderColor = [self.style.secondaryTextColor colorWithAlphaComponent:0.66];
    NSAttributedString *attributedPlaceholder = [[NSAttributedString alloc] initWithString:config.placeholder ?: @""
                                                                                 attributes:@{
        NSFontAttributeName: self.style.placeholderFont,
        NSForegroundColorAttributeName: placeholderColor
    }];

    if (self.textField) {
        self.textField.attributedPlaceholder = attributedPlaceholder;
        self.textField.keyboardType = config.keyboardType;
        self.textField.text = config.value ?: @"";
        self.textField.enabled = config.enabled && config.inputType != PPFormInputTypePicker;
    }

    if (self.toggleSwitch) {
        self.toggleSwitch.on = [config.value boolValue];
        self.toggleSwitch.enabled = config.enabled;
    }

    if (self.segmentedControl) {
        [self.segmentedControl removeAllSegments];
        NSArray<NSString *> *titles = config.optionTitles ?: @[];
        [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
            (void)stop;
            [self.segmentedControl insertSegmentWithTitle:title ?: @"" atIndex:idx animated:NO];
        }];
        self.segmentedControl.enabled = config.enabled;
        self.segmentedControl.selectedSegmentIndex = [self pp_selectedIndexForValue:config.value config:config];
    }

    if (self.textView) {
        self.textView.keyboardType = config.keyboardType;
        self.textView.text = config.value ?: @"";
        self.textView.editable = config.enabled;
        self.textViewPlaceholderLabel.text = config.placeholder ?: @"";
        self.textViewPlaceholderLabel.hidden = self.textView.text.length > 0;
    }

    self.enabled = config.enabled;
    self.hidden = config.hidden;
    self.alpha = config.enabled ? 1.0 : 0.55;

    [self setAttachmentTitle:config.attachmentTitle
                    subtitle:config.attachmentSubtitle
                       image:config.attachmentImage
                     loading:config.attachmentLoading
          removeButtonHidden:config.attachmentRemoveHidden];

    [self clearError];
}

- (NSString *)value {
    if (self.toggleSwitch) return self.toggleSwitch.isOn ? @"1" : @"0";
    if (self.segmentedControl) {
        NSInteger selectedIndex = self.segmentedControl.selectedSegmentIndex;
        NSArray<NSString *> *values = self.config.optionValues ?: self.config.optionTitles ?: @[];
        if (selectedIndex >= 0 && selectedIndex < (NSInteger)values.count) {
            return values[(NSUInteger)selectedIndex] ?: @"";
        }
        return @"";
    }
    if (self.textView) return self.textView.text ?: @"";
    return self.textField.text ?: @"";
}

- (void)setValue:(NSString *)value {
    NSString *safeValue = value ?: @"";
    self.textField.text = safeValue;
    self.textView.text = safeValue;
    self.textViewPlaceholderLabel.hidden = safeValue.length > 0;
    if (self.toggleSwitch) {
        self.toggleSwitch.on = [safeValue boolValue];
    }
    if (self.segmentedControl) {
        self.segmentedControl.selectedSegmentIndex = [self pp_selectedIndexForValue:safeValue config:self.config];
    }
}

- (void)setErrorText:(NSString *)errorText {
    NSString *safeError = errorText ?: @"";
    self.errorLabel.text = safeError;
    self.errorLabel.hidden = safeError.length == 0;
    self.fieldSurface.layer.borderColor = safeError.length > 0
        ? [self.style.errorColor colorWithAlphaComponent:0.42].CGColor
        : self.style.fieldBorderColor.CGColor;
}

- (void)clearError {
    [self setErrorText:nil];
}

- (void)setAttachmentTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                     image:(UIImage *)image
                   loading:(BOOL)loading
        removeButtonHidden:(BOOL)removeButtonHidden {
    self.attachmentTitleLabel.text = title ?: @"";
    self.attachmentSubtitleLabel.text = subtitle ?: @"";
    self.attachmentRemoveButton.hidden = removeButtonHidden;

    if (image) {
        self.attachmentImageView.image = image;
        self.attachmentImageView.contentMode = UIViewContentModeScaleAspectFill;
    } else {
        self.attachmentImageView.image = [UIImage systemImageNamed:@"doc.badge.plus"];
        self.attachmentImageView.contentMode = UIViewContentModeCenter;
    }

    if (loading) {
        [self.attachmentActivityView startAnimating];
    } else {
        [self.attachmentActivityView stopAnimating];
    }
}

- (void)setAttachmentRemoveButtonHidden:(BOOL)hidden {
    self.attachmentRemoveButton.hidden = hidden;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    self.userInteractionEnabled = enabled;
    self.alpha = enabled ? 1.0 : 0.55;
    self.textField.enabled = enabled && self.inputType != PPFormInputTypePicker;
    self.textView.editable = enabled;
    self.pickerButton.enabled = enabled;
    self.toggleSwitch.enabled = enabled;
    self.segmentedControl.enabled = enabled;
}

- (void)pp_textFieldDidChange:(UITextField *)textField {
    if (self.textChangeHandler) self.textChangeHandler(self, textField.text ?: @"");
}

- (void)pp_pickerTapped {
    if (self.pickerTapHandler) self.pickerTapHandler(self);
}

- (void)pp_toggleValueChanged:(UISwitch *)sender {
    if (self.textChangeHandler) self.textChangeHandler(self, sender.isOn ? @"1" : @"0");
}

- (void)pp_segmentedValueChanged:(UISegmentedControl *)sender {
    (void)sender;
    if (self.textChangeHandler) self.textChangeHandler(self, [self value]);
}

- (void)pp_attachmentTapped {
    if (self.attachmentTapHandler) self.attachmentTapHandler(self);
}

- (void)pp_removeAttachmentTapped {
    if (self.attachmentRemoveTapHandler) self.attachmentRemoveTapHandler(self);
}

- (NSInteger)pp_selectedIndexForValue:(NSString *)value config:(PPFormFieldConfig *)config {
    NSArray<NSString *> *values = config.optionValues ?: config.optionTitles ?: @[];
    NSUInteger index = [values indexOfObject:value ?: @""];
    if (index != NSNotFound) {
        return (NSInteger)index;
    }
    if (values.count > 0 && (value ?: @"").length == 0) {
        return 0;
    }
    return UISegmentedControlNoSegment;
}

- (void)textViewDidChange:(UITextView *)textView {
    self.textViewPlaceholderLabel.hidden = textView.text.length > 0;
    if ([self.externalTextViewDelegate respondsToSelector:@selector(textViewDidChange:)]) {
        [self.externalTextViewDelegate textViewDidChange:textView];
    }
    if (self.textChangeHandler) self.textChangeHandler(self, textView.text ?: @"");
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if ([self.externalTextFieldDelegate respondsToSelector:@selector(textFieldShouldBeginEditing:)]) {
        return [self.externalTextFieldDelegate textFieldShouldBeginEditing:textField];
    }
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if ([self.externalTextFieldDelegate respondsToSelector:@selector(textFieldDidBeginEditing:)]) {
        [self.externalTextFieldDelegate textFieldDidBeginEditing:textField];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if ([self.externalTextFieldDelegate respondsToSelector:@selector(textFieldDidEndEditing:)]) {
        [self.externalTextFieldDelegate textFieldDidEndEditing:textField];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([self.externalTextFieldDelegate respondsToSelector:@selector(textFieldShouldReturn:)]) {
        return [self.externalTextFieldDelegate textFieldShouldReturn:textField];
    }
    [textField resignFirstResponder];
    return YES;
}

@end

@interface PPFormEngineView ()
@property (nonatomic, strong, readwrite) UIStackView *stackView;
@property (nonatomic, strong, readwrite) NSArray<PPFormFieldConfig *> *fields;
@property (nonatomic, strong, readwrite) NSDictionary<NSString *, PPFormFieldRowView *> *rowsByIdentifier;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *errorsByIdentifier;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PPFormFieldConfig *> *mutableConfigsByIdentifier;
@end

@implementation PPFormEngineView

- (instancetype)initWithStyle:(PPFormStyle *)style {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _style = [style ?: [PPFormStyle defaultStyle] copy];
        _fields = @[];
        _rowsByIdentifier = @{};
        _errorsByIdentifier = [NSMutableDictionary dictionary];
        _mutableConfigsByIdentifier = [NSMutableDictionary dictionary];
        _validatesOnChange = NO;

        self.translatesAutoresizingMaskIntoConstraints = NO;

        self.stackView = [[UIStackView alloc] init];
        self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
        self.stackView.axis = UILayoutConstraintAxisVertical;
        self.stackView.spacing = self.style.stackSpacing;
        self.stackView.alignment = UIStackViewAlignmentFill;
        self.stackView.distribution = UIStackViewDistributionFill;
        [self addSubview:self.stackView];

        [NSLayoutConstraint activateConstraints:@[
            [self.stackView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)setFields:(NSArray<PPFormFieldConfig *> *)fields {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setFields:fields];
        });
        return;
    }

    for (UIView *view in self.stackView.arrangedSubviews.copy) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSMutableArray<PPFormFieldConfig *> *copiedFields = [NSMutableArray array];
    NSMutableDictionary<NSString *, PPFormFieldRowView *> *rows = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, PPFormFieldConfig *> *configs = [NSMutableDictionary dictionary];

    __weak typeof(self) weakSelf = self;

    for (PPFormFieldConfig *field in fields ?: @[]) {
        PPFormFieldConfig *config = [field copy];
        if (config.identifier.length == 0) continue;

        PPFormFieldRowView *row = [[PPFormFieldRowView alloc] initWithConfig:config style:self.style];
        if (!row) continue;

        row.textChangeHandler = ^(PPFormFieldRowView *rowView, NSString *value) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            PPFormFieldConfig *liveConfig = self.mutableConfigsByIdentifier[config.identifier];
            if (!liveConfig) return;
            liveConfig.value = value ?: @"";
            if (self.validatesOnChange) {
                [self validate];
            }
            if (liveConfig.textChangeBlock) {
                liveConfig.textChangeBlock(liveConfig, value ?: @"");
            }
        };

        row.pickerTapHandler = ^(PPFormFieldRowView *rowView) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            PPFormFieldConfig *liveConfig = self.mutableConfigsByIdentifier[config.identifier];
            if (!liveConfig) return;
            if (liveConfig.pickerTapBlock) {
                liveConfig.pickerTapBlock(liveConfig, rowView);
            }
        };

        row.attachmentTapHandler = ^(PPFormFieldRowView *rowView) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            PPFormFieldConfig *liveConfig = self.mutableConfigsByIdentifier[config.identifier];
            if (!liveConfig) return;
            if (liveConfig.attachmentTapBlock) {
                liveConfig.attachmentTapBlock(liveConfig, rowView);
            }
        };

        row.attachmentRemoveTapHandler = ^(PPFormFieldRowView *rowView) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            PPFormFieldConfig *liveConfig = self.mutableConfigsByIdentifier[config.identifier];
            if (!liveConfig) return;
            if (liveConfig.attachmentRemoveBlock) {
                liveConfig.attachmentRemoveBlock(liveConfig, rowView);
            }
        };

        [self.stackView addArrangedSubview:row];

        [copiedFields addObject:config];
        rows[config.identifier] = row;
        configs[config.identifier] = config;
    }

    _fields = copiedFields.copy;
    _rowsByIdentifier = rows.copy;
    _mutableConfigsByIdentifier = configs.mutableCopy;
    [self.errorsByIdentifier removeAllObjects];
}

- (PPFormFieldRowView *)rowForIdentifier:(NSString *)identifier {
    return self.rowsByIdentifier[identifier ?: @""];
}

- (PPFormFieldConfig *)configForIdentifier:(NSString *)identifier {
    return self.mutableConfigsByIdentifier[identifier ?: @""];
}

- (NSString *)valueForIdentifier:(NSString *)identifier {
    PPFormFieldRowView *row = [self rowForIdentifier:identifier];
    return [row value] ?: @"";
}

- (void)setValue:(NSString *)value forIdentifier:(NSString *)identifier {
    PPFormFieldConfig *config = [self configForIdentifier:identifier];
    PPFormFieldRowView *row = [self rowForIdentifier:identifier];
    if (!config || !row) return;
    config.value = value ?: @"";
    [row setValue:value ?: @""];
}

- (NSDictionary<NSString *,NSString *> *)values {
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    for (PPFormFieldConfig *config in self.fields) {
        values[config.identifier] = [self valueForIdentifier:config.identifier] ?: @"";
    }
    return values.copy;
}

- (void)setValues:(NSDictionary<NSString *,NSString *> *)values {
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
        (void)stop;
        [self setValue:obj forIdentifier:key];
    }];
}

- (BOOL)validate {
    [self.errorsByIdentifier removeAllObjects];

    for (PPFormFieldConfig *config in self.fields) {
        if (config.hidden) {
            [[self rowForIdentifier:config.identifier] clearError];
            continue;
        }

        NSString *value = [self valueForIdentifier:config.identifier];
        NSString *error = nil;

        if (config.required && [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
            NSString *format = PPFormEngineLocalizedString(@"form_required_error_format", @"%@ is required");
            error = [NSString stringWithFormat:format, config.title.length ? config.title : config.identifier];
        }

        if (!error && config.validationBlock) {
            error = config.validationBlock(value ?: @"", config);
        }

        PPFormFieldRowView *row = [self rowForIdentifier:config.identifier];
        if (error.length > 0) {
            self.errorsByIdentifier[config.identifier] = error;
            [row setErrorText:error];
        } else {
            [row clearError];
        }
    }

    return self.errorsByIdentifier.count == 0;
}

- (NSDictionary<NSString *,NSString *> *)validationErrors {
    return self.errorsByIdentifier.copy;
}

- (void)clearErrors {
    [self.errorsByIdentifier removeAllObjects];
    for (PPFormFieldRowView *row in self.rowsByIdentifier.allValues) {
        [row clearError];
    }
}

- (void)setErrorText:(NSString *)errorText forIdentifier:(NSString *)identifier {
    PPFormFieldRowView *row = [self rowForIdentifier:identifier];
    if (errorText.length > 0) {
        self.errorsByIdentifier[identifier ?: @""] = errorText;
        [row setErrorText:errorText];
    } else {
        [self.errorsByIdentifier removeObjectForKey:identifier ?: @""];
        [row clearError];
    }
}

- (void)setFieldHidden:(BOOL)hidden identifier:(NSString *)identifier animated:(BOOL)animated {
    PPFormFieldConfig *config = [self configForIdentifier:identifier];
    PPFormFieldRowView *row = [self rowForIdentifier:identifier];
    if (!config || !row) return;

    config.hidden = hidden;

    void (^changes)(void) = ^{
        row.alpha = hidden ? 0.0 : 1.0;
        row.hidden = hidden;
        [self layoutIfNeeded];
    };

    if (animated) {
        if (!hidden) {
            row.hidden = NO;
            row.alpha = 0.0;
        }
        [UIView animateWithDuration:0.22 animations:changes];
    } else {
        changes();
    }
}

- (void)setFieldEnabled:(BOOL)enabled identifier:(NSString *)identifier {
    PPFormFieldConfig *config = [self configForIdentifier:identifier];
    PPFormFieldRowView *row = [self rowForIdentifier:identifier];
    if (!config || !row) return;
    config.enabled = enabled;
    row.enabled = enabled;
}

- (void)setAttachmentForIdentifier:(NSString *)identifier
                              title:(NSString *)title
                           subtitle:(NSString *)subtitle
                              image:(UIImage *)image
                            loading:(BOOL)loading
                 removeButtonHidden:(BOOL)removeButtonHidden {
    PPFormFieldConfig *config = [self configForIdentifier:identifier];
    PPFormFieldRowView *row = [self rowForIdentifier:identifier];
    if (!config || !row) return;

    config.attachmentTitle = title;
    config.attachmentSubtitle = subtitle;
    config.attachmentImage = image;
    config.attachmentLoading = loading;
    config.attachmentRemoveHidden = removeButtonHidden;

    [row setAttachmentTitle:title subtitle:subtitle image:image loading:loading removeButtonHidden:removeButtonHidden];
}

@end
