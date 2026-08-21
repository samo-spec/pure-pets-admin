#!/usr/bin/env python3
from pathlib import Path

list_path = Path("PurePetsAdmin/AccessorySection/AccessoriesListViewController.m")
cell_path = Path("PurePetsAdmin/AccessorySection/AccessoryCell.m")
list_text = list_path.read_text()
cell_text = cell_path.read_text()


def replace_list(old: str, new: str, count: int = 1) -> None:
    global list_text
    if list_text.count(old) < count:
        raise RuntimeError(f"Missing inventory list block: {old[:120]!r}")
    list_text = list_text.replace(old, new, count)


def replace_cell(old: str, new: str, count: int = 1) -> None:
    global cell_text
    if cell_text.count(old) < count:
        raise RuntimeError(f"Missing inventory cell block: {old[:120]!r}")
    cell_text = cell_text.replace(old, new, count)

helpers = r'''
static NSString *PPInventoryRouteTitle(AccessKindType kind) {
    switch (kind) {
        case AccessTypeFood: return kLang(@"AdminRoute_Food");
        case AccessTypeLivePets: return kLang(@"AdminRoute_LivePets");
        case AccessTypeAccessory:
        default: return kLang(@"AdminRoute_Accessories");
    }
}

static NSString *PPInventoryEmptyTitle(AccessKindType kind) {
    switch (kind) {
        case AccessTypeFood: return kLang(@"Inventory_Empty_Food_Title");
        case AccessTypeLivePets: return kLang(@"Inventory_Empty_LivePets_Title");
        case AccessTypeAccessory:
        default: return kLang(@"Inventory_Empty_Accessories_Title");
    }
}

static NSString *PPInventoryEmptySubtitle(AccessKindType kind) {
    switch (kind) {
        case AccessTypeFood: return kLang(@"Inventory_Empty_Food_Subtitle");
        case AccessTypeLivePets: return kLang(@"Inventory_Empty_LivePets_Subtitle");
        case AccessTypeAccessory:
        default: return kLang(@"Inventory_Empty_Accessories_Subtitle");
    }
}
'''
replace_list('#import "AddAccessoryViewController.h"\n', '#import "AddAccessoryViewController.h"\n' + helpers + '\n')
replace_list(
    '@property (nonatomic, strong) NSMutableDictionary<NSString *, dispatch_block_t> *pendingQuantityDebounceBlocks;\n',
    '@property (nonatomic, strong) NSMutableDictionary<NSString *, dispatch_block_t> *pendingQuantityDebounceBlocks;\n@property (nonatomic, copy, nullable) NSString *loadErrorMessage;\n',
)

# Table uses intrinsic row sizing and tokenized spacing.
replace_list('    // Card-based lists stand out beautifully on the default background color\n', '')
replace_list('    self.tableView.rowHeight = 112.0;\n    self.tableView.estimatedRowHeight = 112.0;', '    self.tableView.rowHeight = UITableViewAutomaticDimension;\n    self.tableView.estimatedRowHeight = 104.0;')
replace_list('    // Premium content inset\n    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 20.0, 0);', '    self.tableView.contentInset = UIEdgeInsetsMake(PPSpaceXS, 0, PPSpaceXL, 0);\n    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];')

# One localization source, no embedded Arabic fallbacks.
old_title = '''    UIButton *plus = [self pp_ButtonWithSystemName:@"plus" action:@selector(addAccessory)];
    NSString *title = kLang(@"Manage Accessories");
    if (self.listKind == AccessTypeFood) {
        title = kLang(@"manageFood");
        if (title.length == 0 || [title isEqualToString:@"manageFood"]) title = @"إدارة الأطعمة";
    } else if (self.listKind == AccessTypeLivePets) {
        title = kLang(@"Manage Live Pets");
        if (title.length == 0 || [title isEqualToString:@"Manage Live Pets"]) title = @"إدارة الحيوانات الأليفة";
    } else {
        if (title.length == 0 || [title isEqualToString:@"Manage Accessories"]) title = @"إدارة الإكسسوارات";
    }
    
    [self pp_navBarWithOtherButton:plus title:title];'''
replace_list(old_title, '''    UIButton *plus = [self pp_ButtonWithSystemName:@"plus" action:@selector(addAccessory)];
    plus.accessibilityLabel = kLang(@"Inventory_Add_Item");
    [self pp_navBarWithOtherButton:plus title:PPInventoryRouteTitle(self.listKind)];''')

# Listener failure becomes a deliberate state and all UI mutations are main-thread.
old_listener = '''    self.listener = [[AccessoryManager shared] observeAccessoriesOfKind:self.listKind callback:^(NSArray<PetAccessory *> * _Nullable items, NSError * _Nullable error) {
        if (error) {
            DLog(@"[AccessoriesList] listen error: %@", error.localizedDescription);
            return;
        }

        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.accessories = [items mutableCopy] ?: [NSMutableArray array];
        NSLog(@"[AccessoriesList] listener received %lu items", (unsigned long)self.accessories.count);
        [self _applyFilterAndReload];
    }];'''
replace_list(old_listener, '''    self.listener = [[AccessoryManager shared] observeAccessoriesOfKind:self.listKind callback:^(NSArray<PetAccessory *> * _Nullable items, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error) {
                DLog(@"[AccessoriesList] listen error: %@", error.localizedDescription);
                self.loadErrorMessage = kLang(@"Inventory_LoadFailed");
                [self.filteredAccessories removeAllObjects];
                [self.tableView reloadData];
                [self updateEmptyState];
                return;
            }
            self.loadErrorMessage = nil;
            self.accessories = [items mutableCopy] ?: [NSMutableArray array];
            [self _applyFilterAndReload];
        });
    }];''')

# Replace hardcoded empty state copy/type with shared localized state.
start = list_text.index('- (void)updateEmptyState {')
end = list_text.index('\n- (PetAccessory *)accessoryAtIndexPath:', start)
new_empty = r'''- (void)updateEmptyState {
    if (self.filteredAccessories.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }

    UIView *emptyView = [[UIView alloc] initWithFrame:self.tableView.bounds];
    emptyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    emptyView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    BOOL failed = self.loadErrorMessage.length > 0;
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:failed ? @"wifi.exclamationmark" : @"shippingbox"]];
    iconView.tintColor = failed ? [UIColor ppError] : [UIColor ppTextTertiary];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.isAccessibilityElement = NO;
    [emptyView addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontTitle3]];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textColor = [UIColor ppTextPrimary];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    titleLabel.text = failed ? kLang(@"Inventory_LoadFailed_Title") : PPInventoryEmptyTitle(self.listKind);
    [emptyView addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontSubheadline]];
    subLabel.adjustsFontForContentSizeCategory = YES;
    subLabel.textColor = [UIColor ppTextSecondary];
    subLabel.textAlignment = NSTextAlignmentCenter;
    subLabel.numberOfLines = 0;
    subLabel.text = failed ? self.loadErrorMessage : PPInventoryEmptySubtitle(self.listKind);
    [emptyView addSubview:subLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:emptyView.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:emptyView.centerYAnchor constant:-PPSpaceXXL],
        [iconView.widthAnchor constraintEqualToConstant:48.0],
        [iconView.heightAnchor constraintEqualToConstant:48.0],
        [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:PPSpaceBase],
        [titleLabel.leadingAnchor constraintEqualToAnchor:emptyView.leadingAnchor constant:PPScreenMargin],
        [titleLabel.trailingAnchor constraintEqualToAnchor:emptyView.trailingAnchor constant:-PPScreenMargin],
        [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:PPSpaceSM],
        [subLabel.leadingAnchor constraintEqualToAnchor:emptyView.leadingAnchor constant:PPScreenMargin],
        [subLabel.trailingAnchor constraintEqualToAnchor:emptyView.trailingAnchor constant:-PPScreenMargin]
    ]];
    self.tableView.backgroundView = emptyView;
}
'''
list_text = list_text[:start] + new_empty + list_text[end:]

# Search field: token geometry, no shadow.
replace_list('    CGFloat barH = 48.0;\n    CGFloat pad = 16.0;', '    CGFloat barH = PPButtonHeightMD;\n    CGFloat pad = PPSpaceSM;')
replace_list('    sv.cornerRadius = barH / 2.0;', '    sv.cornerRadius = PPCorner16;')
replace_list('    sv.shadowEnabled = YES;', '    sv.shadowEnabled = NO;')
replace_list('    sv.strokeColor = [UIColor colorWithWhite:0 alpha:0.04];', '    sv.strokeColor = [UIColor ppSurfaceBorder];')
replace_list('    sv.textField.placeholder = kLang(@"SetPermissions_Search_Placeholder");\n    if (sv.textField.placeholder.length == 0 || [sv.textField.placeholder isEqualToString:@"SetPermissions_Search_Placeholder"]) {\n        sv.textField.placeholder = @"بحث عن المنتجات...";\n    }', '    sv.textField.placeholder = kLang(@"Inventory_Search_Placeholder");')
replace_list('        [sv.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],\n        [sv.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],', '        [sv.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:PPScreenMargin],\n        [sv.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-PPScreenMargin],')

# Generic localized mutation errors; do not leak backend descriptions.
replace_list('[PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Something went wrong.")];', '[PPHUD showError:kLang(@"Error") subtitle:kLang(@"Inventory_StockUpdateFailed")];')
replace_list('                              title:kLang(@"Confirm Delete")\n                           subtitle:kLang(@"Are you sure you want to delete this accessory?")', '                              title:kLang(@"Inventory_DeleteConfirm_Title")\n                           subtitle:kLang(@"Inventory_DeleteConfirm_Subtitle")')
replace_list('[PPHUD showError:kLang(@"Error") subtitle:err.localizedDescription ?: kLang(@"Something went wrong.")];', '[PPHUD showError:kLang(@"Error") subtitle:kLang(@"Inventory_DeleteFailed")];')
replace_list('[PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Accessory removed")];', '[PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Inventory_DeleteSuccess")];')

# -------------------------------------------------------------------------
# Shared inventory cell: semantic surface, Dynamic Type, 44pt stock controls,
# Reduce Motion and no per-card decorative shadow.
# -------------------------------------------------------------------------
replace_cell('        self.insets = UIEdgeInsetsMake(3, 8, 3, 8);\n        self.layer.cornerRadius = 6;\n        self.clipsToBounds = YES;\n        self.font = [UIFont fontWithName:@"Beiruti-Medium" size:11] ?: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];', '        self.insets = UIEdgeInsetsMake(PPSpaceXS, PPSpaceSM, PPSpaceXS, PPSpaceSM);\n        self.layer.cornerRadius = PPCornerSmall;\n        self.clipsToBounds = YES;\n        self.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontCaption1]];\n        self.adjustsFontForContentSizeCategory = YES;')
replace_cell('    _cardView.backgroundColor = AppForgroundColr;\n    _cardView.layer.cornerRadius = 16.0;\n    \n    // Premium soft shadow\n    _cardView.layer.shadowColor = [UIColor blackColor].CGColor;\n    _cardView.layer.shadowOpacity = 0.04;\n    _cardView.layer.shadowRadius = 8.0;\n    _cardView.layer.shadowOffset = CGSizeMake(0, 4);\n    _cardView.layer.masksToBounds = NO;', '    _cardView.backgroundColor = [UIColor ppSurface];\n    _cardView.layer.cornerRadius = PPCorner16;\n    _cardView.layer.cornerCurve = kCACornerCurveContinuous;\n    _cardView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;\n    _cardView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;\n    _cardView.layer.masksToBounds = YES;')
replace_cell('    _thumbView.layer.cornerRadius = 12.0;\n    _thumbView.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.06].CGColor;', '    _thumbView.layer.cornerRadius = PPCornerSmall;\n    _thumbView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;')
replace_cell('    _badgeStackView.spacing = 6.0;', '    _badgeStackView.spacing = PPSpaceSM;')
replace_cell('    _kindBadge.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.08];', '    _kindBadge.backgroundColor = [UIColor ppSecondarySurface];')
replace_cell('    _nameLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:16] ?: [UIFont boldSystemFontOfSize:16];', '    _nameLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontHeadline]];\n    _nameLabel.adjustsFontForContentSizeCategory = YES;')
replace_cell('    _priceStackView.spacing = 8.0;', '    _priceStackView.spacing = PPSpaceSM;')
replace_cell('    _finalPriceLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:15] ?: [UIFont boldSystemFontOfSize:15];', '    _finalPriceLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontCallout]];\n    _finalPriceLabel.adjustsFontForContentSizeCategory = YES;')
replace_cell('    _originalPriceLabel.font = [UIFont fontWithName:@"Beiruti-Regular" size:13] ?: [UIFont systemFontOfSize:13];', '    _originalPriceLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:PPFontFootnote]];\n    _originalPriceLabel.adjustsFontForContentSizeCategory = YES;')
replace_cell('    _stepperContainer.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.06];\n    _stepperContainer.layer.cornerRadius = 10.0;', '    _stepperContainer.backgroundColor = [UIColor ppSecondarySurface];\n    _stepperContainer.layer.cornerRadius = PPCornerSmall;')
replace_cell('    _qtyLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:15] ?: [UIFont boldSystemFontOfSize:15];', '    _qtyLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:PPFontCallout]];\n    _qtyLabel.adjustsFontForContentSizeCategory = YES;')

# Tokenize card layout and raise stock controls to HIG targets.
for old, new in [
    ('constant:6.0]', 'constant:PPSpaceXS]'),
    ('constant:12.0]', 'constant:PPSpaceMD]'),
    ('constant:-12.0]', 'constant:-PPSpaceMD]'),
    ('constant:-6.0]', 'constant:-PPSpaceXS]'),
    ('constant:-8.0]', 'constant:-PPSpaceSM]'),
    ('constant:4.0]', 'constant:PPSpaceXS]'),
]:
    cell_text = cell_text.replace(old, new)
replace_cell('        [_stepperContainer.widthAnchor constraintEqualToConstant:104.0],\n        [_stepperContainer.heightAnchor constraintEqualToConstant:36.0],', '        [_stepperContainer.widthAnchor constraintEqualToConstant:122.0],\n        [_stepperContainer.heightAnchor constraintEqualToConstant:PPTouchTargetMin],')
replace_cell('        [_minusButton.widthAnchor constraintEqualToConstant:32.0],', '        [_minusButton.widthAnchor constraintEqualToConstant:PPTouchTargetMin],')
replace_cell('        [_plusButton.widthAnchor constraintEqualToConstant:32.0],', '        [_plusButton.widthAnchor constraintEqualToConstant:PPTouchTargetMin],')

# Semantic direction/VoiceOver controls.
replace_cell('        [self setupSubviews];\n        [self setupConstraints];', '        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];\n        [self setupSubviews];\n        [self setupConstraints];')
replace_cell('    _thumbView.contentMode = UIViewContentModeScaleAspectFill;', '    _thumbView.contentMode = UIViewContentModeScaleAspectFill;\n    _thumbView.isAccessibilityElement = NO;')
replace_cell('    _cardView.backgroundColor = [UIColor ppSurface];', '    _cardView.backgroundColor = [UIColor ppSurface];\n    _cardView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];')
replace_cell('    _badgeStackView.axis = UILayoutConstraintAxisHorizontal;', '    _badgeStackView.axis = UILayoutConstraintAxisHorizontal;\n    _badgeStackView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];')
replace_cell('    _stepperContainer.translatesAutoresizingMaskIntoConstraints = NO;', '    _stepperContainer.translatesAutoresizingMaskIntoConstraints = NO;\n    _stepperContainer.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];')
replace_cell('    _qtyLabel.text = @(qty).stringValue;', '    _qtyLabel.text = @(qty).stringValue;\n    _minusButton.accessibilityLabel = [NSString stringWithFormat:@"%@، %@", kLang(@"POS_RemoveOne"), _nameLabel.text ?: @""];\n    _plusButton.accessibilityLabel = [NSString stringWithFormat:@"%@، %@", kLang(@"POS_AddOne"), _nameLabel.text ?: @""];')
replace_cell('        _stepperContainer.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.06];', '        _stepperContainer.backgroundColor = [UIColor ppSecondarySurface];')

replace_cell('''- (void)animateButtonPress:(UIView *)view {
    view.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}''', '''- (void)animateButtonPress:(UIView *)view {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    view.transform = CGAffineTransformMakeScale(PPTapScaleDown, PPTapScaleDown);
    [UIView animateWithDuration:PPAnimDurationNormal delay:0 usingSpringWithDamping:PPAnimSpringDamping initialSpringVelocity:PPAnimSpringVelocity options:UIViewAnimationOptionAllowUserInteraction animations:^{
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}''')
replace_cell('''    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (highlighted) {
            self.cardView.transform = CGAffineTransformMakeScale(0.97, 0.97);
            self.cardView.backgroundColor = [AppForgroundColr colorWithAlphaComponent:0.8];
        } else {
            self.cardView.transform = CGAffineTransformIdentity;
            self.cardView.backgroundColor = AppForgroundColr;
        }
    } completion:nil];''', '''    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.cardView.backgroundColor = highlighted ? [UIColor ppSecondarySurface] : [UIColor ppSurface];
        return;
    }
    [UIView animateWithDuration:PPAnimDurationFast delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.cardView.transform = highlighted ? CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown) : CGAffineTransformIdentity;
        self.cardView.backgroundColor = highlighted ? [UIColor ppSecondarySurface] : [UIColor ppSurface];
    } completion:nil];''')

list_path.write_text(list_text)
cell_path.write_text(cell_text)

strings = {
    Path("PurePetsAdmin/en.lproj/Localizable.strings"): {
        "Inventory_Add_Item": "Add item",
        "Inventory_Search_Placeholder": "Search inventory",
        "Inventory_LoadFailed_Title": "Inventory unavailable",
        "Inventory_LoadFailed": "Couldn’t load inventory. Try again.",
        "Inventory_Empty_Accessories_Title": "No accessories yet",
        "Inventory_Empty_Accessories_Subtitle": "Add the first accessory to this catalog.",
        "Inventory_Empty_Food_Title": "No food products yet",
        "Inventory_Empty_Food_Subtitle": "Add the first food product to this catalog.",
        "Inventory_Empty_LivePets_Title": "No live pets yet",
        "Inventory_Empty_LivePets_Subtitle": "Add the first live-pet listing to this catalog.",
        "Inventory_StockUpdateFailed": "Couldn’t update stock. Try again.",
        "Inventory_DeleteConfirm_Title": "Delete item?",
        "Inventory_DeleteConfirm_Subtitle": "This removes the item from the catalog.",
        "Inventory_DeleteFailed": "Couldn’t delete this item. Try again.",
        "Inventory_DeleteSuccess": "Item removed.",
    },
    Path("PurePetsAdmin/ar.lproj/Localizable.strings"): {
        "Inventory_Add_Item": "إضافة عنصر",
        "Inventory_Search_Placeholder": "البحث في المخزون",
        "Inventory_LoadFailed_Title": "المخزون غير متاح",
        "Inventory_LoadFailed": "تعذر تحميل المخزون. حاول مرة أخرى.",
        "Inventory_Empty_Accessories_Title": "لا توجد إكسسوارات بعد",
        "Inventory_Empty_Accessories_Subtitle": "أضف أول إكسسوار إلى هذا الكتالوج.",
        "Inventory_Empty_Food_Title": "لا توجد منتجات طعام بعد",
        "Inventory_Empty_Food_Subtitle": "أضف أول منتج طعام إلى هذا الكتالوج.",
        "Inventory_Empty_LivePets_Title": "لا توجد حيوانات أليفة بعد",
        "Inventory_Empty_LivePets_Subtitle": "أضف أول إعلان حيوان أليف إلى هذا الكتالوج.",
        "Inventory_StockUpdateFailed": "تعذر تحديث المخزون. حاول مرة أخرى.",
        "Inventory_DeleteConfirm_Title": "حذف العنصر؟",
        "Inventory_DeleteConfirm_Subtitle": "سيتم حذف العنصر من الكتالوج.",
        "Inventory_DeleteFailed": "تعذر حذف هذا العنصر. حاول مرة أخرى.",
        "Inventory_DeleteSuccess": "تم حذف العنصر.",
    },
}
for strings_path, additions in strings.items():
    source = strings_path.read_text()
    for key, value in additions.items():
        if f'"{key}"' not in source:
            source += f'\n"{key}" = "{value}";\n'
    strings_path.write_text(source)

print("Applied shared inventory list/cell V6 pass.")
