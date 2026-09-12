//
//  LivePetReturnCommandFactory.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Deterministic idempotent command builder with stable payload fingerprints.
//

import Foundation
import CryptoKit

public struct LivePetReturnCommand {
    public let commandId: String
    public let fingerprint: String
    public let transactionId: String
    public let receivingBranchId: String
    public let units: [LivePetReturnUnit]
    public let refundAmountMinor: Int64
    public let refundAmount: Double
    public let reason: String
    public let refundAdjustmentReason: String?
    public let financialResolution: FinancialResolution
    public let currency: String

    public func buildRefundItemsPayload() -> [[String: Any]] {
        // Group units by productId
        var unitsByProduct: [String: [LivePetReturnUnit]] = [:]
        for unit in units {
            unitsByProduct[unit.productId, default: []].append(unit)
        }

        var payload: [[String: Any]] = []
        for (productId, pUnits) in unitsByProduct {
            let unitIds = pUnits.map { $0.unitId }
            let unitPrices = pUnits.map { [
                "unitId": $0.unitId,
                "unitPrice": $0.originalSalePriceMajor
            ] }

            let primaryUnit = pUnits.first!
            let cond = primaryUnit.conditionAtReturn.rawValue
            let disp = primaryUnit.disposition.rawValue
            let reasonCode = cond == "appears_normal" ? "customer_return_sellable" : "customer_return_\(cond)"

            let itemDict: [String: Any] = [
                "productId": productId,
                "quantity": pUnits.count,
                "unitIds": unitIds,
                "unitPrices": unitPrices,
                "refundAmount": pUnits.reduce(0.0) { $0 + $1.refundAmountMajor },
                "condition": cond,
                "disposition": disp,
                "reasonCode": reasonCode,
                "notes": primaryUnit.notes ?? reason
            ]
            payload.append(itemDict)
        }
        payload.sort { ($0["productId"] as? String ?? "") < ($1["productId"] as? String ?? "") }
        return payload
    }
}

public final class LivePetReturnCommandFactory: @unchecked Sendable {
    public static let shared = LivePetReturnCommandFactory()

    private init() {}

    public func createCommand(
        transactionId: String,
        receivingBranchId: String,
        units: [LivePetReturnUnit],
        reason: String,
        financialResolution: FinancialResolution = .fullRefund,
        currency: String = "QAR",
        refundAdjustmentReason: String? = nil,
        existingCommandId: String? = nil
    ) -> LivePetReturnCommand {
        let commandId = existingCommandId ?? "pos-livepet-return-\(UUID().uuidString)"
        let refundAmountMinor = units.reduce(Int64(0)) { $0 + $1.refundAmountMinor }
        let refundAmount = Double(refundAmountMinor) / LivePetMoney.scaleFactor(for: currency)

        // Compute stable SHA256 fingerprint of critical parameters
        let unitIdsSorted = units.map { $0.unitId }.sorted().joined(separator: ",")
        let adjustment = refundAdjustmentReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawFingerprint = "\(transactionId):\(receivingBranchId):\(unitIdsSorted):\(refundAmountMinor):\(financialResolution.rawValue):\(currency):\(reason):\(adjustment)"
        let digest = SHA256.hash(data: Data(rawFingerprint.utf8))
        let fingerprintString = digest.compactMap { String(format: "%02x", $0) }.joined()

        return LivePetReturnCommand(
            commandId: commandId,
            fingerprint: fingerprintString,
            transactionId: transactionId,
            receivingBranchId: receivingBranchId,
            units: units,
            refundAmountMinor: refundAmountMinor,
            refundAmount: refundAmount,
            reason: reason,
            refundAdjustmentReason: refundAdjustmentReason,
            financialResolution: financialResolution,
            currency: currency
        )
    }
}
