#import "PetAccessory.h"
#import "ArabicNormalizer.h"

#import "MainKindsArrayManager.h"

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

// AppConfig.m
#ifdef DEBUG
BOOL const isPPDebugMode = YES;
#else
BOOL const isPPDebugMode = NO;
#endif







// MARK: - Private interface for searchTitle storage

@interface PetAccessory ()
@property (nonatomic, copy) NSString *searchTitle;
+ (UIViewController *)pp_topViewController;
+ (UIViewController *)pp_topViewControllerFromRoot:(UIViewController *)rootViewController;
@end

static NSDate *PPDateFromFirestoreValue(id value) {
    if ([value isKindOfClass:NSDate.class]) {
        return (NSDate *)value;
    }
    if ([value isKindOfClass:FIRTimestamp.class]) {
        return [(FIRTimestamp *)value dateValue];
    }
    return [NSDate date];
}

static NSDate * _Nullable PPNullableDateFromFirestoreValue(id value) {
    if (!value || [value isKindOfClass:NSNull.class]) return nil;
    if ([value isKindOfClass:NSDate.class]) return (NSDate *)value;
    if ([value isKindOfClass:FIRTimestamp.class]) return [(FIRTimestamp *)value dateValue];
    return nil;
}

static NSArray<NSDictionary *> *PPNormalizedImageMeta(NSArray<NSString *> *urls, NSArray<NSDictionary *> *meta) {
    NSMutableArray<NSDictionary *> *normalized = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSInteger i = 0; i < urls.count; i++) {
        NSString *url = [urls[i] isKindOfClass:NSString.class] ? urls[i] : @"";
        NSDictionary *m = (i < meta.count && [meta[i] isKindOfClass:NSDictionary.class]) ? meta[i] : nil;
        CGFloat width = [m[@"width"] floatValue];
        CGFloat height = [m[@"height"] floatValue];
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
        CGFloat width = [m[@"width"] floatValue];
        CGFloat height = [m[@"height"] floatValue];
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

- (instancetype)init {
    if (self = [super init]) {
        _name = @"";
        _desc = @"";
        _ownerID = @"";
        _storeID = @"";
        _storeName = @"";
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

- (NSDictionary *)toFirestoreDictionary {
    [self normalizeInventoryState];

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // Basic info
    if (self.name) dict[@"name"] = self.name;
    dict[@"searchTitle"] = [ArabicNormalizer normalize:self.name ?: @""];
    if (self.desc) dict[@"desc"] = self.desc;
    if (self.price) dict[@"price"] = self.price;

    // Discount fields
    if (self.discountPercent) dict[@"discountPercent"] = self.discountPercent;
    if (self.discountAmount) dict[@"discountAmount"] = self.discountAmount;

    // Images
    if (self.imageURLsArray) dict[@"imageURLsArray"] = self.imageURLsArray;
    NSArray<NSDictionary *> *normalizedMeta = PPNormalizedImageMeta(self.imageURLsArray ?: @[], self.imageMeta ?: @[]);
    if (normalizedMeta.count > 0) {
        dict[@"imageMeta"] = normalizedMeta;
        dict[@"imageItems"] = PPImageItemsPayload(self.imageURLsArray ?: @[], normalizedMeta, self.blurHash ?: @"");
    } else if (self.imageMeta) {
        dict[@"imageMeta"] = self.imageMeta;
    }
    if (self.blurHash) dict[@"blurHash"] = self.blurHash;

    // Categories
    dict[@"petMainCategoryID"] = @(self.petMainCategoryID);
    dict[@"petSubCategoryID"] = @(self.petSubCategoryID);

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
    if (self.storeID.length > 0) dict[@"storeID"] = self.storeID;
    if (self.storeName.length > 0) dict[@"storeName"] = self.storeName;

    // Enums
    dict[@"accessKindType"] = @(self.accessKindType);
    dict[@"condition"] = @(self.condition);

    // Stock and status
    dict[@"quantity"] = @([self normalizedQuantity]);
    dict[@"noStock"] = @(self.noStock);
    dict[@"active"] = @(self.active);
    dict[@"isNew"] = @(self.isNew);
    dict[@"hasOffer"] = @(self.hasOffer);

    // Calculate and include final price
    NSNumber *finalPrice = [self calculateFinalPrice];
    if (finalPrice) dict[@"finalPrice"] = finalPrice;

    // Add timestamps for Firestore
    dict[@"updatedAt"] = [FIRTimestamp timestampWithDate:[NSDate date]];

    return [dict copy];
}

- (NSNumber *)calculateFinalPrice {
    if (!self.price) return nil;
    
    CGFloat basePrice = [self.price floatValue];
    CGFloat finalPrice = basePrice;
    
    // Apply percentage discount first
    if (self.discountPercent && [self.discountPercent floatValue] > 0) {
        CGFloat discount = (basePrice * [self.discountPercent floatValue]) / 100.0;
        finalPrice = basePrice - discount;
    }
    
    // Apply absolute discount
    if (self.discountAmount && [self.discountAmount floatValue] > 0) {
        finalPrice = finalPrice - [self.discountAmount floatValue];
    }
    
    // Ensure price doesn't go negative
    if (finalPrice < 0) finalPrice = 0;
    
    return @(finalPrice);
}

- (NSString *)stockStatusText {
    NSInteger qty = [self normalizedQuantity];
    if (qty <= 0) {
        return @"Out of Stock";
    } else if (qty <= 5) {
        return [NSString stringWithFormat:@"Only %ld left", (long)qty];
    } else {
        return @"In Stock";
    }
}

- (NSInteger)normalizedQuantity {
    return MAX(0, self.quantity);
}

- (void)normalizeInventoryState {
    self.quantity = [self normalizedQuantity];
    self.noStock = (self.quantity <= 0);

    if (self.accessKindType != AccessTypeAccessory && self.accessKindType != AccessTypeFood && self.accessKindType != AccessTypeLivePets) {
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
        
        CGFloat width = [meta[@"width"] floatValue] ?: 0;
        CGFloat height = [meta[@"height"] floatValue] ?: 0;
        
        PetImageItem *item = [[PetImageItem alloc] initWithURL:url
                                                         width:width
                                                        height:height blurHash:nil];
        [items addObject:item];
    }
    
    return [items copy];
}







/*
 
 
 #pragma mark - 🎯 Weighted Random Discount Generator (Realistic Testing)

 - (void)applyRandomTestDiscount {
     // 0–99 random number for probability weighting
     int roll = arc4random_uniform(100);
     
     // Default (no discount)
     self.discountPercent = nil;
     self.discountAmount = nil;
     
     if (roll < 60) {
         // 60% chance — no discount
         //self.hasOffer = NO;
         return;
     }
     
     // Randomly decide between percentage or fixed
     BOOL usePercent = arc4random_uniform(2) == 0;
     
     if (usePercent) {
         if (roll < 85) {
             // 25% chance total — small 10% discount
             self.discountPercent = @(10);
         } else {
             // 15% chance — big 50% discount
             self.discountPercent = @(50);
         }
     } else {
         if (roll < 85) {
             // 25% chance total — small absolute discount
             NSArray *smallAmounts = @[@10, @20];
             self.discountAmount = smallAmounts[arc4random_uniform((uint32_t)smallAmounts.count)];
         } else {
             // 15% chance — large absolute discount
             NSArray *bigAmounts = @[@70, @100];
             self.discountAmount = bigAmounts[arc4random_uniform((uint32_t)bigAmounts.count)];
         }
     }
     
     // Mark as having offer
     //self.hasOffer = YES;
 }

 */

- (NSNumber *)finalPrice {
    return [self calculateFinalPrice];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    
    if (self = [super init]) {
        _accessoryID = docID ?: @"";
        _name = dict[@"name"] ?: @"";
        _desc = dict[@"desc"] ?: @"";
        _price = dict[@"price"] ?: @(0);
        _discountPercent = dict[@"discountPercent"];
        _discountAmount = dict[@"discountAmount"];
        _imageURLsArray = dict[@"imageURLsArray"] ?: @[];
        _imageMeta  = dict[@"imageMeta"] ?: nil;
        NSArray *imageItemsPayload = [dict[@"imageItems"] isKindOfClass:NSArray.class] ? dict[@"imageItems"] : @[];
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
                CGFloat width = [item[@"width"] floatValue];
                CGFloat height = [item[@"height"] floatValue];
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
        _createdAt = PPDateFromFirestoreValue(dict[@"createdAt"]);
        _expiryDate = PPNullableDateFromFirestoreValue(dict[@"expiryDate"]);
        _ownerID = dict[@"ownerID"] ?: @"";
        _storeID = dict[@"storeID"] ?: @"";
        _storeName = dict[@"storeName"] ?: @"";
        _blurHash = dict[@"blurHash"] ?: @"";
        NSInteger rawKind = [dict[@"accessKindType"] integerValue];
        if (rawKind == AccessTypeFood) {
            _accessKindType = AccessTypeFood;
        } else if (rawKind == AccessTypeLivePets) {
            _accessKindType = AccessTypeLivePets;
        } else {
            _accessKindType = AccessTypeAccessory;
        }
        NSInteger rawCondition = [dict[@"condition"] integerValue];
        _condition = (rawCondition == AccessConditionsUsed ? AccessConditionsUsed : AccessConditionsNew);
        _isNew = [dict[@"isNew"] boolValue];
        _hasOffer = [dict[@"hasOffer"] boolValue];
        _active = dict[@"active"] == nil ? YES : [dict[@"active"] boolValue];
        _quantity = MAX(0, [dict[@"quantity"] integerValue]);
        if (dict[@"noStock"] != nil) {
            _noStock = [dict[@"noStock"] boolValue];
        } else {
            _noStock = (_quantity <= 0);
        }
        _searchTitle = dict[@"searchTitle"];
        if(isPPDebugMode)
        {
            //[self applyRandomTestDiscount];
            //_desc = kLang(@"tempDesc");
            //_quantity = arc4random_uniform(15); // random quantity for testing
        }

        [self normalizeInventoryState];
    }
    return self;
}

// PetAccessory.m
+ (instancetype)deepCopyFrom:(PetAccessory *)source {
    PetAccessory *copy = [[PetAccessory alloc] init];
    copy.accessoryID = [source.accessoryID copy];
    copy.name = [source.name copy];
    copy.price = [source.price copy];
    copy.discountPercent = [source.discountPercent copy];
    copy.discountAmount = [source.discountAmount copy];
    copy.desc = [source.desc copy];
    copy.blurHash = [source.blurHash copy];
    copy.petMainCategoryID = source.petMainCategoryID;
    copy.petSubCategoryID = source.petSubCategoryID;
    copy.condition = source.condition;
    copy.accessKindType = source.accessKindType;
    copy.imageURLsArray = [source.imageURLsArray copy];
    copy.imageMeta = [source.imageMeta copy];
    copy.ownerID = [source.ownerID copy];
    copy.storeID = [source.storeID copy];
    copy.storeName = [source.storeName copy];
    copy.createdAt = [source.createdAt copy];
    copy.expiryDate = [source.expiryDate copy];
    copy.quantity = source.quantity;
    copy.active = source.active;
    copy.noStock = source.noStock;
    copy.hasOffer = source.hasOffer;
    copy.isNew = source.isNew;
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
    
    // Create the share message
    NSString *message = [self shareMessageForAccessory:accessory];
    
    // Prepare share items
    NSMutableArray *items = [NSMutableArray arrayWithObject:message];
    
    // Add first image if available
    NSURL *imageURL = [self firstImageURLForAccessory:accessory];
    if (imageURL) {
        [items addObject:imageURL];
    }
    
    // Create activity view controller
    UIActivityViewController *activityVC = [[UIActivityViewController alloc]
                                            initWithActivityItems:items
                                            applicationActivities:nil];
    
    // Exclude certain activities if needed
    // activityVC.excludedActivityTypes = @[UIActivityTypeAirDrop, UIActivityTypeAddToReadingList];
    
    // For iPad, configure popover
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        activityVC.popoverPresentationController.sourceView = sourceView ?: vc.view;
        
        if (sourceView) {
            activityVC.popoverPresentationController.sourceRect = sourceView.bounds;
        } else {
            // Default to center of view
            activityVC.popoverPresentationController.sourceRect = CGRectMake(
                vc.view.bounds.size.width / 2,
                vc.view.bounds.size.height / 2,
                1, 1
            );
        }
    }
    
    // Present the share sheet
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
    
    // Title/Introduction
    [message appendFormat:@"%@\n\n", kLang(@"Check out this pet accessory!")];
    
    // Name
    if (accessory.name.length > 0) {
        [message appendFormat:@"%@: %@\n", kLang(@"Name"), accessory.name];
    }
    
    // Description (truncated if too long)
    if (accessory.desc.length > 0) {
        NSString *shortDesc = accessory.desc;
        if (shortDesc.length > 100) {
            shortDesc = [[shortDesc substringToIndex:100] stringByAppendingString:@"..."];
        }
        [message appendFormat:@"%@: %@\n", kLang(@"Description"), shortDesc];
    }
    
    // Category Information
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
    
    // Price Information
    if (accessory.finalPrice) {
        NSString *priceString = [self formattedPrice:accessory.finalPrice
                                          originalPrice:accessory.price
                                        discountPercent:accessory.discountPercent];
        [message appendFormat:@"%@: %@\n", kLang(@"Price"), priceString];
    }
    
    // Condition
    NSString *conditionText = [self conditionTextForAccessory:accessory];
    if (conditionText) {
        [message appendFormat:@"%@: %@\n", kLang(@"Condition"), conditionText];
    }
    
    // Stock status
    NSString *stockText = [accessory stockStatusText];
    if (stockText) {
        [message appendFormat:@"%@: %@\n", kLang(@"Availability"), stockText];
    }
    
    // Type
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
    } else if (discountPercent && discountPercent.floatValue == 0) {
        // Special sale indicator (0% might mean "on sale" without discount)
        return [NSString stringWithFormat:@"%@ (On Sale!)", [self formatCurrency:finalPrice]];
    } else {
        return [self formatCurrency:finalPrice];
    }
}

+ (NSString *)formatCurrency:(NSNumber *)amount {
    if (!amount) return @"N/A";
    
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterCurrencyStyle;
    formatter.currencyCode = @"USD"; // Change based on your locale
    formatter.maximumFractionDigits = 2;
    formatter.minimumFractionDigits = 0;
    
    return [formatter stringFromNumber:amount];
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

#pragma mark - Instance Method for Sharing

- (void)shareFromViewController:(UIViewController *)vc {
    [PetAccessory sharePetAccessory:self fromViewController:vc];
}

- (void)shareFromViewController:(UIViewController *)vc sourceView:(nullable UIView *)sourceView {
    [PetAccessory sharePetAccessory:self fromViewController:vc sourceView:sourceView];
}

#pragma mark - Share Link Generation (Optional)

+ (nullable NSURL *)shareableLinkForAccessory:(PetAccessory *)accessory {
    // Generate a deep link or web URL for the accessory
    // This depends on your app's URL scheme or website
    
    if (!accessory.accessoryID) return nil;
    
    // Example: "yourapp://accessory/12345"
    NSString *deepLink = [NSString stringWithFormat:@"yourapp://accessory/%@", accessory.accessoryID];
    
    // OR web URL: "https://yourapp.com/accessory/12345"
    // NSString *webURL = [NSString stringWithFormat:@"https://yourapp.com/accessory/%@", accessory.accessoryID];
    
    return [NSURL URLWithString:deepLink];
}

#pragma mark - Social Media Specific Sharing (Optional)

+ (void)shareToFacebook:(PetAccessory *)accessory fromViewController:(UIViewController *)vc {
    // Facebook-specific sharing implementation
    // You might want to use Facebook SDK or a custom implementation
    
    NSString *message = [self shareMessageForAccessory:accessory];
    
    // For Facebook, you might want to use:
    // - FBSDKShareLinkContent for link sharing
    // - FBSDKSharePhotoContent for photo sharing
    // - FBSDKShareDialog to present the share dialog
    
    NSLog(@"Facebook sharing not implemented. Message: %@", message);
}

+ (void)shareToInstagram:(PetAccessory *)accessory fromViewController:(UIViewController *)vc {
    // Instagram sharing typically requires image or video content
    // You can share via Instagram's URL scheme
    
    NSURL *imageURL = [self firstImageURLForAccessory:accessory];
    if (imageURL) {
        // Save image locally first, then share to Instagram
        [self downloadAndShareToInstagram:imageURL
                         withCaption:accessory.name
                  fromViewController:vc];
    }
}

+ (void)downloadAndShareToInstagram:(NSURL *)imageURL
                       withCaption:(NSString *)caption
                fromViewController:(UIViewController *)vc {
    
    // Implementation for downloading image and sharing to Instagram
    // This would typically involve:
    // 1. Downloading the image
    // 2. Saving to photo library or documents directory
    // 3. Using Instagram's URL scheme: instagram://library?AssetPath=...
    
    NSLog(@"Instagram sharing not fully implemented");
}

#pragma mark - Export Methods (Optional)

+ (void)exportAsPDF:(PetAccessory *)accessory fromViewController:(UIViewController *)vc {
    // Generate and share as PDF
    // This is useful for creating printable listings
    
    NSData *pdfData = [self generatePDFForAccessory:accessory];
    
    if (pdfData) {
        // Save to temporary file
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingFormat:@"%@.pdf", accessory.name ?: @"accessory"];
        [pdfData writeToFile:tempPath atomically:YES];
        
        // Share the file
        NSURL *fileURL = [NSURL fileURLWithPath:tempPath];
        UIActivityViewController *activityVC = [[UIActivityViewController alloc]
                                                initWithActivityItems:@[fileURL]
                                                applicationActivities:nil];
        
        [vc presentViewController:activityVC animated:YES completion:nil];
    }
}

+ (NSData *)generatePDFForAccessory:(PetAccessory *)accessory {
    // Implement PDF generation using Core Graphics
    // This would create a nicely formatted PDF of the accessory details
    
    // Placeholder implementation
    return nil;
}

#pragma mark - Copy to Clipboard

+ (void)copyToClipboard:(PetAccessory *)accessory {
    NSString *message = [self shareMessageForAccessory:accessory];
    [UIPasteboard generalPasteboard].string = message;
    
    // Optional: Show feedback to user
    // [self showToast:@"Copied to clipboard!"];
}



@end
