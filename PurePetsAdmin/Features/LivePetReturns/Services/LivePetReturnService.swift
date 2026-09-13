//
//  LivePetReturnService.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Domain business service orchestrating exact-unit returns, permissions, and refund settlement.
//

import Foundation

public final class LivePetReturnService: @unchecked Sendable {
    public static let shared = LivePetReturnService()

    private let repository = LivePetReturnRepository.shared
    private let commandFactory = LivePetReturnCommandFactory.shared
    private let recoveryService = LivePetReturnRecoveryService.shared
    private let draftStore = LivePetReturnDraftStore.shared

    private init() {}

    // MARK: - Permissions Check

    public func canCreateReturn() -> Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        return staff.hasPermission("returns.live_pet.create") ||
               staff.isAdmin()
    }

    public func canRefundPayment() -> Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        return staff.hasPermission(kStaffPermPaymentsRefund) ||
               staff.hasPermission("payments.refund") ||
               staff.isAdmin()
    }

    public func canInspectOrClear() -> Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        return staff.hasPermission("returns.live_pet.inspect") ||
               staff.isAdmin()
    }

    public func canClearForResale() -> Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        return staff.hasPermission("returns.live_pet.clear_for_resale") || staff.isAdmin()
    }

    // MARK: - Execute Return & Refund

    public func processLivePetReturn(
        transaction: PPPOSReceipt,
        selectedUnits: [LivePetReturnUnit],
        receivingBranchId: String,
        reason: String,
        financialResolution: FinancialResolution = .fullRefund,
        refundAdjustmentReason: String? = nil,
        draftId: String? = nil
    ) async throws -> LivePetReturnCase {
        guard canCreateReturn() else {
            throw NSError(domain: "LivePetReturn", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "You lack authorization to process live pet returns (returns.live_pet.create)."
            ])
        }

        guard !selectedUnits.isEmpty else {
            throw NSError(domain: "LivePetReturn", code: 400, userInfo: [NSLocalizedDescriptionKey: "No units selected for return."])
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReason.count >= 3 else {
            throw NSError(domain: "LivePetReturn", code: 400, userInfo: [NSLocalizedDescriptionKey: "A valid return reason (at least 3 characters) is required."])
        }

        // A refund-bearing return is a two-authority workflow. Fail before
        // creating the server-owned return case when this staff session cannot
        // perform the financial leg; the callable repeats the check server-side.
        if financialResolution == .fullRefund || financialResolution == .partialRefund {
            guard canRefundPayment() else {
                throw NSError(domain: "LivePetReturn", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: "You lack authorization to refund payments (payments.refund)."
                ])
            }
        }

        let maximumRefundMinor = selectedUnits.reduce(Int64(0)) { $0 + $1.refundableRemainingMinor }
        let requestedRefundMinor = selectedUnits.reduce(Int64(0)) { $0 + $1.refundAmountMinor }
        let trimmedAdjustmentReason = refundAdjustmentReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if financialResolution == .fullRefund && requestedRefundMinor != maximumRefundMinor {
            throw NSError(domain: "LivePetReturn", code: 400, userInfo: [NSLocalizedDescriptionKey: "Full refund amount must equal the refundable balance."])
        }
        if financialResolution == .partialRefund {
            guard requestedRefundMinor > 0, requestedRefundMinor < maximumRefundMinor else {
                throw NSError(domain: "LivePetReturn", code: 400, userInfo: [NSLocalizedDescriptionKey: "Partial refund amount must be greater than zero and below the refundable balance."])
            }
            guard trimmedAdjustmentReason.count >= 3 else {
                throw NSError(domain: "LivePetReturn", code: 400, userInfo: [NSLocalizedDescriptionKey: "A partial refund adjustment reason is required."])
            }
        }

        // Check if there is an in-flight command for this transaction
        let existingInFlight = recoveryService.hasUnresolvedCommand(for: transaction.receiptID)
        let commandId = existingInFlight?.commandId

        // 1. Build idempotent command
        let command = commandFactory.createCommand(
            transactionId: transaction.receiptID,
            receivingBranchId: receivingBranchId,
            units: selectedUnits,
            reason: trimmedReason,
            financialResolution: financialResolution,
            currency: transaction.currency.isEmpty ? "QAR" : transaction.currency,
            refundAdjustmentReason: financialResolution == .partialRefund ? trimmedAdjustmentReason : nil,
            existingCommandId: commandId
        )

        // 2. Generate new ReturnCase aggregate
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let caseId = existingInFlight?.returnCaseId ?? "ret-\(UUID().uuidString.prefix(12))"
        let caseNumber = "RTN-\(year)-\(UUID().uuidString.prefix(8).uppercased())"
        let currentUserId = PPStaffAuth.shared().cachedCurrentStaff?.uid ?? "unknown"

        // 3. Track in-flight command for crash recovery
        recoveryService.trackCommand(
            commandId: command.commandId,
            transactionId: transaction.receiptID,
            returnCaseId: caseId,
            fingerprint: command.fingerprint
        )

        // 4. Create the server-owned aggregate before any financial reversal.
        // The create command binds each exact unit while it is still SOLD and
        // advances its inventory version. It deliberately does not claim that
        // a payment refund or physical receipt has already happened.
        let initialRefundStatus: LivePetRefundStatus = financialResolution == .none || financialResolution == .manualSettlement
            ? .notRequired
            : .notRequested
        let returnCase = LivePetReturnCase(
            returnCaseId: caseId,
            caseNumber: caseNumber,
            transactionId: transaction.receiptID,
            originalBranchId: (transaction.branchID?.isEmpty ?? true) ? receivingBranchId : transaction.branchID!,
            receivingBranchId: receivingBranchId,
            customerId: nil,
            customerName: transaction.customerName,
            customerPhone: transaction.customerPhone,
            status: .draft,
            units: selectedUnits,
            reasonCode: "customer_return",
            reasonNotes: trimmedReason,
            financialResolution: financialResolution,
            refundStatus: initialRefundStatus,
            totalRefundAmountMinor: command.refundAmountMinor,
            refundAdjustmentReason: financialResolution == .partialRefund ? trimmedAdjustmentReason : nil,
            currency: command.currency,
            createdAt: now,
            createdBy: currentUserId,
            receivedAt: nil,
            receivedBy: nil,
            version: 1,
            events: []
        )

        let remote = LivePetReturnRemoteDataSource.shared
        let createdCase = try await repository.submitLivePetReturn(
            returnCase: returnCase,
            draftId: draftId,
            commandId: command.commandId
        )

        var caseVersion = createdCase.version
        var unitVersions = Dictionary(uniqueKeysWithValues: createdCase.units.map { ($0.unitId, $0.inventoryVersion) })

        // 5. Request payment reversal through the same server authority. The
        // callable is idempotent and records its own transaction/refund,
        // accounting, case event, command envelope, and audit entry.
        if financialResolution == .fullRefund || financialResolution == .partialRefund {
            guard canRefundPayment() else {
                throw NSError(domain: "LivePetReturn", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: "You lack authorization to refund payments (payments.refund)."
                ])
            }
            let refundCommandId = "\(command.commandId)-refund"
            let refundResult = try await remote.requestReturnRefund(
                returnCaseId: caseId,
                expectedCaseVersion: caseVersion,
                refundItems: command.buildRefundItemsPayload(),
                refundAmount: command.refundAmount,
                reason: trimmedReason,
                currency: command.currency,
                refundMode: financialResolution == .partialRefund ? "partial_amount" : "full_amount",
                refundAdjustmentReason: financialResolution == .partialRefund ? trimmedAdjustmentReason : nil,
                commandId: refundCommandId
            )
            caseVersion = (refundResult["caseVersion"] as? Int) ?? (caseVersion + 1)
        }

        // 6. Accept physical custody one exact unit at a time. A payment
        // reversal never performs this transition; receipt moves SOLD to
        // QUARANTINED/under_inspection and emits the stock movement and audit.
        for unit in selectedUnits {
            let expectedUnitVersion = unitVersions[unit.unitId] ?? (unit.inventoryVersion + 1)
            let receiveResult = try await remote.receiveLivePetReturn(
                returnCaseId: caseId,
                unitId: unit.unitId,
                expectedCaseVersion: caseVersion,
                expectedUnitVersion: expectedUnitVersion,
                conditionAtReturn: unit.conditionAtReturn.rawValue,
                notes: unit.notes ?? "Intake via Live Pet Return Studio",
                commandId: "\(command.commandId)-receive-\(unit.unitId)"
            )
            caseVersion = (receiveResult["caseVersion"] as? Int) ?? (caseVersion + 1)
            unitVersions[unit.unitId] = (receiveResult["unitVersion"] as? Int) ?? (expectedUnitVersion + 1)
        }

        recoveryService.markCommandResolved(commandId: command.commandId)
        return (try? await remote.fetchReturnCase(returnCaseId: caseId)) ?? createdCase
    }
}
