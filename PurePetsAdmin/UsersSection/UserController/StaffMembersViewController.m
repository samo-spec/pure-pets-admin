//
//  StaffMembersViewController.m
//  PurePetsAdmin
//

#import "StaffMembersViewController.h"
#import "PPHero.h"
#import "UserModel.h"
#import "FUManager.h"
#import "Styling.h"
#import "Language.h"
#import "AddUserViewController.h"
#import "AdminService.h"
#import "PPToast.h"
#import "AlertHelper.h"
@import Firebase;
@import FirebaseAuth;

static NSString * const PPStaffMemberCardCellID = @"PPStaffMemberCardCell";

static UIColor *PPStaffMembersSurfaceColor(void) {
    return AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
}

static UIColor *PPStaffMembersBackgroundColor(void) {
    return AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
}

static UIColor *PPStaffMembersPrimaryColor(void) {
    return AppPrimaryClr ?: UIColor.systemBlueColor;
}

static UIColor *PPStaffMembersPrimaryTextColor(void) {
    return PrimaryTextClr ?: UIColor.labelColor;
}

static UIColor *PPStaffMembersSecondaryTextColor(void) {
    return SeconderyTextClr ?: UIColor.secondaryLabelColor;
}

static UIColor *PPStaffMembersBorderColor(void) {
    return [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.08];
}

static NSString *PPStaffMembersStatusText(UserModel *user) {
    NSString *status = user.accountStatus ?: (user.isBlocked ? @"blocked" : @"active");
    if ([status isEqualToString:@"blocked"] || user.isBlocked) {
        return kLang(@"Blocked");
    }
    if ([status isEqualToString:@"disabled"]) {
        return kLang(@"Disabled");
    }
    if ([status isEqualToString:@"pending_review"]) {
        return kLang(@"Pending Review");
    }
    return kLang(@"Active");
}

static UIColor *PPStaffMembersStatusColor(UserModel *user) {
    NSString *status = user.accountStatus ?: (user.isBlocked ? @"blocked" : @"active");
    if ([status isEqualToString:@"blocked"] || user.isBlocked) {
        return UIColor.systemRedColor;
    }
    if ([status isEqualToString:@"disabled"]) {
        return UIColor.systemGrayColor;
    }
    if ([status isEqualToString:@"pending_review"]) {
        return UIColor.systemOrangeColor;
    }
    return UIColor.systemGreenColor;
}

static NSString *PPStaffMembersSafeString(NSString *value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

@interface PPStaffMemberTagLabel : UILabel
- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha;
@end

@implementation PPStaffMemberTagLabel

- (instancetype)init {
    if (self = [super init]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.font = [Styling fontMedium:12];
        self.textAlignment = NSTextAlignmentCenter;
        self.layer.cornerRadius = 13.0;
        self.layer.masksToBounds = YES;
        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:26.0],
            [self.widthAnchor constraintGreaterThanOrEqualToConstant:72.0]
        ]];
    }
    return self;
}

- (void)applyWithText:(NSString *)text tintColor:(UIColor *)tintColor fillAlpha:(CGFloat)fillAlpha {
    self.text = text;
    self.textColor = tintColor;
    self.backgroundColor = [tintColor colorWithAlphaComponent:fillAlpha];
    self.hidden = text.length == 0;
}

@end

@interface PPStaffMemberCardCell : UITableViewCell
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *avatarShellView;
@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIStackView *tagsStackView;
@property (nonatomic, strong) PPStaffMemberTagLabel *statusTagLabel;
@property (nonatomic, strong) PPStaffMemberTagLabel *adminTagLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, copy) NSString *representedUID;
- (void)configureWithUser:(UserModel *)user;
@end

@implementation PPStaffMemberCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _surfaceView = [[UIView alloc] init];
        _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
        _surfaceView.backgroundColor = PPStaffMembersSurfaceColor();
        _surfaceView.layer.cornerRadius = 28.0;
        _surfaceView.layer.borderWidth = 1.0;
        _surfaceView.layer.borderColor = PPStaffMembersBorderColor().CGColor;
        _surfaceView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1.0].CGColor;
        _surfaceView.layer.shadowOpacity = 0.08;
        _surfaceView.layer.shadowRadius = 18.0;
        _surfaceView.layer.shadowOffset = CGSizeMake(0, 10);

        _avatarShellView = [[UIView alloc] init];
        _avatarShellView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarShellView.backgroundColor = [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.12];
        _avatarShellView.layer.cornerRadius = 28.0;

        _avatarImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarImageView.tintColor = PPStaffMembersPrimaryColor();
        _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarImageView.layer.cornerRadius = 24.0;
        _avatarImageView.clipsToBounds = YES;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:18];
        _titleLabel.textColor = PPStaffMembersPrimaryTextColor();
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _titleLabel.numberOfLines = 1;

        UIImageSymbolConfiguration *verifiedConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        _verifiedBadgeView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.seal.fill" withConfiguration:verifiedConfig]];
        _verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
        _verifiedBadgeView.tintColor = UIColor.systemBlueColor;
        _verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;
        _verifiedBadgeView.hidden = YES;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:13];
        _subtitleLabel.textColor = PPStaffMembersSecondaryTextColor();
        _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _subtitleLabel.numberOfLines = 2;

        _statusTagLabel = [[PPStaffMemberTagLabel alloc] init];
        _adminTagLabel = [[PPStaffMemberTagLabel alloc] init];

        _tagsStackView = [[UIStackView alloc] initWithArrangedSubviews:@[_statusTagLabel, _adminTagLabel]];
        _tagsStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _tagsStackView.axis = UILayoutConstraintAxisHorizontal;
        _tagsStackView.alignment = UIStackViewAlignmentLeading;
        _tagsStackView.spacing = 8.0;

        UIImageSymbolConfiguration *chevronConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.forward" withConfiguration:chevronConfig]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.tintColor = [PPStaffMembersSecondaryTextColor() colorWithAlphaComponent:0.72];
        _chevronView.contentMode = UIViewContentModeScaleAspectFit;

        [self.contentView addSubview:_surfaceView];
        [_surfaceView addSubview:_avatarShellView];
        [_avatarShellView addSubview:_avatarImageView];
        [_surfaceView addSubview:_titleLabel];
        [_surfaceView addSubview:_verifiedBadgeView];
        [_surfaceView addSubview:_subtitleLabel];
        [_surfaceView addSubview:_tagsStackView];
        [_surfaceView addSubview:_chevronView];

        [NSLayoutConstraint activateConstraints:@[
            [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            [_avatarShellView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:18.0],
            [_avatarShellView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_avatarShellView.widthAnchor constraintEqualToConstant:56.0],
            [_avatarShellView.heightAnchor constraintEqualToConstant:56.0],

            [_avatarImageView.centerXAnchor constraintEqualToAnchor:_avatarShellView.centerXAnchor],
            [_avatarImageView.centerYAnchor constraintEqualToAnchor:_avatarShellView.centerYAnchor],
            [_avatarImageView.widthAnchor constraintEqualToConstant:48.0],
            [_avatarImageView.heightAnchor constraintEqualToConstant:48.0],

            [_chevronView.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-18.0],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_chevronView.widthAnchor constraintEqualToConstant:16.0],
            [_chevronView.heightAnchor constraintEqualToConstant:16.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:18.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_avatarShellView.trailingAnchor constant:14.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_verifiedBadgeView.leadingAnchor constant:-6.0],

            [_verifiedBadgeView.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_verifiedBadgeView.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-12.0],
            [_verifiedBadgeView.widthAnchor constraintEqualToConstant:16.0],
            [_verifiedBadgeView.heightAnchor constraintEqualToConstant:16.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-12.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],

            [_tagsStackView.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_tagsStackView.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:10.0],
            [_tagsStackView.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-12.0],
            [_tagsStackView.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-18.0]
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
    self.representedUID = nil;
    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.verifiedBadgeView.hidden = YES;
    self.adminTagLabel.hidden = YES;
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

- (void)configureWithUser:(UserModel *)user {
    self.representedUID = user.uid;

    NSString *displayName = PPStaffMembersSafeString(user.UserName);
    NSString *email = PPStaffMembersSafeString(user.UserEmail);
    NSString *phone = PPStaffMembersSafeString(user.MobileNo);

    self.titleLabel.text = displayName.length ? displayName : (email.length ? email : @"—");
    self.verifiedBadgeView.hidden = !user.isVerified;

    if (email.length && phone.length) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"%@  •  %@", email, phone];
    } else if (email.length) {
        self.subtitleLabel.text = email;
    } else if (phone.length) {
        self.subtitleLabel.text = phone;
    } else {
        self.subtitleLabel.text = user.uid.length ? user.uid : @"—";
    }

    UIColor *statusTint = PPStaffMembersStatusColor(user);
    [self.statusTagLabel applyWithText:PPStaffMembersStatusText(user) tintColor:statusTint fillAlpha:0.14];
    if (user.isAdmin || user.isSuperAdmin) {
        [self.adminTagLabel applyWithText:kLang(@"Role_Admin") tintColor:PPStaffMembersPrimaryColor() fillAlpha:0.12];
    } else {
        [self.adminTagLabel applyWithText:@"" tintColor:PPStaffMembersPrimaryColor() fillAlpha:0.12];
    }

    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    if (user.UserImageUrl.absoluteString.length > 0) {
        [self.avatarImageView setImageFromUrl:user.UserImageUrl.absoluteString Blr:NO Shimmering:YES];
    }
}

@end

@interface StaffMembersViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) id<FIRListenerRegistration> staffReg;
@property (nonatomic, strong) NSMutableArray<UserModel *> *allStaff;
@property (nonatomic, strong) NSMutableArray<UserModel *> *filteredStaff;
@property (nonatomic, copy) NSString *currentQuery;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, strong) UILabel *heroTotalLabel;
@property (nonatomic, strong) UIView *emptyStateView;
@property (nonatomic, assign) CGFloat headerWidth;
@property (nonatomic, strong) PPHero *heroGlassBG;
@property (nonatomic, strong) NSMutableSet<NSString *> *animatedStaffIDs;
@end

@implementation StaffMembersViewController

- (void)viewDidLoad {
    [super viewDidLoad];
   // self.title = kLang(@"StaffMembers_Title");
    self.view.backgroundColor = PPStaffMembersBackgroundColor();

    
    [self pp_configureTableView];
    [self setupHeaderUI];

    self.allStaff = [NSMutableArray array];
    self.filteredStaff = [NSMutableArray array];
    self.animatedStaffIDs = [NSMutableSet set];
    self.currentQuery = @"";

    __weak typeof(self) weakSelf = self;
    self.staffReg = [[FUManager shared] listenStaffUsersWithCompletion:^(NSArray<UserModel *> * _Nullable staff, NSError * _Nullable error) {
        if (error) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.allStaff = staff.mutableCopy ?: [NSMutableArray array];
            [weakSelf _applyFilterAndReload];
        });
    }];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if ([self pp_isEmbeddedInStaffManagement]) {
        [self pp_removeNavBar];
        return;
    }
    [self pp_configureNavigationBar];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroGlassBG startAnimations];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.heroGlassBG stopAnimations];
}

- (void)dealloc {
    [self.staffReg remove];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.heroGlassBG reapplyPalette];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (fabs(width - self.headerWidth) > 1.0) {
        self.headerWidth = width;
        NSString *currentText = self.currentQuery ?: @"";
        [self pp_installHeaderViewForWidth:width withText:currentText];
        [self pp_refreshHeroMetrics];
    }
}

- (void)pp_configureNavigationBar {
    UIButton *addButton = [self pp_ButtonWithSystemName:@"plus" action:@selector(didTapAddStaff)];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:addButton title:kLang(@"StaffMembers_Title") showBack:YES];
     
}

- (BOOL)pp_isEmbeddedInStaffManagement {
    return [self.parentViewController isKindOfClass:NSClassFromString(@"PPStaffManagementViewController")];
}

- (void)pp_configureTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = PPStaffMembersBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 118.0;
    self.tableView.contentInset = UIEdgeInsetsMake(8.0, 0.0, 34.0, 0.0);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 20)];
    [self.tableView registerClass:PPStaffMemberCardCell.class forCellReuseIdentifier:PPStaffMemberCardCellID];
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

    self.emptyStateView = [self pp_buildEmptyStateView];
    self.emptyStateView.hidden = YES;
    self.tableView.backgroundView = self.emptyStateView;
}

- (void)setupHeaderUI {
    [self pp_installHeaderViewForWidth:CGRectGetWidth(self.view.bounds) withText:self.currentQuery ?: @""];
}

- (void)pp_installHeaderViewForWidth:(CGFloat)width withText:(NSString *)text {
    CGFloat horizontalInset = width > 800.0 ? 28.0 : 18.0;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 228.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(horizontalInset, 8.0, width - (horizontalInset * 2.0), 208.0)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = UIColor.clearColor;
    card.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:card];

    PPHero *glassBG = [PPHero new];
    glassBG.frame = card.bounds;
    glassBG.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:glassBG];
    self.heroGlassBG = glassBG;

    UIView *countShell = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetWidth(card.bounds) - 94.0, 28.0, 72.0, 72.0)];
    countShell.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    countShell.backgroundColor = [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.1];
    countShell.layer.cornerRadius = 24.0;
    [card addSubview:countShell];

    self.heroCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 12.0, CGRectGetWidth(countShell.bounds), 28.0)];
    self.heroCountLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.heroCountLabel.font = [UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightBold];
    self.heroCountLabel.textColor = PPStaffMembersPrimaryTextColor();
    self.heroCountLabel.textAlignment = NSTextAlignmentCenter;
    self.heroCountLabel.text = @"0";
    [countShell addSubview:self.heroCountLabel];

    self.heroTotalLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 42.0, CGRectGetWidth(countShell.bounds), 18.0)];
    self.heroTotalLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.heroTotalLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    self.heroTotalLabel.textColor = [PPStaffMembersSecondaryTextColor() colorWithAlphaComponent:0.9];
    self.heroTotalLabel.textAlignment = NSTextAlignmentCenter;
    self.heroTotalLabel.text = @"/ 0";
    [countShell addSubview:self.heroTotalLabel];

    UIView *iconShell = [[UIView alloc] initWithFrame:CGRectMake(22.0, 32.0, 52.0, 52.0)];
    iconShell.backgroundColor = [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.12];
    iconShell.layer.cornerRadius = 18.0;
    [card addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.3.sequence.fill"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold]]];
    iconView.frame = CGRectMake(14.0, 14.0, 24.0, 24.0);
    iconView.tintColor = PPStaffMembersPrimaryColor();
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

    CGFloat textLeading = CGRectGetMaxX(iconShell.frame) + 16.0;
    CGFloat textTrailingPadding = 14.0;
    CGFloat textWidth = MAX(120.0, CGRectGetMinX(countShell.frame) - textLeading - textTrailingPadding);
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(textLeading, 34.0, textWidth, 32.0)];
    titleLabel.font = [Styling fontBold:24];
    titleLabel.textColor = PPStaffMembersPrimaryTextColor();
    titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    titleLabel.numberOfLines = 1;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.minimumScaleFactor = 0.78;
    titleLabel.text = kLang(@"StaffMembers_Title");
    [card addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(textLeading, CGRectGetMaxY(titleLabel.frame) + 10.0, textWidth, 40.0)];
    subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitleLabel.font = [Styling fontRegular:14];
    subtitleLabel.textColor = [PPStaffMembersSecondaryTextColor() colorWithAlphaComponent:0.9];
    subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.text = kLang(@"EditUsersRolePerms_List_Subtitle");
    [card addSubview:subtitleLabel];

    self.searchView = [[PPS alloc] initWithFrame:CGRectMake(18.0, CGRectGetHeight(card.bounds) - 70.0, CGRectGetWidth(card.bounds) - 36.0, 50.0)];
    self.searchView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.searchView.delegate = self;
    self.searchView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.searchView.textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.searchView.textField.textAlignment = Language.alignmentForCurrentLanguage;
    self.searchView.textField.placeholder = kLang(@"SetPermissions_Search_Placeholder");
    self.searchView.textField.text = text;
    self.searchView.cornerRadius = 22.0;
    self.searchView.layer.cornerRadius = 22.0;
    self.searchView.layer.borderWidth = 1.0;
    self.searchView.layer.borderColor = [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.12].CGColor;
    self.searchView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1.0].CGColor;
    self.searchView.layer.shadowOpacity = 0.06;
    self.searchView.layer.shadowRadius = 14.0;
    self.searchView.layer.shadowOffset = CGSizeMake(0, 8);
    [self pp_configureSearchAdornmentForView:self.searchView];
    [card addSubview:self.searchView];

    self.tableView.tableHeaderView = header;
}

- (void)pp_configureSearchAdornmentForView:(PPS *)searchView {
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    UIImage *iconImage = [UIImage systemImageNamed:@"magnifyingglass" withConfiguration:iconConfig];
    UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
    iconView.tintColor = [PPStaffMembersSecondaryTextColor() colorWithAlphaComponent:0.85];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(0, 0, 18.0, 18.0);

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28.0, 18.0)];
    iconView.center = CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds));
    [container addSubview:iconView];

    searchView.textField.leftView = nil;
    searchView.textField.rightView = nil;
    if ([Language isRTL]) {
        searchView.textField.rightView = container;
        searchView.textField.rightViewMode = UITextFieldViewModeAlways;
    } else {
        searchView.textField.leftView = container;
        searchView.textField.leftViewMode = UITextFieldViewModeAlways;
    }
}

- (UIView *)pp_buildEmptyStateView {
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.backgroundColor = UIColor.clearColor;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.clearColor;
    [container addSubview:card];

    UIView *iconShell = [[UIView alloc] init];
    iconShell.translatesAutoresizingMaskIntoConstraints = NO;
    iconShell.backgroundColor = [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.08];
    iconShell.layer.cornerRadius = 28.0;
    [card addSubview:iconShell];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.3.sequence.fill"
                                                                        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [PPStaffMembersPrimaryColor() colorWithAlphaComponent:0.9];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconShell addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [Styling fontBold:20];
    titleLabel.textColor = PPStaffMembersPrimaryTextColor();
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.text = kLang(@"NoUsersFound");
    [card addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [Styling fontRegular:14];
    subtitleLabel.textColor = [PPStaffMembersSecondaryTextColor() colorWithAlphaComponent:0.88];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.numberOfLines = 2;
    subtitleLabel.text = kLang(@"SetPermissionsSubtitle");
    [card addSubview:subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:28.0],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:24.0],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-24.0],

        [iconShell.topAnchor constraintEqualToAnchor:card.topAnchor],
        [iconShell.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [iconShell.widthAnchor constraintEqualToConstant:56.0],
        [iconShell.heightAnchor constraintEqualToConstant:56.0],

        [iconView.centerXAnchor constraintEqualToAnchor:iconShell.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:iconShell.centerYAnchor],

        [titleLabel.topAnchor constraintEqualToAnchor:iconShell.bottomAnchor constant:18.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];

    return container;
}

- (void)didTapAddStaff {
    AddUserViewController *vc = [AddUserViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Search

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.currentQuery = text ?: @"";
    [self _applyFilterAndReload];
}

- (void)searchViewDidSubmit:(PPS *)view {
    [view unfocus];
}

- (void)_applyFilterAndReload {
    NSString *query = self.currentQuery ?: @"";
    if (query.length == 0) {
        self.filteredStaff = self.allStaff.mutableCopy ?: [NSMutableArray array];
    } else {
        NSString *needle = query.lowercaseString;
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(UserModel *user, __unused NSDictionary *bindings) {
            NSString *name = PPStaffMembersSafeString(user.UserName).lowercaseString;
            NSString *email = PPStaffMembersSafeString(user.UserEmail).lowercaseString;
            NSString *uid = PPStaffMembersSafeString(user.uid).lowercaseString;
            NSString *phone = PPStaffMembersSafeString(user.MobileNo).lowercaseString;
            return [name containsString:needle] ||
                   [email containsString:needle] ||
                   [uid containsString:needle] ||
                   [phone containsString:needle];
        }];
        self.filteredStaff = [[self.allStaff filteredArrayUsingPredicate:predicate] mutableCopy] ?: [NSMutableArray array];
    }

    [self pp_refreshHeroMetrics];
    [self pp_updateEmptyStateVisibility];
    [self.tableView reloadData];
}

- (void)pp_refreshHeroMetrics {
    self.heroCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.filteredStaff.count];
    self.heroTotalLabel.text = [NSString stringWithFormat:@"/ %lu", (unsigned long)self.allStaff.count];
}

- (void)pp_updateEmptyStateVisibility {
    self.emptyStateView.hidden = (self.filteredStaff.count > 0);
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredStaff.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 12.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 12.0)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPStaffMemberCardCell *cell = [tableView dequeueReusableCellWithIdentifier:PPStaffMemberCardCellID forIndexPath:indexPath];
    [cell configureWithUser:self.filteredStaff[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    UserModel *user = self.filteredStaff[indexPath.row];
    AddUserViewController *vc = [[AddUserViewController alloc] initWithStaffMember:user];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.filteredStaff.count || UIAccessibilityIsReduceMotionEnabled()) return;

    UserModel *user = self.filteredStaff[indexPath.row];
    NSString *identifier = user.uid.length ? user.uid : [NSString stringWithFormat:@"%ld", (long)indexPath.row];
    if ([self.animatedStaffIDs containsObject:identifier]) return;
    [self.animatedStaffIDs addObject:identifier];

    cell.contentView.alpha = 0.0;
    cell.contentView.transform = CGAffineTransformMakeTranslation(0.0, 12.0);
    NSTimeInterval delay = MIN(indexPath.row, 8) * 0.025;
    [UIView animateWithDuration:0.32
                          delay:delay
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        cell.contentView.alpha = 1.0;
        cell.contentView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Swipe Actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UserModel *user = self.filteredStaff[indexPath.row];

    UIContextualAction *disableAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:kLang(@"Service_Action_Block") handler:^(__unused UIContextualAction * _Nonnull action, __unused __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self pp_confirmDisableStaff:user completion:completionHandler];
    }];
    disableAction.backgroundColor = UIColor.systemOrangeColor;
    disableAction.image = [UIImage systemImageNamed:@"person.slash"];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[disableAction]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

- (void)pp_confirmDisableStaff:(UserModel *)user completion:(void(^)(BOOL handled))completion {
    if ([[FIRAuth auth].currentUser.uid isEqualToString:user.uid]) {
        [PPToast toast:kLang(@"StatusNoAccess")];
        if (completion) completion(NO);
        return;
    }

    NSString *displayName = PPStaffMembersSafeString(user.UserName);
    NSString *subtitle = [NSString stringWithFormat:@"%@ %@", kLang(@"Disable"), displayName.length ? displayName : PPStaffMembersSafeString(user.UserEmail)];
    [AlertHelper showConfirmationIn:self title:kLang(@"Confirm") subtitle:subtitle placeholder:nil confirmButton:kLang(@"Confirm") cancelButton:kLang(@"Cancel") icon:nil confirmBlock:^{
        [AdminService disableStaffMember:user.uid completion:^(NSDictionary * _Nullable result, NSError * _Nullable error) {
            if (error) [PPToast toast:error.localizedDescription];
            else [PPToast toast:kLang(@"Success")];
            if (completion) completion(error == nil);
        }];
    } cancelBlock:^{
        if (completion) completion(NO);
    }];
}

@end
