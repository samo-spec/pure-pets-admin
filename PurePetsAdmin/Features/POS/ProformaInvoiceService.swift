import Foundation
import Combine
import CryptoKit
@preconcurrency import FirebaseFunctions

struct ProformaContext: Sendable {
    let currency: String
    let minorUnits: Int
    let maxItems: Int
    init(wire: [String: Any]) throws {
        currency = try ProformaWire.string(wire, "currency")
        minorUnits = try ProformaWire.integer(wire, "minorUnits")
        maxItems = try ProformaWire.integer(wire, "maxItems", positive: true)
        guard minorUnits == 2, maxItems <= 50 else { throw ProformaFailure.invalidResponse }
    }
}

/// The only transport for this feature. There is deliberately no direct Firestore writer.
@MainActor
final class ProformaInvoiceService {
    private let functions = Functions.functions(region: "us-central1")
    private struct Response: @unchecked Sendable { let value: [String: Any] }

    func call(action: String, branchId: String, id: String? = nil, version: Int? = nil,
              commandId: String? = nil, payload: [String: Any]? = nil,
              extras: [String: Any] = [:]) async throws -> [String: Any] {
        var envelope = extras
        envelope["action"] = action; envelope["branchId"] = branchId
        if let id { envelope["id"] = id }; if let version { envelope["expectedVersion"] = version }
        if let commandId { envelope["commandId"] = commandId }; if let payload { envelope["payload"] = payload }
        let callable = functions.httpsCallable("proformaInvoiceCommand")
        callable.timeoutInterval = 45
        do {
            let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Response, Error>) in
                callable.call(envelope) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let wire = result?.data as? [String: Any] { continuation.resume(returning: Response(value: wire)) }
                    else { continuation.resume(throwing: ProformaFailure.invalidResponse) }
                }
            }
            guard response.value["ok"] as? Bool == true else { throw ProformaFailure.invalidResponse }
            return response.value
        } catch let known as ProformaFailure { throw known }
        catch let error as NSError {
            guard error.domain == FunctionsErrorDomain else { throw ProformaFailure.unavailable }
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any] ?? [:]
            let domainCode = details["domainCode"] as? String ?? ""
            if domainCode.contains("EXPIRED") { throw ProformaFailure.expired }
            if domainCode.contains("PRICE") || domainCode.contains("STOCK") || domainCode.contains("INVENTORY") { throw ProformaFailure.stockOrPricing }
            switch FunctionsErrorCode(rawValue: error.code) {
            case .unauthenticated: throw ProformaFailure.unauthenticated
            case .permissionDenied: throw ProformaFailure.denied
            case .aborted, .alreadyExists: throw ProformaFailure.conflict
            case .invalidArgument, .outOfRange: throw ProformaFailure.invalidInput
            case .failedPrecondition: throw ProformaFailure.stockOrPricing
            default: throw ProformaFailure.unavailable
            }
        }
    }

    func invoice(branchId: String, id: String) async throws -> ProformaInvoice {
        let result = try await call(action: "get", branchId: branchId, id: id)
        guard let wire = result["invoice"] as? [String: Any] else { throw ProformaFailure.invalidResponse }
        return try ProformaInvoice(wire: wire)
    }
}

@MainActor
final class ProformaInvoiceStore: ObservableObject {
    @Published private(set) var invoices: [ProformaInvoice] = []
    @Published private(set) var context: ProformaContext?
    @Published private(set) var branchId = ""
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isOpening = false
    @Published private(set) var isMutating = false
    @Published private(set) var confirmationPending = false
    @Published private(set) var isConfirming = false
    @Published private(set) var error: String?
    @Published private(set) var errorIsConflict = false
    @Published private(set) var nextCursor: String?
    @Published private(set) var selected: ProformaInvoice?
    @Published var draft: ProformaDraft?
    @Published private(set) var catalog: [ProformaCatalogItem] = []
    @Published private(set) var catalogCursor: String?
    @Published private(set) var catalogLoading = false
    @Published private(set) var catalogError: String?

    private let service = ProformaInvoiceService()
    private let actorUID: String
    private var savedDraft: ProformaDraft?
    private var generation = UUID()
    private var catalogGeneration = UUID()
    private var selectionGeneration = UUID()
    private var confirmationGeneration = UUID()
    private var pending: PendingCommand?
    private var acceptedID: String?
    private var acceptedVersion: Int?
    private var acceptedStatus: ProformaStatus?

    private struct PendingCommand {
        let action: String
        let branchId: String
        let id: String?
        let version: Int?
        let commandId: String
        let payload: [String: Any]
    }

    init(actorUID: String) { self.actorUID = actorUID }

    var hasUnsavedChanges: Bool { draft != nil && draft != savedDraft }
    var isLocked: Bool { isMutating || confirmationPending || pending != nil || isOpening }
    var canRetryMutation: Bool { pending != nil && !isMutating }
    var hasSelection: Bool { draft != nil || selected != nil }

    func load(branchId: String, force: Bool = false) async {
        if self.branchId != branchId {
            selectionGeneration = UUID(); catalogGeneration = UUID(); isOpening = false; catalogLoading = false
        }
        guard !isMutating, !confirmationPending, pending == nil,
              force || !hasUnsavedChanges else { return }
        let token = UUID(); generation = token
        isLoadingMore = false
        if self.branchId != branchId { clearSelection(); invoices = []; context = nil; nextCursor = nil }
        self.branchId = branchId
        guard !branchId.isEmpty else { return }
        isLoading = true; error = nil; errorIsConflict = false
        defer { if generation == token { isLoading = false } }
        do {
            let response = try await service.call(action: "context", branchId: branchId)
            let loadedContext = try ProformaContext(wire: response)
            guard generation == token, self.branchId == branchId else { return }
            context = loadedContext
            if try restoreRecovery(branchId: branchId) {
                if confirmationPending { await confirmAccepted(branchId: branchId) }
                else if let id = pending?.id {
                    let recovered = try await service.invoice(branchId: branchId, id: id)
                    guard generation == token, self.branchId == branchId else { return }
                    accept(recovered)
                }
                return
            }
            let result = try await service.call(action: "list", branchId: branchId, extras: ["pageSize": 25])
            guard generation == token, self.branchId == branchId else { return }
            guard let rows = result["invoices"] as? [[String: Any]] else { throw ProformaFailure.invalidResponse }
            context = loadedContext; invoices = try rows.map(ProformaInvoice.init(wire:))
            nextCursor = result["nextCursor"] as? String
            if let current = selected, current.branchId == branchId {
                let refreshed = try await service.invoice(branchId: branchId, id: current.id)
                guard generation == token, self.branchId == branchId, !hasUnsavedChanges, !isLocked else { return }; accept(refreshed)
            }
        } catch { if generation == token, self.branchId == branchId { self.error = error.localizedDescription } }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore, !isLoading, !isLocked else { return }
        let token = generation; let branch = branchId
        isLoadingMore = true; defer { if token == generation, branch == branchId { isLoadingMore = false } }
        do {
            let result = try await service.call(action: "list", branchId: branch, extras: ["pageSize": 25, "cursor": cursor])
            guard token == generation, branch == branchId else { return }
            guard let rows = result["invoices"] as? [[String: Any]] else { throw ProformaFailure.invalidResponse }
            let loaded = try rows.map(ProformaInvoice.init(wire:))
            invoices.append(contentsOf: loaded.filter { row in !invoices.contains(where: { $0.id == row.id }) })
            nextCursor = result["nextCursor"] as? String
        } catch { if token == generation, branch == branchId { self.error = error.localizedDescription } }
    }

    func createDraft() {
        guard let context, !isLocked, !isLoading, !hasUnsavedChanges else { return }
        selected = nil; draft = ProformaDraft(branchId: branchId, currency: context.currency)
        savedDraft = nil; error = nil; errorIsConflict = false
    }

    func open(_ invoice: ProformaInvoice) async {
        guard !isLocked, !isLoading, !hasUnsavedChanges else { return }
        let token = UUID(); selectionGeneration = token
        isOpening = true; error = nil
        defer { if selectionGeneration == token { isOpening = false } }
        do {
            let loaded = try await service.invoice(branchId: invoice.branchId, id: invoice.id)
            guard selectionGeneration == token, invoice.branchId == branchId, !hasUnsavedChanges else { return }
            accept(loaded); error = nil; errorIsConflict = false
        } catch { if selectionGeneration == token, invoice.branchId == branchId { self.error = error.localizedDescription } }
    }

    func clearSelection() {
        guard !isLocked else { return }
        selectionGeneration = UUID(); catalogGeneration = UUID()
        draft = nil; selected = nil; savedDraft = nil; error = nil; errorIsConflict = false
    }

    func reloadSelection() async {
        guard let selected, !isLocked, !hasUnsavedChanges else { return }
        await open(selected)
    }

    func searchCatalog(_ query: String, append: Bool = false) async {
        guard let draft, !isLocked else { return }
        if append && catalogLoading { return }
        let token = append ? catalogGeneration : UUID()
        catalogGeneration = token
        if !append { catalog = []; catalogCursor = nil }
        catalogLoading = true; catalogError = nil
        defer { if token == catalogGeneration { catalogLoading = false } }
        var extras: [String: Any] = ["pageSize": 25, "query": query.trimmingCharacters(in: .whitespacesAndNewlines)]
        if append, let cursor = catalogCursor { extras["cursor"] = cursor }
        do {
            let result = try await service.call(action: "catalog", branchId: draft.branchId, extras: extras)
            guard token == catalogGeneration else { return }
            guard let items = result["items"] as? [[String: Any]] else { throw ProformaFailure.invalidResponse }
            let loaded = try items.map(ProformaCatalogItem.init(wire:))
            catalog.append(contentsOf: loaded.filter { item in !catalog.contains(where: { $0.id == item.id }) })
            catalogCursor = result["nextCursor"] as? String
        } catch { if token == catalogGeneration { catalogError = error.localizedDescription } }
    }

    func add(_ item: ProformaCatalogItem) {
        guard var draft, !isLocked, let context, item.currency == draft.currency else { return }
        let selectedIDs = Set(draft.items.flatMap(\.unitIds))
        if selectedIDs.union(item.unitIds).count > 50 {
            error = ProformaFailure.invalidInput.localizedDescription; return
        }
        if draft.items.contains(where: { $0.productId == item.productId && $0.quantityGroupId != item.quantityGroupId }) {
            error = Language.get("Proforma_OneGroupPerProduct", alter: nil); return
        }
        if let index = draft.items.firstIndex(where: { $0.productId == item.productId && $0.quantityGroupId == item.quantityGroupId }) {
            if item.unitIds.isEmpty {
                let old = ProformaDecimal.parse(draft.items[index].quantity, scale: 3) ?? 0
                draft.items[index].quantity = ProformaDecimal.string(old + 1)
                draft.items[index].unitPrice = item.unitPrice
            } else {
                for unit in item.unitPrices {
                    if let existing = draft.items[index].unitPrices.firstIndex(where: { $0.unitId == unit.unitId }) {
                        draft.items[index].unitPrices[existing] = unit
                    } else {
                        draft.items[index].unitIds.append(unit.unitId); draft.items[index].unitPrices.append(unit)
                    }
                }
                draft.items[index].quantity = String(draft.items[index].unitIds.count)
                let sum = draft.items[index].unitPrices.reduce(Decimal(0)) { $0 + (ProformaDecimal.parse($1.unitPrice, scale: 2) ?? 0) }
                draft.items[index].unitPrice = ProformaDecimal.string(ProformaDecimal.rounded(sum / Decimal(draft.items[index].unitIds.count)))
            }
        } else {
            guard draft.items.count < context.maxItems else { error = ProformaFailure.invalidInput.localizedDescription; return }
            draft.items.append(ProformaLine(catalog: item))
        }
        self.draft = draft
    }

    func perform(_ action: String, paymentMethod: String? = nil, cashReceived: String? = nil) async {
        guard !isLocked, !isLoading, let draft else { return }
        do {
            if action != "save" {
                guard !hasUnsavedChanges, let selected else { throw ProformaFailure.invalidInput }
                if action == "issue" || action == "convert" {
                    guard selected.customer != nil, !selected.items.isEmpty,
                          selected.validUntil != nil, !selected.isExpired,
                          action != "convert" || selected.status == .issued else { throw ProformaFailure.invalidInput }
                }
            }
            let payload: [String: Any]
            if action == "save" { payload = try draft.payload() }
            else if action == "convert" {
                guard let method = paymentMethod, ["cash", "card"].contains(method) else { throw ProformaFailure.invalidInput }
                var payment: [String: Any] = ["paymentMethod": method]
                if method == "cash" {
                    guard let cashReceived, let amount = ProformaDecimal.parse(cashReceived, scale: 2),
                          let selected, amount >= ProformaDecimal.minor(selected.totals.totalMinor) else { throw ProformaFailure.invalidInput }
                    payment["cashReceived"] = ProformaDecimal.string(amount)
                }
                payload = payment
            } else { payload = [:] }
            pending = PendingCommand(action: action, branchId: draft.branchId, id: draft.invoiceID,
                                     version: draft.version, commandId: UUID().uuidString, payload: payload)
            do { try persistRecovery(branchId: draft.branchId) }
            catch { pending = nil; throw ProformaFailure.unavailable }
            await executePending()
        } catch { self.error = error.localizedDescription }
    }

    func retryMutation() async { guard !isMutating else { return }; await executePending() }

    private func executePending() async {
        guard let command = pending, !isMutating else { return }
        isMutating = true; error = nil; errorIsConflict = false
        defer { isMutating = false }
        do {
            let result = try await service.call(action: command.action, branchId: command.branchId,
                                                id: command.id, version: command.version,
                                                commandId: command.commandId, payload: command.payload)
            guard let wire = result["invoice"] as? [String: Any] else { throw ProformaFailure.invalidResponse }
            let accepted = try ProformaInvoice(wire: wire)
            // Acceptance is not confirmation: independently observe the persisted document.
            acceptedID = accepted.id; acceptedVersion = accepted.version; acceptedStatus = accepted.status
            confirmationPending = true; pending = nil
            // Persist accepted metadata before readback so an interrupted launch can reconcile safely.
            try persistRecovery(branchId: command.branchId)
            await confirmAccepted(branchId: command.branchId)
        } catch let failure as ProformaFailure {
            error = failure.localizedDescription
            if failure != .unavailable && failure != .invalidResponse {
                pending = nil
                removeRecovery(branchId: command.branchId)
                errorIsConflict = failure == .conflict || failure == .stockOrPricing
            }
        } catch { self.error = ProformaFailure.unavailable.localizedDescription }
    }

    func retryConfirmation() async { await confirmAccepted(branchId: draft?.branchId ?? branchId) }
    private func confirmAccepted(branchId: String) async {
        guard !isConfirming, let id = acceptedID, let version = acceptedVersion, let status = acceptedStatus else { return }
        let token = UUID(); confirmationGeneration = token; isConfirming = true
        defer { if confirmationGeneration == token { isConfirming = false } }
        do {
            let observed = try await service.invoice(branchId: branchId, id: id)
            guard confirmationGeneration == token, acceptedID == id, acceptedVersion == version,
                  acceptedStatus == status else { return }
            guard observed.version >= version, observed.version != version || observed.status == status else { throw ProformaFailure.conflict }
            accept(observed); confirmationPending = false; acceptedID = nil; acceptedVersion = nil; acceptedStatus = nil
            error = nil
            removeRecovery(branchId: branchId)
        } catch { if confirmationGeneration == token, acceptedID == id { self.error = error.localizedDescription } }
    }

    private func accept(_ invoice: ProformaInvoice) {
        selected = invoice; draft = ProformaDraft(invoice); savedDraft = draft
        if let index = invoices.firstIndex(where: { $0.id == invoice.id }) { invoices[index] = invoice }
        else { invoices.insert(invoice, at: 0) }
    }

    private func recoveryURL(branchId: String) throws -> URL {
        guard !actorUID.isEmpty, !branchId.isEmpty else { throw ProformaFailure.denied }
        func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("ProformaRecovery", isDirectory: true).appendingPathComponent(digest(actorUID), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return folder.appendingPathComponent(digest(branchId) + ".json")
    }

    private func persistRecovery(branchId: String) throws {
        var record: [String: Any] = ["schema": 1, "actor": actorUID, "branchId": branchId]
        if let pending {
            record["phase"] = "pending"; record["action"] = pending.action
            record["id"] = pending.id as Any? ?? NSNull(); record["version"] = pending.version as Any? ?? NSNull()
            record["commandId"] = pending.commandId; record["payload"] = pending.payload
        } else if let acceptedID, let acceptedVersion, let acceptedStatus {
            record["phase"] = "accepted"; record["acceptedID"] = acceptedID
            record["acceptedVersion"] = acceptedVersion; record["acceptedStatus"] = acceptedStatus.rawValue
        } else { throw ProformaFailure.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try data.write(to: recoveryURL(branchId: branchId), options: [.atomic, .completeFileProtection])
    }

    private func restoreRecovery(branchId: String) throws -> Bool {
        let url = try recoveryURL(branchId: branchId)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url)
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              record["actor"] as? String == actorUID, record["branchId"] as? String == branchId,
              record["schema"] as? Int == 1 else { throw ProformaFailure.invalidResponse }
        if record["phase"] as? String == "accepted" {
            acceptedID = try ProformaWire.string(record, "acceptedID")
            acceptedVersion = try ProformaWire.integer(record, "acceptedVersion", positive: true)
            guard let status = ProformaStatus(rawValue: try ProformaWire.string(record, "acceptedStatus")) else { throw ProformaFailure.invalidResponse }
            acceptedStatus = status; confirmationPending = true
        } else {
            let action = try ProformaWire.string(record, "action")
            guard ["save", "issue", "cancel", "convert"].contains(action), let payload = record["payload"] as? [String: Any] else { throw ProformaFailure.invalidResponse }
            pending = PendingCommand(action: action, branchId: branchId, id: record["id"] as? String,
                                     version: record["version"] as? Int, commandId: try ProformaWire.string(record, "commandId"), payload: payload)
        }
        error = Language.get("Proforma_RecoveryHint", alter: nil)
        return true
    }

    private func removeRecovery(branchId: String) {
        guard let url = try? recoveryURL(branchId: branchId) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
