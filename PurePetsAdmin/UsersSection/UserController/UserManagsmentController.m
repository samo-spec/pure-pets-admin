//
//  UserManagementController.m
//  PurePetsAdmin
//

#import "UserManagementController.h"
#import "PPImageCollection.h"
#import "Styling.h"
#import "Language.h"
#import "UserManager.h"
#import "UserModel.h"
#import "FUManager.h"
#import "RPManager.h"
#import "AdminService.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPToast.h"
#import "PPFunc.h"

#define RPM [RPManager shared]
#define FUM [FUManager shared]

@interface UserManagementController () <PPImageCollectionDelegate>
@property (nonatomic, strong) UserModel *user;
@property (nonatomic, assign) EditType editType;
@property (nonatomic, assign) BOOL showsAccountUI;
@property (nonatomic, assign) BOOL showsPermRoleUI;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *permSnapshot;
@property (nonatomic, assign) BOOL suppressValueEvents;
@property (nonatomic, assign) BOOL isSavingRole;
@property (nonatomic, assign) BOOL isSavingPerm;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> livePermListener;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *pendingAccountEdits;
@end

@implementation UserManagementController

- (instancetype)initWithUser:(UserModel *)user type:(EditType)type {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    if (self = [super initWithForm:form style:UITableViewStyleInsetGrouped]) {
        _user = user;
        _editType = type;
        _showsAccountUI  = (type == EditTypeDefault || type == EditTypeUserData);
        _showsPermRoleUI = (type == EditTypeDefault || type == EditTypeUserPermisstionAndRoles);
        _permSnapshot = user.permissions ? [user.permissions mutableCopy] : [NSMutableDictionary dictionary];
        _pendingAccountEdits = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    [self buildFormSections];
    [self setupNavButtons];
}

- (void)setupNavButtons {
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    save.backgroundColor = AppForgroundColr;
    [self pp_navBarWithOtherButton:save title:kLang(@"Save_Changes")];
}

- (void)buildFormSections {
    self.form = [XLFormDescriptor formDescriptor];

    if (self.showsAccountUI) {
        [self buildProfileSection];
        [self buildAccountManagementSection];
        [self buildFeaturesSection];
        [self buildSubscriptionsSection];
        [self buildRestrictionsSection];
    }

    if (self.showsPermRoleUI) {
        [self buildRolesSection];
        [self buildUserPermissionsSection];
    }
}

#pragma mark - Section Builders

- (void)buildProfileSection {
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Account_Section")];
    [self.form addFormSection:sec];

    [sec addFormRow:[self textFieldRowWithTag:@"username" title:@"Username_Placeholder" value:self.user.UserName]];
    [sec addFormRow:[self textFieldRowWithTag:@"email" title:@"Email_Placeholder" value:self.user.UserEmail]];
    [sec addFormRow:[self textFieldRowWithTag:@"phone" title:@"Phone_Placeholder" value:self.user.MobileNo]];
}

- (void)buildAccountManagementSection {
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Account_Status")];
    [self.form addFormSection:sec];

    // Verified Switch
    XLFormRowDescriptor *verified = [XLFormRowDescriptor formRowDescriptorWithTag:@"verified" rowType:XLFormRowDescriptorTypeBooleanSwitch title:kLang(@"Verified_Status")];
    verified.value = @(self.user.isVerified);
    [sec addFormRow:verified];

    // Account Status Picker
    XLFormRowDescriptor *status = [XLFormRowDescriptor formRowDescriptorWithTag:@"accountStatus" rowType:XLFormRowDescriptorTypeSelectorPush title:kLang(@"Account_Status")];
    status.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@"active" displayText:kLang(@"Active")],
        [XLFormOptionsObject formOptionsObjectWithValue:@"blocked" displayText:kLang(@"Blocked")],
        [XLFormOptionsObject formOptionsObjectWithValue:@"disabled" displayText:kLang(@"Disabled")],
        [XLFormOptionsObject formOptionsObjectWithValue:@"pending_review" displayText:kLang(@"Pending Review")]
    ];
    status.value = [XLFormOptionsObject formOptionsObjectWithValue:self.user.accountStatus ?: @"active" displayText:kLang(self.user.accountStatus ?: @"Active")];
    [sec addFormRow:status];

    // Protection Status
    XLFormRowDescriptor *protection = [XLFormRowDescriptor formRowDescriptorWithTag:@"prodectionStatus" rowType:XLFormRowDescriptorTypeSelectorPush title:kLang(@"Protection_Status")];
    protection.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@"active" displayText:kLang(@"Active")],
        [XLFormOptionsObject formOptionsObjectWithValue:@"inactive" displayText:kLang(@"Inactive")]
    ];
    protection.value = [XLFormOptionsObject formOptionsObjectWithValue:self.user.prodectionStatus ?: @"inactive" displayText:kLang(self.user.prodectionStatus ?: @"Inactive")];
    [sec addFormRow:protection];
}

- (void)buildFeaturesSection {
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Features")];
    [self.form addFormSection:sec];

    NSDictionary *defaults = @{
        @"canPostPetAds": @YES,
        @"canPostAdoption": @YES,
        @"canSellAccessories": @YES,
        @"canOfferServices": @NO,
        @"canDelivery": @NO,
        @"canUseStories": @YES,
        @"canUseChat": @YES,
        @"canAccessPremiumMarketplace": @NO,
        @"canPharmacy": @NO,
        @"canVet": @NO
    };
    NSDictionary *f = self.user.features.count ? self.user.features : defaults;
    [sec addFormRow:[self switchRowWithTag:@"feat.canPostPetAds" title:(kLang(@"Feature_CanPostPetAds") ?: @"Post pet ads") value:[(f[@"canPostPetAds"] ?: defaults[@"canPostPetAds"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canPostAdoption" title:(kLang(@"Feature_CanPostAdoption") ?: @"Post adoption listings") value:[(f[@"canPostAdoption"] ?: defaults[@"canPostAdoption"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canSellAccessories" title:(kLang(@"Feature_CanSellAccessories") ?: @"Sell accessories") value:[(f[@"canSellAccessories"] ?: defaults[@"canSellAccessories"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canOfferServices" title:(kLang(@"Feature_CanOfferServices") ?: @"Offer services") value:[(f[@"canOfferServices"] ?: defaults[@"canOfferServices"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canDelivery" title:(kLang(@"Feature_CanDelivery") ?: @"Delivery access") value:[(f[@"canDelivery"] ?: defaults[@"canDelivery"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canUseStories" title:(kLang(@"Feature_CanUseStories") ?: @"Use stories") value:[(f[@"canUseStories"] ?: defaults[@"canUseStories"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canUseChat" title:(kLang(@"Feature_CanUseChat") ?: @"Use chat") value:[(f[@"canUseChat"] ?: defaults[@"canUseChat"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canAccessPremiumMarketplace" title:(kLang(@"Feature_CanAccessPremiumMarketplace") ?: @"Premium marketplace access") value:[(f[@"canAccessPremiumMarketplace"] ?: defaults[@"canAccessPremiumMarketplace"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canPharmacy" title:(kLang(@"Feature_CanPharmacy") ?: @"Pharmacy access") value:[(f[@"canPharmacy"] ?: defaults[@"canPharmacy"]) boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"feat.canVet" title:(kLang(@"Feature_CanVet") ?: @"Veterinary access") value:[(f[@"canVet"] ?: defaults[@"canVet"]) boolValue]]];
}

- (void)buildSubscriptionsSection {
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Subscriptions")];
    [self.form addFormSection:sec];

    NSDictionary *s = self.user.subscription;
    XLFormRowDescriptor *plan = [XLFormRowDescriptor formRowDescriptorWithTag:@"sub.plan" rowType:XLFormRowDescriptorTypeSelectorPush title:@"Plan"];
    plan.selectorOptions = @[@"free", @"plus", @"pro", @"business"];
    plan.value = s[@"plan"] ?: @"free";
    [sec addFormRow:plan];
}

- (void)buildRestrictionsSection {
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Restrictions")];
    [self.form addFormSection:sec];

    NSDictionary *r = self.user.restrictions;
    [sec addFormRow:[self switchRowWithTag:@"rest.postingBlocked" title:@"Posting Blocked" value:[r[@"postingBlocked"] boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"rest.chatBlocked" title:@"Chat Blocked" value:[r[@"chatBlocked"] boolValue]]];
    [sec addFormRow:[self switchRowWithTag:@"rest.purchaseBlocked" title:@"Purchase Blocked" value:[r[@"purchaseBlocked"] boolValue]]];
}

- (void)buildRolesSection {
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Roles")];
    [self.form addFormSection:sec];
    // Existing roles logic...
}

- (void)buildUserPermissionsSection {
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Permissions")];
    [self.form addFormSection:sec];
    // Existing perms logic...
}

#pragma mark - Helpers

- (XLFormRowDescriptor *)textFieldRowWithTag:(NSString *)tag title:(NSString *)titleKey value:(id)value {
    XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:XLFormRowDescriptorTypePPTextField title:kLang(titleKey)];
    row.value = value ?: @"";
    [Styling setRowFonts:row];
    return row;
}

- (XLFormRowDescriptor *)switchRowWithTag:(NSString *)tag title:(NSString *)title value:(BOOL)value {
    XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:XLFormRowDescriptorTypeBooleanSwitch title:title];
    row.value = @(value);
    return row;
}

#pragma mark - Actions

- (void)onSave {
    [PPFunc pp_playTapEffect];
    [AlertHelper showInfoIn:self title:kLang(@"Saving") subtitle:kLang(@"Please wait...")];

    NSString *uid = self.user.uid;
    NSDictionary *values = [self.form formValues];
    
    dispatch_group_t group = dispatch_group_create();
    __block NSError *lastError = nil;

    // 1. Profile Fields
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    profile[@"UserName"] = values[@"username"];
    profile[@"UserEmail"] = values[@"email"];
    profile[@"MobileNo"] = values[@"phone"];
    
    dispatch_group_enter(group);
    [FUM updateUserFieldsForUID:uid fields:profile completion:^(NSError * _Nullable error) {
        if (error) lastError = error;
        dispatch_group_leave(group);
    }];

    // 2. Verified Status
    BOOL isVerified = [values[@"verified"] boolValue];
    if (isVerified != self.user.isVerified) {
        dispatch_group_enter(group);
        [AdminService updateUserVerified:uid verified:isVerified completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    // 3. Account Status
    NSString *status = [(XLFormOptionsObject *)values[@"accountStatus"] formValue];
    if (![status isEqualToString:self.user.accountStatus]) {
        dispatch_group_enter(group);
        [AdminService updateUserStatus:uid status:status completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    // 4. Protection Status
    NSString *pStatus = [(XLFormOptionsObject *)values[@"prodectionStatus"] formValue];
    if (![pStatus isEqualToString:self.user.prodectionStatus]) {
        dispatch_group_enter(group);
        [FUM updateUserFieldsForUID:uid fields:@{@"prodectionStatus": pStatus} completion:^(NSError * _Nullable error) {
            if (error) lastError = error;
            dispatch_group_leave(group);
        }];
    }

    // 5. Features
    NSMutableDictionary *features = [NSMutableDictionary dictionary];
    for (NSString *key in values.allKeys) {
        if ([key hasPrefix:@"feat."]) {
            features[[key substringFromIndex:5]] = values[key];
        }
    }
    dispatch_group_enter(group);
    [AdminService updateUserFeatures:uid features:features completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
        if (error) lastError = error;
        dispatch_group_leave(group);
    }];

    // 5. Restrictions
    NSMutableDictionary *rest = [NSMutableDictionary dictionary];
    for (NSString *key in values.allKeys) {
        if ([key hasPrefix:@"rest."]) {
            rest[[key substringFromIndex:5]] = values[key];
        }
    }
    dispatch_group_enter(group);
    [AdminService updateUserRestrictions:uid restrictions:rest completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
        if (error) lastError = error;
        dispatch_group_leave(group);
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:YES completion:nil];
        if (lastError) {
            [PPToast toast:lastError.localizedDescription];
        } else {
            [PPToast toast:kLang(@"Update_Success") style:PPToastStyleSuccess haptic:YES duration:2.0];
            [self.navigationController popViewControllerAnimated:YES];
        }
    });
}

@end
