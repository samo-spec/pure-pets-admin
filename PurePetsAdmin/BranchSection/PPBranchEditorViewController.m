//
//  PPBranchEditorViewController.m
//  PurePetsAdmin
//
//  Branch editor — Apple Design Award–caliber UIKit form.
//  Preserves all business logic, Firestore writes, permission-driven
//  default-branch mutual exclusion, audit logging, and validation.
//

#import "PPBranchEditorViewController.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;

#pragma mark - Font Helpers (Dynamic Type)

static UIFont *PPBranchScaled(UIFont *base, UIFontTextStyle style) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
    }
    return base;
}
static UIFont *PPBranchMedium(CGFloat size, UIFontTextStyle style) {
    return PPBranchScaled(PPFontMedium(size), style);
}
static UIFont *PPBranchRegular(CGFloat size, UIFontTextStyle style) {
    return PPBranchScaled(PPFontRegular(size), style);
}

#pragma mark - TextField Key Association

@interface UITextField (PPBranchKey)
@property (nonatomic, copy, nullable) NSString *pp_branchKey;
@end

@implementation UITextField (PPBranchKey)
- (void)setPp_branchKey:(NSString *)pp_branchKey {
    objc_setAssociatedObject(self, @selector(pp_branchKey), pp_branchKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
- (NSString *)pp_branchKey {
    return objc_getAssociatedObject(self, @selector(pp_branchKey));
}
@end

#pragma mark - PPFieldCell

@interface PPFieldCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, strong) UIView *bottomLine;
- (void)setFocused:(BOOL)focused;
- (void)configureWithTitle:(NSString *)title
                  value:(NSString *)value
             placeholder:(NSString *)placeholder
             keyboardType:(UIKeyboardType)keyboardType
               editable:(BOOL)editable;
@end

@implementation PPFieldCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPBranchMedium(PPFontCaption1, UIFontTextStyleCaption1);
        _titleLabel.textColor = [UIColor ppTextSecondary];
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_titleLabel];

        _textField = [[UITextField alloc] init];
        _textField.font = PPBranchRegular(PPFontBody, UIFontTextStyleBody);
        _textField.textColor = [UIColor ppTextPrimary];
        _textField.textAlignment = Language.alignmentForCurrentLanguage;
        _textField.autocorrectionType = UITextAutocorrectionTypeNo;
        _textField.returnKeyType = UIReturnKeyNext;
        _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _textField.tintColor = AppPrimaryClr;
        _textField.adjustsFontForContentSizeCategory = YES;
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_textField];

        _bottomLine = [[UIView alloc] init];
        _bottomLine.backgroundColor = [UIColor ppSeparator];
        _bottomLine.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_bottomLine];

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:PPSpaceMD],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor],

            [_textField.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],
            [_textField.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_textField.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],

            [_bottomLine.topAnchor constraintEqualToAnchor:_textField.bottomAnchor constant:PPSpaceSM],
            [_bottomLine.leadingAnchor constraintEqualToAnchor:_textField.leadingAnchor],
            [_bottomLine.trailingAnchor constraintEqualToAnchor:_textField.trailingAnchor],
            [_bottomLine.heightAnchor constraintEqualToConstant:1.5 / UIScreen.mainScreen.scale],
            [_bottomLine.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-PPSpaceMD],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                  value:(NSString *)value
             placeholder:(NSString *)placeholder
             keyboardType:(UIKeyboardType)keyboardType
               editable:(BOOL)editable {
    self.titleLabel.text = title;
    self.textField.text = value;
    self.textField.placeholder = placeholder;
    self.textField.keyboardType = keyboardType;
    self.textField.enabled = editable;
    self.textField.textColor = editable ? [UIColor ppTextPrimary] : [UIColor ppTextTertiary];
    [self setFocused:NO animated:NO];
}

- (void)setFocused:(BOOL)focused {
    [self setFocused:focused animated:YES];
}

- (void)setFocused:(BOOL)focused animated:(BOOL)animated {
    UIColor *target = focused ? [UIColor ppPrimary] : [UIColor ppSeparator];
    if (!animated) {
        self.bottomLine.backgroundColor = target;
        return;
    }
    [UIView animateWithDuration:PPAnimDurationNormal delay:0
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.bottomLine.backgroundColor = target;
    } completion:nil];
}

@end

#pragma mark - PPSegmentCell

@interface PPSegmentCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISegmentedControl *segment;
@property (nonatomic, copy) void (^onChange)(NSInteger index);
- (void)configureWithTitle:(NSString *)title
                  options:(NSArray<NSString *> *)options
            selectedIndex:(NSInteger)index;
@end

@implementation PPSegmentCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPBranchMedium(PPFontCaption1, UIFontTextStyleCaption1);
        _titleLabel.textColor = [UIColor ppTextSecondary];
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_titleLabel];

        _segment = [[UISegmentedControl alloc] init];
        _segment.selectedSegmentTintColor = AppPrimaryClr;
        _segment.translatesAutoresizingMaskIntoConstraints = NO;
        [_segment setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor],
                                         NSFontAttributeName: PPBranchMedium(PPFontSubheadline, UIFontTextStyleSubheadline)}
                                  forState:UIControlStateSelected];
        [_segment addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:_segment];

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:PPSpaceMD],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor],

            [_segment.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceSM],
            [_segment.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_segment.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [_segment.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-PPSpaceMD],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                  options:(NSArray<NSString *> *)options
            selectedIndex:(NSInteger)index {
    self.titleLabel.text = title;
    if (self.segment.numberOfSegments != options.count) {
        [self.segment removeAllSegments];
        for (NSInteger i = 0; i < options.count; i++) {
            [self.segment insertSegmentWithTitle:options[i] atIndex:i animated:NO];
        }
    } else {
        for (NSInteger i = 0; i < options.count; i++) {
            [self.segment setTitle:options[i] forSegmentAtIndex:i];
        }
    }
    self.segment.selectedSegmentIndex = index;
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    if (self.onChange) self.onChange(sender.selectedSegmentIndex);
}

@end

#pragma mark - PPSwitchCell

@interface PPSwitchCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UISwitch *toggle;
- (void)configureWithTitle:(NSString *)title on:(BOOL)on;
@end

@implementation PPSwitchCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPBranchRegular(PPFontBody, UIFontTextStyleBody);
        _titleLabel.textColor = [UIColor ppTextPrimary];
        _titleLabel.numberOfLines = 0;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_titleLabel];

        _toggle = [[UISwitch alloc] init];
        _toggle.onTintColor = AppPrimaryClr;
        _toggle.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_toggle];

        UILayoutGuide *guide = self.contentView.layoutMarginsGuide;

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor constant:-PPSpaceMD],
            [_titleLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:PPSpaceMD],
            [_titleLabel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-PPSpaceMD],

            [_toggle.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title on:(BOOL)on {
    self.titleLabel.text = title;
    self.toggle.on = on;
}

@end

#pragma mark - PPBranchEditorViewController

static NSString *const kFieldCellID = @"PPFieldCell";
static NSString *const kSegmentCellID = @"PPSegmentCell";
static NSString *const kSwitchCellID = @"PPSwitchCell";

@interface PPBranchEditorViewController () <UITextFieldDelegate>
@property (nonatomic, strong, nullable) PPBranchModel *branch;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, strong) NSMutableDictionary *draft;
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) NSArray<NSString *> *stockModeOptions;
@property (nonatomic, strong) NSArray<NSString *> *stockModeValues;
@property (nonatomic, assign) NSInteger selectedStockIndex;
@property (nonatomic, strong) NSMapTable<UITextField *, NSString *> *fieldKeys;
@end

@implementation PPBranchEditorViewController

- (instancetype)initWithBranch:(nullable PPBranchModel *)branch {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _branch = branch;
        _isNew = branch == nil;
        _stockModeOptions = @[kLang(@"Branches_Stock_Shared"), kLang(@"Branches_Stock_Separate")];
        _stockModeValues = @[@"shared", @"separate"];
        _fieldKeys = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    [self setupNavigation];
    [self setupDraft];
    [self setupTableView];
    [self registerKeyboard];
}

- (void)setupNavigation {
    self.title = self.isNew ? kLang(@"Branches_New") : kLang(@"Branches_Edit");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.saveButton = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Save")
                                                       style:UIBarButtonItemStyleDone
                                                      target:self
                                                      action:@selector(didTapSave)];
    self.saveButton.tintColor = AppPrimaryClr;
    self.saveButton.accessibilityLabel = kLang(@"Save");
    self.navigationItem.rightBarButtonItem = self.saveButton;
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)setupDraft {
    self.draft = [NSMutableDictionary dictionary];
    if (self.branch) {
        self.draft[@"nameEn"] = self.branch.nameEn ?: @"";
        self.draft[@"nameAr"] = self.branch.nameAr ?: @"";
        self.draft[@"address"] = self.branch.address ?: @"";
        self.draft[@"phone"] = self.branch.phone ?: @"";
        self.draft[@"code"] = self.branch.code ?: @"";
        self.draft[@"isDefault"] = @(self.branch.isDefault);
        NSString *raw = [self.branch stockModeRawValue];
        self.selectedStockIndex = [raw isEqualToString:@"branch"] ? 0 : 1;
    } else {
        self.draft[@"nameEn"] = @"";
        self.draft[@"nameAr"] = @"";
        self.draft[@"address"] = @"";
        self.draft[@"phone"] = @"";
        self.draft[@"code"] = [self generateCode];
        self.draft[@"isDefault"] = @(NO);
        self.selectedStockIndex = 1;
    }
    self.draft[@"stockMode"] = self.stockModeValues[self.selectedStockIndex];
}

- (NSString *)generateCode {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *seg = [[uuid substringToIndex:8] uppercaseString];
    return [NSString stringWithFormat:@"PP-BRCH-%@", seg];
}

- (void)setupTableView {
    [self.tableView registerClass:[PPFieldCell class] forCellReuseIdentifier:kFieldCellID];
    [self.tableView registerClass:[PPSegmentCell class] forCellReuseIdentifier:kSegmentCellID];
    [self.tableView registerClass:[PPSwitchCell class] forCellReuseIdentifier:kSwitchCellID];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Keyboard

- (void)registerKeyboard {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChange:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillChange:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect endFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    BOOL hiding = note.name == UIKeyboardWillHideNotification;
    CGFloat bottom = hiding ? 0 : (self.view.bounds.size.height - endFrame.origin.y);

    [UIView animateWithDuration:duration delay:0
                        options:(curve << 16)
                     animations:^{
        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0);
        self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottom, 0);
    } completion:nil];
}

#pragma mark - Field Mapping

- (NSString *)keyForRow:(NSIndexPath *)ip {
    if (ip.section == 0) {
        if (ip.row == 0) return @"code";
        if (ip.row == 1) return @"nameEn";
        if (ip.row == 2) return @"nameAr";
    }
    if (ip.section == 1) {
        if (ip.row == 0) return @"address";
        if (ip.row == 1) return @"phone";
    }
    return @"";
}

- (NSString *)titleForRow:(NSIndexPath *)ip {
    if (ip.section == 0) {
        if (ip.row == 0) return kLang(@"Branches_Code");
        if (ip.row == 1) return kLang(@"Branches_Name_En");
        if (ip.row == 2) return kLang(@"Branches_Name_Ar");
    }
    if (ip.section == 1) {
        if (ip.row == 0) return kLang(@"Branches_Address");
        if (ip.row == 1) return kLang(@"Branches_Phone");
    }
    return @"";
}

- (NSString *)stringValueForKey:(NSString *)key {
    id val = self.draft[key];
    if ([val isKindOfClass:NSNumber.class]) return [val stringValue];
    return val ?: @"";
}

- (UIKeyboardType)keyboardTypeForKey:(NSString *)key {
    if ([key isEqualToString:@"phone"]) return UIKeyboardTypePhonePad;
    return UIKeyboardTypeDefault;
}

- (NSArray<NSString *> *)orderedEditableKeys {
    return @[@"nameEn", @"nameAr", @"address", @"phone"];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return kLang(@"Branches_Info");
        case 1: return kLang(@"Branches_Contact");
        case 2: return kLang(@"Branches_Stock_Mode");
        case 3: return kLang(@"Branches_Settings");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2) {
        return self.selectedStockIndex == 0 ? kLang(@"Branches_Stock_Shared_Help") : kLang(@"Branches_Stock_Separate_Help");
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 3;
        case 1: return 2;
        case 2: return 1;
        case 3: return 1;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        PPSegmentCell *cell = [tableView dequeueReusableCellWithIdentifier:kSegmentCellID forIndexPath:indexPath];
        cell.titleLabel.text = kLang(@"Branches_Stock_Mode");
        [cell configureWithTitle:kLang(@"Branches_Stock_Mode")
                        options:self.stockModeOptions
                  selectedIndex:self.selectedStockIndex];
        PPweakify(self);
        cell.onChange = ^(NSInteger index) {
            PPstrongify(self);
            [self didChangeStockMode:index];
        };
        return cell;
    }

    if (indexPath.section == 3) {
        PPSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:kSwitchCellID forIndexPath:indexPath];
        [cell configureWithTitle:kLang(@"Branches_Default_Label") on:[self.draft[@"isDefault"] boolValue]];
        [cell.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
        [cell.toggle addTarget:self action:@selector(defaultChanged:) forControlEvents:UIControlEventValueChanged];
        return cell;
    }

    PPFieldCell *cell = [tableView dequeueReusableCellWithIdentifier:kFieldCellID forIndexPath:indexPath];
    NSString *key = [self keyForRow:indexPath];
    NSString *title = [self titleForRow:indexPath];
    NSString *value = [self stringValueForKey:key];
    BOOL editable = ![key isEqualToString:@"code"];

    cell.textField.delegate = self;
    cell.textField.pp_branchKey = key;
    [self.fieldKeys setObject:key forKey:cell.textField];
    cell.textField.returnKeyType = ([key isEqualToString:@"phone"]) ? UIReturnKeyDone : UIReturnKeyNext;

    [cell configureWithTitle:title
                      value:value
                 placeholder:title
                 keyboardType:[self keyboardTypeForKey:key]
                   editable:editable];

    cell.titleLabel.accessibilityLabel = title;
    return cell;
}

#pragma mark - Interactions

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)didChangeStockMode:(NSInteger)index {
    self.selectedStockIndex = index;
    self.draft[@"stockMode"] = self.stockModeValues[index];
    [PPFunc pp_playSelectionEffect];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)defaultChanged:(UISwitch *)sender {
    self.draft[@"isDefault"] = @(sender.on);
    [PPFunc pp_playTapEffect];
}

#pragma mark - Save

- (void)didTapSave {
    [self.view endEditing:YES];
    if (self.isSaving) return;

    NSString *nameEn = self.draft[@"nameEn"];
    NSString *nameAr = self.draft[@"nameAr"];
    if (nameEn.length == 0 && nameAr.length == 0) {
        [PPHUD showError:kLang(@"Branches_Name_Required")];
        [PPFunc pp_playErrorEffect];
        return;
    }

    self.isSaving = YES;
    self.saveButton.enabled = NO;
    self.saveButton.title = kLang(@"Saving");
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Saving") subtitle:nil];
    [PPFunc pp_playTapEffect];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        FIRFirestore *db = [FIRFirestore firestore];

        if ([self.draft[@"isDefault"] boolValue]) {
            FIRQuery *q = [[db collectionWithPath:kPPBranchesCol] queryWhereField:@"isDefault" isEqualTo:@(YES)];
            [q getDocumentsWithCompletion:^(FIRQuerySnapshot *snap, NSError *err) {
                for (FIRDocumentSnapshot *doc in snap.documents) {
                    if (![doc.documentID isEqualToString:self.branch.branchID]) {
                        [[[db collectionWithPath:kPPBranchesCol] documentWithPath:doc.documentID]
                         updateData:@{@"isDefault": @(NO), @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]}];
                    }
                }
                [self executeSave:db];
            }];
        } else {
            [self executeSave:db];
        }
    });
}

- (void)executeSave:(FIRFirestore *)db {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSString *stockRaw = [self.draft[@"stockMode"] isEqualToString:@"shared"] ? @"shared" : @"perAgent";

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    NSString *nameEn = self.draft[@"nameEn"] ?: @"";
    NSString *nameAr = self.draft[@"nameAr"] ?: @"";

    payload[@"name"] = @{@"ar": nameAr, @"en": nameEn};
    payload[@"nameAr"] = nameAr;
    payload[@"nameEn"] = nameEn;
    payload[@"address"] = self.draft[@"address"] ?: @"";
    payload[@"phone"] = self.draft[@"phone"] ?: @"";
    payload[@"stockMode"] = stockRaw;
    payload[@"isDefault"] = self.draft[@"isDefault"] ?: @(NO);
    payload[@"isActive"] = @(YES);
    payload[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];

    if (self.isNew) {
        payload[@"code"] = self.draft[@"code"] ?: @"";
        payload[@"createdAt"] = [FIRFieldValue fieldValueForServerTimestamp];
        payload[@"createdBy"] = uid;

        [[[db collectionWithPath:kPPBranchesCol] documentWithAutoID]
         setData:payload completion:^(NSError *error) {
            [self handleSaveCompletion:error];
        }];
    } else {
        NSString *docID = self.branch.branchID;
        [[[db collectionWithPath:kPPBranchesCol] documentWithPath:docID]
         updateData:payload completion:^(NSError *error) {
            [self handleSaveCompletion:error];
        }];
    }
}

- (void)handleSaveCompletion:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.isSaving = NO;
        self.saveButton.enabled = YES;
        self.saveButton.title = kLang(@"Save");
        [PPHUD dismiss];

        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
            [PPFunc pp_playErrorEffect];
        } else {
            [PPHUD showSuccess:self.isNew ? kLang(@"Branches_Created") : kLang(@"Branches_Updated")];
            [PPFunc pp_playSuccessEffect];
            [self writeAuditLog];
            [self.navigationController popViewControllerAnimated:YES];
        }
    });
}

- (void)writeAuditLog {
    NSString *action = self.isNew ? @"create_branch" : @"update_branch";
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    NSString *targetId = self.branch.branchID ?: self.draft[@"code"] ?: @"";

    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
     setData:@{
        @"action": action,
        @"targetCollection": kPPBranchesCol,
        @"targetId": targetId,
        @"adminUid": uid,
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    PPFieldCell *cell = [self cellForTextField:textField];
    [cell setFocused:YES];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    PPFieldCell *cell = [self cellForTextField:textField];
    [cell setFocused:NO];
    [self commitTextField:textField];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *key = textField.pp_branchKey;
    NSArray<NSString *> *ordered = [self orderedEditableKeys];
    NSUInteger idx = [ordered indexOfObject:key];
    if (idx != NSNotFound && idx + 1 < ordered.count) {
        NSString *nextKey = ordered[idx + 1];
        [self focusFieldWithKey:nextKey];
    } else {
        [textField resignFirstResponder];
        [self didTapSave];
    }
    return YES;
}

- (void)commitTextField:(UITextField *)textField {
    NSString *key = textField.pp_branchKey;
    if (key.length == 0) return;
    self.draft[key] = textField.text ?: @"";
}

- (PPFieldCell *)cellForTextField:(UITextField *)textField {
    UIView *view = textField.superview;
    while (view && ![view isKindOfClass:PPFieldCell.class]) {
        view = view.superview;
    }
    return (PPFieldCell *)view;
}

- (void)focusFieldWithKey:(NSString *)key {
    for (UITextField *tf in self.fieldKeys.keyEnumerator) {
        if ([[self.fieldKeys objectForKey:tf] isEqualToString:key]) {
            [tf becomeFirstResponder];
            return;
        }
    }
}

@end
