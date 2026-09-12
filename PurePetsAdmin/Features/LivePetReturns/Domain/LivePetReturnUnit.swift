//
//  LivePetReturnUnit.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Exact-unit identity model preserving individual animal facts from sale to return.
//

import Foundation

public struct LivePetReturnUnit: Identifiable, Codable, Hashable, Sendable {
    public let unitId: String
    public let productId: String
    public let productName: String
    public let ringTag: String

    public var speciesName: String?
    public var breedName: String?
    public var sex: String?

    public let originalSaleTransactionId: String
    public let originalSalePriceMinor: Int64
    public let allocatedDiscountMinor: Int64
    public let netPaidMinor: Int64
    public var refundableRemainingMinor: Int64 {
        didSet {
            refundableRemainingMinor = max(0, min(refundableRemainingMinor, netPaidMinor))
            if refundAmountMinor > refundableRemainingMinor {
                refundAmountMinor = refundableRemainingMinor
            }
        }
    }
    public var refundAmountMinor: Int64 {
        didSet {
            refundAmountMinor = max(0, min(refundAmountMinor, refundableRemainingMinor))
        }
    }
    public let currency: String

    public var conditionAtReturn: ReturnPhysicalCondition
    public var inspectionStatus: HealthDisposition
    public var disposition: CommercialDisposition

    public var previousLifecycleStatus: LivePetLifecycleStatus
    public var resultingLifecycleStatus: LivePetLifecycleStatus

    public var isAlreadyReturned: Bool
    public var activeReturnCaseId: String?
    public var activeReturnCaseNumber: String?
    public var notes: String?

    public var id: String { unitId }

    public init(
        unitId: String,
        productId: String,
        productName: String,
        ringTag: String,
        speciesName: String? = nil,
        breedName: String? = nil,
        sex: String? = nil,
        originalSaleTransactionId: String,
        originalSalePriceMinor: Int64,
        allocatedDiscountMinor: Int64 = 0,
        refundableRemainingMinor: Int64? = nil,
        refundAmountMinor: Int64? = nil,
        currency: String = "QAR",
        conditionAtReturn: ReturnPhysicalCondition = .appearsNormal,
        inspectionStatus: HealthDisposition = .inspectionRequired,
        disposition: CommercialDisposition = .hold,
        previousLifecycleStatus: LivePetLifecycleStatus = .sold,
        resultingLifecycleStatus: LivePetLifecycleStatus = .returnRequested,
        isAlreadyReturned: Bool = false,
        activeReturnCaseId: String? = nil,
        activeReturnCaseNumber: String? = nil,
        notes: String? = nil
    ) {
        self.unitId = unitId
        self.productId = productId
        self.productName = productName
        self.ringTag = ringTag
        self.speciesName = speciesName
        self.breedName = breedName
        self.sex = sex
        self.originalSaleTransactionId = originalSaleTransactionId
        let normalizedPrice = max(0, originalSalePriceMinor)
        let normalizedDiscount = max(0, min(allocatedDiscountMinor, normalizedPrice))
        self.originalSalePriceMinor = normalizedPrice
        self.allocatedDiscountMinor = normalizedDiscount

        let calculatedNet = normalizedPrice - normalizedDiscount
        self.netPaidMinor = calculatedNet
        let remaining = max(0, min(refundableRemainingMinor ?? calculatedNet, calculatedNet))
        self.refundableRemainingMinor = remaining
        self.refundAmountMinor = min(max(0, refundAmountMinor ?? remaining), remaining)
        self.currency = currency

        self.conditionAtReturn = conditionAtReturn
        self.inspectionStatus = inspectionStatus
        self.disposition = disposition
        self.previousLifecycleStatus = previousLifecycleStatus
        self.resultingLifecycleStatus = resultingLifecycleStatus
        self.isAlreadyReturned = isAlreadyReturned
        self.activeReturnCaseId = activeReturnCaseId
        self.activeReturnCaseNumber = activeReturnCaseNumber
        self.notes = notes
    }

    public var originalSalePriceMajor: Double {
        let divisor = pow(10.0, Double(LivePetMoney.minorUnitScale(for: currency)))
        return Double(originalSalePriceMinor) / divisor
    }

    public var netPaidMajor: Double {
        let divisor = pow(10.0, Double(LivePetMoney.minorUnitScale(for: currency)))
        return Double(netPaidMinor) / divisor
    }

    public var refundAmountMajor: Double {
        let divisor = pow(10.0, Double(LivePetMoney.minorUnitScale(for: currency)))
        return Double(refundAmountMinor) / divisor
    }

    public var displayIdentification: String {
        let tag = ringTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty && tag != unitId {
            return "\(tag) (\(unitId.prefix(8)))"
        }
        return unitId
    }

    // MARK: - Codable Implementation with Strict Invariant Protection

    private enum CodingKeys: String, CodingKey {
        case unitId
        case productId
        case productName
        case ringTag
        case speciesName
        case breedName
        case sex
        case originalSaleTransactionId
        case originalSalePriceMinor
        case allocatedDiscountMinor
        case netPaidMinor
        case refundableRemainingMinor
        case refundAmountMinor
        case currency
        case conditionAtReturn
        case inspectionStatus
        case disposition
        case previousLifecycleStatus
        case resultingLifecycleStatus
        case isAlreadyReturned
        case activeReturnCaseId
        case activeReturnCaseNumber
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let unitId = try container.decode(String.self, forKey: .unitId)
        let productId = try container.decode(String.self, forKey: .productId)
        let productName = try container.decode(String.self, forKey: .productName)
        let ringTag = try container.decode(String.self, forKey: .ringTag)
        let speciesName = try container.decodeIfPresent(String.self, forKey: .speciesName)
        let breedName = try container.decodeIfPresent(String.self, forKey: .breedName)
        let sex = try container.decodeIfPresent(String.self, forKey: .sex)
        let originalSaleTransactionId = try container.decode(String.self, forKey: .originalSaleTransactionId)
        let originalSalePriceMinor = try container.decode(Int64.self, forKey: .originalSalePriceMinor)
        let allocatedDiscountMinor = try container.decodeIfPresent(Int64.self, forKey: .allocatedDiscountMinor) ?? 0
        let refundableRemainingMinor = try container.decodeIfPresent(Int64.self, forKey: .refundableRemainingMinor)
        let refundAmountMinor = try container.decodeIfPresent(Int64.self, forKey: .refundAmountMinor)
        let currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "QAR"
        let conditionAtReturn = try container.decodeIfPresent(ReturnPhysicalCondition.self, forKey: .conditionAtReturn) ?? .appearsNormal
        let inspectionStatus = try container.decodeIfPresent(HealthDisposition.self, forKey: .inspectionStatus) ?? .inspectionRequired
        let disposition = try container.decodeIfPresent(CommercialDisposition.self, forKey: .disposition) ?? .hold
        let previousLifecycleStatus = try container.decodeIfPresent(LivePetLifecycleStatus.self, forKey: .previousLifecycleStatus) ?? .sold
        let resultingLifecycleStatus = try container.decodeIfPresent(LivePetLifecycleStatus.self, forKey: .resultingLifecycleStatus) ?? .returnRequested
        let isAlreadyReturned = try container.decodeIfPresent(Bool.self, forKey: .isAlreadyReturned) ?? false
        let activeReturnCaseId = try container.decodeIfPresent(String.self, forKey: .activeReturnCaseId)
        let activeReturnCaseNumber = try container.decodeIfPresent(String.self, forKey: .activeReturnCaseNumber)
        let notes = try container.decodeIfPresent(String.self, forKey: .notes)

        self.init(
            unitId: unitId,
            productId: productId,
            productName: productName,
            ringTag: ringTag,
            speciesName: speciesName,
            breedName: breedName,
            sex: sex,
            originalSaleTransactionId: originalSaleTransactionId,
            originalSalePriceMinor: originalSalePriceMinor,
            allocatedDiscountMinor: allocatedDiscountMinor,
            refundableRemainingMinor: refundableRemainingMinor,
            refundAmountMinor: refundAmountMinor,
            currency: currency,
            conditionAtReturn: conditionAtReturn,
            inspectionStatus: inspectionStatus,
            disposition: disposition,
            previousLifecycleStatus: previousLifecycleStatus,
            resultingLifecycleStatus: resultingLifecycleStatus,
            isAlreadyReturned: isAlreadyReturned,
            activeReturnCaseId: activeReturnCaseId,
            activeReturnCaseNumber: activeReturnCaseNumber,
            notes: notes
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(unitId, forKey: .unitId)
        try container.encode(productId, forKey: .productId)
        try container.encode(productName, forKey: .productName)
        try container.encode(ringTag, forKey: .ringTag)
        try container.encodeIfPresent(speciesName, forKey: .speciesName)
        try container.encodeIfPresent(breedName, forKey: .breedName)
        try container.encodeIfPresent(sex, forKey: .sex)
        try container.encode(originalSaleTransactionId, forKey: .originalSaleTransactionId)
        try container.encode(originalSalePriceMinor, forKey: .originalSalePriceMinor)
        try container.encode(allocatedDiscountMinor, forKey: .allocatedDiscountMinor)
        try container.encode(netPaidMinor, forKey: .netPaidMinor)
        let safeRemaining = max(0, min(refundableRemainingMinor, netPaidMinor))
        let safeRefund = max(0, min(refundAmountMinor, safeRemaining))
        try container.encode(safeRemaining, forKey: .refundableRemainingMinor)
        try container.encode(safeRefund, forKey: .refundAmountMinor)
        try container.encode(currency, forKey: .currency)
        try container.encode(conditionAtReturn, forKey: .conditionAtReturn)
        try container.encode(inspectionStatus, forKey: .inspectionStatus)
        try container.encode(disposition, forKey: .disposition)
        try container.encode(previousLifecycleStatus, forKey: .previousLifecycleStatus)
        try container.encode(resultingLifecycleStatus, forKey: .resultingLifecycleStatus)
        try container.encode(isAlreadyReturned, forKey: .isAlreadyReturned)
        try container.encodeIfPresent(activeReturnCaseId, forKey: .activeReturnCaseId)
        try container.encodeIfPresent(activeReturnCaseNumber, forKey: .activeReturnCaseNumber)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    public func toDictionary() -> [String: Any] {
        let safeRemaining = max(0, min(refundableRemainingMinor, netPaidMinor))
        let safeRefund = max(0, min(refundAmountMinor, safeRemaining))

        var dict: [String: Any] = [
            "unitId": unitId,
            "productId": productId,
            "productName": productName,
            "ringTag": ringTag,
            "originalSaleTransactionId": originalSaleTransactionId,
            "originalSalePriceMinor": originalSalePriceMinor,
            "allocatedDiscountMinor": allocatedDiscountMinor,
            "netPaidMinor": netPaidMinor,
            "refundableRemainingMinor": safeRemaining,
            "refundAmountMinor": safeRefund,
            "currency": currency,
            "conditionAtReturn": conditionAtReturn.rawValue,
            "inspectionStatus": inspectionStatus.rawValue,
            "disposition": disposition.rawValue,
            "previousLifecycleStatus": previousLifecycleStatus.rawValue,
            "resultingLifecycleStatus": resultingLifecycleStatus.rawValue,
            "isAlreadyReturned": isAlreadyReturned
        ]
        if let speciesName { dict["speciesName"] = speciesName }
        if let breedName { dict["breedName"] = breedName }
        if let sex { dict["sex"] = sex }
        if let activeReturnCaseId { dict["activeReturnCaseId"] = activeReturnCaseId }
        if let activeReturnCaseNumber { dict["activeReturnCaseNumber"] = activeReturnCaseNumber }
        if let notes { dict["notes"] = notes }
        return dict
    }

    public static func fromDictionary(_ dict: [String: Any]) -> LivePetReturnUnit? {
        guard let unitId = dict["unitId"] as? String, !unitId.isEmpty,
              let productId = dict["productId"] as? String, !productId.isEmpty else {
            return nil
        }

        let productName = (dict["productName"] as? String) ?? (dict["name"] as? String) ?? ""
        let ringTag = (dict["ringTag"] as? String) ?? unitId
        let originalSaleTxnId = (dict["originalSaleTransactionId"] as? String) ?? (dict["transactionId"] as? String) ?? ""
        let currencyStr = (dict["currency"] as? String) ?? "QAR"
        let scaleFactor = pow(10.0, Double(LivePetMoney.minorUnitScale(for: currencyStr)))
        let originalPriceMinor = (dict["originalSalePriceMinor"] as? Int64)
            ?? (dict["originalSalePriceMinor"] as? Int).map { Int64($0) }
            ?? Int64(round(((dict["price"] as? Double) ?? (dict["sellingPrice"] as? Double) ?? 0.0) * scaleFactor))

        let discountMinor = (dict["allocatedDiscountMinor"] as? Int64)
            ?? (dict["allocatedDiscountMinor"] as? Int).map { Int64($0) } ?? 0

        let condStr = (dict["conditionAtReturn"] as? String) ?? (dict["condition"] as? String) ?? ""
        let condition = ReturnPhysicalCondition(rawValue: condStr) ?? .appearsNormal

        let inspStr = (dict["inspectionStatus"] as? String) ?? ""
        let inspection = HealthDisposition(rawValue: inspStr) ?? .inspectionRequired

        let dispStr = (dict["disposition"] as? String) ?? ""
        let disposition = CommercialDisposition(rawValue: dispStr) ?? .hold

        let prevStr = (dict["previousLifecycleStatus"] as? String) ?? "sold"
        let prevStatus = LivePetLifecycleStatus(rawValue: prevStr) ?? .sold

        let resultStr = (dict["resultingLifecycleStatus"] as? String) ?? "return_requested"
        let resultStatus = LivePetLifecycleStatus(rawValue: resultStr) ?? .returnRequested

        let alreadyReturned = (dict["isAlreadyReturned"] as? Bool) ?? false
        let activeReturnCaseId = (dict["activeReturnCaseId"] as? String) ?? (dict["activeReturnCase"] as? String)
        let activeReturnCaseNumber = dict["activeReturnCaseNumber"] as? String
        let notes = dict["notes"] as? String

        return LivePetReturnUnit(
            unitId: unitId,
            productId: productId,
            productName: productName,
            ringTag: ringTag,
            speciesName: dict["speciesName"] as? String,
            breedName: dict["breedName"] as? String,
            sex: dict["sex"] as? String,
            originalSaleTransactionId: originalSaleTxnId,
            originalSalePriceMinor: originalPriceMinor,
            allocatedDiscountMinor: discountMinor,
            refundableRemainingMinor: (dict["refundableRemainingMinor"] as? Int64) ?? (dict["refundableRemainingMinor"] as? Int).map { Int64($0) },
            refundAmountMinor: (dict["refundAmountMinor"] as? Int64) ?? (dict["refundAmountMinor"] as? Int).map { Int64($0) },
            currency: (dict["currency"] as? String) ?? "QAR",
            conditionAtReturn: condition,
            inspectionStatus: inspection,
            disposition: disposition,
            previousLifecycleStatus: prevStatus,
            resultingLifecycleStatus: resultStatus,
            isAlreadyReturned: alreadyReturned,
            activeReturnCaseId: activeReturnCaseId,
            activeReturnCaseNumber: activeReturnCaseNumber,
            notes: notes
        )
    }
}
