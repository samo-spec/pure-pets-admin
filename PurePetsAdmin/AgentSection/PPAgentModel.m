//
//  PPAgentModel.m
//  PurePetsAdmin
//
//  Firestore collection: "agents"
//  Follows the same serialization patterns as PPVetModel / PPServiceModel.
//

#import "PPAgentModel.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
 
// PPSafeString, PPSafeDict, PPSafeDouble, PPSafeDate —
// defined in PrefixHeader.pch via FUManager.h / PPMacros.h

// ---------------------------------------------------------------------------
// MARK: - Firestore Field Keys
// ---------------------------------------------------------------------------

static NSString * const kAgtFldUID           = @"uid";
static NSString * const kAgtFldNameAr        = @"nameAr";
static NSString * const kAgtFldNameEn        = @"nameEn";
static NSString * const kAgtFldEmail         = @"email";
static NSString * const kAgtFldPhone         = @"phone";
static NSString * const kAgtFldBranchId      = @"branchId";
static NSString * const kAgtFldBranchName    = @"branchName";
static NSString * const kAgtFldRole          = @"role";
static NSString * const kAgtFldCommission    = @"commissionRate";
static NSString * const kAgtFldIsActive      = @"isActive";
static NSString * const kAgtFldCreatedAt     = @"createdAt";
static NSString * const kAgtFldUpdatedAt     = @"updatedAt";
static NSString * const kAgtFldCreatedBy     = @"createdBy";

// ---------------------------------------------------------------------------
// MARK: - Implementation
// ---------------------------------------------------------------------------

@implementation PPAgentModel

// ---------------------------------------------------------------------------
// MARK: - Known-Key Set
// ---------------------------------------------------------------------------

+ (NSSet<NSString *> *)pp_knownKeys {
    static NSSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[
            kAgtFldUID,
            kAgtFldNameAr, kAgtFldNameEn,
            @"name",             // nested { ar, en } shape
            kAgtFldEmail,
            kAgtFldPhone,
            kAgtFldBranchId,
            kAgtFldBranchName,
            kAgtFldRole,
            kAgtFldCommission,
            kAgtFldIsActive,
            kAgtFldCreatedAt,
            kAgtFldUpdatedAt,
            kAgtFldCreatedBy,
        ]];
    });
    return set;
}

// ---------------------------------------------------------------------------
// MARK: - Factory
// ---------------------------------------------------------------------------

+ (instancetype)fromDictionary:(NSDictionary *)dict withID:(NSString *)agentID {
    PPAgentModel *m = [[PPAgentModel alloc] init];
    NSDictionary *d = PPSafeDict(dict);

    m.agentID = PPSafeString(agentID);
    m.uid     = PPSafeString(d[kAgtFldUID]);

    // Name — support both flat (nameAr / nameEn) and nested ({ ar, en }) shapes.
    NSDictionary *nameDict = ([d[@"name"] isKindOfClass:NSDictionary.class])
                             ? (NSDictionary *)d[@"name"] : @{};

    NSString *flatAr = PPSafeString(d[kAgtFldNameAr]);
    NSString *flatEn = PPSafeString(d[kAgtFldNameEn]);

    m.nameAr = flatAr.length ? flatAr : PPSafeString(nameDict[@"ar"]);
    m.nameEn = flatEn.length ? flatEn : PPSafeString(nameDict[@"en"]);

    m.email = PPSafeString(d[kAgtFldEmail]);
    m.phone = PPSafeString(d[kAgtFldPhone]);

    m.branchId = PPSafeString(d[kAgtFldBranchId]);

    // branchName — supports both nested { ar, en } dict and flat string fallback.
    id rawBranchName = d[kAgtFldBranchName];
    if ([rawBranchName isKindOfClass:NSDictionary.class]) {
        NSDictionary *bn = (NSDictionary *)rawBranchName;
        m.branchNameAr = PPSafeString(bn[@"ar"]);
        m.branchNameEn = PPSafeString(bn[@"en"]);
    } else {
        NSString *flat = PPSafeString(rawBranchName);
        m.branchNameAr = flat;
        m.branchNameEn = flat;
    }

    m.role           = [self agentRoleFromRaw:d[kAgtFldRole]];
    m.commissionRate = PPSafeDouble(d[kAgtFldCommission]);
    m.isActive       = [d[kAgtFldIsActive] boolValue];

    m.createdAt = PPSafeDate(d[kAgtFldCreatedAt]);
    m.updatedAt = PPSafeDate(d[kAgtFldUpdatedAt]);
    m.createdBy = PPSafeString(d[kAgtFldCreatedBy]);

    // Preserve unknown fields.
    NSMutableDictionary *extras = [d mutableCopy];
    [extras removeObjectsForKeys:[[self pp_knownKeys] allObjects]];
    m.extraFields = extras.copy ?: @{};

    return m;
}

// ---------------------------------------------------------------------------
// MARK: - Role Parsing
// ---------------------------------------------------------------------------

+ (PPAgentRole)agentRoleFromRaw:(id)raw {
    // Numeric value (NSNumber or numeric NSString)
    if ([raw isKindOfClass:[NSNumber class]]) {
        NSInteger n = [(NSNumber *)raw integerValue];
        if (n >= PPAgentRoleSales && n <= PPAgentRoleViewer) {
            return (PPAgentRole)n;
        }
    }
    if ([raw isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)raw lowercaseString];
        // Try numeric string first
        if ([s length] == 1 && [s rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound) {
            NSInteger n = s.integerValue;
            if (n >= PPAgentRoleSales && n <= PPAgentRoleViewer) return (PPAgentRole)n;
        }
        if ([s isEqualToString:@"manager"]) return PPAgentRoleManager;
        if ([s isEqualToString:@"cashier"]) return PPAgentRoleCashier;
        if ([s isEqualToString:@"viewer"])  return PPAgentRoleViewer;
    }
    return PPAgentRoleSales;  // default
}

// ---------------------------------------------------------------------------
// MARK: - Serialization
// ---------------------------------------------------------------------------

- (NSDictionary *)toDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];

    // Merge preserved extras first; canonical fields always override.
    [d addEntriesFromDictionary:PPSafeDict(self.extraFields)];

    d[kAgtFldUID]     = PPSafeString(self.uid);

    // Write both flat and nested name shapes for cross-app compatibility.
    d[kAgtFldNameAr]  = PPSafeString(self.nameAr);
    d[kAgtFldNameEn]  = PPSafeString(self.nameEn);
    d[@"name"]        = @{
        @"ar": PPSafeString(self.nameAr),
        @"en": PPSafeString(self.nameEn)
    };

    d[kAgtFldEmail]   = PPSafeString(self.email);
    d[kAgtFldPhone]   = PPSafeString(self.phone);

    d[kAgtFldBranchId]   = PPSafeString(self.branchId);
    d[kAgtFldBranchName] = @{
        @"ar": PPSafeString(self.branchNameAr),
        @"en": PPSafeString(self.branchNameEn)
    };

    d[kAgtFldRole]       = [self roleRawValue];
    d[kAgtFldCommission] = @(self.commissionRate);
    d[kAgtFldIsActive]   = @(self.isActive);

    // Always stamp updatedAt.
    d[kAgtFldUpdatedAt] = [NSDate date];

    if (self.createdAt)        d[kAgtFldCreatedAt] = self.createdAt;
    if (self.createdBy.length) d[kAgtFldCreatedBy] = self.createdBy;

    return [d copy];
}

// ---------------------------------------------------------------------------
// MARK: - Role Raw Value
// ---------------------------------------------------------------------------

- (NSString *)roleRawValue {
    switch (self.role) {
        case PPAgentRoleManager: return @"manager";
        case PPAgentRoleCashier: return @"cashier";
        case PPAgentRoleViewer:  return @"viewer";
        case PPAgentRoleSales:   return @"sales";
    }
    return @"sales";
}

// ---------------------------------------------------------------------------
// MARK: - Localized Helpers
// ---------------------------------------------------------------------------

- (NSString *)localizedName {
    BOOL arabic = [Language isRTL];
    if (arabic) return self.nameAr.length ? self.nameAr : (self.nameEn.length ? self.nameEn : self.uid);
    return       self.nameEn.length ? self.nameEn : (self.nameAr.length ? self.nameAr : self.uid);
}

- (NSString *)localizedBranchName {
    BOOL arabic = [Language isRTL];
    if (arabic) return self.branchNameAr.length ? self.branchNameAr : self.branchNameEn;
    return       self.branchNameEn.length ? self.branchNameEn : self.branchNameAr;
}

- (NSString *)localizedRoleName {
    BOOL arabic = [Language isRTL];
    switch (self.role) {
        case PPAgentRoleSales:
            return arabic ? @"مبيعات" : @"Sales";
        case PPAgentRoleManager:
            return arabic ? @"مدير"   : @"Manager";
        case PPAgentRoleCashier:
            return arabic ? @"كاشير"  : @"Cashier";
        case PPAgentRoleViewer:
            return arabic ? @"مشاهد"  : @"Viewer";
    }
    return arabic ? @"مبيعات" : @"Sales";
}

// ---------------------------------------------------------------------------
// MARK: - NSCopying
// ---------------------------------------------------------------------------

- (id)copyWithZone:(NSZone *)zone {
    PPAgentModel *copy   = [[PPAgentModel allocWithZone:zone] init];
    copy.agentID         = self.agentID;
    copy.uid             = self.uid;
    copy.nameAr          = self.nameAr;
    copy.nameEn          = self.nameEn;
    copy.email           = self.email;
    copy.phone           = self.phone;
    copy.branchId        = self.branchId;
    copy.branchNameAr    = self.branchNameAr;
    copy.branchNameEn    = self.branchNameEn;
    copy.role            = self.role;
    copy.commissionRate  = self.commissionRate;
    copy.isActive        = self.isActive;
    copy.createdAt       = self.createdAt;
    copy.updatedAt       = self.updatedAt;
    copy.createdBy       = self.createdBy;
    copy.extraFields     = self.extraFields;
    return copy;
}

@end
