#import "PPAdminCommandCenterService.h"

#import "Services/Session/PPAdminSessionBridge.h"
#import "Payments/PPPaymentManagementService.h"
#import "Fulfillment/PPFulfillmentService.h"
#import "Delivery/PPDeliveryService.h"
#import "Providers/PPProviderService.h"
#import "UsersSection/SecFil/PPStaffAuth.h"

#import <os/log.h>
#import <objc/runtime.h>

@import FirebaseFirestore;

#pragma mark - Universal Firestore Query Index Logger

static NSString *PPFireCallerDescription(void) {
    NSArray<NSString *> *symbols = [NSThread callStackSymbols];
    for (NSString *symbol in symbols) {
        if ([symbol containsString:@"PurePetsAdmin"] &&
            ![symbol containsString:@"pp_fire_"] &&
            ![symbol containsString:@"PPFireLog"]) {
            NSRange bracketRange = [symbol rangeOfString:@"[-+][a-zA-Z0-9_() ]+" options:NSRegularExpressionSearch];
            if (bracketRange.location != NSNotFound) {
                return [symbol substringWithRange:bracketRange];
            }
            NSArray<NSString *> *parts = [symbol componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray<NSString *> *nonEmpty = [NSMutableArray array];
            for (NSString *p in parts) {
                if (p.length > 0) [nonEmpty addObject:p];
            }
            if (nonEmpty.count >= 4) {
                return [[nonEmpty subarrayWithRange:NSMakeRange(3, nonEmpty.count - 3)] componentsJoinedByString:@" "];
            }
            return symbol;
        }
    }
    return @"UnknownCaller";
}

static NSString *PPFireQueryDescription(id query) {
    if (!query) return @"";
    if ([query respondsToSelector:@selector(path)]) {
        NSString *path = [query valueForKey:@"path"];
        if (path.length > 0) {
            return [NSString stringWithFormat:@"collection='%@'", path];
        }
    }
    return @"";
}

static void PPFireLogQueryOutcome(NSString *opType, id query, NSString *caller, NSError * _Nullable error, NSUInteger docCount) {
    NSString *queryInfo = PPFireQueryDescription(query);
    if (error) {
        NSString *desc = error.localizedDescription ?: @"Unknown error";
        BOOL isIndexNeeded = [desc localizedCaseInsensitiveContainsString:@"index"] ||
                             [desc containsString:@"create_composite="] ||
                             (error.code == 9 && [error.domain isEqualToString:@"FIRFirestoreErrorDomain"]);
        if (isIndexNeeded) {
            NSLog(@"[FIRE] 🚨🚨🚨 FIRESTORE INDEX REQUIRED! 🚨🚨🚨");
            NSLog(@"[FIRE] 📍 Operation: %@", opType);
            if (queryInfo.length > 0) NSLog(@"[FIRE] 📍 Target: %@", queryInfo);
            NSLog(@"[FIRE] 📍 Caller: %@", caller);
            NSLog(@"[FIRE] ⚠️ Message: %@", desc);
            NSRange range = [desc rangeOfString:@"https://console.firebase.google.com[^ \n\t\r]+" options:NSRegularExpressionSearch];
            if (range.location != NSNotFound) {
                NSLog(@"[FIRE] 🔗 Create Index URL:\n%@", [desc substringWithRange:range]);
            }
        } else {
            NSLog(@"[FIRE] ❌ %@ Error in %@: %@ (%@)", opType, caller, desc, queryInfo);
        }
    } else {
        if (queryInfo.length > 0) {
            NSLog(@"[FIRE] ✅ %@ Success (%lu docs) [%@] in %@", opType, (unsigned long)docCount, queryInfo, caller);
        } else {
            NSLog(@"[FIRE] ✅ %@ Success (%lu docs) in %@", opType, (unsigned long)docCount, caller);
        }
    }
}

@interface FIRQuery (PPFireIndexLogging)
@end

@implementation FIRQuery (PPFireIndexLogging)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [FIRQuery class];

        SEL s1 = @selector(getDocumentsWithCompletion:);
        SEL s2 = @selector(pp_fire_getDocumentsWithCompletion:);
        Method m1 = class_getInstanceMethod(cls, s1);
        Method m2 = class_getInstanceMethod(cls, s2);
        if (m1 && m2) method_exchangeImplementations(m1, m2);

        SEL s3 = @selector(getDocumentsWithSource:completion:);
        SEL s4 = @selector(pp_fire_getDocumentsWithSource:completion:);
        Method m3 = class_getInstanceMethod(cls, s3);
        Method m4 = class_getInstanceMethod(cls, s4);
        if (m3 && m4) method_exchangeImplementations(m3, m4);

        SEL s5 = @selector(addSnapshotListenerWithIncludeMetadataChanges:listener:);
        SEL s6 = @selector(pp_fire_addSnapshotListenerWithIncludeMetadataChanges:listener:);
        Method m5 = class_getInstanceMethod(cls, s5);
        Method m6 = class_getInstanceMethod(cls, s6);
        if (m5 && m6) method_exchangeImplementations(m5, m6);

        NSLog(@"[FIRE] 🔥 Firebase Firestore query index detection installed successfully.");
    });
}

- (void)pp_fire_getDocumentsWithCompletion:(void (^)(FIRQuerySnapshot * _Nullable, NSError * _Nullable))completion {
    NSString *caller = PPFireCallerDescription();
    NSString *queryInfo = PPFireQueryDescription(self);
    if (queryInfo.length > 0) {
        NSLog(@"[FIRE] 🔍 Query START [%@] in %@", queryInfo, caller);
    } else {
        NSLog(@"[FIRE] 🔍 Query START in %@", caller);
    }
    [self pp_fire_getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        PPFireLogQueryOutcome(@"getDocuments", self, caller, error, snapshot.documents.count);
        if (completion) {
            completion(snapshot, error);
        }
    }];
}

- (void)pp_fire_getDocumentsWithSource:(FIRFirestoreSource)source
                            completion:(void (^)(FIRQuerySnapshot * _Nullable, NSError * _Nullable))completion {
    NSString *caller = PPFireCallerDescription();
    NSString *queryInfo = PPFireQueryDescription(self);
    if (queryInfo.length > 0) {
        NSLog(@"[FIRE] 🔍 Query (source=%ld) START [%@] in %@", (long)source, queryInfo, caller);
    } else {
        NSLog(@"[FIRE] 🔍 Query (source=%ld) START in %@", (long)source, caller);
    }
    [self pp_fire_getDocumentsWithSource:source completion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        PPFireLogQueryOutcome(@"getDocumentsWithSource", self, caller, error, snapshot.documents.count);
        if (completion) {
            completion(snapshot, error);
        }
    }];
}

- (id<FIRListenerRegistration>)pp_fire_addSnapshotListenerWithIncludeMetadataChanges:(BOOL)includeMetadataChanges
                                                                            listener:(void (^)(FIRQuerySnapshot * _Nullable, NSError * _Nullable))listener {
    NSString *caller = PPFireCallerDescription();
    NSString *queryInfo = PPFireQueryDescription(self);
    if (queryInfo.length > 0) {
        NSLog(@"[FIRE] 📡 SnapshotListener START [%@] in %@", queryInfo, caller);
    } else {
        NSLog(@"[FIRE] 📡 SnapshotListener START in %@", caller);
    }
    return [self pp_fire_addSnapshotListenerWithIncludeMetadataChanges:includeMetadataChanges listener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        PPFireLogQueryOutcome(@"snapshotListener", self, caller, error, snapshot.documents.count);
        if (listener) {
            listener(snapshot, error);
        }
    }];
}

@end

#pragma mark - Privacy-safe source diagnostics

// Public fields below are bounded technical metadata. Actor IDs, entity IDs,
// document payloads, and userInfo values are intentionally never emitted.
static os_log_t PPAdminCommandCenterDiagnosticLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.purepets.admin", "CommandCenterSource");
    });
    return log;
}

static NSInteger PPAdminCommandCenterElapsedMilliseconds(NSDate *startedAt) {
    if (!startedAt) return 0;
    return MAX(0, (NSInteger)(-[startedAt timeIntervalSinceNow] * 1000.0));
}

static NSString *PPAdminCommandCenterPublicList(NSArray<NSString *> *values) {
    NSMutableOrderedSet<NSString *> *safeValues = [NSMutableOrderedSet orderedSet];
    for (id value in values ?: @[]) {
        if (![value isKindOfClass:NSString.class]) continue;
        NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) [safeValues addObject:trimmed];
    }
    return safeValues.count > 0 ? [safeValues.array componentsJoinedByString:@","] : @"none";
}

static NSString *PPAdminCommandCenterErrorUserInfoKeys(NSError *error) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (id key in error.userInfo.allKeys ?: @[]) {
        if ([key isKindOfClass:NSString.class] && [(NSString *)key length] > 0) {
            [keys addObject:key];
        }
    }
    [keys sortUsingSelector:@selector(compare:)];
    return PPAdminCommandCenterPublicList(keys);
}

static NSUInteger PPAdminCommandCenterScopeCount(NSDictionary<NSString *, id> *scope, NSString *key) {
    id value = [scope isKindOfClass:NSDictionary.class] ? scope[key] : nil;
    return [value isKindOfClass:NSArray.class] ? [(NSArray *)value count] : 0;
}

static NSString *PPAdminCommandCenterFulfillmentClassification(NSError *error, BOOL partial) {
    if (partial) return @"partial_read";
    if (![error.domain isEqualToString:@"PPFulfillmentService"]) return @"firestore_query_failure";
    switch (error.code) {
        case 410: return @"permission_denied";
        case 411: return @"missing_read_scope";
        case 412: return @"session_changed";
        case 413: return @"partial_read";
        default: return @"fulfillment_read_failure";
    }
}

static void PPAdminCommandCenterLogSourceStart(NSString *traceID,
                                               NSString *source,
                                               NSString *authority) {
    os_log_with_type(PPAdminCommandCenterDiagnosticLog(), OS_LOG_TYPE_INFO,
                     "trace=%{public}@ event=source.start source=%{public}@ authority=%{public}@",
                     traceID, source, authority);
}

static void PPAdminCommandCenterLogSourceSkip(NSString *traceID, NSString *source) {
    os_log_with_type(PPAdminCommandCenterDiagnosticLog(), OS_LOG_TYPE_INFO,
                     "trace=%{public}@ event=source.skip source=%{public}@ reason=permission_gate",
                     traceID, source);
}

static void PPAdminCommandCenterLogSourceResult(NSString *traceID,
                                                NSString *source,
                                                NSString *outcome,
                                                NSDate *startedAt,
                                                NSInteger recordCount,
                                                NSInteger actionableCount,
                                                NSString *metadata) {
    os_log_with_type(PPAdminCommandCenterDiagnosticLog(),
                     [outcome isEqualToString:@"success"] ? OS_LOG_TYPE_INFO : OS_LOG_TYPE_DEFAULT,
                     "trace=%{public}@ event=source.finish source=%{public}@ outcome=%{public}@ durationMs=%{public}ld records=%{public}ld actionable=%{public}ld metadata=%{public}@",
                     traceID, source, outcome,
                     (long)PPAdminCommandCenterElapsedMilliseconds(startedAt),
                     (long)recordCount, (long)actionableCount, metadata ?: @"none");
}

static void PPAdminCommandCenterLogSourceError(NSString *traceID,
                                               NSString *source,
                                               NSString *classification,
                                               NSDate *startedAt,
                                               NSError *error) {
    NSDictionary<NSString *, id> *details = [PPDeliveryService domainDetailsForError:error];
    NSString *domainCode = [details[@"domainCode"] isKindOfClass:NSString.class] ? details[@"domainCode"] : @"none";
    NSString *entityType = [details[@"entityType"] isKindOfClass:NSString.class] ? details[@"entityType"] : @"none";
    NSString *reasonCodes = [details[@"reasons"] isKindOfClass:NSArray.class]
        ? PPAdminCommandCenterPublicList(details[@"reasons"])
        : @"none";
    NSInteger retryable = [details[@"retryable"] isKindOfClass:NSNumber.class]
        ? [details[@"retryable"] boolValue]
        : -1;
    NSInteger successfulQueries = [error.userInfo[@"successfulQueryCount"] isKindOfClass:NSNumber.class]
        ? [error.userInfo[@"successfulQueryCount"] integerValue]
        : -1;
    NSInteger queryCount = [error.userInfo[@"queryCount"] isKindOfClass:NSNumber.class]
        ? [error.userInfo[@"queryCount"] integerValue]
        : -1;

    NSError *currentError = error;
    NSUInteger depth = 0;
    while (currentError && depth < 4) {
        os_log_with_type(PPAdminCommandCenterDiagnosticLog(), OS_LOG_TYPE_ERROR,
                         "trace=%{public}@ event=source.error source=%{public}@ classification=%{public}@ durationMs=%{public}ld depth=%{public}lu domain=%{public}@ code=%{public}ld domainCode=%{public}@ entityType=%{public}@ retryable=%{public}ld reasons=%{public}@ successfulQueries=%{public}ld queryCount=%{public}ld userInfoKeys=%{public}@ description=%{private}@ failureReason=%{private}@ recovery=%{private}@",
                         traceID, source, classification,
                         (long)PPAdminCommandCenterElapsedMilliseconds(startedAt),
                         (unsigned long)depth,
                         currentError.domain ?: @"none", (long)currentError.code,
                         depth == 0 ? domainCode : @"none",
                         depth == 0 ? entityType : @"none",
                         depth == 0 ? (long)retryable : -1L,
                         depth == 0 ? reasonCodes : @"none",
                         depth == 0 ? (long)successfulQueries : -1L,
                         depth == 0 ? (long)queryCount : -1L,
                         PPAdminCommandCenterErrorUserInfoKeys(currentError),
                         currentError.localizedDescription ?: @"",
                         currentError.localizedFailureReason ?: @"",
                         currentError.localizedRecoverySuggestion ?: @"");
        id underlying = currentError.userInfo[NSUnderlyingErrorKey];
        currentError = [underlying isKindOfClass:NSError.class] ? underlying : nil;
        depth += 1;
    }
}

@implementation PPAdminCommandSnapshot
@end

@implementation PPAdminCommandCenterService

+ (instancetype)shared {
    static PPAdminCommandCenterService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [PPAdminCommandCenterService new];
    });
    return service;
}

- (void)loadSnapshotForSession:(PPAdminSessionSnapshot *)session
                    completion:(PPAdminCommandSnapshotCompletion)completion {
    NSString *traceID = NSUUID.UUID.UUIDString.lowercaseString;
    NSDate *snapshotStartedAt = [NSDate date];
    PPAdminCommandSnapshot *snapshot = [PPAdminCommandSnapshot new];
    snapshot.diagnosticTraceID = traceID;
    snapshot.generatedAt = [NSDate date];
    snapshot.activeOrdersCount = NSNotFound;
    snapshot.awaitingFulfillmentCount = NSNotFound;
    snapshot.activeDeliveryCount = NSNotFound;
    snapshot.pendingProviderApplicationCount = NSNotFound;
    snapshot.adsCount = NSNotFound;
    snapshot.usersCount = NSNotFound;
    snapshot.accessoriesCount = NSNotFound;

    NSMutableOrderedSet<NSString *> *failedAreas = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *partialAreas = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *requestedAreas = [NSMutableOrderedSet orderedSet];
    dispatch_group_t group = dispatch_group_create();
    FIRFirestore *db = [FIRFirestore firestore];

    BOOL canViewPayments = [session hasAnyPermission:@[@"payments.view", @"payments.manage"]];
    BOOL canViewFulfillment = [session hasAnyPermission:@[@"payments.view", @"payments.manage", @"providers.view"]];
    BOOL canViewDelivery = [session hasAnyPermission:@[@"delivery.view", @"payments.manage"]];
    BOOL canViewProviders = [session hasAnyPermission:@[@"providers.view", @"providers.manage"]];
    BOOL canViewListings = [session hasAnyPermission:@[@"listings.view", @"listings.manage", @"listings.moderate"]] &&
                           [session hasPermission:@"stock.manage"];
    BOOL canViewUsers = [session hasAnyPermission:@[@"users.view", @"users.manage"]];
    BOOL canViewStock = [session hasAnyPermission:@[@"stock.view", @"stock.manage"]];

    PPStaffDoc *cachedStaff = [PPStaffAuth shared].cachedCurrentStaff;
    BOOL cachedStaffMatchesSession = cachedStaff.uid.length > 0 && session.uid.length > 0 &&
                                     [cachedStaff.uid isEqualToString:session.uid];
    BOOL cachedPermissionsMatchSession = cachedStaff != nil &&
        [[NSSet setWithArray:cachedStaff.permissions ?: @[]] isEqualToSet:[NSSet setWithArray:session.permissions ?: @[]]];
    os_log_with_type(PPAdminCommandCenterDiagnosticLog(), OS_LOG_TYPE_INFO,
                     "trace=%{public}@ event=snapshot.start role=%{private}@ sessionPermissions=%{public}lu grantsAll=%{public}d globalScope=%{public}d branchScopes=%{public}lu regionScopes=%{public}lu cachedStaffPresent=%{public}d cachedStaffActive=%{public}d cachedStaffMatchesSession=%{public}d cachedPermissionsMatchSession=%{public}d cachedStaffPermissions=%{public}lu cachedGlobalScope=%{public}d cachedBranchScopes=%{public}lu cachedRegionScopes=%{public}lu gates=payments:%{public}d,fulfillment:%{public}d,delivery:%{public}d,providers:%{public}d,listings:%{public}d,users:%{public}d,stock:%{public}d",
                     traceID, session.roleIdentifier ?: @"",
                     (unsigned long)session.permissions.count,
                     session.grantsAllPermissions, session.hasGlobalScope,
                     (unsigned long)PPAdminCommandCenterScopeCount(session.scope, @"branchIds"),
                     (unsigned long)PPAdminCommandCenterScopeCount(session.scope, @"regionIds"),
                     cachedStaff != nil, cachedStaff.isActive, cachedStaffMatchesSession, cachedPermissionsMatchSession,
                     (unsigned long)cachedStaff.permissions.count,
                     cachedStaff.hasGlobalScope,
                     (unsigned long)PPAdminCommandCenterScopeCount(cachedStaff.scope, @"branchIds"),
                     (unsigned long)PPAdminCommandCenterScopeCount(cachedStaff.scope, @"regionIds"),
                     canViewPayments, canViewFulfillment, canViewDelivery, canViewProviders,
                     canViewListings, canViewUsers, canViewStock);

    NSLog(@"[FIRE] ⚡ CommandCenter loadSnapshot started (traceID: %@, payments:%d, fulfillment:%d, delivery:%d, providers:%d, listings:%d, users:%d, stock:%d)",
          traceID, canViewPayments, canViewFulfillment, canViewDelivery, canViewProviders, canViewListings, canViewUsers, canViewStock);

    if (canViewPayments) {
        [requestedAreas addObject:@"payments"];
        PPAdminCommandCenterLogSourceStart(traceID, @"payments", @"service:PPPaymentManagementService pageSize=100");
        NSDate *sourceStartedAt = [NSDate date];
        dispatch_group_enter(group);
        [[PPPaymentManagementService shared] fetchOrdersWithFilters:[PPPaymentManagementFilters defaultFilters]
                                                            pageSize:100
                                                          startAfter:nil
                                                          completion:^(NSArray<PPPaymentAdminRecord *> *records,
                                                                       FIRDocumentSnapshot * _Nullable nextCursor,
                                                                       NSError * _Nullable error) {
            (void)nextCursor;
            BOOL isPartialRead = [PPPaymentManagementService isPartialReadError:error];
            if (error && !isPartialRead) {
                @synchronized (failedAreas) { [failedAreas addObject:@"payments"]; }
                PPAdminCommandCenterLogSourceError(traceID, @"payments", @"payment_read_failure", sourceStartedAt, error);
            } else {
                if (isPartialRead) {
                    @synchronized (partialAreas) { [partialAreas addObject:@"payments"]; }
                }
                NSInteger active = 0;
                for (PPPaymentAdminRecord *record in records ?: @[]) {
                    NSString *status = [record workflowStatusKey];
                    BOOL isResolvedRefund = [status isEqualToString:@"refunded"] || [status isEqualToString:@"partially_refunded"];
                    BOOL isTerminal = [PPPaymentAdminRecord isDeliveredLikeStatus:status] ||
                                      [PPPaymentAdminRecord isCancelledLikeStatus:status] ||
                                      [PPPaymentAdminRecord isFailureLikeStatus:status] ||
                                      isResolvedRefund;
                    if (!isTerminal) {
                        active += 1;
                    }
                }
                snapshot.activeOrdersCount = active;
                PPAdminCommandCenterLogSourceResult(traceID, @"payments",
                                                     isPartialRead ? @"partial" : @"success",
                                                     sourceStartedAt, records.count, active,
                                                     nextCursor ? @"nextPage=yes" : @"nextPage=no");
                if (isPartialRead) {
                    PPAdminCommandCenterLogSourceError(traceID, @"payments", @"partial_read", sourceStartedAt, error);
                }
            }
            dispatch_group_leave(group);
        }];
    } else {
        PPAdminCommandCenterLogSourceSkip(traceID, @"payments");
    }

    if (canViewFulfillment) {
        [requestedAreas addObject:@"fulfillment"];
        PPAdminCommandCenterLogSourceStart(traceID, @"fulfillment", @"firestore:FulfillmentOrders scoped limit=100");
        NSDate *sourceStartedAt = [NSDate date];
        dispatch_group_enter(group);
        [[PPFulfillmentService shared] fetchFulfillmentsWithCompletion:^(NSArray<PPFulfillmentRecord *> *records,
                                                                         NSError * _Nullable error) {
            BOOL isPartialRead = [PPFulfillmentService isPartialReadError:error];
            if (error && !isPartialRead) {
                @synchronized (failedAreas) { [failedAreas addObject:@"fulfillment"]; }
                PPAdminCommandCenterLogSourceError(traceID, @"fulfillment",
                                                   PPAdminCommandCenterFulfillmentClassification(error, NO),
                                                   sourceStartedAt, error);
            } else {
                if (isPartialRead) {
                    @synchronized (partialAreas) { [partialAreas addObject:@"fulfillment"]; }
                }
                NSSet<NSString *> *awaiting = [NSSet setWithArray:@[
                    @"new_request", @"accepted", @"preparing", @"ready_for_pickup", @"delivery_assigned"
                ]];
                NSInteger count = 0;
                for (PPFulfillmentRecord *record in records ?: @[]) {
                    NSString *status = record.status.lowercaseString ?: @"";
                    if ([awaiting containsObject:status]) count += 1;
                }
                snapshot.awaitingFulfillmentCount = count;
                PPAdminCommandCenterLogSourceResult(traceID, @"fulfillment",
                                                     isPartialRead ? @"partial" : @"success",
                                                     sourceStartedAt, records.count, count,
                                                     @"statuses=new_request|accepted|preparing|ready_for_pickup|delivery_assigned");
                if (isPartialRead) {
                    PPAdminCommandCenterLogSourceError(traceID, @"fulfillment", @"partial_read", sourceStartedAt, error);
                }
            }
            dispatch_group_leave(group);
        }];
    } else {
        PPAdminCommandCenterLogSourceSkip(traceID, @"fulfillment");
    }

    if (canViewDelivery) {
        [requestedAreas addObject:@"delivery"];
        PPAdminCommandCenterLogSourceStart(traceID, @"delivery", @"callable:getDeliveryCommandCenter pageSize=100");
        NSDate *sourceStartedAt = [NSDate date];
        dispatch_group_enter(group);
        [[PPDeliveryService shared] fetchCommandCenterWithCompletion:^(PPDeliveryCommandCenterSnapshot *projection,
                                                                        NSError *error) {
            if (error) {
                @synchronized (failedAreas) { [failedAreas addObject:@"delivery"]; }
                PPAdminCommandCenterLogSourceError(traceID, @"delivery",
                                                   [PPDeliveryService domainCodeForError:error],
                                                   sourceStartedAt, error);
            } else {
                NSDictionary *counts = [projection.projection[@"counts"] isKindOfClass:NSDictionary.class]
                    ? projection.projection[@"counts"]
                    : @{};
                NSNumber *active = [counts[@"active"] isKindOfClass:NSNumber.class] ? counts[@"active"] : nil;
                snapshot.activeDeliveryCount = active ? active.integerValue : NSNotFound;
                if (!active) {
                    @synchronized (partialAreas) { [partialAreas addObject:@"delivery"]; }
                }
                NSString *metadata = [NSString stringWithFormat:@"permissionSource=%@ projectionKeys=%@",
                                      projection.permissionSource.length > 0 ? projection.permissionSource : @"none",
                                      PPAdminCommandCenterPublicList(projection.projection.allKeys)];
                PPAdminCommandCenterLogSourceResult(traceID, @"delivery",
                                                     active ? @"success" : @"partial",
                                                     sourceStartedAt, projection.records.count,
                                                     active ? active.integerValue : -1,
                                                     metadata);
            }
            dispatch_group_leave(group);
        }];
    } else {
        PPAdminCommandCenterLogSourceSkip(traceID, @"delivery");
    }

    if (canViewProviders) {
        [requestedAreas addObject:@"providers"];
        PPAdminCommandCenterLogSourceStart(traceID, @"providers", @"service:PPProviderService applications");
        NSDate *sourceStartedAt = [NSDate date];
        dispatch_group_enter(group);
        [[PPProviderService shared] fetchApplicationsWithCompletion:^(NSArray<PPProviderApplication *> *apps,
                                                                       NSError *error) {
            if (error) {
                @synchronized (failedAreas) { [failedAreas addObject:@"providers"]; }
                PPAdminCommandCenterLogSourceError(traceID, @"providers", @"provider_read_failure", sourceStartedAt, error);
            } else {
                NSInteger count = 0;
                for (PPProviderApplication *application in apps ?: @[]) {
                    NSString *status = application.status.lowercaseString ?: @"";
                    if (status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"]) {
                        count += 1;
                    }
                }
                snapshot.pendingProviderApplicationCount = count;
                PPAdminCommandCenterLogSourceResult(traceID, @"providers", @"success",
                                                     sourceStartedAt, apps.count, count,
                                                     @"statuses=pending|under_review|empty");
            }
            dispatch_group_leave(group);
        }];
    } else {
        PPAdminCommandCenterLogSourceSkip(traceID, @"providers");
    }

    [self pp_fetchCountForCollection:@"pet_ads"
                             allowed:canViewListings
                                  key:@"listings"
                                   db:db
                                group:group
                           failedAreas:failedAreas
                                traceID:traceID
                           assignment:^(NSInteger count) { snapshot.adsCount = count; }];
    if (canViewListings) [requestedAreas addObject:@"listings"];
    else PPAdminCommandCenterLogSourceSkip(traceID, @"listings");
    [self pp_fetchCountForCollection:@"UsersCol"
                             allowed:canViewUsers
                                  key:@"users"
                                   db:db
                                group:group
                           failedAreas:failedAreas
                                traceID:traceID
                           assignment:^(NSInteger count) { snapshot.usersCount = count; }];
    if (canViewUsers) [requestedAreas addObject:@"users"];
    else PPAdminCommandCenterLogSourceSkip(traceID, @"users");
    [self pp_fetchCountForCollection:@"petAccessories"
                             allowed:canViewStock
                                  key:@"stock"
                                   db:db
                                group:group
                           failedAreas:failedAreas
                                traceID:traceID
                           assignment:^(NSInteger count) { snapshot.accessoriesCount = count; }];
    if (canViewStock) [requestedAreas addObject:@"stock"];
    else PPAdminCommandCenterLogSourceSkip(traceID, @"stock");

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        snapshot.requestedAreas = requestedAreas.array ?: @[];
        snapshot.failedAreas = failedAreas.array ?: @[];
        snapshot.partialAreas = partialAreas.array ?: @[];
        snapshot.generatedAt = [NSDate date];
        os_log_with_type(PPAdminCommandCenterDiagnosticLog(),
                         snapshot.failedAreas.count > 0 ? OS_LOG_TYPE_ERROR : OS_LOG_TYPE_INFO,
                         "trace=%{public}@ event=snapshot.finish durationMs=%{public}ld requested=%{public}@ failed=%{public}@ partial=%{public}@",
                         traceID, (long)PPAdminCommandCenterElapsedMilliseconds(snapshotStartedAt),
                         PPAdminCommandCenterPublicList(snapshot.requestedAreas),
                         PPAdminCommandCenterPublicList(snapshot.failedAreas),
                         PPAdminCommandCenterPublicList(snapshot.partialAreas));
        if (completion) completion(snapshot);
    });
}

- (void)pp_fetchCountForCollection:(NSString *)collection
                           allowed:(BOOL)allowed
                                key:(NSString *)key
                                 db:(FIRFirestore *)db
                              group:(dispatch_group_t)group
                        failedAreas:(NSMutableOrderedSet<NSString *> *)failedAreas
                            traceID:(NSString *)traceID
                         assignment:(void (^)(NSInteger count))assignment {
    if (!allowed) return;
    NSLog(@"[FIRE] 🔍 CommandCenter querying count for collection: %@", collection);
    PPAdminCommandCenterLogSourceStart(traceID, key,
                                       [NSString stringWithFormat:@"firestore:%@ unfiltered count", collection]);
    NSDate *sourceStartedAt = [NSDate date];
    dispatch_group_enter(group);
    [[db collectionWithPath:collection] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable result,
                                                                      NSError * _Nullable error) {
        if (error) {
            NSLog(@"[FIRE] ❌ CommandCenter collection '%@' query failed: %@", collection, error.localizedDescription);
            @synchronized (failedAreas) { [failedAreas addObject:key]; }
            PPAdminCommandCenterLogSourceError(traceID, key, @"firestore_collection_read_failure", sourceStartedAt, error);
        } else if (assignment) {
            NSLog(@"[FIRE] ✅ CommandCenter collection '%@' count: %lu", collection, (unsigned long)result.documents.count);
            assignment(result.documents.count);
            PPAdminCommandCenterLogSourceResult(traceID, key, @"success", sourceStartedAt,
                                                 result.documents.count, result.documents.count,
                                                 [NSString stringWithFormat:@"collection=%@", collection]);
        }
        dispatch_group_leave(group);
    }];
}

@end
