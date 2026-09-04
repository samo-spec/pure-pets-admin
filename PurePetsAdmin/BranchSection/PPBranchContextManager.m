//
//  PPBranchContextManager.m
//  PurePetsAdmin
//
//  Production-Grade Multi-Branch Context Manager.
//

#import "PPBranchContextManager.h"
#import "PPFirebaseCompat.h"
@import Firebase;
@import FirebaseFirestore;
@import FirebaseAuth;
@import FirebaseFunctions;

NSNotificationName const PPActiveBranchDidChangeNotification = @"PPActiveBranchDidChangeNotification";
NSNotificationName const PPAvailableBranchesDidChangeNotification = @"PPAvailableBranchesDidChangeNotification";

static NSString * const kPPActiveBranchStoragePrefix = @"PPAdminActiveBranchID_";

@interface PPBranchContextManager ()

@property (nonatomic, strong, nullable, readwrite) PPBranchModel *activeBranch;
@property (nonatomic, copy, readwrite) NSArray<PPBranchModel *> *availableBranches;
@property (nonatomic, copy, readwrite) NSArray<PPBranchModel *> *allBranches;
@property (nonatomic, strong, nullable, readwrite) PPStaffDoc *currentStaff;
@property (nonatomic, assign, readwrite) BOOL isGlobalAccess;
@property (nonatomic, assign, readwrite) BOOL needsBranchSelection;

@end

@implementation PPBranchContextManager

+ (instancetype)sharedManager {
    static PPBranchContextManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PPBranchContextManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _availableBranches = @[];
        _allBranches = @[];
        _activeBranch = nil;
        _isGlobalAccess = NO;
        _needsBranchSelection = NO;
    }
    return self;
}

#pragma mark - Getters

- (NSString *)currentBranchID {
    return self.activeBranch.branchID;
}

- (NSString *)currentBranchDisplayName {
    if (self.activeBranch) {
        return [self.activeBranch localizedName];
    }
    if (self.isGlobalAccess) {
        return [Language isRTL] ? @"جميع الفروع (عام)" : @"All Branches (Global)";
    }
    return [Language isRTL] ? @"يرجى اختيار الفرع" : @"Select Branch";
}

#pragma mark - Persistence Key

- (NSString *)persistenceKeyForCurrentStaff {
    NSString *uid = self.currentStaff.uid;
    if (uid.length == 0) {
        uid = [FIRAuth auth].currentUser.uid ?: @"guest";
    }
    return [kPPActiveBranchStoragePrefix stringByAppendingString:uid];
}

#pragma mark - Configuration & Fetching

- (void)configureWithStaff:(nullable PPStaffDoc *)staff completion:(nullable void(^)(void))completion {
    self.currentStaff = staff;
    self.isGlobalAccess = staff != nil && (staff.isAdmin || staff.hasGlobalScope);

    [self reloadAvailableBranchesWithCompletion:^(NSArray<PPBranchModel *> *branches) {
        if (completion) {
            completion();
        }
    }];
}

- (void)reloadAvailableBranchesWithCompletion:(nullable void(^)(NSArray<PPBranchModel *> *branches))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    
    [[db collectionWithPath:@"branches"] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !snapshot) {
                if (completion) {
                    completion(self.availableBranches ?: @[]);
                }
                return;
            }

            NSMutableArray<PPBranchModel *> *all = [NSMutableArray array];
            NSMutableArray<PPBranchModel *> *loaded = [NSMutableArray array];
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                PPBranchModel *branch = [PPBranchModel fromDictionary:doc.data withID:doc.documentID];
                [all addObject:branch];
                if (branch.isActive) {
                    if (self.isGlobalAccess || [self.currentStaff hasAccessToBranch:branch.branchID]) {
                        [loaded addObject:branch];
                    }
                }
            }

            self.allBranches = [all copy];
            self.availableBranches = [loaded copy];
            [[NSNotificationCenter defaultCenter] postNotificationName:PPAvailableBranchesDidChangeNotification object:self];

            [self resolveActiveBranch];

            if (completion) {
                completion(self.availableBranches);
            }
        });
    }];
}

#pragma mark - Resolution & Lookup

- (nullable PPBranchModel *)branchWithID:(nullable NSString *)branchID {
    if (branchID.length == 0) return nil;

    // Resolution is intentionally constrained to the canonical approved list.
    // Global/owner staff already receive all active branches in this list.
    for (PPBranchModel *b in self.availableBranches) {
        if ([b.branchID isEqualToString:branchID] ||
            [b.code caseInsensitiveCompare:branchID] == NSOrderedSame) {
            return b;
        }
    }
    return nil;
}

- (NSString *)localizedBranchNameForID:(nullable NSString *)branchID fallback:(nullable NSString *)fallback {
    if (branchID.length == 0 || [branchID isEqualToString:@"main_store"] || [branchID caseInsensitiveCompare:@"main store"] == NSOrderedSame) {
        if (fallback.length > 0 &&
            ![fallback isEqualToString:@"المتجر الرئيسي"] &&
            ![fallback caseInsensitiveCompare:@"main store"] == NSOrderedSame) {
            return fallback;
        }
        return [Language isRTL] ? @"المتجر الرئيسي" : @"Main Store";
    }

    PPBranchModel *b = [self branchWithID:branchID];
    if (b) {
        return [b localizedName];
    }
    if (fallback.length > 0) {
        return fallback;
    }
    return branchID;
}

- (void)resolveActiveBranch {
    if (self.availableBranches.count == 0) {
        self.activeBranch = nil;
        self.needsBranchSelection = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:PPActiveBranchDidChangeNotification object:self];
        return;
    }

    NSString *savedBranchID = [[NSUserDefaults standardUserDefaults] stringForKey:[self persistenceKeyForCurrentStaff]];
    PPBranchModel *candidate = nil;

    // 1. Saved branch in UserDefaults
    if (savedBranchID.length > 0) {
        for (PPBranchModel *b in self.availableBranches) {
            if ([b.branchID isEqualToString:savedBranchID]) {
                candidate = b;
                break;
            }
        }
    }

    // 2. Default branch assigned to staff
    if (!candidate && self.currentStaff.defaultBranchID.length > 0) {
        for (PPBranchModel *b in self.availableBranches) {
            if ([b.branchID isEqualToString:self.currentStaff.defaultBranchID]) {
                candidate = b;
                break;
            }
        }
    }

    // 3. System default branch (isDefault == YES)
    if (!candidate) {
        for (PPBranchModel *b in self.availableBranches) {
            if (b.isDefault) {
                candidate = b;
                break;
            }
        }
    }

    // 4. If exactly one branch available, automatically pick it
    if (!candidate && self.availableBranches.count == 1) {
        candidate = self.availableBranches.firstObject;
    }

    if (candidate) {
        self.activeBranch = candidate;
        self.needsBranchSelection = NO;
        [[NSUserDefaults standardUserDefaults] setObject:candidate.branchID forKey:[self persistenceKeyForCurrentStaff]];
    } else {
        // Multiple branches available with no pre-selection -> require user to choose
        self.activeBranch = nil;
        self.needsBranchSelection = (self.availableBranches.count > 1);
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PPActiveBranchDidChangeNotification object:self];
}

#pragma mark - Selection

- (BOOL)selectBranch:(PPBranchModel *)branch {
    if (!branch) {
        return NO;
    }
    return [self selectBranchWithID:branch.branchID];
}

- (BOOL)selectBranchWithID:(NSString *)branchID {
    if (branchID.length == 0) {
        return NO;
    }

    PPBranchModel *target = nil;
    for (PPBranchModel *b in self.availableBranches) {
        if ([b.branchID isEqualToString:branchID]) {
            target = b;
            break;
        }
    }

    if (!target) {
        // Non-global caller cannot select unauthorized branch
        return NO;
    }

    self.activeBranch = target;
    self.needsBranchSelection = NO;
    [[NSUserDefaults standardUserDefaults] setObject:target.branchID forKey:[self persistenceKeyForCurrentStaff]];

    // Synchronize to backend staff profile so all Cloud Functions & operations use this default
    [self syncWorkingBranchToBackend:target.branchID completion:nil];

    [[NSNotificationCenter defaultCenter] postNotificationName:PPActiveBranchDidChangeNotification object:self];
    return YES;
}

- (void)syncWorkingBranchToBackend:(NSString *)branchID completion:(nullable void(^)(BOOL success, NSError * _Nullable error))completion {
    if (branchID.length == 0) {
        if (completion) completion(NO, nil);
        return;
    }

    FIRHTTPSCallable *callable = [[FIRFunctions functions] HTTPSCallableWithName:@"setStaffWorkingBranch"];
    [callable callWithObject:@{@"branchId": branchID} completion:^(FIRHTTPSCallableResult * _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"⚠️ [PPBranchContextManager] Failed syncing working branch to backend: %@", error.localizedDescription);
            if (completion) completion(NO, error);
            return;
        }
        NSLog(@"✅ [PPBranchContextManager] Successfully synced working branch '%@' to backend profile.", branchID);
        if (completion) completion(YES, nil);
    }];
}

#pragma mark - Reset

- (void)clearContext {
    self.activeBranch = nil;
    self.availableBranches = @[];
    self.currentStaff = nil;
    self.isGlobalAccess = NO;
    self.needsBranchSelection = NO;

    [[NSNotificationCenter defaultCenter] postNotificationName:PPActiveBranchDidChangeNotification object:self];
}

@end
