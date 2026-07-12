//
//  PPServiceModerationViewController.m
//  PurePetsAdmin
//

#import "PPServiceModerationViewController.h"
#import "PPServiceModel.h"
#import "PPServiceManager.h"

static NSString * const kTagDisabled = @"serviceModerationDisabled";
static NSString * const kTagBlocked = @"serviceModerationBlocked";
static NSString * const kTagVerification = @"serviceModerationVerification";
static NSString * const kTagSubType = @"serviceModerationSubType";
static NSString * const kTagSubPlan = @"serviceModerationSubPlan";
static NSString * const kTagSubStatus = @"serviceModerationSubStatus";
static NSString * const kTagSubActive = @"serviceModerationSubActive";
static NSString * const kTagSubStart = @"serviceModerationSubStart";
static NSString * const kTagSubEnd = @"serviceModerationSubEnd";
static NSString * const kTagFlagsJSON = @"serviceModerationFlags";
static NSString * const kTagAuditNote = @"serviceModerationAudit";

@interface _PPServiceHeroMetricView : UIView
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *valueLabel;
- (instancetype)initWithCaption:(NSString *)caption;
- (void)updateValue:(NSString *)value accent:(UIColor *)accent;
@end

@implementation _PPServiceHeroMetricView

- (instancetype)initWithCaption:(NSString *)caption {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [AppBackgroundClr colorWithAlphaComponent:0.84];
        self.layer.cornerRadius = 18.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _captionLabel = [UILabel new];
        _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _captionLabel.font = [Styling fontMedium:10];
        _captionLabel.textColor = SeconderyTextClr;
        _captionLabel.text = caption;
        [self addSubview:_captionLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:15];
        _valueLabel.textColor = PrimaryTextClr;
        _valueLabel.numberOfLines = 2;
        [self addSubview:_valueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_captionLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [_captionLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_captionLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_valueLabel.topAnchor constraintEqualToAnchor:_captionLabel.bottomAnchor constant:5],
            [_valueLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_valueLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12]
        ]];
    }
    return self;
}

- (void)updateValue:(NSString *)value accent:(UIColor *)accent {
    self.valueLabel.text = value.length > 0 ? value : @"—";
    self.valueLabel.textColor = accent ?: PrimaryTextClr;
}

@end

@interface PPServiceModerationViewController ()
@property (nonatomic, strong) PPServiceModel *service;
@property (nonatomic, strong) UIView *headerRoot;
@property (nonatomic, strong) UIView *heroCard;
@property (nonatomic, strong) UIImageView *heroImageView;
@property (nonatomic, strong) UILabel *eyebrowLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusPillLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) _PPServiceHeroMetricView *verificationMetric;
@property (nonatomic, strong) _PPServiceHeroMetricView *subscriptionMetric;
@property (nonatomic, strong) _PPServiceHeroMetricView *ownerMetric;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation PPServiceModerationViewController

- (instancetype)initWithService:(PPServiceModel *)service {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    self = [super initWithForm:form style:UITableViewStyleInsetGrouped];
    if (self) {
        _service = service;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 4.0;
    }

    self.dateFormatter = [NSDateFormatter new];
    self.dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    self.dateFormatter.timeStyle = NSDateFormatterNoStyle;

    [self buildForm];
    [self populateForm];
    [self setupHeader];
    [self updateHeaderSummary];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:kLang(@"Service_Moderation_Title") showBack:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect frame = self.headerRoot.frame;
    frame.size.width = self.view.bounds.size.width;
    self.headerRoot.frame = frame;
    self.tableView.tableHeaderView = self.headerRoot;
}

#pragma mark - Header

- (void)setupHeader {
    self.headerRoot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 286)];
    self.headerRoot.backgroundColor = UIColor.clearColor;

    self.heroCard = [UIView new];
    self.heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroCard.backgroundColor = AppForgroundColr;
    self.heroCard.layer.cornerRadius = 30.0;
    self.heroCard.layer.cornerCurve = kCACornerCurveContinuous;
    self.heroCard.clipsToBounds = YES;
    [self.headerRoot addSubview:self.heroCard];

    UIView *accentWash = [UIView new];
    accentWash.translatesAutoresizingMaskIntoConstraints = NO;
    accentWash.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.08];
    [self.heroCard addSubview:accentWash];

    self.heroImageView = [UIImageView new];
    self.heroImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.heroImageView.layer.cornerRadius = 24.0;
    self.heroImageView.layer.cornerCurve = kCACornerCurveContinuous;
    self.heroImageView.clipsToBounds = YES;
    self.heroImageView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.10];
    [self.heroCard addSubview:self.heroImageView];

    self.eyebrowLabel = [UILabel new];
    self.eyebrowLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.eyebrowLabel.font = [Styling fontMedium:12];
    self.eyebrowLabel.textColor = SeconderyTextClr;
    self.eyebrowLabel.text = kLang(@"Service_Moderation_Title");
    [self.heroCard addSubview:self.eyebrowLabel];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [Styling fontBold:26];
    self.titleLabel.textColor = PrimaryTextClr;
    self.titleLabel.numberOfLines = 2;
    [self.heroCard addSubview:self.titleLabel];

    self.statusPillLabel = [UILabel new];
    self.statusPillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPillLabel.font = [Styling fontBold:12];
    self.statusPillLabel.textAlignment = NSTextAlignmentCenter;
    self.statusPillLabel.layer.cornerRadius = 14.0;
    self.statusPillLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusPillLabel.clipsToBounds = YES;
    [self.heroCard addSubview:self.statusPillLabel];

    self.detailLabel = [UILabel new];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.font = [Styling fontMedium:13];
    self.detailLabel.textColor = SeconderyTextClr;
    self.detailLabel.numberOfLines = 2;
    [self.heroCard addSubview:self.detailLabel];

    self.verificationMetric = [[_PPServiceHeroMetricView alloc] initWithCaption:kLang(@"Service_Field_VerificationStatus")];
    self.subscriptionMetric = [[_PPServiceHeroMetricView alloc] initWithCaption:kLang(@"Service_Field_SubscriptionStatus")];
    self.ownerMetric = [[_PPServiceHeroMetricView alloc] initWithCaption:kLang(@"Service_Field_OwnerID")];

    UIStackView *metricStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.verificationMetric,
        self.subscriptionMetric,
        self.ownerMetric
    ]];
    metricStack.translatesAutoresizingMaskIntoConstraints = NO;
    metricStack.axis = UILayoutConstraintAxisHorizontal;
    metricStack.spacing = 10.0;
    metricStack.distribution = UIStackViewDistributionFillEqually;
    [self.heroCard addSubview:metricStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroCard.topAnchor constraintEqualToAnchor:self.headerRoot.topAnchor constant:10],
        [self.heroCard.leadingAnchor constraintEqualToAnchor:self.headerRoot.leadingAnchor constant:18],
        [self.heroCard.trailingAnchor constraintEqualToAnchor:self.headerRoot.trailingAnchor constant:-18],
        [self.heroCard.bottomAnchor constraintEqualToAnchor:self.headerRoot.bottomAnchor constant:-14],

        [accentWash.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor],
        [accentWash.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor],
        [accentWash.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor],
        [accentWash.heightAnchor constraintEqualToConstant:120],

        [self.heroImageView.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:20],
        [self.heroImageView.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:18],
        [self.heroImageView.widthAnchor constraintEqualToConstant:88],
        [self.heroImageView.heightAnchor constraintEqualToConstant:88],

        [self.eyebrowLabel.topAnchor constraintEqualToAnchor:self.heroCard.topAnchor constant:24],
        [self.eyebrowLabel.leadingAnchor constraintEqualToAnchor:self.heroImageView.trailingAnchor constant:16],
        [self.eyebrowLabel.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-18],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.eyebrowLabel.bottomAnchor constant:6],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.eyebrowLabel.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-18],

        [self.statusPillLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        [self.statusPillLabel.leadingAnchor constraintEqualToAnchor:self.eyebrowLabel.leadingAnchor],

        [self.detailLabel.topAnchor constraintEqualToAnchor:self.statusPillLabel.bottomAnchor constant:10],
        [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.eyebrowLabel.leadingAnchor],
        [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-18],

        [metricStack.leadingAnchor constraintEqualToAnchor:self.heroCard.leadingAnchor constant:18],
        [metricStack.trailingAnchor constraintEqualToAnchor:self.heroCard.trailingAnchor constant:-18],
        [metricStack.bottomAnchor constraintEqualToAnchor:self.heroCard.bottomAnchor constant:-18]
    ]];

    self.tableView.tableHeaderView = self.headerRoot;

    if (self.service.imageURL.length > 0) {
        [self.heroImageView setImageFromUrl:self.service.imageURL
                           placeholderImage:@"placeholder"
                                        Blr:YES
                                 Shimmering:YES
                                 completion:nil];
    } else {
        self.heroImageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
        self.heroImageView.tintColor = AppPrimaryClr;
        self.heroImageView.contentMode = UIViewContentModeCenter;
    }
}

- (void)updateHeaderSummary {
    self.titleLabel.text = self.service.title.length > 0 ? self.service.title : @"—";
    NSString *status = [self currentStatusTitle];
    UIColor *statusColor = [self currentStatusColor];
    self.statusPillLabel.text = [NSString stringWithFormat:@"  %@  ", status];
    self.statusPillLabel.textColor = statusColor;
    self.statusPillLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.14];

    NSString *availability = self.service.availableDate ? [self.dateFormatter stringFromDate:self.service.availableDate] : kLang(@"Service_Value_NotSpecified");
    self.detailLabel.text = [NSString stringWithFormat:@"%@ · %@", [self.service localizedTypeName], availability];

    [self.verificationMetric updateValue:[self currentVerificationTitle] accent:[self verificationAccentColor]];
    [self.subscriptionMetric updateValue:[self currentSubscriptionSummary] accent:AppPrimaryClr];
    [self.ownerMetric updateValue:(self.service.serviceOwnerID.length > 0 ? self.service.serviceOwnerID : @"—") accent:PrimaryTextClr];
}

#pragma mark - Form

- (void)buildForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    XLFormSectionDescriptor *statusSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Service_Moderation_StatusSection")];
    [form addFormSection:statusSection];

    [statusSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagDisabled rowType:XLFormRowDescriptorTypeBooleanSwitch title:kLang(@"Service_Field_IsDisabled")]];
    [statusSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagBlocked rowType:XLFormRowDescriptorTypeBooleanSwitch title:kLang(@"Service_Field_IsBlocked")]];
    [statusSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagVerification rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_VerificationStatus")]];

    XLFormSectionDescriptor *subscriptionSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Service_Moderation_SubscriptionSection")];
    [form addFormSection:subscriptionSection];

    [subscriptionSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagSubType rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_SubscriptionType")]];
    [subscriptionSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagSubPlan rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_SubscriptionPlan")]];
    [subscriptionSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagSubStatus rowType:XLFormRowDescriptorTypeText title:kLang(@"Service_Field_SubscriptionStatus")]];
    [subscriptionSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagSubActive rowType:XLFormRowDescriptorTypeBooleanSwitch title:kLang(@"Service_Field_SubscriptionActive")]];
    [subscriptionSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagSubStart rowType:XLFormRowDescriptorTypeDateInline title:kLang(@"Service_Field_SubscriptionStart")]];
    [subscriptionSection addFormRow:[XLFormRowDescriptor formRowDescriptorWithTag:kTagSubEnd rowType:XLFormRowDescriptorTypeDateInline title:kLang(@"Service_Field_SubscriptionEnd")]];

    XLFormSectionDescriptor *flagsSection = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Service_Moderation_FlagsSection")];
    [form addFormSection:flagsSection];

    XLFormRowDescriptor *flagsRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagFlagsJSON rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Service_Field_ServiceFlags")];
    flagsRow.cellConfig[@"textView.placeholder"] = kLang(@"Service_Field_ServiceFlags_Placeholder");
    [flagsSection addFormRow:flagsRow];

    XLFormRowDescriptor *auditRow = [XLFormRowDescriptor formRowDescriptorWithTag:kTagAuditNote rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Service_Field_AuditNote")];
    auditRow.cellConfig[@"textView.placeholder"] = kLang(@"Service_Field_AuditNote_Placeholder");
    [flagsSection addFormRow:auditRow];

    XLFormSectionDescriptor *actionSection = [XLFormSectionDescriptor formSection];
    [form addFormSection:actionSection];

    XLFormRowDescriptor *saveRow = [XLFormRowDescriptor formRowDescriptorWithTag:@"saveModeration" rowType:XLFormRowDescriptorTypeButton title:kLang(@"Service_Action_SaveModeration")];
    saveRow.action.formSelector = @selector(saveTapped);
    [actionSection addFormRow:saveRow];
    self.tableView.backgroundColor = AppForgroundColr;
    self.form = form;
}

- (void)populateForm {
    [self.form formRowWithTag:kTagDisabled].value = @(self.service.isDisabled);
    [self.form formRowWithTag:kTagBlocked].value = @(self.service.isBlocked);
    [self.form formRowWithTag:kTagVerification].value = self.service.verificationStatus;
    [self.form formRowWithTag:kTagSubType].value = self.service.subscriptionType;
    [self.form formRowWithTag:kTagSubPlan].value = self.service.subscriptionPlan;
    [self.form formRowWithTag:kTagSubStatus].value = self.service.subscriptionStatus;
    [self.form formRowWithTag:kTagSubActive].value = @(self.service.subscriptionActive);
    [self.form formRowWithTag:kTagSubStart].value = self.service.subscriptionStartDate;
    [self.form formRowWithTag:kTagSubEnd].value = self.service.subscriptionEndDate;
    [self.form formRowWithTag:kTagFlagsJSON].value = [self prettyJSONStringFromDictionary:self.service.serviceFlags];
}

- (void)saveTapped {
    NSDictionary *values = [self formValues];
    NSError *parseError = nil;
    NSDictionary *serviceFlags = [self dictionaryFromJSONText:PPSafeString(values[kTagFlagsJSON]) error:&parseError];
    if (parseError) {
        [PPHUD showError:kLang(@"Error") subtitle:parseError.localizedDescription];
        return;
    }

    PPServiceModel *candidate = [self.service copy];
    candidate.isDisabled = [values[kTagDisabled] boolValue];
    candidate.isBlocked = [values[kTagBlocked] boolValue];
    candidate.verificationStatus = PPSafeString(values[kTagVerification]);
    candidate.subscriptionType = PPSafeString(values[kTagSubType]);
    candidate.subscriptionPlan = PPSafeString(values[kTagSubPlan]);
    candidate.subscriptionStatus = PPSafeString(values[kTagSubStatus]);
    candidate.subscriptionActive = [values[kTagSubActive] boolValue];
    candidate.subscriptionStartDate = [values[kTagSubStart] isKindOfClass:NSDate.class] ? values[kTagSubStart] : nil;
    candidate.subscriptionEndDate = [values[kTagSubEnd] isKindOfClass:NSDate.class] ? values[kTagSubEnd] : nil;
    candidate.serviceFlags = serviceFlags ?: @{};

    if (candidate.subscriptionStartDate &&
        candidate.subscriptionEndDate &&
        [candidate.subscriptionStartDate compare:candidate.subscriptionEndDate] == NSOrderedDescending) {
        [PPHUD showError:kLang(@"Error") subtitle:kLang(@"Service_Error_SubscriptionDateOrder")];
        return;
    }

    NSString *auditNote = PPSafeString(values[kTagAuditNote]);
    [PPHUD showIndeterminateIn:self.view title:kLang(@"Service_Saving") subtitle:nil];

    __weak typeof(self) weakSelf = self;
    [[PPServiceManager sharedManager] updateAdministrativeStateForService:candidate
                                                                auditNote:auditNote
                                                               completion:^(NSError * _Nullable error) {
        [PPHUD dismiss];
        if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            return;
        }
        weakSelf.service = candidate;
        [weakSelf updateHeaderSummary];
        [PPHUD showSuccess:kLang(@"Success_Title") subtitle:kLang(@"Service_Moderation_Updated_Success")];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
    }];
}

#pragma mark - XLForm

- (void)formRowDescriptorValueHasChanged:(XLFormRowDescriptor *)formRow oldValue:(id)oldValue newValue:(id)newValue {
    [super formRowDescriptorValueHasChanged:formRow oldValue:oldValue newValue:newValue];

    self.service.isDisabled = [[self.form formRowWithTag:kTagDisabled].value boolValue];
    self.service.isBlocked = [[self.form formRowWithTag:kTagBlocked].value boolValue];
    self.service.verificationStatus = PPSafeString([self.form formRowWithTag:kTagVerification].value);
    self.service.subscriptionPlan = PPSafeString([self.form formRowWithTag:kTagSubPlan].value);
    self.service.subscriptionStatus = PPSafeString([self.form formRowWithTag:kTagSubStatus].value);
    self.service.subscriptionType = PPSafeString([self.form formRowWithTag:kTagSubType].value);
    self.service.subscriptionActive = [[self.form formRowWithTag:kTagSubActive].value boolValue];
    [self updateHeaderSummary];
}

#pragma mark - Helpers

- (NSString *)currentStatusTitle {
    if (self.service.isDeleted) return kLang(@"Service_Status_Archived");
    if (self.service.isBlocked) return kLang(@"Service_Status_Blocked");
    if (self.service.isDisabled) return kLang(@"Service_Status_Disabled");
    return kLang(@"Service_Status_Active");
}

- (UIColor *)currentStatusColor {
    if (self.service.isDeleted) return UIColor.systemGrayColor;
    if (self.service.isBlocked) return UIColor.systemRedColor;
    if (self.service.isDisabled) return UIColor.systemOrangeColor;
    return UIColor.systemGreenColor;
}

- (NSString *)currentVerificationTitle {
    return [self.service localizedVerificationTitle];
}

- (UIColor *)verificationAccentColor {
    NSString *normalized = [[PPSafeString(self.service.verificationStatus) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([normalized isEqualToString:@"verified"]) return UIColor.systemGreenColor;
    if ([normalized isEqualToString:@"rejected"]) return UIColor.systemRedColor;
    if ([normalized isEqualToString:@"pending"] || [normalized isEqualToString:@"pending_review"] || [normalized isEqualToString:@"verification_pending"]) return UIColor.systemOrangeColor;
    return PrimaryTextClr;
}

- (NSString *)currentSubscriptionSummary {
    return [self.service localizedSubscriptionSummary];
}

- (NSDictionary *)dictionaryFromJSONText:(NSString *)jsonText error:(NSError * _Nullable __autoreleasing *)errorPointer {
    NSString *trimmed = [[PPSafeString(jsonText) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (trimmed.length == 0) {
        return @{};
    }
    NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    NSError *parseError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    if (parseError || ![object isKindOfClass:NSDictionary.class]) {
        if (errorPointer) {
            *errorPointer = [NSError errorWithDomain:@"pp.service.moderation"
                                                code:400
                                            userInfo:@{NSLocalizedDescriptionKey: kLang(@"Service_Error_FlagsJSONInvalid")}];
        }
        return nil;
    }
    return object;
}

- (NSString *)prettyJSONStringFromDictionary:(NSDictionary *)dictionary {
    NSDictionary *safe = PPSafeDict(dictionary);
    if (safe.count == 0) {
        return @"";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

@end
