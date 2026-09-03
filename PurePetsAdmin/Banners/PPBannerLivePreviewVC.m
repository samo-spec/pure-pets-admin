//
//  PPBannerLivePreviewVC.m
//  PurePetsAdmin
//
//  Live In-Situ Consumer App Simulation & Preview Modal
//

#import "PPBannerLivePreviewVC.h"
#import "PPDesignTokens.h"
#import "Language.h"
#import "Styling.h"
#import "PPImageManager.h"

@interface PPBannerLivePreviewVC ()

@property (nonatomic, strong) PPBannerViewModel *banner;
@property (nonatomic, strong) MainBannerModel *group;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *simulatedDeviceCard;
@property (nonatomic, strong) UIImageView *bannerBackgroundImageView;
@property (nonatomic, strong) CAGradientLayer *bannerGradientLayer;
@property (nonatomic, strong) UIImageView *bannerSampleImageView;
@property (nonatomic, strong) UIImageView *bannerBadgeImageView;
@property (nonatomic, strong) UILabel *bannerTitleLabel;
@property (nonatomic, strong) UILabel *bannerDescLabel;
@property (nonatomic, strong) UILabel *bannerDateLabel;

@end

@implementation PPBannerLivePreviewVC

- (instancetype)initWithBanner:(PPBannerViewModel *)banner
                         group:(MainBannerModel *)group {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _banner = banner;
        _group = group;
        self.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self setupHeaderAndControls];
    [self setupSimulatedPhoneFeed];
    [self populateBannerData];
}

- (void)setupHeaderAndControls {
    // Drag Indicator
    UIView *handle = [[UIView alloc] init];
    handle.translatesAutoresizingMaskIntoConstraints = NO;
    handle.backgroundColor = [[UIColor ppTextSecondary] colorWithAlphaComponent:0.35];
    handle.layer.cornerRadius = 2.5;
    [self.view addSubview:handle];

    // Header Stack: Title + Subtitle
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:18]];
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.text = kLang(@"Banners_Sim_Title");
    titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [self.view addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[Styling fontRegular:12]];
    subtitleLabel.textColor = [UIColor ppTextSecondary];
    subtitleLabel.text = kLang(@"Banners_Sim_Subtitle");
    subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [self.view addSubview:subtitleLabel];

    // Close Button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor ppTextSecondary];
    [closeButton addTarget:self action:@selector(onCloseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeButton];

    // Bottom Action Bar: Test Tap + Edit
    UIView *bottomBar = [[UIView alloc] init];
    bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    bottomBar.backgroundColor = [UIColor ppElevatedSurface];
    bottomBar.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.75].CGColor;
    bottomBar.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    [self.view addSubview:bottomBar];

    UIButton *testActionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    testActionButton.translatesAutoresizingMaskIntoConstraints = NO;
    testActionButton.backgroundColor = [UIColor ppPrimary];
    testActionButton.tintColor = UIColor.whiteColor;
    testActionButton.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontBold:15]];
    testActionButton.layer.cornerRadius = 20.0;
    if (@available(iOS 13.0, *)) {
        testActionButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [testActionButton setImage:[UIImage systemImageNamed:@"play.circle.fill"] forState:UIControlStateNormal];
    [testActionButton setTitle:[NSString stringWithFormat:@"  %@", kLang(@"Banners_Sim_TestTap")] forState:UIControlStateNormal];
    [testActionButton addTarget:self action:@selector(onTestTapTapped) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:testActionButton];

    UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    editButton.translatesAutoresizingMaskIntoConstraints = NO;
    editButton.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.45];
    editButton.tintColor = [UIColor ppTextPrimary];
    editButton.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontBold:14]];
    editButton.layer.cornerRadius = 20.0;
    if (@available(iOS 13.0, *)) {
        editButton.layer.cornerCurve = kCACornerCurveContinuous;
    }
    [editButton setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
    [editButton setTitle:[NSString stringWithFormat:@"  %@", kLang(@"Banners_Action_Edit")] forState:UIControlStateNormal];
    [editButton addTarget:self action:@selector(onEditTapped) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:editButton];

    // Scroll View for Simulated Phone
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [handle.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10.0],
        [handle.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [handle.widthAnchor constraintEqualToConstant:38.0],
        [handle.heightAnchor constraintEqualToConstant:5.0],

        [closeButton.topAnchor constraintEqualToAnchor:handle.bottomAnchor constant:12.0],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [closeButton.widthAnchor constraintEqualToConstant:32.0],
        [closeButton.heightAnchor constraintEqualToConstant:32.0],

        [titleLabel.topAnchor constraintEqualToAnchor:handle.bottomAnchor constant:12.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeButton.leadingAnchor constant:-12.0],

        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bottomBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [bottomBar.heightAnchor constraintEqualToConstant:70.0],

        [testActionButton.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor constant:16.0],
        [testActionButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [testActionButton.heightAnchor constraintEqualToConstant:44.0],

        [editButton.leadingAnchor constraintEqualToAnchor:testActionButton.trailingAnchor constant:12.0],
        [editButton.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor constant:-16.0],
        [editButton.centerYAnchor constraintEqualToAnchor:bottomBar.centerYAnchor],
        [editButton.widthAnchor constraintEqualToConstant:105.0],
        [editButton.heightAnchor constraintEqualToConstant:44.0],

        [_scrollView.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:14.0],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor],
    ]];
}

- (void)setupSimulatedPhoneFeed {
    // Simulated Phone Device Card
    _simulatedDeviceCard = [[UIView alloc] init];
    _simulatedDeviceCard.translatesAutoresizingMaskIntoConstraints = NO;
    _simulatedDeviceCard.backgroundColor = [UIColor ppBackground];
    _simulatedDeviceCard.layer.cornerRadius = 28.0;
    if (@available(iOS 13.0, *)) {
        _simulatedDeviceCard.layer.cornerCurve = kCACornerCurveContinuous;
    }
    _simulatedDeviceCard.layer.borderWidth = 2.5;
    _simulatedDeviceCard.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.9].CGColor;
    _simulatedDeviceCard.layer.shadowColor = [UIColor ppShadow].CGColor;
    _simulatedDeviceCard.layer.shadowOffset = CGSizeMake(0, 10);
    _simulatedDeviceCard.layer.shadowRadius = 24;
    _simulatedDeviceCard.layer.shadowOpacity = 0.08;
    _simulatedDeviceCard.clipsToBounds = YES;
    [_scrollView addSubview:_simulatedDeviceCard];

    // Mock Status Bar / Notch
    UIView *mockStatusBar = [[UIView alloc] init];
    mockStatusBar.translatesAutoresizingMaskIntoConstraints = NO;
    mockStatusBar.backgroundColor = UIColor.clearColor;
    [_simulatedDeviceCard addSubview:mockStatusBar];

    UIView *notch = [[UIView alloc] init];
    notch.translatesAutoresizingMaskIntoConstraints = NO;
    notch.backgroundColor = UIColor.blackColor;
    notch.layer.cornerRadius = 10.0;
    [mockStatusBar addSubview:notch];

    // Mock Consumer Navigation Bar
    UIView *mockNavBar = [[UIView alloc] init];
    mockNavBar.translatesAutoresizingMaskIntoConstraints = NO;
    mockNavBar.backgroundColor = [UIColor ppElevatedSurface];
    [_simulatedDeviceCard addSubview:mockNavBar];

    UILabel *logoLabel = [[UILabel alloc] init];
    logoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    logoLabel.font = [Styling fontBold:17];
    logoLabel.textColor = [UIColor ppPrimary];
    logoLabel.text = @"بيوربتس PurePets";
    [mockNavBar addSubview:logoLabel];

    UIImageView *cartIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"cart.fill"]];
    cartIcon.translatesAutoresizingMaskIntoConstraints = NO;
    cartIcon.tintColor = [UIColor ppPrimary];
    [mockNavBar addSubview:cartIcon];

    // Mock Search Pill
    UIView *mockSearch = [[UIView alloc] init];
    mockSearch.translatesAutoresizingMaskIntoConstraints = NO;
    mockSearch.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.4];
    mockSearch.layer.cornerRadius = 16.0;
    [_simulatedDeviceCard addSubview:mockSearch];

    UIImageView *searchIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    searchIcon.translatesAutoresizingMaskIntoConstraints = NO;
    searchIcon.tintColor = [UIColor ppTextSecondary];
    [mockSearch addSubview:searchIcon];

    UILabel *searchPlaceholder = [[UILabel alloc] init];
    searchPlaceholder.translatesAutoresizingMaskIntoConstraints = NO;
    searchPlaceholder.font = [Styling fontRegular:12];
    searchPlaceholder.textColor = [UIColor ppTextSecondary];
    searchPlaceholder.text = @"ابحث في المنتجات، الأطعمة، والعيادات…";
    [mockSearch addSubview:searchPlaceholder];

    // Mock Category Icons Row
    UIStackView *categoryRow = [[UIStackView alloc] init];
    categoryRow.translatesAutoresizingMaskIntoConstraints = NO;
    categoryRow.axis = UILayoutConstraintAxisHorizontal;
    categoryRow.distribution = UIStackViewDistributionFillEqually;
    categoryRow.spacing = 8.0;
    [_simulatedDeviceCard addSubview:categoryRow];

    NSArray *categories = @[
        @{@"t": @"قطط", @"i": @"pawprint.fill"},
        @{@"t": @"كلاب", @"i": @"heart.fill"},
        @{@"t": @"أطعمة", @"i": @"takeoutbag.and.cup.and.straw.fill"},
        @{@"t": @"عيادات", @"i": @"cross.case.fill"}
    ];
    for (NSDictionary *cat in categories) {
        UIView *bubble = [[UIView alloc] init];
        bubble.backgroundColor = [UIColor ppElevatedSurface];
        bubble.layer.cornerRadius = 12.0;
        bubble.layer.borderWidth = 0.5;
        bubble.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.6].CGColor;
        [categoryRow addArrangedSubview:bubble];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:cat[@"i"]]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.tintColor = [UIColor ppPrimary];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [bubble addSubview:icon];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = [Styling fontMedium:10];
        label.textColor = [UIColor ppTextPrimary];
        label.text = cat[@"t"];
        label.textAlignment = NSTextAlignmentCenter;
        [bubble addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [bubble.heightAnchor constraintEqualToConstant:48.0],
            [icon.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:6.0],
            [icon.centerXAnchor constraintEqualToAnchor:bubble.centerXAnchor],
            [icon.widthAnchor constraintEqualToConstant:18.0],
            [icon.heightAnchor constraintEqualToConstant:18.0],
            [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:3.0],
            [label.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor],
            [label.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor]
        ]];
    }

    // THE LIVE BANNER IN-SITU CANVAS
    UIView *liveBannerCanvas = [[UIView alloc] init];
    liveBannerCanvas.translatesAutoresizingMaskIntoConstraints = NO;
    liveBannerCanvas.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.12];
    liveBannerCanvas.layer.cornerRadius = 20.0;
    if (@available(iOS 13.0, *)) {
        liveBannerCanvas.layer.cornerCurve = kCACornerCurveContinuous;
    }
    liveBannerCanvas.clipsToBounds = YES;
    [_simulatedDeviceCard addSubview:liveBannerCanvas];

    _bannerBackgroundImageView = [[UIImageView alloc] init];
    _bannerBackgroundImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerBackgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    _bannerBackgroundImageView.clipsToBounds = YES;
    [liveBannerCanvas addSubview:_bannerBackgroundImageView];

    _bannerGradientLayer = [CAGradientLayer layer];
    _bannerGradientLayer.colors = @[
        (id)[UIColor colorWithWhite:0 alpha:0.75].CGColor,
        (id)[UIColor colorWithWhite:0 alpha:0.40].CGColor,
        (id)[UIColor colorWithWhite:0 alpha:0.70].CGColor
    ];
    _bannerGradientLayer.startPoint = CGPointMake(0, 0.5);
    _bannerGradientLayer.endPoint = CGPointMake(1, 0.5);
    [liveBannerCanvas.layer addSublayer:_bannerGradientLayer];

    _bannerSampleImageView = [[UIImageView alloc] init];
    _bannerSampleImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerSampleImageView.contentMode = UIViewContentModeScaleAspectFill;
    _bannerSampleImageView.clipsToBounds = YES;
    _bannerSampleImageView.layer.cornerRadius = 16.0;
    _bannerSampleImageView.layer.borderWidth = 1.5;
    _bannerSampleImageView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    _bannerSampleImageView.backgroundColor = [[UIColor ppWarmPorcelain] colorWithAlphaComponent:0.5];
    [liveBannerCanvas addSubview:_bannerSampleImageView];

    _bannerBadgeImageView = [[UIImageView alloc] init];
    _bannerBadgeImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerBadgeImageView.contentMode = UIViewContentModeScaleAspectFit;
    _bannerBadgeImageView.clipsToBounds = YES;
    _bannerBadgeImageView.hidden = YES;
    [liveBannerCanvas addSubview:_bannerBadgeImageView];

    UIStackView *bannerTextStack = [[UIStackView alloc] init];
    bannerTextStack.translatesAutoresizingMaskIntoConstraints = NO;
    bannerTextStack.axis = UILayoutConstraintAxisVertical;
    bannerTextStack.spacing = 4.0;
    bannerTextStack.alignment = UIStackViewAlignmentLeading;
    [liveBannerCanvas addSubview:bannerTextStack];

    _bannerTitleLabel = [[UILabel alloc] init];
    _bannerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerTitleLabel.font = [Styling fontBold:16];
    _bannerTitleLabel.textColor = UIColor.whiteColor;
    _bannerTitleLabel.numberOfLines = 2;
    _bannerTitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [bannerTextStack addArrangedSubview:_bannerTitleLabel];

    _bannerDescLabel = [[UILabel alloc] init];
    _bannerDescLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerDescLabel.font = [Styling fontMedium:13];
    _bannerDescLabel.textColor = [UIColor colorWithWhite:1 alpha:0.92];
    _bannerDescLabel.numberOfLines = 2;
    _bannerDescLabel.textAlignment = [Language alignmentForCurrentLanguage];
    [bannerTextStack addArrangedSubview:_bannerDescLabel];

    _bannerDateLabel = [[UILabel alloc] init];
    _bannerDateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerDateLabel.font = [Styling fontRegular:11];
    _bannerDateLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    [bannerTextStack addArrangedSubview:_bannerDateLabel];

    // Mock Bottom Feed Items
    UILabel *feedHeading = [[UILabel alloc] init];
    feedHeading.translatesAutoresizingMaskIntoConstraints = NO;
    feedHeading.font = [Styling fontBold:15];
    feedHeading.textColor = [UIColor ppTextPrimary];
    feedHeading.text = @"المنتجات الأكثر رواجاً 🔥";
    feedHeading.textAlignment = [Language alignmentForCurrentLanguage];
    [_simulatedDeviceCard addSubview:feedHeading];

    UIStackView *mockProductsRow = [[UIStackView alloc] init];
    mockProductsRow.translatesAutoresizingMaskIntoConstraints = NO;
    mockProductsRow.axis = UILayoutConstraintAxisHorizontal;
    mockProductsRow.distribution = UIStackViewDistributionFillEqually;
    mockProductsRow.spacing = 10.0;
    [_simulatedDeviceCard addSubview:mockProductsRow];

    for (int i = 0; i < 2; i++) {
        UIView *prodCard = [[UIView alloc] init];
        prodCard.backgroundColor = [UIColor ppElevatedSurface];
        prodCard.layer.cornerRadius = 16.0;
        prodCard.layer.borderWidth = 0.5;
        prodCard.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.6].CGColor;
        [mockProductsRow addArrangedSubview:prodCard];

        UIView *imgBox = [[UIView alloc] init];
        imgBox.translatesAutoresizingMaskIntoConstraints = NO;
        imgBox.backgroundColor = [[UIColor ppWarmPorcelain] colorWithAlphaComponent:0.5];
        imgBox.layer.cornerRadius = 12.0;
        [prodCard addSubview:imgBox];

        UILabel *pTitle = [[UILabel alloc] init];
        pTitle.translatesAutoresizingMaskIntoConstraints = NO;
        pTitle.font = [Styling fontBold:12];
        pTitle.textColor = [UIColor ppTextPrimary];
        pTitle.text = (i == 0) ? @"طعام رويال كانين" : @"سرير قطط مريح";
        pTitle.textAlignment = [Language alignmentForCurrentLanguage];
        [prodCard addSubview:pTitle];

        UILabel *pPrice = [[UILabel alloc] init];
        pPrice.translatesAutoresizingMaskIntoConstraints = NO;
        pPrice.font = [Styling fontBold:11];
        pPrice.textColor = [UIColor ppPrimary];
        pPrice.text = (i == 0) ? @"120 ر.ق" : @"85 ر.ق";
        pPrice.textAlignment = [Language alignmentForCurrentLanguage];
        [prodCard addSubview:pPrice];

        [NSLayoutConstraint activateConstraints:@[
            [prodCard.heightAnchor constraintEqualToConstant:130.0],
            [imgBox.topAnchor constraintEqualToAnchor:prodCard.topAnchor constant:8.0],
            [imgBox.leadingAnchor constraintEqualToAnchor:prodCard.leadingAnchor constant:8.0],
            [imgBox.trailingAnchor constraintEqualToAnchor:prodCard.trailingAnchor constant:-8.0],
            [imgBox.heightAnchor constraintEqualToConstant:68.0],
            [pTitle.topAnchor constraintEqualToAnchor:imgBox.bottomAnchor constant:6.0],
            [pTitle.leadingAnchor constraintEqualToAnchor:prodCard.leadingAnchor constant:8.0],
            [pTitle.trailingAnchor constraintEqualToAnchor:prodCard.trailingAnchor constant:-8.0],
            [pPrice.topAnchor constraintEqualToAnchor:pTitle.bottomAnchor constant:2.0],
            [pPrice.leadingAnchor constraintEqualToAnchor:prodCard.leadingAnchor constant:8.0],
            [pPrice.trailingAnchor constraintEqualToAnchor:prodCard.trailingAnchor constant:-8.0],
        ]];
    }

    // Constraints for Device Frame & Content
    [NSLayoutConstraint activateConstraints:@[
        [_simulatedDeviceCard.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:12.0],
        [_simulatedDeviceCard.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor constant:18.0],
        [_simulatedDeviceCard.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor constant:-18.0],
        [_simulatedDeviceCard.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-24.0],
        [_simulatedDeviceCard.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor constant:-36.0],

        [mockStatusBar.topAnchor constraintEqualToAnchor:_simulatedDeviceCard.topAnchor],
        [mockStatusBar.leadingAnchor constraintEqualToAnchor:_simulatedDeviceCard.leadingAnchor],
        [mockStatusBar.trailingAnchor constraintEqualToAnchor:_simulatedDeviceCard.trailingAnchor],
        [mockStatusBar.heightAnchor constraintEqualToConstant:34.0],

        [notch.centerXAnchor constraintEqualToAnchor:mockStatusBar.centerXAnchor],
        [notch.topAnchor constraintEqualToAnchor:mockStatusBar.topAnchor constant:6.0],
        [notch.widthAnchor constraintEqualToConstant:90.0],
        [notch.heightAnchor constraintEqualToConstant:18.0],

        [mockNavBar.topAnchor constraintEqualToAnchor:mockStatusBar.bottomAnchor],
        [mockNavBar.leadingAnchor constraintEqualToAnchor:_simulatedDeviceCard.leadingAnchor],
        [mockNavBar.trailingAnchor constraintEqualToAnchor:_simulatedDeviceCard.trailingAnchor],
        [mockNavBar.heightAnchor constraintEqualToConstant:40.0],

        [logoLabel.leadingAnchor constraintEqualToAnchor:mockNavBar.leadingAnchor constant:14.0],
        [logoLabel.centerYAnchor constraintEqualToAnchor:mockNavBar.centerYAnchor],
        [cartIcon.trailingAnchor constraintEqualToAnchor:mockNavBar.trailingAnchor constant:-14.0],
        [cartIcon.centerYAnchor constraintEqualToAnchor:mockNavBar.centerYAnchor],
        [cartIcon.widthAnchor constraintEqualToConstant:20.0],
        [cartIcon.heightAnchor constraintEqualToConstant:20.0],

        [mockSearch.topAnchor constraintEqualToAnchor:mockNavBar.bottomAnchor constant:8.0],
        [mockSearch.leadingAnchor constraintEqualToAnchor:_simulatedDeviceCard.leadingAnchor constant:12.0],
        [mockSearch.trailingAnchor constraintEqualToAnchor:_simulatedDeviceCard.trailingAnchor constant:-12.0],
        [mockSearch.heightAnchor constraintEqualToConstant:34.0],

        [searchIcon.leadingAnchor constraintEqualToAnchor:mockSearch.leadingAnchor constant:10.0],
        [searchIcon.centerYAnchor constraintEqualToAnchor:mockSearch.centerYAnchor],
        [searchIcon.widthAnchor constraintEqualToConstant:14.0],
        [searchIcon.heightAnchor constraintEqualToConstant:14.0],
        [searchPlaceholder.leadingAnchor constraintEqualToAnchor:searchIcon.trailingAnchor constant:6.0],
        [searchPlaceholder.trailingAnchor constraintEqualToAnchor:mockSearch.trailingAnchor constant:-10.0],
        [searchPlaceholder.centerYAnchor constraintEqualToAnchor:mockSearch.centerYAnchor],

        [categoryRow.topAnchor constraintEqualToAnchor:mockSearch.bottomAnchor constant:10.0],
        [categoryRow.leadingAnchor constraintEqualToAnchor:_simulatedDeviceCard.leadingAnchor constant:12.0],
        [categoryRow.trailingAnchor constraintEqualToAnchor:_simulatedDeviceCard.trailingAnchor constant:-12.0],

        // Live Banner in Situ
        [liveBannerCanvas.topAnchor constraintEqualToAnchor:categoryRow.bottomAnchor constant:12.0],
        [liveBannerCanvas.leadingAnchor constraintEqualToAnchor:_simulatedDeviceCard.leadingAnchor constant:12.0],
        [liveBannerCanvas.trailingAnchor constraintEqualToAnchor:_simulatedDeviceCard.trailingAnchor constant:-12.0],
        [liveBannerCanvas.heightAnchor constraintEqualToConstant:128.0],

        [_bannerBackgroundImageView.topAnchor constraintEqualToAnchor:liveBannerCanvas.topAnchor],
        [_bannerBackgroundImageView.leadingAnchor constraintEqualToAnchor:liveBannerCanvas.leadingAnchor],
        [_bannerBackgroundImageView.trailingAnchor constraintEqualToAnchor:liveBannerCanvas.trailingAnchor],
        [_bannerBackgroundImageView.bottomAnchor constraintEqualToAnchor:liveBannerCanvas.bottomAnchor],

        [_bannerSampleImageView.trailingAnchor constraintEqualToAnchor:liveBannerCanvas.trailingAnchor constant:-12.0],
        [_bannerSampleImageView.centerYAnchor constraintEqualToAnchor:liveBannerCanvas.centerYAnchor],
        [_bannerSampleImageView.widthAnchor constraintEqualToConstant:80.0],
        [_bannerSampleImageView.heightAnchor constraintEqualToConstant:80.0],

        [_bannerBadgeImageView.topAnchor constraintEqualToAnchor:_bannerSampleImageView.topAnchor constant:-6.0],
        [_bannerBadgeImageView.trailingAnchor constraintEqualToAnchor:_bannerSampleImageView.trailingAnchor constant:6.0],
        [_bannerBadgeImageView.widthAnchor constraintEqualToConstant:22.0],
        [_bannerBadgeImageView.heightAnchor constraintEqualToConstant:22.0],

        [bannerTextStack.topAnchor constraintEqualToAnchor:liveBannerCanvas.topAnchor constant:12.0],
        [bannerTextStack.leadingAnchor constraintEqualToAnchor:liveBannerCanvas.leadingAnchor constant:12.0],
        [bannerTextStack.trailingAnchor constraintLessThanOrEqualToAnchor:_bannerSampleImageView.leadingAnchor constant:-10.0],
        [bannerTextStack.bottomAnchor constraintLessThanOrEqualToAnchor:liveBannerCanvas.bottomAnchor constant:-12.0],

        // Feed Heading and Products
        [feedHeading.topAnchor constraintEqualToAnchor:liveBannerCanvas.bottomAnchor constant:14.0],
        [feedHeading.leadingAnchor constraintEqualToAnchor:_simulatedDeviceCard.leadingAnchor constant:14.0],
        [feedHeading.trailingAnchor constraintEqualToAnchor:_simulatedDeviceCard.trailingAnchor constant:-14.0],

        [mockProductsRow.topAnchor constraintEqualToAnchor:feedHeading.bottomAnchor constant:8.0],
        [mockProductsRow.leadingAnchor constraintEqualToAnchor:_simulatedDeviceCard.leadingAnchor constant:12.0],
        [mockProductsRow.trailingAnchor constraintEqualToAnchor:_simulatedDeviceCard.trailingAnchor constant:-12.0],
        [mockProductsRow.bottomAnchor constraintEqualToAnchor:_simulatedDeviceCard.bottomAnchor constant:-16.0],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.bannerGradientLayer.frame = self.bannerBackgroundImageView.superview.bounds;
}

- (void)populateBannerData {
    NSString *t = [self.banner localizedTitleText];
    self.bannerTitleLabel.text = t.length > 0 ? t : kLang(@"No Title");

    NSString *d = [self.banner localizedDescText];
    self.bannerDescLabel.text = d.length > 0 ? d : @"";
    self.bannerDescLabel.hidden = d.length == 0;

    if (self.banner.validityDuration && self.banner.countdownTimeRemaining.length > 0) {
        self.bannerDateLabel.text = [NSString stringWithFormat:@"⏳ %@", self.banner.countdownTimeRemaining];
    } else if (self.banner.postDateText.length > 0) {
        self.bannerDateLabel.text = self.banner.postDateText;
    } else {
        self.bannerDateLabel.text = @"";
    }

    if (self.banner.pannerTextStyle == PPBannerTextStyleBlack) {
        self.bannerTitleLabel.textColor = [UIColor ppTextPrimary];
        self.bannerDescLabel.textColor = [UIColor ppTextSecondary];
    } else {
        self.bannerTitleLabel.textColor = UIColor.whiteColor;
        self.bannerDescLabel.textColor = [UIColor colorWithWhite:1 alpha:0.92];
    }

    if (self.banner.backgroundImageURL) {
        [[PPImageManager sharedManager] setImageFromUrl:self.banner.backgroundImageURL.absoluteString
                                            toImageView:self.bannerBackgroundImageView
                                               fadeType:PPImageFadeTypeCrossDissolve
                                               duration:0.3
                                             completion:nil];
    }

    if (self.banner.sampleImageURL) {
        self.bannerSampleImageView.hidden = NO;
        [[PPImageManager sharedManager] setImageFromUrl:self.banner.sampleImageURL.absoluteString
                                            toImageView:self.bannerSampleImageView
                                               fadeType:PPImageFadeTypeCrossDissolve
                                               duration:0.3
                                             completion:nil];
    } else {
        self.bannerSampleImageView.hidden = YES;
    }

    if (self.banner.badgeImageURL) {
        self.bannerBadgeImageView.hidden = NO;
        [[PPImageManager sharedManager] setImageFromUrl:self.banner.badgeImageURL.absoluteString
                                            toImageView:self.bannerBadgeImageView
                                               fadeType:PPImageFadeTypeCrossDissolve
                                               duration:0.3
                                             completion:nil];
    } else {
        self.bannerBadgeImageView.hidden = YES;
    }
}

#pragma mark - Actions

- (void)onCloseTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onEditTapped {
    __weak typeof(self) weakSelf = self;
    [self dismissViewControllerAnimated:YES completion:^{
        if (weakSelf.onEditRequested) {
            weakSelf.onEditRequested(weakSelf.banner, weakSelf.group);
        }
    }];
}

- (void)onTestTapTapped {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [feedback impactOccurred];

    NSString *actionDesc = @"";
    NSString *val = self.banner.onTapValue ?: @"";
    switch (self.banner.onTapAction) {
        case PPBannerOnTapViewAccessory:
            actionDesc = [NSString stringWithFormat:@"%@: %@", kLang(@"Banners_TapAction_Accessory"), val];
            break;
        case PPBannerOnTapViewAd:
            actionDesc = [NSString stringWithFormat:@"%@: %@", kLang(@"Banners_TapAction_Ad"), val];
            break;
        case PPBannerOnTapOpenUrl:
            actionDesc = [NSString stringWithFormat:@"%@: %@", kLang(@"Banners_TapAction_URL"), val];
            break;
        case PPBannerOnTapCallPhoneNumber:
            actionDesc = [NSString stringWithFormat:@"%@: %@", kLang(@"Banners_TapAction_Call"), val];
            break;
        case PPBannerOnTapWhatsApp:
            actionDesc = [NSString stringWithFormat:@"%@: %@", kLang(@"Banners_TapAction_WhatsApp"), val];
            break;
    }

    NSString *msg = [NSString stringWithFormat:kLang(@"Banners_Sim_TapTriggered"), actionDesc];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Banners_Sim_TestTap")
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Common_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
