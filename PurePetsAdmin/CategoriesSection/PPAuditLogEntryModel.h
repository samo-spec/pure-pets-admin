#import <Foundation/Foundation.h>
@import Firebase;

NS_ASSUME_NONNULL_BEGIN

@interface PPAuditLogEntryModel : NSObject

@property (nonatomic, copy) NSString *auditId;
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSString *adminUid;
@property (nonatomic, copy) NSString *targetUid;
@property (nonatomic, copy, nullable) NSString *reason;
@property (nonatomic, strong, nullable) NSDictionary *before;
@property (nonatomic, strong, nullable) NSDictionary *after;
@property (nonatomic, strong) NSDate *timestamp;

+ (instancetype)entryFromSnapshot:(FIRDocumentSnapshot *)snapshot;
- (NSString *)formattedTimestamp;

@end

NS_ASSUME_NONNULL_END
