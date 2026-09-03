//
//  PPAuditLogEntryModel.h
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Audit Ledger, Telemetry, and State Diff Model.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@import Firebase;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPAuditDiffType) {
    PPAuditDiffTypeAdded = 0,
    PPAuditDiffTypeRemoved,
    PPAuditDiffTypeModified,
    PPAuditDiffTypeUnchanged
};

typedef NS_ENUM(NSInteger, PPAuditActionCategory) {
    PPAuditActionCategoryGeneral = 0,
    PPAuditActionCategorySecurity,
    PPAuditActionCategoryServices,
    PPAuditActionCategoryOperations,
    PPAuditActionCategoryFinance,
    PPAuditActionCategoryDestructive
};

typedef NS_ENUM(NSInteger, PPAuditSeverity) {
    PPAuditSeverityInfo = 0,
    PPAuditSeverityConstructive,
    PPAuditSeverityWarning,
    PPAuditSeverityCritical
};

@interface PPAuditDiffItem : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) PPAuditDiffType diffType;
@property (nonatomic, copy, nullable) NSString *oldValueString;
@property (nonatomic, copy, nullable) NSString *newValueString;
- (nullable NSString *)newValueString __attribute__((objc_method_family(none)));
+ (instancetype)itemWithKey:(NSString *)key
                       type:(PPAuditDiffType)type
                   oldValue:(nullable id)oldVal
                   newValue:(nullable id)newVal;
@end

@interface PPAuditLogEntryModel : NSObject

@property (nonatomic, copy) NSString *auditId;
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *adminUid;
@property (nonatomic, copy) NSString *targetUid;
@property (nonatomic, copy, nullable) NSString *targetCollection;
@property (nonatomic, copy, nullable) NSString *reason;
@property (nonatomic, strong, nullable) NSDictionary *before;
@property (nonatomic, strong, nullable) NSDictionary *after;
@property (nonatomic, strong, nullable) NSDictionary *metadata;
@property (nonatomic, strong) NSDate *timestamp;

+ (instancetype)entryFromSnapshot:(FIRDocumentSnapshot *)snapshot;

- (NSString *)formattedTimestamp;
- (NSString *)relativeTimeString;
- (PPAuditActionCategory)actionCategory;
- (PPAuditSeverity)severity;
- (NSString *)categoryTitle;
- (NSString *)localizedActionTitle;
- (NSString *)systemIconName;
- (UIColor *)accentColor;
- (UIColor *)badgeBackgroundColor;
- (UIColor *)badgeTextColor;

- (NSArray<PPAuditDiffItem *> *)computedDiff;
- (NSInteger)addedKeysCount;
- (NSInteger)removedKeysCount;
- (NSInteger)modifiedKeysCount;
- (BOOL)hasDiff;

@end

NS_ASSUME_NONNULL_END
