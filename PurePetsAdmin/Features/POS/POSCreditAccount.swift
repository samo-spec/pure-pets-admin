import Foundation
import SwiftUI
import UIKit
import FirebaseAuth
import CryptoKit

@MainActor
enum POSCreditAccountCopy {
    static func text(_ key: String) -> String { Language.get("POS_CreditAccount_" + key, alter: nil) }
    static func money(_ value: Int) -> String { POSReceiptFormat.currency(Double(value) / 100, code: "QAR") }
    static func permitted(_ permission: String, branchID: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, let staff = PPStaffAuth.shared().cachedCurrentStaff,
              staff.uid == uid, staff.isActive(), !branchID.isEmpty else { return false }
        if staff.isAdmin() { return true }
        return staff.hasPermission(permission, inBranch: branchID)
    }
}

struct POSCreditAccountSummary: Decodable {
    let outstandingMinor: Int
    let overdueMinor: Int
    let pendingAmountMinor: Int
    let openInvoiceCount: Int
    let nextDueDateKey: String?
    let aging: [String: Int]
}
struct POSCreditAccountContext: Decodable {
    let receiptAccounts: [String: String]
    let pendingTendersEnabled: Bool
    let agreementTemplate: POSCreditContext.AgreementTemplate?
}
struct POSCreditAccountPage<Row: Decodable>: Decodable {
    let ok: Bool
    let branchId: String
    let customerId: String
    let currency: String
    let kind: String
    let accountVersion: Int
    let asOfDateKey: String
    let summary: POSCreditAccountSummary
    let collectionContext: POSCreditAccountContext
    let rows: [Row]
    let nextCursor: POSCreditStatementCursor?
}
struct POSCreditStatementCursor: Codable {
    let id: String
    let seconds: Int
    let nanoseconds: Int
    let scopeHash: String
}
struct POSCreditAccountInvoice: Decodable, Identifiable {
    struct Installment: Decodable, Identifiable {
        let id: String
        let dueDateKey: String
        let amountMinor: Int
        let paidMinor: Int
        let pendingAmountMinor: Int
        let creditedMinor: Int?
        let writtenOffMinor: Int?
        var due: Int { max(0, amountMinor - paidMinor - (creditedMinor ?? 0) - (writtenOffMinor ?? 0)) }
    }
    let invoiceId: String
    let saleId: String
    let documentNumber: String
    let version: Int
    let agreementVersion: Int
    let agreement: POSCreditReceiptSummary.Agreement?
    let totalMinor: Int
    let amountPaidMinor: Int
    let amountDueMinor: Int
    let overdueMinor: Int
    let creditedMinor: Int?
    let writtenOffMinor: Int?
    let refundedMinor: Int?
    let refundLiabilityMinor: Int?
    let disputeHold: Bool?
    let pendingAmountMinor: Int
    let paymentStatus: String
    let installments: [Installment]
    let dueDateKey: String?
    let createdAt: String
    var id: String { invoiceId }
    var available: Int { max(0, amountDueMinor - pendingAmountMinor) }
}
struct POSCreditAccountCollection: Decodable, Identifiable {
    struct Allocation: Decodable { let invoiceId: String; let amountMinor: Int }
    let collectionId: String
    let documentNumber: String
    let version: Int
    let status: String
    let tenderAmountMinor: Int
    // Current net allocation from amountPaidMinor; reversals are already deducted.
    let receivedMinor: Int
    let pendingAmountMinor: Int
    let reversedMinor: Int
    let paymentMethod: String
    let requestedAllocations: [Allocation]
    let lastEventId: String
    let createdAt: String
    var id: String { collectionId }
}

/// Exact lifecycle request, kept independently of editable account fields.
/// Each actor retains one unresolved financial intent across customers/branches.
/// Another actor can independently review without replaying this actor's intent.
enum POSCreditAccountCommandStore {
    struct Record: Codable {
        let operation: String
        let actorUID: String
        let branchID: String
        let customerID: String
        let commandID: String
        let request: Data
        let createdAt: Date
        var result: Data?
        var approvalRequest: Data?
    }
    static let operations: Set<String> = ["recordPosCollection", "confirmPosCollectionClearing", "rejectPosCollectionTender", "reversePosCollection", "changeCreditTerms", "approvePosCreditChange", "posCreditPolicyCommand", "posCreditReviewCommand", "posCreditAdjustmentCommand"]
    private static func location(actorUID: String? = nil) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("POSCredit", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protected = root
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try protected.setResourceValues(resources)
        guard let actorUID else { return root.appendingPathComponent("lifecycle-v1.json") }
        guard !actorUID.isEmpty, actorUID.utf8.count <= 256 else { throw POSCreditPendingStore.StoreError.invalidRecord }
        let digest = SHA256.hash(data: Data(actorUID.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("lifecycle-v2-" + digest + ".json")
    }
    static func validate(_ value: Record) throws {
        guard operations.contains(value.operation), !value.actorUID.isEmpty, !value.branchID.isEmpty, !value.customerID.isEmpty,
              !value.commandID.isEmpty, value.request.count <= 256_000,
              let body = try JSONSerialization.jsonObject(with: value.request) as? [String: Any],
              body["commandId"] as? String == value.commandID, body["branchId"] as? String == value.branchID,
              body["customerId"] as? String == value.customerID else { throw POSCreditPendingStore.StoreError.invalidRecord }
        if let result = value.result {
            guard let response = try JSONSerialization.jsonObject(with: result) as? [String: Any], response["ok"] as? Bool == true, response["commandId"] as? String == value.commandID,
                  response["customerId"] as? String == value.customerID, response["branchId"] as? String == value.branchID else {
                throw POSCreditPendingStore.StoreError.invalidRecord
            }
        }
    }
    static func load(actorUID: String) throws -> Record? {
        let file = try location(actorUID: actorUID), legacy = try location()
        // Preserve the first version's durable record across upgrade, including
        // a crash between atomic copy and removal. Other actors never receive it.
        if FileManager.default.fileExists(atPath: legacy.path) {
            let original = try JSONDecoder().decode(Record.self, from: Data(contentsOf: legacy))
            try validate(original)
            if original.actorUID == actorUID {
                if FileManager.default.fileExists(atPath: file.path) {
                    let existing = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
                    try validate(existing)
                    guard existing.actorUID == actorUID, existing.commandID == original.commandID,
                          existing.operation == original.operation, existing.request == original.request else { throw POSCreditPendingStore.StoreError.anotherCommand }
                } else {
                    try JSONEncoder().encode(original).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                try FileManager.default.removeItem(at: legacy)
            }
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let value = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
        try validate(value)
        guard value.actorUID == actorUID else { throw POSCreditPendingStore.StoreError.invalidRecord }
        return value
    }
    static func save(_ value: Record) throws {
        try validate(value)
        if let original = try load(actorUID: value.actorUID) {
            guard original.commandID == value.commandID, original.actorUID == value.actorUID,
                  original.operation == value.operation, original.request == value.request else { throw POSCreditPendingStore.StoreError.anotherCommand }
        }
        try JSONEncoder().encode(value).write(to: location(actorUID: value.actorUID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func acknowledge(_ value: Record) throws {
        guard let stored = try load(actorUID: value.actorUID), stored.commandID == value.commandID, stored.actorUID == value.actorUID,
              stored.result != nil else { throw POSCreditPendingStore.StoreError.invalidRecord }
        try FileManager.default.removeItem(at: location(actorUID: value.actorUID))
    }
}

@MainActor
final class POSCreditAccountModel: ObservableObject {
    let customerID: String
    let branchID: String
    let actorUID: String
    @Published private(set) var summary: POSCreditAccountSummary?
    @Published private(set) var context: POSCreditAccountContext?
    @Published private(set) var invoices: [POSCreditAccountInvoice] = []
    @Published private(set) var collections: [POSCreditAccountCollection] = []
    @Published private(set) var accountVersion = 0
    @Published private(set) var asOf = ""
    @Published private(set) var busy = false
    @Published private(set) var pending: POSCreditAccountCommandStore.Record?
    @Published var error: String?
    @Published var notice: String?
    @Published var shareURL: URL?
    @Published private(set) var storageFailed = false
    @Published private(set) var administration: POSCreditAdministrationPage?
    @Published var needsStepUp = false
    @Published private(set) var adjustmentContext: POSCreditAdjustmentContext?
    private var cursor: POSCreditStatementCursor?
    private var kind = "invoices"
    private var requestID = UUID()
    private nonisolated(unsafe) var authListener: AuthStateDidChangeListenerHandle?
    var hasMore: Bool { cursor != nil }
    var canRead: Bool { Auth.auth().currentUser?.uid == actorUID && POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) }
    var canCollect: Bool { canRead && POSCreditAccountCopy.permitted("pos.credit.collect", branchID: branchID) && accountVersion > 0 }
    var canRecover: Bool { canRead && pending?.actorUID == actorUID && pending?.branchID == branchID && pending?.customerID == customerID }

    init(customerID: String, branchID: String) {
        self.customerID = customerID; self.branchID = branchID
        actorUID = Auth.auth().currentUser?.uid ?? ""
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            Task { @MainActor in
                guard let self else { return }
                if uid == self.actorUID {
                    if self.pending == nil { self.restore() }
                    return
                }
                self.requestID = UUID(); self.busy = false; self.invoices = []; self.collections = []
                self.summary = nil; self.context = nil; self.notice = nil; self.pending = nil; self.shareURL = nil
                self.administration = nil; self.adjustmentContext = nil; self.accountVersion = 0; self.asOf = ""
                self.error = POSCreditAccountCopy.text("Permission")
            }
        }
        restore()
    }
    deinit { if let authListener { Auth.auth().removeStateDidChangeListener(authListener) } }
    func restore() {
        do { pending = try POSCreditAccountCommandStore.load(actorUID: actorUID); storageFailed = false }
        catch { storageFailed = true; self.error = POSCreditAccountCopy.text("StorageFailed") }
    }
    func base() -> [String: Any] { ["contractVersion": 1, "customerId": customerID, "branchId": branchID, "currency": "QAR"] }
    func call(_ operation: String, body: [String: Any], completion: @escaping @MainActor ([String: Any], Data) throws -> Void) {
        do { try call(operation, data: JSONSerialization.data(withJSONObject: body, options: .sortedKeys), completion: completion) }
        catch { self.error = POSCreditAccountCopy.text("Invalid") }
    }
    func call(_ operation: String, data: Data, completion: @escaping @MainActor ([String: Any], Data) throws -> Void) throws {
        guard canRead, !busy else { return }
        busy = true; error = nil
        let ticket = UUID(); requestID = ticket
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000_000)
            guard let self, self.requestID == ticket, self.busy else { return }
            self.requestID = UUID(); self.busy = false; self.error = POSCreditAccountCopy.text(self.pending == nil ? "LoadFailed" : "Uncertain")
        }
        PPPOSService.shared().callCreditOperation(operation, request: data, actorUID: actorUID) { [weak self] response, callError in
            Task { @MainActor in
                guard let self, self.requestID == ticket else { return }
                self.busy = false
                guard self.canRead else { self.invoices = []; self.collections = []; self.summary = nil; self.context = nil; return }
                do {
                    if let callError { throw callError }
                    guard let response, let value = try JSONSerialization.jsonObject(with: response) as? [String: Any], value["ok"] as? Bool == true else { throw POSCreditPendingStore.StoreError.invalidRecord }
                    try completion(value, response)
                } catch {
                    let details = (error as NSError).userInfo["details"] as? [String: Any] ?? (error as NSError).userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any] ?? [:]
                    if let proposal = details["approvalRequest"] as? [String: Any], var pending = self.pending {
                        pending.approvalRequest = try? JSONSerialization.data(withJSONObject: proposal, options: .sortedKeys)
                        do { try POSCreditAccountCommandStore.save(pending); self.pending = pending }
                        catch { self.storageFailed = true }
                        self.error = POSCreditAccountCopy.text("ApprovalRequired")
                    } else if details["recovery"] as? String == "reauthenticate_with_approved_second_factor" {
                        self.needsStepUp = true; self.error = POSCreditAccountCopy.text("StepUp")
                    } else { self.error = POSCreditAccountCopy.text(self.pending == nil ? "LoadFailed" : "Uncertain") }
                }
            }
        }
    }
    func load(kind requestedKind: String = "invoices", more: Bool = false) {
        guard canRead, !busy, ["invoices", "collections"].contains(requestedKind), !more || cursor != nil else { return }
        if !more || kind != requestedKind { cursor = nil; invoices = []; collections = [] }
        kind = requestedKind
        var body = base(); body["kind"] = requestedKind; body["pageSize"] = 50
        if more, let cursor, let encoded = try? JSONEncoder().encode(cursor) { body["cursor"] = try? JSONSerialization.jsonObject(with: encoded) }
        call("getCustomerReceivables", body: body) { [weak self] _, data in
            guard let self else { return }
            if requestedKind == "invoices" {
                let page = try JSONDecoder().decode(POSCreditAccountPage<POSCreditAccountInvoice>.self, from: data)
                try self.accept(page, more: more)
                self.invoices = more ? self.invoices + page.rows.filter { row in !self.invoices.contains(where: { $0.id == row.id }) } : page.rows
            } else {
                let page = try JSONDecoder().decode(POSCreditAccountPage<POSCreditAccountCollection>.self, from: data)
                try self.accept(page, more: more)
                self.collections = more ? self.collections + page.rows.filter { row in !self.collections.contains(where: { $0.id == row.id }) } : page.rows
            }
        }
    }
    private func accept<Row>(_ page: POSCreditAccountPage<Row>, more: Bool) throws {
        guard page.ok, page.customerId == customerID, page.branchId == branchID, page.currency == "QAR", page.kind == kind,
              page.summary.outstandingMinor >= 0, page.summary.pendingAmountMinor >= 0, page.summary.pendingAmountMinor <= page.summary.outstandingMinor,
              !more || page.accountVersion == accountVersion else {
            invoices = []; collections = []; cursor = nil
            throw POSCreditPendingStore.StoreError.invalidRecord
        }
        accountVersion = page.accountVersion; summary = page.summary; context = page.collectionContext; asOf = page.asOfDateKey; cursor = page.nextCursor
    }
    func collect(amounts: [String: Int], method: String, reference: String) {
        guard canCollect, pending == nil, !storageFailed, !busy, !amounts.isEmpty, amounts.count <= 20,
              let accountID = context?.receiptAccounts[method], method == "cash" || context?.pendingTendersEnabled == true else { return }
        let rows = invoices.filter { amounts[$0.id] != nil }
        guard rows.count == amounts.count, rows.allSatisfy({ (amounts[$0.id] ?? 0) > 0 && (amounts[$0.id] ?? 0) <= $0.available }) else { error = POSCreditAccountCopy.text("Invalid"); return }
        var body = base(); body["commandId"] = UUID().uuidString; body["expectedAccountVersion"] = accountVersion
        body["method"] = method; body["accountId"] = accountID; body["reference"] = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        body["allocations"] = rows.map { ["invoiceId": $0.id, "expectedVersion": $0.version, "amountMinor": amounts[$0.id]!] as [String: Any] }
        submit("recordPosCollection", body: body)
    }
    func submit(_ operation: String, body: [String: Any]) {
        do {
            guard pending == nil, !storageFailed, canRead, let command = body["commandId"] as? String else { return }
            let data = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
            let record = POSCreditAccountCommandStore.Record(operation: operation, actorUID: actorUID, branchID: branchID, customerID: customerID, commandID: command, request: data, createdAt: Date())
            try POSCreditAccountCommandStore.save(record)
            pending = record; recover()
        } catch { self.error = POSCreditAccountCopy.text("StorageFailed") }
    }
    func recover() {
        guard canRecover, !busy, let original = pending else { return }
        if let result = original.result { showResult(result); return }
        do {
            try call(original.operation, data: original.request) { [weak self] value, response in
                guard let self else { return }
                guard value["commandId"] as? String == original.commandID, value["customerId"] as? String == original.customerID,
                      value["branchId"] as? String == original.branchID, value["currency"] as? String == "QAR" else { throw POSCreditPendingStore.StoreError.invalidRecord }
                var confirmed = original; confirmed.result = response
                try POSCreditAccountCommandStore.save(confirmed)
                self.pending = confirmed; self.showResult(response)
                NotificationCenter.default.post(name: Notification.Name("PPAccountingDataDidChangeNotification"), object: nil)
            }
        } catch { self.error = POSCreditAccountCopy.text("StorageFailed") }
    }
    private func showResult(_ data: Data) {
        guard canRecover, let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let received = (value["receivedMinor"] as? NSNumber)?.intValue ?? 0
        let pendingAmount = (value["pendingAmountMinor"] as? NSNumber)?.intValue ?? 0
        if let status = value["status"] as? String { notice = POSCreditAccountCopy.text(status); return }
        notice = "\(POSCreditAccountCopy.text("Confirmed"))\n\(POSCreditAccountCopy.text("Received")): \(POSCreditAccountCopy.money(received))\n\(POSCreditAccountCopy.text("Pending")): \(POSCreditAccountCopy.money(pendingAmount))"
    }
    func acknowledge() {
        guard canRecover, let record = pending, record.result != nil else { return }
        do { try POSCreditAccountCommandStore.acknowledge(record); pending = nil; notice = nil; if kind == "administration" { loadAdministration() } else { load(kind: kind) } }
        catch { self.error = POSCreditAccountCopy.text("StorageFailed") }
    }
    func receipt(_ collection: POSCreditAccountCollection) {
        var body = base(); body["kind"] = "receipt"; body["collectionId"] = collection.id; body["eventId"] = collection.lastEventId
        call("getCustomerReceivables", body: body) { [weak self] value, _ in
            guard let self, let receipt = value["receipt"] as? [String: Any], receipt["collectionId"] as? String == collection.id,
                  receipt["customerId"] as? String == self.customerID, receipt["branchId"] as? String == self.branchID else { throw POSCreditPendingStore.StoreError.invalidRecord }
            var lines = [POSCreditAccountCopy.text("Receipt"), collection.documentNumber, receipt["createdAt"] as? String ?? "",
                "\(POSCreditAccountCopy.text("Status")): \(POSCreditAccountCopy.text(receipt["status"] as? String ?? "pending"))",
                "\(POSCreditAccountCopy.text("Received")): \(POSCreditAccountCopy.money((receipt["receivedMinor"] as? NSNumber)?.intValue ?? 0))",
                "\(POSCreditAccountCopy.text("Pending")): \(POSCreditAccountCopy.money((receipt["pendingAmountMinor"] as? NSNumber)?.intValue ?? 0))",
                "\(POSCreditAccountCopy.text("Refunded")): \(POSCreditAccountCopy.money((receipt["refundedMinor"] as? NSNumber)?.intValue ?? 0))",
                "\(POSCreditAccountCopy.text("Reversed")): \(POSCreditAccountCopy.money((receipt["reversedMinor"] as? NSNumber)?.intValue ?? 0))",
                "\(POSCreditAccountCopy.text("ReceiptID")): \(collection.id) / \(collection.lastEventId)"]
            lines.append(POSCreditAccountCopy.text(receipt["paymentMethod"] as? String ?? "cash"))
            if let reference = receipt["reference"] as? String { lines.append(reference) }
            for allocation in receipt["allocations"] as? [[String: Any]] ?? [] {
                lines.append("\(allocation["invoiceId"] as? String ?? "") · \(POSCreditAccountCopy.money((allocation["amountMinor"] as? NSNumber)?.intValue ?? 0))")
            }
            self.shareURL = try POSCreditAccountPDF.export(lines)
        }
    }
    func permitted(_ permission: String) -> Bool { canRead && POSCreditAccountCopy.permitted(permission, branchID: branchID) }
    func loadAdministration(more: Bool = false) {
        kind = "administration"
        var body = base(); body["action"] = "list"
        if more, let cursor = administration?.nextCursor { body["cursor"] = cursor }
        call("posCreditReviewCommand", body: body) { [weak self] _, data in
            let page = try JSONDecoder().decode(POSCreditAdministrationPage.self, from: data)
            guard let self, page.branchId == self.branchID, page.customerId == self.customerID else { throw POSCreditPendingStore.StoreError.invalidRecord }
            let prior = more ? (self.administration?.rows ?? []) : []
            let combined = prior + page.rows.filter { row in !prior.contains(where: { $0.id == row.id }) }
            self.administration = POSCreditAdministrationPage(branchId: page.branchId, customerId: page.customerId, policy: page.policy,
                rows: combined, policyProposals: page.policyProposals, morePolicies: page.morePolicies, nextCursor: page.nextCursor)
        }
    }
    var canAdjust: Bool { permitted("pos.credit.refund") || permitted("pos.credit.writeoff") || permitted("pos.credit.reverse") }
    func loadAdjustmentContext(_ invoice: POSCreditAccountInvoice, more: Bool = false) {
        var body = base(); body["kind"] = "adjustment"; body["invoiceId"] = invoice.id; body["pageSize"] = 50
        if more, let cursor = adjustmentContext?.nextCursor, let data = try? JSONEncoder().encode(cursor) { body["cursor"] = try? JSONSerialization.jsonObject(with: data) }
        else { adjustmentContext = nil }
        call("getCustomerReceivables", body: body) { [weak self] _, data in
            guard let self else { return }
            let value = try JSONDecoder().decode(POSCreditAdjustmentContext.self, from: data)
            guard value.customerId == self.customerID, value.branchId == self.branchID, value.invoiceId == invoice.id,
                  value.version == invoice.version, value.accountVersion == self.accountVersion else { throw POSCreditPendingStore.StoreError.invalidRecord }
            self.adjustmentContext = value
        }
    }
    func adjust(_ invoice: POSCreditAccountInvoice, operation: String, amount: Int?, items: [[String: Any]]?, collection: POSCreditAdjustmentContext.Collection?, source: String, reason: String, evidence: String) -> Bool {
        guard canAdjust, let context = adjustmentContext, context.version == invoice.version, context.accountVersion == accountVersion else { error = POSCreditAccountCopy.text("Invalid"); return false }
        var body = base(); body["operation"] = operation; body["commandId"] = UUID().uuidString; body["expectedAccountVersion"] = accountVersion
        body["invoiceId"] = invoice.id; body["expectedInvoiceVersion"] = invoice.version; body["reason"] = reason
        if let items { body["items"] = items } else { body["amountMinor"] = amount }
        if let collection { body["collectionId"] = collection.collectionId; body["expectedCollectionVersion"] = collection.version; body["evidenceReference"] = evidence }
        if !source.isEmpty { body["sourceAdjustmentId"] = source }
        submit("posCreditAdjustmentCommand", body: body)
        // The parent owns approval, uncertainty and exact-request recovery.
        // Return only after the full reason/evidence/request is safely stored.
        return pending?.commandID == body["commandId"] as? String
    }
    func cancelPending() {
        guard let original = pending, canRecover, original.result == nil,
              let proposal = try? JSONSerialization.jsonObject(with: original.request) as? [String: Any] else { return }
        var body = base(); body["action"] = "cancel"; body["kind"] = original.operation; body["commandId"] = original.commandID; body["proposal"] = proposal
        call("posCreditReviewCommand", body: body) { [weak self] value, response in
            guard let self, value["commandId"] as? String == original.commandID,
                  value["branchId"] as? String == original.branchID, value["customerId"] as? String == original.customerID else { throw POSCreditPendingStore.StoreError.invalidRecord }
            if value["status"] as? String == "committed" { self.recover(); return }
            guard value["status"] as? String == "cancelled" else { throw POSCreditPendingStore.StoreError.invalidRecord }
            var cancelled = original; cancelled.result = response
            try POSCreditAccountCommandStore.save(cancelled); self.pending = cancelled
            self.notice = POSCreditAccountCopy.text("Cancelled")
        }
    }
    func requestApproval() {
        guard let pending, canRecover, let proposalData = pending.approvalRequest,
              let envelope = try? JSONSerialization.jsonObject(with: proposalData) as? [String: Any],
              let operation = envelope["operation"] as? String, let proposal = envelope["command"] as? [String: Any] else { return }
        var body = base(); body["action"] = "request"; body["kind"] = operation; body["commandId"] = pending.commandID; body["proposal"] = proposal
        call("posCreditReviewCommand", body: body) { [weak self] _, _ in self?.notice = POSCreditAccountCopy.text("ApprovalRequested") }
    }
    func canApprove(_ review: POSCreditAdministrationPage.Review) -> Bool {
        guard permitted("pos.credit.approve"), review.makerUid != actorUID else { return false }
        let permissions = ["terms": "pos.credit_terms.manage", "reverse": "pos.credit.reverse", "creditNote": "pos.credit.refund", "refundPayout": "pos.credit.refund", "writeOff": "pos.credit.writeoff", "recoverWriteOff": "pos.credit.writeoff", "recordDispute": "pos.credit.reverse", "recoverDispute": "pos.credit.reverse", "writeOffDispute": "pos.credit.writeoff"]
        if let key = permissions[review.kind], !permitted(key) { return false }
        if review.kind == "refundPayout", !permitted("payments.refund") { return false }
        let finance = ["writeOff", "recoverWriteOff", "recordDispute", "recoverDispute", "writeOffDispute"]
        return !finance.contains(review.kind) || permitted("accounting.approve")
    }
    func approve(_ review: POSCreditAdministrationPage.Review, reason: String) {
        guard canApprove(review) else { return }
        var body = base(); body["action"] = "approve"; body["reviewId"] = review.reviewId; body["commandId"] = UUID().uuidString; body["reason"] = reason
        submit("posCreditReviewCommand", body: body)
    }
    func policy(enabled: Bool, limit: Int, reason: String) {
        guard permitted("pos.credit_terms.manage"), let policy = administration?.policy else { return }
        var body = base(); body["action"] = "setPolicy"; body["commandId"] = UUID().uuidString
        body["expectedVersion"] = policy.version; body["enabled"] = enabled; body["limitMinor"] = limit; body["reason"] = reason
        submit("posCreditPolicyCommand", body: body)
    }
    func approvePolicy(_ proposal: POSCreditAdministrationPage.PolicyProposal, reason: String) {
        guard permitted("pos.credit.approve"), proposal.makerUid != actorUID else { return }
        var body = base(); body["action"] = "approvePolicy"; body["commandId"] = UUID().uuidString; body["proposalId"] = proposal.proposalId; body["reason"] = reason
        submit("posCreditPolicyCommand", body: body)
    }
    func changeTerms(_ invoice: POSCreditAccountInvoice, due: String, reason: String) {
        guard permitted("pos.credit_terms.manage"), let template = context?.agreementTemplate else { return }
        var body = base(); body["commandId"] = UUID().uuidString; body["expectedAccountVersion"] = accountVersion
        body["invoiceId"] = invoice.id; body["expectedInvoiceVersion"] = invoice.version; body["expectedAgreementVersion"] = invoice.agreementVersion
        body["installments"] = [["dueDateKey": due, "amountMinor": invoice.amountDueMinor]]; body["reason"] = reason
        body["agreementTemplateId"] = template.id; body["agreementTemplateVersion"] = template.version
        body["agreementLocale"] = Language.isRTL() ? "ar" : "en"; body["termsAccepted"] = true
        submit("changeCreditTerms", body: body)
    }
    func service(_ collection: POSCreditAccountCollection, operation: String, reason: String, evidence: String, amount: Int?) {
        let permission = operation == "reversePosCollection" ? "pos.credit.reverse" : "pos.credit.clear"
        guard permitted(permission), pending == nil, !storageFailed else { return }
        var query = base(); query["kind"] = "collection"; query["collectionId"] = collection.id
        call("getCustomerReceivables", body: query) { [weak self] value, _ in
            guard let self, let rows = value["invoices"] as? [[String: Any]],
                  let version = value["collectionVersion"] as? Int, version == collection.version,
                  let accountVersion = value["accountVersion"] as? Int, accountVersion == self.accountVersion else { throw POSCreditPendingStore.StoreError.invalidRecord }
            var body = self.base(); body["commandId"] = UUID().uuidString; body["expectedAccountVersion"] = accountVersion
            body["collectionId"] = collection.id; body["expectedCollectionVersion"] = version; body["reason"] = reason
            if operation == "confirmPosCollectionClearing" { body["evidenceReference"] = evidence }
            var remaining = amount ?? 0
            body["allocations"] = rows.compactMap { row -> [String: Any]? in
                guard let id = row["invoiceId"] as? String, let version = row["version"] as? Int else { return nil }
                var allocation: [String: Any] = ["invoiceId": id, "expectedVersion": version]
                if operation == "reversePosCollection" {
                    let portion = min(remaining, row["confirmedMinor"] as? Int ?? 0)
                    guard portion > 0 else { return nil }
                    allocation["amountMinor"] = portion; remaining -= portion
                }
                return allocation
            }
            guard operation != "reversePosCollection" || remaining == 0 else { throw POSCreditPendingStore.StoreError.invalidRecord }
            self.submit(operation, body: body)
        }
    }
    func exportStatement() {
        guard canRead, let summary, !busy else { return }
        var lines = [POSCreditAccountCopy.text("Statement"), "\(POSCreditAccountCopy.text("AsOf")): \(asOf)", customerID, branchID,
            "\(POSCreditAccountCopy.text("Outstanding")): \(POSCreditAccountCopy.money(summary.outstandingMinor))",
            "\(POSCreditAccountCopy.text("Overdue")): \(POSCreditAccountCopy.money(summary.overdueMinor))",
            "\(POSCreditAccountCopy.text("Pending")): \(POSCreditAccountCopy.money(summary.pendingAmountMinor))",
            POSCreditAccountCopy.text("LoadedRecords")]
        lines += invoices.map { "\($0.documentNumber) · \(POSCreditAccountCopy.money($0.amountDueMinor)) · \($0.dueDateKey ?? "—")" }
        lines += collections.map { "\($0.documentNumber) · \(POSCreditAccountCopy.text($0.status)) · \(POSCreditAccountCopy.money($0.receivedMinor))" }
        if hasMore { lines.append(POSCreditAccountCopy.text("MoreAvailable")) }
        do { shareURL = try POSCreditAccountPDF.export(lines) } catch { self.error = POSCreditAccountCopy.text("ExportFailed") }
    }
}

struct POSCreditAccountLink: View {
    let customerID: String
    let branchID: String
    var compact = false
    @State private var presented = false
    var body: some View {
        if !customerID.isEmpty, POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) {
            Group {
                if compact {
                    Button { presented = true } label: {
                        Label(POSCreditAccountCopy.text("Title"), systemImage: "person.text.rectangle")
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(AdminSurface.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: AdminTouchTarget.minimum, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { presented = true } label: {
                        Label(POSCreditAccountCopy.text("Title"), systemImage: "person.text.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .sheet(isPresented: $presented) { POSCreditAccountSheet(customerID: customerID, branchID: branchID) }
        }
    }
}

struct POSCreditAccountSheet: View {
    @StateObject private var model: POSCreditAccountModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAging = false
    @ObservedObject private var branch = BranchContextStore.shared
    @State private var tab = "invoices"
    @State private var aging = "all"
    @State private var amounts: [String: String] = [:]
    @State private var method = "cash"
    @State private var reference = ""
    @State private var reviewing = false
    @State private var accepted = false
    @State private var servicing: POSCreditAccountCollection?
    @State private var revising: POSCreditAccountInvoice?
    @State private var adjusting: POSCreditAccountInvoice?
    @State private var reason = ""
    @State private var policyEnabled = false
    @State private var policyLimit = ""
    @State private var policyVersion: Int?
    @State private var stepUpPresented = false
    private enum InputField: Hashable {
        case invoiceAmount(String), reference, reason, policyLimit
    }
    @FocusState private var editing: InputField?
    init(customerID: String, branchID: String, initialTab: String = "invoices") {
        _model = StateObject(wrappedValue: POSCreditAccountModel(customerID: customerID, branchID: branchID))
        _tab = State(initialValue: initialTab)
    }
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private func money(_ amount: Int) -> String { POSCreditAccountCopy.money(amount) }
    private var selected: [String: Int] { amounts.compactMapValues { POSCreditCheckoutSheet.minor($0).flatMap { $0 > 0 ? $0 : nil } } }
    private var total: Int { selected.values.reduce(0, +) }
    private var methods: [String] { ["cash", "card", "cheque", "fawry", "bank_transfer"].filter { model.context?.receiptAccounts[$0] != nil && ($0 == "cash" || model.context?.pendingTendersEnabled == true) } }
    private var valid: Bool {
        guard model.canCollect, model.pending == nil, !model.storageFailed, !model.busy, amounts.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || POSCreditCheckoutSheet.minor($0) != nil }), !selected.isEmpty, selected.count <= 20, methods.contains(method), reference.count <= 200,
              method == "cash" || !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return model.invoices.filter { selected[$0.id] != nil }.allSatisfy { (selected[$0.id] ?? 0) <= $0.available }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                    if model.canRead {
                        accountContent
                    } else {
                        emptyState("Permission", symbol: "lock.shield")
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.base)
                .padding(.bottom, AdminSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AdminSurface.background)
            .font(AdminType.body)
            .foregroundStyle(AdminSurface.primaryText)
            .tint(AdminSurface.primary)
            .navigationTitle(t("Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("Title"))
                        .font(PPBrandFont.bold(18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.control, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("Close"))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { editing = nil } label: {
                        Text(t("Done")).font(AdminType.calloutBold)
                    }
                }
            }
            .onChange(of: tab) { _ in amounts = [:]; reviewing = false; accepted = false; if tab == "administration" { model.loadAdministration() } else { model.load(kind: tab) } }
            .onChange(of: branch.activeBranch?.branchID) { _ in dismiss() }
            .onChange(of: amounts) { _ in reviewing = false; accepted = false }
            .onChange(of: method) { _ in reviewing = false; accepted = false }
            .onChange(of: reference) { _ in reviewing = false; accepted = false }
            .onChange(of: model.needsStepUp) { value in
                if value && (model.permitted("pos.credit_terms.manage") || model.permitted("pos.credit.approve") || model.canAdjust || model.canCollect) {
                    stepUpPresented = true
                }
            }
            .sheet(item: $servicing) { collection in POSCreditServicingSheet(model: model, collection: collection) }
            .sheet(item: $adjusting) { invoice in POSCreditAdjustmentSheet(model: model, invoice: invoice) }
            .sheet(item: $revising) { invoice in POSCreditTermsSheet(model: model, invoice: invoice) }
            .sheet(isPresented: $stepUpPresented, onDismiss: { model.needsStepUp = false }) { POSCreditStepUpSheet() }
            .onChange(of: model.administration?.policy) { _ in refreshPolicyDraft() }
            .onChange(of: model.accountVersion) { _ in reviewing = false; accepted = false }
            .task {
                if tab == "administration" {
                    model.loadAdministration()
                } else {
                    model.load(kind: tab)
                }
            }
            .sheet(isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })) {
                if let url = model.shareURL { POSCreditAccountShare(url: url) }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
    }

    @ViewBuilder private var accountContent: some View {
        if let error = model.error {
            panel {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(AdminType.subheadline).foregroundStyle(AdminSurface.crimson)
                    .fixedSize(horizontal: false, vertical: true)
                action("Retry", symbol: "arrow.clockwise") {
                    if tab == "administration" { model.loadAdministration() } else { model.load(kind: tab) }
                }.disabled(model.busy)
            }
        }
        if model.busy {
            HStack(spacing: AdminSpacing.md) {
                ProgressView().tint(AdminSurface.primary)
                Text(t("Loading")).font(AdminType.subheadline)
            }
            .foregroundStyle(AdminSurface.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        if model.pending != nil { recovery }
        if let summary = model.summary { accountOverview(summary) }
        recordNavigation
        if tab == "invoices" {
            invoiceSection
            if model.canCollect, model.pending == nil { collectionSection }
        } else if tab == "collections" {
            collectionHistory
        } else {
            administrationSection
        }
        if model.hasMore, tab != "administration" {
            action("More", symbol: "arrow.down") { model.load(kind: tab, more: true) }
                .disabled(model.busy)
        }
    }

    private func accountOverview(_ summary: POSCreditAccountSummary) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    if let activeBranch = branch.activeBranch, activeBranch.branchID == model.branchID {
                        Label(activeBranch.localizedName(), systemImage: "building.2")
                            .font(AdminType.footnoteBold)
                    }
                    if !model.asOf.isEmpty {
                        Text("\(t("AsOf")) \(displayDate(model.asOf))").font(AdminType.footnote)
                    }
                }
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.exportStatement() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(model.busy ? AdminSurface.secondaryText : AdminSurface.primary)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.surface, in: Circle())
                }
                .buttonStyle(.plain).disabled(model.busy)
                .accessibilityLabel(t("Export"))
            }
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(t("Outstanding")).font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(money(summary.outstandingMinor))
                    .font(PPBrandFont.bold(48, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pos.credit.account.balance")
            panel {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AdminSpacing.lg) {
                        summaryMetric("Overdue", amount: summary.overdueMinor, attention: summary.overdueMinor > 0)
                        summaryMetric("Pending", amount: summary.pendingAmountMinor)
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: AdminSpacing.base) {
                        summaryMetric("Overdue", amount: summary.overdueMinor, attention: summary.overdueMinor > 0)
                        summaryMetric("Pending", amount: summary.pendingAmountMinor)
                    }
                }
                Rectangle().fill(AdminSurface.hairline).frame(height: 1).accessibilityHidden(true)
                valueRow(t("NextDue"), value: summary.nextDueDateKey.map(displayDate) ?? t("NoDueDate"))
                DisclosureGroup(isExpanded: $showsAging) {
                    VStack(alignment: .leading, spacing: AdminSpacing.md) {
                        ForEach(["current", "days1to30", "days31to60", "days61to90", "days90plus"], id: \.self) { key in
                            valueRow(t(key), value: money(summary.aging[key] ?? 0))
                        }
                        Text(t("AgingNotice")).font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, AdminSpacing.md)
                } label: {
                    Label(t("Aging"), systemImage: "clock")
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func summaryMetric(_ title: String, amount: Int, attention: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(t(title)).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            Text(money(amount)).font(AdminType.title3Bold).monospacedDigit()
                .foregroundStyle(attention ? AdminSurface.crimson : AdminSurface.primaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var recordNavigation: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(t("Records")).font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityAddTraits(.isHeader)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 4))
            layout {
                recordTab("invoices", title: "Invoices", symbol: "doc.text")
                recordTab("collections", title: "Collections", symbol: "arrow.down.left")
                recordTab("administration", title: "ManageTab", symbol: "slider.horizontal.3")
            }
            .padding(4)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        }
        .disabled(model.busy)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pos.credit.account.records")
    }

    private func recordTab(_ value: String, title: String, symbol: String) -> some View {
        Button { editing = nil; tab = value } label: {
            VStack(spacing: AdminSpacing.xs) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
                Text(t(title)).font(AdminType.footnoteBold)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, AdminSpacing.sm).padding(.vertical, AdminSpacing.sm)
            .foregroundStyle(tab == value ? AdminSurface.primary : AdminSurface.secondaryText)
            .background(tab == value ? AdminSurface.surface : Color.clear,
                        in: RoundedRectangle(cornerRadius: AdminRadius.medium))
            .overlay(alignment: .bottom) {
                if tab == value {
                    Capsule().fill(AdminSurface.primary).frame(width: 20, height: 3).padding(.bottom, 3)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t(value == "administration" ? "Administration" : title))
        .accessibilityAddTraits(tab == value ? .isSelected : [])
        .accessibilityIdentifier("pos.credit.account.tab.\(value)")
    }

    private var recovery: some View {
        panel {
            sectionHeading("Recovery", symbol: "arrow.clockwise.circle")
            Text(model.notice ?? t(model.canRecover ? "Uncertain" : "OtherPending"))
                .font(AdminType.subheadline).fixedSize(horizontal: false, vertical: true)
            if model.canRecover {
                action("Recover", symbol: "arrow.clockwise", prominent: true) { model.recover() }.disabled(model.busy)
                if model.pending?.result == nil {
                    action("CancelPending", symbol: "xmark.circle", role: .destructive) { model.cancelPending() }.disabled(model.busy)
                }
                if model.pending?.approvalRequest != nil {
                    action("RequestApproval", symbol: "person.crop.circle.badge.checkmark") { model.requestApproval() }.disabled(model.busy)
                }
                if model.needsStepUp { action("StepUp", symbol: "lock.shield") { stepUpPresented = true } }
                if model.pending?.result != nil {
                    action("Acknowledge", symbol: "checkmark") { model.acknowledge() }.disabled(model.busy)
                }
            }
        }
    }

    private var invoiceSection: some View {
        let visibleInvoices = model.invoices.filter(matches)
        return LazyVStack(alignment: .leading, spacing: AdminSpacing.md) {
            sectionHeading("Invoices", symbol: "doc.text")
            Picker(t("Filter"), selection: $aging) {
                Text(t("all")).tag("all"); Text(t("Overdue")).tag("overdue")
                Text(t("DueSoon")).tag("dueSoon"); Text(t("paid")).tag("paid")
                ForEach(["current", "days1to30", "days31to60", "days61to90", "days90plus"], id: \.self) { Text(t($0)).tag($0) }
            }
            .pickerStyle(.menu).font(AdminType.subheadlineBold)
            .frame(minHeight: 44).accessibilityLabel(t("Filter"))
            if visibleInvoices.isEmpty, !model.busy, model.error == nil {
                emptyState(model.invoices.isEmpty ? "EmptyInvoices" : "EmptyFilter", symbol: "doc.text.magnifyingglass")
                if aging != "all" { action("ShowAllInvoices", symbol: "line.3.horizontal.decrease") { aging = "all" } }
            }
            ForEach(visibleInvoices) { invoice in
                invoiceCard(invoice)
            }
        }
    }

    private func invoiceCard(_ invoice: POSCreditAccountInvoice) -> some View {
        panel {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: AdminSpacing.md) {
                    valueRow(t("Received"), value: money(invoice.amountPaidMinor))
                    valueRow(t("Refunded"), value: money(invoice.refundedMinor ?? 0))
                    valueRow(t("Pending"), value: money(invoice.pendingAmountMinor))
                    valueRow(t("Credits"), value: money(invoice.creditedMinor ?? 0))
                    valueRow(t("RefundLiability"), value: money(invoice.refundLiabilityMinor ?? 0))
                    if model.canAdjust, model.pending == nil {
                        action("AdjustBalance", symbol: "plus.forwardslash.minus") { adjusting = invoice }
                            .disabled(model.busy || model.storageFailed)
                    }
                    if !invoice.installments.isEmpty {
                        Text(t("InstallmentSchedule")).font(AdminType.footnoteBold).foregroundStyle(AdminSurface.secondaryText)
                        ForEach(invoice.installments) { row in
                            valueRow(displayDate(row.dueDateKey), value: money(row.due))
                        }
                    }
                    if model.permitted("pos.credit_terms.manage"), invoice.amountDueMinor > 0, model.pending == nil {
                        action("ChangeTerms", symbol: "calendar") { revising = invoice }.disabled(model.busy)
                    }
                    if model.canCollect, model.pending == nil, invoice.available > 0 {
                        field("Amount") {
                            TextField(t("Amount"), text: Binding(get: { amounts[invoice.id] ?? "" }, set: { amounts[invoice.id] = $0 }))
                                .keyboardType(.decimalPad).focused($editing, equals: .invoiceAmount(invoice.id))
                                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                                .environment(\.layoutDirection, .leftToRight)
                                .accessibilityLabel("\(t("Amount")) · \(invoice.documentNumber)")
                        }
                    }
                }.padding(.top, AdminSpacing.base)
            } label: {
                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    Text(invoice.documentNumber).font(AdminType.subheadlineBold)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(money(invoice.amountDueMinor)).font(AdminType.title2).monospacedDigit()
                    Text(t(invoice.paymentStatus)).font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                    if invoice.overdueMinor > 0 {
                        Label(t("Overdue"), systemImage: "exclamationmark.circle")
                            .font(AdminType.footnoteBold).foregroundStyle(AdminSurface.crimson)
                    }
                    if let amount = selected[invoice.id] {
                        Label("\(t("SelectedForCollection")) · \(money(amount))", systemImage: "checkmark.circle.fill")
                            .font(AdminType.footnoteBold).foregroundStyle(AdminSurface.primary)
                    }
                }
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, AdminSpacing.xs)
            }
        }
    }
    private func matches(_ invoice: POSCreditAccountInvoice) -> Bool {
        if aging == "overdue" { return invoice.overdueMinor > 0 }
        if aging == "paid" { return invoice.paymentStatus == "paid" }
        if ["current", "days1to30", "days31to60", "days61to90", "days90plus"].contains(aging) {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
            guard let today = f.date(from: model.asOf) else { return false }
            return invoice.installments.contains { row in
                guard row.due > 0, let date = f.date(from: row.dueDateKey) else { return false }
                let days = Int(today.timeIntervalSince(date) / 86400)
                let bucket = days <= 0 ? "current" : days <= 30 ? "days1to30" : days <= 60 ? "days31to60" : days <= 90 ? "days61to90" : "days90plus"
                return aging == bucket
            }
        }
        if aging == "dueSoon" {
            guard let due = invoice.dueDateKey else { return false }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: due), let today = formatter.date(from: model.asOf) else { return false }
            return date >= today && date.timeIntervalSince(today) <= 7 * 86400 && invoice.amountDueMinor > 0
        }
        return true
    }

    private var collectionSection: some View {
        panel {
            sectionHeading("Collect", symbol: "arrow.down.left.circle")
            Text(t("CollectionHelp")).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
            Picker(t("Method"), selection: $method) {
                ForEach(methods, id: \.self) { Text(t($0)).tag($0) }
            }.pickerStyle(.menu).frame(minHeight: 44)
            if methods.isEmpty {
                Text(t("NoCollectionMethod")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            }
            if method != "cash" {
                field("Reference") {
                    TextField(t("Reference"), text: $reference).focused($editing, equals: .reference)
                        .multilineTextAlignment(.leading)
                }
                Text(t("PendingNotice")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            }
            valueRow(t("Total"), value: money(total))
            if reviewing {
                Text(t("ReviewNotice")).font(AdminType.subheadline)
                ForEach(model.invoices.filter { selected[$0.id] != nil }) { invoice in
                    valueRow(invoice.documentNumber, value: money(selected[invoice.id] ?? 0), identifier: true)
                }
                Toggle(t("Accept"), isOn: $accepted).font(AdminType.subheadline)
                action("Confirm", symbol: "checkmark", prominent: true) {
                    model.collect(amounts: selected, method: method, reference: reference)
                    if model.pending?.operation == "recordPosCollection" { amounts = [:]; reference = "" }
                    reviewing = false; accepted = false
                }.disabled(!valid || !accepted)
            } else {
                action("Review", symbol: "checklist", prominent: true) { editing = nil; reviewing = true }
                    .disabled(!valid)
            }
        }
    }
    private func refreshPolicyDraft() {
        guard let policy = model.administration?.policy else { policyVersion = nil; return }
        policyEnabled = policy.enabled
        let cents = policy.limitMinor % 100
        policyLimit = String(policy.limitMinor / 100) + "." + (cents < 10 ? "0" : "") + String(cents)
        policyVersion = policy.version
    }

    private var administrationSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            sectionHeading("Administration", symbol: "slider.horizontal.3")
            if let data = model.administration {
                panel {
                    Text(t("CurrentPolicy")).font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Label(t(data.policy.enabled ? "Enabled" : "Disabled"),
                          systemImage: data.policy.enabled ? "checkmark.circle" : "pause.circle")
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(data.policy.enabled ? AdminSurface.primary : AdminSurface.secondaryText)
                    Text(money(data.policy.limitMinor)).font(PPBrandFont.bold(32, relativeTo: .title)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    Text(t("Limit")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                }
            }
            if model.needsStepUp && (model.permitted("pos.credit_terms.manage") || model.permitted("pos.credit.approve")) {
                panel {
                    Label(t("StepUp"), systemImage: "lock.shield")
                        .font(AdminType.headlineBold).accessibilityAddTraits(.isHeader)
                    Text(t("VerificationHelp")).font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText).fixedSize(horizontal: false, vertical: true)
                    action("StepUp", symbol: "lock.shield") { editing = nil; stepUpPresented = true }
                }
            }
            panel {
                field("Reason") {
                    TextField(t("ReasonPlaceholder"), text: $reason, axis: .vertical)
                        .lineLimit(2...5).focused($editing, equals: .reason).multilineTextAlignment(.leading)
                        .accessibilityLabel(t("Reason"))
                }
                Text(t("ReasonHelp")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                if reason.count > 500 {
                    Label(t("ReasonTooLong"), systemImage: "exclamationmark.circle")
                        .font(AdminType.footnote).foregroundStyle(AdminSurface.crimson)
                }
                if let data = model.administration, model.permitted("pos.credit_terms.manage") {
                    Divider().overlay(AdminSurface.hairline)
                    Text(t("EditPolicy")).font(AdminType.headlineBold).accessibilityAddTraits(.isHeader)
                    Toggle(t("EnableCredit"), isOn: $policyEnabled).font(AdminType.bodyBold)
                    field("Limit") {
                        TextField(t("Limit"), text: $policyLimit)
                            .keyboardType(.decimalPad).focused($editing, equals: .policyLimit)
                            .font(AdminType.title3Bold).monospacedDigit()
                            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    action("SavePolicy", symbol: "arrow.up.doc", prominent: true) {
                        if let amount = POSCreditCheckoutSheet.minor(policyLimit) {
                            model.policy(enabled: policyEnabled, limit: amount, reason: reason)
                        }
                    }
                    .disabled(model.busy || model.pending != nil || policyVersion != data.policy.version || POSCreditCheckoutSheet.minor(policyLimit) == nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 500)
                }
            }
            if let data = model.administration {
                if !data.policyProposals.isEmpty || !data.rows.isEmpty {
                    sectionHeading("ReviewQueue", symbol: "checklist")
                }
                ForEach(data.policyProposals) { proposal in
                    panel {
                        Text(t("PolicyProposal")).font(AdminType.headlineBold)
                        valueRow(t("Limit"), value: money(proposal.limitMinor))
                        valueRow(t("Status"), value: t(proposal.enabled ? "Enabled" : "Disabled"))
                        if model.permitted("pos.credit.approve"), proposal.makerUid != model.actorUID {
                            action("Approve", symbol: "checkmark.seal", prominent: true) { model.approvePolicy(proposal, reason: reason) }
                                .disabled(model.busy || model.pending != nil || reason.isEmpty || reason.count > 500)
                        }
                    }
                }
                if data.morePolicies {
                    Text(t("MorePolicyProposals")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                }
                ForEach(data.rows) { review in
                    panel {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: AdminSpacing.md) {
                                ForEach(review.lines, id: \.self) { Text($0).textSelection(.enabled) }
                                if model.canApprove(review), review.status == "pending_approval" {
                                    action("Approve", symbol: "checkmark.seal", prominent: true) { model.approve(review, reason: reason) }
                                        .disabled(model.busy || model.pending != nil || reason.isEmpty || reason.count > 500)
                                }
                            }.padding(.top, AdminSpacing.base)
                        } label: {
                            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                                Text(t(review.kind)).font(AdminType.headlineBold).foregroundStyle(AdminSurface.primaryText)
                                Text(t(review.status)).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                            }.frame(minHeight: 44).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if data.nextCursor != nil {
                    action("More", symbol: "arrow.down") { model.loadAdministration(more: true) }.disabled(model.busy)
                }
            }
            action("Refresh", symbol: "arrow.clockwise") { model.loadAdministration() }.disabled(model.busy)
        }
        .onAppear { refreshPolicyDraft() }
    }

    private var collectionHistory: some View {
        LazyVStack(alignment: .leading, spacing: AdminSpacing.md) {
            sectionHeading("Collections", symbol: "arrow.down.left.circle")
            if model.collections.isEmpty, !model.busy, model.error == nil {
                emptyState("EmptyCollections", symbol: "tray")
            }
            ForEach(model.collections) { collection in
                panel {
                    Text(collection.documentNumber).font(AdminType.headlineBold)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(t(collection.status)).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                    valueRow(t("Received"), value: money(collection.receivedMinor))
                    valueRow(t("Pending"), value: money(collection.pendingAmountMinor))
                    if collection.reversedMinor > 0 { valueRow(t("Reversed"), value: money(collection.reversedMinor)) }
                    action("Receipt", symbol: "doc.richtext") { model.receipt(collection) }.disabled(model.busy)
                    if model.permitted("pos.credit.clear") || model.permitted("pos.credit.reverse") {
                        action("Service", symbol: "slider.horizontal.3") { servicing = collection }
                            .disabled(model.busy || model.pending != nil || model.storageFailed)
                    }
                }
            }
        }
    }

    // Presentation helpers deliberately keep values and actions with the existing account owner.
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AdminSpacing.screenMargin)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.5).allowsHitTesting(false)
            }
    }

    private func sectionHeading(_ title: String, symbol: String) -> some View {
        Label(t(title), systemImage: symbol)
            .font(AdminType.title3Bold).foregroundStyle(AdminSurface.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func valueRow(_ title: String, value: String, identifier: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.base) {
                valueTitle(title, identifier: identifier).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: AdminSpacing.sm)
                Text(value).font(AdminType.bodyBold).monospacedDigit().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                valueTitle(title, identifier: identifier)
                Text(value).font(AdminType.bodyBold).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AdminSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func valueTitle(_ title: String, identifier: Bool) -> some View {
        Text(title).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
            .environment(\.layoutDirection, identifier ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(t(title)).font(AdminType.footnoteBold).foregroundStyle(AdminSurface.secondaryText)
            content()
                .font(AdminType.body).foregroundStyle(AdminSurface.primaryText)
                .padding(.horizontal, AdminSpacing.md).padding(.vertical, AdminSpacing.md)
                .frame(minHeight: AdminTouchTarget.inputField)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: AdminRadius.medium)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 1).allowsHitTesting(false)
                }
        }
    }

    private func emptyState(_ key: String, symbol: String) -> some View {
        panel {
            Image(systemName: symbol).font(.system(size: 26, weight: .light))
                .foregroundStyle(AdminSurface.primary).accessibilityHidden(true)
            Text(t(key)).font(AdminType.bodyBold).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func action(_ title: String, symbol: String, prominent: Bool = false,
                        role: ButtonRole? = nil, perform: @escaping () -> Void) -> some View {
        Button(role: role, action: perform) {
            Label(t(title), systemImage: symbol)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(AccountActionStyle(prominent: prominent))
    }

    private func displayDate(_ key: String) -> String { AccountDates.text(key) }

    @MainActor private enum AccountDates {
        // Only format server-provided business dates; never infer a due date from device time.
        static let parser: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            return formatter
        }()
        static let arabic = formatter(locale: "ar_QA")
        static let english = formatter(locale: "en_QA")

        static func formatter(locale: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: locale)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateStyle = .medium
            return formatter
        }
        static func text(_ key: String) -> String {
            guard let date = parser.date(from: key) else { return key }
            return (Language.isRTL() ? arabic : english).string(from: date)
        }
    }

    private struct AccountActionStyle: ButtonStyle {
        var prominent = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            let destructive = configuration.role == .destructive
            let foreground = !isEnabled ? AdminSurface.secondaryText
                : prominent ? Color.white : destructive ? AdminSurface.crimson : AdminSurface.primary
            configuration.label
                .font(AdminType.calloutBold)
                .foregroundStyle(foreground)
                .padding(.horizontal, AdminSpacing.base).padding(.vertical, AdminSpacing.md)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                .background(isEnabled && prominent ? AdminSurface.primary : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AdminRadius.button))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(reduceMotion ? nil : AdminAnimation.fast, value: configuration.isPressed)
        }
    }
}

@MainActor
private enum POSCreditAccountPDF {
    static func export(_ lines: [String]) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data: Data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage(); var y: CGFloat = 36
            for line in lines {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = Language.isRTL() ? .right : .left
                paragraph.baseWritingDirection = Language.isRTL() ? .rightToLeft : .leftToRight
                let text = NSAttributedString(string: line, attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .paragraphStyle: paragraph, .foregroundColor: UIColor.black])
                let height = ceil(text.boundingRect(with: CGSize(width: 523, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 12
                if y + height > 806 { context.beginPage(); y = 36 }
                text.draw(in: CGRect(x: 36, y: y, width: 523, height: height)); y += height
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("credit-\(UUID().uuidString).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}
private struct POSCreditAccountShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum POSCreditJSON: Decodable {
    case object([String: POSCreditJSON]), array([POSCreditJSON]), string(String), number(Int), decimal(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Int.self) { self = .number(v) }
        else if let v = try? value.decode(Double.self) { self = .decimal(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([String: POSCreditJSON].self) { self = .object(v) }
        else { self = .array(try value.decode([POSCreditJSON].self)) }
    }
    @MainActor
    func reviewLines() -> [String] {
        let labels = ["totalMinor": "Total", "amountMinor": "Amount", "dueDateKey": "NextDue", "method": "Method", "reference": "Reference", "reason": "Reason", "invoiceId": "Invoice", "collectionId": "Collection", "sourceAdjustmentId": "OriginalAdjustment", "evidenceReference": "Evidence", "itemIndex": "ItemID", "unitIds": "ExactUnits", "name": "Item", "productId": "ItemID", "quantity": "Quantity", "unitPriceMinor": "UnitPrice", "unitPrice": "UnitPrice", "fulfillment": "Fulfillment", "exceptions": "Exceptions"]
        switch self {
        case .array(let rows): return rows.flatMap { $0.reviewLines() }
        case .object(let fields): return fields.keys.sorted().flatMap { key -> [String] in
            guard let value = fields[key] else { return [] }
            if let label = labels[key] {
                switch value {
                case .number(let number):
                    let formatted = key.hasSuffix("Minor") ? POSCreditAccountCopy.money(number) : key == "unitPrice" ? POSReceiptFormat.currency(Double(number), code: "QAR") : String(number)
                    return ["\(POSCreditAccountCopy.text(label)): \(formatted)"]
                case .decimal(let number):
                    let formatted = key.hasSuffix("Minor") ? POSReceiptFormat.currency(number / 100, code: "QAR") : key == "unitPrice" ? POSReceiptFormat.currency(number, code: "QAR") : POSReceiptFormat.quantity(number)
                    return ["\(POSCreditAccountCopy.text(label)): \(formatted)"]
                case .string(let string): return ["\(POSCreditAccountCopy.text(label)): \(["method", "fulfillment"].contains(key) ? POSCreditAccountCopy.text(string) : string)"]
                case .array(let list): return list.compactMap { if case .string(let v) = $0 { return key == "unitIds" ? v : POSCreditAccountCopy.text(v) }; return nil }
                default: break
                }
            }
            return ["review", "terms", "deposit", "items", "installments", "allocations"].contains(key) ? value.reviewLines() : []
        }
        default: return []
        }
    }
}
struct POSCreditAdministrationPage: Decodable {
    struct Policy: Decodable, Equatable { let version: Int; let enabled: Bool; let limitMinor: Int }
    struct PolicyProposal: Decodable, Identifiable {
        let proposalId: String; let makerUid: String; let enabled: Bool; let limitMinor: Int
        var id: String { proposalId }
    }
    struct Review: Decodable, Identifiable {
        let reviewId: String; let kind: String; let makerUid: String; let status: String
        private let proposal: POSCreditJSON
        var id: String { reviewId }
        @MainActor var lines: [String] { proposal.reviewLines() }
    }
    let branchId: String; let customerId: String; let policy: Policy
    let rows: [Review]; let policyProposals: [PolicyProposal]; let morePolicies: Bool; let nextCursor: String?
}

private struct POSCreditServicingSheet: View {
    @ObservedObject var model: POSCreditAccountModel
    let collection: POSCreditAccountCollection
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var evidence = ""
    @State private var amount = ""
    @State private var accepted = false
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private var valid: Bool { !model.busy && model.pending == nil && accepted && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.count <= 500 }
    var body: some View {
        NavigationStack {
            Form {
                Text(collection.documentNumber).font(.headline)
                Text(t(collection.status))
                LabeledContent(t("Received"), value: POSCreditAccountCopy.money(collection.receivedMinor))
                LabeledContent(t("Pending"), value: POSCreditAccountCopy.money(collection.pendingAmountMinor))
                TextField(t("Reason"), text: $reason, axis: .vertical)
                if collection.status == "pending" {
                    TextField(t("Evidence"), text: $evidence, axis: .vertical)
                    Text(t("ClearNotice"))
                } else if ["cleared", "partially_reversed"].contains(collection.status) {
                    TextField(t("Amount"), text: $amount).keyboardType(.decimalPad)
                    Text(t("ReverseNotice"))
                }
                Toggle(t("Accept"), isOn: $accepted)
                if collection.status == "pending", model.permitted("pos.credit.clear") {
                    Button(t("Clear")) { model.service(collection, operation: "confirmPosCollectionClearing", reason: reason, evidence: evidence, amount: nil); dismiss() }
                        .disabled(!valid || evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || evidence.count > 200).frame(minHeight: 44)
                }
                if ["pending", "requires_review"].contains(collection.status), model.permitted("pos.credit.clear") {
                    Button(t("Reject"), role: .destructive) { model.service(collection, operation: "rejectPosCollectionTender", reason: reason, evidence: "", amount: nil); dismiss() }.disabled(!valid).frame(minHeight: 44)
                }
                if ["cleared", "partially_reversed"].contains(collection.status), model.permitted("pos.credit.reverse") {
                    Button(t("Reverse"), role: .destructive) { model.service(collection, operation: "reversePosCollection", reason: reason, evidence: "", amount: POSCreditCheckoutSheet.minor(amount)); dismiss() }
                        .disabled(!valid || (POSCreditCheckoutSheet.minor(amount) ?? 0) <= 0 || (POSCreditCheckoutSheet.minor(amount) ?? 0) > collection.receivedMinor).frame(minHeight: 44)
                }
            }
            .navigationTitle(t("Service"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("Service"))
                        .font(PPBrandFont.bold(18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(t("Close"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
            }
            .onChange(of: reason) { _ in accepted = false }.onChange(of: evidence) { _ in accepted = false }.onChange(of: amount) { _ in accepted = false }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }
}
private struct POSCreditTermsSheet: View {
    @ObservedObject var model: POSCreditAccountModel
    let invoice: POSCreditAccountInvoice
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var reason = ""
    @State private var accepted = false
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private var dateKey: String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    var body: some View {
        NavigationStack {
            Form {
                Text(invoice.documentNumber).font(.headline)
                LabeledContent(t("Outstanding"), value: POSCreditAccountCopy.money(invoice.amountDueMinor))
                Text(t("TermsNotice"))
                DatePicker(t("NextDue"), selection: $date, displayedComponents: .date)
                TextField(t("Reason"), text: $reason, axis: .vertical)
                if let template = model.context?.agreementTemplate, let agreement = invoice.agreement {
                    Text(["customer": agreement.interpolationValues["customer"] ?? "", "currency": "QAR", "total": String(format: "%.2f", Double(invoice.totalMinor) / 100), "deposit": agreement.interpolationValues["deposit"] ?? "", "due": String(format: "%.2f", Double(invoice.amountDueMinor) / 100), "schedule": "\(dateKey): \(String(format: "%.2f", Double(invoice.amountDueMinor) / 100))"].reduce(Language.isRTL() ? template.ar : template.en) { result, item in result.replacingOccurrences(of: "{\(item.key)}", with: item.value) })
                }
                Toggle(t("AcceptTerms"), isOn: $accepted)
                Button(t("ChangeTerms")) { model.changeTerms(invoice, due: dateKey, reason: reason); dismiss() }
                    .disabled(model.busy || model.pending != nil || !accepted || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 500 || dateKey < model.asOf || model.context?.agreementTemplate == nil || invoice.agreement == nil).frame(minHeight: 44)
            }
            .navigationTitle(t("ChangeTerms"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("ChangeTerms"))
                        .font(PPBrandFont.bold(18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(t("Close"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
            }
                .onChange(of: date) { _ in accepted = false }.onChange(of: reason) { _ in accepted = false }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }
}

/// Uses the current Firebase Auth session. No password/code is persisted, and
/// only a refreshed signed token with the server-approved factor is accepted.
@MainActor
struct POSCreditStepUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var resolver: MultiFactorResolver?
    @State private var enrollment = ""
    private enum InputField: Hashable { case password, code }
    @FocusState private var focusedField: InputField?
    @AccessibilityFocusState private var errorFocused: Bool
    @ScaledMetric(relativeTo: .caption) private var stepSize: CGFloat = 26
    private let actorUID = Auth.auth().currentUser?.uid
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private var isCodeStep: Bool { resolver != nil }
    private var canSubmit: Bool {
        !busy && (resolver == nil ? !password.isEmpty : code.count == 6 && !enrollment.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                    verificationProgress
                    phaseIntroduction
                    if let error { errorMessage(error) }
                    credentialEntry
                    Label(t("StepUpFinancialBoundary"), systemImage: "info.circle")
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.lg)
                .padding(.bottom, AdminSpacing.lg)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AdminSurface.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { actionDock }
            .navigationTitle(t("StepUp"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("StepUp"))
                        .font(PPBrandFont.bold(18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        focusedField = nil
                        password = ""
                        code = ""
                        resolver = nil
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.control, in: Circle())
                    }
                    .buttonStyle(.plain).disabled(busy)
                    .accessibilityLabel(t("Close"))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { focusedField = nil } label: {
                        Text(t("Done")).font(AdminType.calloutBold)
                    }
                }
            }
            .interactiveDismissDisabled(busy)
            .onChange(of: isCodeStep) { value in
                if value { focusedField = .code }
            }
            .onChange(of: error) { value in
                errorFocused = value != nil
            }
            .onDisappear { password = ""; code = ""; resolver = nil; focusedField = nil }
        }
        .font(AdminType.body)
        .foregroundStyle(AdminSurface.primaryText)
        .tint(AdminSurface.primary)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var verificationProgress: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.md))
        return layout {
            stageMarker(1, title: "Password", current: !isCodeStep, completed: isCodeStep)
            if !dynamicTypeSize.isAccessibilitySize {
                Rectangle().fill(AdminSurface.hairline).frame(width: 20, height: 1)
            }
            stageMarker(2, title: "Authenticator", current: isCodeStep, completed: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t(isCodeStep ? "StepUpCodeProgress" : "StepUpPasswordProgress"))
        .accessibilityIdentifier("pos.credit.stepup.progress")
        .animation(reduceMotion ? nil : AdminAnimation.fast, value: isCodeStep)
    }

    private func stageMarker(_ number: Int, title: String, current: Bool, completed: Bool) -> some View {
        HStack(alignment: .center, spacing: AdminSpacing.sm) {
            ZStack {
                Circle().fill(current ? AdminSurface.primary : AdminSurface.control)
                if completed {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                } else {
                    Text(number.formatted(.number.locale(Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA"))))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(current ? Color.white : AdminSurface.secondaryText)
                }
            }.frame(width: stepSize, height: stepSize)
            Text(t(title)).font(AdminType.footnoteBold)
                .foregroundStyle(current || completed ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var phaseIntroduction: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            Image(systemName: isCodeStep ? "number" : "key.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 56, height: 56)
                .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .accessibilityHidden(true)
            Text(t(isCodeStep ? "StepUpCodeTitle" : "StepUpPasswordTitle"))
                .font(AdminType.title).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(t(isCodeStep ? "StepUpCodeHelp" : "StepUpPasswordHelp"))
                .font(AdminType.body).foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorMessage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Label(t("StepUpErrorTitle"), systemImage: "exclamationmark.circle")
                .font(AdminType.subheadlineBold).foregroundStyle(AdminSurface.crimson)
            Text(message).font(AdminType.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .strokeBorder(AdminSurface.crimson.opacity(0.35), lineWidth: 1).allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($errorFocused)
        .accessibilityIdentifier("pos.credit.stepup.error")
    }

    private var credentialEntry: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            if let resolver { authenticatorChoice(resolver) }
            VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                Text(t(isCodeStep ? "OneTimeCode" : "Password"))
                    .font(AdminType.subheadlineBold)
                Group {
                    if isCodeStep {
                        SecureField("", text: localizedCode, prompt: Text(t("StepUpCodePlaceholder")).font(AdminType.body).foregroundColor(AdminSurface.secondaryText))
                            .font(AdminType.title2).monospacedDigit()
                            .textContentType(.oneTimeCode).keyboardType(.numberPad)
                            .focused($focusedField, equals: .code)
                            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                            .environment(\.layoutDirection, .leftToRight)
                            .accessibilityLabel(t("OneTimeCode"))
                            .accessibilityHint(t("StepUpCodeHelp"))
                            .accessibilityIdentifier("pos.credit.stepup.code")
                    } else {
                        SecureField("", text: $password, prompt: Text(t("StepUpPasswordPlaceholder")).foregroundColor(AdminSurface.secondaryText))
                            .font(AdminType.body)
                            .textContentType(.password).submitLabel(.continue)
                            .focused($focusedField, equals: .password)
                            .multilineTextAlignment(.leading)
                            .accessibilityLabel(t("Password"))
                            .accessibilityIdentifier("pos.credit.stepup.password")
                    }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .privacySensitive()
                .onSubmit { submit() }
                .padding(.horizontal, AdminSpacing.base)
                .frame(minHeight: 60)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .strokeBorder(focusedField == nil ? AdminSurface.hairline : AdminSurface.primary,
                                      lineWidth: focusedField == nil ? 1 : 1.5)
                        .allowsHitTesting(false)
                }
            }
        }
        .disabled(busy)
    }

    private func authenticatorChoice(_ resolver: MultiFactorResolver) -> some View {
        let hints = resolver.hints.filter { $0.factorID == "totp" }
        let selectedName = hints.first { $0.uid == enrollment }?.displayName
        let displayName = selectedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? t("Authenticator")
        return VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(t("StepUpRegisteredAuthenticator")).font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
            if hints.count > 1 {
                Menu {
                    Picker(t("Authenticator"), selection: $enrollment) {
                        ForEach(hints, id: \.uid) { hint in
                            Text(hint.displayName ?? t("Authenticator")).tag(hint.uid)
                        }
                    }
                } label: {
                    HStack(spacing: AdminSpacing.md) {
                        Text(title).font(AdminType.subheadlineBold)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, AdminSpacing.base).padding(.vertical, AdminSpacing.md)
                    .frame(minHeight: 44)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                }
                .accessibilityLabel(t("Authenticator")).accessibilityValue(title)
            } else {
                Label(title, systemImage: "key.horizontal")
                    .font(AdminType.subheadlineBold).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionDock: some View {
        Button { submit() } label: {
            HStack(spacing: AdminSpacing.md) {
                if busy { ProgressView().tint(AdminSurface.secondaryText).accessibilityHidden(true) }
                Text(t(busy ? (isCodeStep ? "StepUpCheckingCode" : "StepUpCheckingPassword")
                       : (isCodeStep ? "Verify" : "StepUpContinue")))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                if !busy {
                    Image(systemName: isCodeStep ? "checkmark.shield" : "arrow.forward")
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(VerificationActionStyle())
        .disabled(!canSubmit)
        .accessibilityIdentifier("pos.credit.stepup.submit")
        .frame(maxWidth: 520)
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.background)
    }

    private var localizedCode: Binding<String> {
        Binding(get: { code }, set: { value in
            // Normalize decimal glyphs only. Keep leading zeros and reject-length behavior;
            // never truncate a paste or silently discard unsupported characters.
            code = value.map { character in
                guard character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
                      let digit = character.wholeNumberValue, (0...9).contains(digit) else { return String(character) }
                return String(digit)
            }.joined()
        })
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        authenticate()
    }

    private struct VerificationActionStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(AdminType.headlineBold)
                .foregroundStyle(isEnabled ? Color.white : AdminSurface.secondaryText)
                .padding(.horizontal, AdminSpacing.base).padding(.vertical, AdminSpacing.base)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(isEnabled ? AdminSurface.primary : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AdminRadius.card))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(reduceMotion ? nil : AdminAnimation.fast, value: configuration.isPressed)
        }
    }
    private func authenticate() {
        guard let user = Auth.auth().currentUser, user.uid == actorUID, let email = user.email else { error = t("StepUpUnavailable"); return }
        busy = true; error = nil
        let secret = password, otp = code; password = ""; code = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                if let resolver {
                    let assertion = TOTPMultiFactorGenerator.assertionForSignIn(withEnrollmentID: enrollment, oneTimePassword: otp)
                    let signedInUID = try await resolveStepUp(using: resolver, assertion: assertion)
                    guard signedInUID == actorUID else { throw POSCreditPendingStore.StoreError.invalidRecord }
                } else {
                    do {
                        let signedInUID = try await reauthenticateForStepUp(user, credential: EmailAuthProvider.credential(withEmail: email, password: secret))
                        guard signedInUID == actorUID else { throw POSCreditPendingStore.StoreError.invalidRecord }
                    }
                    catch {
                        guard Auth.auth().currentUser?.uid == actorUID,
                              let next = (error as NSError).userInfo[AuthErrors.userInfoMultiFactorResolverKey] as? MultiFactorResolver,
                              let hint = next.hints.first(where: { $0.factorID == "totp" }) else { throw error }
                        resolver = next; enrollment = hint.uid; return
                    }
                }
                guard let current = Auth.auth().currentUser, current.uid == actorUID else { throw POSCreditPendingStore.StoreError.invalidRecord }
                let secondFactor = try await refreshedSecondFactor(for: current)
                guard Auth.auth().currentUser?.uid == actorUID, secondFactor == "totp" else { throw POSCreditPendingStore.StoreError.invalidRecord }
                dismiss()
            } catch { self.error = t("StepUpUnavailable") }
        }
    }

    // Firebase 12.12.1's async overloads cross executors with non-Sendable
    // session objects. Start its callback APIs on this actor and resume with
    // scalar results only; resolver failures are not guaranteed on main.
    private func resolveStepUp(using resolver: MultiFactorResolver, assertion: MultiFactorAssertion) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            resolver.resolveSignIn(with: assertion) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let uid = result?.user.uid { continuation.resume(returning: uid) }
                else { continuation.resume(throwing: POSCreditPendingStore.StoreError.invalidRecord) }
            }
        }
    }

    private func reauthenticateForStepUp(_ user: User, credential: AuthCredential) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.reauthenticate(with: credential) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let uid = result?.user.uid { continuation.resume(returning: uid) }
                else { continuation.resume(throwing: POSCreditPendingStore.StoreError.invalidRecord) }
            }
        }
    }

    private func refreshedSecondFactor(for user: User) async throws -> String? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            user.getIDTokenResult(forcingRefresh: true) { token, error in
                if let error { continuation.resume(throwing: error) }
                else if let token {
                    continuation.resume(returning: (token.claims["firebase"] as? [String: Any])?["sign_in_second_factor"] as? String)
                } else { continuation.resume(throwing: POSCreditPendingStore.StoreError.invalidRecord) }
            }
        }
    }
}
