//
//  LivePetReturnDraftStore.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Offline-safe local return draft storage ensuring work is never lost during outages.
//

import Foundation

public struct LocalReturnDraft: Identifiable, Codable, Hashable, Sendable {
    public let draftId: String
    public let transactionId: String
    public var receivingBranchId: String
    public var selectedUnits: [LivePetReturnUnit]
    public var reasonCode: String
    public var reasonNotes: String
    public var financialResolution: FinancialResolution
    public var allocatedRefundMinor: Int64
    public var refundAdjustmentReason: String?
    public let commandId: String
    public let createdAt: Date
    public var updatedAt: Date

    public var id: String { draftId }

    public init(
        draftId: String = "draft-\(UUID().uuidString)",
        transactionId: String,
        receivingBranchId: String,
        selectedUnits: [LivePetReturnUnit] = [],
        reasonCode: String = "customer_return",
        reasonNotes: String = "",
        financialResolution: FinancialResolution = .fullRefund,
        allocatedRefundMinor: Int64 = 0,
        refundAdjustmentReason: String? = nil,
        commandId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.draftId = draftId
        self.transactionId = transactionId
        self.receivingBranchId = receivingBranchId
        self.selectedUnits = selectedUnits
        self.reasonCode = reasonCode
        self.reasonNotes = reasonNotes
        self.financialResolution = financialResolution
        self.allocatedRefundMinor = allocatedRefundMinor
        self.refundAdjustmentReason = refundAdjustmentReason
        self.commandId = commandId ?? "pos-livepet-return-\(UUID().uuidString)"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var totalRefundAmountMajor: Double {
        Double(allocatedRefundMinor) / 100.0
    }
}

public final class LivePetReturnDraftStore: ObservableObject, @unchecked Sendable {
    public static let shared = LivePetReturnDraftStore()

    @Published public private(set) var drafts: [LocalReturnDraft] = []

    private var storedDrafts: [LocalReturnDraft] = []
    private let storageKey = "purepets.admin.livepet.return_drafts.v1"
    private let queue = DispatchQueue(label: "com.purepets.admin.livepet.draftstore", qos: .utility)

    private init() {
        loadFromDisk()
    }

    public func saveDraft(_ draft: LocalReturnDraft) {
        queue.async { [weak self] in
            guard let self else { return }
            var updated = draft
            updated.updatedAt = Date()

            if let index = self.storedDrafts.firstIndex(where: { $0.draftId == updated.draftId }) {
                self.storedDrafts[index] = updated
            } else if let index = self.storedDrafts.firstIndex(where: { $0.transactionId == updated.transactionId }) {
                self.storedDrafts[index] = updated
            } else {
                self.storedDrafts.insert(updated, at: 0)
            }

            self.persistLocked(self.storedDrafts)
        }
    }

    public func loadDraft(draftId: String) -> LocalReturnDraft? {
        queue.sync {
            storedDrafts.first(where: { $0.draftId == draftId })
        }
    }

    public func loadDraftForTransaction(transactionId: String) -> LocalReturnDraft? {
        queue.sync {
            storedDrafts.first(where: { $0.transactionId == transactionId })
        }
    }

    public func deleteDraft(draftId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.storedDrafts.removeAll(where: { $0.draftId == draftId })
            self.persistLocked(self.storedDrafts)
        }
    }

    public func deleteDraftForTransaction(transactionId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.storedDrafts.removeAll(where: { $0.transactionId == transactionId })
            self.persistLocked(self.storedDrafts)
        }
    }

    // MARK: - Persistence

    private func persistLocked(_ newDrafts: [LocalReturnDraft]) {
        do {
            let data = try JSONEncoder().encode(newDrafts)
            UserDefaults.standard.set(data, forKey: storageKey)
            let snapshot = newDrafts
            DispatchQueue.main.async {
                self.drafts = snapshot
            }
        } catch {
            NSLog("[LivePetReturnDraftStore] Failed to persist drafts: %@", error.localizedDescription)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let loaded = try JSONDecoder().decode([LocalReturnDraft].self, from: data)
            queue.sync {
                self.storedDrafts = loaded
            }
            DispatchQueue.main.async {
                self.drafts = loaded
            }
        } catch {
            NSLog("[LivePetReturnDraftStore] Failed to decode drafts: %@", error.localizedDescription)
        }
    }
}
