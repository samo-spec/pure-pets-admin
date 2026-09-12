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
               staff.hasPermission(kStaffPermPosSell) ||
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
               staff.hasPermission(kStaffPermStockManage) ||
               staff.isAdmin()
    }

    // MARK: - Execute Return & Refund

    public func processLivePetReturn(
        transaction: PPPOSReceipt,
        selectedUnits: [LivePetReturnUnit],
        receivingBranchId: String,
        reason: String,
        financialResolution: FinancialResolution = .fullRefund,
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
            existingCommandId: commandId
        )

        // 2. Generate new ReturnCase aggregate
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let caseId = existingInFlight?.returnCaseId ?? "ret-\(UUID().uuidString.prefix(12))"
        let caseNumber = "RTN-\(year)-\(UUID().uuidString.prefix(8).uppercased())"
        let currentUserId = PPStaffAuth.shared().cachedCurrentStaff?.uid ?? "unknown"
        let currentUserName = PPStaffAuth.shared().cachedCurrentStaff?.displayName ?? PPStaffAuth.shared().cachedCurrentStaff?.email ?? "Staff"

        // 3. Track in-flight command for crash recovery
        recoveryService.trackCommand(
            commandId: command.commandId,
            transactionId: transaction.receiptID,
            returnCaseId: caseId,
            fingerprint: command.fingerprint
        )

        // 4. If financial refund is requested, submit payment refund through PPPOSService with exact units
        var initialRefundStatus: LivePetRefundStatus = .notRequested
        let refundCommandId = "pos-refund-\(UUID().uuidString)"
        var resolvedRefundId: String? = nil

        if financialResolution == .fullRefund || financialResolution == .partialRefund {
            guard canRefundPayment() else {
                throw NSError(domain: "LivePetReturn", code: 403, userInfo: [
                    NSLocalizedDescriptionKey: "You lack authorization to refund payments (payments.refund)."
                ])
            }
            let refundItemsPayload = command.buildRefundItemsPayload()
            initialRefundStatus = .processing

            let (refundStatusResult, actualRefundId): (LivePetRefundStatus, String?) = await withCheckedContinuation { continuation in
                var hasResumed = false
                let lock = NSLock()

                let safeResume: (LivePetRefundStatus, String?) -> Void = { status, rId in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: (status, rId))
                }

                // 25 second timeout safeguard for payment gateway: keep pending for reconciliation
                DispatchQueue.global().asyncAfter(deadline: .now() + 25.0) {
                    safeResume(.processing, refundCommandId)
                }

                PPPOSService.shared().refundTransaction(
                    transactionID: transaction.receiptID,
                    refundAmount: command.refundAmount,
                    refundItems: refundItemsPayload,
                    reason: trimmedReason,
                    currency: command.currency,
                    commandID: refundCommandId
                ) { success, returnedRefundId, error in
                    if success {
                        safeResume(.succeeded, returnedRefundId ?? refundCommandId)
                    } else {
                        NSLog("[LivePetReturnService] Payment refund callable error: %@", error?.localizedDescription ?? "Unknown")
                        safeResume(.failed, nil)
                    }
                }
            }

            initialRefundStatus = refundStatusResult
            resolvedRefundId = actualRefundId

            // 4a. Transition each returned unit to QUARANTINED authoritatively via validateInventoryChange
            if initialRefundStatus == .succeeded, let effectiveRefundId = resolvedRefundId {
                for unit in selectedUnits {
                    let unitCommandId = "cmd_accept_return_\(unit.unitId)_\(UUID().uuidString.prefix(8))"
                    do {
                        _ = try await LivePetReturnRemoteDataSource.shared.acceptLiveAnimalReturn(
                            productId: unit.productId,
                            unitId: unit.unitId,
                            ringTag: unit.ringTag,
                            transactionId: transaction.receiptID,
                            refundId: effectiveRefundId,
                            reason: trimmedReason,
                            notes: "Intake via Live Pet Return Studio",
                            commandId: unitCommandId,
                            returnCaseId: caseId
                        )
                    } catch {
                        NSLog("[LivePetReturnService] acceptLiveAnimalReturn warning for unit %@: %@", unit.unitId, error.localizedDescription)
                    }
                }
            }
        } else {
            initialRefundStatus = .notRequired
        }

        // 5. Construct initial append-only events
        var events: [LivePetReturnEvent] = [
            LivePetReturnEvent(
                eventId: "evt-\(UUID().uuidString)",
                eventType: .returnCreated,
                returnCaseId: caseId,
                actorId: currentUserId,
                actorName: currentUserName,
                branchId: receivingBranchId,
                commandId: command.commandId,
                occurredAt: now,
                notes: trimmedReason
            ),
            LivePetReturnEvent(
                eventId: "evt-\(UUID().uuidString)",
                eventType: .unitReceived,
                returnCaseId: caseId,
                actorId: currentUserId,
                actorName: currentUserName,
                branchId: receivingBranchId,
                commandId: command.commandId,
                occurredAt: now.addingTimeInterval(1),
                notes: "Intake of \(selectedUnits.count) animal(s) into custody at branch return desk."
            )
        ]

        if initialRefundStatus == .succeeded {
            events.append(LivePetReturnEvent(
                eventId: "evt-\(UUID().uuidString)",
                eventType: .refundSucceeded,
                returnCaseId: caseId,
                actorId: currentUserId,
                actorName: currentUserName,
                branchId: receivingBranchId,
                commandId: command.commandId,
                occurredAt: now.addingTimeInterval(2),
                notes: "Refund of \(String(format: "%.2f", command.refundAmount)) \(command.currency) settled."
            ))
        } else if initialRefundStatus == .failed {
            events.append(LivePetReturnEvent(
                eventId: "evt-\(UUID().uuidString)",
                eventType: .refundFailed,
                returnCaseId: caseId,
                actorId: currentUserId,
                actorName: currentUserName,
                branchId: receivingBranchId,
                commandId: command.commandId,
                occurredAt: now.addingTimeInterval(2),
                notes: "Financial settlement failed with gateway; requires manual review or retry."
            ))
        } else if initialRefundStatus == .processing {
            events.append(LivePetReturnEvent(
                eventId: "evt-\(UUID().uuidString)",
                eventType: .refundProcessing,
                returnCaseId: caseId,
                actorId: currentUserId,
                actorName: currentUserName,
                branchId: receivingBranchId,
                commandId: command.commandId,
                occurredAt: now.addingTimeInterval(2),
                notes: "Payment gateway response pending; tracked for automated reconciliation."
            ))
        }

        // 6. Assemble complete LivePetReturnCase aggregate
        let returnCase = LivePetReturnCase(
            returnCaseId: caseId,
            caseNumber: caseNumber,
            transactionId: transaction.receiptID,
            originalBranchId: (transaction.branchID?.isEmpty ?? true) ? receivingBranchId : transaction.branchID!,
            receivingBranchId: receivingBranchId,
            customerId: nil,
            customerName: transaction.customerName,
            customerPhone: transaction.customerPhone,
            status: .underInspection, // Non-negotiable: enters under_inspection, never available
            units: selectedUnits,
            reasonCode: "customer_return",
            reasonNotes: trimmedReason,
            financialResolution: financialResolution,
            refundStatus: initialRefundStatus,
            currency: command.currency,
            createdAt: now,
            createdBy: currentUserId,
            receivedAt: now,
            receivedBy: currentUserId,
            version: 1,
            events: events
        )

        // 7. Persist to Firestore & delete local draft
        do {
            let persistedCase = try await repository.submitLivePetReturn(returnCase: returnCase, draftId: draftId)

            // 8. Mark recovery command resolved only if refund is not pending reconciliation
            if initialRefundStatus != .processing {
                recoveryService.markCommandResolved(commandId: command.commandId)
            }

            return persistedCase
        } catch {
            // If refund was dispatched and settled or processing, ensure rescue case is persisted
            // so custody and financial state are not lost, keeping command tracked for recovery
            if initialRefundStatus == .succeeded || initialRefundStatus == .processing {
                try? await LivePetReturnRemoteDataSource.shared.persistReturnCase(returnCase)
            }
            throw error
        }
    }
}
