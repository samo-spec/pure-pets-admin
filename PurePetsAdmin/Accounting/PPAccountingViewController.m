#import "PPAccountingViewController.h"
#import "PPAccountingService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"
#import "AppManager.h"
#import "PPHero.h"
#import "PPFormEngine.h"
@import FirebaseFirestore;

static UIColor *PPAccountingAccentColor(void) {
    return AppPrimaryClr ?: UIColor.systemPinkColor;
}

static UIColor *PPAccountingCanvasColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.systemGroupedBackgroundColor;
    return [UIColor colorWithWhite:0.96 alpha:1.0];
}

static UIColor *PPAccountingSurfaceColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondarySystemGroupedBackgroundColor;
    return UIColor.whiteColor;
}

static UIColor *PPAccountingInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.labelColor;
    return UIColor.blackColor;
}

static UIColor *PPAccountingSubInkColor(void) {
    if (@available(iOS 13.0, *)) return UIColor.secondaryLabelColor;
    return [UIColor colorWithWhite:0.40 alpha:1.0];
}

static void PPAccountingApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    view.layer.shadowRadius = 22.0;
    view.layer.shadowOpacity = 0.052;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.62].CGColor;
}

static NSString *PPAccountingMoneyString(double amount) {
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 2;
    formatter.maximumFractionDigits = 2;
    NSString *value = [formatter stringFromNumber:@(amount)] ?: [NSString stringWithFormat:@"%.2f", amount];
    return [NSString stringWithFormat:@"%@ %@", value, kLang(@"Accounting_QAR")];
}

static NSString *PPAccountingDateString(NSDate *date) {
    if (!date) return @"-";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

@interface PPAccountingMetricCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)configureTitle:(NSString *)title value:(NSString *)value subtitle:(NSString *)subtitle symbol:(NSString *)symbol tint:(UIColor *)tint;
@end

@implementation PPAccountingMetricCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPAccountingSurfaceColor();
        PPAccountingApplyCardChrome(_cardView, 22.0);
        [self.contentView addSubview:_cardView];

        _symbolView = [UIImageView new];
        _symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        _symbolView.contentMode = UIViewContentModeCenter;
        _symbolView.layer.cornerRadius = 18.0;
        if (@available(iOS 13.0, *)) _symbolView.layer.cornerCurve = kCACornerCurveContinuous;
        [_cardView addSubview:_symbolView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontMedium:12];
        _titleLabel.textColor = PPAccountingSubInkColor();
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_titleLabel];

        _valueLabel = [UILabel new];
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _valueLabel.font = [Styling fontBold:23];
        _valueLabel.textColor = PPAccountingInkColor();
        _valueLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.68;
        [_cardView addSubview:_valueLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:12];
        _subtitleLabel.textColor = PPAccountingSubInkColor();
        _subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

            [_symbolView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_symbolView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_symbolView.widthAnchor constraintEqualToConstant:48.0],
            [_symbolView.heightAnchor constraintEqualToConstant:48.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_symbolView.trailingAnchor constant:15.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:15.0],

            [_valueLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_valueLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_valueLabel.bottomAnchor constant:4.0],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)configureTitle:(NSString *)title value:(NSString *)value subtitle:(NSString *)subtitle symbol:(NSString *)symbol tint:(UIColor *)tint {
    UIColor *safeTint = tint ?: PPAccountingAccentColor();
    self.titleLabel.text = title;
    self.valueLabel.text = value;
    self.subtitleLabel.text = subtitle;
    self.symbolView.image = [UIImage systemImageNamed:symbol ?: @"circle.fill"];
    self.symbolView.tintColor = safeTint;
    self.symbolView.backgroundColor = [safeTint colorWithAlphaComponent:0.11];
}

@end

@interface PPAccountingEntryCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *amountLabel;
- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle amount:(NSString *)amount tint:(UIColor *)tint;
@end

@implementation PPAccountingEntryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [UIView new];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = PPAccountingSurfaceColor();
        PPAccountingApplyCardChrome(_cardView, 18.0);
        [self.contentView addSubview:_cardView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontBold:15];
        _titleLabel.textColor = PPAccountingInkColor();
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _titleLabel.numberOfLines = 2;
        [_cardView addSubview:_titleLabel];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:12];
        _subtitleLabel.textColor = PPAccountingSubInkColor();
        _subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        [_cardView addSubview:_subtitleLabel];

        _amountLabel = [UILabel new];
        _amountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _amountLabel.font = [Styling fontBold:15];
        _amountLabel.textAlignment = NSTextAlignmentCenter;
        _amountLabel.layer.cornerRadius = 14.0;
        _amountLabel.layer.masksToBounds = YES;
        _amountLabel.adjustsFontSizeToFitWidth = YES;
        _amountLabel.minimumScaleFactor = 0.70;
        [_cardView addSubview:_amountLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],

            [_amountLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-16.0],
            [_amountLabel.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_amountLabel.widthAnchor constraintGreaterThanOrEqualToConstant:96.0],
            [_amountLabel.heightAnchor constraintEqualToConstant:30.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:16.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_amountLabel.leadingAnchor constant:-12.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:14.0],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:5.0],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle amount:(NSString *)amount tint:(UIColor *)tint {
    UIColor *safeTint = tint ?: PPAccountingAccentColor();
    self.titleLabel.text = title.length ? title : @"-";
    self.subtitleLabel.text = subtitle.length ? subtitle : @"-";
    self.amountLabel.text = amount.length ? amount : @"-";
    self.amountLabel.textColor = safeTint;
    self.amountLabel.backgroundColor = [safeTint colorWithAlphaComponent:0.10];
}

@end

@interface PPAccountingExpenseFormViewController : UIViewController
@property (nonatomic, strong) PPFormEngineView *formView;
@property (nonatomic, copy) NSString *selectedCategory;
@property (nonatomic, copy) void (^saveHandler)(double amount, NSString *category, NSString *desc, PPAccountingExpenseFormViewController *controller);
@end

@implementation PPAccountingExpenseFormViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Accounting_AddExpense");
    self.selectedCategory = @"other";
    self.view.backgroundColor = PPAccountingCanvasColor();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Cancel") style:UIBarButtonItemStylePlain target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:kLang(@"Save") style:UIBarButtonItemStyleDone target:self action:@selector(saveTapped)];
    [self pp_buildForm];
}

- (void)pp_buildForm {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18.0;
    [scroll addSubview:stack];

    UIView *heroCard = [UIView new];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:heroCard];
    [heroCard.heightAnchor constraintGreaterThanOrEqualToConstant:138.0].active = YES;

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.68;
    hero.accentColorOverride = UIColor.systemRedColor;
    [heroCard addSubview:hero];
    [hero startAnimations];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = kLang(@"Accounting_AddExpense");
    title.font = [Styling fontBold:25];
    title.textColor = PPAccountingInkColor();
    title.textAlignment = [Language alignmentForCurrentLanguage];
    [heroCard addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = kLang(@"Accounting_AddExpenseSubtitle");
    subtitle.font = [Styling fontRegular:13];
    subtitle.textColor = PPAccountingSubInkColor();
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.numberOfLines = 2;
    [heroCard addSubview:subtitle];

    PPFormStyle *style = [[PPFormStyle defaultStyle] copy];
    style.accentColor = PPAccountingAccentColor();
    style.cardBackgroundColor = PPAccountingSurfaceColor();
     style.primaryTextColor = PPAccountingInkColor();
    style.secondaryTextColor = PPAccountingSubInkColor();
    style.cardCornerRadius = 22.0;
    style.stackSpacing = 11.0;
    self.formView = [[PPFormEngineView alloc] initWithStyle:style];
    self.formView.validatesOnChange = YES;

    PPFormFieldConfig *amount = [PPFormFieldConfig fieldWithIdentifier:@"amount" title:kLang(@"Accounting_Amount") placeholder:kLang(@"Accounting_AmountPlaceholder") inputType:PPFormInputTypeText];
    amount.keyboardType = UIKeyboardTypeDecimalPad;
    amount.required = YES;

    PPFormFieldConfig *category = [PPFormFieldConfig fieldWithIdentifier:@"category" title:kLang(@"Accounting_Category") placeholder:kLang(@"Accounting_Category") inputType:PPFormInputTypePicker];
    category.value = kLang(@"Accounting_Cat_other");
    __weak typeof(self) weakSelf = self;
    category.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        (void)config; (void)row;
        [weakSelf showCategoryPicker];
    };

    PPFormFieldConfig *desc = [PPFormFieldConfig fieldWithIdentifier:@"description" title:kLang(@"Accounting_Description") placeholder:kLang(@"Accounting_DescriptionPlaceholder") inputType:PPFormInputTypeTextView];

    [self.formView setFields:@[amount, category, desc]];
    [stack addArrangedSubview:self.formView];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18.0],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28.0],

        [hero.topAnchor constraintEqualToAnchor:heroCard.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:heroCard.bottomAnchor],

        [title.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:26.0],
        [title.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:24.0],
        [title.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-24.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
    ]];
}

- (void)showCategoryPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Accounting_Category") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *categories = @[@"salary", @"rent", @"supplies", @"utilities", @"marketing", @"other"];
    for (NSString *cat in categories) {
        NSString *catKey = [NSString stringWithFormat:@"Accounting_Cat_%@", cat];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(catKey) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.selectedCategory = cat;
            [self.formView setValue:kLang(catKey) forIdentifier:@"category"];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.0, 1.0);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveTapped {
    if (![self.formView validate]) return;
    NSString *amountString = [self.formView valueForIdentifier:@"amount"];
    NSNumberFormatter *amountFormatter = [NSNumberFormatter new];
    amountFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    amountFormatter.locale = [NSLocale localeWithLocaleIdentifier:[Language currentLanguageCode] ?: @"en"];
    NSNumber *parsedAmount = [amountFormatter numberFromString:amountString ?: @""];
    double amount = parsedAmount ? parsedAmount.doubleValue : amountString.doubleValue;
    if (amount <= 0.0) {
        [self.formView setErrorText:kLang(@"Accounting_InvalidAmount") forIdentifier:@"amount"];
        return;
    }
    self.navigationItem.rightBarButtonItem.enabled = NO;
    if (self.saveHandler) {
        self.saveHandler(amount, self.selectedCategory ?: @"other", [self.formView valueForIdentifier:@"description"] ?: @"", self);
    }
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface PPAccountingViewController ()
@property (nonatomic, strong) PPAccountingService *service;
@property (nonatomic, strong) NSArray<id<FIRListenerRegistration>> *listeners;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *currentFilter;
@property (nonatomic, strong) UISegmentedControl *filterSegment;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) PPHero *heroBackground;
@property (nonatomic, strong) UILabel *heroProfitLabel;
@end

@implementation PPAccountingViewController

- (void)dealloc {
    for (id<FIRListenerRegistration> reg in self.listeners) {
        [reg remove];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"Accounting_Title");
    self.service = [PPAccountingService shared];
    self.listeners = @[];
    self.currentFilter = @"month";
    [self pp_configureTableView];
    [self pp_buildHeader];

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(didTapAddExpense)];
    self.navigationItem.rightBarButtonItem = addBtn;

    [self subscribeToData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroBackground startAnimations];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.heroBackground stopAnimations];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_updateInsets];
    [self pp_sizeHeaderToFit];
}

- (void)pp_configureTableView {
    self.view.backgroundColor = PPAccountingCanvasColor();
    self.tableView.backgroundColor = PPAccountingCanvasColor();
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 98.0;
    self.tableView.showsVerticalScrollIndicator = NO;
    [self.tableView registerClass:PPAccountingMetricCell.class forCellReuseIdentifier:@"MetricCell"];
    [self.tableView registerClass:PPAccountingEntryCell.class forCellReuseIdentifier:@"EntryCell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"StateCell"];
}

- (void)pp_buildHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.tableView.bounds), 1.0)];
    header.backgroundColor = UIColor.clearColor;
    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    [header addSubview:stack];

    UIView *heroCard = [UIView new];
    heroCard.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:heroCard];
    [heroCard.heightAnchor constraintGreaterThanOrEqualToConstant:158.0].active = YES;

    PPHero *hero = [PPHero new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.accentStyle = PPHeroGlassAccentStyleCornerGlow;
    hero.cornerGlowOpacityMultiplier = 0.70;
    hero.accentColorOverride = PPAccountingAccentColor();
    [heroCard addSubview:hero];
    self.heroBackground = hero;

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = kLang(@"Accounting_Title");
    title.font = [Styling fontBold:28];
    title.textColor = PPAccountingInkColor();
    title.textAlignment = [Language alignmentForCurrentLanguage];
    [heroCard addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = kLang(@"Accounting_Subtitle");
    subtitle.font = [Styling fontRegular:14];
    subtitle.textColor = PPAccountingSubInkColor();
    subtitle.textAlignment = [Language alignmentForCurrentLanguage];
    subtitle.numberOfLines = 2;
    [heroCard addSubview:subtitle];

    UILabel *profit = [UILabel new];
    profit.translatesAutoresizingMaskIntoConstraints = NO;
    profit.font = [Styling fontBold:13];
    profit.textAlignment = NSTextAlignmentCenter;
    profit.layer.cornerRadius = 17.0;
    profit.layer.masksToBounds = YES;
    profit.adjustsFontSizeToFitWidth = YES;
    profit.minimumScaleFactor = 0.70;
    [heroCard addSubview:profit];
    self.heroProfitLabel = profit;

    self.filterSegment = [[UISegmentedControl alloc] initWithItems:@[kLang(@"Accounting_ThisMonth"), kLang(@"Accounting_AllTime")]];
    self.filterSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterSegment.selectedSegmentIndex = 0;
    self.filterSegment.selectedSegmentTintColor = PPAccountingAccentColor();
    self.filterSegment.backgroundColor = [PPAccountingSurfaceColor() colorWithAlphaComponent:0.88];
    [self.filterSegment setTitleTextAttributes:@{NSFontAttributeName: [Styling fontMedium:13], NSForegroundColorAttributeName: PPAccountingInkColor()} forState:UIControlStateNormal];
    [self.filterSegment setTitleTextAttributes:@{NSFontAttributeName: [Styling fontBold:13], NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [self.filterSegment addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.filterSegment];
    [self.filterSegment.heightAnchor constraintEqualToConstant:48.0].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:18.0],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14.0],

        [hero.topAnchor constraintEqualToAnchor:heroCard.topAnchor],
        [hero.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor],
        [hero.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor],
        [hero.bottomAnchor constraintEqualToAnchor:heroCard.bottomAnchor],

        [profit.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:24.0],
        [profit.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-24.0],
        [profit.widthAnchor constraintGreaterThanOrEqualToConstant:112.0],
        [profit.heightAnchor constraintEqualToConstant:34.0],

        [title.leadingAnchor constraintEqualToAnchor:heroCard.leadingAnchor constant:24.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:profit.leadingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:heroCard.topAnchor constant:30.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:heroCard.trailingAnchor constant:-24.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10.0],
        [subtitle.bottomAnchor constraintLessThanOrEqualToAnchor:heroCard.bottomAnchor constant:-24.0],
    ]];

    self.headerContainer = header;
    self.tableView.tableHeaderView = header;
    [self pp_updateHeaderSummary];
}

- (void)pp_sizeHeaderToFit {
    if (!self.headerContainer) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0) return;
    CGRect frame = self.headerContainer.frame;
    frame.size.width = width;
    self.headerContainer.frame = frame;
    [self.headerContainer layoutIfNeeded];
    CGFloat height = [self.headerContainer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                         withHorizontalFittingPriority:UILayoutPriorityRequired
                                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    frame.size.height = ceil(MAX(1.0, height));
    self.headerContainer.frame = frame;
    self.tableView.tableHeaderView = self.headerContainer;
}

- (void)pp_updateInsets {
    CGFloat tabHeight = self.tabBarController ? CGRectGetHeight(self.tabBarController.tabBar.bounds) : 0.0;
    UIEdgeInsets inset = self.tableView.contentInset;
    inset.bottom = MAX(28.0, tabHeight + 34.0);
    self.tableView.contentInset = inset;
    self.tableView.scrollIndicatorInsets = inset;
}

- (void)pp_updateHeaderSummary {
    double expenses = [self totalExpenses];
    double profit = self.service.orderRevenue - expenses;
    UIColor *color = profit >= 0 ? UIColor.systemGreenColor : UIColor.systemRedColor;
    self.heroProfitLabel.text = PPAccountingMoneyString(profit);
    self.heroProfitLabel.textColor = color;
    self.heroProfitLabel.backgroundColor = [color colorWithAlphaComponent:0.11];
}

- (void)filterChanged:(UISegmentedControl *)sender {
    self.currentFilter = sender.selectedSegmentIndex == 0 ? @"month" : @"all";
    [self subscribeToData];
}

- (void)subscribeToData {
    for (id<FIRListenerRegistration> reg in self.listeners) { [reg remove]; }
    self.isLoading = YES;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    id<FIRListenerRegistration> txnReg = [self.service subscribeTransactionsWithFilter:self.currentFilter callback:^{
        [weakSelf dataUpdated];
    }];
    id<FIRListenerRegistration> expReg = [self.service subscribeExpensesWithFilter:self.currentFilter callback:^{
        [weakSelf dataUpdated];
    }];
    id<FIRListenerRegistration> revReg = [self.service subscribeOrderRevenueWithFilter:self.currentFilter callback:^{
        [weakSelf dataUpdated];
    }];
    self.listeners = @[txnReg, expReg, revReg];
}

- (void)dataUpdated {
    self.isLoading = NO;
    [self pp_updateHeaderSummary];
    [self.tableView reloadData];
}

- (double)totalExpenses {
    double expenses = 0;
    for (PPAccountingExpense *e in self.service.expenses) { expenses += e.amount; }
    return expenses;
}

- (void)didTapAddExpense {
    PPAccountingExpenseFormViewController *form = [PPAccountingExpenseFormViewController new];
    __weak typeof(self) weakSelf = self;
    form.saveHandler = ^(double amount, NSString *category, NSString *desc, PPAccountingExpenseFormViewController *controller) {
        [weakSelf.service addExpense:amount category:category description:desc completion:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                controller.navigationItem.rightBarButtonItem.enabled = YES;
                if (error) {
                    [AlertHelper showAlertIn:controller title:kLang(@"Error_Title") subtitle:error.localizedDescription];
                } else {
                    [PPFunc pp_playSuccessEffect];
                    [controller dismissViewControllerAnimated:YES completion:nil];
                }
            });
        }];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:form];
    if (@available(iOS 13.0, *)) {
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return MAX(self.service.transactions.count, 1);
    return MAX(self.service.expenses.count, 1);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 42.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view = [UIView new];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [Styling fontBold:18];
    label.textColor = PPAccountingInkColor();
    label.textAlignment = [Language alignmentForCurrentLanguage];
    if (section == 0) label.text = kLang(@"Accounting_Overview");
    else if (section == 1) label.text = kLang(@"Accounting_Transactions");
    else label.text = kLang(@"Accounting_Expenses");
    [view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:22.0],
        [label.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-22.0],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-6.0]
    ]];
    return view;
}

- (UITableViewCell *)pp_stateCellWithText:(NSString *)text {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"StateCell"];
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = text;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = PPAccountingSubInkColor();
    cell.textLabel.font = [Styling fontMedium:15];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        PPAccountingMetricCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MetricCell" forIndexPath:indexPath];
        double revenue = self.service.orderRevenue;
        double expenses = [self totalExpenses];
        double profit = revenue - expenses;
        if (indexPath.row == 0) {
            NSString *subtitle = [NSString stringWithFormat:kLang(@"Accounting_OrdersCount_Format"), @(self.service.orderCount)];
            [cell configureTitle:kLang(@"Accounting_Revenue") value:PPAccountingMoneyString(revenue) subtitle:subtitle symbol:@"arrow.up.circle.fill" tint:UIColor.systemGreenColor];
        } else if (indexPath.row == 1) {
            NSString *subtitle = [NSString stringWithFormat:kLang(@"Accounting_ExpensesCount_Format"), @(self.service.expenses.count)];
            [cell configureTitle:kLang(@"Accounting_Expenses") value:PPAccountingMoneyString(expenses) subtitle:subtitle symbol:@"arrow.down.circle.fill" tint:UIColor.systemRedColor];
        } else {
            [cell configureTitle:kLang(@"Accounting_Profit") value:PPAccountingMoneyString(profit) subtitle:kLang(@"Accounting_ProfitSubtitle") symbol:@"dollarsign.circle.fill" tint:(profit >= 0 ? UIColor.systemGreenColor : UIColor.systemRedColor)];
        }
        return cell;
    }

    if (indexPath.section == 1) {
        if (self.service.transactions.count == 0) return [self pp_stateCellWithText:self.isLoading ? kLang(@"Loading") : kLang(@"Accounting_NoTransactions")];
        PPAccountingTransaction *txn = self.service.transactions[indexPath.row];
        PPAccountingEntryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"EntryCell" forIndexPath:indexPath];
        NSString *title = txn.desc.length > 0 ? txn.desc : [NSString stringWithFormat:@"%@ #%@", kLang(@"Accounting_Transaction"), txn.txnID];
        [cell configureTitle:title subtitle:PPAccountingDateString(txn.createdAt) amount:PPAccountingMoneyString(txn.amount) tint:UIColor.systemGreenColor];
        return cell;
    }

    if (self.service.expenses.count == 0) return [self pp_stateCellWithText:self.isLoading ? kLang(@"Loading") : kLang(@"Accounting_NoExpenses")];
    PPAccountingExpense *exp = self.service.expenses[indexPath.row];
    PPAccountingEntryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"EntryCell" forIndexPath:indexPath];
    NSString *catKey = [NSString stringWithFormat:@"Accounting_Cat_%@", exp.category.length ? exp.category : @"other"];
    NSString *title = exp.desc.length ? exp.desc : kLang(catKey);
    [cell configureTitle:title subtitle:[NSString stringWithFormat:@"%@ - %@", kLang(catKey), PPAccountingDateString(exp.createdAt)] amount:PPAccountingMoneyString(exp.amount) tint:UIColor.systemRedColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeTranslation(0.0, 18.0);
    [UIView animateWithDuration:0.42 delay:MIN(indexPath.row * 0.026, 0.20) usingSpringWithDamping:0.86 initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
        cell.alpha = 1.0;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
