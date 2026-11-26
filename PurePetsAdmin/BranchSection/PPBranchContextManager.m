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
static NSString * const kPPKnownSystemDefaultBranchStoragePrefix = @"PPAdminLastDefaultBranchID_";

@interface PPBranchContextManager ()

@property (nonatomic, strong, nullable, readwrite) PPBranchModel *activeBranch;
@property (nonatomic, copy, readwrite) NSArray<PPBranchModel *> *availableBranches;
@property (nonatomic, copy, readwrite) NSArray<PPBranchModel *> *allBranches;
@property (nonatomic, strong, nullable, readwrite) PPStaffDoc *currentStaff;
@property (nonatomic, assign, readwrite) BOOL isGlobalAccess;
@property (nonatomic, assign, readwrite) BOOL needsBranchSelection;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> branchesListener;
@property (nonatomic, assign) NSUInteger resolutionGeneration;
@property (nonatomic, assign) BOOL hasPostedInitialActiveBranch;

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
        _resolutionGeneration = 0;
        _hasPostedInitialActiveBranch = NO;
    }
    return self;
}

- (void)dealloc {
    [_branchesListener remove];
    _branchesListener = nil;
}

#pragma mark - Getters

- (nullable PPBranchModel *)systemDefaultBranch {
    for (PPBranchModel *b in self.availableBranches) {
        if (b.isDefault) {
            return b;
        }
    }
    return nil;
}

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

- (NSString *)defaultTrackingKeyForCurrentStaff {
    NSString *uid = self.currentStaff.uid;
    if (uid.length == 0) {
        uid = [FIRAuth auth].currentUser.uid ?: @"guest";
    }
    return [kPPKnownSystemDefaultBranchStoragePrefix stringByAppendingString:uid];
}

#pragma mark - Configuration & Fetching

- (void)configureWithStaff:(nullable PPStaffDoc *)staff completion:(nullable void(^)(void))completion {
    self.currentStaff = staff;
    self.isGlobalAccess = staff != nil && (staff.isAdmin || staff.hasGlobalScope);
    self.resolutionGeneration += 1;
    [self startBranchesListenerIfNeeded];

    [self reloadAvailableBranchesWithCompletion:^(NSArray<PPBranchModel *> *branches) {
        if (completion) {
            completion();
        }
    }];
}

- (void)startBranchesListenerIfNeeded {
    [self.branchesListener remove];
    self.branchesListener = nil;

    NSUInteger generation = self.resolutionGeneration;
    __weak typeof(self) weakSelf = self;
    FIRFirestore *db = [FIRFirestore firestore];
    self.branchesListener = [[db collectionWithPath:@"branches"] addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.resolutionGeneration != generation) return;
            if (error || !snapshot) return;
            [strongSelf processBranchesSnapshot:snapshot];
        });
    }];
}

- (void)processBranchesSnapshot:(FIRQuerySnapshot *)snapshot {
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

    [loaded sortUsingComparator:^NSComparisonResult(PPBranchModel *a, PPBranchModel *b) {
        if (a.isDefault != b.isDefault) {
            return a.isDefault ? NSOrderedAscending : NSOrderedDescending;
        }
        return [[a localizedName] localizedCaseInsensitiveCompare:[b localizedName]];
    }];

    self.allBranches = [all copy];
    self.availableBranches = [loaded copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:PPAvailableBranchesDidChangeNotification object:self];

    [self resolveActiveBranch];
}

- (void)reloadAvailableBranchesWithCompletion:(nullable void(^)(NSArray<PPBranchModel *> *branches))completion {
    NSUInteger generation = self.resolutionGeneration;
    __weak typeof(self) weakSelf = self;
    FIRFirestore *db = [FIRFirestore firestore];

    [[db collectionWithPath:@"branches"] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                if (completion) completion(@[]);
                return;
            }
            if (error || !snapshot || strongSelf.resolutionGeneration != generation) {
                if (completion) {
                    completion(strongSelf.availableBranches ?: @[]);
                }
                return;
            }

            [strongSelf processBranchesSnapshot:snapshot];

            if (completion) {
                completion(strongSelf.availableBranches);
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
    for (PPBranchModel *b in self.allBranches) {
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

- (nullable PPBranchModel *)findAvailableBranchWithID:(nullable NSString *)branchID {
    if (branchID.length == 0) return nil;
    for (PPBranchModel *b in self.availableBranches) {
        if ([b.branchID isEqualToString:branchID]) {
            return b;
        }
    }
    return nil;
}

- (void)resolveActiveBranch {
    NSString *previousBranchID = self.activeBranch.branchID;
    BOOL previousNeedsSelection = self.needsBranchSelection;
    BOOL previousIsDefault = self.activeBranch.isDefault;
    NSString *previousName = self.activeBranch ? [self.activeBranch localizedName] : @"";
    NSString *previousCode = self.activeBranch.code ?: @"";

    if (self.availableBranches.count == 0) {
        self.activeBranch = nil;
        self.needsBranchSelection = NO;
        if (!self.hasPostedInitialActiveBranch || previousBranchID.length > 0 || previousNeedsSelection) {
            self.hasPostedInitialActiveBranch = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:PPActiveBranchDidChangeNotification object:self];
        }
        return;
    }

    NSString *savedBranchID = [[NSUserDefaults standardUserDefaults] stringForKey:[self persistenceKeyForCurrentStaff]];
    NSString *lastKnownDefaultID = [[NSUserDefaults standardUserDefaults] stringForKey:[self defaultTrackingKeyForCurrentStaff]];
    PPBranchModel *systemDefault = [self systemDefaultBranch];
    PPBranchModel *candidate = nil;

    // 1. If the system Main Branch (`isDefault`) changed (e.g. from Branches screen or Console),
    // or on first upgrade onto `isDefault` tracking for global staff, promote `systemDefault`.
    BOOL systemDefaultChanged = (systemDefault != nil) &&
        (lastKnownDefaultID.length > 0 && ![lastKnownDefaultID isEqualToString:systemDefault.branchID]);
    BOOL initialGlobalDefaultSync = (systemDefault != nil) &&
        (lastKnownDefaultID.length == 0) &&
        self.isGlobalAccess &&
        ![savedBranchID isEqualToString:systemDefault.branchID];

    if (systemDefaultChanged || initialGlobalDefaultSync) {
        candidate = systemDefault;
        if (candidate && ![self.currentStaff.defaultBranchID isEqualToString:candidate.branchID]) {
            [self syncWorkingBranchToBackend:candidate.branchID completion:nil];
        }
    }

    // 2. Saved branch in UserDefaults (preserves explicit switcher selection until Main Branch changes)
    if (!candidate) {
        candidate = [self findAvailableBranchWithID:savedBranchID];
    }

    // 3. Fallback priority: for global admins prefer system Main Branch before stale staff default;
    // for restricted scoped staff prefer their assigned defaultBranchID then system Main Branch.
    if (!candidate) {
        if (self.isGlobalAccess) {
            candidate = systemDefault ?: [self findAvailableBranchWithID:self.currentStaff.defaultBranchID];
        } else {
            candidate = [self findAvailableBranchWithID:self.currentStaff.defaultBranchID] ?: systemDefault;
        }
    }

    // 4. If exactly one branch available, automatically pick it
    if (!candidate && self.availableBranches.count == 1) {
        candidate = self.availableBranches.firstObject;
    }

    if (systemDefault) {
        [[NSUserDefaults standardUserDefaults] setObject:systemDefault.branchID forKey:[self defaultTrackingKeyForCurrentStaff]];
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

    BOOL changed = !self.hasPostedInitialActiveBranch ||
        ![(previousBranchID ?: @"") isEqualToString:(self.activeBranch.branchID ?: @"")] ||
        previousNeedsSelection != self.needsBranchSelection ||
        previousIsDefault != self.activeBranch.isDefault ||
        ![(previousName ?: @"") isEqualToString:(self.activeBranch ? [self.activeBranch localizedName] : @"")] ||
        ![(previousCode ?: @"") isEqualToString:(self.activeBranch.code ?: @"")];

    if (changed) {
        self.hasPostedInitialActiveBranch = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:PPActiveBranchDidChangeNotification object:self];
    }
}

#pragma mark - Selection

- (void)applySystemDefaultBranchChange:(NSString *)branchID completion:(nullable void(^)(BOOL applied))completion {
    NSString *trimmed = [branchID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (completion) completion(NO);
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:[self defaultTrackingKeyForCurrentStaff]];

    PPBranchModel *target = [self findAvailableBranchWithID:trimmed];
    if (target) {
        [[NSUserDefaults standardUserDefaults] setObject:trimmed forKey:[self persistenceKeyForCurrentStaff]];
        BOOL applied = [self selectBranchWithID:trimmed];
        [self reloadAvailableBranchesWithCompletion:nil];
        if (completion) completion(applied);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self reloadAvailableBranchesWithCompletion:^(NSArray<PPBranchModel *> * _Nonnull branches) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(NO);
            return;
        }
        PPBranchModel *reloadedTarget = [strongSelf findAvailableBranchWithID:trimmed];
        if (reloadedTarget) {
            BOOL applied = [strongSelf selectBranchWithID:trimmed];
            if (completion) completion(applied);
        } else {
            if (completion) completion(NO);
        }
    }];
}

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
    self.resolutionGeneration += 1;
    [self.branchesListener remove];
    self.branchesListener = nil;
    self.hasPostedInitialActiveBranch = NO;
    self.activeBranch = nil;
    self.availableBranches = @[];
    self.allBranches = @[];
    self.currentStaff = nil;
    self.isGlobalAccess = NO;
    self.needsBranchSelection = NO;

    [[NSNotificationCenter defaultCenter] postNotificationName:PPActiveBranchDidChangeNotification object:self];
}

@end
