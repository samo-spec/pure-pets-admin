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

@interface PPAccountingService : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<PPAccountingTransaction *> *transactions;
@property (nonatomic, readonly) NSArray<PPAccountingExpense *> *expenses;
@property (nonatomic, readonly) double orderRevenue;
@property (nonatomic, readonly) NSInteger orderCount;

- (id<FIRListenerRegistration>)subscribeTransactionsWithFilter:(NSString *)filter callback:(void(^)(void))callback;
- (id<FIRListenerRegistration>)subscribeExpensesWithFilter:(NSString *)filter callback:(void(^)(void))callback;
- (id<FIRListenerRegistration>)subscribeOrderRevenueWithFilter:(NSString *)filter callback:(void(^)(void))callback;
- (void)addExpense:(double)amount category:(NSString *)category description:(NSString *)desc completion:(void(^)(NSError *error))completion;
- (void)deleteExpense:(NSString *)expenseID completion:(void(^)(NSError *error))completion;
@end

NS_ASSUME_NONNULL_END