#import "PPAuditLogEntryModel.h"

@implementation PPAuditLogEntryModel

+ (instancetype)entryFromSnapshot:(FIRDocumentSnapshot *)snapshot {
    PPAuditLogEntryModel *entry = [PPAuditLogEntryModel new];
    entry.auditId = snapshot.documentID;
    NSDictionary *data = snapshot.data;
    if (!data) return entry;
    entry.action = data[@"action"] ?: @"";
    entry.adminUid = data[@"adminUid"] ?: @"";
    entry.targetUid = data[@"targetUid"] ?: @"";
    entry.reason = data[@"reason"];
    entry.before = [data[@"before"] isKindOfClass:NSDictionary.class] ? data[@"before"] : nil;
    entry.after = [data[@"after"] isKindOfClass:NSDictionary.class] ? data[@"after"] : nil;
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
        [fmt setLocalizedDateFormatFromTemplate:@"d MMM yyyy h:mm a"];
    });
    if (!self.timestamp) return @"--";
    return [fmt stringFromDate:self.timestamp];
}

@end
