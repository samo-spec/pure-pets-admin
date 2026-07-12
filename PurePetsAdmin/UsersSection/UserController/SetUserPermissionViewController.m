#import "SetUserPermissionViewController.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPUserCell.h"
#import "SetUserPermissionsRolesViewController.h"
#import "RPManager.h"
#import "FUManager.h"
#import "Styling.h"
#import "Language.h"
#import "PPFunc.h"
#import "PPToast.h"
#import <objc/runtime.h>
@import Firebase;
@import FirebaseAuth;
#define RPM [RPManager shared]

#pragma mark - PPUsersSummaryHeaderView

@interface PPUsersSummaryHeaderView : UIView
@property (nonatomic, strong) UILabel *totalVal;
@property (nonatomic, strong) UILabel *activeVal;
@property (nonatomic, strong) UILabel *verifiedVal;
@property (nonatomic, strong) UILabel *prodVal;

- (void)updateWithTotal:(NSInteger)total active:(NSInteger)active verified:(NSInteger)verified prod:(NSInteger)prod;
@end

@implementation PPUsersSummaryHeaderView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UIStackView *vStack = [[UIStackView alloc] init];
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 10;
    vStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:vStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [vStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [vStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [vStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [vStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12]
    ]];
    
    UIStackView *row1 = [[UIStackView alloc] init];
    row1.axis = UILayoutConstraintAxisHorizontal;
    row1.distribution = UIStackViewDistributionFillEqually;
    row1.spacing = 10;
    
    UIStackView *row2 = [[UIStackView alloc] init];
    row2.axis = UILayoutConstraintAxisHorizontal;
    row2.distribution = UIStackViewDistributionFillEqually;
    row2.spacing = 10;
    
    [vStack addArrangedSubview:row1];
    [vStack addArrangedSubview:row2];
    
    [row1 addArrangedSubview:[self makeChipWithIcon:@"person.3.fill" titleKey:@"Total_Users" valLabel:&_totalVal color:[UIColor systemBlueColor]]];
    [row1 addArrangedSubview:[self makeChipWithIcon:@"checkmark.circle.fill" titleKey:@"Active_Users" valLabel:&_activeVal color:[UIColor systemGreenColor]]];
    
    [row2 addArrangedSubview:[self makeChipWithIcon:@"patch.check.fill" titleKey:@"Verified_Users" valLabel:&_verifiedVal color:[UIColor systemIndigoColor]]];
    [row2 addArrangedSubview:[self makeChipWithIcon:@"shield.fill" titleKey:@"Production_Users" valLabel:&_prodVal color:[UIColor systemOrangeColor]]];
}

- (UIView *)makeChipWithIcon:(NSString *)iconName titleKey:(NSString *)titleKey valLabel:(UILabel * __strong *)valLabel color:(UIColor *)color {
    UIView *chip = [UIView new];
    chip.backgroundColor = AppBackgroundClrShiner;
    chip.layer.cornerRadius = 16;
    chip.layer.masksToBounds = YES;
    
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.tintColor = color;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *title = [UILabel new];
    title.text = kLang(titleKey);
    title.font = [Styling fontMedium:12];
    title.textColor = SeconderyTextClr;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *val = [UILabel new];
    val.text = @"0";
    val.font = [Styling fontBold:18];
    val.textColor = PrimaryTextClr;
    val.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (valLabel) *valLabel = val;
    
    [chip addSubview:icon];
    [chip addSubview:title];
    [chip addSubview:val];
    
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:chip.topAnchor constant:12],
        [icon.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:12],
        [icon.widthAnchor constraintEqualToConstant:20],
        [icon.heightAnchor constraintEqualToConstant:20],
        
        [val.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:4],
        [val.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:12],
        [val.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-12],
        
        [title.topAnchor constraintEqualToAnchor:val.bottomAnchor constant:2],
        [title.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor constant:12],
        [title.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor constant:-12],
        [title.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor constant:-12]
    ]];
    
    return chip;
}

- (void)updateWithTotal:(NSInteger)total active:(NSInteger)active verified:(NSInteger)verified prod:(NSInteger)prod {
    self.totalVal.text = [NSString stringWithFormat:@"%ld", (long)total];
    self.activeVal.text = [NSString stringWithFormat:@"%ld", (long)active];
    self.verifiedVal.text = [NSString stringWithFormat:@"%ld", (long)verified];
    self.prodVal.text = [NSString stringWithFormat:@"%ld", (long)prod];
}

@end

#pragma mark - SetUserPermissionViewController

@interface SetUserPermissionViewController () <UITableViewDelegate, UITableViewDataSource, PPSDelegate, UserCellDelegate>
@property (nonatomic, strong) id<FIRListenerRegistration> usersReg;
@property (nonatomic, strong) PPUsersSummaryHeaderView *summaryHeader;
@end

@implementation SetUserPermissionViewController
@synthesize rowDescriptor = _rowDescriptor;

- (instancetype)init {
    if (self = [super init]) {
        _viewForMode = ViewForDefault;
    }
    return self;
}

- (instancetype)initWithViewFor:(ViewFor)mode {
    if (self = [super init]) {
        _viewForMode = mode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    //self.title = kLang(@"UsersSection");
    if (self.viewForMode == ViewForPicker) {
        self.title = kLang(@"Staff_Select_Existing_User");
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                              target:self
                                                                                              action:@selector(pp_closePicker)];
    }
    self.view.backgroundColor = AppBackgroundClr;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = 90.0; // Increased for status pill
    self.tableView.showsVerticalScrollIndicator = NO;
    [self.tableView registerClass:PPUserCell.class forCellReuseIdentifier:PPUserCell.reuseIdentifier];
    [self.view addSubview:self.tableView];

    [self setupHeaderUI];

    self.allUsers = [NSMutableArray new];
    self.filteredUsers = [NSMutableArray new];

    __weak typeof(self) weakSelf = self;
    self.usersReg =
    [[FUManager shared] listenAllUsersWithDiffsOrderedBy:@"UserName"
                                               ascending:YES
                                    includeMetadataChanges:YES
                                                   queue:dispatch_get_main_queue()
                                                completion:^(NSArray<UserModel *> *users,
                                                             NSArray<FIRDocumentChange *> *changes,
                                                             FIRSnapshotMetadata *meta,
                                                             NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) return;

        self.allUsers = users.mutableCopy;
        [self _updateSummaryStats];
        [self _applyFilterAndReload];
    }];
}

- (void)dealloc { [self.usersReg remove]; }

- (void)setupHeaderUI {
    UIView *headerRoot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 240)];
    
    PPS *search = [[PPS alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    search.delegate = self;
    search.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.textField.textAlignment = Language.alignmentForCurrentLanguage;
    search.textField.placeholder = self.searchPlaceholderText.length ? self.searchPlaceholderText : kLang(@"SetPermissions_Search_Placeholder");
    [headerRoot addSubview:search];
    self.searchView = search;
    
    self.summaryHeader = [[PPUsersSummaryHeaderView alloc] initWithFrame:CGRectMake(0, 60, self.view.bounds.size.width, 180)];
    [headerRoot addSubview:self.summaryHeader];
    
    self.tableView.tableHeaderView = headerRoot;
}

- (void)pp_closePicker {
    if (self.presentingViewController || self.navigationController.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)_updateSummaryStats {
    NSInteger total = self.allUsers.count;
    NSInteger active = 0;
    NSInteger verified = 0;
    NSInteger prod = 0;
    
    for (UserModel *u in self.allUsers) {
        if (!u.isBlocked && (!u.accountStatus || [u.accountStatus isEqualToString:@"active"])) active++;
        if (u.isVerified) verified++;
        if ([u.prodectionStatus isEqualToString:@"active"]) prod++;
    }
    
    [self.summaryHeader updateWithTotal:total active:active verified:verified prod:prod];
}

#pragma mark - Search delegate

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.currentQuery = text ?: @"";
    [self _applyFilterAndReload];
}

- (void)_applyFilterAndReload {
    NSString *q = self.currentQuery ?: @"";
    if (q.length == 0) {
        self.filteredUsers = self.allUsers.mutableCopy;
    } else {
        NSString *needle = q.lowercaseString;
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(UserModel *u, NSDictionary *_) {
            return [u.UserName.lowercaseString containsString:needle] ||
                   [u.UserEmail.lowercaseString containsString:needle] ||
                   [u.MobileNo.lowercaseString containsString:needle] ||
                   [u.uid.lowercaseString containsString:needle];
        }];
        self.filteredUsers = [[self.allUsers filteredArrayUsingPredicate:p] mutableCopy];
    }
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredUsers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPUserCell *cell = [tableView dequeueReusableCellWithIdentifier:PPUserCell.reuseIdentifier forIndexPath:indexPath];
    UserModel *u = self.filteredUsers[indexPath.row];
    [cell configureWithUser:u indexPath:indexPath viewFor:self.viewForMode];
    cell.delegate = self;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UserModel *u = self.filteredUsers[indexPath.row];
    
    if (self.viewForMode == ViewForPicker) {
        void (^pickBlock)(UserModel *) = [self.onUserPicked copy];
        BOOL isPresented = (self.presentingViewController || self.navigationController.presentingViewController);
        void (^finishPick)(void) = ^{
            if ([self respondsToSelector:@selector(rowDescriptor)] && self.rowDescriptor) {
                self.rowDescriptor.value = u;
            }
            if (pickBlock) {
                pickBlock(u);
            }
        };

        if (isPresented) {
            [self dismissViewControllerAnimated:YES completion:finishPick];
        } else {
            finishPick();
            [self.navigationController popViewControllerAnimated:YES];
        }
        return;
    }
    
    EditType type = EditTypeDefault;
    if (self.viewForMode == ViewForEditAccount) type = EditTypeUserData;
    else if (self.viewForMode == ViewForEditRoleAndPermissions) type = EditTypeUserPermisstionAndRoles;
    
    SetUserPermissionsRolesViewController *vc = [[SetUserPermissionsRolesViewController alloc] initWithUser:u type:type];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)userCellDidTapAction:(PPUserCell *)cell user:(UserModel *)user {
    [self tableView:self.tableView didSelectRowAtIndexPath:cell.indexPath];
}

- (void)didTapAddUser {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"AddUser") message:kLang(@"Enter_Email_Password") preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Name");
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Email");
        textField.keyboardType = UIKeyboardTypeEmailAddress;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = kLang(@"Password");
        textField.secureTextEntry = YES;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *name = alert.textFields[0].text;
        NSString *email = alert.textFields[1].text;
        NSString *password = alert.textFields[2].text;
        
        if (name.length == 0 || email.length == 0 || password.length == 0) {
            [PPToast toast:kLang(@"Error_MissingFields")];
            return;
        }
        
        [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:@""];
        
        [[FUManager shared] createUserWithEmail:email password:password username:name role:0 permissions:nil isAdmin:NO completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPToast toast:error.localizedDescription];
            } else {
                [PPToast toast:kLang(@"Success")];
            }
        }];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UserModel *u = self.filteredUsers[indexPath.row];
    
    BOOL isBlocked = u.isBlocked;
    NSString *title = isBlocked ? kLang(@"Unblock") : kLang(@"BlockUser_Action");
    UIContextualAction *blockAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:title handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self pp_confirmBlockUser:u shouldBlock:!isBlocked completion:completionHandler];
    }];
    blockAction.backgroundColor = isBlocked ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
    blockAction.image = [UIImage systemImageNamed:isBlocked ? @"hand.thumbsup.fill" : @"hand.raised.slash.fill"];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[blockAction]];
}

- (void)pp_confirmBlockUser:(UserModel *)user shouldBlock:(BOOL)shouldBlock completion:(void(^)(BOOL handled))completion {
    // Current user check
    if ([[FIRAuth auth].currentUser.uid isEqualToString:user.uid]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        if (completion) completion(NO);
        return;
    }
    
    NSString *actionName = shouldBlock ? kLang(@"BlockUser_Action") : kLang(@"Unblock");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Confirm") message:[NSString stringWithFormat:@"%@ %@", actionName, user.UserName] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (completion) completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:actionName style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [RPM setBlocked:shouldBlock forUID:user.uid reason:nil duration:nil completion:^(NSError * _Nullable error) {
            if (error) [PPToast toast:error.localizedDescription];
            else [PPToast toast:kLang(@"Success")];
            if (completion) completion(error == nil);
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
