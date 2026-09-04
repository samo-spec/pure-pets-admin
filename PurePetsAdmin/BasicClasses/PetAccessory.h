#import <Foundation/Foundation.h>
#import "PetImageItem.h"

typedef NS_ENUM(NSInteger, AccessConditions)
{
    AccessConditionsNew = 1,
    AccessConditionsUsed = 2,
    AccessConditionsNone = -1
};

typedef NS_ENUM(NSInteger, AccessKindType)
{
    AccessTypeAccessory = 1,
    AccessTypeFood = 2,
    AccessTypeLivePets = 3,
    AccessTypeLivePet = 3,       // iOS App alias
    AccessTypePetMedicine = 4
};

NS_ASSUME_NONNULL_BEGIN

@interface PetAccessory : NSObject
@property (nonatomic, copy)   NSString *blurHash;

// Search-normalized title for Arabic/English safe queries
@property (nonatomic, readonly) NSString *searchTitle;
+ (instancetype)deepCopyFrom:(PetAccessory *)source;

@property (nonatomic, strong) NSString *accessoryID;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *desc;
@property (nonatomic, strong) NSNumber *price;                     // Base/original price
@property (nonatomic, readonly) BOOL hasResolvedSellingPrice;      // NO when the catalog projection has no priced available unit
@property (nonatomic, strong, nullable) NSNumber *discountPercent;  // % discount (0–100)
@property (nonatomic, strong, nullable) NSNumber *discountAmount;   // Absolute discount (e.g. 15.0)
@property (nonatomic, readonly) NSNumber *finalPrice;               // Auto-calculated final price
@property (nonatomic, copy, nullable) NSString *weightText;          // Display-ready package weight, e.g. "2 kg"
@property (nonatomic, strong, nullable) NSNumber *weight;            // Numeric package weight when stored separately
@property (nonatomic, copy, nullable) NSString *weightUnit;          // Unit for numeric package weight

@property (nonatomic, strong) NSArray<NSString *> *imageURLsArray;
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *imageMeta;
@property (nonatomic, copy, readonly)  NSArray<PetImageItem *> *imageItems;

@property (nonatomic, assign) NSInteger petMainCategoryID;
@property (nonatomic, assign) NSInteger petSubCategoryID;
@property (nonatomic, copy, nullable) NSString *AccessoryCategoryID;
@property (nonatomic, assign) NSInteger cityID;

@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *expiryDate;
@property (nonatomic, strong) NSString *ownerID;
@property (nonatomic, copy, nullable) NSString *storeID;
@property (nonatomic, copy, nullable) NSString *storeName;
@property (nonatomic, copy, nullable) NSString *branchID;
@property (nonatomic, copy, nullable) NSString *branchCode;
- (NSString *)resolvedBranchID;
- (NSString *)resolvedBranchName;
@property (nonatomic, strong, nullable) NSString *ownerType;
@property (nonatomic, strong, nullable) NSString *source;
@property (nonatomic, copy, nullable) NSString *inventoryMode;
@property (nonatomic, assign) NSInteger inventorySchemaVersion;
@property (nonatomic, strong, nullable) NSNumber *standardSellingPrice;
@property (nonatomic, assign) NSInteger reservedQuantity;
@property (nonatomic, assign) BOOL isArchived;
@property (nonatomic, assign) AccessKindType accessKindType;
@property (nonatomic, assign) AccessConditions condition;
@property (nonatomic, assign) NSInteger quantity; // how many in stock
@property (nonatomic, assign) BOOL noStock;
@property (nonatomic, assign) BOOL active;
- (NSString *)stockStatusText;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, assign) BOOL hasOffer;
@property (nonatomic, assign) BOOL showInAppMarket;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isDeleted;
@property (nonatomic, assign) BOOL isDisabled;

// Computed type helpers
@property (nonatomic, readonly) BOOL isLivePet;
@property (nonatomic, readonly) BOOL isFood;
@property (nonatomic, readonly) BOOL isPetMedicine;

// Firestore helpers
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
- (NSDictionary *)toFirestoreDictionary;

// Business logic helpers
- (NSNumber *)calculateFinalPrice;
- (NSInteger)normalizedQuantity;
- (void)normalizeInventoryState;

+ (nullable NSURL *)firstImageURLForAccessory:(PetAccessory *)accessory;
+ (NSString *)typeTextForAccessory:(PetAccessory *)accessory;
+ (NSString *)conditionTextForAccessory:(PetAccessory *)accessory;
+ (NSString *)formatCurrency:(NSNumber *)amount;
+ (NSString *)formattedPrice:(NSNumber *)finalPrice
               originalPrice:(NSNumber *)originalPrice
             discountPercent:(NSNumber *)discountPercent;
+ (NSString *)shareMessageForAccessory:(PetAccessory *)accessory;
+ (void)sharePetAccessory:(PetAccessory *)accessory
        fromViewController:(UIViewController *)vc
                sourceView:(nullable UIView *)sourceView;
+ (void)sharePetAccessory:(PetAccessory *)accessory fromViewController:(UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
