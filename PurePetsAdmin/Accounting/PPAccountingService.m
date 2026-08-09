#import "PPAccountingService.h"
@import FirebaseFirestore;
@import FirebaseAuth;

@implementation PPAccountingTransaction
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _txnID = docID ?: @"";
        _amount = PPSafeDouble(dict[@"total"]);
        if (_amount == 0) _amount = PPSafeDouble(dict[@"amount"]);
        _type = PPSafeString(dict[@"type"]);
        if (_type.length == 0) _type = PPSafeString(dict[@"status"]);
        _desc = PPSafeString(dict[@"description"]);
        if (_desc.length == 0) _desc = PPSafeString(dict[@"customerName"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
    }
    return self;
}
@end

@implementation PPAccountingExpense
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID {
    self = [super init];
    if (self) {
        _expenseID = docID ?: @"";
        _amount = PPSafeDouble(dict[@"amount"]);
        _category = PPSafeString(dict[@"category"]);
        _desc = PPSafeString(dict[@"description"]);
        _createdBy = PPSafeString(dict[@"createdBy"]);
        id ca = dict[@"createdAt"];
        if ([ca isKindOfClass:FIRTimestamp.class]) _createdAt = [(FIRTimestamp *)ca dateValue];
    }
    return self;
}
@end

@interface PPAccountingService ()
@property (nonatomic, strong) NSMutableArray<PPAccountingTransaction *> *internalTransactions;
@property (nonatomic, strong) NSMutableArray<PPAccountingExpense *> *internalExpenses;
@property (nonatomic, assign) double internalOrderRevenue;
@property (nonatomic, assign) NSInteger internalOrderCount;
@end

@implementation PPAccountingService

+ (instancetype)shared {
    static PPAccountingService *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [self new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _internalTransactions = [NSMutableArray array];
        _internalExpenses = [NSMutableArray array];
    }
    return self;
}

- (NSArray<PPAccountingTransaction *> *)transactions { return self.internalTransactions; }
- (NSArray<PPAccountingExpense *> *)expenses { return self.internalExpenses; }
- (double)orderRevenue { return self.internalOrderRevenue; }
- (NSInteger)orderCount { return self.internalOrderCount; }

- (FIRTimestamp *)monthStartTimestamp {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *comp = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:[NSDate date]];
    comp.day = 1; comp.hour = 0; comp.minute = 0; comp.second = 0;
    return [FIRTimestamp timestampWithDate:[cal dateFromComponents:comp]];
}

- (id<FIRListenerRegistration>)subscribeTransactionsWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"transactions"] queryOrderedByField:@"createdAt" descending:YES];
    if ([filter isEqualToString:@"month"]) {
        query = [[[db collectionWithPath:@"transactions"] queryWhereField:@"createdAt" isGreaterThanOrEqualTo:[self monthStartTimestamp]] queryOrderedByField:@"createdAt" descending:YES];
    }
    return [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) return;
        [self.internalTransactions removeAllObjects];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [self.internalTransactions addObject:[[PPAccountingTransaction alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (callback) callback();
    }];
}

- (id<FIRListenerRegistration>)subscribeExpensesWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[db collectionWithPath:@"expenses"] queryOrderedByField:@"createdAt" descending:YES];
    if ([filter isEqualToString:@"month"]) {
        query = [[[db collectionWithPath:@"expenses"] queryWhereField:@"createdAt" isGreaterThanOrEqualTo:[self monthStartTimestamp]] queryOrderedByField:@"createdAt" descending:YES];
    }
    return [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) return;
        [self.internalExpenses removeAllObjects];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            [self.internalExpenses addObject:[[PPAccountingExpense alloc] initWithDictionary:doc.data documentID:doc.documentID]];
        }
        if (callback) callback();
    }];
}

- (id<FIRListenerRegistration>)subscribeOrderRevenueWithFilter:(NSString *)filter callback:(void(^)(void))callback {
    FIRFirestore *db = [FIRFirestore firestore];
    FIRQuery *query = [[[db collectionWithPath:@"Orders"] queryWhereField:@"paymentStatus" isEqualTo:@"paid"] queryOrderedByField:@"createdAt" descending:YES];
    if ([filter isEqualToString:@"month"]) {
        query = [[[[db collectionWithPath:@"Orders"] queryWhereField:@"paymentStatus" isEqualTo:@"paid"] queryWhereField:@"createdAt" isGreaterThanOrEqualTo:[self monthStartTimestamp]] queryOrderedByField:@"createdAt" descending:YES];
    }
    return [query addSnapshotListener:^(FIRQuerySnapshot *snapshot, NSError *error) {
        if (error) return;
        double revenue = 0;
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            revenue += PPSafeDouble(doc.data[@"totalAmount"]);
        }
        self.internalOrderRevenue = revenue;
        self.internalOrderCount = (NSInteger)snapshot.documents.count;
        if (callback) callback();
    }];
}

- (void)addExpense:(double)amount category:(NSString *)category description:(NSString *)desc completion:(void(^)(NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"unknown";
    [[db collectionWithPath:@"expenses"] addDocumentWithData:@{
        @"amount": @(amount),
        @"category": category ?: @"other",
        @"description": desc ?: @"",
        @"createdBy": uid,
        @"date": [FIRTimestamp timestampWithDate:[NSDate date]],
        @"status": @"active",
        @"createdAt": [FIRTimestamp timestampWithDate:[NSDate date]]
    } completion:^(NSError *error) {
        if (completion) completion(error);
    }];
}

- (void)deleteExpense:(NSString *)expenseID completion:(void(^)(NSError *))completion {
    FIRFirestore *db = [FIRFirestore firestore];
    [[[db collectionWithPath:@"expenses"] documentWithPath:expenseID] deleteDocumentWithCompletion:^(NSError *error) {
        if (completion) completion(error);
    }];
}

@end