#import <Foundation/Foundation.h>
#import "PPPaymentManagementModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^PPPaymentAdminRecordsCompletion)(NSArray<PPPaymentAdminRecord *> *records,
                                                FIRDocumentSnapshot * _Nullable nextCursor,
                                                NSError * _Nullable error);
typedef void (^PPPaymentAdminRecordCompletion)(PPPaymentAdminRecord * _Nullable record,
                                               NSError * _Nullable error);
typedef void (^PPPaymentAdminRequestEventsCompletion)(NSArray<PPPaymentAdminTimelineEvent *> *events,
                                                      NSError * _Nullable error);
typedef void (^PPPaymentAdminSettingsCompletion)(PPPaymentAdminSettings * _Nullable settings,
                                                 NSError * _Nullable error);

@interface PPPaymentManagementService : NSObject

+ (instancetype)shared;
+ (BOOL)isPartialReadError:(nullable NSError *)error;

- (BOOL)currentAdminCanManagePayments;
- (BOOL)currentAdminCanViewPayments;
- (BOOL)currentAdminCanRefundPayments;
- (void)fetchOrdersWithFilters:(nullable PPPaymentManagementFilters *)filters
                      pageSize:(NSInteger)pageSize
                    startAfter:(nullable FIRDocumentSnapshot *)startAfter
                    completion:(PPPaymentAdminRecordsCompletion)completion;

- (void)refreshRequestSummariesForRecords:(NSArray<PPPaymentAdminRecord *> *)records
                               completion:(void (^_Nullable)(NSArray<PPPaymentAdminRecord *> *records))completion;

- (void)loadFullRecordForOrderID:(NSString *)orderID
                      completion:(PPPaymentAdminRecordCompletion)completion;

- (void)loadEventsForRequest:(PPPaymentAdminSupportRequest *)request
                   completion:(PPPaymentAdminRequestEventsCompletion)completion;

- (void)loadPaymentSettingsWithCompletion:(PPPaymentAdminSettingsCompletion)completion;
- (void)savePaymentSettings:(PPPaymentAdminSettings *)settings
                 completion:(PPPaymentAdminSettingsCompletion)completion;

- (NSString *)defaultAdminNoteForOrderID:(NSString *)orderID
                                  action:(NSString *)action;

// Compatibility surface for callers that only have a projected workflow status.
// New mutations should use the exact callable action above.
- (NSString *)defaultAdminNoteForOrderID:(NSString *)orderID
                               nextStatus:(NSString *)nextStatus;

- (void)approveOrder:(PPPaymentAdminRecord *)record
                note:(nullable NSString *)note
          completion:(PPPaymentAdminRecordCompletion)completion;

- (void)markOrderProcessing:(PPPaymentAdminRecord *)record
                       note:(nullable NSString *)note
                 completion:(PPPaymentAdminRecordCompletion)completion;

- (void)markOrderShipped:(PPPaymentAdminRecord *)record
                    note:(nullable NSString *)note
              completion:(PPPaymentAdminRecordCompletion)completion;

- (void)markOrderDelivered:(PPPaymentAdminRecord *)record
                      note:(nullable NSString *)note
                completion:(PPPaymentAdminRecordCompletion)completion;

- (void)collectOrderPayment:(PPPaymentAdminRecord *)record
                       note:(nullable NSString *)note
                 completion:(PPPaymentAdminRecordCompletion)completion;

- (void)cancelOrder:(PPPaymentAdminRecord *)record
               note:(nullable NSString *)note
         completion:(PPPaymentAdminRecordCompletion)completion;

- (void)resolveRequest:(PPPaymentAdminSupportRequest *)request
              forOrder:(PPPaymentAdminRecord *)record
                action:(PPPaymentAdminRequestResolution)action
                  note:(nullable NSString *)note
                amount:(nullable NSNumber *)amount
            completion:(PPPaymentAdminRecordCompletion)completion;

@end

NS_ASSUME_NONNULL_END
