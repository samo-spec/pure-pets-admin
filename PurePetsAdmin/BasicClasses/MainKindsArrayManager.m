//
//  MainKindsArrayManager.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 08/08/2025.
//

#import "MainKindsArrayManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
static NSString * const kCachedMainKindsKey = @"cachedMainKinds";


//NSArray<MainKindsModel *> *PPMainKinds      = nil;

// MainKindsArrayManager.m
@implementation MainKindsArrayManager
+ (instancetype)shared {
    
    static id s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [self new];
        //   sharedInstance.MainKindsArray = [NSMutableArray<MainKindsModel *> new];
        //   self.subKindsArrayForFilter = [[NSMutableArray<SubKindModel *> alloc] init];
    });
    
    return s;
}

- (void)listenForMainKindsChangesWithBlock:(void (^)(NSArray<MainKindsModel *> *mainKinds, NSError *error))block {
    if (self.mainKindsListener) {
        [self.mainKindsListener remove];
        self.mainKindsListener = nil;
    }
    
    FIRQuery *query = [[[FIRFirestore firestore] collectionWithPath:@"MainKindsCollection"]
                       queryOrderedByField:@"sortingKey" descending:NO];
    
    __weak typeof(self) weakSelf = self;
    self.mainKindsListener = [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            NSLog(@"[MainKinds] ❌ Listener error: %@", error.localizedDescription);
            if (block) block(nil, error);
            return;
        }
        
        NSMutableArray<MainKindsModel *> *arr = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            MainKindsModel *m = [[MainKindsModel alloc] initWithSnapshot:doc];
            if (m) [arr addObject:m];
        }
        
        [arr sortUsingComparator:^NSComparisonResult(MainKindsModel *a, MainKindsModel *b) {
            return a.sortingKey < b.sortingKey ? NSOrderedAscending :
            a.sortingKey > b.sortingKey ? NSOrderedDescending :
            NSOrderedSame;
        }];
        
        strongSelf.MainKindsArray = arr.mutableCopy;
        
        NSLog(@"[MainKinds] 🔄 Listener updated → %lu items", (unsigned long)arr.count);
        
        [self saveMainKindsToCache];
        
        if (block) block(arr, nil);
    }];
}

//tnuBlC!bPt^x]37R
/*
 tnuBlC!bPt^x]37R
 + (void)loadMainDataCompletionHandler:(void (^)(int result))completionHandler {
 NSLog(@"===========================================");
 NSLog(@"PPMainKindsManager: 🔄 loadMainData (prefer cache, fallback server)");
 
 FIRQuery *q = [[[FIRFirestore firestore] collectionWithPath:@"MainKindsCollection"]
 queryOrderedByField:@"ID" descending:NO];
 
 // ---- 1) Try CACHE ----
 [q getDocumentsWithSource:FIRFirestoreSourceCache
 completion:^(FIRQuerySnapshot * _Nullable cacheSnap, NSError * _Nullable cacheErr)
 {
 if (cacheErr) {
 NSLog(@"PPMainKindsManager: ⚠️ Cache read error: %@", cacheErr.localizedDescription);
 }
 
 BOOL hasCache = (cacheSnap && cacheSnap.documents.count > 0);
 if (hasCache) {
 NSLog(@"PPMainKindsManager: 💾 Cache hit. docs=%lu fromCache=%d pending=%d",
 (unsigned long)cacheSnap.documents.count,
 cacheSnap.metadata.isFromCache,
 cacheSnap.metadata.hasPendingWrites);
 
 NSArray<MainKindsModel *> *cacheModels = [self pp_modelsFromSnapshot:cacheSnap];
 // Keep immutable snapshot in global
 PPMainKindsArray = [cacheModels copy];
 
 // Return immediately to UI
 [self pp_finishWithSuccess:YES completion:completionHandler];
 
 // Also refresh from SERVER in background — optional but recommended
 [self pp_refreshFromServerIfChangedWithQuery:q baseline:cacheModels];
 
 return;
 }
 
 // ---- 2) No cache: fall back to SERVER ----
 NSLog(@"PPMainKindsManager: 💨 No cache. Fetching from SERVER...");
 [q getDocumentsWithSource:FIRFirestoreSourceServer
 completion:^(FIRQuerySnapshot * _Nullable serverSnap, NSError * _Nullable serverErr)
 {
 if (serverErr || !serverSnap) {
 NSLog(@"PPMainKindsManager: ❌ Server fetch failed: %@", serverErr.localizedDescription);
 [self pp_finishWithSuccess:NO completion:completionHandler];
 return;
 }
 
 NSLog(@"PPMainKindsManager: 🌐 Server docs=%lu fromCache=%d pending=%d",
 (unsigned long)serverSnap.documents.count,
 serverSnap.metadata.isFromCache,
 serverSnap.metadata.hasPendingWrites);
 
 NSArray<MainKindsModel *> *srvModels = [self pp_modelsFromSnapshot:serverSnap];
 PPMainKindsArray = [srvModels copy];
 
 [self pp_finishWithSuccess:YES completion:completionHandler];
 }];
 }];
 }
 */
#pragma mark - Helpers

/// Map a snapshot to models, sort by numeric `ID`.
+ (NSArray<MainKindsModel *> *)pp_modelsFromSnapshot:(FIRQuerySnapshot *)snap {
    NSMutableArray<MainKindsModel *> *arr = [NSMutableArray arrayWithCapacity:snap.documents.count];
    
    for (FIRDocumentSnapshot *doc in snap.documents) {
        if (!doc.exists) { continue; }
        
        MainKindsModel *m = [[MainKindsModel alloc] initWithSnapshot:doc];
        if (!m) {
            NSLog(@"PPMainKindsManager: ⚠️ initWithSnapshot returned nil for docID=%@", doc.documentID);
            continue;
        }
        
        // Ensure arrays exist if your UI expects them
        if (!m.SubKindsArray) m.SubKindsArray = [NSMutableArray array];
        
        [arr addObject:m];
        // Deep log
        // NSLog(@"PPMainKindsManager: main doc=%@ path=%@ ID=%ld", doc.documentID, doc.reference.path, (long)m.ID);
    }
    
    // Sort by ID ascending (adjust if you need sortingKey, etc.)
    [arr sortUsingComparator:^NSComparisonResult(MainKindsModel *a, MainKindsModel *b) {
        if (a.ID < b.ID) return NSOrderedAscending;
        if (a.ID > b.ID) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    return arr;
}

/// Finish on main thread: call completion(1/0) + post notification if success
+ (void)pp_finishWithSuccess:(BOOL)ok completion:(void (^)(int))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(ok ? 1 : 0);
        if (ok) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"fetchMainKindsComplete"
                                                                object:self
                                                              userInfo:nil];
        }
    });
}

/// Fetch from server and update global if different than baseline. Posts notification on change.
+ (void)pp_refreshFromServerIfChangedWithQuery:(FIRQuery *)q
                                      baseline:(NSArray<MainKindsModel *> *)baseline
{
    [q getDocumentsWithSource:FIRFirestoreSourceServer completion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable err) {
        if (err || !snap) {
            NSLog(@"PPMainKindsManager: ⚠️ Server refresh failed: %@", err.localizedDescription);
            return;
        }
        
        NSArray<MainKindsModel *> *serverModels = [self pp_modelsFromSnapshot:snap];
        
        // Simple difference check: count + IDs ordered. Customize if needed.
        BOOL changed = ![self pp_sameMainKinds:baseline other:serverModels];
        if (changed) {
            NSLog(@"PPMainKindsManager: 🔁 Server has updates. Updating global + notifying.");
            PPMainKindsArray = [serverModels copy];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"fetchMainKindsComplete"
                                                                    object:self
                                                                  userInfo:nil];
            });
        } else {
            NSLog(@"PPMainKindsManager: ✅ Cache already up-to-date with server.");
        }
    }];
}

+ (BOOL)pp_sameMainKinds:(NSArray<MainKindsModel *> *)a other:(NSArray<MainKindsModel *> *)b {
    if (a.count != b.count) return NO;
    for (NSUInteger i = 0; i < a.count; i++) {
        if (a[i].ID != b[i].ID) return NO; // basic equality by ID; extend if needed
    }
    return YES;
}




- (void)fetchMainKindByID:(NSString *)mainID completion:(void(^)(NSDictionary *, NSError *))completion {
    if (!mainID.length) { if (completion) completion(nil, [NSError errorWithDomain:@"arg" code:400 userInfo:nil]); return; }
    [[[[FIRFirestore firestore] collectionWithPath:@"MainKindsCollection"]
      documentWithPath:mainID]
     getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable err) {
        completion(snap.exists ? snap.data : nil, err);
    }];
}

// New subcollection-based implementation
- (void)addOrReplaceSubKind:(SubKindModel *)sub toMainID:(NSString *)mainID completion:(void(^)(NSError *))completion {
    if (!mainID.length || !sub) {
        if (completion) completion([NSError errorWithDomain:@"arg" code:400 userInfo:@{NSLocalizedDescriptionKey:@"Invalid arguments"}]);
        return;
    }
    
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *mainDoc = [[db collectionWithPath:@"MainKindsCollection"] documentWithPath:mainID];
    
    // SubKind document id strategy:
    // - Prefer an existing documentID if present
    // - Else use numeric ID as string (stable)
    NSString *subDocID = nil;
    if ([sub respondsToSelector:@selector(documentID)] && sub.ID > 0) {
        subDocID =  [NSString stringWithFormat:@"%ld", (long)sub.ID];
    } else {
        subDocID = [NSString stringWithFormat:@"%ld", (long)sub.ID];
    }
    
    FIRDocumentReference *subDoc = [[mainDoc collectionWithPath:@"SubKinds"] documentWithPath:subDocID];
    
    NSMutableDictionary *data = [[sub toDict] mutableCopy];
    // Keep strong linkage
    data[@"MainKindID"] = @(sub.MainKindID ?: [mainID integerValue]);
    data[@"documentID"] = subDocID;
    
    [subDoc setData:data merge:YES completion:^(NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}

// New subcollection-based implementation
- (void)removeSubKindID:(NSString *)subID fromMainID:(NSString *)mainID completion:(void(^)(NSError *))completion {
    if (!mainID.length || !subID.length) {
        if (completion) completion([NSError errorWithDomain:@"arg" code:400 userInfo:@{NSLocalizedDescriptionKey:@"Invalid arguments"}]);
        return;
    }
    
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *mainDoc = [[db collectionWithPath:@"MainKindsCollection"] documentWithPath:mainID];
    FIRDocumentReference *subDoc = [[mainDoc collectionWithPath:@"SubKinds"] documentWithPath:subID];
    
    [subDoc deleteDocumentWithCompletion:^(NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}

- (void)FillMainKindsArray
{
    [self loadMainDataCompletionHandler:^(int result) {
        NSLog(@"Initial MainKindsArray Complete From AppDelegate");
    }];
}

- (NSArray<MainKindsModel *> *)loadMainKindsFromCache {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] objectForKey:kCachedMainKindsKey];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (NSDictionary *mainKind in raw) {
        MainKindsModel *u = [[MainKindsModel alloc] initWithDict:mainKind];
        if (u) [out addObject:u];
    }
    //NSLog(@"[Cache] 📥 Loaded %lu users from cache.", (unsigned long)out.count);
    return out;
}


// MARK: - Users cache
- (void)saveMainKindsToCache {
    NSMutableArray *arr = [NSMutableArray array];
    for (MainKindsModel *mainKind in self.MainKindsArray) {
        if ([mainKind respondsToSelector:@selector(toFirestoreDictionary)]) {
            [arr addObject:[mainKind toFirestoreDictionary]];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:kCachedMainKindsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    ////NSLog(@"[Cache] 💾 Saved %lu users.", (unsigned long)arr.count);
}


- (void)loadMainDataCompletionHandler:(void (^)(int result))completionHandler {
    // Initialize array if needed
    
    self.MainKindsArray =  [self loadMainKindsFromCache].mutableCopy;
    NSLog(@"Initial MainKindsArray Complete From %@",self.MainKindsArray.count > 0 ? @"::CACHE::" :  @"::SERVER::");
    if (!self.MainKindsArray) {
        self.MainKindsArray = [NSMutableArray array];
    }
    else
    {
        
        
    }
    
    // If we already have cached MainKinds data, return it immediately.
    BOOL hasCache = (self.MainKindsArray.count > 0);
    if (hasCache) {
        if (completionHandler) {
            
            NSLog(@"completionHandler MainKindsArray Because it complete from cache ✅✅✅✅✅✅");
            completionHandler(1);  // Return success with cached data
        }
    }
    
    // Clean up any existing listener to avoid duplicates
    if (self.mainKindsListener) {
        [self.mainKindsListener remove];
        self.mainKindsListener = nil;
    }
    
    // Set a flag indicating whether initial data has been seeded
    self.didSeedMainKinds = hasCache;
    
    // Build the Firestore query (sorted by ID ascending)
    FIRQuery *query = [[[FIRFirestore firestore] collectionWithPath:@"MainKindsCollection"] queryOrderedByField:@"sortingKey" descending:NO];
    
    // Use weakSelf in the block to avoid retain cycles
    __weak typeof(self) weakSelf = self;
    self.mainKindsListener = [query addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        
        if (error) {
            NSLog(@"Error fetching MainKinds: %@", error.localizedDescription);
            // Only call completion handler with failure if we haven't seeded data yet
            if (completionHandler && !strongSelf.didSeedMainKinds) {
                completionHandler(0);
            }
            return;
        }
        if (!snapshot) {
            NSLog(@"No snapshot returned for MainKindsCollection");
            if (completionHandler && !strongSelf.didSeedMainKinds) {
                completionHandler(0);
            }
            return;
        }
        
        // **Initial load:** seed the array from the first snapshot if not already done
        if (!strongSelf.didSeedMainKinds) {
            NSLog(@"Initial seed of MainKindsArray from snapshot...");
            
            
            [strongSelf.MainKindsArray removeAllObjects];
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                MainKindsModel *model = [[MainKindsModel alloc] initWithSnapshot:doc];
                if (!model.SubKindsArray) model.SubKindsArray = [NSMutableArray array];
                model.didSeedSubKinds = NO;
                [strongSelf.MainKindsArray addObject:model];
            }
            // Sort array by ID to maintain order
            [strongSelf.MainKindsArray sortUsingComparator:^NSComparisonResult(MainKindsModel *a, MainKindsModel *b) {
                if (a.sortingKey < b.sortingKey) return NSOrderedAscending;
                if (a.sortingKey > b.sortingKey) return NSOrderedDescending;
                return NSOrderedSame;
            }];
            strongSelf.didSeedMainKinds = YES;
            [self saveMainKindsToCache];
            // Invoke completion handler now that initial load is done (if not already called)
            if (!hasCache && completionHandler) {
                NSLog(@"Initial MainKindsArray updated with Server %lu items.", (unsigned long)strongSelf.MainKindsArray.count);
                completionHandler(1);
            }
            
            return;  // Return here so we don't also run the incremental loop on this same snapshot
        }
        
        // **Incremental updates:** process any document changes after initial seed
        for (FIRDocumentChange *change in snapshot.documentChanges) {
            NSString *docID = change.document.documentID;
            // Helper: find index in the array by document ID
            NSInteger idx = [strongSelf indexOfMainKindByDocID:docID];
            MainKindsModel *updatedModel = [[MainKindsModel alloc] initWithSnapshot:change.document];
            if (!updatedModel.SubKindsArray) updatedModel.SubKindsArray = [NSMutableArray array];
            updatedModel.didSeedSubKinds = NO;
            
            switch (change.type) {
                case FIRDocumentChangeTypeAdded:
                    if (idx != NSNotFound) {
                        // Already exists: update it
                        strongSelf.MainKindsArray[idx] = updatedModel;
                    } else {
                        // New document: append to array
                        [strongSelf.MainKindsArray addObject:updatedModel];
                    }
                    break;
                case FIRDocumentChangeTypeModified:
                    if (idx != NSNotFound) {
                        strongSelf.MainKindsArray[idx] = updatedModel;
                    } else {
                        [strongSelf.MainKindsArray addObject:updatedModel];
                    }
                    break;
                case FIRDocumentChangeTypeRemoved:
                    if (idx != NSNotFound) {
                        [strongSelf.MainKindsArray removeObjectAtIndex:idx];
                    }
                    break;
                    
                    
            }
        }
        
        // Re-sort the array after processing changes
        [strongSelf.MainKindsArray sortUsingComparator:^NSComparisonResult(MainKindsModel *a, MainKindsModel *b) {
            if (a.sortingKey < b.sortingKey) return NSOrderedAscending;
            if (a.sortingKey > b.sortingKey) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        
        if(snapshot.documentChanges > 0)
        {
            NSLog(@"MainKindsArray documentChanges ");
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"MainKindsUpdatedNotification"
                                                                object:self
                                                              userInfo:@{@"MainKindsArray": strongSelf.MainKindsArray}];
        }
        /*
         
         // Re-sort the array after processing changes
         [strongSelf.MainKindsArray sortUsingComparator:^NSComparisonResult(MainKindsModel *a, MainKindsModel *b) {
         if (a.ID < b.ID) return NSOrderedAscending;
         if (a.ID > b.ID) return NSOrderedDescending;
         return NSOrderedSame;
         }];
         */
        NSLog(@"MainKindsArray updated with Online %lu items.", (unsigned long)strongSelf.MainKindsArray.count);
        // (Optionally, you could post a notification or call completion here if needed.)
        [self saveMainKindsToCache];
        if (completionHandler) {
            completionHandler(1);  // Return success with cached data
        }
    }];
}

// Helper method to find index of MainKind by Firestore documentID
- (NSInteger)indexOfMainKindByDocID:(NSString *)docID {
    if (!docID || self.MainKindsArray.count == 0) {
        return NSNotFound;
    }
    
    __block NSInteger foundIndex = NSNotFound;
    [self.MainKindsArray enumerateObjectsUsingBlock:^(MainKindsModel *obj, NSUInteger idx, BOOL *stop) {
        if ([obj.documentID isEqualToString:docID]) {
            foundIndex = idx;
            *stop = YES;
        }
    }];
    return foundIndex;
}


- (NSArray<SubKindModel *> *)getSubKindArray:(NSInteger)MainKindID
{
    return [[self.MainKindsArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.ID == %ld", MainKindID]] firstObject].SubKindsArray;
    // return  self.MainKindsArray[MainKindID].SubKindsArray;
}
- (MainKindsModel *)mainKindForID:(NSInteger)kindID {
    // snapshot to avoid mutation while iterating
    NSArray<MainKindsModel *> *snapshot = [self.MainKindsArray copy];
    for (MainKindsModel *mk in snapshot) {
        if (mk.ID == kindID) {
            return mk;
        }
    }
    return nil;
}

/*///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

// MARK: - Subcollections API

/// Subcollections API
- (void)listenForSubKindsForMainKind:(MainKindsModel *)mainKind
                               block:(void (^)(NSArray<SubKindModel *> *subKinds, NSError *error))block
{
    if (!mainKind.documentID.length) {
        if (block) block(nil, [NSError errorWithDomain:@"arg" code:400 userInfo:@{NSLocalizedDescriptionKey:@"MainKind documentID is missing"}]);
        return;
    }
    
    // Remove previous listener on this mainKind to avoid duplicate streams
    if (mainKind.subKindsListener) {
        [mainKind.subKindsListener remove];
        mainKind.subKindsListener = nil;
    }
    
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *mainDoc = [[db collectionWithPath:@"MainKindsCollection"] documentWithPath:mainKind.documentID];
    FIRQuery *q = [[mainDoc collectionWithPath:@"SubKinds"] queryOrderedByField:@"ID" descending:NO];
    
    __weak typeof(self) weakSelf = self;
    mainKind.subKindsListener = [q addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            if (block) block(nil, error);
            return;
        }
        if (!snapshot) {
            if (block) block(@[], nil);
            return;
        }
        
        NSMutableArray<SubKindModel *> *arr = [NSMutableArray arrayWithCapacity:snapshot.documents.count];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            SubKindModel *m = [[SubKindModel alloc] initWithSnapshot:doc];
            if (m) {
                m.MainKindID = mainKind.ID; // enforce linkage for UI
                [arr addObject:m];
            }
        }
        
        [arr sortUsingComparator:^NSComparisonResult(SubKindModel *a, SubKindModel *b) {
            if (a.ID < b.ID) return NSOrderedAscending;
            if (a.ID > b.ID) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        
        // Keep it on the model (safe for existing UI that expects SubKindsArray)
        mainKind.SubKindsArray = arr.mutableCopy;
        mainKind.didSeedSubKinds = YES;
        
        if (block) block(arr, nil);
    }];
}

- (void)listenForSubSubKindsForMainKindID:(NSString *)mainKindDocID
                                  subKind:(SubKindModel *)subKind
                                    block:(void (^)(NSArray<subSubKindModel *> *subSubKinds, NSError *error))block
{
    if (!mainKindDocID.length || !subKind) {
        if (block) block(nil, [NSError errorWithDomain:@"arg" code:400 userInfo:@{NSLocalizedDescriptionKey:@"Invalid arguments"}]);
        return;
    }
    
    // Remove previous listener on this subKind
    if (subKind.subSubKindsListener) {
        [subKind.subSubKindsListener remove];
        subKind.subSubKindsListener = nil;
    }
    
    NSString *subDocID =        [NSString stringWithFormat:@"%ld", (long)subKind.ID];
    
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *subDoc = [[[[db collectionWithPath:@"MainKindsCollection"] documentWithPath:mainKindDocID]
                                     collectionWithPath:@"SubKinds"] documentWithPath:subDocID];
    
    FIRQuery *q = [[subDoc collectionWithPath:@"SubSubKinds"] queryOrderedByField:@"ID" descending:NO];
    
    __weak typeof(self) weakSelf = self;
    subKind.subSubKindsListener = [q addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            if (block) block(nil, error);
            return;
        }
        if (!snapshot) {
            if (block) block(@[], nil);
            return;
        }
        
        NSMutableArray<subSubKindModel *> *arr = [NSMutableArray arrayWithCapacity:snapshot.documents.count];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            subSubKindModel *m = [[subSubKindModel alloc] initWithSnapshot:doc];
            if (m) {
                m.subKindID = subKind.ID;
                [arr addObject:m];
            }
        }
        
        [arr sortUsingComparator:^NSComparisonResult(subSubKindModel *a, subSubKindModel *b) {
            if (a.ID < b.ID) return NSOrderedAscending;
            if (a.ID > b.ID) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        
        subKind.subSubKindArray = arr.mutableCopy;
        if (block) block(arr, nil);
    }];
}

- (void)listenForItemsForMainKindID:(NSString *)mainKindDocID
                          subKindID:(NSString *)subKindDocID
                         subSubKind:(subSubKindModel *)subSubKind
                              block:(void (^)(NSArray<subKindItemsModel *> *items, NSError *error))block
{
    if (!mainKindDocID.length || !subKindDocID.length || !subSubKind) {
        if (block) block(nil, [NSError errorWithDomain:@"arg" code:400 userInfo:@{NSLocalizedDescriptionKey:@"Invalid arguments"}]);
        return;
    }
    
    if (subSubKind.subKindItemsListener) {
        [subSubKind.subKindItemsListener remove];
        subSubKind.subKindItemsListener = nil;
    }
    
    NSString *subSubDocID = [NSString stringWithFormat:@"%ld", (long)subSubKind.ID];
    
    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *subSubDoc = [[[[[[db collectionWithPath:@"MainKindsCollection"] documentWithPath:mainKindDocID]
                                          collectionWithPath:@"SubKinds"] documentWithPath:subKindDocID]
                                        collectionWithPath:@"SubSubKinds"] documentWithPath:subSubDocID];
    
    FIRQuery *q = [[subSubDoc collectionWithPath:@"Items"] queryOrderedByField:@"ID" descending:NO];
    
    __weak typeof(self) weakSelf = self;
    subSubKind.subKindItemsListener = [q addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            if (block) block(nil, error);
            return;
        }
        if (!snapshot) {
            if (block) block(@[], nil);
            return;
        }
        
        NSMutableArray<subKindItemsModel *> *arr = [NSMutableArray arrayWithCapacity:snapshot.documents.count];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            subKindItemsModel *m = [[subKindItemsModel alloc] initWithSnapshot:doc];
            if (m) {
                m.subSubKindID = subSubKind.ID;
                [arr addObject:m];
            }
        }
        
        [arr sortUsingComparator:^NSComparisonResult(subKindItemsModel *a, subKindItemsModel *b) {
            if (a.ID < b.ID) return NSOrderedAscending;
            if (a.ID > b.ID) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        
        subSubKind.subKindItemsArray = arr.mutableCopy;
        if (block) block(arr, nil);
    }];
}

- (void)stopAllKindListeners {
    if (self.mainKindsListener) {
        [self.mainKindsListener remove];
        self.mainKindsListener = nil;
    }
    
    // Stop nested listeners
    for (MainKindsModel *mk in [self.MainKindsArray copy]) {
        if (mk.subKindsListener) {
            [mk.subKindsListener remove];
            mk.subKindsListener = nil;
        }
        for (SubKindModel *sk in [mk.SubKindsArray copy]) {
            if (sk.subSubKindsListener) {
                [sk.subSubKindsListener remove];
                sk.subSubKindsListener = nil;
            }
            for (subSubKindModel *ssk in [sk.subSubKindArray copy]) {
                if (ssk.subKindItemsListener) {
                    [ssk.subKindItemsListener remove];
                    ssk.subKindItemsListener = nil;
                }
            }
        }
    }
}
@end
