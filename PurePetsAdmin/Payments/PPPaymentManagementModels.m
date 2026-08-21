#import "PPPaymentManagementModels.h"
#import "Language.h"

static NSString *PPPaymentAdminTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSDate *PPPaymentAdminDateFromValue(id value)
{
    if ([value isKindOfClass:FIRTimestamp.class]) {
        return ((FIRTimestamp *)value).dateValue;
    }
    if ([value isKindOfClass:NSDate.class]) {
        return (NSDate *)value;
    }
    if ([value respondsToSelector:@selector(dateValue)]) {
        return [value dateValue];
    }
    return nil;
}

static NSString *PPPaymentAdminEffectiveString(id value)
{
    NSString *normalized = PPPaymentAdminTrimmedString(value);
    if (normalized.length == 0) return @"";
    normalized = normalized.lowercaseString;
    normalized = [normalized stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    while ([normalized containsString:@"__"]) {
        normalized = [normalized stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
    }
    return normalized;
}

static NSString *PPPaymentAdminNormalizedPaymentMethod(id paymentMethodId, id paymentProvider)
{
    NSString *normalized = PPPaymentAdminEffectiveString(paymentMethodId);
    if (normalized.length == 0) {
        normalized = PPPaymentAdminEffectiveString(paymentProvider);
    }
    if ([normalized isEqualToString:@"cash"] ||
        [normalized isEqualToString:@"cod"] ||
        [normalized isEqualToString:@"cash_on_delivery"]) {
        return @"cash";
    }
    return @"qib";
}

static BOOL PPPaymentAdminLegacyHasCapturedPayment(NSString *paymentMethodId, NSString *statusKey, NSString *transactionId, NSDate *paidAt, NSDate *paymentCollectedAt)
{
    if ([paymentMethodId isEqualToString:@"cash"]) {
        return (PPPaymentAdminTrimmedString(transactionId).length > 0 ||
                [paidAt isKindOfClass:NSDate.class] ||
                [paymentCollectedAt isKindOfClass:NSDate.class]);
    }
    return (PPPaymentAdminTrimmedString(transactionId).length > 0 ||
            [paidAt isKindOfClass:NSDate.class] ||
            [PPPaymentAdminRecord isPaidLikeStatus:statusKey]);
}

static NSString *PPPaymentAdminNormalizedPaymentStatus(id paymentStatus, NSString *paymentMethodId, NSString *statusKey, NSString *transactionId, NSDate *paidAt, NSDate *paymentCollectedAt)
{
    NSString *normalized = PPPaymentAdminEffectiveString(paymentStatus);
    if ([normalized isEqualToString:@"pending"] ||
        [normalized isEqualToString:@"pending_collection"] ||
        [normalized isEqualToString:@"paid"] ||
        [normalized isEqualToString:@"failed"] ||
        [normalized isEqualToString:@"cancelled"]) {
        return normalized;
    }
    if (PPPaymentAdminLegacyHasCapturedPayment(paymentMethodId, statusKey, transactionId, paidAt, paymentCollectedAt)) {
        return @"paid";
    }
    if ([PPPaymentAdminRecord isFailureLikeStatus:statusKey]) {
        return @"failed";
    }
    if ([PPPaymentAdminRecord isCancelledLikeStatus:statusKey]) {
        return @"cancelled";
    }
    return [paymentMethodId isEqualToString:@"cash"] ? @"pending_collection" : @"pending";
}

static NSDictionary *PPPaymentAdminSafeDictionary(id value)
{
    if ([value isKindOfClass:NSDictionary.class]) {
        return (NSDictionary *)value;
    }
    return @{};
}

static NSArray *PPPaymentAdminSafeArray(id value)
{
    if ([value isKindOfClass:NSArray.class]) {
        return (NSArray *)value;
    }
    return @[];
}

static NSString *PPPaymentAdminStringFromCandidates(NSDictionary *dictionary, NSArray<NSString *> *keys)
{
    NSDictionary *source = PPPaymentAdminSafeDictionary(dictionary);
    for (NSString *key in keys) {
        NSString *value = PPPaymentAdminTrimmedString(source[key]);
        if (value.length > 0) {
            return value;
        }
    }
    return @"";
}

static NSString *PPPaymentAdminUppercaseAlphaNumericString(id value)
{
    NSString *trimmed = [[PPPaymentAdminTrimmedString(value) uppercaseString] copy];
    if (trimmed.length == 0) return @"";

    NSMutableString *result = [NSMutableString stringWithCapacity:trimmed.length];
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger index = 0; index < trimmed.length; index += 1) {
        unichar character = [trimmed characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [result appendFormat:@"%C", character];
        }
    }
    return result.copy;
}

static NSString *PPPaymentAdminNormalizedPublicOrderNumberString(id value)
{
    NSString *uppercased = [[PPPaymentAdminTrimmedString(value) uppercaseString] copy];
    if (uppercased.length == 0) return @"";

    NSMutableString *result = [NSMutableString stringWithCapacity:uppercased.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    for (NSUInteger index = 0; index < uppercased.length; index += 1) {
        unichar character = [uppercased characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [result appendFormat:@"%C", character];
        }
    }
    return result.copy;
}

static NSString *PPPaymentAdminLegacyDisplayOrderReference(NSString *orderId)
{
    NSString *normalized = PPPaymentAdminUppercaseAlphaNumericString(orderId);
    if (normalized.length == 0) return @"";

    NSString *tail = normalized.length > 12 ? [normalized substringFromIndex:(normalized.length - 12)] : normalized;
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    for (NSUInteger index = 0; index < tail.length; index += 4) {
        NSUInteger chunkLength = MIN((NSUInteger)4, tail.length - index);
        [groups addObject:[tail substringWithRange:NSMakeRange(index, chunkLength)]];
    }
    return [NSString stringWithFormat:@"PP-%@", [groups componentsJoinedByString:@"-"]];
}

static NSString *PPPaymentAdminHumanizedValue(NSString *value)
{
    NSString *normalized = PPPaymentAdminEffectiveString(value);
    if (normalized.length == 0) return @"";
    NSString *spaced = [[normalized componentsSeparatedByString:@"_"] componentsJoinedByString:@" "];
    NSString *humanized = spaced.capitalizedString;
    humanized = [humanized stringByReplacingOccurrencesOfString:@"Qib" withString:@"QIB"];
    return humanized;
}

@implementation PPPaymentAdminSettings

+ (instancetype)settingsFromDictionary:(NSDictionary *)dictionary
{
    NSDictionary *source = PPPaymentAdminSafeDictionary(dictionary);
    PPPaymentAdminSettings *settings = [PPPaymentAdminSettings new];
    double deliveryFee = [source[@"deliveryFee"] respondsToSelector:@selector(doubleValue)] ? [source[@"deliveryFee"] doubleValue] : 22.0;
    settings.deliveryFee = MAX(0.0, deliveryFee);
    settings.cashOnDeliveryEnabled = source[@"cashOnDeliveryEnabled"] ? [source[@"cashOnDeliveryEnabled"] boolValue] : YES;
    settings.onlinePaymentEnabled = source[@"onlinePaymentEnabled"] ? [source[@"onlinePaymentEnabled"] boolValue] : YES;
    settings.updatedAt = PPPaymentAdminDateFromValue(source[@"updatedAt"]);
    NSString *updatedBy = PPPaymentAdminStringFromCandidates(source, @[@"updatedBy"]);
    settings.updatedBy = updatedBy.length > 0 ? updatedBy : nil;
    return settings;
}

@end

NSString *PPPaymentAdminDisplayTitleForRequestStatus(NSString *statusKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(statusKey);
    if (normalized.length == 0) return kLang(@"PaymentMgmt_RequestStatus_PendingReview");
    if ([normalized isEqualToString:@"pending_review"] || [normalized isEqualToString:@"pending"]) return kLang(@"PaymentMgmt_RequestStatus_PendingReview");
    if ([normalized isEqualToString:@"approved"]) return kLang(@"PaymentMgmt_RequestStatus_Approved");
    if ([normalized isEqualToString:@"rejected"]) return kLang(@"PaymentMgmt_RequestStatus_Rejected");
    if ([normalized isEqualToString:@"completed"]) return kLang(@"PaymentMgmt_RequestStatus_Completed");
    if ([normalized isEqualToString:@"refunded"]) return kLang(@"PaymentMgmt_RequestStatus_Refunded");
    if ([normalized isEqualToString:@"partially_refunded"]) return kLang(@"PaymentMgmt_RequestStatus_PartiallyRefunded");
    if ([normalized isEqualToString:@"cancelled"]) return kLang(@"PaymentMgmt_RequestStatus_Cancelled");
    if ([normalized isEqualToString:@"closed"]) return kLang(@"PaymentMgmt_RequestStatus_Closed");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForRequestType(NSString *typeKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(typeKey);
    if (normalized.length == 0) return kLang(@"PaymentMgmt_RequestType_Support");
    if ([normalized isEqualToString:@"cancel"]) return kLang(@"PaymentMgmt_RequestType_Cancellation");
    if ([normalized isEqualToString:@"return"]) return kLang(@"PaymentMgmt_RequestType_Return");
    if ([normalized isEqualToString:@"refund"]) return kLang(@"PaymentMgmt_RequestType_Refund");
    if ([normalized isEqualToString:@"replacement"]) return kLang(@"PaymentMgmt_RequestType_Replacement");
    if ([normalized isEqualToString:@"complaint"]) return kLang(@"PaymentMgmt_RequestType_Complaint");
    if ([normalized isEqualToString:@"support"]) return kLang(@"PaymentMgmt_RequestType_Support");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForWorkflowStatus(NSString *statusKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(statusKey);
    if (normalized.length == 0 || [normalized isEqualToString:@"pending"] || [normalized isEqualToString:@"pending_collection"]) {
        return kLang(@"PaymentMgmt_WorkflowStatus_Pending");
    }
    if ([normalized isEqualToString:@"verification_pending"]) return PPPaymentAdminDisplayTitleForOrderStatus(@"verification_pending");
    if ([normalized isEqualToString:@"paid"]) return kLang(@"PaymentMgmt_WorkflowStatus_Paid");
    if ([normalized isEqualToString:@"processing"] ||
        [normalized isEqualToString:@"preparing"] ||
        [normalized isEqualToString:@"packed"] ||
        [normalized isEqualToString:@"shipped"] ||
        [normalized isEqualToString:@"shipping"] ||
        [normalized isEqualToString:@"in_transit"] ||
        [normalized isEqualToString:@"out_for_delivery"] ||
        [normalized isEqualToString:@"delivered"] ||
        [normalized isEqualToString:@"completed"]) {
        return PPPaymentAdminDisplayTitleForOrderStatus(normalized);
    }
    if ([normalized isEqualToString:@"shipped"]) return PPPaymentAdminDisplayTitleForOrderStatus(@"shipped");
    if ([normalized isEqualToString:@"delivered"]) return PPPaymentAdminDisplayTitleForOrderStatus(@"delivered");
    if ([normalized isEqualToString:@"failed"]) return kLang(@"PaymentMgmt_WorkflowStatus_Failed");
    if ([normalized isEqualToString:@"cancelled"]) return kLang(@"PaymentMgmt_WorkflowStatus_Cancelled");
    if ([normalized isEqualToString:@"refunded"]) return kLang(@"PaymentMgmt_WorkflowStatus_Refunded");
    if ([normalized isEqualToString:@"partially_refunded"]) return kLang(@"PaymentMgmt_WorkflowStatus_PartiallyRefunded");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForResolutionAction(PPPaymentAdminRequestResolution action)
{
    switch (action) {
        case PPPaymentAdminRequestResolutionApprove: return kLang(@"PaymentMgmt_Resolution_Approve");
        case PPPaymentAdminRequestResolutionReject: return kLang(@"PaymentMgmt_Resolution_Reject");
        case PPPaymentAdminRequestResolutionComplete: return kLang(@"PaymentMgmt_Resolution_Complete");
        case PPPaymentAdminRequestResolutionRefund: return kLang(@"PaymentMgmt_Resolution_Refund");
        case PPPaymentAdminRequestResolutionPartialRefund: return kLang(@"PaymentMgmt_Resolution_PartialRefund");
        case PPPaymentAdminRequestResolutionClose: return kLang(@"PaymentMgmt_Resolution_Close");
    }
    return kLang(@"PaymentMgmt_Resolution_Approve");
}

NSString *PPPaymentAdminDisplayTitleForPaymentMethod(NSString *methodKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(methodKey);
    if ([normalized isEqualToString:@"qib"]) return kLang(@"PaymentMgmt_Method_QIB");
    if ([normalized isEqualToString:@"card"]) return kLang(@"PaymentMgmt_Method_Card");
    if ([normalized isEqualToString:@"cash"]) return kLang(@"PaymentMgmt_Method_Cash");
    if ([normalized isEqualToString:@"manual"]) return kLang(@"PaymentMgmt_Method_Manual");
    if ([normalized isEqualToString:@"wallet"]) return kLang(@"PaymentMgmt_Method_Wallet");
    if ([normalized isEqualToString:@"bank_transfer"]) return kLang(@"PaymentMgmt_Method_BankTransfer");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForOrderStatus(NSString *statusKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(statusKey);
    if ([normalized isEqualToString:@"pending"]) return kLang(@"PaymentMgmt_OrderStatus_Pending");
    if ([normalized isEqualToString:@"verification_pending"]) return kLang(@"PaymentMgmt_OrderStatus_VerificationPending");
    if ([normalized isEqualToString:@"paid"]) return kLang(@"PaymentMgmt_OrderStatus_Paid");
    if ([normalized isEqualToString:@"processing"]) return kLang(@"PaymentMgmt_OrderStatus_Processing");
    if ([normalized isEqualToString:@"preparing"]) return kLang(@"PaymentMgmt_OrderStatus_Preparing");
    if ([normalized isEqualToString:@"packed"]) return kLang(@"PaymentMgmt_OrderStatus_Packed");
    if ([normalized isEqualToString:@"shipped"]) return kLang(@"PaymentMgmt_OrderStatus_Shipped");
    if ([normalized isEqualToString:@"shipping"]) return kLang(@"PaymentMgmt_OrderStatus_Shipping");
    if ([normalized isEqualToString:@"in_transit"]) return kLang(@"PaymentMgmt_OrderStatus_InTransit");
    if ([normalized isEqualToString:@"out_for_delivery"]) return kLang(@"PaymentMgmt_OrderStatus_OutForDelivery");
    if ([normalized isEqualToString:@"delivered"]) return kLang(@"PaymentMgmt_OrderStatus_Delivered");
    if ([normalized isEqualToString:@"completed"]) return kLang(@"PaymentMgmt_OrderStatus_Completed");
    if ([normalized isEqualToString:@"failed"]) return kLang(@"PaymentMgmt_OrderStatus_Failed");
    if ([normalized isEqualToString:@"cancelled"]) return kLang(@"PaymentMgmt_OrderStatus_Cancelled");
    if ([normalized isEqualToString:@"refunded"]) return kLang(@"PaymentMgmt_OrderStatus_Refunded");
    if ([normalized isEqualToString:@"partially_refunded"]) return kLang(@"PaymentMgmt_OrderStatus_PartiallyRefunded");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForVerificationStatus(NSString *statusKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(statusKey);
    if ([normalized isEqualToString:@"verified"]) return kLang(@"PaymentMgmt_Verification_Verified");
    if ([normalized isEqualToString:@"pending"] || [normalized isEqualToString:@"verification_pending"]) return kLang(@"PaymentMgmt_Verification_Pending");
    if ([normalized isEqualToString:@"unverified"]) return kLang(@"PaymentMgmt_Verification_Unverified");
    if ([normalized isEqualToString:@"failed"]) return kLang(@"PaymentMgmt_Verification_Failed");
    if ([normalized isEqualToString:@"requires_review"] || [normalized isEqualToString:@"manual_review"]) return kLang(@"PaymentMgmt_Verification_RequiresReview");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForFailureReason(NSString *reasonKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(reasonKey);
    if ([normalized isEqualToString:@"cancelled_by_admin"]) return kLang(@"PaymentMgmt_FailureReason_CancelledByAdmin");
    if ([normalized isEqualToString:@"payment_failed"]) return kLang(@"PaymentMgmt_FailureReason_PaymentFailed");
    if ([normalized isEqualToString:@"payment_declined"]) return kLang(@"PaymentMgmt_FailureReason_PaymentDeclined");
    if ([normalized isEqualToString:@"payment_expired"]) return kLang(@"PaymentMgmt_FailureReason_PaymentExpired");
    if ([normalized isEqualToString:@"payment_timeout"]) return kLang(@"PaymentMgmt_FailureReason_PaymentTimeout");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForIssueCategory(NSString *categoryKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(categoryKey);
    if ([normalized isEqualToString:@"payment"]) return kLang(@"PaymentMgmt_Category_Payment");
    if ([normalized isEqualToString:@"delivery"]) return kLang(@"PaymentMgmt_Category_Delivery");
    if ([normalized isEqualToString:@"item_quality"]) return kLang(@"PaymentMgmt_Category_ItemQuality");
    if ([normalized isEqualToString:@"wrong_item"]) return kLang(@"PaymentMgmt_Category_WrongItem");
    if ([normalized isEqualToString:@"missing_item"]) return kLang(@"PaymentMgmt_Category_MissingItem");
    if ([normalized isEqualToString:@"damaged_item"]) return kLang(@"PaymentMgmt_Category_DamagedItem");
    if ([normalized isEqualToString:@"return"]) return kLang(@"PaymentMgmt_Category_Return");
    if ([normalized isEqualToString:@"refund"]) return kLang(@"PaymentMgmt_Category_Refund");
    if ([normalized isEqualToString:@"replacement"]) return kLang(@"PaymentMgmt_Category_Replacement");
    if ([normalized isEqualToString:@"support"]) return kLang(@"PaymentMgmt_Category_Support");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForActorType(NSString *actorType)
{
    NSString *normalized = PPPaymentAdminEffectiveString(actorType);
    if ([normalized isEqualToString:@"admin"]) return kLang(@"PaymentMgmt_Actor_Admin");
    if ([normalized isEqualToString:@"system"]) return kLang(@"PaymentMgmt_Actor_System");
    if ([normalized isEqualToString:@"user"] || [normalized isEqualToString:@"customer"]) return kLang(@"PaymentMgmt_Actor_Customer");
    if ([normalized isEqualToString:@"gateway"] || [normalized isEqualToString:@"payment_gateway"]) return kLang(@"PaymentMgmt_Actor_PaymentGateway");
    return PPPaymentAdminHumanizedValue(normalized);
}

NSString *PPPaymentAdminDisplayTitleForTimelineSummary(PPPaymentAdminTimelineEvent *event)
{
    NSString *type = PPPaymentAdminEffectiveString(event.type);
    NSString *summaryCode = PPPaymentAdminEffectiveString(event.summaryCode);
    NSString *contractCode = summaryCode.length > 0 ? summaryCode : type;
    if ([contractCode isEqualToString:@"payment_verified"] || [contractCode isEqualToString:@"order_approve"]) return kLang(@"PaymentMgmt_Event_PaymentApproved");
    if ([contractCode isEqualToString:@"fulfillment_processing"] || [contractCode isEqualToString:@"order_mark_processing"]) return kLang(@"PaymentMgmt_Event_OrderProcessing");
    if ([contractCode isEqualToString:@"fulfillment_shipped"] || [contractCode isEqualToString:@"order_mark_shipped"] || [contractCode isEqualToString:@"order_mark_ready"]) return kLang(@"PaymentMgmt_Event_OrderShipped");
    if ([contractCode isEqualToString:@"fulfillment_delivered"] || [contractCode isEqualToString:@"order_mark_delivered"]) return kLang(@"PaymentMgmt_Event_OrderDelivered");
    if ([contractCode isEqualToString:@"order_cancelled"] || [contractCode isEqualToString:@"order_cancel"]) return kLang(@"PaymentMgmt_Event_OrderCancelled");
    if ([contractCode isEqualToString:@"refund_settlement_initiated"]) return kLang(@"PaymentMgmt_Event_RefundInitiated");
    if ([contractCode isEqualToString:@"request_status_updated"] || [contractCode hasPrefix:@"payment.request."]) {
        NSString *requestType = PPPaymentAdminEffectiveString(event.metadata[@"requestType"]);
        NSString *status = PPPaymentAdminDisplayTitleForRequestStatus(event.status);
        if (requestType.length > 0) {
            return [NSString stringWithFormat:kLang(@"PaymentMgmt_Event_TypedRequestMoved_Format"),
                    PPPaymentAdminDisplayTitleForRequestType(requestType),
                    status];
        }
        return [NSString stringWithFormat:kLang(@"PaymentMgmt_Event_RequestMoved_Format"), status];
    }
    if ([contractCode isEqualToString:@"payment_update"]) return kLang(@"PaymentMgmt_Event_PaymentUpdated");
    if ([contractCode isEqualToString:@"request_update"]) return kLang(@"PaymentMgmt_Event_RequestUpdated");
    return kLang(@"PaymentMgmt_Event_Unknown");
}

NSString *PPPaymentAdminDisplayTitleForAuditAction(NSString *actionKey)
{
    NSString *normalized = PPPaymentAdminEffectiveString(actionKey);
    if ([normalized isEqualToString:@"order_approve"]) return kLang(@"PaymentMgmt_Audit_OrderApprove");
    if ([normalized isEqualToString:@"order_mark_processing"]) return kLang(@"PaymentMgmt_Audit_OrderProcessing");
    if ([normalized isEqualToString:@"order_mark_shipped"]) return kLang(@"PaymentMgmt_Audit_OrderShipped");
    if ([normalized isEqualToString:@"order_mark_delivered"]) return kLang(@"PaymentMgmt_Audit_OrderDelivered");
    if ([normalized isEqualToString:@"order_cancel"]) return kLang(@"PaymentMgmt_Audit_OrderCancel");
    if ([normalized isEqualToString:@"request_refund_refunded"]) return kLang(@"PaymentMgmt_Audit_RequestRefundFull");
    if ([normalized isEqualToString:@"request_refund_partial"]) return kLang(@"PaymentMgmt_Audit_RequestRefundPartial");
    if ([normalized isEqualToString:@"payment_update"]) return kLang(@"PaymentMgmt_Audit_PaymentUpdate");
    if ([normalized isEqualToString:@"request_update"]) return kLang(@"PaymentMgmt_Audit_RequestUpdate");
    if ([normalized hasPrefix:@"request_"]) {
        NSArray<NSString *> *parts = [normalized componentsSeparatedByString:@"_"];
        if (parts.count >= 3) {
            NSString *requestType = parts[1];
            NSString *action = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"_"];
            NSString *requestTitle = PPPaymentAdminDisplayTitleForRequestType(requestType);
            if ([action isEqualToString:@"approve"]) {
                return [NSString stringWithFormat:kLang(@"PaymentMgmt_Audit_RequestApprove_Format"), requestTitle];
            }
            if ([action isEqualToString:@"reject"]) {
                return [NSString stringWithFormat:kLang(@"PaymentMgmt_Audit_RequestReject_Format"), requestTitle];
            }
            if ([action isEqualToString:@"complete"]) {
                return [NSString stringWithFormat:kLang(@"PaymentMgmt_Audit_RequestComplete_Format"), requestTitle];
            }
            if ([action isEqualToString:@"close"]) {
                return [NSString stringWithFormat:kLang(@"PaymentMgmt_Audit_RequestClose_Format"), requestTitle];
            }
        }
    }
    return PPPaymentAdminHumanizedValue(normalized);
}

@implementation PPPaymentManagementFilters

+ (instancetype)defaultFilters
{
    PPPaymentManagementFilters *filters = [PPPaymentManagementFilters new];
    filters.statusKey = @"all";
    filters.paymentTypeKey = @"all";
    filters.searchText = @"";
    filters.dateRange = PPPaymentAdminDateRangeAll;
    return filters;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _statusKey = @"all";
        _paymentTypeKey = @"all";
        _searchText = @"";
        _dateRange = PPPaymentAdminDateRangeAll;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    PPPaymentManagementFilters *copy = [[[self class] allocWithZone:zone] init];
    copy.statusKey = self.statusKey ?: @"all";
    copy.paymentTypeKey = self.paymentTypeKey ?: @"all";
    copy.searchText = self.searchText ?: @"";
    copy.dateRange = self.dateRange;
    return copy;
}

- (BOOL)isDefaultState
{
    return ([PPPaymentAdminEffectiveString(self.statusKey) isEqualToString:@"all"] &&
            [PPPaymentAdminEffectiveString(self.paymentTypeKey) isEqualToString:@"all"] &&
            PPPaymentAdminTrimmedString(self.searchText).length == 0 &&
            self.dateRange == PPPaymentAdminDateRangeAll);
}

@end

@implementation PPPaymentAdminTimelineEvent

+ (instancetype)eventFromSnapshot:(FIRDocumentSnapshot *)snapshot
{
    return [self eventFromDictionary:snapshot.data ?: @{} documentID:snapshot.documentID];
}

+ (instancetype)eventFromDictionary:(NSDictionary *)dictionary documentID:(NSString *)documentID
{
    PPPaymentAdminTimelineEvent *event = [PPPaymentAdminTimelineEvent new];
    event.eventId = PPPaymentAdminStringFromCandidates(dictionary, @[@"eventId"]);
    if (event.eventId.length == 0) event.eventId = PPPaymentAdminTrimmedString(documentID);
    event.type = PPPaymentAdminEffectiveString(dictionary[@"type"]);
    event.status = PPPaymentAdminEffectiveString(dictionary[@"status"]);
    event.actorType = PPPaymentAdminEffectiveString(dictionary[@"actorType"]);
    event.summaryCode = PPPaymentAdminEffectiveString(dictionary[@"summaryCode"]);
    event.summary = PPPaymentAdminStringFromCandidates(dictionary, @[@"summary"]);
    event.metadata = [dictionary[@"metadata"] isKindOfClass:NSDictionary.class] ? dictionary[@"metadata"] : nil;
    event.createdAt = PPPaymentAdminDateFromValue(dictionary[@"createdAt"]) ?: [NSDate date];
    return event;
}

@end

@implementation PPPaymentAdminAuditEntry

+ (instancetype)auditFromSnapshot:(FIRDocumentSnapshot *)snapshot
{
    return [self auditFromDictionary:snapshot.data ?: @{} documentID:snapshot.documentID];
}

+ (instancetype)auditFromDictionary:(NSDictionary *)dictionary documentID:(NSString *)documentID
{
    PPPaymentAdminAuditEntry *entry = [PPPaymentAdminAuditEntry new];
    entry.auditId = PPPaymentAdminTrimmedString(documentID);
    entry.action = PPPaymentAdminEffectiveString(dictionary[@"action"]);
    entry.area = PPPaymentAdminEffectiveString(dictionary[@"area"]);
    entry.entityType = PPPaymentAdminEffectiveString(dictionary[@"entityType"]);
    entry.entityId = PPPaymentAdminStringFromCandidates(dictionary, @[@"entityId"]);
    entry.orderId = PPPaymentAdminStringFromCandidates(dictionary, @[@"orderId"]);
    entry.requestId = PPPaymentAdminStringFromCandidates(dictionary, @[@"requestId"]);
    entry.adminUid = PPPaymentAdminStringFromCandidates(dictionary, @[@"adminUid"]);
    entry.adminName = PPPaymentAdminStringFromCandidates(dictionary, @[@"adminName"]);
    entry.note = PPPaymentAdminStringFromCandidates(dictionary, @[@"note", @"reason"]);
    entry.beforeState = [dictionary[@"before"] isKindOfClass:NSDictionary.class] ? dictionary[@"before"] : nil;
    entry.afterState = [dictionary[@"after"] isKindOfClass:NSDictionary.class] ? dictionary[@"after"] : nil;
    entry.createdAt = PPPaymentAdminDateFromValue(dictionary[@"createdAt"]) ?: PPPaymentAdminDateFromValue(dictionary[@"timestamp"]) ?: [NSDate date];
    return entry;
}

@end

@implementation PPPaymentAdminSupportRequest

+ (instancetype)requestFromSnapshot:(FIRDocumentSnapshot *)snapshot
{
    return [self requestFromDictionary:snapshot.data ?: @{} documentID:snapshot.documentID];
}

+ (instancetype)requestFromDictionary:(NSDictionary *)dictionary documentID:(NSString *)documentID
{
    PPPaymentAdminSupportRequest *request = [PPPaymentAdminSupportRequest new];
    request.requestId = PPPaymentAdminStringFromCandidates(dictionary, @[@"requestId"]);
    if (request.requestId.length == 0) request.requestId = PPPaymentAdminTrimmedString(documentID);
    request.orderId = PPPaymentAdminStringFromCandidates(dictionary, @[@"orderId"]);
    request.userId = PPPaymentAdminStringFromCandidates(dictionary, @[@"userId", @"uid"]);
    request.type = PPPaymentAdminEffectiveString(dictionary[@"type"]);
    request.reasonCode = PPPaymentAdminEffectiveString(dictionary[@"reasonCode"]);
    request.reasonTitle = PPPaymentAdminStringFromCandidates(dictionary, @[@"reasonTitle"]);
    request.issueCategory = PPPaymentAdminEffectiveString(dictionary[@"issueCategory"]);
    request.subject = PPPaymentAdminStringFromCandidates(dictionary, @[@"subject"]);
    request.notes = PPPaymentAdminStringFromCandidates(dictionary, @[@"notes"]);
    request.status = PPPaymentAdminEffectiveString(dictionary[@"status"]);
    request.finalResolution = PPPaymentAdminEffectiveString(dictionary[@"finalResolution"]);
    request.itemIDs = [PPPaymentAdminSafeArray(dictionary[@"itemIDs"]) filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
        return PPPaymentAdminTrimmedString(evaluatedObject).length > 0;
    }]];
    request.itemSnapshots = [PPPaymentAdminSafeArray(dictionary[@"itemSnapshots"]) copy];
    request.attachments = [PPPaymentAdminSafeArray(dictionary[@"attachments"]) copy];
    request.resolution = [dictionary[@"resolution"] isKindOfClass:NSDictionary.class] ? dictionary[@"resolution"] : nil;
    request.adminReview = [dictionary[@"adminReview"] isKindOfClass:NSDictionary.class] ? dictionary[@"adminReview"] : nil;
    request.submittedAt = PPPaymentAdminDateFromValue(dictionary[@"submittedAt"]);
    request.resolvedAt = PPPaymentAdminDateFromValue(dictionary[@"resolvedAt"]);
    request.createdAt = PPPaymentAdminDateFromValue(dictionary[@"createdAt"]) ?: [NSDate date];
    request.updatedAt = PPPaymentAdminDateFromValue(dictionary[@"updatedAt"]) ?: request.createdAt;
    request.events = @[];
    return request;
}

- (BOOL)isRefundLike
{
    NSString *typeKey = PPPaymentAdminEffectiveString(self.type);
    NSString *statusKey = [self effectiveResolutionKey];
    return [typeKey isEqualToString:@"refund"] ||
           [statusKey isEqualToString:@"refunded"] ||
           [statusKey isEqualToString:@"partially_refunded"];
}

- (BOOL)isReturnLike
{
    NSString *typeKey = PPPaymentAdminEffectiveString(self.type);
    return [typeKey isEqualToString:@"return"] ||
           [typeKey isEqualToString:@"replacement"];
}

- (BOOL)isCancellationLike
{
    return [PPPaymentAdminEffectiveString(self.type) isEqualToString:@"cancel"];
}

- (BOOL)isOpen
{
    return [PPPaymentAdminRecord requestStatusIsOpen:self.status];
}

- (NSString *)effectiveResolutionKey
{
    NSString *resolutionKey = PPPaymentAdminEffectiveString(self.finalResolution);
    if (resolutionKey.length > 0 && ![resolutionKey isEqualToString:@"pending_review"]) {
        return resolutionKey;
    }
    return PPPaymentAdminEffectiveString(self.status);
}

@end

@implementation PPPaymentAdminRecord

+ (instancetype)recordFromSnapshot:(FIRDocumentSnapshot *)snapshot
{
    PPPaymentAdminRecord *record = [self recordFromDictionary:snapshot.data ?: @{} documentID:snapshot.documentID];
    record.sourceSnapshot = snapshot;
    return record;
}

+ (instancetype)recordFromDictionary:(NSDictionary *)dictionary documentID:(NSString *)documentID
{
    PPPaymentAdminRecord *record = [PPPaymentAdminRecord new];
    record.orderId = PPPaymentAdminStringFromCandidates(dictionary, @[@"orderId"]);
    if (record.orderId.length == 0) record.orderId = PPPaymentAdminTrimmedString(documentID);
    record.branchId = PPPaymentAdminTrimmedString(dictionary[@"branchId"]);
    record.regionId = PPPaymentAdminTrimmedString(dictionary[@"regionId"]);
    NSString *orderNumber = PPPaymentAdminNormalizedPublicOrderNumberString(dictionary[@"orderNumber"]);
    if (orderNumber.length == 0) {
        orderNumber = PPPaymentAdminNormalizedPublicOrderNumberString(dictionary[@"displayOrderNumber"]);
    }
    record.orderNumber = orderNumber.length > 0 ? orderNumber : nil;
    record.userId = PPPaymentAdminStringFromCandidates(dictionary, @[@"userId", @"uid"]);
    record.userDisplayName = PPPaymentAdminStringFromCandidates(dictionary, @[@"userDisplayName", @"customerName", @"customerDisplayName"]);
    record.userEmail = PPPaymentAdminStringFromCandidates(dictionary, @[@"userEmail", @"customerEmail"]);
    record.rawStatus = [self normalizedStatusString:dictionary[@"status"]];
    record.paymentMethodId = PPPaymentAdminNormalizedPaymentMethod(dictionary[@"paymentMethodId"], dictionary[@"paymentProvider"]);
    record.paymentProvider = PPPaymentAdminStringFromCandidates(dictionary, @[@"paymentProvider"]);
    if (record.paymentProvider.length == 0) record.paymentProvider = [record.paymentMethodId isEqualToString:@"cash"] ? @"CASH" : @"QIB";
    record.paymentTypeKey = PPPaymentAdminEffectiveString(dictionary[@"paymentType"]);
    if (record.paymentTypeKey.length == 0) {
        record.paymentTypeKey = PPPaymentAdminEffectiveString(record.paymentMethodId.length > 0 ? record.paymentMethodId : record.paymentProvider);
    }
    record.currency = PPPaymentAdminStringFromCandidates(dictionary, @[@"currency"]);
    if (record.currency.length == 0) record.currency = @"QAR";
    record.transactionId = PPPaymentAdminStringFromCandidates(dictionary, @[@"transactionId"]);
    record.verificationStatus = PPPaymentAdminEffectiveString(dictionary[@"verificationStatus"]);
    record.failureReason = PPPaymentAdminStringFromCandidates(dictionary, @[@"failureReason", @"cancelReason"]);
    record.refundStatus = PPPaymentAdminEffectiveString(dictionary[@"refundStatus"]);
    record.returnStatus = PPPaymentAdminEffectiveString(dictionary[@"returnStatus"]);
    record.latestRequestType = PPPaymentAdminEffectiveString(dictionary[@"latestRequestType"]);
    record.latestRequestStatus = PPPaymentAdminEffectiveString(dictionary[@"latestRequestStatus"]);
    record.fulfillmentVersion = [dictionary[@"fulfillmentVersion"] respondsToSelector:@selector(integerValue)]
        ? [dictionary[@"fulfillmentVersion"] integerValue]
        : 0;
    NSMutableArray<NSString *> *fulfillmentOrderIDs = [NSMutableArray array];
    for (id value in PPPaymentAdminSafeArray(dictionary[@"fulfillmentOrderIDs"])) {
        NSString *fulfillmentID = PPPaymentAdminTrimmedString(value);
        if (fulfillmentID.length > 0 && ![fulfillmentOrderIDs containsObject:fulfillmentID]) {
            [fulfillmentOrderIDs addObject:fulfillmentID];
        }
    }
    record.fulfillmentOrderIDs = fulfillmentOrderIDs.copy;
    double totalAmount = [dictionary[@"totalAmount"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"totalAmount"] doubleValue] : 0.0;
    if (totalAmount <= 0.0 && [dictionary[@"amount"] respondsToSelector:@selector(doubleValue)]) {
        totalAmount = [dictionary[@"amount"] doubleValue];
    }
    record.totalAmount = MAX(0.0, totalAmount);
    NSDate *now = [NSDate date];
    record.createdAt = PPPaymentAdminDateFromValue(dictionary[@"createdAt"]) ?: now;
    record.updatedAt = PPPaymentAdminDateFromValue(dictionary[@"updatedAt"]) ?: record.createdAt;
    record.statusUpdatedAt = PPPaymentAdminDateFromValue(dictionary[@"statusUpdatedAt"]);
    record.paidAt = PPPaymentAdminDateFromValue(dictionary[@"paidAt"]);
    record.processedAt = PPPaymentAdminDateFromValue(dictionary[@"processedAt"]);
    record.shippedAt = PPPaymentAdminDateFromValue(dictionary[@"shippedAt"]);
    record.deliveredAt = PPPaymentAdminDateFromValue(dictionary[@"deliveredAt"]);
    record.cancelledAt = PPPaymentAdminDateFromValue(dictionary[@"cancelledAt"]) ?: PPPaymentAdminDateFromValue(dictionary[@"canceledAt"]);
    record.paymentCollectedAt = PPPaymentAdminDateFromValue(dictionary[@"paymentCollectedAt"]);
    record.estimatedDeliveryAt = PPPaymentAdminDateFromValue(dictionary[@"estimatedDeliveryAt"]);
    record.paymentStatus = PPPaymentAdminNormalizedPaymentStatus(dictionary[@"paymentStatus"],
                                                                record.paymentMethodId,
                                                                record.rawStatus,
                                                                record.transactionId,
                                                                record.paidAt,
                                                                record.paymentCollectedAt);
    record.items = [PPPaymentAdminSafeArray(dictionary[@"items"]) copy];
    record.shippingAddressSnapshot = PPPaymentAdminSafeDictionary(dictionary[@"shippingAddressSnapshot"]);
    record.inventoryDeducted = [dictionary[@"inventoryDeducted"] boolValue];
    record.inventoryRestocked = [dictionary[@"inventoryRestocked"] boolValue];
    record.paymentResponse = [dictionary[@"paymentResponse"] isKindOfClass:NSDictionary.class] ? dictionary[@"paymentResponse"] : nil;
    record.requests = @[];
    record.timelineEvents = @[];
    record.auditEntries = @[];
    record.auditEvidenceRestricted = NO;
    return record;
}

+ (NSString *)normalizedStatusString:(id)value
{
    return PPPaymentAdminEffectiveString(value);
}

+ (BOOL)status:(NSString *)statusKey matchesAnyKeywords:(NSArray<NSString *> *)keywords
{
    NSString *normalizedStatus = PPPaymentAdminEffectiveString(statusKey);
    if (normalizedStatus.length == 0 || keywords.count == 0) return NO;
    NSString *wrappedStatus = [NSString stringWithFormat:@"_%@_", normalizedStatus];
    for (NSString *keyword in keywords) {
        NSString *normalizedKeyword = PPPaymentAdminEffectiveString(keyword);
        if (normalizedKeyword.length == 0) continue;
        NSString *wrappedKeyword = [NSString stringWithFormat:@"_%@_", normalizedKeyword];
        if ([normalizedStatus isEqualToString:normalizedKeyword] ||
            [normalizedStatus containsString:normalizedKeyword] ||
            [wrappedStatus containsString:wrappedKeyword]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isPaidLikeStatus:(NSString *)statusKey
{
    return [self status:statusKey matchesAnyKeywords:@[@"paid", @"success", @"approved", @"verified", @"processing", @"preparing", @"packed", @"shipped", @"delivery", @"delivered", @"fulfilled", @"completed"]];
}

+ (BOOL)isFailureLikeStatus:(NSString *)statusKey
{
    return [self status:statusKey matchesAnyKeywords:@[@"failed", @"rejected", @"declined", @"expired", @"voided", @"error"]];
}

+ (BOOL)isCancelledLikeStatus:(NSString *)statusKey
{
    return [self status:statusKey matchesAnyKeywords:@[@"cancelled", @"canceled"]];
}

+ (BOOL)isProcessingLikeStatus:(NSString *)statusKey
{
    return [self status:statusKey matchesAnyKeywords:@[@"processing", @"preparing", @"packed", @"confirmed"]];
}

+ (BOOL)isShippedLikeStatus:(NSString *)statusKey
{
    return [self status:statusKey matchesAnyKeywords:@[@"shipped", @"shipping", @"in_transit", @"out_for_delivery"]];
}

+ (BOOL)isDeliveredLikeStatus:(NSString *)statusKey
{
    return [self status:statusKey matchesAnyKeywords:@[@"delivered", @"fulfilled", @"completed"]];
}

+ (BOOL)requestStatusIsOpen:(NSString *)statusKey
{
    NSString *normalizedStatus = PPPaymentAdminEffectiveString(statusKey);
    if (normalizedStatus.length == 0) return YES;
    return ![@[@"rejected", @"completed", @"refunded", @"partially_refunded", @"cancelled", @"closed"] containsObject:normalizedStatus];
}

+ (BOOL)isFinalRequestStatus:(NSString *)statusKey
{
    return ![self requestStatusIsOpen:statusKey];
}

+ (BOOL)canApproveOrderStatus:(NSString *)statusKey
{
    NSString *normalizedStatus = PPPaymentAdminEffectiveString(statusKey);
    return ([normalizedStatus isEqualToString:@"pending"] ||
            [normalizedStatus isEqualToString:@"verification_pending"]);
}

+ (BOOL)canMarkOrderProcessingStatus:(NSString *)statusKey
{
    NSString *normalizedStatus = PPPaymentAdminEffectiveString(statusKey);
    if (normalizedStatus.length == 0) return NO;
    if ([self isCancelledLikeStatus:normalizedStatus] ||
        [self isFailureLikeStatus:normalizedStatus] ||
        [self isProcessingLikeStatus:normalizedStatus] ||
        [self isShippedLikeStatus:normalizedStatus] ||
        [self isDeliveredLikeStatus:normalizedStatus]) {
        return NO;
    }
    return [self orderHasCapturedPaymentForStatus:normalizedStatus
                                    transactionId:nil
                                            paidAt:nil];
}

+ (BOOL)canMarkOrderProcessingForOrder:(PPPaymentAdminRecord *)order
{
    if (!order) return NO;
    NSString *normalizedStatus = PPPaymentAdminEffectiveString(order.rawStatus);
    if (normalizedStatus.length == 0) return NO;
    if ([self isCancelledLikeStatus:normalizedStatus] ||
        [self isFailureLikeStatus:normalizedStatus] ||
        [self isProcessingLikeStatus:normalizedStatus] ||
        [self isShippedLikeStatus:normalizedStatus] ||
        [self isDeliveredLikeStatus:normalizedStatus]) {
        return NO;
    }
    if ([PPPaymentAdminEffectiveString(order.paymentMethodId) isEqualToString:@"cash"]) {
        return [normalizedStatus isEqualToString:@"pending"];
    }
    return ([PPPaymentAdminEffectiveString(order.paymentStatus) isEqualToString:@"paid"] ||
            [self orderHasCapturedPaymentForStatus:normalizedStatus
                                     transactionId:order.transactionId
                                             paidAt:order.paidAt]);
}

+ (BOOL)canMarkOrderShippedStatus:(NSString *)statusKey
{
    return [self isProcessingLikeStatus:statusKey];
}

+ (BOOL)canMarkOrderDeliveredStatus:(NSString *)statusKey
{
    return [self isShippedLikeStatus:statusKey];
}

+ (BOOL)canCancelOrderStatus:(NSString *)statusKey
{
    NSString *normalizedStatus = PPPaymentAdminEffectiveString(statusKey);
    if (normalizedStatus.length == 0) return YES;
    if ([self isCancelledLikeStatus:normalizedStatus]) return NO;
    if ([self isFailureLikeStatus:normalizedStatus]) return NO;
    if ([self isDeliveredLikeStatus:normalizedStatus]) return NO;
    if ([self isShippedLikeStatus:normalizedStatus]) return NO;
    return YES;
}

+ (BOOL)orderHasCapturedPaymentForStatus:(NSString *)statusKey
                           transactionId:(NSString *)transactionId
                                   paidAt:(NSDate *)paidAt
{
    return (PPPaymentAdminTrimmedString(transactionId).length > 0 ||
            [paidAt isKindOfClass:NSDate.class] ||
            [self isPaidLikeStatus:statusKey]);
}

+ (BOOL)canCollectCashPaymentForOrder:(PPPaymentAdminRecord *)order
{
    if (!order || ![PPPaymentAdminEffectiveString(order.paymentMethodId) isEqualToString:@"cash"]) {
        return NO;
    }
    if (![self isDeliveredLikeStatus:order.rawStatus] || [self isCancelledLikeStatus:order.rawStatus]) {
        return NO;
    }
    NSString *paymentStatus = PPPaymentAdminEffectiveString(order.paymentStatus);
    return ([paymentStatus isEqualToString:@"pending_collection"] ||
            [paymentStatus isEqualToString:@"pending"]);
}

+ (BOOL)canResolveRequest:(PPPaymentAdminSupportRequest *)request
                 withAction:(PPPaymentAdminRequestResolution)action
                     order:(PPPaymentAdminRecord *)order
{
    if (!request || !order) return NO;
    NSString *requestStatus = PPPaymentAdminEffectiveString(request.status);
    NSString *requestType = PPPaymentAdminEffectiveString(request.type);
    BOOL isRefundRequest = [requestType isEqualToString:@"refund"];
    BOOL isCompletableType = ([requestType isEqualToString:@"return"] ||
                              [requestType isEqualToString:@"replacement"] ||
                              [requestType isEqualToString:@"complaint"] ||
                              [requestType isEqualToString:@"support"]);
    switch (action) {
        case PPPaymentAdminRequestResolutionApprove:
            return [requestStatus isEqualToString:@"pending_review"];
        case PPPaymentAdminRequestResolutionReject:
            return [requestStatus isEqualToString:@"pending_review"];
        case PPPaymentAdminRequestResolutionComplete:
            return ([requestStatus isEqualToString:@"approved"] && isCompletableType);
        case PPPaymentAdminRequestResolutionRefund:
        case PPPaymentAdminRequestResolutionPartialRefund:
            return (([requestStatus isEqualToString:@"pending_review"] ||
                     [requestStatus isEqualToString:@"approved"]) &&
                    isRefundRequest &&
                    [self orderHasCapturedPaymentForStatus:order.rawStatus
                                             transactionId:order.transactionId
                                                     paidAt:order.paidAt]);
        case PPPaymentAdminRequestResolutionClose:
            return ([self isFinalRequestStatus:requestStatus] &&
                    ![requestStatus isEqualToString:@"closed"]);
    }
    return NO;
}

+ (NSArray<NSString *> *)quickStatusFilterKeys
{
    return @[@"all", @"pending", @"paid", @"processing", @"shipped", @"delivered", @"failed", @"cancelled", @"refunded"];
}

- (NSString *)workflowStatusKey
{
    if ([PPPaymentAdminRecord status:self.refundStatus matchesAnyKeywords:@[@"refunded", @"partially_refunded"]]) {
        return PPPaymentAdminEffectiveString(self.refundStatus);
    }
    if ([self hasRefundSignal]) {
        return @"refunded";
    }
    if ([PPPaymentAdminRecord isCancelledLikeStatus:self.rawStatus]) {
        return @"cancelled";
    }
    if ([PPPaymentAdminRecord isFailureLikeStatus:self.rawStatus]) {
        return @"failed";
    }
    if ([PPPaymentAdminRecord isDeliveredLikeStatus:self.rawStatus]) {
        return @"delivered";
    }
    if ([PPPaymentAdminRecord isShippedLikeStatus:self.rawStatus]) {
        return @"shipped";
    }
    if ([PPPaymentAdminRecord isProcessingLikeStatus:self.rawStatus]) {
        return @"processing";
    }
    if ([PPPaymentAdminEffectiveString(self.paymentStatus) isEqualToString:@"paid"] ||
        [PPPaymentAdminRecord orderHasCapturedPaymentForStatus:self.rawStatus
                                                 transactionId:self.transactionId
                                                         paidAt:self.paidAt]) {
        return @"paid";
    }
    return @"pending";
}

- (BOOL)matchesFilters:(PPPaymentManagementFilters *)filters
{
    PPPaymentManagementFilters *resolvedFilters = filters ?: [PPPaymentManagementFilters defaultFilters];
    NSString *statusFilter = PPPaymentAdminEffectiveString(resolvedFilters.statusKey);
    if (statusFilter.length > 0 && ![statusFilter isEqualToString:@"all"]) {
        NSString *workflowStatus = [self workflowStatusKey];
        if ([statusFilter isEqualToString:@"refunded"]) {
            if (![workflowStatus isEqualToString:@"refunded"] &&
                ![workflowStatus isEqualToString:@"partially_refunded"]) {
                return NO;
            }
        } else if (![workflowStatus isEqualToString:statusFilter]) {
            return NO;
        }
    }

    NSString *typeFilter = PPPaymentAdminEffectiveString(resolvedFilters.paymentTypeKey);
    if (typeFilter.length > 0 && ![typeFilter isEqualToString:@"all"]) {
        NSString *paymentType = PPPaymentAdminEffectiveString(self.paymentTypeKey);
        NSString *paymentProvider = PPPaymentAdminEffectiveString(self.paymentProvider);
        BOOL matched = ([paymentType isEqualToString:typeFilter] ||
                        [paymentProvider isEqualToString:typeFilter]);
        if (!matched) {
            return NO;
        }
    }

    NSDate *anchorDate = self.updatedAt ?: self.createdAt;
    if (![self pp_matchesDateRange:resolvedFilters.dateRange anchorDate:anchorDate]) {
        return NO;
    }

    return [self matchesSearchText:resolvedFilters.searchText ?: @""];
}

- (BOOL)matchesSearchText:(NSString *)searchText
{
    NSString *needle = PPPaymentAdminEffectiveString(searchText);
    if (needle.length == 0) return YES;

    NSArray<NSString *> *fields = @[
        PPPaymentAdminEffectiveString([self displayOrderReference]),
        PPPaymentAdminEffectiveString(self.orderId),
        PPPaymentAdminEffectiveString(self.orderNumber),
        PPPaymentAdminEffectiveString(self.userDisplayName),
        PPPaymentAdminEffectiveString(self.userEmail),
        PPPaymentAdminEffectiveString(self.paymentMethodId),
        PPPaymentAdminEffectiveString(self.paymentStatus),
        PPPaymentAdminEffectiveString(self.paymentProvider),
        PPPaymentAdminEffectiveString(self.paymentTypeKey),
        PPPaymentAdminEffectiveString(self.transactionId),
        PPPaymentAdminEffectiveString(self.latestRequestType),
        PPPaymentAdminEffectiveString(self.latestRequestStatus),
    ];
    for (NSString *field in fields) {
        if (field.length > 0 && [field containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)hasOpenRequests
{
    for (PPPaymentAdminSupportRequest *request in self.requests ?: @[]) {
        if ([request isOpen]) return YES;
    }
    return NO;
}

- (BOOL)hasRefundSignal
{
    if ([PPPaymentAdminRecord status:self.refundStatus matchesAnyKeywords:@[@"refunded", @"partially_refunded"]]) {
        return YES;
    }
    for (PPPaymentAdminSupportRequest *request in self.requests ?: @[]) {
        if ([request isRefundLike] &&
            ([PPPaymentAdminRecord status:request.status matchesAnyKeywords:@[@"refunded", @"partially_refunded"]] ||
             [PPPaymentAdminRecord status:request.finalResolution matchesAnyKeywords:@[@"refunded", @"partially_refunded"]])) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)hasReturnSignal
{
    if (self.returnStatus.length > 0) return YES;
    for (PPPaymentAdminSupportRequest *request in self.requests ?: @[]) {
        if ([request isReturnLike]) return YES;
    }
    return NO;
}

- (NSString *)displayOrderReference
{
    NSString *explicitNumber = PPPaymentAdminNormalizedPublicOrderNumberString(self.orderNumber);
    if (explicitNumber.length > 0) {
        return explicitNumber;
    }
    return PPPaymentAdminLegacyDisplayOrderReference(self.orderId);
}

- (void)applyRequestSummaries:(NSArray<PPPaymentAdminSupportRequest *> *)requests
{
    self.requests = requests ?: @[];
    NSString *latestRequestType = @"";
    NSString *latestRequestStatus = @"";
    NSString *resolvedRefundStatus = @"";
    NSString *resolvedReturnStatus = @"";
    NSDate *latestDate = nil;

    for (PPPaymentAdminSupportRequest *request in self.requests) {
        NSDate *requestDate = request.updatedAt ?: request.createdAt;
        if (!latestDate || [requestDate compare:latestDate] == NSOrderedDescending) {
            latestDate = requestDate;
            latestRequestType = PPPaymentAdminEffectiveString(request.type);
            latestRequestStatus = PPPaymentAdminEffectiveString(request.status);
        }

        NSString *effectiveResolution = [request effectiveResolutionKey];
        if ([request isRefundLike] && effectiveResolution.length > 0) {
            resolvedRefundStatus = effectiveResolution;
        }
        if ([request isReturnLike] && effectiveResolution.length > 0) {
            resolvedReturnStatus = effectiveResolution;
        }
    }

    if (latestRequestType.length > 0) self.latestRequestType = latestRequestType;
    if (latestRequestStatus.length > 0) self.latestRequestStatus = latestRequestStatus;
    if (resolvedRefundStatus.length > 0) self.refundStatus = resolvedRefundStatus;
    if (resolvedReturnStatus.length > 0) self.returnStatus = resolvedReturnStatus;
}

- (BOOL)pp_matchesDateRange:(PPPaymentAdminDateRange)dateRange anchorDate:(NSDate *)anchorDate
{
    if (dateRange == PPPaymentAdminDateRangeAll || ![anchorDate isKindOfClass:NSDate.class]) {
        return YES;
    }

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDate *startOfToday = nil;
    [calendar rangeOfUnit:NSCalendarUnitDay startDate:&startOfToday interval:NULL forDate:now];

    switch (dateRange) {
        case PPPaymentAdminDateRangeToday:
            return ([anchorDate compare:startOfToday] != NSOrderedAscending);

        case PPPaymentAdminDateRangeLast7Days:
        case PPPaymentAdminDateRangeLast30Days:
        case PPPaymentAdminDateRangeLast90Days: {
            NSInteger dayCount = 7;
            if (dateRange == PPPaymentAdminDateRangeLast30Days) dayCount = 30;
            if (dateRange == PPPaymentAdminDateRangeLast90Days) dayCount = 90;
            NSDate *floorDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:-dayCount toDate:now options:0];
            return ([anchorDate compare:floorDate] != NSOrderedAscending);
        }

        case PPPaymentAdminDateRangeAll:
            break;
    }
    return YES;
}

@end
