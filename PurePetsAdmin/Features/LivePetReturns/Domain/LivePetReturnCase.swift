//
//  LivePetReturnCase.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  ReturnCase Aggregate Root managing exact animal return state, custody, and refund.
//

import Foundation
import FirebaseFirestore

public struct LivePetReturnCase: Identifiable, Codable, Hashable, Sendable {
    public let returnCaseId: String
    public let caseNumber: String
    public let transactionId: String
    public let originalBranchId: String
    public var receivingBranchId: String

    public var customerId: String?
    public var customerName: String?
    public var customerPhone: String?

    public var status: ReturnCaseStatus
    public var units: [LivePetReturnUnit]

    public var reasonCode: String
    public var reasonNotes: String

    public var financialResolution: FinancialResolution
    public var refundStatus: LivePetRefundStatus
    public var totalRefundAmountMinor: Int64
    public var currency: String

    public let createdAt: Date
    public let createdBy: String
    public var receivedAt: Date?
    public var receivedBy: String?
    public var approvedAt: Date?
    public var approvedBy: String?
    public var completedAt: Date?

    public var version: Int
    public var events: [LivePetReturnEvent]

    public var id: String { returnCaseId }

    public init(
        returnCaseId: String,
        caseNumber: String,
        transactionId: String,
        originalBranchId: String,
        receivingBranchId: String,
        customerId: String? = nil,
        customerName: String? = nil,
        customerPhone: String? = nil,
        status: ReturnCaseStatus = .draft,
        units: [LivePetReturnUnit] = [],
        reasonCode: String = "customer_return",
        reasonNotes: String = "",
        financialResolution: FinancialResolution = .fullRefund,
        refundStatus: LivePetRefundStatus = .notRequested,
        totalRefundAmountMinor: Int64? = nil,
        currency: String = "QAR",
        createdAt: Date = Date(),
        createdBy: String,
        receivedAt: Date? = nil,
        receivedBy: String? = nil,
        approvedAt: Date? = nil,
        approvedBy: String? = nil,
        completedAt: Date? = nil,
        version: Int = 1,
        events: [LivePetReturnEvent] = []
    ) {
        self.returnCaseId = returnCaseId
        self.caseNumber = caseNumber
        self.transactionId = transactionId
        self.originalBranchId = originalBranchId
        self.receivingBranchId = receivingBranchId
        self.customerId = customerId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.status = status
        self.units = units
        self.reasonCode = reasonCode
        self.reasonNotes = reasonNotes
        self.financialResolution = financialResolution
        self.refundStatus = refundStatus
        self.totalRefundAmountMinor = totalRefundAmountMinor ?? units.reduce(0) { $0 + $1.refundAmountMinor }
        self.currency = currency
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.receivedAt = receivedAt
        self.receivedBy = receivedBy
        self.approvedAt = approvedAt
        self.approvedBy = approvedBy
        self.completedAt = completedAt
        self.version = version
        self.events = events
    }

    public var totalRefundAmountMajor: Double {
        Double(totalRefundAmountMinor) / 100.0
    }

    public var isCrossBranchReturn: Bool {
        !originalBranchId.isEmpty && !receivingBranchId.isEmpty && originalBranchId != receivingBranchId
    }

    public var activeUnitCount: Int {
        units.count
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "returnCaseId": returnCaseId,
            "caseNumber": caseNumber,
            "transactionId": transactionId,
            "originalBranchId": originalBranchId,
            "receivingBranchId": receivingBranchId,
            "status": status.rawValue,
            "reasonCode": reasonCode,
            "reasonNotes": reasonNotes,
            "financialResolution": financialResolution.rawValue,
            "refundStatus": refundStatus.rawValue,
            "totalRefundAmountMinor": totalRefundAmountMinor,
            "currency": currency,
            "createdAt": createdAt,
            "createdBy": createdBy,
            "version": version
        ]
        if let customerId { dict["customerId"] = customerId }
        if let customerName { dict["customerName"] = customerName }
        if let customerPhone { dict["customerPhone"] = customerPhone }
        if let receivedAt { dict["receivedAt"] = receivedAt }
        if let receivedBy { dict["receivedBy"] = receivedBy }
        if let approvedAt { dict["approvedAt"] = approvedAt }
        if let approvedBy { dict["approvedBy"] = approvedBy }
        if let completedAt { dict["completedAt"] = completedAt }
        return dict
    }

    public static func fromDictionary(_ dict: [String: Any], returnCaseId: String, units: [LivePetReturnUnit] = [], events: [LivePetReturnEvent] = []) -> LivePetReturnCase? {
        guard let transactionId = dict["transactionId"] as? String else {
            return nil
        }

        let caseNumber = (dict["caseNumber"] as? String) ?? "RTN-\(returnCaseId.prefix(8).uppercased())"
        let origBranch = (dict["originalBranchId"] as? String) ?? (dict["branchId"] as? String) ?? ""
        let recvBranch = (dict["receivingBranchId"] as? String) ?? origBranch

        let statusStr = (dict["status"] as? String) ?? "draft"
        let status = ReturnCaseStatus(rawValue: statusStr) ?? .draft

        let finStr = (dict["financialResolution"] as? String) ?? "full_refund"
        let financialResolution = FinancialResolution(rawValue: finStr) ?? .fullRefund

        let refStr = (dict["refundStatus"] as? String) ?? "not_requested"
        let refundStatus = LivePetRefundStatus(rawValue: refStr) ?? .notRequested

        let totalMinor = (dict["totalRefundAmountMinor"] as? Int64)
            ?? (dict["totalRefundAmountMinor"] as? Int).map { Int64($0) }
            ?? Int64(round(((dict["refundAmount"] as? Double) ?? 0.0) * 100.0))

        let createdBy = (dict["createdBy"] as? String) ?? (dict["actorId"] as? String) ?? ""
        let parseDate: (Any?) -> Date? = { val in
            if let d = val as? Date { return d }
            if let ts = val as? Timestamp { return ts.dateValue() }
            if let sec = val as? Double { return Date(timeIntervalSince1970: sec) }
            return nil
        }
        let createdAt = parseDate(dict["createdAt"]) ?? Date()

        return LivePetReturnCase(
            returnCaseId: returnCaseId,
            caseNumber: caseNumber,
            transactionId: transactionId,
            originalBranchId: origBranch,
            receivingBranchId: recvBranch,
            customerId: dict["customerId"] as? String,
            customerName: dict["customerName"] as? String,
            customerPhone: dict["customerPhone"] as? String,
            status: status,
            units: units,
            reasonCode: (dict["reasonCode"] as? String) ?? "customer_return",
            reasonNotes: (dict["reasonNotes"] as? String) ?? (dict["notes"] as? String) ?? "",
            financialResolution: financialResolution,
            refundStatus: refundStatus,
            totalRefundAmountMinor: totalMinor,
            currency: (dict["currency"] as? String) ?? "QAR",
            createdAt: createdAt,
            createdBy: createdBy,
            receivedAt: parseDate(dict["receivedAt"]),
            receivedBy: dict["receivedBy"] as? String,
            approvedAt: parseDate(dict["approvedAt"]),
            approvedBy: dict["approvedBy"] as? String,
            completedAt: parseDate(dict["completedAt"]),
            version: (dict["version"] as? Int) ?? 1,
            events: events
        )
    }
}
