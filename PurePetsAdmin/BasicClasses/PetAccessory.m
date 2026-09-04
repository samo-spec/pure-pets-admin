#import "PetAccessory.h"
#import "ArabicNormalizer.h"
#import "MainKindsArrayManager.h"
#import "PPBranchContextManager.h"
#import "PPBranchModel.h"
#import <math.h>

@interface PetImageItem (PPAccessoryMetadata)
+ (nullable instancetype)itemWithMediaMetadata:(NSDictionary *)metadata;
@end

@implementation PetImageItem (PPAccessoryMetadata)
+ (nullable instancetype)itemWithMediaMetadata:(NSDictionary *)metadata {
    if (![metadata isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *url = metadata[@"url"];
    if (![url isKindOfClass:NSString.class] || url.length == 0) {
        url = metadata[@"thumbnail_url"];
    }
    if (![url isKindOfClass:NSString.class] || url.length == 0) {
        return nil;
    }
    id widthValue = metadata[@"width"];
    id heightValue = metadata[@"height"];
    CGFloat width = [widthValue respondsToSelector:@selector(doubleValue)] ? [widthValue doubleValue] : 0.0;
    CGFloat height = [heightValue respondsToSelector:@selector(doubleValue)] ? [heightValue doubleValue] : 0.0;
    NSString *blurHash = [metadata[@"blurHash"] isKindOfClass:NSString.class] ? metadata[@"blurHash"] : nil;
    return [[PetImageItem alloc] initWithURL:url width:width height:height blurHash:blurHash];
}
@end


@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;

#ifdef DEBUG
BOOL const isPPDebugMode = YES;
#else
BOOL const isPPDebugMode = NO;
#endif

@interface PetAccessory ()
@property (nonatomic, copy) NSString *searchTitle;
@property (nonatomic, assign, readwrite) BOOL hasResolvedSellingPrice;
+ (UIViewController *)pp_topViewController;
+ (UIViewController *)pp_topViewControllerFromRoot:(UIViewController *)rootViewController;
@end

static NSDate *PPDateFromFirestoreValue(id value) {
    if (!value || [value isKindOfClass:[NSNull class]]) {
        return [NSDate distantPast];
    }
    if ([value isKindOfClass:NSDate.class]) {
        return (NSDate *)value;
    }
    if ([value isKindOfClass:FIRTimestamp.class]) {
        return [(FIRTimestamp *)value dateValue];
    }
    if ([value isKindOfClass:NSNumber.class]) {
        NSTimeInterval t = [(NSNumber *)value doubleValue];
        if (t > 10000000000.0) t /= 1000.0;
        return [NSDate dateWithTimeIntervalSince1970:t];
    }
    if ([value isKindOfClass:NSString.class]) {
        NSTimeInterval t = [(NSString *)value doubleValue];
        if (t > 0) {
            if (t > 10000000000.0) t /= 1000.0;
            return [NSDate dateWithTimeIntervalSince1970:t];
        }
    }
    return [NSDate distantPast];
}

static NSDate * _Nullable PPNullableDateFromFirestoreValue(id value) {
    if (!value || [value isKindOfClass:NSNull.class]) return nil;
    if ([value isKindOfClass:NSDate.class]) return (NSDate *)value;
    if ([value isKindOfClass:FIRTimestamp.class]) return [(FIRTimestamp *)value dateValue];
    return nil;
}

static NSString *PPAccessoryTrimmedString(id value) {
    if ([value isKindOfClass:[NSNull class]] || value == nil) {
        return @"";
    }
    NSString *string = nil;
    if ([value isKindOfClass:[NSString class]]) {
        string = (NSString *)value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        string = [(NSNumber *)value stringValue];
    }
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSString *PPAccessoryStringValueForKeys(NSDictionary *dict, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSString *value = PPAccessoryTrimmedString(dict[key]);
        if (value.length > 0) {
            return value;
        }
    }
    return @"";
}

static NSNumber *PPAccessoryNumberValueForKeys(NSDictionary *dict, NSArray<NSString *> *keys) {
    static NSNumberFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
    });

    for (NSString *key in keys) {
        id value = dict[key];
        if ([value isKindOfClass:[NSNumber class]]) {
            return value;
        }
        NSString *string = PPAccessoryTrimmedString(value);
        if (string.length > 0) {
            NSNumber *number = [formatter numberFromString:string];
            if (number) {
                return number;
            }
        }
    }
    return nil;
}

static NSNumber * _Nullable PPAccessorySellingPriceValueForKeys(NSDictionary *dict, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSNumber *candidate = PPAccessoryNumberValueForKeys(dict, @[key]);
        if (!candidate) continue;
        double value = candidate.doubleValue;
        if (isfinite(value) && value >= 0.0) {
            return candidate;
        }
    }
    return nil;
}

static NSArray<NSString *> *PPAccessoryStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (id candidate in (NSArray *)value) {
        NSString *string = PPAccessoryTrimmedString(candidate);
        if (string.length > 0) [strings addObject:string];
    }
    return [strings copy];
}

static NSArray<NSDictionary *> *PPAccessoryDictionaryArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSDictionary *> *dictionaries = [NSMutableArray array];
    for (id candidate in (NSArray *)value) {
        if ([candidate isKindOfClass:NSDictionary.class]) {
            [dictionaries addObject:candidate];
        }
    }
    return [dictionaries copy];
}

static NSArray<NSDictionary *> *PPNormalizedImageMeta(NSArray<NSString *> *urls, NSArray<NSDictionary *> *meta) {
    NSMutableArray<NSDictionary *> *normalized = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSInteger i = 0; i < urls.count; i++) {
        NSString *url = [urls[i] isKindOfClass:NSString.class] ? urls[i] : @"";
        NSDictionary *m = (i < meta.count && [meta[i] isKindOfClass:NSDictionary.class]) ? meta[i] : nil;
        id widthValue = m[@"width"];
        id heightValue = m[@"height"];
        CGFloat width = [widthValue respondsToSelector:@selector(doubleValue)] ? [widthValue doubleValue] : 0.0;
        CGFloat height = [heightValue respondsToSelector:@selector(doubleValue)] ? [heightValue doubleValue] : 0.0;
        [normalized addObject:@{
            @"url": url,
            @"width": @(MAX(0.0, width)),
            @"height": @(MAX(0.0, height))
        }];
    }
    return [normalized copy];
}

static NSArray<NSDictionary *> *PPImageItemsPayload(NSArray<NSString *> *urls, NSArray<NSDictionary *> *meta, NSString *blurHash) {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSInteger i = 0; i < urls.count; i++) {
        NSString *url = [urls[i] isKindOfClass:NSString.class] ? urls[i] : @"";
        NSDictionary *m = (i < meta.count && [meta[i] isKindOfClass:NSDictionary.class]) ? meta[i] : nil;
        id widthValue = m[@"width"];
        id heightValue = m[@"height"];
        CGFloat width = [widthValue respondsToSelector:@selector(doubleValue)] ? [widthValue doubleValue] : 0.0;
        CGFloat height = [heightValue respondsToSelector:@selector(doubleValue)] ? [heightValue doubleValue] : 0.0;
        NSMutableDictionary *item = [@{
            @"url": url,
            @"width": @(MAX(0.0, width)),
            @"height": @(MAX(0.0, height))
        } mutableCopy];
        if (blurHash.length > 0) {
            item[@"blurHash"] = blurHash;
        }
        [items addObject:[item copy]];
    }
    return [items copy];
}

@implementation PetAccessory

@synthesize price = _price;
@synthesize hasResolvedSellingPrice = _hasResolvedSellingPrice;

- (instancetype)init {
    if (self = [super init]) {
        _name = @"";
        _sku = @"";
        _barcode = @"";
        _costPrice = nil;
        _desc = @"";
        _price = @(0);
        _hasResolvedSellingPrice = NO;
        _ownerID = @"";
        _storeID = @"";
        _storeName = @"";
        _branchID = @"";
        _branchCode = @"";
        _imageURLsArray = @[];
        _createdAt = [NSDate date];
        _accessKindType = AccessTypeAccessory;
        _condition = AccessConditionsNew;
        _active = YES;
        _quantity = 0;
        _noStock = YES;
        _searchTitle = @"";
    }
    return self;
}

- (void)setPrice:(NSNumber *)price {
    id candidate = price;
    if ([candidate isKindOfClass:NSNumber.class]) {
        double value = [(NSNumber *)candidate doubleValue];
        if (isfinite(value) && value >= 0.0) {
            _price = [(NSNumber *)candidate copy];
            _hasResolvedSellingPrice = YES;
            return;
        }
    }

    // Keep the Objective-C/Swift surface nonnull while retaining whether the
    // backend actually supplied a selling price. Never reinterpret unknown as
    // a real zero-price item.
    _price = @(0);
    _hasResolvedSellingPrice = NO;
}

- (NSDictionary *)toFirestoreDictionary {
    [self normalizeInventoryState];

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // Basic info
    if (self.name) dict[@"name"] = self.name;
    dict[@"searchTitle"] = [ArabicNormalizer normalize:self.name ?: @""];
    dict[@"sku"] = self.sku.length > 0 ? self.sku : [NSNull null];
    dict[@"barcode"] = self.barcode.length > 0 ? self.barcode : [NSNull null];
    dict[@"costPrice"] = self.costPrice ?: [NSNull null];
    if (self.desc) dict[@"desc"] = self.desc;
    if (self.hasResolvedSellingPrice) dict[@"price"] = self.price;

    // Discount fields
    // The editor uses merge writes, so explicit nulls are required to clear a
    // discount that existed on the previous revision.
    dict[@"discountPercent"] = self.discountPercent ?: [NSNull null];
    dict[@"discountAmount"] = self.discountAmount ?: [NSNull null];
    if (self.weightText.length > 0) {
        dict[@"weightText"] = self.weightText;
    } else {
        dict[@"weightText"] = [NSNull null];
    }
    if (self.weight) {
        dict[@"weight"] = self.weight;
    } else {
        dict[@"weight"] = [NSNull null];
    }
    if (self.weightUnit.length > 0) {
        dict[@"weightUnit"] = self.weightUnit;
    } else {
        dict[@"weightUnit"] = [NSNull null];
    }

    // Images
    if (self.imageURLsArray) dict[@"imageURLsArray"] = self.imageURLsArray;
    NSArray<NSDictionary *> *normalizedMeta = PPNormalizedImageMeta(self.imageURLsArray ?: @[], self.imageMeta ?: @[]);
    if (normalizedMeta.count > 0) {
        dict[@"imageMeta"] = normalizedMeta;
        dict[@"imageItems"] = PPImageItemsPayload(self.imageURLsArray ?: @[], normalizedMeta, self.blurHash ?: @"");
    } else {
        dict[@"imageMeta"] = self.imageMeta ?: @[];
        dict[@"imageItems"] = @[];
    }
    dict[@"blurHash"] = self.blurHash ?: @"";

    // Categories
    dict[@"petMainCategoryID"] = @(self.petMainCategoryID);
    dict[@"petSubCategoryID"] = @(self.petSubCategoryID);
    if (self.AccessoryCategoryID) dict[@"AccessoryCategoryID"] = self.AccessoryCategoryID;
    dict[@"cityID"] = @(self.cityID);

    // Dates and ownership
    if (self.createdAt) {
        dict[@"createdAt"] = [FIRTimestamp timestampWithDate:self.createdAt];
    }
    if (self.expiryDate) {
        dict[@"expiryDate"] = [FIRTimestamp timestampWithDate:self.expiryDate];
    } else {
        dict[@"expiryDate"] = [NSNull null];
    }
    if (self.ownerID.length > 0) dict[@"ownerID"] = self.ownerID;
    if (self.branchID.length > 0) {
        dict[@"branchID"] = self.branchID;
        dict[@"branchId"] = self.branchID;
    } else if (self.storeID.length > 0 && ![self.storeID isEqualToString:@"main_store"]) {
        dict[@"branchID"] = self.storeID;
        dict[@"branchId"] = self.storeID;
    }
    if (self.branchCode.length > 0) dict[@"branchCode"] = self.branchCode;
    if (self.storeID.length > 0) dict[@"storeID"] = self.storeID;
    if (self.storeName.length > 0) dict[@"storeName"] = self.storeName;
    if (self.ownerType) dict[@"ownerType"] = self.ownerType;
    if (self.source) dict[@"source"] = self.source;

    // Enums
    dict[@"accessKindType"] = @(self.accessKindType);
    dict[@"condition"] = @(self.condition);

    // Stock and status
    dict[@"quantity"] = @([self normalizedQuantity]);
    dict[@"noStock"] = @(self.noStock);
    dict[@"active"] = @(self.active);
    dict[@"isNew"] = @(self.isNew);
    dict[@"hasOffer"] = @(self.hasOffer);
    dict[@"showInAppMarket"] = @(self.showInAppMarket);
    dict[@"isBlocked"] = @(self.isBlocked);
    dict[@"isDeleted"] = @(self.isDeleted);
    dict[@"isDisabled"] = @(self.isDisabled);

    // Calculate and include final price
    if (self.hasResolvedSellingPrice) {
        dict[@"finalPrice"] = [self calculateFinalPrice];
    }

    // Add timestamps for Firestore
    dict[@"updatedAt"] = [FIRTimestamp timestampWithDate:[NSDate date]];

    return [dict copy];
}

- (NSNumber *)calculateFinalPrice {
    if (!self.hasResolvedSellingPrice || ![self.price isKindOfClass:NSNumber.class]) return @(0);

    double basePrice = [self.price doubleValue];
    if (!isfinite(basePrice) || basePrice < 0.0) return @(0);
    double finalPrice = basePrice;

    // Apply percentage discount first
    double discountPercent = [self.discountPercent isKindOfClass:NSNumber.class]
        ? self.discountPercent.doubleValue
        : 0.0;
    if (isfinite(discountPercent) && discountPercent > 0.0) {
        double discount = (basePrice * discountPercent) / 100.0;
        finalPrice = basePrice - discount;
    }

    // Apply absolute discount
    double discountAmount = [self.discountAmount isKindOfClass:NSNumber.class]
        ? self.discountAmount.doubleValue
        : 0.0;
    if (isfinite(discountAmount) && discountAmount > 0.0) {
        finalPrice = finalPrice - discountAmount;
    }
    
    // Ensure price doesn't go negative
    if (finalPrice < 0) finalPrice = 0;
    
    return @(finalPrice);
}

- (NSString *)stockStatusText {
    NSInteger qty = [self normalizedQuantity];
    if (qty <= 0) {
        return kLang(@"Out of stock");
    } else if (qty <= 5) {
        return [NSString stringWithFormat:@"%@ %ld %@", kLang(@"Only"), (long)qty, kLang(@"leftInStock")];
    } else {
        return kLang(@"inStock");
    }
}

- (NSInteger)normalizedQuantity {
    return MAX(0, self.quantity);
}

- (void)normalizeInventoryState {
    self.quantity = [self normalizedQuantity];
    self.noStock = (self.quantity <= 0);

    if (self.accessKindType != AccessTypeAccessory &&
        self.accessKindType != AccessTypeFood &&
        self.accessKindType != AccessTypeLivePets &&
        self.accessKindType != AccessTypePetMedicine) {
        self.accessKindType = AccessTypeAccessory;
    }
    if (self.accessKindType == AccessTypeFood) {
        self.condition = AccessConditionsNew;
    } else if (self.condition != AccessConditionsNew && self.condition != AccessConditionsUsed) {
        self.condition = AccessConditionsNew;
    }
}

- (NSArray<PetImageItem *> *)imageItems {
    NSMutableArray *items = [NSMutableArray array];
    
    for (NSInteger i = 0; i < self.imageURLsArray.count; i++) {
        NSString *url = self.imageURLsArray[i];
        NSDictionary *meta = (i < self.imageMeta.count) ? self.imageMeta[i] : nil;

        PetImageItem *mediaItem = [PetImageItem itemWithMediaMetadata:meta];
        if (mediaItem) {
            [items addObject:mediaItem];
            continue;
        }
        
        CGFloat width = [meta[@"width"] floatValue] ?: 0;
        CGFloat height = [meta[@"height"] floatValue] ?: 0;
        
        PetImageItem *item = [[PetImageItem alloc] initWithURL:url
                                                         width:width
                                                        height:height blurHash:nil];
        [items addObject:item];
    }

    if (items.count == 0 && self.imageMeta.count > 0) {
        for (NSDictionary *meta in self.imageMeta) {
            PetImageItem *mediaItem = [PetImageItem itemWithMediaMetadata:meta];
            if (mediaItem) {
                [items addObject:mediaItem];
            }
        }
    }
    
    return [items copy];
}

- (NSNumber *)finalPrice {
    return [self calculateFinalPrice];
}

- (BOOL)isLivePet {
    return self.accessKindType == AccessTypeLivePet;
}

- (BOOL)isFood {
    return self.accessKindType == AccessTypeFood;
}

- (BOOL)isPetMedicine {
    return self.accessKindType == AccessTypePetMedicine;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    if (self = [super init]) {
        _accessoryID = docID ?: @"";
        _name = PPAccessoryStringValueForKeys(dict, (@[@"name", @"title"]));
        _sku = PPAccessoryStringValueForKeys(dict, (@[@"sku", @"SKU", @"itemSku"]));
        _barcode = PPAccessoryStringValueForKeys(dict, (@[@"barcode", @"Barcode", @"barCode", @"upc", @"ean"]));
        _costPrice = PPAccessoryNumberValueForKeys(dict, (@[@"costPrice", @"cost_price", @"cost"]));
        _desc = PPAccessoryStringValueForKeys(dict, (@[@"desc", @"description"]));

        // Individually tracked live-pet parent documents intentionally expose
        // a null aggregate price when no available unit has a selling price.
        // Prefer the base catalog price, then the server-derived display hint,
        // while preserving an explicit unresolved state when all are absent.
        NSNumber *basePrice = PPAccessorySellingPriceValueForKeys(dict, (@[@"price", @"sellPrice"]));
        NSNumber *projectedPrice = PPAccessorySellingPriceValueForKeys(dict, (@[@"finalPrice", @"availableUnitPriceMin"]));
        NSNumber *resolvedPrice = basePrice;
        if (!resolvedPrice || (resolvedPrice.doubleValue <= 0.0 && projectedPrice.doubleValue > 0.0)) {
            resolvedPrice = projectedPrice ?: resolvedPrice;
        }
        [self setPrice:resolvedPrice];
        _discountPercent = PPAccessoryNumberValueForKeys(dict, (@[@"discountPercent"]));
        _discountAmount = PPAccessoryNumberValueForKeys(dict, (@[@"discountAmount"]));
        _weightText = PPAccessoryStringValueForKeys(dict, (@[
            @"weightText",
            @"weightLabel",
            @"packageWeightText",
            @"netWeightText",
            @"itemWeightText"
        ]));
        _weight = PPAccessoryNumberValueForKeys(dict, (@[
            @"weight",
            @"packageWeight",
            @"netWeight",
            @"itemWeight",
            @"unitWeight"
        ]));
        _weightUnit = PPAccessoryStringValueForKeys(dict, (@[
            @"weightUnit",
            @"unit",
            @"packageUnit",
            @"measurementUnit",
            @"weight_unit"
        ]));
        _imageURLsArray = PPAccessoryStringArray(dict[@"imageURLsArray"]);
        _imageMeta = PPAccessoryDictionaryArray(dict[@"imageMeta"]);
        NSArray *imageItemsPayload = PPAccessoryDictionaryArray(dict[@"imageItems"]);
        if (_imageURLsArray.count == 0 && imageItemsPayload.count > 0) {
            NSMutableArray<NSString *> *urls = [NSMutableArray arrayWithCapacity:imageItemsPayload.count];
            for (NSDictionary *item in imageItemsPayload) {
                if (![item isKindOfClass:NSDictionary.class]) continue;
                NSString *url = [item[@"url"] isKindOfClass:NSString.class] ? item[@"url"] : @"";
                if (url.length > 0) [urls addObject:url];
            }
            _imageURLsArray = [urls copy];
        }
        if ((_imageMeta == nil || _imageMeta.count == 0) && imageItemsPayload.count > 0) {
            NSMutableArray<NSDictionary *> *meta = [NSMutableArray arrayWithCapacity:imageItemsPayload.count];
            for (NSDictionary *item in imageItemsPayload) {
                if (![item isKindOfClass:NSDictionary.class]) continue;
                NSString *url = [item[@"url"] isKindOfClass:NSString.class] ? item[@"url"] : @"";
                id widthValue = item[@"width"];
                id heightValue = item[@"height"];
                CGFloat width = [widthValue respondsToSelector:@selector(doubleValue)] ? [widthValue doubleValue] : 0.0;
                CGFloat height = [heightValue respondsToSelector:@selector(doubleValue)] ? [heightValue doubleValue] : 0.0;
                [meta addObject:@{
                    @"url": url,
                    @"width": @(MAX(0.0, width)),
                    @"height": @(MAX(0.0, height))
                }];
            }
            _imageMeta = [meta copy];
        }
        _petMainCategoryID = [dict[@"petMainCategoryID"] integerValue];
        _petSubCategoryID = [dict[@"petSubCategoryID"] integerValue];
        _AccessoryCategoryID = [dict[@"AccessoryCategoryID"] isKindOfClass:NSString.class] ? dict[@"AccessoryCategoryID"] : nil;
        _cityID = [dict[@"cityID"] ?: @(0) integerValue];
        
        id rawCreated = dict[@"createdAt"] ?: dict[@"created_at"] ?: dict[@"timestamp"] ?: dict[@"date"] ?: dict[@"updatedAt"];
        _createdAt = PPDateFromFirestoreValue(rawCreated);
        _expiryDate = PPNullableDateFromFirestoreValue(dict[@"expiryDate"]);

        _ownerID = PPAccessoryStringValueForKeys(dict, (@[@"ownerID"]));
        _branchID = PPAccessoryStringValueForKeys(dict, (@[@"branchID", @"branchId", @"branch_id"]));
        _branchCode = PPAccessoryStringValueForKeys(dict, (@[@"branchCode", @"branch_code"]));
        _storeID = PPAccessoryStringValueForKeys(dict, (@[@"storeID", @"storeId"]));
        _storeName = PPAccessoryStringValueForKeys(dict, (@[@"storeName", @"branchName"]));

        if (_branchID.length == 0 && _storeID.length > 0 && ![_storeID isEqualToString:@"main_store"]) {
            _branchID = _storeID;
        }
        if (_storeID.length == 0 && _branchID.length > 0) {
            _storeID = _branchID;
        }
        _ownerType = [dict[@"ownerType"] isKindOfClass:NSString.class] ? dict[@"ownerType"] : nil;
        _source = [dict[@"source"] isKindOfClass:NSString.class] ? dict[@"source"] : nil;
        _inventoryMode = [dict[@"inventoryMode"] isKindOfClass:NSString.class]
            ? [dict[@"inventoryMode"] uppercaseString]
            : nil;
        _inventorySchemaVersion = [dict[@"inventorySchemaVersion"] integerValue];
        _standardSellingPrice = PPAccessorySellingPriceValueForKeys(dict, (@[@"standardSellingPrice"]));
        _reservedQuantity = MAX(0, [dict[@"reservedQuantity"] integerValue]);
        _isArchived = [dict[@"isArchived"] boolValue];
        _blurHash = PPAccessoryTrimmedString(dict[@"blurHash"]);
        
        _accessKindType = ({
            NSInteger rawKind = [dict[@"accessKindType"] integerValue];
            AccessKindType parsed;
            switch (rawKind) {
                case AccessTypeFood:     parsed = AccessTypeFood;     break;
                case AccessTypeLivePet:  parsed = AccessTypeLivePet;  break;
                case AccessTypePetMedicine: parsed = AccessTypePetMedicine; break;
                default:                 parsed = AccessTypeAccessory; break;
            }
            if (parsed == AccessTypeAccessory) {
                NSString *productType = dict[@"product_type"];
                if ([productType isKindOfClass:[NSString class]] &&
                    [productType caseInsensitiveCompare:@"live"] == NSOrderedSame) {
                    parsed = AccessTypeLivePet;
                }
            }
            parsed;
        });
        
        _condition = [dict[@"condition"] integerValue];
        _isNew = [dict[@"isNew"] boolValue];
        
        if (_condition == AccessConditionsUsed || !_isNew) {
            _condition = AccessConditionsUsed;
            _isNew = NO;
        } else {
            _condition = AccessConditionsNew;
            _isNew = YES;
        }
        
        _hasOffer = [dict[@"hasOffer"] boolValue];
        _showInAppMarket = [dict[@"showInAppMarket"] boolValue];
        _isBlocked = [dict[@"isBlocked"] boolValue];
        _isDeleted = [dict[@"isDeleted"] boolValue];
        _isDisabled = [dict[@"isDisabled"] boolValue];
        _active = dict[@"active"] == nil ? YES : [dict[@"active"] boolValue];

        _quantity = MAX(0, [dict[@"quantity"] integerValue]);
        if (dict[@"noStock"] != nil) {
            _noStock = [dict[@"noStock"] boolValue];
        } else {
            _noStock = (_quantity <= 0);
        }
        
        _searchTitle = PPAccessoryStringValueForKeys(dict, (@[@"searchTitle"]));
        if (_searchTitle.length == 0) {
            _searchTitle = [ArabicNormalizer normalize:_name ?: @""] ?: @"";
        }
        [self normalizeInventoryState];
    }
    return self;
}

+ (instancetype)deepCopyFrom:(PetAccessory *)source {
    PetAccessory *copy = [[PetAccessory alloc] init];
    copy.accessoryID = [source.accessoryID copy];
    copy.name = [source.name copy];
    copy.sku = [source.sku copy];
    copy.barcode = [source.barcode copy];
    copy.costPrice = [source.costPrice copy];
    if (source.hasResolvedSellingPrice) {
        copy.price = [source.price copy];
    }
    copy.discountPercent = [source.discountPercent copy];
    copy.discountAmount = [source.discountAmount copy];
    copy.weightText = [source.weightText copy];
    copy.weight = [source.weight copy];
    copy.weightUnit = [source.weightUnit copy];
    copy.desc = [source.desc copy];
    copy.blurHash = [source.blurHash copy];
    copy.petMainCategoryID = source.petMainCategoryID;
    copy.petSubCategoryID = source.petSubCategoryID;
    copy.AccessoryCategoryID = [source.AccessoryCategoryID copy];
    copy.cityID = source.cityID;
    copy.condition = source.condition;
    copy.accessKindType = source.accessKindType;
    copy.imageURLsArray = [source.imageURLsArray copy];
    copy.imageMeta = [source.imageMeta copy];
    copy.ownerID = [source.ownerID copy];
    copy.storeID = [source.storeID copy];
    copy.storeName = [source.storeName copy];
    copy.branchID = [source.branchID copy];
    copy.branchCode = [source.branchCode copy];
    copy.ownerType = [source.ownerType copy];
    copy.source = [source.source copy];
    copy.inventoryMode = [source.inventoryMode copy];
    copy.inventorySchemaVersion = source.inventorySchemaVersion;
    copy.standardSellingPrice = source.standardSellingPrice;
    copy.reservedQuantity = source.reservedQuantity;
    copy.isArchived = source.isArchived;
    copy.createdAt = [source.createdAt copy];
    copy.expiryDate = [source.expiryDate copy];
    copy.quantity = source.quantity;
    copy.isNew = source.isNew;
    copy.hasOffer = source.hasOffer;
    copy.showInAppMarket = source.showInAppMarket;
    copy.isBlocked = source.isBlocked;
    copy.isDeleted = source.isDeleted;
    copy.isDisabled = source.isDisabled;
    copy.active = source.active;
    copy.noStock = source.noStock;
    [copy normalizeInventoryState];
    return copy;
}

#pragma mark - Sharing

+ (void)sharePetAccessory:(PetAccessory *)accessory fromViewController:(UIViewController *)vc {
    [self sharePetAccessory:accessory fromViewController:vc sourceView:nil];
}

+ (void)sharePetAccessory:(PetAccessory *)accessory
        fromViewController:(UIViewController *)vc
                sourceView:(nullable UIView *)sourceView {
    
    NSString *message = [self shareMessageForAccessory:accessory];
    NSMutableArray *items = [NSMutableArray arrayWithObject:message];
    
    NSURL *imageURL = [self firstImageURLForAccessory:accessory];
    if (imageURL) {
        [items addObject:imageURL];
    }
    
    UIActivityViewController *activityVC = [[UIActivityViewController alloc]
                                            initWithActivityItems:items
                                            applicationActivities:nil];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = sourceView ?: vc.view;
        if (sourceView) {
            activityVC.popoverPresentationController.sourceRect = sourceView.bounds;
        } else {
            activityVC.popoverPresentationController.sourceRect = CGRectMake(
                vc.view.bounds.size.width / 2,
                vc.view.bounds.size.height / 2,
                1, 1
            );
        }
    }
    
    [PPFunc presentSheetFrom:[self pp_topViewController]
                     sheetVC:activityVC
                 detentStyle:PPSheetDetentStyleMediumOnly];
}

- (UIViewController *)topViewController {
    return [PetAccessory pp_topViewController];
}

- (UIViewController *)topViewController:(UIViewController *)rootViewController {
    return [PetAccessory pp_topViewControllerFromRoot:rootViewController];
}

+ (UIViewController *)pp_topViewController {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        NSSet *connectedScenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) { continue; }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) { keyWindow = window; break; }
            }
            if (keyWindow) { break; }
        }
    } else {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    return [self pp_topViewControllerFromRoot:keyWindow.rootViewController];
}

+ (UIViewController *)pp_topViewControllerFromRoot:(UIViewController *)rootViewController {
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController;
        return [self pp_topViewControllerFromRoot:[navigationController.viewControllers lastObject]];
    }
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)rootViewController;
        return [self pp_topViewControllerFromRoot:tabController.selectedViewController];
    }
    if (rootViewController.presentedViewController) {
        return [self pp_topViewControllerFromRoot:rootViewController.presentedViewController];
    }
    return rootViewController;
}

#pragma mark - Share Content Generation

+ (NSString *)shareMessageForAccessory:(PetAccessory *)accessory {
    NSMutableString *message = [NSMutableString string];
    [message appendFormat:@"%@\n\n", kLang(@"Check out this pet accessory!")];
    
    if (accessory.name.length > 0) {
        [message appendFormat:@"%@: %@\n", kLang(@"Name"), accessory.name];
    }
    if (accessory.desc.length > 0) {
        NSString *shortDesc = accessory.desc;
        if (shortDesc.length > 100) {
            shortDesc = [[shortDesc substringToIndex:100] stringByAppendingString:@"..."];
        }
        [message appendFormat:@"%@: %@\n", kLang(@"Description"), shortDesc];
    }
    if (accessory.petMainCategoryID > 0) {
        NSString *mainCategoryName = [MainKindsModel kindNameForID:accessory.petMainCategoryID];
        if (mainCategoryName) {
            [message appendFormat:@"%@: %@\n", kLang(@"Category"), mainCategoryName];
        }
    }
    if (accessory.petSubCategoryID > 0) {
        NSArray *subKinds = [MKM getSubKindArray:accessory.petMainCategoryID];
        NSString *subCategoryName = [SubKindModel getSubKindName:accessory.petSubCategoryID
                                                   subKindsArrayLocal:subKinds];
        if (subCategoryName) {
            [message appendFormat:@"%@: %@\n", kLang(@"Subcategory"), subCategoryName];
        }
    }
    if (accessory.finalPrice) {
        NSString *priceString = [self formattedPrice:accessory.finalPrice
                                           originalPrice:accessory.price
                                         discountPercent:accessory.discountPercent];
        [message appendFormat:@"%@: %@\n", kLang(@"Price"), priceString];
    }
    NSString *conditionText = [self conditionTextForAccessory:accessory];
    if (conditionText) {
        [message appendFormat:@"%@: %@\n", kLang(@"Condition"), conditionText];
    }
    NSString *stockText = [accessory stockStatusText];
    if (stockText) {
        [message appendFormat:@"%@: %@\n", kLang(@"Availability"), stockText];
    }
    NSString *typeText = [self typeTextForAccessory:accessory];
    if (typeText) {
        [message appendFormat:@"%@: %@", kLang(@"Type"), typeText];
    }
    return [message copy];
}

+ (NSString *)formattedPrice:(NSNumber *)finalPrice
               originalPrice:(NSNumber *)originalPrice
             discountPercent:(NSNumber *)discountPercent {
    if (discountPercent && discountPercent.floatValue > 0) {
        return [NSString stringWithFormat:@"%@ (Was %@, %@%% off)",
                [self formatCurrency:finalPrice],
                [self formatCurrency:originalPrice],
                discountPercent];
    } else {
        return [self formatCurrency:finalPrice];
    }
}

+ (NSString *)formatCurrency:(NSNumber *)amount {
    if (!amount) return [NSString stringWithFormat:@"0 %@", kLang(@"QAR")];
    return [NSString stringWithFormat:@"%@ %@", amount, kLang(@"QAR")];
}

+ (NSString *)conditionTextForAccessory:(PetAccessory *)accessory {
    switch (accessory.condition) {
        case AccessConditionsNew:
            return kLang(@"New");
        case AccessConditionsUsed:
            return kLang(@"Used");
        case AccessConditionsNone:
        default:
            return kLang(@"Not specified");
    }
}

+ (NSString *)typeTextForAccessory:(PetAccessory *)accessory {
    switch (accessory.accessKindType) {
        case AccessTypeAccessory:
            return kLang(@"Accessory");
        case AccessTypeFood:
            return kLang(@"Food");
        case AccessTypeLivePets:
            return kLang(@"Live pets");
        default:
            return kLang(@"Unknown");
    }
}

+ (nullable NSURL *)firstImageURLForAccessory:(PetAccessory *)accessory {
    if (accessory.imageURLsArray.count > 0) {
        NSString *firstImageURL = accessory.imageURLsArray.firstObject;
        if (firstImageURL.length > 0) {
            return [NSURL URLWithString:firstImageURL];
        }
    }
    return nil;
}

- (void)shareFromViewController:(UIViewController *)vc {
    [PetAccessory sharePetAccessory:self fromViewController:vc];
}

- (void)shareFromViewController:(UIViewController *)vc sourceView:(nullable UIView *)sourceView {
    [PetAccessory sharePetAccessory:self fromViewController:vc sourceView:sourceView];
}

+ (void)copyToClipboard:(PetAccessory *)accessory {
    NSString *message = [self shareMessageForAccessory:accessory];
    [UIPasteboard generalPasteboard].string = message;
}

#pragma mark - Branch Resolution

- (NSString *)resolvedBranchID {
    if (self.branchID.length > 0) return self.branchID;
    if (self.storeID.length > 0) return self.storeID;
    return @"";
}

- (NSString *)resolvedBranchName {
    NSString *bID = [self resolvedBranchID];
    if (bID.length > 0 && ![bID isEqualToString:@"main_store"]) {
        PPBranchModel *branch = [[PPBranchContextManager sharedManager] branchWithID:bID];
        if (branch) {
            return [branch localizedName];
        }
    }
    if (self.storeName.length > 0 &&
        ![self.storeName isEqualToString:@"المتجر الرئيسي"] &&
        ![self.storeName caseInsensitiveCompare:@"main store"] == NSOrderedSame) {
        return self.storeName;
    }
    if (self.branchCode.length > 0) {
        return self.branchCode;
    }
    return [Language isRTL] ? @"المتجر الرئيسي" : @"Main Store";
}

@end
