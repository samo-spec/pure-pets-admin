import Foundation
import SwiftUI
import UIKit
import FirebaseAuth
import CryptoKit

enum POSCreditAccountCopy {
    static func text(_ key: String) -> String { Language.get("POS_CreditAccount_" + key, alter: nil) }
    static func money(_ value: Int) -> String { POSReceiptFormat.currency(Double(value) / 100, code: "QAR") }
    static func permitted(_ permission: String, branchID: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, let staff = PPStaffAuth.shared().cachedCurrentStaff,
              staff.uid == uid, staff.isActive(), !branchID.isEmpty else { return false }
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
        catch { storageFailed = true; error = POSCreditAccountCopy.text("StorageFailed") }
    }
    func base() -> [String: Any] { ["contractVersion": 1, "customerId": customerID, "branchId": branchID, "currency": "QAR"] }
    func call(_ operation: String, body: [String: Any], completion: @escaping ([String: Any], Data) throws -> Void) {
        do { try call(operation, data: JSONSerialization.data(withJSONObject: body, options: .sortedKeys), completion: completion) }
        catch { error = POSCreditAccountCopy.text("Invalid") }
    }
    func call(_ operation: String, data: Data, completion: @escaping ([String: Any], Data) throws -> Void) throws {
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
        } catch { error = POSCreditAccountCopy.text("StorageFailed") }
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
        } catch { error = POSCreditAccountCopy.text("StorageFailed") }
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
        catch { error = POSCreditAccountCopy.text("StorageFailed") }
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
    @State private var presented = false
    var body: some View {
        if !customerID.isEmpty, POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) {
            Button { presented = true } label: {
                Label(POSCreditAccountCopy.text("Title"), systemImage: "person.text.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $presented) { POSCreditAccountSheet(customerID: customerID, branchID: branchID) }
        }
    }
}

struct POSCreditAccountSheet: View {
    @StateObject private var model: POSCreditAccountModel
    @Environment(\.dismiss) private var dismiss
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
    @FocusState private var editing: Bool
    init(customerID: String, branchID: String) { _model = StateObject(wrappedValue: POSCreditAccountModel(customerID: customerID, branchID: branchID)) }
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
            Form {
                if !model.canRead { Text(t("Permission")) }
                else {
                    if let error = model.error { Section { Text(error).foregroundStyle(.red); Button(t("Retry")) { if tab == "administration" { model.loadAdministration() } else { model.load(kind: tab) } }.disabled(model.busy) } }
                    if model.busy { ProgressView(t("Loading")) }
                    if model.pending != nil { recovery }
                    if let summary = model.summary {
                        Section(t("Title")) {
                            LabeledContent(t("Outstanding"), value: money(summary.outstandingMinor))
                            LabeledContent(t("Overdue"), value: money(summary.overdueMinor))
                            LabeledContent(t("Pending"), value: money(summary.pendingAmountMinor))
                            LabeledContent(t("NextDue"), value: summary.nextDueDateKey ?? "—")
                            LabeledContent(t("AsOf"), value: model.asOf)
                            Button(t("Export")) { model.exportStatement() }.frame(minHeight: 44).disabled(model.busy)
                        }
                        Section(t("Aging")) {
                            ForEach(["current", "days1to30", "days31to60", "days61to90", "days90plus"], id: \.self) { key in
                                LabeledContent(t(key), value: money(summary.aging[key] ?? 0))
                            }
                        }
                    }
                    Picker(t("Records"), selection: $tab) { Text(t("Invoices")).tag("invoices"); Text(t("Collections")).tag("collections"); Text(t("Administration")).tag("administration") }
                        .disabled(model.busy)
                        .onChange(of: tab) { _ in amounts = [:]; reviewing = false; accepted = false; if tab == "administration" { model.loadAdministration() } else { model.load(kind: tab) } }
                    if tab == "invoices" { invoiceSection; if model.canCollect, model.pending == nil { collectionSection } }
                    else if tab == "collections" { collectionHistory } else { administrationSection }
                    if model.hasMore, tab != "administration" { Button(t("More")) { model.load(kind: tab, more: true) }.disabled(model.busy) }
                }
            }
            .navigationTitle(t("Title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Close")) { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(t("Done")) { editing = false } }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .onChange(of: branch.activeBranch?.branchID) { _ in dismiss() }
            .onChange(of: amounts) { _ in reviewing = false; accepted = false }
            .onChange(of: method) { _ in reviewing = false; accepted = false }
            .onChange(of: reference) { _ in reviewing = false; accepted = false }
            .onChange(of: model.needsStepUp) { value in if value { stepUpPresented = true } }
            .sheet(item: $servicing) { collection in POSCreditServicingSheet(model: model, collection: collection) }
            .sheet(item: $adjusting) { invoice in POSCreditAdjustmentSheet(model: model, invoice: invoice) }
            .sheet(item: $revising) { invoice in POSCreditTermsSheet(model: model, invoice: invoice) }
            .sheet(isPresented: $stepUpPresented, onDismiss: { model.needsStepUp = false }) { POSCreditStepUpSheet() }
            .onChange(of: model.administration?.policy) { _ in refreshPolicyDraft() }
            .onChange(of: model.accountVersion) { _ in reviewing = false; accepted = false }
            .task { model.load() }
            .sheet(isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })) {
                if let url = model.shareURL { POSCreditAccountShare(url: url) }
            }
        }
    }
    private var recovery: some View {
        Section(t("Recovery")) {
            if let notice = model.notice { Text(notice) }
            else { Text(t(model.canRecover ? "Uncertain" : "OtherPending")) }
            if model.canRecover {
                Button(t("Recover")) { model.recover() }.disabled(model.busy)
                if model.pending?.result == nil { Button(t("CancelPending"), role: .destructive) { model.cancelPending() }.disabled(model.busy) }
                if model.pending?.approvalRequest != nil { Button(t("RequestApproval")) { model.requestApproval() }.disabled(model.busy) }
                if model.needsStepUp { Button(t("StepUp")) { stepUpPresented = true } }
                if model.pending?.result != nil { Button(t("Acknowledge")) { model.acknowledge() }.disabled(model.busy) }
            }
        }
    }
    private var invoiceSection: some View {
        Section(t("Invoices")) {
            Picker(t("Filter"), selection: $aging) { Text(t("all")).tag("all"); Text(t("Overdue")).tag("overdue"); Text(t("DueSoon")).tag("dueSoon"); Text(t("paid")).tag("paid"); ForEach(["current", "days1to30", "days31to60", "days61to90", "days90plus"], id: \.self) { Text(t($0)).tag($0) } }
            if model.invoices.isEmpty, !model.busy { Text(t("Empty")) }
            ForEach(model.invoices.filter(matches)) { invoice in
                DisclosureGroup {
                    LabeledContent(t("Received"), value: money(invoice.amountPaidMinor))
                    LabeledContent(t("Refunded"), value: money(invoice.refundedMinor ?? 0))
                    LabeledContent(t("Pending"), value: money(invoice.pendingAmountMinor))
                    LabeledContent(t("Credits"), value: money(invoice.creditedMinor ?? 0))
                    LabeledContent(t("RefundLiability"), value: money(invoice.refundLiabilityMinor ?? 0))
                    if model.canAdjust, model.pending == nil { Button(t("AdjustBalance")) { adjusting = invoice }.disabled(model.busy || model.storageFailed) }
                    ForEach(invoice.installments) { row in LabeledContent(row.dueDateKey, value: money(row.due)) }
                    if model.permitted("pos.credit_terms.manage"), invoice.amountDueMinor > 0, model.pending == nil {
                        Button(t("ChangeTerms")) { revising = invoice }.disabled(model.busy)
                    }
                    if model.canCollect, model.pending == nil, invoice.available > 0 {
                        TextField(t("Amount"), text: Binding(get: { amounts[invoice.id] ?? "" }, set: { amounts[invoice.id] = $0 }))
                            .keyboardType(.decimalPad).focused($editing).frame(minHeight: 44)
                            .accessibilityLabel("\(t("Amount")) · \(invoice.documentNumber)")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(invoice.documentNumber).font(.headline)
                        Text("\(t(invoice.paymentStatus)) · \(money(invoice.amountDueMinor))")
                        if invoice.overdueMinor > 0 { Text(t("Overdue")).foregroundStyle(.red) }
                    }.padding(.vertical, 4)
                }
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
        Section(t("Collect")) {
            Picker(t("Method"), selection: $method) { ForEach(methods, id: \.self) { Text(t($0)).tag($0) } }
            if method != "cash" { TextField(t("Reference"), text: $reference).focused($editing).frame(minHeight: 44); Text(t("PendingNotice")).font(.footnote) }
            LabeledContent(t("Total"), value: money(total))
            if reviewing {
                Text(t("ReviewNotice"))
                ForEach(model.invoices.filter { selected[$0.id] != nil }) { invoice in LabeledContent(invoice.documentNumber, value: money(selected[invoice.id] ?? 0)) }
                Toggle(t("Accept"), isOn: $accepted)
                Button(t("Confirm")) {
                    model.collect(amounts: selected, method: method, reference: reference)
                    if model.pending?.operation == "recordPosCollection" { amounts = [:]; reference = "" }
                    reviewing = false; accepted = false
                }
                    .disabled(!valid || !accepted).frame(minHeight: 44)
            } else { Button(t("Review")) { editing = false; reviewing = true }.disabled(!valid).frame(minHeight: 44) }
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
        Section(t("Administration")) {
            Button(t("StepUp")) { stepUpPresented = true }.frame(minHeight: 44)
            TextField(t("Reason"), text: $reason, axis: .vertical).frame(minHeight: 44)
            if let data = model.administration {
                LabeledContent(t("Limit"), value: money(data.policy.limitMinor))
                Text(t(data.policy.enabled ? "Enabled" : "Disabled"))
                if model.permitted("pos.credit_terms.manage") {
                    Toggle(t("Enabled"), isOn: $policyEnabled)
                    TextField(t("Limit"), text: $policyLimit).keyboardType(.decimalPad).focused($editing)
                    Button(t("SavePolicy")) { if let amount = POSCreditCheckoutSheet.minor(policyLimit) { model.policy(enabled: policyEnabled, limit: amount, reason: reason) } }
                        .disabled(model.busy || model.pending != nil || policyVersion != data.policy.version || POSCreditCheckoutSheet.minor(policyLimit) == nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 500)
                }
                ForEach(data.policyProposals) { proposal in
                    VStack(alignment: .leading) {
                        Text(t("PolicyProposal")); Text(money(proposal.limitMinor)); Text(t(proposal.enabled ? "Enabled" : "Disabled"))
                        if model.permitted("pos.credit.approve"), proposal.makerUid != model.actorUID {
                            Button(t("Approve")) { model.approvePolicy(proposal, reason: reason) }.disabled(model.busy || model.pending != nil || reason.isEmpty || reason.count > 500)
                        }
                    }
                }
                if data.morePolicies { Text(t("MorePolicyProposals")) }
                ForEach(data.rows) { review in
                    DisclosureGroup {
                        ForEach(review.lines, id: \.self) { Text($0).textSelection(.enabled) }
                        if model.canApprove(review), review.status == "pending_approval" {
                            Button(t("Approve")) { model.approve(review, reason: reason) }.disabled(model.busy || model.pending != nil || reason.isEmpty || reason.count > 500)
                        }
                    } label: { Text("\(t(review.kind)) · \(t(review.status))") }
                }
                if data.nextCursor != nil { Button(t("More")) { model.loadAdministration(more: true) }.disabled(model.busy) }
            }
            Button(t("Refresh")) { model.loadAdministration() }.disabled(model.busy)
        }.onAppear { refreshPolicyDraft() }
    }
    private var collectionHistory: some View {
        Section(t("Collections")) {
            if model.collections.isEmpty, !model.busy { Text(t("Empty")) }
            ForEach(model.collections) { collection in
                VStack(alignment: .leading, spacing: 8) {
                    Text(collection.documentNumber).font(.headline)
                    Text(t(collection.status))
                    LabeledContent(t("Received"), value: money(collection.receivedMinor))
                    LabeledContent(t("Pending"), value: money(collection.pendingAmountMinor))
                    if collection.reversedMinor > 0 { LabeledContent(t("Reversed"), value: money(collection.reversedMinor)) }
                    Button(t("Receipt")) { model.receipt(collection) }.disabled(model.busy).frame(minHeight: 44)
                    if model.permitted("pos.credit.clear") || model.permitted("pos.credit.reverse") {
                        Button(t("Service")) { servicing = collection }.disabled(model.busy || model.pending != nil || model.storageFailed).frame(minHeight: 44)
                    }
                }.padding(.vertical, 4)
            }
        }
    }
}

@MainActor
private enum POSCreditAccountPDF {
    static func export(_ lines: [String]) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage(); var y: CGFloat = 36
            for line in lines {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = Language.isRTL() ? .right : .left
                paragraph.baseWritingDirection = Language.isRTL() ? .rightToLeft : .leftToRight
                let text = NSAttributedString(string: line, attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .paragraphStyle: paragraph, .foregroundColor: UIColor.black])
                let height = ceil(text.boundingRect(with: CGSize(width: 523, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) + 12
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
        var lines: [String] { proposal.reviewLines() }
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Close")) { dismiss() } } }
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
            }.navigationTitle(t("ChangeTerms"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Close")) { dismiss() } } }
                .onChange(of: date) { _ in accepted = false }.onChange(of: reason) { _ in accepted = false }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }
}

/// Uses the current Firebase Auth session. No password/code is persisted, and
/// only a refreshed signed token with the server-approved factor is accepted.
struct POSCreditStepUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var resolver: MultiFactorResolver?
    @State private var enrollment = ""
    private let actorUID = Auth.auth().currentUser?.uid
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    var body: some View {
        NavigationStack {
            Form {
                Text(t("StepUpNotice"))
                if let error { Text(error).foregroundStyle(.red) }
                if let resolver {
                    Picker(t("Authenticator"), selection: $enrollment) {
                        ForEach(resolver.hints.filter { $0.factorID == "totp" }, id: \.uid) { hint in Text(hint.displayName ?? t("Authenticator")).tag(hint.uid) }
                    }
                    SecureField(t("OneTimeCode"), text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                } else { SecureField(t("Password"), text: $password).textContentType(.password) }
                Button(t("Verify")) { authenticate() }.disabled(busy || (resolver == nil ? password.isEmpty : code.count != 6 || enrollment.isEmpty)).frame(minHeight: 44)
                if busy { ProgressView() }
            }.navigationTitle(t("StepUp"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Close")) { password = ""; code = ""; resolver = nil; dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .onDisappear { password = ""; code = ""; resolver = nil }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
                    let result = try await resolver.resolveSignIn(with: assertion)
                    guard result.user.uid == actorUID else { throw POSCreditPendingStore.StoreError.invalidRecord }
                } else {
                    do { _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: secret)) }
                    catch {
                        guard let next = (error as NSError).userInfo[AuthErrors.userInfoMultiFactorResolverKey] as? MultiFactorResolver,
                              let hint = next.hints.first(where: { $0.factorID == "totp" }) else { throw error }
                        resolver = next; enrollment = hint.uid; return
                    }
                }
                guard let current = Auth.auth().currentUser, current.uid == actorUID else { throw POSCreditPendingStore.StoreError.invalidRecord }
                let token = try await current.getIDTokenResult(forcingRefresh: true)
                guard (token.claims["firebase"] as? [String: Any])?["sign_in_second_factor"] as? String == "totp" else { throw POSCreditPendingStore.StoreError.invalidRecord }
                dismiss()
            } catch { self.error = t("StepUpUnavailable") }
        }
    }
}
