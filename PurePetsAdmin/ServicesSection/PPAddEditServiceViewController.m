//
//  PPAddEditServiceViewController.m
//  PurePetsAdmin
//

#import "PPAddEditServiceViewController.h"
#import "PPServiceModel.h"
#import "PPServiceManager.h"
#import "PPFormEngine.h"
#import "Styling.h"
#import "Language.h"
#import "PPHero.h"
#import "PPFunc.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static NSString * const kTagTitle = @"serviceTitle";
static NSString * const kTagDescription = @"serviceDescription";
static NSString * const kTagPrice = @"servicePrice";
static NSString * const kTagType = @"serviceType";
static NSString * const kTagCategory = @"serviceCategory";
static NSString * const kTagCategoryID = @"serviceCategoryID";
static NSString * const kTagOwnerID = @"serviceOwnerID";
static NSString * const kTagPetKindID = @"servicePetKindID";
static NSString * const kTagAvailableDate = @"serviceAvailableDate";
static NSString * const kTagTimestamp = @"serviceTimestamp";
static NSString * const kTagImageURL = @"serviceImageURL";
static NSString * const kTagBlurHash = @"serviceBlurHash";
static NSString * const kTagExtraJSON = @"serviceExtraJSON";
static NSString * const kTagAuditNote = @"serviceAuditNote";

static UIColor *PPServiceSurfaceColor(void) {
    return [UIColor ppElevatedSurface];
}

static UIColor *PPServiceBackgroundColor(void) {
    return [UIColor ppBackground];
}

static UIColor *PPServiceAccentColor(void) {
    return [UIColor ppPrimary];
}

@interface PPAddEditServiceViewController () <PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong, nullable) PPServiceModel *serviceToEdit;
@property (nonatomic, assign) BOOL isEditingService;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIImageView *heroImageView;
@property (nonatomic, strong) UILabel *heroHintLabel;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong, nullable) UIImage *selectedImage;
@property (nonatomic, strong) PPFormEngineView *basicFormView;
@property (nonatomic, strong) PPFormEngineView *classificationFormView;
@property (nonatomic, strong) PPFormEngineView *ownershipFormView;
@property (nonatomic, strong) PPFormEngineView *advancedFormView;
@end

@implementation PPAddEditServiceViewController

- (instancetype)initWithService:(PPServiceModel *)service {
    self = [super init];
    if (self) {
        _serviceToEdit = service;
        _isEditingService = (service != nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PPServiceBackgroundColor();
    [self pp_buildUI];
    [self pp_populateFieldsIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto
                      button:nil
                       title:(self.isEditingService ? kLang(@"Service_Edit_Title") : kLang(@"Service_Add_Title"))
                    showBack:YES];

    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:save];
}

#pragma mark - UI

- (void)pp_buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.backgroundColor = PPServiceBackgroundColor();
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 24.0;
    [self.contentView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-32.0],
    ]];

    [self.contentStack addArrangedSubview:[self pp_buildHeroSection]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitle:kLang(@"Service_Form_BasicSection")
                                                               body:[self pp_buildBasicForm]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitle:kLang(@"Service_Form_ClassificationSection")
                                                               body:[self pp_buildClassificationForm]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitle:kLang(@"Service_Form_OwnershipSection")
                                                               body:[self pp_buildOwnershipForm]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitle:kLang(@"Service_Form_AdvancedSection")
                                                               body:[self pp_buildAdvancedForm]]];
}

- (UIView *)pp_buildHeroSection {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    card.layer.cornerRadius = 28.0;
    if (@available(iOS 13.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    [card.heightAnchor constraintEqualToConstant:228.0].active = YES;

    self.heroBackground = [PPHero new];
    self.heroBackground.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroBackground.accentColorOverride = PPServiceAccentColor();
    [card addSubview:self.heroBackground];

    self.heroImageView = [[UIImageView alloc] init];
    self.heroImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.heroImageView.clipsToBounds = YES;
    self.heroImageView.layer.cornerRadius = 28.0;
    if (@available(iOS 13.0, *)) self.heroImageView.layer.cornerCurve = kCACornerCurveContinuous;
    self.heroImageView.backgroundColor = [PPServiceAccentColor() colorWithAlphaComponent:0.08];
    self.heroImageView.userInteractionEnabled = YES;
    [card addSubview:self.heroImageView];

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.18];
    [self.heroImageView addSubview:overlay];

    UIImageView *cameraIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"camera.circle.fill"]];
    cameraIcon.translatesAutoresizingMaskIntoConstraints = NO;
    cameraIcon.tintColor = UIColor.whiteColor;
    cameraIcon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:42 weight:UIImageSymbolWeightSemibold];
    [self.heroImageView addSubview:cameraIcon];

    self.heroHintLabel = [[UILabel alloc] init];
    self.heroHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroHintLabel.font = [Styling fontBold:14];
    self.heroHintLabel.textColor = UIColor.whiteColor;
    self.heroHintLabel.textAlignment = NSTextAlignmentCenter;
    self.heroHintLabel.numberOfLines = 2;
    self.heroHintLabel.text = kLang(@"Service_Form_ImageHint");
    [self.heroImageView addSubview:self.heroHintLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickImageTapped)];
    [self.heroImageView addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroBackground.topAnchor constraintEqualToAnchor:card.topAnchor],
        [self.heroBackground.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [self.heroBackground.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.heroBackground.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [self.heroImageView.topAnchor constraintEqualToAnchor:card.topAnchor],
        [self.heroImageView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [self.heroImageView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.heroImageView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [overlay.topAnchor constraintEqualToAnchor:self.heroImageView.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.heroImageView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.heroImageView.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.heroImageView.bottomAnchor],

        [cameraIcon.centerXAnchor constraintEqualToAnchor:self.heroImageView.centerXAnchor],
        [cameraIcon.centerYAnchor constraintEqualToAnchor:self.heroImageView.centerYAnchor constant:-12.0],
        [cameraIcon.widthAnchor constraintEqualToConstant:42.0],
        [cameraIcon.heightAnchor constraintEqualToConstant:42.0],

        [self.heroHintLabel.topAnchor constraintEqualToAnchor:cameraIcon.bottomAnchor constant:8.0],
        [self.heroHintLabel.leadingAnchor constraintEqualToAnchor:self.heroImageView.leadingAnchor constant:16.0],
        [self.heroHintLabel.trailingAnchor constraintEqualToAnchor:self.heroImageView.trailingAnchor constant:-16.0],
    ]];

    self.heroImageView.image = [UIImage systemImageNamed:@"sparkles.rectangle.stack.fill"];
    self.heroImageView.tintColor = PPServiceAccentColor();
    self.heroImageView.contentMode = UIViewContentModeCenter;
    return card;
}

- (UIView *)pp_sectionWithTitle:(NSString *)title body:(UIView *)body {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    UILabel *label = [[UILabel alloc] init];
    label.font = [Styling fontMedium:13];
    label.textColor = [UIColor ppTextSecondary];
    label.text = title;
    [stack addArrangedSubview:label];
    [stack addArrangedSubview:body];
    return container;
}

- (PPFormStyle *)pp_formStyle {
    PPFormStyle *style = [PPFormStyle defaultStyle];
    style.cardBackgroundColor = PPServiceSurfaceColor();
     style.cardBorderColor = [PPServiceAccentColor() colorWithAlphaComponent:0.08];
    style.fieldBorderColor = [PPServiceAccentColor() colorWithAlphaComponent:0.10];
    style.accentColor = PPServiceAccentColor();
    style.primaryTextColor = [UIColor ppTextPrimary];
    style.secondaryTextColor = [UIColor ppTextSecondary];
    style.cardCornerRadius = 24.0;
    style.fieldCornerRadius = 18.0;
    return style;
}

- (UIView *)pp_buildBasicForm {
    self.basicFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *title = [PPFormFieldConfig fieldWithIdentifier:kTagTitle title:kLang(@"Service_Field_Title") placeholder:kLang(@"Service_Field_Title") inputType:PPFormInputTypeText];
    title.required = YES;
    PPFormFieldConfig *desc = [PPFormFieldConfig fieldWithIdentifier:kTagDescription title:kLang(@"Service_Field_Description") placeholder:kLang(@"Service_Field_Description") inputType:PPFormInputTypeTextView];
    desc.required = YES;
    PPFormFieldConfig *price = [PPFormFieldConfig fieldWithIdentifier:kTagPrice title:kLang(@"Service_Field_Price") placeholder:@"0.00" inputType:PPFormInputTypeNumber];
    price.required = YES;
    [self.basicFormView setFields:@[title, desc, price]];
    return self.basicFormView;
}

- (UIView *)pp_buildClassificationForm {
    self.classificationFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];

    PPFormFieldConfig *type = [PPFormFieldConfig fieldWithIdentifier:kTagType title:@"" placeholder:@"" inputType:PPFormInputTypeSegmented];
    type.optionTitles = @[kLang(@"Service_Type_Training"), kLang(@"Service_Type_Grooming")];
    type.optionValues = @[@"training", @"grooming"];
    type.value = @"training";

    PPFormFieldConfig *category = [PPFormFieldConfig fieldWithIdentifier:kTagCategory title:kLang(@"Service_Field_Category") placeholder:kLang(@"Service_Field_Category") inputType:PPFormInputTypeText];
    PPFormFieldConfig *categoryID = [PPFormFieldConfig fieldWithIdentifier:kTagCategoryID title:kLang(@"Service_Field_CategoryID") placeholder:kLang(@"Service_Field_CategoryID") inputType:PPFormInputTypeText];
    PPFormFieldConfig *petKind = [PPFormFieldConfig fieldWithIdentifier:kTagPetKindID title:kLang(@"Service_Field_PetMainKindID") placeholder:@"0" inputType:PPFormInputTypeNumber];

    PPFormFieldConfig *availableDate = [PPFormFieldConfig fieldWithIdentifier:kTagAvailableDate title:kLang(@"Service_Field_AvailableDate") placeholder:kLang(@"Service_Field_AvailableDate") inputType:PPFormInputTypePicker];
    __weak typeof(self) weakSelf = self;
    availableDate.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        [weakSelf pp_presentDatePickerForIdentifier:config.identifier title:config.title sourceView:row];
    };

    PPFormFieldConfig *timestamp = [PPFormFieldConfig fieldWithIdentifier:kTagTimestamp title:kLang(@"Service_Field_Timestamp") placeholder:kLang(@"Service_Field_Timestamp") inputType:PPFormInputTypePicker];
    timestamp.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        [weakSelf pp_presentDatePickerForIdentifier:config.identifier title:config.title sourceView:row];
    };

    [self.classificationFormView setFields:@[type, category, categoryID, petKind, availableDate, timestamp]];
    return self.classificationFormView;
}

- (UIView *)pp_buildOwnershipForm {
    self.ownershipFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *owner = [PPFormFieldConfig fieldWithIdentifier:kTagOwnerID title:kLang(@"Service_Field_OwnerID") placeholder:kLang(@"Service_Field_OwnerID") inputType:PPFormInputTypeText];
    owner.required = YES;
    PPFormFieldConfig *imageURL = [PPFormFieldConfig fieldWithIdentifier:kTagImageURL title:kLang(@"Service_Field_ImageURL") placeholder:kLang(@"Service_Field_ImageURL") inputType:PPFormInputTypeText];
    PPFormFieldConfig *blurHash = [PPFormFieldConfig fieldWithIdentifier:kTagBlurHash title:kLang(@"Service_Field_BlurHash") placeholder:kLang(@"Service_Field_BlurHash") inputType:PPFormInputTypeText];
    [self.ownershipFormView setFields:@[owner, imageURL, blurHash]];
    return self.ownershipFormView;
}

- (UIView *)pp_buildAdvancedForm {
    self.advancedFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *extraJSON = [PPFormFieldConfig fieldWithIdentifier:kTagExtraJSON title:kLang(@"Service_Field_ExtraJSON") placeholder:kLang(@"Service_Field_ExtraJSON_Placeholder") inputType:PPFormInputTypeTextView];
    PPFormFieldConfig *audit = [PPFormFieldConfig fieldWithIdentifier:kTagAuditNote title:kLang(@"Service_Field_AuditNote") placeholder:kLang(@"Service_Field_AuditNote_Placeholder") inputType:PPFormInputTypeTextView];
    [self.advancedFormView setFields:@[extraJSON, audit]];
    return self.advancedFormView;
}

- (void)pp_populateFieldsIfNeeded {
    if (!self.serviceToEdit) {
        [self.ownershipFormView setValue:([FIRAuth auth].currentUser.uid ?: @"") forIdentifier:kTagOwnerID];
        [self.classificationFormView setValue:[self pp_displayStringForDate:[NSDate date]] forIdentifier:kTagTimestamp];
        return;
    }

    PPServiceModel *service = self.serviceToEdit;
    [self.basicFormView setValue:PPSafeString(service.title) forIdentifier:kTagTitle];
    [self.basicFormView setValue:PPSafeString(service.serviceDescriptionText) forIdentifier:kTagDescription];
    [self.basicFormView setValue:[NSString stringWithFormat:@"%g", service.price] forIdentifier:kTagPrice];
    [self.classificationFormView setValue:(service.type == PPServiceTypeGrooming ? @"grooming" : @"training") forIdentifier:kTagType];
    [self.classificationFormView setValue:PPSafeString(service.category) forIdentifier:kTagCategory];
    [self.classificationFormView setValue:PPSafeString(service.categoryID) forIdentifier:kTagCategoryID];
    [self.classificationFormView setValue:[NSString stringWithFormat:@"%ld", (long)service.petMainKindID] forIdentifier:kTagPetKindID];
    [self.classificationFormView setValue:[self pp_displayStringForDate:service.availableDate] forIdentifier:kTagAvailableDate];
    [self.classificationFormView setValue:[self pp_displayStringForDate:service.timestamp ?: [NSDate date]] forIdentifier:kTagTimestamp];
    [self.ownershipFormView setValue:PPSafeString(service.serviceOwnerID) forIdentifier:kTagOwnerID];
    [self.ownershipFormView setValue:PPSafeString(service.imageURL) forIdentifier:kTagImageURL];
    [self.ownershipFormView setValue:PPSafeString(service.blurHash) forIdentifier:kTagBlurHash];
    [self.advancedFormView setValue:[self prettyJSONStringFromDictionary:service.extraFields] forIdentifier:kTagExtraJSON];

    if (service.imageURL.length > 0) {
        self.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
        [self.heroImageView setImageFromUrl:service.imageURL placeholderImage:@"placeholder" Blr:YES Shimmering:YES completion:nil];
    }
}

#pragma mark - Actions

- (void)saveTapped {
    NSString *title = PPSafeString([self.basicFormView valueForIdentifier:kTagTitle]);
    NSString *descriptionText = PPSafeString([self.basicFormView valueForIdentifier:kTagDescription]);
    NSString *priceText = PPSafeString([self.basicFormView valueForIdentifier:kTagPrice]);
    NSString *ownerID = [[PPSafeString([self.ownershipFormView valueForIdentifier:kTagOwnerID]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];

    if (title.length == 0 || descriptionText.length == 0 || priceText.length == 0 || ownerID.length == 0) {
        [self pp_showErrorAlert:kLang(@"Error") ?: @"Missing required fields"];
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *extraFields = [self dictionaryFromJSONText:PPSafeString([self.advancedFormView valueForIdentifier:kTagExtraJSON]) error:&jsonError];
    if (jsonError) {
        [self pp_showErrorAlert:jsonError.localizedDescription];
        return;
    }

    PPServiceModel *model = self.serviceToEdit ? [self.serviceToEdit copy] : [PPServiceModel new];
    model.title = title;
    model.serviceDescriptionText = descriptionText;
    model.price = [priceText doubleValue];
    model.category = PPSafeString([self.classificationFormView valueForIdentifier:kTagCategory]);
    model.categoryID = PPSafeString([self.classificationFormView valueForIdentifier:kTagCategoryID]);
    model.serviceOwnerID = ownerID;
    model.petMainKindID = [PPSafeString([self.classificationFormView valueForIdentifier:kTagPetKindID]) integerValue];
    model.availableDate = [self pp_dateForIdentifier:kTagAvailableDate];
    model.timestamp = [self pp_dateForIdentifier:kTagTimestamp] ?: self.serviceToEdit.timestamp ?: [NSDate date];
    model.imageURL = PPSafeString([self.ownershipFormView valueForIdentifier:kTagImageURL]);
    model.blurHash = PPSafeString([self.ownershipFormView valueForIdentifier:kTagBlurHash]);
    model.extraFields = extraFields ?: @{};
    model.type = [[self.classificationFormView valueForIdentifier:kTagType] isEqualToString:@"grooming"] ? PPServiceTypeGrooming : PPServiceTypeTraining;

    NSString *auditNote = PPSafeString([self.advancedFormView valueForIdentifier:kTagAuditNote]);
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Service_Saving") subtitle:nil];

    __weak typeof(self) weakSelf = self;
    PPServiceVoidBlock completion = ^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [weakSelf pp_showErrorAlert:error.localizedDescription];
            return;
        }
        NSString *msg = weakSelf.isEditingService ? (kLang(@"Service_Updated_Success") ?: @"Service updated successfully") : (kLang(@"Service_Added_Success") ?: @"Service added successfully");
        [weakSelf pp_showSuccessAlertAndPop:msg];
    };

    if (self.isEditingService) {
        [[PPServiceManager sharedManager] updateService:model image:self.selectedImage auditNote:auditNote completion:completion];
    } else {
        [[PPServiceManager sharedManager] addService:model image:self.selectedImage auditNote:auditNote completion:completion];
    }
}

#pragma mark - Date Picking

- (void)pp_presentDatePickerForIdentifier:(NSString *)identifier title:(NSString *)title sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:@"\n\n\n\n\n\n\n\n\n" preferredStyle:UIAlertControllerStyleActionSheet];
    UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:CGRectMake(8, 30, 320, 180)];
    picker.datePickerMode = UIDatePickerModeDateAndTime;
    if (@available(iOS 13.4, *)) picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    NSDate *existingDate = [self pp_dateForIdentifier:identifier];
    if (existingDate) picker.date = existingDate;
    [sheet.view addSubview:picker];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") ?: @"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"OK") ?: @"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf pp_setDate:picker.date forIdentifier:identifier];
    }]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: self.view;
        popover.sourceRect = sourceView ? sourceView.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pp_setDate:(NSDate *)date forIdentifier:(NSString *)identifier {
    if (!date || identifier.length == 0) return;
    [self pp_storeDate:date identifier:identifier];
    [self.classificationFormView setValue:[self pp_displayStringForDate:date] forIdentifier:identifier];
}

- (void)pp_storeDate:(NSDate *)date identifier:(NSString *)identifier {
    objc_setAssociatedObject(self, (__bridge const void *)(identifier), date, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDate *)pp_dateForIdentifier:(NSString *)identifier {
    return objc_getAssociatedObject(self, (__bridge const void *)(identifier));
}

- (NSString *)pp_displayStringForDate:(NSDate *)date {
    if (!date) return @"";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

#pragma mark - Alerts

- (void)pp_showErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Error") ?: @"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") ?: @"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pp_showSuccessAlertAndPop:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Success_Title") ?: @"Success" message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") ?: @"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Image Picking

- (void)pickImageTapped {
    [PPFunc pp_playTapEffect];
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
        config.selectionLimit = 1;
        config.filter = [PHPickerFilter imagesFilter];
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }

    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *firstResult = results.firstObject;
    if (!firstResult) return;

    __weak typeof(self) weakSelf = self;
    if ([firstResult.itemProvider canLoadObjectOfClass:[UIImage class]]) {
        [firstResult.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
            if ([object isKindOfClass:[UIImage class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.selectedImage = (UIImage *)object;
                    weakSelf.heroImageView.image = weakSelf.selectedImage;
                    weakSelf.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
                });
            }
        }];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (!image) return;
    self.selectedImage = image;
    self.heroImageView.image = image;
    self.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
}

#pragma mark - JSON

- (NSDictionary *)dictionaryFromJSONText:(NSString *)jsonText error:(NSError * _Nullable __autoreleasing *)errorPointer {
    NSString *trimmed = [[PPSafeString(jsonText) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (trimmed.length == 0) return @{};

    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    NSError *parseError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    if (parseError || ![object isKindOfClass:NSDictionary.class]) {
        if (errorPointer) {
            *errorPointer = [NSError errorWithDomain:@"pp.service.form"
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"Service_Error_ExtraJSONInvalid")}];
        }
        return nil;
    }
    return object;
}

- (NSString *)prettyJSONStringFromDictionary:(NSDictionary *)dictionary {
    NSDictionary *safe = PPSafeDict(dictionary);
    if (safe.count == 0) return @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

@end
