//
//  BlockUserViewController.m
//  PurePetsAdmin
//

#import "BlockUserViewController.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@interface BlockUserViewController ()
// UI
@property (nonatomic, strong) NSMutableArray<UserModel *> *availableUsers; // header animation (150)
@property (nonatomic, strong) UserModel *selectedUser;
@property (nonatomic, strong) NSString *selectedUserID;
@property (nonatomic, strong) NSMutableArray<UserModel *> *cachedUsers;


@end
// In MyFormViewController.h  (or wherever you call the picker from)
typedef void(^PPUserPickedBlock)(NSString *displayName, NSString *uid, UIImage * _Nullable avatar);

@implementation BlockUserViewController

-(void)viewDidLoad
{
    [super viewDidLoad];
    [self cachedUsersfetching];
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
}


-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Nav
    //[self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:kLang(@"BlockUser_Title") showBack:YES];
    
    //UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    [self pp_navBarWithOtherButton:nil title:kLang(@"BlockUser_Title")];
}


#pragma mark - Init
- (instancetype)init {
    XLFormDescriptor *form = [self buildForm];
    return [super initWithForm:form style:UITableViewStyleInsetGrouped];
}


#pragma mark - User Picker
- (void)cachedUsersfetching {
    // Safety: avoid retain cycles
    __weak typeof(self) weakSelf = self;

    [[UserManager shared] fetchAllUsersWithCompletion:^(NSArray<UserModel *> *users, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        
        if (error) { [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription]; return; }
        if (users.count == 0) { [AlertHelper showInfoIn:self title:kLang(@"Info") subtitle:kLang(@"NoUsersFound")]; return; }
        self.cachedUsers = users.mutableCopy;
        
    }];
    
}


#pragma mark - User Picker
- (void)didTapSelectUser:(XLFormRowDescriptor *)row pickerCompletion:(PPUserPickedBlock)pickerCompletion {
    // Safety: avoid retain cycles
    __weak typeof(self) weakSelf = self;

    [[UserManager shared] fetchAllUsersWithCompletion:^(NSArray<UserModel *> *users, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        
        if (error) { [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription]; return; }
        if (users.count == 0) { [AlertHelper showInfoIn:self title:kLang(@"Info") subtitle:kLang(@"NoUsersFound")]; return; }
        self.cachedUsers = users.mutableCopy;
        
    }];
    
}



#pragma mark - Build Form
- (XLFormDescriptor *)buildForm {
    DLog(@"[BuildForm] starting...");

    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    
    // Section
    XLFormSectionDescriptor *section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];
    
    // User Email/ID row
    XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:@"pick_user"
                                                                      rowType:XLFormRowDescriptorTypePickOption
                                                                        title:kLang(@"Select User")];
    row.height = 70.0;
    DLog(@"[BuildForm] created row pick_user with type=%@", row.rowType);
    __weak typeof(self) weakSelf = self;
    row.cellConfig[@"onPickTap"] = ^(XLFormRowDescriptor *r) {
        __strong typeof(weakSelf) self = weakSelf;
        NSArray *options = self.cachedUsers ?: @[];
        
        PPSelectOptionViewController *vc =
        [[PPSelectOptionViewController alloc] initWithCompletion:^(id selected) {
            DLog(@"[PickUser] completion fired with selected=%@", selected);
            self.selectedUser = selected;
             [self pp_updatePickRow:r withUser:self.selectedUser];
            DLog(@"[PickUser] \nrow.value \nupdated='%@' \nuid='%@' \nselectedUser=%@", self.selectedUser.UserName, self.selectedUser.uid, self.selectedUser);
        }];

        // 3) Supply data + references for XLForm updates
        vc.allOptions      = options;
        vc.filteredOptions = options;
        vc.rowDescriptor   = r;
        vc.parentForm      = self;
        vc.imageLoaded = NO;
        vc.presentationStyle = PPSelectOptionPresentationSheet;
        vc.title = kLang(@"Select User");
        vc.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

        vc.modalPresentationCapturesStatusBarAppearance = YES;
        vc.view.backgroundColor = UIColor.systemBackgroundColor;
        vc.modalPresentationStyle = UIModalPresentationPageSheet;
        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = vc.sheetPresentationController;
            if (sheet) {
                sheet.detents = @[
                    [UISheetPresentationControllerDetent mediumDetent],
                    [UISheetPresentationControllerDetent largeDetent]
                ];
                sheet.prefersGrabberVisible = YES;
                sheet.preferredCornerRadius = 26.0;
                sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
            }
        }
       [self presentViewController:vc animated:YES completion:nil];
    };
    [section addFormRow:row];

    
    // Reason
    XLFormRowDescriptor *reasonRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"reason"
                                                                           rowType:XLFormRowDescriptorTypeTextView
                                                                             title:kLang(@"BlockUser_Reason")];
    reasonRow.cellConfigAtConfigure[@"textView.placeholder"] = kLang(@"BlockUser_Reason_Placeholder");
    [section addFormRow:reasonRow];
    DLog(@"[BuildForm] added row reason");

    // Duration
    XLFormRowDescriptor *durationRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"duration"
                                                                             rowType:XLFormRowDescriptorTypeSelectorSegmentedControl
                                                                               title:kLang(@"BlockUser_Duration")];
    durationRow.selectorOptions = @[kLang(@"BlockUser_Permanent"),
                                    kLang(@"BlockUser_7Days"),
                                    kLang(@"BlockUser_30Days")];
    durationRow.value = kLang(@"BlockUser_Permanent");
    durationRow.height = 50;
    [section addFormRow:durationRow];
    DLog(@"[BuildForm] added row duration with default=%@", durationRow.value);

    // Action Section
    XLFormSectionDescriptor *actionSection = [XLFormSectionDescriptor formSection];
    [form addFormSection:actionSection];
    
    XLFormRowDescriptor *saveRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"block"
                                                                         rowType:XLFormRowDescriptorTypeButton
                                                                           title:kLang(@"BlockUser_Action")];
    saveRow.action.formSelector = @selector(didTapBlock:);
    saveRow.cellConfig[@"textLabel.font"] = [Styling fontBold:16];
    saveRow.cellConfig[@"textLabel.textColor"] = [UIColor whiteColor];
    saveRow.cellConfig[@"backgroundColor"]     = AppPrimaryClr;
    saveRow.cellConfig[@"tintColor"]           = [UIColor whiteColor];
    [actionSection addFormRow:saveRow];
    DLog(@"[BuildForm] added row block (button)");

    DLog(@"[BuildForm] finished building form");
    return form;
}

// In AdminFormViewController.m — helper to update a PickOption row with a UserModel
- (void)pp_updatePickRow:(XLFormRowDescriptor *)row withUser:(UserModel *)user {
    PPItem *it = [PPItem itemWithID:(user.uid ?: user.ID ?: @"ID Not found")
                              title:(user.UserName ?: user.UserEmail ?: user.MobileNo ?: kLang(@"Select User"))];
    it.imageURLString = user.UserImageUrl.absoluteString;
    
    row.value = user;
    row.title = user.UserName ?: user.UserEmail ?: @"";
    [self updateFormRow:row];

    DLog(@"[PPUpdateRow] tag=%@ user=%@ (%@)", row.tag, it.title, it.itemID);
}


#pragma mark - Actions
- (void)didTapBlock:(XLFormRowDescriptor *)sender {
    NSDictionary *values = [self.form formValues];
    UserModel *picked = nil;
    id rawPick = values[@"pick_user"];
    if ([rawPick isKindOfClass:UserModel.class]) {
        picked = (UserModel *)rawPick;
    }
    if (!picked) {
        picked = self.selectedUser;
    }

    NSString *reason = values[@"reason"] ?: @"";
    NSString *duration = values[@"duration"];

    if (!picked.uid.length) {
        [self showAlert:kLang(@"Error") message:kLang(@"BlockUser_Error_UserRequired")];
        return;
    }

    if ([[FIRAuth auth].currentUser.uid isEqualToString:picked.uid]) {
        [self showAlert:kLang(@"Error") message:kLang(@"StatusNoAccess")];
        return;
    }

    BOOL shouldBlock = !picked.isBlocked;
    [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:kLang(@"Please wait")];

    [RPM setBlocked:shouldBlock
             forUID:picked.uid
             reason:(shouldBlock ? reason : nil)
           duration:(shouldBlock ? duration : nil)
         completion:^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [self showAlert:kLang(@"Error") message:error.localizedDescription];
            return;
        }
        picked.isBlocked = shouldBlock;
        self.selectedUser = picked;
        [self showAlert:kLang(@"Success")
                message:(shouldBlock ? kLang(@"BlockUser_Success") : kLang(@"SetStatusUnBlocked"))];
    }];
}

#pragma mark - Helpers
- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:kLang(@"OK") style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

// Add this flag somewhere (property or global)
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO buttonRowIndex:0 buttonSection:1];
}

@end
