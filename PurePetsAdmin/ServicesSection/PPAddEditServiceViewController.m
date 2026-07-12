//
//  PPAddEditServiceViewController.m
//  PurePetsAdmin
//

#import "PPAddEditServiceViewController.h"
#import "PPServiceModel.h"
#import "PPServiceManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import <PhotosUI/PhotosUI.h>
@import Firebase;
@import FirebaseAuth;
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

@interface PPAddEditServiceViewController () <PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong, nullable) PPServiceModel *serviceToEdit;
@property (nonatomic, assign) BOOL isEditingService;
@property (nonatomic, strong) UIImageView *heroImageView;
@property (nonatomic, strong, nullable) UIImage *selectedImage;
@end

@implementation PPAddEditServiceViewController

- (instancetype)initWithService:(PPServiceModel *)service {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    self = [super initWithForm:form style:UITableViewStyleInsetGrouped];
    if (self) {
        _serviceToEdit = service;
        _isEditingService = (service != nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppForgroundColr;
    self.tableView.backgroundColor = AppForgroundColr;
    [self setupHeader];
    [self buildForm];
    [self populateFormIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto
                      button:nil
                       title:(self.isEditingService ? kLang(@"Service_Edit_Title") : kLang(@"Service_Add_Title"))
                    showBack:YES];
}

#pragma mark - UI

- (void)setupHeader {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 222)];
    container.backgroundColor = UIColor.clearColor;

    self.heroImageView = [UIImageView new];
    self.heroImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.heroImageView.layer.cornerRadius = 24.0;
    self.heroImageView.layer.cornerCurve = kCACornerCurveContinuous;
    self.heroImageView.clipsToBounds = YES;
    self.heroImageView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.08];
    self.heroImageView.userInteractionEnabled = YES;
    [container addSubview:self.heroImageView];

    UIView *overlay = [UIView new];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.18];
    overlay.userInteractionEnabled = NO;
    [self.heroImageView addSubview:overlay];

    UILabel *hintLabel = [UILabel new];
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    hintLabel.font = [Styling fontBold:14];
    hintLabel.textColor = UIColor.whiteColor;
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.text = kLang(@"Service_Form_ImageHint");
    [self.heroImageView addSubview:hintLabel];

    UIImageView *cameraIcon = [UIImageView new];
    cameraIcon.translatesAutoresizingMaskIntoConstraints = NO;
    cameraIcon.tintColor = UIColor.whiteColor;
    cameraIcon.image = [UIImage systemImageNamed:@"camera.circle.fill"];
    [self.heroImageView addSubview:cameraIcon];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickImageTapped)];
    [self.heroImageView addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroImageView.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [self.heroImageView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [self.heroImageView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [self.heroImageView.heightAnchor constraintEqualToConstant:190],

        [overlay.topAnchor constraintEqualToAnchor:self.heroImageView.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.heroImageView.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.heroImageView.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.heroImageView.bottomAnchor],

        [cameraIcon.centerXAnchor constraintEqualToAnchor:self.heroImageView.centerXAnchor],
        [cameraIcon.centerYAnchor constraintEqualToAnchor:self.heroImageView.centerYAnchor constant:-12],
        [cameraIcon.widthAnchor constraintEqualToConstant:42],
        [cameraIcon.heightAnchor constraintEqualToConstant:42],

        [hintLabel.topAnchor constraintEqualToAnchor:cameraIcon.bottomAnchor constant:8],
        [hintLabel.leadingAnchor constraintEqualToAnchor:self.heroImageView.leadingAnchor constant:16],
        [hintLabel.trailingAnchor constraintEqualToAnchor:self.heroImageView.trailingAnchor constant:-16]
    ]];

    self.heroImageView.image = [UIImage systemImageNamed:@"sparkles.rectangle.stack.fill"];
    self.heroImageView.tintColor = AppPrimaryClr;
    self.heroImageView.contentMode = UIViewContentModeCenter;
    self.tableView.tableHeaderView = container;
}

- (void)buildForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    XLFormSectionDescriptor *basicSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Service_Form_BasicSection")];
    [form addFormSection:basicSection];

    XLFormRowDescriptor *titleRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagTitle rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_Title")];
    titleRow.required = YES;
    [basicSection addFormRow:titleRow];

    XLFormRowDescriptor *descRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagDescription rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Service_Field_Description")];
    descRow.required = YES;
    [basicSection addFormRow:descRow];

    XLFormRowDescriptor *priceRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagPrice rowType:XLFormRowDescriptorTypeDecimal title:kLang(@"Service_Field_Price")];
    priceRow.required = YES;
    [basicSection addFormRow:priceRow];

    XLFormSectionDescriptor *classificationSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Service_Form_ClassificationSection")];
    [form addFormSection:classificationSection];

    XLFormRowDescriptor *typeRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagType rowType:XLFormRowDescriptorTypeSelectorSegmentedControl title:kLang(@"Service_Field_Type")];
    typeRow.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPServiceTypeTraining) displayText:kLang(@"Service_Type_Training")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPServiceTypeGrooming) displayText:kLang(@"Service_Type_Grooming")]
    ];
    typeRow.value = [XLFormOptionsObject formOptionsObjectWithValue:@(PPServiceTypeTraining) displayText:kLang(@"Service_Type_Training")];
    [classificationSection addFormRow:typeRow];

    [classificationSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagCategory rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_Category")]];
    [classificationSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagCategoryID rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_CategoryID")]];

    XLFormRowDescriptor *petKindRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagPetKindID rowType:XLFormRowDescriptorTypeInteger title:kLang(@"Service_Field_PetMainKindID")];
    petKindRow.value = @(0);
    [classificationSection addFormRow:petKindRow];

    XLFormRowDescriptor *availableDateRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagAvailableDate rowType:XLFormRowDescriptorTypeDateInline title:kLang(@"Service_Field_AvailableDate")];
    [classificationSection addFormRow:availableDateRow];

    XLFormRowDescriptor *timestampRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagTimestamp rowType:XLFormRowDescriptorTypeDateInline title:kLang(@"Service_Field_Timestamp")];
    timestampRow.value = [NSDate date];
    [classificationSection addFormRow:timestampRow];

    XLFormSectionDescriptor *ownershipSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Service_Form_OwnershipSection")];
    [form addFormSection:ownershipSection];

    XLFormRowDescriptor *ownerRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagOwnerID rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_OwnerID")];
    ownerRow.required = YES;
    [ownershipSection addFormRow:ownerRow];

    [ownershipSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagImageURL rowType:XLFormRowDescriptorTypeURL title:kLang(@"Service_Field_ImageURL")]];
    [ownershipSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagBlurHash rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_BlurHash")]];

    XLFormSectionDescriptor *advancedSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Service_Form_AdvancedSection")];
    [form addFormSection:advancedSection];

    XLFormRowDescriptor *extraJSONRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagExtraJSON rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Service_Field_ExtraJSON")];
    extraJSONRow.cellConfig[@"textView.placeholder"] = kLang(@"Service_Field_ExtraJSON_Placeholder");
    [advancedSection addFormRow:extraJSONRow];

    XLFormRowDescriptor *auditRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagAuditNote rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Service_Field_AuditNote")];
    auditRow.cellConfig[@"textView.placeholder"] = kLang(@"Service_Field_AuditNote_Placeholder");
    [advancedSection addFormRow:auditRow];

    XLFormSectionDescriptor *actionSection = [XLFormSectionDescriptor formSection];
    [form addFormSection:actionSection];

    XLFormRowDescriptor *saveRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"saveRow" rowType:XLFormRowDescriptorTypeButton title:kLang(@"Service_Action_Save")];
    saveRow.action.formSelector = @selector(saveTapped);
    [actionSection addFormRow:saveRow];
    self.tableView.backgroundColor = AppForgroundColr;
    self.form = form;
}

- (void)populateFormIfNeeded {
    if (!self.serviceToEdit) {
        [self.form formRowWithTag:kTagOwnerID].value = [FIRAuth auth].currentUser.uid ?: @"";
        return;
    }

    PPServiceModel *service = self.serviceToEdit;
    [self.form formRowWithTag:kTagTitle].value = service.title;
    [self.form formRowWithTag:kTagDescription].value = service.serviceDescriptionText;
    [self.form formRowWithTag:kTagPrice].value = @(service.price);
    [self.form formRowWithTag:kTagCategory].value = service.category;
    [self.form formRowWithTag:kTagCategoryID].value = service.categoryID;
    [self.form formRowWithTag:kTagOwnerID].value = service.serviceOwnerID;
    [self.form formRowWithTag:kTagPetKindID].value = @(service.petMainKindID);
    [self.form formRowWithTag:kTagAvailableDate].value = service.availableDate;
    [self.form formRowWithTag:kTagTimestamp].value = service.timestamp ?: [NSDate date];
    [self.form formRowWithTag:kTagImageURL].value = service.imageURL;
    [self.form formRowWithTag:kTagBlurHash].value = service.blurHash;
    [self.form formRowWithTag:kTagExtraJSON].value = [self prettyJSONStringFromDictionary:service.extraFields];

    XLFormRowDescriptor *typeRow = [self.form formRowWithTag:kTagType];
    NSString *typeDisplay = [service localizedTypeName];
    typeRow.value = [XLFormOptionsObject formOptionsObjectWithValue:@(service.type) displayText:typeDisplay];

    if (service.imageURL.length > 0) {
        self.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
        [self.heroImageView setImageFromUrl:service.imageURL
                           placeholderImage:@"placeholder"
                                        Blr:YES
                                 Shimmering:YES
                                 completion:nil];
    }
}

#pragma mark - Modern Alerts

- (void)pp_showAlertWithTitle:(NSString *)title
                      message:(NSString *)message
                        style:(UIAlertControllerStyle)style
                      actions:(NSArray<UIAlertAction *> *)actions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:style];
    for (UIAlertAction *action in actions) {
        [alert addAction:action];
    }
    if (actions.count == 0) {
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") ?: @"OK"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pp_showErrorAlert:(NSString *)message {
    [self pp_showAlertWithTitle:kLang(@"Error") ?: @"Error"
                        message:message
                          style:UIAlertControllerStyleAlert
                        actions:@[]];
}

- (void)pp_showSuccessAlertAndPop:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Success_Title") ?: @"Success"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") ?: @"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFormValidationError:(NSError *)error {
    [self pp_showErrorAlert:error.localizedDescription];
}

#pragma mark - Save

- (void)saveTapped {
    NSArray *errors = [self formValidationErrors];
    if (errors.count > 0) {
        [self showFormValidationError:errors.firstObject];
        return;
    }

    NSDictionary *values = [self formValues];
    NSError *jsonError = nil;
    NSDictionary *extraFields = [self dictionaryFromJSONText:PPSafeString(values[kTagExtraJSON]) error:&jsonError];
    if (jsonError) {
        [self pp_showErrorAlert:jsonError.localizedDescription];
        return;
    }

    PPServiceModel *model = self.serviceToEdit ? [self.serviceToEdit copy] : [PPServiceModel new];
    model.title = PPSafeString(values[kTagTitle]);
    model.serviceDescriptionText = PPSafeString(values[kTagDescription]);
    model.price = [values[kTagPrice] doubleValue];
    model.category = PPSafeString(values[kTagCategory]);
    model.categoryID = PPSafeString(values[kTagCategoryID]);
    model.serviceOwnerID = [[PPSafeString(values[kTagOwnerID]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    model.petMainKindID = [values[kTagPetKindID] integerValue];
    model.availableDate = [values[kTagAvailableDate] isKindOfClass:NSDate.class] ? values[kTagAvailableDate] : nil;
    model.timestamp = [values[kTagTimestamp] isKindOfClass:NSDate.class] ? values[kTagTimestamp] : self.serviceToEdit.timestamp ?: [NSDate date];
    model.imageURL = PPSafeString(values[kTagImageURL]);
    model.blurHash = PPSafeString(values[kTagBlurHash]);
    model.extraFields = extraFields ?: @{};

    id typeValue = values[kTagType];
    if ([typeValue respondsToSelector:@selector(formValue)]) {
        model.type = [[typeValue formValue] integerValue];
    }

    NSString *auditNote = PPSafeString(values[kTagAuditNote]);
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Service_Saving") subtitle:nil];

    __weak typeof(self) weakSelf = self;
    PPServiceVoidBlock completion = ^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [weakSelf pp_showErrorAlert:error.localizedDescription];
            return;
        }
        NSString *msg = weakSelf.isEditingService
            ? (kLang(@"Service_Updated_Success") ?: @"Service updated successfully")
            : (kLang(@"Service_Added_Success") ?: @"Service added successfully");
        [weakSelf pp_showSuccessAlertAndPop:msg];
    };

    if (self.isEditingService) {
        [[PPServiceManager sharedManager] updateService:model image:self.selectedImage auditNote:auditNote completion:completion];
    } else {
        [[PPServiceManager sharedManager] addService:model image:self.selectedImage auditNote:auditNote completion:completion];
    }
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
    if (!firstResult) {
        return;
    }

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
    if (!image) {
        return;
    }
    self.selectedImage = image;
    self.heroImageView.image = image;
    self.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
}

#pragma mark - JSON

- (NSDictionary *)dictionaryFromJSONText:(NSString *)jsonText error:(NSError * _Nullable __autoreleasing *)errorPointer {
    NSString *trimmed = [[PPSafeString(jsonText) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (trimmed.length == 0) {
        return @{};
    }

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
    if (safe.count == 0) {
        return @"";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

@end
