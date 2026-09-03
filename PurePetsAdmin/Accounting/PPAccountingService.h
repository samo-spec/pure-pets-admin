#import <Foundation/Foundation.h>

@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@interface PPAccountingTransaction : NSObject
@property (nonatomic, copy) NSString *txnID;
@property (nonatomic, assign) double amount;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPAccountingExpense : NSObject
@property (nonatomic, copy) NSString *expenseID;
@property (nonatomic, assign) double amount;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *desc;
@property (nonatomic, copy) NSString *createdBy;
@property (nonatomic, copy, nullable) NSDate *createdAt;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPAccountingWorkspaceDashboard : NSObject
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, assign) double income;
@property (nonatomic, assign) int64_t incomeMinor;
@property (nonatomic, assign) double expenses;
@property (nonatomic, assign) int64_t expensesMinor;
@property (nonatomic, assign) double netProfit;
@property (nonatomic, assign) int64_t netProfitMinor;
@property (nonatomic, assign) double cashIn;
@property (nonatomic, assign) int64_t cashInMinor;
@property (nonatomic, assign) double cashOut;
@property (nonatomic, assign) int64_t cashOutMinor;
@property (nonatomic, assign) double currentCashBalance;
@property (nonatomic, assign) int64_t currentCashBalanceMinor;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *categoryIncomeMinor;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *categoryExpenseMinor;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPAccountingDocument : NSObject
@property (nonatomic, copy) NSString *documentID;
@property (nonatomic, copy) NSString *documentNumber;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *accountingDateKey;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, assign) double total;
@property (nonatomic, assign) int64_t totalMinor;
@property (nonatomic, copy, nullable) NSString *categoryId;
@property (nonatomic, copy, nullable) NSString *categoryName;
@property (nonatomic, copy, nullable) NSString *descriptionText;
@property (nonatomic, copy, nullable) NSString *sourceType;
@property (nonatomic, copy, nullable) NSString *sourceDocumentId;
@property (nonatomic, assign) BOOL isLegacy;
@property (nonatomic, assign) BOOL canonicalLinked;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPAccountingWorkspaceSnapshot : NSObject
@property (nonatomic, copy) NSString *period;
@property (nonatomic, copy) NSString *fromDateKey;
@property (nonatomic, copy) NSString *toDateKey;
@property (nonatomic, strong, nullable) PPAccountingWorkspaceDashboard *primaryDashboard;
@property (nonatomic, strong) NSArray<PPAccountingDocument *> *documents;
@property (nonatomic, assign) NSInteger incomeCount;
@property (nonatomic, assign) NSInteger expenseCount;
@property (nonatomic, strong, nullable) NSError *error;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPAccountingService : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<PPAccountingTransaction *> *transactions;
@property (nonatomic, readonly) NSArray<PPAccountingExpense *> *expenses;
@property (nonatomic, readonly) double orderRevenue;
@property (nonatomic, readonly) NSInteger orderCount;
@property (nonatomic, readonly) BOOL orderRevenueEvidenceAvailable;
@property (nonatomic, strong, nullable, readonly) NSError *orderRevenueError;
@property (nonatomic, strong, nullable, readonly) PPAccountingWorkspaceSnapshot *currentWorkspace;
@property (nonatomic, readonly) double liveTotalExpenses;
@property (nonatomic, readonly) NSInteger liveExpenseCount;
@property (nonatomic, readonly) double liveTransactionRevenue;
@property (nonatomic, readonly) NSInteger liveTransactionCount;

- (nullable PPAccountingWorkspaceSnapshot *)workspaceForFilter:(NSString *)filter;

- (BOOL)currentStaffCanReadOrderRevenue;

- (id<FIRListenerRegistration>)subscribeTransactionsWithFilter:(NSString *)filter callback:(void(^)(void))callback;
- (id<FIRListenerRegistration>)subscribeExpensesWithFilter:(NSString *)filter callback:(void(^)(void))callback;
- (id<FIRListenerRegistration>)subscribeOrderRevenueWithFilter:(NSString *)filter callback:(void(^)(void))callback;

- (void)fetchAccountingWorkspaceWithFilter:(NSString *)filter
                                completion:(nullable void(^)(PPAccountingWorkspaceSnapshot * _Nullable snapshot, NSError * _Nullable error))completion;

- (id<FIRListenerRegistration>)subscribeAccountingWorkspaceWithFilter:(NSString *)filter
                                                              callback:(void(^)(PPAccountingWorkspaceSnapshot * _Nullable snapshot))callback;

- (void)addExpense:(double)amount category:(NSString *)category description:(NSString *)desc completion:(nullable void(^)(NSError * _Nullable error))completion;
- (void)deleteExpense:(NSString *)expenseID completion:(nullable void(^)(NSError * _Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
