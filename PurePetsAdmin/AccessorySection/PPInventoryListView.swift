//
//  PPInventoryListView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//  Preserves 100% of AccessoryManager, PetAccessory, and Firestore backend contracts.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Sendable Conformance

extension PetAccessory: @unchecked Sendable, Identifiable {
    public var id: String { accessoryID }
}

private extension PetAccessory {
    var inventoryDisplayPrice: String {
        guard hasResolvedSellingPrice else {
            return Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح")
        }
        return PetAccessory.formatCurrency(finalPrice)
    }
}

// MARK: - Canonical Live-Pet Inventory Contract

enum PPLivePetInventoryMode: String, CaseIterable, Identifiable {
    case individual = "INDIVIDUAL_TRACKED"
    case quantity = "QUANTITY_TRACKED"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .individual: return Language.get("LivePet_Tracking_Individual", alter: "تتبع كل حيوان")
        case .quantity: return Language.get("LivePet_Tracking_Group", alter: "مجموعة بالكمية")
        }
    }

    var localizedHint: String {
        switch self {
        case .individual: return Language.get("LivePet_Tracking_Individual_Hint", alter: "سجل مستقل لكل حيوان برقم تعريف وسعر بيع خاص.")
        case .quantity: return Language.get("LivePet_Tracking_Group_Hint", alter: "مجموعة متجانسة تُدار ككمية واحدة دون أرقام تعريف فردية.")
        }
    }
}

struct PPLivePetUnitDraft: Identifiable, Equatable {
    let id: String
    var ringTag: String
    var acquisitionDate: Date
    var purchaseCostText: String
    var sellingPriceText: String
    var supplier: String
    var notes: String

    init(
        id: String = "unit_draft_\(UUID().uuidString.lowercased())",
        ringTag: String = "",
        acquisitionDate: Date = Date(),
        purchaseCostText: String = "",
        sellingPriceText: String = "",
        supplier: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.ringTag = ringTag
        self.acquisitionDate = acquisitionDate
        self.purchaseCostText = purchaseCostText
        self.sellingPriceText = sellingPriceText
        self.supplier = supplier
        self.notes = notes
    }
}

struct PPLivePetInventoryUnit: Identifiable, Equatable {
    let id: String
    let ringTag: String
    let status: String
    let sellingPrice: Double?
    let purchaseCost: Double?
    let supplier: String
    let notes: String
    let currentBranchID: String
    let reservationTransactionID: String
    let reservationCustomerName: String
    let reservationCustomerPhone: String
    let reservationValidUntil: Date?
    let mortalityReason: String
    let transferReason: String

    init(dictionary: [String: Any]) {
        id = PPLivePetInventoryService.string(dictionary["unitId"] ?? dictionary["id"])
        ringTag = PPLivePetInventoryService.string(dictionary["ringTag"])
        status = PPLivePetInventoryService.string(dictionary["status"]).uppercased()
        sellingPrice = PPLivePetInventoryService.optionalNumber(dictionary["sellingPrice"])
        purchaseCost = PPLivePetInventoryService.optionalNumber(dictionary["purchaseCost"])
        supplier = PPLivePetInventoryService.string(dictionary["supplier"])
        notes = PPLivePetInventoryService.string(dictionary["notes"])
        currentBranchID = PPLivePetInventoryService.string(dictionary["currentBranchId"])
        reservationTransactionID = PPLivePetInventoryService.string(dictionary["reservationTransactionId"])
        reservationCustomerName = PPLivePetInventoryService.string(dictionary["reservationCustomerName"])
        reservationCustomerPhone = PPLivePetInventoryService.string(dictionary["reservationCustomerPhone"])
        reservationValidUntil = PPLivePetInventoryService.date(dictionary["reservationValidUntil"])
        mortalityReason = PPLivePetInventoryService.string(dictionary["mortalityReason"])
        transferReason = PPLivePetInventoryService.string(dictionary["transferReason"])
    }
}

struct PPLivePetReservationItem: Equatable {
    let productID: String
    let unitIDs: [String]
    let ringTags: [String]
}

struct PPLivePetReservation: Identifiable, Equatable {
    let id: String
    let customerID: String
    let customerSource: String
    let customerName: String
    let customerPhone: String
    let branchID: String
    let validUntil: Date?
    let total: Double
    let currency: String
    let paymentMethod: String
    let items: [PPLivePetReservationItem]

    init(dictionary: [String: Any]) {
        id = PPLivePetInventoryService.string(dictionary["id"])
        customerID = PPLivePetInventoryService.string(dictionary["reservationCustomerId"] ?? dictionary["reservationCustomerUid"])
        customerSource = PPLivePetInventoryService.string(dictionary["reservationCustomerSource"]).lowercased() == "directory" ? "directory" : "account"
        customerName = PPLivePetInventoryService.string(dictionary["customerName"])
        customerPhone = PPLivePetInventoryService.string(dictionary["customerPhone"])
        branchID = PPLivePetInventoryService.string(dictionary["reservationBranchId"])
        validUntil = PPLivePetInventoryService.date(dictionary["reservationValidUntil"])
        total = PPLivePetInventoryService.optionalNumber(dictionary["total"]) ?? 0
        currency = PPLivePetInventoryService.string(dictionary["currency"])
        paymentMethod = PPLivePetInventoryService.string(dictionary["paymentMethod"]).lowercased()
        items = (dictionary["items"] as? [[String: Any]] ?? []).map { source in
            PPLivePetReservationItem(
                productID: PPLivePetInventoryService.string(source["productId"]),
                unitIDs: PPLivePetInventoryService.strings(source["unitIds"]),
                ringTags: PPLivePetInventoryService.strings(source["unitRingTags"])
            )
        }
    }

    func contains(productID: String, unitID: String) -> Bool {
        items.contains { $0.productID == productID && $0.unitIDs.contains(unitID) }
    }
}

struct PPInventoryBranchOption: Identifiable, Equatable {
    let id: String
    let name: String
}

struct PPPosCustomerRecord: Equatable {
    let id: String
    let name: String
    let phone: String
}

@MainActor
enum PPLivePetInventoryService {
    private static let callableTimeout: TimeInterval = 30

    nonisolated static func string(_ value: Any?) -> String {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    nonisolated static func strings(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).map(string).filter { !$0.isEmpty }
    }

    nonisolated static func optionalNumber(_ value: Any?) -> Double? {
        if value is NSNull || value == nil { return nil }
        if let number = value as? NSNumber, number.doubleValue.isFinite { return number.doubleValue }
        if let text = value as? String, let number = Double(text), number.isFinite { return number }
        return nil
    }

    nonisolated static func date(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let seconds = (value as? [String: Any]).flatMap({ optionalNumber($0["seconds"] ?? $0["_seconds"]) }) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let text = value as? String { return ISO8601DateFormatter().date(from: text) }
        return nil
    }

    nonisolated static func commandID(_ purpose: String) -> String {
        "admin-ios-\(purpose)-\(UUID().uuidString.lowercased())"
    }

    nonisolated static func localizedMessage(for error: Error) -> String {
        if error is PPLivePetServiceError || error is PPLivePetOperationValidationError {
            return error.localizedDescription
        }
        let nsError = error as NSError
        let details = (nsError.userInfo["details"] as? [String: Any])
            ?? (nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any])
            ?? [:]
        let domainCode = string(details["domainCode"])
        if domainCode == "POS_RESERVATION_EXPIRED" {
            return Language.get("LivePet_Error_ReservationExpired", alter: "انتهت صلاحية الحجز. حرره ثم أنشئ حجزاً جديداً.")
        }
        switch domainCode {
        case "POS_INVENTORY_UNIT_UNAVAILABLE":
            return Language.get("LivePet_Error_UnitUnavailable", alter: "لم يعد هذا الحيوان متاحاً. حدّث السجل قبل المتابعة.")
        case "POS_INVENTORY_UNIT_BRANCH_MISMATCH", "INVENTORY_UNIT_BRANCH_MISMATCH":
            return Language.get("LivePet_Error_BranchChanged", alter: "تغير فرع الحيوان. حدّث السجل ثم أعد المحاولة.")
        case "POS_INSUFFICIENT_STOCK":
            return Language.get("LivePet_Error_InsufficientStock", alter: "الكمية المتاحة تغيرت. حدّث السجل ثم أعد المحاولة.")
        case "POS_TRANSACTION_STATUS_CHANGED":
            return Language.get("LivePet_Error_ReservationChanged", alter: "تغيرت حالة الحجز بواسطة مستخدم آخر. حدّث الحجوزات قبل المتابعة.")
        case "POS_PRODUCT_NOT_FOUND":
            return Language.get("LivePet_Error_ProductNotFound", alter: "لم يعد سجل الحيوان موجوداً في الكتالوج. حدّث القائمة.")
        case "POS_INVENTORY_UNIT_NOT_FOUND":
            return Language.get("LivePet_Error_UnitNotFound", alter: "لم يعد سجل الحيوان موجوداً. حدّث القائمة قبل المتابعة.")
        case "POS_RESERVATION_BRANCH_SCOPE_TOO_LARGE":
            return Language.get("LivePet_Error_BranchScope", alter: "نطاق فروع حسابك كبير لتحميل الحجوزات دفعة واحدة. استخدم نقطة البيع أو اطلب من المشرف تضييق النطاق.")
        case "POS_RESERVATION_INVALID_PROJECTION":
            return Language.get("LivePet_Error_ReservationProjection", alter: "تعذر عرض حجز بسبب بيانات غير مكتملة. أبلغ المشرف مع تحديث الصفحة.")
        default:
            break
        }
        let reference = domainCode.isEmpty ? "\(nsError.domain):\(nsError.code)" : domainCode
        return String(
            format: Language.get("LivePet_Error_RequestFailed_Format", alter: "تعذر إكمال العملية بأمان. حدّث البيانات وحاول مرة أخرى. المرجع: %@"),
            reference
        )
    }

    static func callInventory(
        action: String,
        productID: String? = nil,
        commandID: String? = nil,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        var request: [String: Any] = ["action": action, "payload": payload]
        if let productID, !productID.isEmpty { request["productId"] = productID }
        if let commandID, !commandID.isEmpty { request["commandId"] = commandID }
        return try await call("validateInventoryChange", payload: request)
    }

    static func callTransaction(_ payload: [String: Any]) async throws -> [String: Any] {
        try await call("processTransaction", payload: payload)
    }

    static func listUnits(
        productID: String,
        includeHistory: Bool = true,
        includeReservations: Bool = true
    ) async throws -> [PPLivePetInventoryUnit] {
        var result: [PPLivePetInventoryUnit] = []
        var cursor = ""
        var seenCursors = Set<String>()
        repeat {
            var request: [String: Any] = [
                "productId": productID,
                "includeHistory": includeHistory,
                "includeReservations": includeReservations,
                "pageSize": 100,
            ]
            if !cursor.isEmpty { request["cursor"] = cursor }
            let response = try await call("listLivePetInventoryUnits", payload: request)
            let page = (response["units"] as? [[String: Any]] ?? []).map(PPLivePetInventoryUnit.init)
            result.append(contentsOf: page.filter { !$0.id.isEmpty })
            let nextCursor = string(response["nextCursor"])
            let hasMore = response["hasMore"] as? Bool == true
            if !hasMore { break }
            guard !nextCursor.isEmpty, !seenCursors.contains(nextCursor) else {
                throw PPLivePetServiceError.invalidResponse
            }
            seenCursors.insert(nextCursor)
            cursor = nextCursor
        } while true
        return result
    }

    static func listReservations(productID: String) async throws -> [PPLivePetReservation] {
        let response = try await call("listPosReservations", payload: ["pageSize": 500])
        if response["truncated"] as? Bool == true {
            throw PPLivePetServiceError.truncatedReservations
        }
        return (response["reservations"] as? [[String: Any]] ?? [])
            .map(PPLivePetReservation.init)
            .filter { reservation in reservation.items.contains(where: { $0.productID == productID }) }
    }

    static func listBranches() async throws -> [PPInventoryBranchOption] {
        let snapshot = try await Firestore.firestore().collection("branches").getDocuments()
        return snapshot.documents.compactMap { document -> PPInventoryBranchOption? in
            let data = document.data()
            if data["isActive"] as? Bool == false { return nil }
            let name = string(data["name"] ?? data["nameAr"] ?? data["branchName"])
            return PPInventoryBranchOption(id: document.documentID, name: name.isEmpty ? document.documentID : name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func createOrMatchCustomer(name: String, phone: String, branchID: String) async throws -> PPPosCustomerRecord {
        let response = try await call("posCustomerCommand", payload: [
            "action": "create",
            "payload": [
                "name": name,
                "phone": phone,
                "branchId": branchID,
                "note": "admin_ios_live_pet_reservation",
            ],
        ])
        guard let source = response["customer"] as? [String: Any] else {
            throw PPLivePetServiceError.invalidResponse
        }
        let customer = PPPosCustomerRecord(
            id: string(source["id"]),
            name: string(source["name"]),
            phone: string(source["phone"])
        )
        guard !customer.id.isEmpty else { throw PPLivePetServiceError.invalidResponse }
        return customer
    }

    static func createReservation(
        productID: String,
        unit: PPLivePetInventoryUnit,
        customer: PPPosCustomerRecord,
        branchID: String,
        validUntil: Date
    ) async throws {
        guard let sellingPrice = unit.sellingPrice, sellingPrice > 0 else {
            throw PPLivePetServiceError.missingSellingPrice
        }
        _ = try await callTransaction([
            "action": "create",
            "commandId": commandID("live-reservation"),
            "payload": [
                "items": [[
                    "productId": productID,
                    "quantity": 1,
                    "inventoryMode": PPLivePetInventoryMode.individual.rawValue,
                    "unitIds": [unit.id],
                    "unitPrices": [["unitId": unit.id, "unitPrice": sellingPrice]],
                ]],
                "paymentMethod": "cash",
                "status": "pending",
                "source": "pos",
                "posCustomerId": customer.id,
                "customerName": customer.name,
                "customerPhone": customer.phone,
                "branchId": branchID,
                "reservationValidUntil": ISO8601DateFormatter().string(from: validUntil),
                "note": "live_pet_customer_reservation",
            ],
        ])
    }

    static func completeReservation(_ reservation: PPLivePetReservation, cashReceived: Double) async throws {
        var binding: [String: Any] = reservation.customerSource == "directory"
            ? ["posCustomerId": reservation.customerID]
            : ["customerUid": reservation.customerID]
        binding["branchId"] = reservation.branchID
        binding["total"] = reservation.total
        binding["currency"] = reservation.currency
        binding["cashReceived"] = cashReceived
        _ = try await callTransaction([
            "action": "complete",
            "transactionId": reservation.id,
            "commandId": commandID("complete-reservation"),
            "payload": binding,
        ])
    }

    static func cancelReservation(_ reservation: PPLivePetReservation) async throws {
        _ = try await callTransaction([
            "action": "cancel",
            "transactionId": reservation.id,
            "commandId": commandID("release-reservation"),
            "expectedStatus": "pending",
            "reason": "admin_live_pet_reservation_release",
            "currency": reservation.currency,
        ])
    }

    @MainActor
    static func updateCatalogPresentation(productID: String, values: [String: Any]) async throws {
        let boxed = PPSendableDictionary(dict: values)
        try await Firestore.firestore().collection("petAccessories").document(productID).updateData(boxed.dict)
    }

    private static func call(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        let boxed = PPSendableDictionary(dict: payload)
        let callable = Functions.functions().httpsCallable(name)
        callable.timeoutInterval = callableTimeout
        let result = try await callable.call(boxed.dict)
        guard let data = result.data as? [String: Any], data["ok"] as? Bool != false else {
            throw PPLivePetServiceError.invalidResponse
        }
        return data
    }
}

private struct PPSendableDictionary: @unchecked Sendable {
    let dict: [String: Any]
}

enum PPLivePetServiceError: LocalizedError {
    case invalidResponse
    case truncatedReservations
    case missingSellingPrice

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return Language.get("LivePet_Error_InvalidResponse", alter: "تعذر تأكيد استجابة الخادم. حدّث البيانات وحاول مرة أخرى.")
        case .truncatedReservations:
            return Language.get("LivePet_Error_ReservationLimit", alter: "تعذر تحميل جميع الحجوزات بأمان. استخدم نقطة البيع لمراجعة القائمة الكاملة.")
        case .missingSellingPrice:
            return Language.get("LivePet_Error_MissingUnitPrice", alter: "حدد سعر بيع صالحاً للحيوان قبل حجزه أو بيعه.")
        }
    }
}

// MARK: - Live-Pet Operations State

private enum PPLivePetOperationContext: Identifiable {
    case migrate
    case intake
    case reserve(PPLivePetInventoryUnit)
    case reservation(PPLivePetReservation)
    case transfer(PPLivePetInventoryUnit)
    case quarantine(PPLivePetInventoryUnit)
    case releaseQuarantine(PPLivePetInventoryUnit)
    case mortality(PPLivePetInventoryUnit)
    case remove(PPLivePetInventoryUnit)
    case price(PPLivePetInventoryUnit)
    case groupAdjustment
    case archive(Bool)

    var id: String {
        switch self {
        case .migrate: return "migrate"
        case .intake: return "intake"
        case .reserve(let unit): return "reserve-\(unit.id)"
        case .reservation(let reservation): return "reservation-\(reservation.id)"
        case .transfer(let unit): return "transfer-\(unit.id)"
        case .quarantine(let unit): return "quarantine-\(unit.id)"
        case .releaseQuarantine(let unit): return "release-\(unit.id)"
        case .mortality(let unit): return "mortality-\(unit.id)"
        case .remove(let unit): return "remove-\(unit.id)"
        case .price(let unit): return "price-\(unit.id)"
        case .groupAdjustment: return "group-adjustment"
        case .archive(let archived): return archived ? "archive" : "restore"
        }
    }
}

@MainActor
private final class PPLivePetOperationsViewModel: ObservableObject {
    let item: PetAccessory

    @Published private(set) var units: [PPLivePetInventoryUnit] = []
    @Published private(set) var reservations: [PPLivePetReservation] = []
    @Published private(set) var branches: [PPInventoryBranchOption] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var operation: PPLivePetOperationContext?

    init(item: PetAccessory) {
        self.item = item
    }

    var mode: PPLivePetInventoryMode? {
        PPLivePetInventoryMode(rawValue: item.inventoryMode ?? "")
    }

    private var staff: PPStaffDoc? { PPStaffAuth.shared().cachedCurrentStaff }
    var canManageStock: Bool { staff?.hasPermission(kStaffPermStockManage) ?? false }
    var canSell: Bool { staff?.hasPermission(kStaffPermPosSell) ?? false }
    var canViewReservations: Bool {
        (staff?.hasPermission(kStaffPermPosView) ?? false) || canSell
    }
    // `processTransaction` enforces both POS selling access and refund access
    // for cancellation. Mirror that compound gate in the UI so a viewer-only
    // staff member never reaches a guaranteed permission-denied mutation.
    var canReleaseReservations: Bool {
        canSell && (staff?.hasPermission(kStaffPermPaymentsRefund) ?? false)
    }
    var canReleaseQuarantine: Bool { staff?.hasPermission("stock.quarantine.release") ?? false }
    var canViewCosts: Bool { staff?.hasPermission("stock.cost.view") ?? false }

    func reservation(for unit: PPLivePetInventoryUnit) -> PPLivePetReservation? {
        reservations.first { $0.contains(productID: item.accessoryID, unitID: unit.id) }
    }

    func load() async {
        guard item.isLivePet else { return }
        isLoading = true
        errorMessage = nil
        do {
            if mode == .individual {
                do {
                    if canManageStock {
                        units = try await PPLivePetInventoryService.listUnits(productID: item.accessoryID)
                    } else if canSell {
                        // `includeReservations` is a stock.manage-only read in
                        // Infra. POS staff still receive available units here;
                        // their pending reservations are loaded through the
                        // separate reservation projection below.
                        units = try await PPLivePetInventoryService.listUnits(
                            productID: item.accessoryID,
                            includeHistory: false,
                            includeReservations: false
                        )
                    } else {
                        units = []
                    }
                } catch {
                    if canManageStock { throw error }
                    units = []
                    errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
                }
            } else {
                units = []
            }
            do {
                branches = scopedBranches(try await PPLivePetInventoryService.listBranches())
            } catch {
                branches = []
            }
            if canViewReservations {
                do {
                    reservations = try await PPLivePetInventoryService.listReservations(productID: item.accessoryID)
                } catch {
                    reservations = []
                    errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
                }
            } else {
                reservations = []
            }
        } catch {
            errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
        }
        isLoading = false
    }

    private func scopedBranches(_ options: [PPInventoryBranchOption]) -> [PPInventoryBranchOption] {
        // Owner/super-admin staff are globally authorized by the same Infra
        // predicate that protects branch transfers. Do not accidentally hide
        // destinations from them when an older staff document has no explicit
        // `scope.global` flag.
        guard let staff, !staff.isAdmin(), !staff.hasGlobalScope() else { return options }
        guard let scope = staff.scope as? [String: Any],
              let branchIDs = scope["branchIds"] as? [String] else { return [] }
        let allowed = Set(
            branchIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return options.filter { allowed.contains($0.id) }
    }

    func perform(_ work: () async throws -> Void, successKey: String, successFallback: String) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        errorMessage = nil
        successMessage = nil
        do {
            try await work()
            await load()
            successMessage = Language.get(successKey, alter: successFallback)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isMutating = false
            return true
        } catch {
            errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isMutating = false
            return false
        }
    }

    func migrate(mode: PPLivePetInventoryMode, units: [PPLivePetUnitDraft], standardSellingPrice: Double) async -> Bool {
        await perform({
            let unitPayloads = try self.validatedUnitPayloads(units, allowEmpty: true)
            var payload: [String: Any] = [
                "inventoryMode": mode.rawValue,
                "units": mode == .individual ? unitPayloads : [],
            ]
            if mode == .individual { payload["standardSellingPrice"] = standardSellingPrice }
            _ = try await PPLivePetInventoryService.callInventory(
                action: "migrate_inventory",
                productID: self.item.accessoryID,
                commandID: PPLivePetInventoryService.commandID("inventory-migration"),
                payload: payload
            )
            self.item.inventoryMode = mode.rawValue
            self.item.inventorySchemaVersion = 2
        }, successKey: "LivePet_Migration_Success", successFallback: "تم اعتماد نمط تتبع المخزون الحي.")
    }

    func intake(mode: PPLivePetInventoryMode, unit: PPLivePetUnitDraft, quantity: Int, cost: Double, supplier: String, notes: String) async -> Bool {
        await perform({
            var payload: [String: Any] = [
                "quantity": max(1, quantity),
                "costPrice": max(0, cost),
                "supplier": supplier,
                "arrivalDate": ISO8601DateFormatter().string(from: unit.acquisitionDate),
                "notes": notes,
            ]
            if mode == .individual { payload["units"] = try self.validatedUnitPayloads([unit]) }
            _ = try await PPLivePetInventoryService.callInventory(
                action: "intake",
                productID: self.item.accessoryID,
                commandID: PPLivePetInventoryService.commandID("stock-intake"),
                payload: payload
            )
        }, successKey: "LivePet_Intake_Success", successFallback: "تمت إضافة المخزون وتأكيد سجل الحركة.")
    }

    func reserve(unit: PPLivePetInventoryUnit, customerName: String, phone: String, branchID: String, validUntil: Date) async -> Bool {
        await perform({
            let customer = try await PPLivePetInventoryService.createOrMatchCustomer(
                name: customerName,
                phone: phone,
                branchID: branchID
            )
            try await PPLivePetInventoryService.createReservation(
                productID: self.item.accessoryID,
                unit: unit,
                customer: customer,
                branchID: branchID,
                validUntil: validUntil
            )
        }, successKey: "LivePet_Reservation_Success", successFallback: "تم حجز الحيوان وربطه بالعميل ونقطة البيع.")
    }

    func complete(reservation: PPLivePetReservation, cashReceived: Double) async -> Bool {
        await perform({
            try await PPLivePetInventoryService.completeReservation(reservation, cashReceived: cashReceived)
        }, successKey: "LivePet_Reservation_Complete_Success", successFallback: "اكتمل البيع وتم تحويل الحيوان إلى حالة مباع.")
    }

    func cancel(reservation: PPLivePetReservation) async -> Bool {
        await perform({
            try await PPLivePetInventoryService.cancelReservation(reservation)
        }, successKey: "LivePet_Reservation_Release_Success", successFallback: "تم تحرير الحجز وإعادة الحيوان إلى المتاح.")
    }

    func transfer(unit: PPLivePetInventoryUnit, sourceBranchID: String, destinationBranchID: String, reason: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "transfer_units_branch",
                productID: self.item.accessoryID,
                commandID: PPLivePetInventoryService.commandID("branch-transfer"),
                payload: [
                    "unitIds": [unit.id],
                    "expectedSourceBranchId": sourceBranchID,
                    "destinationBranchId": destinationBranchID,
                    "reason": reason,
                ]
            )
        }, successKey: "LivePet_Transfer_Success", successFallback: "تم نقل عهدة الحيوان إلى الفرع المحدد.")
    }

    func lifecycle(action: String, unit: PPLivePetInventoryUnit, reason: String, causeCode: String = "UNKNOWN", notes: String = "", veterinaryReference: String = "", observedDeathAt: Date? = nil) async -> Bool {
        await perform({
            var payload: [String: Any] = ["unitId": unit.id, "reason": reason]
            if action == "record_mortality" {
                payload["causeCode"] = causeCode
                payload["notes"] = notes
                payload["veterinaryReference"] = veterinaryReference
                payload["attachmentURLs"] = []
                if let observedDeathAt { payload["observedDeathAt"] = ISO8601DateFormatter().string(from: observedDeathAt) }
            }
            _ = try await PPLivePetInventoryService.callInventory(
                action: action,
                productID: self.item.accessoryID,
                commandID: PPLivePetInventoryService.commandID(action),
                payload: payload
            )
        }, successKey: "LivePet_Lifecycle_Success", successFallback: "تم تحديث حالة الحيوان وتسجيل الحركة في سجل التدقيق.")
    }

    func remove(unit: PPLivePetInventoryUnit, reason: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "remove_unit",
                productID: self.item.accessoryID,
                commandID: PPLivePetInventoryService.commandID("remove-unit"),
                payload: ["unitId": unit.id, "reason": reason]
            )
        }, successKey: "LivePet_Remove_Success", successFallback: "تمت إزالة السجل المتاح من المخزون مع حفظ الأثر التشغيلي.")
    }

    func updatePrice(unit: PPLivePetInventoryUnit, price: Double) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "update_unit_selling_price",
                productID: self.item.accessoryID,
                commandID: PPLivePetInventoryService.commandID("unit-price"),
                payload: ["unitId": unit.id, "sellingPrice": price]
            )
        }, successKey: "LivePet_Price_Success", successFallback: "تم تحديث سعر بيع الحيوان.")
    }

    func adjustGroup(targetQuantity: Int, reason: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "adjust",
                productID: self.item.accessoryID,
                payload: [
                    "adjustmentType": "manual",
                    "targetQuantity": max(0, targetQuantity),
                    "reason": reason,
                ]
            )
        }, successKey: "LivePet_Group_Adjust_Success", successFallback: "تم تحديث كمية المجموعة وتسجيل سبب التعديل.")
    }

    func archive(_ archived: Bool, reason: String) async -> Bool {
        await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "archive",
                productID: self.item.accessoryID,
                payload: ["archived": archived, "reason": reason]
            )
            self.item.isArchived = archived
        }, successKey: archived ? "LivePet_Archive_Success" : "LivePet_Restore_Success", successFallback: archived ? "تمت أرشفة سجل الكتالوج." : "تمت استعادة سجل الكتالوج.")
    }

    private func validatedUnitPayloads(_ drafts: [PPLivePetUnitDraft], allowEmpty: Bool = false) throws -> [[String: Any]] {
        let ringKeys = drafts.map {
            $0.ringTag.precomposedStringWithCompatibilityMapping
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
        }
        guard (allowEmpty || !drafts.isEmpty),
              !ringKeys.contains(where: { $0.isEmpty || $0.count > 80 }),
              Set(ringKeys).count == ringKeys.count else {
            throw PPLivePetOperationValidationError.invalidRing
        }
        return try drafts.map { draft in
            let sellingText = draft.sellingPriceText.replacingOccurrences(of: ",", with: ".")
            guard let price = Double(sellingText), price > 0, price <= 999_999_999.99,
                  abs(price * 100 - (price * 100).rounded()) < 0.000_001 else {
                throw PPLivePetOperationValidationError.invalidPrice
            }
            let purchaseCost = Double(draft.purchaseCostText.replacingOccurrences(of: ",", with: "."))
            if canViewCosts {
                let cleanCost = draft.purchaseCostText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanCost.isEmpty,
                      let purchaseCost,
                      purchaseCost >= 0,
                      purchaseCost <= 999_999_999.99,
                      abs(purchaseCost * 100 - (purchaseCost * 100).rounded()) < 0.000_001 else {
                    throw PPLivePetOperationValidationError.invalidCost
                }
            }
            return [
                "draftUnitId": draft.id,
                "ringTag": draft.ringTag.trimmingCharacters(in: .whitespacesAndNewlines),
                "acquisitionDate": ISO8601DateFormatter().string(from: draft.acquisitionDate),
                "purchaseCost": purchaseCost ?? NSNull(),
                "sellingPrice": price,
                "supplier": draft.supplier.trimmingCharacters(in: .whitespacesAndNewlines),
                "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                "mediaURLs": [],
            ]
        }
    }
}

private enum PPLivePetOperationValidationError: LocalizedError {
    case invalidRing
    case invalidPrice
    case invalidCost

    var errorDescription: String? {
        switch self {
        case .invalidRing:
            return Language.get("LivePet_Validation_RingRequired", alter: "أدخل رقم حلقة أو شريحة صالحاً وغير مكرر لكل حيوان.")
        case .invalidPrice:
            return Language.get("LivePet_Validation_UnitPrice", alter: "حدد سعر بيع صالحاً لكل حيوان وبحد أقصى منزلتين عشريتين.")
        case .invalidCost:
            return Language.get("LivePet_Validation_UnitCost", alter: "أدخل تكلفة استلام صالحة لكل حيوان وبحد أقصى منزلتين عشريتين.")
        }
    }
}

private struct PPLivePetMortalityCause: Identifiable {
    let code: String
    let title: String

    var id: String { code }
}

// MARK: - Inventory Filter Enum

private enum InventoryFilter: Int, CaseIterable, Identifiable {
    case all = 0
    case inStock
    case lowStock
    case outOfStock
    case hasOffer
    case conditionNew
    case conditionUsed

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "All"
        case .inStock: return "InStock"
        case .lowStock: return "LowStock"
        case .outOfStock: return "OutOfStock"
        case .hasOffer: return "Offers"
        case .conditionNew: return "New"
        case .conditionUsed: return "Used"
        }
    }

    var defaultTitle: String {
        switch self {
        case .all: return Language.get("All", alter: "الكل")
        case .inStock: return Language.get("InStock", alter: "متوفر")
        case .lowStock: return Language.get("LowStock", alter: "مخزون منخفض")
        case .outOfStock: return Language.get("OutOfStock", alter: "نفذ من المخزون")
        case .hasOffer: return Language.get("Offers", alter: "العروض والتخفيضات")
        case .conditionNew: return Language.get("Condition_New", alter: "جديد")
        case .conditionUsed: return Language.get("Condition_Used", alter: "مستعمل")
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .inStock: return "checkmark.circle.fill"
        case .lowStock: return "exclamationmark.triangle.fill"
        case .outOfStock: return "xmark.octagon.fill"
        case .hasOffer: return "tag.fill"
        case .conditionNew: return "sparkles"
        case .conditionUsed: return "arrow.3.trianglepath"
        }
    }
}

// MARK: - Inventory Horizon Tabs

enum CatalogHorizonTab: Int, CaseIterable, Identifiable {
    case accessories = 0
    case food
    case livePets

    var id: Int { rawValue }

    var kind: AccessKindType {
        switch self {
        case .accessories: return .typeAccessory
        case .food: return .typeFood
        case .livePets: return .typeLivePets
        }
    }

    var title: String {
        switch self {
        case .accessories: return Language.get("Manage Accessories", alter: "إكسسوارات ومستلزمات")
        case .food: return Language.get("manageFood", alter: "أغذية ومكملات")
        case .livePets: return Language.get("Manage Live Pets", alter: "حيوانات أليفة حية")
        }
    }

    var shortTitle: String {
        switch self {
        case .accessories: return Language.get("Accessories", alter: "إكسسوارات")
        case .food: return Language.get("Food", alter: "أغذية")
        case .livePets: return Language.get("LivePets", alter: "حيوانات حية")
        }
    }

    var icon: String {
        switch self {
        case .accessories: return "bag.fill"
        case .food: return "fork.knife"
        case .livePets: return "pawprint.fill"
        }
    }
}

// MARK: - Inventory List View Model

@MainActor
final class PPInventoryListViewModel: ObservableObject {
    @Published private(set) var allItems: [PetAccessory] = []
    @Published private(set) var filteredItems: [PetAccessory] = []
    @Published var searchText: String = ""
    @Published fileprivate var activeFilter: InventoryFilter = .all
    @Published var activeTab: CatalogHorizonTab
    @Published private(set) var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var selectedItemForDossier: PetAccessory? = nil

    private var listener: AnyObject?
    private var pendingQuantityDeltas: [String: Int] = [:]
    private var pendingDebounceWorkItems: [String: DispatchWorkItem] = [:]

    var totalCount: Int { allItems.count }
    var inStockCount: Int { allItems.filter { $0.quantity > 0 && !$0.noStock }.count }
    var lowStockCount: Int { allItems.filter { $0.quantity > 0 && $0.quantity <= 3 && !$0.noStock }.count }
    var outOfStockCount: Int { allItems.filter { $0.quantity <= 0 || $0.noStock }.count }
    var offersCount: Int {
        allItems.filter {
            $0.hasOffer || ($0.discountPercent?.doubleValue ?? 0) > 0 || ($0.discountAmount?.doubleValue ?? 0) > 0
        }.count
    }
    var unpricedItemsCount: Int {
        allItems.filter { !$0.hasResolvedSellingPrice }.count
    }
    var totalValuation: Double {
        allItems.reduce(0.0) { sum, item in
            guard item.hasResolvedSellingPrice else { return sum }
            return sum + (item.finalPrice.doubleValue * Double(max(0, item.quantity)))
        }
    }

    init(kind: AccessKindType = .typeAccessory) {
        switch kind {
        case .typeFood:
            self.activeTab = .food
        case .typeLivePets:
            self.activeTab = .livePets
        default:
            self.activeTab = .accessories
        }
    }

    var currentKind: AccessKindType {
        activeTab.kind
    }

    var navigationTitle: String {
        activeTab.title
    }

    func switchTab(to tab: CatalogHorizonTab) {
        guard tab != activeTab else { return }
        activeTab = tab
        stopListening()
        startListening()
    }

    func startListening() {
        isLoading = true
        errorMessage = nil
        listener = AccessoryManager.shared().observeAccessories(of: currentKind) { [weak self] items, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.allItems = items ?? []
                self.applyFilter()
            }
        }
    }

    func stopListening() {
        if let reg = listener as? AnyObject {
            _ = reg.perform(Selector(("remove")))
        }
        listener = nil
        for workItem in pendingDebounceWorkItems.values {
            workItem.cancel()
        }
        pendingDebounceWorkItems.removeAll()
        pendingQuantityDeltas.removeAll()
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = allItems.filter { item in
            switch activeFilter {
            case .all:
                break
            case .inStock:
                if item.quantity <= 0 || item.noStock { return false }
            case .lowStock:
                if item.quantity <= 0 || item.quantity > 3 || item.noStock { return false }
            case .outOfStock:
                if item.quantity > 0 && !item.noStock { return false }
            case .hasOffer:
                let hasDiscount = (itemDiscountValue(item) > 0) || item.hasOffer
                if !hasDiscount { return false }
            case .conditionNew:
                if item.condition != .new { return false }
            case .conditionUsed:
                if item.condition != .used { return false }
            }

            guard !query.isEmpty else { return true }
            let name = item.name.lowercased()
            let desc = item.desc.lowercased()
            let searchTitle = item.searchTitle.lowercased()
            let store = (item.storeName ?? "").lowercased()
            let docID = item.accessoryID.lowercased()
            return name.contains(query) || desc.contains(query) || searchTitle.contains(query) || store.contains(query) || docID.contains(query)
        }

        result.sort { a, b in
            // In-stock items first, then alphabetical
            if a.noStock != b.noStock {
                return !a.noStock && b.noStock
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        filteredItems = result
    }

    private func itemDiscountValue(_ item: PetAccessory) -> Double {
        let percent = item.discountPercent?.doubleValue ?? 0
        let amount = item.discountAmount?.doubleValue ?? 0
        return max(percent, amount)
    }

    func refresh() async {
        await withCheckedContinuation { continuation in
            AccessoryManager.shared().fetchAccessories(of: currentKind) { [weak self] items, _ in
                DispatchQueue.main.async {
                    self?.allItems = items ?? []
                    self?.applyFilter()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Quantity Adjustment with Real-time Debounce

    func adjustQuantity(by delta: Int, for item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }

        if item.isLivePet {
            errorMessage = Language.get(
                "LivePet_Exact_Quantity_Derived",
                alter: "يُدار مخزون الحيوانات الحية من تفاصيل الصنف حتى تُسجل الهوية أو الكمية والسبب بأمان."
            )
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        // Local optimistic update
        item.quantity = max(0, item.quantity + delta)
        item.noStock = (item.quantity <= 0)
        objectWillChange.send()
        applyFilter()

        // Batch delta
        let currentPending = pendingQuantityDeltas[docID] ?? 0
        let newPending = currentPending + delta
        pendingQuantityDeltas[docID] = newPending

        // Cancel existing debounce timer for this item
        pendingDebounceWorkItems[docID]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let batchedDelta = self.pendingQuantityDeltas[docID], batchedDelta != 0 else { return }
            self.pendingQuantityDeltas.removeValue(forKey: docID)
            self.pendingDebounceWorkItems.removeValue(forKey: docID)

            AccessoryManager.shared().adjustQuantity(by: batchedDelta, forAccessoryID: docID) { error in
                if let error = error {
                    PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
                }
            }
        }

        pendingDebounceWorkItems[docID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    // MARK: - Quick Out of Stock Toggle

    func toggleStockAvailability(for item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }
        if item.isLivePet {
            errorMessage = Language.get(
                "LivePet_Availability_ServerOwned",
                alter: "توفر الحيوان يتغير من خلال البيع أو الحجر أو النقل أو الوفاة، وليس من مفتاح يدوي."
            )
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let newNoStock = !item.noStock
        item.noStock = newNoStock
        if newNoStock {
            item.quantity = 0
        } else if item.quantity == 0 {
            item.quantity = 1
        }
        objectWillChange.send()
        applyFilter()

        AccessoryManager.shared().setNoStock(item.noStock, forAccessoryID: docID) { _ in }
        AccessoryManager.shared().updateQuantity(item.quantity, forAccessoryID: docID) { error in
            if let error = error {
                PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
            }
        }
    }

    // MARK: - Delete & Status Operations

    func deleteAccessory(_ item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }
        PPHUD.showIndeterminate(in: nil, title: Language.get("Deleting", alter: "جاري الحذف..."), subtitle: nil)
        if item.isLivePet {
            Task { @MainActor in
                do {
                    _ = try await PPLivePetInventoryService.callInventory(
                        action: "delete",
                        productID: docID,
                        payload: ["reason": "admin_ios_soft_delete"]
                    )
                    PPHUD.dismiss()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    PPHUD.showSuccess(
                        Language.get("Deleted", alter: "تم الحذف بنجاح"),
                        subtitle: Language.get("StockUpdated", alter: "تم تحديث المخزون")
                    )
                } catch {
                    PPHUD.dismiss()
                    PPHUD.showError(
                        Language.get("Error", alter: "خطأ"),
                        subtitle: PPLivePetInventoryService.localizedMessage(for: error)
                    )
                }
            }
            return
        }
        AccessoryManager.shared().deleteAccessory(withID: docID) { error in
            PPHUD.dismiss()
            if let error = error {
                PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
            } else {
                DispatchQueue.main.async {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                PPHUD.showSuccess(Language.get("Deleted", alter: "تم الحذف بنجاح"), subtitle: Language.get("StockUpdated", alter: "تم تحديث المخزون"))
            }
        }
    }

    func toggleActive(_ item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }
        let newActive = !item.active
        AccessoryManager.shared().setActive(newActive, forAccessoryID: docID) { error in
            if let error = error {
                PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
            }
        }
    }
}

// MARK: - Reimagined Flagship Inventory Screen

@MainActor
public struct PPInventoryListView: View {
    @StateObject private var viewModel: PPInventoryListViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onPushViewController: (UIViewController) -> Void
    private let onDismiss: (() -> Void)?

    @State private var itemToDelete: PetAccessory?
    @State private var showDeleteConfirmation = false
    @State private var spinAngle: Double = 0
    @FocusState private var isSearchFocused: Bool

    public init(
        kind: AccessKindType = .typeAccessory,
        onPushViewController: @escaping (UIViewController) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PPInventoryListViewModel(kind: kind))
        self.onPushViewController = onPushViewController
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sovereignHeaderBar
                catalogHorizonSwitcher

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        apexTelemetryRadar
                        searchAndFilterMatrix

                        if viewModel.isLoading && viewModel.allItems.isEmpty {
                            loadingSkeletonView
                        } else if viewModel.filteredItems.isEmpty {
                            emptyStateView
                        } else {
                            itemsListSection
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 64)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $viewModel.selectedItemForDossier) { item in
            PPInventoryItemDossierSheet(
                item: item,
                viewModel: viewModel,
                onOpenFullEditor: {
                    let editVC = AddAccessoryViewController(accessory: item)
                    editVC.showTypeRow = false
                    editVC.defaultKind = viewModel.currentKind
                    onPushViewController(editVC)
                },
                onOpenPOS: {
                    if let controller = PPAdminRouteFactory.viewController(routeIdentifier: "pos", payload: item.accessoryID) {
                        onPushViewController(controller)
                    }
                }
            )
        }
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onChange(of: viewModel.searchText) { _ in
            viewModel.applyFilter()
        }
        .onChange(of: viewModel.activeFilter) { _ in
            viewModel.applyFilter()
        }
        .confirmationDialog(
            Language.get("Confirm Delete", alter: "تأكيد حذف المنتج"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(Language.get("Delete", alter: "حذف نهائي من المخزون"), role: .destructive) {
                if let item = itemToDelete {
                    viewModel.deleteAccessory(item)
                }
                itemToDelete = nil
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text(Language.get("Are you sure you want to delete this accessory?", alter: "هل أنت متأكد من رغبتك في حذف هذا المنتج نهائياً من قاعدة بيانات المخزون؟"))
        }
    }

    // MARK: - Sovereign Header Bar

    private var sovereignHeaderBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let onDismiss = onDismiss {
                        onDismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                            .font(.system(size: 15, weight: .bold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AdminSurface.control, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                    )
                }
                .buttonStyle(CatalogPressStyle())

                Spacer()

                // Add (+) Button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let addVC = AddAccessoryViewController(accessory: nil)
                    addVC.showTypeRow = false
                    addVC.defaultKind = viewModel.currentKind
                    onPushViewController(addVC)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Add", alter: "إضافة منتج"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityLabel(Language.get("Add", alter: "إضافة"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("CommandCenter_Work_Workspace", alter: "مساحة المخزون") + " / " + viewModel.navigationTitle)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminCommandInk.secondary)

                HStack {
                    Text(viewModel.navigationTitle)
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)

                    Spacer()

                    Text(String(format: Language.get("Total_Items_Format", alter: "%d صنف مسجل"), viewModel.totalCount))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }
            }
            .padding(.top, 2)

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.startListening() }
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Catalog Horizon Switcher (Tabs)

    private var catalogHorizonSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(CatalogHorizonTab.allCases) { tab in
                let isSelected = viewModel.activeTab == tab
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        viewModel.switchTab(to: tab)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        Text(tab.shortTitle)
                            .font(isSelected ? AdminType.captionBold : AdminType.caption1)
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        isSelected
                            ? AnyView(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AdminSurface.primary)
                                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 2)
                            )
                            : AnyView(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AdminSurface.control)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.4),
                                lineWidth: 0.75
                            )
                    )
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 6)
    }

    // MARK: - Apex Live Telemetry Radar

    private var apexTelemetryRadar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 8, height: 8)
                            .shadow(color: Color(uiColor: .ppSuccess).opacity(0.8), radius: 4, x: 0, y: 0)
                        Text(Language.get("Inventory_Live_Radar", alter: "رصد المخزون الحي • مزامنة لحظية"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                    }

                    Text(viewModel.activeTab.title)
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)

                    if viewModel.totalValuation > 0 {
                        Text(String(format: Language.get("Inventory_Valuation_Format", alter: "القيمة الإجمالية للمخزون: %.2f ر.ق"), viewModel.totalValuation))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminCommandInk.secondary)
                    }

                    if viewModel.unpricedItemsCount > 0 {
                        Label {
                            Text(
                                String(
                                    format: Language.get(
                                        "Inventory_Unpriced_Items_Format",
                                        alter: "لم يُحدَّد سعر البيع لعدد %ld من الأصناف. لا تشملها قيمة المخزون."
                                    ),
                                    viewModel.unpricedItemsCount
                                )
                            )
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(AdminType.caption2)
                        .foregroundStyle(Color(uiColor: .ppWarning))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.6)) {
                        spinAngle += 360
                    }
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                            .rotationEffect(.degrees(spinAngle))
                    }
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            }

            // 4-Tile Telemetry Deck
            HStack(spacing: 8) {
                telemetryTile(
                    title: Language.get("InStock", alter: "متوفر"),
                    count: viewModel.inStockCount,
                    color: Color(uiColor: .ppSuccess),
                    icon: "checkmark.circle.fill"
                )
                telemetryTile(
                    title: Language.get("LowStock", alter: "مخزون حرج"),
                    count: viewModel.lowStockCount,
                    color: Color(uiColor: .ppWarning),
                    icon: "exclamationmark.triangle.fill"
                )
                telemetryTile(
                    title: Language.get("OutOfStock", alter: "نفذ"),
                    count: viewModel.outOfStockCount,
                    color: Color(uiColor: .ppError),
                    icon: "xmark.octagon.fill"
                )
                telemetryTile(
                    title: Language.get("Offers", alter: "تخفيضات"),
                    count: viewModel.offersCount,
                    color: Color(red: 0.65, green: 0.35, blue: 0.95),
                    icon: "tag.fill"
                )
            }

            // Proportional Health Spectrum
            if !viewModel.allItems.isEmpty {
                stockHealthSpectrum
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.60), lineWidth: 0.75)
        )
    }

    private func telemetryTile(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 0.75)
        )
    }

    private var stockHealthSpectrum: some View {
        let total = max(1, viewModel.totalCount)
        let inStockFrac = CGFloat(viewModel.inStockCount) / CGFloat(total)
        let lowStockFrac = CGFloat(viewModel.lowStockCount) / CGFloat(total)
        let outStockFrac = CGFloat(viewModel.outOfStockCount) / CGFloat(total)

        return VStack(spacing: 4) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if inStockFrac > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: max(4, proxy.size.width * inStockFrac))
                    }
                    if lowStockFrac > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(uiColor: .ppWarning))
                            .frame(width: max(4, proxy.size.width * lowStockFrac))
                    }
                    if outStockFrac > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(uiColor: .ppError))
                            .frame(width: max(4, proxy.size.width * outStockFrac))
                    }
                }
            }
            .frame(height: 5)
            .clipShape(Capsule())
            .background(AdminSurface.control, in: Capsule())

            HStack {
                Text(String(format: Language.get("Inventory_Available_Ratio", alter: "نسبة التوفر: %.0f%%"), (CGFloat(viewModel.inStockCount) / CGFloat(total)) * 100.0))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.tertiary)
                Spacer()
                Text(String(format: Language.get("Inventory_Showing_Count", alter: "%d معروض"), viewModel.filteredItems.count))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Search & Filter Matrix

    private var searchAndFilterMatrix: some View {
        VStack(spacing: 10) {
            // Liquid Search Field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminCommandInk.secondary)

                TextField(
                    Language.get("Inventory_Search_Placeholder", alter: "ابحث بالاسم، الباركود، المتجر، أو المعرّف..."),
                    text: $viewModel.searchText
                )
                .font(AdminType.callout)
                .foregroundStyle(AdminSurface.primaryText)
                .focused($isSearchFocused)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AdminCommandInk.tertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSearchFocused ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.6),
                        lineWidth: isSearchFocused ? 1.5 : 0.75
                    )
            )

            // Horizontal Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(InventoryFilter.allCases) { filter in
                        let isSelected = viewModel.activeFilter == filter
                        let count: Int = {
                            switch filter {
                            case .all: return viewModel.totalCount
                            case .inStock: return viewModel.inStockCount
                            case .lowStock: return viewModel.lowStockCount
                            case .outOfStock: return viewModel.outOfStockCount
                            case .hasOffer: return viewModel.offersCount
                            case .conditionNew: return viewModel.allItems.filter { $0.condition == .new }.count
                            case .conditionUsed: return viewModel.allItems.filter { $0.condition == .used }.count
                            }
                        }()

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewModel.activeFilter = filter
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: filter.iconName)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                Text(filter.defaultTitle)
                                    .font(isSelected ? AdminType.captionBold : AdminType.caption1)

                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        isSelected
                                            ? Color.white.opacity(0.25)
                                            : AdminSurface.primary.opacity(0.12),
                                        in: Capsule(style: .continuous)
                                    )
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? AnyView(Capsule(style: .continuous).fill(AdminSurface.primary))
                                    : AnyView(Capsule(style: .continuous).fill(AdminSurface.control))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.5),
                                        lineWidth: 0.75
                                    )
                            )
                        }
                        .buttonStyle(CatalogPressStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Items List Section

    private var itemsListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.filteredItems, id: \.accessoryID) { item in
                FlagshipInventoryCard(
                    item: item,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectedItemForDossier = item
                    },
                    onEdit: {
                        let editVC = AddAccessoryViewController(accessory: item)
                        editVC.showTypeRow = false
                        editVC.defaultKind = viewModel.currentKind
                        onPushViewController(editVC)
                    },
                    onAdjustQuantity: { delta in
                        viewModel.adjustQuantity(by: delta, for: item)
                    },
                    onToggleStock: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.toggleStockAvailability(for: item)
                    },
                    onDelete: {
                        itemToDelete = item
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.10))
                    .frame(width: 64, height: 64)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .padding(.top, 24)

            Text(Language.get("No Accessories Found", alter: "لا توجد أصناف مطابقة"))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            Text(Language.get("Tap + to add your first accessory.", alter: "جرب تغيير كلمات البحث أو تصفية الحالة، أو اضغط + لإضافة صنف جديد."))
                .font(AdminType.caption1)
                .foregroundColor(AdminCommandInk.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 10) {
                if !viewModel.searchText.isEmpty || viewModel.activeFilter != .all {
                    Button {
                        viewModel.searchText = ""
                        viewModel.activeFilter = .all
                    } label: {
                        Text(Language.get("ResetFilters", alter: "إعادة ضبط الفلاتر"))
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                    }
                }

                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let addVC = AddAccessoryViewController(accessory: nil)
                    addVC.showTypeRow = false
                    addVC.defaultKind = viewModel.currentKind
                    onPushViewController(addVC)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text(Language.get("Add", alter: "إضافة صنف جديد"))
                    }
                    .font(AdminType.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary, in: Capsule(style: .continuous))
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
        )
    }

    // MARK: - Loading Skeleton

    private var loadingSkeletonView: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdminSurface.control)
                            .frame(width: 160, height: 16)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdminSurface.control)
                            .frame(width: 100, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdminSurface.control)
                            .frame(width: 120, height: 14)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AdminSurface.surface)
                )
            }
        }
    }
}

// MARK: - Flagship Category-Defining Inventory Card

private struct FlagshipInventoryCard: View {
    let item: PetAccessory
    let onTap: () -> Void
    let onEdit: () -> Void
    let onAdjustQuantity: (Int) -> Void
    let onToggleStock: () -> Void
    let onDelete: () -> Void

    private var imageURL: URL? {
        PetAccessory.firstImageURL(for: item)
    }

    private var hasDiscount: Bool {
        let percent = item.discountPercent?.doubleValue ?? 0
        let amount = item.discountAmount?.doubleValue ?? 0
        return percent > 0 || amount > 0 || item.hasOffer
    }

    private var finalPriceFormatted: String {
        item.inventoryDisplayPrice
    }

    private var originalPriceFormatted: String? {
        guard item.hasResolvedSellingPrice,
              hasDiscount,
              item.price.doubleValue > item.finalPrice.doubleValue else {
            return nil
        }
        return PetAccessory.formatCurrency(item.price)
    }

    private var stockTone: Color {
        if item.quantity <= 0 || item.noStock {
            return Color(uiColor: .ppError)
        } else if item.quantity <= 3 {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppSuccess)
        }
    }

    private var stockText: String {
        if item.quantity <= 0 || item.noStock {
            return Language.get("OutOfStock", alter: "نفذ من المخزون")
        } else if item.quantity <= 3 {
            return String(format: Language.get("LowStock_Qty_Format", alter: "مخزون منخفض (%d)"), item.quantity)
        } else {
            return String(format: Language.get("InStock_Qty_Format", alter: "متوفر (%d)"), item.quantity)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Top Row: Image Thumbnail + Details + Stock Beacon
                HStack(alignment: .top, spacing: 14) {
                    // Visual Specimen Thumbnail
                    ZStack(alignment: .topLeading) {
                        productThumbnail
                            .frame(width: 82, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                            )

                        if hasDiscount, let percent = item.discountPercent, percent.intValue > 0 {
                            Text("-\(percent.intValue)%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .ppError), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(5)
                        }
                    }

                    // Metadata Runway
                    VStack(alignment: .leading, spacing: 4) {
                        // Chips Row: Condition + Store
                        HStack(spacing: 6) {
                            if let store = item.storeName, !store.isEmpty {
                                Text(store)
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                            }

                            let condText = PetAccessory.conditionText(for: item)
                            if !condText.isEmpty {
                                Text(condText)
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminCommandInk.secondary)
                            }

                            Spacer(minLength: 4)

                            // Stock Capsule
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(stockTone)
                                    .frame(width: 6, height: 6)
                                Text(stockText)
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(stockTone)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(stockTone.opacity(0.10), in: Capsule(style: .continuous))
                        }

                        // Product Title
                        Text(item.name)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        // Micro Detail (Weight or Expiry if present)
                        if let weight = item.weightText, !weight.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "scalemass.fill")
                                    .font(.system(size: 9))
                                Text(weight)
                                    .font(AdminType.caption2)
                            }
                            .foregroundStyle(AdminCommandInk.tertiary)
                        }
                    }
                }

                Divider()
                    .background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))

                // Bottom Flight Deck: Price + Stepper + Quick Stock Pill
                HStack(alignment: .center, spacing: 10) {
                    // Financial Readout
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(finalPriceFormatted)
                                .font(AdminType.title3)
                                .foregroundColor(item.hasResolvedSellingPrice ? AdminSurface.primary : Color(uiColor: .ppWarning))
                                .monospacedDigit()

                            if let original = originalPriceFormatted {
                                Text(original)
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminCommandInk.tertiary)
                                    .strikethrough()
                            }
                        }
                    }

                    Spacer()

                    if item.isLivePet {
                        Label(Language.get("LivePet_Manage_Units", alter: "إدارة الحيوانات"), systemImage: "pawprint.fill")
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                    } else {
                        if !item.isLivePet {
                            // Quick Out-of-Stock / Stock Toggle
                            Button {
                                onToggleStock()
                            } label: {
                                Image(systemName: item.noStock ? "bolt.slash.fill" : "bolt.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        (item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(CatalogPressStyle())
                            .accessibilityLabel(item.noStock ? Language.get("MarkInStock", alter: "تفعيل المخزون") : Language.get("MarkOutOfStock", alter: "تعطيل المخزون"))
                        }

                        // Quantity-tracked inventory remains adjustable from the card.
                        stepperControl
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AdminSurface.surface)
                    .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
            )
        }
        .buttonStyle(CatalogPressStyle())
        .contextMenu {
            Button(action: onEdit) {
                Label(Language.get("Edit", alter: "تعديل الصنف"), systemImage: "pencil")
            }

            Button(action: {
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    PetAccessory.share(item, from: root)
                }
            }) {
                Label(Language.get("Share", alter: "مشاركة الصنف"), systemImage: "square.and.arrow.up")
            }

            if !item.isLivePet {
                Button(action: onToggleStock) {
                    Label(
                        item.noStock ? Language.get("MarkInStock", alter: "تفعيل التوفر بالمخزون") : Language.get("MarkOutOfStock", alter: "تعيين كنفاذ المخزون"),
                        systemImage: item.noStock ? "checkmark.circle" : "xmark.circle"
                    )
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label(Language.get("Delete", alter: "حذف من المخزون"), systemImage: "trash")
            }
        }
    }

    // MARK: - Quantity Stepper

    private var stepperControl: some View {
        HStack(spacing: 2) {
            // Decrement (-)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(item.quantity > 0 ? AdminSurface.primaryText : AdminCommandInk.tertiary)
                    .frame(width: 32, height: 32)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(CatalogPressStyle())
            .disabled(item.quantity <= 0)

            // Value Display
            Text("\(item.quantity)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AdminSurface.primaryText)
                .frame(minWidth: 32)
                .multilineTextAlignment(.center)

            // Increment (+)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 32, height: 32)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(CatalogPressStyle())
        }
        .padding(3)
        .background(AdminSurface.control.opacity(0.60), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
        )
    }

    // MARK: - Product Thumbnail

    @ViewBuilder
    private var productThumbnail: some View {
        if let imageURL = imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderThumbnail
                case .empty:
                    ZStack {
                        AdminSurface.control
                        ProgressView()
                            .tint(AdminSurface.primary)
                    }
                @unknown default:
                    placeholderThumbnail
                }
            }
        } else {
            placeholderThumbnail
        }
    }

    private var placeholderThumbnail: some View {
        ZStack {
            AdminSurface.control
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 24))
                .foregroundColor(AdminCommandInk.tertiary)
        }
    }
}

// MARK: - Flagship Item Quick Dossier Sheet

private struct PPInventoryItemDossierSheet: View {
    let item: PetAccessory
    @ObservedObject var viewModel: PPInventoryListViewModel
    let onOpenFullEditor: () -> Void
    let onOpenPOS: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var liveModel: PPLivePetOperationsViewModel

    init(
        item: PetAccessory,
        viewModel: PPInventoryListViewModel,
        onOpenFullEditor: @escaping () -> Void,
        onOpenPOS: @escaping () -> Void
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onOpenFullEditor = onOpenFullEditor
        self.onOpenPOS = onOpenPOS
        _liveModel = StateObject(wrappedValue: PPLivePetOperationsViewModel(item: item))
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Hero Image & Title
                        VStack(spacing: 12) {
                            if let firstURL = PetAccessory.firstImageURL(for: item) {
                                AsyncImage(url: firstURL) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 200)
                                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    } else {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(AdminSurface.control)
                                            .frame(height: 180)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(AdminType.title2)
                                    .foregroundStyle(AdminSurface.primaryText)

                                if !item.desc.isEmpty {
                                    Text(item.desc)
                                        .font(AdminType.caption1)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                        // Stock & Price Quick Readout
                        HStack(spacing: 12) {
                            dossierMetricCard(
                                title: Language.get("Price", alter: "السعر الحالي"),
                                value: item.inventoryDisplayPrice,
                                color: item.hasResolvedSellingPrice ? AdminSurface.primary : Color(uiColor: .ppWarning)
                            )
                            dossierMetricCard(
                                title: Language.get("Quantity", alter: "الكمية المتاحة"),
                                value: "\(item.quantity)",
                                color: item.quantity > 0 ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError)
                            )
                        }

                        // Identifiers Matrix
                        VStack(spacing: 10) {
                            dossierRow(title: Language.get("ID", alter: "معرّف الصنف"), value: item.accessoryID)
                            if let store = item.storeName {
                                dossierRow(title: Language.get("Store", alter: "المتجر / الفرع"), value: store)
                            }
                            dossierRow(title: Language.get("Condition", alter: "الحالة"), value: PetAccessory.conditionText(for: item))
                        }
                        .padding(16)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        if item.isLivePet {
                            livePetOperationsSection
                        }

                        // CTAs
                        Button {
                            dismiss()
                            onOpenFullEditor()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 15, weight: .bold))
                                Text(Language.get("EditFullDetails", alter: "فتح محرر البيانات الكامل"))
                                    .font(AdminType.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(AdminSurface.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(CatalogPressStyle())
                    }
                    .padding(16)
                }
            }
            .navigationTitle(Language.get("ItemDetails", alter: "تفاصيل الصنف"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            if item.isLivePet { await liveModel.load() }
        }
        .sheet(item: $liveModel.operation) { operation in
            PPLivePetOperationSheet(context: operation, model: liveModel)
        }
    }

    private var livePetOperationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("LivePet_Operations_Title", alter: "عمليات دورة حياة الحيوان"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("LivePet_Operations_Hint", alter: "كل تغيير يُنفذ من الخادم ويُسجل في حركة المخزون والتدقيق."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                Spacer()
                Button {
                    Task { await liveModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(AdminSurface.control, in: Circle())
                }
                .disabled(liveModel.isLoading || liveModel.isMutating)
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            }

            if let success = liveModel.successMessage {
                Label(success, systemImage: "checkmark.circle.fill")
                    .font(AdminType.caption1)
                    .foregroundStyle(Color(uiColor: .ppSuccess))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = liveModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(AdminType.caption1)
                    .foregroundStyle(Color(uiColor: .ppError))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if liveModel.mode == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        Language.get("LivePet_Legacy_Mode_Title", alter: "يلزم اعتماد نمط التتبع"),
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .font(AdminType.captionBold)
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    Text(Language.get("LivePet_Legacy_Mode_Hint", alter: "هذا سجل قديم. اختر تتبعاً فردياً أو إدارة بالكمية قبل تنفيذ أي حركة جديدة."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        liveModel.operation = .migrate
                    } label: {
                        Label(Language.get("LivePet_Migrate_Action", alter: "اعتماد نمط المخزون"), systemImage: "arrow.triangle.branch")
                            .font(AdminType.captionBold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AdminSurface.primary)
                    .disabled(!liveModel.canManageStock)
                }
                .padding(12)
                .background(Color(uiColor: .ppWarning).opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Button {
                        liveModel.operation = .intake
                    } label: {
                        Label(Language.get("LivePet_Intake_Action", alter: "إضافة مخزون"), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!liveModel.canManageStock)

                    Button {
                        dismiss()
                        onOpenPOS()
                    } label: {
                        Label(Language.get("LivePet_Open_POS", alter: "فتح نقطة البيع"), systemImage: "cart.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AdminSurface.primary)
                    .disabled(!liveModel.canSell)
                }

                Button {
                    liveModel.operation = .archive(!liveModel.item.isArchived)
                } label: {
                    Label(
                        liveModel.item.isArchived
                            ? Language.get("LivePet_Restore_Action", alter: "استعادة سجل الكتالوج")
                            : Language.get("LivePet_Archive_Action", alter: "أرشفة سجل الكتالوج"),
                        systemImage: liveModel.item.isArchived ? "arrow.uturn.backward.circle" : "archivebox"
                    )
                    .font(AdminType.captionBold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!liveModel.canManageStock)
            }

            if liveModel.mode == .quantity {
                Button {
                    liveModel.operation = .groupAdjustment
                } label: {
                    Label(Language.get("LivePet_Group_Adjust_Action", alter: "مطابقة كمية المجموعة"), systemImage: "slider.horizontal.3")
                        .font(AdminType.captionBold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!liveModel.canManageStock)

                Text(Language.get("LivePet_Group_Exact_Action_Hint", alter: "الحجز الفردي والنقل والوفاة لكل حيوان تتطلب نمط التتبع الفردي."))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if liveModel.mode == .individual {
                if liveModel.isLoading && liveModel.units.isEmpty {
                    ProgressView(Language.get("LivePet_Units_Loading", alter: "جارٍ تحميل سجلات الحيوانات..."))
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else if liveModel.units.isEmpty {
                    Text(Language.get("LivePet_Units_Empty", alter: "لا توجد سجلات فردية لهذا الصنف بعد."))
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    VStack(spacing: 8) {
                        ForEach(liveModel.units) { unit in
                            livePetUnitRow(unit)
                        }
                    }
                }
            }

            if liveModel.canViewReservations && !liveModel.reservations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Language.get("LivePet_Reservations_Title", alter: "الحجوزات النشطة"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    ForEach(liveModel.reservations) { reservation in
                        Button {
                            liveModel.operation = .reservation(reservation)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reservation.customerName.isEmpty ? reservation.customerPhone : reservation.customerName)
                                        .font(AdminType.captionBold)
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Text(String(format: Language.get("LivePet_Reservation_Branch_Format", alter: "الفرع: %@"), reservation.branchID))
                                        .font(AdminType.caption2)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                    if let validUntil = reservation.validUntil {
                                        Text(String(format: Language.get("LivePet_Reservation_Until_Format", alter: "الحجز صالح حتى %@"), validUntil.formatted(date: .abbreviated, time: .shortened)))
                                            .font(AdminType.caption2)
                                            .foregroundStyle(validUntil <= Date() ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(PetAccessory.formatCurrency(NSNumber(value: reservation.total)))
                                        .font(AdminType.captionBold)
                                        .foregroundStyle(AdminSurface.primary)
                                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(liveModel.isMutating)
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func livePetUnitRow(_ unit: PPLivePetInventoryUnit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(unit.ringTag.isEmpty ? unit.id : unit.ringTag)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(liveUnitStatus(unit.status))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(liveUnitStatusColor(unit.status))
                    if !unit.currentBranchID.isEmpty {
                        Text(String(format: Language.get("LivePet_Branch_Format", alter: "الفرع: %@"), unit.currentBranchID))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
                Spacer()
                if let price = unit.sellingPrice {
                    Text(PetAccessory.formatCurrency(NSNumber(value: price)))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primary)
                }
            }

            if unit.status == "RESERVED" {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.reservationCustomerName.isEmpty ? unit.reservationCustomerPhone : unit.reservationCustomerName)
                        .font(AdminType.captionBold)
                    if let validUntil = unit.reservationValidUntil {
                        Text(String(format: Language.get("LivePet_Reservation_Until_Format", alter: "الحجز صالح حتى %@"), validUntil.formatted(date: .abbreviated, time: .shortened)))
                            .font(AdminType.caption2)
                            .foregroundStyle(validUntil <= Date() ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
                    }
                }
            }

            Menu {
                livePetUnitActions(unit)
            } label: {
                Label(Language.get("LivePet_Unit_Actions", alter: "إجراءات الحيوان"), systemImage: "ellipsis.circle")
                    .font(AdminType.captionBold)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)
            .disabled(liveModel.isMutating)
        }
        .padding(12)
        .background(AdminSurface.control.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func livePetUnitActions(_ unit: PPLivePetInventoryUnit) -> some View {
        if unit.status == "AVAILABLE" {
            Button { liveModel.operation = .reserve(unit) } label: {
                Label(Language.get("LivePet_Reserve_Action", alter: "حجز لعميل"), systemImage: "calendar.badge.plus")
            }
            .disabled(!liveModel.canSell)
            Button { liveModel.operation = .transfer(unit) } label: {
                Label(Language.get("LivePet_Transfer_Action", alter: "نقل إلى فرع"), systemImage: "arrow.left.arrow.right")
            }
            .disabled(!liveModel.canManageStock)
            Button { liveModel.operation = .quarantine(unit) } label: {
                Label(Language.get("LivePet_Quarantine_Action", alter: "إدخال الحجر"), systemImage: "cross.case")
            }
            .disabled(!liveModel.canManageStock)
            Button { liveModel.operation = .price(unit) } label: {
                Label(Language.get("LivePet_Edit_Price_Action", alter: "تعديل سعر البيع"), systemImage: "tag")
            }
            .disabled(!liveModel.canManageStock)
            Button(role: .destructive) { liveModel.operation = .remove(unit) } label: {
                Label(Language.get("LivePet_Remove_Action", alter: "إزالة من المخزون"), systemImage: "minus.circle")
            }
            .disabled(!liveModel.canManageStock)
            Button(role: .destructive) { liveModel.operation = .mortality(unit) } label: {
                Label(Language.get("LivePet_Mortality_Action", alter: "تسجيل وفاة"), systemImage: "heart.slash")
            }
            .disabled(!liveModel.canManageStock)
        } else if unit.status == "RESERVED" {
            if let reservation = liveModel.reservation(for: unit) {
                Button { liveModel.operation = .reservation(reservation) } label: {
                    Label(Language.get("LivePet_Manage_Reservation", alter: "إدارة الحجز"), systemImage: "creditcard")
                }
            } else {
                Button { Task { await liveModel.load() } } label: {
                    Label(Language.get("Refresh", alter: "تحديث"), systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) { liveModel.operation = .mortality(unit) } label: {
                Label(Language.get("LivePet_Mortality_Action", alter: "تسجيل وفاة وإلغاء الحجز"), systemImage: "heart.slash")
            }
            .disabled(!liveModel.canManageStock)
        } else if unit.status == "QUARANTINED" {
            Button { liveModel.operation = .releaseQuarantine(unit) } label: {
                Label(Language.get("LivePet_Release_Quarantine_Action", alter: "إخراج من الحجر"), systemImage: "checkmark.shield")
            }
            .disabled(!liveModel.canReleaseQuarantine)
            Button { liveModel.operation = .transfer(unit) } label: {
                Label(Language.get("LivePet_Transfer_Action", alter: "نقل إلى فرع"), systemImage: "arrow.left.arrow.right")
            }
            .disabled(!liveModel.canManageStock)
            Button(role: .destructive) { liveModel.operation = .mortality(unit) } label: {
                Label(Language.get("LivePet_Mortality_Action", alter: "تسجيل وفاة"), systemImage: "heart.slash")
            }
            .disabled(!liveModel.canManageStock)
        } else {
            Text(Language.get("LivePet_Terminal_No_Actions", alter: "هذه حالة نهائية للعرض فقط"))
        }
    }

    private func liveUnitStatus(_ status: String) -> String {
        switch status {
        case "AVAILABLE": return Language.get("LivePet_Status_Available", alter: "متاح")
        case "RESERVED": return Language.get("LivePet_Status_Reserved", alter: "محجوز")
        case "SOLD": return Language.get("LivePet_Status_Sold", alter: "مباع")
        case "QUARANTINED": return Language.get("LivePet_Status_Quarantined", alter: "في الحجر")
        case "DECEASED": return Language.get("LivePet_Status_Deceased", alter: "متوفى")
        case "TRANSFERRED": return Language.get("LivePet_Status_Transferred", alter: "منقول نهائياً")
        default: return Language.get("LivePet_Status_Removed", alter: "مزال")
        }
    }

    private func liveUnitStatusColor(_ status: String) -> Color {
        switch status {
        case "AVAILABLE": return Color(uiColor: .ppSuccess)
        case "RESERVED", "QUARANTINED": return Color(uiColor: .ppWarning)
        case "SOLD", "TRANSFERRED": return AdminCommandInk.secondary
        default: return Color(uiColor: .ppError)
        }
    }

    private func dossierMetricCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dossierRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AdminSurface.primaryText)
        }
    }
}

// MARK: - Live-Pet Operation Sheet

private struct PPLivePetOperationSheet: View {
    let context: PPLivePetOperationContext
    @ObservedObject var model: PPLivePetOperationsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: PPLivePetInventoryMode = .individual
    @State private var unitDrafts: [PPLivePetUnitDraft]
    @State private var quantityText: String
    @State private var costText: String = ""
    @State private var standardPriceText: String
    @State private var supplier: String = ""
    @State private var notes: String = ""
    @State private var reason: String = ""
    @State private var customerName: String = ""
    @State private var customerPhone: String = ""
    @State private var selectedBranchID: String = ""
    @State private var reservationValidUntil: Date = Date().addingTimeInterval(24 * 60 * 60)
    @State private var cashReceivedText: String = ""
    @State private var causeCode: String = "UNKNOWN"
    @State private var veterinaryReference: String = ""
    @State private var observedDeathAt: Date = Date()
    @State private var validationMessage: String?

    init(context: PPLivePetOperationContext, model: PPLivePetOperationsViewModel) {
        self.context = context
        self.model = model
        let standardPrice = model.item.standardSellingPrice?.doubleValue ?? model.item.price.doubleValue
        _standardPriceText = State(initialValue: standardPrice > 0 ? String(format: "%g", standardPrice) : "")
        _quantityText = State(initialValue: "\(max(0, model.item.quantity))")

        let draftCount: Int
        if case .migrate = context, model.item.quantity <= 100 {
            draftCount = max(0, model.item.quantity)
        } else {
            draftCount = 1
        }
        _unitDrafts = State(initialValue: (0..<draftCount).map { _ in
            PPLivePetUnitDraft(sellingPriceText: standardPrice > 0 ? String(format: "%g", standardPrice) : "")
        })

        switch context {
        case .reserve(let unit):
            _selectedBranchID = State(initialValue: unit.currentBranchID.isEmpty ? (model.item.storeID ?? "") : unit.currentBranchID)
        case .transfer(let unit):
            _selectedBranchID = State(initialValue: unit.currentBranchID.isEmpty ? (model.item.storeID ?? "") : unit.currentBranchID)
        case .reservation(let reservation):
            _selectedBranchID = State(initialValue: reservation.branchID)
            _customerName = State(initialValue: reservation.customerName)
            _customerPhone = State(initialValue: reservation.customerPhone)
            _cashReceivedText = State(initialValue: String(format: "%.2f", reservation.total))
        case .intake:
            _selectedMode = State(initialValue: model.mode ?? .individual)
        default:
            break
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        operationHeader
                        operationFields

                        if let message = validationMessage ?? model.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(AdminType.caption1)
                                .foregroundStyle(Color(uiColor: .ppError))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        actionButtons
                    }
                    .padding(16)
                }
            }
            .navigationTitle(operationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) { dismiss() }
                        .disabled(model.isMutating)
                }
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            normalizeBranchSelection()
        }
        .onChange(of: model.branches) { _ in
            // Branches are fetched after the sheet is presented. Reconcile the
            // initial branch selection again when the scoped options arrive so
            // reservation and transfer actions never start on a stale/invalid
            // branch identifier.
            normalizeBranchSelection()
        }
    }

    private var operationHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(operationTitle, systemImage: operationIcon)
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
            Text(operationHint)
                .font(AdminType.caption1)
                .foregroundStyle(AdminCommandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var operationFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch context {
            case .migrate:
                Picker(Language.get("LivePet_Tracking_Title", alter: "نمط إدارة المخزون الحي"), selection: $selectedMode) {
                    ForEach(PPLivePetInventoryMode.allCases) { mode in Text(mode.localizedTitle).tag(mode) }
                }
                .pickerStyle(.segmented)
                Text(selectedMode.localizedHint)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)
                if selectedMode == .individual {
                    if model.item.quantity > 100 {
                        Text(Language.get("LivePet_Migration_TooMany", alter: "لا يمكن تحويل أكثر من 100 حيوان قديم دفعة واحدة. طابق الكمية أولاً أو استخدم وضع المجموعة."))
                            .font(AdminType.caption1)
                            .foregroundStyle(Color(uiColor: .ppError))
                    } else if model.item.quantity == 0 {
                        Text(Language.get("LivePet_Migration_Empty", alter: "سيتم اعتماد التتبع الفردي دون سجلات حالية، ويمكنك إضافة الحيوانات بعد ذلك."))
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminCommandInk.secondary)
                    } else {
                        migrationUnitFields
                    }
                    decimalField(Language.get("LivePet_Standard_SellingPrice_QAR", alter: "السعر القياسي (ر.ق)"), text: $standardPriceText)
                }

            case .intake:
                if model.mode == .individual {
                    unitDraftFields($unitDrafts[0], showRemove: false)
                } else {
                    numberField(Language.get("LivePet_Group_Quantity", alter: "الكمية المضافة"), text: $quantityText)
                    if model.canViewCosts {
                        decimalField(Language.get("LivePet_Group_PurchaseCost", alter: "تكلفة الوحدة"), text: $costText)
                    }
                    DatePicker(Language.get("LivePet_Unit_AcquisitionDate", alter: "تاريخ الاستلام"), selection: $unitDrafts[0].acquisitionDate, displayedComponents: .date)
                    textField(Language.get("LivePet_Supplier_Placeholder", alter: "المورد، اختياري"), text: $supplier)
                    textField(Language.get("LivePet_Group_Notes_Placeholder", alter: "ملاحظات الإدخال، اختيارية"), text: $notes)
                }

            case .reserve(let unit):
                unitIdentity(unit)
                textField(Language.get("LivePet_Customer_Name", alter: "اسم العميل"), text: $customerName)
                textField(Language.get("LivePet_Customer_Phone", alter: "رقم هاتف العميل"), text: $customerPhone, keyboard: .phonePad)
                branchPicker(excluding: nil)
                DatePicker(
                    Language.get("LivePet_Reservation_ValidUntil", alter: "صلاحية الحجز حتى"),
                    selection: $reservationValidUntil,
                    in: Date().addingTimeInterval(60)...,
                    displayedComponents: [.date, .hourAndMinute]
                )

            case .reservation(let reservation):
                reservationSummary(reservation)
                if reservation.paymentMethod == "cash" {
                    decimalField(Language.get("LivePet_Cash_Received", alter: "المبلغ النقدي المستلم"), text: $cashReceivedText)
                }
                if !model.canReleaseReservations {
                    Text(Language.get("LivePet_Reservation_Release_Permission_Hint", alter: "تحرير الحجز يتطلب صلاحية البيع وصلاحية رد المدفوعات."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .transfer(let unit):
                unitIdentity(unit)
                readOnlyField(
                    Language.get("LivePet_Source_Branch", alter: "الفرع الحالي"),
                    value: unit.currentBranchID.isEmpty ? (model.item.storeID ?? "") : unit.currentBranchID
                )
                branchPicker(excluding: unit.currentBranchID.isEmpty ? model.item.storeID : unit.currentBranchID)
                textField(Language.get("LivePet_Transfer_Reason", alter: "سبب النقل"), text: $reason)

            case .quarantine(let unit), .releaseQuarantine(let unit), .remove(let unit):
                unitIdentity(unit)
                textField(Language.get("LivePet_Operation_Reason", alter: "سبب الإجراء"), text: $reason)

            case .mortality(let unit):
                unitIdentity(unit)
                Picker(Language.get("LivePet_Mortality_Cause", alter: "سبب الوفاة"), selection: $causeCode) {
                    ForEach(mortalityCauses) { cause in
                        Text(cause.title).tag(cause.code)
                    }
                }
                .pickerStyle(.menu)
                DatePicker(
                    Language.get("LivePet_Mortality_ObservedAt", alter: "وقت ملاحظة الوفاة"),
                    selection: $observedDeathAt,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                textField(Language.get("LivePet_Mortality_Reason", alter: "وصف السبب"), text: $reason)
                textField(Language.get("LivePet_Mortality_Notes", alter: "ملاحظات داخلية، اختيارية"), text: $notes)
                textField(Language.get("LivePet_Mortality_VetReference", alter: "مرجع الطبيب البيطري، اختياري"), text: $veterinaryReference)

            case .price(let unit):
                unitIdentity(unit)
                decimalField(Language.get("LivePet_Unit_SellingPrice", alter: "سعر البيع"), text: $standardPriceText)

            case .groupAdjustment:
                numberField(Language.get("LivePet_Group_TargetQuantity", alter: "الكمية الفعلية الحالية"), text: $quantityText)
                textField(Language.get("LivePet_Adjustment_Reason", alter: "سبب المطابقة"), text: $reason)

            case .archive:
                textField(Language.get("LivePet_Operation_Reason", alter: "سبب الإجراء"), text: $reason)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var actionButtons: some View {
        Group {
            if case .reservation(let reservation) = context {
                VStack(spacing: 10) {
                    Button {
                        submitReservationCompletion(reservation)
                    } label: {
                        operationButtonLabel(Language.get("LivePet_Complete_Sale", alter: "إكمال البيع"), icon: "checkmark.seal.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AdminSurface.primary)
                    .disabled(model.isMutating || !model.canSell)

                    Button(role: .destructive) {
                        submitReservationRelease(reservation)
                    } label: {
                        operationButtonLabel(Language.get("LivePet_Release_Reservation", alter: "تحرير الحجز"), icon: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isMutating || !model.canReleaseReservations)
                }
            } else {
                Button {
                    submitPrimaryAction()
                } label: {
                    operationButtonLabel(primaryActionTitle, icon: operationIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(isDestructive ? Color(uiColor: .ppError) : AdminSurface.primary)
                .disabled(model.isMutating || !canSubmitByPermission)
            }
        }
    }

    private func operationButtonLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            if model.isMutating { ProgressView().tint(.white) }
            else { Image(systemName: icon) }
            Text(model.isMutating ? Language.get("LivePet_Operation_Processing", alter: "جارٍ التأكيد من الخادم...") : title)
                .font(AdminType.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private var migrationUnitFields: some View {
        VStack(spacing: 10) {
            ForEach($unitDrafts) { $unit in
                unitDraftFields($unit, showRemove: false)
            }
        }
    }

    private func unitDraftFields(_ unit: Binding<PPLivePetUnitDraft>, showRemove: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            textField(Language.get("LivePet_Ring_Placeholder", alter: "رقم الحلقة أو الشريحة"), text: unit.ringTag)
                .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 10) {
                decimalField(Language.get("LivePet_Unit_SellingPrice", alter: "سعر البيع"), text: unit.sellingPriceText)
                if model.canViewCosts {
                    decimalField(Language.get("LivePet_Unit_PurchaseCost", alter: "تكلفة الشراء"), text: unit.purchaseCostText)
                }
            }
            DatePicker(Language.get("LivePet_Unit_AcquisitionDate", alter: "تاريخ الاستلام"), selection: unit.acquisitionDate, displayedComponents: .date)
            textField(Language.get("LivePet_Supplier_Placeholder", alter: "المورد، اختياري"), text: unit.supplier)
            textField(Language.get("LivePet_Unit_Notes_Placeholder", alter: "ملاحظات داخلية، اختيارية"), text: unit.notes)
        }
        .padding(12)
        .background(AdminSurface.control.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func textField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(AdminType.caption2Bold).foregroundStyle(AdminCommandInk.secondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .font(AdminType.callout)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func decimalField(_ title: String, text: Binding<String>) -> some View {
        textField(title, text: text, keyboard: .decimalPad)
            .environment(\.layoutDirection, .leftToRight)
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        textField(title, text: text, keyboard: .numberPad)
            .environment(\.layoutDirection, .leftToRight)
    }

    private func readOnlyField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(AdminType.caption2Bold).foregroundStyle(AdminCommandInk.secondary)
            Text(value.isEmpty ? Language.get("LivePet_Branch_Unknown", alter: "الفرع غير محدد") : value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func branchPicker(excluding excludedID: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Language.get("LivePet_Destination_Branch", alter: "الفرع"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
            Picker(Language.get("LivePet_Select_Branch", alter: "اختر الفرع"), selection: $selectedBranchID) {
                Text(Language.get("LivePet_Select_Branch", alter: "اختر الفرع")).tag("")
                ForEach(model.branches.filter { $0.id != excludedID }) { branch in
                    Text(branch.name).tag(branch.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func normalizeBranchSelection() {
        let excludedID: String?
        switch context {
        case .transfer(let unit):
            excludedID = unit.currentBranchID.isEmpty ? model.item.storeID : unit.currentBranchID
        case .reserve:
            excludedID = nil
        default:
            return
        }
        let destinations = model.branches.filter { $0.id != excludedID }
        guard let firstDestination = destinations.first else {
            selectedBranchID = ""
            return
        }
        if !destinations.contains(where: { $0.id == selectedBranchID }) {
            selectedBranchID = firstDestination.id
        }
    }

    private func unitIdentity(_ unit: PPLivePetInventoryUnit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("LivePet_Selected_Animal", alter: "الحيوان المحدد"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(unit.ringTag.isEmpty ? unit.id : unit.ringTag)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
            }
            Spacer()
            Text(unit.status)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.primary)
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reservationSummary(_ reservation: PPLivePetReservation) -> some View {
        VStack(spacing: 10) {
            readOnlyField(Language.get("LivePet_Customer_Name", alter: "اسم العميل"), value: reservation.customerName)
            readOnlyField(Language.get("LivePet_Customer_Phone", alter: "رقم الهاتف"), value: reservation.customerPhone)
            readOnlyField(Language.get("LivePet_Source_Branch", alter: "فرع الحجز"), value: reservation.branchID)
            HStack {
                Text(Language.get("LivePet_Reservation_Total", alter: "إجمالي الحجز"))
                    .font(AdminType.caption2Bold)
                Spacer()
                Text(PetAccessory.formatCurrency(NSNumber(value: reservation.total)))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primary)
            }
            if let validUntil = reservation.validUntil {
                HStack {
                    Text(Language.get("LivePet_Reservation_ValidUntil", alter: "صالح حتى"))
                        .font(AdminType.caption2Bold)
                    Spacer()
                    Text(validUntil.formatted(date: .abbreviated, time: .shortened))
                        .font(AdminType.caption1)
                        .foregroundStyle(validUntil <= Date() ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
                }
            }
        }
    }

    private var mortalityCauses: [PPLivePetMortalityCause] {
        [
            PPLivePetMortalityCause(code: "ILLNESS", title: Language.get("LivePet_Mortality_Illness", alter: "مرض")),
            PPLivePetMortalityCause(code: "INJURY", title: Language.get("LivePet_Mortality_Injury", alter: "إصابة")),
            PPLivePetMortalityCause(code: "NATURAL", title: Language.get("LivePet_Mortality_Natural", alter: "أسباب طبيعية")),
            PPLivePetMortalityCause(code: "VETERINARY_EUTHANASIA", title: Language.get("LivePet_Mortality_Euthanasia", alter: "إنهاء رحيم بيطري")),
            PPLivePetMortalityCause(code: "ACCIDENT", title: Language.get("LivePet_Mortality_Accident", alter: "حادث")),
            PPLivePetMortalityCause(code: "UNKNOWN", title: Language.get("LivePet_Mortality_Unknown", alter: "غير معروف")),
            PPLivePetMortalityCause(code: "OTHER", title: Language.get("LivePet_Mortality_Other", alter: "سبب آخر")),
        ]
    }

    private func submitPrimaryAction() {
        validationMessage = nil
        Task { @MainActor in
            let success: Bool
            switch context {
            case .migrate:
                guard selectedMode != .individual || model.item.quantity <= 100 else {
                    validationMessage = Language.get("LivePet_Migration_TooMany", alter: "عدد السجلات يتجاوز الحد الآمن للتحويل الفردي.")
                    return
                }
                guard let price = validPositiveMoney(standardPriceText, required: selectedMode == .individual) else {
                    validationMessage = Language.get("LivePet_Validation_UnitPrice", alter: "أدخل سعراً قياسياً صالحاً.")
                    return
                }
                success = await model.migrate(mode: selectedMode, units: selectedMode == .individual ? unitDrafts : [], standardSellingPrice: price)

            case .intake:
                if model.mode == .individual {
                    let unit = unitDrafts[0]
                    let cost: Double
                    if model.canViewCosts {
                        guard !unit.purchaseCostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let validatedCost = validNonnegativeMoney(unit.purchaseCostText) else {
                            validationMessage = Language.get("LivePet_Validation_UnitCost", alter: "أدخل تكلفة استلام صالحة.")
                            return
                        }
                        cost = validatedCost
                    } else {
                        cost = 0
                    }
                    success = await model.intake(mode: .individual, unit: unit, quantity: 1, cost: cost, supplier: unit.supplier, notes: unit.notes)
                } else {
                    guard let quantity = Int(quantityText), quantity > 0 else {
                        validationMessage = Language.get("LivePet_Validation_GroupQuantity", alter: "أدخل كمية صحيحة أكبر من صفر.")
                        return
                    }
                    let cost: Double
                    if model.canViewCosts {
                        guard !costText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let validatedCost = validNonnegativeMoney(costText) else {
                            validationMessage = Language.get("LivePet_Validation_UnitCost", alter: "أدخل تكلفة استلام صالحة.")
                            return
                        }
                        cost = validatedCost
                    } else {
                        cost = 0
                    }
                    success = await model.intake(mode: .quantity, unit: unitDrafts[0], quantity: quantity, cost: cost, supplier: supplier, notes: notes)
                }

            case .reserve(let unit):
                guard customerName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
                    validationMessage = Language.get("LivePet_Validation_CustomerName", alter: "أدخل اسم العميل بصورة واضحة.")
                    return
                }
                guard customerPhone.filter(\.isNumber).count >= 7 else {
                    validationMessage = Language.get("LivePet_Validation_CustomerPhone", alter: "أدخل رقم هاتف صالحاً للعميل.")
                    return
                }
                guard !selectedBranchID.isEmpty else {
                    validationMessage = Language.get("LivePet_Validation_Branch", alter: "اختر فرع الحجز.")
                    return
                }
                guard reservationValidUntil > Date() else {
                    validationMessage = Language.get("LivePet_Error_ReservationExpired", alter: "يجب أن تكون صلاحية الحجز في المستقبل.")
                    return
                }
                success = await model.reserve(
                    unit: unit,
                    customerName: customerName.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: customerPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                    branchID: selectedBranchID,
                    validUntil: reservationValidUntil
                )

            case .transfer(let unit):
                let source = unit.currentBranchID.isEmpty ? (model.item.storeID ?? "") : unit.currentBranchID
                guard !source.isEmpty, !selectedBranchID.isEmpty, source != selectedBranchID else {
                    validationMessage = Language.get("LivePet_Validation_TransferBranch", alter: "اختر فرعاً مختلفاً عن الفرع الحالي.")
                    return
                }
                guard validateReason() else { return }
                success = await model.transfer(unit: unit, sourceBranchID: source, destinationBranchID: selectedBranchID, reason: reasonTrimmed)

            case .quarantine(let unit):
                guard validateReason() else { return }
                success = await model.lifecycle(action: "quarantine_unit", unit: unit, reason: reasonTrimmed)

            case .releaseQuarantine(let unit):
                guard validateReason() else { return }
                success = await model.lifecycle(action: "release_quarantine", unit: unit, reason: reasonTrimmed)

            case .mortality(let unit):
                guard validateReason() else { return }
                success = await model.lifecycle(
                    action: "record_mortality",
                    unit: unit,
                    reason: reasonTrimmed,
                    causeCode: causeCode,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    veterinaryReference: veterinaryReference.trimmingCharacters(in: .whitespacesAndNewlines),
                    observedDeathAt: observedDeathAt
                )

            case .remove(let unit):
                guard validateReason() else { return }
                success = await model.remove(unit: unit, reason: reasonTrimmed)

            case .price(let unit):
                guard let price = validPositiveMoney(standardPriceText) else {
                    validationMessage = Language.get("LivePet_Validation_UnitPrice", alter: "أدخل سعر بيع صالحاً.")
                    return
                }
                success = await model.updatePrice(unit: unit, price: price)

            case .groupAdjustment:
                guard let quantity = Int(quantityText), quantity >= 0 else {
                    validationMessage = Language.get("LivePet_Validation_TargetQuantity", alter: "أدخل كمية فعلية صحيحة لا تقل عن صفر.")
                    return
                }
                guard validateReason() else { return }
                success = await model.adjustGroup(targetQuantity: quantity, reason: reasonTrimmed)

            case .archive(let archived):
                guard validateReason() else { return }
                success = await model.archive(archived, reason: reasonTrimmed)

            case .reservation:
                return
            }
            if success { dismiss() }
        }
    }

    private func submitReservationCompletion(_ reservation: PPLivePetReservation) {
        validationMessage = nil
        guard reservation.validUntil.map({ $0 > Date() }) == true else {
            validationMessage = Language.get("LivePet_Error_ReservationExpired", alter: "انتهت صلاحية الحجز. حرره ولا تكمل البيع.")
            return
        }
        let cashReceived = validNonnegativeMoney(cashReceivedText) ?? 0
        if reservation.paymentMethod == "cash", cashReceived < reservation.total {
            validationMessage = Language.get("LivePet_Validation_Cash", alter: "يجب أن يغطي المبلغ النقدي إجمالي الحجز.")
            return
        }
        Task { @MainActor in
            if await model.complete(reservation: reservation, cashReceived: cashReceived) { dismiss() }
        }
    }

    private func submitReservationRelease(_ reservation: PPLivePetReservation) {
        validationMessage = nil
        Task { @MainActor in
            if await model.cancel(reservation: reservation) { dismiss() }
        }
    }

    private var reasonTrimmed: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func validateReason() -> Bool {
        if reasonTrimmed.count >= 3 { return true }
        validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
        return false
    }

    private func validPositiveMoney(_ text: String, required: Bool = true) -> Double? {
        if !required && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value > 0,
              value <= 999_999_999.99,
              abs(value * 100 - (value * 100).rounded()) < 0.000_001 else { return nil }
        return value
    }

    private func validNonnegativeMoney(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value >= 0 else { return nil }
        return value
    }

    private var canSubmitByPermission: Bool {
        switch context {
        case .reserve: return model.canSell
        case .reservation: return false
        case .releaseQuarantine: return model.canReleaseQuarantine
        default: return model.canManageStock
        }
    }

    private var isDestructive: Bool {
        switch context {
        case .mortality, .remove, .archive(true): return true
        default: return false
        }
    }

    private var operationTitle: String {
        switch context {
        case .migrate: return Language.get("LivePet_Migrate_Action", alter: "اعتماد نمط المخزون")
        case .intake: return Language.get("LivePet_Intake_Action", alter: "إضافة مخزون حي")
        case .reserve: return Language.get("LivePet_Reserve_Action", alter: "حجز الحيوان")
        case .reservation: return Language.get("LivePet_Manage_Reservation", alter: "إدارة الحجز")
        case .transfer: return Language.get("LivePet_Transfer_Action", alter: "نقل الحيوان إلى فرع")
        case .quarantine: return Language.get("LivePet_Quarantine_Action", alter: "إدخال الحجر")
        case .releaseQuarantine: return Language.get("LivePet_Release_Quarantine_Action", alter: "إخراج من الحجر")
        case .mortality: return Language.get("LivePet_Mortality_Action", alter: "تسجيل وفاة")
        case .remove: return Language.get("LivePet_Remove_Action", alter: "إزالة سجل")
        case .price: return Language.get("LivePet_Edit_Price_Action", alter: "تعديل سعر البيع")
        case .groupAdjustment: return Language.get("LivePet_Group_Adjust_Action", alter: "مطابقة كمية المجموعة")
        case .archive(let archived): return archived
            ? Language.get("LivePet_Archive_Action", alter: "أرشفة سجل الكتالوج")
            : Language.get("LivePet_Restore_Action", alter: "استعادة سجل الكتالوج")
        }
    }

    private var primaryActionTitle: String {
        switch context {
        case .migrate: return Language.get("LivePet_Migration_Confirm", alter: "تأكيد نمط التتبع")
        case .intake: return Language.get("LivePet_Intake_Confirm", alter: "تأكيد إضافة المخزون")
        case .reserve: return Language.get("LivePet_Reservation_Confirm", alter: "تأكيد الحجز")
        case .transfer: return Language.get("LivePet_Transfer_Confirm", alter: "تأكيد النقل")
        case .quarantine: return Language.get("LivePet_Quarantine_Confirm", alter: "تأكيد الحجر")
        case .releaseQuarantine: return Language.get("LivePet_Release_Confirm", alter: "تأكيد الإخراج")
        case .mortality: return Language.get("LivePet_Mortality_Confirm", alter: "تأكيد تسجيل الوفاة")
        case .remove: return Language.get("LivePet_Remove_Confirm", alter: "تأكيد الإزالة")
        case .price: return Language.get("LivePet_Price_Confirm", alter: "حفظ السعر")
        case .groupAdjustment: return Language.get("LivePet_Group_Adjust_Confirm", alter: "تأكيد المطابقة")
        case .archive(let archived): return archived
            ? Language.get("LivePet_Archive_Confirm", alter: "تأكيد الأرشفة")
            : Language.get("LivePet_Restore_Confirm", alter: "تأكيد الاستعادة")
        case .reservation: return ""
        }
    }

    private var operationHint: String {
        switch context {
        case .migrate: return Language.get("LivePet_Migration_Hint", alter: "يحافظ الخادم على الكمية الحالية وينشئ سجلات الهوية عند اختيار التتبع الفردي.")
        case .intake: return Language.get("LivePet_Intake_Hint", alter: "تُضاف الكمية أو الهوية داخل معاملة واحدة مع حركة مخزون وسجل تدقيق.")
        case .reserve: return Language.get("LivePet_Reservation_Hint", alter: "سيُحفظ العميل في دليل نقطة البيع ويُحجز هذا الحيوان حتى الموعد المحدد.")
        case .reservation: return Language.get("LivePet_Manage_Reservation_Hint", alter: "أكمل البيع بعد استلام المبلغ، أو حرر الحجز لإعادة الحيوان إلى المتاح.")
        case .transfer: return Language.get("LivePet_Transfer_Hint", alter: "يتغير فرع العهدة فقط؛ هوية الحيوان وحالته وسجله تبقى محفوظة.")
        case .quarantine: return Language.get("LivePet_Quarantine_Hint", alter: "يخرج الحيوان من الكمية المتاحة حتى يتم إخراجه من الحجر بصلاحية مستقلة.")
        case .releaseQuarantine: return Language.get("LivePet_Release_Hint", alter: "يعيد الحيوان إلى المتاح ويعيد حساب سعر عرض الكتالوج من السجلات المتاحة.")
        case .mortality: return Language.get("LivePet_Mortality_Hint", alter: "حالة نهائية. يسجل الخادم التكلفة والسبب ويلغي الحجز النشط بأمان عند الحاجة.")
        case .remove: return Language.get("LivePet_Remove_Hint", alter: "متاح فقط للسجل المتاح، ويحتفظ الخادم بأثر الإزالة.")
        case .price: return Language.get("LivePet_Price_Hint", alter: "سعر هذا الحيوان هو مرجع نقطة البيع النهائي.")
        case .groupAdjustment: return Language.get("LivePet_Group_Adjust_Hint", alter: "استخدم العدد الفعلي بعد الجرد؛ لا تستخدمه لتسجيل بيع.")
        case .archive(let archived): return archived
            ? Language.get("LivePet_Archive_Hint", alter: "يُخفى السجل من قنوات البيع مع بقاء الوحدات والحركات محفوظة.")
            : Language.get("LivePet_Restore_Hint", alter: "يعاد السجل إلى الكتالوج وفق حالته الحالية وتوفره الفعلي.")
        }
    }

    private var operationIcon: String {
        switch context {
        case .migrate: return "arrow.triangle.branch"
        case .intake: return "plus.circle.fill"
        case .reserve: return "calendar.badge.plus"
        case .reservation: return "creditcard"
        case .transfer: return "arrow.left.arrow.right"
        case .quarantine: return "cross.case"
        case .releaseQuarantine: return "checkmark.shield"
        case .mortality: return "heart.slash"
        case .remove: return "minus.circle"
        case .price: return "tag"
        case .groupAdjustment: return "slider.horizontal.3"
        case .archive(let archived): return archived ? "archivebox" : "arrow.uturn.backward.circle"
        }
    }
}

// MARK: - Press Style

private struct CatalogPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - UIViewController Hosting Bridge for ObjC Routing

@objc public final class PPInventoryListHostingController: UIViewController {
    private let kind: AccessKindType
    private var hostingController: UIHostingController<PPInventoryListView>?

    @objc public init(kind: AccessKindType = .typeAccessory) {
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.kind = .typeAccessory
        super.init(coder: coder)
    }

    @objc public static func makeForAccessories() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeAccessory)
    }

    @objc public static func makeForFood() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeFood)
    }

    @objc public static func makeForLivePets() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeLivePets)
    }

    @objc public static func make(kind: AccessKindType) -> UIViewController {
        return PPInventoryListHostingController(kind: kind)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground

        let swiftUIView = PPInventoryListView(
            kind: kind,
            onPushViewController: { [weak self] targetVC in
                self?.navigationController?.pushViewController(targetVC, animated: true)
            },
            onDismiss: { [weak self] in
                if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true)
                }
            }
        )

        let host = UIHostingController(rootView: swiftUIView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
