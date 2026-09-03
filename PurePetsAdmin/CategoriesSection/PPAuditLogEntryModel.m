//
//  PPAuditLogEntryModel.m
//  PurePetsAdmin
//
//  Created from absolute first principles.
//  Category-defining Audit Ledger, Telemetry, and State Diff Model.
//

#import "PPAuditLogEntryModel.h"
#import "PPDesignTokens.h"
#import "Language.h"

#pragma mark - Helper Stringifier

static NSString * _Nonnull PPAuditStringFromObject(id _Nullable obj) {
    if (!obj || [obj isKindOfClass:[NSNull class]]) {
        return @"--";
    }
    if ([obj isKindOfClass:[NSString class]]) {
        return (NSString *)obj;
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        NSNumber *num = (NSNumber *)obj;
        // Check if boolean
        if (strcmp([num objCType], @encode(char)) == 0 || [num isKindOfClass:NSClassFromString(@"__NSCFBoolean")]) {
            return [num boolValue] ? @"true" : @"false";
        }
        return [num stringValue];
    }
    if ([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSDictionary class]]) {
        NSError *err = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:&err];
        if (data && !err) {
            NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            return [json stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    return [NSString stringWithFormat:@"%@", obj];
}

#pragma mark - PPAuditDiffItem

@implementation PPAuditDiffItem

+ (instancetype)itemWithKey:(NSString *)key
                       type:(PPAuditDiffType)type
                   oldValue:(nullable id)oldVal
                   newValue:(nullable id)newVal {
    PPAuditDiffItem *item = [PPAuditDiffItem new];
    item.key = key ?: @"";
    item.diffType = type;
    item.oldValueString = oldVal ? PPAuditStringFromObject(oldVal) : nil;
    item.newValueString = newVal ? PPAuditStringFromObject(newVal) : nil;
    return item;
}

@end

#pragma mark - PPAuditLogEntryModel

@interface PPAuditLogEntryModel ()
@property (nonatomic, strong, nullable) NSArray<PPAuditDiffItem *> *cachedDiff;
@end

@implementation PPAuditLogEntryModel

+ (instancetype)entryFromSnapshot:(FIRDocumentSnapshot *)snapshot {
    PPAuditLogEntryModel *entry = [PPAuditLogEntryModel new];
    entry.auditId = snapshot.documentID;
    NSDictionary *data = snapshot.data;
    if (!data) return entry;

    entry.action = [data[@"action"] isKindOfClass:[NSString class]] ? data[@"action"] : @"";
    entry.adminUid = [data[@"adminUid"] isKindOfClass:[NSString class]] ? data[@"adminUid"] : @"";
    if (entry.adminUid.length == 0 && [data[@"userId"] isKindOfClass:[NSString class]]) {
        entry.adminUid = data[@"userId"];
    }
    entry.targetUid = [data[@"targetUid"] isKindOfClass:[NSString class]] ? data[@"targetUid"] : @"";
    if (entry.targetUid.length == 0 && [data[@"targetId"] isKindOfClass:[NSString class]]) {
        entry.targetUid = data[@"targetId"];
    }
    entry.targetCollection = [data[@"targetCollection"] isKindOfClass:[NSString class]] ? data[@"targetCollection"] : nil;
    entry.reason = [data[@"reason"] isKindOfClass:[NSString class]] ? data[@"reason"] : nil;

    entry.before = [data[@"before"] isKindOfClass:NSDictionary.class] ? data[@"before"] : nil;
    entry.after = [data[@"after"] isKindOfClass:NSDictionary.class] ? data[@"after"] : nil;
    entry.metadata = [data[@"metadata"] isKindOfClass:NSDictionary.class] ? data[@"metadata"] : nil;

    id ts = data[@"timestamp"];
    if ([ts isKindOfClass:FIRTimestamp.class]) {
        entry.timestamp = [(FIRTimestamp *)ts dateValue];
    } else if ([ts isKindOfClass:NSDate.class]) {
        entry.timestamp = ts;
    } else {
        entry.timestamp = [NSDate date];
    }
    return entry;
}

- (NSString *)formattedTimestamp {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale currentLocale];
        [fmt setLocalizedDateFormatFromTemplate:@"d MMM yyyy h:mm:ss a"];
    });
    if (!self.timestamp) return @"--";
    return [fmt stringFromDate:self.timestamp];
}

- (NSString *)relativeTimeString {
    if (!self.timestamp) return @"--";
    NSTimeInterval delta = fabs([[NSDate date] timeIntervalSinceDate:self.timestamp]);
    if (delta < 60) {
        return kLang(@"Audit_Time_JustNow");
    } else if (delta < 3600) {
        NSInteger mins = MAX(1, (NSInteger)(delta / 60));
        return [NSString stringWithFormat:kLang(@"Audit_Time_MinutesAgo"), (long)mins];
    } else if (delta < 86400) {
        NSInteger hrs = MAX(1, (NSInteger)(delta / 3600));
        return [NSString stringWithFormat:kLang(@"Audit_Time_HoursAgo"), (long)hrs];
    } else {
        NSInteger days = MAX(1, (NSInteger)(delta / 86400));
        return [NSString stringWithFormat:kLang(@"Audit_Time_DaysAgo"), (long)days];
    }
}

- (PPAuditActionCategory)actionCategory {
    NSString *act = self.action.lowercaseString;
    if ([act hasPrefix:@"delete_"] || [act isEqualToString:@"set_blocked"] || [act containsString:@"void"] || [act containsString:@"cancel"]) {
        return PPAuditActionCategoryDestructive;
    }
    if ([act hasPrefix:@"set_permission"] || [act hasPrefix:@"set_role"] || [act hasPrefix:@"set_admin"] ||
        [act isEqualToString:@"set_unblocked"] || [act containsString:@"auth"] || [act containsString:@"login"]) {
        return PPAuditActionCategorySecurity;
    }
    if ([act containsString:@"service"] || [act containsString:@"category"] || [act containsString:@"accessory"] || [act containsString:@"ad_"]) {
        return PPAuditActionCategoryServices;
    }
    if ([act containsString:@"branch"] || [act containsString:@"agent"] || [act containsString:@"banner"] || [act containsString:@"settings"]) {
        return PPAuditActionCategoryOperations;
    }
    if ([act containsString:@"pos"] || [act containsString:@"transaction"] || [act containsString:@"order"] ||
        [act containsString:@"payment"] || [act containsString:@"refund"] || [act containsString:@"expense"] || [act containsString:@"income"]) {
        return PPAuditActionCategoryFinance;
    }
    return PPAuditActionCategoryGeneral;
}

- (PPAuditSeverity)severity {
    NSString *act = self.action.lowercaseString;
    if ([act hasPrefix:@"delete_"] || [act isEqualToString:@"set_blocked"] || [act containsString:@"cancel"] || [act containsString:@"void"]) {
        return PPAuditSeverityCritical;
    }
    if ([act hasPrefix:@"update_"] || [act hasPrefix:@"set_"] || [act containsString:@"override"] || [act containsString:@"moderate"]) {
        return PPAuditSeverityWarning;
    }
    if ([act hasPrefix:@"create_"] || [act hasPrefix:@"add_"] || [act isEqualToString:@"set_unblocked"]) {
        return PPAuditSeverityConstructive;
    }
    return PPAuditSeverityInfo;
}

- (NSString *)categoryTitle {
    switch ([self actionCategory]) {
        case PPAuditActionCategoryDestructive:
            return kLang(@"Audit_Filter_Destructive");
        case PPAuditActionCategorySecurity:
            return kLang(@"Audit_Filter_Security");
        case PPAuditActionCategoryServices:
            return kLang(@"Audit_Filter_Services");
        case PPAuditActionCategoryOperations:
            return kLang(@"Audit_Filter_Ops");
        case PPAuditActionCategoryFinance:
            return kLang(@"Audit_Filter_Finance");
        case PPAuditActionCategoryGeneral:
        default:
            return kLang(@"Audit_Filter_All");
    }
}

- (NSString *)localizedActionTitle {
    NSString *act = self.action;
    if ([act isEqualToString:@"set_blocked"]) return kLang(@"Audit_ActionSetBlocked");
    if ([act isEqualToString:@"set_unblocked"]) return kLang(@"Audit_ActionSetUnblocked");
    if ([act isEqualToString:@"set_permission"]) return kLang(@"Audit_ActionSetPermission");
    if ([act isEqualToString:@"set_role"]) return kLang(@"Audit_ActionSetRole");
    if ([act isEqualToString:@"create_user"]) return kLang(@"Audit_ActionCreateUser");
    if ([act isEqualToString:@"delete_user"]) return kLang(@"Audit_ActionDeleteUser");
    if ([act isEqualToString:@"update_user"]) return kLang(@"Audit_ActionUpdateUser");

    if ([act isEqualToString:@"UPDATE_SERVICE_TITLES_3_WORDS_MAX"]) {
        return [Language isRTL] ? @"تحديث عناوين الخدمات (حد أقصى ٣ كلمات)" : @"Update Service Titles (3 Words Max)";
    }
    if ([act containsString:@"_"]) {
        NSString *humanized = [[act stringByReplacingOccurrencesOfString:@"_" withString:@" "] capitalizedString];
        return humanized;
    }
    return act.length > 0 ? act : kLang(@"None");
}

- (NSString *)systemIconName {
    switch ([self actionCategory]) {
        case PPAuditActionCategoryDestructive:
            return @"trash.fill";
        case PPAuditActionCategorySecurity:
            return @"shield.checkerboard";
        case PPAuditActionCategoryServices:
            return @"pawprint.fill";
        case PPAuditActionCategoryOperations:
            return @"slider.horizontal.3";
        case PPAuditActionCategoryFinance:
            return @"creditcard.fill";
        case PPAuditActionCategoryGeneral:
        default:
            return @"doc.text.magnifyingglass";
    }
}

- (UIColor *)accentColor {
    switch ([self actionCategory]) {
        case PPAuditActionCategoryDestructive:
            return [UIColor ppError];
        case PPAuditActionCategorySecurity:
            return [UIColor ppQuickActionAnimals];
        case PPAuditActionCategoryServices:
            return [UIColor ppQuickActionServices];
        case PPAuditActionCategoryOperations:
            return [UIColor ppQuickActionCommunity];
        case PPAuditActionCategoryFinance:
            return [UIColor ppPremiumAccent];
        case PPAuditActionCategoryGeneral:
        default:
            return [UIColor ppTextSecondary];
    }
}

- (UIColor *)badgeBackgroundColor {
    UIColor *base = [self accentColor];
    return [base colorWithAlphaComponent:0.12];
}

- (UIColor *)badgeTextColor {
    return [self accentColor];
}

- (NSArray<PPAuditDiffItem *> *)computedDiff {
    if (self.cachedDiff) return self.cachedDiff;

    NSDictionary *before = self.before ?: @{};
    NSDictionary *after = self.after ?: @{};

    NSMutableSet *allKeys = [NSMutableSet setWithArray:before.allKeys];
    [allKeys addObjectsFromArray:after.allKeys];

    NSMutableArray<PPAuditDiffItem *> *items = [NSMutableArray array];
    NSArray *sortedKeys = [[allKeys allObjects] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *key in sortedKeys) {
        id oldVal = before[key];
        id newVal = after[key];

        if (oldVal == nil && newVal != nil) {
            [items addObject:[PPAuditDiffItem itemWithKey:key
                                                     type:PPAuditDiffTypeAdded
                                                 oldValue:nil
                                                 newValue:newVal]];
        } else if (oldVal != nil && newVal == nil) {
            [items addObject:[PPAuditDiffItem itemWithKey:key
                                                     type:PPAuditDiffTypeRemoved
                                                 oldValue:oldVal
                                                 newValue:nil]];
        } else if (![PPAuditStringFromObject(oldVal) isEqualToString:PPAuditStringFromObject(newVal)]) {
            [items addObject:[PPAuditDiffItem itemWithKey:key
                                                     type:PPAuditDiffTypeModified
                                                 oldValue:oldVal
                                                 newValue:newVal]];
        } else {
            [items addObject:[PPAuditDiffItem itemWithKey:key
                                                     type:PPAuditDiffTypeUnchanged
                                                 oldValue:oldVal
                                                 newValue:newVal]];
        }
    }

    self.cachedDiff = items.copy;
    return self.cachedDiff;
}

- (NSInteger)addedKeysCount {
    NSInteger count = 0;
    for (PPAuditDiffItem *item in [self computedDiff]) {
        if (item.diffType == PPAuditDiffTypeAdded) count++;
    }
    return count;
}

- (NSInteger)removedKeysCount {
    NSInteger count = 0;
    for (PPAuditDiffItem *item in [self computedDiff]) {
        if (item.diffType == PPAuditDiffTypeRemoved) count++;
    }
    return count;
}

- (NSInteger)modifiedKeysCount {
    NSInteger count = 0;
    for (PPAuditDiffItem *item in [self computedDiff]) {
        if (item.diffType == PPAuditDiffTypeModified) count++;
    }
    return count;
}

- (BOOL)hasDiff {
    return self.before.count > 0 || self.after.count > 0;
}

@end

