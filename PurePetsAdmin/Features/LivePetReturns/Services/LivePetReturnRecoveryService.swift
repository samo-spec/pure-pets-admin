//
//  LivePetReturnRecoveryService.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  In-flight command recovery service surviving app restarts, crashes, and network drops.
//

import Foundation
import FirebaseFirestore

public struct InFlightCommandRecord: Codable, Hashable, Sendable {
    public let commandId: String
    public let transactionId: String
    public let returnCaseId: String
    public let fingerprint: String
    public let submittedAt: Date
    public var lastAttemptAt: Date
    public var attemptCount: Int

    public init(
        commandId: String,
        transactionId: String,
        returnCaseId: String,
        fingerprint: String,
        submittedAt: Date = Date(),
        lastAttemptAt: Date = Date(),
        attemptCount: Int = 1
    ) {
        self.commandId = commandId
        self.transactionId = transactionId
        self.returnCaseId = returnCaseId
        self.fingerprint = fingerprint
        self.submittedAt = submittedAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
    }
}

public final class LivePetReturnRecoveryService: ObservableObject, @unchecked Sendable {
    public static let shared = LivePetReturnRecoveryService()

    @Published public private(set) var inFlightCommands: [String: InFlightCommandRecord] = [:]

    private var storedCommands: [String: InFlightCommandRecord] = [:]
    private let storageKey = "purepets.admin.livepet.inflight_commands.v1"
    private let queue = DispatchQueue(label: "com.purepets.admin.livepet.recovery", qos: .utility)

    private init() {
        loadFromDisk()
        Task { [weak self] in
            await self?.reconcileInFlightCommands()
        }
    }

    public func trackCommand(
        commandId: String,
        transactionId: String,
        returnCaseId: String,
        fingerprint: String
    ) {
        queue.sync {
            self.storedCommands[commandId] = InFlightCommandRecord(
                commandId: commandId,
                transactionId: transactionId,
                returnCaseId: returnCaseId,
                fingerprint: fingerprint
            )
            self.persistLocked(self.storedCommands)
        }
    }

    public func markCommandResolved(commandId: String) {
        queue.sync {
            self.storedCommands.removeValue(forKey: commandId)
            self.persistLocked(self.storedCommands)
        }
    }

    public func hasUnresolvedCommand(for transactionId: String) -> InFlightCommandRecord? {
        queue.sync {
            storedCommands.values.first(where: { $0.transactionId == transactionId })
        }
    }

    // MARK: - Auto-Reconciliation on Startup / Reconnect

    public func reconcileInFlightCommands() async {
        let commandsToReconcile: [InFlightCommandRecord] = queue.sync {
            Array(storedCommands.values)
        }
        guard !commandsToReconcile.isEmpty else { return }

        let db = Firestore.firestore()
        for record in commandsToReconcile {
            do {
                let caseDoc = try await db.collection("returnCases").document(record.returnCaseId).getDocument()
                if caseDoc.exists, let data = caseDoc.data() {
                    let refundStatus = data["refundStatus"] as? String ?? ""
                    if refundStatus == "succeeded" || refundStatus == "not_required" || refundStatus == "failed" {
                        markCommandResolved(commandId: record.commandId)
                        continue
                    }
                }

                let age = Date().timeIntervalSince(record.submittedAt)
                if age > 7 * 86400 {
                    markCommandResolved(commandId: record.commandId)
                }
            } catch {
                NSLog("[LivePetReturnRecoveryService] Failed to reconcile command %@: %@", record.commandId, error.localizedDescription)
            }
        }
    }

    // MARK: - Persistence

    private func persistLocked(_ records: [String: InFlightCommandRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            UserDefaults.standard.set(data, forKey: storageKey)
            let snapshot = records
            DispatchQueue.main.async {
                self.inFlightCommands = snapshot
            }
        } catch {
            NSLog("[LivePetReturnRecoveryService] Failed to persist command records: %@", error.localizedDescription)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let loaded = try JSONDecoder().decode([String: InFlightCommandRecord].self, from: data)
            queue.sync {
                self.storedCommands = loaded
            }
            DispatchQueue.main.async {
                self.inFlightCommands = loaded
            }
        } catch {
            NSLog("[LivePetReturnRecoveryService] Failed to decode command records: %@", error.localizedDescription)
        }
    }
}

// MARK: - Objective-C App Lifecycle Bridge

@objc public final class LivePetReturnRecoveryServiceBridge: NSObject {
    @objc public static func startAutoReconciliation() {
        Task {
            await LivePetReturnRecoveryService.shared.reconcileInFlightCommands()
        }
    }
}
