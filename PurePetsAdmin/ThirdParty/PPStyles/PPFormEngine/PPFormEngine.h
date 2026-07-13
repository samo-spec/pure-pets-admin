//
//  PPFormEngine.h
//
//  Reusable UIKit form engine + pixel-perfect row UI.
//  Drag this file and PPFormEngine.m into your UIKit target.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPFormFieldRowView;
@class PPFormEngineView;
@class PPFormFieldConfig;

typedef NS_ENUM(NSInteger, PPFormInputType) {
    PPFormInputTypeText = 0,
    PPFormInputTypePhone,
    PPFormInputTypeNumber,
    PPFormInputTypePicker,
    PPFormInputTypeAttachment,
    PPFormInputTypeTextView,
    PPFormInputTypeToggle,
    PPFormInputTypeSegmented,
};

typedef NSString * _Nullable (^PPFormFieldValidationBlock)(NSString *value, PPFormFieldConfig *config);
typedef void (^PPFormFieldTextChangeBlock)(PPFormFieldConfig *config, NSString *value);
typedef void (^PPFormFieldTapBlock)(PPFormFieldConfig *config, PPFormFieldRowView *row);
typedef void (^PPFormAttachmentRemoveBlock)(PPFormFieldConfig *config, PPFormFieldRowView *row);

@interface PPFormStyle : NSObject <NSCopying>

@property (nonatomic, strong) UIColor *cardBackgroundColor;
@property (nonatomic, strong) UIColor *fieldBackgroundColor;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, strong) UIColor *primaryTextColor;
@property (nonatomic, strong) UIColor *secondaryTextColor;
@property (nonatomic, strong) UIColor *errorColor;
@property (nonatomic, strong) UIColor *cardBorderColor;
@property (nonatomic, strong) UIColor *fieldBorderColor;
@property (nonatomic, strong) UIColor *shadowColor;

@property (nonatomic, strong) UIFont *titleFont;
@property (nonatomic, strong) UIFont *inputFont;
@property (nonatomic, strong) UIFont *placeholderFont;
@property (nonatomic, strong) UIFont *errorFont;
@property (nonatomic, strong) UIFont *attachmentTitleFont;
@property (nonatomic, strong) UIFont *attachmentSubtitleFont;

@property (nonatomic, assign) CGFloat stackSpacing;
@property (nonatomic, assign) CGFloat cardCornerRadius;
@property (nonatomic, assign) CGFloat fieldCornerRadius;
@property (nonatomic, assign) CGFloat attachmentThumbCornerRadius;
@property (nonatomic, assign) CGFloat cardBorderWidth;
@property (nonatomic, assign) CGFloat fieldBorderWidth;
@property (nonatomic, assign) CGFloat shadowOpacity;
@property (nonatomic, assign) CGFloat shadowRadius;
@property (nonatomic, assign) CGSize shadowOffset;

@property (nonatomic, assign) CGFloat accentLeading;
@property (nonatomic, assign) CGFloat accentTop;
@property (nonatomic, assign) CGFloat accentWidth;
@property (nonatomic, assign) CGFloat accentHeight;
@property (nonatomic, assign) CGFloat titleLeadingFromAccent;
@property (nonatomic, assign) CGFloat titleTrailing;
@property (nonatomic, assign) CGFloat titleToFieldSpacing;

@property (nonatomic, assign) CGFloat fieldLeading;
@property (nonatomic, assign) CGFloat fieldTrailing;
@property (nonatomic, assign) CGFloat fieldTopInset;
@property (nonatomic, assign) CGFloat fieldHorizontalInset;
@property (nonatomic, assign) CGFloat fieldBottomInset;

@property (nonatomic, assign) CGFloat rowBottomInset;
@property (nonatomic, assign) CGFloat errorTopSpacing;
@property (nonatomic, assign) CGFloat attachmentDividerTopSpacing;
@property (nonatomic, assign) CGFloat attachmentZoneTopSpacing;
@property (nonatomic, assign) CGFloat attachmentZoneBottomInset;

@property (nonatomic, assign) CGFloat minimumSingleLineFieldHeight;
@property (nonatomic, assign) CGFloat minimumTextViewFieldHeight;
@property (nonatomic, assign) CGFloat attachmentThumbSize;

+ (instancetype)defaultStyle;

@end

@interface PPFormFieldConfig : NSObject <NSCopying>

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, assign) PPFormInputType inputType;
@property (nonatomic, assign) UIKeyboardType keyboardType;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, assign) BOOL required;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, copy, nullable) NSArray<NSString *> *optionTitles;
@property (nonatomic, copy, nullable) NSArray<NSString *> *optionValues;

@property (nonatomic, copy, nullable) NSString *attachmentTitle;
@property (nonatomic, copy, nullable) NSString *attachmentSubtitle;
@property (nonatomic, strong, nullable) UIImage *attachmentImage;
@property (nonatomic, assign) BOOL attachmentLoading;
@property (nonatomic, assign) BOOL attachmentRemoveHidden;

@property (nonatomic, copy, nullable) PPFormFieldValidationBlock validationBlock;
@property (nonatomic, copy, nullable) PPFormFieldTextChangeBlock textChangeBlock;
@property (nonatomic, copy, nullable) PPFormFieldTapBlock pickerTapBlock;
@property (nonatomic, copy, nullable) PPFormFieldTapBlock attachmentTapBlock;
@property (nonatomic, copy, nullable) PPFormAttachmentRemoveBlock attachmentRemoveBlock;

+ (instancetype)fieldWithIdentifier:(NSString *)identifier
                              title:(NSString *)title
                        placeholder:(NSString *)placeholder
                          inputType:(PPFormInputType)inputType;

@end

@interface PPFormFieldRowView : UIView <UITextFieldDelegate, UITextViewDelegate>

@property (nonatomic, assign, readonly) PPFormInputType inputType;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly, nullable) UITextField *textField;
@property (nonatomic, strong, readonly, nullable) UITextView *textView;
@property (nonatomic, strong, readonly, nullable) UIButton *pickerButton;
@property (nonatomic, strong, readonly, nullable) UISwitch *toggleSwitch;
@property (nonatomic, strong, readonly, nullable) UISegmentedControl *segmentedControl;
@property (nonatomic, strong, readonly, nullable) UIStackView *attachmentZone;
@property (nonatomic, strong, readonly, nullable) UIImageView *attachmentImageView;
@property (nonatomic, strong, readonly, nullable) UILabel *attachmentTitleLabel;
@property (nonatomic, strong, readonly, nullable) UILabel *attachmentSubtitleLabel;
@property (nonatomic, strong, readonly, nullable) UIActivityIndicatorView *attachmentActivityView;
@property (nonatomic, strong, readonly, nullable) UIButton *attachmentRemoveButton;

@property (nonatomic, copy, nullable) void (^textChangeHandler)(PPFormFieldRowView *row, NSString *value);
@property (nonatomic, copy, nullable) void (^pickerTapHandler)(PPFormFieldRowView *row);
@property (nonatomic, copy, nullable) void (^attachmentTapHandler)(PPFormFieldRowView *row);
@property (nonatomic, copy, nullable) void (^attachmentRemoveTapHandler)(PPFormFieldRowView *row);

@property (nonatomic, weak, nullable) id<UITextFieldDelegate> externalTextFieldDelegate;
@property (nonatomic, weak, nullable) id<UITextViewDelegate> externalTextViewDelegate;

- (instancetype)initWithConfig:(PPFormFieldConfig *)config style:(PPFormStyle *)style NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (NSString *)value;
- (void)setValue:(nullable NSString *)value;
- (void)applyConfig:(PPFormFieldConfig *)config;
- (void)setErrorText:(nullable NSString *)errorText;
- (void)clearError;
- (void)setAttachmentTitle:(nullable NSString *)title
                  subtitle:(nullable NSString *)subtitle
                     image:(nullable UIImage *)image
                   loading:(BOOL)loading
        removeButtonHidden:(BOOL)removeButtonHidden;

@end

@interface PPFormEngineView : UIView

@property (nonatomic, strong, readonly) UIStackView *stackView;
@property (nonatomic, strong, readonly) NSArray<PPFormFieldConfig *> *fields;
@property (nonatomic, strong, readonly) NSDictionary<NSString *, PPFormFieldRowView *> *rowsByIdentifier;
@property (nonatomic, strong) PPFormStyle *style;
@property (nonatomic, assign) BOOL validatesOnChange;

- (instancetype)initWithStyle:(nullable PPFormStyle *)style;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)setFields:(NSArray<PPFormFieldConfig *> *)fields;
- (nullable PPFormFieldRowView *)rowForIdentifier:(NSString *)identifier;
- (nullable PPFormFieldConfig *)configForIdentifier:(NSString *)identifier;

- (NSString *)valueForIdentifier:(NSString *)identifier;
- (void)setValue:(nullable NSString *)value forIdentifier:(NSString *)identifier;

- (NSDictionary<NSString *, NSString *> *)values;
- (void)setValues:(NSDictionary<NSString *, NSString *> *)values;

- (BOOL)validate;
- (NSDictionary<NSString *, NSString *> *)validationErrors;
- (void)clearErrors;

- (void)setErrorText:(nullable NSString *)errorText forIdentifier:(NSString *)identifier;
- (void)setFieldHidden:(BOOL)hidden identifier:(NSString *)identifier animated:(BOOL)animated;
- (void)setFieldEnabled:(BOOL)enabled identifier:(NSString *)identifier;

- (void)setAttachmentForIdentifier:(NSString *)identifier
                              title:(nullable NSString *)title
                           subtitle:(nullable NSString *)subtitle
                              image:(nullable UIImage *)image
                            loading:(BOOL)loading
                 removeButtonHidden:(BOOL)removeButtonHidden;

@end

NS_ASSUME_NONNULL_END
