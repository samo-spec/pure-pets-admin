#import "PPPOSFastSellViewController.h"
#import "PPPOSService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

// Canonical official seller identity from Pure Pets Infra seed/migration contracts.
static NSString * const kPPPOSOfficialOwnerID = @"PUIDPOFFICILAL20262214";
static NSInteger const kPPPOSSearchFieldTag = 6101;

// Warm till surface (warm settle language carried from the Command Bar).
static UIColor *PPFastSellWarmIvory(void) {
    return [UIColor ppSurfaceOverlay];
}

// Gold ops signal for count chip and in-cart badges.
static UIColor *PPFastSellOpsGold(void) {
    return [UIColor ppPremiumAccent];
}

// Gold hairline for the till edge.
static UIColor *PPFastSellGoldHairline(void) {
    return [[UIColor ppPremiumAccent] colorWithAlphaComponent:0.55];
}

static BOOL PPFastSellAccessibilitySize(UITraitCollection *traits) {
    return UIContentSizeCategoryIsAccessibilityCategory(traits.preferredContentSizeCategory);
}

@interface PPPOSFastSellViewController ()
@property (nonatomic, strong) NSMutableArray<PPPOSCartItem *> *cart;
@property (nonatomic, copy) NSArray<PetAccessory *> *catalog;
@property (nonatomic, copy) NSArray<PetAccessory *> *filteredCatalog;
@property (nonatomic, copy, nullable) NSString *catalogErrorMessage;
@property (nonatomic, assign) BOOL isLoadingCatalog;
@property (nonatomic, strong) UILabel *checkoutTotalLabel;
@property (nonatomic, strong) UIButton *checkoutButton;
@property (nonatomic, strong) UIBarButtonItem *clearButton;
@property (nonatomic, weak) UITextField *searchField;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, strong) UILabel *countChip;
@end

@implementation PPPOSFastSellViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"POS_Title");
    self.cart = [NSMutableArray array];
    self.catalog = @[];
    self.filteredCatalog = @[];
    self.view.backgroundColor = AppBackgroundClr;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 92.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    self.clearButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"trash"] style:UIBarButtonItemStylePlain target:self action:@selector(didTapClear)];
    self.clearButton.accessibilityLabel = kLang(@"POS_Clear");
    self.navigationItem.leftBarButtonItem = self.clearButton;
    PPCommandCenterNavigationItemsDidChange(self);

    [self buildCheckoutDock];
    [self buildSearchHeader];
    [self refreshCartPresentation];
    [self loadCatalog];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = UIEdgeInsetsMake(PPSpaceBase, 0.0, CGRectGetHeight(self.checkoutButton.superview.bounds) + PPSpaceLG, 0.0);
    if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.contentInset, insets)) {
        self.tableView.contentInset = insets;
        self.tableView.scrollIndicatorInsets = insets;
    }
}

#pragma mark - Catalog

- (void)loadCatalog {
    self.isLoadingCatalog = YES;
    self.catalogErrorMessage = nil;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[AccessoryManager shared] fetchAccessoriesForOwnerID:kPPPOSOfficialOwnerID completion:^(NSArray<PetAccessory *> *items, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.isLoadingCatalog = NO;
            self.catalogErrorMessage = error.localizedDescription;
            self.catalog = error ? @[] : (items ?: @[]);
            [self applyCatalogFilter];
        });
    }];
}

- (void)applyCatalogFilter {
    NSString *query = [self.searchField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (query.length == 0) {
        self.filteredCatalog = self.catalog;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PetAccessory *item, NSDictionary *bindings) {
            return [item.name rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
                   [item.searchTitle rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
                   [item.accessoryID rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
        }];
        self.filteredCatalog = [self.catalog filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

- (BOOL)isSellableAccessory:(PetAccessory *)accessory {
    return accessory.active && !accessory.noStock && accessory.quantity > 0 &&
           !accessory.isBlocked && !accessory.isDeleted && !accessory.isDisabled;
}

- (PetAccessory *)accessoryForID:(NSString *)accessoryID {
    if (accessoryID.length == 0) return nil;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"accessoryID == %@", accessoryID];
    return [self.catalog filteredArrayUsingPredicate:predicate].firstObject;
}

- (NSInteger)quantityInCartForAccessoryID:(NSString *)accessoryID {
    NSInteger quantity = 0;
    for (PPPOSCartItem *item in self.cart) {
        if ([item.itemID isEqualToString:accessoryID]) quantity += item.quantity;
    }
    return quantity;
}

- (void)didChangeSearch:(UITextField *)textField {
    [self applyCatalogFilter];
}

- (void)didTapScan {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"POS_ScanCode") message:kLang(@"POS_ScanCodeHint") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = kLang(@"POS_ScanCodePlaceholder");
        field.keyboardType = UIKeyboardTypeASCIICapable;
        field.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"POS_Scan") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *code = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        weakSelf.searchField.text = code;
        [weakSelf applyCatalogFilter];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Cart

- (void)didTapClear {
    [self.cart removeAllObjects];
    [self refreshCartPresentation];
}

- (void)addAccessoryToCart:(PetAccessory *)accessory {
    if (![self isSellableAccessory:accessory]) {
        [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"POS_ItemUnavailable")];
        return;
    }

    PPPOSCartItem *existingItem = nil;
    for (PPPOSCartItem *item in self.cart) {
        if ([item.itemID isEqualToString:accessory.accessoryID]) {
            existingItem = item;
            break;
        }
    }
    if (existingItem) {
        if (existingItem.quantity >= accessory.quantity) {
            [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"POS_StockLimitReached")];
            return;
        }
        existingItem.quantity += 1;
    } else {
        PPPOSCartItem *item = [PPPOSCartItem new];
        item.itemID = accessory.accessoryID;
        item.name = accessory.name;
        item.price = accessory.finalPrice.doubleValue;
        item.quantity = 1;
        [self.cart addObject:item];
    }
    [self refreshCartPresentation];
    [PPFunc pp_playTapEffect];
}

- (void)didTapCatalogItem:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.filteredCatalog.count) return;
    [self addAccessoryToCart:self.filteredCatalog[index]];
}

- (void)didTapStepperMinus:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.cart.count) return;
    PPPOSCartItem *item = self.cart[index];
    if (item.quantity > 1) {
        item.quantity -= 1;
    } else {
        [self.cart removeObjectAtIndex:index];
    }
    [PPFunc pp_playTapEffect];
    [self refreshCartPresentation];
}

- (void)didTapStepperPlus:(UIButton *)sender {
    NSInteger index = sender.tag;
    if (index < 0 || index >= self.cart.count) return;
    PPPOSCartItem *item = self.cart[index];
    PetAccessory *accessory = [self accessoryForID:item.itemID];
    if (accessory) {
        if (item.quantity >= accessory.quantity) {
            [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"POS_StockLimitReached")];
            return;
        }
    }
    item.quantity += 1;
    [PPFunc pp_playTapEffect];
    [self refreshCartPresentation];
}

- (void)removeCartItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= self.cart.count) return;
    [self.cart removeObjectAtIndex:index];
    [self refreshCartPresentation];
}

- (void)didTapCheckout {
    if (self.cart.count == 0) {
        [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"POS_EmptyCart")];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"POS_Checkout") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"POS_Cash") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self submitOrder:@"cash"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"POS_Card") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self submitOrder:@"card"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)submitOrder:(NSString *)method {
    NSMutableArray *itemsPayload = [NSMutableArray array];
    double total = 0;
    for (PPPOSCartItem *item in self.cart) {
        [itemsPayload addObject:@{
            @"itemId": item.itemID,
            @"name": item.name,
            @"price": @(item.price),
            @"quantity": @(item.quantity)
        }];
        total += item.price * item.quantity;
    }

    [[PPPOSService shared] submitPOSOrderWithItems:itemsPayload total:total paymentMethod:method completion:^(NSString *orderID, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                [PPFunc pp_playSuccessEffect];
                [self stampSaleWithOrderID:orderID];
            }
        });
    }];
}

#pragma mark - Presentation

- (void)buildCheckoutDock {
    UIView *dock = [UIView new];
    dock.translatesAutoresizingMaskIntoConstraints = NO;
    dock.backgroundColor = PPFastSellWarmIvory();
    dock.layer.cornerRadius = PPCornerCard;
    dock.layer.cornerCurve = kCACornerCurveContinuous;
    dock.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    dock.layer.borderColor = PPFastSellGoldHairline().CGColor;
    dock.layer.shadowColor = UIColor.blackColor.CGColor;
    dock.layer.shadowOpacity = PPShadowSubtleOpacity;
    dock.layer.shadowRadius = PPShadowCardRadius;
    dock.layer.shadowOffset = CGSizeMake(0.0, PPShadowCardOffsetY);
    dock.accessibilityIdentifier = @"FastSellDock";
    [self.view addSubview:dock];

    UILabel *captionLabel = [UILabel new];
    captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    captionLabel.text = kLang(@"POS_Total");
    captionLabel.textColor = SeconderyTextClr;
    captionLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:13.0]];
    captionLabel.adjustsFontForContentSizeCategory = YES;

    self.checkoutTotalLabel = [UILabel new];
    self.checkoutTotalLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.checkoutTotalLabel.textColor = AppPrimaryClr;
    self.checkoutTotalLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:21.0]];
    self.checkoutTotalLabel.adjustsFontForContentSizeCategory = YES;
    self.checkoutTotalLabel.textAlignment = [Language alignmentForCurrentLanguage];

    UILabel *countChip = [UILabel new];
    countChip.translatesAutoresizingMaskIntoConstraints = NO;
    countChip.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:12.0]];
    countChip.adjustsFontForContentSizeCategory = YES;
    countChip.textColor = PPFastSellOpsGold();
    countChip.backgroundColor = [PPFastSellOpsGold() colorWithAlphaComponent:0.14];
    countChip.layer.cornerRadius = 13.0;
    countChip.layer.masksToBounds = YES;
    countChip.textAlignment = NSTextAlignmentCenter;
    countChip.accessibilityIdentifier = @"FastSellCountChip";
    countChip.translatesAutoresizingMaskIntoConstraints = NO;
    self.countChip = countChip;
    [dock addSubview:countChip];

    self.checkoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.checkoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.checkoutButton.backgroundColor = PPPrimaryColor();
    self.checkoutButton.tintColor = UIColor.whiteColor;
    self.checkoutButton.layer.cornerRadius = PPCornerMedium;
    self.checkoutButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.checkoutButton.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:16.0]];
    self.checkoutButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.checkoutButton setTitle:kLang(@"POS_Checkout") forState:UIControlStateNormal];
    [self.checkoutButton setImage:[UIImage systemImageNamed:@"arrow.left.circle.fill"] forState:UIControlStateNormal];
    self.checkoutButton.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.checkoutButton.accessibilityHint = kLang(@"POS_CheckoutHint");
    [self.checkoutButton addTarget:self action:@selector(didTapCheckout) forControlEvents:UIControlEventTouchUpInside];

    [dock addSubview:captionLabel];
    [dock addSubview:self.checkoutTotalLabel];
    [dock addSubview:self.checkoutButton];
    [NSLayoutConstraint activateConstraints:@[
        [dock.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [dock.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [dock.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [dock.heightAnchor constraintGreaterThanOrEqualToConstant:84.0],

        [captionLabel.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:PPSpaceLG],
        [captionLabel.topAnchor constraintEqualToAnchor:dock.topAnchor constant:PPSpaceMD],

        [countChip.leadingAnchor constraintGreaterThanOrEqualToAnchor:captionLabel.trailingAnchor constant:PPSpaceMD],
        [countChip.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-PPSpaceLG],
        [countChip.centerYAnchor constraintEqualToAnchor:captionLabel.centerYAnchor],
        [countChip.heightAnchor constraintEqualToConstant:26.0],
        [countChip.widthAnchor constraintGreaterThanOrEqualToConstant:44.0],

        [self.checkoutTotalLabel.leadingAnchor constraintEqualToAnchor:captionLabel.leadingAnchor],
        [self.checkoutTotalLabel.topAnchor constraintEqualToAnchor:captionLabel.bottomAnchor constant:2.0],
        [self.checkoutTotalLabel.bottomAnchor constraintEqualToAnchor:dock.bottomAnchor constant:-PPSpaceMD],

        [self.checkoutButton.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-PPSpaceMD],
        [self.checkoutButton.bottomAnchor constraintEqualToAnchor:dock.bottomAnchor constant:-PPSpaceMD],
        [self.checkoutButton.widthAnchor constraintGreaterThanOrEqualToConstant:116.0],
        [self.checkoutButton.heightAnchor constraintEqualToConstant:PPButtonHeightMD],
    ]];
}

- (void)buildSearchHeader {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 76.0)];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIView *searchSurface = [UIView new];
    searchSurface.translatesAutoresizingMaskIntoConstraints = NO;
    searchSurface.backgroundColor = AppForgroundColr;
    searchSurface.layer.cornerRadius = PPCornerMedium;
    searchSurface.layer.cornerCurve = kCACornerCurveContinuous;
    searchSurface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    searchSurface.layer.borderColor = PPHairlineColor().CGColor;
    [header addSubview:searchSurface];

    UITextField *field = [UITextField new];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = kLang(@"POS_SearchPlaceholder");
    field.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:16.0]];
    field.adjustsFontForContentSizeCategory = YES;
    field.textColor = PrimaryTextClr;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    field.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    UIImageView *searchGlyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    searchGlyph.tintColor = SeconderyTextClr;
    searchGlyph.frame = CGRectMake(0.0, 0.0, 28.0, 20.0);
    searchGlyph.contentMode = UIViewContentModeScaleAspectFit;
    field.leftView = searchGlyph;
    field.leftViewMode = UITextFieldViewModeAlways;
    [field addTarget:self action:@selector(didChangeSearch:) forControlEvents:UIControlEventEditingChanged];
    [searchSurface addSubview:field];
    self.searchField = field;

    UIButton *scanButton = [UIButton buttonWithType:UIButtonTypeSystem];
    scanButton.translatesAutoresizingMaskIntoConstraints = NO;
    scanButton.backgroundColor = AppForgroundColr;
    scanButton.tintColor = AppPrimaryClr;
    scanButton.layer.cornerRadius = PPCornerMedium;
    scanButton.layer.cornerCurve = kCACornerCurveContinuous;
    scanButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    scanButton.layer.borderColor = PPHairlineColor().CGColor;
    [scanButton setImage:[UIImage systemImageNamed:@"barcode.viewfinder"] forState:UIControlStateNormal];
    scanButton.accessibilityLabel = kLang(@"POS_Scan");
    scanButton.accessibilityHint = kLang(@"POS_ScanCodeHint");
    [scanButton addTarget:self action:@selector(didTapScan) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:scanButton];

    [NSLayoutConstraint activateConstraints:@[
        [searchSurface.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [searchSurface.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceXS],
        [searchSurface.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceSM],
        [searchSurface.trailingAnchor constraintEqualToAnchor:scanButton.leadingAnchor constant:-PPSpaceSM],
        [field.leadingAnchor constraintEqualToAnchor:searchSurface.layoutMarginsGuide.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:searchSurface.layoutMarginsGuide.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:searchSurface.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:searchSurface.bottomAnchor],
        [scanButton.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [scanButton.centerYAnchor constraintEqualToAnchor:searchSurface.centerYAnchor],
        [scanButton.widthAnchor constraintEqualToConstant:PPButtonHeightLG],
        [scanButton.heightAnchor constraintEqualToConstant:PPButtonHeightLG],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)refreshCartPresentation {
    double total = 0.0;
    NSInteger count = 0;
    for (PPPOSCartItem *item in self.cart) {
        total += item.price * item.quantity;
        count += item.quantity;
    }
    self.checkoutTotalLabel.text = [NSString stringWithFormat:@"%.2f %@", total, kLang(@"Accounting_QAR")];
    self.checkoutTotalLabel.textColor = AppPrimaryClr;
    self.checkoutButton.enabled = self.cart.count > 0;
    self.checkoutButton.alpha = self.checkoutButton.enabled ? 1.0 : 0.55;
    self.clearButton.enabled = self.cart.count > 0;
    self.countChip.text = [NSString stringWithFormat:kLang(@"POS_ItemsInCart"), (long)count];
    [self.tableView reloadData];
}

- (void)stampSaleWithOrderID:(NSString *)orderID {
    if (PPFastSellAccessibilitySize(self.traitCollection) || UIAccessibilityIsReduceMotionEnabled()) {
        self.checkoutTotalLabel.text = [NSString stringWithFormat:kLang(@"POS_OrderCreated"), orderID];
        [self.cart removeAllObjects];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf refreshCartPresentation];
        });
        return;
    }

    self.checkoutTotalLabel.text = [NSString stringWithFormat:@"✓ %@", [NSString stringWithFormat:kLang(@"POS_OrderCreated"), orderID]];
    self.checkoutTotalLabel.textColor = PPFastSellOpsGold();
    self.checkoutTotalLabel.transform = CGAffineTransformMakeScale(0.6, 0.6);
    [UIView animateWithDuration:0.45 delay:0.0
         usingSpringWithDamping:0.6 initialSpringVelocity:0.9
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.checkoutTotalLabel.transform = CGAffineTransformIdentity;
    } completion:nil];

    [self.cart removeAllObjects];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf refreshCartPresentation];
    });
}

- (UITableViewCell *)baseCardCellForTableView:(UITableView *)tableView identifier:(NSString *)identifier style:(UITableViewCellStyle)style {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = AppForgroundColr;
        cell.contentView.layer.cornerRadius = PPCornerMedium;
        cell.contentView.layer.cornerCurve = kCACornerCurveContinuous;
        cell.contentView.layer.masksToBounds = YES;
        cell.layoutMargins = UIEdgeInsetsMake(PPSpaceLG, PPSpaceLG, PPSpaceLG, PPSpaceLG);
        cell.textLabel.numberOfLines = 2;
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    }
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
    cell.detailTextLabel.textAlignment = [Language alignmentForCurrentLanguage];
    cell.textLabel.textColor = PrimaryTextClr;
    cell.detailTextLabel.textColor = SeconderyTextClr;
    cell.tintColor = AppPrimaryClr;
    return cell;
}

- (UIView *)stepperForCartItem:(PPPOSCartItem *)item indexPath:(NSIndexPath *)indexPath {
    UIView *container = [[UIView alloc] init];
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIButton *minus = [UIButton buttonWithType:UIButtonTypeSystem];
    minus.translatesAutoresizingMaskIntoConstraints = NO;
    minus.tag = indexPath.row;
    minus.backgroundColor = [PPFastSellOpsGold() colorWithAlphaComponent:0.10];
    minus.tintColor = PPFastSellOpsGold();
    minus.layer.cornerRadius = 12.0;
    [minus setImage:[UIImage systemImageNamed:@"minus"] forState:UIControlStateNormal];
    minus.accessibilityLabel = [NSString stringWithFormat:@"%@، %@", kLang(@"POS_RemoveOne"), item.name];
    [minus addTarget:self action:@selector(didTapStepperMinus:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:minus];

    UILabel *qty = [UILabel new];
    qty.translatesAutoresizingMaskIntoConstraints = NO;
    qty.text = [NSString stringWithFormat:@"%ld", (long)item.quantity];
    qty.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:14.0]];
    qty.adjustsFontForContentSizeCategory = YES;
    qty.textColor = PrimaryTextClr;
    qty.textAlignment = NSTextAlignmentCenter;
    qty.accessibilityLabel = [NSString stringWithFormat:@"%@: %ld", kLang(@"POS_ItemQty"), (long)item.quantity];
    [container addSubview:qty];

    UIButton *plus = [UIButton buttonWithType:UIButtonTypeSystem];
    plus.translatesAutoresizingMaskIntoConstraints = NO;
    plus.tag = indexPath.row;
    plus.backgroundColor = PPPrimaryColor();
    plus.tintColor = UIColor.whiteColor;
    plus.layer.cornerRadius = 12.0;
    [plus setImage:[UIImage systemImageNamed:@"plus"] forState:UIControlStateNormal];
    plus.accessibilityLabel = [NSString stringWithFormat:@"%@، %@", kLang(@"POS_AddOne"), item.name];
    [plus addTarget:self action:@selector(didTapStepperPlus:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:plus];

    [NSLayoutConstraint activateConstraints:@[
        [minus.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [minus.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [minus.widthAnchor constraintEqualToConstant:36.0],
        [minus.heightAnchor constraintEqualToConstant:44.0],

        [qty.leadingAnchor constraintEqualToAnchor:minus.trailingAnchor],
        [qty.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [qty.widthAnchor constraintEqualToConstant:30.0],

        [plus.leadingAnchor constraintEqualToAnchor:qty.trailingAnchor],
        [plus.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [plus.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [plus.widthAnchor constraintEqualToConstant:36.0],
        [plus.heightAnchor constraintEqualToConstant:44.0],
    ]];
    return container;
}

- (UIButton *)catalogButtonForAccessory:(PetAccessory *)accessory index:(NSInteger)index {
    BOOL sellable = [self isSellableAccessory:accessory];
    NSInteger inCart = [self quantityInCartForAccessoryID:accessory.accessoryID];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = index;
    button.backgroundColor = AppForgroundColr;
    button.layer.cornerRadius = PPCornerMedium;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    button.layer.borderColor = inCart > 0 ? PPFastSellGoldHairline().CGColor : PPHairlineColor().CGColor;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
    button.accessibilityLabel = inCart > 0
        ? [NSString stringWithFormat:@"%@, %@, %@", accessory.name, [self priceTextForAccessory:accessory sellable:sellable], [NSString stringWithFormat:kLang(@"POS_InCartBadge"), (long)inCart]]
        : [NSString stringWithFormat:@"%@, %@", accessory.name, [self priceTextForAccessory:accessory sellable:sellable]];
    button.accessibilityHint = sellable ? kLang(@"POS_AddToCartHint") : kLang(@"POS_ItemUnavailable");
    button.enabled = sellable;
    button.alpha = sellable ? 1.0 : 0.52;
    [button addTarget:self action:@selector(didTapCatalogItem:) forControlEvents:UIControlEventTouchUpInside];

    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.12];
    tile.layer.cornerRadius = PPCornerSmall;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.layer.masksToBounds = YES;
    [button addSubview:tile];

    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:sellable ? @"bag.badge.plus" : @"cart.badge.minus"]];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    glyph.tintColor = sellable ? AppPrimaryClr : SeconderyTextClr;
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    [tile addSubview:glyph];

    NSURL *firstImage = [PetAccessory firstImageURLForAccessory:accessory];
    UIImageView *photo = nil;
    if (firstImage) {
        photo = [[UIImageView alloc] init];
        photo.translatesAutoresizingMaskIntoConstraints = NO;
        photo.contentMode = UIViewContentModeScaleAspectFill;
        photo.clipsToBounds = YES;
        [tile addSubview:photo];
        __weak typeof(self) weakSelf = self;
        [photo setImageFromUrl:firstImage.absoluteString completion:^(UIImage *image) {
            if (!image) {
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                glyph.image = [UIImage systemImageNamed:sellable ? @"bag.badge.plus" : @"cart.badge.minus"];
                glyph.tintColor = sellable ? AppPrimaryClr : SeconderyTextClr;
            }
        }];
    }

    UILabel *badge = nil;
    if (inCart > 0) {
        badge = [UILabel new];
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        badge.text = [NSString stringWithFormat:kLang(@"POS_InCartBadge"), (long)inCart];
        badge.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:11.0]];
        badge.adjustsFontForContentSizeCategory = YES;
        badge.textColor = [UIColor whiteColor];
        badge.backgroundColor = PPPrimaryColor();
        badge.layer.cornerRadius = 9.0;
        badge.layer.masksToBounds = YES;
        badge.textAlignment = NSTextAlignmentCenter;
        badge.accessibilityIdentifier = @"FastSellInCartBadge";
        [button addSubview:badge];
    }

    UILabel *name = [UILabel new];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.text = accessory.name;
    name.textColor = PrimaryTextClr;
    name.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:14.0]];
    name.adjustsFontForContentSizeCategory = YES;
    name.numberOfLines = 2;
    name.textAlignment = [Language alignmentForCurrentLanguage];

    UILabel *price = [UILabel new];
    price.translatesAutoresizingMaskIntoConstraints = NO;
    price.text = [self priceTextForAccessory:accessory sellable:sellable];
    price.textColor = sellable ? AppPrimaryClr : SeconderyTextClr;
    price.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:13.0]];
    price.adjustsFontForContentSizeCategory = YES;
    price.textAlignment = [Language alignmentForCurrentLanguage];

    [button addSubview:name];
    [button addSubview:price];
    [NSLayoutConstraint activateConstraints:@[
        [tile.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:PPSpaceMD],
        [tile.topAnchor constraintEqualToAnchor:button.topAnchor constant:PPSpaceMD],
        [tile.widthAnchor constraintEqualToConstant:40.0],
        [tile.heightAnchor constraintEqualToConstant:40.0],

        [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [glyph.widthAnchor constraintEqualToConstant:20.0],
        [glyph.heightAnchor constraintEqualToConstant:20.0],

        [name.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:PPSpaceMD],
        [name.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-PPSpaceMD],
        [name.topAnchor constraintEqualToAnchor:tile.bottomAnchor constant:PPSpaceSM],
        [price.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [price.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [price.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:PPSpaceXS],
        [price.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-PPSpaceMD],
    ]];
    if (photo) {
        [NSLayoutConstraint activateConstraints:@[
            [photo.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
            [photo.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
            [photo.topAnchor constraintEqualToAnchor:tile.topAnchor],
            [photo.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor],
        ]];
    }
    if (badge) {
        [NSLayoutConstraint activateConstraints:@[
            [badge.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-PPSpaceSM],
            [badge.topAnchor constraintEqualToAnchor:button.topAnchor constant:PPSpaceSM],
            [badge.heightAnchor constraintEqualToConstant:18.0],
            [badge.widthAnchor constraintGreaterThanOrEqualToConstant:36.0],
        ]];
    }
    return button;
}

- (NSString *)priceTextForAccessory:(PetAccessory *)accessory sellable:(BOOL)sellable {
    if (!sellable) return kLang(@"POS_ItemUnavailable");
    return [NSString stringWithFormat:@"%.2f %@", accessory.finalPrice.doubleValue, kLang(@"Accounting_QAR")];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(self.cart.count, 1);
    if (self.isLoadingCatalog || self.catalogErrorMessage.length || self.filteredCatalog.count == 0) return 1;
    return (self.filteredCatalog.count + 1) / 2;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 44.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *container = [UIView new];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = section == 0 ? kLang(@"POS_Cart") : kLang(@"POS_Catalog");
    label.textColor = PrimaryTextClr;
    label.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:18.0]];
    label.adjustsFontForContentSizeCategory = YES;
    label.textAlignment = [Language alignmentForCurrentLanguage];
    label.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    ]];
    return container;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if (self.cart.count == 0) {
            UITableViewCell *cell = [self baseCardCellForTableView:tableView identifier:@"EmptyCartCell" style:UITableViewCellStyleSubtitle];
            cell.textLabel.text = kLang(@"POS_CartEmpty");
            cell.detailTextLabel.text = kLang(@"POS_CartEmptyCompactHint");
            cell.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
            cell.detailTextLabel.textAlignment = [Language alignmentForCurrentLanguage];
            cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:16.0]];
            cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:13.0]];
            cell.textLabel.textColor = [UIColor ppTextSecondary];
            cell.imageView.image = [[UIImage systemImageNamed:@"bag"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        UITableViewCell *cell = [self baseCardCellForTableView:tableView identifier:@"CartCell" style:UITableViewCellStyleValue1];
        PPPOSCartItem *item = self.cart[indexPath.row];
        cell.textLabel.text = item.name;
        cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:16.0]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", item.price * item.quantity, kLang(@"Accounting_QAR")];
        cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:15.0]];
        cell.detailTextLabel.textColor = AppPrimaryClr;
        cell.imageView.image = [[UIImage systemImageNamed:@"bag.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [self stepperForCartItem:item indexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.isAccessibilityElement = NO;
        cell.accessibilityElements = @[cell.textLabel ?: [UIView new],
                                       cell.detailTextLabel ?: [UIView new],
                                       cell.accessoryView ?: [UIView new]];
        NSInteger itemIndex = indexPath.row;
        __weak typeof(self) weakSelf = self;
        UIAccessibilityCustomAction *removeAction =
            [[UIAccessibilityCustomAction alloc] initWithName:kLang(@"POS_RemoveFromCart")
                                                actionHandler:^BOOL(UIAccessibilityCustomAction * _Nonnull action) {
                [weakSelf removeCartItemAtIndex:itemIndex];
                return YES;
            }];
        cell.accessibilityCustomActions = @[removeAction];
        return cell;
    }

    if (self.isLoadingCatalog || self.catalogErrorMessage.length || self.filteredCatalog.count == 0) {
        UITableViewCell *cell = [self baseCardCellForTableView:tableView identifier:@"CatalogStateCell" style:UITableViewCellStyleSubtitle];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;

        [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [self configureCatalogStateCell:cell];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CatalogGridCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CatalogGridCell"];
        cell.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSInteger firstIndex = indexPath.row * 2;
    UIButton *first = [self catalogButtonForAccessory:self.filteredCatalog[firstIndex] index:firstIndex];
    [cell.contentView addSubview:first];
    UIButton *second = nil;
    if (firstIndex + 1 < self.filteredCatalog.count) {
        second = [self catalogButtonForAccessory:self.filteredCatalog[firstIndex + 1] index:firstIndex + 1];
        [cell.contentView addSubview:second];
    }
    [NSLayoutConstraint activateConstraints:@[
        [first.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [first.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceXS],
        [first.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-PPSpaceXS],
        second ? [first.trailingAnchor constraintEqualToAnchor:second.leadingAnchor constant:-PPSpaceSM] : [first.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        second ? [first.widthAnchor constraintEqualToAnchor:second.widthAnchor] : [first.widthAnchor constraintGreaterThanOrEqualToConstant:0.0],
    ]];
    if (second) {
        [NSLayoutConstraint activateConstraints:@[
            [second.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [second.topAnchor constraintEqualToAnchor:first.topAnchor],
            [second.bottomAnchor constraintEqualToAnchor:first.bottomAnchor],
        ]];
    }
    return cell;
}

- (void)configureCatalogStateCell:(UITableViewCell *)cell {
    if (self.isLoadingCatalog) {
        cell.textLabel.text = kLang(@"Loading");
        cell.textLabel.textColor = SeconderyTextClr;
        cell.detailTextLabel.text = @"";
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = AppPrimaryClr;
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [spinner startAnimating];
        [cell.contentView addSubview:spinner];
        [NSLayoutConstraint activateConstraints:@[
            [spinner.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
            [spinner.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD],
        ]];
        return;
    }

    if (self.catalogErrorMessage.length) {
        cell.textLabel.text = kLang(@"Error_Title");
        cell.textLabel.textColor = [UIColor ppError];
        cell.detailTextLabel.text = self.catalogErrorMessage;
        cell.detailTextLabel.textColor = SeconderyTextClr;
        cell.detailTextLabel.numberOfLines = 3;

        UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
        retry.translatesAutoresizingMaskIntoConstraints = NO;
        retry.backgroundColor = AppPrimaryClr;
        retry.tintColor = UIColor.whiteColor;
        retry.layer.cornerRadius = PPCornerMedium;
        retry.layer.cornerCurve = kCACornerCurveContinuous;
        retry.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:15.0]];
        retry.titleLabel.adjustsFontForContentSizeCategory = YES;
        [retry setTitle:kLang(@"TryAgain") forState:UIControlStateNormal];
        [retry addTarget:self action:@selector(didTapRetryCatalog) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:retry];

        [NSLayoutConstraint activateConstraints:@[
            [retry.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
            [retry.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD],
            [retry.heightAnchor constraintEqualToConstant:44.0],
            [retry.widthAnchor constraintGreaterThanOrEqualToConstant:120.0],
        ]];
        return;
    }

    cell.textLabel.text = kLang(@"POS_CatalogEmpty");
    cell.textLabel.textColor = SeconderyTextClr;
    cell.detailTextLabel.text = kLang(@"POS_CatalogEmptyHint");
    cell.detailTextLabel.textColor = SeconderyTextClr;
}

- (void)didTapRetryCatalog {
    [self loadCatalog];
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL ax = PPFastSellAccessibilitySize(self.traitCollection);
    if (indexPath.section == 0) {
        if (self.cart.count == 0) return ax ? 104.0 : 78.0;
        return ax ? 100.0 : 72.0;
    }
    if (self.isLoadingCatalog) return 104.0;
    if (self.catalogErrorMessage.length) return 150.0;
    if (self.filteredCatalog.count == 0) return 104.0;
    return ax ? 176.0 : 136.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == 2 ? PPSpaceXXL : PPSpaceLG;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 0 || self.cart.count == 0) return;
    [self.cart removeObjectAtIndex:indexPath.row];
    [self refreshCartPresentation];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return kLang(@"Delete");
}

#pragma mark - Entrance Animation

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self runEntranceIfNeeded];
}

- (void)runEntranceIfNeeded {
    if (self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;

    if (UIAccessibilityIsReduceMotionEnabled()) return;

    UIView *dock = self.checkoutButton.superview;
    UIView *header = self.tableView.tableHeaderView;
    dock.alpha = 0.0;
    dock.transform = CGAffineTransformMakeTranslation(0, 16);
    header.alpha = 0.0;
    header.transform = CGAffineTransformMakeTranslation(0, 10);

    [UIView animateWithDuration:0.4 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        dock.alpha = 1.0;
        dock.transform = CGAffineTransformIdentity;
        header.alpha = 1.0;
        header.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end
