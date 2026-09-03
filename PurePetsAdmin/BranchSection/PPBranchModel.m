//
//  PPBranchModel.m
//  PurePetsAdmin
//
//  Firestore collection: "branches"
//  Follows the same serialization patterns as PPVetModel / PPServiceModel.
//

#import "PPBranchModel.h"
#import "PPFirebaseCompat.h"
 
// PPSafeString, PPSafeDict, PPSafeDouble, PPSafeDate, PPSafeArray —
// defined in PrefixHeader.pch via FUManager.h / PPMacros.h

// ---------------------------------------------------------------------------
// MARK: - Firestore Field Keys (avoids typos across serialize/deserialize)
// ---------------------------------------------------------------------------

static NSString * const kFldCode        = @"code";
static NSString * const kFldNameAr      = @"nameAr";
static NSString * const kFldNameEn      = @"nameEn";
static NSString * const kFldAddress     = @"address";
static NSString * const kFldPhone       = @"phone";
static NSString * const kFldIsActive    = @"isActive";
static NSString * const kFldIsDefault   = @"isDefault";
static NSString * const kFldStockMode   = @"stockMode";
static NSString * const kFldManagerId   = @"managerId";
static NSString * const kFldOperatingHours = @"operatingHours";
static NSString * const kFldTaxNumber   = @"taxNumber";
static NSString * const kFldCrNumber    = @"crNumber";
static NSString * const kFldCreatedAt   = @"createdAt";
static NSString * const kFldUpdatedAt   = @"updatedAt";
static NSString * const kFldCreatedBy   = @"createdBy";

// Raw Firestore stockMode strings (canonical values).
static NSString * const kStockModePerAgent = @"perAgent";
static NSString * const kStockModeBranch   = @"branch";

// ---------------------------------------------------------------------------
// MARK: - Implementation
// ---------------------------------------------------------------------------

@implementation PPBranchModel

// ---------------------------------------------------------------------------
// MARK: - Known-Key Set (used to populate extraFields safely)
// ---------------------------------------------------------------------------

+ (NSSet<NSString *> *)pp_knownKeys {
    static NSSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[
            kFldCode,
            kFldNameAr, kFldNameEn,
            @"name",           // legacy nested { ar, en } dict
            kFldAddress,
            kFldPhone,
            kFldIsActive,
            kFldIsDefault,
            kFldStockMode,
            kFldManagerId,
            kFldOperatingHours,
            kFldTaxNumber,
            kFldCrNumber,
            kFldCreatedAt,
            kFldUpdatedAt,
            kFldCreatedBy,
        ]];
    });
    return set;
}

// ---------------------------------------------------------------------------
// MARK: - Factory
// ---------------------------------------------------------------------------

+ (instancetype)fromDictionary:(NSDictionary *)dict withID:(NSString *)branchID {
    PPBranchModel *m  = [[PPBranchModel alloc] init];
    NSDictionary  *d  = PPSafeDict(dict);

    m.branchID = PPSafeString(branchID);
    m.code     = PPSafeString(d[kFldCode]);

    // Name — support both flat (nameAr / nameEn) and nested ({ ar, en }) shapes.
    NSDictionary *nameDict = ([d[@"name"] isKindOfClass:NSDictionary.class])
                             ? (NSDictionary *)d[@"name"] : @{};

    NSString *flatAr = PPSafeString(d[kFldNameAr]);
    NSString *flatEn = PPSafeString(d[kFldNameEn]);

    m.nameAr = flatAr.length ? flatAr : PPSafeString(nameDict[@"ar"]);
    m.nameEn = flatEn.length ? flatEn : PPSafeString(nameDict[@"en"]);

    m.address   = PPSafeString(d[kFldAddress]);
    m.phone     = PPSafeString(d[kFldPhone]);
    m.isActive  = [d[kFldIsActive]  boolValue];
    m.isDefault = [d[kFldIsDefault] boolValue];
    m.stockMode = [self stockModeFromRaw:PPSafeString(d[kFldStockMode])];

    m.managerId        = PPSafeString(d[kFldManagerId]);
    m.operatingHours   = PPSafeString(d[kFldOperatingHours]);
    m.taxNumber        = PPSafeString(d[kFldTaxNumber]);
    m.crNumber         = PPSafeString(d[kFldCrNumber]);

    // Timestamps — Firestore may send FIRTimestamp; PPSafeDate handles the cast.
    m.createdAt = PPSafeDate(d[kFldCreatedAt]);
    m.updatedAt = PPSafeDate(d[kFldUpdatedAt]);
    m.createdBy = PPSafeString(d[kFldCreatedBy]);

    // Preserve unknown fields for forward-compatibility.
    NSMutableDictionary *extras = [d mutableCopy];
    [extras removeObjectsForKeys:[[self pp_knownKeys] allObjects]];
    m.extraFields = extras.copy ?: @{};

    return m;
}

// ---------------------------------------------------------------------------
// MARK: - Stock Mode Parsing
// ---------------------------------------------------------------------------

+ (PPBranchStockMode)stockModeFromRaw:(NSString *)raw {
    NSString *lower = raw.lowercaseString;
    if ([lower isEqualToString:@"branch"] ||
        [lower isEqualToString:@"shared"]) {   // "shared" is a Console alias
        return PPBranchStockModeBranch;
    }
    // Default: "perAgent" (also handles "separate" Console alias)
    return PPBranchStockModePerAgent;
}

// ---------------------------------------------------------------------------
// MARK: - Serialization
// ---------------------------------------------------------------------------

- (NSDictionary *)toDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];

    // Merge preserved extras first; canonical fields override below.
    [d addEntriesFromDictionary:PPSafeDict(self.extraFields)];

    // Core fields — write both flat and nested name for cross-app compat.
    d[kFldCode]    = PPSafeString(self.code);
    d[kFldNameAr]  = PPSafeString(self.nameAr);
    d[kFldNameEn]  = PPSafeString(self.nameEn);
    d[@"name"]     = @{
        @"ar": PPSafeString(self.nameAr),
        @"en": PPSafeString(self.nameEn)
    };

    d[kFldAddress]   = PPSafeString(self.address);
    d[kFldPhone]     = PPSafeString(self.phone);
    d[kFldIsActive]  = @(self.isActive);
    d[kFldIsDefault] = @(self.isDefault);
    d[kFldStockMode] = [self stockModeRawValue];

    if (self.managerId.length)      d[kFldManagerId]      = self.managerId;
    if (self.operatingHours.length) d[kFldOperatingHours] = self.operatingHours;
    if (self.taxNumber.length)      d[kFldTaxNumber]      = self.taxNumber;
    if (self.crNumber.length)       d[kFldCrNumber]       = self.crNumber;

    // Always stamp updatedAt on every write.
    d[kFldUpdatedAt] = [NSDate date];

    // createdAt and createdBy only written when present (set at creation time).
    if (self.createdAt)        d[kFldCreatedAt] = self.createdAt;
    if (self.createdBy.length) d[kFldCreatedBy] = self.createdBy;

    return [d copy];
}

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

- (NSString *)stockModeRawValue {
    switch (self.stockMode) {
        case PPBranchStockModeBranch:   return kStockModeBranch;
        case PPBranchStockModePerAgent: return kStockModePerAgent;
    }
    return kStockModePerAgent;
}

- (NSString *)localizedName {
    BOOL arabic = [Language isRTL];
    if (arabic) return self.nameAr.length ? self.nameAr : (self.nameEn.length ? self.nameEn : self.code);
    return       self.nameEn.length ? self.nameEn : (self.nameAr.length ? self.nameAr : self.code);
}

- (NSString *)localizedStockModeName {
    BOOL arabic = [Language isRTL];
    switch (self.stockMode) {
        case PPBranchStockModeBranch:
            return arabic ? @"مخزون مشترك" : @"Branch Stock";
        case PPBranchStockModePerAgent:
            return arabic ? @"مخزون الوكيل" : @"Per Agent";
    }
    return arabic ? @"مخزون الوكيل" : @"Per Agent";
}

// ---------------------------------------------------------------------------
// MARK: - NSCopying
// ---------------------------------------------------------------------------

- (id)copyWithZone:(NSZone *)zone {
    PPBranchModel *copy        = [[PPBranchModel allocWithZone:zone] init];
    copy.branchID   = self.branchID;
    copy.code       = self.code;
    copy.nameAr     = self.nameAr;
    copy.nameEn     = self.nameEn;
    copy.address    = self.address;
    copy.phone      = self.phone;
    copy.isActive   = self.isActive;
    copy.isDefault  = self.isDefault;
    copy.stockMode  = self.stockMode;
    copy.createdAt  = self.createdAt;
    copy.updatedAt  = self.updatedAt;
    copy.createdBy  = self.createdBy;
    copy.extraFields = self.extraFields;
    return copy;
}

@end
