//
//  PPAddEditVetViewController.m
//  PurePetsAdmin
//

#import "PPAddEditVetViewController.h"
#import "PPVetModel.h"
#import "PPVetManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import <PhotosUI/PhotosUI.h>
@import Firebase;
@import FirebaseAuth;
static NSString * const kTagTitle       = @"vetTitle";
static NSString * const kTagPhone       = @"vetPhone";
static NSString * const kTagWhatsapp    = @"vetWhatsapp";
static NSString * const kTagDesc        = @"vetDescription";
static NSString * const kTagType        = @"vetType";
static NSString * const kTagCost        = @"vetCost";
static NSString * const kTagDate        = @"vetAvailableDate";
static NSString * const kTagKindID      = @"vetPetMainKindID";

@interface PPAddEditVetViewController () <PHPickerViewControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UIImageView *logoImageView;
@property (nonatomic, strong, nullable) UIImage *selectedImage;
@property (nonatomic, assign) BOOL isEditing;
@end

@implementation PPAddEditVetViewController

- (instancetype)initWithVet:(PPVetModel *)vet {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    self = [super initWithForm:form style:UITableViewStyleInsetGrouped];
    if (self) {
        _vetToEdit = vet;
        _isEditing = (vet != nil);
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppForgroundColr;
    self.tableView.backgroundColor = AppForgroundColr;

    [self setupLogoHeader];
    [self buildForm];

    if (self.isEditing) {
        [self populateForm];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSString *title = self.isEditing ? kLang(@"Vet_Edit_Title") : kLang(@"Vet_Add_Title");
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:title showBack:YES];
}

#pragma mark - Logo Header

- (void)setupLogoHeader {
    CGFloat imgH = 180.0;
    CGFloat pad = 16.0;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, imgH + pad * 2)];
    container.backgroundColor = UIColor.clearColor;

    self.logoImageView = [[UIImageView alloc] init];
    self.logoImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logoImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.logoImageView.clipsToBounds = YES;
    self.logoImageView.layer.cornerRadius = 20;
    self.logoImageView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.06];
    self.logoImageView.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pickImageTapped)];
    [self.logoImageView addGestureRecognizer:tap];

    // Overlay icon
    UIImageView *cameraIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"camera.circle.fill"]];
    cameraIcon.translatesAutoresizingMaskIntoConstraints = NO;
    cameraIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    cameraIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.logoImageView addSubview:cameraIcon];

    [container addSubview:self.logoImageView];

    [NSLayoutConstraint activateConstraints:@[
        [self.logoImageView.topAnchor constraintEqualToAnchor:container.topAnchor constant:pad],
        [self.logoImageView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:pad],
        [self.logoImageView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-pad],
        [self.logoImageView.heightAnchor constraintEqualToConstant:imgH],

        [cameraIcon.centerXAnchor constraintEqualToAnchor:self.logoImageView.centerXAnchor],
        [cameraIcon.centerYAnchor constraintEqualToAnchor:self.logoImageView.centerYAnchor],
        [cameraIcon.widthAnchor constraintEqualToConstant:44],
        [cameraIcon.heightAnchor constraintEqualToConstant:44],
    ]];

    self.tableView.tableHeaderView = container;

    if (self.vetToEdit.logoURL.length > 0) {
        [self.logoImageView setImageFromUrl:self.vetToEdit.logoURL
                           placeholderImage:@"veterinary"
                                        Blr:YES
                                 Shimmering:YES
                                 completion:nil];
    } else {
        self.logoImageView.image = [UIImage systemImageNamed:@"stethoscope.circle.fill"];
        self.logoImageView.tintColor = AppPrimaryClr;
    }
}

#pragma mark - Form

- (void)buildForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    // ── Basic Info ──
    XLFormSectionDescriptor *infoSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Vet_Section_Info")];
    [form addFormSection:infoSection];

    XLFormRowDescriptor *titleRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagTitle rowType:XLFormRowDescriptorTypeText title:kLang(@"Vet_Field_Name")];
    titleRow.required = YES;
    [infoSection addFormRow:titleRow];

    XLFormRowDescriptor *typeRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagType rowType:XLFormRowDescriptorTypeSelectorSegmentedControl title:kLang(@"Vet_Field_Type")];
    typeRow.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPVetTypePersonal) displayText:kLang(@"Vet_Type_Personal")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPVetTypeCompany) displayText:kLang(@"Vet_Type_Company")]
    ];
    typeRow.value = [XLFormOptionsObject formOptionsObjectWithValue:@(PPVetTypePersonal) displayText:kLang(@"Vet_Type_Personal")];
    [infoSection addFormRow:typeRow];

    XLFormRowDescriptor *descRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagDesc rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Vet_Field_Description")];
    [infoSection addFormRow:descRow];

    // ── Contact ──
    XLFormSectionDescriptor *contactSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Vet_Section_Contact")];
    [form addFormSection:contactSection];

    XLFormRowDescriptor *phoneRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagPhone rowType:XLFormRowDescriptorTypePhone title:kLang(@"Vet_Field_Phone")];
    [contactSection addFormRow:phoneRow];

    XLFormRowDescriptor *whatsappRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagWhatsapp rowType:XLFormRowDescriptorTypePhone title:kLang(@"Vet_Field_Whatsapp")];
    [contactSection addFormRow:whatsappRow];

    // ── Details ──
    XLFormSectionDescriptor *detailSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Vet_Section_Details")];
    [form addFormSection:detailSection];

    XLFormRowDescriptor *costRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagCost rowType:XLFormRowDescriptorTypeDecimal title:kLang(@"Vet_Field_Cost")];
    [detailSection addFormRow:costRow];

    XLFormRowDescriptor *dateRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagDate rowType:XLFormRowDescriptorTypeDateInline title:kLang(@"Vet_Field_AvailableDate")];
    dateRow.value = [NSDate date];
    [detailSection addFormRow:dateRow];

    XLFormRowDescriptor *kindRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagKindID rowType:XLFormRowDescriptorTypeInteger title:kLang(@"Vet_Field_PetKindID")];
    kindRow.value = @(0);
    [detailSection addFormRow:kindRow];

    // ── Save Button ──
    XLFormSectionDescriptor *btnSection = [XLFormSectionDescriptor formSection];
    [form addFormSection:btnSection];

    XLFormRowDescriptor *saveRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"save" rowType:XLFormRowDescriptorTypeButton title:kLang(@"Vet_Action_Save")];
    saveRow.action.formSelector = @selector(saveTapped);
    [btnSection addFormRow:saveRow];

    self.form = form;
}

- (void)populateForm {
    PPVetModel *v = self.vetToEdit;
    [self.form formRowWithTag:kTagTitle].value = v.title;
    [self.form formRowWithTag:kTagPhone].value = v.phone;
    [self.form formRowWithTag:kTagWhatsapp].value = v.whatsapp;
    [self.form formRowWithTag:kTagDesc].value = v.descriptionText;
    [self.form formRowWithTag:kTagCost].value = @(v.vetCost);
    [self.form formRowWithTag:kTagDate].value = v.availableDate ?: [NSDate date];
    [self.form formRowWithTag:kTagKindID].value = @(v.petMainKindID);

    XLFormRowDescriptor *typeRow = [self.form formRowWithTag:kTagType];
    NSString *typeDisplay = (v.type == PPVetTypeCompany) ? kLang(@"Vet_Type_Company") : kLang(@"Vet_Type_Personal");
    typeRow.value = [XLFormOptionsObject formOptionsObjectWithValue:@(v.type) displayText:typeDisplay];
}

#pragma mark - Save

- (void)saveTapped {
    NSArray *errors = [self formValidationErrors];
    if (errors.count > 0) {
        [self showFormValidationError:errors.firstObject];
        return;
    }

    NSDictionary *values = [self formValues];

    PPVetModel *model = self.vetToEdit ? [self.vetToEdit copy] : [[PPVetModel alloc] init];
    model.title           = PPSafeString(values[kTagTitle]);
    model.phone           = PPSafeString(values[kTagPhone]);
    model.whatsapp        = PPSafeString(values[kTagWhatsapp]);
    model.descriptionText = PPSafeString(values[kTagDesc]);
    model.vetCost         = [values[kTagCost] doubleValue];
    model.availableDate   = values[kTagDate];
    model.petMainKindID   = [values[kTagKindID] integerValue];

    id typeVal = values[kTagType];
    if ([typeVal respondsToSelector:@selector(formValue)]) {
        model.type = [[typeVal formValue] integerValue];
    }

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
        [PPHUD showSuccess:kLang(@"Success_Title") subtitle:self.isEditing ? kLang(@"Vet_Updated_Success") : kLang(@"Vet_Added_Success")];
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
                });
            }
        }];
    }
}

@end
