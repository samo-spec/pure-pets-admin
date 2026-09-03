#import "PPPaymentBasicsSettingsViewController.h"

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

static UIFont *PPPaymentBasicsScaledFont(UIFont *baseFont, UIFontTextStyle textStyle)
{
    if (!baseFont) return [UIFont preferredFontForTextStyle:textStyle];
    return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
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
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.estimatedSectionHeaderHeight = 32.0;
    self.tableView.estimatedSectionFooterHeight = 44.0;

    [self pp_setupDossierHeader];
    [self pp_applySaveButton];
    [self pp_loadSettings];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (!self.tableView.tableHeaderView) return;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;
    CGSize fitting = [self.tableView.tableHeaderView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                                   withHorizontalFittingPriority:UILayoutPriorityRequired
                                                         verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGRect frame = self.tableView.tableHeaderView.frame;
    CGFloat targetHeight = MAX(fitting.height, 104.0);
    if (fabs(frame.size.width - width) > 0.5 || fabs(frame.size.height - targetHeight) > 0.5) {
        frame.size.width = width;
        frame.size.height = targetHeight;
        self.tableView.tableHeaderView.frame = frame;
        self.tableView.tableHeaderView = self.tableView.tableHeaderView;
    }
}

- (void)pp_onBackTapped
{
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)pp_setupDossierHeader
{
    CGFloat horizontal = PPScreenMargin;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;

    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 110.0)];
    headerContainer.backgroundColor = UIColor.clearColor;

    // 1. Navigation Top Bar (Back Button + Save Button / Indicator)
    UIButton *backBtn = [self pp_BackButtonWithSystemName:PPNavBackSymbolName() action:@selector(pp_onBackTapped)];
    [headerContainer addSubview:backBtn];

    UIButton *saveActionBtn = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(pp_saveButtonTapped:)];
    [headerContainer addSubview:saveActionBtn];

    // 2. Eyebrow Category Breadcrumb
    UILabel *eyebrowLabel = [UILabel new];
    eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    eyebrowLabel.font = [Styling fontRegular:12];
    eyebrowLabel.textColor = [UIColor ppTextSecondary];
    eyebrowLabel.text = [NSString stringWithFormat:@"%@ / %@", kLang(@"CommandCenter_Work_Workspace"), kLang(@"PaymentMgmt_Settings_Title")];
    eyebrowLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [headerContainer addSubview:eyebrowLabel];

    // 3. Dossier Large Title
    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:22];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = kLang(@"PaymentMgmt_Settings_Title");
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [headerContainer addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        // Back Button & Save Button
        [backBtn.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:4],
        [backBtn.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [backBtn.widthAnchor constraintEqualToConstant:44],
        [backBtn.heightAnchor constraintEqualToConstant:44],

        [saveActionBtn.centerYAnchor constraintEqualToAnchor:backBtn.centerYAnchor],
        [saveActionBtn.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],
        [saveActionBtn.heightAnchor constraintEqualToConstant:38],

        // Eyebrow
        [eyebrowLabel.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:2],
        [eyebrowLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [eyebrowLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],

        // Title
        [titleLabel.topAnchor constraintEqualToAnchor:eyebrowLabel.bottomAnchor constant:2],
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:horizontal],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-horizontal],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerContainer.bottomAnchor constant:-8]
    ]];

    self.tableView.tableHeaderView = headerContainer;
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
        button.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);
        PPApplyContinuousCorners(button, PPCorner16);
        button.titleLabel.font = PPPaymentBasicsScaledFont([Styling fontBold:15], UIFontTextStyleCallout);
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.titleLabel.numberOfLines = 1;
        [button addTarget:self action:@selector(onSaveTapped) forControlEvents:UIControlEventTouchUpInside];
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:72.0].active = YES;
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

    navBar.tintColor = [UIColor ppPrimary];

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.shadowColor = UIColor.clearColor;
        appearance.shadowImage = [[UIImage alloc] init];
        appearance.titleTextAttributes = @{
            NSFontAttributeName: PPPaymentBasicsScaledFont([Styling fontBold:20], UIFontTextStyleHeadline),
            NSForegroundColorAttributeName: [UIColor ppTextPrimary]
        };
        navBar.standardAppearance = appearance;
        navBar.scrollEdgeAppearance = appearance;
        navBar.compactAppearance = appearance;
    } else {
        navBar.translucent = YES;
        navBar.barTintColor = UIColor.clearColor;
        navBar.shadowImage = [UIImage new];
        [navBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
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

    BOOL enabled = !(self.isLoadingSettings || self.isSaving);
    UIColor *activeTitle = UIColor.whiteColor;
    UIColor *disabledTitle = [UIColor.whiteColor colorWithAlphaComponent:0.62];

    [self.saveButton setTitle:kLang(@"PaymentMgmt_Settings_Save") forState:UIControlStateNormal];
    [self.saveButton setTitleColor:activeTitle forState:UIControlStateNormal];
    [self.saveButton setTitleColor:disabledTitle forState:UIControlStateDisabled];
    self.saveButton.titleLabel.font = PPPaymentBasicsScaledFont([Styling fontBold:15], UIFontTextStyleCallout);
    self.saveButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.saveButton.backgroundColor = enabled
        ? [UIColor ppPrimary]
        : [[UIColor ppPrimary] colorWithAlphaComponent:0.30];
    self.saveButton.layer.borderWidth = 0.0;
    self.saveButton.enabled = enabled;
    self.saveButton.alpha = enabled ? 1.0 : 0.76;
    self.saveButton.accessibilityLabel = kLang(@"PaymentMgmt_Settings_Save");
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
            [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_LoadPayments")];
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
        [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:message];
        return;
    }

    double deliveryFee = PPPaymentBasicsDoubleValue([self.form formRowWithTag:kPPPaymentSettingsRowDeliveryFee].value);
    if (!isfinite(deliveryFee) || deliveryFee < 0.0) {
        [PPAlertHelper showWarningIn:self
                             title:kLang(@"Error")
                          subtitle:kLang(@"PaymentMgmt_Settings_Error_InvalidDeliveryFee")];
        return;
    }

    BOOL cashEnabled = [[self.form formRowWithTag:kPPPaymentSettingsRowCashOnDelivery].value boolValue];
    BOOL onlineEnabled = [[self.form formRowWithTag:kPPPaymentSettingsRowOnlinePayments].value boolValue];
    if (!(cashEnabled || onlineEnabled)) {
        [PPAlertHelper showWarningIn:self
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
            [PPAlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"PaymentMgmt_Error_UpdateOrder")];
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
    header.textLabel.font = PPPaymentBasicsScaledFont([Styling fontMedium:15], UIFontTextStyleHeadline);
    header.textLabel.adjustsFontForContentSizeCategory = YES;
    header.textLabel.textColor = [UIColor ppTextPrimary];
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
    footer.textLabel.font = PPPaymentBasicsScaledFont([Styling fontRegular:13], UIFontTextStyleFootnote);
    footer.textLabel.adjustsFontForContentSizeCategory = YES;
    footer.textLabel.textColor = [UIColor ppTextSecondary];
}

@end
