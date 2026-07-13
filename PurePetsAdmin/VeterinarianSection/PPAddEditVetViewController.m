//
//  PPAddEditVetViewController.m
//  PurePetsAdmin
//

#import "PPAddEditVetViewController.h"
#import "PPVetModel.h"
#import "PPVetManager.h"
#import "PPFormEngine.h"
#import "Styling.h"
#import "PPHero.h"
#import "PPFunc.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static NSString * const kTagTitle       = @"vetTitle";
static NSString * const kTagPhone       = @"vetPhone";
static NSString * const kTagWhatsapp    = @"vetWhatsapp";
static NSString * const kTagDesc        = @"vetDescription";
static NSString * const kTagType        = @"vetType";
static NSString * const kTagCost        = @"vetCost";
static NSString * const kTagDate        = @"vetAvailableDate";
static NSString * const kTagKindID      = @"vetPetMainKindID";

static UIColor *PPVetSurfaceColor(void) {
    return AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
}

static UIColor *PPVetBackgroundColor(void) {
    return AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
}

static UIColor *PPVetAccentColor(void) {
    return AppPrimaryClr ?: UIColor.systemPinkColor;
}

@interface PPAddEditVetViewController () <PHPickerViewControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIImageView *logoImageView;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong, nullable) UIImage *selectedImage;
@property (nonatomic, assign) BOOL isEditing;
@property (nonatomic, strong) PPFormEngineView *infoFormView;
@property (nonatomic, strong) PPFormEngineView *contactFormView;
@property (nonatomic, strong) PPFormEngineView *detailFormView;
@end

@implementation PPAddEditVetViewController

- (instancetype)initWithVet:(PPVetModel *)vet {
    self = [super init];
    if (self) {
        _vetToEdit = vet;
        _isEditing = (vet != nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = PPVetBackgroundColor();
    [self pp_buildUI];
    [self pp_populateForm];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSString *title = self.isEditing ? kLang(@"Vet_Edit_Title") : kLang(@"Vet_Add_Title");
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:title showBack:YES];
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(saveTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:save];
}

#pragma mark - UI

- (void)pp_buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
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
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitle:kLang(@"Vet_Section_Info") body:[self pp_buildInfoForm]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitle:kLang(@"Vet_Section_Contact") body:[self pp_buildContactForm]]];
    [self.contentStack addArrangedSubview:[self pp_sectionWithTitle:kLang(@"Vet_Section_Details") body:[self pp_buildDetailForm]]];
}

- (UIView *)pp_buildHeroSection {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 28.0;
    if (@available(iOS 13.0, *)) card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    [card.heightAnchor constraintEqualToConstant:220.0].active = YES;

    self.heroBackground = [PPHero new];
    self.heroBackground.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroBackground.accentColorOverride = PPVetAccentColor();
    [card addSubview:self.heroBackground];

    self.logoImageView = [[UIImageView alloc] init];
    self.logoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logoImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.logoImageView.clipsToBounds = YES;
    self.logoImageView.layer.cornerRadius = 28.0;
    if (@available(iOS 13.0, *)) self.logoImageView.layer.cornerCurve = kCACornerCurveContinuous;
    self.logoImageView.backgroundColor = [PPVetAccentColor() colorWithAlphaComponent:0.06];
    self.logoImageView.userInteractionEnabled = YES;
    [card addSubview:self.logoImageView];

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.12];
    [self.logoImageView addSubview:overlay];

    UIImageView *cameraIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"camera.circle.fill"]];
    cameraIcon.translatesAutoresizingMaskIntoConstraints = NO;
    cameraIcon.tintColor = UIColor.whiteColor;
    cameraIcon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:42 weight:UIImageSymbolWeightSemibold];
    [self.logoImageView addSubview:cameraIcon];

    UILabel *hint = [[UILabel alloc] init];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.font = [Styling fontBold:14];
    hint.textColor = UIColor.whiteColor;
    hint.textAlignment = NSTextAlignmentCenter;
    hint.text = kLang(@"Tap to choose a service image");
    [self.logoImageView addSubview:hint];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickImageTapped)];
    [self.logoImageView addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroBackground.topAnchor constraintEqualToAnchor:card.topAnchor],
        [self.heroBackground.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [self.heroBackground.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.heroBackground.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [self.logoImageView.topAnchor constraintEqualToAnchor:card.topAnchor],
        [self.logoImageView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [self.logoImageView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [self.logoImageView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [overlay.topAnchor constraintEqualToAnchor:self.logoImageView.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.logoImageView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.logoImageView.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.logoImageView.bottomAnchor],

        [cameraIcon.centerXAnchor constraintEqualToAnchor:self.logoImageView.centerXAnchor],
        [cameraIcon.centerYAnchor constraintEqualToAnchor:self.logoImageView.centerYAnchor constant:-10.0],
        [hint.topAnchor constraintEqualToAnchor:cameraIcon.bottomAnchor constant:8.0],
        [hint.leadingAnchor constraintEqualToAnchor:self.logoImageView.leadingAnchor constant:16.0],
        [hint.trailingAnchor constraintEqualToAnchor:self.logoImageView.trailingAnchor constant:-16.0],
    ]];

    if (self.vetToEdit.logoURL.length > 0) {
        [self.logoImageView setImageFromUrl:self.vetToEdit.logoURL placeholderImage:@"veterinary" Blr:YES Shimmering:YES completion:nil];
    } else {
        self.logoImageView.image = [UIImage systemImageNamed:@"stethoscope.circle.fill"];
        self.logoImageView.tintColor = PPVetAccentColor();
        self.logoImageView.contentMode = UIViewContentModeCenter;
    }

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
    label.textColor = SeconderyTextClr ?: UIColor.secondaryLabelColor;
    label.text = title;
    [stack addArrangedSubview:label];
    [stack addArrangedSubview:body];
    return container;
}

- (PPFormStyle *)pp_formStyle {
    PPFormStyle *style = [PPFormStyle defaultStyle];
    style.cardBackgroundColor = PPVetSurfaceColor();
    style.fieldBackgroundColor = [PPVetAccentColor() colorWithAlphaComponent:0.05];
    style.cardBorderColor = [PPVetAccentColor() colorWithAlphaComponent:0.08];
    style.fieldBorderColor = [PPVetAccentColor() colorWithAlphaComponent:0.10];
    style.accentColor = PPVetAccentColor();
    style.primaryTextColor = PrimaryTextClr ?: UIColor.labelColor;
    style.secondaryTextColor = SeconderyTextClr ?: UIColor.secondaryLabelColor;
    style.cardCornerRadius = 24.0;
    style.fieldCornerRadius = 18.0;
    return style;
}

- (UIView *)pp_buildInfoForm {
    self.infoFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *name = [PPFormFieldConfig fieldWithIdentifier:kTagTitle title:kLang(@"Vet_Field_Name") placeholder:kLang(@"Vet_Field_Name") inputType:PPFormInputTypeText];
    name.required = YES;
    PPFormFieldConfig *type = [PPFormFieldConfig fieldWithIdentifier:kTagType title:@"" placeholder:@"" inputType:PPFormInputTypeSegmented];
    type.optionTitles = @[kLang(@"Vet_Type_Personal"), kLang(@"Vet_Type_Company")];
    type.optionValues = @[@"personal", @"company"];
    type.value = @"personal";
    PPFormFieldConfig *desc = [PPFormFieldConfig fieldWithIdentifier:kTagDesc title:kLang(@"Vet_Field_Description") placeholder:kLang(@"Vet_Field_Description") inputType:PPFormInputTypeTextView];
    [self.infoFormView setFields:@[name, type, desc]];
    return self.infoFormView;
}

- (UIView *)pp_buildContactForm {
    self.contactFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *phone = [PPFormFieldConfig fieldWithIdentifier:kTagPhone title:kLang(@"Vet_Field_Phone") placeholder:kLang(@"Vet_Field_Phone") inputType:PPFormInputTypePhone];
    PPFormFieldConfig *whatsapp = [PPFormFieldConfig fieldWithIdentifier:kTagWhatsapp title:kLang(@"Vet_Field_Whatsapp") placeholder:kLang(@"Vet_Field_Whatsapp") inputType:PPFormInputTypePhone];
    [self.contactFormView setFields:@[phone, whatsapp]];
    return self.contactFormView;
}

- (UIView *)pp_buildDetailForm {
    self.detailFormView = [[PPFormEngineView alloc] initWithStyle:[self pp_formStyle]];
    PPFormFieldConfig *cost = [PPFormFieldConfig fieldWithIdentifier:kTagCost title:kLang(@"Vet_Field_Cost") placeholder:@"0.00" inputType:PPFormInputTypeNumber];
    PPFormFieldConfig *date = [PPFormFieldConfig fieldWithIdentifier:kTagDate title:kLang(@"Vet_Field_AvailableDate") placeholder:kLang(@"Vet_Field_AvailableDate") inputType:PPFormInputTypePicker];
    __weak typeof(self) weakSelf = self;
    date.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        [weakSelf pp_presentDatePickerForIdentifier:config.identifier title:config.title sourceView:row];
    };
    PPFormFieldConfig *kind = [PPFormFieldConfig fieldWithIdentifier:kTagKindID title:kLang(@"Vet_Field_PetKindID") placeholder:@"0" inputType:PPFormInputTypeNumber];
    [self.detailFormView setFields:@[cost, date, kind]];
    return self.detailFormView;
}

- (void)pp_populateForm {
    if (!self.vetToEdit) {
        NSDate *today = [NSDate date];
        [self pp_storeDate:today identifier:kTagDate];
        [self.detailFormView setValue:[self pp_displayStringForDate:today] forIdentifier:kTagDate];
        return;
    }

    PPVetModel *v = self.vetToEdit;
    [self.infoFormView setValue:PPSafeString(v.title) forIdentifier:kTagTitle];
    [self.infoFormView setValue:(v.type == PPVetTypeCompany ? @"company" : @"personal") forIdentifier:kTagType];
    [self.infoFormView setValue:PPSafeString(v.descriptionText) forIdentifier:kTagDesc];
    [self.contactFormView setValue:PPSafeString(v.phone) forIdentifier:kTagPhone];
    [self.contactFormView setValue:PPSafeString(v.whatsapp) forIdentifier:kTagWhatsapp];
    [self.detailFormView setValue:[NSString stringWithFormat:@"%g", v.vetCost] forIdentifier:kTagCost];
    [self pp_storeDate:(v.availableDate ?: [NSDate date]) identifier:kTagDate];
    [self.detailFormView setValue:[self pp_displayStringForDate:(v.availableDate ?: [NSDate date])] forIdentifier:kTagDate];
    [self.detailFormView setValue:[NSString stringWithFormat:@"%ld", (long)v.petMainKindID] forIdentifier:kTagKindID];
}

#pragma mark - Save

- (void)saveTapped {
    NSString *name = PPSafeString([self.infoFormView valueForIdentifier:kTagTitle]);
    if (name.length == 0) {
        [PPHUD showError:kLang(@"Error") subtitle:kLang(@"Vet_Field_Name")];
        return;
    }

    PPVetModel *model = self.vetToEdit ? [self.vetToEdit copy] : [[PPVetModel alloc] init];
    model.title = name;
    model.phone = PPSafeString([self.contactFormView valueForIdentifier:kTagPhone]);
    model.whatsapp = PPSafeString([self.contactFormView valueForIdentifier:kTagWhatsapp]);
    model.descriptionText = PPSafeString([self.infoFormView valueForIdentifier:kTagDesc]);
    model.vetCost = [PPSafeString([self.detailFormView valueForIdentifier:kTagCost]) doubleValue];
    model.availableDate = [self pp_dateForIdentifier:kTagDate];
    model.petMainKindID = [PPSafeString([self.detailFormView valueForIdentifier:kTagKindID]) integerValue];
    model.type = [[self.infoFormView valueForIdentifier:kTagType] isEqualToString:@"company"] ? PPVetTypeCompany : PPVetTypePersonal;

    if (!self.isEditing) {
        model.userID = [FIRAuth auth].currentUser.uid ?: @"";
    }

    [PPHUD showIndeterminateIn:self.view title:kLang(@"Vet_Saving") subtitle:nil];
    __weak typeof(self) weakSelf = self;
    PPVetVoidBlock done = ^(NSError *error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            return;
        }
        [PPHUD showSuccess:kLang(@"Success_Title") subtitle:weakSelf.isEditing ? kLang(@"Vet_Updated_Success") : kLang(@"Vet_Added_Success")];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
    };

    if (self.isEditing) {
        [[PPVetManager sharedManager] updateVet:model image:self.selectedImage completion:done];
    } else {
        [[PPVetManager sharedManager] addVet:model image:self.selectedImage completion:done];
    }
}

#pragma mark - Date

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
        [weakSelf pp_storeDate:picker.date identifier:identifier];
        [weakSelf.detailFormView setValue:[weakSelf pp_displayStringForDate:picker.date] forIdentifier:identifier];
    }]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: self.view;
        popover.sourceRect = sourceView ? sourceView.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
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

#pragma mark - Image Picker

- (void)pickImageTapped {
    [PPFunc pp_playTapEffect];
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
        config.selectionLimit = 1;
        config.filter = [PHPickerFilter imagesFilter];
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    PHPickerResult *first = results.firstObject;
    if ([first.itemProvider canLoadObjectOfClass:[UIImage class]]) {
        __weak typeof(self) weakSelf = self;
        [first.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
            if ([object isKindOfClass:[UIImage class]]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakSelf.selectedImage = (UIImage *)object;
                    weakSelf.logoImageView.image = weakSelf.selectedImage;
                    weakSelf.logoImageView.contentMode = UIViewContentModeScaleAspectFill;
                });
            }
        }];
    }
}

@end
