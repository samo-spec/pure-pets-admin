//
//  StaffRoleEditorViewController.m
//  PurePetsAdmin
//

#import "StaffRoleEditorViewController.h"
#import "Styling.h"
#import "Language.h"
#import "PPStaffAuth.h"
#import "AdminService.h"
#import "PPToast.h"
#import "AlertHelper.h"
#import "PPRolePermission.h"

@interface StaffRoleEditorViewController ()
@end

@implementation StaffRoleEditorViewController

- (instancetype)initWithRole:(StaffRoleTemplate *)role {
    self.roleTemplate = role;
    XLFormDescriptor *form = [self buildForm];
    return [super initWithForm:form style:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
 
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(10, 0, 40, 0);

   
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    [self pp_navBarWithOtherButton:save title:kLang(@"Role_Info")];
}

- (XLFormDescriptor *)buildForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    
    // Section: Name & Description
    XLFormSectionDescriptor *infoSec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Role_Info")];
    [form addFormSection:infoSec];
    
    [infoSec addFormRow:[self textFieldRowWithTag:@"nameEn" title:@"RoleNameEn" value:self.roleTemplate.name[@"en"]]];
    [infoSec addFormRow:[self textFieldRowWithTag:@"nameAr" title:@"RoleNameAr" value:self.roleTemplate.name[@"ar"]]];
    [infoSec addFormRow:[self textFieldRowWithTag:@"descEn" title:@"RoleDescEn" value:self.roleTemplate.roleDescription[@"en"]]];
    [infoSec addFormRow:[self textFieldRowWithTag:@"descAr" title:@"RoleDescAr" value:self.roleTemplate.roleDescription[@"ar"]]];
    
    // Section: Permissions
    XLFormSectionDescriptor *permSec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Permissions")];
    [form addFormSection:permSec];
    
    NSArray *modules = [self pp_allPermissionModules];
    NSSet *activePerms = [NSSet setWithArray:self.roleTemplate.permissions ?: @[]];
    
    for (PermissionModule *mod in modules) {
        // Module header row (optional, could use segmented header)
        for (PermissionAction *action in mod.actions) {
            XLFormRowDescriptor *pRow = [XLFormRowDescriptor formRowDescriptorWithTag:action.key rowType:XLFormRowDescriptorTypeBooleanSwitch title:([Language isRTL] ? action.labelAr : action.labelEn)];
            pRow.value = @([activePerms containsObject:action.key]);
            [permSec addFormRow:pRow];
        }
    }
    
    return form;
}

- (XLFormRowDescriptor *)textFieldRowWithTag:(NSString *)tag title:(NSString *)titleKey value:(id)value {
    XLFormRowDescriptor *row = [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:XLFormRowDescriptorTypePPTextField title:kLang(titleKey)];
    row.value = value ?: @"";
    [Styling setRowFonts:row];
    return row;
}

- (void)onSave {
    NSDictionary *values = [self.form formValues];
    NSString *nameEn = values[@"nameEn"];
    NSString *nameAr = values[@"nameAr"];
    
    if (nameEn.length == 0 || nameAr.length == 0) {
        [PPToast toast:kLang(@"Error_FillAllFields")];
        return;
    }
    
    NSMutableArray *perms = [NSMutableArray array];
    for (NSString *key in values.allKeys) {
        if ([key containsString:@"."] && [values[key] boolValue]) {
            [perms addObject:key];
        }
    }
    
    NSDictionary *payload = @{
        @"name": @{@"en": nameEn, @"ar": nameAr},
        @"description": @{@"en": values[@"descEn"] ?: @"", @"ar": values[@"descAr"] ?: @""},
        @"permissions": perms
    };
    
    [PPHUD showRingIn:self.view title:kLang(@"Saving") subtitle:@""];
    
    if (self.roleTemplate) {
        [[RPManager shared] updateStaffRole:self.roleTemplate.id data:payload completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) [PPToast toast:error.localizedDescription];
            else [self.navigationController popViewControllerAnimated:YES];
        }];
    } else {
        [[RPManager shared] createStaffRole:payload completion:^(NSString * _Nullable roleID, NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) [PPToast toast:error.localizedDescription];
            else [self.navigationController popViewControllerAnimated:YES];
        }];
    }
}

- (NSArray<PermissionModule *> *)pp_allPermissionModules {
    static NSMutableArray<PermissionModule *> *modules = nil;
    if (modules) return modules;
    
    modules = [NSMutableArray array];
    
    // Dashboard
    PermissionModule *dashboard = [PermissionModule new];
    dashboard.key = @"dashboard";
    dashboard.labelEn = @"Dashboard";
    dashboard.labelAr = @"لوحة التحكم";
    PermissionAction *dView = [PermissionAction new]; dView.key = @"dashboard.view"; dView.labelEn = @"View dashboard"; dView.labelAr = @"عرض لوحة التحكم";
    dashboard.actions = @[dView];
    [modules addObject:dashboard];
    
    // Staff
    PermissionModule *staff = [PermissionModule new];
    staff.key = @"staff";
    staff.labelEn = @"Staff";
    staff.labelAr = @"الموظفون";
    PermissionAction *sView = [PermissionAction new]; sView.key = @"staff.view"; sView.labelEn = @"View staff"; sView.labelAr = @"عرض الموظفين";
    PermissionAction *sManage = [PermissionAction new]; sManage.key = @"staff.manage"; sManage.labelEn = @"Manage staff"; sManage.labelAr = @"إدارة الموظفين";
    staff.actions = @[sView, sManage];
    [modules addObject:staff];
    
    // Users
    PermissionModule *users = [PermissionModule new];
    users.key = @"users";
    users.labelEn = @"Users";
    users.labelAr = @"المستخدمون";
    PermissionAction *uView = [PermissionAction new]; uView.key = @"users.view"; uView.labelEn = @"View users"; uView.labelAr = @"عرض المستخدمين";
    PermissionAction *uManage = [PermissionAction new]; uManage.key = @"users.manage"; uManage.labelEn = @"Manage users"; uManage.labelAr = @"إدارة المستخدمين";
    PermissionAction *uBlock = [PermissionAction new]; uBlock.key = @"users.block"; uBlock.labelEn = @"Block / unblock users"; uBlock.labelAr = @"حظر / إلغاء حظر المستخدمين";
    users.actions = @[uView, uManage, uBlock];
    [modules addObject:users];
    
    // Stock
    PermissionModule *stock = [PermissionModule new];
    stock.key = @"stock";
    stock.labelEn = @"Stock";
    stock.labelAr = @"المخزون";
    PermissionAction *stView = [PermissionAction new]; stView.key = @"stock.view"; stView.labelEn = @"View stock"; stView.labelAr = @"عرض المخزون";
    PermissionAction *stManage = [PermissionAction new]; stManage.key = @"stock.manage"; stManage.labelEn = @"Manage stock"; stManage.labelAr = @"إدارة المخزون";
    PermissionAction *stCreate = [PermissionAction new]; stCreate.key = @"stock.create"; stCreate.labelEn = @"Create stock items"; stCreate.labelAr = @"إنشاء عناصر المخزون";
    PermissionAction *stDelete = [PermissionAction new]; stDelete.key = @"stock.delete"; stDelete.labelEn = @"Delete stock items"; stDelete.labelAr = @"حذف عناصر المخزون";
    stock.actions = @[stView, stManage, stCreate, stDelete];
    [modules addObject:stock];

    // Listings
    PermissionModule *listings = [PermissionModule new];
    listings.key = @"listings";
    listings.labelEn = @"Listings";
    listings.labelAr = @"الإعلانات";
    PermissionAction *lView = [PermissionAction new]; lView.key = @"listings.view"; lView.labelEn = @"View listings"; lView.labelAr = @"عرض الإعلانات";
    PermissionAction *lManage = [PermissionAction new]; lManage.key = @"listings.manage"; lManage.labelEn = @"Manage listings"; lManage.labelAr = @"إدارة الإعلانات";
    PermissionAction *lModerate = [PermissionAction new]; lModerate.key = @"listings.moderate"; lModerate.labelEn = @"Moderate listings"; lModerate.labelAr = @"مراجعة الإعلانات";
    listings.actions = @[lView, lManage, lModerate];
    [modules addObject:listings];

    // Payments
    PermissionModule *payments = [PermissionModule new];
    payments.key = @"payments";
    payments.labelEn = @"Payments";
    payments.labelAr = @"المدفوعات";
    PermissionAction *pView = [PermissionAction new]; pView.key = @"payments.view"; pView.labelEn = @"View payments"; pView.labelAr = @"عرض المدفوعات";
    PermissionAction *pManage = [PermissionAction new]; pManage.key = @"payments.manage"; pManage.labelEn = @"Manage payments"; pManage.labelAr = @"إدارة المدفوعات";
    PermissionAction *pRefund = [PermissionAction new]; pRefund.key = @"payments.refund"; pRefund.labelEn = @"Process refunds"; pRefund.labelAr = @"معالجة الاسترجاعات";
    payments.actions = @[pView, pManage, pRefund];
    [modules addObject:payments];
    
    return modules;
}

@end
