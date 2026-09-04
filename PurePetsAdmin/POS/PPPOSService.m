#import "PPPOSService.h"
#import "PPFirebaseCompat.h"
#import "PPBranchContextManager.h"
#import <os/log.h>
@import Firebase;
@import FirebaseFirestore;
@import FirebaseFunctions;

NSString * const PPPOSLogDidAppendNotification = @"PPPOSLogDidAppendNotification";

static NSString * const PPPOSServiceErrorDomain = @"pp.pos.service";
static NSString * const PPPOSIndividualInventoryMode = @"INDIVIDUAL_TRACKED";

static os_log_t PPPOSSystemLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.purepets.admin", "POS");
    });
    return log;
}

static NSInteger PPPOSElapsedMilliseconds(NSDate *startedAt) {
    if (!startedAt) return 0;
    return MAX(0, (NSInteger)(-[startedAt timeIntervalSinceNow] * 1000.0));
}

static NSError *PPPOSServiceError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:PPPOSServiceErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Invalid POS response."}];
}

static NSArray<NSString *> *PPPOSStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        NSString *string = PPSafeString(item);
        if (string.length > 0) [result addObject:string];
    }
    return result.copy;
}

@implementation PPPOSCartItem
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _itemID = PPSafeString(dict[@"productId"] ?: dict[@"itemId"] ?: dict[@"itemID"]);
        _name = PPSafeString(dict[@"name"]);
        _price = PPSafeDouble(dict[@"unitPrice"] ?: dict[@"price"]);
        _quantity = MAX(1, [PPSafeNumber(dict[@"quantity"]) integerValue]);
        _lineTotal = dict[@"lineTotal"] == nil
            ? _price * _quantity
            : PPSafeDouble(dict[@"lineTotal"]);
        _inventoryMode = PPSafeString(dict[@"inventoryMode"]);
        _unitIDs = PPPOSStringArray(dict[@"unitIds"]);
        _unitRingTags = PPPOSStringArray(dict[@"unitRingTags"]);
        _unitPrices = [dict[@"unitPrices"] isKindOfClass:NSArray.class] ? dict[@"unitPrices"] : @[];
    }
    return self;
}
@end

@implementation PPPOSInventoryUnit
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _unitID = PPSafeString(dict[@"unitId"] ?: dict[@"id"]);
        _ringTag = PPSafeString(dict[@"ringTag"]);
        _sellingPrice = PPSafeDouble(dict[@"sellingPrice"]);
    }
    return self;
}
@end

@implementation PPPOSSubmitResult
@end

@implementation PPPOSReceipt
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _receiptID = docID ?: @"";
        _subtotal = PPSafeDouble(dict[@"subtotal"]);
        _discount = PPSafeDouble(dict[@"discount"]);
        _total = PPSafeDouble(dict[@"total"]);
        _cashReceived = PPSafeDouble(dict[@"cashReceived"]);
        _changeDue = PPSafeDouble(dict[@"changeDue"]);
        _paymentMethod = PPSafeString(dict[@"paymentMethod"]);
        _currency = PPSafeString(dict[@"currency"]);
        _status = PPSafeString(dict[@"status"]);
        _customerName = PPSafeString(dict[@"customerName"]);
        _customerPhone = PPSafeString(dict[@"customerPhone"]);
        _note = PPSafeString(dict[@"note"]);
        _source = PPSafeString(dict[@"source"]);
        _operatorID = PPSafeString(dict[@"operator"] ?: dict[@"createdBy"]);
        _schemaVersion = [PPSafeNumber(dict[@"posSchemaVersion"]) integerValue];
        NSArray *rawItems = PPSafeArray(dict[@"items"]);
        NSMutableArray *parsedItems = [NSMutableArray array];
        for (NSDictionary *raw in rawItems) {
            if ([raw isKindOfClass:NSDictionary.class]) {
                [parsedItems addObject:[[PPPOSCartItem alloc] initWithDictionary:raw]];
            }
        }
        _items = parsedItems.copy;
        id createdAt = dict[@"createdAt"] ?: dict[@"timestamp"];
        if ([createdAt isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)createdAt dateValue];
    }
    return self;
}
@end

#pragma mark - PPPOSLogEntry Implementation

@implementation PPPOSLogEntry

- (instancetype)initWithLevel:(PPPOSLogLevel)level
                     category:(NSString *)category
                        event:(NSString *)event
                      message:(NSString *)message
                      traceID:(nullable NSString *)traceID
                   durationMs:(NSInteger)durationMs
                     metadata:(nullable NSDictionary<NSString *, id> *)metadata {
    self = [super init];
    if (self) {
        _entryID = [[NSUUID UUID] UUIDString];
        _timestamp = [NSDate date];
        _level = level;
        _category = [category copy] ?: @"pos";
        _event = [event copy] ?: @"general";
        _message = [message copy] ?: @"";
        _traceID = [traceID copy];
        _durationMs = durationMs;
        _metadata = metadata ? [metadata copy] : @{};
    }
    return self;
}

- (NSString *)levelString {
    switch (_level) {
        case PPPOSLogLevelDebug: return @"DEBUG";
        case PPPOSLogLevelInfo: return @"INFO";
        case PPPOSLogLevelWarning: return @"WARN";
        case PPPOSLogLevelError: return @"ERROR";
    }
}

- (NSString *)formattedConsoleLine {
    NSMutableString *line = [NSMutableString stringWithFormat:@"[POS][%@][%@]", self.levelString, self.category];
    if (self.traceID.length > 0) {
        [line appendFormat:@" trace=%@", self.traceID];
    }
    [line appendFormat:@" event=%@", self.event];
    if (self.durationMs >= 0) {
        [line appendFormat:@" durationMs=%ld", (long)self.durationMs];
    }
    if (self.message.length > 0) {
        [line appendFormat:@" - %@", self.message];
    }
    if (self.metadata.count > 0) {
        NSMutableArray *pairs = [NSMutableArray array];
        NSArray *sortedKeys = [self.metadata.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *key in sortedKeys) {
            id val = self.metadata[key];
            if ([val isKindOfClass:NSDictionary.class] || [val isKindOfClass:NSArray.class]) {
                NSData *data = [NSJSONSerialization dataWithJSONObject:val options:0 error:nil];
                if (data) {
                    NSString *compact = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, compact]];
                    continue;
                }
            }
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, val]];
        }
        [line appendFormat:@" | %@", [pairs componentsJoinedByString:@" "]];
    }
    return line.copy;
}

- (NSString *)jsonString {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = _entryID;
    static NSISO8601DateFormatter *isoFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isoFormatter = [NSISO8601DateFormatter new];
    });
    dict[@"timestamp"] = [isoFormatter stringFromDate:_timestamp];
    dict[@"level"] = self.levelString;
    dict[@"category"] = _category;
    dict[@"event"] = _event;
    dict[@"message"] = _message;
    if (_traceID.length > 0) dict[@"traceId"] = _traceID;
    if (_durationMs >= 0) dict[@"durationMs"] = @(_durationMs);
    if (_metadata.count > 0) dict[@"metadata"] = _metadata;

    if ([NSJSONSerialization isValidJSONObject:dict]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
        if (data) return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return [NSString stringWithFormat:@"{\"event\":\"%@\",\"message\":\"%@\"}", _event, _message];
}

@end

#pragma mark - PPPOSLogger Implementation

@interface PPPOSLogger ()
@property (nonatomic, strong) NSMutableArray<PPPOSLogEntry *> *buffer;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@end

@implementation PPPOSLogger

+ (instancetype)sharedLogger {
    static PPPOSLogger *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [self new];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _buffer = [NSMutableArray array];
        _logQueue = dispatch_queue_create("com.purepets.admin.poslogger", DISPATCH_QUEUE_SERIAL);
        _consoleLoggingEnabled = YES;
        _maxBufferSize = 500;
    }
    return self;
}

+ (NSString *)generateTraceID {
    return [[NSUUID UUID] UUIDString].lowercaseString;
}

- (void)logLevel:(PPPOSLogLevel)level
        category:(NSString *)category
           event:(NSString *)event
         message:(NSString *)message
         traceID:(nullable NSString *)traceID
      durationMs:(NSInteger)durationMs
        metadata:(nullable NSDictionary<NSString *, id> *)metadata {
    PPPOSLogEntry *entry = [[PPPOSLogEntry alloc] initWithLevel:level
                                                       category:category
                                                          event:event
                                                        message:message
                                                        traceID:traceID
                                                     durationMs:durationMs
                                                       metadata:metadata];

    if (_consoleLoggingEnabled) {
        os_log_type_t osType = OS_LOG_TYPE_DEFAULT;
        switch (level) {
            case PPPOSLogLevelDebug: osType = OS_LOG_TYPE_DEBUG; break;
            case PPPOSLogLevelInfo: osType = OS_LOG_TYPE_INFO; break;
            case PPPOSLogLevelWarning: osType = OS_LOG_TYPE_DEFAULT; break;
            case PPPOSLogLevelError: osType = OS_LOG_TYPE_ERROR; break;
        }
        NSString *consoleLine = [entry formattedConsoleLine];
        os_log_with_type(PPPOSSystemLog(), osType, "%{public}@", consoleLine);
    }

    dispatch_async(self.logQueue, ^{
        [self.buffer addObject:entry];
        while (self.buffer.count > (NSUInteger)self.maxBufferSize) {
            [self.buffer removeObjectAtIndex:0];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:PPPOSLogDidAppendNotification
                                                                object:self
                                                              userInfo:@{ @"entry": entry }];
        });
    });
}

- (void)infoWithCategory:(NSString *)category event:(NSString *)event message:(NSString *)message {
    [self logLevel:PPPOSLogLevelInfo category:category event:event message:message traceID:nil durationMs:-1 metadata:nil];
}

- (void)infoWithCategory:(NSString *)category event:(NSString *)event traceID:(nullable NSString *)traceID metadata:(nullable NSDictionary<NSString *, id> *)metadata message:(NSString *)message {
    [self logLevel:PPPOSLogLevelInfo category:category event:event message:message traceID:traceID durationMs:-1 metadata:metadata];
}

- (void)warnWithCategory:(NSString *)category event:(NSString *)event traceID:(nullable NSString *)traceID metadata:(nullable NSDictionary<NSString *, id> *)metadata message:(NSString *)message {
    [self logLevel:PPPOSLogLevelWarning category:category event:event message:message traceID:traceID durationMs:-1 metadata:metadata];
}

- (void)errorWithCategory:(NSString *)category event:(NSString *)event traceID:(nullable NSString *)traceID durationMs:(NSInteger)durationMs error:(nullable NSError *)error metadata:(nullable NSDictionary<NSString *, id> *)metadata message:(NSString *)message {
    NSMutableDictionary *combined = [NSMutableDictionary dictionaryWithDictionary:metadata ?: @{}];
    if (error) {
        combined[@"errorDomain"] = error.domain ?: @"unknown";
        combined[@"errorCode"] = @(error.code);
        combined[@"errorLocalized"] = error.localizedDescription ?: @"";
        NSDictionary *conflict = [PPPOSService exactUnitConflictDetailsForError:error];
        if (conflict.count > 0) {
            combined[@"conflictDetails"] = conflict;
        }
    }
    [self logLevel:PPPOSLogLevelError category:category event:event message:message traceID:traceID durationMs:durationMs metadata:combined];
}

- (NSArray<PPPOSLogEntry *> *)allEntries {
    __block NSArray *copy;
    dispatch_sync(self.logQueue, ^{
        copy = [self.buffer copy];
    });
    return copy ?: @[];
}

- (NSArray<PPPOSLogEntry *> *)recentEntriesWithLimit:(NSUInteger)limit {
    __block NSArray *copy;
    dispatch_sync(self.logQueue, ^{
        if (self.buffer.count <= limit) {
            copy = [self.buffer copy];
        } else {
            NSRange range = NSMakeRange(self.buffer.count - limit, limit);
            copy = [self.buffer subarrayWithRange:range];
        }
    });
    return copy ?: @[];
}

- (void)clearLogs {
    dispatch_async(self.logQueue, ^{
        [self.buffer removeAllObjects];
    });
}

- (NSString *)exportLogsAsPlainText {
    NSArray *entries = [self allEntries];
    NSMutableArray *lines = [NSMutableArray arrayWithCapacity:entries.count];
    for (PPPOSLogEntry *entry in entries) {
        [lines addObject:[entry formattedConsoleLine]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)exportLogsAsJSON {
    NSArray *entries = [self allEntries];
    NSMutableArray *jsonList = [NSMutableArray arrayWithCapacity:entries.count];
    for (PPPOSLogEntry *entry in entries) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"id"] = entry.entryID;
        dict[@"timestamp"] = entry.timestamp.description;
        dict[@"level"] = entry.levelString;
        dict[@"category"] = entry.category;
        dict[@"event"] = entry.event;
        dict[@"message"] = entry.message;
        if (entry.traceID.length > 0) dict[@"traceId"] = entry.traceID;
        if (entry.durationMs >= 0) dict[@"durationMs"] = @(entry.durationMs);
        if (entry.metadata.count > 0) dict[@"metadata"] = entry.metadata;
        [jsonList addObject:dict];
    }
    if ([NSJSONSerialization isValidJSONObject:jsonList]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:jsonList options:NSJSONWritingPrettyPrinted error:nil];
        if (data) return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return @"[]";
}

- (NSDictionary<NSString *, id> *)diagnosticSummary {
    NSArray *entries = [self allEntries];
    NSInteger infoCount = 0;
    NSInteger warnCount = 0;
    NSInteger errorCount = 0;
    NSString *lastTrace = @"none";
    NSString *lastTxnId = @"none";
    NSInteger lastCheckoutDuration = -1;

    for (PPPOSLogEntry *entry in entries) {
        switch (entry.level) {
            case PPPOSLogLevelInfo: infoCount++; break;
            case PPPOSLogLevelWarning: warnCount++; break;
            case PPPOSLogLevelError: errorCount++; break;
            default: break;
        }
        if (entry.traceID.length > 0) lastTrace = entry.traceID;
        if ([entry.event containsString:@"submit.success"] && entry.metadata[@"transactionId"]) {
            lastTxnId = entry.metadata[@"transactionId"];
            if (entry.metadata[@"durationMs"]) {
                lastCheckoutDuration = [entry.metadata[@"durationMs"] integerValue];
            } else {
                lastCheckoutDuration = entry.durationMs;
            }
        }
    }

    return @{
        @"totalLogs": @(entries.count),
        @"infoCount": @(infoCount),
        @"warningCount": @(warnCount),
        @"errorCount": @(errorCount),
        @"lastTraceID": lastTrace,
        @"lastTransactionID": lastTxnId,
        @"lastCheckoutDurationMs": @(lastCheckoutDuration)
    };
}

@end

#pragma mark - PPPOSService Implementation

@implementation PPPOSService

+ (instancetype)shared {
    static PPPOSService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

+ (BOOL)isExactUnitSelectionConflictError:(NSError *)error {
    if (!error) return NO;
    if (![error.domain isEqualToString:FIRFunctionsErrorDomain] &&
        ![error.domain isEqualToString:@"com.firebase.functions"]) return NO;
    NSDictionary *details = [self exactUnitConflictDetailsForError:error];
    NSString *domainCode = [PPSafeString(details[@"domainCode"]) uppercaseString];
    if ([domainCode hasPrefix:@"POS_INVENTORY_UNIT_"] ||
        [domainCode isEqualToString:@"POS_PRODUCT_NOT_FOUND"] ||
        [domainCode isEqualToString:@"POS_INSUFFICIENT_STOCK"]) {
        return YES;
    }
    if (error.code == FIRFunctionsErrorCodeNotFound) return YES;
    if (error.code != FIRFunctionsErrorCodeFailedPrecondition) return NO;

    NSString *message = [error.localizedDescription lowercaseString];
    return [message containsString:@"inventory unit"] ||
        [message containsString:@"animal"] ||
        [message containsString:@"no longer available"] ||
        [message containsString:@"product is unavailable"] ||
        [message containsString:@"insufficient stock"];
}

+ (NSDictionary<NSString *, id> *)exactUnitConflictDetailsForError:(NSError *)error {
    if (!error || ![error.userInfo isKindOfClass:NSDictionary.class]) return @{};
    id details = error.userInfo[FIRFunctionsErrorDetailsKey] ?: error.userInfo[@"details"];
    return [details isKindOfClass:NSDictionary.class] ? (NSDictionary<NSString *, id> *)details : @{};
}

- (void)listAvailableUnitsForProductID:(NSString *)productID
                                cursor:(NSString *)cursor
                            completion:(void(^)(NSArray<PPPOSInventoryUnit *> *, NSString *, BOOL, NSError *))completion {
    NSString *trimmedProductID = [productID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedProductID.length == 0) {
        NSError *err = PPPOSServiceError(400, @"productId is required.");
        [[PPPOSLogger sharedLogger] errorWithCategory:@"unit"
                                                event:@"unit.list.error"
                                              traceID:nil
                                           durationMs:0
                                                error:err
                                             metadata:nil
                                              message:@"productId is required for unit listing"];
        if (completion) completion(nil, nil, NO, err);
        return;
    }

    NSString *traceID = [PPPOSLogger generateTraceID];
    NSDate *startedAt = [NSDate date];
    [[PPPOSLogger sharedLogger] infoWithCategory:@"unit"
                                           event:@"unit.list.start"
                                         traceID:traceID
                                        metadata:@{ @"productId": trimmedProductID, @"cursor": cursor ?: @"none" }
                                         message:[NSString stringWithFormat:@"Listing available units for product: %@", trimmedProductID]];

    NSMutableDictionary *payload = [@{
        @"productId": trimmedProductID,
        @"includeHistory": @NO,
        @"status": @"AVAILABLE",
        @"pageSize": @(50),
    } mutableCopy];
    if (cursor.length > 0) payload[@"cursor"] = cursor;

    [[[FIRFunctions functions] HTTPSCallableWithName:@"listLivePetInventoryUnits"]
     callWithObject:payload
     completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        NSInteger durationMs = PPPOSElapsedMilliseconds(startedAt);
        if (error) {
            [[PPPOSLogger sharedLogger] errorWithCategory:@"unit"
                                                    event:@"unit.list.error"
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:error
                                                 metadata:@{ @"productId": trimmedProductID }
                                                  message:[NSString stringWithFormat:@"Failed listing units: %@", error.localizedDescription]];
            if (completion) completion(nil, nil, NO, error);
            return;
        }
        NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
        if (![response[@"ok"] boolValue] ||
            ![PPSafeString(response[@"inventoryMode"]) isEqualToString:PPPOSIndividualInventoryMode]) {
            NSError *err = PPPOSServiceError(502, @"Invalid exact-unit response.");
            [[PPPOSLogger sharedLogger] errorWithCategory:@"unit"
                                                    event:@"unit.list.invalid_response"
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:err
                                                 metadata:@{ @"productId": trimmedProductID, @"raw": response ?: @{} }
                                                  message:@"Server returned invalid exact-unit response"];
            if (completion) completion(nil, nil, NO, err);
            return;
        }
        NSMutableArray<PPPOSInventoryUnit *> *units = [NSMutableArray array];
        for (NSDictionary *rawUnit in PPSafeArray(response[@"units"])) {
            if (![rawUnit isKindOfClass:NSDictionary.class]) continue;
            PPPOSInventoryUnit *unit = [[PPPOSInventoryUnit alloc] initWithDictionary:rawUnit];
            if (unit.unitID.length > 0) [units addObject:unit];
        }

        [[PPPOSLogger sharedLogger] logLevel:PPPOSLogLevelInfo
                                    category:@"unit"
                                       event:@"unit.list.success"
                                     message:[NSString stringWithFormat:@"Found %lu units for %@", (unsigned long)units.count, trimmedProductID]
                                     traceID:traceID
                                  durationMs:durationMs
                                    metadata:@{
                                        @"productId": trimmedProductID,
                                        @"unitsCount": @(units.count),
                                        @"hasMore": @([response[@"hasMore"] boolValue]),
                                        @"nextCursor": PPSafeString(response[@"nextCursor"])
                                    }];

        if (completion) {
            completion(units.copy,
                       PPSafeString(response[@"nextCursor"]),
                       [response[@"hasMore"] boolValue],
                       nil);
        }
    }];
}

- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                     completion:(void(^)(PPPOSSubmitResult *, NSError *))completion {
    [self submitPOSOrderWithItems:items
                            total:total
                    paymentMethod:paymentMethod
                     cashReceived:cashReceived
                        commandID:commandID
                     customerName:nil
                    customerPhone:nil
                    posCustomerID:nil
                       completion:completion];
}

- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(NSString *)customerName
                  customerPhone:(NSString *)customerPhone
                  posCustomerID:(NSString *)posCustomerID
                     completion:(void(^)(PPPOSSubmitResult *, NSError *))completion {
    [self submitPOSOrderWithItems:items
                         subtotal:total
                         discount:0.0
                            total:total
                    paymentMethod:paymentMethod
                     cashReceived:cashReceived
                        commandID:commandID
                     customerName:customerName
                    customerPhone:customerPhone
                    posCustomerID:posCustomerID
                       completion:completion];
}

- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                       subtotal:(double)subtotal
                       discount:(double)discount
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(NSString *)customerName
                  customerPhone:(NSString *)customerPhone
                  posCustomerID:(NSString *)posCustomerID
                     completion:(void(^)(PPPOSSubmitResult *, NSError *))completion {
    [self submitPOSOrderWithItems:items
                         subtotal:subtotal
                         discount:discount
                            total:total
                    paymentMethod:paymentMethod
                     cashReceived:cashReceived
                        commandID:commandID
                     customerName:customerName
                    customerPhone:customerPhone
                    posCustomerID:posCustomerID
                         branchID:nil
                       completion:completion];
}

- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                       subtotal:(double)subtotal
                       discount:(double)discount
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(NSString *)customerName
                  customerPhone:(NSString *)customerPhone
                  posCustomerID:(NSString *)posCustomerID
                        branchID:(NSString *)branchID
                      completion:(void(^)(PPPOSSubmitResult *, NSError *))completion {
    NSString *traceID = [PPPOSLogger generateTraceID];
    NSDate *startedAt = [NSDate date];

    NSMutableArray *mappedItems = [NSMutableArray array];
    NSInteger bulkItemsCount = 0;
    NSInteger exactUnitItemsCount = 0;
    NSInteger totalUnitsTracked = 0;

    for (NSDictionary *item in items) {
        NSString *productID = PPSafeString(item[@"itemID"] ?: item[@"itemId"] ?: item[@"productId"]);
        NSString *inventoryMode = PPSafeString(item[@"inventoryMode"]);
        NSMutableDictionary *mapped = [@{
            @"productId": productID,
            @"quantity": item[@"quantity"] ?: @(1),
        } mutableCopy];
        if ([inventoryMode isEqualToString:PPPOSIndividualInventoryMode]) {
            mapped[@"inventoryMode"] = PPPOSIndividualInventoryMode;
            NSArray *uids = [item[@"unitIds"] isKindOfClass:NSArray.class] ? item[@"unitIds"] : @[];
            mapped[@"unitIds"] = uids;
            mapped[@"unitPrices"] = [item[@"unitPrices"] isKindOfClass:NSArray.class] ? item[@"unitPrices"] : @[];
            exactUnitItemsCount++;
            totalUnitsTracked += uids.count;
        } else {
            mapped[@"unitPrice"] = item[@"price"] ?: item[@"unitPrice"] ?: @(0);
            bulkItemsCount++;
        }
        [mappedItems addObject:mapped];
    }

    double roundedSubtotal = round(subtotal * 100.0) / 100.0;
    double roundedDiscount = round(discount * 100.0) / 100.0;
    double roundedTotal = round(total * 100.0) / 100.0;

    NSString *effectiveBranchID = branchID;
    if (effectiveBranchID.length == 0) {
        effectiveBranchID = [PPBranchContextManager sharedManager].activeBranch.branchID;
    }

    NSMutableDictionary *salePayload = [@{
        @"items": mappedItems,
        @"paymentMethod": paymentMethod ?: @"cash",
        @"status": @"completed",
        @"subtotal": @(roundedSubtotal),
        @"discount": @(roundedDiscount),
        @"total": @(roundedTotal),
        @"currency": @"QAR",
        @"source": @"admin_ios",
    } mutableCopy];
    if (effectiveBranchID.length > 0) {
        // `processTransaction` has always accepted `branchID` as the
        // operational branch alias. Use it for completed sales so older
        // deployed revisions do not mistake canonical `branchId` for an
        // explicit customer reservation. Infra still resolves this value into
        // the same branch scope, transaction, inventory, income, and audit
        // fields; reservation commands continue to use canonical `branchId`.
        salePayload[@"branchID"] = effectiveBranchID;
    }
    NSString *activeSessionId = [[NSUserDefaults standardUserDefaults] stringForKey:@"PPActiveBranchSessionID"];
    if (activeSessionId.length > 0) {
        salePayload[@"sessionId"] = activeSessionId;
        salePayload[@"branchSessionId"] = activeSessionId;
    }
    if ([paymentMethod isEqualToString:@"cash"]) {
        salePayload[@"cashReceived"] = @(MAX(roundedTotal, PPSafeDouble(cashReceived)));
    }
    if (customerName.length > 0) {
        salePayload[@"customerName"] = customerName;
    }
    if (customerPhone.length > 0) {
        salePayload[@"customerPhone"] = customerPhone;
    }
    (void)posCustomerID;

    NSMutableDictionary *startMeta = [NSMutableDictionary dictionary];
    startMeta[@"commandId"] = commandID ?: @"none";
    startMeta[@"branchId"] = effectiveBranchID ?: @"none";
    startMeta[@"paymentMethod"] = paymentMethod ?: @"cash";
    startMeta[@"subtotal"] = @(roundedSubtotal);
    startMeta[@"discount"] = @(roundedDiscount);
    startMeta[@"total"] = @(roundedTotal);
    startMeta[@"itemsCount"] = @(mappedItems.count);
    startMeta[@"bulkItemsCount"] = @(bulkItemsCount);
    startMeta[@"exactUnitItemsCount"] = @(exactUnitItemsCount);
    startMeta[@"totalUnitsTracked"] = @(totalUnitsTracked);
    if (activeSessionId.length > 0) startMeta[@"sessionId"] = activeSessionId;
    if (customerPhone.length > 0) startMeta[@"customerPhone"] = customerPhone;

    [[PPPOSLogger sharedLogger] infoWithCategory:@"checkout"
                                           event:@"order.submit.start"
                                         traceID:traceID
                                        metadata:startMeta
                                         message:[NSString stringWithFormat:@"Submitting POS order (%lu items, %.2f QAR via %@, cmd: %@)",
                                                  (unsigned long)mappedItems.count, roundedTotal, paymentMethod, commandID ?: @"none"]];

    NSDictionary *data = @{
        @"action": @"create",
        @"commandId": commandID ?: @"",
        @"payload": salePayload,
    };

    [[[FIRFunctions functions] HTTPSCallableWithName:@"processTransaction"]
     callWithObject:data
     completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        NSInteger durationMs = PPPOSElapsedMilliseconds(startedAt);
        if (error) {
            BOOL isConflict = [PPPOSService isExactUnitSelectionConflictError:error];
            NSDictionary *conflictDetails = isConflict ? [PPPOSService exactUnitConflictDetailsForError:error] : @{};

            NSMutableDictionary *errMeta = [NSMutableDictionary dictionary];
            errMeta[@"commandId"] = commandID ?: @"";
            errMeta[@"branchId"] = effectiveBranchID ?: @"none";
            errMeta[@"isExactUnitConflict"] = @(isConflict);
            if (conflictDetails.count > 0) errMeta[@"conflictDetails"] = conflictDetails;

            NSString *event = isConflict ? @"order.submit.conflict" : @"order.submit.error";
            NSString *msg = isConflict
                ? [NSString stringWithFormat:@"Exact unit selection conflict: %@ (%@)", conflictDetails[@"domainCode"] ?: @"conflict", error.localizedDescription]
                : [NSString stringWithFormat:@"Transaction failed: %@", error.localizedDescription];

            [[PPPOSLogger sharedLogger] errorWithCategory:@"checkout"
                                                    event:event
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:error
                                                 metadata:errMeta
                                                  message:msg];

            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *response = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
        NSString *transactionID = PPSafeString(response[@"transactionId"]);
        NSString *currency = PPSafeString(response[@"currency"]);
        if (![response[@"ok"] boolValue] || transactionID.length == 0 || currency.length == 0) {
            NSError *respError = PPPOSServiceError(502, @"Invalid transaction response.");
            [[PPPOSLogger sharedLogger] errorWithCategory:@"checkout"
                                                    event:@"order.submit.invalid_response"
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:respError
                                                 metadata:@{ @"raw": response ?: @{} }
                                                  message:@"Transaction response missing ok, transactionId or currency"];
            if (completion) completion(nil, respError);
            return;
        }
        PPPOSSubmitResult *submitResult = [PPPOSSubmitResult new];
        submitResult.transactionID = transactionID;
        submitResult.total = PPSafeDouble(response[@"total"]);
        submitResult.currency = currency;
        submitResult.idempotent = [response[@"idempotent"] boolValue];

        [[PPPOSLogger sharedLogger] logLevel:PPPOSLogLevelInfo
                                    category:@"checkout"
                                       event:@"order.submit.success"
                                     message:[NSString stringWithFormat:@"Order committed: %@ (Total: %.2f %@, Idempotent: %@, Duration: %ldms)",
                                              transactionID, submitResult.total, currency, submitResult.isIdempotent ? @"YES" : @"NO", (long)durationMs]
                                     traceID:traceID
                                  durationMs:durationMs
                                    metadata:@{
                                        @"transactionId": transactionID,
                                        @"total": @(submitResult.total),
                                        @"currency": currency,
                                        @"idempotent": @(submitResult.isIdempotent),
                                        @"commandId": commandID ?: @"",
                                        @"branchId": effectiveBranchID ?: @"none",
                                        @"paymentMethod": paymentMethod ?: @"cash",
                                        @"itemsCount": @(mappedItems.count)
                                    }];

        if (completion) completion(submitResult, nil);
    }];
}

- (void)fetchPOSHistoryWithCompletion:(void(^)(NSArray<PPPOSReceipt *> *, NSError *))completion {
    NSString *traceID = [PPPOSLogger generateTraceID];
    NSDate *startedAt = [NSDate date];
    [[PPPOSLogger sharedLogger] infoWithCategory:@"history"
                                           event:@"history.fetch.start"
                                         traceID:traceID
                                        metadata:@{ @"schemas": @"[2, 3]" }
                                         message:@"Fetching POS transaction history (schemas 2 & 3)"];

    FIRCollectionReference *transactions = [[FIRFirestore firestore] collectionWithPath:@"transactions"];
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<PPPOSReceipt *> *receipts = [NSMutableArray array];
    __block NSError *firstError = nil;

    for (NSNumber *schemaVersion in @[@(2), @(3)]) {
        dispatch_group_enter(group);
        [[[transactions queryWhereField:@"posSchemaVersion" isEqualTo:schemaVersion]
           queryOrderedByField:@"createdAt" descending:YES]
          getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
            @synchronized (receipts) {
                if (error && !firstError) firstError = error;
                if (!error) {
                    for (FIRDocumentSnapshot *doc in snapshot.documents) {
                        [receipts addObject:[[PPPOSReceipt alloc] initWithDictionary:doc.data documentID:doc.documentID]];
                    }
                }
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSInteger durationMs = PPPOSElapsedMilliseconds(startedAt);
        if (firstError) {
            [[PPPOSLogger sharedLogger] errorWithCategory:@"history"
                                                    event:@"history.fetch.error"
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:firstError
                                                 metadata:nil
                                                  message:[NSString stringWithFormat:@"History fetch failed: %@", firstError.localizedDescription]];
            if (completion) completion(@[], firstError);
            return;
        }
        [receipts sortUsingComparator:^NSComparisonResult(PPPOSReceipt *left, PPPOSReceipt *right) {
            NSDate *leftDate = left.createdAt ?: NSDate.distantPast;
            NSDate *rightDate = right.createdAt ?: NSDate.distantPast;
            return [rightDate compare:leftDate];
        }];

        [[PPPOSLogger sharedLogger] logLevel:PPPOSLogLevelInfo
                                    category:@"history"
                                       event:@"history.fetch.success"
                                     message:[NSString stringWithFormat:@"Loaded %lu POS history receipts (%ldms)", (unsigned long)receipts.count, (long)durationMs]
                                     traceID:traceID
                                  durationMs:durationMs
                                    metadata:@{ @"receiptsCount": @(receipts.count) }];

        if (completion) completion(receipts.copy, nil);
    });
}

- (void)fetchPOSReceiptForTransactionID:(NSString *)transactionID
                             completion:(void(^)(PPPOSReceipt *, NSError *))completion {
    NSString *trimmedID = [transactionID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedID.length == 0) {
        NSError *err = PPPOSServiceError(400, @"transactionId is required.");
        [[PPPOSLogger sharedLogger] errorWithCategory:@"receipt"
                                                event:@"receipt.fetch.error"
                                              traceID:nil
                                           durationMs:0
                                                error:err
                                             metadata:nil
                                              message:@"transactionId is required"];
        if (completion) completion(nil, err);
        return;
    }

    NSString *traceID = [PPPOSLogger generateTraceID];
    NSDate *startedAt = [NSDate date];
    [[PPPOSLogger sharedLogger] infoWithCategory:@"receipt"
                                           event:@"receipt.fetch.start"
                                         traceID:traceID
                                        metadata:@{ @"transactionId": trimmedID }
                                         message:[NSString stringWithFormat:@"Fetching receipt for transaction: %@", trimmedID]];

    FIRDocumentReference *reference = [[[FIRFirestore firestore] collectionWithPath:@"transactions"]
                                       documentWithPath:trimmedID];
    [reference getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        NSInteger durationMs = PPPOSElapsedMilliseconds(startedAt);
        if (error) {
            [[PPPOSLogger sharedLogger] errorWithCategory:@"receipt"
                                                    event:@"receipt.fetch.error"
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:error
                                                 metadata:@{ @"transactionId": trimmedID }
                                                  message:[NSString stringWithFormat:@"Receipt fetch failed: %@", error.localizedDescription]];
            if (completion) completion(nil, error);
            return;
        }
        NSDictionary *data = snapshot.data;
        if (!snapshot.exists || ![data isKindOfClass:NSDictionary.class]) {
            NSError *notFound = PPPOSServiceError(404, @"Transaction receipt was not found.");
            [[PPPOSLogger sharedLogger] errorWithCategory:@"receipt"
                                                    event:@"receipt.fetch.not_found"
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:notFound
                                                 metadata:@{ @"transactionId": trimmedID }
                                                  message:[NSString stringWithFormat:@"Transaction receipt %@ was not found in Firestore", trimmedID]];
            if (completion) completion(nil, notFound);
            return;
        }

        PPPOSReceipt *receipt = [[PPPOSReceipt alloc] initWithDictionary:data documentID:snapshot.documentID];
        if (receipt.receiptID.length == 0 || receipt.items.count == 0 || receipt.currency.length == 0) {
            NSError *invalid = PPPOSServiceError(502, @"Invalid transaction receipt.");
            [[PPPOSLogger sharedLogger] errorWithCategory:@"receipt"
                                                    event:@"receipt.fetch.invalid"
                                                  traceID:traceID
                                               durationMs:durationMs
                                                    error:invalid
                                                 metadata:@{ @"transactionId": trimmedID }
                                                  message:@"Transaction receipt document payload is incomplete"];
            if (completion) completion(nil, invalid);
            return;
        }

        [[PPPOSLogger sharedLogger] logLevel:PPPOSLogLevelInfo
                                    category:@"receipt"
                                       event:@"receipt.fetch.success"
                                     message:[NSString stringWithFormat:@"Receipt loaded: %@ (%lu items, %.2f %@, %ldms)",
                                              receipt.receiptID, (unsigned long)receipt.items.count, receipt.total, receipt.currency, (long)durationMs]
                                     traceID:traceID
                                  durationMs:durationMs
                                    metadata:@{
                                        @"transactionId": receipt.receiptID,
                                        @"itemsCount": @(receipt.items.count),
                                        @"total": @(receipt.total),
                                        @"currency": receipt.currency
                                    }];

        if (completion) completion(receipt, nil);
    }];
}

@end
