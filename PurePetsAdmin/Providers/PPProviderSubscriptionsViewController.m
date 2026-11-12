#import "PPProviderSubscriptionsViewController.h"
#import "PPProviderService.h"
#import "PPProviderUI.h"
#import "PPProviderSubscriptionPresentation.h"
#import "PPDesignTokens.h"
#import "PPStaffAuth.h"
#import <math.h>
#import "Language.h"
#import "Styling.h"
#import "PPFirebaseCompat.h"

static NSString *PPSSubString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSDictionary *PPSSubDict(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }
static NSArray *PPSSubArray(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static NSString *PPSSubKey(NSString *prefix, NSString *value) { return kLang([prefix stringByAppendingString:value]); }
static NSString *PPSSubStatus(NSString *value) { return PPSSubKey(@"PartnerSub_Status_", value); }
static NSString *PPSSubAction(NSString *value) { return PPSSubKey(@"PartnerSub_Action_", value); }
static NSString *PPSSubStatusSymbol(NSString *status) {
    if ([status isEqualToString:@"active"]) return @"checkmark.circle.fill";
    if ([status isEqualToString:@"paused"]) return @"pause.circle.fill";
    if ([status isEqualToString:@"expired"]) return @"exclamationmark.circle.fill";
    if ([status isEqualToString:@"cancelled"]) return @"xmark.circle.fill";
    if ([status isEqualToString:@"unmanaged"]) return @"questionmark.circle.fill";
    return @"tray.2.fill";
}
static UIColor *PPSSubStatusAccentColor(NSString *status) {
    if ([status isEqualToString:@"active"]) return [UIColor ppSuccess];
    if ([status isEqualToString:@"paused"]) return [UIColor ppWarning];
    if ([status isEqualToString:@"expired"]) return [UIColor ppError];
    if ([status isEqualToString:@"cancelled"]) return PPProviderSecondaryTextColor();
    if ([status isEqualToString:@"unmanaged"]) return [UIColor systemPurpleColor];
    return PPProviderBrandColor();
}
static NSString *PPSSubDate(id value) {
    if (![value isKindOfClass:NSNumber.class]) return kLang(@"PartnerSub_NoEnd");
    return PPProviderDateText([NSDate dateWithTimeIntervalSince1970:[value doubleValue] / 1000.0]);
}
static UILabel *PPSSubLabel(UIFontTextStyle style, BOOL bold) {
    UILabel *label = [UILabel new]; label.numberOfLines = 0;
    CGFloat size = [style isEqualToString:UIFontTextStyleTitle2] ? 24 : [style isEqualToString:UIFontTextStyleFootnote] ? 13 : bold ? 17 : 15;
    UIFont *base = bold ? [Styling fontBold:size] : [Styling fontRegular:size];
    label.font = [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:base];
    label.adjustsFontForContentSizeCategory = YES; label.textColor = PPProviderPrimaryTextColor();
    label.textAlignment = Language.alignmentForCurrentLanguage;
    return label;
}
static void PPSSubAlert(UIViewController *owner, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [owner presentViewController:alert animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
}

static NSString *PPSSubReadFailure(NSError *error, BOOL hasRetainedRecords) {
    if ([error.domain isEqualToString:FIRFunctionsErrorDomain]) {
        if (error.code == FIRFunctionsErrorCodePermissionDenied) return kLang(@"PartnerSub_Permission");
        if (error.code == FIRFunctionsErrorCodeUnauthenticated) return kLang(@"PartnerSub_SessionEnded");
        if ([@[@(FIRFunctionsErrorCodeInternal), @(FIRFunctionsErrorCodeUnavailable),
               @(FIRFunctionsErrorCodeDeadlineExceeded), @(FIRFunctionsErrorCodeResourceExhausted)] containsObject:@(error.code)]) {
            return hasRetainedRecords ? kLang(@"PartnerSub_LoadFailed") : kLang(@"PartnerSub_ServiceUnavailable");
        }
    }
    if ([error.domain isEqualToString:NSURLErrorDomain] &&
        (error.code == NSURLErrorNotConnectedToInternet || error.code == NSURLErrorNetworkConnectionLost)) return kLang(@"PartnerSub_Offline");
    return hasRetainedRecords ? kLang(@"PartnerSub_LoadFailed") : kLang(@"PartnerSub_InitialLoadFailed");
}

@interface PPSSubscriptionSearchField : UISearchTextField
@end
@implementation PPSSubscriptionSearchField
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.height = MAX(44, MAX(size.height, ceil(self.font.lineHeight + 16)));
    return size;
}
@end

@interface PPSSubscriptionCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@end
@implementation PPSSubscriptionCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor = PPProviderSurfaceColor();
        self.nameLabel = PPSSubLabel(UIFontTextStyleHeadline, YES);
        self.summaryLabel = PPSSubLabel(UIFontTextStyleSubheadline, NO); self.summaryLabel.textColor = PPProviderSecondaryTextColor();
        self.stateLabel = PPSSubLabel(UIFontTextStyleSubheadline, YES); self.stateLabel.textColor = PPProviderBrandColor();
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.summaryLabel, self.stateLabel]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 7; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:18],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-18],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor]]];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } return self;
}
@end

@interface PPSSubscriptionDetailController : UITableViewController <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, copy) void (^didClose)(void);
@property (nonatomic, strong) NSString *profileID;
@property (nonatomic, strong) NSDictionary *partner;
@property (nonatomic, strong) NSArray *plans;
@property (nonatomic, strong) NSArray *history;
@property (nonatomic, strong) NSDictionary *pendingCommand;
@property (nonatomic, strong) NSString *actorUID;
@property (nonatomic, assign) BOOL canManage;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL submitting;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) NSString *statusMessage;
@end

@interface PPProviderRefreshPillButton : UIButton
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabelCustom;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, assign) BOOL isLoading;
- (void)updateWithTitle:(NSString *)title
               iconName:(NSString *)iconName
              tintColor:(UIColor *)tintColor
        backgroundColor:(UIColor *)bgColor
              isLoading:(BOOL)isLoading;
- (void)updateColors;
@end

@implementation PPProviderRefreshPillButton

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.layer.cornerRadius = 24.0;
    self.layer.masksToBounds = NO;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.06;
    self.layer.shadowOffset = CGSizeMake(0, 3);
    self.layer.shadowRadius = 8.0;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    self.backgroundColor = PPProviderRaisedSurfaceColor();
    
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.iconImageView.widthAnchor constraintEqualToConstant:16],
        [self.iconImageView.heightAnchor constraintEqualToConstant:16]
    ]];
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.titleLabelCustom = [UILabel new];
    self.titleLabelCustom.font = [Styling fontBold:15];
    self.titleLabelCustom.adjustsFontForContentSizeCategory = YES;
    self.titleLabelCustom.textAlignment = NSTextAlignmentCenter;
    self.titleLabelCustom.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.iconImageView, self.spinner, self.titleLabelCustom]];
    self.contentStack.axis = UILayoutConstraintAxisHorizontal;
    self.contentStack.spacing = 8;
    self.contentStack.alignment = UIStackViewAlignmentCenter;
    self.contentStack.userInteractionEnabled = NO;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    
    [self addSubview:self.contentStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.contentStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.contentStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.contentStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:22],
        [self.contentStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-22]
    ]];
    
    [self addTarget:self action:@selector(touchDownAnimation) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(touchUpAnimation) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

- (void)touchDownAnimation {
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.transform = CGAffineTransformMakeScale(0.96, 0.96);
        self.alpha = 0.88;
    } completion:nil];
}

- (void)touchUpAnimation {
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.transform = CGAffineTransformIdentity;
        self.alpha = 1.0;
    } completion:nil];
}

- (void)updateWithTitle:(NSString *)title
               iconName:(NSString *)iconName
              tintColor:(UIColor *)tintColor
        backgroundColor:(UIColor *)bgColor
              isLoading:(BOOL)isLoading {
    self.isLoading = isLoading;
    self.titleLabelCustom.text = title;
    self.titleLabelCustom.textColor = tintColor;
    self.backgroundColor = bgColor ?: PPProviderRaisedSurfaceColor();
    self.layer.borderColor = [tintColor colorWithAlphaComponent:0.22].CGColor;
    
    if (isLoading) {
        self.iconImageView.hidden = YES;
        [self.spinner startAnimating];
        self.spinner.color = tintColor;
    } else {
        [self.spinner stopAnimating];
        self.iconImageView.hidden = NO;
        if (iconName.length) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
            self.iconImageView.image = [[UIImage systemImageNamed:iconName withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            self.iconImageView.tintColor = tintColor;
        } else {
            self.iconImageView.image = nil;
        }
    }
}

- (void)updateColors {
    self.layer.borderColor = self.titleLabelCustom.textColor ? [self.titleLabelCustom.textColor colorWithAlphaComponent:0.22].CGColor : [UIColor ppSurfaceBorder].CGColor;
}

- (void)setTitle:(NSString *)title forState:(UIControlState)state {
    [super setTitle:title forState:state];
    if (state == UIControlStateNormal && title.length) {
        self.titleLabelCustom.text = title;
    }
}

@end

@interface PPProviderTableFooterView : UIView
@property (nonatomic, strong) UIView *badgePill;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) PPProviderRefreshPillButton *refreshButton;
- (void)updateWithTitle:(NSString *)title
               iconName:(NSString *)iconName
              tintColor:(UIColor *)tintColor
        backgroundColor:(UIColor *)bgColor
              isLoading:(BOOL)isLoading
               infoText:(nullable NSString *)infoText
             isSuccess:(BOOL)isSuccess;
- (void)updateColors;
@end

@implementation PPProviderTableFooterView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = UIColor.clearColor;
    self.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    
    self.badgePill = [UIView new];
    self.badgePill.backgroundColor = [PPProviderSurfaceColor() colorWithAlphaComponent:0.85];
    self.badgePill.layer.cornerRadius = 12;
    self.badgePill.layer.borderWidth = 0.5;
    self.badgePill.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    self.badgePill.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.statusDot = [UIView new];
    self.statusDot.layer.cornerRadius = 3.5;
    self.statusDot.backgroundColor = [UIColor ppSuccess];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.statusDot.widthAnchor constraintEqualToConstant:7],
        [self.statusDot.heightAnchor constraintEqualToConstant:7]
    ]];
    
    self.badgeLabel = [UILabel new];
    self.badgeLabel.font = [Styling fontRegular:12];
    self.badgeLabel.textColor = PPProviderSecondaryTextColor();
    self.badgeLabel.textAlignment = NSTextAlignmentCenter;
    self.badgeLabel.adjustsFontForContentSizeCategory = YES;
    self.badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIStackView *badgeStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot, self.badgeLabel]];
    badgeStack.axis = UILayoutConstraintAxisHorizontal;
    badgeStack.spacing = 6;
    badgeStack.alignment = UIStackViewAlignmentCenter;
    badgeStack.translatesAutoresizingMaskIntoConstraints = NO;
    badgeStack.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    [self.badgePill addSubview:badgeStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [badgeStack.topAnchor constraintEqualToAnchor:self.badgePill.topAnchor constant:4],
        [badgeStack.bottomAnchor constraintEqualToAnchor:self.badgePill.bottomAnchor constant:-4],
        [badgeStack.leadingAnchor constraintEqualToAnchor:self.badgePill.leadingAnchor constant:10],
        [badgeStack.trailingAnchor constraintEqualToAnchor:self.badgePill.trailingAnchor constant:-10]
    ]];
    
    self.refreshButton = [[PPProviderRefreshPillButton alloc] init];
    self.refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self addSubview:self.badgePill];
    [self addSubview:self.refreshButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.badgePill.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [self.badgePill.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        
        [self.refreshButton.topAnchor constraintEqualToAnchor:self.badgePill.bottomAnchor constant:10],
        [self.refreshButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.refreshButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24],
        [self.refreshButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-24],
        [self.refreshButton.heightAnchor constraintEqualToConstant:48],
        [self.bottomAnchor constraintEqualToAnchor:self.refreshButton.bottomAnchor constant:28]
    ]];
}

- (void)updateWithTitle:(NSString *)title
               iconName:(NSString *)iconName
              tintColor:(UIColor *)tintColor
        backgroundColor:(UIColor *)bgColor
              isLoading:(BOOL)isLoading
               infoText:(nullable NSString *)infoText
             isSuccess:(BOOL)isSuccess {
    if (infoText.length) {
        self.badgePill.hidden = NO;
        self.badgeLabel.text = infoText;
        self.statusDot.backgroundColor = isSuccess ? [UIColor ppSuccess] : (isLoading ? PPProviderBrandColor() : [UIColor ppTextSecondary]);
    } else {
        self.badgePill.hidden = YES;
        self.badgeLabel.text = nil;
    }
    [self.refreshButton updateWithTitle:title iconName:iconName tintColor:tintColor backgroundColor:bgColor isLoading:isLoading];
    [self setNeedsLayout];
}

- (void)updateColors {
    self.badgePill.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [self.refreshButton updateColors];
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat badgeHeight = self.badgePill.hidden ? 0 : 28;
    CGFloat spacing = self.badgePill.hidden ? 0 : 10;
    CGFloat buttonHeight = 48;
    CGFloat total = 14 + badgeHeight + spacing + buttonHeight + 28;
    return CGSizeMake(size.width, total);
}
@end

@interface PPProviderSubscriptionsViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *registerHeader;
@property (nonatomic, strong) UISearchTextField *searchField;
@property (nonatomic, strong) UIView *searchSurface;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) PPProviderTableFooterView *footerView;
@property (nonatomic, strong) UIButton *pageButton;
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, strong) UIImageView *filterChevronView;
@property (nonatomic, strong) UIScrollView *statusRailScrollView;
@property (nonatomic, strong) UIStackView *statusRailStackView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *statusCapsuleButtons;
@property (nonatomic, strong) NSArray<NSDictionary *> *partners;
@property (nonatomic, strong) NSArray<NSDictionary *> *visiblePartners;
@property (nonatomic, strong) NSString *nextCursor;
@property (nonatomic, strong) NSString *filter;
@property (nonatomic, strong) NSString *actorUID;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL hasLoaded;
@property (nonatomic, strong) NSError *loadError;
@property (nonatomic, copy) NSString *failedCursor;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, copy) NSString *selectedProfileID;
@end

@implementation PPProviderSubscriptionsViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.partners = @[]; self.visiblePartners = @[]; self.filter = @"all";
    self.actorUID = [FIRAuth auth].currentUser.uid ?: @"";
    self.view.backgroundColor = PPProviderCanvasColor(); self.view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    UILabel *title = PPSSubLabel(UIFontTextStyleTitle2, YES); title.text = kLang(@"PartnerSub_Title");
    UILabel *subtitle = PPSSubLabel(UIFontTextStyleFootnote, NO); subtitle.text = kLang(@"PartnerSub_RegisterHint"); subtitle.textColor = PPProviderSecondaryTextColor();
    self.filterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.filterButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterButton.accessibilityLabel = kLang(@"PartnerSub_StatusFilter");
    [self.filterButton.heightAnchor constraintGreaterThanOrEqualToConstant:42].active = YES;
    [self.filterButton addTarget:self action:@selector(chooseFilter) forControlEvents:UIControlEventTouchUpInside];
    
    self.filterChevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold]]];
    self.filterChevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterChevronView.tintColor = PPProviderBrandColor();
    self.filterChevronView.contentMode = UIViewContentModeCenter;
    self.filterChevronView.isAccessibilityElement = NO;
    [self.filterButton addSubview:self.filterChevronView];
    [NSLayoutConstraint activateConstraints:@[
        [self.filterChevronView.trailingAnchor constraintEqualToAnchor:self.filterButton.trailingAnchor constant:-12],
        [self.filterChevronView.centerYAnchor constraintEqualToAnchor:self.filterButton.centerYAnchor],
        [self.filterChevronView.widthAnchor constraintEqualToConstant:14],
        [self.filterChevronView.heightAnchor constraintEqualToConstant:14]
    ]];

    self.statusCapsuleButtons = [NSMutableArray array];
    self.statusRailScrollView = [UIScrollView new];
    self.statusRailScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusRailScrollView.showsHorizontalScrollIndicator = NO;
    self.statusRailScrollView.showsVerticalScrollIndicator = NO;
    self.statusRailScrollView.clipsToBounds = NO;
    self.statusRailScrollView.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    [self.statusRailScrollView.heightAnchor constraintEqualToConstant:38].active = YES;

    self.statusRailStackView = [UIStackView new];
    self.statusRailStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusRailStackView.axis = UILayoutConstraintAxisHorizontal;
    self.statusRailStackView.spacing = 8;
    self.statusRailStackView.alignment = UIStackViewAlignmentCenter;
    self.statusRailStackView.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    [self.statusRailScrollView addSubview:self.statusRailStackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusRailStackView.leadingAnchor constraintEqualToAnchor:self.statusRailScrollView.contentLayoutGuide.leadingAnchor],
        [self.statusRailStackView.trailingAnchor constraintEqualToAnchor:self.statusRailScrollView.contentLayoutGuide.trailingAnchor],
        [self.statusRailStackView.topAnchor constraintEqualToAnchor:self.statusRailScrollView.contentLayoutGuide.topAnchor],
        [self.statusRailStackView.bottomAnchor constraintEqualToAnchor:self.statusRailScrollView.contentLayoutGuide.bottomAnchor],
        [self.statusRailStackView.heightAnchor constraintEqualToAnchor:self.statusRailScrollView.frameLayoutGuide.heightAnchor]
    ]];

    NSArray<NSString *> *statuses = @[@"all", @"active", @"paused", @"expired", @"cancelled", @"unmanaged"];
    for (NSString *status in statuses) {
        UIButton *capsule = [self createCapsuleButtonForStatus:status];
        [self.statusCapsuleButtons addObject:capsule];
        [self.statusRailStackView addArrangedSubview:capsule];
    }
    self.searchSurface = [UIView new]; self.searchSurface.layer.cornerRadius = 14;
    self.searchSurface.backgroundColor = PPProviderSurfaceColor();
    self.searchField = [PPSSubscriptionSearchField new]; self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchField.delegate = self; self.searchField.borderStyle = UITextBorderStyleNone;
    self.searchField.backgroundColor = UIColor.clearColor; self.searchField.textColor = PPProviderPrimaryTextColor();
    self.searchField.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[Styling fontRegular:17]];
    self.searchField.adjustsFontForContentSizeCategory = YES;
    self.searchField.placeholder = kLang(@"PartnerSub_Search"); self.searchField.accessibilityLabel = kLang(@"PartnerSub_Search");
    self.searchField.accessibilityHint = kLang(@"PartnerSub_SearchHint");
    self.searchField.textAlignment = Language.alignmentForCurrentLanguage; self.searchField.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    self.searchField.autocorrectionType = UITextAutocorrectionTypeNo; self.searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchField.spellCheckingType = UITextSpellCheckingTypeNo; self.searchField.returnKeyType = UIReturnKeySearch;
    self.searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    UIImageView *magnifier = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]]];
    magnifier.frame = CGRectMake(0, 0, 32, 44); magnifier.contentMode = UIViewContentModeCenter;
    magnifier.tintColor = PPProviderSecondaryTextColor(); magnifier.isAccessibilityElement = NO;
    self.searchField.leftView = magnifier; self.searchField.leftViewMode = UITextFieldViewModeAlways;
    [self.searchField addTarget:self action:@selector(searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    [self.searchField addTarget:self action:@selector(updateSearchAppearance) forControlEvents:UIControlEventEditingDidBegin | UIControlEventEditingDidEnd];
    [self.searchSurface addSubview:self.searchField];
    [NSLayoutConstraint activateConstraints:@[[self.searchField.leadingAnchor constraintEqualToAnchor:self.searchSurface.leadingAnchor constant:12],
        [self.searchField.trailingAnchor constraintEqualToAnchor:self.searchSurface.trailingAnchor constant:-12],
        [self.searchField.topAnchor constraintEqualToAnchor:self.searchSurface.topAnchor constant:6],
        [self.searchField.bottomAnchor constraintEqualToAnchor:self.searchSurface.bottomAnchor constant:-6],
        [self.searchSurface.heightAnchor constraintGreaterThanOrEqualToConstant:56]]];
    UILabel *searchScope = PPSSubLabel(UIFontTextStyleFootnote, NO); searchScope.text = kLang(@"PartnerSub_SearchScope"); searchScope.textColor = PPProviderSecondaryTextColor();
    self.messageLabel = PPSSubLabel(UIFontTextStyleFootnote, NO); self.messageLabel.textColor = PPProviderSecondaryTextColor();
    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.hidesWhenStopped = YES; self.loadingIndicator.accessibilityElementsHidden = YES;
    UIStackView *statusInfoStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.loadingIndicator, self.messageLabel]];
    statusInfoStack.axis = UILayoutConstraintAxisHorizontal; statusInfoStack.spacing = 6; statusInfoStack.alignment = UIStackViewAlignmentCenter;
    [statusInfoStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIView *filterSpacer = [UIView new];
    [filterSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *filterRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.filterButton, filterSpacer, statusInfoStack]];
    filterRow.axis = UILayoutConstraintAxisHorizontal; filterRow.spacing = 8; filterRow.alignment = UIStackViewAlignmentCenter;
    [self.filterButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle, self.searchSurface, searchScope, filterRow, self.statusRailScrollView]];
    header.axis = UILayoutConstraintAxisVertical; header.spacing = 10; header.translatesAutoresizingMaskIntoConstraints = NO;
    [header setCustomSpacing:20 afterView:subtitle]; [header setCustomSpacing:6 afterView:self.searchSurface]; [header setCustomSpacing:10 afterView:filterRow];
    self.registerHeader = [UIView new];
    [self.registerHeader addSubview:header];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = PPProviderCanvasColor(); self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 130;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.tableView registerClass:PPSSubscriptionCell.class forCellReuseIdentifier:@"subscription"];
    self.tableView.refreshControl = [UIRefreshControl new]; [self.tableView.refreshControl addTarget:self action:@selector(reloadPage) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.tableView];
    self.tableView.tableHeaderView = self.registerHeader;
    self.footerView = [[PPProviderTableFooterView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 116)];
    self.pageButton = self.footerView.refreshButton;
    [self.pageButton addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside];
    self.tableView.tableFooterView = self.footerView;
    [NSLayoutConstraint activateConstraints:@[[header.topAnchor constraintEqualToAnchor:self.registerHeader.topAnchor constant:12],
        [header.leadingAnchor constraintEqualToAnchor:self.registerHeader.leadingAnchor constant:20], [header.trailingAnchor constraintEqualToAnchor:self.registerHeader.trailingAnchor constant:-20],
        [header.bottomAnchor constraintEqualToAnchor:self.registerHeader.bottomAnchor constant:-12],
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor], [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    [self updateSearchAppearance]; [self applyFilter]; [self reloadPage];
}
- (void)updateSearchAppearance {
    self.searchSurface.layer.borderWidth = self.searchField.isFirstResponder ? 1.5 : 1;
    self.searchSurface.layer.borderColor = (self.searchField.isFirstResponder ? PPProviderBrandColor() : [UIColor ppSurfaceBorder]).CGColor;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateSearchAppearance];
    [self.footerView updateColors];
    [self updateFilterButtonAppearance];
    [self updateStatusRailSelection];
    [self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGFloat width = self.tableView.bounds.size.width; if (width <= 0) return;
    CGFloat height = [self.registerHeader systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (fabs(self.registerHeader.frame.size.height - height) > 0.5 || self.registerHeader.frame.size.width != width) {
        self.registerHeader.frame = CGRectMake(0, 0, width, height); self.tableView.tableHeaderView = self.registerHeader;
    }
    CGFloat footerHeight = [self.footerView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height;
    if (self.footerView.frame.size.width != width || fabs(self.footerView.frame.size.height - footerHeight) > 0.5) {
        self.footerView.frame = CGRectMake(0, 0, width, footerHeight); self.tableView.tableFooterView = self.footerView;
    }
}
- (BOOL)canRead {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [self.actorUID isEqualToString:[FIRAuth auth].currentUser.uid] && staff.isActive && staff.hasGlobalScope &&
        [staff hasAnyPermission:@[kStaffPermProvidersView, kStaffPermProvidersManage]];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshSelectedProfile];
    if (!self.loading && !self.hasLoaded && !self.loadError) [self reloadPage];
    [self updateFetchState];
}
- (void)refreshSelectedProfile {
    if (![self canRead]) { [self reloadPage]; return; }
    if (self.loading || !self.selectedProfileID.length) return;
    NSString *profileID = self.selectedProfileID; self.selectedProfileID = nil; NSUInteger generation = ++self.generation;
    self.loading = YES; self.loadError = nil; [self updateFetchState];
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchSubscriptionWorkspace:@{@"profileId":profileID} shouldContinue:^BOOL{
        return weakSelf && generation == weakSelf.generation;
    } completion:^(NSDictionary *result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self || generation != self.generation) return;
        self.loading = NO;
        if (![self canRead]) { self.partners = @[]; [self applyFilter]; return; }
        if (error) { self.loadError = error; self.failedCursor = nil; [self updateFetchState]; return; }
        NSDictionary *partner = PPSSubDict(result[@"partner"]); if (!partner.count) { [self updateFetchState]; return; }
        NSMutableArray *retained = self.partners.mutableCopy;
        for (NSUInteger index = 0; index < retained.count; index++) if ([PPSSubString(retained[index][@"profileId"]) isEqualToString:profileID]) { retained[index] = partner; break; }
        self.partners = retained; CGPoint offset = self.tableView.contentOffset; [self applyFilter]; [self.tableView setContentOffset:offset animated:NO];
    }];
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; self.generation++; self.loading = NO; }
- (void)reloadPage { if (!self.loading) [self fetchAfter:nil]; }
- (void)loadMore {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    if (!self.loading) [self fetchAfter:self.loadError ? self.failedCursor : self.nextCursor];
}
- (void)fetchAfter:(NSString *)cursor {
    if (![self canRead]) { self.partners = @[]; [self applyFilter]; [self.tableView.refreshControl endRefreshing]; return; }
    self.loading = YES; self.loadError = nil; [self updateFetchState]; NSUInteger generation = ++self.generation;
    NSDictionary *query = cursor.length ? @{@"after":cursor, @"limit":@40} : @{@"limit":@40};
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchSubscriptionWorkspace:query shouldContinue:^BOOL{
        return weakSelf && generation == weakSelf.generation;
    } completion:^(NSDictionary *result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self || generation != self.generation) return;
        self.loading = NO; [self.tableView.refreshControl endRefreshing];
        if (![self canRead]) { self.partners = @[]; [self applyFilter]; return; }
        if (error) { self.loadError = error; self.failedCursor = [cursor copy]; [self updateFetchState]; return; }
        NSArray *page = PPSSubArray(result[@"partners"]); self.partners = cursor.length ? [self.partners arrayByAddingObjectsFromArray:page] : page;
        self.hasLoaded = YES; self.loadError = nil; self.failedCursor = nil;
        self.nextCursor = PPSSubString(result[@"nextCursor"]); [self applyFilter];
    }];
}
- (void)applyFilter {
    NSString *term = [(self.searchField.text ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.visiblePartners = [self.partners filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *p, NSDictionary *bindings) {
        BOOL status = [self.filter isEqualToString:@"all"] || [self.filter isEqualToString:p[@"status"]];
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@ %@", p[@"displayName"] ?: @"", p[@"userId"] ?: @"", PPProviderLocalizedType(p[@"providerType"]), PPProviderLocalizedText(PPSSubDict(p[@"planName"]), @"")];
        return status && (!term.length || [text rangeOfString:term options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound);
    }]];
    [self updateFilterButtonAppearance];
    [self updateStatusRailSelection];
    [self.tableView reloadData];
    [self updateFetchState];
}

- (UIButton *)createCapsuleButtonForStatus:(NSString *)status {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *statuses = @[@"all", @"active", @"paused", @"expired", @"cancelled", @"unmanaged"];
    button.tag = [statuses indexOfObject:status];
    button.layer.cornerRadius = 17;
    button.layer.masksToBounds = YES;
    button.layer.borderWidth = 1.0;
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 6;
        UIImageSymbolConfiguration *symConfig = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
        config.image = [UIImage systemImageNamed:PPSSubStatusSymbol(status) withConfiguration:symConfig];
        button.configuration = config;
    } else {
        button.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
        button.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 0);
    }
    
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:34].active = YES;
    [button addTarget:self action:@selector(statusCapsuleTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (NSUInteger)countForStatus:(NSString *)status {
    if ([status isEqualToString:@"all"]) return self.partners.count;
    NSUInteger count = 0;
    for (NSDictionary *p in self.partners) {
        if ([PPSSubString(p[@"status"]) isEqualToString:status]) {
            count++;
        }
    }
    return count;
}

- (UIMenu *)buildFilterMenu API_AVAILABLE(ios(14.0)) {
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    NSArray<NSString *> *statuses = @[@"all", @"active", @"paused", @"expired", @"cancelled", @"unmanaged"];
    __weak typeof(self) weakSelf = self;
    
    for (NSString *status in statuses) {
        NSUInteger count = [self countForStatus:status];
        NSString *title = PPSSubStatus(status);
        NSString *actionTitle = [NSString stringWithFormat:@"%@  (%lu)", title, (unsigned long)count];
        UIImage *image = [UIImage systemImageNamed:PPSSubStatusSymbol(status)];
        
        UIAction *action = [UIAction actionWithTitle:actionTitle image:image identifier:nil handler:^(__kindof UIAction * _Nonnull act) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self selectFilter:status];
        }];
        
        action.state = [self.filter isEqualToString:status] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    
    return [UIMenu menuWithTitle:kLang(@"PartnerSub_Filter") children:actions];
}

- (void)selectFilter:(NSString *)status {
    if ([self.filter isEqualToString:status]) return;
    UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
    [generator prepare];
    [generator selectionChanged];
    self.filter = status;
    [self applyFilter];
    
    NSArray<NSString *> *statuses = @[@"all", @"active", @"paused", @"expired", @"cancelled", @"unmanaged"];
    NSUInteger index = [statuses indexOfObject:status];
    if (index != NSNotFound && index < self.statusCapsuleButtons.count) {
        UIButton *btn = self.statusCapsuleButtons[index];
        [self.statusRailScrollView scrollRectToVisible:CGRectInset(btn.frame, -16, 0) animated:!UIAccessibilityIsReduceMotionEnabled()];
    }
}

- (void)statusCapsuleTapped:(UIButton *)sender {
    NSArray<NSString *> *statuses = @[@"all", @"active", @"paused", @"expired", @"cancelled", @"unmanaged"];
    if (sender.tag < statuses.count) {
        NSString *status = statuses[sender.tag];
        [self selectFilter:status];
        [self.statusRailScrollView scrollRectToVisible:CGRectInset(sender.frame, -16, 0) animated:!UIAccessibilityIsReduceMotionEnabled()];
    }
}

- (void)updateFilterButtonAppearance {
    BOOL isAll = [self.filter isEqualToString:@"all"];
    UIColor *accent = PPSSubStatusAccentColor(self.filter);
    NSUInteger count = [self countForStatus:self.filter];
    NSString *statusTitle = PPSSubStatus(self.filter);
    NSString *displayTitle = [NSString stringWithFormat:@"%@  (%lu)", statusTitle, (unsigned long)count];
    
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        UIImageSymbolConfiguration *symConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
        config.image = [UIImage systemImageNamed:PPSSubStatusSymbol(self.filter) withConfiguration:symConfig];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 8;
        config.baseForegroundColor = isAll ? PPProviderBrandColor() : accent;
        
        NSDictionary *attrs = @{
            NSFontAttributeName: [Styling fontBold:14],
            NSForegroundColorAttributeName: isAll ? PPProviderPrimaryTextColor() : accent
        };
        config.attributedTitle = [[NSAttributedString alloc] initWithString:displayTitle attributes:attrs];
        config.contentInsets = NSDirectionalEdgeInsetsMake(8, 14, 8, 32);
        config.background.backgroundColor = isAll ? PPProviderRaisedSurfaceColor() : [accent colorWithAlphaComponent:0.10];
        config.background.cornerRadius = 14;
        config.background.strokeColor = isAll ? [UIColor ppSurfaceBorder] : [accent colorWithAlphaComponent:0.35];
        config.background.strokeWidth = isAll ? 1.0 : 1.5;
        self.filterButton.configuration = config;
    } else {
        [self.filterButton setTitle:displayTitle forState:UIControlStateNormal];
        [self.filterButton setTitleColor:isAll ? PPProviderPrimaryTextColor() : accent forState:UIControlStateNormal];
        self.filterButton.layer.cornerRadius = 14;
        self.filterButton.layer.borderWidth = isAll ? 1.0 : 1.5;
        self.filterButton.layer.borderColor = (isAll ? [UIColor ppSurfaceBorder] : [accent colorWithAlphaComponent:0.35]).CGColor;
        self.filterButton.backgroundColor = isAll ? PPProviderRaisedSurfaceColor() : [accent colorWithAlphaComponent:0.10];
    }
    
    self.filterChevronView.tintColor = isAll ? PPProviderSecondaryTextColor() : accent;
    self.filterButton.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", kLang(@"PartnerSub_StatusFilter"), statusTitle];
    self.filterButton.accessibilityValue = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    
    if (@available(iOS 14.0, *)) {
        self.filterButton.showsMenuAsPrimaryAction = YES;
        self.filterButton.menu = [self buildFilterMenu];
    }
}

- (void)updateStatusRailSelection {
    NSArray<NSString *> *statuses = @[@"all", @"active", @"paused", @"expired", @"cancelled", @"unmanaged"];
    for (NSUInteger i = 0; i < self.statusCapsuleButtons.count && i < statuses.count; i++) {
        NSString *status = statuses[i];
        UIButton *capsule = self.statusCapsuleButtons[i];
        BOOL isSelected = [self.filter isEqualToString:status];
        NSUInteger count = [self countForStatus:status];
        UIColor *accent = PPSSubStatusAccentColor(status);
        NSString *title = PPSSubStatus(status);
        NSString *capsuleTitle = [NSString stringWithFormat:@"%@  %lu", title, (unsigned long)count];
        
        capsule.selected = isSelected;
        capsule.layer.borderWidth = isSelected ? 1.5 : 1.0;
        capsule.layer.borderColor = (isSelected ? accent : [UIColor ppSurfaceBorder]).CGColor;
        capsule.backgroundColor = isSelected ? [accent colorWithAlphaComponent:0.14] : PPProviderSurfaceColor();
        capsule.alpha = (count == 0 && !isSelected) ? 0.45 : 1.0;
        
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *config = capsule.configuration;
            if (!config) config = [UIButtonConfiguration plainButtonConfiguration];
            
            UIImageSymbolConfiguration *symConfig = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:isSelected ? UIImageSymbolWeightBold : UIImageSymbolWeightMedium];
            config.image = [UIImage systemImageNamed:PPSSubStatusSymbol(status) withConfiguration:symConfig];
            config.imagePlacement = NSDirectionalRectEdgeLeading;
            config.imagePadding = 6;
            config.baseForegroundColor = isSelected ? accent : PPProviderSecondaryTextColor();
            
            NSDictionary *attrs = @{
                NSFontAttributeName: isSelected ? [Styling fontBold:13] : [Styling fontRegular:13],
                NSForegroundColorAttributeName: isSelected ? accent : PPProviderSecondaryTextColor()
            };
            config.attributedTitle = [[NSAttributedString alloc] initWithString:capsuleTitle attributes:attrs];
            config.background.backgroundColor = isSelected ? [accent colorWithAlphaComponent:0.14] : PPProviderSurfaceColor();
            config.background.strokeColor = isSelected ? accent : [UIColor ppSurfaceBorder];
            config.background.strokeWidth = isSelected ? 1.5 : 1.0;
            config.background.cornerRadius = 17;
            capsule.configuration = config;
        } else {
            [capsule setTitle:capsuleTitle forState:UIControlStateNormal];
            [capsule setTitleColor:isSelected ? accent : PPProviderSecondaryTextColor() forState:UIControlStateNormal];
        }
        
        capsule.accessibilityLabel = [NSString stringWithFormat:@"%@: %lu", title, (unsigned long)count];
        capsule.accessibilityTraits = UIAccessibilityTraitButton | (isSelected ? UIAccessibilityTraitSelected : 0);
    }
}

- (void)chooseFilter {
    [self.searchField resignFirstResponder];
    if (@available(iOS 14.0, *)) {
        self.filterButton.menu = [self buildFilterMenu];
    } else {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"PartnerSub_Filter") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *status in @[@"all", @"active", @"paused", @"expired", @"cancelled", @"unmanaged"]) {
            [sheet addAction:[UIAlertAction actionWithTitle:PPSSubStatus(status) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self selectFilter:status];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = self.filterButton;
        sheet.popoverPresentationController.sourceRect = self.filterButton.bounds;
        [self presentViewController:sheet animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
    }
}
- (void)updateFetchState {
    BOOL allowed = [self canRead];
    self.footerView.hidden = !allowed;
    self.pageButton.enabled = allowed && !self.loading;
    self.messageLabel.textColor = self.loadError ? [UIColor ppError] : PPProviderSecondaryTextColor();
    if (self.loading && allowed) [self.loadingIndicator startAnimating]; else [self.loadingIndicator stopAnimating];
    if (!allowed) self.messageLabel.text = kLang([self.actorUID isEqualToString:[FIRAuth auth].currentUser.uid] ? @"PartnerSub_Permission" : @"PartnerSub_SessionEnded");
    else if (self.loading || (!self.hasLoaded && !self.loadError)) self.messageLabel.text = kLang(@"PartnerSub_Loading");
    else if (self.loadError) self.messageLabel.text = PPSSubReadFailure(self.loadError, self.partners.count > 0);
    else {
        self.messageLabel.text = self.partners.count ? [NSString stringWithFormat:kLang(@"PartnerSub_LoadedCount"), (unsigned long)self.visiblePartners.count, (unsigned long)self.partners.count] : kLang(@"PartnerSub_Empty");
        if (self.partners.count && !self.visiblePartners.count) self.messageLabel.text = [NSString stringWithFormat:@"%@\n%@", kLang(@"PartnerSub_NoMatches"), self.messageLabel.text];
    }
    
    NSString *buttonTitle;
    NSString *iconName;
    UIColor *tintColor;
    NSString *infoText = nil;
    BOOL isSuccess = NO;
    
    if (self.loadError) {
        buttonTitle = kLang(@"PartnerSub_Retry");
        iconName = @"exclamationmark.arrow.triangle.2.circlepath";
        tintColor = [UIColor ppWarning];
        infoText = PPSSubReadFailure(self.loadError, self.partners.count > 0);
    } else if (self.loading) {
        buttonTitle = kLang(@"PartnerSub_Refreshing");
        iconName = @"arrow.clockwise";
        tintColor = PPProviderBrandColor();
    } else if (self.nextCursor.length) {
        buttonTitle = kLang(@"PartnerSub_LoadMore");
        iconName = @"arrow.down.circle.fill";
        tintColor = PPProviderBrandColor();
        infoText = [NSString stringWithFormat:kLang(@"PartnerSub_LoadedCount"), (unsigned long)self.visiblePartners.count, (unsigned long)self.partners.count];
    } else {
        buttonTitle = kLang(@"PartnerSub_Refresh");
        iconName = @"arrow.clockwise";
        tintColor = PPProviderBrandColor();
        if (self.visiblePartners.count > 0) {
            infoText = [NSString stringWithFormat:kLang(@"PartnerSub_EndOfList"), (unsigned long)self.visiblePartners.count];
            isSuccess = YES;
        }
    }
    
    [self.footerView updateWithTitle:buttonTitle
                            iconName:iconName
                           tintColor:tintColor
                     backgroundColor:PPProviderRaisedSurfaceColor()
                           isLoading:self.loading
                            infoText:infoText
                           isSuccess:isSuccess];
    [self.view setNeedsLayout];
}

- (void)searchTextChanged:(UITextField *)field { [self applyFilter]; }
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visiblePartners.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPSSubscriptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"subscription" forIndexPath:indexPath]; NSDictionary *p = self.visiblePartners[indexPath.row];
    cell.nameLabel.text = PPSSubString(p[@"displayName"]);
    cell.summaryLabel.text = [NSString stringWithFormat:@"%@ · %@", PPProviderLocalizedType(p[@"providerType"]), PPProviderLocalizedText(PPSSubDict(p[@"planName"]), kLang(@"PartnerSub_NoPlan"))];
    NSDictionary *sub = PPSSubDict(p[@"subscription"]);
    cell.stateLabel.text = [NSString stringWithFormat:@"%@\n%@", PPSSubStatus(p[@"status"]), sub.count ? PPSSubDate(sub[@"expiresAt"]) : kLang(@"PartnerSub_UnmanagedHint")];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO]; if (![self canRead]) return;
    PPSSubscriptionDetailController *detail = [[PPSSubscriptionDetailController alloc] initWithStyle:UITableViewStylePlain];
    detail.profileID = self.visiblePartners[indexPath.row][@"profileId"]; detail.actorUID = self.actorUID;
    self.selectedProfileID = detail.profileID;
    __weak typeof(self) weakSelf = self;
    detail.didClose = ^{ [weakSelf refreshSelectedProfile]; };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:detail];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.presentationController.delegate = detail;
    if (@available(iOS 15.0, *)) navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
    [self presentViewController:navigation animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
}
@end

@interface PPSSubscriptionConfirmationController : UIViewController <UITextViewDelegate>
@property (nonatomic, strong) NSDictionary *partner;
@property (nonatomic, strong) NSDictionary *plan;
@property (nonatomic, strong) NSString *action;
@property (nonatomic, strong) UITextView *reasonView;
@property (nonatomic, strong) PPSubscriptionReasonView *reasonEditor;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *reasonGuidance;
@property (nonatomic, assign) BOOL confirming;
@property (copy) void (^onConfirm)(NSString *reason);
@end

static NSString *PPSSubRecordedDate(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) ? PPSSubDate(value) : kLang(@"PartnerSub_DateUnset");
}
static NSString *PPSSubPlanPrice(NSDictionary *plan) {
    BOOL percentage = [PPSSubString(plan[@"costType"]) isEqualToString:@"percentage"];
    id value = percentage ? plan[@"costValue"] : (plan[@"priceAmount"] ?: plan[@"costValue"]);
    if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return @"";
    if (percentage) return [NSString stringWithFormat:kLang(@"PartnerSub_Percentage"), [value doubleValue]];
    NSString *currency = PPSSubString(plan[@"currency"]);
    return currency.length ? PPProviderMoneyText([value doubleValue], currency) : @"";
}
static UIColor *PPSSubAgreementColor(NSString *state) {
    if ([state isEqualToString:@"active"]) return [UIColor ppSuccess];
    if ([state isEqualToString:@"paused"] || [state isEqualToString:@"expired"]) return [UIColor ppWarning];
    if ([state isEqualToString:@"unavailable"]) return [UIColor ppError];
    return PPProviderSecondaryTextColor();
}
static NSString *PPSSubCommandSymbol(NSString *action) {
    NSDictionary *symbols = @{@"create":@"plus.circle", @"change_plan":@"arrow.triangle.swap", @"pause":@"pause.circle",
        @"activate":@"play.circle", @"renew":@"arrow.clockwise", @"cancel":@"xmark.circle", @"retry":@"arrow.clockwise.circle"};
    return symbols[action] ?: @"calendar";
}

@implementation PPSSubscriptionDetailController
- (NSString *)draftKey { return [NSString stringWithFormat:@"PPPartnerSub.Pending.%@.%@", self.actorUID, self.profileID]; }
- (BOOL)canRead {
    PPStaffDoc *staff = [PPStaffAuth shared].cachedCurrentStaff;
    return [self.actorUID isEqualToString:[FIRAuth auth].currentUser.uid] && staff.isActive && staff.hasGlobalScope && [staff hasAnyPermission:@[kStaffPermProvidersView,kStaffPermProvidersManage]];
}
- (BOOL)mayWrite { return [self canRead] && [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermProvidersManage] && self.canManage; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = kLang(@"PartnerSub_DetailTitle"); self.tableView.backgroundColor = PPProviderCanvasColor();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 96;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone; self.tableView.sectionHeaderTopPadding = 0;
    self.tableView.estimatedSectionHeaderHeight = 44; self.tableView.estimatedSectionFooterHeight = 44;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 24, 0);
    self.view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.refreshControl = [UIRefreshControl new]; [self.refreshControl addTarget:self action:@selector(loadDossier) forControlEvents:UIControlEventValueChanged];
    self.pendingCommand = [[NSUserDefaults standardUserDefaults] dictionaryForKey:self.draftKey];
    [self loadDossier];
}
- (void)close {
    if (self.submitting) return;
    self.generation++; self.loading = NO;
    void (^callback)(void) = self.didClose;
    [self dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:callback];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    self.generation++; self.loading = NO;
    if (self.didClose) self.didClose();
}
- (void)loadDossier {
    if (self.loading || self.submitting) { [self.refreshControl endRefreshing]; return; }
    if (![self canRead]) { self.partner = nil; self.history = @[]; self.plans = @[]; self.statusMessage = kLang(@"PartnerSub_Permission"); [self.tableView reloadData]; return; }
    self.loading = YES; self.statusMessage = kLang(@"PartnerSub_Loading"); [self.tableView reloadData]; NSUInteger generation = ++self.generation;
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] fetchSubscriptionWorkspace:@{@"profileId":self.profileID} shouldContinue:^BOOL{
        return weakSelf && generation == weakSelf.generation;
    } completion:^(NSDictionary *result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self || generation != self.generation) return;
        self.loading = NO; [self.refreshControl endRefreshing];
        if (![self canRead]) { self.partner = nil; self.history = @[]; self.statusMessage = kLang(@"PartnerSub_Permission"); }
        else if (error) self.statusMessage = PPSSubReadFailure(error, self.partner.count > 0);
        else { self.partner = PPSSubDict(result[@"partner"]); self.plans = PPSSubArray(result[@"plans"]); self.history = PPSSubArray(result[@"history"]);
            self.canManage = [result[@"canManage"] boolValue]; self.statusMessage = self.pendingCommand ? kLang(@"PartnerSub_Uncertain") : kLang(@"PartnerSub_ManualTerms"); }
        [self.tableView reloadData];
    }];
}
- (NSArray *)actions { return self.pendingCommand ? @[@"retry"] : ([self mayWrite] && !self.loading ? PPSSubArray(self.partner[@"allowedActions"]) : @[]); }
- (BOOL)showsFetchNotice {
    return self.loading || self.submitting || self.pendingCommand || (self.statusMessage.length &&
        ![self.statusMessage isEqualToString:kLang(@"PartnerSub_ManualTerms")] && ![self.statusMessage isEqualToString:kLang(@"PartnerSub_Saved")]);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.partner.count ? 1 + (self.showsFetchNotice ? 1 : 0) : 1;
    if (section == 1) return self.partner.count ? 4 : 0;
    if (section == 2) return self.actions.count ?: (self.partner.count && !self.loading ? 1 : 0);
    return self.history.count ?: (self.partner.count && !self.loading ? 1 : 0);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (![self tableView:tableView numberOfRowsInSection:section]) return nil;
    return section == 1 ? kLang(@"PartnerSub_Terms") : section == 2 ? kLang(@"PartnerSub_Actions") : section == 3 ? kLang(@"PartnerSub_History") : nil;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!self.partner.count) return nil;
    if (section == 1) return kLang(@"PartnerSub_ManualTerms");
    if (section == 2) return [self mayWrite] ? kLang(@"PartnerSub_AccessNotice") : kLang(@"PartnerSub_ReadOnly");
    return nil;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForHeaderInSection:section];
    return text.length ? PPSubscriptionSectionText(text, YES) : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section].length ? UITableViewAutomaticDimension : 0.01;
}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    return text.length ? PPSubscriptionSectionText(text, NO) : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return [self tableView:tableView titleForFooterInSection:section].length ? UITableViewAutomaticDimension : 0.01;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *sub = PPSSubDict(self.partner[@"subscription"]);
    if (indexPath.section == 0) {
        if (self.partner.count && indexPath.row == 0) {
            NSString *state = PPSSubString(self.partner[@"status"]);
            return PPSubscriptionHostedCell(PPSubscriptionIdentity(PPSSubString(self.partner[@"displayName"]), PPProviderLocalizedType(self.partner[@"providerType"]), PPSSubStatus(state), PPSSubAgreementColor(state)));
        }
        BOOL busy = self.loading || self.submitting;
        NSString *message = self.statusMessage ?: kLang(@"PartnerSub_Loading");
        if (!self.submitting) message = [NSString stringWithFormat:@"%@\n%@", message, kLang(@"PartnerSub_PullToRefresh")];
        return PPSubscriptionHostedCell(PPSubscriptionNotice(message, busy ? @"arrow.clockwise" : @"exclamationmark.circle", !busy));
    }
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            NSDictionary *plan = PPSSubDict(sub[@"planSnapshot"]);
            NSString *interval = PPSSubString(plan[@"billingInterval"]);
            return PPSubscriptionHostedCell(PPSubscriptionPlanSummary(kLang(@"PartnerSub_CurrentPlan"), PPProviderLocalizedText(PPSSubDict(self.partner[@"planName"]), kLang(@"PartnerSub_NoPlan")), PPSSubPlanPrice(plan), interval.length ? PPProviderLocalizedBillingInterval(interval) : @""));
        }
        if (indexPath.row == 1) return PPSubscriptionFactCell(kLang(@"PartnerSub_TermStarts"), PPSSubRecordedDate(sub[@"startedAt"]), @"calendar");
        if (indexPath.row == 2) {
            BOOL noScheduledEnd = [PPSSubString(PPSSubDict(sub[@"planSnapshot"])[@"billingInterval"]) isEqualToString:@"one_time"] && (!sub[@"expiresAt"] || sub[@"expiresAt"] == NSNull.null);
            return PPSubscriptionFactCell(kLang(@"PartnerSub_TermEnds"), noScheduledEnd ? kLang(@"PartnerSub_NoEnd") : PPSSubRecordedDate(sub[@"expiresAt"]), @"calendar.badge.clock");
        }
        return PPSubscriptionFactCell(kLang(@"PartnerSub_Operations"), PPSSubKey(@"PartnerSub_Op_", PPSSubString(self.partner[@"operationalStatus"])), @"shield");
    }
    if (indexPath.section == 2) {
        if (!self.actions.count) {
            UITableViewCell *cell = PPSubscriptionFactCell(kLang(@"PartnerSub_NoActions"), [self mayWrite] ? kLang(@"PartnerSub_AccessNotice") : kLang(@"PartnerSub_ReadOnly"), @"lock");
            cell.userInteractionEnabled = NO; return cell;
        }
        NSString *action = self.actions[indexPath.row];
        BOOL emphasized = self.actions.count == 1 && [action isEqualToString:@"create"];
        return PPSubscriptionActionCell(PPSSubAction(action), PPSSubKey(@"PartnerSub_Impact_", action), PPSSubCommandSymbol(action), [action isEqualToString:@"cancel"], emphasized, !self.submitting);
    }
    if (!self.history.count) return PPSubscriptionFactCell(kLang(@"PartnerSub_EmptyHistory"), kLang(@"PartnerSub_EmptyHistoryHint"), @"clock.arrow.circlepath");
    NSDictionary *event = self.history[indexPath.row];
    NSString *reason = [PPSSubString(event[@"reason"]) isEqualToString:@"term_expired"] ? kLang(@"PartnerSub_TermExpired") : PPSSubString(event[@"reason"]);
    return PPSubscriptionFactCell(PPSSubAction(event[@"action"]), [NSString stringWithFormat:@"%@\n%@", PPSSubRecordedDate(event[@"createdAt"]), reason], @"clock");
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO]; if (indexPath.section != 2 || indexPath.row >= self.actions.count || self.submitting || ![self mayWrite]) return;
    NSString *action = self.actions[indexPath.row]; if ([action isEqualToString:@"retry"]) { [self sendPending]; return; }
    if ([action isEqualToString:@"create"] || [action isEqualToString:@"change_plan"]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:kLang(@"PartnerSub_ChoosePlan") message:kLang(@"PartnerSub_PlanChoiceHint") preferredStyle:UIAlertControllerStyleActionSheet];
        NSUInteger choices = 0;
        for (NSDictionary *plan in self.plans) {
            if ([action isEqualToString:@"change_plan"] && [PPSSubString(plan[@"id"]) isEqualToString:PPSSubString(self.partner[@"planId"])]) continue;
            choices++;
            NSString *title = [NSString stringWithFormat:@"%@ · %@", PPProviderLocalizedText(PPSSubDict(plan[@"name"]), PPSSubString(plan[@"id"])), PPProviderLocalizedBillingInterval(plan[@"billingInterval"])];
            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *choice) { [self confirmAction:action plan:plan]; }]];
        }
        if (!choices) { PPSSubAlert(self, kLang(@"PartnerSub_ChoosePlan"), kLang(@"PartnerSub_NoPlans")); return; }
        [sheet addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = self.tableView; sheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
        [self presentViewController:sheet animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
    } else [self confirmAction:action plan:nil];
}
- (void)confirmAction:(NSString *)action plan:(NSDictionary *)plan {
    NSDictionary *reviewedPartner = [self.partner copy]; NSDictionary *reviewedPlan = [plan copy];
    NSString *reviewedProfileID = [self.profileID copy]; NSNumber *reviewedVersion = [reviewedPartner[@"version"] copy] ?: @0;
    PPSSubscriptionConfirmationController *form = [PPSSubscriptionConfirmationController new];
    form.partner = reviewedPartner; form.action = action; form.plan = reviewedPlan;
    __weak typeof(self) weakSelf = self;
    form.onConfirm = ^(NSString *reason) {
        __strong typeof(weakSelf) self = weakSelf; if (!self || ![self mayWrite] || self.pendingCommand || ![self.profileID isEqualToString:reviewedProfileID]) return;
        NSMutableDictionary *payload = [@{@"profileId":reviewedProfileID, @"action":action, @"expectedVersion":reviewedVersion,
            @"reason":reason, @"idempotencyKey":NSUUID.UUID.UUIDString.lowercaseString} mutableCopy];
        if (reviewedPlan) { payload[@"planId"] = PPSSubString(reviewedPlan[@"id"]); payload[@"expectedPlanHash"] = PPSSubString(reviewedPlan[@"planHash"]); }
        self.pendingCommand = payload.copy; [[NSUserDefaults standardUserDefaults] setObject:self.pendingCommand forKey:self.draftKey];
        [self sendPending];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:form];
    if (@available(iOS 15.0, *)) nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
    [self presentViewController:nav animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
}
- (void)sendPending {
    if (![self mayWrite] || self.submitting || !self.pendingCommand) return;
    self.submitting = YES; self.modalInPresentation = YES; self.navigationController.modalInPresentation = YES; self.navigationItem.leftBarButtonItem.enabled = NO;
    self.statusMessage = kLang(@"PartnerSub_Saving"); [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[PPProviderService shared] executeSubscriptionCommand:self.pendingCommand completion:^(NSDictionary *result, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf; if (!self) return;
        self.submitting = NO; self.modalInPresentation = NO; self.navigationController.modalInPresentation = NO; self.navigationItem.leftBarButtonItem.enabled = YES;
        if (![self canRead]) { self.partner = nil; self.history = @[]; self.statusMessage = kLang(@"PartnerSub_Permission"); [self.tableView reloadData]; return; }
        if (error) {
            BOOL finalError = [error.domain isEqualToString:FIRFunctionsErrorDomain] && [@[@3,@5,@6,@7,@9,@10,@16] containsObject:@(error.code)];
            if (finalError) { self.pendingCommand = nil; [[NSUserDefaults standardUserDefaults] removeObjectForKey:self.draftKey]; [self loadDossier]; }
            self.statusMessage = finalError ? kLang(@"PartnerSub_CommandRejected") : kLang(@"PartnerSub_Uncertain");
            [self.tableView reloadData]; PPSSubAlert(self, kLang(@"PartnerSub_UpdateFailed"), self.statusMessage); return;
        }
        NSDictionary *confirmed = PPSSubDict(result[@"partner"]);
        if (![result[@"ok"] isKindOfClass:NSNumber.class] || ![result[@"ok"] boolValue] ||
            ![result[@"contractVersion"] isKindOfClass:NSNumber.class] || [result[@"contractVersion"] integerValue] != 1 ||
            !PPSSubString(result[@"commandId"]).length || ![PPSSubString(confirmed[@"profileId"]) isEqualToString:self.profileID] ||
            ![confirmed[@"version"] isKindOfClass:NSNumber.class]) {
            self.statusMessage = kLang(@"PartnerSub_Uncertain"); [self.tableView reloadData]; return;
        }
        self.pendingCommand = nil; [[NSUserDefaults standardUserDefaults] removeObjectForKey:self.draftKey];
        self.partner = PPSSubDict(result[@"partner"]); self.statusMessage = kLang(@"PartnerSub_Saved"); [self.tableView reloadData];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, kLang(@"PartnerSub_Saved")); [self loadDossier];
    }];
}
@end

@implementation PPSSubscriptionConfirmationController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = PPSSubAction(self.action); self.view.backgroundColor = PPProviderCanvasColor();
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];

    self.scrollView = [UIScrollView new]; self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES; self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:self.scrollView];
    UIView *content = [UIView new]; content.translatesAutoresizingMaskIntoConstraints = NO; [self.scrollView addSubview:content];

    UIView *identity = PPSubscriptionIdentity(PPSSubString(self.partner[@"displayName"]), PPProviderLocalizedType(self.partner[@"providerType"]), @"", PPProviderSecondaryTextColor());
    UILabel *effectCaption = PPSubscriptionLabel(UIFontTextStyleFootnote, 13, YES);
    effectCaption.text = kLang(@"PartnerSub_ReviewChange"); effectCaption.textColor = PPProviderSecondaryTextColor();
    UILabel *effectTitle = PPSubscriptionLabel(UIFontTextStyleTitle2, 22, YES); effectTitle.text = PPSSubAction(self.action);
    UILabel *effect = PPSubscriptionLabel(UIFontTextStyleBody, 15, NO); effect.text = PPSSubKey(@"PartnerSub_Impact_", self.action);
    effect.textColor = PPProviderSecondaryTextColor();
    UIStackView *effectBlock = [[UIStackView alloc] initWithArrangedSubviews:@[effectCaption, effectTitle, effect]];
    effectBlock.axis = UILayoutConstraintAxisVertical; effectBlock.spacing = 8;

    NSDictionary *plan = self.plan ?: PPSSubDict(PPSSubDict(self.partner[@"subscription"])[@"planSnapshot"]);
    NSString *planName = PPProviderLocalizedText(PPSSubDict(plan[@"name"]), PPProviderLocalizedText(PPSSubDict(self.partner[@"planName"]), kLang(@"PartnerSub_NoPlan")));
    NSString *interval = PPSSubString(plan[@"billingInterval"]);
    UIView *planReview = PPSubscriptionPlanSummary(kLang(@"PartnerSub_SelectedPlan"), planName, PPSSubPlanPrice(plan), interval.length ? PPProviderLocalizedBillingInterval(interval) : @"");
    UIView *manualNotice = PPSubscriptionNotice(kLang(@"PartnerSub_ManualTerms"), @"info.circle", NO);
    UILabel *reasonTitle = PPSubscriptionLabel(UIFontTextStyleHeadline, 17, YES); reasonTitle.text = kLang(@"PartnerSub_Reason");
    reasonTitle.accessibilityTraits |= UIAccessibilityTraitHeader;
    self.reasonEditor = [PPSubscriptionReasonView new]; self.reasonView = self.reasonEditor.textView; self.reasonView.delegate = self;
    self.reasonGuidance = PPSubscriptionLabel(UIFontTextStyleFootnote, 13, NO); self.reasonGuidance.textColor = PPProviderSecondaryTextColor();
    UIStackView *reasonBlock = [[UIStackView alloc] initWithArrangedSubviews:@[reasonTitle, self.reasonEditor, self.reasonGuidance]];
    reasonBlock.axis = UILayoutConstraintAxisVertical; reasonBlock.spacing = 10;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[identity, effectBlock, planReview, manualNotice, reasonBlock]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 24; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    UIView *dock = [UIView new]; dock.translatesAutoresizingMaskIntoConstraints = NO; dock.backgroundColor = PPProviderCanvasColor();
    [self.view addSubview:dock];
    self.confirmButton = PPSubscriptionCommitButton(PPSSubKey(@"PartnerSub_Commit_", self.action), [self.action isEqualToString:@"cancel"]);
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO; self.confirmButton.enabled = NO;
    [self.confirmButton addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside]; [dock addSubview:self.confirmButton];
    NSLayoutConstraint *preferredContentWidth = [stack.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-40];
    NSLayoutConstraint *preferredButtonWidth = [self.confirmButton.widthAnchor constraintEqualToAnchor:dock.widthAnchor constant:-40];
    preferredContentWidth.priority = UILayoutPriorityDefaultHigh; preferredButtonWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:dock.topAnchor],
        [dock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [dock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [dock.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [self.confirmButton.topAnchor constraintEqualToAnchor:dock.topAnchor constant:12], [self.confirmButton.bottomAnchor constraintEqualToAnchor:dock.bottomAnchor constant:-12],
        [self.confirmButton.centerXAnchor constraintEqualToAnchor:dock.centerXAnchor],
        [self.confirmButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:dock.leadingAnchor constant:20],
        [self.confirmButton.trailingAnchor constraintLessThanOrEqualToAnchor:dock.trailingAnchor constant:-20],
        [self.confirmButton.widthAnchor constraintLessThanOrEqualToConstant:640], preferredButtonWidth,
        [content.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20], [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor constant:20],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:640], preferredContentWidth]];

    UIToolbar *toolbar = [UIToolbar new]; [toolbar sizeToFit]; toolbar.items = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil], [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(endEditing)]]; self.reasonView.inputAccessoryView = toolbar;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [self updateReasonState];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)endEditing { [self.view endEditing:YES]; }
- (void)cancel { if (!self.confirming) [self dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:nil]; }
- (void)confirm {
    NSString *reason = [self.reasonView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (reason.length < 3 || reason.length > 500) return;
    if (self.confirming) return;
    self.confirming = YES; self.confirmButton.enabled = NO; self.navigationItem.leftBarButtonItem.enabled = NO;
    self.modalInPresentation = YES; self.navigationController.modalInPresentation = YES;
    [self endEditing]; void (^callback)(NSString *) = self.onConfirm;
    [self dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:^{ if (callback) callback(reason); }];
}
- (void)updateReasonState {
    NSUInteger length = [self.reasonView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length;
    BOOL valid = length >= 3 && length <= 500;
    self.confirmButton.enabled = valid && !self.confirming;
    [self.reasonEditor updateCount:length limit:500 placeholderVisible:self.reasonView.text.length == 0 exceedsLimit:length > 500];
    self.reasonGuidance.text = kLang(length > 500 ? @"PartnerSub_ReasonTooLong" : @"PartnerSub_ReasonHint");
    self.reasonGuidance.textColor = length > 500 ? [UIColor ppError] : PPProviderSecondaryTextColor();
    self.confirmButton.accessibilityHint = valid ? nil : self.reasonGuidance.text;
}
- (void)textViewDidChange:(UITextView *)textView {
    [self updateReasonState]; [textView invalidateIntrinsicContentSize]; [self.view layoutIfNeeded]; [self revealReasonCaret];
}
- (void)textViewDidBeginEditing:(UITextView *)textView { [self.reasonEditor setEditing:YES]; [self revealReasonCaret]; }
- (void)textViewDidEndEditing:(UITextView *)textView { [self.reasonEditor setEditing:NO]; }
- (void)textViewDidChangeSelection:(UITextView *)textView { if (textView.isFirstResponder) [self revealReasonCaret]; }
- (void)keyboardDidShow:(NSNotification *)notification { [self.view layoutIfNeeded]; [self revealReasonCaret]; }
- (void)revealReasonCaret {
    if (!self.view.window || !self.reasonView.isFirstResponder || !self.reasonView.selectedTextRange) return;
    CGRect caret = [self.reasonView caretRectForPosition:self.reasonView.selectedTextRange.end];
    CGRect visibleTarget = [self.reasonView convertRect:CGRectInset(caret, -8, -12) toView:self.scrollView];
    [self.scrollView scrollRectToVisible:visibleTarget animated:NO];
}
@end
