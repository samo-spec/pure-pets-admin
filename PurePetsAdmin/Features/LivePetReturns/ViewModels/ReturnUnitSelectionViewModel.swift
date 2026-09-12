//
//  ReturnUnitSelectionViewModel.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  ViewModel managing exact-unit live pet selection, condition capture, and draft syncing.
//

import Foundation
import SwiftUI

@MainActor
public final class ReturnUnitSelectionViewModel: ObservableObject {
    public let receipt: PPPOSReceipt

    @Published public private(set) var availableUnits: [LivePetReturnUnit] = []
    @Published public var selectedUnitIds: Set<String> = []
    @Published public var unitConditions: [String: ReturnPhysicalCondition] = [:]
    @Published public var unitNotes: [String: String] = [:]

    @Published public var selectedReasonPreset: String = ""
    @Published public var customReason: String = ""
    @Published public var financialResolution: FinancialResolution = .fullRefund

    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    // Draft ID if restored from offline storage
    @Published public var activeDraftId: String?

    private let repository = LivePetReturnRepository.shared
    private let draftStore = LivePetReturnDraftStore.shared

    public init(receipt: PPPOSReceipt) {
        self.receipt = receipt
        loadUnitsAndDraft()
    }

    public func loadUnitsAndDraft() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // 1. Fetch sold live pet units from transaction
                let units = try await repository.fetchReturnUnits(for: receipt.receiptID)
                self.availableUnits = units

                // 2. Check if a local draft exists for this transaction
                if let draft = draftStore.loadDraftForTransaction(transactionId: receipt.receiptID) {
                    let returnableIds = Set(units.filter { !$0.isAlreadyReturned }.map { $0.unitId })
                    self.activeDraftId = draft.draftId
                    self.selectedUnitIds = Set(draft.selectedUnits.map { $0.unitId }).intersection(returnableIds)
                    for unit in draft.selectedUnits where returnableIds.contains(unit.unitId) {
                        self.unitConditions[unit.unitId] = unit.conditionAtReturn
                        if let notes = unit.notes {
                            self.unitNotes[unit.unitId] = notes
                        }
                    }
                    self.customReason = draft.reasonNotes
                    self.financialResolution = draft.financialResolution
                } else {
                    // Default selection: select all unreturned units if single animal
                    let unreturned = units.filter { !$0.isAlreadyReturned }
                    if unreturned.count == 1 {
                        self.selectedUnitIds.insert(unreturned[0].unitId)
                        self.unitConditions[unreturned[0].unitId] = .appearsNormal
                    }
                }

                self.isLoading = false
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Selection Toggles

    public func toggleUnitSelection(_ unit: LivePetReturnUnit) {
        guard !unit.isAlreadyReturned else { return }

        if selectedUnitIds.contains(unit.unitId) {
            selectedUnitIds.remove(unit.unitId)
        } else {
            selectedUnitIds.insert(unit.unitId)
            if unitConditions[unit.unitId] == nil {
                unitConditions[unit.unitId] = .appearsNormal
            }
        }
        syncDraft()
    }

    public func setCondition(_ condition: ReturnPhysicalCondition, for unitId: String) {
        unitConditions[unitId] = condition
        syncDraft()
    }

    public func setNotes(_ notes: String, for unitId: String) {
        unitNotes[unitId] = notes
        syncDraft()
    }

    // MARK: - Selected Units Assembly

    public var selectedUnitsList: [LivePetReturnUnit] {
        availableUnits.compactMap { unit in
            guard selectedUnitIds.contains(unit.unitId) else { return nil }
            var updated = unit
            updated.conditionAtReturn = unitConditions[unit.unitId] ?? .appearsNormal
            updated.disposition = updated.conditionAtReturn.suggestedCommercialDisposition
            updated.inspectionStatus = updated.conditionAtReturn.suggestedHealthDisposition
            updated.notes = unitNotes[unit.unitId]
            return updated
        }
    }

    // MARK: - Refund Calculation

    public var calculatedRefundAmountMajor: Double {
        selectedUnitsList.reduce(0.0) { $0 + $1.refundAmountMajor }
    }

    public var canProceed: Bool {
        !selectedUnitIds.isEmpty &&
        (!customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedReasonPreset.isEmpty)
    }

    public var effectiveReason: String {
        let custom = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return selectedReasonPreset
    }

    // MARK: - Save Draft to Local Offline Store

    public func syncDraft() {
        let receivingBranch = BranchContextStore.shared.activeBranch?.branchID ?? receipt.branchID ?? ""
        let draft = LocalReturnDraft(
            draftId: activeDraftId ?? "draft-\(UUID().uuidString)",
            transactionId: receipt.receiptID,
            receivingBranchId: receivingBranch,
            selectedUnits: selectedUnitsList,
            reasonCode: "customer_return",
            reasonNotes: effectiveReason,
            financialResolution: financialResolution,
            allocatedRefundMinor: Int64(round(calculatedRefundAmountMajor * 100.0))
        )
        self.activeDraftId = draft.draftId
        draftStore.saveDraft(draft)
    }

    public func clearDraft() {
        if let activeDraftId {
            draftStore.deleteDraft(draftId: activeDraftId)
        } else {
            draftStore.deleteDraftForTransaction(transactionId: receipt.receiptID)
        }
    }
}
