#import "PPAgentEditorViewController.h"
#import "PPAgentModel.h"
#import "PPBranchModel.h"
#import "PPHUD.h"
#import "Language.h"
#import "Styling.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;

static NSString *const kFieldCell = @"FieldCell";
static NSString *const kSwitchCell = @"SwitchCell";
static NSString *const kPickerCell = @"PickerCell";

@interface PPAgentEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong, nullable) PPAgentModel *agent;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, strong) NSMutableDictionary *draft;
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) NSArray<PPBranchModel *> *branches;
@property (nonatomic, strong) NSArray<NSDictionary *> *roleOptions;
@property (nonatomic, assign) NSInteger selectedRoleIndex;
@property (nonatomic, strong) NSString *selectedBranchId;
@property (nonatomic, strong) NSString *selectedBranchNameEn;
@property (nonatomic, strong) NSString *selectedBranchNameAr;
@end

@implementation PPAgentEditorViewController

- (instancetype)initWithAgent:(nullable PPAgentModel *)agent {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _agent = agent;
        _isNew = agent == nil;
        _roleOptions = @[
            @{@"key": @"sales",   @"en": @"Sales",   @"ar": @"مبيعات"},
            @{@"key": @"manager", @"en": @"Manager", @"ar": @"مدير"},
            @{@"key": @"cashier", @"en": @"Cashier", @"ar": @"كاشير"},
            @{@"key": @"viewer",  @"en": @"Viewer",  @"ar": @"مشاهد"},
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigation];
    [self setupDraft];
    [self setupTableView];
    [self loadBranches];
}

- (void)setupNavigation {
    self.title = self.isNew ? kLang(@"Agents_New") : kLang(@"Agents_Edit");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    
    self.saveButton = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Save")
                                                       style:UIBarButtonItemStyleDone
                                                      target:self
                                                      action:@selector(didTapSave)];
    self.saveButton.tintColor = AppPrimaryClr;
    self.navigationItem.rightBarButtonItem = self.saveButton;
}

- (void)setupDraft {
    self.draft = [NSMutableDictionary dictionary];
    if (self.agent) {
        self.draft[@"nameEn"] = self.agent.nameEn ?: @"";
        self.draft[@"nameAr"] = self.agent.nameAr ?: @"";
        self.draft[@"email"] = self.agent.email ?: @"";
        self.draft[@"phone"] = self.agent.phone ?: @"";
        self.draft[@"uid"] = self.agent.uid ?: @"";
        self.draft[@"commissionRate"] = @(self.agent.commissionRate);
        self.draft[@"isActive"] = @(self.agent.isActive);
        self.selectedBranchId = self.agent.branchId;
        self.selectedBranchNameEn = self.agent.branchNameEn;
        self.selectedBranchNameAr = self.agent.branchNameAr;
        NSString *roleKey = [self.agent roleRawValue];
        for (NSInteger i = 0; i < self.roleOptions.count; i++) {
            if ([self.roleOptions[i][@"key"] isEqualToString:roleKey]) {
                self.selectedRoleIndex = i;
                break;
            }
        }
    } else {
        self.draft[@"nameEn"] = @"";
        self.draft[@"nameAr"] = @"";
        self.draft[@"email"] = @"";
        self.draft[@"phone"] = @"";
        self.draft[@"uid"] = [self generateUid];
        self.draft[@"commissionRate"] = @(0);
        self.draft[@"isActive"] = @(YES);
        self.selectedRoleIndex = 0;
    }
}

- (NSString *)generateUid {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *seg = [[uuid substringToIndex:8] uppercaseString];
    return [NSString stringWithFormat:@"PP-AGT-%@", seg];
}

- (void)loadBranches {
    [[[[FIRFirestore firestore] collectionWithPath:kPPBranchesCol]
      queryOrderedByField:@"createdAt" descending:NO]
     getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) return;
        NSMutableArray *items = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPBranchModel *branch = [PPBranchModel fromDictionary:doc.data withID:doc.documentID];
            if (branch.isActive) [items addObject:branch];
        }
        self.branches = items.copy;
        if (self.selectedBranchId) {
            BOOL stillExists = NO;
            for (PPBranchModel *b in self.branches) {
                if ([b.branchID isEqualToString:self.selectedBranchId]) {
                    stillExists = YES;
                    break;
                }
            }
            if (!stillExists) {
                self.selectedBranchId = nil;
                self.selectedBranchNameEn = nil;
                self.selectedBranchNameAr = nil;
            }
        }
        [self.tableView reloadData];
    }];
}

- (void)setupTableView {
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kFieldCell];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kSwitchCell];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kPickerCell];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return kLang(@"Agents_Identity");
        case 1: return kLang(@"Agents_Contact");
        case 2: return kLang(@"Agents_Assignment");
        case 3: return kLang(@"Agents_Commission");
        case 4: return kLang(@"Agents_Settings");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 3) {
        return kLang(@"Agents_Commission_Help");
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 3;
        case 1: return 2;
        case 2: return 2;
        case 3: return 1;
        case 4: return 1;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPickerCell forIndexPath:indexPath];
        cell.textLabel.font = PPFontRegular(PPFontBody);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        
        UILabel *valueLabel = [cell.contentView viewWithTag:400];
        if (!valueLabel) {
            valueLabel = [[UILabel alloc] init];
            valueLabel.tag = 400;
            valueLabel.font = PPFontRegular(PPFontBody);
            valueLabel.textColor = [UIColor secondaryLabelColor];
            valueLabel.textAlignment = NSTextAlignmentNatural;
            valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:valueLabel];
            
            [NSLayoutConstraint activateConstraints:@[
                [valueLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-(PPSpace4XL + PPSpaceBase)],
                [valueLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [valueLabel.leadingAnchor constraintEqualToAnchor:cell.textLabel.trailingAnchor constant:PPSpaceMD],
            ]];
        }
        
        if (indexPath.row == 0) {
            cell.textLabel.text = kLang(@"Agents_Branch");
            PPBranchModel *selected = [self selectedBranch];
            valueLabel.text = selected ? [selected localizedName] : (self.selectedBranchNameEn ?: kLang(@"Agents_Select_Branch"));
            valueLabel.textColor = selected ? [UIColor secondaryLabelColor] : [UIColor tertiaryLabelColor];
        } else {
            cell.textLabel.text = kLang(@"Agents_Role");
            valueLabel.text = [self localizedRoleName:self.selectedRoleIndex];
            valueLabel.textColor = [UIColor secondaryLabelColor];
        }
        return cell;
    }
    
    if (indexPath.section == 4) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSwitchCell forIndexPath:indexPath];
        cell.textLabel.text = kLang(@"Agents_Active");
        cell.textLabel.font = PPFontRegular(PPFontBody);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UISwitch *sw = [cell.contentView viewWithTag:200];
        if (!sw) {
            sw = [[UISwitch alloc] init];
            sw.tag = 200;
            sw.onTintColor = AppPrimaryClr;
            [sw addTarget:self action:@selector(activeChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        sw.on = [self.draft[@"isActive"] boolValue];
        return cell;
    }
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFieldCell forIndexPath:indexPath];
    cell.textLabel.font = PPFontRegular(PPFontBody);
    cell.textLabel.textColor = [UIColor labelColor];
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
    
    NSString *title = [self titleForRow:indexPath];
    NSString *key = [self keyForRow:indexPath];
    NSString *value = [self stringValueForKey:key];
    
    cell.textLabel.text = title;
    tf.placeholder = title;
    tf.text = value;
    tf.keyboardType = [self keyboardTypeForKey:key];
    tf.enabled = ![key isEqualToString:@"uid"];
    tf.textColor = [key isEqualToString:@"uid"] ? [UIColor tertiaryLabelColor] : [UIColor labelColor];
    
    return cell;
}

#pragma mark - Field Mapping

- (NSString *)keyForRow:(NSIndexPath *)ip {
    if (ip.section == 0) {
        if (ip.row == 0) return @"uid";
        if (ip.row == 1) return @"nameEn";
        if (ip.row == 2) return @"nameAr";
    }
    if (ip.section == 1) {
        if (ip.row == 0) return @"email";
        if (ip.row == 1) return @"phone";
    }
    if (ip.section == 3) return @"commissionRate";
    return @"";
}

- (NSString *)titleForRow:(NSIndexPath *)ip {
    if (ip.section == 0) {
        if (ip.row == 0) return kLang(@"Agents_Uid");
        if (ip.row == 1) return kLang(@"Agents_Name_En");
        if (ip.row == 2) return kLang(@"Agents_Name_Ar");
    }
    if (ip.section == 1) {
        if (ip.row == 0) return kLang(@"Agents_Email");
        if (ip.row == 1) return kLang(@"Agents_Phone");
    }
    if (ip.section == 3) return kLang(@"Agents_Commission");
    return @"";
}

- (NSString *)stringValueForKey:(NSString *)key {
    id val = self.draft[key];
    if ([val isKindOfClass:NSNumber.class]) {
        return [NSString stringWithFormat:@"%.1f", [val doubleValue]];
    }
    return val ?: @"";
}

- (UIKeyboardType)keyboardTypeForKey:(NSString *)key {
    if ([key isEqualToString:@"phone"]) return UIKeyboardTypePhonePad;
    if ([key isEqualToString:@"commissionRate"]) return UIKeyboardTypeDecimalPad;
    if ([key isEqualToString:@"email"]) return UIKeyboardTypeEmailAddress;
    return UIKeyboardTypeDefault;
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.view endEditing:YES];
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            [self showBranchPicker];
        } else {
            [self showRolePicker];
        }
    }
}

- (PPBranchModel *)selectedBranch {
    for (PPBranchModel *b in self.branches) {
        if ([b.branchID isEqualToString:self.selectedBranchId]) return b;
    }
    return nil;
}

- (NSString *)localizedRoleName:(NSInteger)index {
    BOOL ar = [Language isRTL];
    return index < self.roleOptions.count ? self.roleOptions[index][ar ? @"ar" : @"en"] : @"";
}

- (void)showBranchPicker {
    if (self.branches.count == 0) {
        [PPHUD showError:kLang(@"Agents_No_Branches")];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Agents_Select_Branch")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (PPBranchModel *branch in self.branches) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:[branch localizedName]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            self.selectedBranchId = branch.branchID;
            self.selectedBranchNameEn = branch.nameEn;
            self.selectedBranchNameAr = branch.nameAr;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationAutomatic];
        }];
        [alert addAction:action];
    }
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancel];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        alert.popoverPresentationController.sourceView = cell ?: self.tableView;
        alert.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(0, 0, 320, 44);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRolePicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Agents_Role")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    BOOL ar = [Language isRTL];
    for (NSInteger i = 0; i < self.roleOptions.count; i++) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:self.roleOptions[i][ar ? @"ar" : @"en"]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            self.selectedRoleIndex = i;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationAutomatic];
        }];
        [alert addAction:action];
    }
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancel];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
        alert.popoverPresentationController.sourceView = cell ?: self.tableView;
        alert.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(0, 0, 320, 44);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)activeChanged:(UISwitch *)sender {
    self.draft[@"isActive"] = @(sender.on);
}

- (void)didTapSave {
    [self.view endEditing:YES];
    if (self.isSaving) return;
    
    NSString *nameEn = self.draft[@"nameEn"];
    NSString *nameAr = self.draft[@"nameAr"];
    if (nameEn.length == 0 && nameAr.length == 0) {
        [PPHUD showError:kLang(@"Agents_Name_Required")];
        return;
    }
    if (self.selectedBranchId.length == 0) {
        [PPHUD showError:kLang(@"Agents_Branch_Required")];
        return;
    }
    
    double commission = [self.draft[@"commissionRate"] doubleValue];
    if (commission < 0 || commission > 100) {
        [PPHUD showError:kLang(@"Agents_Commission_Invalid")];
        return;
    }
    
    self.isSaving = YES;
    self.saveButton.enabled = NO;
    self.saveButton.title = kLang(@"Saving");
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self executeSave];
    });
}

- (void)executeSave {
    FIRFirestore *db = [FIRFirestore firestore];
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSString *nameEn = self.draft[@"nameEn"] ?: @"";
    NSString *nameAr = self.draft[@"nameAr"] ?: @"";
    
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"name"] = @{@"ar": nameAr, @"en": nameEn};
    payload[@"nameEn"] = nameEn;
    payload[@"nameAr"] = nameAr;
    payload[@"email"] = self.draft[@"email"] ?: @"";
    payload[@"phone"] = self.draft[@"phone"] ?: @"";
    payload[@"branchId"] = self.selectedBranchId ?: @"";
    
    PPBranchModel *branch = [self selectedBranch];
    payload[@"branchName"] = @{
        @"ar": branch.nameAr ?: (self.selectedBranchNameAr ?: @""),
        @"en": branch.nameEn ?: (self.selectedBranchNameEn ?: @""),
    };
    
    NSString *roleKey = self.selectedRoleIndex < self.roleOptions.count ? self.roleOptions[self.selectedRoleIndex][@"key"] : @"sales";
    payload[@"role"] = roleKey;
    payload[@"commissionRate"] = self.draft[@"commissionRate"] ?: @(0);
    payload[@"isActive"] = @([self.draft[@"isActive"] boolValue]);
    payload[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
    
    if (self.isNew) {
        payload[@"uid"] = self.draft[@"uid"] ?: @"";
        payload[@"createdAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        payload[@"createdBy"] = uid;
        
        [[[db collectionWithPath:kPPAgentsCol] documentWithAutoID]
         setData:payload completion:^(NSError *error) {
            [self handleSaveCompletion:error];
        }];
    } else {
        NSString *docID = self.agent.agentID;
        [[[db collectionWithPath:kPPAgentsCol] documentWithPath:docID]
         updateData:payload completion:^(NSError *error) {
            [self handleSaveCompletion:error];
        }];
    }
}

- (void)handleSaveCompletion:(NSError *)error {
        self.isSaving = NO;
        self.saveButton.enabled = YES;
        self.saveButton.title = kLang(@"Save");
        
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:self.isNew ? kLang(@"Agents_Created") : kLang(@"Agents_Updated")];
            [self writeAuditLog];
            [self.navigationController popViewControllerAnimated:YES];
        }
}

- (void)writeAuditLog {
    NSString *action = self.isNew ? @"create_agent" : @"update_agent";
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSString *targetId = self.agent.agentID ?: self.draft[@"uid"] ?: @"";
    
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
     setData:@{
        @"action": action,
        @"targetCollection": kPPAgentsCol,
        @"targetId": targetId,
        @"adminUid": uid,
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    UIView *cell = textField.superview;
    while (cell && ![cell isKindOfClass:UITableViewCell.class]) {
        cell = cell.superview;
    }
    if (!cell) return;
    NSIndexPath *ip = [self.tableView indexPathForCell:(UITableViewCell *)cell];
    if (!ip) return;
    
    NSString *key = [self keyForRow:ip];
    if ([key isEqualToString:@"commissionRate"]) {
        self.draft[key] = @([textField.text doubleValue]);
    } else {
        self.draft[key] = textField.text ?: @"";
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
