import Foundation
import SwiftUI
import UIKit
import PDFKit
import FirebaseAuth
import CryptoKit
import Combine

@MainActor
enum POSCreditAccountCopy {
    private static let fallbacks: [String: String] = [
        "Title": "حساب الائتمان والمديونيات",
        "Administration": "الإدارة والسياسات",
        "CurrentPolicy": "سياسة الائتمان الحالية",
        "Limit": "الحد الائتماني",
        "EditPolicy": "اقتراح تعديل السياسة",
        "EnableCredit": "تفعيل الائتمان لهذا الحساب",
        "Reason": "السبب",
        "ReasonPlaceholder": "وضّح سبب هذا الطلب",
        "ReasonHelp": "يلزم توضيح السبب لإرسال الطلب أو الموافقة عليه. الحد الأقصى ٥٠٠ حرف.",
        "SavePolicy": "إرسال سياسة الائتمان",
        "Refresh": "تحديث",
        "Done": "تم",
        "Loading": "جارٍ التحميل…",
        "PolicyProposal": "اقتراح سياسة ائتمان",
        "ReviewQueue": "طلبات المراجعة",
        "Status": "الحالة",
        "Enabled": "مفعّل",
        "Disabled": "معطّل",
        "Approve": "اعتماد",
        "Reject": "رفض",
        "StepUp": "تأكيد الهوية",
        "VerificationHelp": "تحقّق من هويتك قبل التغييرات الحساسة.",
        "Retry": "إعادة المحاولة",
        "More": "المزيد",
        "Review": "مراجعة",
        "Accept": "قبول",
        "Clear": "تأكيد التحصيل",
        "Reverse": "عكس التحصيل",
        "Service": "خدمة التحصيل",
        "Close": "إغلاق",
        "Export": "تصدير",
        "Filter": "تصفية",
        "Total": "الإجمالي",
        "Outstanding": "الرصيد القائم",
        "Overdue": "المتأخرات",
        "NextDue": "الاستحقاق القادم",
        "Pending": "معلّق",
        "DueSoon": "يستحق قريباً",
        "NoDueDate": "لا يوجد موعد استحقاق محدد",
        "InstallmentSchedule": "أرصدة الأقساط",
        "CollectionHelp": "افتح الفاتورة وأدخل المبلغ المراد تحصيله، ثم راجع الإجمالي المحدد قبل التأكيد.",
        "SelectedForCollection": "محدد للتحصيل",
        "NoCollectionMethod": "لا تتوفر وسيلة دفع للتحصيل في هذا الفرع.",
        "Records": "السجلات",
        "Amount": "المبلغ",
        "Method": "طريقة الدفع",
        "Reference": "المرجع",
        "Evidence": "مستند الإثبات",
        "Received": "المستلم",
        "Reversed": "المعكوس",
        "Credits": "الائتمانات",
        "Refunded": "المسترد",
        "RefundLiability": "التزامات الاسترداد",
        "AsOf": "بتاريخ",
        "Authenticator": "تطبيق المصادقة",
        "Password": "كلمة المرور",
        "OneTimeCode": "الرمز لمرة واحدة",
        "StepUpUnavailable": "التحقق غير متاح",
        "StepUpErrorTitle": "أعد محاولة تأكيد الهوية",
        "StepUpCodePlaceholder": "أدخل ٦ أرقام",
        "StepUpPasswordPlaceholder": "أدخل كلمة المرور",
        "StepUpRegisteredAuthenticator": "تطبيق المصادقة المسجّل",
        "StepUpCheckingPassword": "جارٍ التحقّق من كلمة المرور…",
        "StepUpCheckingCode": "جارٍ التحقّق من الرمز…",
        "StepUpContinue": "متابعة",
        "StepUpPasswordProgress": "الخطوة ١ من ٢: كلمة المرور",
        "StepUpCodeProgress": "الخطوة ٢ من ٢: تطبيق المصادقة",
        "StepUpPasswordTitle": "ابدأ بكلمة المرور",
        "StepUpCodeTitle": "رمز تطبيق المصادقة",
        "StepUpPasswordHelp": "أدخل كلمة مرور حساب الموظف الحالي، ثم أكّد هويتك عبر تطبيق المصادقة المسجّل.",
        "StepUpCodeHelp": "افتح تطبيق المصادقة المسجّل وأدخل الرمز الحالي المكوّن من ٦ أرقام.",
        "StepUpFinancialBoundary": "هذه الخطوة لتأكيد هويتك فقط، ولا ترسل أو تعتمد أي عملية مالية.",
        "all": "الكل",
        "paid": "مدفوع"
    ]

    static func text(_ key: String) -> String {
        let localizedKey = "POS_CreditAccount_" + key
        // A valid Arabic translation may equal our fallback. Look up the key first
        // so Language does not mistake that translation for a missing resource.
        let localized: String = Language.get(localizedKey, alter: nil)
        return localized == localizedKey ? (fallbacks[key] ?? key) : localized
    }
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
    let installmentAllocationVersion: Int?
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
    let customerName: String?
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
        var available: Int { max(0, due - pendingAmountMinor) }
    }
    let invoiceId: String
    let saleId: String
    let documentNumber: String
    let version: Int
    let agreementVersion: Int
    let settlementMode: String?
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
    var usesInstallments: Bool {
        if let settlementMode { return settlementMode == "installments" }
        // Older read projections lack the mode. A deposit is not a future installment.
        return installments.filter { $0.id != "initial_deposit" }.count > 1
    }
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

/// Presentation validation; the callable independently checks every version and allocation.
enum POSCreditCollectionAllocation {
    static func sum(_ amounts: [Int]) -> Int? {
        var total = 0
        for amount in amounts {
            guard amount > 0 else { return nil }
            let result = total.addingReportingOverflow(amount)
            guard !result.overflow, result.partialValue <= 9_007_199_254_740_991 else { return nil }
            total = result.partialValue
        }
        return total
    }
    static func installmentTotal(_ amounts: [String: Int], invoice: POSCreditAccountInvoice) -> Int? {
        guard !amounts.isEmpty, amounts.count <= 25 else { return nil }
        for (id, amount) in amounts {
            guard let row = invoice.installments.first(where: { $0.id == id }),
                  amount > 0, amount <= row.available else { return nil }
        }
        return sum(Array(amounts.values))
    }
    static func total(_ amounts: [String: Int], invoices: [POSCreditAccountInvoice],
                      installments: [String: [String: Int]] = [:]) -> Int? {
        guard !amounts.isEmpty, amounts.count <= 20,
              installments.keys.allSatisfy({ amounts[$0] != nil }) else { return nil }
        for (id, amount) in amounts {
            guard let invoice = invoices.first(where: { $0.id == id }),
                  invoice.disputeHold != true, amount > 0, amount <= invoice.available else { return nil }
            if invoice.usesInstallments {
                guard let rows = installments[id], installmentTotal(rows, invoice: invoice) == amount else { return nil }
            } else if installments[id] != nil { return nil }
        }
        return sum(Array(amounts.values))
    }
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
    @Published private(set) var customerName: String?
    @Published private(set) var invoices: [POSCreditAccountInvoice] = []
    @Published private(set) var collections: [POSCreditAccountCollection] = []
    @Published private(set) var accountVersion = 0
    @Published private(set) var asOf = ""
    @Published private(set) var busy = false
    @Published private(set) var pending: POSCreditAccountCommandStore.Record?
    @Published var error: String?
    @Published var notice: String?
    @Published var shareURL: URL?
    @Published var previewReceiptDocument: POSCreditCollectionReceiptDocument? = nil
    @Published private(set) var storageFailed = false
    @Published private(set) var administration: POSCreditAdministrationPage?
    @Published var needsStepUp = false
    @Published private(set) var adjustmentContext: POSCreditAdjustmentContext?
    private var cursor: POSCreditStatementCursor?
    private var kind = "invoices"
    private var requestID = UUID()
    private var authorizationCancellable: AnyCancellable?
    private var invoicesAreCurrent = false
    private nonisolated(unsafe) var authListener: AuthStateDidChangeListenerHandle?
    var hasMore: Bool { cursor != nil }
    var canRead: Bool { Auth.auth().currentUser?.uid == actorUID && POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) }
    var canCollect: Bool { canRead && POSCreditAccountCopy.permitted("pos.credit.collect", branchID: branchID) && accountVersion > 0 && invoicesAreCurrent }
    var canRecover: Bool { canRead && pending?.actorUID == actorUID && pending?.branchID == branchID && pending?.customerID == customerID }
    var isPendingCancelled: Bool {
        guard let data = pending?.result,
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return (value["status"] as? String) == "cancelled"
    }

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
                self.summary = nil; self.context = nil; self.customerName = nil; self.notice = nil; self.pending = nil; self.shareURL = nil; self.previewReceiptDocument = nil
                self.invoicesAreCurrent = false
                self.administration = nil; self.adjustmentContext = nil; self.accountVersion = 0; self.asOf = ""
                self.error = POSCreditAccountCopy.text("Permission")
            }
        }
        authorizationCancellable = NotificationCenter.default.publisher(for: Notification.Name("PPAdminCommandAuthorizationDidChangeNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.requestID = UUID(); self.busy = false; self.invoicesAreCurrent = false
                self.invoices = []; self.collections = []; self.summary = nil; self.context = nil; self.customerName = nil
                self.administration = nil; self.adjustmentContext = nil; self.shareURL = nil
                if self.canRead { self.load() } else { self.error = POSCreditAccountCopy.text("Permission") }
            }
        restore()
    }
    deinit { if let authListener { Auth.auth().removeStateDidChangeListener(authListener) } }
    func restore() {
        do {
            pending = try POSCreditAccountCommandStore.load(actorUID: actorUID)
            storageFailed = false
            if let result = pending?.result { showResult(result) }
        }
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
                guard self.canRead else {
                    self.invoices = []; self.collections = []; self.summary = nil; self.context = nil; self.customerName = nil
                    self.invoicesAreCurrent = false
                    return
                }
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
        invoicesAreCurrent = false
        kind = requestedKind
        var body = base(); body["kind"] = requestedKind; body["pageSize"] = 50
        if more, let cursor, let encoded = try? JSONEncoder().encode(cursor) { body["cursor"] = try? JSONSerialization.jsonObject(with: encoded) }
        call("getCustomerReceivables", body: body) { [weak self] _, data in
            guard let self else { return }
            if requestedKind == "invoices" {
                let page = try JSONDecoder().decode(POSCreditAccountPage<POSCreditAccountInvoice>.self, from: data)
                try self.accept(page, more: more)
                self.invoices = more ? self.invoices + page.rows.filter { row in !self.invoices.contains(where: { $0.id == row.id }) } : page.rows
                self.invoicesAreCurrent = true
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
        customerName = page.customerName
    }
    func collect(amounts: [String: Int], installments: [String: [String: Int]], method: String, reference: String) {
        guard canCollect, pending == nil, !storageFailed, !busy, !amounts.isEmpty, amounts.count <= 20,
              let accountID = context?.receiptAccounts[method], method == "cash" || context?.pendingTendersEnabled == true else { return }
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard POSCreditCollectionAllocation.total(amounts, invoices: invoices, installments: installments) != nil,
              installments.isEmpty || context?.installmentAllocationVersion == 1,
              ["cash", "card", "cheque", "fawry", "bank_transfer"].contains(method),
              trimmedReference.count <= 200, method == "cash" || !trimmedReference.isEmpty else {
            error = POSCreditAccountCopy.text("Invalid"); return
        }
        let rows = invoices.filter { amounts[$0.id] != nil }
        var body = base(); body["commandId"] = UUID().uuidString; body["expectedAccountVersion"] = accountVersion
        body["method"] = method; body["accountId"] = accountID; body["reference"] = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        body["allocations"] = rows.map { invoice -> [String: Any] in
            var row: [String: Any] = ["invoiceId": invoice.id, "expectedVersion": invoice.version, "amountMinor": amounts[invoice.id]!]
            if let selected = installments[invoice.id] {
                row["installmentAllocations"] = invoice.installments.compactMap { entry -> [String: Any]? in
                    guard let amount = selected[entry.id] else { return nil }
                    return ["installmentId": entry.id, "amountMinor": amount]
                }
            }
            return row
        }
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
                NotificationCenter.default.post(name: Notification.Name("PPAccountingDataDidChangeNotification"), object: nil,
                    userInfo: ["customerId": self.customerID, "branchId": self.branchID, "actorUID": self.actorUID])
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
    func acknowledge(nextKind: String? = nil) {
        guard canRecover, let record = pending, record.result != nil else { return }
        do { try POSCreditAccountCommandStore.acknowledge(record); pending = nil; notice = nil; if let nextKind { kind = nextKind }; if kind == "administration" { loadAdministration() } else { load(kind: kind) } }
        catch { self.error = POSCreditAccountCopy.text("StorageFailed") }
    }
    func receipt(_ collection: POSCreditAccountCollection) {
        var body = base(); body["kind"] = "receipt"; body["collectionId"] = collection.id; body["eventId"] = collection.lastEventId
        call("getCustomerReceivables", body: body) { [weak self] value, _ in
            guard let self, let receiptDict = value["receipt"] as? [String: Any], receiptDict["collectionId"] as? String == collection.id,
                  receiptDict["customerId"] as? String == self.customerID, receiptDict["branchId"] as? String == self.branchID else { throw POSCreditPendingStore.StoreError.invalidRecord }

            let allocationsRaw = receiptDict["allocations"] as? [[String: Any]] ?? []
            let allocations = allocationsRaw.compactMap { alloc -> POSCreditCollectionReceipt.Allocation? in
                guard let invoiceId = alloc["invoiceId"] as? String else { return nil }
                let amountMinor = (alloc["amountMinor"] as? NSNumber)?.intValue ?? 0
                return POSCreditCollectionReceipt.Allocation(invoiceId: invoiceId, amountMinor: amountMinor)
            }

            let createdAtStr = receiptDict["createdAt"] as? String ?? ""
            let createdAtDate: Date? = {
                if let str = receiptDict["createdAt"] as? String, !str.isEmpty {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let d = iso.date(from: str) { return d }
                    let isoBasic = ISO8601DateFormatter()
                    return isoBasic.date(from: str)
                }
                return nil
            }()

            let modelReceipt = POSCreditCollectionReceipt(
                collectionId: collection.id,
                eventId: collection.lastEventId,
                documentNumber: collection.documentNumber,
                customerId: self.customerID,
                customerName: self.customerName ?? "",
                branchId: self.branchID,
                createdAt: createdAtDate,
                createdAtString: createdAtStr,
                status: receiptDict["status"] as? String ?? collection.status,
                operation: receiptDict["operation"] as? String ?? "record",
                paymentMethod: receiptDict["paymentMethod"] as? String ?? "cash",
                reference: receiptDict["reference"] as? String,
                reason: receiptDict["reason"] as? String,
                tenderAmountMinor: (receiptDict["tenderAmountMinor"] as? NSNumber)?.intValue ?? 0,
                receivedMinor: (receiptDict["receivedMinor"] as? NSNumber)?.intValue ?? collection.receivedMinor,
                pendingAmountMinor: (receiptDict["pendingAmountMinor"] as? NSNumber)?.intValue ?? collection.pendingAmountMinor,
                reversedMinor: (receiptDict["reversedMinor"] as? NSNumber)?.intValue ?? collection.reversedMinor,
                refundedMinor: (receiptDict["refundedMinor"] as? NSNumber)?.intValue ?? 0,
                remainingBalanceMinor: self.summary?.outstandingMinor,
                allocations: allocations
            )

            let document = try POSCreditCollectionReceiptPDF.document(for: modelReceipt)
            self.previewReceiptDocument = document
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

private struct POSCreditAccountPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Hosting Controller & Push Navigation

@objc(POSCreditAccountHostingController)
public final class POSCreditAccountHostingController: UIViewController {
    private let customerID: String
    private let branchID: String
    private let initialTab: String
    private var onDismissCallback: (() -> Void)?

    @objc public init(customerID: String, branchID: String, initialTab: String = "invoices", onDismiss: (() -> Void)? = nil) {
        self.customerID = customerID
        self.branchID = branchID
        self.initialTab = initialTab
        self.onDismissCallback = onDismiss
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let sheetView = POSCreditAccountSheet(
            customerID: customerID,
            branchID: branchID,
            initialTab: initialTab,
            onDismiss: { [weak self] in
                self?.handleDismiss()
            }
        )

        let host = UIHostingController(rootView: sheetView)
        host.view.backgroundColor = .clear
        host.extendedLayoutIncludesOpaqueBars = true
        host.edgesForExtendedLayout = .all
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func handleDismiss() {
        if let onDismissCallback = onDismissCallback {
            onDismissCallback()
        }
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else if let presenting = presentingViewController {
            dismiss(animated: true)
        } else if let presenting = navigationController?.presentingViewController {
            navigationController?.dismiss(animated: true)
        } else {
            PPAdminNavigationFallback.popOrDismiss(from: self)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.pp_enableSwipeToPop()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.pp_enableSwipeToPop()
    }
}

@MainActor
public func pushPOSCreditAccount(
    customerID: String,
    branchID: String,
    initialTab: String = "invoices",
    from sourceVC: UIViewController? = nil,
    onDismiss: (() -> Void)? = nil
) {
    guard !customerID.isEmpty else { return }

    let targetVC = POSCreditAccountHostingController(
        customerID: customerID,
        branchID: branchID,
        initialTab: initialTab,
        onDismiss: onDismiss
    )
    targetVC.hidesBottomBarWhenPushed = true

    let topVC = sourceVC ?? PPAdminNavigationFallback.keyWindowTopViewController()
    if let nav = topVC as? UINavigationController {
        nav.pushViewController(targetVC, animated: true)
        return
    }
    if let nav = topVC?.navigationController {
        nav.pushViewController(targetVC, animated: true)
        return
    }

    var current = topVC?.presentingViewController
    while let c = current {
        if let nav = c as? UINavigationController {
            nav.pushViewController(targetVC, animated: true)
            return
        }
        if let nav = c.navigationController {
            nav.pushViewController(targetVC, animated: true)
            return
        }
        current = c.presentingViewController
    }

    let nav = UINavigationController(rootViewController: targetVC)
    nav.modalPresentationStyle = .fullScreen
    nav.setNavigationBarHidden(true, animated: false)
    topVC?.present(nav, animated: true)
}

struct POSCreditAccountLink: View {
    let customerID: String
    let branchID: String
    var compact = false
    var opensCollection = false
    private var collect: Bool { opensCollection && POSCreditAccountCopy.permitted("pos.credit.collect", branchID: branchID) }
    var body: some View {
        if !customerID.isEmpty, POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) {
            Group {
                if compact {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        pushPOSCreditAccount(customerID: customerID, branchID: branchID, initialTab: collect ? "collect" : "invoices")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: collect ? "arrow.down.left" : "person.text.rectangle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AdminSurface.primary)
                            Text(POSCreditAccountCopy.text(collect ? "Collect" : "Title"))
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AdminSurface.primary.opacity(0.7))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(minHeight: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AdminSurface.primarySoft.opacity(0.40))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 1)
                        )
                        .frame(minHeight: AdminTouchTarget.minimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(POSCreditAccountPressableButtonStyle())
                    .accessibilityIdentifier("pos.credit.accountLink.compact")
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        pushPOSCreditAccount(customerID: customerID, branchID: branchID, initialTab: collect ? "collect" : "invoices")
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(AdminSurface.primary.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: collect ? "arrow.down.left" : "person.text.rectangle")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(AdminSurface.primary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(POSCreditAccountCopy.text(collect ? "Collect" : "Title"))
                                    .font(AdminType.headlineBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(POSCreditAccountCopy.text(collect ? "CollectionEntryHelp" : "QuickViewSubtitle"))
                                    .font(AdminType.caption)
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }

                            Spacer(minLength: 8)

                            HStack(spacing: 4) {
                                Text(Language.get("POS_CreditAccount_ViewAction", alter: "عرض"))
                                    .font(AdminType.footnoteBold)
                                    .foregroundStyle(AdminSurface.primary)
                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AdminSurface.primarySoft.opacity(0.40))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 1.2)
                        )
                    }
                    .buttonStyle(POSCreditAccountPressableButtonStyle())
                    .accessibilityIdentifier("pos.credit.accountLink")
                }
            }
        }
    }
}

struct POSCreditAccountSheet: View {
    @StateObject private var model: POSCreditAccountModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onDismiss: (() -> Void)? = nil
    @State private var showsAging = false
    @ObservedObject private var branch = BranchContextStore.shared
    @State private var tab = "invoices"
    @State private var aging = "all"
    @State private var amounts: [String: String] = [:]
    @State private var installmentAmounts: [String: [String: String]] = [:]
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
    @State private var policyValidationError: String? = nil
    @State private var policyReasonAttempted = false
    @State private var stepUpPresented = false
    private enum InputField: Hashable {
        case invoiceAmount(String), installmentAmount(String, String), reference, reason, policyLimit
    }
    @FocusState private var editing: InputField?
    private enum CollectionFocus: Hashable { case review, receipt }
    @AccessibilityFocusState private var collectionFocus: CollectionFocus?
    init(customerID: String, branchID: String, initialTab: String = "invoices", onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        _model = StateObject(wrappedValue: POSCreditAccountModel(customerID: customerID, branchID: branchID))
        _tab = State(initialValue: initialTab)
    }
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private func money(_ amount: Int) -> String { POSCreditAccountCopy.money(amount) }
    private func handleBack() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
            PPAdminNavigationFallback.popOrDismiss()
        }
    }
    private var selected: [String: Int] {
        var result: [String: Int] = [:]
        let installmentSelection = selectedInstallments
        for (id, val) in amounts {
            if let invoice = model.invoices.first(where: { $0.id == id }), invoice.usesInstallments {
                if let rows = installmentSelection[id], let amount = POSCreditCollectionAllocation.installmentTotal(rows, invoice: invoice) {
                    result[id] = amount
                }
            } else if let minor = POSCreditCheckoutSheet.minor(val), minor > 0 {
                result[id] = minor
            }
        }
        return result
    }
    private var selectedInstallments: [String: [String: Int]] {
        var result: [String: [String: Int]] = [:]
        for (invoiceID, entries) in installmentAmounts where amounts[invoiceID] != nil {
            var parsed: [String: Int] = [:]
            for (id, raw) in entries {
                if let amount = POSCreditCheckoutSheet.minor(raw), amount > 0 { parsed[id] = amount }
            }
            if !parsed.isEmpty, parsed.count == entries.count { result[invoiceID] = parsed }
        }
        return result
    }
    private var total: Int { POSCreditCollectionAllocation.sum(Array(selected.values)) ?? 0 }
    private var supportsInstallmentSelection: Bool { model.context?.installmentAllocationVersion == 1 }
    private var methods: [String] {
        guard let context = model.context else { return [] }
        let candidates = ["cash", "card", "cheque", "fawry", "bank_transfer"]
        return candidates.filter { m in
            let hasAccount = context.receiptAccounts[m] != nil
            let allowed = (m == "cash") || (context.pendingTendersEnabled == true)
            return hasAccount && allowed
        }
    }
    private var valid: Bool {
        guard model.canCollect else { return false }
        guard model.pending == nil else { return false }
        guard !model.storageFailed && !model.busy else { return false }
        guard !selected.isEmpty && selected.count <= 20 && selected.count == amounts.count else { return false }
        guard methods.contains(method) else { return false }
        guard selectedInstallments.isEmpty || supportsInstallmentSelection else { return false }
        guard reference.count <= 200 else { return false }

        let trimmedRef = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if method != "cash" && trimmedRef.isEmpty {
            return false
        }

        let allAmountsValid = amounts.values.allSatisfy { rawValue in
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || (POSCreditCheckoutSheet.minor(trimmed) != nil)
        }
        guard allAmountsValid else { return false }

        return POSCreditCollectionAllocation.total(selected, invoices: model.invoices, installments: selectedInstallments) != nil
    }
    private var headerSubtitle: String? {
        if branch.activeBranch?.branchID == model.branchID,
           let branchName = branch.activeBranch?.localizedName(), !branchName.isEmpty {
            return branchName
        }
        if let match = branch.availableBranches.first(where: { $0.branchID == model.branchID }) {
            return match.localizedName()
        }
        return model.branchID.isEmpty ? nil : String(format: t("CollectionBranchReference"), model.branchID)
    }

    private var headerBar: some View {
        AdminSovereignNavigationBar(
            title: t(tab == "collect" ? "Collect" : "Title"),
            subtitle: headerSubtitle,
            statusDotColor: model.error != nil ? AdminSurface.amber : model.busy ? AdminSurface.secondaryText : AdminSurface.primary,
            isModal: false,
            customTopSpacing: 0,
            showsTopFade: false,
            onBack: { handleBack() }
        )
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                    if model.canRead { accountContent }
                    else { emptyState("Permission", symbol: "lock.shield") }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .id("credit.account.top")
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.base)
                .padding(.bottom, AdminSpacing.lg)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTapOutside()
            .onChange(of: reviewing) { _ in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo("credit.account.top", anchor: .top)
                }
            }
            .onChange(of: model.pending?.commandID) { _ in proxy.scrollTo("credit.account.top", anchor: .top) }
        }
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                editing = nil
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            } label: {
                Text(t("Done")).font(AdminType.calloutBold)
            }
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            AdminSurface.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                scrollContent
            }
        }
        .font(AdminType.body)
        .foregroundStyle(AdminSurface.primaryText)
        .multilineTextAlignment(.leading)
        .tint(AdminSurface.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if tab == "collect", model.canRead, model.summary != nil, model.pending == nil {
                collectionDock
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            keyboardToolbar
        }
        .enableSwipeToPop { handleBack() }
    }

    var body: some View {
        mainContent
            .onChange(of: tab) { _ in amounts = [:]; installmentAmounts = [:]; reviewing = false; accepted = false; reloadRecords() }
            .onChange(of: branch.activeBranch?.branchID) { _ in handleBack() }
            .onChange(of: amounts) { _ in reviewing = false; accepted = false }
            .onChange(of: installmentAmounts) { _ in reviewing = false; accepted = false }
            .onChange(of: method) { value in
                reviewing = false; accepted = false
                if value == "cash" { reference = "" }
            }
            .onChange(of: reference) { _ in reviewing = false; accepted = false }
            .onChange(of: reviewing) { value in
                if value { collectionFocus = .review }
            }
            .onChange(of: model.pending?.result) { _ in
                if collectionResult != nil { collectionFocus = .receipt }
            }
            .onChange(of: methods) { values in
                if !values.contains(method) { method = values.first ?? "" }
                reviewing = false; accepted = false
            }
            .onChange(of: model.needsStepUp) { value in
                if value && (model.permitted("pos.credit_terms.manage") || model.permitted("pos.credit.approve") || model.permitted("pos.credit.clear") || model.canAdjust || model.canCollect) {
                    stepUpPresented = true
                }
            }
            .sheet(item: $servicing) { collection in POSCreditServicingSheet(model: model, collection: collection) }
            .sheet(item: $adjusting) { invoice in POSCreditAdjustmentSheet(model: model, invoice: invoice) }
            .sheet(item: $revising) { invoice in POSCreditTermsSheet(model: model, invoice: invoice) }
            .sheet(isPresented: $stepUpPresented, onDismiss: { model.needsStepUp = false }) { POSCreditStepUpSheet() }
            .onChange(of: model.administration?.policy) { _ in refreshPolicyDraft() }
            .onChange(of: model.accountVersion) { _ in
                amounts = [:]; installmentAmounts = [:]; reviewing = false; accepted = false
            }
            .task {
                reloadRecords()
                if collectionResult != nil { collectionFocus = .receipt }
            }
            .sheet(isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })) {
                if let url = model.shareURL { POSCreditAccountShare(url: url) }
            }
            .sheet(item: $model.previewReceiptDocument) { doc in
                POSCreditCollectionReceiptSheet(document: doc)
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .environment(\.locale, Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA"))
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
    }

    private func reloadRecords() {
        if tab == "administration" { model.loadAdministration() }
        else { model.load(kind: tab == "collect" ? "invoices" : tab) }
    }

    @ViewBuilder private var accountContent: some View {
        if let error = model.error {
            panel {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(AdminType.subheadline).foregroundStyle(AdminSurface.crimson)
                    .fixedSize(horizontal: false, vertical: true)
                action("Retry", symbol: "arrow.clockwise") {
                    reloadRecords()
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
        if model.pending != nil {
            if let result = collectionResult { collectionReceipt(result) } else { recovery }
        }
        if tab == "collect" {
            if model.pending == nil, let summary = model.summary { collectionWorkspace(summary) }
        } else {
            if let summary = model.summary { accountOverview(summary) }
            recordNavigation
            if tab == "invoices" { invoiceSection }
            else if tab == "collections" { collectionHistory }
            else { administrationSection }
        }
        if model.hasMore, tab != "administration", tab != "collect" {
            action("More", symbol: "arrow.down") { model.load(kind: tab, more: true) }
                .disabled(model.busy)
        }
    }

    private func accountOverview(_ summary: POSCreditAccountSummary) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            if let name = model.customerName, !name.isEmpty {
                Text(name).font(PPBrandFont.bold(26, relativeTo: .title2))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            if model.permitted("pos.credit.collect"), model.pending == nil, summary.outstandingMinor > 0 {
                action("Collect", symbol: "arrow.down.left", prominent: true) { tab = "collect" }
                    .accessibilityIdentifier("pos.credit.account.startCollection")
            }
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
            Text(money(amount)).font(PPBrandFont.bold(18, relativeTo: .title3))
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
                if model.pending?.result != nil {
                    let isCancelled = model.isPendingCancelled
                    action(isCancelled ? "DismissCancelled" : "Acknowledge", symbol: isCancelled ? "xmark.circle" : "checkmark", prominent: true) {
                        model.acknowledge()
                    }
                    .disabled(model.busy)
                } else {
                    action("Recover", symbol: "arrow.clockwise", prominent: true) { model.recover() }.disabled(model.busy)
                    action("CancelPending", symbol: "xmark.circle", role: .destructive) { model.cancelPending() }.disabled(model.busy)
                    if model.pending?.approvalRequest != nil {
                        action("RequestApproval", symbol: "person.crop.circle.badge.checkmark") { model.requestApproval() }.disabled(model.busy)
                    }
                    if model.needsStepUp { action("StepUp", symbol: "lock.shield") { stepUpPresented = true } }
                }
            }
        }
    }

    private var invoiceSection: some View {
        let visibleInvoices = model.invoices.filter(matches)
        return VStack(alignment: .leading, spacing: AdminSpacing.md) {
            sectionHeading("Invoices", symbol: "doc.text")
            invoiceFilterControl
            if visibleInvoices.isEmpty, !model.busy, model.error == nil {
                emptyState(model.invoices.isEmpty ? "EmptyInvoices" : "EmptyFilter", symbol: "doc.text.magnifyingglass")
                if aging != "all" { action("ShowAllInvoices", symbol: "line.3.horizontal.decrease") { aging = "all" } }
            }
            ForEach(visibleInvoices) { invoice in
                invoiceCard(invoice)
            }
        }
    }

    private var invoiceFilterControl: some View {
        Menu {
            Picker(t("Filter"), selection: $aging) {
                Text(t("all")).tag("all").font(AdminType.subheadlineBold)
                Text(t("Overdue")).tag("overdue").font(AdminType.subheadlineBold)
                Text(t("DueSoon")).tag("dueSoon").font(AdminType.subheadlineBold)
                Text(t("paid")).tag("paid").font(AdminType.subheadlineBold)
                ForEach(["current", "days1to30", "days31to60", "days61to90", "days90plus"], id: \.self) { key in
                    Text(t(key)).tag(key).font(AdminType.subheadlineBold)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(t(aging))
                    .font(AdminType.subheadlineBold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AdminSurface.primary)
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, 8)
            .background(AdminSurface.control, in: Capsule())
            .frame(minHeight: 44)
        }
        .accessibilityLabel(t("Filter"))
        .accessibilityValue(t(aging))
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
                    if model.canCollect, model.pending == nil, invoice.available > 0, invoice.disputeHold != true {
                        action("Collect", symbol: "arrow.down.left") { tab = "collect" }
                            .disabled(model.busy || model.storageFailed)
                    }
                }.padding(.top, AdminSpacing.base)
            } label: {
                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    Text(invoice.documentNumber).font(AdminType.subheadlineBold)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(money(invoice.amountDueMinor)).font(PPBrandFont.bold(20, relativeTo: .title2))
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

    private var collectionInvoices: [POSCreditAccountInvoice] {
        model.invoices.filter { $0.available > 0 && $0.disputeHold != true }
            .sorted {
                if ($0.overdueMinor > 0) != ($1.overdueMinor > 0) { return $0.overdueMinor > 0 }
                if $0.dueDateKey != $1.dueDateKey { return ($0.dueDateKey ?? "9999") < ($1.dueDateKey ?? "9999") }
                return $0.id < $1.id
            }
    }

    private var collectionAccent: Color { Color(uiColor: .ppAccentText) }

    private func collectionWorkspace(_ summary: POSCreditAccountSummary) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            collectionIdentity
            if reviewing {
                collectionReview(summary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("Outstanding")).font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(money(summary.outstandingMinor))
                        .font(PPBrandFont.bold(44, relativeTo: .largeTitle))
                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pos.credit.collect.outstanding")
                    if summary.overdueMinor > 0 {
                        Label("\(t("Overdue")) · \(money(summary.overdueMinor))", systemImage: "clock.badge.exclamationmark")
                            .font(AdminType.footnoteBold).foregroundStyle(AdminSurface.crimson)
                    }
                    if summary.pendingAmountMinor > 0 {
                        Label("\(t("CollectionAwaiting")) · \(money(summary.pendingAmountMinor))", systemImage: "clock")
                            .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if !model.permitted("pos.credit.collect") {
                    emptyState("CollectionReadOnly", symbol: "lock.shield")
                } else if summary.outstandingMinor == 0 {
                    emptyState("CollectionSettled", symbol: "checkmark.circle")
                } else {
                    collectionInvoiceSelection
                    if !selected.isEmpty { collectionPayment }
                }
            }
        }
    }

    private var collectionIdentity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.customerName?.isEmpty == false ? model.customerName! : t("CollectionCustomer"))
                        .font(PPBrandFont.bold(26, relativeTo: .title2))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let subtitle = headerSubtitle {
                        Label(subtitle, systemImage: "building.2")
                            .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button { editing = nil; tab = "invoices" } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(collectionAccent)
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain).disabled(model.busy)
                .accessibilityLabel(t("CollectionOpenAccount"))
            }
            Rectangle().fill(AdminSurface.hairline).frame(height: 1).accessibilityHidden(true)
        }
    }

    private var collectionInvoiceSelection: some View {
        let invoices = collectionInvoices
        return VStack(alignment: .leading, spacing: 12) {
            Text(t("CollectionChooseInvoices"))
                .font(PPBrandFont.bold(20, relativeTo: .title3)).accessibilityAddTraits(.isHeader)
            Text(t("CollectionChooseHelp")).font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText).fixedSize(horizontal: false, vertical: true)
            LazyVStack(spacing: 0) {
                ForEach(invoices) { invoice in
                    collectionInvoiceRow(invoice)
                    if invoice.id != invoices.last?.id {
                        Rectangle().fill(AdminSurface.hairline).frame(height: 1).padding(.horizontal, 16)
                            .accessibilityHidden(true)
                    }
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            if invoices.isEmpty, !model.busy, model.error == nil {
                Text(t(model.hasMore ? "CollectionMoreInvoices" : "CollectionNoAllocations"))
                    .font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.invoices.contains(where: { $0.disputeHold == true && $0.amountDueMinor > 0 }) {
                Label(t("CollectionDisputeHelp"), systemImage: "lock.doc")
                    .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if amounts.count >= 20 {
                Text(t("CollectionSelectionLimit")).font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            if model.hasMore {
                action("CollectionLoadMore", symbol: "arrow.down") { model.load(more: true) }
                    .disabled(model.busy)
            }
        }
    }

    private func collectionInvoiceRow(_ invoice: POSCreditAccountInvoice) -> some View {
        let isSelected = amounts[invoice.id] != nil
        let supportsInvoice = !invoice.usesInstallments || supportsInstallmentSelection
        let amount = selected[invoice.id] ?? 0
        let invalidAmount = isSelected && (amount <= 0 || amount > invoice.available || POSCreditCheckoutSheet.minor(amounts[invoice.id] ?? "") == nil)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                editing = nil
                if isSelected {
                    amounts.removeValue(forKey: invoice.id)
                    installmentAmounts.removeValue(forKey: invoice.id)
                } else if supportsInvoice, amounts.count < 20 {
                    amounts[invoice.id] = invoice.usesInstallments ? "" : decimalAmount(invoice.available)
                    if invoice.usesInstallments { installmentAmounts[invoice.id] = [:] }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(isSelected ? collectionAccent : AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(invoice.documentNumber).font(AdminType.headlineBold)
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let due = invoice.dueDateKey {
                            Text(displayDate(due)).font(AdminType.footnote)
                                .foregroundStyle(invoice.overdueMinor > 0 ? AdminSurface.crimson : AdminSurface.secondaryText)
                        }
                        Text("\(t("CollectionAvailable")) · \(money(invoice.available))")
                            .font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if invoice.pendingAmountMinor > 0 {
                            Text("\(t("CollectionAwaiting")) · \(money(invoice.pendingAmountMinor))")
                                .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                    .multilineTextAlignment(.leading)
                }
                .padding(16).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.busy || (!isSelected && (!supportsInvoice || amounts.count >= 20)))
            .accessibilityLabel("\(invoice.documentNumber), \(t("CollectionAvailable")), \(money(invoice.available))")
            .accessibilityHint(t(isSelected ? "CollectionDeselectHint" : invoice.usesInstallments ? "CollectionScheduleSelectHint" : "CollectionSelectHint"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("pos.credit.collect.invoice.\(invoice.id)")
            if !supportsInvoice {
                Label(t("CollectionInstallmentsUnavailable"), systemImage: "clock")
                    .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            } else if isSelected, invoice.usesInstallments {
                collectionInstallments(invoice)
                    .padding(.horizontal, 16).padding(.bottom, 16)
            } else if isSelected {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("CollectionAmountLabel")).font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField(t("Amount"), text: Binding(get: { amounts[invoice.id] ?? "" }, set: { amounts[invoice.id] = $0 }))
                        .font(PPBrandFont.bold(26, relativeTo: .title2)).monospacedDigit()
                        .keyboardType(.decimalPad).focused($editing, equals: .invoiceAmount(invoice.id))
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 52)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(invalidAmount ? AdminSurface.crimson : AdminSurface.hairline, lineWidth: 1))
                        .accessibilityLabel("\(t("CollectionAmountLabel")), \(invoice.documentNumber)")
                        .accessibilityIdentifier("pos.credit.collect.amount.\(invoice.id)")
                    if invalidAmount {
                        Text(t("CollectionInvalidAmount")).font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.crimson).fixedSize(horizontal: false, vertical: true)
                    } else if amount < invoice.available {
                        valueRow(t("CollectionInvoiceRemainder"), value: money(invoice.available - amount))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    private func installmentTitle(_ row: POSCreditAccountInvoice.Installment, invoice: POSCreditAccountInvoice) -> String {
        if row.id == "initial_deposit" { return t("CollectionInitialPayment") }
        let index = (invoice.installments.filter { $0.id != "initial_deposit" }.firstIndex { $0.id == row.id } ?? 0) + 1
        return String(format: t("CollectionInstallmentNumber"), locale: Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA"), index)
    }

    private func collectionInstallments(_ invoice: POSCreditAccountInvoice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(AdminSurface.hairline).frame(height: 1).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(t(invoice.agreementVersion > 1 ? "CollectionCurrentSchedule" : "CollectionRecordedSchedule"))
                        .font(AdminType.headlineBold).fixedSize()
                    Spacer(minLength: 0)
                    collectionSelectAllInstallments(invoice)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(t(invoice.agreementVersion > 1 ? "CollectionCurrentSchedule" : "CollectionRecordedSchedule"))
                        .font(AdminType.headlineBold).fixedSize(horizontal: false, vertical: true)
                    collectionSelectAllInstallments(invoice)
                }
            }
            Text(t(supportsInstallmentSelection ? "CollectionInstallmentHelp" : "CollectionInstallmentsUnavailable"))
                .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(invoice.installments) { row in
                    collectionInstallmentRow(row, invoice: invoice)
                    if row.id != invoice.installments.last?.id {
                        Rectangle().fill(AdminSurface.hairline).frame(height: 1)
                            .padding(.horizontal, 12).accessibilityHidden(true)
                    }
                }
            }
            .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 14))
            if let amount = selected[invoice.id] {
                valueRow(t("SelectedForCollection"), value: money(amount))
            }
        }
        .accessibilityIdentifier("pos.credit.collect.schedule.\(invoice.id)")
    }

    private func collectionSelectAllInstallments(_ invoice: POSCreditAccountInvoice) -> some View {
        let eligible = invoice.installments.filter { $0.available > 0 }
        let allSelected = !eligible.isEmpty && Set((installmentAmounts[invoice.id] ?? [:]).keys) == Set(eligible.map(\.id))
        return Button {
            editing = nil
            installmentAmounts[invoice.id] = allSelected ? [:] : Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, decimalAmount($0.available)) })
        } label: {
            Text(t(allSelected ? "CollectionClearInstallments" : "CollectionSelectAllInstallments"))
                .font(AdminType.footnoteBold).foregroundStyle(collectionAccent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy || !supportsInstallmentSelection || eligible.isEmpty)
        .accessibilityIdentifier("pos.credit.collect.installments.all.\(invoice.id)")
    }

    private func collectionInstallmentRow(_ row: POSCreditAccountInvoice.Installment, invoice: POSCreditAccountInvoice) -> some View {
        let title = installmentTitle(row, invoice: invoice)
        let isSelected = installmentAmounts[invoice.id]?[row.id] != nil
        let selectable = row.available > 0 && supportsInstallmentSelection
        let symbol = isSelected ? "checkmark.circle.fill" : row.due == 0 ? "checkmark.circle" : row.available == 0 ? "clock" : "circle"
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                editing = nil
                var entries = installmentAmounts[invoice.id] ?? [:]
                if isSelected { entries.removeValue(forKey: row.id) }
                else { entries[row.id] = decimalAmount(row.available) }
                installmentAmounts[invoice.id] = entries
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isSelected ? collectionAccent : row.due == 0 ? AdminSurface.emerald : AdminSurface.secondaryText)
                        .frame(width: 28).frame(minHeight: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(AdminType.headlineBold)
                        Text(displayDate(row.dueDateKey)).font(AdminType.footnote)
                            .foregroundStyle(row.due > 0 && row.dueDateKey < model.asOf ? AdminSurface.crimson : AdminSurface.secondaryText)
                        valueRow(t("CollectionRecordedAmount"), value: money(row.amountMinor))
                        if row.paidMinor > 0 {
                            valueRow(t("Received"), value: money(row.paidMinor))
                        }
                        if (row.creditedMinor ?? 0) > 0 {
                            valueRow(t("Credits"), value: money(row.creditedMinor ?? 0))
                        }
                        if (row.writtenOffMinor ?? 0) > 0 {
                            valueRow(t("CollectionWrittenOff"), value: money(row.writtenOffMinor ?? 0))
                        }
                        if row.pendingAmountMinor > 0 {
                            valueRow(t("CollectionAwaiting"), value: money(row.pendingAmountMinor))
                        }
                        if row.due == 0 {
                            Text(t("CollectionInstallmentSettled")).font(AdminType.footnoteBold).foregroundStyle(AdminSurface.emerald)
                        } else if row.available != row.amountMinor {
                            valueRow(t("CollectionAvailable"), value: money(row.available))
                        }
                    }
                    .foregroundStyle(AdminSurface.primaryText).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(model.busy || !selectable)
            .accessibilityElement(children: .combine)
            .accessibilityHint(selectable ? t(isSelected ? "CollectionInstallmentDeselectHint" : "CollectionInstallmentSelectHint") : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("pos.credit.collect.installment.\(invoice.id).\(row.id)")
            if isSelected { collectionInstallmentAmount(row, invoice: invoice).padding(.horizontal, 12).padding(.bottom, 12) }
        }
    }

    private func collectionInstallmentAmount(_ row: POSCreditAccountInvoice.Installment, invoice: POSCreditAccountInvoice) -> some View {
        let raw = installmentAmounts[invoice.id]?[row.id] ?? ""
        let amount = POSCreditCheckoutSheet.minor(raw) ?? 0
        let invalid = amount <= 0 || amount > row.available
        return VStack(alignment: .leading, spacing: 8) {
            Text(t("CollectionAmountLabel")).font(AdminType.footnoteBold).foregroundStyle(AdminSurface.secondaryText)
            TextField(t("Amount"), text: Binding(get: { installmentAmounts[invoice.id]?[row.id] ?? "" }, set: { value in
                var entries = installmentAmounts[invoice.id] ?? [:]
                entries[row.id] = value
                installmentAmounts[invoice.id] = entries
            }))
            .font(PPBrandFont.bold(24, relativeTo: .title2)).monospacedDigit()
            .keyboardType(.decimalPad).focused($editing, equals: .installmentAmount(invoice.id, row.id))
            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 52)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(invalid ? AdminSurface.crimson : AdminSurface.hairline, lineWidth: 1))
            .accessibilityLabel("\(t("CollectionAmountLabel")), \(installmentTitle(row, invoice: invoice)), \(invoice.documentNumber)")
            .accessibilityIdentifier("pos.credit.collect.installmentAmount.\(invoice.id).\(row.id)")
            if invalid {
                Text(t("CollectionInvalidAmount")).font(AdminType.footnote).foregroundStyle(AdminSurface.crimson)
                    .fixedSize(horizontal: false, vertical: true)
            } else if amount < row.available {
                valueRow(t("CollectionInstallmentRemainder"), value: money(row.available - amount))
            }
        }
    }

    private var collectionPayment: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("CollectionPaymentTitle")).font(PPBrandFont.bold(20, relativeTo: .title3))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                ForEach(methods, id: \.self) { key in
                    Button { editing = nil; method = key } label: {
                        HStack(spacing: 10) {
                            Image(systemName: methodSymbol(key)).font(.system(size: 19, weight: .medium)).accessibilityHidden(true)
                            Text(t(key)).font(AdminType.headlineBold)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if method == key {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(method == key ? collectionAccent : AdminSurface.primaryText)
                        .padding(14).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background(method == key ? AdminSurface.primarySoft : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(method == key ? collectionAccent : AdminSurface.hairline, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(method == key ? .isSelected : [])
                    .accessibilityIdentifier("pos.credit.collect.method.\(key)")
                }
            }
            if methods.isEmpty {
                Text(t("NoCollectionMethod")).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
            } else {
                Label(t(method == "cash" ? "CollectionCashHelp" : "CollectionPendingHelp"), systemImage: method == "cash" ? "checkmark.shield" : "clock")
                    .font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if method != "cash", !method.isEmpty {
                field("Reference") {
                    TextField(t("CollectionReferencePlaceholder"), text: $reference)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editing, equals: .reference)
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityIdentifier("pos.credit.collect.reference")
                }
                if reference.count > 200 {
                    Text(t("CollectionReferenceLimit")).font(AdminType.footnote).foregroundStyle(AdminSurface.crimson)
                }
            }
        }
    }

    private func collectionReview(_ summary: POSCreditAccountSummary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("CollectionReviewTitle")).font(AdminType.subheadlineBold).foregroundStyle(AdminSurface.secondaryText)
                Text(money(total)).font(PPBrandFont.bold(44, relativeTo: .largeTitle)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Label(t(method), systemImage: methodSymbol(method)).font(AdminType.headlineBold).foregroundStyle(collectionAccent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($collectionFocus, equals: .review)
            panel {
                ForEach(model.invoices.filter { selected[$0.id] != nil }) { invoice in
                    valueRow(invoice.documentNumber, value: money(selected[invoice.id] ?? 0), identifier: true)
                    if invoice.usesInstallments {
                        ForEach(invoice.installments.filter { selectedInstallments[invoice.id]?[$0.id] != nil }) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                valueRow(installmentTitle(row, invoice: invoice), value: money(selectedInstallments[invoice.id]?[row.id] ?? 0))
                                Text(displayDate(row.dueDateKey)).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if method != "cash" {
                    valueRow(t("Reference"), value: reference.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                Rectangle().fill(AdminSurface.hairline).frame(height: 1).accessibilityHidden(true)
                valueRow(t(method == "cash" ? "CollectionBalanceAfter" : "CollectionBalanceUntilClear"),
                         value: money(max(0, summary.outstandingMinor - (method == "cash" ? total : 0))))
            }
            Text(t(method == "cash" ? "CollectionCashHelp" : "CollectionPendingHelp"))
                .font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(t(method == "cash" ? "CollectionCashAcceptance" : "CollectionPendingAcceptance"), isOn: $accepted)
                .font(AdminType.headlineBold).tint(collectionAccent).padding(.vertical, 8)
                .accessibilityIdentifier("pos.credit.collect.accept")
            action("CollectionEdit", symbol: "pencil") { reviewing = false; accepted = false }
                .disabled(model.busy)
        }
    }

    private var collectionDock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !reviewing {
                valueRow(t("SelectedForCollection"), value: money(total))
            }
            Button {
                editing = nil
                if reviewing {
                    guard valid, accepted else { return }
                    model.collect(amounts: selected, installments: selectedInstallments, method: method, reference: reference)
                    if model.pending?.operation == "recordPosCollection" { amounts = [:]; installmentAmounts = [:]; reference = "" }
                    reviewing = false; accepted = false
                } else {
                    guard valid else { return }
                    reviewing = true
                }
            } label: {
                HStack(spacing: 10) {
                    Text(t(reviewing ? (method == "cash" ? "CollectionConfirmCash" : "CollectionConfirmPending") : "CollectionReviewAction"))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: reviewing ? "checkmark" : (Language.isRTL() ? "arrow.left" : "arrow.right"))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(AccountActionStyle(prominent: true, cornerRadius: 11))
            .disabled(!valid || (reviewing && !accepted))
            .accessibilityIdentifier(reviewing ? "pos.credit.collect.confirm" : "pos.credit.collect.review")
        }
        .frame(maxWidth: 720).padding(.horizontal, AdminSpacing.screenMargin).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.surface)
        .overlay(alignment: .top) { Rectangle().fill(AdminSurface.hairline).frame(height: 1).accessibilityHidden(true) }
    }

    private var collectionResult: [String: Any]? {
        guard model.canRecover, let record = model.pending, record.operation == "recordPosCollection",
              let data = record.result, let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = value["collectionStatus"] as? String, ["cleared", "pending"].contains(status),
              let outstanding = value["outstandingMinor"] as? Int, outstanding >= 0 else { return nil }
        return value
    }

    private func collectionReceipt(_ result: [String: Any]) -> some View {
        let pending = result["collectionStatus"] as? String == "pending"
        let request = model.pending.flatMap { try? JSONSerialization.jsonObject(with: $0.request) as? [String: Any] } ?? [:]
        let allocations = request["allocations"] as? [[String: Any]] ?? []
        let recordedAmount = allocations.reduce(0) { $0 + ($1["amountMinor"] as? Int ?? 0) }
        return VStack(alignment: .leading, spacing: 20) {
            Image(systemName: pending ? "clock.badge.checkmark" : "checkmark.circle.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(pending ? collectionAccent : AdminSurface.emerald).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(t(pending ? "CollectionPendingTitle" : "CollectionSuccessTitle"))
                    .font(PPBrandFont.bold(28, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader)
                Text(money(recordedAmount)).font(PPBrandFont.bold(44, relativeTo: .largeTitle)).monospacedDigit()
                if let name = model.customerName { Text(name).font(AdminType.headlineBold) }
                if let subtitle = headerSubtitle { Text(subtitle).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pos.credit.collect.result")
            .accessibilityFocused($collectionFocus, equals: .receipt)
            Text(t(pending ? "CollectionPendingHelp" : "CollectionSuccessHelp"))
                .font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            panel {
                valueRow(t("Method"), value: t(request["method"] as? String ?? "cash"))
                valueRow(t("CollectionBalanceRemaining"), value: money(result["outstandingMinor"] as? Int ?? 0))
                if let ref = request["reference"] as? String, !ref.isEmpty { valueRow(t("Reference"), value: ref) }
            }
            action("CollectionViewReceipt", symbol: "doc.text", prominent: true) {
                tab = "collections"
                model.acknowledge(nextKind: "collections")
            }
            .disabled(model.busy)
            .accessibilityIdentifier("pos.credit.collect.finish")
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(AdminSurface.hairline, lineWidth: 1))
    }

    private func decimalAmount(_ minor: Int) -> String {
        String(minor / 100) + "." + String(format: "%02d", minor % 100)
    }

    private func methodSymbol(_ method: String) -> String {
        switch method {
        case "cash": return "banknote"
        case "card": return "creditcard"
        case "cheque": return "doc.text"
        case "bank_transfer": return "building.columns"
        default: return "arrow.left.arrow.right"
        }
    }
    private var policyPresets: [Int] { [5000, 10000, 15000, 25000, 50000] }

    private var quickReasonTags: [String] {
        [
            Language.get("POS_CreditAccount_ReasonTagClientRequest", alter: "طلب من العميل"),
            Language.get("POS_CreditAccount_ReasonTagIncreasePurchases", alter: "توسيع المشتريات"),
            Language.get("POS_CreditAccount_ReasonTagAdminApproval", alter: "موافقة الإدارة"),
            Language.get("POS_CreditAccount_ReasonTagAnnualReview", alter: "مراجعة دورية"),
            Language.get("POS_CreditAccount_ReasonTagAccountSettlement", alter: "تسوية حساب")
        ]
    }

    private func refreshPolicyDraft() {
        guard let policy = model.administration?.policy else {
            policyVersion = nil
            return
        }
        if policyVersion == nil || policyVersion != policy.version {
            policyEnabled = policy.enabled
            let cents = policy.limitMinor % 100
            policyLimit = String(policy.limitMinor / 100) + "." + (cents < 10 ? "0" : "") + String(cents)
            policyVersion = policy.version
            policyValidationError = nil
            policyReasonAttempted = false
        }
    }

    private func submitPolicyProposal(data: POSCreditAdministrationPage) {
        editing = nil

        // Validate Limit
        guard let amount = POSCreditCheckoutSheet.minor(policyLimit), amount >= 0 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                policyValidationError = Language.get("POS_CreditAccount_InvalidLimit", alter: "يرجى إدخال حد ائتماني صالح بالأرقام.")
            }
            editing = .policyLimit
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // Validate Reason
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                policyReasonAttempted = true
                policyValidationError = Language.get("POS_CreditAccount_ReasonRequired", alter: "يلزم كتابة سبب الطلب لإرسال سياسة الائتمان.")
            }
            editing = .reason
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        guard trimmedReason.count <= 500 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                policyReasonAttempted = true
                policyValidationError = Language.get("POS_CreditAccount_ReasonTooLong", alter: "اختصر السبب إلى ٥٠٠ حرف أو أقل.")
            }
            editing = .reason
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // Clean validation state
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            policyValidationError = nil
            policyReasonAttempted = false
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        model.policy(enabled: policyEnabled, limit: amount, reason: trimmedReason)
    }

    private var administrationSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            sectionHeading("Administration", symbol: "slider.horizontal.3")

            if let data = model.administration {
                currentPolicyCard(data: data)
            }

            if model.needsStepUp && (model.permitted("pos.credit_terms.manage") || model.permitted("pos.credit.approve")) {
                stepUpVerificationCard
            }

            if let data = model.administration, model.permitted("pos.credit_terms.manage") {
                editPolicyProposalCard(data: data)
            }

            if let data = model.administration {
                reviewQueueSection(data: data)
            }

            action("Refresh", symbol: "arrow.clockwise") { model.loadAdministration() }
                .disabled(model.busy)
        }
        .onAppear { refreshPolicyDraft() }
    }

    private func currentPolicyCard(data: POSCreditAdministrationPage) -> some View {
        panel {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(data.policy.enabled ? AdminSurface.primary.opacity(0.12) : Color.gray.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: data.policy.enabled ? "shield.checkmark.fill" : "lock.shield.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(data.policy.enabled ? AdminSurface.primary : AdminSurface.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(t("CurrentPolicy"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(data.policy.enabled
                         ? Language.get("POS_CreditAccount_ActivePolicyStatus", alter: "الائتمان مفعّل ونشط")
                         : Language.get("POS_CreditAccount_DisabledPolicyStatus", alter: "الائتمان مقفل حالياً"))
                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                        .foregroundStyle(data.policy.enabled ? AdminSurface.primary : AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(data.policy.enabled ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(String(format: Language.get("POS_CreditAccount_PolicyVersionLabel", alter: "إصدار v%d"), Int32(data.policy.version)))
                        .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AdminSurface.control, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(t("Limit"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)

                Text(money(data.policy.limitMinor))
                    .font(PPBrandFont.bold(Language.isRTL() ? 34 : 30, relativeTo: .title))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    private var stepUpVerificationCard: some View {
        panel {
            Label(t("StepUp"), systemImage: "lock.shield")
                .font(AdminType.headlineBold).accessibilityAddTraits(.isHeader)
            Text(t("VerificationHelp")).font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText).fixedSize(horizontal: false, vertical: true)
            action("StepUp", symbol: "lock.shield") { editing = nil; stepUpPresented = true }
        }
    }

    private func editPolicyProposalCard(data: POSCreditAdministrationPage) -> some View {
        panel {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(t("EditPolicy"))
                        .font(PPBrandFont.bold(17, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text("اقتراح تعديل سقف وحالة الائتمان للحساب")
                        .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
            }

            // Toggle Enable/Disable
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("EnableCredit"))
                        .font(AdminType.bodyBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text("السماح للعميل بالشراء الآجل وسحب الفواتير")
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
                Toggle("", isOn: $policyEnabled)
                    .labelsHidden()
                    .tint(AdminSurface.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Credit Limit Field
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                HStack {
                    Text(t("Limit"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text("المبلغ بالريال القطري")
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                HStack(spacing: 8) {
                    TextField(t("Limit"), text: $policyLimit)
                        .keyboardType(.decimalPad)
                        .focused($editing, equals: .policyLimit)
                        .font(PPBrandFont.bold(22, relativeTo: .title3))
                        .monospacedDigit()
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .onChange(of: policyLimit) { _ in
                            if policyValidationError != nil {
                                policyValidationError = nil
                            }
                        }

                    Text("ر.ق.")
                        .font(PPBrandFont.bold(15, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                )

                // Quick Preset Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(policyPresets, id: \.self) { preset in
                            Button {
                                policyLimit = "\(preset).00"
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if policyValidationError != nil {
                                    policyValidationError = nil
                                }
                            } label: {
                                Text("\(preset)")
                                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AdminSurface.control, in: Capsule())
                                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.5))
                                    .foregroundStyle(AdminSurface.primaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider().overlay(AdminSurface.hairline)

            // Reason & Justification Section
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                HStack(alignment: .center, spacing: 6) {
                    Text(t("Reason"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(Language.get("POS_CreditAccount_ReasonRequiredBadge", alter: "مطلوب للتوثيق"))
                        .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.10), in: Capsule())

                    Spacer()

                    Text("\(reason.count)/500")
                        .font(AdminType.caption)
                        .foregroundStyle(reason.count > 500 ? AdminSurface.crimson : AdminSurface.secondaryText)
                }

                // Quick Reason Tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickReasonTags, id: \.self) { tag in
                            Button {
                                reason = tag
                                policyReasonAttempted = false
                                if policyValidationError != nil {
                                    policyValidationError = nil
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Text(tag)
                                    .font(Font.custom("Beiruti-Medium", size: 11.5, relativeTo: .caption2))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Reason Input Area
                TextField(t("ReasonPlaceholder"), text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($editing, equals: .reason)
                    .multilineTextAlignment(.leading)
                    .font(AdminType.body)
                    .foregroundStyle(AdminSurface.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                policyReasonAttempted && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.red
                                    : (reason.count > 500 ? AdminSurface.crimson : AdminSurface.hairline),
                                lineWidth: (policyReasonAttempted && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 1.5 : 1
                            )
                    )
                    .onChange(of: reason) { _ in
                        if policyValidationError != nil {
                            policyValidationError = nil
                        }
                    }
                    .accessibilityLabel(t("Reason"))

                Text(t("ReasonHelp"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            // Inline Validation Error Banner
            if let error = policyValidationError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.red)
                    Text(error)
                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.red)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Primary Send Button
            Button {
                submitPolicyProposal(data: data)
            } label: {
                HStack(spacing: 8) {
                    if model.busy {
                        ProgressView()
                            .tint(.white)
                        Text(Language.get("POS_CreditAccount_SubmittingPolicy", alter: "جارٍ إرسال سياسة الائتمان…"))
                            .font(PPBrandFont.bold(16, relativeTo: .callout))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .bold))
                            .rotationEffect(.degrees(Language.isRTL() ? 180 : 0))
                        Text(t("SavePolicy"))
                            .font(PPBrandFont.bold(16, relativeTo: .callout))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundColor(.white)
                .background(
                    model.busy || model.pending != nil ? AdminSurface.primary.opacity(0.6) : AdminSurface.primary,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(model.busy || model.pending != nil)

            Text(Language.get("POS_CreditAccount_PolicyHint", alter: "سيتم تطبيق التعديل فورياً أو توجيهه للاعتماد المالي المستقل بحسب صلاحياتك."))
                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func reviewQueueSection(data: POSCreditAdministrationPage) -> some View {
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

    private var collectionHistory: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
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
                Text(value).font(PPBrandFont.bold(15, relativeTo: .body)).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                valueTitle(title, identifier: identifier)
                Text(value).font(PPBrandFont.bold(15, relativeTo: .body))
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
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(t(title))
                    .font(AdminType.calloutBold)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
        var cornerRadius: CGFloat = AdminRadius.button
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            let destructive = configuration.role == .destructive
            let foreground: Color = {
                if !isEnabled {
                    return AdminSurface.secondaryText.opacity(0.7)
                }
                if prominent {
                    return Color.white
                }
                if destructive {
                    return AdminSurface.crimson
                }
                return AdminSurface.primary
            }()

            let background: Color = {
                if !isEnabled {
                    return AdminSurface.control.opacity(0.4)
                }
                if prominent {
                    return configuration.isPressed ? AdminSurface.primaryPressed : AdminSurface.primary
                }
                if destructive {
                    return configuration.isPressed
                        ? AdminSurface.crimson.opacity(0.14)
                        : AdminSurface.crimson.opacity(0.08)
                }
                return configuration.isPressed
                    ? AdminSurface.primary.opacity(0.14)
                    : AdminSurface.primary.opacity(0.075)
            }()

            let strokeColor: Color = {
                if !isEnabled {
                    return AdminSurface.hairline.opacity(0.5)
                }
                if prominent {
                    return Color.clear
                }
                if destructive {
                    return AdminSurface.crimson.opacity(0.24)
                }
                return AdminSurface.primary.opacity(0.20)
            }()

            configuration.label
                .foregroundStyle(foreground)
                .padding(.horizontal, AdminSpacing.base)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                .background(background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if !prominent {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(strokeColor, lineWidth: 1.2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: AdminSurface.primary.opacity(isEnabled && prominent ? 0.25 : 0), radius: 6, y: 2)
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

// MARK: - Collection Receipt Models & PDF Generation

@MainActor
struct POSCreditCollectionReceipt: Equatable, Identifiable {
    nonisolated var id: String { collectionId + "_" + eventId }

    struct Allocation: Equatable, Identifiable {
        var id: String { invoiceId }
        let invoiceId: String
        let amountMinor: Int
    }

    let collectionId: String
    let eventId: String
    let documentNumber: String
    let customerId: String
    let customerName: String
    
    let branchId: String
    let createdAt: Date?
    let createdAtString: String
    let status: String
    let operation: String
    let paymentMethod: String
    let reference: String?
    let reason: String?
    let tenderAmountMinor: Int
    let receivedMinor: Int
    let pendingAmountMinor: Int
    let reversedMinor: Int
    let refundedMinor: Int
    let remainingBalanceMinor: Int?
    let allocations: [Allocation]
}

struct POSCreditCollectionReceiptDocument: Identifiable {
    let id: String
    let receipt: POSCreditCollectionReceipt
    let pdfData: Data
    let pdfURL: URL
}

@MainActor
enum POSCreditCollectionReceiptPDF {
    static func document(for receipt: POSCreditCollectionReceipt) throws -> POSCreditCollectionReceiptDocument {
        let data = try pdfData(for: receipt)
        let safeDocNum = receipt.documentNumber.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
        let filename = "collection-receipt-\(safeDocNum.isEmpty ? receipt.collectionId : safeDocNum)-\(UUID().uuidString.prefix(6)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return POSCreditCollectionReceiptDocument(
            id: receipt.id,
            receipt: receipt,
            pdfData: data,
            pdfURL: url
        )
    }

    static func pdfData(for receipt: POSCreditCollectionReceipt) throws -> Data {
        let receiptWidth: CGFloat = 340.0
        let margin: CGFloat = 20.0
        let contentWidth = receiptWidth - (margin * 2)
        let rtl = Language.isRTL()

        // Fonts (matching POSReceiptDocument.swift)
        let brandFont = UIFont(name: "Beiruti-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let titleFont = UIFont(name: "Beiruti-Medium", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .medium)
        let headerFont = UIFont(name: "Beiruti-Bold", size: 13) ?? UIFont.boldSystemFont(ofSize: 13)
        let bodyFont = UIFont(name: "Beiruti-Regular", size: 11.5) ?? UIFont.systemFont(ofSize: 11.5)
        let boldBodyFont = UIFont(name: "Beiruti-Bold", size: 11.5) ?? UIFont.boldSystemFont(ofSize: 11.5)
        let totalTitleFont = UIFont(name: "Beiruti-Bold", size: 15) ?? UIFont.boldSystemFont(ofSize: 15)
        let totalAmountFont = UIFont(name: "Beiruti-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let footerFont = UIFont(name: "Beiruti-Medium", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .medium)
        let boldMicroFont = UIFont(name: "Beiruti-Bold", size: 9.5) ?? UIFont.boldSystemFont(ofSize: 9.5)
        let microFont = UIFont(name: "Beiruti-Regular", size: 8.5) ?? UIFont.systemFont(ofSize: 8.5)

        // Colors (matching POSReceiptDocument.swift)
        let primaryColor = UIColor(red: 0.49, green: 0.06, blue: 0.20, alpha: 1.0)
        let textColor = UIColor(red: 0.12, green: 0.10, blue: 0.11, alpha: 1.0)
        let secondaryColor = UIColor(red: 0.46, green: 0.42, blue: 0.44, alpha: 1.0)
        let lineColor = UIColor(red: 0.88, green: 0.84, blue: 0.86, alpha: 1.0)
        let amberColor = UIColor(red: 0.78, green: 0.45, blue: 0.05, alpha: 1.0)
        let redColor = UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1.0)

        // Paragraph styles
        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center
        centerStyle.baseWritingDirection = rtl ? .rightToLeft : .leftToRight

        let leadingStyle = NSMutableParagraphStyle()
        leadingStyle.alignment = rtl ? .right : .left
        leadingStyle.baseWritingDirection = rtl ? .rightToLeft : .leftToRight

        let trailingStyle = NSMutableParagraphStyle()
        trailingStyle.alignment = rtl ? .left : .right
        trailingStyle.baseWritingDirection = rtl ? .rightToLeft : .leftToRight

        // Dynamic Height Calculation
        var dynamicHeight: CGFloat = margin

        // Logo
        let logoImage = UIImage(named: "LogoV5") ?? UIImage(named: "AD_LOGO")
        if logoImage != nil {
            dynamicHeight += 48.0 + 8.0
        }

        // Brand + Subtitle + Badge
        dynamicHeight += 24.0 + 20.0 + 20.0

        // Separator + Metadata rows + Separator
        var metadataRowCount = 5
        if !receipt.customerName.isEmpty || !receipt.customerId.isEmpty { metadataRowCount += 1 }
        if let ref = receipt.reference, !ref.isEmpty { metadataRowCount += 1 }
        if let reason = receipt.reason, !reason.isEmpty { metadataRowCount += 1 }
        dynamicHeight += 10.0 + (CGFloat(metadataRowCount) * 16.0) + 12.0

        // Allocations Section
        dynamicHeight += 22.0
        if !receipt.allocations.isEmpty {
            dynamicHeight += 16.0
            dynamicHeight += CGFloat(receipt.allocations.count) * 18.0 + 8.0
        } else {
            dynamicHeight += 22.0
        }

        // Totals Block
        var totalsRowCount = 1
        if receipt.tenderAmountMinor > 0 && receipt.tenderAmountMinor != receipt.receivedMinor { totalsRowCount += 1 }
        if receipt.pendingAmountMinor > 0 { totalsRowCount += 1 }
        if receipt.reversedMinor > 0 { totalsRowCount += 1 }
        if receipt.refundedMinor > 0 { totalsRowCount += 1 }
        if receipt.remainingBalanceMinor != nil { totalsRowCount += 1 }
        dynamicHeight += 26.0 + (CGFloat(totalsRowCount - 1) * 18.0) + 12.0

        // Footer Section
        dynamicHeight += 8.0 + 12.0 + 18.0 + 20.0 + 12.0 + 13.0 + 12.0 + 16.0 + 14.0 + margin

        let totalPageHeight = max(dynamicHeight, 420.0)
        let pageBounds = CGRect(x: 0, y: 0, width: receiptWidth, height: totalPageHeight)

        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = [
            kCGPDFContextCreator as String: "Pure Pets Admin",
            kCGPDFContextTitle as String: "\(Language.isRTL() ? "سند تحصيل حساب آجل" : "Credit Collection Receipt") #\(receipt.documentNumber)"
        ]

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: rendererFormat)

        let data = pdfRenderer.pdfData { context in
            let w = receiptWidth
            let m = margin
            let cw = contentWidth

            context.beginPage()
            let cgContext = context.cgContext

            // White background
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(pageBounds)

            var currentY: CGFloat = m

            // 1. Draw Logo
            if let logo = logoImage {
                let logoSize: CGFloat = 48.0
                let logoRect = CGRect(x: (w - logoSize) / 2.0, y: currentY, width: logoSize, height: logoSize)
                logo.draw(in: logoRect)
                currentY += logoSize + 8.0
            }

            // 2. Brand Name
            let brandString = rtl ? "بيور بتس" : "PURE PETS"
            let brandAttr: [NSAttributedString.Key: Any] = [
                .font: brandFont,
                .foregroundColor: textColor,
                .paragraphStyle: centerStyle
            ]
            let brandRect = CGRect(x: m, y: currentY, width: cw, height: 24.0)
            brandString.draw(in: brandRect, withAttributes: brandAttr)
            currentY += 24.0

            // 3. Title
            let titleString = rtl ? "سند تحصيل حساب آجل" : "Credit Collection Receipt"
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: secondaryColor,
                .paragraphStyle: centerStyle
            ]
            let titleRect = CGRect(x: m, y: currentY, width: cw, height: 18.0)
            titleString.draw(in: titleRect, withAttributes: titleAttr)
            currentY += 20.0

            // 4. Status Badge Stamp
            let isConfirmed = receipt.status == "cleared" || receipt.operation == "clear"
            let isPending = receipt.status == "pending"
            let isReversed = receipt.status == "reversed" || receipt.operation == "reverse"
            let isRefunded = receipt.status == "refunded" || receipt.operation == "refundPayout"

            let badgeText: String
            let badgeColor: UIColor
            if isConfirmed {
                badgeText = rtl ? "[ تم التحصيل بنجاح ومؤكد ]" : "[ Collection Confirmed ]"
                badgeColor = primaryColor
            } else if isPending {
                badgeText = rtl ? "[ بانتظار المقاصة والتأكيد ]" : "[ Pending Clearing ]"
                badgeColor = amberColor
            } else if isReversed {
                badgeText = rtl ? "[ سند تحصيل معكوس ]" : "[ Collection Reversed ]"
                badgeColor = redColor
            } else if isRefunded {
                badgeText = rtl ? "[ مسترد ]" : "[ Refunded ]"
                badgeColor = redColor
            } else {
                badgeText = "[ \(POSCreditAccountCopy.text(receipt.status)) ]"
                badgeColor = secondaryColor
            }

            let badgeAttr: [NSAttributedString.Key: Any] = [
                .font: boldBodyFont,
                .foregroundColor: badgeColor,
                .paragraphStyle: centerStyle
            ]
            let badgeRect = CGRect(x: m, y: currentY, width: cw, height: 16.0)
            badgeText.draw(in: badgeRect, withAttributes: badgeAttr)
            currentY += 18.0

            // Separator helpers
            func drawDashedSeparator(y: CGFloat) {
                cgContext.saveGState()
                cgContext.setStrokeColor(lineColor.cgColor)
                cgContext.setLineWidth(0.8)
                let dashes: [CGFloat] = [4.0, 3.0]
                cgContext.setLineDash(phase: 0, lengths: dashes)
                cgContext.move(to: CGPoint(x: m, y: y))
                cgContext.addLine(to: CGPoint(x: w - m, y: y))
                cgContext.strokePath()
                cgContext.restoreGState()
            }

            func drawSolidSeparator(y: CGFloat) {
                cgContext.saveGState()
                cgContext.setStrokeColor(lineColor.cgColor)
                cgContext.setLineWidth(0.5)
                cgContext.move(to: CGPoint(x: m, y: y))
                cgContext.addLine(to: CGPoint(x: w - m, y: y))
                cgContext.strokePath()
                cgContext.restoreGState()
            }

            func drawRow(
                label: String,
                value: String,
                labelFont: UIFont? = nil,
                valueFont: UIFont? = nil,
                labelColor: UIColor? = nil,
                valueColor: UIColor? = nil,
                y: CGFloat,
                height: CGFloat = 16.0
            ) {
                let actualLabelFont = labelFont ?? bodyFont
                let actualValueFont = valueFont ?? boldBodyFont
                let actualLabelColor = labelColor ?? secondaryColor
                let actualValueColor = valueColor ?? textColor

                let halfWidth = cw * 0.52
                let valWidth = cw * 0.48

                let labelAttr: [NSAttributedString.Key: Any] = [
                    .font: actualLabelFont,
                    .foregroundColor: actualLabelColor,
                    .paragraphStyle: leadingStyle
                ]
                let valAttr: [NSAttributedString.Key: Any] = [
                    .font: actualValueFont,
                    .foregroundColor: actualValueColor,
                    .paragraphStyle: trailingStyle
                ]

                if rtl {
                    let labelRect = CGRect(x: w - m - halfWidth, y: y, width: halfWidth, height: height)
                    let valRect = CGRect(x: m, y: y, width: valWidth, height: height)
                    label.draw(in: labelRect, withAttributes: labelAttr)
                    value.draw(in: valRect, withAttributes: valAttr)
                } else {
                    let labelRect = CGRect(x: m, y: y, width: halfWidth, height: height)
                    let valRect = CGRect(x: m + halfWidth, y: y, width: valWidth, height: height)
                    label.draw(in: labelRect, withAttributes: labelAttr)
                    value.draw(in: valRect, withAttributes: valAttr)
                }
            }

            // Top dashed separator
            currentY += 4.0
            drawDashedSeparator(y: currentY)
            currentY += 8.0

            // Metadata rows
            drawRow(label: rtl ? "رقم السند" : "Receipt No.", value: receipt.documentNumber, y: currentY)
            currentY += 16.0

            let formattedDate: String = {
                if let date = receipt.createdAt {
                    return POSReceiptFormat.date(date)
                } else if !receipt.createdAtString.isEmpty {
                    return receipt.createdAtString
                }
                return POSReceiptFormat.date(Date())
            }()
            drawRow(label: rtl ? "التاريخ والوقت" : "Date & Time", value: formattedDate, y: currentY)
            currentY += 16.0

            let customerDisplay = !receipt.customerName.isEmpty ? receipt.customerName : receipt.customerId
            if !customerDisplay.isEmpty {
                drawRow(label: rtl ? "العميل" : "Customer", value: customerDisplay, y: currentY)
                currentY += 16.0
            }

            drawRow(label: rtl ? "الفرع" : "Branch", value: receipt.branchId, y: currentY)
            currentY += 16.0

            drawRow(label: rtl ? "طريقة الدفع" : "Payment Method", value: POSReceiptFormat.paymentMethod(receipt.paymentMethod), y: currentY)
            currentY += 16.0

            if let ref = receipt.reference, !ref.isEmpty {
                drawRow(label: rtl ? "الرقم المرجعي" : "Reference", value: ref, y: currentY)
                currentY += 16.0
            }

            let statusDisplay: String = {
                if isConfirmed { return rtl ? "تم التحصيل والمقاصة" : "Cleared & Confirmed" }
                if isPending { return rtl ? "بانتظار التأكيد" : "Pending Confirmation" }
                if isReversed { return rtl ? "تم عكس السند" : "Reversed" }
                if isRefunded { return rtl ? "مسترد" : "Refunded" }
                return POSCreditAccountCopy.text(receipt.status)
            }()
            drawRow(label: rtl ? "حالة السند" : "Status", value: statusDisplay, y: currentY)
            currentY += 16.0

            if let reason = receipt.reason, !reason.isEmpty {
                drawRow(label: rtl ? "السبب" : "Reason", value: reason, y: currentY)
                currentY += 16.0
            }

            // Dashed separator before allocations
            currentY += 4.0
            drawDashedSeparator(y: currentY)
            currentY += 10.0

            // Allocations Section
            let allocHeader = rtl ? "الفواتير المسددة" : "Allocated Invoices"
            let allocHeaderAttr: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: primaryColor,
                .paragraphStyle: leadingStyle
            ]
            allocHeader.draw(in: CGRect(x: m, y: currentY, width: cw, height: 18.0), withAttributes: allocHeaderAttr)
            currentY += 20.0

            if !receipt.allocations.isEmpty {
                let col1Title = rtl ? "رقم الفاتورة" : "Invoice ID"
                let col2Title = rtl ? "المبلغ المسدد" : "Allocated Amount"
                let subheaderAttr: [NSAttributedString.Key: Any] = [
                    .font: boldMicroFont,
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: leadingStyle
                ]
                let subheaderValAttr: [NSAttributedString.Key: Any] = [
                    .font: boldMicroFont,
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: trailingStyle
                ]

                let halfWidth = cw * 0.55
                let valWidth = cw * 0.45
                if rtl {
                    col1Title.draw(in: CGRect(x: w - m - halfWidth, y: currentY, width: halfWidth, height: 14.0), withAttributes: subheaderAttr)
                    col2Title.draw(in: CGRect(x: m, y: currentY, width: valWidth, height: 14.0), withAttributes: subheaderValAttr)
                } else {
                    col1Title.draw(in: CGRect(x: m, y: currentY, width: halfWidth, height: 14.0), withAttributes: subheaderAttr)
                    col2Title.draw(in: CGRect(x: m + halfWidth, y: currentY, width: valWidth, height: 14.0), withAttributes: subheaderValAttr)
                }
                currentY += 16.0

                for allocation in receipt.allocations {
                    drawRow(
                        label: allocation.invoiceId,
                        value: POSCreditAccountCopy.money(allocation.amountMinor),
                        labelFont: bodyFont,
                        valueFont: boldBodyFont,
                        labelColor: textColor,
                        valueColor: textColor,
                        y: currentY,
                        height: 16.0
                    )
                    currentY += 18.0
                }
            } else {
                let note = rtl ? "دفعة عامة على الحساب" : "Payment on Account"
                let noteAttr: [NSAttributedString.Key: Any] = [
                    .font: bodyFont,
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: leadingStyle
                ]
                note.draw(in: CGRect(x: m, y: currentY, width: cw, height: 16.0), withAttributes: noteAttr)
                currentY += 20.0
            }

            // Solid separator before totals
            currentY += 4.0
            drawSolidSeparator(y: currentY)
            currentY += 8.0

            // Financial Summary Block
            drawRow(
                label: rtl ? "المبلغ المستلم" : "Total Received",
                value: POSCreditAccountCopy.money(receipt.receivedMinor),
                labelFont: totalTitleFont,
                valueFont: totalAmountFont,
                labelColor: textColor,
                valueColor: primaryColor,
                y: currentY,
                height: 24.0
            )
            currentY += 24.0

            if receipt.tenderAmountMinor > 0 && receipt.tenderAmountMinor != receipt.receivedMinor {
                drawRow(label: rtl ? "مبلغ العملية" : "Tendered Amount", value: POSCreditAccountCopy.money(receipt.tenderAmountMinor), y: currentY)
                currentY += 16.0
            }

            if receipt.pendingAmountMinor > 0 {
                drawRow(label: rtl ? "بانتظار المقاصة" : "Pending Amount", value: POSCreditAccountCopy.money(receipt.pendingAmountMinor), valueColor: amberColor, y: currentY)
                currentY += 16.0
            }

            if receipt.reversedMinor > 0 {
                drawRow(label: rtl ? "المبلغ المعكوس" : "Reversed Amount", value: POSCreditAccountCopy.money(receipt.reversedMinor), valueColor: redColor, y: currentY)
                currentY += 16.0
            }

            if receipt.refundedMinor > 0 {
                drawRow(label: rtl ? "المبلغ المسترد" : "Refunded Amount", value: POSCreditAccountCopy.money(receipt.refundedMinor), valueColor: redColor, y: currentY)
                currentY += 16.0
            }

            if let remaining = receipt.remainingBalanceMinor {
                drawRow(
                    label: rtl ? "رصيد الحساب المتبقي" : "Remaining Balance",
                    value: POSCreditAccountCopy.money(remaining),
                    labelFont: bodyFont,
                    valueFont: boldBodyFont,
                    labelColor: secondaryColor,
                    valueColor: textColor,
                    y: currentY
                )
                currentY += 16.0
            }

            // Footer (Identical to POSReceiptDocument.swift)
            currentY += 8.0
            drawDashedSeparator(y: currentY)
            currentY += 12.0

            // Thank You Note
            let thanksStr = Language.get("POS_Receipt_ThankYou", alter: "شكرًا لاختياركم بيوربيتس")
            let thanksAttr: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: primaryColor,
                .paragraphStyle: centerStyle
            ]
            thanksStr.draw(in: CGRect(x: m, y: currentY, width: cw, height: 18.0), withAttributes: thanksAttr)
            currentY += 20.0

            // Website
            let urlStr = "https://pure-pets.net"
            let contactAttr: [NSAttributedString.Key: Any] = [
                .font: microFont,
                .foregroundColor: secondaryColor,
                .paragraphStyle: centerStyle
            ]
            urlStr.draw(in: CGRect(x: m, y: currentY, width: cw, height: 12.0), withAttributes: contactAttr)
            currentY += 13.0

            // Support phone & email
            let supportStr = "support@pure-pets.net  •  +974 5999 7720"
            supportStr.draw(in: CGRect(x: m, y: currentY, width: cw, height: 12.0), withAttributes: contactAttr)
            currentY += 16.0

            // Footer Tx / Document ID
            let txFooter = "#" + receipt.documentNumber + " · " + (receipt.eventId.isEmpty ? receipt.collectionId : receipt.eventId)
            txFooter.draw(in: CGRect(x: m, y: currentY, width: cw, height: 14.0), withAttributes: contactAttr)
        }

        guard data.count > 0 else { throw POSReceiptExportError.emptyDocument }
        return data
    }
}

// MARK: - PDFKit SwiftUI Viewer

struct POSCreditPDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = true
        pdfView.backgroundColor = UIColor.systemGroupedBackground
        if let doc = PDFDocument(data: data) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil, let doc = PDFDocument(data: data) {
            uiView.document = doc
        }
    }
}

// MARK: - Dedicated Collection Receipt Preview Sheet

struct POSCreditCollectionReceiptSheet: View {
    let document: POSCreditCollectionReceiptDocument
    @Environment(\.dismiss) private var dismiss
    @State private var sharePresented = false
    @State private var copiedNotice = false

    private var receipt: POSCreditCollectionReceipt { document.receipt }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    POSCreditPDFPreview(data: document.pdfData)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 96)
                }

                bottomDock
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $sharePresented) {
                POSCreditAccountShare(url: document.pdfURL)
            }
            .overlay(alignment: .top) {
                if copiedNotice {
                    Text(Language.isRTL() ? "تم نسخ رقم السند" : "Receipt number copied")
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85), in: Capsule())
                        .padding(.top, 64)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Language.isRTL() ? "إغلاق" : "Close")

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.isRTL() ? "معاينة سند التحصيل" : "Collection Receipt Preview")
                    .font(AdminType.headlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                HStack(spacing: 6) {
                    Text(receipt.documentNumber)
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .monospacedDigit()
                    Button {
                        UIPasteboard.general.string = receipt.documentNumber
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            copiedNotice = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                copiedNotice = false
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Spacer()

            Button {
                printPDF()
            } label: {
                Image(systemName: "printer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Language.isRTL() ? "طباعة" : "Print")

            Button {
                sharePresented = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Language.isRTL() ? "مشاركة" : "Share")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AdminSurface.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AdminSurface.hairline).frame(height: 0.5)
        }
    }

    private var bottomDock: some View {
        HStack(spacing: 12) {
            Button {
                printPDF()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "printer.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(Language.isRTL() ? "طباعة السند" : "Print Receipt")
                        .font(AdminType.calloutBold)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                sharePresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text(Language.isRTL() ? "مشاركة PDF" : "Share PDF")
                        .font(AdminType.calloutBold)
                }
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AdminSurface.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(AdminSurface.hairline).frame(height: 0.5)
        }
    }

    private func printPDF() {
        guard UIPrintInteractionController.isPrintingAvailable else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "\(Language.isRTL() ? "سند تحصيل" : "Collection Receipt") #\(receipt.documentNumber)"
        controller.printInfo = info
        controller.printingItem = document.pdfData

        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let root = window.rootViewController else { return }
        let presenter = topPresenter(from: root)

        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: presenter.view.bounds, in: presenter.view, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }

    private func topPresenter(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController { return topPresenter(from: presented) }
        if let nav = root as? UINavigationController, let visible = nav.visibleViewController { return topPresenter(from: visible) }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController { return topPresenter(from: selected) }
        return root
    }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var reason = ""
    @State private var evidence = ""
    @State private var amount = ""
    @State private var accepted = false
    @State private var selectedOperation: Operation?
    @State private var reviewing = false
    @State private var showsValidation = false
    @FocusState private var focusedInput: Input?
    @AccessibilityFocusState private var reviewFocused: Bool

    private enum Input: Hashable { case amount, reason, evidence }
    private enum Operation: String, Identifiable {
        case clear, reject, reverse
        var id: String { rawValue }
        var titleKey: String {
            switch self { case .clear: return "ServiceClearTitle"; case .reject: return "ServiceRejectTitle"; case .reverse: return "ServiceReverseTitle" }
        }
        var reviewKey: String {
            switch self { case .clear: return "ServiceReviewClear"; case .reject: return "ServiceReviewReject"; case .reverse: return "ServiceReviewReverse" }
        }
        var submitKey: String {
            switch self { case .clear: return "Clear"; case .reject: return "ServiceRejectTitle"; case .reverse: return "ServiceSubmitReverse" }
        }
        var noticeKey: String {
            switch self { case .clear: return "ClearNotice"; case .reject: return "ServiceRejectNotice"; case .reverse: return "ReverseNotice" }
        }
        var symbol: String {
            switch self { case .clear: return "checkmark.seal"; case .reject: return "xmark.circle"; case .reverse: return "arrow.uturn.backward" }
        }
        var callable: String {
            switch self { case .clear: return "confirmPosCollectionClearing"; case .reject: return "rejectPosCollectionTender"; case .reverse: return "reversePosCollection" }
        }
    }

    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private func money(_ value: Int) -> String { POSCreditAccountCopy.money(value) }
    private var operations: [Operation] {
        switch collection.status {
        case "pending": return model.permitted("pos.credit.clear") ? [.clear, .reject] : []
        case "requires_review": return model.permitted("pos.credit.clear") ? [.reject] : []
        case "cleared", "partially_reversed":
            return collection.receivedMinor > 0 && model.permitted("pos.credit.reverse") ? [.reverse] : []
        default: return []
        }
    }
    private var operation: Operation? {
        if let selectedOperation, operations.contains(selectedOperation) { return selectedOperation }
        return operations.first
    }
    private var canEdit: Bool { operation != nil && !model.busy && model.pending == nil && !model.storageFailed }
    private var amountMinor: Int? { POSCreditCheckoutSheet.minor(amount) }
    private var amountValid: Bool {
        operation != .reverse || (amountMinor.map { $0 > 0 && $0 <= collection.receivedMinor } ?? false)
    }
    private var reasonValid: Bool { !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.count <= 500 }
    private var evidenceValid: Bool {
        operation != .clear || (!evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && evidence.count <= 200)
    }
    private var fieldsValid: Bool { amountValid && reasonValid && evidenceValid }
    private var statusColor: Color {
        switch collection.status {
        case "cleared": return AdminSurface.emerald
        case "pending", "requires_review": return AdminSurface.amber
        case "rejected": return AdminSurface.crimson
        default: return AdminSurface.secondaryText
        }
    }
    private var statusSymbol: String {
        switch collection.status {
        case "cleared": return "checkmark.circle.fill"
        case "pending": return "clock.fill"
        case "requires_review": return "exclamationmark.circle.fill"
        case "reversed", "partially_reversed": return "arrow.uturn.backward.circle.fill"
        case "rejected": return "xmark.circle.fill"
        default: return "doc.text"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                            if model.canRead {
                                paymentReceipt
                                availabilityNotice
                                if let operation {
                                    if reviewing { review(operation).id("payment-review") }
                                    else { editor(operation) }
                                } else {
                                    notice(t("ServiceNoAction"), symbol: "lock", color: AdminSurface.secondaryText)
                                }
                            } else {
                                notice(t("ServiceAccessChanged"), symbol: "lock.shield", color: AdminSurface.secondaryText)
                            }
                        }
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, AdminSpacing.sm)
                        .padding(.bottom, AdminSpacing.lg)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .dismissKeyboardOnTapOutside()
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let operation { actionDock(operation) }
                    }
                    .onChange(of: reviewing) {
                        if reviewing {
                            proxy.scrollTo("payment-review", anchor: .top)
                            reviewFocused = true
                        }
                    }
                }
            }
            .background(AdminSurface.background)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("Done")) {
                        focusedInput = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.font(AdminType.calloutBold)
                }
            }
            .onChange(of: reason) { invalidateReview() }
            .onChange(of: evidence) { invalidateReview() }
            .onChange(of: amount) { invalidateReview() }
            .onChange(of: selectedOperation) { invalidateReview(); showsValidation = false; focusedInput = nil }
            .onChange(of: operations) { invalidateReview() }
            .onChange(of: model.accountVersion) { invalidateReview() }
        }
        .tint(AdminSurface.primary)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA"))
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: AdminSpacing.md) {
            Text(t("Service"))
                .font(PPBrandFont.bold(22, relativeTo: .title2))
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Close"))
            .accessibilityIdentifier("pos.credit.service.close")
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.base)
        .frame(maxWidth: .infinity)
    }

    private var paymentReceipt: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AdminSpacing.md))
            layout {
                Text(collection.documentNumber)
                    .font(PPBrandFont.bold(18, relativeTo: .headline)).monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label(t(collection.status), systemImage: statusSymbol)
                    .font(AdminType.footnoteBold).foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(t(collection.status == "pending" ? "Pending" : "Received"))
                    .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                Text(money(collection.status == "pending" ? collection.pendingAmountMinor : collection.receivedMinor))
                    .font(PPBrandFont.bold(36, relativeTo: .largeTitle)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pos.credit.service.paymentAmount")
            }
            DisclosureGroup {
                VStack(spacing: AdminSpacing.sm) {
                    fact(t("ServicePaymentAmount"), money(collection.tenderAmountMinor))
                    fact(t("Received"), money(collection.receivedMinor))
                    fact(t("Pending"), money(collection.pendingAmountMinor))
                    if collection.reversedMinor > 0 { fact(t("Reversed"), money(collection.reversedMinor)) }
                    fact(t("Method"), t(collection.paymentMethod))
                }
                .padding(.top, AdminSpacing.sm)
            } label: {
                Text(t("ServicePaymentDetails"))
                    .font(AdminType.footnoteBold)
                    .frame(minHeight: AdminTouchTarget.minimum, alignment: .leading)
            }
            .accessibilityIdentifier("pos.credit.service.paymentDetails")
        }
        .foregroundStyle(AdminSurface.primaryText)
        .padding(AdminSpacing.lg)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var availabilityNotice: some View {
        if model.storageFailed {
            notice(t("StorageFailed"), symbol: "lock.shield", color: AdminSurface.crimson)
        } else if model.pending != nil {
            notice(t("OtherPending"), symbol: "clock.arrow.circlepath", color: AdminSurface.secondaryText)
        } else if model.busy {
            HStack(spacing: AdminSpacing.sm) {
                ProgressView()
                Text(t("Loading")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            }
        }
    }

    private func editor(_ operation: Operation) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.lg) {
            if operations.count > 1 {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: AdminSpacing.sm))
                    : AnyLayout(HStackLayout(spacing: AdminSpacing.sm))
                layout {
                    ForEach(operations) { option in
                        Button { selectedOperation = option } label: {
                            Label(t(option.titleKey), systemImage: option.symbol)
                                .font(AdminType.calloutBold)
                                .foregroundStyle(option == operation ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(AdminSpacing.md)
                                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                                .background(option == operation ? AdminSurface.primarySoft : AdminSurface.surface,
                                            in: RoundedRectangle(cornerRadius: AdminRadius.button))
                                .overlay {
                                    RoundedRectangle(cornerRadius: AdminRadius.button)
                                        .strokeBorder(option == operation ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == operation ? [.isSelected] : [])
                        .accessibilityIdentifier("pos.credit.service.operation.\(option.rawValue)")
                    }
                }
            }
            Label(t(operation.titleKey), systemImage: operation.symbol)
                .font(PPBrandFont.bold(22, relativeTo: .title2))
                .foregroundStyle(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
            if operation == .reverse { reversalAmount }
            reasonField
            if operation == .clear { evidenceField }
            notice(t(operation.noticeKey), symbol: operation == .reverse ? "checkmark.shield" : "info.circle",
                   color: AdminSurface.secondaryText)
        }
        .disabled(!canEdit)
    }

    private var reversalAmount: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.md))
            layout {
                Text(t("ServiceReverseAmount")).font(AdminType.calloutBold).foregroundStyle(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    amount = "\(collection.receivedMinor / 100)." + String(format: "%02d", collection.receivedMinor % 100)
                    focusedInput = nil
                } label: {
                    Text(t("ServiceFullAmount"))
                        .font(AdminType.footnoteBold).foregroundStyle(AdminSurface.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: AdminTouchTarget.minimum, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: t("ServiceUseFullAmount"), money(collection.receivedMinor)))
                .accessibilityIdentifier("pos.credit.service.useFullAmount")
            }
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.md) {
                TextField(t("ServiceAmountPlaceholder"), text: $amount)
                    .font(PPBrandFont.bold(32, relativeTo: .title))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(direction == .rightToLeft ? .trailing : .leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .focused($focusedInput, equals: .amount)
                    .accessibilityLabel(t("ServiceReverseAmount"))
                    .accessibilityIdentifier("pos.credit.service.amount")
                Text(t("ServiceCurrency")).font(AdminType.calloutBold).foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(.horizontal, AdminSpacing.base).padding(.vertical, AdminSpacing.md)
            .frame(minHeight: 64)
            .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay { fieldBorder(invalid: (showsValidation || !amount.isEmpty) && !amountValid, focused: focusedInput == .amount) }
            if (showsValidation || !amount.isEmpty) && !amountValid {
                validation(String(format: t("ServiceAmountError"), money(collection.receivedMinor)))
            } else {
                Text(String(format: t("ServiceAvailableToReverse"), money(collection.receivedMinor)))
                    .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let amountMinor, amountValid, amountMinor > 0 {
                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    Label(t("ServiceAfterApproval"), systemImage: "checkmark.shield")
                        .font(AdminType.footnoteBold).foregroundStyle(AdminSurface.secondaryText)
                    fact(t("ServiceRestoredDebt"), money(amountMinor))
                    fact(t("ServiceCollectedRemaining"), money(collection.receivedMinor - amountMinor))
                }
                .padding(AdminSpacing.base)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(t("ServiceReasonTitle")).font(AdminType.calloutBold).foregroundStyle(AdminSurface.primaryText)
            TextField(t("ServiceReasonPlaceholder"), text: $reason, axis: .vertical)
                .font(AdminType.body).lineLimit(2...6)
                .multilineTextAlignment(.leading)
                .focused($focusedInput, equals: .reason)
                .padding(AdminSpacing.base)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay { fieldBorder(invalid: (showsValidation || reason.count > 500) && !reasonValid, focused: focusedInput == .reason) }
                .accessibilityLabel(t("ServiceReasonTitle"))
                .accessibilityHint(t("ReasonHelp"))
                .accessibilityIdentifier("pos.credit.service.reason")
            Text(String(format: t("ServiceCharacterCount"), reason.count, 500))
                .font(AdminType.caption).foregroundStyle(reason.count > 500 ? AdminSurface.crimson : AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if (showsValidation || reason.count > 500) && !reasonValid { validation(t("ServiceReasonError")) }
        }
    }

    private var evidenceField: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(t("Evidence")).font(AdminType.calloutBold).foregroundStyle(AdminSurface.primaryText)
            TextField(t("ServiceEvidencePlaceholder"), text: $evidence, axis: .vertical)
                .font(AdminType.body).lineLimit(2...4)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .multilineTextAlignment(.leading)
                .focused($focusedInput, equals: .evidence)
                .padding(AdminSpacing.base)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay { fieldBorder(invalid: (showsValidation || evidence.count > 200) && !evidenceValid, focused: focusedInput == .evidence) }
                .accessibilityLabel(t("Evidence"))
                .accessibilityIdentifier("pos.credit.service.evidence")
            Text(String(format: t("ServiceCharacterCount"), evidence.count, 200))
                .font(AdminType.caption).foregroundStyle(evidence.count > 200 ? AdminSurface.crimson : AdminSurface.secondaryText)
            if (showsValidation || evidence.count > 200) && !evidenceValid { validation(t("ServiceEvidenceError")) }
        }
    }

    private func review(_ operation: Operation) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            Text(t("ServiceReviewTitle"))
                .font(PPBrandFont.bold(24, relativeTo: .title2)).foregroundStyle(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader).accessibilityFocused($reviewFocused)
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                fact(t("ServiceOperation"), t(operation.titleKey))
                if operation == .reverse, let amountMinor {
                    fact(t("ServiceReverseAmount"), money(amountMinor))
                    fact(t("ServiceCollectedAfterApproval"), money(collection.receivedMinor - amountMinor))
                } else if operation == .clear {
                    fact(t("Pending"), money(collection.pendingAmountMinor))
                }
                Divider().overlay(AdminSurface.hairline)
                Text(t("ServiceReasonTitle")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                Text(reason.trimmingCharacters(in: .whitespacesAndNewlines)).font(AdminType.body)
                if operation == .clear {
                    Text(t("Evidence")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                    Text(evidence.trimmingCharacters(in: .whitespacesAndNewlines)).font(AdminType.body)
                }
            }
            .foregroundStyle(AdminSurface.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AdminSpacing.base)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            notice(t(operation.noticeKey), symbol: "info.circle", color: AdminSurface.secondaryText)
            Toggle(isOn: $accepted) {
                Text(t("ServiceAcknowledge"))
                    .font(AdminType.calloutBold).foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, AdminSpacing.sm)
            .disabled(!canEdit)
            .accessibilityIdentifier("pos.credit.service.acknowledge")
        }
    }

    private func actionDock(_ operation: Operation) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(AdminSurface.hairline).frame(height: 1)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: AdminSpacing.sm))
                : AnyLayout(HStackLayout(spacing: AdminSpacing.md))
            layout {
                if reviewing {
                    Button { invalidateReview(); showsValidation = false } label: {
                        Text(t("ServiceEditDetails"))
                            .font(AdminType.calloutBold).foregroundStyle(AdminSurface.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: AdminTouchTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                }
                Button(role: reviewing && operation != .clear ? .destructive : nil) {
                    if reviewing { submit(operation) } else { beginReview() }
                } label: {
                    Text(t(reviewing ? operation.submitKey : operation.reviewKey))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(ServiceActionStyle(destructive: reviewing && operation != .clear))
                .disabled(!canEdit || (reviewing && (!accepted || !fieldsValid)))
                .accessibilityIdentifier(reviewing ? "pos.credit.service.submit" : "pos.credit.service.review")
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, AdminSpacing.md)
            .frame(maxWidth: .infinity)
        }
        .background(AdminSurface.surface)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AdminSpacing.md))
        return layout {
            Text(title).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(AdminType.calloutBold).foregroundStyle(AdminSurface.primaryText).monospacedDigit()
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func fieldBorder(invalid: Bool, focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: AdminRadius.card)
            .strokeBorder(invalid ? AdminSurface.crimson : focused ? AdminSurface.primary : AdminSurface.hairline,
                          lineWidth: invalid || focused || contrast == .increased ? 2 : 1)
            .allowsHitTesting(false)
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label {
            Text(text).font(AdminType.footnote).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
        }
        .foregroundStyle(color)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    private func validation(_ message: String) -> some View {
        notice(message, symbol: "exclamationmark.circle", color: AdminSurface.crimson)
    }

    private func invalidateReview() { accepted = false; reviewing = false; reviewFocused = false }
    private func beginReview() {
        guard canEdit else { return }
        showsValidation = true
        guard fieldsValid else {
            focusedInput = !amountValid ? .amount : !reasonValid ? .reason : .evidence
            return
        }
        focusedInput = nil; accepted = false; reviewing = true
    }
    private func submit(_ operation: Operation) {
        guard canEdit, self.operation == operation, fieldsValid, accepted else { return }
        model.service(collection, operation: operation.callable, reason: reason,
                      evidence: operation == .clear ? evidence : "", amount: operation == .reverse ? amountMinor : nil)
        // The existing account owner retains version checks, approval, step-up and recovery.
        dismiss()
    }

    private struct ServiceActionStyle: ButtonStyle {
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(AdminType.calloutBold)
                .foregroundStyle(isEnabled ? Color.white : AdminSurface.secondaryText)
                .padding(.horizontal, AdminSpacing.base).padding(.vertical, AdminSpacing.md)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                .background(isEnabled ? (destructive ? AdminSurface.crimson : AdminSurface.primary) : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: AdminRadius.button))
                .contentShape(RoundedRectangle(cornerRadius: AdminRadius.button))
                .opacity(configuration.isPressed ? 0.75 : 1)
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
            .dismissKeyboardOnTapOutside()
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
                    Button {
                        focusedField = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
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
