//
//  PPServiceDetailViewController.m
//  PurePetsAdmin
//

#import "PPServiceDetailViewController.h"
#import "PPServiceModel.h"
#import "PPServiceManager.h"
#import "PPAddEditServiceViewController.h"
#import "PPServiceModerationViewController.h"

@interface PPServiceDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) PPServiceModel *service;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIImageView *headerImageView;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerMetaLabel;
@property (nonatomic, strong) UILabel *headerStatusLabel;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) UIView *actionBar;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation PPServiceDetailViewController

- (instancetype)initWithService:(PPServiceModel *)service {
    self = [super init];
    if (self) {
        _service = service;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.dateFormatter = [NSDateFormatter new];
    self.dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    self.dateFormatter.timeStyle = NSDateFormatterNoStyle;
    [self buildRows];
    [self setupHeader];
    [self setupTableView];
    [self setupActionBar];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:(self.service.title.length > 0 ? self.service.title : kLang(@"Service_Detail_Title")) showBack:YES];
    [self reloadService];
}

#pragma mark - Data

- (void)reloadService {
    if (self.service.serviceID.length == 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[PPServiceManager sharedManager] fetchServiceByID:self.service.serviceID completion:^(PPServiceModel * _Nullable service, NSError * _Nullable error) {
        if (service) {
            weakSelf.service = service;
            [weakSelf buildRows];
            [weakSelf refreshHeader];
            [weakSelf.tableView reloadData];
        } else if (error) {
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        }
    }];
}

- (void)buildRows {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];

    [rows addObject:@{@"title": kLang(@"Service_Field_ID"), @"value": self.service.serviceID ?: @"—"}];
    [rows addObject:@{@"title": kLang(@"Service_Field_Title"), @"value": self.service.title ?: @"—"}];
    [rows addObject:@{@"title": kLang(@"Service_Field_Description"), @"value": self.service.serviceDescriptionText ?: @"—"}];
    [rows addObject:@{@"title": kLang(@"Service_Field_Price"), @"value": [NSString stringWithFormat:@"%.2f %@", self.service.price, kLang(@"QAR")]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_Type"), @"value": [self.service localizedTypeName]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_Category"), @"value": (self.service.category.length > 0 ? self.service.category : @"—")}];
    [rows addObject:@{@"title": kLang(@"Service_Field_CategoryID"), @"value": (self.service.categoryID.length > 0 ? self.service.categoryID : @"—")}];
    [rows addObject:@{@"title": kLang(@"Service_Field_OwnerID"), @"value": (self.service.serviceOwnerID.length > 0 ? self.service.serviceOwnerID : @"—")}];
    [rows addObject:@{@"title": kLang(@"Service_Field_PetMainKindID"), @"value": [NSString stringWithFormat:@"%ld", (long)self.service.petMainKindID]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_AvailableDate"), @"value": [self formattedDate:self.service.availableDate]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_Timestamp"), @"value": [self formattedDate:self.service.timestamp]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_Status"), @"value": [self.service localizedPrimaryStatusTitle]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_VerificationStatus"), @"value": [self.service localizedVerificationTitle]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_SubscriptionType"), @"value": (self.service.subscriptionType.length > 0 ? self.service.subscriptionType : @"—")}];
    [rows addObject:@{@"title": kLang(@"Service_Field_SubscriptionPlan"), @"value": (self.service.subscriptionPlan.length > 0 ? self.service.subscriptionPlan : @"—")}];
    [rows addObject:@{@"title": kLang(@"Service_Field_SubscriptionStatus"), @"value": (self.service.subscriptionStatus.length > 0 ? self.service.subscriptionStatus : @"—")}];
    [rows addObject:@{@"title": kLang(@"Service_Field_SubscriptionActive"), @"value": (self.service.subscriptionActive ? kLang(@"Service_Subscription_Active") : kLang(@"Service_Subscription_Inactive"))}];
    [rows addObject:@{@"title": kLang(@"Service_Field_SubscriptionStart"), @"value": [self formattedDate:self.service.subscriptionStartDate]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_SubscriptionEnd"), @"value": [self formattedDate:self.service.subscriptionEndDate]}];
    [rows addObject:@{@"title": kLang(@"Service_Field_ImageURL"), @"value": (self.service.imageURL.length > 0 ? self.service.imageURL : @"—"), @"long": @YES}];
    [rows addObject:@{@"title": kLang(@"Service_Field_BlurHash"), @"value": (self.service.blurHash.length > 0 ? self.service.blurHash : @"—"), @"long": @YES}];

    if (self.service.serviceFlags.count > 0) {
        [rows addObject:@{@"title": kLang(@"Service_Field_ServiceFlags"), @"value": [self prettyJSONString:self.service.serviceFlags], @"long": @YES}];
    }
    if (self.service.extraFields.count > 0) {
        [rows addObject:@{@"title": kLang(@"Service_Field_ExtraJSON"), @"value": [self prettyJSONString:self.service.extraFields], @"long": @YES}];
    }
    if (self.service.createdAt) {
        [rows addObject:@{@"title": kLang(@"Service_Field_CreatedAt"), @"value": [self formattedDate:self.service.createdAt]}];
    }
    if (self.service.updatedAt) {
        [rows addObject:@{@"title": kLang(@"Service_Field_UpdatedAt"), @"value": [self formattedDate:self.service.updatedAt]}];
    }

    self.rows = rows.copy;
}

#pragma mark - UI

- (void)setupHeader {
    CGFloat headerHeight = 248.0;
    self.headerImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, headerHeight)];
    self.headerImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.headerImageView.clipsToBounds = YES;
    self.headerImageView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.08];

    UIView *overlay = [[UIView alloc] initWithFrame:self.headerImageView.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.28];
    [self.headerImageView addSubview:overlay];

    self.headerTitleLabel = [UILabel new];
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitleLabel.font = [Styling fontBold:28];
    self.headerTitleLabel.textColor = UIColor.whiteColor;
    self.headerTitleLabel.numberOfLines = 2;
    self.headerTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.headerTitleLabel.adjustsFontForContentSizeCategory = YES;
    [overlay addSubview:self.headerTitleLabel];

    self.headerMetaLabel = [UILabel new];
    self.headerMetaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerMetaLabel.font = [Styling fontMedium:13];
    self.headerMetaLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.92];
    self.headerMetaLabel.numberOfLines = 2;
    self.headerMetaLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.headerMetaLabel.adjustsFontForContentSizeCategory = YES;
    [overlay addSubview:self.headerMetaLabel];

    self.headerStatusLabel = [UILabel new];
    self.headerStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerStatusLabel.font = [Styling fontBold:12];
    self.headerStatusLabel.textAlignment = NSTextAlignmentCenter;
    self.headerStatusLabel.adjustsFontForContentSizeCategory = YES;
    self.headerStatusLabel.layer.cornerRadius = 14.0;
    self.headerStatusLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.headerStatusLabel.clipsToBounds = YES;
    [overlay addSubview:self.headerStatusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerTitleLabel.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:18],
        [self.headerTitleLabel.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-18],
        [self.headerTitleLabel.bottomAnchor constraintEqualToAnchor:self.headerMetaLabel.topAnchor constant:-8],

        [self.headerMetaLabel.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:18],
        [self.headerMetaLabel.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-18],
        [self.headerMetaLabel.bottomAnchor constraintEqualToAnchor:self.headerStatusLabel.topAnchor constant:-10],

        [self.headerStatusLabel.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:18],
        [self.headerStatusLabel.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor constant:-18]
    ]];

    [self refreshHeader];
}

- (void)refreshHeader {
    if (self.service.imageURL.length > 0) {
        self.headerImageView.contentMode = UIViewContentModeScaleAspectFill;
        [self.headerImageView setImageFromUrl:self.service.imageURL
                             placeholderImage:@"placeholder"
                                          Blr:YES
                                   Shimmering:YES
                                   completion:nil];
    } else {
        self.headerImageView.image = [UIImage systemImageNamed:@"sparkles.rectangle.stack.fill"];
        self.headerImageView.tintColor = AppPrimaryClr;
        self.headerImageView.contentMode = UIViewContentModeCenter;
    }

    self.headerTitleLabel.text = self.service.title.length > 0 ? self.service.title : @"—";
    self.headerMetaLabel.text = [NSString stringWithFormat:@"%@ · %@", [self.service localizedVerificationTitle], [self.service localizedSubscriptionSummary]];
    UIColor *statusColor = [self currentStatusColor];
    self.headerStatusLabel.text = [NSString stringWithFormat:@"  %@  ", [self.service localizedPrimaryStatusTitle]];
    self.headerStatusLabel.textColor = statusColor;
    self.headerStatusLabel.backgroundColor = [statusColor colorWithAlphaComponent:0.18];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.tableView.tableHeaderView = self.headerImageView;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 14.0, 0.0);
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupActionBar {
    self.actionBar = [UIView new];
    self.actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.actionBar.backgroundColor = [AppForgroundColr colorWithAlphaComponent:0.94];
    self.actionBar.layer.shadowColor = AppShadowColor.CGColor;
    self.actionBar.layer.shadowOpacity = 0.08;
    self.actionBar.layer.shadowRadius = 18.0;
    self.actionBar.layer.shadowOffset = CGSizeMake(0.0, -8.0);
    [self.view addSubview:self.actionBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.actionBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.actionBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.actionBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.actionBar.heightAnchor constraintEqualToConstant:68]
    ]];

    NSArray<NSString *> *icons = @[@"square.and.pencil", @"slider.horizontal.3", (self.service.isDeleted ? @"arrow.uturn.backward.circle" : @"archivebox"), @"trash"];
    NSArray<NSString *> *selectors = @[@"editTapped", @"moderationTapped", @"archiveTapped", @"deleteTapped"];
    NSArray<UIColor *> *colors = @[[UIColor ppInfo], [UIColor ppPrimary], [UIColor ppWarning], [UIColor ppError]];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 22.0;
    stack.alignment = UIStackViewAlignmentCenter;
    [self.actionBar addSubview:stack];

    for (NSUInteger idx = 0; idx < icons.count; idx++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tintColor = UIColor.whiteColor;
        button.backgroundColor = colors[idx];
        button.layer.cornerRadius = 25.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.clipsToBounds = YES;
        [button setImage:[UIImage systemImageNamed:icons[idx]] forState:UIControlStateNormal];
        [button addTarget:self action:NSSelectorFromString(selectors[idx]) forControlEvents:UIControlEventTouchUpInside];
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:50],
            [button.heightAnchor constraintEqualToConstant:50]
        ]];
        [PPButtonHelper attachTapAnimationToButton:button style:PPButtonAnimationStylePulse];
        [stack addArrangedSubview:button];
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.actionBar.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.actionBar.centerYAnchor]
    ]];
}

#pragma mark - Actions

- (void)editTapped {
    [PPFunc pp_playTapEffect];
    PPAddEditServiceViewController *controller = [[PPAddEditServiceViewController alloc] initWithService:self.service];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)moderationTapped {
    [PPFunc pp_playTapEffect];
    PPServiceModerationViewController *controller = [[PPServiceModerationViewController alloc] initWithService:self.service];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)archiveTapped {
    __weak typeof(self) weakSelf = self;
    BOOL shouldArchive = !self.service.isDeleted;
    [PPAlertHelper showConfirmationIn:self
                              title:(shouldArchive ? kLang(@"Service_Confirm_Archive_Title") : kLang(@"Service_Confirm_Restore_Title"))
                           subtitle:(shouldArchive ? kLang(@"Service_Confirm_Archive_Subtitle") : kLang(@"Service_Confirm_Restore_Subtitle"))
                        placeholder:nil
                      confirmButton:(shouldArchive ? kLang(@"Service_Action_Archive") : kLang(@"Service_Action_Restore"))
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Service_Updating") subtitle:nil];
        PPServiceVoidBlock completion = ^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
                return;
            }
            [PPHUD showSuccess:kLang(@"Success_Title") subtitle:(shouldArchive ? kLang(@"Service_Archived_Success") : kLang(@"Service_Restored_Success"))];
            [weakSelf reloadService];
        };
        if (shouldArchive) {
            [[PPServiceManager sharedManager] archiveServiceID:weakSelf.service.serviceID auditNote:nil completion:completion];
        } else {
            [[PPServiceManager sharedManager] restoreServiceID:weakSelf.service.serviceID auditNote:nil completion:completion];
        }
    } cancelBlock:nil];
}

- (void)deleteTapped {
    __weak typeof(self) weakSelf = self;
    [PPAlertHelper showConfirmationIn:self
                              title:kLang(@"Service_Confirm_Delete_Title")
                           subtitle:kLang(@"Service_Confirm_Delete_Subtitle")
                        placeholder:nil
                      confirmButton:kLang(@"Delete")
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        [PPHUD showIndeterminateIn:weakSelf.view title:kLang(@"Deleting") subtitle:nil];
        [[PPServiceManager sharedManager] deleteServicePermanently:weakSelf.service.serviceID
                                                         auditNote:nil
                                                        completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Service_Deleted_Success")];
                [weakSelf.navigationController popViewControllerAnimated:YES];
            }
        }];
    } cancelBlock:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"detailCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"detailCell"];
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = AppForgroundColr;
        cell.contentView.layer.cornerRadius = 18.0;
        cell.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        cell.contentView.layer.masksToBounds = YES;
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    }

    NSDictionary *row = self.rows[indexPath.row];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:13]];
    cell.textLabel.textColor = SeconderyTextClr;
    cell.textLabel.textAlignment = [Language alignmentForCurrentLanguage];

    cell.detailTextLabel.text = row[@"value"];
    cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:15]];
    cell.detailTextLabel.textColor = PrimaryTextClr;
    cell.detailTextLabel.numberOfLines = [row[@"long"] boolValue] ? 0 : 2;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.detailTextLabel.textAlignment = [Language alignmentForCurrentLanguage];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.rows[indexPath.row];
    return [row[@"long"] boolValue] ? UITableViewAutomaticDimension : 74.0;
}

#pragma mark - Helpers

- (NSString *)formattedDate:(NSDate *)date {
    return date ? [self.dateFormatter stringFromDate:date] : kLang(@"Service_Value_NotSpecified");
}

- (UIColor *)currentStatusColor {
    if (self.service.isDeleted) return [UIColor ppTextSecondary];
    if (self.service.isBlocked) return [UIColor ppError];
    if (self.service.isDisabled) return [UIColor ppWarning];
    return [UIColor ppSuccess];
}

- (NSString *)prettyJSONString:(NSDictionary *)dictionary {
    NSDictionary *safe = PPSafeDict(dictionary);
    NSData *data = [NSJSONSerialization dataWithJSONObject:safe options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"—";
}

@end
