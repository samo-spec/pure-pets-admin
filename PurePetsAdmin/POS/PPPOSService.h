#import <Foundation/Foundation.h>

@protocol FIRListenerRegistration;

NS_ASSUME_NONNULL_BEGIN

@interface PPPOSCartItem : NSObject
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double price;
@property (nonatomic, assign) double lineTotal;
@property (nonatomic, assign) NSInteger quantity;
@property (nonatomic, copy, nullable) NSString *inventoryMode;
@property (nonatomic, copy) NSArray<NSString *> *unitIDs;
@property (nonatomic, copy) NSArray<NSString *> *unitRingTags;
@property (nonatomic, copy) NSArray<NSDictionary *> *unitPrices;
@property (nonatomic, copy, nullable) NSString *subSubKindName;
@property (nonatomic, copy, nullable) NSString *subSubKindItemName;
@property (nonatomic, copy) NSArray<NSString *> *unitSubSubKinds;
@property (nonatomic, copy) NSArray<NSString *> *unitSubSubKindItems;
@property (nonatomic, copy, nullable) NSString *salesChannel;
@property (nonatomic, copy, nullable) NSString *quantityGroupId;
@property (nonatomic, copy, nullable) NSString *quantityGroupName;
@property (nonatomic, assign) NSInteger unitsPerGroup;
@property (nonatomic, assign) NSInteger groupQuantity;
@property (nonatomic, assign) NSInteger baseUnitQuantity;
@property (nonatomic, assign) NSInteger unitGroupPriceMinor;
@property (nonatomic, assign) NSInteger refundedQuantity;
@property (nonatomic, copy) NSArray<NSString *> *refundedUnitIds;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPPOSInventoryUnit : NSObject
@property (nonatomic, copy) NSString *unitID;
@property (nonatomic, copy) NSString *ringTag;
@property (nonatomic, assign) double sellingPrice;
@property (nonatomic, copy) NSString *currentBranchId;
@property (nonatomic, strong, nullable) NSNumber *subSubKindID;
@property (nonatomic, copy, nullable) NSString *subSubKindNameAr;
@property (nonatomic, copy, nullable) NSString *subSubKindNameEn;
@property (nonatomic, strong, nullable) NSNumber *subSubKindItemID;
@property (nonatomic, copy, nullable) NSString *subSubKindItemNameAr;
@property (nonatomic, copy, nullable) NSString *subSubKindItemNameEn;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
@end

@interface PPPOSSubmitResult : NSObject
@property (nonatomic, copy) NSString *transactionID;
@property (nonatomic, assign) double total;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, assign, getter=isIdempotent) BOOL idempotent;
@end

@interface PPPOSReceipt : NSObject
@property (nonatomic, copy) NSString *receiptID;
@property (nonatomic, strong) NSArray<PPPOSCartItem *> *items;
@property (nonatomic, assign) double subtotal;
@property (nonatomic, assign) double discount;
@property (nonatomic, assign) double total;
@property (nonatomic, assign) double cashReceived;
@property (nonatomic, assign) double changeDue;
@property (nonatomic, copy) NSString *paymentMethod;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *customerName;
@property (nonatomic, copy) NSString *customerPhone;
@property (nonatomic, copy) NSString *note;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *operatorID;
@property (nonatomic, copy, nullable) NSString *salesChannel;
@property (nonatomic, assign) NSInteger schemaVersion;
@property (nonatomic, copy, nullable) NSDate *createdAt;
@property (nonatomic, assign) double refundedAmount;
@property (nonatomic, copy, nullable) NSString *refundReason;
@property (nonatomic, copy, nullable) NSDate *refundedAt;
@property (nonatomic, copy, nullable) NSString *refundedBy;
@property (nonatomic, copy, nullable) NSString *cancellationReason;
@property (nonatomic, copy, nullable) NSDate *cancelledAt;
@property (nonatomic, copy, nullable) NSString *cancelledBy;
@property (nonatomic, copy, nullable) NSString *branchID;
@property (nonatomic, copy, nullable) NSString *branchName;
@property (nonatomic, copy, nullable) NSString *cashierName;
@property (nonatomic, readonly) BOOL hasIndividuallyTrackedLivePets;
@property (nonatomic, readonly) BOOL hasGenericMerchandise;
@property (nonatomic, readonly) NSArray<PPPOSCartItem *> *livePetCartItems;
@property (nonatomic, readonly) NSArray<PPPOSCartItem *> *genericCartItems;
- (instancetype)initWithDictionary:(NSDictionary *)dict documentID:(NSString *)docID;
@end

@interface PPPOSService : NSObject
+ (instancetype)shared;
+ (BOOL)isExactUnitSelectionConflictError:(NSError *)error;
+ (NSDictionary<NSString *, id> *)exactUnitConflictDetailsForError:(NSError *)error;
- (void)listAvailableUnitsForProductID:(NSString *)productID
                               cursor:(nullable NSString *)cursor
                           completion:(void(^)(NSArray<PPPOSInventoryUnit *> * _Nullable units,
                                               NSString * _Nullable nextCursor,
                                               BOOL hasMore,
                                               NSError * _Nullable error))completion;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(nullable NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                     completion:(void(^)(PPPOSSubmitResult * _Nullable result,
                                         NSError * _Nullable error))completion;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(nullable NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(nullable NSString *)customerName
                  customerPhone:(nullable NSString *)customerPhone
                  posCustomerID:(nullable NSString *)posCustomerID
                     completion:(void(^)(PPPOSSubmitResult * _Nullable result,
                                         NSError * _Nullable error))completion;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                       subtotal:(double)subtotal
                       discount:(double)discount
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(nullable NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(nullable NSString *)customerName
                  customerPhone:(nullable NSString *)customerPhone
                  posCustomerID:(nullable NSString *)posCustomerID
                     completion:(void(^)(PPPOSSubmitResult * _Nullable result,
                                         NSError * _Nullable error))completion;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                       subtotal:(double)subtotal
                       discount:(double)discount
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(nullable NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(nullable NSString *)customerName
                  customerPhone:(nullable NSString *)customerPhone
                  posCustomerID:(nullable NSString *)posCustomerID
                       branchID:(nullable NSString *)branchID
                     completion:(void(^)(PPPOSSubmitResult * _Nullable result,
                                         NSError * _Nullable error))completion;
- (void)submitPOSOrderWithItems:(NSArray<NSDictionary *> *)items
                       subtotal:(double)subtotal
                       discount:(double)discount
                          total:(double)total
                  paymentMethod:(NSString *)paymentMethod
                   cashReceived:(nullable NSNumber *)cashReceived
                      commandID:(NSString *)commandID
                   customerName:(nullable NSString *)customerName
                  customerPhone:(nullable NSString *)customerPhone
                  posCustomerID:(nullable NSString *)posCustomerID
                       branchID:(nullable NSString *)branchID
                   salesChannel:(nullable NSString *)salesChannel
                     completion:(void(^)(PPPOSSubmitResult * _Nullable result,
                                         NSError * _Nullable error))completion;
- (void)fetchPOSHistoryForBranchID:(NSString *)branchID
                         completion:(void(^)(NSArray<PPPOSReceipt *> * _Nullable receipts,
                                             NSError * _Nullable error))completion
    NS_SWIFT_NAME(fetchPOSHistory(branchID:completion:));
- (void)fetchPOSReceiptForTransactionID:(NSString *)transactionID
                             completion:(void(^)(PPPOSReceipt * _Nullable receipt,
                                                 NSError * _Nullable error))completion;
- (void)cancelTransaction:(NSString *)transactionId
           expectedStatus:(nullable NSString *)expectedStatus
                   reason:(NSString *)reason
               completion:(void(^)(BOOL success, NSError * _Nullable error))completion
    NS_SWIFT_NAME(cancelTransaction(transactionID:expectedStatus:reason:completion:));
- (void)refundTransaction:(NSString *)transactionId
             refundAmount:(double)refundAmount
              refundItems:(nullable NSArray<NSDictionary *> *)refundItems
                   reason:(NSString *)reason
                 currency:(nullable NSString *)currency
               completion:(void(^)(BOOL success, NSError * _Nullable error))completion
    NS_SWIFT_NAME(refundTransaction(transactionID:refundAmount:refundItems:reason:currency:completion:));
- (void)refundTransaction:(NSString *)transactionId
             refundAmount:(double)refundAmount
              refundItems:(nullable NSArray<NSDictionary *> *)refundItems
                   reason:(NSString *)reason
                 currency:(nullable NSString *)currency
                commandID:(nullable NSString *)commandID
               completion:(void(^)(BOOL success, NSString * _Nullable refundID, NSError * _Nullable error))completion
    NS_SWIFT_NAME(refundTransaction(transactionID:refundAmount:refundItems:reason:currency:commandID:completion:));
- (void)refundTransaction:(NSString *)transactionId
             refundAmount:(double)refundAmount
              refundItems:(nullable NSArray<NSDictionary *> *)refundItems
                   reason:(NSString *)reason
                 currency:(nullable NSString *)currency
                commandID:(nullable NSString *)commandID
               refundMode:(nullable NSString *)refundMode
   refundAdjustmentReason:(nullable NSString *)refundAdjustmentReason
               completion:(void(^)(BOOL success, NSString * _Nullable refundID, NSError * _Nullable error))completion
    NS_SWIFT_NAME(refundTransaction(transactionID:refundAmount:refundItems:reason:currency:commandID:refundMode:refundAdjustmentReason:completion:));
@end

// MARK: - POS Deep Diagnostic Logging

typedef NS_ENUM(NSInteger, PPPOSLogLevel) {
    PPPOSLogLevelDebug = 0,
    PPPOSLogLevelInfo = 1,
    PPPOSLogLevelWarning = 2,
    PPPOSLogLevelError = 3
};

@interface PPPOSLogEntry : NSObject
@property (nonatomic, copy, readonly) NSString *entryID;
@property (nonatomic, copy, readonly) NSDate *timestamp;
@property (nonatomic, assign, readonly) PPPOSLogLevel level;
@property (nonatomic, copy, readonly) NSString *levelString;
@property (nonatomic, copy, readonly) NSString *category;
@property (nonatomic, copy, readonly) NSString *event;
@property (nonatomic, copy, readonly) NSString *message;
@property (nonatomic, copy, readonly, nullable) NSString *traceID;
@property (nonatomic, assign, readonly) NSInteger durationMs;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *metadata;

- (instancetype)initWithLevel:(PPPOSLogLevel)level
                     category:(NSString *)category
                        event:(NSString *)event
                      message:(NSString *)message
                      traceID:(nullable NSString *)traceID
                   durationMs:(NSInteger)durationMs
                     metadata:(nullable NSDictionary<NSString *, id> *)metadata;

- (NSString *)formattedConsoleLine;
- (NSString *)jsonString;
@end

FOUNDATION_EXPORT NSString * const PPPOSLogDidAppendNotification;

@interface PPPOSLogger : NSObject
+ (instancetype)sharedLogger;
+ (NSString *)generateTraceID;

@property (nonatomic, assign) BOOL consoleLoggingEnabled;
@property (nonatomic, assign) NSInteger maxBufferSize;

- (void)logLevel:(PPPOSLogLevel)level
        category:(NSString *)category
           event:(NSString *)event
         message:(NSString *)message
         traceID:(nullable NSString *)traceID
      durationMs:(NSInteger)durationMs
        metadata:(nullable NSDictionary<NSString *, id> *)metadata;

- (void)infoWithCategory:(NSString *)category event:(NSString *)event message:(NSString *)message;
- (void)infoWithCategory:(NSString *)category event:(NSString *)event traceID:(nullable NSString *)traceID metadata:(nullable NSDictionary<NSString *, id> *)metadata message:(NSString *)message;
- (void)warnWithCategory:(NSString *)category event:(NSString *)event traceID:(nullable NSString *)traceID metadata:(nullable NSDictionary<NSString *, id> *)metadata message:(NSString *)message;
- (void)errorWithCategory:(NSString *)category event:(NSString *)event traceID:(nullable NSString *)traceID durationMs:(NSInteger)durationMs error:(nullable NSError *)error metadata:(nullable NSDictionary<NSString *, id> *)metadata message:(NSString *)message;

- (NSArray<PPPOSLogEntry *> *)allEntries;
- (NSArray<PPPOSLogEntry *> *)recentEntriesWithLimit:(NSUInteger)limit;
- (void)clearLogs;
- (NSString *)exportLogsAsPlainText;
- (NSString *)exportLogsAsJSON;
- (NSDictionary<NSString *, id> *)diagnosticSummary;
@end

NS_ASSUME_NONNULL_END
