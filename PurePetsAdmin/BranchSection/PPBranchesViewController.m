//
//  PPBranchesViewController.m
//  PurePetsAdmin
//
//  Branch list — Apple Design Award–caliber UIKit experience.
//  Preserves all business logic, Firestore listeners, permissions, swipe
//  actions, search, and agent-count accounting from the previous version.
//

#import "PPBranchesViewController.h"
#import "PPBranchEditorViewController.h"
#import "PPHero.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;

#pragma mark - Font Helpers (Dynamic Type)

static UIFont *PPBranchScaled(UIFont *base, UIFontTextStyle style) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
    }
    return base;
}
static UIFont *PPBranchMedium(CGFloat size, UIFontTextStyle style) {
    return PPBranchScaled(PPFontMedium(size), style);
}
static UIFont *PPBranchRegular(CGFloat size, UIFontTextStyle style) {
    return PPBranchScaled(PPFontRegular(size), style);
}
static UIFont *PPBranchBold(CGFloat size, UIFontTextStyle style) {
    return PPBranchScaled(PPFontBold(size), style);
}

#pragma mark - State

typedef NS_ENUM(NSInteger, PPBranchesState) {
    PPBranchesStateLoading = 0,
    PPBranchesStateReady,
    PPBranchesStateEmpty,
    PPBranchesStateNoResults,
    PPBranchesStateError,
};

#pragma mark - PPBranchHeroView

@interface PPBranchHeroView : UIView
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UIImageView *glyphView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *countPill;
@property (nonatomic, strong) UILabel *countLabel;
- (void)configureWithTotal:(NSInteger)total active:(NSInteger)active;
@end

@implementation PPBranchHeroView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _heroBackground = [PPHero new];
        _heroBackground.translatesAutoresizingMaskIntoConstraints = NO;
        _heroBackground.accentStyle = PPHeroGlassAccentStyleCornerGlow;
        _heroBackground.cornerGlowOpacityMultiplier = 0.72;
        _heroBackground.accentColorOverride = [UIColor ppPrimary];
        [self addSubview:_heroBackground];
        [self sendSubviewToBack:_heroBackground];
        [NSLayoutConstraint activateConstraints:@[
            [_heroBackground.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_heroBackground.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_heroBackground.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_heroBackground.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];

        _glyphView = [[UIImageView alloc] init];
        _glyphView.contentMode = UIViewContentModeScaleAspectFit;
        _glyphView.tintColor = [UIColor ppPrimary];
        _glyphView.layer.cornerRadius = PPCornerMedium;
        _glyphView.layer.masksToBounds = YES;
        _glyphView.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.11];
        _glyphView.image = [UIImage pp_symbolNamed:@"building.2"
                                          pointSize:26
                                             weight:UIImageSymbolWeightSemibold
                                              scale:UIImageSymbolScaleMedium
                                          palette:@[[UIColor ppPrimary]]
                                      makeTemplate:YES];
        _glyphView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glyphView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = PPBranchBold(PPFontTitle2, UIFontTextStyleTitle2);
        _titleLabel.textColor = [UIColor ppTextPrimary];
        _titleLabel.numberOfLines = 1;
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = PPBranchRegular(PPFontSubheadline, UIFontTextStyleSubheadline);
        _subtitleLabel.textColor = [UIColor ppTextSecondary];
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_subtitleLabel];

        _countPill = [[UIView alloc] init];
        _countPill.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
        _countPill.layer.cornerRadius = PPCornerPill;
        _countPill.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_countPill];

        _countLabel = [[UILabel alloc] init];
        _countLabel.font = PPBranchMedium(PPFontFootnote, UIFontTextStyleFootnote);
        _countLabel.textColor = [UIColor ppPrimary];
        _countLabel.numberOfLines = 1;
        _countLabel.adjustsFontForContentSizeCategory = YES;
        _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_countPill addSubview:_countLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_glyphView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:PPSpaceLG],
            [_glyphView.topAnchor constraintEqualToAnchor:self.topAnchor constant:PPSpaceLG],
            [_glyphView.widthAnchor constraintEqualToConstant:PPSpace4XL],
            [_glyphView.heightAnchor constraintEqualToConstant:PPSpace4XL],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_glyphView.trailingAnchor constant:PPSpaceMD],
            [_titleLabel.topAnchor constraintEqualToAnchor:_glyphView.topAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:PPSpaceXS],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-PPSpaceLG],

            [_countPill.leadingAnchor constraintEqualToAnchor:_glyphView.leadingAnchor],
            [_countPill.topAnchor constraintEqualToAnchor:_glyphView.bottomAnchor constant:PPSpaceMD],
            [_countPill.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-PPSpaceLG],

            [_countLabel.leadingAnchor constraintEqualToAnchor:_countPill.leadingAnchor constant:PPSpaceMD],
            [_countLabel.trailingAnchor constraintEqualToAnchor:_countPill.trailingAnchor constant:-PPSpaceMD],
            [_countLabel.topAnchor constraintEqualToAnchor:_countPill.topAnchor constant:PPSpaceXS],
            [_countLabel.bottomAnchor constraintEqualToAnchor:_countPill.bottomAnchor constant:-PPSpaceXS],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
}

- (void)configureWithTotal:(NSInteger)total active:(NSInteger)active {
    NSString *count = [NSString stringWithFormat:kLang(@"Branches_Count_Format"), (long)total, (long)active];
    self.countLabel.text = count;
    [self.countPill setNeedsLayout];
    [self.countPill layoutIfNeeded];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
}

@end

#pragma mark - PPBranchCell

@interface PPBranchCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconTile;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *defaultBadge;
@property (nonatomic, strong) UIView *statusDot;
- (void)configureWithBranch:(PPBranchModel *)branch agentCount:(NSInteger)agentCount canManage:(BOOL)canManage;
@end

@implementation PPBranchCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = [UIColor ppElevatedSurface];
        _cardView.layer.cornerRadius = PPCornerCard;
        _cardView.layer.cornerCurve = kCACornerCurveContinuous;
        _cardView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _cardView.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.72].CGColor;
        _cardView.layer.shadowColor = [UIColor ppShadow].CGColor;
        _cardView.layer.shadowOpacity = 0.045;
        _cardView.layer.shadowOffset = CGSizeMake(0, 7);
        _cardView.layer.shadowRadius = 16;
        [self.contentView addSubview:_cardView];
        [_cardView.heightAnchor constraintGreaterThanOrEqualToConstant:82.0].active = YES;

        _iconTile = [[UIView alloc] init];
        _iconTile.layer.cornerRadius = PPCornerMedium;
        _iconTile.layer.masksToBounds = YES;
        _iconTile.layer.cornerCurve = kCACornerCurveContinuous;
        _iconTile.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_iconTile];

        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeCenter;
        _iconView.tintColor = [UIColor whiteColor];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [_iconTile addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.font = PPBranchMedium(PPFontHeadline, UIFontTextStyleHeadline);
        _nameLabel.textColor = [UIColor ppTextPrimary];
        _nameLabel.numberOfLines = 1;
        _nameLabel.adjustsFontForContentSizeCategory = YES;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_nameLabel];

        _codeLabel = [[UILabel alloc] init];
        _codeLabel.font = PPBranchRegular(PPFontSubheadline, UIFontTextStyleSubheadline);
        _codeLabel.textColor = [UIColor ppTextSecondary];
        _codeLabel.numberOfLines = 1;
        _codeLabel.adjustsFontForContentSizeCategory = YES;
        _codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_codeLabel];

        _metaLabel = [[UILabel alloc] init];
        _metaLabel.font = PPBranchRegular(PPFontCaption1, UIFontTextStyleCaption1);
        _metaLabel.textColor = [UIColor ppTextTertiary];
        _metaLabel.numberOfLines = 1;
        _metaLabel.adjustsFontForContentSizeCategory = YES;
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_metaLabel];

        _defaultBadge = [[UILabel alloc] init];
        _defaultBadge.font = PPBranchMedium(PPFontCaption2, UIFontTextStyleCaption2);
        _defaultBadge.textColor = [UIColor whiteColor];
        _defaultBadge.textAlignment = NSTextAlignmentCenter;
        _defaultBadge.backgroundColor = AppPrimaryClr;
        _defaultBadge.layer.cornerRadius = PPSpaceXS + 2;
        _defaultBadge.layer.masksToBounds = YES;
        _defaultBadge.text = kLang(@"Branches_Default");
        _defaultBadge.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_defaultBadge];

        _statusDot = [[UIView alloc] init];
        _statusDot.layer.cornerRadius = PPSpaceXS;
        _statusDot.layer.masksToBounds = YES;
        _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_statusDot];

        UIView *selectedBg = [[UIView alloc] init];
        selectedBg.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.10];
        selectedBg.layer.cornerRadius = PPCornerSmall;
        selectedBg.layer.masksToBounds = YES;
        self.selectedBackgroundView = selectedBg;

        _cardView.layoutMargins = UIEdgeInsetsMake(12.0, 14.0, 12.0, 14.0);
        UILayoutGuide *guide = _cardView.layoutMarginsGuide;

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],

            [_iconTile.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [_iconTile.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_iconTile.widthAnchor constraintEqualToConstant:PPSpace4XL],
            [_iconTile.heightAnchor constraintEqualToConstant:PPSpace4XL],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconTile.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconTile.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:PPSpaceXL],
            [_iconView.heightAnchor constraintEqualToConstant:PPSpaceXL],

            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconTile.trailingAnchor constant:PPSpaceMD],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_defaultBadge.leadingAnchor constant:-PPSpaceSM],
            [_nameLabel.topAnchor constraintEqualToAnchor:_iconTile.topAnchor],

            [_codeLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_codeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_defaultBadge.leadingAnchor constant:-PPSpaceSM],
            [_codeLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:PPSpaceXXS],

            [_metaLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_metaLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_defaultBadge.leadingAnchor constant:-PPSpaceSM],
            [_metaLabel.topAnchor constraintEqualToAnchor:_codeLabel.bottomAnchor constant:PPSpaceXXS],
            [_metaLabel.bottomAnchor constraintEqualToAnchor:_iconTile.bottomAnchor],

            [_defaultBadge.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [_defaultBadge.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_defaultBadge.heightAnchor constraintEqualToConstant:PPSpaceLG + 2],

            [_statusDot.topAnchor constraintEqualToAnchor:_defaultBadge.topAnchor],
            [_statusDot.trailingAnchor constraintEqualToAnchor:_defaultBadge.leadingAnchor constant:-PPSpaceXS],
            [_statusDot.widthAnchor constraintEqualToConstant:PPSpaceXS * 2],
            [_statusDot.heightAnchor constraintEqualToConstant:PPSpaceXS * 2],
        ]];

        [_defaultBadge setContentCompressionResistancePriority:UILayoutPriorityRequired
                                               forAxis:UILayoutConstraintAxisHorizontal];
        [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                          forAxis:UILayoutConstraintAxisHorizontal];
    }
    return self;
}

- (void)configureWithBranch:(PPBranchModel *)branch agentCount:(NSInteger)agentCount canManage:(BOOL)canManage {
    self.nameLabel.text = [branch localizedName];
    self.nameLabel.textColor = branch.isActive ? [UIColor ppTextPrimary] : [UIColor ppTextTertiary];

    self.codeLabel.text = branch.code;

    UIColor *baseColor = branch.isActive ? [UIColor ppPrimary] : [UIColor ppTextTertiary];
    self.iconTile.backgroundColor = baseColor;
    self.iconView.image = [UIImage pp_symbolNamed:(branch.isDefault ? @"building.columns" : @"building.2")
                                          pointSize:PPSpaceLG
                                             weight:UIImageSymbolWeightMedium
                                              scale:UIImageSymbolScaleMedium
                                            palette:@[[UIColor whiteColor]]
                                      makeTemplate:YES];

    NSString *stockName = [branch localizedStockModeName];
    NSString *agentsWord = kLang(agentCount == 1 ? @"Branches_Agent_Count" : @"Branches_Agent_Count_Plural");
    self.metaLabel.text = [NSString stringWithFormat:@"%@ · %ld %@", stockName, (long)agentCount, agentsWord];
    self.metaLabel.textColor = branch.isActive ? [UIColor ppTextTertiary] : [[UIColor ppTextTertiary] colorWithAlphaComponent:0.72];

    self.defaultBadge.hidden = !branch.isDefault;
    self.statusDot.hidden = !branch.isDefault;
    self.statusDot.backgroundColor = branch.isActive ? [UIColor ppSuccess] : [UIColor ppTextTertiary];

    self.accessoryType = canManage ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    self.nameLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.codeLabel.textAlignment = Language.alignmentForCurrentLanguage;
    self.metaLabel.textAlignment = Language.alignmentForCurrentLanguage;

    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", self.nameLabel.text, self.codeLabel.text];
    self.accessibilityValue = [NSString stringWithFormat:@"%@, %ld %@%@",
                              stockName, (long)agentCount, agentsWord,
                              branch.isDefault ? [NSString stringWithFormat:@", %@", kLang(@"Branches_Default")] : @""];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.iconTile.transform = highlighted ? CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown) : CGAffineTransformIdentity;
        return;
    }
    [UIView animateWithDuration:PPAnimDurationFast delay:0
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.iconTile.transform = highlighted ? CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown)
                                            : CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - PPBranchesViewController

static NSString *const kBranchCellID = @"PPBranchCell";

@interface PPBranchesViewController ()
@property (nonatomic, strong) NSArray<PPBranchModel *> *branches;
@property (nonatomic, strong) NSArray<PPBranchModel *> *filteredBranches;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) PPBranchesState state;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) id branchesListener;
@property (nonatomic, strong) id agentsListener;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *agentCounts;

@property (nonatomic, strong) PPBranchHeroView *heroView;
@property (nonatomic, strong) UIView *stateView;
@property (nonatomic, strong) UIView *loadingView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIView *noResultsView;
@property (nonatomic, strong) UIView *errorView;
@end

@implementation PPBranchesViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];

    [self evaluatePermissions];
    [self setupNavigation];
    [self setupTableView];
    [self setupHero];
    [self setupStateViews];
    [self startListening];
}

#pragma mark - Setup

- (void)setupNavigation {
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.title = kLang(@"Branches_Title");
    if (self.canManage) {
        UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                  target:self
                                                                                  action:@selector(didTapAdd)];
        addButton.accessibilityLabel = kLang(@"Branches_New");
        self.navigationItem.rightBarButtonItem = addButton;
    }
}

- (void)setupTableView {
    [self.tableView registerClass:[PPBranchCell class] forCellReuseIdentifier:kBranchCellID];
    self.tableView.backgroundColor = [UIColor ppBackground];
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL + PPSpaceLG;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.accessibilityIdentifier = @"BranchesTable";

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = kLang(@"Branches_Search");
    self.searchController.searchBar.tintColor = AppPrimaryClr;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 24.0, 0.0);
}

- (void)setupHero {
    self.heroView = [[PPBranchHeroView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 184)];
    self.heroView.titleLabel.text = kLang(@"Branches_Title");
    self.heroView.subtitleLabel.text = kLang(@"Branches_Subtitle");
    self.tableView.tableHeaderView = self.heroView;
    [self updateHero];
}

- (void)setupStateViews {
    self.stateView = [[UIView alloc] init];
    self.stateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateView.hidden = YES;
    [self.view addSubview:self.stateView];

    [NSLayoutConstraint activateConstraints:@[
        [self.stateView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.stateView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.stateView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stateView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self buildLoadingView];
    [self buildEmptyView];
    [self buildNoResultsView];
    [self buildErrorView];
}

- (void)buildLoadingView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = AppPrimaryClr;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [container addSubview:spinner];

    UILabel *label = [[UILabel alloc] init];
    label.font = PPBranchMedium(PPFontSubheadline, UIFontTextStyleSubheadline);
    label.textColor = [UIColor ppTextSecondary];
    label.text = kLang(@"Branches_Loading");
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontForContentSizeCategory = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [spinner.topAnchor constraintEqualToAnchor:container.topAnchor],
        [spinner.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:PPSpaceMD],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    self.loadingView = container;
}

- (void)buildEmptyView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"building.2" tint:[AppPrimaryClr colorWithAlphaComponent:0.16] glyphTint:AppPrimaryClr];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"Branches_Empty_Title");
    [container addSubview:title];

    UILabel *subtitle = [self stateSubtitleLabel];
    subtitle.text = kLang(@"Branches_Empty_Subtitle");
    [container addSubview:subtitle];

    UIButton *cta = [UIButton buttonWithType:UIButtonTypeSystem];
    cta.translatesAutoresizingMaskIntoConstraints = NO;
    cta.backgroundColor = AppPrimaryClr;
    cta.tintColor = [UIColor whiteColor];
    cta.titleLabel.font = PPBranchMedium(PPFontHeadline, UIFontTextStyleHeadline);
    [cta setTitle:kLang(@"Branches_Empty_CTA") forState:UIControlStateNormal];
    cta.layer.cornerRadius = PPCornerMedium;
    cta.layer.masksToBounds = YES;
    cta.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceXL, PPSpaceMD, PPSpaceXL);
    [cta addTarget:self action:@selector(didTapAdd) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:cta];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceXS],
        [subtitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [cta.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:PPSpaceLG],
        [cta.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [cta.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    self.emptyView = container;
}

- (void)buildNoResultsView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"magnifyingglass" tint:[[UIColor ppTextTertiary] colorWithAlphaComponent:0.16] glyphTint:[UIColor ppTextTertiary]];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"Branches_NoResults_Title");
    [container addSubview:title];

    UILabel *subtitle = [self stateSubtitleLabel];
    subtitle.text = kLang(@"Branches_NoResults_Subtitle");
    [container addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceXS],
        [subtitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    self.noResultsView = container;
}

- (void)buildErrorView {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stateView addSubview:container];
    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:self.stateView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:self.stateView.centerYAnchor],
        [container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.stateView.leadingAnchor constant:PPSpaceXL],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:self.stateView.trailingAnchor constant:-PPSpaceXL],
    ]];

    UIView *icon = [self stateGlyphWithName:@"exclamationmark.triangle" tint:[[UIColor ppError] colorWithAlphaComponent:0.14] glyphTint:[UIColor ppError]];
    [container addSubview:icon];

    UILabel *title = [self stateTitleLabel];
    title.text = kLang(@"Branches_Error_Title");
    [container addSubview:title];

    UILabel *subtitle = [self stateSubtitleLabel];
    subtitle.text = kLang(@"Branches_Error_Subtitle");
    [container addSubview:subtitle];

    UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
    retry.translatesAutoresizingMaskIntoConstraints = NO;
    retry.backgroundColor = AppPrimaryClr;
    retry.tintColor = [UIColor whiteColor];
    retry.titleLabel.font = PPBranchMedium(PPFontHeadline, UIFontTextStyleHeadline);
    [retry setTitle:kLang(@"Branches_Retry") forState:UIControlStateNormal];
    retry.layer.cornerRadius = PPCornerMedium;
    retry.layer.masksToBounds = YES;
    retry.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceXL, PPSpaceMD, PPSpaceXL);
    [retry addTarget:self action:@selector(didTapRetry) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:retry];

    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],
        [icon.heightAnchor constraintEqualToConstant:PPSpace4XL + PPSpaceXL],

        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:PPSpaceLG],
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:PPSpaceXS],
        [subtitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],

        [retry.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:PPSpaceLG],
        [retry.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [retry.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    self.errorView = container;
}

- (UIView *)stateGlyphWithName:(NSString *)name tint:(UIColor *)tint glyphTint:(UIColor *)glyphTint {
    UIView *circle = [[UIView alloc] init];
    circle.translatesAutoresizingMaskIntoConstraints = NO;
    circle.backgroundColor = tint;
    circle.layer.cornerRadius = (PPSpace4XL + PPSpaceXL) / 2.0;
    circle.layer.masksToBounds = YES;

    UIImageView *iv = [[UIImageView alloc] init];
    iv.contentMode = UIViewContentModeCenter;
    iv.tintColor = glyphTint;
    iv.image = [UIImage pp_symbolNamed:name
                              pointSize:34
                                 weight:UIImageSymbolWeightSemibold
                                  scale:UIImageSymbolScaleMedium
                                palette:@[glyphTint]
                          makeTemplate:YES];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [circle addSubview:iv];

    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:40],
        [iv.heightAnchor constraintEqualToConstant:40],
    ]];
    return circle;
}

- (UILabel *)stateTitleLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = PPBranchBold(PPFontTitle3, UIFontTextStyleTitle3);
    label.textColor = [UIColor ppTextPrimary];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontForContentSizeCategory = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UILabel *)stateSubtitleLabel {
    UILabel *label = [[UILabel alloc] init];
    label.font = PPBranchRegular(PPFontSubheadline, UIFontTextStyleSubheadline);
    label.textColor = [UIColor ppTextSecondary];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontForContentSizeCategory = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

#pragma mark - Permissions

- (void)evaluatePermissions {
    BOOL hasView = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermBranchesView];
    BOOL hasManage = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermBranchesManage];
    self.canManage = hasManage;
    if (!hasView && !hasManage) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - Listeners

- (void)startListening {
    self.state = PPBranchesStateLoading;
    [self refreshStateVisibility];

    PPweakify(self);
    FIRQuery *query = [[[FIRFirestore firestore] collectionWithPath:kPPBranchesCol]
                        queryOrderedByField:@"createdAt" descending:YES];
    self.branchesListener = [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        PPstrongify(self);
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
            self.state = PPBranchesStateError;
            [self refreshStateVisibility];
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPBranchModel *branch = [PPBranchModel fromDictionary:doc.data withID:doc.documentID];
            if (branch) [items addObject:branch];
        }
        self.branches = items.copy;
        [self applyFilter];
    }];
    [self startAgentCountListener];
}

- (void)startAgentCountListener {
    PPweakify(self);
    self.agentsListener = [[[FIRFirestore firestore] collectionWithPath:@"agents"]
      addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) return;
        NSMutableDictionary *counts = [NSMutableDictionary dictionary];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            NSDictionary *data = doc.data;
            if ([data[@"isActive"] boolValue] && [data[@"branchId"] isKindOfClass:NSString.class]) {
                NSString *bid = (NSString *)data[@"branchId"];
                counts[bid] = @([counts[bid] integerValue] + 1);
            }
        }
        self.agentCounts = counts.copy;
        if (self.state == PPBranchesStateReady || self.state == PPBranchesStateNoResults) {
            [self.tableView reloadData];
        }
    }];
}

- (void)didTapRetry {
    [self.branchesListener remove]; self.branchesListener = nil;
    [self.agentsListener remove]; self.agentsListener = nil;
    [self startListening];
}

#pragma mark - Filtering

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text;
    if (query.length == 0) {
        self.filteredBranches = self.branches;
    } else {
        NSString *q = query.lowercaseString;
        NSMutableArray *filtered = [NSMutableArray array];
        for (PPBranchModel *b in self.branches) {
            if ([b.nameEn.lowercaseString containsString:q] ||
                [b.nameAr containsString:q] ||
                [b.code.lowercaseString containsString:q] ||
                [b.address.lowercaseString containsString:q]) {
                [filtered addObject:b];
            }
        }
        self.filteredBranches = filtered.copy;
    }
    [self updateHero];

    if (self.branches.count == 0) {
        self.state = PPBranchesStateEmpty;
    } else if (self.filteredBranches.count == 0) {
        self.state = PPBranchesStateNoResults;
    } else {
        self.state = PPBranchesStateReady;
    }
    [self refreshStateVisibility];
    [self.tableView reloadData];
}

- (void)updateHero {
    NSInteger total = self.filteredBranches.count;
    NSInteger active = 0;
    for (PPBranchModel *b in self.filteredBranches) {
        if (b.isActive) active++;
    }
    [self.heroView configureWithTotal:total active:active];
}

- (void)refreshStateVisibility {
    BOOL ready = (self.state == PPBranchesStateReady);
    self.tableView.hidden = !ready;
    self.stateView.hidden = ready;
    self.loadingView.hidden = (self.state != PPBranchesStateLoading);
    self.emptyView.hidden = (self.state != PPBranchesStateEmpty);
    self.noResultsView.hidden = (self.state != PPBranchesStateNoResults);
    self.errorView.hidden = (self.state != PPBranchesStateError);
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredBranches.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPBranchCell *cell = [tableView dequeueReusableCellWithIdentifier:kBranchCellID forIndexPath:indexPath];
    PPBranchModel *branch = self.filteredBranches[indexPath.row];
    NSInteger agentCount = [self.agentCounts[branch.branchID] integerValue];
    [cell configureWithBranch:branch agentCount:agentCount canManage:self.canManage];
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.canManage;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPBranchModel *branch = self.filteredBranches[indexPath.row];
    if (!self.canManage || branch.isDefault) return nil;

    UIContextualAction *toggleAction = [UIContextualAction contextualActionWithStyle:branch.isActive ? UIContextualActionStyleDestructive : UIContextualActionStyleNormal
                                                                               title:branch.isActive ? kLang(@"Branches_Deactivate") : kLang(@"Branches_Activate")
                                                                             handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [self toggleActive:branch];
        completionHandler(YES);
    }];
    toggleAction.backgroundColor = branch.isActive ? [UIColor ppError] : [UIColor ppSuccess];
    toggleAction.accessibilityLabel = branch.isActive ? kLang(@"Branches_Deactivate") : kLang(@"Branches_Activate");
    return [UISwipeActionsConfiguration configurationWithActions:@[toggleAction]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.canManage) return;
    PPBranchModel *branch = self.filteredBranches[indexPath.row];
    PPBranchEditorViewController *editor = [[PPBranchEditorViewController alloc] initWithBranch:branch];
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - Actions

- (void)didTapAdd {
    PPBranchEditorViewController *editor = [[PPBranchEditorViewController alloc] initWithBranch:nil];
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)toggleActive:(PPBranchModel *)branch {
    if (branch.isActive) {
        NSInteger count = [self.agentCounts[branch.branchID] integerValue];
        if (count > 0) {
            [PPHUD showError:[NSString stringWithFormat:kLang(@"Branches_Cannot_Deactivate_Agents"), (long)count]];
            return;
        }
    }

    BOOL newActive = !branch.isActive;
    [[[[FIRFirestore firestore] collectionWithPath:kPPBranchesCol] documentWithPath:branch.branchID]
     updateData:@{
        @"isActive": @(newActive),
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
    } completion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:newActive ? kLang(@"Branches_Activated") : kLang(@"Branches_Deactivated")];
            [self writeToggleAuditLog:branch newActive:newActive];
        }
    }];
}

- (void)writeToggleAuditLog:(PPBranchModel *)branch newActive:(BOOL)newActive {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
     setData:@{
        @"action": @"toggle_branch_active",
        @"targetCollection": kPPBranchesCol,
        @"targetId": branch.branchID ?: @"",
        @"adminUid": uid,
        @"before": @{@"isActive": @(!newActive)},
        @"after": @{@"isActive": @(newActive)},
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter];
}

#pragma mark - Entrance Animation

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [self.heroView.heroBackground startAnimations];
    }
    [self runEntranceIfNeeded];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.heroView.heroBackground stopAnimations];
}

- (void)runEntranceIfNeeded {
    if (self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;

    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.heroView.alpha = 1.0;
        self.heroView.transform = CGAffineTransformIdentity;
        for (UITableViewCell *cell in self.tableView.visibleCells) {
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        }
        return;
    }

    self.heroView.alpha = 0;
    self.heroView.transform = CGAffineTransformMakeTranslation(0, 16);

    [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.heroView.alpha = 1;
        self.heroView.transform = CGAffineTransformIdentity;
    } completion:nil];

    [self.tableView.visibleCells enumerateObjectsUsingBlock:^(UITableViewCell *cell, NSUInteger idx, BOOL *stop) {
        cell.alpha = 0;
        cell.transform = CGAffineTransformMakeTranslation(0, 12);
        [UIView animateWithDuration:0.36 delay:0.06 + idx * 0.045 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.heroView) {
        CGFloat width = self.tableView.bounds.size.width;
        CGSize size = [self.heroView systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                    withHorizontalFittingPriority:UILayoutPriorityRequired
                                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        if (fabs(self.heroView.frame.size.height - size.height) > 0.5) {
            self.heroView.frame = CGRectMake(0, 0, width, size.height);
            self.tableView.tableHeaderView = self.heroView;
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self.tableView reloadData];
}

#pragma mark - Cleanup

- (void)dealloc {
    [self.branchesListener remove];
    [self.agentsListener remove];
}

@end
