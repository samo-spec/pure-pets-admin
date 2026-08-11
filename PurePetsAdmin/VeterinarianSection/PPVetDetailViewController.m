//
//  PPVetDetailViewController.m
//  PurePetsAdmin
//

#import "PPVetDetailViewController.h"
#import "PPVetModel.h"
#import "PPVetManager.h"
#import "PPAddEditVetViewController.h"
#import "PPVetSubscriptionViewController.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

@interface PPVetDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) PPVetModel *vet;
@property (nonatomic, strong) UIImageView *headerImageView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) UIView *actionBar;
@end

@implementation PPVetDetailViewController

- (instancetype)initWithVet:(PPVetModel *)vet {
    self = [super init];
    if (self) {
        _vet = vet;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppForgroundColr;

    [self buildRows];
    [self setupHeaderImage];
    [self setupTableView];
    [self setupActionBar];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIButton *editBtn = [self pp_ButtonWithSystemName:@"pencil" action:@selector(editTapped)];
    [self pp_navBarWithOtherButton:editBtn title:self.vet.title ?: kLang(@"Vet_Detail_Title")];
}

#pragma mark - Data

- (void)buildRows {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateStyle = NSDateFormatterMediumStyle;
    df.timeStyle = NSDateFormatterNoStyle;

    NSMutableArray *r = [NSMutableArray array];

    [r addObject:@{@"label": kLang(@"Vet_Field_Name"),          @"value": self.vet.title ?: @"—"}];
    [r addObject:@{@"label": kLang(@"Vet_Field_Type"),          @"value": [self.vet localizedTypeName]}];
    [r addObject:@{@"label": kLang(@"Vet_Field_Phone"),         @"value": self.vet.phone ?: @"—"}];
    [r addObject:@{@"label": kLang(@"Vet_Field_Whatsapp"),      @"value": self.vet.whatsapp ?: @"—"}];
    [r addObject:@{@"label": kLang(@"Vet_Field_Description"),   @"value": self.vet.descriptionText ?: @"—"}];
    [r addObject:@{@"label": kLang(@"Vet_Field_Cost"),          @"value": [NSString stringWithFormat:@"%.2f %@", self.vet.vetCost, kLang(@"QAR")]}];
    [r addObject:@{@"label": kLang(@"Vet_Field_AvailableDate"), @"value": self.vet.availableDate ? [df stringFromDate:self.vet.availableDate] : @"—"}];
    [r addObject:@{@"label": kLang(@"Vet_Field_Status"),        @"value": self.vet.isDisabled ? kLang(@"Vet_Status_Disabled") : kLang(@"Vet_Status_Active")}];
    [r addObject:@{@"label": kLang(@"Vet_Subscription"),        @"value": [self.vet localizedSubscriptionTierName]}];

    if (self.vet.subscriptionEndDate) {
        NSString *expiry = [df stringFromDate:self.vet.subscriptionEndDate];
        BOOL expired = [self.vet isSubscriptionExpired];
        NSString *expiryLabel = expired ? [NSString stringWithFormat:@"%@ (%@)", expiry, kLang(@"Vet_Sub_Expired")] : expiry;
        [r addObject:@{@"label": kLang(@"Vet_Sub_EndDate"), @"value": expiryLabel}];
    }

    if (self.vet.createdAt) {
        [r addObject:@{@"label": kLang(@"Vet_Field_CreatedAt"), @"value": [df stringFromDate:self.vet.createdAt]}];
    }

    self.rows = [r copy];
}

#pragma mark - UI

- (void)setupHeaderImage {
    CGFloat imgH = 200.0;
    _headerImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, imgH)];
    _headerImageView.contentMode = UIViewContentModeScaleAspectFill;
    _headerImageView.clipsToBounds = YES;
    _headerImageView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.06];

    if (self.vet.logoURL.length > 0) {
        [_headerImageView setImageFromUrl:self.vet.logoURL
                         placeholderImage:@"veterinary"
                                      Blr:YES
                               Shimmering:YES
                               completion:nil];
    } else {
        _headerImageView.image = [UIImage systemImageNamed:@"stethoscope.circle.fill"];
        _headerImageView.tintColor = AppPrimaryClr;
        _headerImageView.contentMode = UIViewContentModeCenter;
    }

    // Rounded bottom corners
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, self.view.bounds.size.width, imgH)
                                                   byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                                         cornerRadii:CGSizeMake(24, 24)];
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = maskPath.CGPath;
    _headerImageView.layer.mask = mask;
}

- (void)setupTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorInset = UIEdgeInsetsMake(0, 16, 0, 16);
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 52;
    _tableView.tableHeaderView = _headerImageView;
    _tableView.showsVerticalScrollIndicator = NO;

    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-70],
    ]];
}

- (void)setupActionBar {
    CGFloat barH = 60;
    _actionBar = [[UIView alloc] init];
    _actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    _actionBar.backgroundColor = AppForgroundColr;

    [self.view addSubview:_actionBar];
    [NSLayoutConstraint activateConstraints:@[
        [_actionBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_actionBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_actionBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [_actionBar.heightAnchor constraintEqualToConstant:barH],
    ]];

    // Action buttons
    NSArray *icons    = @[@"phone.fill", @"message.fill", @"square.and.pencil", @"creditcard.circle"];
    NSArray *actions  = @[@"callTapped", @"whatsappTapped", @"editTapped", @"subscriptionTapped"];
    NSArray *colors   = @[[UIColor ppSuccess], [UIColor ppQuickActionServices], [UIColor ppInfo], [UIColor ppPrimary]];

    CGFloat btnSize = 44;
    CGFloat spacing = 24;
    CGFloat totalW = (btnSize * icons.count) + (spacing * (icons.count - 1));
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = spacing;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSUInteger i = 0; i < icons.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [btn setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];
        btn.tintColor = UIColor.whiteColor;
        btn.backgroundColor = colors[i];
        btn.layer.cornerRadius = btnSize / 2.0;
        btn.clipsToBounds = YES;
        [btn addTarget:self action:NSSelectorFromString(actions[i]) forControlEvents:UIControlEventTouchUpInside];
        [NSLayoutConstraint activateConstraints:@[
            [btn.widthAnchor constraintEqualToConstant:btnSize],
            [btn.heightAnchor constraintEqualToConstant:btnSize],
        ]];
        [stack addArrangedSubview:btn];
    }

    [_actionBar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:_actionBar.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:_actionBar.centerYAnchor],
    ]];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"detail"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"detail"];
    }
    NSDictionary *row = self.rows[indexPath.row];
    cell.textLabel.text = row[@"label"];
    cell.textLabel.font = [Styling fontMedium:14];
    cell.textLabel.textColor = SeconderyTextClr;
    cell.textLabel.textAlignment = Language.alignmentForCurrentLanguage;

    cell.detailTextLabel.text = row[@"value"];
    cell.detailTextLabel.font = [Styling fontBold:14];
    cell.detailTextLabel.textColor = PrimaryTextClr;
    cell.detailTextLabel.textAlignment = Language.isRTL ? NSTextAlignmentLeft : NSTextAlignmentRight;
    cell.detailTextLabel.numberOfLines = 0;

    cell.backgroundColor = AppForgroundColr;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - Actions

- (void)editTapped {
    [PPFunc pp_playTapEffect];
    PPAddEditVetViewController *vc = [[PPAddEditVetViewController alloc] initWithVet:self.vet];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)subscriptionTapped {
    [PPFunc pp_playTapEffect];
    PPVetSubscriptionViewController *vc = [[PPVetSubscriptionViewController alloc] initWithVet:self.vet];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)callTapped {
    NSString *phone = [self.vet.phone stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (phone.length == 0) {
        [PPHUD showError:kLang(@"Error") subtitle:kLang(@"Vet_No_Phone")];
        return;
    }
    NSURL *url = [NSURL URLWithString:[@"tel://" stringByAppendingString:phone]];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)whatsappTapped {
    NSString *wa = [self.vet.whatsapp stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (wa.length == 0) wa = [self.vet.phone stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (wa.length == 0) {
        [PPHUD showError:kLang(@"Error") subtitle:kLang(@"Vet_No_Phone")];
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://wa.me/%@", wa]];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
