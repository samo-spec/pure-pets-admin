//
//  PPAgentModel.h
//  PurePetsAdmin
//
//  Sales agent model — maps to the `agents` Firestore collection.
//  An agent is a sales representative linked to a branch.
//
//  Field shape is the Admin source-of-truth.  Console, iOS, and Android
//  all follow this exact structure.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// MARK: - Agent Role
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, PPAgentRole) {
    PPAgentRoleSales   = 0,
    PPAgentRoleManager = 1,
    PPAgentRoleCashier = 2,
    PPAgentRoleViewer  = 3
};

// ---------------------------------------------------------------------------
// MARK: - Model
// ---------------------------------------------------------------------------

/// Represents a sales agent assigned to a branch in the Pure Pets platform.
/// Maps directly to Firestore collection `agents`.
@interface PPAgentModel : NSObject <NSCopying>

// ── Identity ──────────────────────────────────────────────────────────────
@property (nonatomic, copy) NSString *agentID;   ///< Firestore document ID
@property (nonatomic, copy) NSString *uid;        ///< Human-readable ID e.g. PP-AGT-A1B2C3D4

// ── Localized Name ────────────────────────────────────────────────────────
@property (nonatomic, copy) NSString *nameAr;
@property (nonatomic, copy) NSString *nameEn;

// ── Contact ───────────────────────────────────────────────────────────────
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSString *phone;

// ── Branch Assignment ─────────────────────────────────────────────────────
@property (nonatomic, copy) NSString *branchId;       ///< Firestore doc ID of the branch
@property (nonatomic, copy) NSString *branchNameAr;   ///< Cached from branch doc (AR)
@property (nonatomic, copy) NSString *branchNameEn;   ///< Cached from branch doc (EN)

// ── Role & Commerce ───────────────────────────────────────────────────────
@property (nonatomic, assign) PPAgentRole role;
@property (nonatomic, assign) double commissionRate;  ///< 0–100 percent

// ── State ─────────────────────────────────────────────────────────────────
@property (nonatomic, assign) BOOL isActive;

// ── Meta ──────────────────────────────────────────────────────────────────
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
@property (nonatomic, copy) NSString *createdBy;   ///< UID of admin who created this agent

// ── Future Compatibility ──────────────────────────────────────────────────
/// Unknown top-level Firestore fields preserved to prevent data loss across
/// app versions.
@property (nonatomic, copy) NSDictionary<NSString *, id> *extraFields;

// ── Serialization ─────────────────────────────────────────────────────────
+ (instancetype)fromDictionary:(NSDictionary *)dict withID:(NSString *)agentID;
- (NSDictionary *)toDictionary;

// ── Helpers ───────────────────────────────────────────────────────────────
/// Returns the localized display name for the current app language (AR/EN).
- (NSString *)localizedName;

/// Returns the cached branch name for the current app language.
- (NSString *)localizedBranchName;

/// Returns the localized role display string.
- (NSString *)localizedRoleName;

/// Returns the raw Firestore string for `role` (e.g. "sales", "manager").
- (NSString *)roleRawValue;

/// Converts a raw Firestore role string or numeric string to PPAgentRole.
+ (PPAgentRole)agentRoleFromRaw:(id)raw;

@end

NS_ASSUME_NONNULL_END
