#import "PPFulfillmentService.h"
@import FirebaseFunctions;

@interface PPFulfillmentService ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *userProfileCache;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@end

@implementation PPFulfillmentRecord
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _fulfillmentID = docID ?: @"";
        _parentOrderID = PPSafeString(dict[@"parentOrderId"]);
        _parentOrderNumber = PPSafeString(dict[@"parentOrderNumber"]);
        _parentUserId = PPSafeString(dict[@"parentUserId"]);
        _customerID = PPSafeString(dict[@"customerID"]);
        if (!_customerID.length) _customerID = _parentUserId;
        _customerName = PPSafeString(dict[@"customerName"]);
        _ownerID = PPSafeString(dict[@"ownerID"]);
        if (!_ownerID.length) _ownerID = PPSafeString(dict[@"ownerId"]);
        _ownerType = PPSafeString(dict[@"ownerType"]);
        _fulfillmentMode = PPSafeString(dict[@"fulfillmentMode"]);
        _status = PPSafeString(dict[@"status"]);
        _items = PPSafeArray(dict[@"items"]);
        _money = PPSafeDict(dict[@"money"]);
        
        _adminOverrideBy = PPSafeString(dict[@"adminOverrideBy"]);
        _adminOverrideReason = PPSafeString(dict[@"adminOverrideReason"]);

        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
        id ua = dict[@"updatedAt"];
        if ([ua isKindOfClass:FIRTimestamp.class]) _updatedAt = [(FIRTimestamp *)ua dateValue];
        id oa = dict[@"adminOverrideAt"];
        if ([oa isKindOfClass:FIRTimestamp.class]) _adminOverrideAt = [(FIRTimestamp *)oa dateValue];
    }
    return self;
}
@end

@implementation PPFulfillmentService

+ (instancetype)shared {
    static PPFulfillmentService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _userProfileCache = [NSMutableDictionary dictionary];
        _cacheQueue = dispatch_queue_create("com.purepets.fulfillment.cache", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)fetchFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[[db collectionWithPath:@"FulfillmentOrders"] queryOrderedByField:@"updatedAt" descending:YES]
     getDocumentsWithCompletion:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) {
            // Fallback query by createdAt if updatedAt index is absent
            [[[db collectionWithPath:@"FulfillmentOrders"] queryOrderedByField:@"createdAt" descending:YES]
             getDocumentsWithCompletion:^(FIRQuerySnapshot *snap2, NSError *err2) {
                if (err2) { if (completion) completion(@[], err2); return; }
                NSMutableArray *records = [NSMutableArray array];
                for (FIRDocumentSnapshot *doc in snap2.documents) {
                    PPFulfillmentRecord *r = [[PPFulfillmentRecord alloc] initWithDictionary:doc.data documentID:doc.documentID];
                    [records addObject:r];
                }
                if (completion) completion(records, nil);
            }];
            return;
        }
        NSMutableArray *records = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPFulfillmentRecord *r = [[PPFulfillmentRecord alloc] initWithDictionary:doc.data documentID:doc.documentID];
            [records addObject:r];
        }
        if (completion) completion(records, nil);
    }];
}

- (id<FIRListenerRegistration>)observeFulfillmentsWithCompletion:(void(^)(NSArray<PPFulfillmentRecord *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[[db collectionWithPath:@"FulfillmentOrders"] queryOrderedByField:@"updatedAt" descending:YES] queryLimitedTo:100];
    return [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray *records = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            PPFulfillmentRecord *r = [[PPFulfillmentRecord alloc] initWithDictionary:doc.data documentID:doc.documentID];
            [records addObject:r];
        }
        if (completion) completion(records, nil);
    }];
}

- (void)fetchFulfillmentDetail:(NSString *)fulfillmentID completion:(void(^)(PPFulfillmentRecord *, NSArray *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *ref = [[db collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID];
    [ref getDocumentWithCompletion:^(FIRDocumentSnapshot *snap, NSError *error) {
        if (error) { if (completion) completion(nil, @[], error); return; }
        PPFulfillmentRecord *r = [[PPFulfillmentRecord alloc] initWithDictionary:snap.data documentID:snap.documentID];
        [[[ref collectionWithPath:@"events"] queryOrderedByField:@"createdAt" descending:YES]
         getDocumentsWithCompletion:^(FIRQuerySnapshot *eventSnap, NSError *eventError) {
            NSMutableArray *events = [NSMutableArray array];
            for (FIRDocumentSnapshot *edoc in eventSnap.documents) {
                [events addObject:edoc.data ?: @{}];
            }
            if (completion) completion(r, events, eventError);
        }];
    }];
}

- (id<FIRListenerRegistration>)observeFulfillmentEvents:(NSString *)fulfillmentID completion:(void(^)(NSArray<NSDictionary *> *, NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[[[db collectionWithPath:@"FulfillmentOrders"] documentWithPath:fulfillmentID] collectionWithPath:@"events"] queryOrderedByField:@"createdAt" descending:YES];
    return [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(@[], error);
            return;
        }
        NSMutableArray *events = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:doc.data ?: @{}];
            dict[@"id"] = doc.documentID;
            [events addObject:dict];
        }
        if (completion) completion(events, nil);
    }];
}

- (void)resolveUserProfilesForIDs:(NSArray<NSString *> *)userIDs completion:(void(^)(NSDictionary<NSString *, NSString *> *names))completion {
    if (!userIDs.count) {
        if (completion) completion(@{});
        return;
    }
    
    NSMutableSet *missing = [NSMutableSet set];
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    
    dispatch_sync(self.cacheQueue, ^{
        for (NSString *uid in userIDs) {
            if (!uid.length) continue;
            NSString *cached = self.userProfileCache[uid];
            if (cached) {
                results[uid] = cached;
            } else {
                [missing addObject:uid];
            }
        }
    });
    
    if (!missing.count) {
        if (completion) completion(results);
        return;
    }
    
    FIRFirestore *db = [FIRFirestore firestore];
    dispatch_group_t group = dispatch_group_create();
    
    NSArray *missingList = missing.allObjects;
    NSUInteger chunkSize = 10;
    
    for (NSUInteger i = 0; i < missingList.count; i += chunkSize) {
        NSRange range = NSMakeRange(i, MIN(chunkSize, missingList.count - i));
        NSArray *chunk = [missingList subarrayWithRange:range];
        
        dispatch_group_enter(group);
        [[[db collectionWithPath:@"PublicUserProfiles"] queryWhereFieldPath:[FIRFieldPath documentID] in:chunk] getDocumentsWithCompletion:^(FIRQuerySnapshot *snap, NSError *err) {
            NSMutableSet *found = [NSMutableSet set];
            if (!err) {
                for (FIRDocumentSnapshot *doc in snap.documents) {
                    NSDictionary *data = doc.data;
                    NSString *name = PPSafeString(data[@"displayName"]);
                    if (!name.length) name = PPSafeString(data[@"name"]);
                    if (!name.length) name = PPSafeString(data[@"fullName"]);
                    if (!name.length) name = PPSafeString(data[@"email"]);
                    if (name.length) {
                        [found addObject:doc.documentID];
                        dispatch_barrier_async(self.cacheQueue, ^{
                            self.userProfileCache[doc.documentID] = name;
                        });
                        results[doc.documentID] = name;
                    }
                }
            }
            
            NSMutableArray *stillMissing = [NSMutableArray array];
            for (NSString *uid in chunk) {
                if (![found containsObject:uid]) [stillMissing addObject:uid];
            }
            
            if (stillMissing.count > 0) {
                [[[db collectionWithPath:@"UsersCol"] queryWhereFieldPath:[FIRFieldPath documentID] in:stillMissing] getDocumentsWithCompletion:^(FIRQuerySnapshot *uSnap, NSError *uErr) {
                    if (!uErr) {
                        for (FIRDocumentSnapshot *doc in uSnap.documents) {
                            NSDictionary *data = doc.data;
                            NSString *name = PPSafeString(data[@"displayName"]);
                            if (!name.length) name = PPSafeString(data[@"name"]);
                            if (!name.length) name = PPSafeString(data[@"fullName"]);
                            if (!name.length) name = PPSafeString(data[@"email"]);
                            if (name.length) {
                                dispatch_barrier_async(self.cacheQueue, ^{
                                    self.userProfileCache[doc.documentID] = name;
                                });
                                results[doc.documentID] = name;
                            }
                        }
                    }
                    dispatch_group_leave(group);
                }];
            } else {
                dispatch_group_leave(group);
            }
        }];
    }
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (completion) completion(results);
    });
}

- (void)adminOverrideFulfillment:(NSString *)fulfillmentID targetStatus:(NSString *)status reason:(NSString *)reason note:(nullable NSString *)note notify:(BOOL)notify completion:(void(^)(NSDictionary * _Nullable, NSError * _Nullable))completion {
    FIRFunctions *functions = [FIRFunctions functions];
    FIRHTTPSCallable *callable = [functions HTTPSCallableWithName:@"adminOverrideFulfillment"];
    [callable callWithObject:@{
        @"fulfillmentID": fulfillmentID ?: @"",
        @"targetStatus": status ?: @"",
        @"reason": reason ?: @"",
        @"note": note ?: @"",
        @"notifyCustomer": @(notify)
    } completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        NSDictionary *dict = [result.data isKindOfClass:NSDictionary.class] ? (NSDictionary *)result.data : nil;
        if (completion) completion(dict, error);
    }];
}

+ (NSArray<NSString *> *)allowedOverrideTargetsForStatus:(NSString *)currentStatus {
    if (!currentStatus.length) return @[];
    NSDictionary *transitions = @{
        @"new_request": @[@"accepted", @"rejected", @"cancelled", @"failed", @"returned"],
        @"accepted": @[@"preparing", @"rejected", @"cancelled", @"failed", @"returned"],
        @"preparing": @[@"ready_for_pickup", @"rejected", @"cancelled", @"failed", @"returned"],
        @"ready_for_pickup": @[@"delivery_requested", @"cancelled", @"failed", @"returned"],
        @"delivery_requested": @[@"awaiting_handover", @"completed", @"cancelled", @"failed", @"returned"],
        @"delivery_assigned": @[@"awaiting_handover", @"handed_over", @"completed", @"cancelled", @"failed", @"returned"],
        @"awaiting_handover": @[@"handed_over", @"completed", @"cancelled", @"failed", @"returned"],
        @"handed_over": @[@"completed", @"cancelled", @"failed", @"returned"],
        @"completed": @[@"cancelled", @"failed", @"returned"],
        @"rejected": @[@"cancelled", @"failed", @"returned"],
        @"cancelled": @[@"failed", @"returned"],
        @"failed": @[@"cancelled", @"returned"],
        @"returned": @[@"cancelled", @"failed"]
    };
    return transitions[currentStatus] ?: @[];
}

@end