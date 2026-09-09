//
//  PPInventoryListView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//  Preserves 100% of AccessoryManager, PetAccessory, and Firestore backend contracts.
//

import SwiftUI
import Combine
import UIKit
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

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

/// Biological sex recorded for one individually tracked live animal.
///
/// Raw values mirror the Infra `LIVE_PET_UNIT_GENDER` allowlist exactly; the
/// server rejects anything outside it, so this type is the client-side guard
/// that a malformed value can never be assembled in the first place.
enum PPLivePetUnitGender: String, CaseIterable, Identifiable, Equatable {
    case male = "MALE"
    case female = "FEMALE"
    case pair = "PAIR"
    case unspecified = "UNSPECIFIED"

    var id: String { rawValue }

    /// Compatible resolution for stored or transported values, including units
    /// created before the field existed.
    static func resolved(_ raw: Any?) -> PPLivePetUnitGender {
        let candidate = PPLivePetInventoryService.string(raw).uppercased()
        return PPLivePetUnitGender(rawValue: candidate) ?? .unspecified
    }

    var localizedTitle: String {
        switch self {
        case .male: return Language.get("LivePetUnit_Gender_Male", alter: "ذكر")
        case .female: return Language.get("LivePetUnit_Gender_Female", alter: "أنثى")
        case .pair: return Language.get("LivePetUnit_Gender_Pair", alter: "زوج")
        case .unspecified: return Language.get("LivePetUnit_Gender_Unspecified", alter: "غير محدد")
        }
    }

    /// Short form used inside dense identity rows where the full label would
    /// truncate before the ring/tag.
    var localizedShortTitle: String {
        switch self {
        case .male: return Language.get("LivePetUnit_Gender_Male_Short", alter: "ذكر")
        case .female: return Language.get("LivePetUnit_Gender_Female_Short", alter: "أنثى")
        case .pair: return Language.get("LivePetUnit_Gender_Pair_Short", alter: "زوج")
        case .unspecified: return Language.get("LivePetUnit_Gender_Unspecified_Short", alter: "بلا جنس")
        }
    }

    var symbolName: String {
        switch self {
        case .male: return "arrow.up.right.circle.fill"
        case .female: return "arrow.down.circle.fill"
        case .pair: return "circle.grid.2x1.fill"
        case .unspecified: return "questionmark.circle.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .male: return .ppInfo
        case .female: return .ppPrimary
        case .pair: return .ppSuccess
        case .unspecified: return .ppTextTertiary
        }
    }
}

struct PPLivePetUnitDraft: Identifiable, Equatable {
    let id: String
    var ringTag: String
    var gender: PPLivePetUnitGender
    var acquisitionDate: Date
    var purchaseCostText: String
    var sellingPriceText: String
    var supplier: String
    var notes: String
    var subSubKindID: Int?
    var subSubKindNameAr: String?
    var subSubKindNameEn: String?
    var subSubKindItemID: Int?
    var subSubKindItemNameAr: String?
    var subSubKindItemNameEn: String?

    var subSubKindName: String? {
        if Language.isRTL() {
            return !(subSubKindNameAr ?? "").isEmpty ? subSubKindNameAr : subSubKindNameEn
        } else {
            return !(subSubKindNameEn ?? "").isEmpty ? subSubKindNameEn : subSubKindNameAr
        }
    }

    var subSubKindItemName: String? {
        if Language.isRTL() {
            return !(subSubKindItemNameAr ?? "").isEmpty ? subSubKindItemNameAr : subSubKindItemNameEn
        } else {
            return !(subSubKindItemNameEn ?? "").isEmpty ? subSubKindItemNameEn : subSubKindItemNameAr
        }
    }

    init(
        id: String = "unit_draft_\(UUID().uuidString.lowercased())",
        ringTag: String = "",
        gender: PPLivePetUnitGender = .unspecified,
        acquisitionDate: Date = Date(),
        purchaseCostText: String = "",
        sellingPriceText: String = "",
        supplier: String = "",
        notes: String = "",
        subSubKindID: Int? = nil,
        subSubKindNameAr: String? = nil,
        subSubKindNameEn: String? = nil,
        subSubKindItemID: Int? = nil,
        subSubKindItemNameAr: String? = nil,
        subSubKindItemNameEn: String? = nil
    ) {
        self.id = id
        self.ringTag = ringTag
        self.gender = gender
        self.acquisitionDate = acquisitionDate
        self.purchaseCostText = purchaseCostText
        self.sellingPriceText = sellingPriceText
        self.supplier = supplier
        self.notes = notes
        self.subSubKindID = subSubKindID
        self.subSubKindNameAr = subSubKindNameAr
        self.subSubKindNameEn = subSubKindNameEn
        self.subSubKindItemID = subSubKindItemID
        self.subSubKindItemNameAr = subSubKindItemNameAr
        self.subSubKindItemNameEn = subSubKindItemNameEn
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
    let subSubKindID: Int?
    let subSubKindNameAr: String?
    let subSubKindNameEn: String?
    let subSubKindItemID: Int?
    let subSubKindItemNameAr: String?
    let subSubKindItemNameEn: String?

    var subSubKindName: String? {
        if Language.isRTL() {
            return !(subSubKindNameAr ?? "").isEmpty ? subSubKindNameAr : subSubKindNameEn
        } else {
            return !(subSubKindNameEn ?? "").isEmpty ? subSubKindNameEn : subSubKindNameAr
        }
    }

    var subSubKindItemName: String? {
        if Language.isRTL() {
            return !(subSubKindItemNameAr ?? "").isEmpty ? subSubKindItemNameAr : subSubKindItemNameEn
        } else {
            return !(subSubKindItemNameEn ?? "").isEmpty ? subSubKindItemNameEn : subSubKindItemNameAr
        }
    }

    init(dictionary: [String: Any]) {
        id = PPLivePetInventoryService.string(dictionary["unitId"] ?? dictionary["id"])
        ringTag = PPLivePetInventoryService.string(dictionary["ringTag"])
        status = PPLivePetInventoryService.string(dictionary["status"]).uppercased()
        sellingPrice = PPLivePetInventoryService.optionalNumber(dictionary["sellingPrice"])
        purchaseCost = PPLivePetInventoryService.optionalNumber(dictionary["purchaseCost"])
        supplier = PPLivePetInventoryService.string(dictionary["supplier"])
        notes = PPLivePetInventoryService.string(dictionary["notes"])
        currentBranchID = PPLivePetInventoryService.string(
            dictionary["currentBranchId"]
            ?? dictionary["currentBranchID"]
            ?? dictionary["branchId"]
            ?? dictionary["branchID"]
            ?? dictionary["storeId"]
            ?? dictionary["storeID"]
        )
        reservationTransactionID = PPLivePetInventoryService.string(dictionary["reservationTransactionId"])
        reservationCustomerName = PPLivePetInventoryService.string(dictionary["reservationCustomerName"])
        reservationCustomerPhone = PPLivePetInventoryService.string(dictionary["reservationCustomerPhone"])
        reservationValidUntil = PPLivePetInventoryService.date(dictionary["reservationValidUntil"])
        mortalityReason = PPLivePetInventoryService.string(dictionary["mortalityReason"])
        transferReason = PPLivePetInventoryService.string(dictionary["transferReason"])
        subSubKindID = (dictionary["subSubKindID"] as? NSNumber)?.intValue
            ?? (dictionary["subSubKindId"] as? NSNumber)?.intValue
        subSubKindNameAr = PPLivePetInventoryService.string(dictionary["subSubKindNameAr"] ?? dictionary["subSubKindName"])
        subSubKindNameEn = PPLivePetInventoryService.string(dictionary["subSubKindNameEn"])
        subSubKindItemID = (dictionary["subSubKindItemID"] as? NSNumber)?.intValue
            ?? (dictionary["subSubKindItemId"] as? NSNumber)?.intValue
        subSubKindItemNameAr = PPLivePetInventoryService.string(dictionary["subSubKindItemNameAr"] ?? dictionary["subSubKindItemName"])
        subSubKindItemNameEn = PPLivePetInventoryService.string(dictionary["subSubKindItemNameEn"])
    }
}

struct PPLivePetReservationItem: Equatable {
    let productID: String
    let name: String
    let unitPrice: Double
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
                name: PPLivePetInventoryService.string(source["name"]),
                unitPrice: PPLivePetInventoryService.optionalNumber(source["unitPrice"]) ?? 0,
                unitIDs: PPLivePetInventoryService.strings(source["unitIds"]),
                ringTags: PPLivePetInventoryService.strings(source["unitRingTags"])
            )
        }
    }

    func contains(productID: String, unitID: String) -> Bool {
        items.contains { $0.productID == productID && $0.unitIDs.contains(unitID) }
    }
}

struct PPInventoryBranchOption: Identifiable, Equatable, Hashable {
    let id: String
    let code: String
    let nameAr: String
    let nameEn: String
    let address: String
    let phone: String
    let isDefault: Bool
    let stockMode: String

    init(id: String, name: String) {
        self.id = id
        self.code = ""
        self.nameAr = name
        self.nameEn = name
        self.address = ""
        self.phone = ""
        self.isDefault = false
        self.stockMode = ""
    }

    init(
        id: String,
        code: String = "",
        nameAr: String = "",
        nameEn: String = "",
        address: String = "",
        phone: String = "",
        isDefault: Bool = false,
        stockMode: String = ""
    ) {
        self.id = id
        self.code = code
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.address = address
        self.phone = phone
        self.isDefault = isDefault
        self.stockMode = stockMode
    }

    var name: String { displayName }

    var displayName: String {
        if Language.isRTL() {
            if !nameAr.isEmpty { return nameAr }
            if !nameEn.isEmpty { return nameEn }
        } else {
            if !nameEn.isEmpty { return nameEn }
            if !nameAr.isEmpty { return nameAr }
        }
        if id == "main_store" || id.lowercased() == "main_store" || id.lowercased() == "main store" {
            return Language.get("MainStore", alter: "المتجر الرئيسي")
        }
        if id.lowercased().contains("reservation") {
            return Language.get("ReservationBranch", alter: "فرع الحجوزات")
        }
        if !code.isEmpty { return code }
        return id
    }

    var fullMeaningfulTitle: String {
        var parts: [String] = [displayName]
        if !code.isEmpty && !displayName.contains(code) {
            parts.append("(\(code))")
        }
        if isDefault {
            parts.append("★ " + Language.get("DefaultBranch", alter: "الفرع الافتراضي"))
        }
        return parts.joined(separator: " ")
    }

    var locationDetail: String {
        var parts: [String] = []
        if !address.isEmpty { parts.append(address) }
        if !phone.isEmpty { parts.append(phone) }
        return parts.joined(separator: " • ")
    }

    var stockModeTitle: String {
        if stockMode.lowercased() == "shared" || stockMode.lowercased() == "branch" {
            return Language.get("StockMode_Shared", alter: "مخزون مشترك للفرع")
        } else if stockMode.lowercased() == "separate" || stockMode.lowercased() == "peragent" {
            return Language.get("StockMode_PerAgent", alter: "مخزون مستقل لكل موظف")
        }
        return ""
    }
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
        let isUnauth = nsError.code == 16 ||
            nsError.code == FunctionsErrorCode.unauthenticated.rawValue ||
            nsError.localizedDescription.lowercased() == "unauthenticated" ||
            domainCode.lowercased() == "unauthenticated"
        if isUnauth {
            return Language.get("LivePet_Error_Unauthenticated", alter: "انتهت صلاحية جلسة الموظف أو تعذر التحقق من المصادقة. أعد فتح التطبيق وسجّل الدخول مجدداً.")
        }
        let backendMsg = string(details["message"] ?? details["error"] ?? nsError.userInfo[NSLocalizedDescriptionKey])
        if !backendMsg.isEmpty && !backendMsg.contains("com.firebase.functions") && !backendMsg.lowercased().contains("the operation couldn") {
            return backendMsg
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

    /// Uses the redacted, permission-scoped POS reservation projection. Passing
    /// no product returns the complete scoped queue; callers never read unit
    /// subcollections directly because those records include protected fields.
    static func listReservations(productID: String? = nil) async throws -> [PPLivePetReservation] {
        let response = try await call("listPosReservations", payload: ["pageSize": 500])
        if response["truncated"] as? Bool == true {
            throw PPLivePetServiceError.truncatedReservations
        }
        let reservations = (response["reservations"] as? [[String: Any]] ?? [])
            .map(PPLivePetReservation.init)
        guard let productID = productID?.trimmingCharacters(in: .whitespacesAndNewlines), !productID.isEmpty else {
            return reservations
        }
        return reservations.filter { reservation in
            reservation.items.contains(where: { $0.productID == productID })
        }
    }

    static var cachedBranches: [PPInventoryBranchOption] = []

    static func branch(for id: String) -> PPInventoryBranchOption? {
        cachedBranches.first { $0.id == id }
    }

    static func canonicalBranch(for identifier: String, in branches: [PPInventoryBranchOption]) -> PPInventoryBranchOption? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Exact match by Document ID
        if let match = branches.first(where: { $0.id == trimmed }) {
            return match
        }

        // 2. Exact match by Code (case-insensitive)
        if let match = branches.first(where: { !$0.code.isEmpty && $0.code.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }

        // 3. Match by nameAr, nameEn, or displayName (case-insensitive)
        if let match = branches.first(where: {
            (!$0.nameAr.isEmpty && $0.nameAr.caseInsensitiveCompare(trimmed) == .orderedSame) ||
            (!$0.nameEn.isEmpty && $0.nameEn.caseInsensitiveCompare(trimmed) == .orderedSame) ||
            (!$0.displayName.isEmpty && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame)
        }) {
            return match
        }

        // 4. Match cached branches
        if let cached = cachedBranches.first(where: {
            $0.id == trimmed ||
            (!$0.code.isEmpty && $0.code.caseInsensitiveCompare(trimmed) == .orderedSame) ||
            (!$0.nameAr.isEmpty && $0.nameAr.caseInsensitiveCompare(trimmed) == .orderedSame) ||
            (!$0.nameEn.isEmpty && $0.nameEn.caseInsensitiveCompare(trimmed) == .orderedSame) ||
            (!$0.displayName.isEmpty && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame)
        }) {
            return cached
        }

        // 5. Match PPBranchContextManager model
        if let b = PPBranchContextManager.shared().branch(withID: trimmed) {
            if let match = branches.first(where: { $0.id == b.branchID }) {
                return match
            }
        }

        // 6. Substring match (e.g. if identifier contains the branch name or code)
        let substringMatches = branches.filter {
            ($0.displayName.count >= 3 && trimmed.contains($0.displayName)) ||
            ($0.code.count >= 3 && trimmed.contains($0.code))
        }
        if substringMatches.count == 1 {
            return substringMatches[0]
        }

        return nil
    }

    static func listBranches() async throws -> [PPInventoryBranchOption] {
        let snapshot = try await Firestore.firestore().collection("branches").getDocuments()
        let branches = snapshot.documents.compactMap { document -> PPInventoryBranchOption? in
            let data = document.data()
            if data["isActive"] as? Bool == false { return nil }

            var nameAr = string(data["nameAr"])
            var nameEn = string(data["nameEn"])

            if let nameMap = data["name"] as? [String: Any] {
                if nameAr.isEmpty { nameAr = string(nameMap["ar"]) }
                if nameEn.isEmpty { nameEn = string(nameMap["en"]) }
            } else if let nameStr = data["name"] as? String {
                if nameAr.isEmpty {
                    if nameStr.lowercased().contains("reservation") {
                        nameAr = Language.get("ReservationBranch", alter: "فرع الحجوزات")
                        nameEn = "Reservation Branch"
                    } else {
                        nameAr = nameStr
                    }
                }
            }

            if let branchName = data["branchName"] as? String, nameAr.isEmpty {
                nameAr = branchName
            }

            if nameAr.isEmpty && nameEn.isEmpty {
                if document.documentID.lowercased().contains("reservation") {
                    nameAr = Language.get("ReservationBranch", alter: "فرع الحجوزات")
                    nameEn = "Reservation Branch"
                } else if document.documentID.lowercased() == "main_store" {
                    nameAr = Language.get("MainStore", alter: "المتجر الرئيسي")
                    nameEn = "Main Store"
                }
            }

            let code = string(data["code"])
            let address = string(data["address"])
            let phone = string(data["phone"])
            let stockMode = string(data["stockMode"])
            let isDefault = data["isDefault"] as? Bool ?? false

            return PPInventoryBranchOption(
                id: document.documentID,
                code: code,
                nameAr: nameAr,
                nameEn: nameEn,
                address: address,
                phone: phone,
                isDefault: isDefault,
                stockMode: stockMode
            )
        }.sorted {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault && !$1.isDefault
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        cachedBranches = branches
        return branches
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

        // Strict: ONLY in live pets case each pet showing in ios consumer app as a separate and independent ad
        let isLive = (values["accessKindType"] as? Int == 3) ||
                     (values["product_type"] as? String == "live") ||
                     (values["category"] as? String == "Live Pets")
        guard isLive else { return }

        let showInAppMarket = values["showInAppMarket"] as? Bool ?? false
        let active = values["active"] as? Bool ?? true
        let shouldBeVisible = showInAppMarket && active

        let db = Firestore.firestore()
        let name = values["name"] as? String ?? ""
        let desc = values["desc"] as? String ?? ""
        let category = values["petMainCategoryID"] as? Int ?? 1
        let subcategory = values["petSubCategoryID"] as? Int ?? 0
        let storeID = values["storeID"] as? String ?? ""
        let storeName = values["storeName"] as? String ?? "Pure Pets"
        let ownerID = values["ownerID"] as? String ?? Auth.auth().currentUser?.uid ?? ""
        let catalogImages = values["imageURLsArray"] as? [String] ?? []
        let basePrice = (values["price"] as? Double) ?? (values["finalPrice"] as? Double) ?? 0.0

        do {
            let unitsSnapshot = try await db.collection("petAccessories")
                .document(productID)
                .collection("inventoryUnits")
                .getDocuments()

            if !unitsSnapshot.isEmpty {
                for unitDoc in unitsSnapshot.documents {
                    let unitData = unitDoc.data()
                    let unitID = unitDoc.documentID
                    let unitStatus = (unitData["status"] as? String ?? "AVAILABLE").uppercased()
                    let adDocID = "ad_unit_\(unitID)"
                    let adRef = db.collection("pet_ads").document(adDocID)

                    if shouldBeVisible && unitStatus == "AVAILABLE" {
                        let ringTag = (unitData["ringTag"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let adTitle = ringTag.isEmpty ? name : "\(name) (\(ringTag))"
                        let unitPrice = (unitData["sellingPrice"] as? Double) ?? basePrice
                        let gender = unitData["gender"] as? String ?? "undefined"
                        let unitImages = (unitData["mediaURLs"] as? [String])?.filter { !$0.isEmpty }
                        let images = (unitImages != nil && !unitImages!.isEmpty) ? unitImages! : catalogImages

                        var adPayload: [String: Any] = [
                            "adID": adDocID,
                            "adTitle": adTitle,
                            "name_lowercase": adTitle.lowercased(),
                            "desc": (unitData["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? desc,
                            "adDescription": (unitData["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? desc,
                            "price": unitPrice,
                            "finalPrice": unitPrice,
                            "category": category,
                            "mainKindID": category,
                            "subcategory": subcategory,
                            "kindID": subcategory,
                            "gender": gender,
                            "isFemale": gender == "female",
                            "imageURLs": images,
                            "images": images,
                            "imageItems": images.map { ["url": $0, "media_type": "image"] },
                            "status": 1, // PetAdStatusActive
                            "visibility": 0, // PetAdVisibilityPublic
                            "isApproved": true,
                            "isDeleted": false,
                            "isBlocked": false,
                            "isSold": false,
                            "ownerID": ownerID,
                            "ownerName": storeName,
                            "storeID": storeID,
                            "branchId": storeID,
                            "catalogItemId": productID,
                            "unitId": unitID,
                            "ringTag": ringTag,
                            "isLivePet": true,
                            "isFromCatalog": true,
                            "latitude": 25.2854,
                            "longitude": 51.5310,
                            "geohash": "tky60",
                            "adLocation": 1,
                            "locationName": "Doha",
                            "updatedAt": FieldValue.serverTimestamp(),
                        ]
                        try await adRef.setData(adPayload, merge: true)
                    } else {
                        try await adRef.setData([
                            "status": 0,
                            "visibility": 1,
                            "isDeleted": !shouldBeVisible,
                            "isSold": unitStatus == "SOLD",
                            "updatedAt": FieldValue.serverTimestamp(),
                        ], merge: true)
                    }
                }
            } else {
                let adDocID = "ad_live_\(productID)"
                let adRef = db.collection("pet_ads").document(adDocID)
                if shouldBeVisible {
                    var adPayload: [String: Any] = [
                        "adID": adDocID,
                        "adTitle": name,
                        "name_lowercase": name.lowercased(),
                        "desc": desc,
                        "adDescription": desc,
                        "price": basePrice,
                        "finalPrice": basePrice,
                        "category": category,
                        "mainKindID": category,
                        "subcategory": subcategory,
                        "kindID": subcategory,
                        "gender": "undefined",
                        "isFemale": false,
                        "imageURLs": catalogImages,
                        "images": catalogImages,
                        "imageItems": catalogImages.map { ["url": $0, "media_type": "image"] },
                        "status": 1,
                        "visibility": 0,
                        "isApproved": true,
                        "isDeleted": false,
                        "isBlocked": false,
                        "isSold": false,
                        "ownerID": ownerID,
                        "ownerName": storeName,
                        "storeID": storeID,
                        "branchId": storeID,
                        "catalogItemId": productID,
                        "isLivePet": true,
                        "isFromCatalog": true,
                        "latitude": 25.2854,
                        "longitude": 51.5310,
                        "geohash": "tky60",
                        "adLocation": 1,
                        "locationName": "Doha",
                        "updatedAt": FieldValue.serverTimestamp(),
                    ]
                    try await adRef.setData(adPayload, merge: true)
                } else {
                    try await adRef.setData([
                        "status": 0,
                        "visibility": 1,
                        "isDeleted": true,
                        "updatedAt": FieldValue.serverTimestamp(),
                    ], merge: true)
                }
            }
        } catch {
            print("⚠️ [PPLivePetInventoryService] syncLivePetAds error: \(error.localizedDescription)")
        }
    }

    private static func call(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        let boxed = PPSendableDictionary(dict: payload)
        guard let currentUser = Auth.auth().currentUser else {
            throw PPLivePetServiceError.notAuthenticated
        }
        _ = try? await currentUser.getIDTokenResult(forcingRefresh: false)
        let callable = Functions.functions().httpsCallable(name)
        callable.timeoutInterval = callableTimeout
        do {
            let result = try await callable.call(boxed.dict)
            guard let data = result.data as? [String: Any], data["ok"] as? Bool != false else {
                throw PPLivePetServiceError.invalidResponse
            }
            return data
        } catch {
            let nsError = error as NSError
            let isUnauth = (nsError.code == 16 || nsError.code == FunctionsErrorCode.unauthenticated.rawValue) ||
                nsError.localizedDescription.lowercased().contains("unauthenticated")
            if isUnauth, let currentUser = Auth.auth().currentUser {
                _ = try? await currentUser.getIDTokenResult(forcingRefresh: true)
                let retryResult = try await callable.call(boxed.dict)
                guard let data = retryResult.data as? [String: Any], data["ok"] as? Bool != false else {
                    throw PPLivePetServiceError.invalidResponse
                }
                return data
            }
            throw error
        }
    }
}

private struct PPSendableDictionary: @unchecked Sendable {
    let dict: [String: Any]
}

enum PPLivePetServiceError: LocalizedError {
    case invalidResponse
    case truncatedReservations
    case missingSellingPrice
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return Language.get("LivePet_Error_InvalidResponse", alter: "تعذر تأكيد استجابة الخادم. حدّث البيانات وحاول مرة أخرى.")
        case .truncatedReservations:
            return Language.get("LivePet_Error_ReservationLimit", alter: "تعذر تحميل جميع الحجوزات بأمان. استخدم نقطة البيع لمراجعة القائمة الكاملة.")
        case .missingSellingPrice:
            return Language.get("LivePet_Error_MissingUnitPrice", alter: "حدد سعر بيع صالحاً للحيوان قبل حجزه أو بيعه.")
        case .notAuthenticated:
            return Language.get("LivePet_Error_NotAuthenticated", alter: "يجب تسجيل الدخول بحساب موظف معتمد لإجراء هذه العملية.")
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
    var canReleaseQuarantine: Bool { canManageStock || (staff?.hasPermission("stock.quarantine.release") ?? false) }
    var canViewCosts: Bool { canManageStock || (staff?.hasPermission("stock.view") ?? false) || (staff?.hasPermission("stock.cost.view") ?? false) }

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
            let branchId = BranchContextStore.shared.activeBranch?.branchID ?? self.item.storeID ?? ""
            var payload: [String: Any] = [
                "inventoryMode": mode.rawValue,
                "units": mode == .individual ? unitPayloads : [],
            ]
            if !branchId.isEmpty { payload["branchId"] = branchId }
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

    func intake(mode: PPLivePetInventoryMode, unit: PPLivePetUnitDraft, quantity: Int, cost: Double, supplier: String, notes: String, branchID: String? = nil) async -> Bool {
        await perform({
            let targetBranch = branchID ?? BranchContextStore.shared.activeBranch?.branchID ?? self.item.storeID ?? ""
            var payload: [String: Any] = [
                "quantity": max(1, quantity),
                "costPrice": max(0, cost),
                "supplier": supplier,
                "arrivalDate": ISO8601DateFormatter().string(from: unit.acquisitionDate),
                "notes": notes,
            ]
            if !targetBranch.isEmpty {
                payload["branchId"] = targetBranch
            }
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
        let unitID = unit.id
        // Optimistically remove unit from active units list so the row disappears immediately
        self.units.removeAll { $0.id == unitID }
        self.objectWillChange.send()
        let ok = await perform({
            _ = try await PPLivePetInventoryService.callInventory(
                action: "remove_unit",
                productID: self.item.accessoryID,
                commandID: PPLivePetInventoryService.commandID("remove-unit"),
                payload: ["unitId": unitID, "reason": reason]
            )
        }, successKey: "LivePet_Remove_Success", successFallback: "تمت إزالة السجل المتاح من المخزون مع حفظ الأثر التشغيلي.")
        if !ok {
            await load()
        }
        return ok
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
            let sellingText = draft.sellingPriceText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
            guard let price = Double(sellingText), price > 0, price <= 999_999_999.99,
                  abs(price * 100 - (price * 100).rounded()) < 0.000_001 else {
                throw PPLivePetOperationValidationError.invalidPrice
            }
            let purchaseCostText = draft.purchaseCostText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
            let purchaseCost = Double(purchaseCostText)
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
            var dict: [String: Any] = [
                "draftUnitId": draft.id,
                "ringTag": draft.ringTag.trimmingCharacters(in: .whitespacesAndNewlines),
                "gender": draft.gender.rawValue,
                "acquisitionDate": ISO8601DateFormatter().string(from: draft.acquisitionDate),
                "purchaseCost": purchaseCost ?? NSNull(),
                "sellingPrice": price,
                "supplier": draft.supplier.trimmingCharacters(in: .whitespacesAndNewlines),
                "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                "mediaURLs": [],
            ]
            if let subSubID = draft.subSubKindID {
                dict["subSubKindID"] = subSubID
                dict["subSubKindNameAr"] = draft.subSubKindNameAr ?? ""
                dict["subSubKindNameEn"] = draft.subSubKindNameEn ?? ""
            }
            if let itemID = draft.subSubKindItemID {
                dict["subSubKindItemID"] = itemID
                dict["subSubKindItemNameAr"] = draft.subSubKindItemNameAr ?? ""
                dict["subSubKindItemNameEn"] = draft.subSubKindItemNameEn ?? ""
            }
            return dict
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
    @Published var branches: [PPInventoryBranchOption] = []
    @Published var searchText: String = ""
    @Published fileprivate var activeFilter: InventoryFilter = .all
    @Published var activeTab: CatalogHorizonTab
    @Published private(set) var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var selectedItemForDossier: PetAccessory? = nil

    private var listener: AnyObject?
    private var branchInventoryCancellable: AnyCancellable?
    private var pendingQuantityDeltas: [String: Int] = [:]
    private var pendingDebounceWorkItems: [String: DispatchWorkItem] = [:]
    private var pendingDeletedIDs = Set<String>()

    func effectiveStock(for item: PetAccessory) -> Int {
        let activeBranch = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let activeBranch, !activeBranch.isEmpty {
            if let branchRecord = PPBranchInventoryService.shared.inventory(for: item.accessoryID) {
                return branchRecord.availableQuantity
            }
            let itemBranch = (item.storeID ?? item.branchID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !itemBranch.isEmpty && itemBranch != "main_store" && itemBranch != activeBranch {
                return 0
            }
        }
        return PPBranchInventoryService.shared.availableStock(for: item.accessoryID, fallback: item.quantity)
    }

    var totalCount: Int { allItems.count }
    var inStockCount: Int { allItems.filter { effectiveStock(for: $0) > 0 && !$0.noStock }.count }
    var lowStockCount: Int { allItems.filter { let q = effectiveStock(for: $0); return q > 0 && q <= 3 && !$0.noStock }.count }
    var outOfStockCount: Int { allItems.filter { effectiveStock(for: $0) <= 0 || $0.noStock }.count }
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
            let price = PPBranchInventoryService.shared.effectiveSellingPrice(for: item.accessoryID, fallbackPrice: item.finalPrice.doubleValue)
            return sum + (price * Double(max(0, effectiveStock(for: item))))
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

        branchInventoryCancellable = PPBranchInventoryService.shared.$inventoryMap
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.applyFilter()
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
        Task { [weak self] in
            if let loaded = try? await PPLivePetInventoryService.listBranches() {
                await MainActor.run {
                    self?.branches = loaded
                }
            }
        }
        listener = AccessoryManager.shared().observeAccessories(of: currentKind) { [weak self] items, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.allItems = (items ?? []).filter { item in
                    !item.isDeleted && !self.pendingDeletedIDs.contains(item.accessoryID)
                }.sorted { a, b in
                    let dateA = a.createdAt
                    let dateB = b.createdAt
                    if dateA != dateB {
                        return dateA > dateB
                    }
                    return a.accessoryID > b.accessoryID
                }
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
            if item.isDeleted || pendingDeletedIDs.contains(item.accessoryID) { return false }
            let stock = effectiveStock(for: item)
            switch activeFilter {
            case .all:
                break
            case .inStock:
                if stock <= 0 || item.noStock { return false }
            case .lowStock:
                if stock <= 0 || stock > 3 || item.noStock { return false }
            case .outOfStock:
                if stock > 0 && !item.noStock { return false }
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
            let branchName = item.resolvedBranchName().lowercased()
            let branchCode = (item.branchCode ?? "").lowercased()
            let docID = item.accessoryID.lowercased()
            let sku = (item.sku ?? "").lowercased()
            let barcode = (item.barcode ?? "").lowercased()
            return name.contains(query) || desc.contains(query) || searchTitle.contains(query) || store.contains(query) || branchName.contains(query) || branchCode.contains(query) || docID.contains(query) || sku.contains(query) || barcode.contains(query)
        }

        result.sort { a, b in
            let dateA = a.createdAt
            let dateB = b.createdAt
            if dateA != dateB {
                return dateA > dateB
            }
            return a.accessoryID > b.accessoryID
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
                    self?.allItems = (items ?? []).filter { item in
                        !item.isDeleted && !(self?.pendingDeletedIDs.contains(item.accessoryID) ?? false)
                    }.sorted { a, b in
                        let dateA = a.createdAt
                        let dateB = b.createdAt
                        if dateA != dateB {
                            return dateA > dateB
                        }
                        return a.accessoryID > b.accessoryID
                    }
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

            if let branchId = BranchContextStore.shared.activeBranch?.branchID, !branchId.isEmpty {
                PPBranchInventoryService.shared.adjustStock(
                    productId: docID,
                    branchId: branchId,
                    delta: batchedDelta,
                    type: batchedDelta > 0 ? "purchase" : "adjustment",
                    referenceId: "admin_inventory_list",
                    reason: "manual_adjustment",
                    notes: "Adjusted from admin inventory list"
                ) { [weak self] result in
                    if case .failure(let error) = result {
                        DispatchQueue.main.async {
                            item.quantity -= batchedDelta
                            if item.quantity <= 0 {
                                item.quantity = 0
                                item.noStock = true
                            }
                            self?.objectWillChange.send()
                            let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                            PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: message)
                        }
                    }
                }
            } else {
                AccessoryManager.shared().adjustQuantity(by: batchedDelta, forAccessoryID: docID) { [weak self] error in
                    if let error = error {
                        DispatchQueue.main.async {
                            item.quantity -= batchedDelta
                            if item.quantity <= 0 {
                                item.quantity = 0
                                item.noStock = true
                            }
                            self?.objectWillChange.send()
                            let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                            PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: message)
                        }
                    }
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
        }
        objectWillChange.send()
        applyFilter()

        AccessoryManager.shared().setNoStock(item.noStock, forAccessoryID: docID) { _ in }
        AccessoryManager.shared().updateQuantity(item.quantity, forAccessoryID: docID) { error in
            if let error = error {
                DispatchQueue.main.async {
                    let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: message)
                }
            }
        }

        if let branchId = BranchContextStore.shared.activeBranch?.branchID, !branchId.isEmpty {
            let currentBranchStock = PPBranchInventoryService.shared.availableStock(for: docID, fallback: item.quantity)
            if newNoStock && currentBranchStock > 0 {
                PPBranchInventoryService.shared.adjustStock(
                    productId: docID,
                    branchId: branchId,
                    delta: -currentBranchStock,
                    type: "adjustment",
                    referenceId: "admin_toggle_stock",
                    reason: "marked_no_stock",
                    notes: "Marked out of stock from inventory list"
                ) { result in
                    if case .failure(let error) = result {
                        DispatchQueue.main.async {
                            let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                            PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: message)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Delete & Status Operations

    func deleteAccessory(_ item: PetAccessory) {
        let docID = item.accessoryID
        guard !docID.isEmpty else { return }

        // Optimistically remove from view model immediately so the card disappears at once
        pendingDeletedIDs.insert(docID)
        allItems.removeAll { $0.accessoryID == docID }
        filteredItems.removeAll { $0.accessoryID == docID }
        applyFilter()
        objectWillChange.send()

        PPHUD.showIndeterminate(in: nil, title: Language.get("Deleting", alter: "جاري الحذف..."), subtitle: nil)
        if item.isLivePet {
            Task { @MainActor in
                do {
                    _ = try await PPLivePetInventoryService.callInventory(
                        action: "delete",
                        productID: docID,
                        payload: ["reason": "admin_ios_soft_delete"]
                    )
                    // Also soft-delete linked live-pet marketplace ad if present
                    let db = Firestore.firestore()
                    try? await db.collection("pet_ads").document("ad_live_\(docID)").setData([
                        "status": 0,
                        "visibility": 1,
                        "isDeleted": true,
                        "updatedAt": FieldValue.serverTimestamp()
                    ], merge: true)

                    PPHUD.dismiss()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    PPHUD.showSuccess(
                        Language.get("Deleted", alter: "تم الحذف بنجاح"),
                        subtitle: Language.get("StockUpdated", alter: "تم تحديث المخزون")
                    )
                } catch {
                    self.pendingDeletedIDs.remove(docID)
                    Task { await self.refresh() }
                    PPHUD.dismiss()
                    PPHUD.showError(
                        Language.get("Error", alter: "خطأ"),
                        subtitle: PPLivePetInventoryService.localizedMessage(for: error)
                    )
                }
            }
            return
        }
        AccessoryManager.shared().deleteAccessory(withID: docID) { [weak self] error in
            PPHUD.dismiss()
            if let error = error {
                DispatchQueue.main.async {
                    self?.pendingDeletedIDs.remove(docID)
                    Task { await self?.refresh() }
                    PPHUD.showError(Language.get("Error", alter: nil), subtitle: error.localizedDescription)
                }
            } else {
                DispatchQueue.main.async {
                    self?.allItems.removeAll { $0.accessoryID == docID }
                    self?.filteredItems.removeAll { $0.accessoryID == docID }
                    self?.applyFilter()
                    self?.objectWillChange.send()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    PPHUD.showSuccess(Language.get("Deleted", alter: "تم الحذف بنجاح"), subtitle: Language.get("StockUpdated", alter: "تم تحديث المخزون"))
                }
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

@available(iOS 16.0, *)
@MainActor
public struct PPInventoryListView: View {
    @StateObject private var viewModel: PPInventoryListViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let onPushViewController: (UIViewController) -> Void
    private let onDismiss: (() -> Void)?
    private let showsCatalogSwitcher: Bool

    @State private var spinAngle: Double = 0
    @FocusState private var isSearchFocused: Bool
    @State private var showingBranchSwitcherSheet: Bool = false

    public init(
        kind: AccessKindType = .typeAccessory,
        showsCatalogSwitcher: Bool = true,
        onPushViewController: @escaping (UIViewController) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PPInventoryListViewModel(kind: kind))
        self.showsCatalogSwitcher = showsCatalogSwitcher
        self.onPushViewController = onPushViewController
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geometry in
            let isRegular = geometry.size.width >= 760

            ZStack(alignment: .top) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    sovereignHeaderBar
                        .frame(maxWidth: isRegular ? 980 : .infinity)
                        .frame(maxWidth: .infinity)

                    PPAdminBranchSwitcherBar(style: .compact)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.vertical, 4)
                        .frame(maxWidth: isRegular ? 980 : .infinity)
                        .frame(maxWidth: .infinity)

                    if showsCatalogSwitcher {
                        catalogHorizonSwitcher
                            .frame(maxWidth: isRegular ? 980 : .infinity)
                            .frame(maxWidth: .infinity)
                    }

                    if viewModel.isLoading && viewModel.allItems.isEmpty {
                        ScrollView(.vertical, showsIndicators: false) {
                            loadingSkeletonView
                                .padding(.horizontal, AdminSpacing.screenMargin)
                                .padding(.top, 10)
                                .padding(.bottom, 64)
                                .frame(maxWidth: isRegular ? 980 : .infinity)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.allItems.isEmpty {
                        flagshipCatalogEmptyStateView(isRegular: isRegular)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                apexTelemetryRadar
                                searchAndFilterMatrix

                                if viewModel.filteredItems.isEmpty {
                                    filterEmptyStateCard
                                } else {
                                    itemsListSection
                                }
                            }
                            .padding(.horizontal, AdminSpacing.screenMargin)
                            .padding(.top, 10)
                            .padding(.bottom, 64)
                            .frame(maxWidth: isRegular ? 980 : .infinity)
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .refreshable {
                            await viewModel.refresh()
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showingBranchSwitcherSheet) {
            PPBranchSelectionGateView()
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
    }

    private func confirmDelete(item: PetAccessory) {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Confirm Delete", alter: "تأكيد حذف المنتج"),
            subtitle: Language.get("Are you sure you want to delete this accessory?", alter: "هل أنت متأكد من رغبتك في حذف هذا المنتج نهائياً من قاعدة بيانات المخزون؟"),
            confirmButton: Language.get("Delete", alter: "حذف نهائي من المخزون"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.deleteAccessory(item)
            },
            cancelBlock: nil
        )
    }

    // MARK: - Sovereign Header Bar

    private var sovereignHeaderBar: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            AdminSovereignNavigationBar(
                title: viewModel.navigationTitle,
                subtitle: (Language.get("CommandCenter_Work_Workspace", alter: "مساحة المخزون") + (viewModel.totalCount > 0 ? " • " + String(format: Language.get("Total_Items_Format", alter: "%@ صنف مسجل"), viewModel.totalCount.englishDigits) : "")).normalizedEnglishDigits,
                statusDotColor: Color(uiColor: .ppSuccess),
                onBack: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let onDismiss = onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                        PPAdminNavigationFallback.popOrDismiss()
                    }
                }
            ) {
                AdminPrimaryPillButton(
                    title: Language.get("Add", alter: "إضافة منتج"),
                    systemImage: "plus"
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let addVC = AddAccessoryViewController(accessory: nil)
                    addVC.showTypeRow = false
                    addVC.defaultKind = viewModel.currentKind
                    onPushViewController(addVC)
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.startListening() }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 4)
            }
        }
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
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
                        Text(verbatim: String(format: Language.get("Inventory_Valuation_Format", alter: "القيمة الإجمالية للمخزون: %.2f ر.ق"), viewModel.totalValuation).normalizedEnglishDigits)
                            .font(AdminType.caption1)
                            .foregroundColor(AdminCommandInk.secondary)
                    }

                    if viewModel.unpricedItemsCount > 0 {
                        Label {
                            Text(verbatim:
                                String(
                                    format: Language.get(
                                        "Inventory_Unpriced_Items_Format",
                                        alter: "لم يُحدَّد سعر البيع لعدد %@ من الأصناف. لا تشملها قيمة المخزون."
                                    ),
                                    viewModel.unpricedItemsCount.englishDigits
                                ).normalizedEnglishDigits
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

            // 4-Tile Telemetry Deck (Adaptive with ViewThatFits for small screens)
            ViewThatFits(in: .horizontal) {
                // Primary: 4-tile single row (Standard iPhone & iPad)
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

                // Fallback: 2x2 grid for compact widths / high dynamic type
                VStack(spacing: 8) {
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
                    }
                    HStack(spacing: 8) {
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
                }
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
                Text(verbatim: count.englishDigits)
                    .font(PPBrandFont.bold(size: 18))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.80)
            }
            Text(title)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
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
                Text(verbatim: String(format: Language.get("Inventory_Available_Ratio", alter: "نسبة التوفر: %.0f%%"), (CGFloat(viewModel.inStockCount) / CGFloat(total)) * 100.0).normalizedEnglishDigits)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.tertiary)
                Spacer()
                Text(verbatim: String(format: Language.get("Inventory_Showing_Count", alter: "%@ معروض"), viewModel.filteredItems.count.englishDigits).normalizedEnglishDigits)
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

                AdminBarcodeScanButton { scanned in
                    viewModel.searchText = scanned
                    isSearchFocused = false
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

                                Text(verbatim: count.englishDigits)
                                    .font(PPBrandFont.bold(size: 11))
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

    @ViewBuilder
    private var itemsListSection: some View {
        ForEach(viewModel.filteredItems, id: \.accessoryID) { item in
            FlagshipInventoryCard(
                item: item,
                onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let detailVC = PPInventoryItemDetailHostingController(
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
                        },
                        onAdjustQuantity: { delta in
                            viewModel.adjustQuantity(by: delta, for: item)
                        },
                        onToggleStock: {
                            viewModel.toggleStockAvailability(for: item)
                        },
                        onDelete: {
                            viewModel.deleteAccessory(item)
                        }
                    )
                    onPushViewController(detailVC)
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
                    confirmDelete(item: item)
                }
            )
        }
    }

    // MARK: - Flagship Empty State View (Zero Catalog Items)

    @ViewBuilder
    private func flagshipCatalogEmptyStateView(isRegular: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer(minLength: 28)

                // Concentric Aura Squircle Deck
                ZStack {
                    // Outermost ambient glow halo
                    Circle()
                        .fill(catalogTabThemeColor.opacity(0.09))
                        .frame(width: 140, height: 140)
                        .scaleEffect(reduceMotion ? 1.0 : 1.04)

                    // Secondary ring contour
                    Circle()
                        .stroke(catalogTabThemeColor.opacity(0.20), lineWidth: 1.5)
                        .frame(width: 110, height: 110)

                    // Core Gradient Squircle Monolith
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    catalogTabThemeColor,
                                    catalogTabThemeColor.opacity(0.80)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 78, height: 78)
                        .shadow(color: catalogTabThemeColor.opacity(0.32), radius: 16, x: 0, y: 8)

                    // Symbol Icon
                    Image(systemName: catalogTabEmptyIcon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white)

                    // Elevated Micro-Badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.white)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(catalogTabThemeColor)
                                )
                                .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                                .offset(x: Language.isRTL() ? -6 : 6, y: 4)
                        }
                    }
                    .frame(width: 78, height: 78)
                }
                .padding(.top, 12)

                // Branch Context Pill
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 7, height: 7)
                        .shadow(color: Color(uiColor: .ppSuccess).opacity(0.8), radius: 3, x: 0, y: 0)

                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdminSurface.primary)

                    Text(activeBranchLabelText)
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(AdminSurface.surface)
                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.75)
                )

                // Beiruti Typographic Hierarchy
                VStack(spacing: 10) {
                    Text(catalogTabEmptyTitle)
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text(catalogTabEmptySubtitle)
                        .font(AdminType.callout)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Command Horizon Action Buttons
                VStack(spacing: 12) {
                    // Primary Action Button: Add Item
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let addVC = AddAccessoryViewController(accessory: nil)
                        addVC.showTypeRow = false
                        addVC.defaultKind = viewModel.currentKind
                        onPushViewController(addVC)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                            Text(catalogTabAddButtonTitle)
                                .font(AdminType.bodyBold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.90)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.28), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(CatalogPressStyle())

                    // Secondary Action Horizon: Switch Branch & Refresh
                    HStack(spacing: 10) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showingBranchSwitcherSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(Language.get("SwitchBranch_Action", alter: "تبديل الفرع"))
                                    .font(AdminType.captionBold)
                            }
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AdminSurface.control)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
                            )
                        }
                        .buttonStyle(CatalogPressStyle())

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Task {
                                await viewModel.refresh()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(Language.get("Sync_Inventory_Action", alter: "تحديث السحابة"))
                                    .font(AdminType.captionBold)
                            }
                            .foregroundColor(AdminSurface.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AdminSurface.primary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AdminSurface.primary.opacity(0.2), lineWidth: 0.75)
                            )
                        }
                        .buttonStyle(CatalogPressStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)

                // Feature Badges
                HStack(spacing: 10) {
                    featureBadge(
                        icon: "shippingbox.and.arrow.backward.fill",
                        text: Language.get("Instant_Stock_Control", alter: "مخزون لحظي")
                    )
                    featureBadge(
                        icon: "tag.circle.fill",
                        text: Language.get("Branch_Pricing_Control", alter: "تسعير مخصص")
                    )
                    featureBadge(
                        icon: "bolt.shield.fill",
                        text: Language.get("Secure_Cloud_Sync", alter: "مزامنة سحابية")
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: isRegular ? 640 : .infinity)
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Filter / Search Empty State Card

    private var filterEmptyStateCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 58, height: 58)

                Image(systemName: viewModel.searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(Language.get("Inventory_No_Filter_Matches", alter: "لا توجد نتائج مطابقة للبحث أو التصفية"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                if !viewModel.searchText.isEmpty {
                    Text(String(format: Language.get("Inventory_No_Results_For_Query", alter: "لم نجد أي أصناف تطابق «%@». جرب البحث باسم آخر أو كود الصنف."), viewModel.searchText))
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                } else {
                    Text(Language.get("Inventory_No_Results_Filter_Hint", alter: "لا توجد عناصر تطابق الفلتر المحدد حالياً في هذا القسم."))
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.searchText = ""
                        viewModel.activeFilter = .all
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("ResetFilters", alter: "إعادة ضبط الفلاتر"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                }
                .buttonStyle(CatalogPressStyle())

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let addVC = AddAccessoryViewController(accessory: nil)
                    addVC.showTypeRow = false
                    addVC.defaultKind = viewModel.currentKind
                    onPushViewController(addVC)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Add", alter: "إضافة صنف جديد"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AdminSurface.primary, in: Capsule(style: .continuous))
                }
                .buttonStyle(CatalogPressStyle())
            }
            .padding(.bottom, 8)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75)
        )
    }

    // MARK: - Empty State Contextual Helpers

    private var catalogTabThemeColor: Color {
        switch viewModel.activeTab {
        case .food:
            return Color(red: 0.95, green: 0.60, blue: 0.12)
        case .livePets:
            return Color(red: 0.10, green: 0.74, blue: 0.52)
        case .accessories:
            return AdminSurface.primary
        }
    }

    private var catalogTabEmptyIcon: String {
        switch viewModel.activeTab {
        case .food:
            return "takeoutbag.and.cup.and.straw.fill"
        case .livePets:
            return "pawprint.fill"
        case .accessories:
            return "bag.fill"
        }
    }

    private var catalogTabEmptyTitle: String {
        switch viewModel.activeTab {
        case .food:
            return Language.get("Inventory_Food_Empty_Title", alter: "لا توجد أطعمة أو مكملات مسجلة")
        case .livePets:
            return Language.get("Inventory_LivePets_Empty_Title", alter: "لا توجد حيوانات حية مسجلة")
        case .accessories:
            return Language.get("Inventory_Accessories_Empty_Title", alter: "لا توجد إكسسوارات مسجلة")
        }
    }

    private var catalogTabEmptySubtitle: String {
        let branchName = BranchContextStore.shared.currentBranchDisplayName
        let hasBranch = !branchName.isEmpty && branchName != "main_store"
        switch viewModel.activeTab {
        case .food:
            return hasBranch
                ? String(format: Language.get("Inventory_Food_Empty_Subtitle_Branch", alter: "لم يتم تسجيل أي منتجات أطعمة أو مكملات في فرع «%@» حتى الآن. يمكنك إضافة صنف جديد فوراً."), branchName)
                : Language.get("Inventory_Food_Empty_Subtitle", alter: "لم يتم تسجيل أي منتجات أطعمة أو مكملات في قاعدة البيانات حتى الآن. ابدأ بإضافة الأصناف وتحديد التكلفة والأسعار.")
        case .livePets:
            return hasBranch
                ? String(format: Language.get("Inventory_LivePets_Empty_Subtitle_Branch", alter: "لا توجد حيوانات مسجلة في فرع «%@» حالياً. يمكنك إضافة حيوان جديد إلى السجل أو تبديل الفرع."), branchName)
                : Language.get("Inventory_LivePets_Empty_Subtitle", alter: "لا توجد حيوانات حية مسجلة في قاعدة البيانات حالياً. يمكنك إضافة حيوان جديد الآن وتوثيق بياناته.")
        case .accessories:
            return hasBranch
                ? String(format: Language.get("Inventory_Accessories_Empty_Subtitle_Branch", alter: "لم يتم إضافة أي إكسسوارات أو مستلزمات في فرع «%@». يمكنك إضافة أول صنف جديد الآن."), branchName)
                : Language.get("Inventory_Accessories_Empty_Subtitle", alter: "لم يتم تسجيل أي إكسسوارات في قاعدة البيانات حالياً. يمكنك الضغط على زر الإضافة لتسجيل أول صنف.")
        }
    }

    private var catalogTabAddButtonTitle: String {
        switch viewModel.activeTab {
        case .food:
            return Language.get("Inventory_Add_Food", alter: "+ إضافة طعام أو مكمل جديد")
        case .livePets:
            return Language.get("Inventory_Add_LivePet", alter: "+ إضافة حيوان جديد")
        case .accessories:
            return Language.get("Inventory_Add_Accessory", alter: "+ إضافة إكسسوار جديد")
        }
    }

    private var activeBranchLabelText: String {
        let name = BranchContextStore.shared.currentBranchDisplayName
        if !name.isEmpty && name != "main_store" {
            return String(format: Language.get("Inventory_Active_Branch_Pill", alter: "الفرع: %@"), name)
        }
        return Language.get("Inventory_All_Branches_Pill", alter: "جميع الفروع • نطاق عام")
    }

    private func featureBadge(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(catalogTabThemeColor)
            Text(text)
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(AdminSurface.control.opacity(0.85))
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

// MARK: - Flagship Category-Defining Inventory Specimen Monolith

// MARK: - Category Specimen Aura Theme Engine

private struct CategorySpecimenAuraTheme {
    let gradient: [Color]
    let glyphName: String
    let accentTint: Color
    let categoryName: String

    static func resolve(for item: PetAccessory) -> CategorySpecimenAuraTheme {
        // Live Pet Archetypes
        if item.isLivePet {
            let catName = MainKindsModel.kindName(forID: item.petMainCategoryID).lowercased()
            if catName.contains("طير") || catName.contains("طيور") || catName.contains("bird") {
                return CategorySpecimenAuraTheme(
                    gradient: [Color(red: 251/255, green: 146/255, blue: 60/255), Color(red: 234/255, green: 88/255, blue: 12/255)],
                    glyphName: "bird.fill",
                    accentTint: Color(red: 234/255, green: 88/255, blue: 12/255),
                    categoryName: Language.get("Birds", alter: "طيور")
                )
            } else if catName.contains("قط") || catName.contains("cat") {
                return CategorySpecimenAuraTheme(
                    gradient: [Color(red: 167/255, green: 139/255, blue: 250/255), Color(red: 124/255, green: 58/255, blue: 237/255)],
                    glyphName: "cat.fill",
                    accentTint: Color(red: 124/255, green: 58/255, blue: 237/255),
                    categoryName: Language.get("Cats", alter: "قطط")
                )
            } else if catName.contains("كلب") || catName.contains("كلاب") || catName.contains("dog") {
                return CategorySpecimenAuraTheme(
                    gradient: [Color(red: 52/255, green: 211/255, blue: 153/255), Color(red: 5/255, green: 150/255, blue: 105/255)],
                    glyphName: "dog.fill",
                    accentTint: Color(red: 5/255, green: 150/255, blue: 105/255),
                    categoryName: Language.get("Dogs", alter: "كلاب")
                )
            } else if catName.contains("سمك") || catName.contains("أسماك") || catName.contains("fish") {
                return CategorySpecimenAuraTheme(
                    gradient: [Color(red: 56/255, green: 189/255, blue: 248/255), Color(red: 2/255, green: 132/255, blue: 199/255)],
                    glyphName: "fish.fill",
                    accentTint: Color(red: 2/255, green: 132/255, blue: 199/255),
                    categoryName: Language.get("Aquatic", alter: "أسماك")
                )
            } else {
                return CategorySpecimenAuraTheme(
                    gradient: [Color(red: 244/255, green: 114/255, blue: 182/255), Color(red: 225/255, green: 29/255, blue: 72/255)],
                    glyphName: "pawprint.fill",
                    accentTint: Color(red: 225/255, green: 29/255, blue: 72/255),
                    categoryName: Language.get("LivePets", alter: "أليف")
                )
            }
        }

        // Food Archetype
        if item.isFood {
            return CategorySpecimenAuraTheme(
                gradient: [Color(red: 251/255, green: 191/255, blue: 36/255), Color(red: 217/255, green: 119/255, blue: 6/255)],
                glyphName: "takeoutbag.and.cup.and.straw.fill",
                accentTint: Color(red: 217/255, green: 119/255, blue: 6/255),
                categoryName: Language.get("Food", alter: "طعام")
            )
        }

        // Medicine Archetype
        if item.isPetMedicine {
            return CategorySpecimenAuraTheme(
                gradient: [Color(red: 45/255, green: 212/255, blue: 191/255), Color(red: 13/255, green: 148/255, blue: 136/255)],
                glyphName: "cross.case.fill",
                accentTint: Color(red: 13/255, green: 148/255, blue: 136/255),
                categoryName: Language.get("Medicine", alter: "صيدلية")
            )
        }

        // General Accessories Archetype
        let catDisplay = item.accessoryCategoryName ?? item.category ?? (item.petMainCategoryID > 0 ? (MainKindsModel.kindName(forID: item.petMainCategoryID) ?? "") : "")
        return CategorySpecimenAuraTheme(
            gradient: [Color(red: 96/255, green: 165/255, blue: 250/255), Color(red: 37/255, green: 99/255, blue: 235/255)],
            glyphName: "sparkles",
            accentTint: Color(red: 37/255, green: 99/255, blue: 235/255),
            categoryName: catDisplay.isEmpty ? Language.get("Accessory", alter: "إكسسوار") : catDisplay
        )
    }
}

// MARK: - Flagship Category-Defining Inventory Specimen Monolith

@available(iOS 16.0, *)
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

    private var displayQuantity: Int {
        let activeBranch = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let activeBranch, !activeBranch.isEmpty {
            if let branchRecord = PPBranchInventoryService.shared.inventory(for: item.accessoryID) {
                return branchRecord.availableQuantity
            }
            let itemBranch = (item.storeID ?? item.branchID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !itemBranch.isEmpty && itemBranch != "main_store" && itemBranch != activeBranch {
                return 0
            }
        }
        return PPBranchInventoryService.shared.availableStock(for: item.accessoryID, fallback: item.quantity)
    }

    private var stockTone: Color {
        let qty = displayQuantity
        if qty <= 0 || (item.noStock && !item.isLivePet) {
            return Color(uiColor: .ppError)
        } else if qty <= 3 {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppSuccess)
        }
    }

    private var stockStatusText: String {
        let qty = displayQuantity
        if (item.noStock && !item.isLivePet) || qty <= 0 {
            return Language.get("OutOfStock", alter: "نفذ من المخزون")
        } else if qty <= 3 {
            return String(format: Language.get("LowStock_Qty_Format", alter: "وشك النفاذ (%@)"), qty.englishDigits).normalizedEnglishDigits
        } else {
            return String(format: Language.get("InStock_Qty_Format", alter: "متوفر (%@)"), qty.englishDigits).normalizedEnglishDigits
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Main Specimen Presentation Chamber (Tappable Area)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            }) {
                HStack(alignment: .top, spacing: 14) {
                    // Visual Specimen Vitrine (88x88)
                    specimenVitrine

                    // Nomenclature, Runway & Valuation Track
                    VStack(alignment: .leading, spacing: 6) {
                        // Architectural Metadata Runway
                        architecturalMetadataRunway

                        // Specimen Nomenclature (Title)
                        Text(item.name)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 2)

                        // Financial Valuation Readout
                        financialValuationReadout
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CatalogPressStyle())

            // Tactical Horizon Negative-Space Divider
            Divider()
                .background(AdminSurface.hairline.opacity(0.65))

            // Integrated Tactical Horizon Cockpit
            tacticalHorizonCockpit
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.60), lineWidth: 0.75)
        )
        .contextMenu {
            Button(action: onEdit) {
                Label {
                    Text(Language.get("Edit", alter: "تعديل الصنف"))
                        .font(PPBrandFont.bold(size: 16))
                } icon: {
                    Image(systemName: "pencil")
                }
            }

            Button(action: {
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController {
                    PetAccessory.share(item, from: root)
                }
            }) {
                Label {
                    Text(Language.get("Share", alter: "مشاركة الصنف"))
                        .font(PPBrandFont.bold(size: 16))
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            if !item.isLivePet {
                Button(action: onToggleStock) {
                    Label {
                        Text(item.noStock ? Language.get("MarkInStock", alter: "تفعيل التوفر بالمخزون") : Language.get("MarkOutOfStock", alter: "تعيين كنفاذ المخزون"))
                            .font(PPBrandFont.bold(size: 16))
                    } icon: {
                        Image(systemName: item.noStock ? "checkmark.circle" : "xmark.circle")
                    }
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label {
                    Text(Language.get("Delete", alter: "حذف من المخزون"))
                        .font(PPBrandFont.bold(size: 16))
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    // MARK: - Architectural Metadata Runway

    private var architecturalMetadataRunway: some View {
        let aura = CategorySpecimenAuraTheme.resolve(for: item)
        let branchDisplayName = item.resolvedBranchName()
        let condText = PetAccessory.conditionText(for: item)

        return HStack(spacing: 5) {
            // Taxonomy Capsule with live tint
            HStack(spacing: 3.5) {
                Circle()
                    .fill(aura.accentTint)
                    .frame(width: 5, height: 5)
                Text(aura.categoryName)
                    .font(AdminType.caption2Bold)
                    .foregroundColor(aura.accentTint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(aura.accentTint.opacity(0.10), in: Capsule(style: .continuous))

            // Branch Beacon
            if !branchDisplayName.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "building.2")
                        .font(.system(size: 8))
                    Text(branchDisplayName)
                        .font(AdminType.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(AdminCommandInk.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(AdminSurface.control, in: Capsule(style: .continuous))
            }

            // Condition Tag (e.g. جديد / مستعمل)
            if !condText.isEmpty {
                Text(condText)
                    .font(AdminType.caption2Bold)
                    .foregroundColor(Color(red: 234/255, green: 88/255, blue: 12/255))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color(red: 234/255, green: 88/255, blue: 12/255).opacity(0.10), in: Capsule(style: .continuous))
                    .lineLimit(1)
            }

            // Package Weight Chip
            if let weight = item.weightText, !weight.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 8))
                    Text(weight)
                        .font(AdminType.caption2)
                }
                .foregroundColor(AdminCommandInk.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Financial Valuation Readout

    private var financialValuationReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: finalPriceFormatted.normalizedEnglishDigits)
                .font(AdminType.title3)
                .foregroundColor(item.hasResolvedSellingPrice ? AdminSurface.primary : Color(uiColor: .ppWarning))
                .monospacedDigit()

            if let original = originalPriceFormatted {
                Text(verbatim: original.normalizedEnglishDigits)
                    .font(AdminType.caption)
                    .foregroundColor(AdminCommandInk.tertiary)
                    .strikethrough()
            }

            if let wp = item.wholesalePrice?.doubleValue, wp > 0 {
                HStack(spacing: 3) {
                    Text(Language.get("Wholesale_Short", alter: "جملة:"))
                        .font(PPBrandFont.bold(size: 10))
                    Text(verbatim: "\(wp.englishDigits(decimals: 0)) \(Language.get("QAR", alter: "ر.ق"))")
                        .font(PPBrandFont.bold(size: 11))
                        .monospacedDigit()

                    // Margin intelligence readout
                    let fp = item.finalPrice.doubleValue
                    if fp > wp && fp > 0 {
                        let marginPercent = Int(round(((fp - wp) / fp) * 100.0))
                        Text(verbatim: "• \(marginPercent.englishDigits)%")
                            .font(PPBrandFont.bold(size: 10))
                            .foregroundColor(Color(uiColor: .systemTeal).opacity(0.85))
                    }
                }
                .foregroundColor(Color(uiColor: .systemTeal))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color(uiColor: .systemTeal).opacity(0.12), in: Capsule(style: .continuous))
            }
        }
    }

    // MARK: - Specimen Visual Vitrine (88x88)

    private var specimenVitrine: some View {
        ZStack(alignment: .topLeading) {
            // Artwork Vessel (Image or Procedural Aura)
            Group {
                if let imageURL = imageURL {
                    AdminRemoteImage(url: imageURL, contentMode: .fill, targetSize: CGSize(width: 88, height: 88)) {
                        ZStack {
                            AdminSurface.control
                            ProgressView()
                                .tint(AdminSurface.primary)
                        }
                        .frame(width: 88, height: 88)
                    }
                    .frame(width: 88, height: 88)
                    .clipped()
                } else {
                    proceduralAuraVitrine
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
            )

            // Dynamic Discount Ribbon
            if hasDiscount, let percent = item.discountPercent, percent.intValue > 0 {
                Text(verbatim: "-\(percent.intValue.englishDigits)%")
                    .font(PPBrandFont.bold(size: 10))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2.5)
                    .background(
                        LinearGradient(
                            colors: [Color(uiColor: .ppError), Color(red: 225/255, green: 29/255, blue: 72/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .shadow(color: Color(uiColor: .ppError).opacity(0.35), radius: 3, x: 0, y: 1.5)
                    .padding(5)
            }

            // Multi-Photo Stack Pip
            if item.imageURLsArray.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 7.5, weight: .bold))
                            Text(verbatim: item.imageURLsArray.count.englishDigits)
                                .font(PPBrandFont.bold(size: 8.5))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.65), in: Capsule(style: .continuous))
                        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                        .padding(5)
                    }
                }
            }
        }
        .frame(width: 88, height: 88)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var proceduralAuraVitrine: some View {
        let aura = CategorySpecimenAuraTheme.resolve(for: item)
        return ZStack {
            // Soft atmospheric ambient gradient
            LinearGradient(
                colors: [aura.gradient[0].opacity(0.18), aura.gradient[1].opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Inner soft luminous focal aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [aura.gradient[0].opacity(0.30), aura.gradient[1].opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 36
                    )
                )
                .frame(width: 56, height: 56)

            // Category Vector Archetype Glyph
            Image(systemName: aura.glyphName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: aura.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: aura.accentTint.opacity(0.3), radius: 4, y: 2)
        }
        .frame(width: 88, height: 88)
    }

    // MARK: - Integrated Tactical Horizon Cockpit

    private var tacticalHorizonCockpit: some View {
        HStack(alignment: .center, spacing: 8) {
            // Store Visibility Sentinel
            if !item.isLivePet {
                storeVisibilitySentinel
            }

            Spacer(minLength: 4)

            // Stepper or Live Pet Unit Registry
            if item.isLivePet {
                livePetRosterButton
            } else {
                quantumPrecisionStepper
            }
        }
    }

    private var storeVisibilitySentinel: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onToggleStock()
        }) {
            HStack(spacing: 5) {
                Image(systemName: item.noStock ? "eye.slash.fill" : "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))

                Text(item.noStock ? Language.get("HiddenFromCatalog", alter: "موقوف مؤقتاً") : Language.get("ActiveInCatalog", alter: "متاح بالمتجر"))
                    .font(AdminType.caption2Bold)
                    .lineLimit(1)
            }
            .foregroundColor(item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                (item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.09),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder((item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.24), lineWidth: 0.75)
            )
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityLabel(item.noStock ? Language.get("MarkInStock", alter: "تفعيل المخزون") : Language.get("MarkOutOfStock", alter: "تعطيل المخزون"))
    }

    private var livePetRosterButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(Language.get("LivePet_Manage_Units", alter: "سجل الحيوانات"))
                    .font(AdminType.captionBold)
                Text(verbatim: "(\(displayQuantity.englishDigits))")
                    .font(PPBrandFont.bold(size: 11))
                    .monospacedDigit()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(AdminSurface.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(AdminSurface.primary.opacity(0.22), lineWidth: 0.75)
            )
        }
        .buttonStyle(CatalogPressStyle())
    }

    private var quantumPrecisionStepper: some View {
        HStack(spacing: 0) {
            // Decrement (-)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(displayQuantity > 0 ? AdminSurface.primaryText : AdminCommandInk.tertiary.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CatalogPressStyle())
            .disabled(displayQuantity <= 0)

            // Tabular Count with Stock Vitality Tint & Rolling Transition
            HStack(spacing: 4) {
                Circle()
                    .fill(stockTone)
                    .frame(width: 5, height: 5)

                Text(verbatim: displayQuantity.englishDigits)
                    .font(PPBrandFont.bold(size: 14))
                    .monospacedDigit()
                    .foregroundColor(stockTone == Color(uiColor: .ppError) ? Color(uiColor: .ppError) : AdminSurface.primaryText)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 44)
            .frame(height: 36)
            .contentShape(Rectangle())
            .accessibilityLabel(stockStatusText)
            .onTapGesture {
                promptQuantityEdit()
            }

            // Increment (+)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onAdjustQuantity(1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CatalogPressStyle())
        }
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
        )
    }

    private func promptQuantityEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        PPAlertHelper.showTextPrompt(
            in: nil,
            title: Language.get("EditQuantity", alter: "تعديل الكمية"),
            subtitle: Language.get("EnterQuantityPrompt", alter: "أدخل كمية المخزون المتاحة لهذا الصنف"),
            placeholder: Language.get("Quantity", alter: "الكمية"),
            initialText: displayQuantity.englishDigits,
            confirmText: Language.get("Save", alter: "حفظ"),
            cancelText: Language.get("Cancel", alter: "إلغاء"),
            secureEntry: false,
            keyboardType: .numberPad
        ) { text in
            guard let text else { return }
            let normalized = text.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Int(normalized) {
                let sanitized = max(0, val)
                let delta = sanitized - displayQuantity
                if delta != 0 {
                    onAdjustQuantity(delta)
                }
            }
        }
    }
}

// MARK: - Flagship Item Master Detail Screen (Push Navigation)

@available(iOS 16.0, *)
public struct PPInventoryItemDetailView: View {
    let item: PetAccessory
    let viewModel: PPInventoryListViewModel?
    let onDismiss: () -> Void
    let onOpenFullEditor: () -> Void
    let onOpenPOS: () -> Void
    let onAdjustQuantity: ((Int) -> Void)?
    let onToggleStock: (() -> Void)?
    let onDelete: (() -> Void)?

    @ObservedObject private var branchInventory = PPBranchInventoryService.shared
    @StateObject private var liveModel: PPLivePetOperationsViewModel
    @State private var selectedImageIndex: Int = 0
    @State private var isDescriptionExpanded: Bool = false
    @State private var copiedField: String? = nil
    @State private var copiedTask: Task<Void, Never>? = nil
    @State private var hasAppeared: Bool = false
    @State private var isLightboxPresented: Bool = false
    @State private var currentQuantity: Int = 0
    @State private var showTransferSheet: Bool = false
    @State private var showBasicDataEditor: Bool = false
    @State private var activeCommandUnit: PPLivePetInventoryUnit? = nil
    @State private var showHistoryUnits: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(
        item: PetAccessory,
        viewModel: PPInventoryListViewModel? = nil,
        onDismiss: @escaping () -> Void,
        onOpenFullEditor: @escaping () -> Void,
        onOpenPOS: @escaping () -> Void,
        onAdjustQuantity: ((Int) -> Void)? = nil,
        onToggleStock: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onOpenFullEditor = onOpenFullEditor
        self.onOpenPOS = onOpenPOS
        self.onAdjustQuantity = onAdjustQuantity
        self.onToggleStock = onToggleStock
        self.onDelete = onDelete
        _liveModel = StateObject(wrappedValue: PPLivePetOperationsViewModel(item: item))
        let initialStock = PPBranchInventoryService.shared.availableStock(for: item.accessoryID, fallback: item.quantity)
        _currentQuantity = State(initialValue: initialStock)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            AdminSurface.background.ignoresSafeArea()

            // Dynamic Ambient Aura reacting to stock health
            ambientLuminousAura

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Top spacing clearance for floating apex bar
                    Color.clear.frame(height: 52)

                    // Flagship Hero Specimen Stage (Expansive Vessel with Carousel / Lightbox / 3D Emblems)
                    heroSpecimenStage

                    // Sovereign Nomenclature & Identification Deck (Title, Condition, Tracking, Interactive SKU Cryptopill)
                    sovereignIdentificationDeck

                    // Unified Commerce & Stock Velocity Engine (Valuation, Margins, Stock Gauge, Precision Stepper)
                    unifiedCommerceAndStockInstrument

                    // Specimen Telemetry Ribbon (Sculpted 2x2 Glass Grid: Branch, Condition, Weight, Category)
                    specimenTelemetryRibbon

                    // Specimen Narrative Deck (Typographic Description with Expandable Fold)
                    if !item.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        specimenNarrativeDeck
                    }

                    // Live Pet Lifecycle Operations Hub
                    if item.isLivePet {
                        livePetOperationsSection
                    }

                    // Bottom clearance for floating command dock
                    Color.clear.frame(height: 105)
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, AdminSpacing.base)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: accessibilityReduceMotion || hasAppeared ? 0 : 8)
            }

            // Persistent Floating Master Command Dock
            floatingMasterCommandDock

            // Floating Apex Navigation Bar
            VStack {
                apexNavigationBar
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 6)
                    .background(
                        LinearGradient(
                            colors: [
                                AdminSurface.background.opacity(0.98),
                                AdminSurface.background.opacity(0.85),
                                AdminSurface.background.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .top)
                    )
                Spacer()
            }

            // Sovereign Live Pet Specimen Action Portal Deck
            if let unit = activeCommandUnit {
                PPLivePetActionPortalDeck(
                    unit: unit,
                    liveModel: liveModel,
                    onDismiss: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            activeCommandUnit = nil
                        }
                    },
                    onSelectOperation: { op in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            activeCommandUnit = nil
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            liveModel.operation = op
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
                .zIndex(100)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if item.isLivePet && item.quantity > 0 {
                currentQuantity = item.quantity
            } else {
                currentQuantity = PPBranchInventoryService.shared.availableStock(for: item.accessoryID, fallback: item.quantity)
            }
            if accessibilityReduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.easeOut(duration: 0.28)) {
                    hasAppeared = true
                }
            }
        }
        .task {
            if item.isLivePet {
                await liveModel.load()
                if liveModel.mode == .individual {
                    let count = effectiveAvailableUnitsCount
                    currentQuantity = count
                    item.quantity = count
                    item.noStock = (count <= 0)
                }
            }
        }
        .onChange(of: liveModel.units) { updatedUnits in
            if let current = activeCommandUnit, let fresh = updatedUnits.first(where: { $0.id == current.id }) {
                activeCommandUnit = fresh
            }
            if item.isLivePet && liveModel.mode == .individual {
                let count = effectiveAvailableUnitsCount
                currentQuantity = count
                item.quantity = count
                item.noStock = (count <= 0)
            }
        }
        .sheet(item: $liveModel.operation) { operation in
            PPLivePetOperationSheet(context: operation, model: liveModel)
        }
        .sheet(isPresented: $isLightboxPresented) {
            specimenLightboxView
        }
        .sheet(isPresented: $showTransferSheet) {
            PPStockTransferSheet(
                item: item,
                currentBranchID: BranchContextStore.shared.activeBranch?.branchID ?? item.storeID ?? "main_store",
                availableQuantity: currentQuantity,
                branches: (viewModel?.branches.isEmpty == false ? viewModel?.branches : nil) ?? PPLivePetInventoryService.cachedBranches,
                onComplete: { newQuantity in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        currentQuantity = newQuantity
                        item.quantity = newQuantity
                        item.noStock = (newQuantity <= 0)
                    }
                    if let branchId = BranchContextStore.shared.activeBranch?.branchID {
                        branchInventory.updateAvailableStockLocally(
                            for: item.accessoryID,
                            branchId: branchId,
                            newQuantity: newQuantity
                        )
                    }
                    viewModel?.applyFilter()
                }
            )
        }
        .sheet(isPresented: $showBasicDataEditor) {
            PPLivePetBasicDataEditorView(item: item) { _ in
                viewModel?.applyFilter()
            }
        }
        .onChange(of: branchInventory.inventoryMap) { _ in
            if !item.isLivePet {
                let fresh = branchInventory.availableStock(for: item.accessoryID, fallback: currentQuantity)
                if currentQuantity != fresh {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        currentQuantity = fresh
                        item.quantity = fresh
                        item.noStock = (fresh <= 0)
                    }
                }
            }
        }
        .onChange(of: branchInventory.currentBranchId) { _ in
            if !item.isLivePet {
                let fresh = branchInventory.availableStock(for: item.accessoryID, fallback: item.quantity)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    currentQuantity = fresh
                    item.quantity = fresh
                    item.noStock = (fresh <= 0)
                }
            }
        }
    }

    private func promptQuantityEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        PPAlertHelper.showTextPrompt(
            in: nil,
            title: Language.get("EditQuantity", alter: "تعديل الكمية"),
            subtitle: Language.get("EnterQuantityPrompt", alter: "أدخل كمية المخزون المتاحة لهذا الصنف"),
            placeholder: Language.get("Quantity", alter: "الكمية"),
            initialText: "\(currentQuantity)",
            confirmText: Language.get("Save", alter: "حفظ"),
            cancelText: Language.get("Cancel", alter: "إلغاء"),
            secureEntry: false,
            keyboardType: .numberPad
        ) { text in
            guard let text else { return }
            let normalized = text.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Int(normalized) {
                setExactQuantity(val)
            }
        }
    }

    // MARK: - Dynamic Ambient Luminous Aura

    private var ambientLuminousAura: some View {
        VStack {
            RadialGradient(
                colors: [
                    stockTone.opacity(0.14),
                    AdminSurface.primary.opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 15,
                endRadius: 420
            )
            .frame(height: 420)
            .ignoresSafeArea()
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Apex Navigation Bar

    private var apexNavigationBar: some View {
        HStack(alignment: .center, spacing: 12) {
            AdminSquircleCloseButton {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("ItemDetails", alter: "تفاصيل الصنف"))
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(stockTone)
                        .frame(width: 6, height: 6)
                    Text(stockStatusText)
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(stockTone)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Quick Actions / Context Menu Jewel
            Menu {
                Button {
                    onOpenFullEditor()
                } label: {
                    Label(Language.get("Edit", alter: "تعديل الصنف"), systemImage: "pencil")
                }

                if item.isLivePet {
                    Button {
                        showBasicDataEditor = true
                    } label: {
                        Label(Language.get("LivePet_EditBasicData", alter: "تعديل البيانات الأساسية"), systemImage: "pencil.and.list.clipboard")
                    }
                }

                Button {
                    onOpenPOS()
                } label: {
                    Label(Language.get("LivePet_Open_POS", alter: "فتح في نقطة البيع"), systemImage: "cart.fill")
                }

                if !item.isLivePet {
                    if currentQuantity > 0 {
                        Button {
                            showTransferSheet = true
                        } label: {
                            Label(Language.get("Stock_Transfer_Action", alter: "نقل كمية إلى فرع آخر"), systemImage: "arrow.left.arrow.right")
                        }
                    }

                    Button {
                        toggleStockVisibility()
                    } label: {
                        Label(
                            item.noStock ? Language.get("MarkInStock", alter: "تفعيل التوفر بالمخزون") : Language.get("MarkOutOfStock", alter: "تعيين كنفاذ المخزون"),
                            systemImage: item.noStock ? "checkmark.circle" : "xmark.circle"
                        )
                    }
                }

                Button {
                    if let root = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows })
                        .first(where: { $0.isKeyWindow })?.rootViewController {
                        PetAccessory.share(item, from: root)
                    }
                } label: {
                    Label(Language.get("Share", alter: "مشاركة الصنف"), systemImage: "square.and.arrow.up")
                }

                Divider()

                Button(role: .destructive) {
                    promptDeleteConfirm()
                } label: {
                    Label(Language.get("Delete", alter: "حذف من المخزون"), systemImage: "trash")
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .accessibilityLabel(Language.get("MoreActions", alter: "إجراءات إضافية"))
        }
        .padding(.vertical, 4)
    }

    private func promptDeleteConfirm() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("DeleteConfirm_Title", alter: "تأكيد حذف الصنف"),
            subtitle: Language.get("DeleteConfirm_Message", alter: "هل أنت متأكد من حذف هذا الصنف من المخزون نهائياً؟"),
            confirmButton: Language.get("Delete", alter: "حذف"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                onDelete?()
            },
            cancelBlock: nil
        )
    }

    // MARK: - Flagship Hero Specimen Stage

    private var specimenImageURLs: [URL] {
        if let arr = item.imageURLsArray as? [String], !arr.isEmpty {
            return arr.compactMap { URL(string: $0) }
        } else if let arr = item.imageURLsArray as? [NSString], !arr.isEmpty {
            return arr.compactMap { URL(string: $0 as String) }
        }
        if let first = PetAccessory.firstImageURL(for: item) {
            return [first]
        }
        return []
    }

    private var heroSpecimenStage: some View {
        ZStack(alignment: .bottom) {
            if !specimenImageURLs.isEmpty {
                TabView(selection: $selectedImageIndex) {
                    ForEach(Array(specimenImageURLs.enumerated()), id: \.offset) { index, url in
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 700, height: 700)) {
                            placeholderSpecimenBox
                        }
                        .tag(index)
                        .frame(maxWidth: .infinity)
                        .frame(height: 230)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isLightboxPresented = true
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 230)
            } else {
                placeholderSpecimenBox
                    .frame(height: 230)
            }

            // Overlay Controls
            VStack {
                HStack {
                    // Live Availability Beacon Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(stockTone)
                            .frame(width: 8, height: 8)
                        Text(stockStatusText)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .foregroundStyle(stockTone)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(stockTone.opacity(0.35), lineWidth: 0.5))

                    Spacer()

                    // Fullscreen Lightbox Trigger
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isLightboxPresented = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(Language.get("InspectSpecimen", alter: "معاينة صورة الصنف"))
                }
                .padding(12)

                Spacer()

                // Carousel Indicator Dots
                if specimenImageURLs.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<specimenImageURLs.count, id: \.self) { idx in
                            Capsule()
                                .fill(selectedImageIndex == idx ? AdminSurface.primary : Color.white.opacity(0.55))
                                .frame(width: selectedImageIndex == idx ? 16 : 6, height: 5)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedImageIndex)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private var placeholderSpecimenBox: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AdminSurface.control,
                    AdminSurface.surface,
                    AdminSurface.primary.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .strokeBorder(AdminSurface.primary.opacity(0.06), lineWidth: 40)
                .frame(width: 220, height: 220)

            Circle()
                .strokeBorder(AdminSurface.primary.opacity(0.04), lineWidth: 20)
                .frame(width: 140, height: 140)

            VStack(spacing: 8) {
                Image(systemName: item.isLivePet ? "pawprint.fill" : "shippingbox.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AdminSurface.primary.opacity(0.7), AdminSurface.primary.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.15), radius: 8, x: 0, y: 4)

                Text(item.isLivePet ? Language.get("LivePetSpecimen", alter: "حيوان حي") : Language.get("AccessorySpecimen", alter: "مستلزم حيوانات"))
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundStyle(AdminCommandInk.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lightbox Specimen Gallery

    private var specimenLightboxView: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if !specimenImageURLs.isEmpty {
                    TabView(selection: $selectedImageIndex) {
                        ForEach(Array(specimenImageURLs.enumerated()), id: \.offset) { index, url in
                            AdminRemoteImage(url: url, contentMode: .fit) {
                                placeholderSpecimenBox
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page)
                } else {
                    placeholderSpecimenBox
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isLightboxPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.2), in: Circle())
                    }
                }
            }
        }
    }

    // MARK: - Sovereign Nomenclature & Identification Deck

    private var specimenIdentifierText: String {
        if let sku = item.sku, !sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sku
        }
        if let barcode = item.barcode, !barcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return barcode
        }
        return item.accessoryID
    }

    private var sovereignIdentificationDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Full Specimen Name
            Text(item.name)
                .font(Font.custom("Beiruti-Bold", size: 24))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // Smart Badge Cluster: Condition + Tracking Mode + Catalog Status
            HStack(spacing: 6) {
                let cond = PetAccessory.conditionText(for: item)
                if !cond.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                        Text(cond)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(AdminSurface.primary.opacity(0.22), lineWidth: 0.5))
                }

                // Tracking Mode Pill
                HStack(spacing: 4) {
                    Image(systemName: inventoryTrackingSymbol)
                        .font(.system(size: 9))
                    Text(inventoryTrackingTitle)
                        .font(Font.custom("Beiruti-Bold", size: 11))
                }
                .foregroundStyle(inventoryTrackingTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(inventoryTrackingTint.opacity(0.10), in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(inventoryTrackingTint.opacity(0.22), lineWidth: 0.5))

                // Catalog Active Status Pill
                HStack(spacing: 4) {
                    Image(systemName: item.noStock ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 9))
                    Text(item.noStock ? Language.get("HiddenFromCatalog", alter: "موقوف") : Language.get("VisibleInCatalog", alter: "معروض"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                }
                .foregroundStyle(item.noStock ? Color(uiColor: .ppWarning) : AdminSurface.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(AdminSurface.control, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.5))
            }

            // Interactive SKU/Barcode Cryptopill
            Button {
                copyToClipboard(specimenIdentifierText, field: "sku")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: copiedField == "sku" ? "checkmark.circle.fill" : "barcode.viewfinder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(copiedField == "sku" ? Color(uiColor: .ppSuccess) : AdminSurface.primary)

                    Text(copiedField == "sku" ? Language.get("Copied", alter: "تم النسخ بنجاح") : specimenIdentifierText)
                        .font(PPBrandFont.bold(size: 12))
                        .foregroundStyle(copiedField == "sku" ? Color(uiColor: .ppSuccess) : AdminSurface.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    if copiedField != "sku" {
                        Text(Language.get("TapToCopy", alter: "نسخ الكود"))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(copiedField == "sku" ? Color(uiColor: .ppSuccess).opacity(0.5) : AdminSurface.hairline, lineWidth: 0.75)
                )
            }
            .buttonStyle(CatalogPressStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.65), lineWidth: 0.75)
        )
    }

    // MARK: - Unified Commerce & Stock Velocity Instrument

    private var stockVelocityRatio: CGFloat {
        let qty = CGFloat(displayedQuantity)
        if qty <= 0 { return 0.0 }
        if qty >= 50 { return 1.0 }
        return max(0.12, qty / 50.0)
    }

    private var profitMarginInfo: (margin: Double, percent: Double)? {
        guard let wp = item.wholesalePrice?.doubleValue, wp > 0 else { return nil }
        let fp = item.finalPrice.doubleValue
        guard fp > wp else { return nil }
        let margin = fp - wp
        let pct = (margin / fp) * 100
        return (margin, pct)
    }

    private var unifiedCommerceAndStockInstrument: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Valuation Wing (Leading)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("Price", alter: "السعر"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.inventoryDisplayPrice.normalizedEnglishDigits)
                            .font(PPBrandFont.bold(size: 28))
                            .foregroundStyle(AdminSurface.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        if let orig = originalPriceFormatted {
                            HStack(spacing: 6) {
                                Text(verbatim: orig.normalizedEnglishDigits)
                                    .font(PPBrandFont.regular(size: 12))
                                    .strikethrough()
                                    .foregroundStyle(AdminCommandInk.tertiary)
                                if let percent = item.discountPercent, percent.intValue > 0 {
                                    Text(verbatim: "-\(percent.intValue.englishDigits)%")
                                        .font(PPBrandFont.bold(size: 10))
                                        .foregroundStyle(Color(uiColor: .ppError))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color(uiColor: .ppError).opacity(0.12), in: Capsule())
                                }
                            }
                        } else {
                            Text(Language.get("LivePetDossier_PriceDetail", alter: "سعر البيع المعروض"))
                                .font(Font.custom("Beiruti-Regular", size: 11))
                                .foregroundStyle(AdminCommandInk.tertiary)
                                .lineLimit(1)
                        }
                    }

                    // Wholesale and Margin Telemetry
                    if let wp = item.wholesalePrice?.doubleValue, wp > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 10))
                                Text(verbatim: String(format: Language.get("Wholesale_Price_Format", alter: "جملة: %.2f ر.ق"), wp).normalizedEnglishDigits)
                                    .font(PPBrandFont.bold(size: 12))
                            }
                            .foregroundStyle(Color(uiColor: .systemTeal))

                            if let margin = profitMarginInfo {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(verbatim: String(format: "+%.2f ر.ق (%.0f%%)", margin.margin, margin.percent).normalizedEnglishDigits)
                                        .font(PPBrandFont.bold(size: 11))
                                }
                                .foregroundStyle(Color(uiColor: .ppSuccess))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // Subtle vertical dividing separator
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // Stock Velocity Wing (Trailing)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: item.isLivePet ? "pawprint.fill" : "shippingbox.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(stockTone)
                        Text(Language.get("Quantity", alter: "الكمية"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        if let activeBranch = BranchContextStore.shared.activeBranch {
                            Text(verbatim: (activeBranch.code.isEmpty ? activeBranch.localizedName() : activeBranch.code).normalizedEnglishDigits)
                                .font(PPBrandFont.bold(size: 10))
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: displayedQuantity.englishDigits)
                            .font(PPBrandFont.bold(size: 28))
                            .foregroundStyle(stockTone)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !item.isLivePet {
                                    promptQuantityEdit()
                                }
                            }

                        // Stock Velocity Gauge Line
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(stockTone.opacity(0.16))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(stockTone)
                                    .frame(width: max(8, geo.size.width * stockVelocityRatio), height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text(verbatim: stockStatusText.normalizedEnglishDigits)
                            .font(PPBrandFont.bold(size: 11))
                            .foregroundStyle(stockTone)
                            .lineLimit(1)
                    }

                    // Precision Stepper
                    if !item.isLivePet {
                        HStack(spacing: 0) {
                            Button {
                                adjustQuantity(-1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(currentQuantity > 0 ? AdminSurface.primaryText : AdminCommandInk.tertiary.opacity(0.4))
                                    .frame(width: 36, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(CatalogPressStyle())
                            .disabled(currentQuantity <= 0)

                            Text(verbatim: currentQuantity.englishDigits)
                                .font(PPBrandFont.bold(size: 14))
                                .foregroundStyle(AdminSurface.primaryText)
                                .frame(minWidth: 32)
                                .multilineTextAlignment(.center)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    promptQuantityEdit()
                                }

                            Button {
                                adjustQuantity(1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .frame(width: 36, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(CatalogPressStyle())
                        }
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            // Branch Transfer Bar (if stock available & non-live pet)
            if !item.isLivePet && currentQuantity > 0 {
                Button {
                    showTransferSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("Stock_Transfer_Action", alter: "نقل كمية إلى فرع آخر"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                        Spacer()
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(CatalogPressStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Specimen Telemetry Ribbon

    private var specimenTelemetryRibbon: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                telemetryTile(
                    title: Language.get("Store", alter: "المتجر والفرع"),
                    value: item.resolvedBranchName().isEmpty ? Language.get("MainStore", alter: "المتجر الرئيسي") : item.resolvedBranchName(),
                    icon: "building.2.fill",
                    tint: Color(uiColor: .systemIndigo)
                )
                telemetryTile(
                    title: Language.get("Condition", alter: "الحالة والضمان"),
                    value: PetAccessory.conditionText(for: item).isEmpty ? Language.get("OriginalCondition", alter: "أصلي ومضمون") : PetAccessory.conditionText(for: item),
                    icon: "checkmark.seal.fill",
                    tint: Color(uiColor: .ppSuccess)
                )
            }

            HStack(spacing: 10) {
                telemetryTile(
                    title: Language.get("Weight", alter: "الوزن والمواصفة"),
                    value: item.weightText?.isEmpty == false ? item.weightText! : Language.get("StandardUnit", alter: "وحدة قياسية"),
                    icon: "scalemass.fill",
                    tint: Color(uiColor: .systemOrange)
                )
                telemetryTile(
                    title: Language.get("Category", alter: "القسم والتصنيف"),
                    value: item.accessoryCategoryID?.isEmpty == false ? item.accessoryCategoryID! : PetAccessory.typeText(for: item),
                    icon: "folder.fill",
                    tint: AdminSurface.primary
                )
            }
        }
    }

    private func telemetryTile(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Specimen Narrative Deck

    private var specimenNarrativeDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Description", alter: "الوصف والتفاصيل"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer()
            }

            Text(item.desc)
                .font(Font.custom("Beiruti-Regular", size: 14))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if item.desc.count > 90 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isDescriptionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isDescriptionExpanded ? Language.get("ShowLess", alter: "عرض أقل") : Language.get("ShowMore", alter: "قراءة المزيد"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                        Image(systemName: isDescriptionExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Floating Master Command Dock

    private var floatingMasterCommandDock: some View {
        HStack(spacing: 12) {
            // Primary POS FastSell Button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpenPOS()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Image(systemName: "cart.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(Language.get("LivePet_Open_POS", alter: "فتح نقطة البيع"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(.white)

                    Spacer(minLength: 4)

                    // Final display price tag pill
                    Text(item.inventoryDisplayPrice)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: AdminSurface.primary.opacity(0.32), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(CatalogPressStyle())
            .accessibilityLabel(Language.get("LivePet_Open_POS", alter: "فتح في نقطة البيع"))

            // Secondary Full Editor Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenFullEditor()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .bold))
                    Text(Language.get("Edit", alter: "تعديل"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(AdminSurface.primary)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AdminSurface.primary.opacity(0.24), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(CatalogPressStyle())
            .accessibilityLabel(Language.get("EditFullDetails", alter: "فتح محرر البيانات الكامل"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 10)
    }

    // MARK: - State Helpers

    private var originalPriceFormatted: String? {
        guard let percent = item.discountPercent, percent.intValue > 0,
              item.price.doubleValue > 0 else {
            return nil
        }
        return PetAccessory.formatCurrency(item.price)
    }

    private var effectiveAvailableUnitsCount: Int {
        let activeBranch = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        return liveModel.units.filter { unit in
            guard unit.status == "AVAILABLE" else { return false }
            if let activeBranch, !activeBranch.isEmpty {
                let unitBranch = unit.currentBranchID.isEmpty ? (item.resolvedBranchID() ?? item.storeID ?? "") : unit.currentBranchID
                return unitBranch.isEmpty || unitBranch == "main_store" || unitBranch == activeBranch
            }
            return true
        }.count
    }

    private var displayedQuantity: Int {
        if item.isLivePet && liveModel.mode == .individual {
            if !liveModel.units.isEmpty || !liveModel.isLoading {
                return effectiveAvailableUnitsCount
            }
        }
        return branchInventory.availableStock(for: item.accessoryID, fallback: currentQuantity)
    }

    private var stockTone: Color {
        let qty = displayedQuantity
        if qty <= 0 || (item.noStock && !item.isLivePet) {
            return Color(uiColor: .ppError)
        } else if qty <= 3 {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppSuccess)
        }
    }

    private var stockStatusText: String {
        let qty = displayedQuantity
        if item.noStock && !item.isLivePet {
            return Language.get("HiddenFromCatalog", alter: "موقوف مؤقتاً")
        } else if qty <= 0 {
            return Language.get("OutOfStock", alter: "نفذ من المخزون")
        } else if qty <= 3 {
            return Language.get("LowStock", alter: "وشك النفاذ")
        } else {
            return Language.get("InStock", alter: "متوفر بالمخزون")
        }
    }

    private func copyToClipboard(_ text: String, field: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copiedTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            copiedField = field
        }
        copiedTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                if copiedField == field {
                    copiedField = nil
                }
            }
        }
    }

    private func adjustQuantity(_ delta: Int) {
        let newQty = max(0, currentQuantity + delta)
        guard newQty != currentQuantity else { return }
        let effectiveDelta = newQty - currentQuantity
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        currentQuantity = newQty
        item.quantity = newQty
        if newQty == 0 {
            item.noStock = true
        } else if item.noStock && effectiveDelta > 0 {
            item.noStock = false
        }
        if let onAdjust = onAdjustQuantity {
            onAdjust(effectiveDelta)
        } else if let vm = viewModel {
            vm.adjustQuantity(by: effectiveDelta, for: item)
        } else {
            if let branchId = BranchContextStore.shared.activeBranch?.branchID, !branchId.isEmpty {
                PPBranchInventoryService.shared.adjustStock(
                    productId: item.accessoryID,
                    branchId: branchId,
                    delta: effectiveDelta,
                    type: effectiveDelta > 0 ? "purchase" : "adjustment",
                    referenceId: "admin_item_detail",
                    reason: "detail_view_stepper",
                    notes: "Adjusted from detail view stepper"
                ) { result in
                    if case .failure(let error) = result {
                        DispatchQueue.main.async {
                            let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                            PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: message)
                        }
                    }
                }
            } else {
                AccessoryManager.shared().adjustQuantity(by: effectiveDelta, forAccessoryID: item.accessoryID) { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                            PPHUD.showError(Language.get("Error", alter: "خطأ"), subtitle: message)
                        }
                    }
                }
            }
        }
    }

    private func setExactQuantity(_ targetQty: Int) {
        let sanitized = max(0, targetQty)
        let delta = sanitized - currentQuantity
        guard delta != 0 else { return }
        adjustQuantity(delta)
    }

    private func toggleStockVisibility() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            item.noStock.toggle()
        }
        onToggleStock?()
    }

    // MARK: - Live-Pet Operations Section

    private var livePetOperationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            livePetCommandHeader

            if let success = liveModel.successMessage {
                dossierStateNotice(
                    success,
                    symbol: "checkmark.circle.fill",
                    tone: Color(uiColor: .ppSuccess)
                )
            }
            if let error = liveModel.errorMessage {
                dossierStateNotice(
                    error,
                    symbol: "exclamationmark.triangle.fill",
                    tone: Color(uiColor: .ppError)
                )
            }

            if liveModel.mode == nil {
                legacyTrackingDecision
            } else {
                livePetPrimaryCommands
                archiveCatalogCommand

                if liveModel.mode == .quantity {
                    groupReconciliationCommand
                } else if liveModel.mode == .individual {
                    individualAnimalLedger
                }
            }

            if liveModel.canViewReservations && !liveModel.reservations.isEmpty {
                activeReservationsLedger
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var livePetCommandHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.12))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("LivePet_Operations_Title", alter: "عمليات دورة حياة الحيوان"))
                    .font(Font.custom("Beiruti-Bold", size: 17))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("LivePet_Operations_Hint", alter: "كل تغيير يُنفذ من الخادم ويُسجل في حركة المخزون والتدقيق."))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AdminSpacing.xs)

            Button {
                Task { await liveModel.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.primary.opacity(0.09), in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.primary.opacity(0.18), lineWidth: 0.75))
            }
            .buttonStyle(CatalogPressStyle())
            .disabled(liveModel.isLoading || liveModel.isMutating)
            .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
        }
    }

    private var legacyTrackingDecision: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("LivePet_Legacy_Mode_Title", alter: "يلزم اعتماد نمط التتبع"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("LivePet_Legacy_Mode_Hint", alter: "هذا سجل قديم. اختر تتبعاً فردياً أو إدارة بالكمية قبل تنفيذ أي حركة جديدة."))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                liveModel.operation = .migrate
            } label: {
                Label(Language.get("LivePet_Migrate_Action", alter: "اعتماد نمط المخزون"), systemImage: "arrow.triangle.branch")
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
                    .background(Color(uiColor: .ppWarning), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            }
            .buttonStyle(CatalogPressStyle())
            .disabled(!liveModel.canManageStock || liveModel.isMutating)
        }
        .padding(AdminSpacing.md)
        .background(Color(uiColor: .ppWarning).opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color(uiColor: .ppWarning).opacity(0.26), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var livePetPrimaryCommands: some View {
        HStack(spacing: 12) {
            // Intake Action Tile (Emerald)
            dossierOperationTile(
                title: Language.get("LivePet_Intake_Action", alter: "إضافة مخزون"),
                detail: Language.get("LivePetDossier_IntakeDetail", alter: "تسجيل وصول حيوان أو كمية جديدة"),
                symbol: "plus.circle.fill",
                tint: Color(uiColor: .ppSuccess),
                enabled: liveModel.canManageStock
            ) {
                liveModel.operation = .intake
            }

            // POS Sell Action Tile (Brand Red)
            dossierOperationTile(
                title: Language.get("LivePet_Open_POS", alter: "فتح نقطة البيع"),
                detail: Language.get("LivePetDossier_POSDetail", alter: "بيع أو حجز حيوان لعميل"),
                symbol: "cart.fill",
                tint: AdminSurface.primary,
                enabled: liveModel.canSell
            ) {
                onOpenPOS()
            }
        }
    }

    private func dossierOperationTile(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(0.16))
                            .frame(width: 38, height: 38)
                        Image(systemName: symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Spacer(minLength: 0)
                    if !enabled {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 0.75)
            )
        }
        .buttonStyle(CatalogPressStyle())
        .disabled(!enabled || liveModel.isMutating)
        .opacity(enabled ? 1 : 0.6)
    }

    private var archiveCatalogCommand: some View {
        let archived = liveModel.item.isArchived
        let enabled = liveModel.canManageStock
        let title = archived
            ? Language.get("LivePet_Restore_Action", alter: "استعادة سجل الكتالوج")
            : Language.get("LivePet_Archive_Action", alter: "أرشفة سجل الكتالوج")
        let detail = archived
            ? Language.get("LivePetDossier_RestoreDetail", alter: "إعادة السجل إلى مساحة العمل")
            : Language.get("LivePetDossier_ArchiveDetail", alter: "إيقاف السجل دون حذف تاريخه")

        return Button {
            liveModel.operation = .archive(!archived)
        } label: {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: archived ? "arrow.uturn.backward.circle.fill" : "archivebox.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? AdminCommandInk.secondary : Color(uiColor: .ppTextTertiary))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(enabled ? AdminSurface.primaryText : AdminSurface.secondaryText)
                    Text(detail)
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AdminSpacing.xs)
                if !enabled {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppTextTertiary))
                } else {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
            }
            .padding(.horizontal, AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .buttonStyle(CatalogPressStyle())
        .disabled(!enabled || liveModel.isMutating)
    }

    private var groupReconciliationCommand: some View {
        dossierOperationTile(
            title: Language.get("LivePet_Group_Adjust_Action", alter: "مطابقة كمية المجموعة"),
            detail: Language.get("LivePet_Group_Exact_Action_Hint", alter: "الحجز الفردي والنقل والوفاة لكل حيوان تتطلب نمط التتبع الفردي."),
            symbol: "slider.horizontal.3",
            tint: Color(uiColor: .ppInfo),
            enabled: liveModel.canManageStock
        ) {
            liveModel.operation = .groupAdjustment
        }
    }

    // MARK: - Individual Animal Ledger

    private var individualAnimalLedger: some View {
        let activeUnits = liveModel.units.filter { $0.status != "REMOVED" && $0.status != "DECEASED" && $0.status != "TRANSFERRED" }
        let historyUnits = liveModel.units.filter { $0.status == "REMOVED" || $0.status == "DECEASED" || $0.status == "TRANSFERRED" }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("LivePetDossier_UnitLedgerTitle", alter: "سجل الحيوانات الفردية"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(String(
                        format: Language.get("LivePetDossier_ActiveUnitLedgerCount", alter: "%ld سجلات هوية نشطة"),
                        activeUnits.count
                    ))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminCommandInk.secondary)
                }
                Spacer(minLength: AdminSpacing.xs)
                dossierStatusPill(
                    title: inventoryTrackingTitle,
                    symbol: inventoryTrackingSymbol,
                    tint: inventoryTrackingTint
                )
            }

            if liveModel.isLoading && liveModel.units.isEmpty {
                dossierLoadingState
            } else if activeUnits.isEmpty && historyUnits.isEmpty {
                dossierUnitEmptyState
            } else {
                if !activeUnits.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(activeUnits) { unit in
                            livePetUnitRow(unit)
                        }
                    }
                } else {
                    dossierUnitEmptyState
                }

                if !historyUnits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHistoryUnits.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showHistoryUnits ? "chevron.down" : "chevron.forward")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AdminCommandInk.secondary)
                                Text(String(
                                    format: Language.get("LivePet_Units_Archived_Count", alter: "السجلات المؤرشفة والمزالة (%ld)"),
                                    historyUnits.count
                                ))
                                .font(Font.custom("Beiruti-SemiBold", size: 13))
                                .foregroundStyle(AdminCommandInk.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if showHistoryUnits {
                            VStack(spacing: 8) {
                                ForEach(historyUnits) { unit in
                                    livePetUnitRow(unit)
                                        .opacity(0.7)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.top, 4)
    }

    private var dossierLoadingState: some View {
        HStack(spacing: AdminSpacing.md) {
            ProgressView()
                .tint(AdminSurface.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("LivePet_Units_Loading", alter: "جارٍ تحميل سجلات الحيوانات..."))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("LivePetDossier_LoadingHint", alter: "يتم جلب الحالة الحالية قبل إتاحة الإجراءات."))
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminCommandInk.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AdminSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
    }

    @ViewBuilder
    private var dossierUnitEmptyState: some View {
        let canReadVisibleUnits = liveModel.canManageStock || liveModel.canSell
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Label(
                canReadVisibleUnits
                    ? Language.get("LivePet_Units_Empty", alter: "لا توجد سجلات فردية لهذا الصنف بعد.")
                    : Language.get("LivePetDossier_UnitsRestricted", alter: "سجلات الحيوانات الفردية غير متاحة لصلاحيتك."),
                systemImage: canReadVisibleUnits ? "tray" : "lock.shield"
            )
            .font(Font.custom("Beiruti-Bold", size: 13))
            .foregroundStyle(canReadVisibleUnits ? AdminSurface.secondaryText : Color(uiColor: .ppWarning))

            Text(
                canReadVisibleUnits
                    ? Language.get("LivePetDossier_EmptyUnitsHint", alter: "أضف مخزوناً فردياً لإنشاء سجل هوية لكل حيوان.")
                    : Language.get("LivePetDossier_RestrictedUnitsHint", alter: "اطلب صلاحية المخزون أو المبيعات لرؤية السجلات التي يسمح لك بها الدور.")
            )
            .font(Font.custom("Beiruti-Regular", size: 11))
            .foregroundStyle(AdminCommandInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AdminSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var activeReservationsLedger: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .ppWarning))
                    .frame(width: 28, height: 28)
                    .background(Color(uiColor: .ppWarning).opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("LivePet_Reservations_Title", alter: "الحجوزات النشطة"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(String(
                        format: Language.get("LivePetDossier_ReservationCount", alter: "%ld حجوزات بحاجة إلى متابعة"),
                        liveModel.reservations.count
                    ))
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminCommandInk.secondary)
                }
            }

            VStack(spacing: AdminSpacing.xs) {
                ForEach(liveModel.reservations) { reservation in
                    reservationDossierRow(reservation)
                }
            }
        }
        .padding(.top, AdminSpacing.sm)
    }

    private func reservationDossierRow(_ reservation: PPLivePetReservation) -> some View {
        Button {
            liveModel.operation = .reservation(reservation)
        } label: {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.primary.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(reservation.customerName.isEmpty ? reservation.customerPhone : reservation.customerName)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(String(format: Language.get("LivePet_Reservation_Branch_Format", alter: "الفرع: %@"), localizedBranchName(reservation.branchID, id: reservation.branchID)))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminCommandInk.secondary)
                    if let validUntil = reservation.validUntil {
                        Text(String(format: Language.get("LivePet_Reservation_Until_Format", alter: "الحجز صالح حتى %@"), validUntil.formatted(date: .abbreviated, time: .shortened)))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(validUntil <= Date() ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
                    }
                }

                Spacer(minLength: AdminSpacing.xs)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(PetAccessory.formatCurrency(NSNumber(value: reservation.total)))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primary)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
            }
            .padding(AdminSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .buttonStyle(CatalogPressStyle())
        .disabled(liveModel.isMutating)
    }

    private func livePetUnitRow(_ unit: PPLivePetInventoryUnit) -> some View {
        let identity = unit.ringTag.isEmpty ? unit.id : unit.ringTag
        let status = liveUnitStatus(unit.status)
        let statusColor = liveUnitStatusColor(unit.status)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                // Status Jewel (Right in RTL)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(statusColor.opacity(0.12))
                    Image(systemName: liveUnitStatusSymbol(unit.status))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                // Identity + Badges Track
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: identity.normalizedEnglishDigits)
                        .font(PPBrandFont.bold(size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        dossierStatusPill(
                            title: status,
                            symbol: liveUnitStatusSymbol(unit.status),
                            tint: statusColor
                        )

                        let unitBranchID = unit.currentBranchID.isEmpty ? (item.resolvedBranchID() ?? item.storeID ?? "") : unit.currentBranchID
                        if !unitBranchID.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "building.2")
                                    .font(.system(size: 9))
                                Text(localizedBranchName(unitBranchID, id: unitBranchID))
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                            }
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AdminSurface.control, in: Capsule(style: .continuous))
                        }
                    }
                }

                Spacer(minLength: AdminSpacing.xs)

                // Price & Actions (Left in RTL)
                VStack(alignment: .trailing, spacing: 6) {
                    if let price = unit.sellingPrice {
                        Text(PetAccessory.formatCurrency(NSNumber(value: price)))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primary)
                    } else {
                        Text(Language.get("LivePetDossier_PriceUnspecified", alter: "السعر غير محدد"))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Menu {
                        livePetUnitActions(unit)
                    } label: {
                        HStack(spacing: 2.5) {
                            Circle().fill(AdminSurface.primary).frame(width: 3.5, height: 3.5)
                            Circle().fill(AdminSurface.primary).frame(width: 3.5, height: 3.5)
                            Circle().fill(AdminSurface.primary).frame(width: 3.5, height: 3.5)
                        }
                        .frame(width: 34, height: 34)
                        .background(AdminSurface.primary.opacity(0.12), in: Circle())
                        .overlay(Circle().strokeBorder(AdminSurface.primary.opacity(0.24), lineWidth: 0.75))
                    }
                    .disabled(liveModel.isMutating)
                    .accessibilityLabel(String(
                        format: Language.get("LivePetDossier_UnitActionsAccessibility", alter: "إجراءات الحيوان %@"),
                        identity
                    ))
                }
            }

            if unit.status == "RESERVED" {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .ppWarning))
                        .frame(width: 28, height: 28)
                        .background(Color(uiColor: .ppWarning).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit.reservationCustomerName.isEmpty ? unit.reservationCustomerPhone : unit.reservationCustomerName)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)
                        if let validUntil = unit.reservationValidUntil {
                            Text(String(format: Language.get("LivePet_Reservation_Until_Format", alter: "الحجز صالح حتى %@"), validUntil.formatted(date: .abbreviated, time: .shortened)))
                                .font(Font.custom("Beiruti-Regular", size: 11))
                                .foregroundStyle(validUntil <= Date() ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color(uiColor: .ppWarning).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                activeCommandUnit = unit
            }
        }
        .contextMenu {
            livePetUnitActions(unit)
        }
    }

    private func selectUnitAction(_ op: PPLivePetOperationContext) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            liveModel.operation = op
        }
    }

    private func livePetMenuActionLabel(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(PPBrandFont.bold(size: 16))
        } icon: {
            Image(systemName: systemImage)
        }
    }

    @ViewBuilder
    private func livePetUnitActions(_ unit: PPLivePetInventoryUnit) -> some View {
        if unit.status == "AVAILABLE" {
            Button { selectUnitAction(.reserve(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Reserve_Action", alter: "حجز لعميل"), systemImage: "calendar.badge.plus")
            }
            .disabled(!liveModel.canSell)
            Button { selectUnitAction(.transfer(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Transfer_Action", alter: "نقل إلى فرع"), systemImage: "arrow.left.arrow.right")
            }
            .disabled(!liveModel.canManageStock)
            Button { selectUnitAction(.quarantine(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Quarantine_Action", alter: "إدخال الحجر"), systemImage: "cross.case")
            }
            .disabled(!liveModel.canManageStock)
            Button { selectUnitAction(.price(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Edit_Price_Action", alter: "تعديل سعر البيع"), systemImage: "tag")
            }
            .disabled(!liveModel.canManageStock)
            Button(role: .destructive) { selectUnitAction(.remove(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Remove_Action", alter: "إزالة من المخزون"), systemImage: "minus.circle")
            }
            .disabled(!liveModel.canManageStock)
            Button(role: .destructive) { selectUnitAction(.mortality(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Mortality_Action", alter: "تسجيل وفاة"), systemImage: "heart.slash")
            }
            .disabled(!liveModel.canManageStock)
        } else if unit.status == "RESERVED" {
            if let reservation = liveModel.reservation(for: unit) {
                Button { selectUnitAction(.reservation(reservation)) } label: {
                    livePetMenuActionLabel(title: Language.get("LivePet_Manage_Reservation", alter: "إدارة الحجز"), systemImage: "creditcard")
                }
            } else {
                Button { Task { await liveModel.load() } } label: {
                    livePetMenuActionLabel(title: Language.get("Refresh", alter: "تحديث"), systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) { selectUnitAction(.mortality(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Mortality_Action", alter: "تسجيل وفاة وإلغاء الحجز"), systemImage: "heart.slash")
            }
            .disabled(!liveModel.canManageStock)
        } else if unit.status == "QUARANTINED" {
            Button { selectUnitAction(.releaseQuarantine(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Release_Quarantine_Action", alter: "إخراج من الحجر"), systemImage: "checkmark.shield")
            }
            .disabled(!liveModel.canReleaseQuarantine)
            Button { selectUnitAction(.transfer(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Transfer_Action", alter: "نقل إلى فرع"), systemImage: "arrow.left.arrow.right")
            }
            .disabled(!liveModel.canManageStock)
            Button { selectUnitAction(.price(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Edit_Price_Action", alter: "تعديل سعر البيع"), systemImage: "tag")
            }
            .disabled(!liveModel.canManageStock)
            Button(role: .destructive) { selectUnitAction(.mortality(unit)) } label: {
                livePetMenuActionLabel(title: Language.get("LivePet_Mortality_Action", alter: "تسجيل وفاة"), systemImage: "heart.slash")
            }
            .disabled(!liveModel.canManageStock)
        } else {
            Text(Language.get("LivePet_Terminal_No_Actions", alter: "هذه حالة نهائية للعرض فقط"))
                .font(Font.custom("Beiruti-Bold", size: 14))
        }
    }

    private func localizedBranchName(_ name: String, id: String) -> String {
        let lookupKey = id.isEmpty ? name : id
        if lookupKey == "main_store" || lookupKey.lowercased() == "main_store" || lookupKey.lowercased() == "main store" {
            return Language.get("MainStore", alter: "المتجر الرئيسي")
        }
        if lookupKey.lowercased().contains("reservation") {
            return Language.get("ReservationBranch", alter: "فرع الحجوزات")
        }
        if let canonical = PPLivePetInventoryService.canonicalBranch(for: lookupKey, in: liveModel.branches) {
            return canonical.fullMeaningfulTitle
        }
        if let branch = liveModel.branches.first(where: { $0.id == id }) {
            return branch.fullMeaningfulTitle
        }
        if let cached = PPLivePetInventoryService.branch(for: id) {
            return cached.fullMeaningfulTitle
        }
        if let b = PPBranchContextManager.shared().branch(withID: id) {
            return b.localizedName()
        }
        return name.isEmpty ? id : name
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

    private func liveUnitStatusSymbol(_ status: String) -> String {
        switch status {
        case "AVAILABLE": return "checkmark.circle.fill"
        case "RESERVED": return "calendar.badge.clock"
        case "SOLD": return "checkmark.seal.fill"
        case "QUARANTINED": return "cross.case.fill"
        case "DECEASED": return "heart.slash.fill"
        case "TRANSFERRED": return "arrow.left.arrow.right.circle.fill"
        default: return "minus.circle.fill"
        }
    }

    private func dossierStateNotice(_ text: String, symbol: String, tone: Color) -> some View {
        Label {
            Text(text)
                .font(Font.custom("Beiruti-SemiBold", size: 12))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(tone)
        .padding(AdminSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                .strokeBorder(tone.opacity(0.22), lineWidth: 0.75)
        )
    }

    private func dossierStatusPill(title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(Font.custom("Beiruti-Bold", size: 11))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, AdminSpacing.xs)
            .padding(.vertical, 4)
            .background(tint.opacity(0.11), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
    }

    private var inventoryTrackingTitle: String {
        switch liveModel.mode {
        case .some(.individual):
            return Language.get("LivePetDossier_IndividualTracking", alter: "تتبع فردي")
        case .some(.quantity):
            return Language.get("LivePetDossier_QuantityTracking", alter: "تتبع بالكمية")
        case .none:
            return Language.get("LivePetDossier_TrackingPending", alter: "يتطلب اعتماد نمط التتبع")
        }
    }

    private var inventoryTrackingSymbol: String {
        switch liveModel.mode {
        case .some(.individual): return "number.square.fill"
        case .some(.quantity): return "square.stack.3d.up.fill"
        case .none: return "exclamationmark.triangle.fill"
        }
    }

    private var inventoryTrackingTint: Color {
        switch liveModel.mode {
        case .some(.individual): return Color(uiColor: .ppSuccess)
        case .some(.quantity): return Color(uiColor: .ppInfo)
        case .none: return Color(uiColor: .ppWarning)
        }
    }
}

// MARK: - Sovereign Action Portal Shapes & Styles

private struct PPSheetTopRoundedShape: Shape {
    var radius: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: Angle(degrees: 270),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PPLivePetActionPortalCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconTint: Color
    let iconBackground: Color
    var badge: String? = nil
    var badgeTint: Color? = nil
    var trailingPill: String? = nil
    var isDestructive: Bool = false
    var isHero: Bool = false
    var isLocked: Bool = false
    var lockReason: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            if !isLocked {
                action()
            }
        }) {
            HStack(alignment: .center, spacing: 14) {
                // Leading Icon Vessel
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(iconBackground)
                    Image(systemName: icon)
                        .font(.system(size: isHero ? 20 : 17, weight: .bold))
                        .foregroundStyle(iconTint)
                }
                .frame(width: isHero ? 46 : 42, height: isHero ? 46 : 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(iconTint.opacity(0.25), lineWidth: 0.75)
                )

                // Title & Subtitle Stack
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(Font.custom("Beiruti-Bold", size: isHero ? 16 : 15))
                            .foregroundStyle(isDestructive ? Color(uiColor: .ppError) : AdminSurface.primaryText)

                        if let badge = badge {
                            Text(badge)
                                .font(Font.custom("Beiruti-Bold", size: 10))
                                .foregroundStyle(badgeTint ?? iconTint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background((badgeTint ?? iconTint).opacity(0.12), in: Capsule(style: .continuous))
                        }

                        if isLocked {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                if let lockReason = lockReason {
                                    Text(lockReason)
                                        .font(Font.custom("Beiruti-Regular", size: 10))
                                }
                            }
                            .foregroundStyle(AdminCommandInk.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: Capsule(style: .continuous))
                        }
                    }

                    Text(subtitle)
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Optional Trailing Badge or Price Pill
                if let trailingPill = trailingPill {
                    Text(trailingPill)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(iconTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(iconTint.opacity(0.10), in: Capsule(style: .continuous))
                }

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isDestructive ? Color(uiColor: .ppError).opacity(0.6) : AdminCommandInk.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, isHero ? 14 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHero
                    ? iconTint.opacity(0.06)
                    : (isDestructive ? Color(uiColor: .ppError).opacity(0.04) : AdminSurface.control),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isHero
                            ? iconTint.opacity(0.35)
                            : (isDestructive ? Color(uiColor: .ppError).opacity(0.20) : AdminSurface.hairline),
                        lineWidth: isHero ? 1.0 : 0.75
                    )
            )
            .opacity(isLocked ? 0.55 : 1.0)
        }
        .buttonStyle(CatalogPressStyle())
        .disabled(isLocked)
    }
}

// MARK: - Sovereign Live Pet Action Portal & Command Deck (Reimagined from First Principles)

private struct PPLivePetActionPortalDeck: View {
    let unit: PPLivePetInventoryUnit
    @ObservedObject var liveModel: PPLivePetOperationsViewModel
    let onDismiss: () -> Void
    let onSelectOperation: (PPLivePetOperationContext) -> Void

    @State private var hasCopiedTag: Bool = false
    @State private var dragOffset: CGFloat = 0

    private var identity: String {
        unit.ringTag.isEmpty ? unit.id : unit.ringTag
    }

    private var statusTitle: String {
        switch unit.status {
        case "AVAILABLE": return Language.get("LivePet_Status_Available", alter: "متاح بالمخزون")
        case "RESERVED": return Language.get("LivePet_Status_Reserved", alter: "محجوز لعميل")
        case "SOLD": return Language.get("LivePet_Status_Sold", alter: "مباع ومسلّم")
        case "QUARANTINED": return Language.get("LivePet_Status_Quarantined", alter: "في الحجر الصحي")
        case "DECEASED": return Language.get("LivePet_Status_Deceased", alter: "متوفى")
        case "TRANSFERRED": return Language.get("LivePet_Status_Transferred", alter: "منقول لفرع آخر")
        default: return Language.get("LivePet_Status_Removed", alter: "مزال من المخزون")
        }
    }

    private var statusColor: Color {
        switch unit.status {
        case "AVAILABLE": return Color(uiColor: .ppSuccess)
        case "RESERVED": return Color(uiColor: .ppWarning)
        case "QUARANTINED": return Color(uiColor: .ppInfo)
        case "SOLD", "TRANSFERRED": return AdminCommandInk.secondary
        default: return Color(uiColor: .ppError)
        }
    }

    private var statusSymbol: String {
        switch unit.status {
        case "AVAILABLE": return "checkmark.circle.fill"
        case "RESERVED": return "calendar.badge.clock"
        case "SOLD": return "checkmark.seal.fill"
        case "QUARANTINED": return "cross.case.fill"
        case "DECEASED": return "heart.slash.fill"
        case "TRANSFERRED": return "arrow.left.arrow.right.circle.fill"
        default: return "minus.circle.fill"
        }
    }

    private func localizedBranchName(_ name: String, id: String) -> String {
        let lookupKey = id.isEmpty ? name : id
        if lookupKey == "main_store" || lookupKey.lowercased() == "main_store" || lookupKey.lowercased() == "main store" {
            return Language.get("MainStore", alter: "المتجر الرئيسي")
        }
        if lookupKey.lowercased().contains("reservation") {
            return Language.get("ReservationBranch", alter: "فرع الحجوزات")
        }
        if let canonical = PPLivePetInventoryService.canonicalBranch(for: lookupKey, in: liveModel.branches) {
            return canonical.fullMeaningfulTitle
        }
        if let branch = liveModel.branches.first(where: { $0.id == id }) {
            return branch.fullMeaningfulTitle
        }
        if let cached = PPLivePetInventoryService.branch(for: id) {
            return cached.fullMeaningfulTitle
        }
        if let b = PPBranchContextManager.shared().branch(withID: id) {
            return b.localizedName()
        }
        return name.isEmpty ? id : name
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // High-Performance Ambient Scrim
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }

            // Sovereign Sheet Deck Vessel
            VStack(spacing: 0) {
                // Drag Capsule
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 44, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                VStack(spacing: 16) {
                    // Specimen Sovereign Telemetry Card
                    specimenTelemetryHUD

                    // Active Reservation Banner if Reserved
                    if unit.status == "RESERVED" {
                        activeReservationBanner
                    }

                    // Active Quarantine Notice if Quarantined
                    if unit.status == "QUARANTINED" {
                        activeQuarantineNotice
                    }

                    // Tactical Action Sectors
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 18) {
                            if unit.status == "AVAILABLE" {
                                commercialMovementsSector
                                careAndGovernanceSector
                                terminalGuardSector
                            } else if unit.status == "RESERVED" {
                                reservedStateSector
                                terminalGuardSector
                            } else if unit.status == "QUARANTINED" {
                                quarantinedStateSector
                                terminalGuardSector
                            } else {
                                terminalReadOnlySector
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.54)
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
            }
            .padding(.bottom, 24)
            .background(
                AdminSurface.surface
                    .clipShape(PPSheetTopRoundedShape(radius: 32))
                    .ignoresSafeArea(edges: .bottom)
            )
            .overlay(
                PPSheetTopRoundedShape(radius: 32)
                    .stroke(AdminSurface.hairline, lineWidth: 1)
                    .ignoresSafeArea(edges: .bottom)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: -8)
            .offset(y: max(0, dragOffset))
            .gesture(
                DragGesture()
                    .onChanged { val in
                        if val.translation.height > 0 {
                            dragOffset = val.translation.height
                        }
                    }
                    .onEnded { val in
                        if val.translation.height > 80 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Specimen Sovereign Telemetry Card (HUD)

    private var specimenTelemetryHUD: some View {
        VStack(spacing: 12) {
            // Top ID & Close Bar
            HStack(alignment: .center, spacing: 10) {
                // Identity Jewel
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(statusColor.opacity(0.14))
                    Image(systemName: statusSymbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: identity.normalizedEnglishDigits)
                            .font(PPBrandFont.bold(size: 18))
                            .foregroundStyle(AdminSurface.primaryText)

                        Button {
                            UIPasteboard.general.string = identity
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                hasCopiedTag = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    hasCopiedTag = false
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: hasCopiedTag ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10, weight: .bold))
                                Text(hasCopiedTag ? Language.get("Copied", alter: "تم النسخ") : Language.get("Copy", alter: "نسخ"))
                                    .font(Font.custom("Beiruti-Bold", size: 10))
                            }
                            .foregroundStyle(hasCopiedTag ? Color(uiColor: .ppSuccess) : AdminSurface.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                (hasCopiedTag ? Color(uiColor: .ppSuccess) : AdminSurface.primary).opacity(0.10),
                                in: Capsule(style: .continuous)
                            )
                        }
                    }

                    Text(Language.get("LivePet_Command_Hub_Subtitle", alter: "لوحة التحكم السريعة في دورة حياة السجل"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.control, in: Circle())
                }
            }

            // Telemetry Bento Strip
            HStack(spacing: 8) {
                // Status Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusTitle)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.10), in: Capsule(style: .continuous))

                // Branch Location
                let displayBranchID = unit.currentBranchID.isEmpty ? (liveModel.item.resolvedBranchID() ?? liveModel.item.storeID ?? "") : unit.currentBranchID
                if !displayBranchID.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 10))
                        Text(localizedBranchName(displayBranchID, id: displayBranchID))
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(AdminSurface.control, in: Capsule(style: .continuous))
                }

                Spacer(minLength: 0)

                // Selling Price
                if let price = unit.sellingPrice {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10))
                        Text(PetAccessory.formatCurrency(NSNumber(value: price)))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule(style: .continuous))
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Active Reservation Banner

    private var activeReservationBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(uiColor: .ppWarning))
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .ppWarning).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(unit.reservationCustomerName.isEmpty ? unit.reservationCustomerPhone : unit.reservationCustomerName)
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)

                if let validUntil = unit.reservationValidUntil {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                        Text(String(format: Language.get("LivePet_Reservation_Until_Format", alter: "الحجز صالح حتى %@"), validUntil.formatted(date: .abbreviated, time: .shortened)))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                    }
                    .foregroundStyle(validUntil <= Date() ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .ppWarning).opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppWarning).opacity(0.24), lineWidth: 0.75)
        )
    }

    // MARK: - Active Quarantine Notice

    private var activeQuarantineNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(uiColor: .ppInfo))
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .ppInfo).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("LivePet_Quarantine_Notice_Title", alter: "الحيوان خاضع للعزل البيطري"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("LivePet_Quarantine_Notice_Desc", alter: "تم إيقاف عرض هذا الحيوان من نقاط البيع لحين التحقق من التعافي وإصدار إذن خروج."))
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .ppInfo).opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppInfo).opacity(0.24), lineWidth: 0.75)
        )
    }

    // MARK: - Tactical Sectors

    // Commercial Movements (Tier 1)
    private var commercialMovementsSector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bag.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePet_Sector_Commercial", alter: "حركات الحجز واللوجستيات"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            VStack(spacing: 8) {
                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Reserve_Action", alter: "حجز لعميل"),
                    subtitle: Language.get("LivePet_Reserve_Action_Desc", alter: "تخصيص هذا الحيوان حصرياً لعميل محدد وتجميده من المعارض"),
                    icon: "calendar.badge.plus",
                    iconTint: Color(uiColor: .ppWarning),
                    iconBackground: Color(uiColor: .ppWarning).opacity(0.12),
                    badge: Language.get("Badge_Exclusive", alter: "تخصيص فوري"),
                    isHero: true,
                    isLocked: !liveModel.canSell,
                    lockReason: !liveModel.canSell ? Language.get("Stock_Perm_Required", alter: "صلاحية البيع مطلوبة") : nil
                ) {
                    triggerAction(.reserve(unit))
                }

                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Transfer_Action", alter: "نقل إلى فرع آخر"),
                    subtitle: Language.get("LivePet_Transfer_Action_Desc", alter: "ترحيل العهدة والحيازة إلى معرض أو مستودع أو فرع جديد"),
                    icon: "arrow.left.arrow.right",
                    iconTint: AdminSurface.primary,
                    iconBackground: AdminSurface.primary.opacity(0.12),
                    badge: Language.get("Badge_Logistics", alter: "حركة مخزنية"),
                    isLocked: !liveModel.canManageStock,
                    lockReason: !liveModel.canManageStock ? Language.get("Stock_Perm_Required", alter: "صلاحية إدارة المخزون") : nil
                ) {
                    triggerAction(.transfer(unit))
                }
            }
        }
    }

    // Care & Governance (Tier 2)
    private var careAndGovernanceSector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cross.case.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(uiColor: .ppInfo))
                Text(Language.get("LivePet_Sector_Care_Pricing", alter: "الرعاية الصحية وحوكمة الأسعار"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            VStack(spacing: 8) {
                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Quarantine_Action", alter: "إدخال الحجر الصحي"),
                    subtitle: Language.get("LivePet_Quarantine_Action_Desc", alter: "عزل بيطري فوري وفصل السجل عن قنوات العرض والبيع"),
                    icon: "cross.case",
                    iconTint: Color(uiColor: .ppInfo),
                    iconBackground: Color(uiColor: .ppInfo).opacity(0.12),
                    badge: Language.get("Badge_Biosecurity", alter: "أمان حيوي"),
                    isLocked: !liveModel.canManageStock,
                    lockReason: !liveModel.canManageStock ? Language.get("Stock_Perm_Required", alter: "صلاحية إدارة المخزون") : nil
                ) {
                    triggerAction(.quarantine(unit))
                }

                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Edit_Price_Action", alter: "تعديل سعر البيع"),
                    subtitle: Language.get("LivePet_Edit_Price_Action_Desc", alter: "تحديث السعر الفردي المعتمد لهذا الحيوان"),
                    icon: "tag",
                    iconTint: AdminSurface.primary,
                    iconBackground: AdminSurface.primary.opacity(0.12),
                    trailingPill: unit.sellingPrice != nil ? PetAccessory.formatCurrency(NSNumber(value: unit.sellingPrice!)) : nil,
                    isLocked: !liveModel.canManageStock,
                    lockReason: !liveModel.canManageStock ? Language.get("Stock_Perm_Required", alter: "صلاحية إدارة المخزون") : nil
                ) {
                    triggerAction(.price(unit))
                }
            }
        }
    }

    // Terminal Safety Guard (Tier 3)
    private var terminalGuardSector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(uiColor: .ppError))
                Text(Language.get("LivePet_Sector_Terminal", alter: "الإجراءات النهائية وإسقاط العهدة"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(Color(uiColor: .ppError).opacity(0.85))
            }

            VStack(spacing: 8) {
                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Remove_Action", alter: "إزالة من المخزون"),
                    subtitle: Language.get("LivePet_Remove_Action_Desc", alter: "شطب إداري للسجل وتحديث إجمالي الكميات المسجلة"),
                    icon: "minus.circle",
                    iconTint: Color(uiColor: .ppError),
                    iconBackground: Color(uiColor: .ppError).opacity(0.12),
                    isDestructive: true,
                    isLocked: !liveModel.canManageStock,
                    lockReason: !liveModel.canManageStock ? Language.get("Stock_Perm_Required", alter: "صلاحية إدارة المخزون") : nil
                ) {
                    triggerAction(.remove(unit))
                }

                PPLivePetActionPortalCard(
                    title: unit.status == "RESERVED"
                        ? Language.get("LivePet_Mortality_Cancel_Action", alter: "تسجيل وفاة وإلغاء الحجز")
                        : Language.get("LivePet_Mortality_Action", alter: "تسجيل حالة وفاة"),
                    subtitle: Language.get("LivePet_Mortality_Action_Desc", alter: "توثيق السبب البيطري والإسقاط النهائي من الدورة الحية"),
                    icon: "heart.slash",
                    iconTint: Color(uiColor: .ppError),
                    iconBackground: Color(uiColor: .ppError).opacity(0.12),
                    isDestructive: true,
                    isLocked: !liveModel.canManageStock,
                    lockReason: !liveModel.canManageStock ? Language.get("Stock_Perm_Required", alter: "صلاحية إدارة المخزون") : nil
                ) {
                    triggerAction(.mortality(unit))
                }
            }
        }
    }

    // Reserved State Sector
    private var reservedStateSector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(uiColor: .ppWarning))
                Text(Language.get("LivePet_Sector_Reservation_Active", alter: "إدارة الحجز القائم"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            VStack(spacing: 8) {
                if let reservation = liveModel.reservation(for: unit) {
                    PPLivePetActionPortalCard(
                        title: Language.get("LivePet_Manage_Reservation", alter: "إدارة وتسوية الحجز"),
                        subtitle: Language.get("LivePet_Manage_Reservation_Desc", alter: "إتمام عملية البيع أو الإلغاء واسترداد الحيوان للمخزون"),
                        icon: "creditcard",
                        iconTint: Color(uiColor: .ppWarning),
                        iconBackground: Color(uiColor: .ppWarning).opacity(0.14),
                        badge: Language.get("Badge_Active_Hold", alter: "حجز نشط"),
                        isHero: true
                    ) {
                        triggerAction(.reservation(reservation))
                    }
                } else {
                    PPLivePetActionPortalCard(
                        title: Language.get("Refresh", alter: "تحديث السجلات"),
                        subtitle: Language.get("LivePet_Refresh_Hint", alter: "إعادة جلب حالة الحجز والمطابقة من السحابة"),
                        icon: "arrow.clockwise",
                        iconTint: AdminSurface.primary,
                        iconBackground: AdminSurface.primary.opacity(0.12)
                    ) {
                        Task { await liveModel.load() }
                        onDismiss()
                    }
                }
            }
        }
    }

    // Quarantined State Sector
    private var quarantinedStateSector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "cross.case.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(uiColor: .ppInfo))
                Text(Language.get("LivePet_Sector_Quarantine_Protocol", alter: "بروتوكول الفحص البيطري والحجر"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminCommandInk.secondary)
            }

            VStack(spacing: 8) {
                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Release_Quarantine_Action", alter: "إخراج من الحجر الصحي"),
                    subtitle: Language.get("LivePet_Release_Quarantine_Desc", alter: "إعادة إتاحة الحيوان للبيع بعد التأكد من سلامته البيطرية"),
                    icon: "checkmark.shield",
                    iconTint: Color(uiColor: .ppSuccess),
                    iconBackground: Color(uiColor: .ppSuccess).opacity(0.14),
                    badge: Language.get("Badge_Medical_Clearance", alter: "تصريح طبي"),
                    isHero: true,
                    isLocked: !liveModel.canReleaseQuarantine,
                    lockReason: !liveModel.canReleaseQuarantine ? Language.get("Stock_Perm_Required", alter: "صلاحية الفحص الطبي") : nil
                ) {
                    triggerAction(.releaseQuarantine(unit))
                }

                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Transfer_Action", alter: "نقل إلى فرع آخر"),
                    subtitle: Language.get("LivePet_Transfer_Action_Desc", alter: "نقل الحيوان إلى مصحة الفرع أو العيادة المعتمدة"),
                    icon: "arrow.left.arrow.right",
                    iconTint: AdminSurface.primary,
                    iconBackground: AdminSurface.primary.opacity(0.12),
                    badge: Language.get("Badge_Logistics", alter: "حركة مخزن"),
                    isLocked: !liveModel.canManageStock,
                    lockReason: !liveModel.canManageStock ? Language.get("Stock_Perm_Required", alter: "صلاحية إدارة المخزون") : nil
                ) {
                    triggerAction(.transfer(unit))
                }

                PPLivePetActionPortalCard(
                    title: Language.get("LivePet_Edit_Price_Action", alter: "تعديل سعر البيع"),
                    subtitle: Language.get("LivePet_Edit_Price_Desc_Quarantine", alter: "تحديث السعر المعتمد للحيوان خلال فترة العزل"),
                    icon: "tag",
                    iconTint: AdminSurface.primary,
                    iconBackground: AdminSurface.primary.opacity(0.12),
                    trailingPill: unit.sellingPrice != nil ? PetAccessory.formatCurrency(NSNumber(value: unit.sellingPrice!)) : nil,
                    isLocked: !liveModel.canManageStock,
                    lockReason: !liveModel.canManageStock ? Language.get("Stock_Perm_Required", alter: "صلاحية إدارة المخزون") : nil
                ) {
                    triggerAction(.price(unit))
                }
            }
        }
    }

    // Terminal Read-Only Sector
    private var terminalReadOnlySector: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(AdminCommandInk.secondary)
            Text(Language.get("LivePet_Terminal_No_Actions", alter: "هذه حالة نهائية للعرض والتدقيق فقط"))
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)
            Text(Language.get("LivePet_Terminal_No_Actions_Hint", alter: "لا يمكن تنفيذ إجراءات تشغيلية إضافية على الحيوانات المباعة أو المتوفاة."))
                .font(Font.custom("Beiruti-Regular", size: 12))
                .foregroundStyle(AdminCommandInk.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private func triggerAction(_ operation: PPLivePetOperationContext) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSelectOperation(operation)
    }
}


// MARK: - Flagship Item Detail Hosting Controller (Push Citizenship)

@available(iOS 16.0, *)
@objc public final class PPInventoryItemDetailHostingController: UIViewController {
    private let item: PetAccessory
    private weak var viewModel: PPInventoryListViewModel?
    private let onOpenFullEditor: (() -> Void)?
    private let onOpenPOS: (() -> Void)?
    private let onAdjustQuantity: ((Int) -> Void)?
    private let onToggleStock: (() -> Void)?
    private let onDelete: (() -> Void)?

    init(
        item: PetAccessory,
        viewModel: PPInventoryListViewModel? = nil,
        onOpenFullEditor: (() -> Void)? = nil,
        onOpenPOS: (() -> Void)? = nil,
        onAdjustQuantity: ((Int) -> Void)? = nil,
        onToggleStock: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.item = item
        self.viewModel = viewModel
        self.onOpenFullEditor = onOpenFullEditor
        self.onOpenPOS = onOpenPOS
        self.onAdjustQuantity = onAdjustQuantity
        self.onToggleStock = onToggleStock
        self.onDelete = onDelete
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = nil

        let detailView = PPInventoryItemDetailView(
            item: item,
            viewModel: viewModel,
            onDismiss: { [weak self] in
                guard let self = self else { return }
                if let nav = self.navigationController {
                    nav.popViewController(animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            },
            onOpenFullEditor: { [weak self] in
                guard let self = self else { return }
                if let block = self.onOpenFullEditor {
                    block()
                } else {
                    let editVC = AddAccessoryViewController(accessory: self.item)
                    editVC.showTypeRow = false
                    self.navigationController?.pushViewController(editVC, animated: true)
                }
            },
            onOpenPOS: { [weak self] in
                guard let self = self else { return }
                if let block = self.onOpenPOS {
                    block()
                } else if let controller = PPAdminRouteFactory.viewController(routeIdentifier: "pos", payload: self.item.accessoryID) {
                    self.navigationController?.pushViewController(controller, animated: true)
                }
            },
            onAdjustQuantity: { [weak self] delta in
                self?.onAdjustQuantity?(delta)
            },
            onToggleStock: { [weak self] in
                self?.onToggleStock?()
            },
            onDelete: { [weak self] in
                guard let self = self else { return }
                self.onDelete?()
                if let nav = self.navigationController {
                    nav.popViewController(animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            }
        )

        let host = UIHostingController(rootView: detailView)
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
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}

// MARK: - Legacy Compatibility Shim

@available(iOS 16.0, *)
private struct PPInventoryItemDossierSheet: View {
    let item: PetAccessory
    @ObservedObject var viewModel: PPInventoryListViewModel
    let onOpenFullEditor: () -> Void
    let onOpenPOS: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PPInventoryItemDetailView(
            item: item,
            viewModel: viewModel,
            onDismiss: { dismiss() },
            onOpenFullEditor: {
                dismiss()
                onOpenFullEditor()
            },
            onOpenPOS: {
                dismiss()
                onOpenPOS()
            },
            onAdjustQuantity: { delta in
                viewModel.adjustQuantity(by: delta, for: item)
            },
            onToggleStock: {
                viewModel.toggleStockAvailability(for: item)
            },
            onDelete: {
                dismiss()
                viewModel.deleteAccessory(item)
            }
        )
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
    @State private var isBranchPickerPresented: Bool = false
    @State private var branchPickerExcludedID: String? = nil

    private var currentLiveUnit: PPLivePetInventoryUnit? {
        switch context {
        case .reserve(let unit), .transfer(let unit), .quarantine(let unit), .releaseQuarantine(let unit), .mortality(let unit), .price(let unit), .remove(let unit):
            return model.units.first(where: { $0.id == unit.id }) ?? unit
        default:
            return nil
        }
    }

    private func effectiveCurrentBranchID(for unit: PPLivePetInventoryUnit) -> String {
        let raw = unit.currentBranchID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            if let canonical = PPLivePetInventoryService.canonicalBranch(for: raw, in: model.branches) {
                return canonical.id
            }
            return raw
        }
        let itemBranch = (model.item.resolvedBranchID() ?? model.item.storeID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !itemBranch.isEmpty {
            if let canonical = PPLivePetInventoryService.canonicalBranch(for: itemBranch, in: model.branches) {
                return canonical.id
            }
            return itemBranch
        }
        return ""
    }

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
        case .price(let unit):
            let liveUnit = model.units.first(where: { $0.id == unit.id }) ?? unit
            if let unitPrice = liveUnit.sellingPrice, unitPrice > 0 {
                _standardPriceText = State(initialValue: String(format: "%g", unitPrice))
            } else if standardPrice > 0 {
                _standardPriceText = State(initialValue: String(format: "%g", standardPrice))
            }
        case .reserve(let unit):
            let liveUnit = model.units.first(where: { $0.id == unit.id }) ?? unit
            let rawBranch = liveUnit.currentBranchID.isEmpty ? (model.item.resolvedBranchID() ?? model.item.storeID ?? "") : liveUnit.currentBranchID
            let canonical = PPLivePetInventoryService.canonicalBranch(for: rawBranch, in: model.branches)?.id ?? rawBranch
            _selectedBranchID = State(initialValue: canonical)
        case .transfer(let unit):
            let liveUnit = model.units.first(where: { $0.id == unit.id }) ?? unit
            let rawBranch = liveUnit.currentBranchID.isEmpty ? (model.item.resolvedBranchID() ?? model.item.storeID ?? "") : liveUnit.currentBranchID
            let canonicalCurrent = PPLivePetInventoryService.canonicalBranch(for: rawBranch, in: model.branches)?.id ?? rawBranch
            let targetBranch = model.branches.first(where: {
                let bCanonical = PPLivePetInventoryService.canonicalBranch(for: $0.id, in: model.branches)?.id ?? $0.id
                return bCanonical != canonicalCurrent
            })?.id ?? ""
            _selectedBranchID = State(initialValue: targetBranch)
        case .reservation(let reservation):
            _selectedBranchID = State(initialValue: reservation.branchID)
            _customerName = State(initialValue: reservation.customerName)
            _customerPhone = State(initialValue: reservation.customerPhone)
            _cashReceivedText = State(initialValue: String(format: "%.2f", reservation.total))
        case .intake:
            let defaultBranch = (model.item.resolvedBranchID() ?? model.item.storeID ?? BranchContextStore.shared.activeBranch?.branchID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalDefault = PPLivePetInventoryService.canonicalBranch(for: defaultBranch, in: model.branches)?.id ?? defaultBranch
            _selectedBranchID = State(initialValue: canonicalDefault)
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
                                .font(Font.custom("Beiruti-SemiBold", size: 13))
                                .foregroundStyle(Color(uiColor: .ppError))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppError).opacity(0.20), lineWidth: 0.75))
                        }

                        actionButtons
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(operationTitle)
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    AdminSquircleCloseButton {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .disabled(model.isMutating)
                }
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $isBranchPickerPresented) {
            PPBranchSelectionStudioSheet(
                branches: model.branches,
                selectedBranchID: $selectedBranchID,
                excludedBranchID: branchPickerExcludedID
            )
        }
        .onAppear {
            normalizeBranchSelection()
        }
        .onChange(of: model.branches) { _ in
            normalizeBranchSelection()
        }
        .onChange(of: model.units) { _ in
            normalizeBranchSelection()
        }
    }

    private var operationHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(operationColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: operationIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(operationColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(operationTitle)
                    .font(Font.custom("Beiruti-Bold", size: 19))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(operationHint)
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
    }

    private var operationColor: Color {
        switch context {
        case .intake:
            return Color(uiColor: .ppSuccess)
        case .transfer:
            return AdminSurface.primary
        case .reserve, .reservation:
            return Color(uiColor: .ppWarning)
        case .quarantine, .releaseQuarantine:
            return Color(uiColor: .ppInfo)
        case .mortality, .remove:
            return Color(uiColor: .ppError)
        case .price:
            return AdminSurface.primary
        case .groupAdjustment, .migrate:
            return Color(uiColor: .ppInfo)
        case .archive:
            return Color(uiColor: .ppTextSecondary)
        }
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
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminCommandInk.secondary)
                if selectedMode == .individual {
                    if model.item.quantity > 100 {
                        Text(Language.get("LivePet_Migration_TooMany", alter: "لا يمكن تحويل أكثر من 100 حيوان قديم دفعة واحدة. طابق الكمية أولاً أو استخدم وضع المجموعة."))
                            .font(Font.custom("Beiruti-SemiBold", size: 13))
                            .foregroundStyle(Color(uiColor: .ppError))
                    } else if model.item.quantity == 0 {
                        Text(Language.get("LivePet_Migration_Empty", alter: "سيتم اعتماد التتبع الفردي دون سجلات حالية، ويمكنك إضافة الحيوانات بعد ذلك."))
                            .font(Font.custom("Beiruti-Regular", size: 13))
                            .foregroundStyle(AdminCommandInk.secondary)
                    } else {
                        migrationUnitFields
                    }
                    decimalField(Language.get("LivePet_Standard_SellingPrice_QAR", alter: "السعر القياسي (ر.ق)"), text: $standardPriceText)
                }

            case .intake:
                branchPicker(excluding: nil)
                if model.mode == .individual {
                    unitDraftFields($unitDrafts[0], showRemove: false)
                } else {
                    numberField(Language.get("LivePet_Group_Quantity", alter: "الكمية المضافة"), text: $quantityText)
                    if model.canViewCosts {
                        decimalField(Language.get("LivePet_Group_PurchaseCost", alter: "تكلفة الوحدة"), text: $costText)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AdminSurface.primary)
                            Text(Language.get("LivePet_Unit_AcquisitionDate", alter: "تاريخ الاستلام"))
                                .font(Font.custom("Beiruti-SemiBold", size: 13))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        DatePicker("", selection: $unitDrafts[0].acquisitionDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }
                    textField(Language.get("LivePet_Supplier_Placeholder", alter: "المورد (اختياري)"), text: $supplier, icon: "person.crop.square")
                    textField(Language.get("LivePet_Group_Notes_Placeholder", alter: "ملاحظات الإدخال (اختيارية)"), text: $notes, icon: "note.text")
                }

            case .reserve(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                unitIdentity(unit)

                // Approved Reservation Price Banner
                let unitPrice = unit.sellingPrice ?? model.item.standardSellingPrice?.doubleValue ?? model.item.price.doubleValue
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(unitPrice > 0 ? AdminSurface.primary.opacity(0.12) : Color(uiColor: .ppError).opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: unitPrice > 0 ? "tag.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(unitPrice > 0 ? AdminSurface.primary : Color(uiColor: .ppError))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("LivePet_Reservation_SellingPrice_Title", alter: "سعر البيع المعتمد للحجز"))
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(unitPrice > 0 ? PetAccessory.formatCurrency(NSNumber(value: unitPrice)) : Language.get("LivePet_Error_MissingUnitPrice", alter: "حدد سعر بيع صالحاً للحيوان قبل حجزه أو بيعه."))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(unitPrice > 0 ? AdminSurface.primaryText : Color(uiColor: .ppError))
                    }
                    Spacer()
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(unitPrice > 0 ? AdminSurface.hairline : Color(uiColor: .ppError).opacity(0.3), lineWidth: 0.75))

                textField(Language.get("LivePet_Customer_Name", alter: "اسم العميل"), text: $customerName, icon: "person.fill")
                textField(Language.get("LivePet_Customer_Phone_Prompt", alter: "رقم هاتف العميل (مطلوب - ٦ أرقام على الأقل)"), text: $customerPhone, icon: "phone.fill", keyboard: .phonePad)

                // Physical branch lock to prevent POS_INVENTORY_UNIT_BRANCH_MISMATCH
                let currentBranch = effectiveCurrentBranchID(for: unit)
                currentBranchDossierCard(currentBranch)
                Text(Language.get("LivePet_Reservation_Branch_Locked_Hint", alter: "فرع الحجز محدد تلقائياً بنفس مقر تواجد الحيوان الفعلي."))
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminCommandInk.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("LivePet_Reservation_ValidUntil", alter: "صلاحية الحجز حتى"))
                            .font(Font.custom("Beiruti-SemiBold", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    DatePicker("", selection: $reservationValidUntil, in: Date().addingTimeInterval(60)..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }

            case .reservation(let reservation):
                let isExpired = reservation.validUntil != nil && reservation.validUntil! <= Date()
                if isExpired {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(uiColor: .ppError))
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .ppError).opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Language.get("LivePet_Reservation_Expired_Warning", alter: "انتهت صلاحية هذا الحجز. يجب تحرير الحجز أولاً ليعود الحيوان إلى المخزون المتاح."))
                                .font(Font.custom("Beiruti-Bold", size: 13))
                                .foregroundStyle(Color(uiColor: .ppError))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppError).opacity(0.20), lineWidth: 0.75))
                }
                reservationSummary(reservation)
                if reservation.paymentMethod == "cash" && !isExpired {
                    decimalField(Language.get("LivePet_Cash_Received", alter: "المبلغ النقدي المستلم"), text: $cashReceivedText)
                }
                if !model.canReleaseReservations {
                    Text(Language.get("LivePet_Reservation_Release_Permission_Hint", alter: "تحرير الحجز يتطلب صلاحية البيع وصلاحية رد المدفوعات."))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminCommandInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .transfer(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                unitIdentity(unit)
                let currentBranch = effectiveCurrentBranchID(for: unit)
                currentBranchDossierCard(currentBranch)
                let canonicalCurrent = PPLivePetInventoryService.canonicalBranch(for: currentBranch, in: model.branches)?.id ?? currentBranch
                let otherBranches = model.branches.filter {
                    let bCanonical = PPLivePetInventoryService.canonicalBranch(for: $0.id, in: model.branches)?.id ?? $0.id
                    return bCanonical != canonicalCurrent
                }
                if otherBranches.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Color(uiColor: .ppWarning))
                        Text(Language.get("LivePet_NoOtherBranches", alter: "لا توجد فروع أخرى مسجلة أو مصرح بها للنقل إليها."))
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .foregroundStyle(Color(uiColor: .ppWarning))
                    }
                    .padding(12)
                    .background(Color(uiColor: .ppWarning).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    branchPicker(excluding: canonicalCurrent)
                }
                textField(Language.get("LivePet_Transfer_Reason_Prompt", alter: "سبب النقل (مطلوب - ٣ أحرف على الأقل)"), text: $reason, icon: "arrow.left.arrow.right")

            case .quarantine(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                unitIdentity(unit)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppInfo))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .ppInfo).opacity(0.12), in: Circle())
                    Text(Language.get("LivePet_Quarantine_Biosecurity_Notice", alter: "سيتم عزل هذا الحيوان طبياً وفصل سجله فوراً عن قنوات العرض والبيع حتى إصدار إذن إخراج معتمد."))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(uiColor: .ppInfo).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                textField(Language.get("LivePet_Quarantine_Reason_Prompt", alter: "سبب وتفاصيل الإدخال إلى الحجر (مطلوب - ٣ أحرف على الأقل)"), text: $reason, icon: "cross.case")

            case .releaseQuarantine(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                unitIdentity(unit)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Circle())
                    Text(Language.get("LivePet_Release_Medical_Clearance_Notice", alter: "سيُعاد الحيوان إلى المخزون المتاح للبيع ويُعاد حساب متوسطات أسعار العرض بالكتالوج."))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                textField(Language.get("LivePet_Release_Quarantine_Reason_Prompt", alter: "تقرير وتفاصيل الإخراج من الحجر (مطلوب - ٣ أحرف على الأقل)"), text: $reason, icon: "checkmark.shield")

            case .remove(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                unitIdentity(unit)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppError))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .ppError).opacity(0.12), in: Circle())
                    Text(Language.get("LivePet_Remove_Audit_Notice", alter: "إزالة السجل المتاح من المخزون مع توثيق الحركة في سجل التدقيق المالي والإداري."))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                textField(Language.get("LivePet_Remove_Reason_Prompt", alter: "سبب الشطب من المخزون (مطلوب - ٣ أحرف على الأقل)"), text: $reason, icon: "minus.circle")

            case .mortality(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                unitIdentity(unit)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "heart.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(uiColor: .ppError))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .ppError).opacity(0.12), in: Circle())
                    Text(Language.get("LivePet_Mortality_Finality_Notice", alter: "تسجيل حالة الوفاة هو إجراء نهائي لا يمكن الرجوع عنه، ويقوم الخادم تلقائياً بإسقاط العهدة وتسوية أي حجز نشط."))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .ppError))
                        Text(Language.get("LivePet_Mortality_Cause", alter: "سبب الوفاة"))
                            .font(Font.custom("Beiruti-SemiBold", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    Menu {
                        ForEach(mortalityCauses) { cause in
                            Button { causeCode = cause.code } label: { Text(cause.title) }
                        }
                    } label: {
                        HStack {
                            Text(mortalityCauses.first(where: { $0.code == causeCode })?.title ?? causeCode)
                                .font(Font.custom("Beiruti-Bold", size: 15))
                                .foregroundStyle(AdminSurface.primaryText)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AdminCommandInk.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("LivePet_Mortality_ObservedAt", alter: "وقت ملاحظة الوفاة"))
                            .font(Font.custom("Beiruti-SemiBold", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    DatePicker("", selection: $observedDeathAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }
                textField(Language.get("LivePet_Mortality_Reason_Prompt", alter: "تقرير وتفاصيل الوفاة (مطلوب - ٣ أحرف على الأقل)"), text: $reason, icon: "text.alignleft")
                textField(Language.get("LivePet_Mortality_Notes", alter: "ملاحظات داخلية (اختيارية)"), text: $notes, icon: "note.text")
                textField(Language.get("LivePet_Mortality_VetReference", alter: "مرجع الطبيب البيطري (اختياري)"), text: $veterinaryReference, icon: "cross.case")

            case .price(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                unitIdentity(unit)
                decimalField(Language.get("LivePet_Unit_SellingPrice", alter: "سعر البيع الجديد"), text: $standardPriceText)

            case .groupAdjustment:
                numberField(Language.get("LivePet_Group_TargetQuantity", alter: "الكمية الفعلية الحالية"), text: $quantityText)
                textField(Language.get("LivePet_Adjustment_Reason", alter: "سبب المطابقة"), text: $reason, icon: "slider.horizontal.3")

            case .archive:
                textField(Language.get("LivePet_Operation_Reason", alter: "سبب الإجراء"), text: $reason, icon: "archivebox")
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
    }

    private func unitIdentity(_ unit: PPLivePetInventoryUnit) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .ppSuccess).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(uiColor: .ppSuccess))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: (unit.ringTag.isEmpty ? unit.id : unit.ringTag).normalizedEnglishDigits)
                    .font(PPBrandFont.bold(size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                HStack(spacing: 6) {
                    Text(liveUnitStatus(unit.status))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(liveUnitStatusColor(unit.status))
                    let unitBranchID = effectiveCurrentBranchID(for: unit)
                    if !unitBranchID.isEmpty {
                        Text("•")
                            .foregroundStyle(AdminCommandInk.tertiary)
                        Text(localizedBranchName(unitBranchID, id: unitBranchID))
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
    }

    private func localizedBranchName(_ name: String, id: String) -> String {
        let lookupKey = id.isEmpty ? name : id
        if lookupKey == "main_store" || lookupKey.lowercased() == "main_store" || lookupKey.lowercased() == "main store" {
            return Language.get("MainStore", alter: "المتجر الرئيسي")
        }
        if lookupKey.lowercased().contains("reservation") {
            return Language.get("ReservationBranch", alter: "فرع الحجوزات")
        }
        if let canonical = PPLivePetInventoryService.canonicalBranch(for: lookupKey, in: model.branches) {
            return canonical.fullMeaningfulTitle
        }
        if let branch = model.branches.first(where: { $0.id == id }) {
            return branch.fullMeaningfulTitle
        }
        if let cached = PPLivePetInventoryService.branch(for: id) {
            return cached.fullMeaningfulTitle
        }
        if let b = PPBranchContextManager.shared().branch(withID: id) {
            return b.localizedName()
        }
        return name.isEmpty ? id : name
    }

    private func currentBranchDossierCard(_ branchID: String) -> some View {
        let branch = PPLivePetInventoryService.canonicalBranch(for: branchID, in: model.branches)
        let branchTitle: String
        let branchCode: String
        let branchAddress: String

        if let branch {
            branchTitle = branch.displayName
            branchCode = branch.code
            branchAddress = branch.address
        } else if branchID.isEmpty || branchID == "main_store" {
            branchTitle = Language.get("MainStore", alter: "المتجر الرئيسي")
            branchCode = ""
            branchAddress = ""
        } else {
            var clean = branchID
            if let parenIdx = clean.range(of: " (") {
                clean = String(clean[..<parenIdx.lowerBound])
            }
            branchTitle = clean
            branchCode = ""
            branchAddress = ""
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.left.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(Language.get("LivePet_Source_Branch", alter: "الفرع الحالي (نقطة الانطلاق)"))
                    .font(Font.custom("Beiruti-SemiBold", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.08))
                        .frame(width: 42, height: 42)
                    Image(systemName: "building.2")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(branchTitle)
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                        if !branchCode.isEmpty {
                            Text(verbatim: "# " + branchCode.normalizedEnglishDigits)
                                .font(PPBrandFont.bold(size: 11))
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    if !branchAddress.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                            Text(branchAddress)
                                .font(Font.custom("Beiruti-Regular", size: 12))
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                Text(Language.get("CurrentCustody", alter: "العهدة الحالية"))
                    .font(Font.custom("Beiruti-Bold", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(AdminSurface.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.5))
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func reservationSummary(_ reservation: PPLivePetReservation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reservation.customerName.isEmpty ? reservation.customerPhone : reservation.customerName)
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Text(PetAccessory.formatCurrency(NSNumber(value: reservation.total)))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primary)
            }
            Text(String(format: Language.get("LivePet_Reservation_Branch_Format", alter: "الفرع: %@"), localizedBranchName(reservation.branchID, id: reservation.branchID)))
                .font(Font.custom("Beiruti-Regular", size: 12))
                .foregroundStyle(AdminCommandInk.secondary)
            if let validUntil = reservation.validUntil {
                Text(String(format: Language.get("LivePet_Reservation_Until_Format", alter: "صلاحية الحجز حتى %@"), validUntil.formatted(date: .abbreviated, time: .shortened)))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(validUntil <= Date() ? Color(uiColor: .ppError) : AdminCommandInk.secondary)
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if case .reservation(let reservation) = context,
               let validUntil = reservation.validUntil, validUntil <= Date() {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        let ok = await model.cancel(reservation: reservation)
                        if ok { dismiss() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if model.isMutating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(Language.get("LivePet_Release_Reservation", alter: "تحرير الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(uiColor: .ppWarning), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(CatalogPressStyle())
                .disabled(!model.canReleaseReservations || model.isMutating)
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    performAction()
                } label: {
                    HStack(spacing: 10) {
                        if model.isMutating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: operationActionIcon)
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(model.isMutating ? Language.get("LivePet_Operation_Processing", alter: "جارٍ التأكيد من الخادم...") : actionTitle)
                            .font(Font.custom("Beiruti-Bold", size: 17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        LinearGradient(
                            colors: [operationColor, operationColor.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: operationColor.opacity(0.35), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(CatalogPressStyle())
                .disabled(model.isMutating)

                if case .reservation = context {
                    releaseReservationButton
                }
            }
        }
    }

    private var operationActionIcon: String {
        switch context {
        case .intake: return "plus.circle.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .reserve: return "calendar.badge.plus"
        case .reservation: return "checkmark.seal.fill"
        case .quarantine: return "cross.case.fill"
        case .releaseQuarantine: return "checkmark.shield.fill"
        case .mortality: return "heart.slash.fill"
        case .price: return "tag.fill"
        case .remove: return "minus.circle.fill"
        case .groupAdjustment: return "slider.horizontal.3"
        case .migrate: return "arrow.triangle.branch"
        case .archive: return "archivebox.fill"
        }
    }

    private var releaseReservationButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                if case .reservation(let reservation) = context {
                    let ok = await model.cancel(reservation: reservation)
                    if ok { dismiss() }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 15, weight: .bold))
                Text(Language.get("LivePet_Release_Reservation", alter: "تحرير الحجز"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
            }
            .foregroundStyle(Color(uiColor: .ppWarning))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(uiColor: .ppWarning).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppWarning).opacity(0.24), lineWidth: 0.75))
        }
        .buttonStyle(CatalogPressStyle())
        .disabled(!model.canReleaseReservations || model.isMutating)
    }

    private var migrationUnitFields: some View {
        VStack(spacing: 12) {
            ForEach($unitDrafts) { $unit in
                unitDraftFields($unit, showRemove: false)
            }
        }
    }

    private func unitDraftFields(_ unit: Binding<PPLivePetUnitDraft>, showRemove: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            textField(
                Language.get("LivePet_Ring_Placeholder", alter: "رقم الحلقة أو الشريحة"),
                text: unit.ringTag,
                icon: "barcode.viewfinder"
            )

            HStack(spacing: 12) {
                decimalField(
                    Language.get("LivePet_Unit_SellingPrice", alter: "سعر البيع"),
                    text: unit.sellingPriceText,
                    icon: "tag.fill"
                )
                if model.canViewCosts {
                    decimalField(
                        Language.get("LivePet_Unit_PurchaseCost", alter: "تكلفة الشراء"),
                        text: unit.purchaseCostText,
                        icon: "creditcard.fill"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("LivePet_Unit_AcquisitionDate", alter: "تاريخ الاستلام"))
                        .font(Font.custom("Beiruti-SemiBold", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                DatePicker("", selection: unit.acquisitionDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }

            textField(
                Language.get("LivePet_Supplier_Placeholder", alter: "المورد (اختياري)"),
                text: unit.supplier,
                icon: "person.crop.square"
            )

            textField(
                Language.get("LivePet_Unit_Notes_Placeholder", alter: "ملاحظات داخلية (اختيارية)"),
                text: unit.notes,
                icon: "note.text"
            )
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
    }

    private func textField(_ title: String, text: Binding<String>, icon: String? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
                Text(title)
                    .font(Font.custom("Beiruti-SemiBold", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            HStack(spacing: 8) {
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .font(Font.custom("Beiruti-Regular", size: 16))

                if icon == "barcode.viewfinder" {
                    AdminBarcodeScanButton { scanned in
                        text.wrappedValue = scanned
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decimalField(_ title: String, text: Binding<String>, icon: String? = "tag.fill") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
                Text(title)
                    .font(Font.custom("Beiruti-SemiBold", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            HStack(spacing: 8) {
                TextField(title, text: text)
                    .englishNumericInput(text: text, allowsDecimal: true)
                    .font(PPBrandFont.bold(size: 16))
                Text("ر.ق")
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberField(_ title: String, text: Binding<String>, icon: String? = "number") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
                Text(title)
                    .font(Font.custom("Beiruti-SemiBold", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            TextField(title, text: text)
                .englishNumericInput(text: text, allowsDecimal: false)
                .font(PPBrandFont.bold(size: 16))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readOnlyField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Font.custom("Beiruti-SemiBold", size: 13))
                .foregroundStyle(AdminSurface.secondaryText)
            Text(value.isEmpty ? Language.get("LivePet_Branch_Unknown", alter: "الفرع غير محدد") : value)
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func branchPicker(excluding excludedID: String?) -> some View {
        let canonicalExcluded = excludedID.flatMap { PPLivePetInventoryService.canonicalBranch(for: $0, in: model.branches)?.id ?? $0 }
        let canonicalSelected = PPLivePetInventoryService.canonicalBranch(for: selectedBranchID, in: model.branches)?.id ?? selectedBranchID
        let isExcluded = canonicalExcluded != nil && !canonicalSelected.isEmpty && canonicalSelected == canonicalExcluded
        let selectedBranch = isExcluded ? nil : PPLivePetInventoryService.canonicalBranch(for: selectedBranchID, in: model.branches)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("LivePet_Destination_Branch", alter: "الفرع المستهدف"))
                    .font(Font.custom("Beiruti-SemiBold", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer()
                if let b = selectedBranch, b.isDefault {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text(Language.get("DefaultBranch", alter: "الفرع الافتراضي"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundStyle(Color(uiColor: .ppSuccess))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                branchPickerExcludedID = canonicalExcluded
                isBranchPickerPresented = true
            } label: {
                if let b = selectedBranch {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(b.displayName)
                                    .font(Font.custom("Beiruti-Bold", size: 16))
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .lineLimit(1)
                                if !b.code.isEmpty {
                                    Text(verbatim: "# " + b.code.normalizedEnglishDigits)
                                        .font(PPBrandFont.bold(size: 11))
                                        .foregroundStyle(AdminSurface.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AdminSurface.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }

                            HStack(spacing: 8) {
                                if !b.address.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.system(size: 10))
                                        Text(b.address)
                                            .font(Font.custom("Beiruti-Regular", size: 12))
                                    }
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .lineLimit(1)
                                }

                                if !b.stockModeTitle.isEmpty {
                                    Text(b.stockModeTitle)
                                        .font(Font.custom("Beiruti-Regular", size: 11))
                                        .foregroundStyle(Color(uiColor: .ppInfo))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Color(uiColor: .ppInfo).opacity(0.08), in: Capsule())
                                }
                            }
                        }

                        Spacer(minLength: 6)

                        HStack(spacing: 4) {
                            Text(Language.get("Change", alter: "تغيير"))
                                .font(Font.custom("Beiruti-Bold", size: 13))
                                .foregroundStyle(AdminSurface.primary)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 0.5))
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                } else {
                    HStack {
                        Image(systemName: "building.2")
                            .font(.system(size: 16))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("LivePet_Select_Branch", alter: "اضغط لاختيار الفرع المستهدف..."))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminCommandInk.tertiary)
                        Spacer()
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AdminCommandInk.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }
            }
            .buttonStyle(CatalogPressStyle())
            .contextMenu {
                ForEach(model.branches.filter {
                    let bCanonical = PPLivePetInventoryService.canonicalBranch(for: $0.id, in: model.branches)?.id ?? $0.id
                    return bCanonical != canonicalExcluded
                }) { branch in
                    Button {
                        selectedBranchID = branch.id
                    } label: {
                        Text(branch.displayName)
                        if selectedBranchID == branch.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var operationTitle: String {
        switch context {
        case .migrate: return Language.get("LivePet_Migrate_Title", alter: "اعتماد نمط المخزون")
        case .intake: return Language.get("LivePet_Intake_Title", alter: "إضافة مخزون")
        case .reserve: return Language.get("LivePet_Reserve_Title", alter: "حجز لعميل")
        case .reservation: return Language.get("LivePet_Reservation_Details_Title", alter: "تفاصيل الحجز")
        case .transfer: return Language.get("LivePet_Transfer_Title", alter: "نقل إلى فرع")
        case .quarantine: return Language.get("LivePet_Quarantine_Title", alter: "إدخال الحجر الصحي")
        case .releaseQuarantine: return Language.get("LivePet_Release_Quarantine_Title", alter: "إخراج من الحجر الصحي")
        case .mortality: return Language.get("LivePet_Mortality_Title", alter: "تسجيل وفاة")
        case .price: return Language.get("LivePet_Edit_Price_Title", alter: "تعديل سعر البيع")
        case .remove: return Language.get("LivePet_Remove_Title", alter: "إزالة من المخزون")
        case .groupAdjustment: return Language.get("LivePet_Group_Adjust_Title", alter: "مطابقة كمية المجموعة")
        case .archive(let target):
            return target
                ? Language.get("LivePet_Archive_Title", alter: "أرشفة سجل الكتالوج")
                : Language.get("LivePet_Restore_Title", alter: "استعادة سجل الكتالوج")
        }
    }

    private var operationIcon: String {
        switch context {
        case .migrate: return "arrow.triangle.branch"
        case .intake: return "plus.circle.fill"
        case .reserve: return "calendar.badge.plus"
        case .reservation: return "creditcard.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .quarantine: return "cross.case.fill"
        case .releaseQuarantine: return "checkmark.shield.fill"
        case .mortality: return "heart.slash.fill"
        case .price: return "tag.fill"
        case .remove: return "minus.circle.fill"
        case .groupAdjustment: return "slider.horizontal.3"
        case .archive(let target): return target ? "archivebox.fill" : "arrow.uturn.backward.circle.fill"
        }
    }

    private var operationHint: String {
        switch context {
        case .migrate: return Language.get("LivePet_Migrate_Hint", alter: "اختر نمط الإدارة المناسب لهذا الحيوان لتأكيد هيكل التتبع المعتمد.")
        case .intake: return Language.get("LivePet_Intake_Hint", alter: "تضاف الكمية أو الهوية داخل معاملة واحدة مع حركة مخزون وسجل تدقيق.")
        case .reserve: return Language.get("LivePet_Reserve_Hint", alter: "يُحجز الحيوان للعميل حصرياً مع تحديد الفرع ومدة الصلاحية.")
        case .reservation: return Language.get("LivePet_Reservation_Hint", alter: "متابعة بيانات الحجز والدفع أو تحرير الحيوان لإتاحته من جديد.")
        case .transfer: return Language.get("LivePet_Transfer_Hint", alter: "بتغيير فرع العهدة فقط، وتبقى هوية الحيوان وحالته وسجله محفوظة.")
        case .quarantine: return Language.get("LivePet_Quarantine_Hint", alter: "يُعزل الحيوان طبياً ويُمنع بيعه حتى يتم التأكد من سلامته.")
        case .releaseQuarantine: return Language.get("LivePet_Release_Quarantine_Hint", alter: "يُعاد الحيوان إلى المخزون المتاح بعد انتهاء فترة الفحص.")
        case .mortality: return Language.get("LivePet_Mortality_Hint", alter: "يوثق سبب الوفاة رسمياً ويُسوى المخزون مع إلغاء أي حجز قائم.")
        case .price: return Language.get("LivePet_Price_Hint", alter: "يُحدث سعر البيع المعتمد لهذا الحيوان فقط ويُسجل التغيير في السجل.")
        case .remove: return Language.get("LivePet_Remove_Hint", alter: "تتم إزالة هذا السجل مع حفظ التدقيق لضبط المطابقة والعهدة.")
        case .groupAdjustment: return Language.get("LivePet_Group_Adjust_Hint", alter: "تُطابق الكمية الفعلية للمجموعة مع تسجيل الفارق وسبب التسوية.")
        case .archive(let target):
            return target
                ? Language.get("LivePet_Archive_Hint", alter: "يُوقف ظهور السجل في القوائم النشطة دون حذف بياناته أو حركاته السابقة.")
                : Language.get("LivePet_Restore_Hint", alter: "يُعاد السجل إلى الحالة النشطة للاستمرار في إدارته والبيع منه.")
        }
    }

    private var actionTitle: String {
        switch context {
        case .migrate: return Language.get("LivePet_Confirm_Migrate", alter: "تأكيد نمط المخزون")
        case .intake: return Language.get("LivePet_Confirm_Intake", alter: "تأكيد إضافة المخزون")
        case .reserve: return Language.get("LivePet_Confirm_Reserve", alter: "تأكيد الحجز")
        case .reservation: return Language.get("LivePet_Confirm_Sale", alter: "إتمام البيع الآن")
        case .transfer: return Language.get("LivePet_Confirm_Transfer", alter: "تأكيد النقل إلى الفرع")
        case .quarantine: return Language.get("LivePet_Confirm_Quarantine", alter: "تأكيد العزل الطبي")
        case .releaseQuarantine: return Language.get("LivePet_Confirm_Release", alter: "تأكيد الإخراج من الحجر")
        case .mortality: return Language.get("LivePet_Confirm_Mortality", alter: "تسجيل الوفاة رسمياً")
        case .price: return Language.get("LivePet_Confirm_Price", alter: "تحديث سعر البيع")
        case .remove: return Language.get("LivePet_Confirm_Remove", alter: "تأكيد الإزالة")
        case .groupAdjustment: return Language.get("LivePet_Confirm_Group_Adjust", alter: "تأكيد مطابقة الكمية")
        case .archive(let target):
            return target
                ? Language.get("LivePet_Confirm_Archive", alter: "تأكيد الأرشفة")
                : Language.get("LivePet_Confirm_Restore", alter: "تأكيد الاستعادة")
        }
    }

    private var mortalityCauses: [PPLivePetMortalityCause] {
        [
            PPLivePetMortalityCause(code: "ILLNESS", title: Language.get("LivePet_Mortality_Illness", alter: "مرض أو عدوى")),
            PPLivePetMortalityCause(code: "INJURY", title: Language.get("LivePet_Mortality_Injury", alter: "إصابة أو حادث")),
            PPLivePetMortalityCause(code: "NATURAL", title: Language.get("LivePet_Mortality_Natural", alter: "أسباب طبيعية")),
            PPLivePetMortalityCause(code: "UNKNOWN", title: Language.get("LivePet_Mortality_Unknown", alter: "سبب غير محدد"))
        ]
    }

    private func normalizeBranchSelection() {
        if case .transfer(let contextUnit) = context {
            let unit = currentLiveUnit ?? contextUnit
            let currentBranch = effectiveCurrentBranchID(for: unit)
            let canonicalCurrent = PPLivePetInventoryService.canonicalBranch(for: currentBranch, in: model.branches)?.id ?? currentBranch
            let canonicalSelected = PPLivePetInventoryService.canonicalBranch(for: selectedBranchID, in: model.branches)?.id ?? selectedBranchID

            if canonicalSelected.isEmpty || canonicalSelected == canonicalCurrent {
                if let next = model.branches.first(where: {
                    let bCanonical = PPLivePetInventoryService.canonicalBranch(for: $0.id, in: model.branches)?.id ?? $0.id
                    return bCanonical != canonicalCurrent
                })?.id {
                    selectedBranchID = next
                } else {
                    selectedBranchID = ""
                }
            }
        } else if selectedBranchID.isEmpty {
            if let active = BranchContextStore.shared.activeBranch?.branchID, !active.isEmpty {
                let canonicalActive = PPLivePetInventoryService.canonicalBranch(for: active, in: model.branches)?.id ?? active
                selectedBranchID = canonicalActive
            } else if let first = model.branches.first?.id {
                selectedBranchID = first
            }
        }
    }

    private func performAction() {
        validationMessage = nil
        Task {
            let ok: Bool
            switch context {
            case .migrate:
                let cleanPriceText = standardPriceText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                let price = Double(cleanPriceText) ?? 0
                ok = await model.migrate(
                    mode: selectedMode,
                    units: selectedMode == .individual ? unitDrafts : [],
                    standardSellingPrice: price
                )
            case .intake:
                let targetBranch = selectedBranchID.isEmpty ? (BranchContextStore.shared.activeBranch?.branchID ?? model.item.storeID ?? "") : selectedBranchID
                if model.mode == .individual {
                    let cleanCostText = unitDrafts[0].purchaseCostText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                    let cost = Double(cleanCostText) ?? 0
                    ok = await model.intake(
                        mode: .individual,
                        unit: unitDrafts[0],
                        quantity: 1,
                        cost: cost,
                        supplier: unitDrafts[0].supplier.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: unitDrafts[0].notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        branchID: targetBranch
                    )
                } else {
                    let cleanQty = quantityText.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
                    let qty = Int(cleanQty) ?? 0
                    guard qty > 0 else {
                        validationMessage = Language.get("LivePet_Validation_GroupQuantity", alter: "أدخل كمية صحيحة لا تقل عن حيوان واحد.")
                        return
                    }
                    let cleanCostText = costText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                    let cost = Double(cleanCostText) ?? 0
                    ok = await model.intake(
                        mode: .quantity,
                        unit: unitDrafts[0],
                        quantity: qty,
                        cost: cost,
                        supplier: supplier.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        branchID: targetBranch
                    )
                }
            case .reserve(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let cleanPhone = customerPhone.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanPhone.count >= 6 else {
                    validationMessage = Language.get("LivePet_Validation_CustomerPhone", alter: "أدخل رقم هاتف صالحاً للعميل.")
                    return
                }
                let cleanCustomerName = customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Language.get("POS_Default_Customer_Name", alter: "عميل نقطة بيع")
                    : customerName.trimmingCharacters(in: .whitespacesAndNewlines)
                let unitPrice = unit.sellingPrice ?? model.item.standardSellingPrice?.doubleValue ?? model.item.price.doubleValue
                guard unitPrice > 0 else {
                    validationMessage = Language.get("LivePet_Error_MissingUnitPrice", alter: "حدد سعر بيع صالحاً للحيوان قبل حجزه أو بيعه.")
                    return
                }
                let currentBranch = effectiveCurrentBranchID(for: unit)
                let targetBranch = PPLivePetInventoryService.canonicalBranch(for: currentBranch, in: model.branches)?.id ?? currentBranch
                guard !targetBranch.isEmpty else {
                    validationMessage = Language.get("LivePet_Validation_Branch", alter: "اختر فرع الحجز.")
                    return
                }
                ok = await model.reserve(
                    unit: unit,
                    customerName: cleanCustomerName,
                    phone: cleanPhone,
                    branchID: targetBranch,
                    validUntil: reservationValidUntil
                )
            case .reservation(let reservation):
                if let validUntil = reservation.validUntil, validUntil <= Date() {
                    validationMessage = Language.get("LivePet_Error_ReservationExpired", alter: "انتهت صلاحية الحجز. حرره ثم أنشئ حجزاً جديداً.")
                    return
                }
                let cleanCashText = cashReceivedText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                let cash = Double(cleanCashText) ?? reservation.total
                if reservation.paymentMethod == "cash" && cash < reservation.total {
                    validationMessage = Language.get("LivePet_Validation_Cash", alter: "يجب أن يغطي المبلغ النقدي إجمالي الحجز.")
                    return
                }
                ok = await model.complete(reservation: reservation, cashReceived: cash)
            case .transfer(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let currentBranch = effectiveCurrentBranchID(for: unit)
                let canonicalCurrent = PPLivePetInventoryService.canonicalBranch(for: currentBranch, in: model.branches)?.id ?? currentBranch
                let canonicalTarget = PPLivePetInventoryService.canonicalBranch(for: selectedBranchID, in: model.branches)?.id ?? selectedBranchID

                guard !canonicalTarget.isEmpty else {
                    validationMessage = Language.get("LivePet_Validation_TransferBranch", alter: "اختر فرعاً مختلفاً عن الفرع الحالي.")
                    return
                }
                guard canonicalTarget != canonicalCurrent else {
                    validationMessage = Language.get("LivePet_Validation_TransferBranch", alter: "اختر فرعاً مختلفاً عن الفرع الحالي.")
                    return
                }
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.transfer(
                    unit: unit,
                    sourceBranchID: canonicalCurrent,
                    destinationBranchID: canonicalTarget,
                    reason: trimmedReason
                )
            case .quarantine(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.lifecycle(action: "quarantine_unit", unit: unit, reason: trimmedReason)
            case .releaseQuarantine(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.lifecycle(action: "release_quarantine", unit: unit, reason: trimmedReason)
            case .mortality(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.lifecycle(
                    action: "record_mortality",
                    unit: unit,
                    reason: trimmedReason,
                    causeCode: causeCode,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    veterinaryReference: veterinaryReference.trimmingCharacters(in: .whitespacesAndNewlines),
                    observedDeathAt: observedDeathAt
                )
            case .price(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let cleanPriceText = standardPriceText.normalizedEnglishDigits(allowsDecimal: true).replacingOccurrences(of: ",", with: ".")
                guard let price = Double(cleanPriceText), price > 0, price <= 999_999_999.99 else {
                    validationMessage = Language.get("LivePet_Validation_UnitPrice", alter: "حدد سعر بيع صالحاً لكل حيوان وبحد أقصى منزلتين عشريتين.")
                    return
                }
                ok = await model.updatePrice(unit: unit, price: price)
            case .remove(let contextUnit):
                let unit = currentLiveUnit ?? contextUnit
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.remove(unit: unit, reason: trimmedReason)
            case .groupAdjustment:
                let cleanQty = quantityText.normalizedEnglishDigits(allowsDecimal: false).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let target = Int(cleanQty), target >= 0 else {
                    validationMessage = Language.get("LivePet_Validation_TargetQuantity", alter: "أدخل كمية فعلية صحيحة لا تقل عن صفر.")
                    return
                }
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.adjustGroup(targetQuantity: target, reason: trimmedReason)
            case .archive(let target):
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedReason.count >= 3 else {
                    validationMessage = Language.get("LivePet_Validation_Reason", alter: "اكتب سبباً واضحاً من ثلاثة أحرف على الأقل.")
                    return
                }
                ok = await model.archive(target, reason: trimmedReason)
            }

            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}



// MARK: - Dedicated Branch Selection Studio Sheet

private struct PPBranchSelectionStudioSheet: View {
    let branches: [PPInventoryBranchOption]
    @Binding var selectedBranchID: String
    let excludedBranchID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""

    private var filteredBranches: [PPInventoryBranchOption] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return branches }
        return branches.filter { b in
            b.displayName.lowercased().contains(q) ||
            b.nameAr.lowercased().contains(q) ||
            b.nameEn.lowercased().contains(q) ||
            b.code.lowercased().contains(q) ||
            b.address.lowercased().contains(q) ||
            b.phone.contains(q)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        // Search Bar Container
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                            TextField(Language.get("SearchBranch_Placeholder", alter: "ابحث بالاسم، الكود، المنطقة أو الهاتف..."), text: $searchQuery)
                                .font(Font.custom("Beiruti-Regular", size: 15))
                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

                        // Branches Count Banner
                        HStack {
                            Text(String(format: Language.get("AvailableBranchesCount", alter: "%ld فرع متاح"), filteredBranches.count))
                                .font(Font.custom("Beiruti-Bold", size: 13))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        // Branch Cards Stack
                        VStack(spacing: 10) {
                            ForEach(filteredBranches) { branch in
                                branchOptionCard(branch)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("SelectDestinationBranch", alter: "اختيار الفرع المستهدف"))
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    AdminSquircleCloseButton {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func branchOptionCard(_ branch: PPInventoryBranchOption) -> some View {
        let canonicalSelected = PPLivePetInventoryService.canonicalBranch(for: selectedBranchID, in: branches)?.id ?? selectedBranchID
        let canonicalExcluded = excludedBranchID.flatMap { PPLivePetInventoryService.canonicalBranch(for: $0, in: branches)?.id ?? $0 }
        let canonicalBranchId = PPLivePetInventoryService.canonicalBranch(for: branch.id, in: branches)?.id ?? branch.id

        let isSelected = !canonicalSelected.isEmpty && canonicalSelected == canonicalBranchId
        let isCurrent = canonicalExcluded != nil && !canonicalExcluded!.isEmpty && canonicalBranchId == canonicalExcluded!

        return Button {
            if !isCurrent {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                selectedBranchID = branch.id
                dismiss()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // Radio Selection Jewel (Right in RTL)
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .strokeBorder(AdminSurface.hairline, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                    }
                }

                // Building Jewel
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color(uiColor: .ppSuccess).opacity(0.12) : AdminSurface.primary.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: isSelected ? "building.2.fill" : "building.2")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? Color(uiColor: .ppSuccess) : AdminSurface.primary)
                }

                // Branch Details Track
                VStack(alignment: .leading, spacing: 4) {
                    // Top: Name + Default Badge
                    HStack(spacing: 6) {
                        Text(branch.displayName)
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(isCurrent ? AdminSurface.secondaryText : AdminSurface.primaryText)
                            .lineLimit(1)

                        if !branch.code.isEmpty {
                            Text(verbatim: "# " + branch.code.normalizedEnglishDigits)
                                .font(PPBrandFont.bold(size: 11))
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }

                        if branch.isDefault {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                Text(Language.get("DefaultBranch", alter: "الفرع الافتراضي"))
                                    .font(Font.custom("Beiruti-Bold", size: 10))
                            }
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                        }
                    }

                    // Second: English Name if different
                    if !branch.nameEn.isEmpty && branch.nameEn != branch.displayName {
                        Text(branch.nameEn)
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .foregroundStyle(AdminCommandInk.tertiary)
                            .lineLimit(1)
                    }

                    // Third: Address & Location
                    if !branch.address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                                .foregroundStyle(AdminSurface.primary)
                            Text(branch.address)
                                .font(Font.custom("Beiruti-Regular", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    // Fourth: Stock mode & Phone
                    HStack(spacing: 8) {
                        if !branch.stockModeTitle.isEmpty {
                            Text(branch.stockModeTitle)
                                .font(Font.custom("Beiruti-Regular", size: 11))
                                .foregroundStyle(Color(uiColor: .ppInfo))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .ppInfo).opacity(0.08), in: Capsule())
                        }
                        if !branch.phone.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 9))
                                Text(verbatim: branch.phone.normalizedEnglishDigits)
                                    .font(PPBrandFont.medium(size: 11))
                            }
                            .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }

                    if isCurrent {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text(Language.get("LivePet_Current_Source_Branch_Hint", alter: "الفرع الحالي للحيوان (لا يمكن النقل لنفس الفرع)"))
                                .font(Font.custom("Beiruti-Bold", size: 11))
                        }
                        .foregroundStyle(Color(uiColor: .ppWarning))
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color(uiColor: .ppSuccess).opacity(0.06) : (isCurrent ? AdminSurface.control.opacity(0.5) : AdminSurface.surface),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color(uiColor: .ppSuccess).opacity(0.4) : (isCurrent ? Color(uiColor: .ppWarning).opacity(0.2) : AdminSurface.hairline),
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            )
            .opacity(isCurrent ? 0.6 : 1.0)
        }
        .buttonStyle(CatalogPressStyle())
        .disabled(isCurrent)
    }
}

// MARK: - Sovereign Inter-Branch Logistics Conduit Sheet (NextGen First-Principles)

private struct PPStockTransferSheet: View {
    let item: PetAccessory
    let currentBranchID: String
    let availableQuantity: Int
    @State var branches: [PPInventoryBranchOption] = []
    let onComplete: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedBranchID: String = ""
    @State private var transferQuantity: Int = 1
    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showBranchPickerModal: Bool = false
    @State private var branchSearchText: String = ""
    @State private var conduitPulsing: Bool = false

    private var canonicalSourceBranchID: String {
        PPLivePetInventoryService.canonicalBranch(for: currentBranchID, in: branches)?.id ?? currentBranchID
    }

    private var otherBranches: [PPInventoryBranchOption] {
        let sourceID = canonicalSourceBranchID
        return branches.filter {
            let branchCanonicalID = PPLivePetInventoryService.canonicalBranch(for: $0.id, in: branches)?.id ?? $0.id
            return branchCanonicalID != sourceID && $0.id != currentBranchID
        }
    }

    private var filteredBranches: [PPInventoryBranchOption] {
        let trimmed = branchSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return otherBranches }
        return otherBranches.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed) ||
            $0.code.localizedCaseInsensitiveContains(trimmed) ||
            $0.address.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var currentBranchName: String {
        if let canonical = PPLivePetInventoryService.canonicalBranch(for: currentBranchID, in: branches) {
            return canonical.displayName
        }
        return branches.first(where: { $0.id == currentBranchID })?.displayName ??
        (currentBranchID.isEmpty || currentBranchID == "main_store" ? Language.get("MainStore", alter: "المتجر الرئيسي") : currentBranchID)
    }

    private var selectedDestinationBranch: PPInventoryBranchOption? {
        otherBranches.first(where: { $0.id == selectedBranchID })
    }

    private var destinationBranchDisplayName: String {
        selectedDestinationBranch?.displayName ?? Language.get("Stock_Transfer_Select_Branch", alter: "اختر فرع الاستلام (المحول إليه)")
    }

    private var remainingSourceStock: Int {
        max(0, availableQuantity - transferQuantity)
    }

    private var transferRatio: Double {
        guard availableQuantity > 0 else { return 0 }
        return Double(transferQuantity) / Double(availableQuantity)
    }

    private var itemThumbnailURL: URL? {
        PetAccessory.firstImageURL(for: item)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Sovereign Glassmorphic Navigation Bar
            AdminSovereignNavigationBar(
                title: Language.get("Stock_Transfer_Title", alter: "نقل مخزون الصنف بين الفروع"),
                subtitle: Language.get("Stock_Transfer_LiveSync", alter: "مزامنة العهدة الفورية • توثيق الحركة"),
                statusDotColor: Color(uiColor: .ppSuccess),
                isModal: true,
                onBack: {
                    dismiss()
                }
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.system(size: 11, weight: .bold))
                    Text(Language.get("Logistics_Conduit", alter: "ترحيل فروع"))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                }
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // 2. Logistics Twin - Physical Specimen Dossier
                    specimenDigitalTwinCard

                    if let err = errorMessage {
                        errorBanner(err)
                    }

                    // 3. The Bilateral Custody Bridge (Two-Node Interactive Conduit)
                    bilateralCustodyBridge

                    // 4. Quantum Quantity Controller & Custody Proportion Bar
                    quantumQuantityController

                    // 5. Smart Audit Reason & Quick Chips
                    auditReasonSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 120) // clearance for sovereign bottom action dock
            }
        }
        .overlay(alignment: .bottom) {
            sovereignDispatchDock
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showBranchPickerModal) {
            destinationBranchPickerSheet
        }
        .onAppear {
            if let first = otherBranches.first {
                selectedBranchID = first.id
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                conduitPulsing = true
            }
        }
        .task {
            if branches.isEmpty {
                if let loaded = try? await PPLivePetInventoryService.listBranches() {
                    branches = loaded
                    if selectedBranchID.isEmpty, let first = otherBranches.first {
                        selectedBranchID = first.id
                    }
                } else if !PPLivePetInventoryService.cachedBranches.isEmpty {
                    branches = PPLivePetInventoryService.cachedBranches
                    if selectedBranchID.isEmpty, let first = otherBranches.first {
                        selectedBranchID = first.id
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var specimenDigitalTwinCard: some View {
        HStack(spacing: 12) {
            // Visual Specimen Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AdminSurface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )

                if let url = itemThumbnailURL {
                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 76, height: 76)) {
                        ProgressView().tint(AdminSurface.primary)
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: item.isFood ? "fork.knife.circle.fill" : (item.isLivePet ? "pawprint.fill" : "shippingbox.fill"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary.opacity(0.85))
                }
            }
            .frame(width: 76, height: 76)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

            VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 3) {
                Text(item.name)
                    .font(Font.custom("Beiruti-Bold", size: 16.5))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                let catDisplay = item.accessoryCategoryName ?? item.category ?? (item.petMainCategoryID > 0 ? (MainKindsModel.kindName(forID: item.petMainCategoryID) ?? "") : (item.storeName ?? ""))
                HStack(spacing: 6) {
                    if !catDisplay.isEmpty {
                        Text(catDisplay)
                            .font(Font.custom("Beiruti-Medium", size: 11.5))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    if let barcode = item.barcode, !barcode.isEmpty {
                        Text(verbatim: ("#" + barcode).normalizedEnglishDigits)
                            .font(PPBrandFont.bold(size: 10))
                            .foregroundStyle(AdminCommandInk.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: Capsule())
                    }
                }

                // Balance Telemetry Indicator
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 6, height: 6)
                    Text(verbatim: String(format: Language.get("Stock_Transfer_CurrentStockFormat", alter: "المتوفر في عهدة الفرع: %@ وحدة"), availableQuantity.englishDigits).normalizedEnglishDigits)
                        .font(PPBrandFont.bold(size: 12))
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 4)
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
    }

    private var bilateralCustodyBridge: some View {
        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 10) {
            HStack {
                Label(
                    Language.get("Stock_Transfer_Custody_Bridge", alter: "مسار تحويل العهدة بين الفروع"),
                    systemImage: "arrow.triangle.swap"
                )
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundStyle(AdminSurface.secondaryText)

                Spacer()

                Button {
                    showBranchPickerModal = true
                } label: {
                    HStack(spacing: 4) {
                        Text(Language.get("Stock_Transfer_Change_Branch", alter: "تغيير الفرع"))
                            .font(Font.custom("Beiruti-Bold", size: 11.5))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }
            }

            // Two-Node Conduit Container
            VStack(spacing: 8) {
                // Node 1: Source Branch (Origin)
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }

                    VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(currentBranchName)
                                .font(Font.custom("Beiruti-Bold", size: 14.5))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)

                            Text(Language.get("Stock_Transfer_SourceTag", alter: "فرع المصدر"))
                                .font(Font.custom("Beiruti-Bold", size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                                .foregroundStyle(AdminSurface.primary)
                        }

                        Text(Language.get("Stock_Transfer_CurrentHolder", alter: "العهدة الحالية المسجل بها الصنف"))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    // Source Stock Live Projection Pill
                    VStack(alignment: Language.isRTL() ? .leading : .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Text(verbatim: availableQuantity.englishDigits)
                                .font(PPBrandFont.medium(size: 14))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(verbatim: remainingSourceStock.englishDigits)
                                .font(PPBrandFont.bold(size: 16))
                                .foregroundStyle(remainingSourceStock <= 0 ? Color(uiColor: .ppError) : AdminSurface.primaryText)
                        }
                        Text(verbatim: "-\(transferQuantity.englishDigits)")
                            .font(PPBrandFont.bold(size: 11))
                            .foregroundStyle(Color(uiColor: .ppError))
                    }
                }
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )

                // Kinetic Transfer Conduit Vector
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary.opacity(0.1), AdminSurface.primary.opacity(0.4)],
                                startPoint: Language.isRTL() ? .trailing : .leading,
                                endPoint: Language.isRTL() ? .leading : .trailing
                            )
                        )
                        .frame(height: 2)

                    // Floating Pulse Badge
                    HStack(spacing: 5) {
                        Image(systemName: Language.isRTL() ? "arrow.down" : "arrow.down")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color.white)
                        Text(verbatim: String(format: Language.get("Stock_Transfer_TransferringCount", alter: "ترحيل %@ قطعة"), transferQuantity.englishDigits).normalizedEnglishDigits)
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, Color(red: 0.78, green: 0.12, blue: 0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: AdminSurface.primary.opacity(conduitPulsing ? 0.45 : 0.2), radius: conduitPulsing ? 6 : 3, y: 1)

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary.opacity(0.4), Color(uiColor: .ppSuccess).opacity(0.4)],
                                startPoint: Language.isRTL() ? .trailing : .leading,
                                endPoint: Language.isRTL() ? .leading : .trailing
                            )
                        )
                        .frame(height: 2)
                }
                .padding(.vertical, 2)

                // Node 2: Destination Branch (Interactive Recipient)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showBranchPickerModal = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(uiColor: .ppSuccess).opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: "storefront.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(uiColor: .ppSuccess))
                        }

                        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(destinationBranchDisplayName)
                                    .font(Font.custom("Beiruti-Bold", size: 14.5))
                                    .foregroundStyle(selectedBranchID.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)
                                    .lineLimit(1)

                                Text(Language.get("Stock_Transfer_DestTag", alter: "فرع الاستلام"))
                                    .font(Font.custom("Beiruti-Bold", size: 10))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color(uiColor: .ppSuccess))
                            }

                            if let b = selectedDestinationBranch, !b.address.isEmpty {
                                Text(b.address)
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            } else {
                                Text(Language.get("Stock_Transfer_TapToChoose", alter: "اضغط لتحديد الفرع المستقبل للشحنة"))
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }

                        Spacer()

                        // Incoming Indicator
                        VStack(alignment: Language.isRTL() ? .leading : .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(uiColor: .ppSuccess))
                                Text(verbatim: "+\(transferQuantity.englishDigits)")
                                    .font(PPBrandFont.bold(size: 16))
                                    .foregroundStyle(Color(uiColor: .ppSuccess))
                            }
                            Text(Language.get("Stock_Transfer_IncomingLabel", alter: "رصيد وارد"))
                                .font(Language.isRTL() ? Font.custom("Beiruti-Regular", size: 10.5) : .system(size: 10.5))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                selectedBranchID.isEmpty
                                    ? Color(uiColor: .ppSurfaceBorder).opacity(0.7)
                                    : Color(uiColor: .ppSuccess).opacity(0.5),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(CatalogPressStyle())
            }
        }
    }

    private var quantumQuantityController: some View {
        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 12) {
            HStack {
                Label(
                    Language.get("Stock_Transfer_Quantity", alter: "الكمية المراد نقلها"),
                    systemImage: "number.square.fill"
                )
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundStyle(AdminSurface.secondaryText)

                Spacer()

                Text(verbatim: String(format: Language.get("Stock_Transfer_MaxFormat", alter: "الحد الأقصى المتاح: %@"), availableQuantity.englishDigits).normalizedEnglishDigits)
                    .font(Font.custom("Beiruti-Bold", size: 11.5))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            // Sculptural Stepper Block
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Decrement Button
                    Button {
                        if transferQuantity > 1 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                transferQuantity -= 1
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.control)
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                                )
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(transferQuantity > 1 ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.35))
                        }
                    }
                    .buttonStyle(CatalogPressStyle())
                    .disabled(transferQuantity <= 1)

                    Spacer()

                    // Center Numeric Readout
                    VStack(spacing: 1) {
                        Text(verbatim: transferQuantity.englishDigits)
                            .font(PPBrandFont.bold(size: 40))
                            .foregroundStyle(AdminSurface.primaryText)
                            .contentTransition(.numericText())

                        Text(verbatim: String(format: Language.get("Stock_Transfer_OutOfTotal", alter: "من أصل %@ وحدة"), availableQuantity.englishDigits).normalizedEnglishDigits)
                            .font(Language.isRTL() ? Font.custom("Beiruti-Regular", size: 11.5) : .system(size: 11.5))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    // Increment Button
                    Button {
                        if transferQuantity < availableQuantity {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                transferQuantity += 1
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    Circle()
                                        .strokeBorder(AdminSurface.primary.opacity(0.35), lineWidth: 0.8)
                                )
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(transferQuantity < availableQuantity ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.35))
                        }
                    }
                    .buttonStyle(CatalogPressStyle())
                    .disabled(transferQuantity >= availableQuantity)
                }

                // Custody Proportion Spectrum Bar
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: Language.isRTL() ? .trailing : .leading) {
                            Capsule()
                                .fill(AdminSurface.control)
                                .frame(height: 6)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.18, blue: 0.35)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(transferRatio)), height: 6)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: transferQuantity)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(verbatim: String(format: Language.get("Stock_Transfer_Ratio_Format", alter: "ترحيل %.0f%% من مخزون الفرع"), transferRatio * 100).normalizedEnglishDigits)
                            .font(Language.isRTL() ? Font.custom("Beiruti-Regular", size: 11) : .system(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        Text(verbatim: String(format: Language.get("Stock_Transfer_Remaining_Count", alter: "المتبقي: %@"), remainingSourceStock.englishDigits).normalizedEnglishDigits)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .foregroundStyle(remainingSourceStock <= 0 ? Color(uiColor: .ppError) : AdminSurface.primary)
                    }
                }
                .padding(.top, 4)

                // Quick Quantum Presets
                HStack(spacing: 7) {
                    ForEach([1, 5, 10], id: \.self) { val in
                        if val <= availableQuantity {
                            quantumPresetButton(label: val.englishDigits, isSelected: transferQuantity == val) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    transferQuantity = val
                                }
                            }
                        }
                    }

                    if availableQuantity >= 20 {
                        let quarter = max(1, availableQuantity / 4)
                        quantumPresetButton(label: "25%", isSelected: transferQuantity == quarter) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                transferQuantity = quarter
                            }
                        }
                    }

                    if availableQuantity >= 4 {
                        let half = max(1, availableQuantity / 2)
                        quantumPresetButton(label: "50%", isSelected: transferQuantity == half) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                transferQuantity = half
                            }
                        }
                    }

                    quantumPresetButton(label: Language.get("All", alter: "الكل"), isSelected: transferQuantity == availableQuantity) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            transferQuantity = availableQuantity
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
        }
    }

    private func quantumPresetButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label.normalizedEnglishDigits)
                .font(Font.custom("Beiruti-Bold", size: 12.5))
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: [AdminSurface.primary, Color(red: 0.75, green: 0.08, blue: 0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            AdminSurface.control
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? AdminSurface.primary.opacity(0.5) : Color(uiColor: .ppSurfaceBorder).opacity(0.7),
                            lineWidth: 0.75
                        )
                )
        }
        .buttonStyle(CatalogPressStyle())
    }

    private var auditReasonSection: some View {
        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 10) {
            Label(
                Language.get("Stock_Transfer_Reason", alter: "سبب النقل وتوثيق الحركة"),
                systemImage: "doc.text.fill"
            )
            .font(Font.custom("Beiruti-Bold", size: 13))
            .foregroundStyle(AdminSurface.secondaryText)

            // One-Tap Quick Reason Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([
                        Language.get("Stock_Transfer_Reason_Sales", alter: "طلب تعزيز مبيعات"),
                        Language.get("Stock_Transfer_Reason_Rebalance", alter: "إعادة توازن مخزون الفروع"),
                        Language.get("Stock_Transfer_Reason_VIP", alter: "طلب عميل خاص"),
                        Language.get("Stock_Transfer_Reason_Liquidation", alter: "تصفية رصيد الفرع"),
                        Language.get("Stock_Transfer_Reason_Inspection", alter: "معاينة وفحص جودة")
                    ], id: \.self) { chip in
                        let isSelected = reason == chip
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            reason = chip
                        } label: {
                            Text(chip)
                                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 12))
                                .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    isSelected ? AdminSurface.primary.opacity(0.12) : AdminSurface.surface,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? AdminSurface.primary.opacity(0.4) : Color(uiColor: .ppSurfaceBorder).opacity(0.8),
                                            lineWidth: 0.8
                                        )
                                )
                        }
                        .buttonStyle(CatalogPressStyle())
                    }
                }
                .padding(.horizontal, 2)
            }

            // Reason Text Input Field
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)

                TextField(
                    Language.get("Stock_Transfer_Reason_Placeholder", alter: "مثال: طلب تعزيز مخزون الفرع، إعادة توازن"),
                    text: $reason
                )
                .font(Font.custom("Beiruti-Regular", size: 13.5))
                .foregroundStyle(AdminSurface.primaryText)

                if !reason.isEmpty {
                    Button {
                        reason = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                    }
                }
            }
            .padding(12)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
            )
        }
    }

    private var sovereignDispatchDock: some View {
        VStack(spacing: 8) {
            // Live Transfer Summary Strip
            if !selectedBranchID.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.primary)
                    Text(verbatim: String(
                        format: Language.get("Stock_Transfer_Summary_Format", alter: "ترحيل %@ قطعة إلى %@"),
                        transferQuantity.englishDigits,
                        destinationBranchDisplayName
                    ).normalizedEnglishDigits)
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            // Executive Dispatch Action Button
            Button {
                promptTransferConfirmation()
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                    }

                    Text(isSubmitting ? Language.get("Saving", alter: "جاري المعالجة...") : Language.get("Stock_Transfer_Confirm", alter: "تأكيد ترحيل ونقل المخزون"))
                        .font(Font.custom("Beiruti-Bold", size: 16.5))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.72, green: 0.08, blue: 0.22)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: AdminSurface.primary.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(CatalogPressStyle())
            .disabled(isSubmitting || selectedBranchID.isEmpty || transferQuantity < 1 || transferQuantity > availableQuantity)
            .opacity((isSubmitting || selectedBranchID.isEmpty || transferQuantity < 1 || transferQuantity > availableQuantity) ? 0.6 : 1.0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().background(Color(uiColor: .ppSurfaceBorder).opacity(0.8))
        }
    }

    private func promptTransferConfirmation() {
        guard !selectedBranchID.isEmpty, transferQuantity >= 1 else { return }

        // If transferring 100% of branch stock, warn before full depletion
        if transferQuantity >= availableQuantity {
            PPAlertHelper.showConfirmation(
                in: nil,
                title: Language.get("Stock_Transfer_Warning_Full_Title", alter: "تنبيه: تصفية كامل مخزون الفرع"),
                subtitle: String(
                    format: Language.get(
                        "Stock_Transfer_Warning_Full_Msg",
                        alter: "أنت على وشك ترحيل كامل رصيد هذا الصنف (%@ قطعة) إلى %@. سيصبح رصيد الفرع الحالي صفراً. هل ترغب بالمتابعة؟"
                    ),
                    transferQuantity.englishDigits,
                    destinationBranchDisplayName
                ).normalizedEnglishDigits,
                confirmButton: Language.get("Stock_Transfer_Proceed", alter: "تأكيد ونقل الرصيد"),
                cancelButton: Language.get("Cancel", alter: "إلغاء"),
                icon: UIImage(systemName: "exclamationmark.triangle.fill"),
                confirmBlock: { _, didConfirm in
                    guard didConfirm else { return }
                    executeTransfer()
                },
                cancelBlock: nil
            )
        } else {
            executeTransfer()
        }
    }

    private func executeTransfer() {
        isSubmitting = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "admin_branch_stock_transfer"
            : reason.trimmingCharacters(in: .whitespacesAndNewlines)

        PPBranchInventoryService.shared.transferStock(
            productId: item.accessoryID,
            sourceBranchId: canonicalSourceBranchID,
            destinationBranchId: selectedBranchID,
            quantity: transferQuantity,
            reason: cleanReason,
            notes: "Transferred from admin item detail"
        ) { result in
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success(let data):
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    let newQty = (data["sourceNewQuantity"] as? NSNumber)?.intValue ?? max(0, self.availableQuantity - self.transferQuantity)
                    self.onComplete(newQty)
                    self.dismiss()
                case .failure(let error):
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    let message = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    self.errorMessage = message
                    PPAlertHelper.showFail(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ في نقل المخزون"),
                        subtitle: message,
                        completion: nil
                    )
                }
            }
        }
    }

    private var destinationBranchPickerSheet: some View {
        VStack(spacing: 0) {
            // Sheet Header
            AdminSovereignNavigationBar(
                title: Language.get("Stock_Transfer_Select_Branch", alter: "اختر فرع الاستلام (المحول إليه)"),
                subtitle: Language.get("Stock_Transfer_ActiveBranchesCount", alter: "الفروع المتاحة لاستقبال الشحنة"),
                isModal: true,
                onBack: {
                    showBranchPickerModal = false
                }
            ) {
                EmptyView()
            }

            // Search Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AdminSurface.secondaryText)
                TextField(
                    Language.get("Stock_Transfer_Search_Branch", alter: "ابحث عن اسم أو كود الفرع..."),
                    text: $branchSearchText
                )
                .font(Font.custom("Beiruti-Regular", size: 14))

                if !branchSearchText.isEmpty {
                    Button {
                        branchSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(10)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Branch List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if filteredBranches.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "building.2.slash")
                                .font(.system(size: 32))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                            Text(Language.get("Stock_Transfer_NoOtherBranches", alter: "لا توجد فروع أخرى نشطة للنقل إليها"))
                                .font(Font.custom("Beiruti-Bold", size: 13.5))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(filteredBranches) { b in
                            let isSelected = selectedBranchID == b.id
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedBranchID = b.id
                                showBranchPickerModal = false
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                                            .frame(width: 38, height: 38)
                                        Image(systemName: "storefront.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(isSelected ? Color.white : AdminSurface.primary)
                                    }

                                    VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                                        Text(b.displayName)
                                            .font(Font.custom("Beiruti-Bold", size: 15))
                                            .foregroundStyle(AdminSurface.primaryText)

                                        if !b.address.isEmpty {
                                            Text(b.address)
                                                .font(Font.custom("Beiruti-Regular", size: 11.5))
                                                .foregroundStyle(AdminSurface.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(AdminSurface.primary)
                                    }
                                }
                                .padding(12)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.8),
                                            lineWidth: isSelected ? 1.5 : 0.8
                                        )
                                )
                            }
                            .buttonStyle(CatalogPressStyle())
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Color(uiColor: .ppError))
            Text(message)
                .font(Font.custom("Beiruti-Bold", size: 12.5))
                .foregroundColor(Color(uiColor: .ppError))
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(uiColor: .ppError).opacity(0.3), lineWidth: 0.8)
        )
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

@available(iOS 16.0, *)
@objc public final class PPInventoryListHostingController: UIViewController {
    private let kind: AccessKindType
    private let showsCatalogSwitcher: Bool
    private var hostingController: UIViewController?
    private let onDismissBlock: (() -> Void)?

    @objc public init(kind: AccessKindType = .typeAccessory, showsCatalogSwitcher: Bool = true) {
        self.kind = kind
        self.showsCatalogSwitcher = showsCatalogSwitcher
        self.onDismissBlock = nil
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    @objc public init(kind: AccessKindType, showsCatalogSwitcher: Bool, onDismiss: (() -> Void)?) {
        self.kind = kind
        self.showsCatalogSwitcher = showsCatalogSwitcher
        self.onDismissBlock = onDismiss
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    @objc public convenience init(kind: AccessKindType, onDismiss: (() -> Void)?) {
        self.init(kind: kind, showsCatalogSwitcher: true, onDismiss: onDismiss)
    }

    public required init?(coder: NSCoder) {
        self.kind = .typeAccessory
        self.showsCatalogSwitcher = true
        self.onDismissBlock = nil
        super.init(coder: coder)
        self.hidesBottomBarWhenPushed = true
    }

    @objc public static func makeForAccessories() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeAccessory, showsCatalogSwitcher: true)
    }

    @objc public static func makeForFood() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeFood, showsCatalogSwitcher: true)
    }

    @objc public static func makeForLivePets() -> UIViewController {
        return PPInventoryListHostingController(kind: .typeLivePets, showsCatalogSwitcher: true)
    }

    @objc public static func make(kind: AccessKindType) -> UIViewController {
        return PPInventoryListHostingController(kind: kind, showsCatalogSwitcher: true)
    }

    @objc(makeForAccessoriesWithShowsCatalogSwitcher:)
    public static func makeForAccessories(showsCatalogSwitcher: Bool) -> UIViewController {
        return PPInventoryListHostingController(kind: .typeAccessory, showsCatalogSwitcher: showsCatalogSwitcher)
    }

    @objc(makeForFoodWithShowsCatalogSwitcher:)
    public static func makeForFood(showsCatalogSwitcher: Bool) -> UIViewController {
        return PPInventoryListHostingController(kind: .typeFood, showsCatalogSwitcher: showsCatalogSwitcher)
    }

    @objc(makeForLivePetsWithShowsCatalogSwitcher:)
    public static func makeForLivePets(showsCatalogSwitcher: Bool) -> UIViewController {
        return PPInventoryListHostingController(kind: .typeLivePets, showsCatalogSwitcher: showsCatalogSwitcher)
    }

    @objc(makeWithKind:showsCatalogSwitcher:)
    public static func make(kind: AccessKindType, showsCatalogSwitcher: Bool) -> UIViewController {
        return PPInventoryListHostingController(kind: kind, showsCatalogSwitcher: showsCatalogSwitcher)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all

        let swiftUIView = PPInventoryListView(
            kind: kind,
            showsCatalogSwitcher: showsCatalogSwitcher,
            onPushViewController: { [weak self] targetVC in
                self?.navigationController?.pushViewController(targetVC, animated: true)
            },
            onDismiss: { [weak self] in
                if let block = self?.onDismissBlock {
                    block()
                    return
                }
                guard let self = self else {
                    PPAdminNavigationFallback.popOrDismiss()
                    return
                }
                PPAdminNavigationFallback.popOrDismiss(from: self)
            }
        )

        let host = UIHostingController(rootView: swiftUIView.ignoresSafeArea())
        host.view.backgroundColor = .clear
        host.extendedLayoutIncludesOpaqueBars = true
        host.edgesForExtendedLayout = .all
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
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}
