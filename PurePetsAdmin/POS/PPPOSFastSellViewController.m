#import "PPPOSFastSellViewController.h"
#import "PPPOSService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

// Canonical official seller identity from Pure Pets Infra seed/migration contracts.
static NSString * const kPPPOSOfficialOwnerID = @"PUIDPOFFICILAL20262214";
static NSInteger const kPPPOSSearchFieldTag = 6101;

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
                [self.cart removeAllObjects];
                [self refreshCartPresentation];
                [AlertHelper showAlertIn:self title:kLang(@"Success_Title") subtitle:[NSString stringWithFormat:kLang(@"POS_OrderCreated"), orderID]];
            }
        });
    }];
}

#pragma mark - Presentation

- (void)buildCheckoutDock {
    UIView *dock = [UIView new];
    dock.translatesAutoresizingMaskIntoConstraints = NO;
    dock.backgroundColor = AppForgroundColr;
    dock.layer.cornerRadius = PPCornerCard;
    dock.layer.cornerCurve = kCACornerCurveContinuous;
    dock.layer.shadowColor = UIColor.blackColor.CGColor;
    dock.layer.shadowOpacity = PPShadowSubtleOpacity;
    dock.layer.shadowRadius = PPShadowCardRadius;
    dock.layer.shadowOffset = CGSizeMake(0.0, PPShadowCardOffsetY);
    [self.view addSubview:dock];

    UILabel *captionLabel = [UILabel new];
    captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    captionLabel.text = kLang(@"POS_Total");
    captionLabel.textColor = SeconderyTextClr;
    captionLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:13.0]];
    captionLabel.adjustsFontForContentSizeCategory = YES;

    self.checkoutTotalLabel = [UILabel new];
    self.checkoutTotalLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.checkoutTotalLabel.textColor = PrimaryTextClr;
    self.checkoutTotalLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:21.0]];
    self.checkoutTotalLabel.adjustsFontForContentSizeCategory = YES;
    self.checkoutTotalLabel.textAlignment = [Language alignmentForCurrentLanguage];

    self.checkoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.checkoutButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.checkoutButton.backgroundColor = AppPrimaryClr;
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
        [dock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-PPSpaceMD],
        [dock.heightAnchor constraintGreaterThanOrEqualToConstant:76.0],
        [captionLabel.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:PPSpaceLG],
        [captionLabel.topAnchor constraintEqualToAnchor:dock.topAnchor constant:PPSpaceMD],
        [captionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.checkoutButton.leadingAnchor constant:-PPSpaceMD],
        [self.checkoutTotalLabel.leadingAnchor constraintEqualToAnchor:captionLabel.leadingAnchor],
        [self.checkoutTotalLabel.topAnchor constraintEqualToAnchor:captionLabel.bottomAnchor constant:1.0],
        [self.checkoutTotalLabel.bottomAnchor constraintLessThanOrEqualToAnchor:dock.bottomAnchor constant:-PPSpaceMD],
        [self.checkoutTotalLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.checkoutButton.leadingAnchor constant:-PPSpaceMD],
        [self.checkoutButton.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-PPSpaceMD],
        [self.checkoutButton.centerYAnchor constraintEqualToAnchor:dock.centerYAnchor],
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
    for (PPPOSCartItem *item in self.cart) total += item.price * item.quantity;
    self.checkoutTotalLabel.text = [NSString stringWithFormat:@"%.2f %@", total, kLang(@"Accounting_QAR")];
    self.checkoutButton.enabled = self.cart.count > 0;
    self.checkoutButton.alpha = self.checkoutButton.enabled ? 1.0 : 0.46;
    self.clearButton.enabled = self.cart.count > 0;
    [self.tableView reloadData];
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

- (UIButton *)catalogButtonForAccessory:(PetAccessory *)accessory index:(NSInteger)index {
    BOOL sellable = [self isSellableAccessory:accessory];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = index;
    button.backgroundColor = AppForgroundColr;
    button.layer.cornerRadius = PPCornerMedium;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
    button.accessibilityLabel = accessory.name;
    button.accessibilityHint = sellable ? kLang(@"POS_AddToCartHint") : kLang(@"POS_ItemUnavailable");
    button.enabled = sellable;
    button.alpha = sellable ? 1.0 : 0.52;
    [button addTarget:self action:@selector(didTapCatalogItem:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:sellable ? @"bag.badge.plus" : @"cart.badge.minus"]];
    glyph.translatesAutoresizingMaskIntoConstraints = NO;
    glyph.tintColor = sellable ? AppPrimaryClr : SeconderyTextClr;
    glyph.contentMode = UIViewContentModeScaleAspectFit;

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
    price.text = sellable ? [NSString stringWithFormat:@"%.2f %@", accessory.finalPrice.doubleValue, kLang(@"Accounting_QAR")] : kLang(@"POS_ItemUnavailable");
    price.textColor = sellable ? AppPrimaryClr : SeconderyTextClr;
    price.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:13.0]];
    price.adjustsFontForContentSizeCategory = YES;
    price.textAlignment = [Language alignmentForCurrentLanguage];

    [button addSubview:glyph];
    [button addSubview:name];
    [button addSubview:price];
    [NSLayoutConstraint activateConstraints:@[
        [glyph.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:PPSpaceMD],
        [glyph.topAnchor constraintEqualToAnchor:button.topAnchor constant:PPSpaceMD],
        [glyph.widthAnchor constraintEqualToConstant:20.0],
        [glyph.heightAnchor constraintEqualToConstant:20.0],
        [name.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:PPSpaceMD],
        [name.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-PPSpaceMD],
        [name.topAnchor constraintEqualToAnchor:glyph.bottomAnchor constant:PPSpaceSM],
        [price.leadingAnchor constraintEqualToAnchor:name.leadingAnchor],
        [price.trailingAnchor constraintEqualToAnchor:name.trailingAnchor],
        [price.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:PPSpaceXS],
        [price.bottomAnchor constraintLessThanOrEqualToAnchor:button.bottomAnchor constant:-PPSpaceMD],
    ]];
    return button;
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
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            cell.imageView.image = [[UIImage systemImageNamed:@"bag"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }

        UITableViewCell *cell = [self baseCardCellForTableView:tableView identifier:@"CartCell" style:UITableViewCellStyleValue1];
        PPPOSCartItem *item = self.cart[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ x%ld", item.name, (long)item.quantity];
        cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:16.0]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f %@", item.price * item.quantity, kLang(@"Accounting_QAR")];
        cell.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:15.0]];
        cell.detailTextLabel.textColor = AppPrimaryClr;
        cell.imageView.image = [[UIImage systemImageNamed:@"bag.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (self.isLoadingCatalog || self.catalogErrorMessage.length || self.filteredCatalog.count == 0) {
        UITableViewCell *cell = [self baseCardCellForTableView:tableView identifier:@"CatalogStateCell" style:UITableViewCellStyleSubtitle];
        cell.textLabel.text = self.isLoadingCatalog ? kLang(@"Loading") : (self.catalogErrorMessage.length ? kLang(@"Error_Title") : kLang(@"POS_CatalogEmpty"));
        cell.detailTextLabel.text = self.catalogErrorMessage.length ? self.catalogErrorMessage : kLang(@"POS_CatalogEmptyHint");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = self.catalogErrorMessage.length ? UIColor.systemRedColor : SeconderyTextClr;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return self.cart.count == 0 ? 78.0 : 72.0;
    return (self.isLoadingCatalog || self.catalogErrorMessage.length || self.filteredCatalog.count == 0) ? 104.0 : 136.0;
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

@end
