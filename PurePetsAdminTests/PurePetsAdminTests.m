//
//  PurePetsAdminTests.m
//  PurePetsAdminTests
//
//  Created by Mohammed Ahmed on 20/08/2025.
//

#import <XCTest/XCTest.h>
#import "PPPaymentManagementModels.h"
#import "PPStaffAuth.h"

@interface PurePetsAdminTests : XCTestCase

@end

@implementation PurePetsAdminTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testExample {
    PPPaymentAdminRecord *record = [PPPaymentAdminRecord recordFromDictionary:@{
        @"orderId": @"order_1",
        @"status": @"paid",
        @"refundStatus": @"",
        @"totalAmount": @100,
        @"currency": @"QAR"
    } documentID:@"order_1"];

    XCTAssertEqualObjects([record workflowStatusKey], @"paid");
}

- (void)testWorkflowStatusPrefersRefundSignals {
    PPPaymentAdminRecord *record = [PPPaymentAdminRecord recordFromDictionary:@{
        @"orderId": @"order_2",
        @"status": @"paid",
        @"totalAmount": @120,
        @"currency": @"QAR"
    } documentID:@"order_2"];

    PPPaymentAdminSupportRequest *refundRequest = [PPPaymentAdminSupportRequest requestFromDictionary:@{
        @"requestId": @"req_1",
        @"type": @"refund",
        @"status": @"refunded",
        @"finalResolution": @"refunded"
    } documentID:@"req_1"];

    [record applyRequestSummaries:@[refundRequest]];
    XCTAssertEqualObjects([record workflowStatusKey], @"refunded");
}

- (void)testCanApproveOnlyPendingOrders {
    XCTAssertTrue([PPPaymentAdminRecord canApproveOrderStatus:@"pending"]);
    XCTAssertTrue([PPPaymentAdminRecord canApproveOrderStatus:@"verification_pending"]);
    XCTAssertFalse([PPPaymentAdminRecord canApproveOrderStatus:@"paid"]);
    XCTAssertFalse([PPPaymentAdminRecord canApproveOrderStatus:@"cancelled"]);
}

- (void)testRefundResolutionRequiresRefundRequestType {
    PPPaymentAdminRecord *order = [PPPaymentAdminRecord recordFromDictionary:@{
        @"orderId": @"order_3",
        @"status": @"paid",
        @"transactionId": @"txn_1",
        @"paidAt": [NSDate date],
        @"totalAmount": @200
    } documentID:@"order_3"];

    PPPaymentAdminSupportRequest *complaintRequest = [PPPaymentAdminSupportRequest requestFromDictionary:@{
        @"requestId": @"req_2",
        @"type": @"complaint",
        @"status": @"approved"
    } documentID:@"req_2"];

    XCTAssertFalse([PPPaymentAdminRecord canResolveRequest:complaintRequest
                                                withAction:PPPaymentAdminRequestResolutionRefund
                                                    order:order]);
    XCTAssertFalse([PPPaymentAdminRecord canResolveRequest:complaintRequest
                                                withAction:PPPaymentAdminRequestResolutionPartialRefund
                                                    order:order]);
}

- (void)testCompleteResolutionAllowsReturnRequestsOnlyAfterApproval {
    PPPaymentAdminRecord *order = [PPPaymentAdminRecord recordFromDictionary:@{
        @"orderId": @"order_4",
        @"status": @"paid",
        @"transactionId": @"txn_4",
        @"paidAt": [NSDate date],
        @"totalAmount": @90
    } documentID:@"order_4"];

    PPPaymentAdminSupportRequest *returnPending = [PPPaymentAdminSupportRequest requestFromDictionary:@{
        @"requestId": @"req_3",
        @"type": @"return",
        @"status": @"pending_review"
    } documentID:@"req_3"];
    PPPaymentAdminSupportRequest *returnApproved = [PPPaymentAdminSupportRequest requestFromDictionary:@{
        @"requestId": @"req_4",
        @"type": @"return",
        @"status": @"approved"
    } documentID:@"req_4"];
    PPPaymentAdminSupportRequest *refundApproved = [PPPaymentAdminSupportRequest requestFromDictionary:@{
        @"requestId": @"req_5",
        @"type": @"refund",
        @"status": @"approved"
    } documentID:@"req_5"];

    XCTAssertFalse([PPPaymentAdminRecord canResolveRequest:returnPending
                                                withAction:PPPaymentAdminRequestResolutionComplete
                                                    order:order]);
    XCTAssertTrue([PPPaymentAdminRecord canResolveRequest:returnApproved
                                               withAction:PPPaymentAdminRequestResolutionComplete
                                                   order:order]);
    XCTAssertFalse([PPPaymentAdminRecord canResolveRequest:refundApproved
                                                withAction:PPPaymentAdminRequestResolutionComplete
                                                    order:order]);
}

- (void)testRoleOnlyCanonicalStaffRecordUsesInfraDefaults {
    PPStaffDoc *staff = [[PPStaffDoc alloc] initWithDictionary:@{
        @"status": @"active",
        @"role": @"payments_manager"
    } uid:@"staff_1"];

    XCTAssertTrue(staff.canAccessStaffWorkspace);
    XCTAssertTrue([staff hasPermission:kStaffPermPaymentsView]);
    XCTAssertTrue([staff hasPermission:kStaffPermPosHistory]);
    XCTAssertFalse([staff hasPermission:kStaffPermStockManage]);
}

- (void)testDisabledCanonicalStaffRecordCannotAuthorize {
    PPStaffDoc *staff = [[PPStaffDoc alloc] initWithDictionary:@{
        @"status": @"disabled",
        @"role": @"owner"
    } uid:@"staff_2"];

    XCTAssertFalse(staff.isActive);
    XCTAssertFalse(staff.canAccessStaffWorkspace);
    XCTAssertFalse([staff hasPermission:kStaffPermPaymentsView]);
}

- (void)testUnknownCanonicalRoleFallsBackToViewerWithoutDroppingExplicitPermission {
    PPStaffDoc *staff = [[PPStaffDoc alloc] initWithDictionary:@{
        @"status": @"active",
        @"role": @"custom_operations_label",
        @"permissions": @[kStaffPermDashboardView, kStaffPermSupportView]
    } uid:@"staff_3"];

    XCTAssertEqualObjects(staff.role, PPStaffRoleViewer);
    XCTAssertTrue([staff hasPermission:kStaffPermSupportView]);
    XCTAssertFalse([staff hasPermission:kStaffPermPaymentsManage]);
}

@end
