//
//  PPBranchModel.h
//  PurePetsAdmin
//
//  Branch model — maps to the `branches` Firestore collection.
//
//  stockMode "perAgent" → each agent manages their own stock pool
//  stockMode "branch"   → all agents in the branch share one stock pool
//
//  This is the Admin source-of-truth for branch data.
//  Consumers (Console, iOS, Android) follow this model shape exactly.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// MARK: - Stock Mode
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, PPBranchStockMode) {
    PPBranchStockModePerAgent = 0,  // "perAgent" — agent-owned inventory
    PPBranchStockModeBranch   = 1   // "branch"   — shared branch inventory
};

// ---------------------------------------------------------------------------
// MARK: - Model
// ---------------------------------------------------------------------------

/// Represents a physical or logical branch in the Pure Pets platform.
/// Maps directly to Firestore collection `branches`.
@interface PPBranchModel : NSObject <NSCopying>

// ── Identity ──────────────────────────────────────────────────────────────
@property (nonatomic, copy) NSString *branchID;   ///< Firestore document ID
@property (nonatomic, copy) NSString *code;        ///< Human-readable code e.g. PP-BRCH-A1B2C3D4

// ── Localized Name ────────────────────────────────────────────────────────
@property (nonatomic, copy) NSString *nameAr;
@property (nonatomic, copy) NSString *nameEn;

// ── Contact ───────────────────────────────────────────────────────────────
@property (nonatomic, copy) NSString *address;
@property (nonatomic, copy) NSString *phone;

// ── State ─────────────────────────────────────────────────────────────────
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL isDefault;   ///< Only one branch should be default at a time
@property (nonatomic, assign) PPBranchStockMode stockMode;

// ── Enterprise Metadata ──────────────────────────────────────────────────
@property (nonatomic, copy, nullable) NSString *managerId;
@property (nonatomic, copy, nullable) NSString *operatingHours;
@property (nonatomic, copy, nullable) NSString *taxNumber;
@property (nonatomic, copy, nullable) NSString *crNumber;

// ── Meta ──────────────────────────────────────────────────────────────────
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
@property (nonatomic, copy) NSString *createdBy;   ///< UID of admin who created this branch

// ── Future Compatibility ──────────────────────────────────────────────────
/// Unknown top-level Firestore fields are preserved here so no data is lost
/// when newer app versions write additional fields.
@property (nonatomic, copy) NSDictionary<NSString *, id> *extraFields;

// ── Serialization ─────────────────────────────────────────────────────────
+ (instancetype)fromDictionary:(NSDictionary *)dict withID:(NSString *)branchID;
- (NSDictionary *)toDictionary;

// ── Helpers ───────────────────────────────────────────────────────────────
/// Returns the localized name for the current app language (AR/EN).
- (NSString *)localizedName;

/// Returns the localized stock-mode display string.
- (NSString *)localizedStockModeName;

/// Returns the raw Firestore string for `stockMode`.
- (NSString *)stockModeRawValue;

/// Converts a raw Firestore string to a PPBranchStockMode enum value.
+ (PPBranchStockMode)stockModeFromRaw:(NSString *)raw;

@end

NS_ASSUME_NONNULL_END
