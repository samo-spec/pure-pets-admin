import SwiftUI
import CoreFoundation
import FirebaseAuth

struct POSCreditAdjustmentContext: Decodable {
    struct OriginalItem: Decodable, Identifiable {
        let itemIndex: Int; let name: String; let quantity: Int; let unitIds: [String]; let creditedQuantity: Int; let creditedUnitIds: [String]
        var id: Int { itemIndex }
        var remaining: Int { max(0, quantity - creditedQuantity) }
    }
    struct Collection: Decodable, Identifiable {
        let collectionId: String; let version: Int; let paymentMethod: String; let status: String; let adjustmentHold: Bool; let availableMinor: Int
        var id: String { collectionId }
    }
    struct Writeoff: Decodable, Identifiable { let adjustmentId: String; let remainingMinor: Int; var id: String { adjustmentId } }
    struct Dispute: Decodable, Identifiable { let adjustmentId: String; let collectionId: String; let remainingMinor: Int; var id: String { adjustmentId } }
    let branchId: String; let customerId: String; let invoiceId: String; let version: Int; let accountVersion: Int
    let creditedMinor: Int; let writtenOffMinor: Int; let refundedMinor: Int; let refundLiabilityMinor: Int; let disputeHold: Bool
    let collections: [Collection]; let items: [OriginalItem]; let writeoffs: [Writeoff]; let disputes: [Dispute]; let nextCursor: POSCreditStatementCursor?
}

struct POSCreditAdjustmentSheet: View {
    @ObservedObject var model: POSCreditAccountModel
    let invoice: POSCreditAccountInvoice
    @Environment(\.dismiss) private var dismiss
    @State private var operation = "creditNote"
    @State private var amount = ""
    @State private var reason = ""
    @State private var evidence = ""
    @State private var collectionID = ""
    @State private var sourceID = ""
    @State private var itemMode = false
    @State private var quantities: [Int: Int] = [:]
    @State private var units: Set<String> = []
    @State private var accepted = false
    @State private var verifying = false
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private var operations: [String] {
        var list: [String] = []
        if model.permitted("pos.credit.refund") {
            list.append("creditNote")
            if model.permitted("payments.refund") { list.append("refundPayout") }
        }
        if model.permitted("pos.credit.writeoff") { list += ["writeOff", "recoverWriteOff", "writeOffDispute"] }
        if model.permitted("pos.credit.reverse") { list += ["recordDispute", "recoverDispute"] }
        return list
    }
    private var usesCollection: Bool { ["refundPayout", "recordDispute", "recoverDispute", "writeOffDispute"].contains(operation) }
    private var usesSource: Bool { ["recoverWriteOff", "recoverDispute", "writeOffDispute"].contains(operation) }
    private var collection: POSCreditAdjustmentContext.Collection? { model.adjustmentContext?.collections.first { $0.id == collectionID } }
    private var itemRows: [[String: Any]] {
        (model.adjustmentContext?.items ?? []).compactMap { item in
            let selected = item.unitIds.filter { units.contains("\(item.id):\($0)") && !item.creditedUnitIds.contains($0) }
            let count = item.unitIds.isEmpty ? quantities[item.id] ?? 0 : selected.count
            guard count > 0 else { return nil }
            var row: [String: Any] = ["itemIndex": item.id, "quantity": count]
            if !item.unitIds.isEmpty { row["unitIds"] = selected }
            return row
        }
    }
    private var valid: Bool {
        guard operations.contains(operation), let context = model.adjustmentContext, context.version == invoice.version,
              model.pending == nil, !model.busy, !model.storageFailed, accepted,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 500,
              !usesSource || !sourceID.isEmpty,
              !usesCollection || collection != nil && !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && evidence.count <= 200 else { return false }
        if operation == "creditNote", itemMode { return !itemRows.isEmpty }
        guard let minor = POSCreditCheckoutSheet.minor(amount), minor > 0 else { return false }
        if operation == "refundPayout" { return minor <= context.refundLiabilityMinor && minor <= (collection?.availableMinor ?? 0) && collection?.adjustmentHold != true }
        return true
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(invoice.documentNumber).font(.headline)
                    LabeledContent(t("Outstanding"), value: POSCreditAccountCopy.money(invoice.amountDueMinor))
                    if let context = model.adjustmentContext {
                        LabeledContent(t("Credits"), value: POSCreditAccountCopy.money(context.creditedMinor))
                        LabeledContent(t("RefundLiability"), value: POSCreditAccountCopy.money(context.refundLiabilityMinor))
                        if context.disputeHold { Text(t("DisputeHold")).foregroundStyle(.red) }
                    }
                    Text(t("AdjustmentNotice"))
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    if model.busy { ProgressView() }
                    Button(t("Refresh")) { model.loadAdjustmentContext(invoice) }.disabled(model.busy)
                }
                Picker(t("Action"), selection: $operation) { ForEach(operations, id: \.self) { Text(t($0)).tag($0) } }
                if operation == "creditNote" {
                    Toggle(t("SelectItems"), isOn: $itemMode)
                    if itemMode { itemSelection }
                }
                if operation != "creditNote" || !itemMode { TextField(t("Amount"), text: $amount).keyboardType(.decimalPad) }
                if usesCollection {
                    Picker(t("Collection"), selection: $collectionID) {
                        Text(t("Choose")).tag("")
                        ForEach(model.adjustmentContext?.collections ?? []) { row in Text("\(t(row.paymentMethod)) · \(POSCreditAccountCopy.money(row.availableMinor)) · \(row.id.suffix(8))").tag(row.id) }
                    }
                    if model.adjustmentContext?.nextCursor != nil { Button(t("More")) { collectionID = ""; model.loadAdjustmentContext(invoice, more: true) }.disabled(model.busy) }
                    TextField(t("Evidence"), text: $evidence, axis: .vertical)
                    Text(t("VerifiedPayoutNotice"))
                }
                if usesSource {
                    Picker(t("OriginalAdjustment"), selection: $sourceID) {
                        Text(t("Choose")).tag("")
                        if operation == "recoverWriteOff" {
                            ForEach(model.adjustmentContext?.writeoffs ?? []) { row in Text("\(POSCreditAccountCopy.money(row.remainingMinor)) · \(row.id.suffix(8))").tag(row.id) }
                        } else {
                            ForEach((model.adjustmentContext?.disputes ?? []).filter { $0.collectionId == collectionID }) { row in Text("\(POSCreditAccountCopy.money(row.remainingMinor)) · \(row.id.suffix(8))").tag(row.id) }
                        }
                    }
                }
                TextField(t("Reason"), text: $reason, axis: .vertical)
                Toggle(t("AcceptAdjustment"), isOn: $accepted)
                Button(t("SubmitAdjustment"), role: .destructive) {
                    if model.adjust(invoice, operation: operation, amount: POSCreditCheckoutSheet.minor(amount), items: operation == "creditNote" && itemMode ? itemRows : nil,
                                    collection: usesCollection ? collection : nil, source: usesSource ? sourceID : "", reason: reason, evidence: evidence) {
                        // Return to the account's durable command/review controls.
                        // A storage/preflight failure leaves the entered draft here.
                        dismiss()
                    }
                }.disabled(!valid).frame(minHeight: 44)
                if model.needsStepUp && model.canAdjust {
                    Button(t("StepUp")) { verifying = true }.frame(minHeight: 44)
                }
            }
            .navigationTitle(t("AdjustBalance"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("AdjustBalance"))
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
                .task { operation = operations.first ?? ""; model.loadAdjustmentContext(invoice) }
                .onChange(of: operation) { _ in accepted = false; sourceID = "" }
                .onChange(of: amount) { _ in accepted = false }.onChange(of: reason) { _ in accepted = false }.onChange(of: evidence) { _ in accepted = false }
                .onChange(of: collectionID) { _ in accepted = false; sourceID = "" }.onChange(of: sourceID) { _ in accepted = false }
                .onChange(of: itemMode) { _ in accepted = false }.onChange(of: quantities) { _ in accepted = false }.onChange(of: units) { _ in accepted = false }
                .sheet(isPresented: $verifying, onDismiss: { model.needsStepUp = false }) { POSCreditStepUpSheet() }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }
    private var itemSelection: some View {
        Section(t("SelectItems")) {
            ForEach(model.adjustmentContext?.items ?? []) { item in
                if item.remaining > 0 {
                    if item.unitIds.isEmpty {
                        Stepper("\(item.name) · \(quantities[item.id] ?? 0)", value: Binding(get: { quantities[item.id] ?? 0 }, set: { quantities[item.id] = $0 }), in: 0...item.remaining)
                    } else {
                        DisclosureGroup(item.name) {
                            ForEach(item.unitIds.filter { !item.creditedUnitIds.contains($0) }, id: \.self) { unit in
                                Toggle(unit, isOn: Binding(get: { units.contains("\(item.id):\(unit)") }, set: { if $0 { units.insert("\(item.id):\(unit)") } else { units.remove("\(item.id):\(unit)") } }))
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                    }
                }
            }
            Text(t("PhysicalReturnNotice"))
        }
    }
}

struct POSCreditReportLink: View {
    let branchID: String
    @State private var presented = false
    var body: some View {
        if POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) {
            Button(POSCreditAccountCopy.text("Reports")) { presented = true }.frame(minHeight: 44)
                .sheet(isPresented: $presented) { POSCreditReportSheet(branchID: branchID) }
        }
    }
}
private struct POSCreditReconciliationIssue: Identifiable {
    let documentID: String
    let code: String
    var id: String { documentID + ":" + code }
}
private struct POSCreditReportSheet: View {
    let branchID: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var branch = BranchContextStore.shared
    @State private var kind = "cashflow"
    @State private var start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var totals: [String: Int] = [:]
    @State private var aging: [String: Int] = [:]
    @State private var tenders: [String: Int] = [:]
    @State private var issues: [POSCreditReconciliationIssue] = []
    @State private var cursor: [String: Any]?
    @State private var busy = false
    @State private var error: String?
    @State private var ticket = UUID()
    @State private var asOf = ""
    @State private var count = 0
    @State private var authListener: AuthStateDidChangeListenerHandle?
    private let actorUID = Auth.auth().currentUser?.uid
    private func t(_ key: String) -> String { POSCreditAccountCopy.text(key) }
    private func dateKey(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    var body: some View {
        NavigationStack {
            Form {
                Picker(t("Records"), selection: $kind) { Text(t("Cashflow")).tag("cashflow"); Text(t("Aging")).tag("receivables"); Text(t("Reconciliation")).tag("reconciliation") }
                    .onChange(of: kind) { _ in reset() }
                if kind == "cashflow" {
                    DatePicker(t("From"), selection: $start, displayedComponents: .date).onChange(of: start) { _ in reset() }
                    DatePicker(t("To"), selection: $end, displayedComponents: .date).onChange(of: end) { _ in reset() }
                }
                Text(t(kind == "cashflow" ? "CashflowNotice" : kind == "receivables" ? "AgingNotice" : "ReconciliationNotice"))
                if let error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView() }
                Button(t("Refresh")) { load(more: false) }.disabled(busy || (kind == "cashflow" && (start > end || end.timeIntervalSince(start) > 366 * 86400))).frame(minHeight: 44)
                if !asOf.isEmpty {
                    LabeledContent(t("AsOf"), value: asOf)
                    LabeledContent(t("LoadedCount"), value: String(count))
                    ForEach(totals.keys.sorted(), id: \.self) { key in LabeledContent(t(key), value: POSCreditAccountCopy.money(totals[key] ?? 0)) }
                    ForEach(tenders.keys.sorted(), id: \.self) { key in LabeledContent(t(key), value: POSCreditAccountCopy.money(tenders[key] ?? 0)) }
                    ForEach(["current", "days1to30", "days31to60", "days61to90", "days90plus"].filter { aging[$0] != nil }, id: \.self) { key in LabeledContent(t(key), value: POSCreditAccountCopy.money(aging[key] ?? 0)) }
                    if kind == "reconciliation" {
                        LabeledContent(t("IssueCount"), value: String(issues.count))
                        if issues.isEmpty { Text(t("NoLoadedIssues")) }
                        ForEach(issues) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("Issue_" + issue.code)).foregroundStyle(.red)
                                Text(issue.documentID).font(.caption.monospaced()).textSelection(.enabled)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                    if cursor != nil { Text(t("MoreAvailable")); Button(t("More")) { load(more: true) }.disabled(busy) }
                }
            }
            .navigationTitle(t("Reports"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("Reports"))
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
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
                .onChange(of: branch.activeBranch?.branchID) { _ in dismiss() }
                .onAppear {
                    authListener = Auth.auth().addStateDidChangeListener { _, user in
                        let uid = user?.uid
                        Task { @MainActor in if uid != actorUID { reset(); dismiss() } }
                    }
                    load(more: false)
                }
                .onDisappear { ticket = UUID(); if let authListener { Auth.auth().removeStateDidChangeListener(authListener) }; authListener = nil }
        }
    }
    private func safeMerged(_ current: [String: Int], _ values: [String: Any]) -> [String: Int]? {
        var result = current
        for (key, raw) in values {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            guard value.isFinite, value.rounded() == value, abs(value) <= 9_007_199_254_740_991 else { return nil }
            let (total, overflow) = result[key, default: 0].addingReportingOverflow(Int(value))
            guard !overflow, total >= -9_007_199_254_740_991, total <= 9_007_199_254_740_991 else { return nil }
            result[key] = total
        }
        return result
    }
    private func reset() { ticket = UUID(); busy = false; totals = [:]; aging = [:]; tenders = [:]; issues = []; cursor = nil; asOf = ""; count = 0; error = nil }
    private func load(more: Bool) {
        guard !busy, let actorUID, Auth.auth().currentUser?.uid == actorUID, POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) else { return }
        if !more { reset() }
        var body: [String: Any] = ["contractVersion": 1, "branchId": branchID, "kind": kind, "dateFrom": dateKey(kind == "cashflow" ? start : end), "dateTo": dateKey(end)]
        if more, let cursor { body["cursor"] = cursor }
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else { return }
        busy = true; error = nil; let id = UUID(); ticket = id
        Task { @MainActor in try? await Task.sleep(nanoseconds: 40_000_000_000); if ticket == id, busy { ticket = UUID(); busy = false; error = t("LoadFailed") } }
        PPPOSService.shared().callCreditOperation("getPosCreditReport", request: data, actorUID: actorUID) { data, failure in
            Task { @MainActor in
                guard ticket == id, Auth.auth().currentUser?.uid == actorUID else { return }
                busy = false
                guard failure == nil, let data, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], value["ok"] as? Bool == true,
                      value["branchId"] as? String == branchID, value["kind"] as? String == kind, value["currency"] as? String == "QAR",
                      let scanned = value["scannedCount"], let nextCount = safeMerged(["count": count], ["count": scanned])?["count"], nextCount >= count else { error = t("LoadFailed"); return }
                if kind == "cashflow", let page = value["totals"] as? [String: Any] {
                    let scalar = page.filter { $0.key != "receivedByTender" }
                    guard let nextTotals = safeMerged(totals, scalar), let rawTenders = page["receivedByTender"] as? [String: Any],
                          let nextTenders = safeMerged(tenders, rawTenders) else { error = t("LoadFailed"); return }
                    totals = nextTotals; tenders = nextTenders
                } else if kind == "reconciliation" {
                    guard let page = value["reconciliation"] as? [String: Any], let rawIssues = page["issues"] as? [[String: Any]],
                          let rawCount = page["issueCount"], let expectedCount = safeMerged([:], ["count": rawCount])?["count"],
                          expectedCount == rawIssues.count, rawIssues.count <= 400 else { error = t("LoadFailed"); return }
                    let known = Set(["invoice_balance", "invoice_projection", "invoice_identity", "sale_linkage", "sale_projection", "missing_journal", "journal_mismatch"])
                    let pageIssues = rawIssues.compactMap { row -> POSCreditReconciliationIssue? in
                        guard let document = row["documentId"] as? String, !document.isEmpty, document.count <= 200,
                              let code = row["code"] as? String, known.contains(code) else { return nil }
                        return POSCreditReconciliationIssue(documentID: document, code: code)
                    }
                    guard pageIssues.count == rawIssues.count else { error = t("LoadFailed"); return }
                    issues += pageIssues
                } else {
                    // Aging is one bounded complete snapshot with no More cursor.
                    guard value["nextCursor"] is NSNull, let due = value["outstandingMinor"], let pending = value["pendingAmountMinor"],
                          let nextTotals = safeMerged([:], ["Outstanding": due, "Pending": pending]),
                          let rawAging = value["aging"] as? [String: Any], let nextAging = safeMerged([:], rawAging) else { error = t("LoadFailed"); return }
                    totals = nextTotals; aging = nextAging
                }
                count = nextCount
                asOf = value["asOfDateKey"] as? String ?? ""; cursor = value["nextCursor"] as? [String: Any]
            }
        }
    }
}
