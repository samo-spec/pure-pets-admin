
/*
 // Arabic
 "ItemType"       = "نوع العنصر";
 "Accessory"      = "إكسسوار";
 "Food"           = "طعام";
 "AddAccessory"   = "إضافة إكسسوار";
 "EditAccessory"  = "تعديل الإكسسوار";
 "AddFood"        = "إضافة طعام";
 "EditFood"       = "تعديل الطعام";
 */



//
//  AddAccessoryViewController.m
//  PurePetsAdmin
//

#import "AddAccessoryViewController.h"
#import "AlertHelper.h"
#import "PPImageCollectionRow.h"
@import Photos;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
static NSString * const PPMainStoreID = @"main_store";
static NSString * const PPMainStoreFallbackName = @"Main Store";
static NSString * const PPMyStoreFallbackName = @"My Store";
static CGFloat const PPAccessoryDefaultRowHeight = 48.0;

@interface AddAccessoryViewController ()

@property (nonatomic, strong) NSArray<UIBarButtonItem *> *prevLeftItems;
@property (nonatomic, strong) NSArray<UIBarButtonItem *> *prevRightItems;
@property (nonatomic, assign) BOOL prevHidesBack;

@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *storeNamesByID;

@end

@implementation AddAccessoryViewController

// AddAccessoryViewController.m

- (instancetype)initWithAccessory:(PetAccessory * _Nullable)accessory {
    self = [super initWithForm:nil style:UITableViewStyleInsetGrouped];
    if (self) {
        _editingAccessory = accessory;
        _showTypeRow = YES;                    // default; caller can set to NO before presenting
        _defaultKind = AccessTypeAccessory;    // default; caller can set Food, etc.
        // ❌ DO NOT build the form here
        // ❌ DO NOT call pp_setupPhotoManager… here
    }
    return self;
}

- (instancetype)init {
    return [self initWithAccessory:nil];
}

/// Effective kind considering showTypeRow, the current form selection, the editing item, and defaultKind
- (AccessKindType)pp_resolvedKind {
    if (self.showTypeRow) {
        XLFormRowDescriptor *typeRow = [self.form formRowWithTag:@"itemType"];
        if ([typeRow.value isKindOfClass:XLFormOptionsObject.class]) {
            XLFormOptionsObject *opt = (XLFormOptionsObject *)typeRow.value;
            return [self pp_normalizedKindFromRaw:[opt.formValue integerValue]];
        }
    }
    if (self.editingAccessory) {
        return [self pp_normalizedKindFromRaw:self.editingAccessory.accessKindType];
    }
    return [self pp_normalizedKindFromRaw:self.defaultKind];
}

- (AccessKindType)pp_normalizedKindFromRaw:(NSInteger)rawKind {
    if (rawKind == AccessTypeFood) return AccessTypeFood;
    if (rawKind == AccessTypeLivePets) return AccessTypeLivePets;
    return AccessTypeAccessory;
}

- (NSInteger)pp_integerFromValue:(id)value defaultValue:(NSInteger)defaultValue {
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value integerValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value integerValue];
    return defaultValue;
}

- (NSNumber *)pp_numberFromValue:(id)value {
    if ([value isKindOfClass:NSNumber.class]) return (NSNumber *)value;
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) {
        NSNumberFormatter *formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        return [formatter numberFromString:(NSString *)value];
    }
    return nil;
}

- (NSInteger)pp_optionValueFromFormValue:(id)value defaultValue:(NSInteger)defaultValue {
    if ([value isKindOfClass:XLFormOptionsObject.class]) {
        return [self pp_integerFromValue:((XLFormOptionsObject *)value).formValue defaultValue:defaultValue];
    }
    return [self pp_integerFromValue:value defaultValue:defaultValue];
}

- (NSString *)pp_localizedStringForKey:(NSString *)key fallback:(NSString *)fallback {
    NSString *value = kLang(key);
    if (value.length == 0 || [value isEqualToString:key]) {
        return fallback;
    }
    return value;
}

- (NSString *)pp_mainStoreDisplayName {
    return [self pp_localizedStringForKey:@"MainStore" fallback:PPMainStoreFallbackName];
}

- (NSString *)pp_myStoreDisplayName {
    return [self pp_localizedStringForKey:@"MyStore" fallback:PPMyStoreFallbackName];
}

- (void)pp_applyDefaultRowHeight:(XLFormRowDescriptor *)row {
    row.height = PPAccessoryDefaultRowHeight;
}

- (NSArray<XLFormOptionsObject *> *)pp_storeOptionsForAccessory:(PetAccessory *)accessory {
    NSMutableArray<XLFormOptionsObject *> *options = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];

    NSString *mainName = [self pp_mainStoreDisplayName];
    [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:PPMainStoreID displayText:mainName]];
    map[PPMainStoreID] = mainName;

    NSString *myStoreID = PPSafeString(UsrMgr.currentUser.uid);
    NSString *myStoreName = PPSafeString(UsrMgr.currentUser.displayName);
    if (myStoreID.length > 0 && ![myStoreID isEqualToString:PPMainStoreID]) {
        if (myStoreName.length == 0) myStoreName = [self pp_myStoreDisplayName];
        [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:myStoreID displayText:myStoreName]];
        map[myStoreID] = myStoreName;
    }

    NSString *existingStoreID = PPSafeString(accessory.storeID);
    NSString *existingStoreName = PPSafeString(accessory.storeName);
    if (existingStoreID.length > 0 && !map[existingStoreID]) {
        NSString *resolved = existingStoreName.length > 0 ? existingStoreName : existingStoreID;
        [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:existingStoreID displayText:resolved]];
        map[existingStoreID] = resolved;
    }

    self.storeNamesByID = [map copy];
    return [options copy];
}

- (NSString *)pp_storeNameForID:(NSString *)storeID {
    NSString *sid = PPSafeString(storeID);
    if (sid.length == 0) sid = PPMainStoreID;
    NSString *name = self.storeNamesByID[sid];
    if (name.length > 0) return name;
    if ([sid isEqualToString:PPMainStoreID]) return [self pp_mainStoreDisplayName];
    return sid;
}

- (NSString *)pp_storeIDFromFormValue:(id)value {
    if ([value isKindOfClass:XLFormOptionsObject.class]) {
        id formValue = ((XLFormOptionsObject *)value).formValue;
        if ([formValue isKindOfClass:NSString.class]) return PPSafeString(formValue);
    } else if ([value isKindOfClass:NSString.class]) {
        return PPSafeString(value);
    }
    return @"";
}

- (NSNumber *)pp_calculateFinalPriceFromForm {
    XLFormRowDescriptor *priceRow = [self.form formRowWithTag:@"price"];
    XLFormRowDescriptor *percentRow = [self.form formRowWithTag:@"discountPercent"];
    XLFormRowDescriptor *amountRow = [self.form formRowWithTag:@"discountAmount"];

    NSNumber *price = [self pp_numberFromValue:priceRow.value];
    NSNumber *discountPercent = [self pp_numberFromValue:percentRow.value];
    NSNumber *discountAmount = [self pp_numberFromValue:amountRow.value];

    if (!price) return nil;
    CGFloat basePrice = MAX(0.0, price.floatValue);
    CGFloat final = basePrice;

    if (discountPercent && discountPercent.floatValue > 0) {
        CGFloat clampedPercent = MIN(100.0, MAX(0.0, discountPercent.floatValue));
        final = basePrice - (basePrice * clampedPercent / 100.0);
    }
    if (discountAmount && discountAmount.floatValue > 0) {
        final -= discountAmount.floatValue;
    }
    return @(MAX(0.0, final));
}

- (void)pp_refreshFinalPriceRow {
    XLFormRowDescriptor *finalPriceRow = [self.form formRowWithTag:@"finalPrice"];
    if (!finalPriceRow) return;
    finalPriceRow.value = [self pp_calculateFinalPriceFromForm] ?: @(0);
    [self updateFormRow:finalPriceRow];
}

- (NSDictionary *)pp_metaForURL:(NSString *)url width:(CGFloat)width height:(CGFloat)height {
    return @{
        @"url": PPSafeString(url),
        @"width": @(MAX(0.0, width)),
        @"height": @(MAX(0.0, height))
    };
}

- (NSDictionary<NSString *, NSDictionary *> *)pp_existingMetaByURLForAccessory:(PetAccessory *)accessory {
    NSMutableDictionary<NSString *, NSDictionary *> *map = [NSMutableDictionary dictionary];
    NSArray<NSString *> *urls = accessory.imageURLsArray ?: @[];
    NSArray<NSDictionary *> *meta = accessory.imageMeta ?: @[];

    for (NSInteger i = 0; i < urls.count; i++) {
        NSString *url = PPSafeString(urls[i]);
        if (url.length == 0) continue;

        NSDictionary *m = (i < meta.count && [meta[i] isKindOfClass:NSDictionary.class]) ? meta[i] : nil;
        CGFloat width = [m[@"width"] floatValue];
        CGFloat height = [m[@"height"] floatValue];
        map[url] = [self pp_metaForURL:url width:width height:height];
    }
    return [map copy];
}

- (NSArray<NSDictionary *> *)pp_imageMetaForURLs:(NSArray<NSString *> *)urls
                                  existingMetaByURL:(NSDictionary<NSString *, NSDictionary *> *)existingMetaByURL
                                  uploadedMetaByURL:(NSDictionary<NSString *, NSDictionary *> *)uploadedMetaByURL {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSString *url in urls) {
        NSString *clean = PPSafeString(url);
        if (clean.length == 0) continue;
        NSDictionary *meta = uploadedMetaByURL[clean] ?: existingMetaByURL[clean];
        if (!meta) {
            meta = [self pp_metaForURL:clean width:0 height:0];
        }
        [out addObject:meta];
    }
    return [out copy];
}

- (void)pp_backfillMissingEditFieldsIfNeeded {
    if (!self.editingAccessory) return;

    PetAccessory *candidate = [PetAccessory deepCopyFrom:self.editingAccessory];
    BOOL changed = NO;

    if (candidate.ownerID.length == 0) {
        candidate.ownerID = [FIRAuth auth].currentUser.uid ?: @"";
        changed = changed || (candidate.ownerID.length > 0);
    }
    if (candidate.storeID.length == 0) {
        candidate.storeID = PPMainStoreID;
        changed = YES;
    }
    if (candidate.storeName.length == 0) {
        candidate.storeName = [self pp_mainStoreDisplayName];
        changed = YES;
    }

    NSDictionary<NSString *, NSDictionary *> *existingMap = [self pp_existingMetaByURLForAccessory:candidate];
    NSArray<NSDictionary *> *normalizedMeta = [self pp_imageMetaForURLs:(candidate.imageURLsArray ?: @[])
                                                       existingMetaByURL:existingMap
                                                       uploadedMetaByURL:@{}];
    if (normalizedMeta.count != (candidate.imageMeta ?: @[]).count) {
        candidate.imageMeta = normalizedMeta;
        changed = YES;
    }

    NSInteger oldQty = candidate.quantity;
    BOOL oldNoStock = candidate.noStock;
    [candidate normalizeInventoryState];
    if (candidate.quantity != oldQty || candidate.noStock != oldNoStock) {
        changed = YES;
    }

    self.editingAccessory = candidate;
    if (!changed) return;

    [[AccessoryManager shared] createOrUpdateAccessory:candidate completion:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"[AddAccessory] backfill save failed: %@", error.localizedDescription);
        } else {
            DLog(@"[AddAccessory] backfill save completed");
        }
    }];
}

/// Returns the UIImages currently in the PPImageCollection photos row.
- (NSArray<UIImage *> *)pp_selectedImages {
    XLFormRowDescriptor *photosRow = [self.form formRowWithTag:@"photos"];
    id val = photosRow.value;
    if ([val isKindOfClass:[NSArray class]]) {
        NSMutableArray<UIImage *> *result = [NSMutableArray array];
        for (id item in (NSArray *)val) {
            if ([item isKindOfClass:[UIImage class]]) {
                [result addObject:item];
            }
        }
        return result;
    }
    if ([val isKindOfClass:[UIImage class]]) {
        return @[(UIImage *)val];
    }
    return @[];
}

/// Returns YES if the user modified the images after preload (editing mode).
- (BOOL)pp_imagesModified {
    XLFormRowDescriptor *photosRow = [self.form formRowWithTag:@"photos"];
    NSIndexPath *ip = [self.form indexPathOfFormRow:photosRow];
    PPImageCollectionRow *cell = (PPImageCollectionRow *)[self.tableView cellForRowAtIndexPath:ip];
    if ([cell isKindOfClass:[PPImageCollectionRow class]]) {
        return cell.imagesModified;
    }
    // If cell not visible, check if value differs from editing state
    return YES;
}
- (XLFormDescriptor *)buildFormWithAccessory:(PetAccessory * _Nullable)accessory {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    // ===== Section 0: Type (Accessory/Food) when visible =====
    XLFormSectionDescriptor *section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    AccessKindType initialKind = AccessTypeAccessory;
    if (self.showTypeRow) {
        XLFormRowDescriptor *typeRow =
        [XLFormRowDescriptor formRowDescriptorWithTag:@"itemType"
                                              rowType:XLFormRowDescriptorTypeSelectorSegmentedControl
                                                title:kLang(@"ItemType")];

        typeRow.selectorOptions = @[
            [XLFormOptionsObject formOptionsObjectWithValue:@(AccessTypeAccessory) displayText:kLang(@"Accessory")],
            [XLFormOptionsObject formOptionsObjectWithValue:@(AccessTypeFood)      displayText:kLang(@"Food")],
            [XLFormOptionsObject formOptionsObjectWithValue:@(AccessTypeLivePets)  displayText:kLang(@"Live pets")]
        ];

        // Preselect
        AccessKindType preselect = accessory ? accessory.accessKindType : self.defaultKind;
        if (preselect != AccessTypeAccessory && preselect != AccessTypeFood && preselect != AccessTypeLivePets) {
            preselect = AccessTypeAccessory;
        }
        for (XLFormOptionsObject *opt in typeRow.selectorOptions) {
            if ([opt.formValue integerValue] == preselect) { typeRow.value = opt; break; }
        }

        // If editing, lock the type (don't let the user change)
        if (self.editingAccessory) typeRow.disabled = @YES;

        __weak typeof(self) weakSelf = self;
        typeRow.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *r) {
            __strong typeof(weakSelf) self = weakSelf;
            // toggle Condition row + update title live for new flow
            [self pp_applyKindDrivenUIAndTitle];
        };

        [self pp_applyDefaultRowHeight:typeRow];
        [Styling applyGlobalStyleToRow:typeRow];
        [section addFormRow:typeRow];

        initialKind = [self pp_resolvedKind];
    } else {
        // Hidden mode: infer kind now (from editing item, or defaultKind, else Accessory)
        initialKind = [self pp_resolvedKind];
        // (No itemType row is added)
    }

    // ===== Section 1: Basic =====
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    // Name
    XLFormRowDescriptor *row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"name"
                                           rowType:XLFormRowDescriptorTypeText
                                             title:kLang(@"Name")];
    row.required = YES;
    row.value = self.editingAccessory.name;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"Enter name");
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Description
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"desc"
                                           rowType:XLFormRowDescriptorTypeTextView
                                             title:kLang(@"Description")];
    row.value = self.editingAccessory.desc;
    row.cellConfigAtConfigure[@"textView.placeholder"] = kLang(@"Enter description");
    row.height = 60;
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // ===== Section 2: Species / Breed =====
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    // Species (required)
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"mainKind"
                                           rowType:XLFormRowDescriptorTypeSelectorPush
                                             title:kLang(@"Species")];
    row.required = YES;
    row.noValueDisplayText = kLang(@"SpeciesPlaceholder");
    row.selectorOptions = AppMgr.MainKindsArray ?: @[];
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    if (self.editingAccessory && self.editingAccessory.petMainCategoryID > 0) {
        MainKindsModel *mk = [self mainKindForID:self.editingAccessory.petMainCategoryID];
        if (mk) row.value = mk;
    }
    __weak typeof(self) weakSelf = self;
    row.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *r) {
        __strong typeof(weakSelf) self = weakSelf;
        XLFormRowDescriptor *subRow = [form formRowWithTag:@"subKind"];
        if ([newValue isKindOfClass:[MainKindsModel class]]) {
            MainKindsModel *selected = (MainKindsModel *)newValue;
            subRow.selectorOptions = selected.SubKindsArray ?: @[];
            subRow.hidden = @NO;
        } else {
            subRow.value = nil;
            subRow.selectorOptions = @[];
            subRow.hidden = @YES;
        }
        [self updateFormRow:subRow];
    };
    [section addFormRow:row];

    // Breed (optional)
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"subKind"
                                           rowType:XLFormRowDescriptorTypeSelectorPush
                                             title:kLang(@"Breed")];
    row.noValueDisplayText = kLang(@"BreedPlaceholder");
    row.selectorOptions = @[];
    row.hidden = [NSPredicate predicateWithFormat:@"$mainKind == nil"];
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    if (self.editingAccessory && self.editingAccessory.petSubCategoryID > 0) {
        SubKindModel *sk = [self subKindForID:self.editingAccessory.petSubCategoryID
                                       mainID:self.editingAccessory.petMainCategoryID];
        if (sk) row.value = sk;
    }
    [section addFormRow:row];

    // ===== Section 3: Pricing & Condition =====
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    // Price
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"price"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"Price")];
    row.required = YES;
    row.value = self.editingAccessory.price;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"0.00");
    __weak typeof(self) weakPricingSelf = self;
    row.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *r) {
        __strong typeof(weakPricingSelf) self = weakPricingSelf;
        [self pp_refreshFinalPriceRow];
    };
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Discount %
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"discountPercent"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"DiscountPercent")];
    row.value = self.editingAccessory.discountPercent;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"DiscountPercentPlaceholder");
    row.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *r) {
        __strong typeof(weakPricingSelf) self = weakPricingSelf;
        [self pp_refreshFinalPriceRow];
    };
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Discount amount
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"discountAmount"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"DiscountAmount")];
    row.value = self.editingAccessory.discountAmount;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"0.00");
    row.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *r) {
        __strong typeof(weakPricingSelf) self = weakPricingSelf;
        [self pp_refreshFinalPriceRow];
    };
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Final price (auto)
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"finalPrice"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"FinalPrice")];
    row.disabled = @YES;
    row.value = self.editingAccessory.finalPrice ?: self.editingAccessory.price ?: @(0);
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Quantity
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"quantity"
                                           rowType:XLFormRowDescriptorTypeInteger
                                             title:kLang(@"Quantity")];
    row.value = @(MAX(0, self.editingAccessory ? self.editingAccessory.quantity : 0));
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"Enter quantity");
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Condition (New/Used) — shown only for Accessory, hidden for Food
    XLFormRowDescriptor *conditionRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"condition"
                                           rowType:XLFormRowDescriptorTypeSelectorSegmentedControl
                                             title:kLang(@"Condition")];
    conditionRow.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(AccessConditionsNew)  displayText:kLang(@"New")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(AccessConditionsUsed) displayText:kLang(@"Used")]
    ];
    if (self.editingAccessory) {
        NSInteger cond = self.editingAccessory.condition;
        conditionRow.value = conditionRow.selectorOptions[(cond == AccessConditionsUsed ? 1 : 0)];
    } else {
        conditionRow.value = conditionRow.selectorOptions.firstObject;
    }
    [self pp_applyDefaultRowHeight:conditionRow];
    [Styling applyGlobalStyleToRow:conditionRow];
    [section addFormRow:conditionRow];

    // Initial visibility/lock for Condition based on resolved kind
    BOOL isFood = (initialKind == AccessTypeFood);
    if (isFood) {
        conditionRow.hidden = @YES;
        conditionRow.value  = conditionRow.selectorOptions.firstObject; // force "New"
        conditionRow.disabled = @YES;
    } else {
        conditionRow.hidden = @NO;
        conditionRow.disabled = @NO;
    }

    // ===== Section: Expiry Date =====
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    XLFormRowDescriptor *expiryRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"expiryDate"
                                           rowType:XLFormRowDescriptorTypeDate
                                             title:kLang(@"Expiry Date")];
    expiryRow.noValueDisplayText = kLang(@"No Expiry");
    expiryRow.required = NO;
    if (self.editingAccessory.expiryDate) {
        expiryRow.value = self.editingAccessory.expiryDate;
    }
    [self pp_applyDefaultRowHeight:expiryRow];
    [Styling applyGlobalStyleToRow:expiryRow];
    [section addFormRow:expiryRow];

    // ===== Section 4: Store =====
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    XLFormRowDescriptor *storeRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"store"
                                           rowType:XLFormRowDescriptorTypeSelectorPush
                                             title:kLang(@"Store")];
    storeRow.noValueDisplayText = [self pp_mainStoreDisplayName];
    NSArray<XLFormOptionsObject *> *storeOptions = [self pp_storeOptionsForAccessory:accessory];
    storeRow.selectorOptions = storeOptions;
    NSString *selectedStoreID = PPSafeString(accessory.storeID);
    if (selectedStoreID.length == 0) selectedStoreID = PPMainStoreID;
    for (XLFormOptionsObject *opt in storeOptions) {
        if ([[self pp_storeIDFromFormValue:opt] isEqualToString:selectedStoreID]) {
            storeRow.value = opt;
            break;
        }
    }
    if (!storeRow.value && storeOptions.count > 0) {
        storeRow.value = storeOptions.firstObject;
    }
    [self pp_applyDefaultRowHeight:storeRow];
    [Styling applyGlobalStyleToRow:storeRow];
    [section addFormRow:storeRow];

    // ===== Section 5: Images =====
    section = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Images")];
    [form addFormSection:section];

    XLFormRowDescriptor *photosRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"photos"
                                           rowType:XLFormRowDescriptorTypePPImageCollection
                                             title:nil];
    photosRow.cellConfigAtConfigure[@"maxImages"] = @(9);
    // Preload existing images when editing
    if (accessory.imageURLsArray.count > 0) {
        photosRow.cellConfigAtConfigure[@"preloadImageURLs"] = accessory.imageURLsArray;
    }
    [section addFormRow:photosRow];

    return form;
}

/// Called after typeRow change to refresh title + condition visibility
- (void)pp_applyKindDrivenUIAndTitle {
    AccessKindType kind = [self pp_resolvedKind];
    BOOL isFood = (kind == AccessTypeFood);
    BOOL isLivePets = (kind == AccessTypeLivePets);

    // Toggle condition row
    XLFormRowDescriptor *cond = [self.form formRowWithTag:@"condition"];
    cond.hidden   = @(isFood);
    cond.disabled = @(isFood);
    if (isFood && [cond.selectorOptions count] > 0) {
        cond.value = cond.selectorOptions.firstObject; // force "New"
    }
    [self updateFormRow:cond];

    // Live title only for "add" flow (editing title is locked)
    if (!self.editingAccessory) {
        if (isFood) self.title = kLang(@"AddFood");
        else if (isLivePets) self.title = kLang(@"AddLivePet");
        else self.title = kLang(@"AddAccessory");
    }
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;

    [self pp_backfillMissingEditFieldsIfNeeded];
    
       if (!self.editingAccessory) {
           // New accessory — nothing to prefill
       }

       // ✅ Now build the form using the final values of showTypeRow/defaultKind
       [self setForm:[self buildFormWithAccessory:self.editingAccessory]];
       [self pp_refreshFinalPriceRow];

       // (keep your existing main kinds fetch, etc.)
       if (AppMgr.MainKindsArray.count == 0) {
           __weak typeof(self) weakSelf = self;
           [AppMgr fetchMainKindsWithCompletion:^(NSArray<MainKindsModel *> * _Nullable kinds, NSError * _Nullable error) {
               __strong typeof(weakSelf) self = weakSelf;
               if (error) return;
               XLFormRowDescriptor *mkRow = [self.form formRowWithTag:@"mainKind"];
               mkRow.selectorOptions = kinds ?: @[];
               [self updateFormRow:mkRow];
           }];
       }
    
   /*
    // Ensure Species options loaded; update row if they arrive later
    if (AppMgr.MainKindsArray.count == 0) {
        DLog(@"[AddAccessory] mainKinds empty -> fetching…");
        __weak typeof(self) weakSelf = self;
        [AppMgr fetchMainKindsWithCompletion:^(NSArray<MainKindsModel *> * _Nullable kinds, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (error) {
                DLog(@"[AddAccessory] fetchMainKinds error: %@", error.localizedDescription);
                return;
            }
            XLFormRowDescriptor *mkRow = [self.form formRowWithTag:@"mainKind"];
            mkRow.selectorOptions = kinds ?: @[];
            [self updateFormRow:mkRow];
            DLog(@"[AddAccessory] mainKinds loaded: %lu", (unsigned long)kinds.count);
        }];
    }
    */
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    
    // Premium Form TableView Styling
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor colorWithWhite:0 alpha:0.04];
    self.tableView.contentInset = UIEdgeInsetsMake(12, 0, 30, 0);
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    AccessKindType kind = [self pp_resolvedKind];
    BOOL isFood = (kind == AccessTypeFood);
    BOOL isLivePets = (kind == AccessTypeLivePets);

    NSString *title = @"";
    if (self.editingAccessory) {
        if (isFood) title = kLang(@"EditFood");
        else if (isLivePets) title = kLang(@"EditLivePet");
        else title = kLang(@"EditAccessory");
    } else {
        if (isFood) title = kLang(@"AddFood");
        else if (isLivePets) title = kLang(@"AddLivePet");
        else title = kLang(@"AddAccessory");
    }

    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    [self pp_navBarWithOtherButton:save title:title];
}
- (void)onSave { [self saveAccessory]; }
- (void)onBack { [self.navigationController popViewControllerAnimated:YES]; }



- (UIButton *)circleButton:(NSString *)sfName action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setImage:[UIImage systemImageNamed:sfName] forState:UIControlStateNormal];
    b.tintColor = AppPrimaryClr;
    b.contentEdgeInsets = UIEdgeInsetsMake(6,6,6,6);
    b.layer.cornerRadius = 18;
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.05]; // subtle touch target
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:38],
        [b.heightAnchor constraintEqualToConstant:38]
    ]];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}



#pragma mark - Save

- (void)saveAccessory {
    NSDictionary *values = [self.form formValues];
    DLog(@"[AddAccessory] saveAccessory tapped. values=%@", values);

    NSString *name = [[NSString stringWithFormat:@"%@", values[@"name"] ?: @""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSNumber *price = [self pp_numberFromValue:values[@"price"]];
    NSNumber *discountPercentInput = [self pp_numberFromValue:values[@"discountPercent"]];
    NSNumber *discountAmountInput = [self pp_numberFromValue:values[@"discountAmount"]];
    NSInteger quantity = [self pp_integerFromValue:values[@"quantity"] defaultValue:0];
    MainKindsModel *mk = values[@"mainKind"];
    SubKindModel *sk = values[@"subKind"];
    NSString *storeID = [self pp_storeIDFromFormValue:values[@"store"]];
    if (storeID.length == 0) storeID = PPMainStoreID;
    NSString *storeName = [self pp_storeNameForID:storeID];

    if (name.length == 0 || !price) {
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"NamePriceRequired")];
        return;
    }
    if (!mk) {
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"SpeciesPlaceholder")];
        return;
    }

    [PPHUD showRingIn:self.view title:kLang(@"Uploading") subtitle:kLang(@"PleaseWait")];

    PetAccessory *accessory = self.editingAccessory ?: [PetAccessory new];
    accessory.name = name;
    accessory.desc = [NSString stringWithFormat:@"%@", values[@"desc"] ?: @""];
    accessory.price = price;
    CGFloat clampedDiscountPercent = MIN(100.0, MAX(0.0, discountPercentInput.floatValue));
    accessory.discountPercent = (clampedDiscountPercent > 0.0) ? @(clampedDiscountPercent) : nil;
    accessory.discountAmount = (discountAmountInput.floatValue > 0.0) ? @(MAX(0.0, discountAmountInput.floatValue)) : nil;
    accessory.quantity = MAX(0, quantity);

    NSInteger defaultCondition = (accessory.condition == AccessConditionsUsed) ? AccessConditionsUsed : AccessConditionsNew;
    accessory.condition = [self pp_optionValueFromFormValue:values[@"condition"] defaultValue:defaultCondition];

    // Species / Breed IDs
    accessory.petMainCategoryID = mk ? mk.ID : 0;
    accessory.petSubCategoryID = sk ? sk.ID : 0;

    AccessKindType resolved = [self pp_resolvedKind];
    accessory.accessKindType = resolved;
    if (resolved == AccessTypeFood) {
        accessory.condition = AccessConditionsNew;
    }

    accessory.createdAt = accessory.createdAt ?: [NSDate date];
    if (accessory.ownerID.length == 0) {
        accessory.ownerID = [FIRAuth auth].currentUser.uid ?: @"";
    }
    accessory.storeID = storeID;
    accessory.storeName = storeName.length > 0 ? storeName : [self pp_mainStoreDisplayName];

    // Expiry date (optional)
    id expiryVal = values[@"expiryDate"];
    accessory.expiryDate = [expiryVal isKindOfClass:[NSDate class]] ? expiryVal : nil;

    accessory.active = YES;
    [accessory normalizeInventoryState];

    NSArray<UIImage *> *images = [self pp_selectedImages];
    BOOL modified = [self pp_imagesModified];
    DLog(@"[AddAccessory] selected images count = %lu, modified = %d", (unsigned long)images.count, modified);
    NSDictionary<NSString *, NSDictionary *> *existingMetaByURL = [self pp_existingMetaByURLForAccessory:self.editingAccessory ?: accessory];

    // Keep existing images when editing and user hasn't changed the selection.
    if (!modified && self.editingAccessory.imageURLsArray.count > 0) {
        DLog(@"[AddAccessory] images not modified; keeping existing URLs and saving meta.");
        accessory.imageURLsArray = self.editingAccessory.imageURLsArray ?: @[];
        accessory.imageMeta = [self pp_imageMetaForURLs:accessory.imageURLsArray
                                      existingMetaByURL:existingMetaByURL
                                      uploadedMetaByURL:@{}];
        [[AccessoryManager shared] createOrUpdateAccessory:accessory completion:^(NSError * _Nullable error) {
            [self handleSaveResult:error];
        }];
        return;
    }

    // Capture old image URLs before uploading replacements
    NSArray<NSString *> *oldImageURLs = self.editingAccessory.imageURLsArray ?: @[];

    // Upload all selected images
    NSMutableArray<NSString *> *uploadedURLs = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSDictionary *> *uploadedMetaByURL = [NSMutableDictionary dictionary];
    __block NSError *uploadError = nil;
    NSObject *uploadLock = [NSObject new];

    FIRStorageReference *storageRef = [[FIRStorage storage] reference];
    dispatch_group_t group = dispatch_group_create();

    for (UIImage *image in images) {
        NSData *data = UIImagePNGRepresentation(image);
        if (!data) continue;

        dispatch_group_enter(group);
        NSString *uuid = [[NSUUID UUID] UUIDString];
        FIRStorageReference *imgRef = [[storageRef child:@"petAccessories"] child:[NSString stringWithFormat:@"%@.png", uuid]];
        DLog(@"[AddAccessory] uploading image %@", uuid);

        [imgRef putData:data metadata:nil completion:^(FIRStorageMetadata *metadata, NSError *error) {
            if (error) {
                DLog(@"[AddAccessory] upload error: %@", error.localizedDescription);
                @synchronized (uploadLock) {
                    if (!uploadError) uploadError = error;
                }
                dispatch_group_leave(group);
                return;
            }
            [imgRef downloadURLWithCompletion:^(NSURL *URL, NSError *error2) {
                @synchronized (uploadLock) {
                    if (URL.absoluteString.length > 0) {
                        [uploadedURLs addObject:URL.absoluteString];
                        uploadedMetaByURL[URL.absoluteString] = [self pp_metaForURL:URL.absoluteString
                                                                                width:image.size.width
                                                                               height:image.size.height];
                    }
                    if (error2 && !uploadError) uploadError = error2;
                }
                DLog(@"[AddAccessory] uploaded -> %@", URL.absoluteString);
                dispatch_group_leave(group);
            }];
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSArray<NSString *> *uploadedSnapshot = nil;
        NSDictionary<NSString *, NSDictionary *> *uploadedMetaSnapshot = nil;
        NSError *uploadErrorSnapshot = nil;
        @synchronized (uploadLock) {
            uploadedSnapshot = [uploadedURLs copy];
            uploadedMetaSnapshot = [uploadedMetaByURL copy];
            uploadErrorSnapshot = uploadError;
        }

        if (uploadedSnapshot.count > 0) {
            accessory.imageURLsArray = uploadedSnapshot;
        } else if (images.count == 0) {
            accessory.imageURLsArray = self.editingAccessory.imageURLsArray ?: @[];
        } else {
            accessory.imageURLsArray = @[];
        }
        accessory.imageMeta = [self pp_imageMetaForURLs:accessory.imageURLsArray
                                      existingMetaByURL:existingMetaByURL
                                      uploadedMetaByURL:uploadedMetaSnapshot ?: @{}];

        if (uploadErrorSnapshot && uploadedSnapshot.count == 0) {
            [self handleSaveResult:uploadErrorSnapshot];
            return;
        }

        DLog(@"[AddAccessory] all uploads done. saving accessory…");
        [[AccessoryManager shared] createOrUpdateAccessory:accessory completion:^(NSError * _Nullable error) {
            if (!error && uploadedSnapshot.count > 0 && oldImageURLs.count > 0) {
                // Delete old images that were replaced
                NSSet *newURLSet = [NSSet setWithArray:uploadedSnapshot];
                for (NSString *oldURL in oldImageURLs) {
                    if (oldURL.length == 0 || [newURLSet containsObject:oldURL]) continue;
                    @try {
                        FIRStorageReference *oldRef = [[FIRStorage storage] referenceForURL:oldURL];
                        [oldRef deleteWithCompletion:^(NSError * _Nullable delErr) {
                            if (delErr) {
                                DLog(@"[AddAccessory] failed to delete old image: %@", delErr.localizedDescription);
                            } else {
                                DLog(@"[AddAccessory] deleted old image: %@", oldURL);
                            }
                        }];
                    } @catch (NSException *exception) {
                        DLog(@"[AddAccessory] invalid storage URL for cleanup: %@", oldURL);
                    }
                }
            }
            [self handleSaveResult:error];
        }];
    });
}

- (void)handleSaveResult:(NSError *)error {
    if (error) {
        [PPHUD dismiss];
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Something went wrong.")];
        DLog(@"[AddAccessory] save error: %@", error.localizedDescription);
        return;
    }
    [PPHUD showSuccess:kLang(@"Saved") subtitle:kLang(@"AccessoryPosted")];

    DLog(@"[AddAccessory] save success");
    // pop after a short delay so user sees the success
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

#pragma mark - Helpers (Species/Breed)

- (NSArray<MainKindsModel *> *)allMainKinds {
    return AppMgr.MainKindsArray ?: @[];
}

- (MainKindsModel *)mainKindForID:(NSInteger)kindID {
    for (MainKindsModel *m in [self allMainKinds]) {
        if (m.ID == kindID) return m;
    }
    return nil;
}

- (SubKindModel *)subKindForID:(NSInteger)subID mainID:(NSInteger)mainID {
    MainKindsModel *main = [self mainKindForID:mainID];
    if (!main) return nil;
    for (SubKindModel *s in main.SubKindsArray) {
        if (s.ID == subID) return s;
    }
    return nil;
}

#pragma mark - Subview Finder

- (UIView *)findSubviewOfClass:(Class)cls inView:(UIView *)view {
    if ([view isKindOfClass:cls]) return view;
    for (UIView *subview in view.subviews) {
        UIView *found = [self findSubviewOfClass:cls inView:subview];
        if (found) return found;
    }
    return nil;
}

#pragma mark - TableView Custom Headers & Footers

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)sectionIndex {
    XLFormSectionDescriptor *section = self.form.formSections[sectionIndex];
    if (section.title.length == 0) return 12.0;
    return 36.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)sectionIndex {
    XLFormSectionDescriptor *section = self.form.formSections[sectionIndex];
    if (section.title.length == 0) return nil;
    
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;
    
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont fontWithName:@"Beiruti-Medium" size:13] ?: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textColor = SeconderyTextClr;
    label.text = [section.title uppercaseString];
    label.textAlignment = Language.isRTL ? NSTextAlignmentRight : NSTextAlignmentLeft;
    
    [header addSubview:label];
    
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-6.0]
    ]];
    
    return header;
}

#pragma mark - Table BG

static const void *kHasAnimatedFormCellKey = &kHasAnimatedFormCellKey;

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {

    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO];

    // Dynamic Premium Font and Color Overrides for Form Rows
    cell.textLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:15] ?: [UIFont systemFontOfSize:15];
    cell.textLabel.textColor = PrimaryTextClr;
    
    cell.detailTextLabel.font = [UIFont fontWithName:@"Beiruti-Regular" size:15] ?: [UIFont systemFontOfSize:15];
    cell.detailTextLabel.textColor = SeconderyTextClr;
    
    UITextField *textField = (UITextField *)[self findSubviewOfClass:[UITextField class] inView:cell];
    if (textField) {
        textField.font = [UIFont fontWithName:@"Beiruti-Regular" size:15] ?: [UIFont systemFontOfSize:15];
        textField.textColor = PrimaryTextClr;
    }
    
    UITextView *textView = (UITextView *)[self findSubviewOfClass:[UITextView class] inView:cell];
    if (textView) {
        textView.font = [UIFont fontWithName:@"Beiruti-Regular" size:15] ?: [UIFont systemFontOfSize:15];
        textView.textColor = PrimaryTextClr;
    }
    
    UISegmentedControl *segmented = (UISegmentedControl *)[self findSubviewOfClass:[UISegmentedControl class] inView:cell];
    if (segmented) {
        segmented.selectedSegmentTintColor = AppPrimaryClr;
        
        NSDictionary *normalAttributes = @{
            NSFontAttributeName: [UIFont fontWithName:@"Beiruti-Medium" size:13] ?: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: SeconderyTextClr
        };
        NSDictionary *selectedAttributes = @{
            NSFontAttributeName: [UIFont fontWithName:@"Beiruti-Bold" size:13] ?: [UIFont boldSystemFontOfSize:13],
            NSForegroundColorAttributeName: [UIColor whiteColor]
        };
        [segmented setTitleTextAttributes:normalAttributes forState:UIControlStateNormal];
        [segmented setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
        segmented.layer.cornerRadius = 10.0;
        segmented.clipsToBounds = YES;
    }

    // Spring Staggered Entrance Animation for Form Rows
    if (!objc_getAssociatedObject(cell, kHasAnimatedFormCellKey)) {
        objc_setAssociatedObject(cell, kHasAnimatedFormCellKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        cell.alpha = 0.0;
        cell.transform = CGAffineTransformMakeTranslation(0, 16.0);
        
        [UIView animateWithDuration:0.5
                              delay:0.03 * indexPath.row
             usingSpringWithDamping:0.85
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

@end
