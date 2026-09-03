//
//  PPBranchContextManager.h
//  PurePetsAdmin
//
//  Production-Grade Multi-Branch Context Manager.
//  Maintains the active working branch for the logged-in staff member,
//  enforces branch switching authorization, and notifies listeners across
//  the Admin app when the branch context changes.
//

#import <Foundation/Foundation.h>
#import "PPBranchModel.h"
#import "PPStaffAuth.h"

NS_ASSUME_NONNULL_BEGIN

/// Notification posted when the active branch context changes.
extern NSNotificationName const PPActiveBranchDidChangeNotification;

/// Notification posted when the list of available branches is reloaded.
extern NSNotificationName const PPAvailableBranchesDidChangeNotification;

@interface PPBranchContextManager : NSObject

+ (instancetype)sharedManager NS_SWIFT_NAME(shared());

// ── State ─────────────────────────────────────────────────────────────────

/// The active working branch for all operations in the Admin app.
@property (nonatomic, strong, nullable, readonly) PPBranchModel *activeBranch;

/// The list of branches the current staff user is authorized to access.
@property (nonatomic, copy, readonly) NSArray<PPBranchModel *> *availableBranches;

/// The active staff profile currently backing this branch context.
@property (nonatomic, strong, nullable, readonly) PPStaffDoc *currentStaff;

/// Whether the current staff user has global reach (SuperAdmin/Owner/Global Scope).
@property (nonatomic, assign, readonly) BOOL isGlobalAccess;

/// True if the user has multiple branches available and has not yet selected an active branch.
@property (nonatomic, assign, readonly) BOOL needsBranchSelection;

/// Shorthand for activeBranch.branchID.
@property (nonatomic, copy, nullable, readonly) NSString *currentBranchID;

/// Localized display name for the active branch, or a fallback if none is selected.
@property (nonatomic, copy, readonly) NSString *currentBranchDisplayName;

// ── Lifecycle & Operations ────────────────────────────────────────────────

/// Initializes or updates the context with the given staff member.
/// Automatically handles:
/// 1. Fetching permitted branches from Firestore `branches`.
/// 2. Restoring the user's previously chosen branch from secure UserDefaults.
/// 3. Auto-selecting single assigned branch or defaultBranchId.
/// 4. Flagging needsBranchSelection if multiple branches exist with no active choice.
- (void)configureWithStaff:(nullable PPStaffDoc *)staff completion:(nullable void(^)(void))completion;

/// Selects an active branch. Fails closed if staff lacks access to this branch.
- (BOOL)selectBranch:(PPBranchModel *)branch;

/// Selects an active branch by ID from the available branches list.
- (BOOL)selectBranchWithID:(NSString *)branchID;

/// Synchronizes the selected working branch to the backend staff profile so that all
/// Cloud Functions, transactions, reports, and ledgers automatically use this branch as default.
- (void)syncWorkingBranchToBackend:(NSString *)branchID completion:(nullable void(^)(BOOL success, NSError * _Nullable error))completion;

/// Clears branch context on staff logout or session termination.
- (void)clearContext;

/// Reloads the branches list from Firestore and updates availableBranches.
- (void)reloadAvailableBranchesWithCompletion:(nullable void(^)(NSArray<PPBranchModel *> *branches))completion;

@end

NS_ASSUME_NONNULL_END
