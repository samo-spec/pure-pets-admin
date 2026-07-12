//
//  StaffRolesViewController.m
//  PurePetsAdmin
//

#import "StaffRolesViewController.h"
#import "RPManager.h"
#import "Styling.h"
#import "Language.h"
#import "StaffRoleEditorViewController.h"
#import "AlertHelper.h"
#import "PPToast.h"
#import "PPStaffAuth.h"

static NSString * const PPStaffRoleCardCellID = @"PPStaffRoleCardCell";

static UIColor *PPStaffRolesSurfaceColor(void) {
    return AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
}

static UIColor *PPStaffRolesBackgroundColor(void) {
    return AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
}

static UIColor *PPStaffRolesPrimaryColor(void) {
    return AppPrimaryClr ?: UIColor.systemBlueColor;
}

static UIColor *PPStaffRolesPrimaryTextColor(void) {
    return PrimaryTextClr ?: UIColor.labelColor;
}

static UIColor *PPStaffRolesSecondaryTextColor(void) {
    return SeconderyTextClr ?: UIColor.secondaryLabelColor;
}

static UIColor *PPStaffRolesBorderColor(void) {
    return [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.08];
}

static NSString *PPStaffRolesLocalizedDictionaryValue(NSDictionary *localizedValue) {
    if (![localizedValue isKindOfClass:NSDictionary.class]) return @"";
    NSString *rtlValue = [localizedValue[@"ar"] isKindOfClass:NSString.class] ? localizedValue[@"ar"] : @"";
    NSString *ltrValue = [localizedValue[@"en"] isKindOfClass:NSString.class] ? localizedValue[@"en"] : @"";
    return [Language isRTL] ? (rtlValue.length ? rtlValue : ltrValue) : (ltrValue.length ? ltrValue : rtlValue);
}

@interface PPStaffRoleCardCell : UITableViewCell
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *iconShellView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIImageView *trailingImageView;
@property (nonatomic, strong) NSLayoutConstraint *subtitleTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *subtitleBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleBottomConstraint;
- (void)configureWithTitle:(NSString *)title
                  subtitle:(nullable NSString *)subtitle
                     badge:(nullable NSString *)badge
                  iconName:(NSString *)iconName
                 tintColor:(UIColor *)tintColor
           showsDisclosure:(BOOL)showsDisclosure;
@end

@implementation PPStaffRoleCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _surfaceView = [[UIView alloc] init];
        _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
        _surfaceView.backgroundColor = PPStaffRolesSurfaceColor();
        _surfaceView.layer.cornerRadius = 26.0;
        _surfaceView.layer.borderWidth = 1.0;
        _surfaceView.layer.borderColor = PPStaffRolesBorderColor().CGColor;
        _surfaceView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1.0].CGColor;
        _surfaceView.layer.shadowOpacity = 0.08;
        _surfaceView.layer.shadowRadius = 18.0;
        _surfaceView.layer.shadowOffset = CGSizeMake(0, 10);

        _iconShellView = [[UIView alloc] init];
        _iconShellView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconShellView.layer.cornerRadius = 22.0;
        _iconShellView.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.12];

        UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
        _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.lefthalf.filled" withConfiguration:iconConfig]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.tintColor = PPStaffRolesPrimaryColor();
        _iconView.contentMode = UIViewContentModeScaleAspectFit;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:18];
        _titleLabel.textColor = PPStaffRolesPrimaryTextColor();
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _titleLabel.numberOfLines = 1;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:13];
        _subtitleLabel.textColor = PPStaffRolesSecondaryTextColor();
        _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _subtitleLabel.numberOfLines = 2;

        _badgeLabel = [[UILabel alloc] init];
        _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _badgeLabel.font = [Styling fontMedium:12];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.textColor = PPStaffRolesPrimaryColor();
        _badgeLabel.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.11];
        _badgeLabel.layer.cornerRadius = 13.0;
        _badgeLabel.layer.masksToBounds = YES;

        UIImageSymbolConfiguration *chevronConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
        _trailingImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:chevronConfig]];
        _trailingImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _trailingImageView.tintColor = [PPStaffRolesSecondaryTextColor() colorWithAlphaComponent:0.72];
        _trailingImageView.contentMode = UIViewContentModeScaleAspectFit;

        [self.contentView addSubview:_surfaceView];
        [_surfaceView addSubview:_iconShellView];
        [_iconShellView addSubview:_iconView];
        [_surfaceView addSubview:_titleLabel];
        [_surfaceView addSubview:_subtitleLabel];
        [_surfaceView addSubview:_badgeLabel];
        [_surfaceView addSubview:_trailingImageView];

        _subtitleTopConstraint = [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0];
        _subtitleBottomConstraint = [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-18.0];
        _titleBottomConstraint = [_titleLabel.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-22.0];

        [NSLayoutConstraint activateConstraints:@[
            [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            [_iconShellView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:18.0],
            [_iconShellView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_iconShellView.widthAnchor constraintEqualToConstant:44.0],
            [_iconShellView.heightAnchor constraintEqualToConstant:44.0],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconShellView.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconShellView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:18.0],
            [_iconView.heightAnchor constraintEqualToConstant:18.0],

            [_trailingImageView.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-18.0],
            [_trailingImageView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_trailingImageView.widthAnchor constraintEqualToConstant:16.0],
            [_trailingImageView.heightAnchor constraintEqualToConstant:16.0],

            [_badgeLabel.trailingAnchor constraintEqualToAnchor:_trailingImageView.leadingAnchor constant:-12.0],
            [_badgeLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:18.0],
            [_badgeLabel.heightAnchor constraintEqualToConstant:26.0],
            [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:86.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:18.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconShellView.trailingAnchor constant:14.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_badgeLabel.leadingAnchor constant:-12.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_trailingImageView.leadingAnchor constant:-12.0],
            _subtitleTopConstraint,
            _subtitleBottomConstraint,
            _titleBottomConstraint
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.surfaceView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.surfaceView.bounds cornerRadius:self.surfaceView.layer.cornerRadius].CGPath;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.subtitleLabel.hidden = NO;
    self.badgeLabel.hidden = NO;
    self.trailingImageView.hidden = NO;
    self.surfaceView.transform = CGAffineTransformIdentity;
    self.surfaceView.alpha = 1.0;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [self pp_updateInteractionStateHighlighted:highlighted];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [self pp_updateInteractionStateHighlighted:selected];
}

- (void)pp_updateInteractionStateHighlighted:(BOOL)highlighted {
    CGFloat scale = highlighted ? 0.985 : 1.0;
    CGFloat alpha = highlighted ? 0.96 : 1.0;
    [UIView animateWithDuration:0.18 animations:^{
        self.surfaceView.transform = CGAffineTransformMakeScale(scale, scale);
        self.surfaceView.alpha = alpha;
    }];
}

- (void)configureWithTitle:(NSString *)title
                  subtitle:(nullable NSString *)subtitle
                     badge:(nullable NSString *)badge
                  iconName:(NSString *)iconName
                 tintColor:(UIColor *)tintColor
           showsDisclosure:(BOOL)showsDisclosure
{
    UIColor *resolvedTint = tintColor ?: PPStaffRolesPrimaryColor();
    self.titleLabel.text = title.length ? title : @"—";
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.hidden = subtitle.length == 0;
    self.badgeLabel.text = badge;
    self.badgeLabel.hidden = badge.length == 0;
    self.trailingImageView.hidden = !showsDisclosure;

    self.iconShellView.backgroundColor = [resolvedTint colorWithAlphaComponent:0.12];
    self.badgeLabel.backgroundColor = [resolvedTint colorWithAlphaComponent:0.12];
    self.badgeLabel.textColor = resolvedTint;
    self.iconView.tintColor = resolvedTint;
    self.iconView.image = [UIImage systemImageNamed:iconName ?: @"shield.lefthalf.filled"
                                   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]];

    self.titleBottomConstraint.active = (subtitle.length == 0);
    self.subtitleTopConstraint.active = (subtitle.length > 0);
    self.subtitleBottomConstraint.active = (subtitle.length > 0);
}

@end

@interface StaffRolesViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<StaffRoleTemplate *> *customRoles;
@property (nonatomic, strong) NSArray<NSDictionary *> *systemRoles;
@property (nonatomic, strong) UILabel *builtInCountLabel;
@property (nonatomic, strong) UILabel *customCountLabel;
@property (nonatomic, assign) CGFloat headerWidth;
@end

@implementation StaffRolesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
  //  self.title = kLang(@"StaffRoles_Title");
    self.view.backgroundColor = PPStaffRolesBackgroundColor();
    self.customRoles = @[];

   
    [self pp_configureTableView];
    [self setupData];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self pp_configureNavigationBar];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (fabs(width - self.headerWidth) > 1.0) {
        self.headerWidth = width;
        self.tableView.tableHeaderView = [self pp_buildTableHeaderViewWithWidth:width];
        [self pp_refreshHeaderMetrics];
    }
}

- (void)pp_configureNavigationBar {
    UIButton *addButton = [self pp_ButtonWithSystemName:@"plus" action:@selector(didTapAddRole)];
    [self pp_navBarWithOtherButton:addButton title:kLang(@"StaffRoles_Title")];
}

- (void)pp_configureTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = PPStaffRolesBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 104.0;
    self.tableView.contentInset = UIEdgeInsetsMake(8.0, 0.0, 34.0, 0.0);
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 18)];
    [self.tableView registerClass:PPStaffRoleCardCell.class forCellReuseIdentifier:PPStaffRoleCardCellID];
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }

    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (UIView *)pp_buildTableHeaderViewWithWidth:(CGFloat)width {
    CGFloat horizontalInset = width > 800.0 ? 28.0 : 18.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 194.0)];
    header.backgroundColor = UIColor.clearColor;

    UIView *card = [[UIView alloc] initWithFrame:CGRectInset(header.bounds, horizontalInset, 8.0)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.backgroundColor = PPStaffRolesSurfaceColor();
    card.layer.cornerRadius = 30.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = PPStaffRolesBorderColor().CGColor;
    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1.0].CGColor;
    card.layer.shadowOpacity = 0.08;
    card.layer.shadowRadius = 24.0;
    card.layer.shadowOffset = CGSizeMake(0, 14);
    card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:card.bounds cornerRadius:30.0].CGPath;
    [header addSubview:card];

    UIView *halo = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetWidth(card.bounds) - 130.0, -24.0, 120.0, 120.0)];
    halo.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    halo.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.09];
    halo.layer.cornerRadius = 60.0;
    [card addSubview:halo];

    UIView *iconShell = [[UIView alloc] initWithFrame:CGRectMake(22.0, 24.0, 52.0, 52.0)];
    iconShell.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.12];
    iconShell.layer.cornerRadius = 18.0;
    [card addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.rectangle.stack.fill"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]];
    iconView.tintColor = PPStaffRolesPrimaryColor();
    iconView.frame = CGRectMake(15.0, 15.0, 22.0, 22.0);
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(iconShell.frame) + 14.0, 26.0, CGRectGetWidth(card.bounds) - CGRectGetMaxX(iconShell.frame) - 118.0, 28.0)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.text = kLang(@"StaffRoles_Title");
    titleLabel.font = [Styling fontBold:24];
    titleLabel.textColor = PPStaffRolesPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [card addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(titleLabel.frame.origin.x, CGRectGetMaxY(titleLabel.frame) + 8.0, CGRectGetWidth(card.bounds) - titleLabel.frame.origin.x - 22.0, 42.0)];
    subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitleLabel.text = kLang(@"StaffRoles_Subtitle");
    subtitleLabel.font = [Styling fontRegular:14];
    subtitleLabel.textColor = [PPStaffRolesSecondaryTextColor() colorWithAlphaComponent:0.9];
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.numberOfLines = 2;
    [card addSubview:subtitleLabel];

    UIStackView *statsStack = [[UIStackView alloc] initWithFrame:CGRectMake(22.0, CGRectGetHeight(card.bounds) - 62.0, CGRectGetWidth(card.bounds) - 44.0, 40.0)];
    statsStack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    statsStack.axis = UILayoutConstraintAxisHorizontal;
    statsStack.alignment = UIStackViewAlignmentFill;
    statsStack.distribution = UIStackViewDistributionFillEqually;
    statsStack.spacing = 12.0;
    [card addSubview:statsStack];

    [statsStack addArrangedSubview:[self pp_buildStatCardWithTitle:kLang(@"BuiltInRoles") countLabel:&_builtInCountLabel]];
    [statsStack addArrangedSubview:[self pp_buildStatCardWithTitle:kLang(@"CustomRoles") countLabel:&_customCountLabel]];

    return header;
}

- (UIView *)pp_buildStatCardWithTitle:(NSString *)title countLabel:(UILabel * __strong *)countLabel {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.07];
    card.layer.cornerRadius = 18.0;

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:20 weight:UIFontWeightBold];
    valueLabel.textColor = PPStaffRolesPrimaryTextColor();
    valueLabel.textAlignment = Language.alignmentForCurrentLanguage;
    valueLabel.text = @"0";
    [card addSubview:valueLabel];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontMedium:12];
    titleLabel.textColor = [PPStaffRolesSecondaryTextColor() colorWithAlphaComponent:0.92];
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.text = title;
    [card addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [valueLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [valueLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:8.0],
        [valueLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:valueLabel.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:valueLabel.trailingAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8.0]
    ]];

    if (countLabel) {
        *countLabel = valueLabel;
    }
    return card;
}

- (void)setupData {
    self.systemRoles = @[
        @{@"key": PPStaffRoleSuperAdmin, @"name": [PPStaffAuth localizedRoleName:PPStaffRoleSuperAdmin]},
        @{@"key": PPStaffRoleOwner, @"name": [PPStaffAuth localizedRoleName:PPStaffRoleOwner]},
        @{@"key": PPStaffRoleOperationsManager, @"name": [PPStaffAuth localizedRoleName:PPStaffRoleOperationsManager]},
        @{@"key": PPStaffRoleInventoryManager, @"name": [PPStaffAuth localizedRoleName:PPStaffRoleInventoryManager]},
        @{@"key": PPStaffRolePaymentsManager, @"name": [PPStaffAuth localizedRoleName:PPStaffRolePaymentsManager]},
        @{@"key": PPStaffRoleSupportAgent, @"name": [PPStaffAuth localizedRoleName:PPStaffRoleSupportAgent]},
        @{@"key": PPStaffRoleViewer, @"name": [PPStaffAuth localizedRoleName:PPStaffRoleViewer]}
    ];
    [self pp_refreshHeaderMetrics];

    __weak typeof(self) weakSelf = self;
    [[RPManager shared] listenStaffRoles:^(NSArray<StaffRoleTemplate *> * _Nullable roles, NSError * _Nullable error) {
        if (error || !roles) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.customRoles = roles;
            [weakSelf pp_refreshHeaderMetrics];
            [weakSelf.tableView reloadData];
        });
    }];
}

- (void)pp_refreshHeaderMetrics {
    self.builtInCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.systemRoles.count];
    self.customCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.customRoles.count];
}

- (void)didTapAddRole {
    StaffRoleEditorViewController *vc = [[StaffRoleEditorViewController alloc] initWithRole:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0) ? self.systemRoles.count : self.customRoles.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 52.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 52.0)];
    container.backgroundColor = UIColor.clearColor;

    CGFloat inset = CGRectGetWidth(tableView.bounds) > 800.0 ? 28.0 : 18.0;
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(inset, 18.0, CGRectGetWidth(container.bounds) - (inset * 2.0) - 66.0, 24.0)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.font = [Styling fontBold:18];
    titleLabel.textColor = PPStaffRolesPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.text = (section == 0) ? kLang(@"BuiltInRoles") : kLang(@"CustomRoles");
    [container addSubview:titleLabel];

    UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetWidth(container.bounds) - inset - 52.0, 14.0, 52.0, 30.0)];
    countLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    countLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    countLabel.textAlignment = NSTextAlignmentCenter;
    countLabel.textColor = PPStaffRolesPrimaryColor();
    countLabel.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.09];
    countLabel.layer.cornerRadius = 15.0;
    countLabel.layer.masksToBounds = YES;
    countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)((section == 0) ? self.systemRoles.count : self.customRoles.count)];
    [container addSubview:countLabel];

    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 1 && self.customRoles.count == 0) {
        return 152.0;
    }
    return section == 0 ? 8.0 : 20.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != 1 || self.customRoles.count > 0) {
        return [[UIView alloc] initWithFrame:CGRectZero];
    }

    CGFloat inset = CGRectGetWidth(tableView.bounds) > 800.0 ? 28.0 : 18.0;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 152.0)];
    container.backgroundColor = UIColor.clearColor;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(inset, 14.0, CGRectGetWidth(container.bounds) - (inset * 2.0), 122.0)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = PPStaffRolesSurfaceColor();
    card.layer.cornerRadius = 26.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = PPStaffRolesBorderColor().CGColor;
    [container addSubview:card];

    UIView *iconShell = [[UIView alloc] initWithFrame:CGRectMake(18.0, 22.0, 42.0, 42.0)];
    iconShell.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.12];
    iconShell.layer.cornerRadius = 16.0;
    [card addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"sparkles"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]]];
    iconView.tintColor = PPStaffRolesPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(12.0, 12.0, 18.0, 18.0);
    [iconShell addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(iconShell.frame) + 12.0, 22.0, CGRectGetWidth(card.bounds) - CGRectGetMaxX(iconShell.frame) - 120.0, 24.0)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.font = [Styling fontBold:18];
    titleLabel.textColor = PPStaffRolesPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.text = kLang(@"NewRole");
    [card addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(titleLabel.frame.origin.x, CGRectGetMaxY(titleLabel.frame) + 6.0, CGRectGetWidth(card.bounds) - titleLabel.frame.origin.x - 18.0, 36.0)];
    subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitleLabel.font = [Styling fontRegular:13];
    subtitleLabel.textColor = [PPStaffRolesSecondaryTextColor() colorWithAlphaComponent:0.88];
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.text = kLang(@"StaffRoles_Subtitle");
    [card addSubview:subtitleLabel];

    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeSystem];
    addButton.frame = CGRectMake(18.0, CGRectGetHeight(card.bounds) - 46.0, 120.0, 32.0);
    addButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    addButton.backgroundColor = [PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.11];
    addButton.layer.cornerRadius = 16.0;
    addButton.tintColor = PPStaffRolesPrimaryColor();
    addButton.titleLabel.font = [Styling fontMedium:14];
    addButton.semanticContentAttribute = [Language isRTL] ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.title = kLang(@"NewRole");
        configuration.image = [UIImage systemImageNamed:@"plus"];
        configuration.imagePadding = 6.0;
        configuration.baseForegroundColor = PPStaffRolesPrimaryColor();
        addButton.configuration = configuration;
    } else {
        [addButton setTitle:kLang(@"NewRole") forState:UIControlStateNormal];
        [addButton setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    }
    [addButton addTarget:self action:@selector(didTapAddRole) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:addButton];

    return container;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPStaffRoleCardCell *cell = [tableView dequeueReusableCellWithIdentifier:PPStaffRoleCardCellID forIndexPath:indexPath];

    if (indexPath.section == 0) {
        NSDictionary *systemRole = self.systemRoles[indexPath.row];
        [cell configureWithTitle:systemRole[@"name"]
                        subtitle:nil
                           badge:kLang(@"SystemRole")
                        iconName:@"lock.shield.fill"
                       tintColor:[PPStaffRolesPrimaryColor() colorWithAlphaComponent:0.9]
                 showsDisclosure:NO];
    } else {
        StaffRoleTemplate *role = self.customRoles[indexPath.row];
        NSString *title = PPStaffRolesLocalizedDictionaryValue(role.name);
        NSString *subtitle = PPStaffRolesLocalizedDictionaryValue(role.roleDescription);
        NSString *badge = [NSString stringWithFormat:@"%lu %@", (unsigned long)role.permissions.count, kLang(@"Permissions")];
        [cell configureWithTitle:title
                        subtitle:subtitle.length ? subtitle : badge
                           badge:badge
                        iconName:@"slider.horizontal.3"
                       tintColor:PPStaffRolesPrimaryColor()
                 showsDisclosure:YES];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;

    StaffRoleTemplate *role = self.customRoles[indexPath.row];
    StaffRoleEditorViewController *vc = [[StaffRoleEditorViewController alloc] initWithRole:role];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return nil;

    StaffRoleTemplate *role = self.customRoles[indexPath.row];
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:kLang(@"Delete") handler:^(__unused UIContextualAction * _Nonnull action, __unused __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [AlertHelper showConfirmationIn:self title:kLang(@"Confirm") subtitle:kLang(@"confirmDeleteRole") placeholder:nil confirmButton:kLang(@"Delete") cancelButton:kLang(@"Cancel") icon:nil confirmBlock:^{
            [[RPManager shared] deleteStaffRole:role.id completion:^(NSError * _Nullable error) {
                if (error) [PPToast toast:error.localizedDescription];
                completionHandler(error == nil);
            }];
        } cancelBlock:^{
            completionHandler(NO);
        }];
    }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];
    deleteAction.backgroundColor = UIColor.systemRedColor;

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

@end
