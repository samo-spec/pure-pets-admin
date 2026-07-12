//
//  PPBannersManager 2.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 09/09/2025.
//


// PPBannersManager.m

#import "PPBannersManager.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@class MainBannerModel;
@import Firebase;
@import FirebaseAuth;
@interface PPBannersManager ()
@property (nonatomic, strong) FIRFirestore *db;
@property (nonatomic, strong) id<FIRListenerRegistration> bannersListener;
@property (nonatomic, copy, readwrite) NSArray<MainBannerModel *> *bannerGroups;
@end

@implementation PPBannersManager

+ (instancetype)sharedManager {
    static PPBannersManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PPBannersManager alloc] initPrivate];
    });
    return instance;
}

// Private initializer for singleton.
- (instancetype)initPrivate {
    if (self = [super init]) {
        _db = [FIRFirestore firestore];
        _bannerGroups = @[];
    }
    return self;
}

// Prevent direct init/use of new for singleton.
- (instancetype)init {
    @throw [NSException exceptionWithName:@"Singleton"
                                   reason:@"Use +[PPBannersManager sharedManager] to get the singleton instance."
                                 userInfo:nil];
    return nil;
}

- (void)startListeningForBannersWithCompletion:(void (^)(NSArray<MainBannerModel *> * _Nullable, NSError * _Nullable))completion {
    // Remove existing listener
    [self stopListening];
    __weak typeof(self) weakSelf = self;
    
    // Optional: order by something (e.g. creation time) — omit if not available
    FIRCollectionReference *collection = [self.db collectionWithPath:@"MainBannersViewsCol"];
    self.bannersListener = [collection addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            NSLog(@"[PPBannersManager] startListening error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, error);
            });
            return;
        }
        
        NSMutableArray<MainBannerModel *> *groups = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            NSDictionary *data = doc.data;
            if (!data) continue;
            
            // Ensure the document ID is present in dictionary so model init can read it.
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:data];
            if (!dict[@"BannerViewID"]) {
                dict[@"BannerViewID"] = doc.documentID ?: @"";
            }
            if (!dict[@"docID"]) {
                dict[@"docID"] = doc.documentID ?: @"";
            }
            
            MainBannerModel *model = [[MainBannerModel alloc] initWithDictionary:dict];
            if (model) {
                [groups addObject:model];
            }
        }
        
        strongSelf.bannerGroups = [groups copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(strongSelf.bannerGroups, nil);
        });
    }];
}

- (void)stopListening {
    if (self.bannersListener) {
        [self.bannersListener remove];
        self.bannersListener = nil;
    }
}

- (void)addBannerGroup:(MainBannerModel *)bannerGroup completion:(void (^)(NSError * _Nullable))completion {
    if (!bannerGroup) {
        if (completion) completion([NSError errorWithDomain:@"PPBannersManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"bannerGroup is nil"}]);
        return;
    }
    
    // Use model -> dictionary (ensures consistent formatting)
    NSDictionary *data = [bannerGroup toDictionary];
    
    FIRCollectionReference *collection = [self.db collectionWithPath:@"MainBannersViewsCol"];
    
    if (bannerGroup.bannerViewID.length > 0) {
        // create or replace with merge to avoid erasing unrelated fields if doc exists
        FIRDocumentReference *docRef = [collection documentWithPath:bannerGroup.bannerViewID];
        [docRef setData:data merge:YES completion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"Error adding/updating banner group with ID %@: %@", bannerGroup.bannerViewID, error);
            } else {
                NSLog(@"Banner group added/updated with ID: %@", bannerGroup.bannerViewID);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }];
    } else {
        // No ID: add new document with auto-generated ID
        __block FIRDocumentReference *ref = [collection addDocumentWithData:data completion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"Error adding banner group: %@", error);
            } else {
                NSLog(@"Banner group added with generated ID: %@", ref.documentID);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(error);
            });
        }];
    }
}

- (void)updateBannerGroup:(MainBannerModel *)bannerGroup completion:(void (^)(NSError * _Nullable))completion {
    if (!bannerGroup || bannerGroup.bannerViewID.length == 0) {
        if (completion) completion([NSError errorWithDomain:@"PPBannersManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid bannerGroup or missing ID"}]);
        return;
    }
    
    NSDictionary *data = [bannerGroup toDictionary];
    
    FIRDocumentReference *docRef = [[self.db collectionWithPath:@"MainBannersViewsCol"] documentWithPath:bannerGroup.bannerViewID];
    
    // Use merge:YES so we don't remove fields that other parts of the app might be maintaining
    [docRef setData:data merge:YES completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Error updating banner group %@: %@", bannerGroup.bannerViewID, error);
        } else {
            NSLog(@"Banner group %@ successfully updated", bannerGroup.bannerViewID);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    }];
}


- (void)deleteBannerGroup:(MainBannerModel *)bannerGroup completion:(void (^)(NSError * _Nullable))completion {
    if (!bannerGroup || bannerGroup.bannerViewID.length == 0) {
        if (completion) completion([NSError errorWithDomain:@"PPBannersManager" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid bannerGroup or missing ID"}]);
        return;
    }
    
    FIRDocumentReference *docRef = [[self.db collectionWithPath:@"MainBannersViewsCol"] documentWithPath:bannerGroup.bannerViewID];
    [docRef deleteDocumentWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Error deleting banner group %@: %@", bannerGroup.bannerViewID, error);
        } else {
            NSLog(@"Banner group %@ deleted.", bannerGroup.bannerViewID);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(error);
        });
    }];
}



// Real-time listener that returns the registration and keeps self.bannerGroups in sync.
- (id<FIRListenerRegistration>)observeAllBanner:
(void (^)(NSArray<MainBannerModel *> * _Nullable items, NSError * _Nullable error))callback
{
    // ensure we don’t stack listeners
    [self stopListening];
    
    __weak typeof(self) weakSelf = self;
    self.bannersListener = [[self.db collectionWithPath:@"MainBannersViewsCol"]
                            addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            NSLog(@"[PPBannersManager] observeAllBanner error: %@", error);
            if (callback) callback(nil, error);
            return;
        }
        
        NSMutableArray<MainBannerModel *> *accum = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            NSDictionary *data = doc.data;
            if (!data) continue;
            
            // Merge documentID so model always has it
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:data];
            dict[@"docID"] = doc.documentID;
            if (!dict[@"BannerViewID"]) {
                dict[@"BannerViewID"] = doc.documentID ?: @"";
            }
            
            MainBannerModel *model = [[MainBannerModel alloc] initWithDictionary:dict];
            if (model) [accum addObject:model];
        }
        
        strongSelf.bannerGroups = [accum copy];
        if (callback) callback(strongSelf.bannerGroups, nil);
    }];
    
    return self.bannersListener;
}

// Alias to match your VC code ([[PPBannersManager shared] observeAllMainBanners:…])
- (id<FIRListenerRegistration>)observeAllMainBanners:
(void (^)(NSArray<MainBannerModel *> * _Nullable items, NSError * _Nullable error))callback
{
    return [self observeAllBanner:callback];
}


#pragma mark - Child banners (subcollection)

- (void)addChildBanner:(PPBannerViewModel *)child
               toGroup:(NSString *)bannerViewID
            completion:(void (^)(NSError * _Nullable))completion {
    if (!bannerViewID || bannerViewID.length == 0 || !child) {
        if (completion) completion([NSError errorWithDomain:@"PPBannersManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid bannerViewID or child"}]);
        return;
    }
    
    NSDictionary *data = [child toDictionary];
    FIRCollectionReference *subCol = [[[self.db collectionWithPath:@"MainBannersViewsCol"]
                                       documentWithPath:bannerViewID]
                                      collectionWithPath:@"ChildBanners"];
    
    if (child.bannerID.length > 0) {
        FIRDocumentReference *doc = [subCol documentWithPath:child.bannerID];
        [doc setData:data merge:YES completion:^(NSError * _Nullable error) {
            if (completion) completion(error);
        }];
    } else {
        __block FIRDocumentReference *ref = [subCol addDocumentWithData:data completion:^(NSError * _Nullable error) {
            if (!error) {
                child.bannerID = ref.documentID;
            }
            if (completion) completion(error);
        }];
    }
}

- (void)updateChildBanner:(PPBannerViewModel *)child
                  inGroup:(MainBannerModel *)group
               completion:(void (^)(NSError * _Nullable))completion {
    if (!group || !child.bannerID.length) {
        if (completion) completion([NSError errorWithDomain:@"PPBannersManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid IDs"}]);
        return;
    }
    
    NSMutableArray *updatedBanners = [group.childBanners mutableCopy] ?: [NSMutableArray array];
    NSUInteger idx = [updatedBanners indexOfObjectPassingTest:^BOOL(PPBannerViewModel *obj, NSUInteger idx, BOOL *stop) { return [obj.bannerID isEqualToString:child.bannerID];  }];
    
    if (idx != NSNotFound) {
        [updatedBanners replaceObjectAtIndex:idx withObject:child];
    }
    else
    {
        [updatedBanners addObject:child];
    }
    group.childBanners = updatedBanners;
    group.bannerViewVisible = true;
    [self updateBannerGroup:group completion:completion];
    
}



- (id<FIRListenerRegistration>)observeChildBannersInGroup:(NSString *)bannerViewID
                                               completion:(void (^)(NSArray<PPBannerViewModel *> * _Nullable,
                                                                    NSError * _Nullable))completion {
    if (!bannerViewID.length) return nil;
    
    FIRCollectionReference *subCol = [[[self.db collectionWithPath:@"MainBannersViewsCol"]
                                       documentWithPath:bannerViewID]
                                      collectionWithPath:@"ChildBanners"];
    
    id<FIRListenerRegistration> listener = [subCol addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        
        NSMutableArray *accum = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:doc.data];
            dict[@"BannerID"] = doc.documentID;
            PPBannerViewModel *child = [[PPBannerViewModel alloc] initWithDictionary:dict];
            if (child) [accum addObject:child];
        }
        if (completion) completion([accum copy], nil);
    }];
    
    return listener;
}


- (void)addBanner:(PPBannerViewModel *)banner
          toGroup:(MainBannerModel *)group
       completion:(void(^)(NSError * _Nullable error))completion {
    
    NSMutableArray *updatedBanners = [group.childBanners mutableCopy] ?: [NSMutableArray array];
    NSUInteger idx = [updatedBanners indexOfObjectPassingTest:^BOOL(PPBannerViewModel *obj, NSUInteger idx, BOOL *stop) { return [obj.bannerID isEqualToString:banner.bannerID];  }];
    
    if (idx != NSNotFound) {
        [updatedBanners replaceObjectAtIndex:idx withObject:banner];
    }
    else
    {
        [updatedBanners addObject:banner];
    }
    group.childBanners = updatedBanners;
    group.bannerViewVisible = true;
    [self updateBannerGroup:group completion:completion];
    
}

- (void)deleteChildBanner:(PPBannerViewModel *)child
                  inGroup:(MainBannerModel *)group
               completion:(void (^)(NSError * _Nullable))completion {
    
    if (!child || !group) {
        if (completion) completion([NSError errorWithDomain:@"PPBannersManager"
                                                       code:-1
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Invalid IDs"}]);
        return;
    }
    
    NSMutableArray *updatedBanners = [group.childBanners mutableCopy] ?: [NSMutableArray array];
    NSUInteger idx = [updatedBanners indexOfObjectPassingTest:^BOOL(PPBannerViewModel *obj, NSUInteger idx, BOOL *stop) { return [obj.bannerID isEqualToString:child.bannerID];  }];
    
    if (idx != NSNotFound) {
        [updatedBanners removeObjectAtIndex:idx];
    }
    
    group.childBanners = updatedBanners;
    group.bannerViewVisible = YES;
    [self updateBannerGroup:group completion:completion];
}

@end


/*
 
 /// update top-level flags
 NSMutableDictionary *update = [NSMutableDictionary dictionary];
 update[@"BannerViewVisible"] = @(bannerGroup.bannerViewVisible);
 update[@"BannerViewHolder"] = @(bannerGroup.bannerViewHolder);
 update[@"BannerViewPosition"] = @(bannerGroup.bannerViewPosition);
 update[@"BannerViewTransaction"] = @(bannerGroup.bannerViewTransaction);
 
 [[[self.db collectionWithPath:@"MainBannersViewsCol"] documentWithPath:bannerGroup.bannerViewID] updateData:update completion:^(NSError * _Nullable error) {
 // completion...
 }];
 
 
 */
