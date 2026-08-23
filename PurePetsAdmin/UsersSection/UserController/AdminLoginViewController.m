//  AdminLoginViewController.m
#import "AdminLoginViewController.h"
#import "Lottie.h"

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPStaffAuth.h"

@interface PPStaffAuth (PPAdminLoginCacheAccess)
@property (nonatomic, strong, nullable, readwrite) PPStaffDoc *cachedCurrentStaff;
@end

// Login-in-progress flag — defined in SceneDelegate.m
extern BOOL PPAdminLoginInProgress(void);
extern void PPAdminSetLoginInProgress(BOOL);

// Declare (or import) the shared auth-change notification name.
extern NSString * const UserManagerAuthStateDidChangeNotification;

static NSString * const kPPFIRAuthInternalErrorDomain = @"FIRAuthInternalErrorDomain";
static NSString * const kPPFIRAuthDeserializedResponseKey = @"FIRAuthErrorUserInfoDeserializedResponseKey";



@interface AdminLoginViewController ()
// UI
@property (nonatomic, strong) LOTAnimationView *topAnimationView; // header animation (150)
// Form rows
@property (nonatomic, strong) XLFormRowDescriptor *emailRow;
@property (nonatomic, strong) XLFormRowDescriptor *passwordRow;

@property (nonatomic, assign) BOOL didScheduleAutoFaceID;
@property (nonatomic, strong) dispatch_block_t pendingAutoBlock;


// FUManager combined user listener
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> combinedReg;

- (BOOL)pp_hasUnderlyingFirebaseAuthError:(NSError * _Nullable)error;
- (NSString *)pp_authBackendMessageFromError:(NSError * _Nullable)error;
- (NSString *)pp_authBackendMessageFromDeserializedPayload:(NSDictionary * _Nullable)payload;
- (NSString *)pp_authErrorSubtitle:(NSError * _Nullable)error;
- (BOOL)pp_errorLooksLikeAppCheckFailure:(NSError * _Nullable)error;
- (NSString *)pp_firestoreAccessSubtitleForError:(NSError * _Nullable)error;
@end

@implementation AdminLoginViewController

#pragma mark - Init

- (instancetype)init {
    XLFormDescriptor *form = [self buildLoginForm];
    self = [super initWithForm:form style:UITableViewStyleInsetGrouped];
    if (self) { }
    return self;
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    // ---- Header animation BELOW nav bar; height = 150 ----
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width-0, 270)];
    header.backgroundColor = UIColor.clearColor;
    header.clipsToBounds= YES;
    self.topAnimationView = [[LOTAnimationView alloc] init];
    self.topAnimationView.frame = header.bounds;
    self.topAnimationView.loopAnimation = YES;
    self.topAnimationView.hidden = NO;
    self.topAnimationView.contentMode = UIViewContentModeScaleToFill;
    self.topAnimationView.backgroundColor = UIColor.clearColor;

    self.topAnimationView.hxy = 50;
    self.topAnimationView.hxw = 200;
    self.topAnimationView.hxh = 200;
    
    CGPoint c = self.topAnimationView.center;
    c.x = CGRectGetMidX(self.view.bounds);
    self.topAnimationView.center = c;

    self.topAnimationView.clipsToBounds = YES;
    self.topAnimationView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.12].CGColor;
    self.topAnimationView.layer.shadowOpacity = 1.0;
    self.topAnimationView.layer.shadowOffset = CGSizeMake(0, 2);
    self.topAnimationView.layer.shadowRadius = 6;
    self.topAnimationView.layer.masksToBounds = NO; // shadow needs this
    
    [header addSubview:self.topAnimationView];
    self.tableView.tableHeaderView = header;
    self.tableView.estimatedRowHeight = 50;
    
    
    if (@available(iOS 15.0, *)) { self.tableView.sectionHeaderTopPadding = 0; }
    
     self.view.backgroundColor = AppBackgroundClr;
 
    [Styling setAnimationNamed:@"AdminAppLotFiles/Signup" toView:self.topAnimationView withSpeed:1.0 completion:^(BOOL success) {
        DLog(@"[ProfileImage] Lottie load success = %d", success);
        if (success)
        {
            [self.topAnimationView play];
            [self.tableView reloadData];
        }
    }];
    
    // Show
   // self.hud = [JGProgressHUD progressHUDWithStyle:JGProgressHUDStyleDark];
    
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
}


- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    DLog(@"[AdminLogin] viewDidAppear: %p, scheduled=%d", self, self.didScheduleAutoFaceID);

    // Auto FaceID flow (delegates sign-in to FUManager)
    if (self.didScheduleAutoFaceID) { DLog(@"[Biometric] auto already scheduled; skip"); return; }
    if ([FIRAuth auth].currentUser) { return; }
    if (![PPBiometric.shared hasStoredCredentials]) { return; }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kBiometricDisabledUntilManualLogin]) {
        DLog(@"[Biometric] disabled until manual login");
        return;
    }

    self.didScheduleAutoFaceID = YES;

    __weak typeof(self) weakSelf = self;
    self.pendingAutoBlock = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        [PPBiometric.shared authenticateFrom:self
                                      reason:@"Authenticate to login securely"
                                  completion:^(NSString * _Nullable email,
                                               NSString * _Nullable password,
                                               NSError * _Nullable error) {
            if (error || email.length == 0 || password.length == 0) {
                DLog(@"[Biometric] auto-auth canceled/failed: %@", error.localizedDescription);
                return;
            }

            self.emailRow.value = email;
            self.passwordRow.value = nil;
            [self.tableView reloadData];

            [self signInWithFUManagerEmail:email
                                  password:password
                            onSuccessToast:NO
                             fromBiometric:YES
                        persistCredentials:YES];
        }];
    });

    // Short delay so prompt appears after screen settles.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(),
                   self.pendingAutoBlock);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.pendingAutoBlock) {
        dispatch_block_cancel(self.pendingAutoBlock);
        self.pendingAutoBlock = nil;
    }
    // Do NOT remove combinedReg here unless you only want it active on this screen.
    // If you need to stop listening when leaving, uncomment:
    // [self.combinedReg remove]; self.combinedReg = nil;
    
    [PPHUD dismiss]; // ✅ guarantees no stuck HUD when popping controller

}

#pragma mark - Language toggle

- (void)onLanguageChange {
    Language.languageVal == 0 ?  [Language userSelectedLanguage:LanguageCode[1]]
                              :  [Language userSelectedLanguage:LanguageCode[0]];
}


- (void)onRequestSupport {
    Language.languageVal == 0 ?  [Language userSelectedLanguage:LanguageCode[1]]
                              :  [Language userSelectedLanguage:LanguageCode[0]];
}
#pragma mark - Form

- (XLFormDescriptor *)buildLoginForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    XLFormSectionDescriptor *section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    // Email
    self.emailRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"email"
                                                          rowType:XLFormRowDescriptorTypeEmail
                                                            title:kLang(@"Email")];
    self.emailRow.required = YES;
    self.emailRow.cellConfig[@"textField.placeholder"] = kLang(@"EmailPlaceholder");
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:self.emailRow];
    }
    
    
    NSString *savedEmail = [[NSUserDefaults standardUserDefaults] stringForKey:@"savedEmail"];
    if (savedEmail) {
        self.emailRow.value = savedEmail;
    }
    
    
    [section addFormRow:self.emailRow];

    // Password
    self.passwordRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"password"
                                                             rowType:XLFormRowDescriptorTypePassword
                                                               title:kLang(@"Password")];
    self.passwordRow.required = YES;
    self.passwordRow.cellConfig[@"textField.placeholder"] = kLang(@"PasswordPlaceholder");
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:self.passwordRow];
    }
    [section addFormRow:self.passwordRow];
    
    
    // In buildLoginForm (after password)
    XLFormRowDescriptor *rememberRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"rememberMe"
                                           rowType:XLFormRowDescriptorTypeBooleanSwitch
                                             title:kLang(@"RememberMe")];
    rememberRow.value = @([[NSUserDefaults standardUserDefaults] boolForKey:@"rememberMe"]);
    [section addFormRow:rememberRow];



    // Actions
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    XLFormRowDescriptor *loginRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"login"
                                                                          rowType:XLFormRowDescriptorTypeButton
                                                                            title:kLang(@"Login")];
    loginRow.action.formSelector = @selector(handleLogin:);
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:loginRow];
    }
    if ([Styling respondsToSelector:@selector(setRowButtonStyle:)]) {
        [Styling setRowButtonStyle:loginRow];
    }
    loginRow.cellConfig[@"detailTextLabel.textColor"] = AppForgroundColr;
    loginRow.cellConfig[@"textLabel.textColor"] = AppForgroundColr;
    [section addFormRow:loginRow];

    // Google Login
    XLFormRowDescriptor *googleRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"googleLogin"
                                                                          rowType:XLFormRowDescriptorTypeButton
                                                                            title:kLang(@"SignInWithGoogle")];
    googleRow.action.formSelector = @selector(handleGoogleLogin:);
    if ([Styling respondsToSelector:@selector(applyGlobalStyleToRow:)]) {
        [Styling applyGlobalStyleToRow:googleRow];
    }
    if ([Styling respondsToSelector:@selector(setRowButtonStyle:)]) {
        [Styling setRowButtonStyle:googleRow];
    }
    googleRow.cellConfig[@"textLabel.textColor"] = [UIColor whiteColor];
    googleRow.cellConfigAtConfigure[@"backgroundColor"] = AppPrimaryClr;
    [section addFormRow:googleRow];
    
    // Actions
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];
    
    
    
    XLFormRowDescriptor *forgotRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"forgotPassword"
                                           rowType:XLFormRowDescriptorTypeButton
                                             title:kLang(@"ForgotPassword")];
    forgotRow.action.formBlock = ^(XLFormRowDescriptor *row) {
        NSString *email = self.emailRow.value;
        if (!email.length) {
            [PPAlertHelper showWarningIn:self title:kLang(@"Warning") subtitle:kLang(@"EnterEmailFirst")];
            return;
        }
        [[FIRAuth auth] sendPasswordResetWithEmail:email completion:^(NSError * _Nullable error) {
            if (error) {
                [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPAlertHelper showSuccessIn:self title:kLang(@"Success") subtitle:kLang(@"PasswordResetEmailSent")];
            }
        }];
    };
    [Styling fontMedium:14];
    // Always safe
    forgotRow.cellConfig[@"textLabel.font"] = [Styling fontMedium:16];
    forgotRow.cellConfig[@"textLabel.textColor"] = PrimaryTextClr;
    forgotRow.cellConfig[@"detailTextLabel.font"] = [Styling fontMedium:16];;
    forgotRow.cellConfig[@"detailTextLabel.textColor"] = SeconderyTextClr;

    forgotRow.cellConfig[@"textLabel.textColor"] = AppPrimaryClr;
    
    
    [section addFormRow:forgotRow];


    return form;
}

#pragma mark - Actions

- (void)handleLogin:(XLFormRowDescriptor *)sender {
    (void)sender;
    
    NSString *email = [((NSString *)self.emailRow.value ?: @"")
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *password = self.passwordRow.value;

    if (email.length == 0 || password.length == 0) {
        [PPAlertHelper showWarningIn:self title:kLang(@"Warning") subtitle:kLang(@"StatusEnterBoth")];
        return;
    }
    
    [self.view endEditing:YES];
   
    
    
   // [PPAlertHelper showInfoIn:self title:kLang(@"Please wait") subtitle:kLang(@"StatusLoggingIn")];

    BOOL remember = [[self.form formRowWithTag:@"rememberMe"].value boolValue];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:remember forKey:kRememberMeKey];
    if (remember) {
        [ud setObject:email forKey:kSavedEmailKey];
    } else {
        [ud removeObjectForKey:kSavedEmailKey];
    }
    [ud synchronize];

    PPAdminSetLoginInProgress(YES);   // prevent SceneDelegate re-routing during login pipeline

    [self signInWithFUManagerEmail:email
                          password:password
                    onSuccessToast:NO
                     fromBiometric:NO
                persistCredentials:YES];
}

- (void)handleGoogleLogin:(XLFormRowDescriptor *)sender {
    (void)sender;
    [self.view endEditing:YES];

    PPAdminSetLoginInProgress(YES);

    __weak typeof(self) weakSelf = self;
    [PPHUD showIndeterminateIn:self.view
                          title:kLang(@"Please wait")
                       subtitle:kLang(@"StatusLoggingIn")];

    [[FUManager shared] signInWithGoogle:self completion:^(FIRUser * _Nullable user, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;

        if (error || !user) {
            PPAdminSetLoginInProgress(NO);
            [PPHUD dismiss];
            if (error.code != -5) { // -5 is user cancel
                NSString *subtitle = [self pp_authErrorSubtitle:error];
                [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:subtitle];
            }
            return;
        }

        [self pp_gatekeepUsersColForUID:user.uid
                                  email:user.email ?: @""
                               password:@""
                           onSuccessToast:YES
                            fromBiometric:NO
                       persistCredentials:NO];
    }];
}

#pragma mark - Core sign-in pipeline (FUManager owns everything)

// In AdminLoginViewController.m
- (void)signInWithFUManagerEmail:(NSString *)email
                        password:(NSString *)password
                  onSuccessToast:(BOOL)showToast
                   fromBiometric:(BOOL)fromBiometric
              persistCredentials:(BOOL)persistCredentials
{
    [self pp_signInWithFUManagerEmail:email
                             password:password
                       onSuccessToast:showToast
                        fromBiometric:fromBiometric
                   persistCredentials:persistCredentials
             allowRetryOnInternalError:YES];
}

- (void)pp_signInWithFUManagerEmail:(NSString *)email
                           password:(NSString *)password
                     onSuccessToast:(BOOL)showToast
                      fromBiometric:(BOOL)fromBiometric
                 persistCredentials:(BOOL)persistCredentials
           allowRetryOnInternalError:(BOOL)allowRetryOnInternalError
{
    __weak typeof(self) weakSelf = self;
    [PPHUD showIndeterminateIn:self.view
                          title:kLang(@"Please wait")
                       subtitle:kLang(@"StatusLoggingIn")];


    [[FUManager shared] signInWithEmail:email password:password completion:^(FIRUser * _Nullable user, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;

        FIRUser *effectiveUser = user ?: [FIRAuth auth].currentUser;
        BOOL recoveredFromTransientError =
            (error != nil && effectiveUser != nil && [self pp_shouldRetryInternalAuthError:error]);

        if ((error && !recoveredFromTransientError) || !effectiveUser) {
            if (error) {
                [self pp_logAuthError:error context:@"signIn"];
            }

            if (fromBiometric && [self pp_shouldDisableBiometricForAuthError:error]) {
                [PPBiometric.shared disableBiometric];
                [self pp_setBiometricDisabledUntilManualLogin:YES];
            }

            if (allowRetryOnInternalError && [self pp_shouldRetryInternalAuthError:error]) {
                NSLog(@"[AdminLogin] retrying once after internal auth error");
                [UsrMgr signOutWithCompletion:^(NSError * _Nullable signOutError) {
                    if (signOutError) {
                        NSLog(@"[AdminLogin] pre-retry signOut warning: %@", signOutError.localizedDescription);
                    }
                    [PPHUD dismiss];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(350 * NSEC_PER_MSEC)),
                                   dispatch_get_main_queue(), ^{
                        [self pp_signInWithFUManagerEmail:email
                                                 password:password
                                           onSuccessToast:showToast
                                            fromBiometric:fromBiometric
                                       persistCredentials:persistCredentials
                                 allowRetryOnInternalError:NO];
                    });
                }];
                return;
            }

            [PPHUD dismiss];
            PPAdminSetLoginInProgress(NO);
            NSString *subtitle = [self pp_authErrorSubtitle:error];
            [PPAlertHelper showErrorIn:self title:kLang(@"Error")
                             subtitle:subtitle];
            return;
        }

        if (error && recoveredFromTransientError) {
            [self pp_logAuthError:error context:@"signIn_recovered_transient"];
            DLog(@"[AdminLogin] continuing with recovered auth session uid=%@", effectiveUser.uid);
        }

        // (Optional) Log claims for diagnostics. Do NOT gate on this anymore.
        [effectiveUser getIDTokenResultForcingRefresh:YES completion:^(FIRAuthTokenResult * _Nullable tokenResult, NSError * _Nullable refreshError) {
            (void)tokenResult;
            if (!refreshError) {
                [RPM fetchIDTokenClaims:^(NSDictionary * _Nullable claims, NSError * _Nullable claimsErr) {
                    if (!claimsErr) {
                        BOOL hasAdminClaim = [claims[@"admin"] boolValue] || [claims[@"isAdmin"] boolValue];
                        DLog(@"[Login] 🔑 Claims=%@ → hasAdminClaim=%d", claims, hasAdminClaim);
                        
                           BOOL hasSuper = [claims[@"superadmin"] boolValue];
                           BOOL hasAdmin = [claims[@"admin"] boolValue];
                           DLog(@"claims  superAdmin=%d admin=%d", hasSuper, hasAdmin);
                    }
                }];
            }
        }];

        // Ensure user root exists, then gate on UsersCol
        [[FUManager shared] ensureUserDocumentExistsForCurrentUserWithExtra:nil completion:^(NSError * _Nullable eDoc) {
            if (eDoc && ![self pp_shouldContinueAfterEnsureUserDocError:eDoc]) {
                [PPHUD dismiss];
                PPAdminSetLoginInProgress(NO);
                [PPAlertHelper showErrorIn:self
                                   title:kLang(@"Error")
                                subtitle:[self pp_firestoreAccessSubtitleForError:eDoc]];
                return;
            }
            if (eDoc) {
                DLog(@"[Gatekeep] ⚠️ proceeding despite ensureUserDocument error: %@", eDoc.localizedDescription);
            }

            // FINAL GATE → UsersCol only
            [self pp_gatekeepUsersColForUID:effectiveUser.uid
                                      email:email
                                   password:password
                               onSuccessToast:showToast
                                fromBiometric:fromBiometric
                           persistCredentials:persistCredentials];
        }];
    }];
}

- (BOOL)pp_shouldContinueAfterEnsureUserDocError:(NSError * _Nullable)error {
    if (!error) return YES;

    if ([self pp_errorLooksLikeAppCheckFailure:error]) {
        return NO;
    }

    if ([error.domain isEqualToString:FIRFirestoreErrorDomain] &&
        error.code == FIRFirestoreErrorCodePermissionDenied) {
        return YES;
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        [underlying.domain isEqualToString:FIRFirestoreErrorDomain] &&
        underlying.code == FIRFirestoreErrorCodePermissionDenied) {
        return YES;
    }

    return NO;
}

#pragma mark - Table styling passthroughs

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    
        [Styling applyBackgroundStyleForTableView:tableView
                                        cell:cell
                                   indexPath:indexPath
                               useRowCardMode:NO
                              buttonRowIndex:0
                                    buttonSection:20];
     if(indexPath.section == 1)
     {
         cell.backgroundColor = AppPrimaryClr;
         cell.contentView.backgroundColor = AppPrimaryClr;
         cell.tintColor  = AppForgroundColr;
     }
    
    if(indexPath.section == 2)
    {
        cell.backgroundColor = AppForgroundColr;
        cell.contentView.backgroundColor = AppForgroundColr;
        cell.tintColor  = AppPrimaryClr;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 50;
}
#pragma mark - Init


-(void)onSettings
{
}
-(void)viewWillAppear:(BOOL)animated
{
    
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:kLang(@"") showBack:nil]; // removes bar
    UIButton *custom = [self pp_ButtonWithSystemName:@"headset" action:@selector(onRequestSupport)];
    [self forceReplaceRightButtonWith:custom];
    
    UIButton *custom2 = [self pp_ButtonWithSystemName:@"globe" action:@selector(onLanguageChange)];
    [self forceReplaceLeftButtonWith:custom2];
    
    
    // 1) Use custom view as title
    UIView *pill = [self pp_viewWithImage:@"pure shelid icon filled" andTitle:kLang(@"PURE PETS")];
    [self pp_navBarForeTitleView:pill];
    
    
}

-(void)didTapLanguage
{
    
}


-(void)didTapSupport
{
    
}


/// Final gate: resolve staff workspace access from UsersCol only.
- (void)pp_gatekeepUsersColForUID:(NSString *)uid
                            email:(NSString *)email
                         password:(NSString *)password
                    onSuccessToast:(BOOL)showToast
                     fromBiometric:(BOOL)fromBiometric
                persistCredentials:(BOOL)persistCredentials
{
    if (uid.length == 0) {
        [PPHUD dismiss];
        PPAdminSetLoginInProgress(NO);
        [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"StatusUserDocError")];
        [UsrMgr signOut];
        return;
    }

    __weak typeof(self) weakSelf = self;
    DLog(@"[Gatekeep] 🔎 Resolve staff access from UsersCol/%@ ...", uid);

    [[PPStaffAuth shared] fetchStaffDoc:uid completion:^(PPStaffDoc * _Nullable staffDoc, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;

        if (error) {
            DLog(@"[Gatekeep] ❌ UsersCol staff access read error: %@", error.localizedDescription);
            if ([self pp_errorLooksLikeAppCheckFailure:error]) {
                [PPHUD dismiss];
                PPAdminSetLoginInProgress(NO);
                [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:[self pp_firestoreAccessSubtitleForError:error]];
                return;
            }
            [self pp_denyAccessWithBiometric:fromBiometric subtitle:kLang(@"StatusUserDocError")];
            return;
        }

        DLog(@"[Gatekeep] UsersCol staff doc: accountType=%@ status=%@ role=%@ perms=%lu",
             staffDoc.accountType ?: @"",
             staffDoc.status ?: @"",
             staffDoc.role ?: @"",
             (unsigned long)staffDoc.permissions.count);

        if (staffDoc.canAccessStaffWorkspace) {
            [PPStaffAuth shared].cachedCurrentStaff = staffDoc;
            [self pp_finishLoginAndStartUserStreamWithEmail:email
                                                   password:password
                                                  showToast:showToast
                                               fromBiometric:fromBiometric
                                          persistCredentials:persistCredentials];
            return;
        }

        [self pp_denyAccessWithBiometric:fromBiometric subtitle:kLang(@"StatusNoAccess")];
    }];
}

- (void)pp_denyAccessWithBiometric:(BOOL)fromBiometric subtitle:(NSString *)subtitle {
    if (fromBiometric) {
        [PPBiometric.shared disableBiometric];
        [self pp_setBiometricDisabledUntilManualLogin:YES];
    }
    [PPHUD dismiss];
    PPAdminSetLoginInProgress(NO);
    [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:subtitle];
    [UsrMgr signOut];
}

/// Success path (shared): start your combined listener, cache, biometrics, notify app.
- (void)pp_finishLoginAndStartUserStreamWithEmail:(NSString *)email
                                         password:(NSString *)password
                                        showToast:(BOOL)showToast
                                     fromBiometric:(BOOL)fromBiometric
                                persistCredentials:(BOOL)persistCredentials
{
    (void)fromBiometric;
    (void)persistCredentials;

    if (self.combinedReg) { [self.combinedReg remove]; self.combinedReg = nil; }

    __weak typeof(self) weakSelf = self;
    self.combinedReg = [[FUManager shared] listenCombinedUser:^(UserModel * _Nullable u, NSError * _Nullable err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (err || !u) {
            PPAdminSetLoginInProgress(NO);   // clear flag on listener error
            DLog(@"[Gatekeep] ⚠️ combined user stream error=%@", err.localizedDescription);
            [PPHUD dismiss];
            [self.combinedReg remove];
            self.combinedReg = nil;
            [PPAlertHelper showErrorIn:self
                               title:kLang(@"Error")
                            subtitle:[self pp_firestoreAccessSubtitleForError:err]];
            if (![self pp_errorLooksLikeAppCheckFailure:err]) {
                [UsrMgr signOut];
            }
            return;
        }

        // Always keep biometric credentials after a successful login.
        [PPBiometric.shared enableBiometricWithEmail:email password:password];
        [self pp_setBiometricDisabledUntilManualLogin:NO];

        self.passwordRow.value = nil;
        [UsrMgr p_writeUserToDisk:u forUID:u.uid];

        [PPHUD dismiss];
        PPAdminSetLoginInProgress(NO);   // login pipeline complete → allow SceneDelegate routing
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:UserManagerAuthStateDidChangeNotification object:nil];
        });

        if (showToast) {
            [PPToast toast:kLang(@"Login successful")
                     style:PPToastStyleSuccess
                     haptic:YES
                   duration:2.0];
        }
    }];
}

- (void)pp_setBiometricDisabledUntilManualLogin:(BOOL)disabled {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:disabled forKey:kBiometricDisabledUntilManualLogin];
    [ud synchronize];
}

- (BOOL)pp_shouldDisableBiometricForAuthError:(NSError * _Nullable)error {
    if (![self pp_isFirebaseAuthError:error]) return NO;
    FIRAuthErrorCode code = [self pp_normalizedAuthErrorCode:error];
    switch (code) {
        case FIRAuthErrorCodeInvalidCredential:
        case FIRAuthErrorCodeWrongPassword:
        case FIRAuthErrorCodeUserDisabled:
        case FIRAuthErrorCodeUserNotFound:
            return YES;
        default:
            return NO;
    }
}


- (BOOL)pp_hasUnderlyingFirebaseAuthError:(NSError * _Nullable)error {
    if (!error) return NO;
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (![underlying isKindOfClass:NSError.class]) return NO;
    return [underlying.domain isEqualToString:FIRAuthErrorDomain] ||
           [underlying.domain isEqualToString:kPPFIRAuthInternalErrorDomain];
}

- (NSString *)pp_authBackendMessageFromDeserializedPayload:(NSDictionary * _Nullable)payload {
    if (![payload isKindOfClass:NSDictionary.class]) return @"";

    NSString *(^asString)(id) = ^NSString *(id value) {
        return [value isKindOfClass:NSString.class] ? value : @"";
    };

    NSString *message = asString(payload[@"message"]);
    if (message.length > 0) return message;

    NSDictionary *errorPayload = [payload[@"error"] isKindOfClass:NSDictionary.class]
        ? payload[@"error"]
        : nil;
    if (errorPayload) {
        message = asString(errorPayload[@"message"]);
        if (message.length > 0) return message;

        NSArray *errors = [errorPayload[@"errors"] isKindOfClass:NSArray.class]
            ? errorPayload[@"errors"]
            : nil;
        NSDictionary *firstError = errors.count > 0 && [errors.firstObject isKindOfClass:NSDictionary.class]
            ? errors.firstObject
            : nil;
        message = asString(firstError[@"message"]);
        if (message.length > 0) return message;
    }

    return @"";
}

- (NSString *)pp_authBackendMessageFromError:(NSError * _Nullable)error {
    if (!error) return @"";

    NSString *message = [self pp_authBackendMessageFromDeserializedPayload:error.userInfo[kPPFIRAuthDeserializedResponseKey]];
    if (message.length > 0) return message;

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class]) {
        message = [self pp_authBackendMessageFromDeserializedPayload:underlying.userInfo[kPPFIRAuthDeserializedResponseKey]];
        if (message.length > 0) return message;

        NSError *deepUnderlying = underlying.userInfo[NSUnderlyingErrorKey];
        if ([deepUnderlying isKindOfClass:NSError.class]) {
            message = [self pp_authBackendMessageFromDeserializedPayload:deepUnderlying.userInfo[kPPFIRAuthDeserializedResponseKey]];
            if (message.length > 0) return message;
        }
    }

    return @"";
}

- (BOOL)pp_errorLooksLikeAppCheckFailure:(NSError * _Nullable)error {
    if (![error isKindOfClass:NSError.class]) {
        return NO;
    }

    NSArray<NSString *> *messages = @[
        error.localizedDescription ?: @"",
        [self pp_authBackendMessageFromError:error] ?: @""
    ];
    for (NSString *message in messages) {
        NSString *lower = [message lowercaseString];
        if ([lower containsString:@"appcheck"] ||
            [lower containsString:@"app check"] ||
            [lower containsString:@"app attest"] ||
            [lower containsString:@"app attestation failed"] ||
            [lower containsString:@"app check token is invalid"] ||
            [lower containsString:@"exchangeappattestattestation"]) {
            return YES;
        }
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] && underlying != error) {
        return [self pp_errorLooksLikeAppCheckFailure:underlying];
    }

    return NO;
}

- (NSString *)pp_firestoreAccessSubtitleForError:(NSError * _Nullable)error {
    if ([self pp_errorLooksLikeAppCheckFailure:error]) {
        return kLang(@"StatusAppCheckInvalid");
    }
    return kLang(@"StatusUserDocError");
}

- (NSString *)pp_authErrorSubtitle:(NSError * _Nullable)error {
    NSString *fallback = kLang(@"StatusLoginFailed");
    if (!error) return fallback;

    NSString *backendMessage = [self pp_authBackendMessageFromError:error];
    if (backendMessage.length > 0) {
        if ([backendMessage rangeOfString:@"app check token is invalid"
                                  options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return kLang(@"StatusAppCheckInvalid");
        }
        return backendMessage;
    }

    NSString *description = error.localizedDescription;
    if (description.length > 0 && ![description isEqualToString:@"(null)"]) {
        return description;
    }

    return fallback;
}

- (BOOL)pp_shouldRetryInternalAuthError:(NSError * _Nullable)error {
    if (![self pp_isFirebaseAuthError:error]) return NO;

    NSString *backendMessage = [self pp_authBackendMessageFromError:error];
    if ([backendMessage rangeOfString:@"app check token is invalid"
                              options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [backendMessage rangeOfString:@"app attestation failed"
                              options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return NO;
    }

    FIRAuthErrorCode code = [self pp_normalizedAuthErrorCode:error];
    switch (code) {
        case FIRAuthErrorCodeInternalError:
        case FIRAuthErrorCodeNetworkError:
            return YES;
        default:
            if (![error.domain isEqualToString:kPPFIRAuthInternalErrorDomain]) {
                return NO;
            }
            // When Firebase wraps a concrete auth code in an internal-domain shell,
            // keep the concrete code and do not treat it as transient.
            return ![self pp_hasUnderlyingFirebaseAuthError:error];
    }
}

- (BOOL)pp_isFirebaseAuthError:(NSError * _Nullable)error {
    if (!error) return NO;
    if ([error.domain isEqualToString:FIRAuthErrorDomain]) return YES;
    if ([error.domain isEqualToString:kPPFIRAuthInternalErrorDomain]) return YES;

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        ([underlying.domain isEqualToString:FIRAuthErrorDomain] ||
         [underlying.domain isEqualToString:kPPFIRAuthInternalErrorDomain])) {
        return YES;
    }
    return NO;
}

- (FIRAuthErrorCode)pp_normalizedAuthErrorCode:(NSError *)error {
    if ([error.domain isEqualToString:FIRAuthErrorDomain]) {
        return (FIRAuthErrorCode)error.code;
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        [underlying.domain isEqualToString:FIRAuthErrorDomain]) {
        return (FIRAuthErrorCode)underlying.code;
    }
    return (FIRAuthErrorCode)error.code;
}

- (void)pp_logAuthError:(NSError *)error context:(NSString *)context {
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    NSDictionary *deserialized = error.userInfo[kPPFIRAuthDeserializedResponseKey];
    NSLog(@"[AdminLogin] %@ auth error domain=%@ code=%ld normalizedCode=%ld name=%@ desc=%@ underlyingDomain=%@ underlyingCode=%ld deserialized=%@ userInfo=%@",
          context ?: @"",
          error.domain ?: @"",
          (long)error.code,
          (long)[self pp_normalizedAuthErrorCode:error],
          error.userInfo[FIRAuthErrorUserInfoNameKey] ?: @"",
          error.localizedDescription ?: @"",
          underlying.domain ?: @"",
          (long)underlying.code,
          deserialized ?: @{},
          error.userInfo ?: @{});
}

@end
