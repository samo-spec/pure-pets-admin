#import "PPCategoryEditorViewController.h"
#import "SubKindModel.h"
@import Firebase;
@import FirebaseAuth;
@interface PPCategoryEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong, nullable) MainKindsModel *category;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, strong) NSMutableDictionary *draft;
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, strong) UIView *previewCard;
@property (nonatomic, strong) UIImageView *previewIcon;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@end

@implementation PPCategoryEditorViewController

- (instancetype)initWithCategory:(nullable MainKindsModel *)category {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _category = category;
        _isNew = category == nil;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigation];
    [self setupDraft];
    [self setupTableView];
}

- (void)setupNavigation {
    self.title = self.isNew ? kLang(@"Category_New") : kLang(@"Category_Edit");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    
    self.saveButton = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Save")
                                                       style:UIBarButtonItemStyleDone
                                                      target:self
                                                      action:@selector(didTapSave)];
    self.saveButton.tintColor = AppPrimaryClr;
    self.navigationItem.rightBarButtonItem = self.saveButton;
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)setupDraft {
    self.draft = [NSMutableDictionary dictionary];
    if (self.category) {
        self.draft[@"documentID"] = self.category.documentID ?: @"";
        self.draft[@"ID"] = @(self.category.ID);
        self.draft[@"sortingKey"] = @(self.category.sortingKey);
        self.draft[@"KindNameEn"] = self.category.KindNameEn ?: @"";
        self.draft[@"KindNameAr"] = self.category.KindNameAr ?: @"";
        self.draft[@"KindImageNamed"] = self.category.KindImageNamed ?: @"";
        self.draft[@"KindIconName"] = self.category.KindIconName ?: @"";
        self.draft[@"KindImageUrl"] = self.category.KindImageUrl ?: @"";
        self.draft[@"LightenAmount"] = @(self.category.LightenAmount);
        self.draft[@"professionalAngle"] = @(self.category.professionalAngle);
        self.draft[@"visible"] = @(self.category.is_visible_in_user_app);
    } else {
        self.draft[@"documentID"] = @"";
        self.draft[@"ID"] = @(0);
        self.draft[@"sortingKey"] = @(0);
        self.draft[@"KindNameEn"] = @"";
        self.draft[@"KindNameAr"] = @"";
        self.draft[@"KindImageNamed"] = @"";
        self.draft[@"KindIconName"] = @"";
        self.draft[@"KindImageUrl"] = @"";
        self.draft[@"LightenAmount"] = @(0.0);
        self.draft[@"professionalAngle"] = @(0.0);
        self.draft[@"visible"] = @(YES);
    }
}

- (void)setupTableView {
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"FieldCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"SwitchCell"];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}

#pragma mark - Preview Header

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != 0) return nil;
    if (!self.previewCard) {
        self.previewCard = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 100)];
        
        UIView *card = [[UIView alloc] init];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        PPApplyContinuousCorners(card, PPCornerMedium);
        PPApplyCardShadow(card);
        [self.previewCard addSubview:card];
        
        self.previewIcon = [[UIImageView alloc] init];
        self.previewIcon.translatesAutoresizingMaskIntoConstraints = NO;
        self.previewIcon.layer.cornerRadius = PPSpaceXXL;
        self.previewIcon.clipsToBounds = YES;
        self.previewIcon.contentMode = UIViewContentModeCenter;
        self.previewIcon.tintColor = [UIColor whiteColor];
        [card addSubview:self.previewIcon];
        
        self.previewLabel = [[UILabel alloc] init];
        self.previewLabel.font = PPFontMedium(PPFontTitle3);
        self.previewLabel.textAlignment = NSTextAlignmentNatural;
        [card addSubview:self.previewLabel];
        
        UILabel *hintLabel = [[UILabel alloc] init];
        hintLabel.font = PPFontRegular(PPFontCaption1);
        hintLabel.textColor = [UIColor ppTextTertiary];
        hintLabel.text = kLang(@"Category_Editor_Hint");
        hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:hintLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [card.leadingAnchor constraintEqualToAnchor:self.previewCard.leadingAnchor constant:PPSpaceBase],
            [card.trailingAnchor constraintEqualToAnchor:self.previewCard.trailingAnchor constant:-PPSpaceBase],
            [card.topAnchor constraintEqualToAnchor:self.previewCard.topAnchor constant:PPSpaceMD],
            [card.bottomAnchor constraintEqualToAnchor:self.previewCard.bottomAnchor constant:-PPSpaceSM],
            
            [self.previewIcon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceLG],
            [self.previewIcon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [self.previewIcon.widthAnchor constraintEqualToConstant:PPSpace4XL + 4],
            [self.previewIcon.heightAnchor constraintEqualToConstant:PPSpace4XL + 4],
            
            [self.previewLabel.leadingAnchor constraintEqualToAnchor:self.previewIcon.trailingAnchor constant:PPSpaceMD],
            [self.previewLabel.topAnchor constraintEqualToAnchor:self.previewIcon.topAnchor constant:PPSpaceXS],
            [self.previewLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceLG],
            
            [hintLabel.leadingAnchor constraintEqualToAnchor:self.previewLabel.leadingAnchor],
            [hintLabel.topAnchor constraintEqualToAnchor:self.previewLabel.bottomAnchor constant:PPSpaceXXS],
            [hintLabel.trailingAnchor constraintEqualToAnchor:self.previewLabel.trailingAnchor],
        ]];
        
        card.backgroundColor = [UIColor ppBackground];
    }
    
    UIColor *tintColor = self.category ? [self.category kindColor] : AppPrimaryClr;
    self.previewIcon.backgroundColor = tintColor;
    NSString *iconName = [self.draft[@"KindIconName"] length] > 0 ? self.draft[@"KindIconName"] : @"pawprint";
    self.previewIcon.image = [[UIImage systemImageNamed:iconName] imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:PPSpaceLG weight:UIImageSymbolWeightMedium]];
    NSString *name = self.draft[@"KindNameEn"];
    if (name.length == 0) name = self.draft[@"KindNameAr"];
    self.previewLabel.text = name.length > 0 ? name : kLang(@"Category_New");
    
    return self.previewCard;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 110 : UITableViewAutomaticDimension;
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.isNew ? 4 : 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return nil;
        case 1: return kLang(@"Category_Identity");
        case 2: return kLang(@"Category_Names");
        case 3: return kLang(@"Category_Appearance");
        case 4: return kLang(@"Category_Settings");
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 0;
        case 1: return 3;
        case 2: return 2;
        case 3: return 4;
        case 4: return 1;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 4 && indexPath.row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SwitchCell" forIndexPath:indexPath];
        cell.textLabel.text = kLang(@"Categories_Visibility");
        cell.textLabel.font = PPFontRegular(PPFontBody);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UISwitch *sw = [cell.contentView viewWithTag:200];
        if (!sw) {
            sw = [[UISwitch alloc] init];
            sw.tag = 200;
            sw.onTintColor = AppPrimaryClr;
            [sw addTarget:self action:@selector(visibilityChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        sw.on = [self.draft[@"visible"] boolValue];
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FieldCell" forIndexPath:indexPath];
    cell.textLabel.font = PPFontRegular(PPFontBody);
    cell.textLabel.textColor = [UIColor ppTextPrimary];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    UITextField *tf = [cell.contentView viewWithTag:300];
    if (!tf) {
        tf = [[UITextField alloc] init];
        tf.tag = 300;
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.textAlignment = NSTextAlignmentNatural;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.returnKeyType = UIReturnKeyDone;
        tf.delegate = self;
        [cell.contentView addSubview:tf];
        
        [NSLayoutConstraint activateConstraints:@[
            [tf.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:PPSpaceMD],
            [tf.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [tf.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPSpaceBase],
        ]];
    }
    
    NSString *key = [self keyForIndexPath:indexPath];
    NSString *value = [self stringValueForKey:key];
    NSString *title = [self titleForIndexPath:indexPath];
    
    cell.textLabel.text = title;
    tf.placeholder = title;
    tf.text = value;
    tf.keyboardType = [self keyboardTypeForKey:key];
    tf.tag = 300 + indexPath.section * 10 + indexPath.row;
    
    if (indexPath.section == 1 && indexPath.row == 0) {
        tf.enabled = self.isNew;
        tf.textColor = self.isNew ? [UIColor ppTextPrimary] : [UIColor ppTextTertiary];
    } else {
        tf.enabled = YES;
        tf.textColor = [UIColor ppTextPrimary];
    }
    
    return cell;
}

#pragma mark - Field Mapping

- (NSString *)keyForIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1) {
        if (ip.row == 0) return @"documentID";
        if (ip.row == 1) return @"ID";
        if (ip.row == 2) return @"sortingKey";
    }
    if (ip.section == 2) {
        if (ip.row == 0) return @"KindNameEn";
        if (ip.row == 1) return @"KindNameAr";
    }
    if (ip.section == 3) {
        if (ip.row == 0) return @"KindImageNamed";
        if (ip.row == 1) return @"KindIconName";
        if (ip.row == 2) return @"KindImageUrl";
        if (ip.row == 3) return @"LightenAmount";
    }
    return @"";
}

- (NSString *)titleForIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1) {
        if (ip.row == 0) return kLang(@"Category_DocID");
        if (ip.row == 1) return kLang(@"Category_NumericID");
        if (ip.row == 2) return kLang(@"Category_SortingKey");
    }
    if (ip.section == 2) {
        if (ip.row == 0) return kLang(@"Category_NameEn");
        if (ip.row == 1) return kLang(@"Category_NameAr");
    }
    if (ip.section == 3) {
        if (ip.row == 0) return kLang(@"Category_ImageAsset");
        if (ip.row == 1) return kLang(@"Category_IconName");
        if (ip.row == 2) return kLang(@"Category_ImageURL");
        if (ip.row == 3) return kLang(@"Category_Lighten");
    }
    return @"";
}

- (NSString *)stringValueForKey:(NSString *)key {
    id val = self.draft[key];
    if ([val isKindOfClass:[NSNumber class]]) {
        return [NSString stringWithFormat:@"%@", val];
    }
    return val ?: @"";
}

- (UIKeyboardType)keyboardTypeForKey:(NSString *)key {
    if ([key isEqualToString:@"ID"] || [key isEqualToString:@"sortingKey"]) return UIKeyboardTypeNumberPad;
    if ([key isEqualToString:@"LightenAmount"] || [key isEqualToString:@"professionalAngle"]) return UIKeyboardTypeDecimalPad;
    if ([key isEqualToString:@"KindImageUrl"]) return UIKeyboardTypeURL;
    return UIKeyboardTypeDefault;
}

#pragma mark - Actions

- (void)visibilityChanged:(UISwitch *)sender {
    self.draft[@"visible"] = @(sender.on);
}

- (void)didTapSave {
    [self.view endEditing:YES];
    if (self.isSaving) return;
    
    NSString *docID = self.draft[@"documentID"];
    NSInteger numericID = [self.draft[@"ID"] integerValue];
    if (docID.length == 0 && numericID <= 0) {
        [PPHUD showError:kLang(@"Category_Error_ID")];
        return;
    }
    if (docID.length == 0) {
        docID = [NSString stringWithFormat:@"%ld", (long)numericID];
        self.draft[@"documentID"] = docID;
    }
    
    self.isSaving = YES;
    self.saveButton.enabled = NO;
    self.saveButton.title = kLang(@"Saving");
    
    NSDictionary *payload = @{
        @"ID": self.draft[@"ID"] ?: @(0),
        @"sortingKey": self.draft[@"sortingKey"] ?: @(0),
        @"KindNameEn": self.draft[@"KindNameEn"] ?: @"",
        @"KindNameAr": self.draft[@"KindNameAr"] ?: @"",
        @"KindImageNamed": self.draft[@"KindImageNamed"] ?: @"",
        @"KindIconName": self.draft[@"KindIconName"] ?: @"",
        @"documentID": docID,
        @"KindImageUrl": self.draft[@"KindImageUrl"] ?: @"",
        @"LightenAmount": self.draft[@"LightenAmount"] ?: @(0),
        @"professionalAngle": self.draft[@"professionalAngle"] ?: @(0),
        @"is_visible_in_user_app": self.draft[@"visible"] ?: @(YES),
        @"SubKindsArray": self.category.SubKindsArray ? [self subKindsToArray] : @[],
    };
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [[[[FIRFirestore firestore] collectionWithPath:@"MainKindsCollection"] documentWithPath:docID]
         setData:payload merge:YES completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isSaving = NO;
                self.saveButton.enabled = YES;
                self.saveButton.title = kLang(@"Save");
                
                if (error) {
                    [PPHUD showError:kLang(@"Error_Generic")];
                } else {
                    [PPHUD showSuccess:kLang(@"Category_Saved")];
                    [self writeAuditLog];
                    [self.navigationController popViewControllerAnimated:YES];
                }
            });
        }];
    });
}

- (NSArray *)subKindsToArray {
    NSMutableArray *result = [NSMutableArray array];
    for (SubKindModel *sub in self.category.SubKindsArray) {
        [result addObject:@{
            @"ID": @(sub.ID),
            @"MainKindID": @(sub.MainKindID),
            @"SubKindNameAr": sub.SubKindNameAr ?: @"",
            @"SubKindNameEn": sub.SubKindNameEn ?: @"",
            @"subKindIconUrl": sub.subKindIconUrl ?: @"",
            @"subKindIconBlurHash": sub.subKindIconBlurHash ?: @"",
            @"have_subSub": @(sub.have_subSub),
            @"have_items": @(sub.have_items),
            @"adultHood": @(sub.adultHood)
        }];
    }
    return result;
}

- (void)writeAuditLog {
    NSString *action = self.isNew ? @"create_category" : @"update_category";
    NSString *docID = self.draft[@"documentID"] ?: @"";
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
     setData:@{
        @"action": action,
        @"targetCollection": @"MainKindsCollection",
        @"targetId": docID,
        @"adminUid": uid,
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSIndexPath *ip = [self indexPathForTag:textField.tag];
    if (!ip) return;
    NSString *key = [self keyForIndexPath:ip];
    id value = textField.text ?: @"";
    if ([key isEqualToString:@"ID"] || [key isEqualToString:@"sortingKey"]) {
        value = @([textField.text integerValue]);
    } else if ([key isEqualToString:@"LightenAmount"] || [key isEqualToString:@"professionalAngle"]) {
        value = @([textField.text floatValue]);
    }
    self.draft[key] = value;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (NSIndexPath *)indexPathForTag:(NSInteger)tag {
    if (tag < 300) return nil;
    NSInteger offset = tag - 300;
    NSInteger section = offset / 10;
    NSInteger row = offset % 10;
    return [NSIndexPath indexPathForRow:row inSection:section];
}

@end
