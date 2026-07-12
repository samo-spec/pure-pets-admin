#import "PPPaymentBasicsSettingsViewController.h"

#import "PPButtonHelper.h"
#import "PPPaymentManagementService.h"
#import "Styling.h"

#import <math.h>

static NSString * const kPPPaymentSettingsRowDeliveryFee = @"deliveryFee";
static NSString * const kPPPaymentSettingsRowCashOnDelivery = @"cashOnDeliveryEnabled";
static NSString * const kPPPaymentSettingsRowOnlinePayments = @"onlinePaymentEnabled";

static NSString *PPPaymentBasicsTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static double PPPaymentBasicsDoubleValue(id value)
{
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return [value doubleValue];
    }
    NSString *trimmed = PPPaymentBasicsTrimmedString(value);
    if (trimmed.length == 0) return 0.0;

    NSString *normalized = [[trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."] copy];
    return normalized.doubleValue;
}

@interface PPPaymentBasicsSettingsViewController ()

@property (nonatomic, strong) PPPaymentManagementService *service;
@property (nonatomic, strong, nullable) PPPaymentAdminSettings *settings;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, assign) BOOL isLoadingSettings;
@property (nonatomic, assign) BOOL isSaving;
@property (nonatomic, strong) UIButton *saveButton;

- (void)pp_applyNavigationChrome;
- (void)pp_resetNavigationChrome;
- (void)pp_refreshSaveButton;

@end

@implementation PPPaymentBasicsSettingsViewController

- (instancetype)init
{
    UITableViewStyle style = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) {
        style = UITableViewStyleInsetGrouped;
    }

    self = [super initWithForm:nil style:style];
    if (self) {
        _service = [PPPaymentManagementService shared];
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale currentLocale];
        [_dateFormatter setLocalizedDateFormatFromTemplate:@"d MMM yyyy h:mm a"];
        [self pp_buildForm];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.estimatedSectionHeaderHeight = 32.0;
    self.tableView.estimatedSectionFooterHeight = 44.0;

    [self pp_applySaveButton];
    [self pp_loadSettings];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self pp_applySaveButton];
    [self pp_navBarWithOtherButton:self.saveButton title:kLang(@"PaymentMgmt_Settings_Title")];
    [self pp_applyNavigationChrome];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self pp_resetNavigationChrome];
}

#pragma mark - Form

- (void)pp_buildForm
{
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    XLFormSectionDescriptor *pricingSection =
    [XLFormSectionDescriptor formSectionWithTitle:kLang(@"PaymentMgmt_Settings_Section_Pricing")];
    pricingSection.footerTitle = kLang(@"PaymentMgmt_Settings_Footer_DeliveryFee");
    [form addFormSection:pricingSection];

    XLFormRowDescriptor *deliveryFeeRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:kPPPaymentSettingsRowDeliveryFee
                                          rowType:XLFormRowDescriptorTypeDecimal
                                            title:kLang(@"PaymentMgmt_Settings_Field_DeliveryFee")];
    deliveryFeeRow.required = YES;
    deliveryFeeRow.cellConfigAtConfigure[@"textField.placeholder"] = @"0.00";
    [Styling applyGlobalStyleToRow:deliveryFeeRow];
    [pricingSection addFormRow:deliveryFeeRow];

    XLFormSectionDescriptor *methodsSection =
    [XLFormSectionDescriptor formSectionWithTitle:kLang(@"PaymentMgmt_Settings_Section_Methods")];
    methodsSection.footerTitle = kLang(@"PaymentMgmt_Settings_Footer_Methods");
    [form addFormSection:methodsSection];

    XLFormRowDescriptor *cashRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:kPPPaymentSettingsRowCashOnDelivery
                                          rowType:XLFormRowDescriptorTypeBooleanSwitch
                                            title:kLang(@"PaymentMgmt_Settings_Field_CashOnDelivery")];
    [Styling applyGlobalStyleToRow:cashRow];
    [methodsSection addFormRow:cashRow];

    XLFormRowDescriptor *onlineRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:kPPPaymentSettingsRowOnlinePayments
                                          rowType:XLFormRowDescriptorTypeBooleanSwitch
                                            title:kLang(@"PaymentMgmt_Settings_Field_OnlinePayments")];
    [Styling applyGlobalStyleToRow:onlineRow];
    [methodsSection addFormRow:onlineRow];

    XLFormSectionDescriptor *metaSection = [XLFormSectionDescriptor formSection];
    metaSection.footerTitle = kLang(@"PaymentMgmt_Settings_Footer_Metadata");
    [form addFormSection:metaSection];

    self.form = form;
}

- (void)pp_applySaveButton
{
    if (!self.saveButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.contentEdgeInsets = UIEdgeInsetsMake(7, 14, 7, 14);
        button.layer.cornerRadius = 18.0;
        button.layer.masksToBounds = YES;
        button.layer.borderWidth = 1.0;
        button.titleLabel.font = [Styling fontMedium:17];
        [button addTarget:self action:@selector(onSaveTapped) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintEqualToConstant:36.0].active = YES;
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:58.0].active = YES;
        [PPButtonHelper attachTapAnimationToButton:button style:PPButtonAnimationStylePulse];
        self.saveButton = button;
    }

    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.leftBarButtonItem = nil;
    [self pp_refreshSaveButton];
}

- (void)pp_applyNavigationChrome
{
    UINavigationBar *navBar = self.navigationController.navigationBar;
    if (!navBar) return;

    navBar.tintColor = AppPrimaryClr ?: UIColor.systemBlueColor;

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = AppBackgroundClr;
        appearance.shadowColor = UIColor.clearColor;
        appearance.titleTextAttributes = @{
            NSFontAttributeName: [Styling fontBold:20],
            NSForegroundColorAttributeName: PrimaryTextClr
        };
        navBar.standardAppearance = appearance;
        navBar.scrollEdgeAppearance = appearance;
        navBar.compactAppearance = appearance;
    } else {
        navBar.translucent = NO;
        navBar.barTintColor = AppBackgroundClr;
        navBar.shadowImage = [UIImage new];
    }
}

- (void)pp_resetNavigationChrome
{
    UINavigationBar *navBar = self.navigationController.navigationBar;
    if (!navBar) return;

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.shadowColor = UIColor.clearColor;
        navBar.standardAppearance = appearance;
        navBar.scrollEdgeAppearance = appearance;
        navBar.compactAppearance = appearance;
    } else {
        [navBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
        navBar.shadowImage = [UIImage new];
        navBar.translucent = YES;
        navBar.barTintColor = UIColor.clearColor;
    }
}

- (void)pp_refreshSaveButton
{
    if (!self.saveButton) return;

    UIColor *titleColor = PrimaryTextClr ?: UIColor.labelColor;
    UIColor *borderColor = (AppPrimaryClr ?: UIColor.systemBlueColor);
    BOOL enabled = !(self.isLoadingSettings || self.isSaving);

    [self.saveButton setTitle:kLang(@"PaymentMgmt_Settings_Save") forState:UIControlStateNormal];
    [self.saveButton setTitleColor:titleColor forState:UIControlStateNormal];
    [self.saveButton setTitleColor:[titleColor colorWithAlphaComponent:0.45] forState:UIControlStateDisabled];
    self.saveButton.titleLabel.font = [Styling fontMedium:17];
    self.saveButton.backgroundColor = AppBackgroundClr;
    self.saveButton.layer.borderColor = [borderColor colorWithAlphaComponent:0.18].CGColor;
    self.saveButton.enabled = enabled;
    self.saveButton.alpha = enabled ? 1.0 : 0.65;
}

- (void)pp_applySettingsToForm:(PPPaymentAdminSettings *)settings
{
    self.settings = settings;

    XLFormRowDescriptor *deliveryFeeRow = [self.form formRowWithTag:kPPPaymentSettingsRowDeliveryFee];
    deliveryFeeRow.value = @(MAX(0.0, settings.deliveryFee));

    XLFormRowDescriptor *cashRow = [self.form formRowWithTag:kPPPaymentSettingsRowCashOnDelivery];
    cashRow.value = @(settings.cashOnDeliveryEnabled);

    XLFormRowDescriptor *onlineRow = [self.form formRowWithTag:kPPPaymentSettingsRowOnlinePayments];
    onlineRow.value = @(settings.onlinePaymentEnabled);

    XLFormSectionDescriptor *metaSection = self.form.formSections.count > 2 ? self.form.formSections[2] : nil;
    if (metaSection) {
        NSString *updatedText = settings.updatedAt ? [self.dateFormatter stringFromDate:settings.updatedAt] : kLang(@"PaymentMgmt_Value_NotAvailable");
        NSString *updatedBy = PPPaymentBasicsTrimmedString(settings.updatedBy);
        if (updatedBy.length == 0) updatedBy = kLang(@"PaymentMgmt_Value_SystemDefault");
        metaSection.footerTitle = [NSString stringWithFormat:kLang(@"PaymentMgmt_Settings_Footer_Metadata_Format"), updatedText, updatedBy];
    }

    [self updateFormRow:deliveryFeeRow];
    [self updateFormRow:cashRow];
    [self updateFormRow:onlineRow];
    [self.tableView reloadData];
}

#pragma mark - Data

- (void)pp_loadSettings
{
    if (self.isLoadingSettings) return;
    self.isLoadingSettings = YES;
    [self pp_applySaveButton];
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Loading") subtitle:kLang(@"PaymentMgmt_Settings_Loading")];

    __weak typeof(self) weakSelf = self;
    [self.service loadPaymentSettingsWithCompletion:^(PPPaymentAdminSettings * _Nullable settings, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        [PPHUD dismiss];
        self.isLoadingSettings = NO;
        [self pp_applySaveButton];

        if (error) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"PaymentMgmt_Error_LoadPayments")];
            return;
        }

        [self pp_applySettingsToForm:settings ?: [PPPaymentAdminSettings settingsFromDictionary:@{}]];
    }];
}

- (void)onSaveTapped
{
    if (self.isLoadingSettings || self.isSaving) return;
    [self.view endEditing:YES];

    NSArray<NSError *> *validationErrors = [self formValidationErrors];
    if (validationErrors.count > 0) {
        NSString *message = validationErrors.firstObject.localizedDescription ?: kLang(@"PaymentMgmt_Settings_Error_InvalidDeliveryFee");
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:message];
        return;
    }

    double deliveryFee = PPPaymentBasicsDoubleValue([self.form formRowWithTag:kPPPaymentSettingsRowDeliveryFee].value);
    if (!isfinite(deliveryFee) || deliveryFee < 0.0) {
        [AlertHelper showWarningIn:self
                             title:kLang(@"Error")
                          subtitle:kLang(@"PaymentMgmt_Settings_Error_InvalidDeliveryFee")];
        return;
    }

    BOOL cashEnabled = [[self.form formRowWithTag:kPPPaymentSettingsRowCashOnDelivery].value boolValue];
    BOOL onlineEnabled = [[self.form formRowWithTag:kPPPaymentSettingsRowOnlinePayments].value boolValue];
    if (!(cashEnabled || onlineEnabled)) {
        [AlertHelper showWarningIn:self
                             title:kLang(@"Error")
                          subtitle:kLang(@"PaymentMgmt_Settings_Error_NoMethodEnabled")];
        return;
    }

    PPPaymentAdminSettings *payload = [PPPaymentAdminSettings new];
    payload.deliveryFee = MAX(0.0, deliveryFee);
    payload.cashOnDeliveryEnabled = cashEnabled;
    payload.onlinePaymentEnabled = onlineEnabled;

    self.isSaving = YES;
    [self pp_applySaveButton];
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Loading") subtitle:kLang(@"PaymentMgmt_Loading_Updating")];

    __weak typeof(self) weakSelf = self;
    [self.service savePaymentSettings:payload completion:^(PPPaymentAdminSettings * _Nullable settings, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        [PPHUD dismiss];
        self.isSaving = NO;
        [self pp_applySaveButton];

        if (error) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"PaymentMgmt_Error_UpdateOrder")];
            return;
        }

        PPPaymentAdminSettings *resolvedSettings = settings ?: payload;
        [self pp_applySettingsToForm:resolvedSettings];
        [PPHUD showSuccess:kLang(@"Updated") subtitle:kLang(@"PaymentMgmt_Settings_Saved")];
    }];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    (void)tableView;
    (void)section;

    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.contentView.backgroundColor = UIColor.clearColor;
    if (header.backgroundView) {
        header.backgroundView.backgroundColor = UIColor.clearColor;
    }
    header.textLabel.font = [Styling fontMedium:15];
    header.textLabel.textColor = PrimaryTextClr;
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section
{
    (void)tableView;
    (void)section;

    if (![view isKindOfClass:UITableViewHeaderFooterView.class]) return;
    UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
    footer.contentView.backgroundColor = UIColor.clearColor;
    if (footer.backgroundView) {
        footer.backgroundView.backgroundColor = UIColor.clearColor;
    }
    footer.textLabel.font = [Styling fontRegular:13];
    footer.textLabel.textColor = SeconderyTextClr;
}

@end
