//
//  BlockUserViewController.m
//  PurePetsAdmin
//

#import "BlockUserViewController.h"
#import "PPAlertHelper.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;

@interface BlockUserViewController ()
// UI
@property (nonatomic, strong) NSMutableArray<UserModel *> *availableUsers; // header animation (150)
@property (nonatomic, strong) UserModel *selectedUser;
@property (nonatomic, strong) NSString *selectedUserID;
@property (nonatomic, strong) NSMutableArray<UserModel *> *cachedUsers;

- (void)pp_updatePickRow:(XLFormRowDescriptor *)row withUser:(UserModel *)user;

@end
// In MyFormViewController.h  (or wherever you call the picker from)
typedef void(^PPUserPickedBlock)(NSString *displayName, NSString *uid, UIImage * _Nullable avatar);

@implementation BlockUserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupHeaderView];
    [self cachedUsersfetching];
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.backgroundColor = [UIColor ppBackground];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        self.navigationController.navigationBarHidden = YES;
    }
}

- (void)setupHeaderView {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 140.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *navRow = [UIView new];
    navRow.translatesAutoresizingMaskIntoConstraints = NO;
    navRow.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:navRow];

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    backButton.tintColor = [UIColor ppPrimary];
    backButton.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    
    UIImageSymbolConfiguration *chevronConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    NSString *chevronName = [Language isRTL] ? @"chevron.right" : @"chevron.left";
    UIImage *chevronImg = [UIImage systemImageNamed:chevronName withConfiguration:chevronConfig];
    [backButton setImage:chevronImg forState:UIControlStateNormal];
    [backButton setTitle:[NSString stringWithFormat:@" %@", kLang(@"Back")] forState:UIControlStateNormal];
    [backButton setTitleColor:[UIColor ppPrimary] forState:UIControlStateNormal];
    backButton.titleLabel.font = [Styling fontBold:15.0];
    backButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    backButton.contentHorizontalAlignment = [Language isRTL] ? UIControlContentHorizontalAlignmentRight : UIControlContentHorizontalAlignmentLeft;
    [backButton addTarget:self action:@selector(didTapBack) forControlEvents:UIControlEventTouchUpInside];
    backButton.accessibilityLabel = kLang(@"Back");
    [navRow addSubview:backButton];

    UILabel *eyebrowLabel = [UILabel new];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:12.0]];
    eyebrowLabel.textColor = [UIColor ppTextSecondary];
    eyebrowLabel.textAlignment = Language.alignmentForCurrentLanguage;
    eyebrowLabel.adjustsFontForContentSizeCategory = YES;
    eyebrowLabel.numberOfLines = 1;
    eyebrowLabel.text = [NSString stringWithFormat:@"%@ / %@", kLang(@"CommandCenter_Customers_Workspace"), kLang(@"BlockUser_Title")];
    [header addSubview:eyebrowLabel];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:22.0]];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 1;
    titleLabel.text = kLang(@"BlockUser_Title");
    [header addSubview:titleLabel];

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:13.0]];
    subtitleLabel.textColor = [UIColor ppTextSecondary];
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.adjustsFontForContentSizeCategory = YES;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.text = kLang(@"MissionControl_Customers_Briefing");
    [header addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [navRow.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceXS],
        [navRow.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPSpaceBase],
        [navRow.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPSpaceBase],
        [navRow.heightAnchor constraintEqualToConstant:44.0],

        [backButton.leadingAnchor constraintEqualToAnchor:navRow.leadingAnchor],
        [backButton.centerYAnchor constraintEqualToAnchor:navRow.centerYAnchor],
        [backButton.heightAnchor constraintEqualToConstant:44.0],

        [eyebrowLabel.topAnchor constraintEqualToAnchor:navRow.bottomAnchor constant:2.0],
        [eyebrowLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPSpaceBase],
        [eyebrowLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPSpaceBase],

        [titleLabel.topAnchor constraintEqualToAnchor:eyebrowLabel.bottomAnchor constant:2.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPSpaceBase],
        [titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPSpaceBase],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPSpaceBase],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPSpaceBase],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceSM],
    ]];

    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(self.view.bounds.size.width, UILayoutFittingCompressedSize.height)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame = header.frame;
    frame.size.height = size.height;
    header.frame = frame;
    self.tableView.tableHeaderView = header;
}

- (void)didTapBack {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController || self.navigationController.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
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
        
        if (error) { [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription]; return; }
        if (users.count == 0) { [PPAlertHelper showInfoIn:self title:kLang(@"Info") subtitle:kLang(@"NoUsersFound")]; return; }
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
        
        if (error) { [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription]; return; }
        if (users.count == 0) { [PPAlertHelper showInfoIn:self title:kLang(@"Info") subtitle:kLang(@"NoUsersFound")]; return; }
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
        vc.view.backgroundColor = [UIColor ppSurface];
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
        if (self.navigationController) {
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            [self presentViewController:vc animated:YES completion:nil];
        }
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
    [PPAlertHelper showAlertIn:self title:title subtitle:msg];
}

// Add this flag somewhere (property or global)
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO buttonRowIndex:0 buttonSection:1];
}

@end
